# Fastlane for MacroMark

This directory contains the `fastlane` configuration for automating screenshots,
metadata, and App Store Connect deployments for MacroMark.

## Setup

1. **Install Fastlane**:
   Ensure you have fastlane installed, usually via Bundler or Homebrew:
   ```bash
   brew install fastlane
   ```
2. **Initialize Fastlane** if needed:
   ```bash
   fastlane init
   ```

## Workflows

### 1. App Store Optimization Metadata

You can manage your App Store metadata locally. We recommend using the
`app-store-aso` AI skill to generate optimized metadata:

- **Title**: MacroMark: Zero-Friction Notes
- **Subtitle**: Append voice memos to Markdown with accurate timestamps
- **Keywords**: pkm,markdown,voice,dictation,obsidian,logseq,apple watch,capture,liquid glass

Put these generated strings into `fastlane/metadata/en-US/` and run:

```bash
fastlane deliver
```

### 2. Screenshots

To automate screenshot generation for both iOS and watchOS:

1. Run `fastlane snapshot init`.
2. Add the generated `SnapshotHelper.swift` to your UI Test targets.
3. Configure your `Snapfile` to point to the `MacroMark` scheme.
4. Run:
   ```bash
   fastlane snapshot
   ```

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

App Store submissions use manual release after approval by default. Set
`APP_STORE_AUTOMATIC_RELEASE=true` only if approved builds should release
automatically.
