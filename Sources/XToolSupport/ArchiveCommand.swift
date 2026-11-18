import ArgumentParser
import Dependencies
import Foundation
import PackLib
import XCLIUtils
import XKit
import XUtils

struct DevArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Build, validate and distribution-sign a release IPA without uploading it"
    )

    @Option(help: "Marketing version, for example 1.0.0") var version: String
    @Option(help: "Unique numeric build number, for example 2") var buildNumber: String
    @Option(help: "Configuration file") var config = "xtool.yml"
    @Option(help: "Directory of compiled asset folders, named after each app executable") var assets: String
    @Option(help: "Destination IPA; existing files are never overwritten") var output: String?

    func run() async throws {
        try ArchiveValidation.validateVersions(version: version, build: buildNumber)
        let schema = try await PackSchema(url: URL(fileURLWithPath: config))
        let token = try AuthToken.saved()
        let context = SigningContext(auth: token.authData(), purpose: .appStore)
        let app = try await PackOperation(
            buildOptions: .init(configuration: .release), schemaOverride: schema, distribution: true
        ).run()
        let archive = try await DistributionArchive.prepare(
            app: app, assets: URL(fileURLWithPath: assets), version: version, build: buildNumber
        )
        let filename = "\(app.deletingPathExtension().lastPathComponent)-\(version)-\(buildNumber).ipa"
        let destination = output.map { URL(fileURLWithPath: $0) }
            ?? app.deletingLastPathComponent().appendingPathComponent(filename)
        guard destination.pathExtension == "ipa", !destination.exists else {
            throw Console.Error("Choose an unused .ipa output path. Existing archives are preserved.")
        }
        _ = try await AutoSigner(context: context, confirmRevocation: { _ in false }).sign(
            app: archive.app, status: { d.out.print($0) }, progress: { _ in }
        )
        try await ArchiveValidation.validateSignatures(in: archive.app)
        try await DistributionArchive.writeIPA(app: archive.app, to: destination)
        d.out.print("Wrote locally validated distribution IPA to \(destination.path)")
        d.out.print("Version \(version), build \(buildNumber). Not uploaded; Apple processing has not been verified.")
    }
}

struct DistributionArchive: ~Copyable {
    let directory: TemporaryDirectory
    let app: URL

    static func prepare(app: URL, assets: URL, version: String, build: String) async throws -> Self {
        try ArchiveValidation.validateVersions(version: version, build: build)
        let directory = try TemporaryDirectory(name: "distribution-archive")
        let copy = directory.url.appendingPathComponent(app.lastPathComponent)
        try FileManager.default.copyItem(at: app, to: copy)
        let result = Self(directory: directory, app: copy)
        let bundles = try DeveloperServicesAddAppOperation.appBundles(in: copy)
        let mainID = try ArchiveValidation.info(copy)["CFBundleIdentifier"] as? String
        for bundle in bundles {
            var info = try ArchiveValidation.info(bundle)
            guard let executable = info["CFBundleExecutable"] as? String,
                  URL(fileURLWithPath: executable).lastPathComponent == executable,
                  let minimum = info["MinimumOSVersion"] as? String else {
                throw Console.Error("Missing executable or minimum OS in \(bundle.lastPathComponent).")
            }
            let watch = bundle.pathComponents.contains("Watch")
            let platform = watch ? "watchos" : "iphoneos"
            let metadata = try await ArchiveMetadata.load(platform: platform)
            let binary = try ArchiveMachO(contentsOf: bundle.appendingPathComponent(executable))
            try binary.validate(platform: platform, minimum: minimum, sdk: metadata.sdkVersion)
            info.merge(metadata.values) { _, new in new }
            info["CFBundleShortVersionString"] = version
            info["CFBundleVersion"] = build
            info["CFBundleSupportedPlatforms"] = [watch ? "WatchOS" : "iPhoneOS"]
            if !watch { try ArchiveValidation.requireArm64(in: &info) }
            if bundle.pathExtension == "app" {
                try mergeAssets(from: assets.appendingPathComponent(executable), into: bundle, info: &info)
            }
            if bundle != copy {
                guard let identifier = info["CFBundleIdentifier"] as? String,
                      let mainID, identifier.hasPrefix(mainID + ".") else {
                    throw Console.Error("Embedded bundle IDs must be prefixed by the host bundle ID.")
                }
            }
            if watch, bundle.pathExtension == "app", info["WKCompanionAppBundleIdentifier"] as? String != mainID {
                throw Console.Error("Watch companion identifier does not match the iOS host.")
            }
            try ArchiveValidation.writeInfo(info, to: bundle)
            try ArchiveValidation.validateEmbeddedCode(in: bundle, platform: platform, minimum: minimum)
        }
        try ArchiveValidation.rejectUncompiledResources(in: copy)
        return result
    }

    static func mergeAssets(from source: URL, into bundle: URL, info: inout [String: Any]) throws {
        let car = source.appendingPathComponent("Assets.car")
        guard let data = try? Data(contentsOf: car, options: .mappedIfSafe), data.count >= 512,
              data.prefix(8) == Data("BOMStore".utf8) else {
            throw Console.Error("Missing compiled Assets.car in \(source.path). Compile icons with macOS actool; see Distribution.md.")
        }
        let additions = try ArchiveValidation.info(source)
        let permitted: Set<String> = ["CFBundleIcons", "CFBundleIcons~ipad", "CFBundleIconName", "CFBundleIconFiles"]
        guard additions["CFBundleIcons"] != nil || additions["CFBundleIconName"] != nil else {
            throw Console.Error("Compiled asset Info.plist must declare the application icon.")
        }
        for (key, value) in additions where permitted.contains(key) { info[key] = value }
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            guard file.lastPathComponent == "Assets.car" || file.pathExtension == "png" else { continue }
            let destination = bundle.appendingPathComponent(file.lastPathComponent)
            if destination.exists { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: file, to: destination)
        }
    }

    static func writeIPA(app: URL, to destination: URL) async throws {
        guard !destination.exists else { throw Console.Error("Archive already exists: \(destination.path)") }
        @Dependency(\.zipCompressor) var compressor
        let temporary = try TemporaryDirectory(name: "Payload")
        try FileManager.default.copyItem(at: app, to: temporary.url.appendingPathComponent(app.lastPathComponent))
        let ipa = try await compressor.compress(directory: temporary.url, progress: { _ in })
        // Stage on the destination filesystem, then rename without removing an existing archive.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).ipa")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: ipa, to: staging)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
    }
}
