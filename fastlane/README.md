fastlane documentation
----

This directory contains the `fastlane` configuration for automating screenshots,
metadata, and App Store Connect deployments for MacroMark.

Use Bundler from the repository root so CI and local lanes run the same Fastlane version:

```bash
bundle install
bundle exec fastlane ios test_auth
```

Local App Store Connect access uses a git-ignored `fastlane/api_key.json`. CI can use either `APP_STORE_CONNECT_API_KEY_JSON` or the component secrets `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_KEY`.

## Workflows

### 1. App Store Optimization Metadata

You can manage App Store metadata locally in `fastlane/metadata/en-US/`.
Kickstart/App Store Connect refresh on 2026-07-01 reports an ASO score of
89/100, with one `en-US` localization and these current keywords:
`notes, dictation, watch, obsidian, logseq, daily, journal, memo, transcribe,
vault, shortcut, inbox, quick`.

Upload metadata without a binary or screenshots with:

```bash
bundle exec fastlane ios upload_metadata
```

Run `bundle exec fastlane ios refresh_meta` before editing if App Store Connect
may contain newer metadata than the repository.

### 2. Screenshots

The repository includes a `Snapfile` and screenshot lane. Capture screenshots with:

```bash
bundle exec fastlane ios screenshots
```

Upload already-generated screenshots with:

```bash
bundle exec fastlane ios upload_screenshots
```

Use `bundle exec fastlane ios screenshot_release` to capture and upload in one run.

### 3. Release Train Deployment

The `release_train` lane accepts a release-train channel and ships it to the
expected destination:

- `nightly` uploads to internal TestFlight only.
- `weekly` uploads to external TestFlight groups.
- `appstore` uploads the main build and submits it to App Store Review.

```bash
bundle exec fastlane release_train channel:nightly
bundle exec fastlane release_train channel:weekly
bundle exec fastlane release_train channel:appstore
```

As of 2026-07-05, the scheduled GitHub Actions release workflow is intentionally
narrowed to the `nightly` internal TestFlight train. Manual dispatch also exposes
a `weekly` channel for external TestFlight attempts; it builds the current
`nightly` branch because the long-lived `weekly` branch may not contain the
latest v1 release candidate.

CI expects App Store Connect API key credentials plus `MATCH_PASSWORD`,
`MATCH_GIT_SSH_KEY`, and `MATCH_GIT_URL` to be present before uploading.
The API key can be provided either as `APP_STORE_CONNECT_API_KEY_JSON` or as
the component secrets `APP_STORE_CONNECT_API_KEY_KEY_ID`,
`APP_STORE_CONNECT_API_KEY_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_KEY`.
Missing secrets leave the release-train workflow in compile-only mode.

Nightly internal TestFlight uses `TESTFLIGHT_INTERNAL_GROUPS`, defaulting to
`Nightly`.

Weekly external TestFlight requires `TESTFLIGHT_EXTERNAL_GROUPS` as a
comma-separated list, for example:

```bash
TESTFLIGHT_EXTERNAL_GROUPS="External Testers"
```

CI release lanes call `setup_ci` before `match` so signing keys are imported into
a noninteractive temporary keychain. Without that, a headless runner can hang
during archive signing while waiting for a keychain permission dialog.

App Store submissions use manual release after approval by default. Set
`APP_STORE_AUTOMATIC_RELEASE=true` only if approved builds should release
automatically.

### 4. Current Release Blockers

- No processed TestFlight build has been verified yet.
- App Store distribution profiles must cover the iOS app, Watch app, and widget extension.
- StoreKit annual/lifetime purchase and restore flows still need local verification.
- Screenshots, privacy answers, Accessibility Nutrition Labels, and paired-device smoke testing remain pre-submission gates.
