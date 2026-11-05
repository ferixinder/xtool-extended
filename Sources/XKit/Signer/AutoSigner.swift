import Foundation
import Dependencies

/// Provisions and codesigns.
public struct AutoSigner {

    @Dependency(\.signer) private var signer

    public enum Error: LocalizedError {
        case errorReading(String)
        case errorWriting(String)

        public var errorDescription: String? {
            switch self {
            case .errorReading(let file):
                return "\(file)".withCString {
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "signer.error.error_reading", value: "Error while reading %s", comment: ""
                        ), $0
                    )
                }
            case .errorWriting(let file):
                return "\(file)".withCString {
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "signer.error.error_writing", value: "Error while writing %s", comment: ""
                        ), $0
                    )
                }
            }
        }
    }

    public let context: SigningContext
    public let confirmRevocation: @Sendable ([DeveloperServicesCertificate]) async -> Bool
    public init(
        context: SigningContext,
        confirmRevocation: @escaping @Sendable ([DeveloperServicesCertificate]) async -> Bool
    ) {
        self.context = context
        self.confirmRevocation = confirmRevocation
    }

    public func sign(
        app: URL,
        status: @escaping (String) -> Void,
        progress: @escaping @Sendable (Double?) -> Void,
        didProvision: @escaping () throws -> Void = {}
    ) async throws -> String {
        status(NSLocalizedString("signer.provisioning", value: "Provisioning", comment: ""))
        let response = try await DeveloperServicesProvisioningOperation(
            context: context,
            app: app,
            confirmRevocation: confirmRevocation,
            progress: progress
        ).perform()

        let provisioningDict = response.provisioningDict
        let signingInfo = response.signingInfo
        guard let mainInfo = provisioningDict[app] else {
            throw Error.errorReading("app bundle ID")
        }

        try didProvision()

        var bundleIDs: [String: String] = [:]
        for (url, info) in provisioningDict {
            let plist = try Data(contentsOf: url.appendingPathComponent("Info.plist"))
            let dict = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
            guard let originalID = dict?["CFBundleIdentifier"] as? String else {
                throw Error.errorReading("CFBundleIdentifier")
            }
            bundleIDs[originalID] = info.newBundleID
        }

        for (url, info) in provisioningDict {
            let infoPlist = url.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: infoPlist),
                let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { throw Error.errorReading(infoPlist.lastPathComponent) }
            let nsDict = NSMutableDictionary(dictionary: Self.remappingWatchIdentifiers(in: dict, bundleIDs: bundleIDs))
            nsDict["CFBundleIdentifier"] = info.newBundleID
            guard nsDict.write(to: infoPlist, atomically: true) else {
                throw Error.errorWriting(infoPlist.lastPathComponent)
            }

            let profURL = url.appendingPathComponent("embedded.mobileprovision")
            if profURL.exists {
                try FileManager.default.removeItem(at: profURL)
            }
            try info.mobileprovision.data().write(to: profURL)
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let entitlements = try provisioningDict.mapValues { try encoder.encode($0.entitlements) }

        status(NSLocalizedString("signer.signing", value: "Signing", comment: ""))
        try await signer.sign(
            app: app,
            identity: .real(signingInfo.certificate, signingInfo.privateKey),
            entitlementMapping: entitlements,
            deep: true,
            progress: progress
        )
        progress(1)

        return mainInfo.newBundleID
    }

    static func remappingWatchIdentifiers(in plist: [String: Any], bundleIDs: [String: String]) -> [String: Any] {
        var plist = plist
        for key in ["WKCompanionAppBundleIdentifier", "WKAppBundleIdentifier"] {
            if let oldID = plist[key] as? String, let newID = bundleIDs[oldID] {
                plist[key] = newID
            }
        }
        if var ext = plist["NSExtension"] as? [String: Any],
           var attributes = ext["NSExtensionAttributes"] as? [String: Any],
           let oldID = attributes["WKAppBundleIdentifier"] as? String, let newID = bundleIDs[oldID] {
            attributes["WKAppBundleIdentifier"] = newID
            ext["NSExtensionAttributes"] = attributes
            plist["NSExtension"] = ext
        }
        return plist
    }

}
