# Prepare a distribution IPA

Build a release IPA for local inspection, without uploading or distributing it.

## Requirements

Use a paid Apple Developer account and log in with `xtool auth`. Register the exact iOS, Watch, extension and App Group identifiers and capabilities before archiving. Distribution preserves these identifiers, including an existing `XTL-` prefix if it is part of the actual App Store Connect record. It does not change an existing app's capabilities.

Keep account-specific configuration and private keys outside Git. Use `--config` to select a local configuration if the checked-in `xtool.yml` contains placeholder identifiers. The Watch Info.plist's companion identifier must also match the selected iOS identifier.

The host needs `zip` and an OpenSSL executable supporting `openssl cms`. Linux/WSL also needs the configured Darwin SDK, including its retained Xcode version and SDK settings plists. The source SDK supplies build provenance; the command does not invent Xcode or SDK build numbers.

## Compile icons and resources

The current Linux packer copies resource files; it cannot replace Apple's asset compiler for distribution. Compile each app's icon catalog on macOS with Xcode and reuse those outputs on Linux. Keep a directory named after each app's `CFBundleExecutable`:

```text
store-assets/
  MyApp/
    Assets.car
    Info.plist
    AppIcon60x60@2x.png
    ...
  MyWatchApp/
    Assets.car
    Info.plist
    ...
```

For an iOS catalog on a Mac:

```sh
mkdir -p store-assets/MyApp
xcrun actool Resources/Assets.xcassets \
  --compile store-assets/MyApp \
  --platform iphoneos --minimum-deployment-target 17.0 \
  --target-device iphone --target-device ipad --app-icon AppIcon \
  --output-partial-info-plist store-assets/MyApp/Info.plist
```

For Watch use its own icon catalog, `--platform watchos`, `--target-device watch`, the Watch minimum version and a separate output folder. Copy the complete output folder to Linux. Recompile when the catalog, target devices or deployment target changes. The partial Info.plist contributes icon keys only; it cannot replace bundle identifiers, executable names or versions.

For this repository's synthetic fixture, `Examples/DistributionValidation/prepare-assets.py /path/to/assets --compile` generates opaque test icons and compiles both catalogs on a Mac. Its `iphoneos` and `watchos` output folders correspond to `DistributionValidation` and `DistributionValidationWatch`; rename or copy them accordingly. The manually runnable **Distribution fixture assets** GitHub Actions workflow provides the same macOS path without uploading account keys, user data, or application binaries. It verifies both catalogs with Apple's `assetutil`.

Raw `.xcassets`, `.storyboard` and `.xib` resources in the final bundle are rejected. Compile non-icon catalogs and interface resources with the appropriate Xcode tools before adding their outputs through `resources`. A widget does not receive the host application's app-icon catalog.

## Archive

From the application's project directory:

```sh
xtool dev archive \
  --version 1.0.0 --build-number 2 \
  --assets /absolute/path/to/store-assets
```

The command always builds release, synchronizes versions across the iOS app, Watch app and extensions, imports compiled icons, checks Mach-O platform/architecture/deployment/SDK values, signs with App Store profiles and verifies the resulting CMS signatures and executable page hashes. It also checks the signed Info.plist and resource-manifest seals. Embedded frameworks and dylibs must target a compatible device architecture and OS.

Versions use three numeric components, such as `1.0.0`. Build numbers use one to three numeric components (up to four digits in the first, two in the others), starting above zero. Use a new build number for each upload. By default the IPA is written as `xtool/MyApp-1.0.0-2.ipa`. An explicit `--output /path/to/result.ipa` is also supported. Existing outputs are refused and preserved; a packaging failure does not publish a partial destination IPA.

The ordinary development commands retain their existing signing and installation behavior. The archive command separately supplies the actual SDK version to the linker: otherwise Linux's linker may record the deployment target as the SDK version.

## Limits of local validation

This produces a distribution-signed IPA, not a TestFlight build. It does not contact the build-upload API, check App Store Connect for a duplicate build number, invite testers or submit a version for review. Existing output protection prevents accidental local overwrites; remote duplicate detection belongs to the upload milestone.

The local Mach-O validator supports device arm64 and Watch arm64_32, thin Mach-O and ordinary fat containers; unsupported formats fail explicitly. Watch distribution below watchOS 27 requires both arm64 and arm64_32. The archive path builds both and combines the Watch executable and embedded Mach-O libraries before signing. watchOS 27+ requires arm64 only. Apple returned error 90733 for the earlier arm64-only watchOS 26 validation build; a local architecture check alone had not established acceptance. Development builds still select a single device architecture.

All iOS bundles, including extensions, receive the arm64 required-device capability while preserving other capability requirements. Apple returned error 90502 when this was missing from the widget.

Framework architecture and minimum OS are checked, but this is not a replacement for Apple's complete bundle/resource validation or certificate trust policy. Apple's processing establishes acceptance in milestone 3. A macOS full archive run and distribution to Watch targets older than watchOS 26 have not yet been verified; macOS asset compilation and Linux IPA production have been verified separately.

## References

- [Apple: preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Apple: configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Apple: creating an App Store profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
