import ArgumentParser
import Dependencies
import Foundation
import Subprocess
import XCLIUtils
import XKit
import XUtils

struct DSUploadBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upload-build", abstract: "Upload a prepared distribution IPA and check Apple's processing result"
    )
    @Argument(help: "Distribution-signed IPA") var ipa: String
    @Option(help: "Existing App Store Connect app record ID") var appID: String
    @Option(help: "Maximum processing wait in seconds") var timeout = 600

    func run() async throws {
        guard timeout >= 0, timeout <= 3600 else { throw ValidationError("timeout must be between 0 and 3600 seconds") }
        let uploader = try BuildUploadMonitor.uploader()
        let temporary = try TemporaryDirectory(name: "upload-build")
        let ipaURL = URL(fileURLWithPath: ipa)
        try await Self.checkArchivePaths(ipaURL)
        @Dependency(\.zipCompressor) var compressor
        try await compressor.decompress(file: ipaURL, in: temporary.url, progress: { _ in })
        let apps = try FileManager.default.contentsOfDirectory(
            at: temporary.url.appendingPathComponent("Payload"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "app" }
        guard apps.count == 1 else { throw Console.Error("The IPA must contain exactly one Payload/*.app.") }
        let app = apps[0]
        try await ArchiveValidation.validateSignatures(in: app)
        let info = try ArchiveValidation.info(app)
        guard let bundleID = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { throw Console.Error("Missing IPA version or bundle identifier.") }
        try ArchiveValidation.validateVersions(version: version, build: build)
        for bundle in try DeveloperServicesAddAppOperation.appBundles(in: app) {
            let nested = try ArchiveValidation.info(bundle)
            guard nested["CFBundleShortVersionString"] as? String == version,
                  nested["CFBundleVersion"] as? String == build else {
                throw Console.Error("Embedded bundle versions must match the host.")
            }
        }
        let id = try await uploader.upload(ipa: ipaURL, appID: appID, bundleID: bundleID, version: version, build: build) { event in
            switch event {
            case .created(let id): d.out.print("Build upload ID: \(id)")
            case .transferred(let sent, let total): d.out.print("Transferred \(sent)/\(total) bytes")
            case .committed: d.out.print("File committed. Waiting for Apple processing; not yet accepted.")
            }
        }
        try await BuildUploadMonitor.wait(uploader: uploader, id: id, timeout: timeout)
    }

    private static func checkArchivePaths(_ ipa: URL) async throws {
        let result = try await Subprocess.run(.name("unzip"), arguments: ["-Z1", ipa.path], output: .string(limit: 4 * 1024 * 1024))
            .checkSuccess()
        let metadata = try await Subprocess.run(
            .name("unzip"), arguments: ["-Z", "-l", ipa.path], output: .string(limit: 4 * 1024 * 1024)
        )
            .checkSuccess()
        try validateArchiveEntries(names: result.standardOutput, listing: metadata.standardOutput)
    }

    static func validateArchiveEntries(names: String, listing: String) throws {
        for name in names.split(separator: "\n") {
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/").contains("..") else {
                throw Console.Error("The IPA contains an unsafe archive entry.")
            }
        }
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw Console.Error("The prepared IPA upload path currently requires an archive without symlinks.")
        }
    }
}

struct DSBuildUploadStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-upload-status", abstract: "Check an existing build upload without uploading again"
    )
    @Argument var uploadID: String
    @Option(help: "Maximum processing wait in seconds; zero checks once") var timeout = 0

    func run() async throws {
        guard timeout >= 0, timeout <= 3600 else { throw ValidationError("timeout must be between 0 and 3600 seconds") }
        try await BuildUploadMonitor.wait(uploader: BuildUploadMonitor.uploader(), id: uploadID, timeout: timeout)
    }
}

private enum BuildUploadMonitor {
    static func uploader() throws -> BuildUploader {
        guard case .appStoreConnect(let key) = try AuthToken.saved() else {
            throw Console.Error("Build uploads require an App Store Connect API key. Configure one with xtool auth.")
        }
        return BuildUploader(key: .init(id: key.id, issuerID: key.issuerID, pem: key.pem))
    }

    static func wait(uploader: BuildUploader, id: String, timeout: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        repeat {
            let status = try await uploader.status(uploadID: id)
            d.out.print("Upload \(id): \(status.state); build processing: \(status.processingState ?? "not available")")
            if status.failed {
                let details = status.errors.isEmpty
                    ? "See App Store Connect for validation details." : status.errors.joined(separator: "\n")
                throw Console.Error("Apple rejected the build: \(details)")
            }
            if status.accepted {
                d.out.print("Apple processing accepted build \(status.buildID ?? ""). No tester distribution was requested.")
                return
            }
            if timeout == 0 { return }
            guard clock.now < deadline else {
                let command = "xtool ds build-upload-status \(id) --timeout 600"
                throw Console.Error("Still processing. Check with \(command). Do not upload again.")
            }
            try await clock.sleep(for: .seconds(5))
        } while true
    }
}
