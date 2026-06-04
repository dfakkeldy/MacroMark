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
You can create a custom lane in your `Fastfile` to build the app and deploy it to TestFlight:
```ruby
lane :beta do
  increment_build_number
  build_app(scheme: "MacroMark")
  upload_to_testflight
end
```
Then run:
```bash
fastlane beta
```
