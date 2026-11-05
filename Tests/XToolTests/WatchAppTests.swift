import Foundation
import Testing
import DeveloperAPI
@testable import PackLib
@testable import XKit

@Test func modernWatchCompanionsUseTheNativeDeviceArchitecture() {
    #expect(BuildSettings.watchDeviceTriple(minimumVersion: "26.0") == "arm64-apple-watchos")
    #expect(BuildSettings.watchDeviceTriple(minimumVersion: "27.0") == "arm64-apple-watchos")
    #expect(BuildSettings.watchDeviceTriple(minimumVersion: "10.0") == "arm64_32-apple-watchos")
    #expect(BuildSettings.watchDeviceTriple(minimumVersion: "11.6") == "arm64_32-apple-watchos")
}

@Test func developmentProfilesIncludeRegisteredAppleWatches() {
    typealias DeviceClass = Components.Schemas.Device.AttributesPayload.DeviceClassPayload.Value1Payload
    #expect(DeviceClass.appleWatch.supportsIOSDevelopmentProfiles)
    #expect(DeviceClass.iphone.supportsIOSDevelopmentProfiles)
    #expect(DeviceClass.ipad.supportsIOSDevelopmentProfiles)
    #expect(!DeviceClass.appleTv.supportsIOSDevelopmentProfiles)
    #expect(!DeviceClass.mac.supportsIOSDevelopmentProfiles)
}

@Test func watchCompanionIdentifiersFollowProvisionedBundleIDs() {
    let result = AutoSigner.remappingWatchIdentifiers(in: [
        "WKCompanionAppBundleIdentifier": "com.example.phone",
        "CFBundleDisplayName": "Counters",
        "NSExtension": ["NSExtensionAttributes": ["WKAppBundleIdentifier": "com.example.phone.watchkitapp"]],
    ], bundleIDs: [
        "com.example.phone": "XTL-123.com.example.phone",
        "com.example.phone.watchkitapp": "XTL-123.com.example.phone.watchkitapp",
    ])
    #expect(result["WKCompanionAppBundleIdentifier"] as? String == "XTL-123.com.example.phone")
    #expect(result["CFBundleDisplayName"] as? String == "Counters")
    let ext = result["NSExtension"] as? [String: Any]
    let attributes = ext?["NSExtensionAttributes"] as? [String: Any]
    #expect(attributes?["WKAppBundleIdentifier"] as? String == "XTL-123.com.example.phone.watchkitapp")
}

@Test func provisioningIncludesWatchAppsAndTheirExtensions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: root) }
    let widget = root.appendingPathComponent("PlugIns/Widget.appex")
    let watch = root.appendingPathComponent("Watch/Counter.app")
    let complication = watch.appendingPathComponent("PlugIns/Complication.appex")
    for directory in [widget, complication, root.appendingPathComponent("Watch/Ignore.bundle")] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let apps = try DeveloperServicesAddAppOperation.appBundles(in: root)
    #expect(Set(apps.map(\.path)) == Set([root, widget, watch, complication].map(\.path)))
}

@Test func watchBuildSettingsSelectTheWatchPlatform() async throws {
    let device = try await BuildSettings(configuration: .debug, triple: "arm64_32-apple-watchos", buildSystem: .swiftPM)
    let simulator = try await BuildSettings(configuration: .debug, triple: "arm64-apple-watchos-simulator", buildSystem: .swiftPM)
    let phone = try await BuildSettings(configuration: .debug, triple: "arm64-apple-ios", buildSystem: .swiftPM)
    #expect(device.isWatchOS && device.platformName == "watchos")
    #expect(simulator.isWatchOS && simulator.platformName == "watchsimulator")
    #expect(!phone.isWatchOS && phone.platformName == "iphoneos")
}
