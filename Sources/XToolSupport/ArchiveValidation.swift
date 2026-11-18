import Dependencies
import Foundation
import Subprocess
import XCLIUtils
import XKit
import XUtils

enum ArchiveValidation {
    static func requireArm64(in info: inout [String: Any]) throws {
        let key = "UIRequiredDeviceCapabilities"
        if var capabilities = info[key] as? [String: Bool] {
            guard capabilities["arm64"] != false else { throw Console.Error("Distribution requires the arm64 device capability.") }
            capabilities["arm64"] = true
            info[key] = capabilities
        } else if var capabilities = info[key] as? [String] {
            if !capabilities.contains("arm64") { capabilities.append("arm64") }
            info[key] = capabilities
        } else if info[key] == nil {
            info[key] = ["arm64"]
        } else {
            throw Console.Error("Invalid UIRequiredDeviceCapabilities.")
        }
    }

    static func validateVersions(version: String, build: String) throws {
        func numbers(_ string: String, counts: ClosedRange<Int>, widths: [Int]) -> Bool {
            let parts = string.split(separator: ".", omittingEmptySubsequences: false)
            return counts.contains(parts.count) && parts.enumerated().allSatisfy { index, part in
                !part.isEmpty && part.count <= widths[index] && part.allSatisfy { $0 >= "0" && $0 <= "9" }
                    && (part == "0" || !part.hasPrefix("0"))
            }
        }
        guard numbers(version, counts: 3...3, widths: [4, 4, 4]),
              numbers(build, counts: 1...3, widths: [4, 2, 2]), !build.hasPrefix("0") else {
            throw Console.Error("Use a version such as 1.0.0 and a positive build number such as 2 or 2.1.0.")
        }
    }

    static func readPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Console.Error("Expected a plist dictionary at \(url.path)")
        }
        return info
    }

    static func info(_ bundle: URL) throws -> [String: Any] {
        try readPlist(bundle.appendingPathComponent("Info.plist"))
    }

    static func writeInfo(_ info: [String: Any], to bundle: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Info.plist"), options: .atomic)
    }

    static func rejectUncompiledResources(in app: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else {
            throw Console.Error("Cannot inspect archive resources.")
        }
        for case let url as URL in enumerator where ["xcassets", "storyboard", "xib"].contains(url.pathExtension) {
            throw Console.Error("Uncompiled resource: \(url.lastPathComponent). Compile it with the matching Xcode tool first.")
        }
    }

    static func validateEmbeddedCode(in bundle: URL, platform: String, minimum: String) throws {
        let frameworks = bundle.appendingPathComponent("Frameworks")
        guard frameworks.exists else { return }
        for url in try FileManager.default.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil) {
            let binary: URL
            if url.pathExtension == "framework" {
                let plist = try info(url)
                guard let name = plist["CFBundleExecutable"] as? String, !name.contains("/") else {
                    throw Console.Error("Invalid embedded framework executable.")
                }
                binary = url.appendingPathComponent(name)
            } else if url.pathExtension == "dylib" {
                binary = url
            } else {
                throw Console.Error("Unexpected Frameworks entry: \(url.lastPathComponent)")
            }
            let code = try ArchiveMachO(contentsOf: binary)
            let expectedPlatform: UInt32 = platform == "watchos" ? 4 : 2
            let minimumVersion = try ArchiveMachO.version(minimum)
            guard Set(code.slices.map(\.cpu)) == (try ArchiveMachO.requiredCPUs(platform: platform, minimum: minimum)) else {
                throw Console.Error("Embedded framework is missing a required architecture: \(url.lastPathComponent)")
            }
            for slice in code.slices {
                guard slice.platform == expectedPlatform, slice.minimum <= minimumVersion else {
                    throw Console.Error("Incompatible embedded framework architecture or deployment target: \(url.lastPathComponent)")
                }
            }
        }
    }

    static func validateSignatures(in app: URL) async throws {
        @Dependency(\.signer) var signer
        for bundle in try DeveloperServicesAddAppOperation.appBundles(in: app) {
            let plist = try info(bundle)
            guard let executable = plist["CFBundleExecutable"] as? String,
                  let identifier = plist["CFBundleIdentifier"] as? String else {
                throw Console.Error("Missing signed bundle identifiers.")
            }
            let binaryURL = bundle.appendingPathComponent(executable)
            let binary = try ArchiveMachO(contentsOf: binaryURL)
            try await verifyCMS(binary)
            try binary.validateBundleSeals(
                info: Data(contentsOf: bundle.appendingPathComponent("Info.plist")),
                resources: Data(contentsOf: bundle.appendingPathComponent("_CodeSignature/CodeResources"))
            )
            let profile = try Mobileprovision(data: Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")))
            let digest = try profile.digest()
            let data = try await signer.analyze(executable: binaryURL)
            guard let data,
                  let entitlements = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let appID = entitlements["application-identifier"] as? String,
                  appID.hasSuffix(".\(identifier)"), entitlements["get-task-allow"] as? Bool == false,
                  digest.devices.isEmpty, digest.provisionsAllDevices != true, digest.expirationDate > Date() else {
                throw Console.Error("Invalid App Store profile or distribution entitlements in \(bundle.lastPathComponent)")
            }
            if let frameworks = FileManager.default.enumerator(
                at: bundle.appendingPathComponent("Frameworks"), includingPropertiesForKeys: nil
            ) {
                for case let file as URL in frameworks where file.pathExtension == "dylib" {
                    try await verifyCMS(ArchiveMachO(contentsOf: file))
                }
            }
            let frameworkRoot = bundle.appendingPathComponent("Frameworks")
            if frameworkRoot.exists {
                for framework in try FileManager.default.contentsOfDirectory(at: frameworkRoot, includingPropertiesForKeys: nil)
                    where framework.pathExtension == "framework" {
                    guard let name = try info(framework)["CFBundleExecutable"] as? String else {
                        throw Console.Error("Missing framework executable.")
                    }
                    try await verifyCMS(ArchiveMachO(contentsOf: framework.appendingPathComponent(name)))
                }
            }
        }
    }

    static func verifyCMS(_ binary: ArchiveMachO) async throws {
        let directory = try TemporaryDirectory(name: "verify-signature")
        for slice in binary.slices {
            guard let code = slice.codeDirectory, let signature = slice.signature, !signature.isEmpty else {
                throw Console.Error("An executable is unsigned or ad-hoc signed.")
            }
            let codeURL = directory.url.appendingPathComponent("CodeDirectory")
            let signatureURL = directory.url.appendingPathComponent("Signature.der")
            try code.write(to: codeURL)
            try signature.write(to: signatureURL)
            // Verify the CMS signature; Apple's trust and full package validation run during processing.
            try await Subprocess.run(.name("openssl"), arguments: [
                "cms", "-verify", "-binary", "-inform", "DER", "-noverify",
                "-in", signatureURL.path, "-content", codeURL.path,
            ], output: .discarded, error: .discarded).checkSuccess()
        }
    }
}
