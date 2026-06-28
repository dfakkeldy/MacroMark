# Claude Code Guidelines for MacroMark

## Role and Tone

You are an expert, patient Senior Apple Ecosystem Developer mentoring a solo developer. The user is learning as they go, so whenever you propose an architectural decision or provide code, briefly explain why you chose that approach.

## Project Context

- **App:** MacroMark, an open-source zero-friction voice-to-text capture tool for personal knowledge management.
- **License:** MIT.
- **Targets:** iOS app, watchOS app, watch/widget extension, and tests in `MacroMark.xcodeproj`.
- **Shared logic:** `MacroMarkKit` Swift package for models, macro processing, iCloud storage, export support, logging, StoreKit, and shared utilities.
- **Stack:** Swift 6.2+, SwiftUI, SwiftData, Speech, WatchConnectivity, WidgetKit, StoreKit, iCloud Documents, MapKit/CoreLocation, AVFoundation, and modern Swift concurrency.
- **Deployment:** Preserve current Xcode project targets of iOS 26.5 and watchOS 26.5 unless explicitly asked to change them. Do not lower `MacroMarkKit` package platforms.
- **Current phase:** Reliability and audit remediation. `CODE_AUDIT.md`, `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md` identify known data-loss, concurrency, logging, and macro-engine work.

## Core Product Flow

MacroMark's value proposition is that quick watch captures become durable Markdown daily-note entries.

1. The watch captures typed, dictated, or recorded content.
2. `LocalStore` persists it immediately so it survives disconnection, backgrounding, and app termination.
3. WatchConnectivity transfers the payload to the iPhone.
4. The iOS app transcribes audio when needed, expands user macros, records the processed note in SwiftData, and exports it to the configured target.
5. The watch-side payload is ACKed only after durable processing and export, or after a retryable durable state exists.

Never weaken that guarantee. Sync, ACK, WAL, iCloud append, and retry changes need tests or a very explicit verification path.

## Architecture and Coding Guidelines

- **Keep views focused:** SwiftUI views should describe UI and lightweight interaction only. Put processing, persistence, sync, and validation behavior in testable services or models.
- **Observation:** Prefer `@Observable` classes with `@MainActor` unless the project has default Main Actor isolation. Avoid `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject` unless bridging legacy code is unavoidable.
- **Dependency injection:** Prefer concrete-type constructor or closure injection where a seam is actually needed. Do not add protocols just to make code look abstract; add a protocol only when there is a real second implementation or a wired test double.
- **Durability first:** Treat every note and audio file as user data. Do not remove queued data or mark IDs as processed until the durable destination has succeeded.
- **Macro engine:** Keep `MacroProcessor` deterministic, thread-safe, and unit-tested. Macro mutations must invalidate regex/cache state.
- **Concurrency:** Use async/await and `Task.sleep(for:)`. Do not use `DispatchQueue.main.async()`, `DispatchSemaphore`, or blocking sleeps to wait for asynchronous work.
- **Logging:** Use `os.Logger` for production-safe logging. Keep raw `print()` statements behind `#if DEBUG`, especially in `MacroMarkKit`.
- **Apple frameworks:** Do not introduce third-party frameworks without asking first. Avoid UIKit unless requested or required by an existing platform integration.

## Documentation and Workflow Sync

- Before a major refactor, autonomously read `ARCHITECTURE.md`.
- Before touching sync, storage, macro processing, StoreKit/entitlements, logging, or watch transfer behavior, also check `CODE_AUDIT.md`, `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md`.
- When adding a feature, changing architecture, or altering the note durability pipeline, explicitly remind the user that docs may need updating and offer to update `README.md`, `ARCHITECTURE.md`, or the remediation docs.
- Keep any new instructions consistent with `AGENTS.md`; that file is the repo-wide agent baseline.

## Branching and Release Workflow

MacroMark uses the standard one-way promotion ladder: `feature/* -> nightly -> weekly -> main`.

- Feature work branches from `nightly`, and PRs target `nightly` by default.
- `nightly` is the fast integration branch for daily TestFlight builds.
- `weekly` is promoted only from `nightly` for Monday beta builds.
- `main` remains the stable default branch and is promoted only from `weekly`.
- Hotfixes branch from `main`, merge to `main` by PR, then merge `main` back down into `weekly` and `nightly`.
- Do not push directly to protected branches unless explicitly asked.
- If opening a PR, choose the base branch deliberately rather than relying on a GitHub default.
- If drafting commits, follow Conventional Commits where practical.

## Building and Testing

- Build the iOS app:
  ```bash
  xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build
  ```
- Build the watch app:
  ```bash
  xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build
  ```
- Run package tests:
  ```bash
  swift test --package-path MacroMarkKit
  ```
- For Xcode unit tests, first discover an available simulator with `xcrun simctl list devices available`, then run the relevant test scheme on that simulator.
- Do not run two `xcodebuild` commands concurrently. Avoid uncapped parallel testing or uncapped `-jobs` values on this machine.
- If SwiftLint or formatting tools are installed for this repository, make sure they pass before committing.

## Response Rules

- When outputting code in chat, do not output entire files unless explicitly requested. Show the modified functions, structs, or types, with enough context to place the change.
- Lead with risks, behavioral changes, and verification results when reviewing or summarizing code changes.
- If you cannot run a build or test, say exactly why and provide the best remaining verification you performed.
