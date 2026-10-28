# MacroMark Remediation Plan

Generated 2026-06-20. Companion to `docs/audits/CODE_AUDIT.md` (same date). This plan maps every audit finding to a concrete remediation, ordered by severity and dependency, and groups them into batches suitable for parallel subagent execution (see `docs/plans/IMPLEMENTATION_PLAN.md`).

> Status update, 2026-07-02: this is a historical audit-remediation ledger. The
> active release reconciliation brings together later v1 product/reliability work
> from `origin/nightly` and release automation fixes from `origin/main`. Read `docs/V1_ROADMAP.md` and `docs/APP_STORE_READINESS.md`
> before treating any row below as still open.

## Status as of 2026-10-24

Re-checked against `nightly` at `3b0fe40`. Version 1.0 is live on the App
Store (released 2026-10-23). Rows are marked from the code only; they are not
device evidence. Later bug-hunt findings MM-051 to MM-058 are open GitHub
issues [#79–#86](https://github.com/dfakkeldy/MacroMark/issues?q=is%3Aissue+is%3Aopen+MM-05)
and are not tracked here.

| Status | Items | Code evidence |
| --- | --- | --- |
| Done | P0.1, P0.2 | ACK and WAL clearing only after `.appended` / `.savedInInbox` (`MacroMark/MacroMarkApp.swift:594–615`); `AppendResult.deferred` (`iCloudStorageManager.swift:13`) keeps the WAL and a pending-export record |
| Done | P0.3, P0.5, P1.1 | Already verified 2026-06-25 (see note below) |
| Done | P0.4 | `invalidateRegexCache()` called from delete, move, restore, add and edit (`MacroManagerView.swift:267,279,350`, `AddMacroView.swift:72`, `MacroEditView.swift:112`) |
| Done | P1.2 | No `print()` in MacroMarkKit (uses `os.Logger`, `Support/Logger.swift`); app and watch `print()` calls are inside `#if DEBUG` |
| Done | P1.3 | Watch `Storage/WatchConnectivityProvider.swift` is a symlink to `MacroMark/Shared/WatchConnectivityProvider.swift` |
| Done | P1.4 | `MacroMarkKit/Sources/MacroMarkKit/Support/UserDefaultsKey.swift` |
| Done | P1.5 | `formatWithSettings` removed; `FolderSettingsView.currentDateExample` calls `FolderSettings.format(date:)` |
| Done | P1.6 | Confirmation dialog (`MacroManagerView.swift:244`); only `isDefault` macros are replaced (`:341–351`) |
| Done | P1.7 | `hadPartialFailure` (`AudioTranscriber.swift:19`) sets `transcriptionPartial`, shown in `InboxView.swift:110` and `NoteDetailView.swift:10` |
| Done | P2.3 | Processed-ID set capped (`ProcessedNoteIDStore.swift:15–20`) |
| Done | P2.4 | Watch queries the phone after a 24 h reconciliation interval (`LocalStore.swift:53,114–123,238–252`); audio is re-sent until ACK ([#145](https://github.com/dfakkeldy/MacroMark/pull/145)) |
| Done | P2.6 | `kSecAttrSynchronizable` on the lifetime flag (`EntitlementManager.swift:96–126`) |
| Done | P2.7 | Device builds use the `-MacroMarkSimulateEntitled` launch argument; simulators still auto-entitle (`EntitlementManager.swift:20–26`) |
| Done | P2.8 | `ContinuationTimeout` in MacroMarkKit, used by `AudioTranscriber.swift:24` and `LocationManager.swift:13` |
| Done | P2.10 | Reprocessing runs from the scene `.task` (`MacroMarkApp.swift:228–235,1059`) |
| Done | P2.12, P2.13 | `Settings/AddMacroView.swift`; notes shown in the macro row (`MacroManagerView.swift:149–150`) |
| Done | P2.17 | `purchaseState`, `isLoadingProducts` and `PurchaseState` removed; `customMacroCount` and `isUsingFallbackStorage` are used |
| Done | P3.1, P3.2, P3.3, P3.4 | Daily-log page and chunk fetches cancel their timeout tasks (`WatchConnectivityProvider.swift:568–646`); speech task behind `OSAllocatedUnfairLock`; `endBackgroundTask` in a `defer` (`MacroMarkApp.swift:370–376`); no launch-time speech request in `MacroMarkApp.swift` |
| Done | P3.7, P3.8, P3.10 | `Models/CaptureMode.swift`; `test.swift` and widget template files gone; watch app type is `MacroMarkWatchApp` |
| Partly done | P2.9 | Non-string input handled (`SystemCaptureView.extractedText`), but the deprecated `WKExtension…presentTextInputController` is still used (`SystemCaptureView.swift:40`); see MM-056 / [#84](https://github.com/dfakkeldy/MacroMark/issues/84) |
| Partly done | P3.5 | `fetchLimit` on some descriptors (`InboxView.swift:179`, `MacroManagerView.swift:336`); not every `@Query` |
| Open | P2.11 | Base directory is still resolved on each append (`iCloudStorageManager.swift:47–71`) |
| Open | P2.16 | Defaults still live in a view (`MacroManagerView.swift:285–318`) |
| Not re-checked | P2.1, P2.2, P2.5, P2.14, P2.15, P3.6, P3.9 | Related code changed (`NoteDetailView` saves, wrapping placeholders in `MacroProcessor`, no `LocalStore` `didSet`), but these were not re-verified line by line |

Conventions:
- **§N.M** = finding in `docs/audits/CODE_AUDIT.md`.
- **Effort** = S (≤30 min) / M (1–3 h) / L (½–1 day).
- **Risk** = the blast radius if the fix is wrong (data-loss / crash / UX / none).
- **Depends on** = must land after the referenced item.

---

> **Swift 6.2 migration status (2026-06-25):** P0.3 (§3.1 regex-cache race) and P0.5 (§3.2 watch semaphore deadlock) were verified already complete in the code, as was P1.1 (§3.3 `Thread.sleep` on MainActor). The Swift 6 language-mode migration additionally fixed a **critical `WatchConnectivityProvider` launch crash** (`@MainActor` WCSession delegate invoked off-main), introduced a `Sendable` `MacroRule` so `MacroProcessor` no longer takes SwiftData models off-actor, and hardened `LocationManager` / `AudioTranscriber`. The P0 data-loss items **P0.1 (§5.1) and P0.2 (§5.2) remain open.** See `docs/audits/CODE_AUDIT.md` → "Swift 6.2 Migration Update".

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

- Anything listed in `docs/audits/CODE_AUDIT.md` §11 ("What was NOT audited").
- App Store Connect product/pricing validation.
- Localization / string catalogs.
- Instruments-based performance profiling (the §7 findings are static; a separate profiling pass can follow).
- Renaming the widget bundle kind string (`com.danfakkeldy.macromark.watchkitapp.MacroMarkWidget`) — flagged in §11 for the user to confirm the intended reverse-DNS.
