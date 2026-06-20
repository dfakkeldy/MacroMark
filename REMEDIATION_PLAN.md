# MacroMark Remediation Plan

Generated 2026-06-20. Companion to `CODE_AUDIT.md` (same date). This plan maps every audit finding to a concrete remediation, ordered by severity and dependency, and groups them into batches suitable for parallel subagent execution (see `IMPLEMENTATION_PLAN.md`).

Conventions:
- **§N.M** = finding in `CODE_AUDIT.md`.
- **Effort** = S (≤30 min) / M (1–3 h) / L (½–1 day).
- **Risk** = the blast radius if the fix is wrong (data-loss / crash / UX / none).
- **Depends on** = must land after the referenced item.

---

## P0 — Data-loss & crash (do first)

These are the user's stated #1 concern (note data loss) plus the crash-class race.

| # | Finding | Fix | Effort | Risk | Depends on |
|---|---------|-----|--------|------|------------|
| P0.1 | §5.1 ACK before iCloud append confirmed | Only ACK + clear WAL after the export target succeeds. Add an "exported" WAL state; retry deferred notes on next launch. | M | data-loss | — |
| P0.2 | §5.2 iCloud append drops notes on un-materialized placeholder | Return a distinct `deferred` result from `appendText`; caller re-enqueues deferred notes with bounded retry. | M | data-loss | P0.1 |
| P0.3 | §3.1 Data race on MacroProcessor regex cache | Move cache behind `OSAllocatedUnfairLock<[String: NSRegularExpression]>` (or a small actor). | S | crash | — |
| P0.4 | §5.3 Stale regex never invalidated | Call `invalidateRegexCache()` from `deleteMacros`, `moveMacros`, `restoreDefaults`, `AddMacroView` Save, `MacroEditView` Save. | S | correctness | P0.3 |
| P0.5 | §3.2 watchOS semaphore deadlock | Drop `DispatchSemaphore` + `Task.detached`; call `Task { await processAudioFile(...) }` directly in both capture views. | S | data-loss | — |

**Exit criteria for P0:** A note captured under (a) iCloud append failure, (b) un-materialized daily file, (c) concurrent processing, and (d) editing a macro trigger all reach the daily file with correct expansion and no dropped/duplicated entries. Watch recordings always reach `LocalStore`.

---

## P1 — High-severity correctness, security, duplication

| # | Finding | Fix | Effort | Risk | Depends on |
|---|---------|-----|--------|------|------------|
| P1.1 | §3.3 Blocking `Thread.sleep` on MainActor | Make `appendText` `async`; use `Task.sleep(for:)`. Move `iCloudStorageManager` off `@MainActor`. | M | UX | P0.2 |
| P1.2 | §6.3 Unguarded `print()` ships IAP errors/paths | Replace kit `print()` with `os.Logger` (subsystem `com.macromark`); wrap the 4 iOS-app prints in `#if DEBUG`. | M | security | — |
| P1.3 | §9.1 WatchConnectivityProvider duplicated ×2 | Delete one copy; add the surviving file to both targets via Target Membership (already conditional-compiles). Move watch copy out of `Storage/`. | S | correctness | — |
| P1.4 | §9.4 Magic UserDefaults keys ×18 | Add `enum UserDefaultsKey` in MacroMarkKit; use everywhere. | S | correctness | — |
| P1.5 | §9.2 Date format duplicated ×3 | Delete `currentDateExample`/`formatWithSettings`; call `FolderSettings.format(date:)`. | S | correctness | — |
| P1.6 | §5.4 `restoreDefaults` deletes custom macros | Add `.confirmationDialog`; scope deletion to `isDefault == true`. | S | data-loss | — |
| P1.7 | §5.5 Audio transcription silently truncates | Mark `transcriptionPartial` on chunk failure; join chunks with newline; surface warning in Inbox/NoteDetail. | M | data-loss | — |

**Exit criteria for P1:** No main-thread freeze on append; release logs contain no IAP errors; one WatchConnectivityProvider; all `@AppStorage` keys compile-checked; macro edits invalidate regex; restore-defaults is confirmed and non-destructive; partial transcriptions are visible.

---

## P2 — Medium-severity cleanup, modernization, UX

| # | Finding | Fix | Effort | Risk |
|---|---------|-----|--------|------|
| P2.1 | §5.6 Export badge can be wrong | `do/try/catch` on save; `NoteDetailView.exportTo` saves context. | S |
| P2.2 | §5.7 `wrapCleanupRegex` mangles literal `*`/`_`/`~` | Apply cleanup only to macro-expanded substrings, not whole text. Add tests. | M |
| P2.3 | §5.8 `processedNoteIDs` grows unbounded | Cache in memory; cap or move to a lightweight SwiftData model. | M |
| P2.4 | §5.9 Watch ACK-lost zombie notes | Reconcile via `sendMessage` "isProcessed?" after a grace period. | M |
| P2.5 | §5.10/§5.11 Date-format escaping; LocalStore double-save | Use `Date.FormatStyle`; remove `didSet { save() }`. | S |
| P2.6 | §6.1 Keychain not syncable | Add `kSecAttrSynchronizable: true` to add+query. | S |
| P2.7 | §6.2 `simulateEntitled` TestFlight leak | Gate on `-MacroMarkSimulateEntitled` launch arg, not sandbox receipt. | S |
| P2.8 | §3.4/§3.5 Continuation timeouts (speech, location) | Add `Task.sleep` timeout via `ContinuationTimeout` pattern. | S |
| P2.9 | §4.3 Deprecated `presentTextInputController`; silent emoji drop | Migrate API; handle `[Any]`. | S |
| P2.10 | §7.2 `reprocessPendingItems` on main thread at launch | Move to `.task` on root view. | S |
| P2.11 | §7.3 `baseDirectoryURL` recomputed per call | Cache resolved URL; no side-effect-on-read. | S |
| P2.12 | §8.1 `AddMacroView` in wrong file | Extract to `Settings/AddMacroView.swift`. | S |
| P2.13 | §8.2 `Macro.notes` collected but never shown | Render in row, or remove field + Section. | S |
| P2.14 | §9.3 WAL round-trips ×4 | Extract generic `load`/`save` helpers. | S |
| P2.15 | §9.5 Security-scope access ×2 | Extract `withSecurityScope` helper. | S |
| P2.16 | §9.6 Default-macros in a View | Move to `DefaultMacros` type in MacroMarkKit. | S |
| P2.17 | §9.7 Dead symbols | Wire or remove `purchaseState`/`isLoadingProducts`/`PurchaseState`/`isUsingFallbackStorage`/`customMacroCount(_:)`. | S |

**Exit criteria for P2:** No silent error drops in UI state; no unbounded growth; no deprecated watch API; no dead state; AGENTS.md file-organization rules met.

---

## P3 — Low-severity polish

| # | Finding | Fix | Effort |
|---|---------|-----|--------|
| P3.1 | §3.6 `fetchDailyFile` timeout Task never cancelled | Capture + `cancel()` on success. | S |
| P3.2 | §3.7 `speechTask` `nonisolated(unsafe)` | Wrap in `OSAllocatedUnfairLock`. | S |
| P3.3 | §4.1 `beginBackgroundTask` cleanup duplication | Hoist `endBackgroundTask` into `defer`. | S |
| P3.4 | §4.2 Redundant speech-auth at launch | Remove the discarded launch-time request. | S |
| P3.5 | §7.4 `@Query` no fetch limit | Add `fetchLimit` / paginate. | S |
| P3.6 | §8.3 Hardcoded frame heights | Name or remove. | S |
| P3.7 | §8.4 `captureMode` raw strings | `enum CaptureMode: String` in MacroMarkKit. | S |
| P3.8 | §9.8 Delete `test.swift`, widget template files | Delete. | S |
| P3.9 | §9.10 Magic constants | Name with `private static let`. | S |
| P3.10 | Rename `MacroMark_Watch_AppApp` → `MacroMarkApp` | Rename. | S |

---

## Sequencing summary

```
P0 (data-loss + crash) ──┬─► P1 (high correctness/security/dup) ──► P2 (medium) ──► P3 (polish)
                         │
                         └─► P0 items are independent of each other except P0.2 needs P0.1's
                             "exported" WAL state, and P0.4 needs P0.3's locked cache.
```

Most P2/P3 items are independent and parallelizable; the dependency edges are noted per-row.

---

## Out of scope for remediation

- Anything listed in `CODE_AUDIT.md` §11 ("What was NOT audited").
- App Store Connect product/pricing validation.
- Localization / string catalogs.
- Instruments-based performance profiling (the §7 findings are static; a separate profiling pass can follow).
- Renaming the widget bundle kind string (`Dan.MacroMark.watchkitapp.MacroMarkWidget`) — flagged in §11 for the user to confirm the intended reverse-DNS.
