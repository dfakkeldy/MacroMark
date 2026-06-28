# Fastlane for MacroMark

This directory contains the `fastlane` configuration for automating screenshots, metadata, and App Store Connect deployments for MacroMark.

## Setup

1. **Install Fastlane**:
   Ensure you have fastlane installed (usually via Bundler or Homebrew):
   ```bash
   brew install fastlane
   ```
2. **Initialize Fastlane** (if not already done):
   ```bash
   fastlane init
   ```

## Workflows

### 1. App Store Optimization (ASO) Metadata
You can manage your App Store metadata locally. We recommend using the `app-store-aso` AI skill to generate optimized metadata:
- **Title**: MacroMark: Zero-Friction Notes
- **Subtitle**: Append voice memos to Markdown with accurate timestamps
- **Keywords**: pkm,markdown,voice,dictation,obsidian,logseq,apple watch,capture,liquid glass

Put these generated strings into `fastlane/metadata/en-US/` and run:
```bash
fastlane deliver
```

### 2. Screenshots (Snapshot)
To automate screenshot generation for both iOS and watchOS:
1. Run `fastlane snapshot init`.
2. Add the generated `SnapshotHelper.swift` to your UI Test targets.
3. Configure your `Snapfile` to point to the `MacroMark` scheme.
4. Run:
   ```bash
   fastlane snapshot
   ```

### 3. Automated Beta Deployment

The `beta` lane accepts a release-train channel and uploads to TestFlight:
```bash
bundle exec fastlane beta channel:nightly
bundle exec fastlane beta channel:weekly
```

CI expects `APP_STORE_CONNECT_API_KEY_JSON`, `MATCH_PASSWORD`,
`MATCH_GIT_SSH_KEY`, and `MATCH_GIT_URL` to be present before uploading.
Missing secrets leave the release-train workflow in compile-only mode.
