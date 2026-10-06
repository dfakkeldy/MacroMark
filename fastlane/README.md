# Fastlane for MacroMark

This directory contains the `fastlane` configuration for automating screenshots,
metadata, and App Store Connect deployments for MacroMark.

## Setup

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

Each TestFlight upload creates or updates a complete `en-US` beta app
localization with the beta description, feedback email, marketing URL, and
privacy-policy URL. Keep those values in `BETA_APP_LOCALIZED_INFO` in the
`Fastfile`; App Store listing copy remains in `fastlane/metadata/en-US/`.

The scheduled GitHub Actions release workflow ships only the `nightly`
internal TestFlight train. Manual dispatch also exposes a `weekly` channel for
external TestFlight; it builds the workflow ref that was dispatched, so
dispatch it from the release-candidate branch, usually `weekly` after a
promotion. The `appstore` Fastlane path remains manual/local only.

CI expects App Store Connect API key credentials plus `MATCH_PASSWORD`,
`MATCH_GIT_SSH_KEY`, and `MATCH_GIT_URL` to be present before uploading.
The API key can be provided either as `APP_STORE_CONNECT_API_KEY_JSON` or as
the component secrets `APP_STORE_CONNECT_API_KEY_KEY_ID`,
`APP_STORE_CONNECT_API_KEY_ISSUER_ID`, and `APP_STORE_CONNECT_API_KEY_KEY`.
Missing secrets leave the release-train workflow in compile-only mode.

Nightly internal TestFlight deliberately omits Fastlane's `groups` option.
Fastlane treats any explicit group as a reason to submit the build for external
Beta App Review, even when `distribute_external` is false. Eligible builds remain
available to App Store Connect users and internal groups configured for automatic
distribution; other internal groups can add the processed build in App Store Connect.

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

### 4. Current release evidence and blockers

Re-checked: 2026-10-06. Scheduled run
[37306349729](https://github.com/dfakkeldy/MacroMark/actions/runs/37306349729)
uploaded/processed internal `1.0 (75)` from nightly `80455834`, with automation
from main `59b96a15`. This does not prove external review, installation or
App Store approval. Current nightly CI skipped app-hosted iOS tests; the
active main ship workflow does not run them.

Use [App Store readiness](../docs/APP_STORE_READINESS.md) and
[the prepared packet](../docs/APP_STORE_PACKET.md). Paywall bypass, in-app
privacy/Terms links, manifest coverage and paid-flow tests precede final
screenshots and release. Metadata/screenshot upload lanes mutate ASC, and
`appstore`/`release` upload and submit; no such lanes are authorized by a
preparation-only request. Do not read/rotate credentials to audit readiness.
