fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app — no upload

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit tests

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload a new TestFlight beta

### ios release

```sh
[bundle exec] fastlane ios release
```

Build, upload to TestFlight, and optionally submit for App Store review

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots with snapshot

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload generated screenshots without uploading metadata or a binary

### ios screenshot_release

```sh
[bundle exec] fastlane ios screenshot_release
```

Capture and upload App Store screenshots

### ios refresh_meta

```sh
[bundle exec] fastlane ios refresh_meta
```

Download existing App Store metadata for editing locally

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload App Store metadata without uploading a binary or screenshots

### ios test_auth

```sh
[bundle exec] fastlane ios test_auth
```

Verify App Store Connect API key configuration

### ios match_dev

```sh
[bundle exec] fastlane ios match_dev
```

Refresh development certificates & provisioning profiles

### ios match_appstore

```sh
[bundle exec] fastlane ios match_appstore
```

Refresh App Store distribution certificates & provisioning profiles

### Automated Beta Deployment

The `beta` lane accepts a release-train channel and uploads to TestFlight:

```bash
bundle exec fastlane beta channel:nightly
bundle exec fastlane beta channel:weekly
```

CI expects `APP_STORE_CONNECT_API_KEY_JSON`, `MATCH_PASSWORD`,
`MATCH_GIT_SSH_KEY`, and `MATCH_GIT_URL` to be present before uploading.
Missing secrets leave the release-train workflow in compile-only mode.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
