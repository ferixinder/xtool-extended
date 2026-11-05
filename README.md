# xtool-extended

A fork of [xtool-org/xtool](https://github.com/xtool-org/xtool) that adds companion watchOS app building and packaging to xtool's cross-platform iOS development workflow. Build SwiftPM apps on Linux, Windows through WSL, and macOS.

Watch support is experimental. Building a Watch target and installing its containing iPhone app do not prove that the Watch app was installed or launched successfully on the watch.

## What this fork adds

- A `watchApp` entry in `xtool.yml` to build a separate watchOS product and embed it in the iPhone app's `Watch/` directory.
- WatchOS and WatchSimulator SDK extraction and metadata when those platforms are present in Xcode.
- Watch-specific deployment targets, device family, platform metadata, and build output paths.
- Companion device builds using `arm64` for minimum watchOS 26 or later, or `arm64_32` for earlier targets.
- Provisioning of embedded Watch apps, inclusion of registered Apple Watches in development profiles, and companion bundle ID updates during signing.
- Idempotent capability deletion: an already absent capability does not stop provisioning; authentication and permission failures still do.

## Build this fork

Use a CLI built from this repository to access `watchApp`; the upstream installation guides below describe the base xtool setup.

```sh
git clone https://github.com/ferixinder/xtool-extended.git
cd xtool-extended
swift build --build-system native --product xtool
export PATH="$PWD/.build/debug:$PATH"
xtool --version
```

Linux/WSL requires Swift 6.4 or later and xtool's native device libraries. The [Dockerfile](Dockerfile) provides a development environment with those dependencies; see the [Linux development guide](Linux/README.md). macOS app-bundle builds use `make mac` as described in the [macOS guide](macOS/README.md).

## Add a companion Watch app

Expose separate SwiftPM library products for the iPhone app and the Watch app. Keep the Watch app's `@main` entry point in its own target and share only code that supports both platforms. Declare the deployment targets in `Package.swift`, for example:

```swift
platforms: [
    .iOS(.v17),
    .watchOS("26.0"),
],
```

The string version works with a Swift tools 6.0 manifest; `.watchOS(.v26)` requires PackageDescription 6.2 or later.

Select both products in `xtool.yml`:

```yaml
version: 1
bundleID: com.example.MyApp
product: MyApp
watchApp:
  product: MyWatchApp
  bundleID: com.example.MyApp.watchkitapp
  infoPath: Watch-Info.plist
```

The Watch product name must differ from the iPhone product name. Its bundle ID must start with the iPhone bundle ID followed by a dot. Optional `resources` and `entitlementsPath` fields are also supported under `watchApp`.

Create `Watch-Info.plist` with the companion identifier matching the iPhone app:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>WKApplication</key>
    <true/>
    <key>WKCompanionAppBundleIdentifier</key>
    <string>com.example.MyApp</string>
    <key>WKRunsIndependentlyOfCompanionApp</key>
    <false/>
</dict>
</plist>
```

Run `xtool setup` to configure authentication and the SDK if needed, then run `xtool dev` from the app directory. Normal Linux SDK installations can be refreshed with `xtool sdk update` to include Watch platforms from their retained Xcode copy. Slim SDK installations require reinstalling the SDK from Xcode.

The CLI builds both products and produces:

```text
xtool/MyApp.app/
└── Watch/
    └── MyWatchApp.app/
```

## Watch installation and current limits

- Register the paired Apple Watch's UDID in the same Apple Developer team before provisioning. The install flow currently registers the target iPhone automatically, but does not register its paired Watch.
- iPhone installation success is separate from Watch installation. Check the iPhone's Watch app for the companion app and verify installation on the physical watch.
- Device builds contain one selected architecture, not a universal binary. A watchOS 26+ minimum selects `arm64` and excludes older watchOS versions.
- Companion Watch apps are not supported by `generate-xcode-project` yet.
- This fork packages single-target Watch apps; it does not generate a Watch UI, implement phone/watch data sync, or add complications to your application.

See the [configuration documentation](Documentation/xtool.docc/Control.md#companion-watch-app) for the `watchApp` configuration.

## Overview

xtool is a cross-platform (Linux/WSL/macOS) tool that replicates Xcode functionality with open standards.

✅ Build a SwiftPM package into an iOS app

✅ Sign and install iOS apps

✅ Interact with Apple Developer Services programmatically

## Getting Started

1. Follow the guide to install `xtool`
    - [Installation (Linux/Windows)](https://xtool.sh/documentation/xtooldocs/installation-linux)
    - [Installation (macOS)](https://xtool.sh/documentation/xtooldocs/installation-macos)
2. Create and run your first xtool-powered app by following the [tutorial](https://xtool.sh/tutorials/xtooldocs/first-app)!

## Examples

### Screenshot

![A screenshot of xtool being invoked from VSCode](Documentation/xtool.docc/Resources/Cover.png)

### Command line interface

```bash
$ xtool --help
OVERVIEW: Cross-platform Xcode replacement

USAGE: xtool <subcommand>

OPTIONS:
  -h, --help              Show help information.

CONFIGURATION SUBCOMMANDS:
  setup                   Set up xtool for iOS development
  auth                    Manage Apple Developer Services authentication
  sdk                     Manage the Darwin Swift SDK

DEVELOPMENT SUBCOMMANDS:
  new                     Create a new xtool SwiftPM project
  dev                     Build and run an xtool SwiftPM project
  ds                      Interact with Apple Developer Services

DEVICE SUBCOMMANDS:
  devices                 List devices
  install                 Install an ipa file to your device
  uninstall               Uninstall an installed app
  launch                  Launch an installed app

  See 'xtool help <subcommand>' for detailed help.
```

### Library

You can consume xtool itself as a Swift Package, to enable your own app to interact with Apple Developer Services, iOS devices, and more. You can use this by adding `XKit` or `XToolSupport` as a SwiftPM dependency.

Note: while we aim to uphold semver semantics on the CLI interface (breaking change = major version bump), the Swift interface does not offer the same guarantees.

```swift
// package dependency:
.package(url: "https://github.com/xtool-org/xtool", .upToNextMinor(from: "1.2.0"))
// target dependency:
.product(name: "XKit", package: "xtool")
```
