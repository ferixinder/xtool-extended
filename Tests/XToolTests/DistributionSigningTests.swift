import Foundation
import Testing
import X509
@testable import XKit

private func signingContext(_ purpose: SigningContext.Purpose = .development) -> SigningContext {
    SigningContext(auth: .appStoreConnect(.init(id: "test", issuerID: "1234-5678", pem: "")), purpose: purpose)
}

private func entitlements(_ dictionary: [String: Any]) throws -> Entitlements {
    let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    return try PropertyListDecoder().decode(Entitlements.self, from: data)
}

private func appStoreProfile(_ changes: [String: Any] = [:]) throws -> Entitlements {
    try entitlements([
        "application-identifier": "LEGACYPREFIX.com.example.app",
        "com.apple.developer.team-identifier": "TEAMID",
        "get-task-allow": false,
        "aps-environment": "production",
        "keychain-access-groups": ["LEGACYPREFIX.*"],
        "com.apple.security.application-groups": ["group.com.example.shared"],
        "beta-reports-active": true,
    ].merging(changes) { _, new in new })
}

@Test func distributionKeepsExactStoreIdentifiersAndSeparateCertificateStorage() {
    let store = signingContext(.appStore)
    for identifier in ["com.example.app", "XTL-ABC.com.example.app", "com.example.app.watchkitapp"] {
        #expect(ProvisioningIdentifiers.identifier(fromSanitized: identifier, context: store) == identifier)
    }
    let dev = signingContext()
    #expect(dev.purpose == .development)
    #expect(ProvisioningIdentifiers.identifier(fromSanitized: "com.example.app", context: dev)
        == "XTL-1234.com.example.app")
    #expect(ProvisioningIdentifiers.identifier(fromSanitized: "XTL-1234.com.example.app", context: dev)
        == "XTL-1234.com.example.app")
    #expect(dev.purpose.signingInfoID(for: "account") == "account")
    #expect(store.purpose.signingInfoID(for: "account") != "account")
    #expect(store.purpose.acceptsCertificateType("DISTRIBUTION"))
    #expect(store.purpose.acceptsCertificateType("IOS_DISTRIBUTION"))
    #expect(!store.purpose.acceptsCertificateType("DEVELOPMENT"))
    #expect(!dev.purpose.acceptsCertificateType("DISTRIBUTION"))
    #expect(!store.purpose.acceptsCertificateType(nil))
}

@Test func distributionEntitlementsUseProductionPushAndKeepExactAppGroups() throws {
    let requested = try entitlements([
        "get-task-allow": true,
        "aps-environment": "development",
        "keychain-access-groups": ["LEGACYPREFIX.com.example.app"],
        "com.apple.security.application-groups": ["group.com.example.shared"],
    ])
    let result = try requested.forAppStore(profile: appStoreProfile(), bundleID: "com.example.app", teamID: "TEAMID")
    let data = try PropertyListEncoder().encode(result)
    let dictionary = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(dictionary["get-task-allow"] as? Bool == false)
    #expect(dictionary["aps-environment"] as? String == "production")
    #expect(dictionary["application-identifier"] as? String == "LEGACYPREFIX.com.example.app")
    #expect(dictionary["com.apple.security.application-groups"] as? [String] == ["group.com.example.shared"])
    #expect(dictionary["beta-reports-active"] as? Bool == true)
}

@Test func distributionRejectsWrongProfilesAndUnauthorizedEntitlements() throws {
    let empty = try entitlements([:])
    for changes: [String: Any] in [
        ["get-task-allow": true],
        ["application-identifier": "TEAMID.*"],
        ["application-identifier": "TEAMID.com.other.app"],
        ["com.apple.developer.team-identifier": "OTHERTEAM"],
    ] {
        #expect(throws: (any Error).self) {
            try empty.forAppStore(profile: appStoreProfile(changes), bundleID: "com.example.app", teamID: "TEAMID")
        }
    }
    for unauthorized: [String: Any] in [
        ["com.apple.security.application-groups": ["group.other.shared"]],
        ["keychain-access-groups": ["OTHERTEAM.com.example.app"]],
        ["unknown-sensitive-entitlement": true],
    ] {
        #expect(throws: (any Error).self) {
            try entitlements(unauthorized).forAppStore(
                profile: appStoreProfile(), bundleID: "com.example.app", teamID: "TEAMID"
            )
        }
    }
}

@Test func appStoreProfileDigestDoesNotRequireRegisteredDevices() throws {
    let now = Date()
    let data = try PropertyListSerialization.data(fromPropertyList: [
        "Name": "App Store", "UUID": UUID().uuidString, "TeamIdentifier": ["TEAMID"],
        "CreationDate": now, "ExpirationDate": now.addingTimeInterval(3600),
        "DeveloperCertificates": [], "Entitlements": ["get-task-allow": false],
    ], format: .xml, options: 0)
    let digest = try PropertyListDecoder().decode(Mobileprovision.Digest.self, from: data)
    #expect(digest.devices.isEmpty)
    #expect(digest.provisionsAllDevices != true)
}

@Test func distributionRequiresThePrivateKeyMatchingItsCertificate() throws {
    let key = try Keypair()
    let otherKey = try Keypair()
    let name = try DistinguishedName { CommonName("xtool distribution tests") }
    let certificate = try X509.Certificate(
        version: .v3, serialNumber: .init(bytes: [1]), publicKey: .init(key.raw.publicKey),
        notValidBefore: Date(), notValidAfter: Date().addingTimeInterval(3600),
        issuer: name, subject: name, signatureAlgorithm: .sha256WithRSAEncryption,
        extensions: .init(), issuerPrivateKey: .init(key.raw)
    )
    let wrapped = try XKit.Certificate(raw: certificate)
    try SigningInfo(privateKey: key.privateKey(), certificate: wrapped).validateKeypair()
    #expect(throws: (any Error).self) {
        try SigningInfo(privateKey: otherKey.privateKey(), certificate: wrapped).validateKeypair()
    }
}
