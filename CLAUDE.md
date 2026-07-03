# Claude Code Guidelines for MacroMark

<!-- Loads the repo's AGENTS.md (modern Swift/SwiftUI rules + MacroMark specifics) alongside this file.
     Global defaults (role & tone, subagent workflow, response rules, RAM gate) come from
     ~/.claude/CLAUDE.md — do not duplicate them here. -->
@AGENTS.md

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

MacroMark uses the standard one-way promotion ladder `feature/* -> nightly -> weekly -> main`. The authoritative branch/PR rules live in **AGENTS.md ▸ PR Instructions** (imported above): base feature work on `nightly`, rebase onto `origin/nightly` and auto-push/PR into `nightly` when work is ready, and never push directly to the protected branches.

## Building and Testing

Build and test gates live in **AGENTS.md ▸ Build and Test** (imported above): the iOS and watchOS `xcodebuild` gates, `swift test --package-path MacroMarkKit`, simulator discovery via `xcrun simctl list devices available`, and the global memory-pressure RAM gate that governs build concurrency.
