import Testing
@testable import PackLib

@Test func cfBundleSupportedPlatformsFollowsBuildTriple() {
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios") == ["iPhoneOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios-simulator") == ["iPhoneSimulator"])

    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios17.0") == ["iPhoneOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-ios17.0-simulator") == ["iPhoneSimulator"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "x86_64-apple-ios-simulator") == ["iPhoneSimulator"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-macosx") == ["MacOSX"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "x86_64-apple-macosx") == ["MacOSX"])

    #expect(Packer.cfBundleSupportedPlatforms(for: "unknown-triple") == ["iPhoneOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64_32-apple-watchos10.0") == ["WatchOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-watchos") == ["WatchOS"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "arm64-apple-watchos10.0-simulator") == ["WatchSimulator"])
    #expect(Packer.cfBundleSupportedPlatforms(for: "x86_64-apple-watchos-simulator") == ["WatchSimulator"])
}
