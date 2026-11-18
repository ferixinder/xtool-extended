# Upload a prepared build

Upload an existing distribution IPA and distinguish file delivery from Apple's build acceptance.

## Upload

Use an App Store Connect API key saved with `xtool auth`, with permission to upload builds for the selected existing app record. First prepare a distribution-signed IPA as described in <doc:Distribution>.

```sh
xtool ds upload-build /path/to/MyApp-1.0.0-2.ipa --app-id YOUR_APP_RECORD_ID
```

This narrow command does not build or sign a new app, invite testers, attach a build to a test group, submit for review, or publish a version. The combined `xtool deploy testflight` command remains a later milestone.

Before creating an upload, it checks the IPA's signatures and consistent versions, matches the bundle identifier to the selected app record, and checks for an existing build or upload with the same iOS version/build. The prepared-IPA path currently rejects symlinks and unsafe archive paths rather than extracting them unchecked.

It creates a build upload, reserves a file, follows Apple's HTTPS upload operations, and commits the file with an MD5 checksum. The file is hashed and streamed in chunks of at most 1 MiB, and rechecked before committing. The App Store Connect JWT is added only to API requests; file-upload requests receive only the headers specified for that operation. Signed upload URLs and private keys are not printed. Transfer failures report a status without exposing the upload URL.

## Check processing without uploading again

The command prints the upload ID immediately after creation. Save it: a transport failure or timeout does not mean that the upload was never created.

```sh
xtool ds build-upload-status UPLOAD_ID
xtool ds build-upload-status UPLOAD_ID --timeout 600
```

`upload-build` waits up to 600 seconds by default. `--timeout 0` transfers and commits the file, then checks once; its success means the requested transfer completed, not that Apple accepted the build. The status command checks once by default and can wait for up to 3600 seconds.

The output reports both the upload state and the associated build's processing state. Only upload `COMPLETE` plus build `VALID` is reported as Apple acceptance. Upload `FAILED`, or build `INVALID`/`FAILED`, returns an error. Permission errors, an existing version/build, local signature errors and transfer failures also return errors. A processing timeout returns an error with the status command to resume waiting; it does not automatically start another upload.

This first upload implementation deliberately has no automatic retry, transfer resume or upload deletion. Those belong to the combined deployment milestone. A partially created upload may need operator intervention in App Store Connect; do not blindly rerun the upload with the same version/build.

## Apple acceptance and TestFlight distribution

A `VALID` build proves that Apple processed the submitted IPA. It does not establish installation on a real phone/watch or distribution to a tester. App Store Connect can still require export-compliance information before testing. The command does not guess encryption declarations. Obtain the account owner's answer before setting them.

The controlled validation order is a synthetic iOS-only build first, then a separate iOS + Watch + widget build. These builds contain no user data. The account-specific app/upload/build identifiers and their results are stored locally outside Git. Tester distribution and device installation remain separate milestones.

Both validation packages reached upload `COMPLETE`, build `VALID` and internal `READY_FOR_BETA_TESTING`. Export-compliance answers were applied only after the account owner explicitly approved them. The first Watch/widget attempt exposed missing widget device capabilities and missing arm64_32 support for watchOS 26; these were corrected before the successful second attempt. The catalogs were compiled with Apple's tools on macOS; release build, signing, archive production and upload ran on Linux. This does not establish a Linux-native replacement for Apple's asset compiler or installation on a real watch.

## API reference

The upload client uses the existing HTTP dependency and ASC JWT generator. Its small response models follow Apple's OpenAPI specification, including `sourceFileChecksums.file` and `state.state`.

- [Apple: build uploads](https://developer.apple.com/documentation/appstoreconnectapi/build-uploads)
- [Apple: reserve a build upload file](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-builduploadfiles)
- [Apple: commit a build upload file](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-builduploadfiles-_id_)
- [Apple: uploading assets](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect)
