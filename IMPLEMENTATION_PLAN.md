# MacroMark Implementation Plan

Generated 2026-06-20. Companion to `CODE_AUDIT.md` and `REMEDIATION_PLAN.md` (same date). This document defines **self-contained batches** that can be dispatched to parallel coding subagents. Each batch lists the exact files to touch, the exact change, the acceptance test, and the build command.

> Status update, 2026-07-02: this file is a historical audit-remediation execution plan.
> Many P0/P1/P2 items landed later on `nightly`; release automation fixes landed on
> `main` and are being reconciled back toward `nightly`. Use `docs/V1_ROADMAP.md`, `docs/APP_STORE_READINESS.md`, and
> `docs/BRANCH_WORKTREE_CLEANUP.md` for the current release state before dispatching
> any remaining remediation batches from this older snapshot.

All batches assume:
- Working dir: `/Users/dfakkeldy/Developer/MacroMark`
- AGENTS.md rules apply (Swift 6.2+, iOS 26 target, `@Observable` + `@MainActor`, no `DispatchQueue`/`Task.sleep(nanoseconds:)`/`ObservableObject`/C-style formatters, `foregroundStyle`/`clipShape(.rect(cornerRadius:))`, etc.).
- Build gate after every batch:
  ```
  xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | tail -5
  xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build 2>&1 | tail -5
  ```
  Both must print `** BUILD SUCCEEDED **` with no new Swift warnings.
- No third-party dependencies. No new frameworks without asking.
- Commit one batch per commit with message `fix(audit): <batch id> <one-line>` (only when the user asks to commit).

---

## Batch ordering & parallelism

```
Batch 1 (P0 — parallel-safe) ──► Batch 2 (P1 — parallel-safe) ──► Batch 3 (P2 — parallel-safe) ──► Batch 4 (P3 — parallel-safe)
```

Within a batch, sub-batches (1a, 1b, …) are independent and may run concurrently. **Cross-batch** dependencies are noted explicitly (e.g., "waits for 1a").

---

# BATCH 1 — P0: data-loss & crash (run sub-batches in parallel)

## Batch 1a — End-to-end ACK: only ACK after export succeeds (§5.1, §5.2)
**Depends on:** nothing. **Blocks:** 1e (the WAL-state refactor touches the same code).
**Files:**
- `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift` — change `appendText(_:for:) -> Bool` to return an enum: `enum AppendResult { case appended, deferred, failed }`. The `deferred` case is the existing un-materialized-placeholder branch (line 111-115); `failed` is the write-error branch.
- `MacroMark/MacroMarkApp.swift` — in `processAndExport` (lines 399-459):
  - Move `addProcessedNoteID` / `removePendingAudio`/`removePendingProcessing` / ACK to **after** the export target succeeds.
  - For `.iCloud`: ACK only on `.appended`. On `.deferred`, leave the WAL entry in place AND add a `pendingExport` flag to the `PendingNote`/`PendingAudio` WAL records so a background retry pass can re-attempt. On `.failed`, also leave WAL entry.
  - Add a `retryDeferredExports()` method that iterates the WAL for entries flagged `pendingExport`, re-runs the export, and is invoked from `reprocessPendingItems` and on a timer (e.g., every 60s while the app is foregrounded).
  - Keep the in-memory-store ACK suppression (`usingInMemoryStore`) intact.
**Acceptance:** A unit/integration test (in `MacroMarkTests/` or `MacroMarkKit/Tests/`) that simulates `appendText` returning `.deferred` and asserts: (a) no ACK was sent, (b) the WAL entry remains, (c) `processedNoteIDs` does not contain the id, (d) a subsequent successful append ACKs and clears the WAL. Add a test that `.appended` ACKs exactly once.
**Build:** iOS scheme must compile and tests pass.

## Batch 1b — Lock the MacroProcessor regex cache (§3.1)
**Depends on:** nothing.
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift`.
**Change:** Replace `private static nonisolated(unsafe) var regexCache: [String: NSRegularExpression] = [:]` with `private static let regexCache = OSAllocatedUnfairLock<[String: NSRegularExpression]>(initialState: [:])` (requires `import os`). Read/write via `regexCache.withLock { ... }`. `invalidateRegexCache()` becomes `regexCache.withLock { $0.removeAll() }`. Keep `process(...)` non-isolated (the lock makes it safe). `NSRegularExpression` itself is thread-safe so no other change needed.
**Acceptance:** A test in `MacroMarkKit/Tests/` that runs `process(...)` concurrently from many Tasks and asserts no crash + identical output. Build clean.
**Build:** both schemes.

## Batch 1c — Wire regex-cache invalidation (§5.3)
**Depends on:** 1b (the method signature is stable but the lock lands there).
**Files:** `MacroMark/Settings/MacroManagerView.swift` (call `MacroProcessor.invalidateRegexCache()` in `deleteMacros` line 204, `moveMacros` line 210, `restoreDefaults` line 265), `MacroMark/Settings/MacroEditView.swift` (Save action ~line 69-77), and the `AddMacroView` Save action in `MacroManagerView.swift` (~line 310-315).
**Change:** One line — `MacroProcessor.invalidateRegexCache()` — after each mutation, before/after `modelContext.save()`.
**Acceptance:** Add a test: insert a Macro(trigger:"Bold"), process text "Bold test" → "** test"; edit trigger to "Strong"; process "Bold test Strong" → "Bold test **" (Bold no longer matches, Strong does). Requires the cache to be invalidated.
**Build:** iOS scheme.

## Batch 1d — Remove watchOS semaphore deadlock (§3.2)
**Depends on:** nothing.
**Files:** `MacroMark Watch App/Capture/InstantCaptureView.swift` (lines 57-69) and `MacroMark Watch App/Capture/SystemCaptureView.swift` (lines 31-43).
**Change:** Replace the `Task.detached { performExpiringActivity { ... DispatchSemaphore ... } }` with a plain `Task { await Self.processAudioFile(fileURL: fileURL, timestamp: timestamp) }` (or `Task { @MainActor in ... }` since the body already hops to MainActor). Remove the `DispatchSemaphore` import/use entirely. Keep the `dismiss()` call before spawning the Task so the UI returns immediately.
**Acceptance:** The watch scheme compiles; `LocalStore.shared.enqueueAudio` is still reached. Manual verify on simulator if possible.
**Build:** watchOS scheme.

## Batch 1e — (after 1a) Make appendText async + move iCloudStorageManager off MainActor (§3.3)
**Depends on:** 1a (the `AppendResult` enum and caller changes land first).
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift`.
**Change:**
- Remove `@MainActor` from the class. Keep `@Observable` semantics for `isUsingFallbackStorage` by making it `@MainActor`-isolated only where published — or convert to an `actor` if cleaner. Simplest: keep it a plain `final class`, mark `appendText`/`readText` `nonisolated`, and have them hop internally as needed.
- Make `appendText` `async` (returns `AppendResult` from 1a). Replace the `Thread.sleep(forTimeInterval:)` loop in `ensureDownloaded` (lines 151-154) with `try? await Task.sleep(for: .milliseconds(100))` and make `ensureDownloaded` `async`.
- Update callers: `MacroMarkApp.processAndExport` (already `@MainActor`, now `await`s), `NoteDetailView.exportToICloud` (wrap in `Task` — already is).
**Acceptance:** No `Thread.sleep` remains. A test that calls `appendText` against an un-materialized placeholder mock asserts it does not block the calling thread.
**Build:** both schemes.

---

# BATCH 2 — P1: high correctness / security / duplication (run in parallel)

## Batch 2a — Replace print() with os.Logger; gate app prints (§6.3)
**Files:**
- `MacroMarkKit/Sources/MacroMarkKit/` — create `Support/Logger.swift` with `extension Logger { static let subsystem = "com.macromark" }` and convenience loggers per module (e.g., `static let storage = Logger(subsystem: subsystem, category: "storage")`, `store`, `engine`). Replace all 9 kit `print()` calls (`StoreManager.swift:39,65,77,94`; `iCloudStorageManager.swift:109,115,121,126,180`; `MacroProcessor.swift:45,157`) with the appropriate `Logger` at the right level (`.error`/`.info`).
- `MacroMark/` app target — wrap the 4 ungated prints in `#if DEBUG`: `MacroMarkApp.swift:53`, `MacroManagerView.swift:193`, `LocationManager.swift:63`, `AudioTranscriber.swift:55`.
- `MacroMark Watch App/` — wrap the 7 prints in `#if DEBUG`: `AudioRecorder.swift:19,52`; `LocalStore.swift:111,160,170,183`.
**Acceptance:** `grep -rn "print(" MacroMarkKit MacroMark "MacroMark Watch App" MacroMarkWidget` returns only prints inside `#if DEBUG` blocks (or none in MacroMarkKit). Build clean.
**Build:** both schemes.

## Batch 2b — Deduplicate WatchConnectivityProvider (§9.1)
**Files:** `MacroMark/Shared/WatchConnectivityProvider.swift`, `MacroMark Watch App/Storage/WatchConnectivityProvider.swift`, and the Xcode project (`MacroMark.xcodeproj/project.pbxproj`).
**Change:** Keep the iOS copy as the single source. Add it to the watch target's Compile Sources phase (it already uses `#if os(iOS)`/`#if os(watchOS)`). Delete `MacroMark Watch App/Storage/WatchConnectivityProvider.swift`. **The pbxproj edit is the risky part** — use the Xcode MCP `XcodeUpdate`/`XcodeRead` tools if available; otherwise edit `project.pbxproj` carefully: remove the watch file's `PBXFileReference`/`PBXBuildFile`/group entries, and add the iOS file's path to the watch target's `Sources` `PBXSourcesBuildPhase`.
**Acceptance:** `diff` confirms one file. Both schemes build (the watch target now compiles the shared file). No "duplicate symbol" or "file not found" errors.
**Build:** both schemes. **This batch must be verified by a clean build of both schemes.**

> **STATUS (2026-06-20): DEFERRED.** The project uses Xcode 16+ `PBXFileSystemSynchronizedRootGroup` (file-system-synchronized groups), so source files are auto-included per-target-folder rather than individually listed. Cross-target file sharing via the synchronized-group `membershipExceptions` mechanism only supports *excluding* files in a group's own tree — it cannot pull a file from `MacroMark/Shared/` into the watch target. The robust dedup therefore requires moving the shared file into MacroMarkKit, which in turn requires also moving the watch-only `LocalStore` + `CapturedNote` types (the WCProvider's `#if os(watchOS)` branches call `LocalStore.shared` directly). That is a P2-scale refactor (pairs with §9.6). Deferred rather than risk corrupting `project.pbxproj` (which would block every build) for a P1 item. The ACK protocol the file implements is untouched by this deferral and remains correct on both targets.

## Batch 2c — Centralize UserDefaults keys (§9.4)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Support/UserDefaultsKey.swift` (new), plus every file currently using a raw string: `MacroManagerView.swift`, `ContentView.swift`, `WatchConnectivityProvider.swift`, `FolderSettingsView.swift`, `iCloudStorageManager.swift`, `MacroMarkApp.swift`, `MacroMark Watch App/Storage/LocalStore.swift`.
**Change:** Define `public enum UserDefaultsKey: String { case captureMode = "captureMode"; case folderSettings = "folderSettings"; case customSaveBookmark = "customSaveBookmark"; case autoExportEnabled = "autoExportEnabled"; case defaultExportTarget = "defaultExportTarget"; case processedNoteIDs = "MacroMark_ProcessedNoteIDs"; case pendingProcessing = "MacroMark_PendingProcessing"; case pendingAudioIn = "MacroMark_PendingAudioIn"; case pendingNotes = "MacroMark_PendingNotes"; case queuedNoteIDs = "MacroMark_QueuedNoteIDs"; case pendingAudio = "MacroMark_PendingAudio"; case queuedAudioIDs = "MacroMark_QueuedAudioIDs" }`. Replace `@AppStorage("captureMode")` → `@AppStorage(UserDefaultsKey.captureMode.rawValue)`, and `UserDefaults.standard.xxx(forKey: "literal")` → `UserDefaultsKey.literal.rawValue`. Note: `@AppStorage` needs a `String` so use `.rawValue`.
**Acceptance:** `grep -rn 'forKey: "' MacroMark* ` and `@AppStorage("` show only `UserDefaultsKey.<case>.rawValue`. Existing behavior unchanged (key strings identical). Build clean.
**Build:** both schemes.

## Batch 2d — Deduplicate date formatting (§9.2)
**Depends on:** nothing (but coordinate with 2c for the `folderSettings` key).
**Files:** `MacroMark/Settings/FolderSettingsView.swift` (delete `currentDateExample` lines 91-105 and `formatWithSettings` lines 107-121; call `settings.format(date: Date())` at the call sites), `MacroMarkKit/Sources/MacroMarkKit/Models/FolderSettings.swift` (keep as single source).
**Change:** Find the two view properties' usages and replace with `folderSettings.format(date: Date())`. If the `"Notes/"` prefix is needed at a call site, build the string there.
**Acceptance:** `grep -rn 'replacing("yyyy"' MacroMark` returns only `FolderSettings.swift`. The settings preview shows the same date format the storage layer will produce. Build clean.
**Build:** iOS scheme.

## Batch 2e — restoreDefaults confirmation + scope (§5.4)
**Files:** `MacroMark/Settings/MacroManagerView.swift`.
**Change:** Add a `@State private var showingRestoreConfirmation = false`. Attach `.confirmationDialog("Restore defaults? Your custom macros will be kept.", isPresented: $showingRestoreConfirmation) { Button("Restore Defaults", role: .destructive) { restoreDefaults() } }` to the List/NavigationStack. Change `restoreDefaults()` (line 265-273) to delete only `macro.isDefault == true` macros before inserting defaults (preserving custom ones). Wire the button (line 143-145) to set `showingRestoreConfirmation = true` instead of calling `restoreDefaults()` directly.
**Acceptance:** Tapping "Restore Default Macros" shows a confirmation dialog; custom macros survive the restore. Build clean.
**Build:** iOS scheme.

## Batch 2f — Surface partial transcription (§5.5)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Models/ProcessedNote.swift` (add `var transcriptionPartial: Bool = false`), `MacroMark/Engine/AudioTranscriber.swift` (return a struct/tuple with `text` + `hadChunkFailure` instead of just `String` — or throw a `partialResult` error; coordinate the API), `MacroMark/MacroMarkApp.swift` (`processAudio` path sets `note.transcriptionPartial` when the transcriber reports chunk failures), `MacroMark/Views/InboxView.swift` and `NoteDetailView.swift` (show a small warning icon/label when `note.transcriptionPartial`).
**Change:** Join chunks with `"\n"` instead of `" "` (line 50). Track `hadChunkFailure` and propagate.
**Acceptance:** A test that feeds a transcriber mock where one chunk throws asserts the returned result flags partial and the note is marked. Inbox shows a warning badge.
**Build:** iOS scheme.

---

# BATCH 3 — P2: medium cleanup / modernization / UX (run in parallel; coordinate shared files)

> **File-conflict note:** Batches 3a, 3c, 3h, 3j all touch `MacroMarkApp.swift`; 3e and 3f both touch `EntitlementManager.swift`; 3m and 3n both touch `MacroManagerView.swift`. Run conflicting sub-batches **sequentially**, or merge them into one subagent task. Non-conflicting sub-batches run in parallel.

## Batch 3a — Export badge correctness (§5.6)
**Files:** `MacroMark/MacroMarkApp.swift` (`processAndExport` save at 441-458), `MacroMark/Views/NoteDetailView.swift` (`exportTo` at 44-53).
**Change:** Replace `try? context.save()` with `do { try context.save() } catch { logger.ios.error("...") }` (use Logger from 2a). In `NoteDetailView.exportTo`, add `try? modelContext.save()` after mutating `note` inside the completion (or convert to the async `UIApplication.shared.open` and save after).
**Acceptance:** Badge persists across app restarts. Build clean.

## Batch 3b — Limit wrapCleanupRegex to macro output (§5.7)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift`.
**Change:** Instead of running `wrapCleanupRegex` over the whole `processedText` (line 121-130), track the substrings produced by macro expansion and run cleanup only on those. Simplest correct approach: build the result in two passes — apply macros to a working copy, run cleanup on that, then concatenate with non-macro text. Add tests for `"3 * 4 * 5"`, code snippets, and `"**bold**"`.
**Acceptance:** `process(text: "3 * 4 * 5", macros: [])` returns `"3 * 4 * 5"` unchanged; `process(text: "Bold test", macros: [Bold→**])` still collapses correctly.

## Batch 3c — Bound processedNoteIDs growth (§5.8)
**Files:** `MacroMark/MacroMarkApp.swift`.
**Change:** Cache `processedNoteIDs` in an in-memory `@MainActor private static var` loaded once at launch. Cap to an LRU window of e.g. 5000 entries (drop oldest when exceeded). Write through on `addProcessedNoteID`.
**Acceptance:** A test that adds 10k IDs asserts the stored array never exceeds the cap and lookup stays O(1).

## Batch 3d — Watch ACK zombie reconciliation (§5.9)
**Files:** `MacroMark Watch App/Storage/LocalStore.swift`, `MacroMark Watch App/Storage/WatchConnectivityProvider.swift` (after 2b dedup — single file).
**Change:** Add a `lastQueuedAt: [UUID: Date]` map persisted alongside `queuedNoteIDs`. On `syncPendingNotes`, for any note queued > 24h ago, send a `sendMessage(["queryProcessed": id.uuidString])` reconciliation request. The iOS side (`WatchConnectivityProvider.didReceiveMessage`) already answers messages — extend its reply to include "processed" lookup against `processedNoteIDs`. On confirmed-processed reply, `removeNote(withId:)`.
**Acceptance:** Unit test on watch side: a note queued 25h ago triggers a reconciliation message; a "processed" reply removes it; a "not processed" reply re-queues (`markNoteUnqueued`).

## Batch 3e — Keychain synchronizable (§6.1)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift`.
**Change:** Add `kSecAttrSynchronizable as String: kCFBooleanTrue as Any` to both the `addQuery` (line 109-114) and the `query` (line 120-125). **Note:** changing this attribute means existing local-only items won't be found by the new query — add a one-time migration: on `checkKeychainFlag` miss, also query without `kSecAttrSynchronizable`; if found, re-persist with the flag and delete the old.
**Acceptance:** A fresh install on a second device (same iCloud account) sees the lifetime flag after StoreKit sync. Test the migration path with a unit test that seeds a non-synchronized item and asserts it's found and migrated.

## Batch 3f — Gate simulateEntitled on launch arg (§6.2)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift`.
**Change:** Change `simulateEntitled` (lines 18-27) to: `#if targetEnvironment(simulator) { return true } #else { return ProcessInfo.processInfo.arguments.contains("-MacroMarkSimulateEntitled") }`. Remove the sandbox-receipt/profile heuristic. Update the doc comment to reflect that the flag is now opt-in via launch argument.
**Acceptance:** TestFlight builds (no launch arg) no longer auto-unlock. A unit test asserts the launch-arg path.

## Batch 3g — Continuation timeouts (§3.4, §3.5)
**Files:** `MacroMark/Engine/LocationManager.swift`, `MacroMark/Engine/AudioTranscriber.swift`, `MacroMark/MacroMarkApp.swift` (the launch-time speech-auth call — coordinate with 3k).
**Change:** Extract the `ContinuationTimeout` actor (currently inside `WatchConnectivityProvider.swift`) to `MacroMarkKit/Support/ContinuationTimeout.swift` so all three call sites can use it. Add a 5s timeout to `LocationManager.getCurrentLocation` (resume with `nil`). Add a timeout to the speech-auth continuations (resume with `.denied` or the current status). Remove the redundant launch-time speech-auth call (3k/§4.2) as part of this.
**Acceptance:** A test that never fires the CoreLocation callback asserts `getCurrentLocation` returns `nil` within ~5s.

## Batch 3h — reprocessPendingItems off main thread at launch (§7.2)
**Files:** `MacroMark/MacroMarkApp.swift`.
**Change:** Remove the `reprocessPendingItems(container:)` call from `init()` (line 93). Instead, trigger it from a `.task { ... }` on the root view in `body` (or `AppTabView`), so it runs after the first frame. Keep it `@MainActor` for the SwiftData access but the synchronous UserDefaults churn now happens post-launch.
**Acceptance:** Launch-time main-thread work drops; notes still reprocess.

## Batch 3i — Cache baseDirectoryURL (§7.3)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift`.
**Change:** Replace the computed `baseDirectoryURL` with a cached `private var cachedBaseDirectoryURL: URL?` resolved lazily, plus a `resolveBaseDirectoryURL()` method. Invalidate the cache when the stale-bookmark branch clears `customSaveBookmark`. Move the `isUsingFallbackStorage` assignment out of the getter into the resolver method.
**Acceptance:** `forUbiquityContainerIdentifier` is called once per app session, not per append.

## Batch 3j — Deprecated watch text-input API (§4.3)
**Files:** `MacroMark Watch App/Capture/SystemCaptureView.swift`.
**Change:** Replace `WKExtension.shared().visibleInterfaceController?.presentTextInputController(...)` with the non-deprecated API. Handle the result as `[Any]`; extract the first `String`; if a non-string element is picked (emoji/moji), fall back to its localized description rather than silently dismissing.
**Acceptance:** Emoji/moji input no longer silently drops. watchOS scheme builds with no deprecation.

## Batch 3k — Remove redundant launch-time speech auth (§4.2)
**Files:** `MacroMark/MacroMarkApp.swift` (lines 82-88).
**Change:** Delete the `_ = await withCheckedContinuation { ... SFSpeechRecognizer.requestAuthorization ... }` block. `AudioTranscriber.transcribe` owns auth.
**Acceptance:** iOS scheme builds; transcription still requests auth on first use.

## Batch 3l — Extract AddMacroView (§8.1) + defaultMacros (§9.6)
**Files:** `MacroMark/Settings/MacroManagerView.swift`, new `MacroMark/Settings/AddMacroView.swift`, new `MacroMarkKit/Sources/MacroMarkKit/Models/DefaultMacros.swift` (or static on `Macro`).
**Change:** Move `AddMacroView` (lines 278-320) to its own file. Move `defaultMacros` (lines 220-254) to a `public enum DefaultMacros { public static let macros: [Macro] = [...] }` in MacroMarkKit. Update `prepopulateIfNeeded` and `restoreDefaults` (after 2e) to reference `DefaultMacros.macros`.
**Acceptance:** `MacroManagerView.swift` shrinks below ~250 lines. Kit tests can assert on `DefaultMacros.macros.count`.

## Batch 3m — Render Macro.notes or remove (§8.2)
**Files:** `MacroMark/Settings/MacroManagerView.swift` (row at 111-126), possibly `MacroEditView.swift`/`AddMacroView.swift`.
**Change (preferred):** In the macro row, below `replacement`, add `if !macro.notes.isEmpty { Text(macro.notes).font(.caption2).foregroundStyle(.secondary) }`. Keep the field.
**Acceptance:** Default macros' help text (e.g., "Dictation often mishears...") is visible in the list.

## Batch 3n — Extract WAL round-trip helpers (§9.3)
**Files:** `MacroMark/MacroMarkApp.swift` (lines 350-380).
**Change:** Add `private static func load<V: Codable>(_ type: V.Type, forKey key: String) -> [UUID: V]` and `private static func save<V: Codable>(_ dict: [UUID: V], forKey key: String)`. Replace the four functions with thin wrappers (or inline the calls).
**Acceptance:** No behavioral change; ~30 LOC removed. Use `UserDefaultsKey` from 2c.

## Batch 3o — Security-scope helper (§9.5)
**Files:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift`.
**Change:** Extract `private func withSecurityScope<T>(_ block: (URL) -> T) -> T` that resolves the bookmark, calls `startAccessingSecurityScopedResource()`, runs the block, and `defer`s stop. `appendText` and `readText` call it.
**Acceptance:** No behavioral change; the two methods shrink.

## Batch 3p — Wire or remove dead symbols (§9.7)
**Files:** `StoreManager.swift`, `iCloudStorageManager.swift`, `EntitlementManager.swift`, `SubscriptionPaywallView.swift`.
**Change:** Remove `purchaseState`, `isLoadingProducts`, and the `PurchaseState` enum (or wire `SubscriptionPaywallView` to show a spinner while loading and surface purchase errors). Remove `EntitlementManager.customMacroCount(_:)` (callers use `isEntitled` + `maxFreeMacros` — leave those). For `isUsingFallbackStorage`: add a banner in `InboxView` (or `AppTabView`) that shows when true.
**Acceptance:** No `private(set) var` is set-but-never-read. Fallback-storage banner appears when iCloud is unavailable.

---

# BATCH 4 — P3: polish (run in parallel; trivial)

- **4a (§3.6)** — `WatchConnectivityProvider.fetchDailyFile`: capture the timeout `Task` and `cancel()` it on reply/error.
- **4b (§3.7)** — `AudioTranscriber`: wrap `speechTask` in `OSAllocatedUnfairLock<SFSpeechRecognitionTask?>`; drop `nonisolated(unsafe)`.
- **4c (§4.1)** — `MacroMarkApp.startBackgroundTaskAndProcess`: hoist `endBackgroundTask` into a `defer` so all early-return paths clean up.
- **4d (§7.4)** — `InboxView`/`MacroManagerView`: add `fetchLimit` to the `@Query` `FetchDescriptor` (e.g., 200) or paginate.
- **4e (§8.3)** — Replace hardcoded frame heights with named layout constants or remove where Dynamic Type suffices.
- **4f (§8.4)** — Define `enum CaptureMode: String, CaseIterable { case audio, system }` in MacroMarkKit; use `.rawValue` in `@AppStorage` and replace raw-string switches.
- **4g (§9.8)** — `git rm test.swift`, `MacroMarkWidget/MacroMarkWidgetControl.swift`, `MacroMarkWidget/AppIntent.swift`.
- **4h (§9.10)** — Name magic constants with `private static let` per file (audio rates, timeouts, extensions, keychain key).
- **4i** — Rename `MacroMark_Watch_AppApp` → `MacroMarkApp` in `MacroMark Watch App/MacroMarkApp.swift`; update any references.
- **4j** — Add `cancel()` to `fetchDailyFile` (same as 4a if same file).

---

## Verification gate (after each batch)

1. Both schemes build clean (`** BUILD SUCCEEDED **`, no new warnings).
2. Any new test target passes (`xcodebuild test` or Xcode MCP `XcodeTest`).
3. `grep -rn "print(" MacroMarkKit` (post-2a) returns nothing outside `#if DEBUG`.
4. `diff` of the two WatchConnectivityProvider files (post-2b) — one file gone.
5. For P0 batches: re-read `CODE_AUDIT.md` §12 Verification lines and confirm the cited lines no longer exhibit the bug.

## Commit message template

```
fix(audit): <batch id> <one-line summary>

Addresses CODE_AUDIT.md §<N.M> (<severity>).
<2-3 line description of the change and why>.
```

Commit only when the user explicitly asks. Each batch = one commit. P0 batches should be reviewed/merged before P1 starts if the user wants staging.
