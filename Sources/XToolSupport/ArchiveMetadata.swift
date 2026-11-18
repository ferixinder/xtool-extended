import Foundation
import PackLib
import Subprocess
import XCLIUtils
import XUtils

struct ArchiveMetadata {
    let sdkVersion: String
    let values: [String: Any]

    static func load(platform: String) async throws -> Self {
        let sdk: URL
        let xcode: URL
        #if os(macOS)
        func xcrun(_ arguments: [String]) async throws -> String {
            try await Subprocess.run(.path("/usr/bin/xcrun"), arguments: .init(arguments), output: .string(limit: .max))
                .checkSuccess().standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        sdk = try await URL(fileURLWithPath: xcrun(["--sdk", platform, "--show-sdk-path"]))
        let developer = try await URL(fileURLWithPath: xcrun(["--find", "xcodebuild"]))
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        xcode = developer
        #else
        guard let darwin = try DarwinSDK.current() else { throw Console.Error("Run xtool setup to install a Darwin SDK.") }
        let name = platform == "watchos" ? "WatchOS" : "iPhoneOS"
        sdk = darwin.bundle.appendingPathComponent("Developer/Platforms/\(name).platform/Developer/SDKs/\(name).sdk")
        xcode = darwin.bundle.appendingPathComponent("Xcode.app/Contents")
        #endif
        let settings = try ArchiveValidation.readPlist(sdk.appendingPathComponent("SDKSettings.plist"))
        let system = try ArchiveValidation.readPlist(sdk.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist"))
        let version = try ArchiveValidation.readPlist(xcode.appendingPathComponent("version.plist"))
        guard let sdkVersion = settings["Version"] as? String,
              let sdkName = settings["CanonicalName"] as? String,
              let sdkBuild = system["ProductBuildVersion"] as? String,
              let xcodeVersion = version["CFBundleShortVersionString"] as? String,
              let xcodeBuild = version["ProductBuildVersion"] as? String else {
            throw Console.Error("SDK provenance is missing. Reinstall an SDK retaining Xcode and SDK version plists.")
        }
        let parts = xcodeVersion.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first, parts.count <= 3 else { throw Console.Error("Invalid Xcode SDK provenance.") }
        let numeric = major * 100 + (parts.count > 1 ? parts[1] * 10 : 0) + (parts.count > 2 ? parts[2] : 0)
        return Self(sdkVersion: sdkVersion, values: [
            "DTSDKName": sdkName, "DTSDKBuild": sdkBuild,
            "DTPlatformName": platform, "DTPlatformVersion": sdkVersion, "DTPlatformBuild": sdkBuild,
            "DTXcode": String(format: "%04d", numeric), "DTXcodeBuild": xcodeBuild,
        ])
    }
}
