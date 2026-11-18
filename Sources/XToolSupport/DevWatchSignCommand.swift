import ArgumentParser
import Dependencies
import Foundation
import XCLIUtils
import XKit

struct DevWatchSignCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sign-watch",
        abstract: "Provision and sign a standalone Watch app for a paired Watch"
    )

    @Argument(help: "Watch .app bundle to sign")
    var path: String

    @Option(help: "JSON file containing the paired Watch's udid and name")
    var deviceInfo: String

    private struct Target: Decodable {
        var udid: String
        var name: String
    }

    static func validate(info: [String: Any], udid: String) throws {
        guard info["WKApplication"] as? Bool == true,
              info["CFBundleSupportedPlatforms"] as? [String] == ["WatchOS"],
              info["WKWatchOnly"] as? Bool == true else {
            throw Console.Error("sign-watch requires a standalone watchOS device app.")
        }
        guard !udid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Console.Error("The Watch UDID is missing.")
        }
    }

    static func validateAppGroups(requested: Entitlements, allowed: Entitlements) throws {
        func groups(_ entitlements: Entitlements) throws -> Set<DeveloperServicesAppGroup.GroupID> {
            Set(try entitlements.entitlements().compactMap { ($0 as? AppGroupEntitlement)?.rawValue }.flatMap { $0 })
        }
        let missing = try groups(requested).subtracting(groups(allowed))
        guard missing.isEmpty else {
            throw Console.Error("Watch profile is missing App Groups: \(missing.map(\.rawValue).sorted().joined(separator: ", ")). "
                + "Assign them to the App ID in Apple Developer, then sign again.")
        }
    }

    func run() async throws {
        @Dependency(\.signer) var signer
        let app = URL(fileURLWithPath: path)
        let info = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Info.plist")), format: nil
        ) as? [String: Any]
        let target = try JSONDecoder().decode(Target.self, from: Data(contentsOf: URL(fileURLWithPath: deviceInfo)))
        try Self.validate(info: info ?? [:], udid: target.udid)

        let auth = try AuthToken.saved()
        let installDelegate = XToolInstallerDelegate(allowsRevocation: false)
        let installer = IntegratedInstaller(auth: auth.authData(), delegate: installDelegate)
        do {
            defer { print() }
            try await installer.signInPlace(app: app, targetDevice: .init(udid: target.udid, name: target.name))
        } catch let error as CancellationError {
            guard await installDelegate.refusedRevocation else { throw error }
            throw Console.Error("Watch signing stopped: refusing to revoke an existing development certificate.")
        }
        let profile = try Mobileprovision(data: Data(contentsOf: app.appendingPathComponent("embedded.mobileprovision")))
            .digest()
        guard profile.devices.contains(target.udid), profile.expirationDate > Date() else {
            throw Console.Error("The Watch profile is expired or does not include the paired Watch.")
        }
        if let executable = info?["CFBundleExecutable"] as? String,
           let data = try await signer.analyze(executable: app.appendingPathComponent(executable)) {
            try Self.validateAppGroups(requested: PropertyListDecoder().decode(Entitlements.self, from: data),
                                       allowed: profile.entitlements)
        } else {
            throw Console.Error("Cannot verify the signed Watch app's entitlements.")
        }
        print("Signed the Watch app. Install it separately through the paired iPhone.")
    }
}
