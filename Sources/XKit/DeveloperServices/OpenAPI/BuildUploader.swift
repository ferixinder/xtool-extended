import Dependencies
import Foundation
import HTTPTypes
import OpenAPIRuntime

public struct BuildUploader: Sendable {
    public enum Error: LocalizedError {
        case invalidFile
        case invalidOperations
        case duplicateBuild
        case wrongApp
        case invalidIdentifier
        case api(Int, String)
        case transport
        case uploadPart(Int)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .invalidFile: "The IPA is empty, unreadable or changed while uploading."
            case .invalidOperations: "Apple returned invalid or incomplete HTTPS upload operations."
            case .duplicateBuild: "This version/build already has a build or upload. Check its status or use a new build number."
            case .wrongApp: "The selected App Store Connect record does not match the IPA bundle ID."
            case .invalidIdentifier: "Invalid App Store Connect resource identifier."
            case .api(let status, let detail): "App Store Connect API failed (HTTP \(status)): \(detail)"
            case .transport: "App Store Connect transport failed. Check upload status before retrying."
            case .uploadPart(let status): "File transfer failed (HTTP \(status)). Signed upload URLs are omitted."
            case .invalidResponse: "App Store Connect returned an invalid or unexpected response."
            }
        }
    }

    public enum Event: Sendable {
        case created(String)
        case transferred(Int64, Int64)
        case committed(String)
    }

    @Dependency(\.httpClient) private var httpClient
    private let jwt: ASCJWTGenerator

    public init(key: ASCKey) { jwt = ASCJWTGenerator(key: key) }

    public func upload(
        ipa: URL, appID: String, bundleID: String, version: String, build: String,
        onEvent: @Sendable (Event) -> Void
    ) async throws -> String {
        try Self.validateID(appID)
        let file = try BuildUploadFile(url: ipa)
        let app: UploadEnvelope<UploadResource<UploadApp>> = try await api("GET", "/v1/apps/\(appID)")
        guard app.data.attributes.bundleId == bundleID else { throw Error.wrongApp }
        let builds: UploadEnvelope<[UploadResource<UploadBuild>]> = try await api("GET", "/v1/builds", query: [
            "filter[app]": appID, "filter[version]": build, "filter[preReleaseVersion.version]": version,
            "filter[preReleaseVersion.platform]": "IOS", "limit": "1",
        ])
        let uploads: UploadEnvelope<[UploadResource<UploadAttributes>]> = try await api(
            "GET", "/v1/apps/\(appID)/buildUploads",
            query: [
                "filter[cfBundleVersion]": build, "filter[cfBundleShortVersionString]": version,
                "filter[platform]": "IOS", "limit": "1",
            ]
        )
        guard builds.data.isEmpty, uploads.data.isEmpty else { throw Error.duplicateBuild }
        let upload: UploadEnvelope<UploadResource<UploadAttributes>> = try await api("POST", "/v1/buildUploads", body: Self.body(
            type: "buildUploads", attributes: ["cfBundleShortVersionString": version, "cfBundleVersion": build, "platform": "IOS"],
            relationships: ["app": ["data": ["type": "apps", "id": appID]]]
        ))
        let id = upload.data.id
        try Self.validateID(id)
        onEvent(.created(id))
        let reservation: UploadEnvelope<UploadResource<UploadFileAttributes>> = try await api(
            "POST", "/v1/buildUploadFiles",
            body: Self.body(
                type: "buildUploadFiles",
                attributes: ["fileName": ipa.lastPathComponent, "fileSize": file.size, "uti": "com.apple.ipa", "assetType": "ASSET"],
                relationships: ["buildUpload": ["data": ["type": "buildUploads", "id": id]]]
            )
        )
        let fileID = reservation.data.id
        try Self.validateID(fileID)
        guard let operations = reservation.data.attributes.uploadOperations else { throw Error.invalidOperations }
        try file.validate(operations)
        var transferred: Int64 = 0
        for operation in operations {
            try await transfer(operation, file: file)
            transferred += operation.length
            onEvent(.transferred(transferred, file.size))
        }
        // Recheck the source before committing, so a changed IPA cannot be silently accepted.
        let after = try BuildUploadFile(url: ipa)
        guard after.size == file.size, after.md5 == file.md5 else { throw Error.invalidFile }
        let _: UploadEnvelope<UploadResource<UploadFileAttributes>> = try await api(
            "PATCH", "/v1/buildUploadFiles/\(fileID)",
            body: Self.body(
                type: "buildUploadFiles", id: fileID,
                attributes: ["uploaded": true, "sourceFileChecksums": ["file": ["hash": file.md5, "algorithm": "MD5"]]]
            )
        )
        onEvent(.committed(id))
        return id
    }

    public func status(uploadID: String) async throws -> BuildUploadStatus {
        try Self.validateID(uploadID)
        let upload: UploadEnvelope<UploadResource<UploadAttributes>> = try await api(
            "GET", "/v1/buildUploads/\(uploadID)", query: ["include": "build"]
        )
        let state = upload.data.attributes.state
        let buildID = upload.data.relationships?.build?.data?.id
        var processing: String?
        if let buildID {
            try Self.validateID(buildID)
            let build: UploadEnvelope<UploadResource<UploadBuild>> = try await api("GET", "/v1/builds/\(buildID)")
            processing = build.data.attributes.processingState
        }
        return BuildUploadStatus(
            uploadID: uploadID, state: state?.state ?? "UNKNOWN", buildID: buildID, processingState: processing,
            errors: state?.errors?.map { [$0.code, $0.description].compactMap { $0 }.joined(separator: ": ") } ?? []
        )
    }

    private func transfer(_ operation: BuildUploadOperation, file: BuildUploadFile) async throws {
        guard let url = URL(string: operation.url) else { throw Error.invalidOperations }
        var request = HTTPRequest(method: .put, url: url)
        for header in operation.requestHeaders ?? [] {
            guard let name = HTTPField.Name(header.name) else { throw Error.invalidOperations }
            request.headerFields[name] = header.value
        }
        let body = try file.body(offset: operation.offset, length: operation.length)
        do {
            let (response, responseBody) = try await httpClient.send(request, body: body)
            if let responseBody { _ = try await Data(collecting: responseBody, upTo: 1024 * 1024) }
            guard response.status.kind == .successful else { throw Error.uploadPart(response.status.code) }
        } catch let error as Error {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Error.transport
        }
    }

    private func api<T: Decodable>(
        _ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil
    ) async throws -> T {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com")!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components.url, let method = HTTPRequest.Method(method) else { throw Error.invalidResponse }
        var request = HTTPRequest(method: method, url: url)
        request.headerFields[.authorization] = "Bearer \(try await jwt.generate())"
        request.headerFields[.contentType] = "application/json"
        request.headerFields[.accept] = "application/json"
        let response: HTTPResponse
        let responseBody: HTTPBody?
        do {
            (response, responseBody) = try await httpClient.send(request, body: body.map { HTTPBody($0) })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Error.transport
        }
        let data: Data
        if let responseBody {
            data = try await Data(collecting: responseBody, upTo: 4 * 1024 * 1024)
        } else {
            data = Data()
        }
        guard response.status.kind == .successful else {
            let errors = try? JSONDecoder().decode(UploadAPIFailure.self, from: data)
            let detail = errors?.errors.map { [$0.code, $0.detail].compactMap { $0 }.joined(separator: ": ") }.joined(separator: "\n")
            throw Error.api(response.status.code, detail ?? "No structured error details")
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Error.invalidResponse }
    }

    private static func body(
        type: String, id: String? = nil, attributes: [String: Any], relationships: [String: Any] = [:]
    ) throws -> Data {
        var resource: [String: Any] = ["type": type, "attributes": attributes]
        if let id { resource["id"] = id }
        if !relationships.isEmpty { resource["relationships"] = relationships }
        return try JSONSerialization.data(withJSONObject: ["data": resource])
    }

    private static func validateID(_ id: String) throws {
        guard !id.isEmpty, id.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }) else {
            throw Error.invalidIdentifier
        }
    }
}
