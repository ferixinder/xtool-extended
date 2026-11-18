import Foundation

extension Entitlements {
    enum DistributionError: LocalizedError {
        case invalidProfile
        case unsupportedEntitlement(String)

        var errorDescription: String? {
            switch self {
            case .invalidProfile:
                "The App Store profile does not match this application's identifier, team or signing purpose."
            case .unsupportedEntitlement(let key):
                "The App Store profile does not authorize entitlement '\(key)'. Check the registered capabilities."
            }
        }
    }

    func forAppStore(profile: Entitlements, bundleID: String, teamID: String) throws -> Entitlements {
        func dictionary(_ entitlements: Entitlements) throws -> [String: Any] {
            let data = try PropertyListEncoder().encode(entitlements)
            guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw DistributionError.invalidProfile
            }
            return result
        }
        let allowed = try dictionary(profile)
        guard let applicationID = allowed["application-identifier"] as? String,
              applicationID.hasSuffix(".\(bundleID)"), !applicationID.contains("*"),
              allowed["com.apple.developer.team-identifier"] as? String == teamID,
              allowed["get-task-allow"] as? Bool == false else {
            throw DistributionError.invalidProfile
        }
        var requested = try dictionary(self)
        requested["application-identifier"] = applicationID
        requested["com.apple.developer.team-identifier"] = teamID
        requested["get-task-allow"] = false
        if requested["aps-environment"] != nil {
            guard allowed["aps-environment"] as? String == "production" else {
                throw DistributionError.unsupportedEntitlement("aps-environment")
            }
            requested["aps-environment"] = "production"
        }
        if let betaReports = allowed["beta-reports-active"] { requested["beta-reports-active"] = betaReports }
        for (key, value) in requested {
            guard let permission = allowed[key], Self.permits(value, permission: permission) else {
                throw DistributionError.unsupportedEntitlement(key)
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: requested, format: .xml, options: 0)
        return try PropertyListDecoder().decode(Entitlements.self, from: data)
    }

    private static func permits(_ value: Any, permission: Any) -> Bool {
        if let values = value as? [Any], let permissions = permission as? [Any] {
            return values.allSatisfy { value in permissions.contains { permits(value, permission: $0) } }
        }
        if let value = value as? String, let pattern = permission as? String {
            if pattern == "*" { return true }
            if pattern.hasSuffix(".*") { return value.hasPrefix(String(pattern.dropLast())) }
            return value == pattern
        }
        return (value as? NSObject)?.isEqual(permission) == true
    }
}
