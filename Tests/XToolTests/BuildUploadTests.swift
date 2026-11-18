import ConcurrencyExtras
import Crypto
import Dependencies
import Foundation
import OpenAPIRuntime
import Testing
@testable import XKit
@testable import XToolSupport

private struct UploadHTTP: HTTPClientProtocol, ClientTransport {
    enum Failure: Error { case unexpected }
    let handler: @Sendable (HTTPRequest, HTTPBody?) async throws -> (HTTPResponse, HTTPBody?)
    var asOpenAPITransport: any ClientTransport { self }
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String)
        async throws -> (HTTPResponse, HTTPBody?) { try await handler(request, body) }
    func makeWebSocket(url: URL) async throws -> any WebSocketSession { throw Failure.unexpected }
    func withEphemeralClient<T>(perform: (any HTTPClientProtocol) async throws -> T) async throws -> T {
        try await perform(self)
    }
}

private func uploader() -> BuildUploader {
    BuildUploader(key: .init(id: "test", issuerID: "test", pem: P256.Signing.PrivateKey().pemRepresentation))
}

private func response(_ object: [String: Any], status: HTTPResponse.Status = .ok) throws -> (HTTPResponse, HTTPBody?) {
    (HTTPResponse(status: status, headerFields: [.contentType: "application/json"]),
     HTTPBody(try JSONSerialization.data(withJSONObject: object)))
}

private func resource(_ id: String, _ attributes: [String: Any], relationships: [String: Any] = [:]) -> [String: Any] {
    ["id": id, "attributes": attributes, "relationships": relationships]
}

@Test(arguments: ["complete", "mutate", "transfer-error"])
func buildUploadReservesStreamsChecksumsAndCommitsWithoutLeakingJWT(mode: String) async throws {
    let ipa = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
    defer { try? FileManager.default.removeItem(at: ipa) }
    try Data("0123456789".utf8).write(to: ipa)
    let calls = LockIsolated<[String]>([])
    let http = UploadHTTP { request, body in
        let path = request.path ?? ""
        calls.withValue { $0.append("\(request.method) \(path.components(separatedBy: "?")[0])") }
        if request.authority == "upload.example" {
            #expect(request.headerFields[.authorization] == nil)
            #expect(request.headerFields[.cookie] == nil)
            #expect(request.headerFields[.init("X-Apple-Test")!] == "provided")
            let data = try await Data(collecting: #require(body), upTo: 10)
            #expect(data == Data((path.hasPrefix("/first") ? "0123" : "456789").utf8))
            if mode == "transfer-error" { return (HTTPResponse(status: .forbidden), HTTPBody("signed URL details")) }
            if mode == "mutate", path.hasPrefix("/second") { try Data("9876543210".utf8).write(to: ipa) }
            return (HTTPResponse(status: .ok), nil)
        }
        #expect(request.authority == "api.appstoreconnect.apple.com")
        #expect(request.headerFields[.authorization]?.hasPrefix("Bearer ") == true)
        if path == "/v1/apps/app" { return try response(["data": resource("app", ["bundleId": "com.example.app"])]) }
        if path.hasPrefix("/v1/builds?") || path.hasPrefix("/v1/apps/app/buildUploads?") {
            return try response(["data": []])
        }
        if path == "/v1/buildUploads" {
            return try response(["data": resource("upload", [
                "cfBundleShortVersionString": "1.0.0", "cfBundleVersion": "1",
            ])], status: .created)
        }
        if path == "/v1/buildUploadFiles" {
            let operations: [[String: Any]] = [("first", 0, 4), ("second", 4, 6)].map { name, offset, length in
                ["method": "PUT", "url": "https://upload.example/\(name)?signature=secret", "offset": offset, "length": length,
                 "requestHeaders": [["name": "X-Apple-Test", "value": "provided"]]]
            }
            return try response(["data": resource("file", ["uploadOperations": operations])], status: .created)
        }
        #expect(path == "/v1/buildUploadFiles/file" && request.method == .patch)
        let data = try await Data(collecting: #require(body), upTo: 10_000)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try #require(object["data"] as? [String: Any])
        let attrs = try #require(entry["attributes"] as? [String: Any])
        let checksums = try #require(attrs["sourceFileChecksums"] as? [String: Any])
        let checksum = try #require(checksums["file"] as? [String: String])
        #expect(attrs["uploaded"] as? Bool == true)
        #expect(checksum == ["algorithm": "MD5", "hash": "781e5e245d69b566979b86e28d23f2c7"])
        return try response(["data": resource("file", [:])])
    }
    await withDependencies { $0.httpClient = http } operation: {
        do {
            let id = try await uploader().upload(
                ipa: ipa, appID: "app", bundleID: "com.example.app", version: "1.0.0", build: "1", onEvent: { _ in }
            )
            #expect(mode == "complete" && id == "upload")
        } catch {
            #expect(mode != "complete")
            #expect(!error.localizedDescription.contains("signature=secret"))
            #expect(!error.localizedDescription.contains("signed URL details"))
        }
    }
    #expect(calls.value.count == (mode == "complete" ? 8 : mode == "mutate" ? 7 : 6))
}

@Test func buildUploadRejectsWrongAppsAndDuplicateBuildsBeforeCreatingAnything() async throws {
    let ipa = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
    defer { try? FileManager.default.removeItem(at: ipa) }
    try Data("test".utf8).write(to: ipa)
    for wrongApp in [true, false] {
        let http = UploadHTTP { request, _ in
            #expect(request.method == .get)
            let path = request.path ?? ""
            if path == "/v1/apps/app" {
                let bundleID = wrongApp ? "other.app" : "com.example.app"
                return try response(["data": resource("app", ["bundleId": bundleID])])
            }
            if path.hasPrefix("/v1/builds?") {
                return try response(["data": [resource("existing", ["version": "1", "processingState": "VALID"])]])
            }
            return try response(["data": []])
        }
        await withDependencies { $0.httpClient = http } operation: {
            await #expect(throws: (any Error).self) {
                try await uploader().upload(
                    ipa: ipa, appID: "app", bundleID: "com.example.app", version: "1.0.0", build: "1", onEvent: { _ in }
                )
            }
        }
    }
}

@Test func buildUploadDistinguishesTransferFromAppleAcceptanceAndRejection() async throws {
    let states = [("PROCESSING", "PROCESSING"), ("COMPLETE", "PROCESSING"), ("COMPLETE", "VALID"), ("FAILED", "INVALID")]
    for (state, processing) in states {
        let http = UploadHTTP { request, _ in
            if request.path?.hasPrefix("/v1/buildUploads/upload") == true {
                return try response(["data": resource("upload", [
                    "cfBundleShortVersionString": "1.0.0", "cfBundleVersion": "1",
                    "state": ["state": state, "errors": [["code": "TEST", "description": "validation detail"]]],
                ], relationships: ["build": ["data": ["id": "build"]]])])
            }
            return try response(["data": resource("build", ["version": "1", "processingState": processing])])
        }
        try await withDependencies { $0.httpClient = http } operation: {
            let status = try await uploader().status(uploadID: "upload")
            #expect(status.accepted == (state == "COMPLETE" && processing == "VALID"))
            #expect(status.failed == (state == "FAILED"))
            #expect(status.errors == ["TEST: validation detail"])
        }
    }
}

@Test func buildUploadValidatesRangesAndReadsBoundedChunks() async throws {
    let ipa = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
    defer { try? FileManager.default.removeItem(at: ipa) }
    try Data(repeating: 42, count: 3 * 1024 * 1024).write(to: ipa)
    let file = try BuildUploadFile(url: ipa)
    let operation = BuildUploadOperation(
        method: "PUT", url: "https://upload.example/part", length: file.size, offset: 0, requestHeaders: nil
    )
    try file.validate([operation])
    var received = 0
    for try await chunk in try file.body(offset: 0, length: file.size) {
        #expect(chunk.count <= 1024 * 1024)
        received += chunk.count
    }
    #expect(received == 3 * 1024 * 1024)
    for (url, offset, length) in [("http://upload.example/part", 0, file.size), (operation.url, 1, file.size - 1),
                                  (operation.url, 0, file.size + 1), (operation.url, 0, Int64(-1))] {
        #expect(throws: (any Error).self) {
            try file.validate([.init(method: "PUT", url: url, length: length, offset: Int64(offset), requestHeaders: nil)])
        }
    }
}

@Test func buildUploadSurfacesPermissionErrorsWithoutCredentials() async throws {
    let http = UploadHTTP { _, _ in
        try response(["errors": [["code": "FORBIDDEN", "detail": "Insufficient role"]]], status: .forbidden)
    }
    await withDependencies { $0.httpClient = http } operation: {
        do {
            _ = try await uploader().status(uploadID: "upload")
            Issue.record("Expected a permission error")
        } catch {
            #expect(error.localizedDescription.contains("403"))
            #expect(error.localizedDescription.contains("Insufficient role"))
            #expect(!error.localizedDescription.contains("Bearer"))
        }
    }
}

@Test func buildUploadCancellationStopsBeforeCreatingRemoteResources() async throws {
    let ipa = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
    defer { try? FileManager.default.removeItem(at: ipa) }
    try Data("test".utf8).write(to: ipa)
    let http = UploadHTTP { _, _ in
        Issue.record("A cancelled upload must not create remote resources")
        throw UploadHTTP.Failure.unexpected
    }
    await withDependencies { $0.httpClient = http } operation: {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await uploader().upload(
                ipa: ipa, appID: "app", bundleID: "com.example.app", version: "1.0.0", build: "1", onEvent: { _ in }
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Test func preparedBuildUploadRejectsUnsafeZipPathsAndSymlinks() throws {
    try DSUploadBuildCommand.validateArchiveEntries(names: "Payload/App.app/Info.plist\n", listing: "-rw-r--r-- Info.plist")
    for name in ["../outside", "/absolute", "Payload/App.app/../../..", "Payload\\..\\outside"] {
        #expect(throws: (any Error).self) { try DSUploadBuildCommand.validateArchiveEntries(names: name, listing: "") }
    }
    #expect(throws: (any Error).self) {
        try DSUploadBuildCommand.validateArchiveEntries(names: "Payload/App.app/link", listing: "lrwxrwxrwx link")
    }
}
