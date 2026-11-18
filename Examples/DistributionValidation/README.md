# Distribution validation fixture

A small iOS app, companion Watch app, and static widget for exercising xtool's distribution pipeline. The targets have no external dependencies, authentication, network traffic, or real user data.

This fixture stays open for manual testing. It is intentionally outside the `Demo*` set used by `Examples/test.sh`, whose apps must exit automatically.

## Local packaging check

With the current fork CLI and its SDK configured, run `xtool dev build --configuration release` from this directory. This builds and packages all three products without provisioning, uploading, or installing them. Inspect `xtool/DistributionValidation.app`, its `Watch/` app, and its `PlugIns/` widget.

This output is not yet an App Store distribution-signed IPA. Passing local packaging checks does not establish Apple's acceptance.

## Real upload validation

Use a dedicated App Store Connect app record and bundle IDs for this fixture. Installing a fixture with the real app's bundle ID replaces that app on the device; TestFlight updates can replace a development installation too. Do not reuse a production app record without explicitly explaining and agreeing to this replacement.

The checked-in bundle IDs are placeholders for local packaging. Before a real upload, the distribution pipeline must use the exact App Store Connect application's bundle ID and matching Watch/widget IDs, profiles, and entitlements. Do not add or remove an `XTL-` prefix merely because it is present in an existing App Store record.

Use a unique build number and consistent versions across targets. Keep account-specific app/group IDs and private keys out of this fixture and Git. The account selection for this work is stored locally in the ignored `.build/testflight-readiness.json` file at the repository root.

## Distribution signing verification

`SigningContext(auth: auth, purpose: .appStore)` selects distribution signing in XKit. The default purpose remains development. Distribution requires bundle IDs and capabilities already registered in the account; it preserves their exact identifiers and checks requested entitlements against the App Store profile. It never revokes certificates or removes profiles. Certificates without a locally saved matching private key cannot be reused; certificate quota errors require the account owner to resolve the missing key or quota.

For an explicit live check, prepare a disposable copy of the built app with the account's exact bundle IDs and Watch companion relationship, then run from the repository root:

```sh
XTOOL_TEST_DISTRIBUTION_APP=/absolute/path/to/Disposable.app \
  swift test --filter distributionSignsPreparedAppWithSavedAccount
```

This opt-in test uses the saved xtool account, may create a distribution certificate and profiles, and signs the supplied copy in place. It verifies the embedded profiles and signed entitlements. It never uploads a build or invites testers. Ordinary `swift test` skips it and uses fake HTTP responses for provisioning regression tests.

## Release archive verification

Generate and compile the fixture icons on a Mac with `python3 prepare-assets.py /path/to/store-assets --compile`, or run the **Distribution fixture assets** workflow. Apple's asset compiler produces separate `iphoneos` and `watchos` folders; copy these as `DistributionValidation` and `DistributionValidationWatch` under the directory passed to `--assets`.

Run `xtool dev archive --version 1.0.0 --build-number 2 --assets /path/to/store-assets` with a configuration using the account's registered identifiers. This builds release and produces a locally checked, distribution-signed IPA. The [distribution guide](../../Documentation/xtool.docc/Distribution.md) covers configuration, asset preparation, output protection and validation limits.

The Linux archive path uses precompiled Apple catalogs; no Linux Watch asset compiler is claimed. Apple processing and actual TestFlight installation remain separate roadmap milestones.
