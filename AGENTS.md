# MacroMark

MIT-licensed Apple Watch and iPhone capture tool. Dictated or typed captures
become Markdown daily notes. The watch queues each capture durably in
`LocalStore` and sends it over WatchConnectivity; the phone transcribes,
expands macros, records, and exports it.

## Layout

- `MacroMark/`: iOS app. `MacroMark Watch App/`: watch capture and queue.
- `MacroMarkKit/`: shared models, macro processing, storage, export, StoreKit.
- `MacroMarkWidget/`: widgets and complications.
- Tests: `MacroMarkTests/` and `MacroMarkKit/Tests/`.
- `ARCHITECTURE.md` describes the design. `CODE_AUDIT.md`,
  `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md` cover known reliability
  work.

## Commands

```bash
swift test --package-path MacroMarkKit
xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -destination 'generic/platform=iOS' build
xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -destination 'generic/platform=watchOS' build
```

## Reliability rules

- Never ACK or delete a watch capture until the phone has durably processed it
  and export has succeeded or is safely queued for retry.
- Replayed notes, audio files, transfers, and ACKs must be idempotent.
- If an iCloud file is unavailable, keep a retryable state; never drop the
  capture.
- `MacroProcessor` stays deterministic and thread-safe; macro edits must
  invalidate its cached regexes.
- Never silently remove custom macros; restoring defaults is a confirmed user
  action.
- Location and transcription continuations must be bounded so WAL replay
  cannot hang.
- Changes to durability, retry, ACK, export, or the macro engine need focused
  tests.

## Conventions

- Use concrete types with constructor or closure injection; add a protocol only
  for a second real implementation. Log with `os.Logger`.
- Leave the SwiftData schema alone unless the task is about it.
- Ask before adding a third-party dependency.

## Branches

`feature/*` → `nightly` → `weekly` → `main`. Feature PRs target `nightly`.
Hotfixes branch from `main` and are merged back down. Open promotion PRs only
when asked.
