import Dependencies
import Foundation
import Testing
import XKit
@testable import XToolSupport

private func machO(cpu: UInt32 = 0x0100000c, platform: UInt32 = 2, minimum: UInt32 = 17 << 16) -> Data {
    let words: [UInt32] = [0xfeedfacf, cpu, 0, 2, 1, 24, 0, 0, 0x32, 24, platform, minimum, 27 << 16, 0]
    return words.reduce(into: Data()) { data, word in
        var value = word.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

@Test func archiveVersionsRequireExplicitValidStoreNumbers() throws {
    try ArchiveValidation.validateVersions(version: "1.0.0", build: "1")
    try ArchiveValidation.validateVersions(version: "26.2.3", build: "1234.99.99")
    for (version, build) in [("1.0", "1"), ("1.0.0", "0"), ("1.0.0", "01"), ("1.0.0", "2beta"),
                             ("1.0.0", "1.100"), ("1.0.0", "10000"), ("1..0", "1"), ("1.0.0", "١")] {
        #expect(throws: (any Error).self) { try ArchiveValidation.validateVersions(version: version, build: build) }
    }
}

@Test func archiveRejectsSimulatorWrongArchitectureAndMismatchedSDK() throws {
    let ios = try ArchiveMachO(data: machO())
    try ios.validate(platform: "iphoneos", minimum: "17.0", sdk: "27.0")
    let watch = try ArchiveMachO(data: machO(platform: 4, minimum: 27 << 16))
    try watch.validate(platform: "watchos", minimum: "27.0", sdk: "27.0")
    let oldWatch = try ArchiveMachO(data: machO(cpu: 0x0200000c, platform: 4, minimum: 26 << 16))
    #expect(throws: (any Error).self) { try oldWatch.validate(platform: "watchos", minimum: "26.0", sdk: "27.0") }
    for binary in [machO(cpu: 0x01000007), machO(platform: 7), machO(minimum: 18 << 16)] {
        #expect(throws: (any Error).self) {
            try ArchiveMachO(data: binary).validate(platform: "iphoneos", minimum: "17.0", sdk: "27.0")
        }
    }
    #expect(throws: (any Error).self) { try ios.validate(platform: "iphoneos", minimum: "17.0", sdk: "26.0") }
    for data in [Data(), Data(repeating: 255, count: 100), machO().prefix(40)] {
        #expect(throws: (any Error).self) { try ArchiveMachO(data: Data(data)) }
    }
}

@Test func watchDistributionBefore27RequiresBothArchitectures() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let first = root.appendingPathComponent("arm64")
    let second = root.appendingPathComponent("arm64_32")
    let universal = root.appendingPathComponent("universal")
    try machO(platform: 4, minimum: 26 << 16).write(to: first)
    try machO(cpu: 0x0200000c, platform: 4, minimum: 26 << 16).write(to: second)
    try UniversalWatchBinary.merge(first, second, into: universal)
    let binary = try ArchiveMachO(contentsOf: universal)
    #expect(binary.slices.count == 2)
    try binary.validate(platform: "watchos", minimum: "26.0", sdk: "27.0")
    #expect(throws: (any Error).self) {
        try ArchiveMachO(contentsOf: first).validate(platform: "watchos", minimum: "26.0", sdk: "27.0")
    }
}

@Test func distributionAddsArm64CapabilityWithoutDroppingOtherRequirements() throws {
    var dictionary: [String: Any] = ["UIRequiredDeviceCapabilities": ["gps": true]]
    try ArchiveValidation.requireArm64(in: &dictionary)
    #expect(dictionary["UIRequiredDeviceCapabilities"] as? [String: Bool] == ["gps": true, "arm64": true])
    var array: [String: Any] = ["UIRequiredDeviceCapabilities": ["gps"]]
    try ArchiveValidation.requireArm64(in: &array)
    #expect(array["UIRequiredDeviceCapabilities"] as? [String] == ["gps", "arm64"])
    var denied: [String: Any] = ["UIRequiredDeviceCapabilities": ["arm64": false]]
    #expect(throws: (any Error).self) { try ArchiveValidation.requireArm64(in: &denied) }
}

@Test func archiveNeverTreatsUnsignedCodeAsDistributionSigned() async throws {
    await #expect(throws: (any Error).self) { try await ArchiveValidation.verifyCMS(ArchiveMachO(data: machO())) }
}

@Test func archiveRejectsFrameworksRequiringANewerOSOrWrongPlatform() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    defer { try? FileManager.default.removeItem(at: root) }
    let framework = root.appendingPathComponent("Frameworks/Shared.framework")
    try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
    try ArchiveValidation.writeInfo(["CFBundleExecutable": "Shared"], to: framework)
    let executable = framework.appendingPathComponent("Shared")
    try machO(minimum: 16 << 16).write(to: executable)
    try ArchiveValidation.validateEmbeddedCode(in: root, platform: "iphoneos", minimum: "17.0")
    for data in [machO(minimum: 18 << 16), machO(platform: 7), machO(cpu: 0x01000007)] {
        try data.write(to: executable)
        #expect(throws: (any Error).self) {
            try ArchiveValidation.validateEmbeddedCode(in: root, platform: "iphoneos", minimum: "17.0")
        }
    }
}

@Test func archiveAssetMergeOnlyAcceptsIconMetadata() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let assets = root.appendingPathComponent("assets")
    let app = root.appendingPathComponent("test.app")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": "com.example.test"]
    #expect(throws: (any Error).self) { try DistributionArchive.mergeAssets(from: assets, into: app, info: &info) }
    try (Data("BOMStore".utf8) + Data(repeating: 0, count: 504)).write(to: assets.appendingPathComponent("Assets.car"))
    try ArchiveValidation.writeInfo([
        "CFBundleIconName": "AppIcon", "CFBundleIdentifier": "must-not-override",
        "CFBundleExecutable": "must-not-override", "CFBundleVersion": "999",
    ], to: assets)
    try DistributionArchive.mergeAssets(from: assets, into: app, info: &info)
    #expect(info["CFBundleIdentifier"] as? String == "com.example.test")
    #expect(info["CFBundleIconName"] as? String == "AppIcon")
    #expect(info["CFBundleExecutable"] == nil)
    #expect(info["CFBundleVersion"] == nil)
}

@Test func archivePreservesExistingOutputAndFailedPackagingLeavesNoOutput() async throws {
    enum Failure: Error { case compress }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("test.app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    let destination = root.appendingPathComponent("test.ipa")
    let original = Data("previous valid archive".utf8)
    try original.write(to: destination)
    await #expect(throws: (any Error).self) { try await DistributionArchive.writeIPA(app: app, to: destination) }
    #expect(try Data(contentsOf: destination) == original)
    let other = root.appendingPathComponent("new.ipa")
    await withDependencies {
        $0.zipCompressor = ZIPCompressor(compress: { _, _ in throw Failure.compress }, decompress: { _, _, _ in })
    } operation: {
        await #expect(throws: Failure.compress) { try await DistributionArchive.writeIPA(app: app, to: other) }
    }
    #expect(!FileManager.default.fileExists(atPath: other.path))
    #expect(try Data(contentsOf: destination) == original)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["XTOOL_TEST_ARCHIVE_APP"] != nil))
func archiveVerifiesRealDistributionSignatures() async throws {
    let app = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["XTOOL_TEST_ARCHIVE_APP"]))
    try await withDependencies { $0.context = .live } operation: {
        try await ArchiveValidation.validateSignatures(in: app)
        let info = try ArchiveValidation.info(app)
        let name = try #require(info["CFBundleExecutable"] as? String)
        var tampered = try Data(contentsOf: app.appendingPathComponent(name))
        try #require(tampered.count > 8192)
        tampered[8192] ^= 1
        #expect(throws: (any Error).self) { try ArchiveMachO(data: tampered) }
        let binary = try ArchiveMachO(contentsOf: app.appendingPathComponent(name))
        #expect(throws: (any Error).self) {
            try binary.validateBundleSeals(info: Data("tampered".utf8), resources: Data())
        }
    }
}
