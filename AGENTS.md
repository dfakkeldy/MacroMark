# Agent Guide for MacroMark

MacroMark is a zero-friction Apple Watch and iPhone capture tool. Dictated or
typed captures become Markdown daily notes through a durability-first pipeline.

## Project context

- App targets live in `MacroMark.xcodeproj`: iOS, watchOS, widget/complication,
  and tests.
- `MacroMarkKit` contains shared models, macro processing, storage, logging,
  export, and StoreKit support.
- Preserve the current Xcode deployment settings (iOS 26.5 and watchOS 26.5)
  unless the user asks to change them. The package currently declares iOS 26,
  watchOS 11, and macOS 14.
- Read `ARCHITECTURE.md` for major architectural changes. Consult
  `CODE_AUDIT.md`, `REMEDIATION_PLAN.md`, and `IMPLEMENTATION_PLAN.md` only when
  the task touches the audited reliability areas they describe.

## Reliability invariants

- Never acknowledge or delete a watch-side capture until the iPhone has durably
  processed it and export has succeeded or is safely queued for retry.
- Preserve idempotency across replayed notes, audio files, transfers, and ACKs.
- If an iCloud file is unavailable, retain a retryable state instead of dropping
  the capture.
- Keep `MacroProcessor` deterministic and thread-safe. Macro mutations must
  invalidate cached regex state.
- Treat restoring defaults and other destructive macro operations as confirmed
  user actions; never silently remove custom macros.
- Bound location and transcription continuations so WAL replay cannot hang.

## Implementation guidance

- Use the project's Swift 6 concurrency and observation settings. Prefer
  structured concurrency, avoid blocking cooperative threads, and keep
  production logging in `os.Logger`.
- Follow existing architecture in the touched subsystem. Prefer concrete
  constructor or closure injection; add protocols only for real alternative
  implementations or wired test doubles.
- Keep SwiftUI views focused on UI and lightweight interaction. Put durability,
  processing, persistence, and sync behavior in testable services or models.
- Preserve the existing SwiftData model unless schema work is explicitly in
  scope. Respect CloudKit model constraints wherever CloudKit is configured.
- Prefer current APIs available at the deployment target, but do not broaden a
  focused task into nearby modernization.
- Do not introduce a third-party framework without user authorization.
- Never commit secrets, credentials, or personal signing artifacts.
- Update documentation only when the change makes existing architecture, setup,
  durability, release, or user-workflow documentation inaccurate.

## Source map

- `MacroMark/`: iOS app, views, transcription, location, and phone-side transfer.
- `MacroMark Watch App/`: capture UI, recordings, local queue, and watch lifecycle.
- `MacroMarkKit/Sources/MacroMarkKit/`: shared processing and storage.
- `MacroMarkWidget/`: widgets and complications.
- `MacroMarkTests/` and `MacroMarkKit/Tests/`: preferred unit-test locations.

## Verification

Use the narrowest relevant gate:

```bash
xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build
swift test --package-path MacroMarkKit
```

Durability, retry, ACK, export, and macro-engine changes need focused tests or a
clearly reported manual verification path. Instruction-only edits do not require
an app build.

## Repository workflow

- MacroMark uses `feature/* -> nightly -> weekly -> main`.
- Normal feature work branches from and opens a PR to `nightly`. Promotions are
  separate PRs and should be opened only when requested.
- Hotfixes branch from and PR to `main`, then flow back to `weekly` and `nightly`.
- Never push directly to protected branches.
- Inspect branch, upstream, and working tree before editing; preserve unrelated
  changes and user-owned history.
- Use coherent Conventional Commits. Publish when the task type and user request
  call for it; do not auto-rebase or force-push as a standing rule.
- Report local verification and hosted CI as separate states.
