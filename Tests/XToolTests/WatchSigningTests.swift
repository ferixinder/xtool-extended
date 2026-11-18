import Foundation
import Testing
import XKit
@testable import XToolSupport

@Test func standaloneWatchSigningRejectsWrongPlatformsAndMissingDevice() throws {
    let info: [String: Any] = [
        "WKApplication": true, "WKWatchOnly": true, "CFBundleSupportedPlatforms": ["WatchOS"],
    ]
    try DevWatchSignCommand.validate(info: info, udid: "test-watch")
    for change: [String: Any] in [
        ["CFBundleSupportedPlatforms": ["iPhoneOS"]],
        ["CFBundleSupportedPlatforms": ["WatchSimulator"]],
        ["WKApplication": false], ["WKWatchOnly": false],
    ] {
        #expect(throws: (any Error).self) {
            try DevWatchSignCommand.validate(info: info.merging(change) { _, new in new }, udid: "test-watch")
        }
    }
    #expect(throws: (any Error).self) { try DevWatchSignCommand.validate(info: info, udid: " \n") }
}

@Test func standaloneWatchSigningNeverRevokesExistingCertificates() async {
    let delegate = XToolInstallerDelegate(allowsRevocation: false)
    #expect(await !delegate.confirmRevocation(of: []))
    #expect(await delegate.refusedRevocation)
}

@Test func standaloneWatchSigningRejectsAnUnauthorizedAppGroup() throws {
    let requested = try Entitlements(entitlements: [AppGroupEntitlement(rawValue: [.init(rawValue: "group.test")])])
    let empty = try Entitlements(entitlements: [])
    try DevWatchSignCommand.validateAppGroups(requested: requested, allowed: requested)
    try DevWatchSignCommand.validateAppGroups(requested: empty, allowed: requested)
    #expect(throws: (any Error).self) {
        try DevWatchSignCommand.validateAppGroups(requested: requested, allowed: empty)
    }
}
