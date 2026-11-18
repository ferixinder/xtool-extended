import ConcurrencyExtras
import Crypto
import Dependencies
import Foundation
import OpenAPIRuntime
import Testing
import X509
@testable import XKit

private struct ProvisioningHTTP: HTTPClientProtocol, ClientTransport {
    enum Error: Swift.Error { case unexpectedRequest }
    var handler: @Sendable (HTTPRequest, HTTPBody?) async throws -> (HTTPResponse, HTTPBody?)
    var asOpenAPITransport: any ClientTransport { self }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String)
        async throws -> (HTTPResponse, HTTPBody?) {
        try await handler(request, body)
    }

    func makeWebSocket(url: URL) async throws -> any WebSocketSession { throw Error.unexpectedRequest }
    func withEphemeralClient<T>(perform: (any HTTPClientProtocol) async throws -> T) async throws -> T {
        try await perform(self)
    }
}

private func context(purpose: SigningContext.Purpose = .appStore) -> SigningContext {
    SigningContext(auth: .appStoreConnect(.init(
        id: "test", issuerID: "test", pem: P256.Signing.PrivateKey().pemRepresentation
    )), targetDevice: .init(udid: "must-not-register", name: "Test device"), purpose: purpose)
}

private func jsonResponse(_ json: String, status: HTTPResponse.Status = .ok) -> (HTTPResponse, HTTPBody?) {
    (HTTPResponse(status: status, headerFields: [.contentType: "application/json"]), HTTPBody(json))
}

@Test func distributionCertificateQuotaFailureDoesNotRevokeCertificates() async throws {
    let calls = LockIsolated<[String]>([])
    let http = ProvisioningHTTP { request, _ in
        calls.withValue { $0.append("\(request.method) \(request.path ?? "")") }
        if request.method == .get {
            return jsonResponse(#"{"data":[],"links":{"self":"https://api.appstoreconnect.apple.com/v1/certificates"}}"#)
        }
        #expect(request.method == .post)
        return jsonResponse(#"{"errors":[]}"#, status: .conflict)
    }
    await withDependencies {
        $0.httpClient = http
        $0.signingInfoManager = MemoryBackedSigningInfoManager()
    } operation: {
        await #expect(throws: (any Error).self) {
            try await DeveloperServicesFetchCertificateOperation(context: context(), confirmRevocation: { _ in
                Issue.record("Distribution must never request revocation")
                return false
            }).perform()
        }
    }
    #expect(calls.value.count == 2)
    #expect(!calls.value.contains { $0.hasPrefix("DELETE") })
}

@Test(arguments: [SigningContext.Purpose.appStore, .development])
func profileCreationAvoidsDuplicateNamesAndPreservesUnrelatedProfiles(purpose: SigningContext.Purpose) async throws {
    let key = try Keypair()
    let name = try DistinguishedName { CommonName("xtool tests") }
    let certificate = try XKit.Certificate(raw: X509.Certificate(
        version: .v3, serialNumber: .init(bytes: [1]), publicKey: .init(key.raw.publicKey),
        notValidBefore: Date(), notValidAfter: Date().addingTimeInterval(3600), issuer: name, subject: name,
        signatureAlgorithm: .sha256WithRSAEncryption, extensions: .init(), issuerPrivateKey: .init(key.raw)
    ))
    let calls = LockIsolated<[String]>([])
    let createdNames = LockIsolated<[String]>([])
    let http = ProvisioningHTTP { request, body in
        let path = request.path ?? ""
        calls.withValue { $0.append("\(request.method) \(path)") }
        if path.hasPrefix("/v1/bundleIds") {
            let duplicate = purpose == .development ? #",{"type":"profiles","id":"duplicate"}"# : ""
            return jsonResponse("""
                {"data":[{"type":"bundleIds","id":"app","attributes":{"identifier":"com.example.app"},
                "relationships":{"profiles":{"data":[{"type":"profiles","id":"existing"}\(duplicate)]}}}],
                "links":{"self":"https://api.appstoreconnect.apple.com/v1/bundleIds"}}
                """)
        }
        if path.hasPrefix("/v1/profiles/existing") {
            return jsonResponse("""
                {"data":{"type":"profiles","id":"existing",
                "attributes":{"profileType":"IOS_APP_DEVELOPMENT","profileState":"ACTIVE"}},
                "links":{"self":"https://api.appstoreconnect.apple.com/v1/profiles/existing"}}
                """)
        }
        if path.hasPrefix("/v1/certificates") {
            let certificateType = purpose == .appStore ? "DISTRIBUTION" : "DEVELOPMENT"
            return jsonResponse("""
                {"data":[{"type":"certificates","id":"cert",
                "attributes":{"serialNumber":"01","certificateType":"\(certificateType)"}}],
                "links":{"self":"https://api.appstoreconnect.apple.com/v1/certificates"}}
                """)
        }
        if path.hasPrefix("/v1/devices") {
            return jsonResponse(#"{"data":[],"links":{"self":"https://api.appstoreconnect.apple.com/v1/devices"}}"#)
        }
        #expect(request.method == .post && path == "/v1/profiles")
        let data = try await Data(collecting: #require(body), upTo: 100_000)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let profile = try #require(payload["data"] as? [String: Any])
        let attributes = try #require(profile["attributes"] as? [String: Any])
        let relationships = try #require(profile["relationships"] as? [String: Any])
        #expect(attributes["profileType"] as? String == (purpose == .appStore ? "IOS_APP_STORE" : "IOS_APP_DEVELOPMENT"))
        #expect((relationships["devices"] == nil) == (purpose == .appStore))
        let name = try #require(attributes["name"] as? String)
        let prefix = purpose == .appStore ? "XTL App Store app " : "XTL profile app "
        #expect(name.hasPrefix(prefix))
        #expect(UUID(uuidString: String(name.dropFirst(prefix.count))) != nil)
        createdNames.withValue { $0.append(name) }
        // Deliberately stop before decoding a real Apple-signed profile.
        return jsonResponse("""
            {"data":{"type":"profiles","id":"new"},"links":{"self":"https://api.appstoreconnect.apple.com/v1/profiles/new"}}
            """, status: .created)
    }
    await withDependencies {
        $0.httpClient = http
    } operation: {
        for _ in 0..<2 {
            await #expect(throws: DeveloperServicesFetchProfileOperation.Errors.invalidProfileData) {
                try await DeveloperServicesFetchProfileOperation(
                    context: context(purpose: purpose), bundleID: "com.example.app",
                    signingInfo: SigningInfo(privateKey: key.privateKey(), certificate: certificate)
                ).perform()
            }
        }
    }
    #expect(calls.value.count == 8)
    #expect(Set(createdNames.value).count == 2)
    #expect(!calls.value.contains { $0.hasPrefix("DELETE") })
    if purpose == .appStore { #expect(!calls.value.contains { $0.contains("/devices") }) }
}
