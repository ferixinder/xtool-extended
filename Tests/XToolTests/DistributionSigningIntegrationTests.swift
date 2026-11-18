import Dependencies
import Foundation
import Testing
@testable import XKit
@testable import XToolSupport

// Opt-in only: creates distribution certificates/profiles using the saved account, but never uploads a build.
@Test(.enabled(if: ProcessInfo.processInfo.environment["XTOOL_TEST_DISTRIBUTION_APP"] != nil))
func distributionSignsPreparedAppWithSavedAccount() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["XTOOL_TEST_DISTRIBUTION_APP"])
    let app = URL(fileURLWithPath: path)
    try #require(app.pathExtension == "app")
    func info(_ bundle: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("Info.plist"))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
    let originalID = try #require(info(app)["CFBundleIdentifier"] as? String)
    try await withDependencies {
        $0.context = .live
    } operation: {
        let auth = try AuthToken.saved().authData()
        let context = SigningContext(auth: auth, purpose: .appStore)
        let identifier = try await AutoSigner(context: context, confirmRevocation: { _ in
            Issue.record("Distribution signing must never request certificate revocation")
            return false
        }).sign(app: app, status: { _ in }, progress: { _ in })
        #expect(identifier == originalID)
        @Dependency(\.signer) var signer
        for bundle in try DeveloperServicesAddAppOperation.appBundles(in: app) {
            let profile = try Mobileprovision(data: Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")))
            #expect(try profile.digest().devices.isEmpty)
            let executable = try #require(info(bundle)["CFBundleExecutable"] as? String)
            let data = try #require(await signer.analyze(executable: bundle.appendingPathComponent(executable)))
            let entitlements = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            #expect(entitlements["get-task-allow"] as? Bool == false)
        }
    }
}
