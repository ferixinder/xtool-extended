# macOS Packaging

xtool is packaged as a .app bundle on macOS, so that we can add entitlements and use the keychain.

Ideally we'd dogfood xtool to package xtool, but it only supports iOS apps right now. Someday, hopefully.

## Building

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2. Run `xcodegen` inside this (`./macOS`) directory
3. Open the Xcode project and build the `XToolMac` scheme

## Release signing

The release workflow builds a signed, notarized app. Configure these GitHub Actions repository secrets before running it in a fork:

- `APP_STORE_CONNECT_API_KEY_KEY_ID`: App Store Connect API key ID.
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`: API key issuer ID.
- `APP_STORE_CONNECT_API_KEY_KEY`: Base64-encoded contents of the API key's `.p8` file.
- `IDENTITY_P12`: Base64-encoded Developer ID Application certificate and private key, exported as a `.p12` without a password.
- `DEVELOPMENT_TEAM`: Apple Developer team ID.

These credentials must belong to your Apple Developer team; upstream repository secrets are not copied to forks.
