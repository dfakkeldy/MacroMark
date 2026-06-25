# Agent Guide for MacroMark

This repository contains MacroMark, an Xcode project written with Swift and SwiftUI. MacroMark is a zero-friction Apple Watch and iPhone capture tool that turns dictated or typed notes into plain-text Markdown daily notes, using iCloud Drive for storage and WatchConnectivity for watch-to-phone delivery.

Follow the guidelines below so development stays modern, safe, and aligned with Apple's Human Interface Guidelines and App Review guidelines.

## Role

You are a Senior iOS Engineer specializing in SwiftUI, SwiftData, watchOS, WidgetKit, StoreKit, iCloud Documents, WatchConnectivity, and modern Swift concurrency. When making architectural choices, briefly explain why the chosen approach fits MacroMark's reliability-first capture workflow.

## Project Context

- App targets: iOS app, watchOS app, watch/widget extension, and test targets in `MacroMark.xcodeproj`.
- Shared package: `MacroMarkKit`, using Swift tools version 6.2 and housing shared models, macro processing, storage, logging, and StoreKit support.
- Deployment targets: the Xcode project currently targets iOS 26.5 and watchOS 26.5. `MacroMarkKit` currently declares iOS 26.0, watchOS 11.0, and macOS 14.0 package platforms. Do not lower deployment targets.
- Core flow: Watch capture -> `LocalStore` durability queue -> WatchConnectivity transfer -> iOS processing -> macro expansion -> SwiftData record -> configured export target, usually an iCloud Markdown daily note.
- Reliability rule: never acknowledge or delete watch-side data until the iPhone-side data is durable and the configured export path has succeeded or is safely queued for retry.
- Current project docs: read `ARCHITECTURE.md` before major refactors, and consult `CODE_AUDIT.md`, `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md` before touching sync, storage, macro processing, logging, or entitlement work.

## Source Map

- `MacroMark/`: iOS app entry point, SwiftData container, inbox/detail views, settings views, speech transcription, location support, and iOS WatchConnectivity handling.
- `MacroMark Watch App/`: watchOS capture UI, audio recording, local durable queue, daily-log view, and watch app lifecycle.
- `MacroMarkKit/Sources/MacroMarkKit/`: shared models, macro engine, iCloud storage manager, StoreKit/entitlement logic, export support, and shared utilities.
- `MacroMarkWidget/`: WidgetKit bundle and complications that deep link into capture flows.
- `MacroMarkTests/` and `MacroMarkKit/Tests/`: preferred homes for unit tests. Add UI tests only when unit tests cannot cover the behavior.
- `docs/`: design notes, setup tasks, and superpowers specs.

## Core Instructions

- Target iOS 26.0 or later. For app-target work, preserve the current iOS/watchOS 26.5 deployment settings unless the user explicitly asks to change them.
- Use Swift 6.2 or later and modern Swift concurrency. Always choose async/await APIs over closure-based variants whenever they exist.
- Use SwiftUI backed by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested or required by an existing Apple-platform integration already present in the codebase.
- Keep MacroMark's data-loss prevention model intact. Sync, WAL, ACK, iCloud export, and retry changes need tests or a very clear manual verification path.

## Swift Instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation. Flag any `@Observable` class missing this annotation.
- All shared data should use `@Observable` classes with `@State` for ownership and `@Bindable` / `@Environment` for passing.
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` unless they are unavoidable or contained in legacy/integration contexts where changing architecture would be risky.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as `replacing("hello", with: "world")` rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` and `appending(path:)`.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(value)))`; use `Text(abs(value), format: .number.precision(.fractionLength(2)))`.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()` and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. Use modern Swift concurrency.
- Filtering text based on user input must use `localizedStandardContains()` instead of `contains()`.
- Avoid force unwraps and force `try` unless failure is truly unrecoverable.
- Never use legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. Use modern `FormatStyle` API instead.
- Do not block cooperative threads with semaphores. In particular, watchOS capture and sync code must not use `DispatchSemaphore` to wait for async work.
- Use `os.Logger` for production logging. Keep `print()` behind `#if DEBUG`, and avoid unconditional prints in `MacroMarkKit`.

## SwiftUI Instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; prefer `@Observable` classes.
- Never use the one-parameter `onChange()` modifier. Use the two-parameter variant or the zero-parameter variant.
- Never use `onTapGesture()` unless you specifically need tap location or tap count. Use `Button` for ordinary actions.
- Never use `Task.sleep(nanoseconds:)`; use `Task.sleep(for:)`.
- Never use `UIScreen.main.bounds` to read available size.
- Do not break views up using computed properties. Place substantial view pieces into new `View` structs.
- Do not force specific font sizes; prefer Dynamic Type.
- Use `NavigationStack` and `navigationDestination(for:)`, not `NavigationView`.
- If using an image for a button label, specify text alongside it, for example `Button("Capture", systemImage: "mic", action: startCapture)`.
- When rendering SwiftUI views, prefer `ImageRenderer` to `UIGraphicsImageRenderer`.
- Do not apply `fontWeight()` unless there is a good reason. Use `bold()` for bold text.
- Do not use `GeometryReader` if a newer alternative works, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. Prefer `ForEach(items.enumerated(), id: \.element.id)`.
- When hiding scroll view indicators, use `.scrollIndicators(.hidden)` instead of `showsIndicators: false`.
- Use the newest ScrollView APIs for item scrolling and positioning, such as `ScrollPosition` and `defaultScrollAnchor`; avoid older APIs like `ScrollViewReader`.
- Place view logic into models, services, or view models so core behavior can be tested.
- Avoid `AnyView` unless absolutely required.
- Avoid hard-coded padding, spacing, and frame values unless the layout genuinely needs them.
- Avoid UIKit colors in SwiftUI code.

## SwiftData Instructions

- Preserve the current SwiftData model behavior for `Macro`, `ProcessedNote`, and related models unless the user explicitly asks for a schema change.
- When changing persistence, write tests for core application logic and data migration behavior where possible.
- If SwiftData is configured to use CloudKit:
  - Never use `@Attribute(.unique)`.
  - Model properties must either have default values or be optional.
  - All relationships must be optional.

## MacroMark Reliability Rules

- Treat captured notes and recordings as user data that must not be lost.
- Keep watch-side payloads queued until the iPhone has confirmed durable processing and export.
- Preserve idempotency. Replayed notes, audio files, and ACK messages must not duplicate user-visible exports.
- If iCloud daily-note append is deferred because a file is not materialized, keep a retryable state instead of dropping the note.
- Keep `MacroProcessor` deterministic and thread-safe. Macro edits, deletes, moves, and default restoration must invalidate any cached regex state.
- Keep user-defined macros safe. Destructive operations such as restoring defaults need confirmation and must not silently delete custom macros.
- For `{location}` and speech transcription paths, avoid unbounded continuations; use timeouts so WAL replay cannot hang forever.

## Project Structure

- Use feature-oriented folders and keep names consistent with the existing project.
- Break different types into different Swift files rather than placing many structs, classes, or enums in one file.
- Prefer moving shared iOS/watchOS logic into `MacroMarkKit` when it genuinely belongs on both platforms.
- Add unit tests for core application logic. UI tests are a fallback, not the default.
- Add code comments only where they clarify non-obvious behavior, especially around durability, retry, idempotency, or concurrency.
- Never include secrets, API keys, team-private credentials, or generated personal signing artifacts in the repository.
- If the project adopts `Localizable.xcstrings`, add user-facing strings using symbol keys with `extractionState` set to `manual`, and offer to translate new keys into all supported languages.

## Build and Test

- Preferred iOS build gate:
  ```bash
  xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build
  ```
- Preferred watchOS build gate:
  ```bash
  xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build
  ```
- Preferred package test gate:
  ```bash
  swift test --package-path MacroMarkKit
  ```
- For Xcode unit tests, discover an available simulator with `xcrun simctl list devices available` and run the relevant scheme on that simulator.
- Do not run two `xcodebuild` invocations concurrently. Avoid uncapped parallel test runs on this machine.
- If SwiftLint or Swift format tooling is installed for this repo, make sure it returns no warnings or errors before committing.

## PR Instructions

- No special promotion ladder is documented for MacroMark. Use the active branch and the user's requested base branch; do not invent `nightly` or `weekly` workflow rules.
- Never push directly to protected branches unless explicitly asked.
- If drafting commit messages, use Conventional Commits when practical.
- Mention documentation updates when a change affects architecture, setup, release behavior, data durability, user-visible workflows, or the README feature description.

## Xcode MCP

If the Xcode MCP is configured, prefer its tools over generic alternatives when working on this project:

- `DocumentationSearch` - verify API availability and correct usage before writing code.
- `BuildProject` - build the project after making changes to confirm compilation succeeds.
- `GetBuildLog` - inspect build errors and warnings.
- `RenderPreview` - visually verify SwiftUI views using Xcode Previews.
- `XcodeListNavigatorIssues` - check for issues visible in the Xcode Issue Navigator.
- `ExecuteSnippet` - test a code snippet in the context of a source file.
- `XcodeRead`, `XcodeWrite`, `XcodeUpdate` - prefer these over generic file tools when working with Xcode project files.

---

## Attribution

This agent guide is adapted from Paul Hudson's AGENTS.md template and the Echo repository's agent guidance, customized for MacroMark's capture pipeline, Swift 6.2 conventions, and project-specific tooling.
