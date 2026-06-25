# MacroMark PR #1 Remediation Plan

Generated 2026-06-25. Companion to `CODE_AUDIT.md`, scoped to PR #1 (`codex/dated-notes-picker`). Status reflects the stacked remediation branch `codex/dated-notes-remediation`.

Conventions:
- **§N.M** = finding in `CODE_AUDIT.md`.
- **Effort** = S (≤30 min), M (1-3 h), L (half day+).
- **Status** = Applied in this branch, Deferred, or Monitor.

---

## P0 — Reliability-Critical Fixes

| # | Finding | Fix | Effort | Status |
|---|---------|-----|--------|--------|
| P0.1 | §5.1 Future-note iCloud failures not queued | Extract shared `PendingExportEntry` / `PendingExportStore`; enqueue failed/deferred future-note exports with `requiresWatchAcknowledgement == false`. | M | Applied |
| P0.2 | §5.2 Manual iCloud export ignores note date | Export detail notes with `appendText(note.text, for: note.createdAt)` and queue failed/deferred attempts. | S | Applied |
| P0.3 | §9.1 Pending-export WAL private to app entry | Move retry serialization into `MacroMarkKit` with backward-compatible decode of existing watch entries. | M | Applied |

Exit criteria:
- Future notes saved locally but not exported are retryable by the existing app retry loop.
- Watch-originated entries still ACK only after final export delivery.
- Manual export of a future note targets that note's selected daily file.

---

## P1 — Correctness and UX Fixes

| # | Finding | Fix | Effort | Status |
|---|---------|-----|--------|--------|
| P1.1 | §3.1 Stale watch log loads | Capture `requestedDate` before the fetch and reject cancelled/superseded results before assigning UI state. | S | Applied |
| P1.2 | §8.1 Icon-only watch buttons | Convert mic/keyboard button labels to `Label` with `.labelStyle(.iconOnly)`. | S | Applied |
| P1.3 | §9.2 Raw watch `@AppStorage` key | Use `UserDefaultsKey.captureMode.rawValue`. | S | Applied |

Exit criteria:
- Spinning the watch date picker cannot publish a previous day's log under the current date.
- Watch capture controls have accessible action names.

---

## P2 — Hygiene

| # | Finding | Fix | Effort | Status |
|---|---------|-----|--------|--------|
| P2.1 | §2.1 Mutable test variable warning | Change `var settings` to `let`. | S | Applied |
| P2.2 | §2.2 Placeholder app test | Remove generated no-op test. | S | Applied |

Exit criteria:
- `swift test --package-path MacroMarkKit` emits no project warnings.
- App tests contain only behavior tests.

---

## Deferred / Monitor

| Finding | Reason |
|---------|--------|
| §3.2 / §7.1 Timeout task cancellation in `fetchDailyFile` | Low severity; the stale-result guard removes the user-visible bug. Timeout cancellation can be handled in a later connectivity cleanup without affecting PR #1 reliability. |
| §8.2 Stable Inbox toolbar items | Low severity and current behavior is understandable. Monitor after user feedback; avoid extra UI churn in this feature branch. |

---

## Verification Plan

Run the same gates as PR #1 after remediation:

1. `swift test --package-path MacroMarkKit`
2. `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build`
3. `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build`

Expected known warnings:
- AppIntents metadata extraction warnings in Xcode generic builds.

No Swift package warnings are expected after P2.1.
