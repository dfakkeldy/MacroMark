# MacroMark Code Audit

Generated 2026-06-20. Scope: 43 Swift source files (~3,700 LOC) across 4 targets — `MacroMark` (iOS), `MacroMark Watch App`, `MacroMarkKit` (SPM), `MacroMarkWidget`. Excluded: `.git`, `.build`, `.swiftpm`, `MacroMarkKit/.build`, `MacroMarkKit/.swiftpm`, and the untracked scratch file `test.swift` at the repo root. No `Dead/` archive directory exists.

This audit supersedes the 2026-06-05 snapshot. Since then, commits `0a8a9ec`, `b16c535`, `4e2c3dd`, and `f015c9e` landed an end-to-end ACK protocol, a write-ahead log, and several concurrency fixes. Those changes were re-verified here; the prior report's §3.1 (UIPasteboard off MainActor), §3.3 (AudioTranscriber leaked continuation), §3.4 (sendMessage continuation isolation), §5.4 (StoreManager finish-before-entitlement), and §6.1 (compile-time `#if DEBUG` paywall bypass) are now **resolved** and intentionally not re-raised.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made during the audit.

Build ground truth: both the `MacroMark` (iOS) and `MacroMark Watch App` schemes build **clean** under Xcode 26.5 / Swift 6.3.2 with strict concurrency. No Swift warnings were emitted; the concurrency findings below come from reading the code, not the compiler.

---

## Swift 6.2 Migration Update — 2026-06-25

The project was migrated to **Swift 6 language mode**: `SWIFT_VERSION = 6.0` on all 7 Xcode targets and `swiftLanguageModes: [.v6]` in `MacroMarkKit/Package.swift`. Default actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) was extended to the two Swift Testing unit-test targets; the widget and the two XCUITest targets are intentionally left nonisolated (WidgetKit's closure-based `TimelineProvider` and `XCTestCase`'s lifecycle overrides are `nonisolated` and conflict with default MainActor isolation). The watch app scheme's Test action was wired to its test target so the watch durability tests can run.

**Verified:** iOS app, watch app, widget, and `MacroMarkKit` all build clean (0 warnings); `MacroMarkKit` (17 tests), iOS unit (6), and watch unit (2 durability) tests pass on simulators.

**§3.1 / §3.2 / §3.3 were re-verified as already resolved in the code** — this report's 2026-06-20 snapshot is stale on them: §3.1 now uses `OSAllocatedUnfairLock`, §3.2 calls `Task { await processAudioFile(...) }` directly, and §3.3 uses `await Task.sleep(for:)`.

**New issues the migration surfaced and fixed (none were caught by the prior Swift-5-mode build):**

- **[Critical] `WatchConnectivityProvider` crashed at app launch under Swift 6.** The class is `@MainActor`, but `WCSession` delivers `WCSessionDelegate` callbacks on its own background queue. Swift 6's runtime executor check (`_checkExpectedExecutor`) turned this previously-silent hazard into a `SIGTRAP` on WCSession activation — the app crashed at launch, and was already mutating `LocalStore` queue state off-actor. **Fix:** all 9 delegate methods are now `nonisolated`, hopping to the main actor only for state access; the received-audio file copy stays synchronous so WCSession's inbox file isn't lost (`MacroMark/Shared/WatchConnectivityProvider.swift`, symlinked into the watch target).
- **[High] `MacroProcessor.process` took SwiftData `@Model` `Macro` objects off-actor.** Introduced a `Sendable` value snapshot `MacroRule` (`MacroMarkKit/Sources/MacroMarkKit/Models/MacroRule.swift`); callers snapshot `[Macro] → [MacroRule]` on the main actor. Also decouples the macro engine from SwiftData.
- **[Medium] `LocationManager` delegate captured a non-Sendable `CLLocationManager` in a `@MainActor` closure** (`LocationManager.swift:52`). Fixed by reading the Sendable `authorizationStatus` before the hop.
- **[Medium] `AudioTranscriber` used `nonisolated(unsafe)` for the cancellable speech task.** Replaced with an `OSAllocatedUnfairLock`.
- **[Low] `iCloudStorageManager` read path (`readText`, `shared`, `folderSettings`, base-dir resolution) made `nonisolated`** so the WC reply handler reads without sending the non-Sendable reply closure across an actor boundary. The write/append/defer (§5.2) path and `isUsingFallbackStorage` publishing are unchanged.

The open data-loss criticals **§5.1 (ACK before iCloud append confirmed) and §5.2 (un-materialized placeholder drop) remain unaddressed** — out of scope for this migration.

---

## 1. Executive summary

Top items to address, in priority order. Data-loss in the note-sync pipeline is the user's stated #1 concern and dominates this list.

1. **[Critical] ACK is sent before the iCloud append is confirmed** — §5.1 — `MacroMark/MacroMarkApp.swift:424-433`. A note that saves to SwiftData but fails the iCloud append is ACK'd, removed from the WAL, and deleted from the watch — yet never reaches the daily-note file.
2. **[Critical] iCloud append silently drops notes when the day's file is an un-materialized placeholder** — §5.2 — `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:111-115`. Combined with §5.1, a note captured right after a device wake is permanently absent from the `.md` output with no retry.
3. **[Critical · ✅ RESOLVED] Data race on the MacroProcessor regex cache** — §3.1 — `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:13,37-43`. `nonisolated(unsafe)` dictionary mutated from concurrent `process()` calls; the "benign" comment is wrong — Dictionary mutation is a crash-class data race.
4. **[High] Stale compiled regex is never invalidated when macros are edited** — §5.3 — `MacroProcessor.invalidateRegexCache()` exists but is called nowhere; editing a trigger leaves the old pattern replacing text.
5. **[High · ✅ RESOLVED] watchOS semaphore+main-actor pattern can deadlock and lose the recording** — §3.2 — `MacroMark Watch App/Capture/InstantCaptureView.swift:57-69` (and `SystemCaptureView.swift:31-43`). Blocking a cooperative-pool thread on `DispatchSemaphore.wait()` waiting for a MainActor hop.
6. **[High · ✅ RESOLVED] Blocking `Thread.sleep` on the @MainActor during iCloud download wait** — §3.3 — `iCloudStorageManager.swift:151-154`. Up to 2s UI freeze whenever the daily file isn't local.
7. **[High] `WatchConnectivityProvider` is byte-for-byte duplicated across the iOS and watch targets** — §9.1 — 301 lines × 2; the ACK/WAL protocol this code implements must not drift.
8. **[High] Unguarded `print()` calls ship IAP errors and file paths to release logs** — §6.3 — 9 calls in `MacroMarkKit` (incl. `StoreManager` IAP failures), 7 in the watch app, 4 in the iOS app.
9. **[High] `restoreDefaults` silently deletes the user's custom macros** — §5.4 — `MacroMark/Settings/MacroManagerView.swift:265-273`. No confirmation; deletes everything before re-inserting defaults.
10. **[High] Magic `UserDefaults`/`@AppStorage` key strings scattered across 6 files** — §9.4 — 18+ raw-string uses of 5 keys; a typo silently breaks a setting.

---

## 2. Quick wins (≤30 min each)

These deliver outsized value relative to effort and have no architectural ripples.

- **Delete the untracked `test.swift` at the repo root** — `test.swift`. Scratch file, references `WCSession.sendMessage` with the wrong arity, not in any target.
- **Delete `MacroMarkWidget/MacroMarkWidgetControl.swift` and `MacroMarkWidget/AppIntent.swift`** — `MacroMarkWidget/MacroMarkWidgetControl.swift:1-77`, `MacroMarkWidget/AppIntent.swift:1-18`. Xcode "Start Timer" / "Favorite Emoji" template leftovers, unregistered in `MacroMarkWidgetBundle`.
- **Wrap the 4 ungated iOS-app `print()` calls in `#if DEBUG`** — `MacroMark/MacroMarkApp.swift:53`, `MacroMark/Settings/MacroManagerView.swift:193`, `MacroMark/Engine/LocationManager.swift:63`, `MacroMark/Engine/AudioTranscriber.swift:55`.
- **Call `MacroProcessor.invalidateRegexCache()` from every macro-mutation site** — §5.3. One-line fix per site; resolves the stale-regex correctness bug.
- **Add a `.confirmationDialog` to "Restore Default Macros"** — §5.4. The button is already `role: .destructive`; just confirm before the bulk delete.
- **Add a `Task.sleep` timeout to `LocationManager.getCurrentLocation`** — `MacroMark/Engine/LocationManager.swift:27-41`. Reuse the `ContinuationTimeout` actor already in `WatchConnectivityProvider`.
- **Save `note.exportTarget`/`isExported` with a real `do/try/catch` in `NoteDetailView.exportTo`** — `MacroMark/Views/NoteDetailView.swift:44-53`. Currently mutates the model but never calls `context.save()`.
- **Remove the redundant `SFSpeechRecognizer.requestAuthorization` call in `MacroMarkApp.init`** — `MacroMark/MacroMarkApp.swift:82-88`. Result is discarded; `AudioTranscriber.transcribe` already requests it.
- **Rename `MacroMark_Watch_AppApp` → `MacroMarkApp`** — `MacroMark Watch App/MacroMarkApp.swift:11`. Double-App, non-idiomatic.
- **Render `Macro.notes` in the macro row, or remove the field** — §9.7. Today AddMacroView/MacroEditView collect notes that are then invisible.

---

## 3. Concurrency

### 3.1 Data race on the MacroProcessor regex cache

> ✅ **Resolved (verified 2026-06-25):** the cache is now `OSAllocatedUnfairLock<[String: NSRegularExpression]>` with all access via `withLock`. The description below records the prior state.

- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:13` (declared), `:37-43` (read+written), `:16-18` (`invalidateRegexCache` writes it)
- **What:** `regexCache` is `private static nonisolated(unsafe) var regexCache: [String: NSRegularExpression]`. The doc comment claims races are "benign — worst case is compiling the same regex twice." That is incorrect: `regexCache[pattern] = compiled` at line 42 mutates a Swift `Dictionary`, and `process(text:macros:...)` is explicitly documented as non-isolated ("callers should invoke it from the global cooperative pool"). `MacroMarkApp.startBackgroundTaskAndProcess` calls it from a `Task { @MainActor in ... await MacroProcessor.process(...) }`, so it runs off-actor. Two notes processed concurrently → concurrent Dictionary read/write.
- **Why:** Swift `Dictionary` is not thread-safe; concurrent mutation is undefined behavior and a known source of `EXC_BAD_ACCESS` / heap corruption. `nonisolated(unsafe)` only silences the compiler; it does not make the access safe. A crash here aborts the note pipeline mid-transcription.
- **Action:** Protect the cache with `OSAllocatedUnfairLock<[String: NSRegularExpression]>` (or an `actor RegexCache`). `NSRegularExpression` matching is already thread-safe, so only the dictionary mutation needs guarding.
- **Severity:** Critical

### 3.2 DispatchSemaphore.wait() over cooperative-pool work (deadlock risk) on watchOS

> ✅ **Resolved (verified 2026-06-25):** both capture views call `Task { await processAudioFile(...) }` directly — no `DispatchSemaphore`, no `Task.detached`. The description below records the prior state.

- **Location:** `MacroMark Watch App/Capture/InstantCaptureView.swift:57-69`; identical pattern at `MacroMark Watch App/Capture/SystemCaptureView.swift:31-43`
- **What:** `Task.detached { ProcessInfo.processInfo.performExpiringActivity(...) { expired in ... let semaphore = DispatchSemaphore(value: 0); Task { await InstantCaptureView.processAudioFile(...); semaphore.signal() }; semaphore.wait() } }`. A cooperative-pool thread is parked on `semaphore.wait()` waiting for an inner `Task` whose body calls `MainActor.run { LocalStore.shared.enqueueAudio(...) }`.
- **Why:** Blocking a cooperative thread waiting for other cooperative work (here, a MainActor hop) is the classic Swift Concurrency deadlock anti-pattern. Under cooperative-pool pressure on watchOS (tight thread budget) the inner `Task` never schedules and the wait never returns — the audio file is never enqueued into `LocalStore`, so it is never transferred and the recording is lost before it even reaches the WAL. The wrapped work is trivial and needs neither `performExpiringActivity` nor the semaphore.
- **Action:** Drop the semaphore and the `Task.detached`. Call `Task { await InstantCaptureView.processAudioFile(...) }` directly (the `MainActor.run` inside is fine). If a background-execution guarantee is genuinely needed, use a `WKApplication` lifecycle hook instead of blocking a pool thread.
- **Severity:** High

### 3.3 Blocking Thread.sleep on the @MainActor during iCloud download wait

> ✅ **Resolved (verified 2026-06-25):** `appendText`/`ensureDownloaded` are `async` and use `await Task.sleep(for:)` instead of `Thread.sleep`. The description below records the prior state.

- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:143-155` (the `ensureDownloaded` loop), reached from `appendText(_:for:)` at `:92` — `iCloudStorageManager` is `@MainActor` (line 3)
- **What:** `ensureDownloaded` spins `for _ in 0..<20 { ... Thread.sleep(forTimeInterval: 0.1) }` — up to 2 seconds of synchronous blocking. `appendText` is `@MainActor` and is called from `MacroMarkApp.processAndExport` (already on MainActor) and from `NoteDetailView.exportToICloud` (user tap).
- **Why:** Up to a 2-second main-thread freeze whenever the daily file is an iCloud placeholder (common right after a device wake). On iOS this is a frozen UI / watchdog-kill risk; the user perceives the app as hung right after capturing a note.
- **Action:** Make `appendText` `async` and replace `Thread.sleep` with `try? await Task.sleep(for: .milliseconds(100))`. Or move the whole manager off `@MainActor` (it has no UI state beyond `isUsingFallbackStorage`, which can publish from any actor via `@Observable`).
- **Severity:** High

### 3.4 withCheckedContinuation for speech authorization lacks a timeout
- **Location:** `MacroMark/MacroMarkApp.swift:83-87` and `MacroMark/Engine/AudioTranscriber.swift:7-11`
- **What:** `SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: status) }` is wrapped in a plain `withCheckedContinuation` with no cancellation handler and no timeout.
- **Why:** If the Speech framework never invokes the completion handler (rare but reported on restricted/first-launch devices), the continuation is never resumed and the surrounding `Task` hangs forever — leaving the note stuck in-flight (`Self.inFlightIDs` never cleared) and blocking its reprocessing.
- **Action:** Race the callback against a `Task.sleep(for: .seconds(N))` using the `ContinuationTimeout` actor pattern already in `WatchConnectivityProvider.fetchDailyFile` (lines 261-288) — the correct idiom already exists in this codebase.
- **Severity:** Medium

### 3.5 Stored continuations in LocationManager can leak (no timeout)
- **Location:** `MacroMark/Engine/LocationManager.swift:11-12, 27-41`
- **What:** `activeContinuation`/`authContinuation` are stored properties resumed only from CoreLocation delegate callbacks (`didUpdateLocations`, `didFailWithError`, `locationManagerDidChangeAuthorization`). `getCurrentLocation()` has no timeout.
- **Why:** If CoreLocation never delivers a location or an error (intermittent GPS, or the app is backgrounded mid-request), the continuation never resumes. The note containing `{location}` then hangs in processing indefinitely; WAL replay hits the same hang.
- **Action:** Wrap the `requestLocation` continuation in a `Task.sleep(for: .seconds(5))` timeout that resumes with `nil`, reusing the `ContinuationTimeout` pattern.
- **Severity:** Medium

### 3.6 fetchDailyFile's timeout Task is never cancelled on success
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:261-289` (and the watch-target duplicate)
- **What:** The `withCheckedContinuation` spawns `Task { try? await Task.sleep(for: .seconds(15)); ... }` as a timeout racer. When `sendMessage`'s replyHandler fires first, the 15s sleep Task keeps running (it no-ops because `complete()` returns `false`).
- **Why:** Minor resource leak; on watchOS with tight memory, repeated daily-log fetches accumulate sleeper Tasks.
- **Action:** Capture the timeout `Task` and `cancel()` it from the reply/error handlers before resuming.
- **Severity:** Low

### 3.7 nonisolated(unsafe) capture of speechTask in AudioTranscriber
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:28-47`
- **What:** `nonisolated(unsafe) var speechTask: SFSpeechRecognitionTask?` is assigned inside the continuation body and read in the `withTaskCancellationHandler onCancel:`. Sequencing makes this benign today (the `isResumed` guard prevents double-resume, and `onCancel` seeing `nil` is safe).
- **Why:** Theoretical race on the optional itself if cancellation arrives during assignment. Low risk but the `nonisolated(unsafe)` is a smell.
- **Action:** Wrap in `OSAllocatedUnfairLock<SFSpeechRecognitionTask?>` (init `nil`) and `withLock` on both assignment and cancel; drop `nonisolated(unsafe)`.
- **Severity:** Low

---

## 4. API modernity

Both schemes build clean, so there are no deprecation warnings. The items below are opportunities, not compile-time issues. Deployment target is iOS 26.0 / latest watchOS, so any `#available` guard below 26 is dead.

### 4.1 `beginBackgroundTask` legacy pattern, no error-path cleanup
- **Location:** `MacroMark/MacroMarkApp.swift:248-260`
- **What:** `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)` is used to extend processing during watch-data receipt. It's the correct API for "finish a short piece of work if the app is backgrounded," so this is acceptable — but several early-return paths in the surrounding `Task` (transcription failure at `:286-292`, missing text/audio at `:298-305`) duplicate the `endBackgroundTask` cleanup.
- **Why:** Minor; the duplication invites a future path that forgets to call `endBackgroundTask`, leaking a background-time slot.
- **Action:** Hoist the `endBackgroundTask` call into a `defer` at the top of the `Task` so every exit path cleans up.
- **Severity:** Low

### 4.2 Redundant speech-authorization request at launch
- **Location:** `MacroMark/MacroMarkApp.swift:82-88`
- **What:** `init()` calls `SFSpeechRecognizer.requestAuthorization` via a continuation and discards the result (`_ = await ...`). `AudioTranscriber.transcribe` requests it again on every transcription.
- **Why:** Wasted async work at launch; the launch-time result is unused.
- **Action:** Remove the launch-time call and let `AudioTranscriber` own authorization (ideally caching the status and only calling when `.notDetermined`).
- **Severity:** Low

### 4.3 `WKExtension.presentTextInputController` deprecated; `as? [String]` drops non-string picks
- **Location:** `MacroMark Watch App/Capture/SystemCaptureView.swift:23-27`
- **What:** `WKExtension.shared().visibleInterfaceController?.presentTextInputController(...)` is deprecated. The result is cast `as? [String]`; if the user picks a moji/emoji (non-string `Any` element), the cast yields `nil` and the input is silently dropped — dismiss-without-save.
- **Why:** Deprecation will eventually block builds; the silent-drop is a data-loss path for emoji/moji input.
- **Action:** Migrate to the non-deprecated `WKInterfaceController.presentTextInputController`. Handle `result` as `[Any]`, extract the first `String`, and fall back to a localized description for non-string picks.
- **Severity:** Medium

---

## 5. Bugs / logic errors

### 5.1 ACK is sent before the iCloud append is confirmed — note saved but never written to the daily file
- **Location:** `MacroMark/MacroMarkApp.swift:424-458` (ACK at `:429`/`:432`, iCloud append at `:442`)
- **What:** `processAndExport` calls `addProcessedNoteID(noteId)`, removes the WAL entry, and fires `acknowledgeNoteIfDurable`/`acknowledgeFileIfDurable` immediately after `context.save()` succeeds. The iCloud append (`iCloudStorageManager.shared.appendText(...)`) happens *after* the ACK. The comment at line 435 ("failures don't undo the ACK") explicitly accepts this gap.
- **Why:** The app's entire value proposition is "Markdown appended to iCloud Drive." A note that the watch believes delivered, that disappears from the WAL, and that never lands in the `.md` file is effectively lost from the user's perspective. This directly contradicts the data-loss-prevention intent of the recent ACK/WAL commits.
- **Action:** Do not ACK (and do not clear the WAL entry / add to `processedNoteIDs`) until the configured export target has actually succeeded. For the `.iCloud` target, gate the ACK on `appendText` returning `true`. Introduce a separate "exported" WAL state so a note that saved to SwiftData but failed iCloud append is retried on next launch rather than silently dropped from the pipeline.
- **Severity:** Critical

### 5.2 iCloud append silently drops notes when the day's file is an un-materialized placeholder
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:88-128` (deferral at `:111-115`)
- **What:** When `cloudCopyExistsButNotDownloaded(url)` is true after the 2s `ensureDownloaded` wait, the coordinator prints and leaves `writeSucceeded = false`, so `appendText` returns `false`. The caller (`MacroMarkApp.processAndExport`) only uses that return to set `note.isExported`; it does **not** re-queue. Combined with §5.1, the note is then gone from the WAL.
- **Why:** Anytime the daily file is an iCloud placeholder (common right after a device wake or mid-sync), a captured note is permanently absent from the `.md` output. There is no retry loop — the deferral only resolves if another note happens to arrive later and triggers a download.
- **Action:** Return a distinct "deferred" result from `appendText` and have the caller re-enqueue deferred notes (timer-based retry, or re-add to the WAL) until the file materializes. Consider buffering pending appends in SwiftData with a `pendingExport: Bool` flag and a background `ensureDownloaded` + retry pass.
- **Severity:** Critical

### 5.3 Stale compiled regex never invalidated when macros are edited
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:16-18` (the method); uncalled from `MacroMark/Settings/MacroManagerView.swift:204-216` (`deleteMacros`/`moveMacros`), `:265-273` (`restoreDefaults`), `:310-315` (`AddMacroView` Save), `MacroMark/Settings/MacroEditView.swift:69-77` (Save)
- **What:** `MacroProcessor` caches compiled regex keyed by the escaped trigger pattern (`MacroProcessor.swift:13,37-43`) and exposes `invalidateRegexCache()`. None of the five mutation sites call it. After a user edits a macro trigger from "Bold" to "Strong", the cached `\bBold\b` regex persists and keeps replacing "Bold" in new notes; "Strong" is compiled lazily on the next `process`, but the stale entry lingers (and any rename of an existing trigger leaves the old pattern firing).
- **Why:** Users who edit/rename macros see incorrect macro expansion — a real, user-visible correctness bug in the core processing path. Restoring defaults after heavy editing leaves a mix of stale and fresh regexes.
- **Action:** Call `MacroProcessor.invalidateRegexCache()` from `deleteMacros`, `moveMacros`, `restoreDefaults`, `AddMacroView`'s Save, and `MacroEditView`'s Save. (Also pairs with §3.1 — once the cache is locked, invalidation is a one-liner.)
- **Severity:** High

### 5.4 "Restore Default Macros" silently deletes the user's custom macros
- **Location:** `MacroMark/Settings/MacroManagerView.swift:265-273`
- **What:** The destructive button loops over **all** macros (including user customizations) and deletes them before re-inserting the 23 defaults. `role: .destructive` only styles the row; there is no `.confirmationDialog`.
- **Why:** User data loss with no confirmation. A user who built custom macros and taps "Restore Defaults" expecting only the defaults to reset loses their custom work.
- **Action:** Add a `.confirmationDialog`. Scope the deletion to `macro.isDefault == true` macros only, leaving custom macros intact.
- **Severity:** High

### 5.5 Audio transcription silently truncates on chunk failure
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:48-76`
- **What:** Chunks that fail transcription are appended to `chunkErrors` (`:54`) and skipped; the loop continues and returns whatever partial transcript exists (`:75`). Chunks are joined with a single space (`:50`), which can merge the last word of chunk N with the first word of chunk N+1 into a non-word. The only failure signal is `print("Failed to transcribe chunk")` (`:55`).
- **Why:** A 3-minute recording split into 4 chunks where chunk 2 fails silently produces a note with a gap the user cannot detect. Silent partial loss of dictated content is a data-integrity bug.
- **Action:** When any chunk fails, mark the note `transcriptionPartial` in SwiftData and surface a visible warning in InboxView/NoteDetailView. Insert a newline (or configurable separator) between chunks rather than a space. Consider failing the whole note (relying on WAL retry) if more than N% of chunks fail.
- **Severity:** High

### 5.6 Export badge in InboxView can be wrong (silent save drops; NoteDetailView never saves)
- **Location:** `MacroMark/MacroMarkApp.swift:441-458` (`try? context.save()`); `MacroMark/Views/NoteDetailView.swift:44-53` (mutates `note` but never saves)
- **What:** After a successful iCloud append or URL export, the iOS pipeline sets `note.isExported`/`note.exportTarget` and calls `try? context.save()`, discarding the error. `NoteDetailView.exportTo` mutates `note` inside the `UIApplication.open` completion but never calls `context.save()` at all.
- **Why:** The "Exported" badge in `InboxView` (lines 29-32) can be wrong — either stuck false (silent save failure) or set true in memory but never persisted (NoteDetailView). Not data loss, but incorrect UI state the user relies on to know a note reached its target.
- **Action:** Persist export-state changes with a real `do/try/catch` (log on failure). In `NoteDetailView.exportTo`, save the context after mutating `note`.
- **Severity:** Medium

### 5.7 `wrapCleanupRegex` mangles legitimate `*`/`_`/`~` in user dictation
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:21-23, 121-130`
- **What:** The regex `([\*\_\~]+)\s+(.+?)\s+\1` → `$1$2$1` collapses `** text **` into `**text**`. It runs over the **entire** processed text, including legitimate markdown or symbols the user dictated — e.g., "3 * 4 * 5" or a code snippet.
- **Why:** Silent mutation of user content. Users dictating math, code, or literal asterisks/underscores/tildes see corrupted output.
- **Action:** Apply the cleanup only to substrings produced by macro expansion, not the whole string. Or require the wrapping to span a single word boundary. Add tests for `*`/`_`/`~` in non-markdown contexts.
- **Severity:** Medium

### 5.8 `processedNoteIDs` dedup set grows unbounded in UserDefaults
- **Location:** `MacroMark/MacroMark/MacroMarkApp.swift:126-137`
- **What:** `addProcessedNoteID` reads the entire `MacroMark_ProcessedNoteIDs` string array from `UserDefaults`, inserts one UUID, and re-writes the whole array on every received note. `processedNoteIDs` (line 137) re-decodes the full set on every read, and `handleIncomingNote` reads it on every incoming message.
- **Why:** After months of use this is tens of thousands of UUID strings serialized/deserialized on the main actor for every note — degrading receive latency and inflating the UserDefaults plist. The dedup is also the only thing preventing duplicates when the watch re-sends after a missed ACK, so its reliability matters.
- **Action:** Move dedup state to SwiftData (a lightweight `ProcessedNoteID` model with the UUID as a unique attribute), or cap the set to an LRU window. At minimum, cache the set in memory rather than re-decoding per call.
- **Severity:** Medium

### 5.9 Watch notes whose ACK was lost become permanent zombies
- **Location:** `MacroMark Watch App/Storage/LocalStore.swift:72-79, 165-189`
- **What:** `syncPendingNotes` correctly skips notes already in `queuedNoteIDs`, and `queuedNoteIDs` is persisted across cold launch. So a note that was transferred but whose ACK was lost stays in both `pendingNotes` and `queuedNoteIDs` forever — never re-sent (good, the phone dedups) but never removed. `DailyLogView` shows these as "Pending Offline Notes" indefinitely.
- **Why:** Not data loss on the phone side (the phone has the note and its `processedNoteIDs` dedup protects against duplicates), but the watch's queue grows unbounded and the user sees stale "pending" notes forever.
- **Action:** Add a watchdog: after a grace period (e.g., 24h) with the note still queued and no ACK, reconcile via a `sendMessage` "isProcessed?" query when the phone is reachable (the phone already answers messages), then remove confirmed ones.
- **Severity:** Medium

### 5.10 FolderSettings date-format token replacement has no escaping
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Models/FolderSettings.swift:28-40` (and duplicated in `FolderSettingsView.swift:99-104, 115-120`)
- **What:** The format string is processed by sequential `replacing("yyyy", ...)`, then `"yy"`, `"MM"`, `"dd"`. There is no way to include a literal "dd"/"MM"/"yy" in a filename — the tokens are always substituted. The two view-local copies can also drift from the kit's version.
- **Why:** A user wanting literal text in their date format cannot get it. Combined with the duplication, the "example" shown in settings can disagree with the actual filename.
- **Action:** Use `Date.FormatStyle` (or `DateFormatter` with the user's format string, which supports `'literal'` quoting), or document the limitation and validate the format on save. De-duplicate into `FolderSettings.format` only (§9.2).
- **Severity:** Medium

### 5.11 LocalStore `pendingNotes.didSet` triggers a redundant save on every mutation
- **Location:** `MacroMark Watch App/Storage/LocalStore.swift:23-27, 149-162`
- **What:** `pendingNotes` has `didSet { save() }`, and `save()` JSON-encodes both `pendingNotes` and `pendingAudio` plus writes four UserDefaults keys. `addNote`, `syncPendingNotes`, `removeNote`, `enqueueAudio`, `syncPendingAudio`, and `removeAudio` also call `save()` explicitly — so every `pendingNotes.append` triggers a double full re-encode of both arrays.
- **Why:** On watchOS with limited CPU/battery, repeated JSON encoding of growing arrays on the main actor is wasteful. `pendingNotes.append` becomes O(n) in array size due to the didSet save.
- **Action:** Remove the `didSet { save() }` (rely on the explicit `save()` calls at mutation sites), or debounce.
- **Severity:** Medium

---

## 6. Security

### 6.1 Keychain lifetime-unlock is local-only (no `kSecAttrSynchronizable`, no access group)
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:99-138`; entitlements `MacroMark/MacroMark.entitlements:1-14`
- **What:** The keychain add/query (lines 103-115, 120-125) specify no `kSecAttrAccessGroup` and no `kSecAttrSynchronizable`, so the lifetime flag lives in the app's default local keychain. The iOS entitlements file declares iCloud CloudDocuments only — no `keychain-access-groups`, no `com.apple.security.application-groups`. The watch target has no entitlements file. `EntitlementManager` is iOS-only today, so this is internally consistent, but: a fresh install on a new device relies entirely on `Transaction.currentEntitlements` re-running. If StoreKit is unavailable at first launch, the lifetime unlock is invisible until the next `Transaction.updates` fire.
- **Why:** A lifetime-paying user who reinstalls on a device with no network at launch briefly appears non-entitled. Not permanent (the unlock returns once StoreKit syncs), but the keychain flag — meant to be the durable backstop — provides no cross-device resilience.
- **Action:** Add `kSecAttrSynchronizable: true` to both the add and query (iCloud-syncs across the user's devices as a backstop), or add an App Group + shared keychain access group and persist there. Verify the watch target's entitlements if/when it ever reads entitlement.
- **Severity:** Medium

### 6.2 `simulateEntitled` heuristic grants entitlement in TestFlight
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:18-27, 78-81`
- **What:** `simulateEntitled` returns `true` when the receipt is `sandboxReceipt` (TestFlight) OR an embedded provisioning profile is present (any dev/ad-hoc build). `isEntitled` short-circuits to `true` when `simulateEntitled`. (Note: the previous audit's compile-time `#if DEBUG` bypass is resolved; this is the runtime replacement.)
- **Why:** TestFlight beta testers see all features unlocked — appropriate for testing, but the comment claims it "cannot leak into distribution builds" while App Store builds can transit TestFlight for some distribution flows, and any build with an embedded profile (ad-hoc, enterprise) is also unlocked. The boundary is fuzzier than the comment implies.
- **Action:** Document this loudly. Gate on a stricter signal — a `DEBUG`-only launch argument (`-MacroMarkSimulateEntitled`, which the doc comment already references but the code doesn't read) — rather than the presence of a sandbox receipt / profile.
- **Severity:** Medium

### 6.3 Unguarded `print()` calls ship IAP errors and file paths to release logs
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:39, 65, 77, 94`; `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:109, 115, 121, 126, 180`; `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:45, 157`; `MacroMark Watch App/Storage/LocalStore.swift:111, 160, 170, 183`; `MacroMark Watch App/Capture/AudioRecorder.swift:19, 52`; `MacroMark/MacroMarkApp.swift:53`; `MacroMark/Settings/MacroManagerView.swift:193`; `MacroMark/Engine/LocationManager.swift:63`; `MacroMark/Engine/AudioTranscriber.swift:55`
- **What:** ~20 `print()` calls are not behind `#if DEBUG`. The MacroMarkKit library cannot reliably see the app's `DEBUG` flag (SPM `DEBUG` isn't propagated the same way for app-consuming-package release builds), so its 9 prints ship unconditionally. Notably `StoreManager.swift:65 print("Purchase failed: \(error)")` and `:94 print("Restore purchases failed: \(error)")` leak StoreKit error details, and `:77 print("Unverified transaction received")` runs on every unverified (potentially fraudulent) transaction.
- **Why:** Release builds log internal errors to stdout. No PII/bearer tokens/IAP receipts appear, but file paths and StoreKit error descriptions do, which can reveal user-identifiable information.
- **Action:** Replace all kit `print()` with `os.Logger` (subsystem `com.macromark`, categories per module) — production-safe and level-filtered at runtime. Wrap the 4 iOS-app prints in `#if DEBUG`. This is the single most impactful logging cleanup.
- **Severity:** High

---

## 7. Performance

### 7.1 NSRegularExpression recompiled per macro per call (cache exists but unsynchronized — see §3.1)
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:13, 37-43`
- **What:** A cache *does* exist (the prior audit's "no caching" finding is resolved). However, until §3.1's lock is added and §5.3's invalidation is wired, the cache is both unsafe and stale.
- **Why:** Once those are fixed, per-call regex compilation drops to zero for an unchanged macro set. Listed here so the perf win is credited alongside the correctness work.
- **Action:** Resolve §3.1 and §5.3 together; the cache then delivers its intended benefit.
- **Severity:** Medium

### 7.2 `reprocessPendingItems` runs synchronously in `MacroMarkApp.init` on the main thread
- **Location:** `MacroMark/MacroMarkApp.swift:93, 148-168`
- **What:** `init()` calls `reprocessPendingItems(container:)`, which iterates the WAL and calls `handleIncomingNote`/`processAudio` for each item. The dedup checks and WAL reads/writes are synchronous on the main thread during launch.
- **Why:** With a backlog at launch (phone was off, watch queued many notes), launch is delayed by synchronous UserDefaults churn on the main thread.
- **Action:** Move `reprocessPendingItems` into a `.task` modifier on the root view (or a `Task` launched from `init` that hops off the main actor for the read phase) so it runs after launch completes.
- **Severity:** Medium

### 7.3 `baseDirectoryURL` recomputed (bookmark resolve + ubiquity lookup) on every append/read
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:20-44, 71-73, 157-160`
- **What:** `baseDirectoryURL` is a computed property. `appendText` and `readText` each resolve the security-scoped bookmark, call `url(forUbiquityContainerIdentifier:)` (known-slow), and mutate `isUsingFallbackStorage` as a side effect of a "getter."
- **Why:** `forUbiquityContainerIdentifier` can take hundreds of ms on first call; calling it per-append is a perf hit, and the side-effect-on-read pattern is fragile (reading a property mutates published state, risking SwiftUI re-render loops if observed).
- **Action:** Cache the resolved URL after first successful resolution; invalidate only when a bookmark is marked stale. Make the fallback flag a method, not a side effect of the computed property.
- **Severity:** Medium

### 7.4 `@Query` in InboxView/MacroManagerView has no fetch limit
- **Location:** `MacroMark/Views/InboxView.swift:7`; `MacroMark/Settings/MacroManagerView.swift:9`
- **What:** `@Query(sort: \ProcessedNote.createdAt, order: .reverse) private var notes` fetches all notes with no `fetchLimit`. `List { ForEach(notes) }` materializes a row per note.
- **Why:** After thousands of captures the Inbox initial render gets slow.
- **Action:** Add `fetchLimit` to the `FetchDescriptor` or paginate; consider sectioning by day.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 `AddMacroView` lives inside `MacroManagerView.swift` (AGENTS.md violation)
- **Location:** `MacroMark/Settings/MacroManagerView.swift:278-320`
- **What:** `AddMacroView` is a peer of `MacroEditView.swift` (which correctly gets its own file) but is bundled into `MacroManagerView.swift`. AGENTS.md: "Break different types up into different Swift files."
- **Why:** Inconsistent with the sibling-view convention; the host file is 326 lines.
- **Action:** Extract `AddMacroView` to `Settings/AddMacroView.swift`.
- **Severity:** Medium

### 8.2 `Macro.notes` is collected but never shown
- **Location:** `MacroMark/Settings/MacroManagerView.swift:111-126` (row omits it); set at `:225, 246, 248, 249, 252`; editable in `AddMacroView:297-300` and `MacroEditView`
- **What:** The `notes` help text (e.g., "Dictation often mishears 'Heading Two' as 'Heading To'.") is stored and editable, but the macro row only renders `trigger` and `replacement`. `AddMacroView` lets the user type notes that then vanish.
- **Why:** Misleading UX and dead data. The "Notes (Optional)" section implies the user will see them later.
- **Action:** Render `notes` as a caption in the macro row (under `replacement`), or remove the field and the Section.
- **Severity:** Medium

### 8.3 Hardcoded frame heights and `minHeight` literals
- **Location:** `MacroMark Watch App/ContentView.swift:38, 45` (`.frame(height: 70)`, `.frame(minHeight: 44)`); `MacroMark/Views/NoteDetailView.swift:12` (`.frame(minHeight: 200)`); `MacroMark Watch App/Capture/InstantCaptureView.swift:13` (`.frame(width: 80, height: 80)`)
- **What:** Hardcoded layout dimensions. AGENTS.md leans on Dynamic Type for fonts; frames are a softer case but still magic numbers.
- **Why:** Minor; inconsistent with a scalable-layout philosophy and uncentralized.
- **Action:** Extract named layout constants, or remove where Dynamic Type / relative sizing could replace them.
- **Severity:** Low

### 8.4 `captureMode` stored/compared as raw strings
- **Location:** `MacroMark/Settings/MacroManagerView.swift:11, 39-42`; `MacroMark Watch App/ContentView.swift:10, 86-94`
- **What:** Capture mode is stored in `@AppStorage` and compared via raw strings (`"audio"`, `"system"`). (The watch `ContentView` does define a local `CaptureMode` enum, but it's the navigation enum, not the storage one.)
- **Why:** A typo in any string silently breaks functionality with no compiler help.
- **Action:** Define `enum CaptureMode: String, CaseIterable { case audio, system }` in MacroMarkKit and use `.rawValue` for `@AppStorage`.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 `WatchConnectivityProvider.swift` duplicated byte-for-byte across iOS and watch targets
- **Locations:** `MacroMark/Shared/WatchConnectivityProvider.swift:1-301` and `MacroMark Watch App/Storage/WatchConnectivityProvider.swift:1-301`
- **What:** The two files are byte-identical (verified by diff). Every method — `sendNote`, `sendFile`, `acknowledgeNote/File`, `updateSettings`, both `didReceive*` handlers, both `didFinish*` handlers, `fetchDailyFile`, `didReceiveMessage`, the `ContinuationTimeout` actor — is duplicated. The file already uses `#if os(iOS)` / `#if os(watchOS)` throughout, so a single source file compiles in both targets. (The watch copy also lives under `Storage/`, misleading — it handles connectivity, not storage.)
- **Why:** Two copies of 301 lines (602 LOC total) drift silently. Any future fix to the ACK/WAL protocol — exactly the data-loss-sensitive code in §5.1 — must be made twice; a missed edit causes watch/iOS protocol divergence.
- **Action:** Delete one copy. Add the single file to BOTH targets via Xcode Target Membership (it already conditionally compiles), or move it into MacroMarkKit gated by `#if os(iOS) || os(watchOS)`. Move the watch-side file out of `Storage/` regardless.
- **Severity:** High

### 9.2 Date-format token-replacement logic duplicated 3×
- **Locations:** `MacroMarkKit/Sources/MacroMarkKit/Models/FolderSettings.swift:28-40` (`format(date:)`); `MacroMark/Settings/FolderSettingsView.swift:91-105` (`currentDateExample`); `MacroMark/Settings/FolderSettingsView.swift:107-121` (`formatWithSettings`)
- **What:** All three do the same `Calendar.current.dateComponents` + `replacing("yyyy"/"yy"/"MM"/"dd")`. The two view-local copies differ only in fallback string and a `"Notes/"` prefix. `FolderSettings.format` is imported by the view, so the copies are pure reimplementation — and the kit's version falls back to ISO8601 while the view falls back to a hardcoded literal, so the "example" can disagree with the actual filename (also §5.10).
- **Why:** DRY violation; a format change must be replicated in three spots and they have already diverged.
- **Action:** Delete `currentDateExample` and `formatWithSettings`; call `settings.format(date: Date())` from the view. Build the `"Notes/"` prefix at the call site.
- **Severity:** High

### 9.3 WAL Codable round-trips duplicated 4× in MacroMarkApp
- **Location:** `MacroMark/MacroMarkApp.swift:350-380` (`readPendingProcessing`, `writePendingProcessing`, `readPendingAudio`, `writePendingAudio`)
- **What:** Four functions, each doing the same `[UUID: Codable] ↔ [String: Codable]` JSON round-trip with the same `reduce(into:) { if let id = UUID(uuidString:) ... }` mapping, differing only in key and payload type.
- **Why:** 30+ lines of copy-paste; the mapping is duplicated verbatim.
- **Action:** Extract generic `load<V: Codable>(_:forKey:)` / `save(_:forKey:)` helpers parameterized by key.
- **Severity:** Medium

### 9.4 Magic `UserDefaults` / `@AppStorage` key strings scattered across 6 files
- **Locations:** `"captureMode"` — `MacroManagerView.swift:11`, `ContentView.swift:10`, `WatchConnectivityProvider.swift:128, 240, 241`; `"folderSettings"` — `FolderSettingsView.swift:7, 13`, `iCloudStorageManager.swift:13`; `"customSaveBookmark"` — `MacroManagerView.swift:12`, `iCloudStorageManager.swift:21, 26, 73, 159`; `"autoExportEnabled"` — `MacroManagerView.swift:14`, `MacroMarkApp.swift:272`; `"defaultExportTarget"` — `MacroManagerView.swift:13`, `MacroMarkApp.swift:273`; plus WAL keys `MacroMark_ProcessedNoteIDs`, `MacroMark_PendingProcessing`, `MacroMark_PendingAudioIn`
- **What:** 18+ raw-string uses of these keys across 6 files, no shared constants.
- **Why:** A typo in any key silently breaks a setting or the WAL. No compiler checking or autocompletion.
- **Action:** A single `enum UserDefaultsKey` in MacroMarkKit, used everywhere.
- **Severity:** High

### 9.5 Security-scope access duplicated in iCloudStorageManager
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:71-84` (appendText), `:157-170` (readText)
- **What:** Both methods independently read `customSaveBookmark`, derive `isSecurityScoped`, call `startAccessingSecurityScopedResource()`, and `defer { stopAccessingSecurityScopedResource() }`. Re-derives from UserDefaults on every call rather than caching.
- **Why:** Two near-identical 14-line scopes; any bookmark-handling change must be made twice.
- **Action:** Extract `withSecurityScope<T>(_ block:)` that resolves the bookmark once and wraps start/stop.
- **Severity:** Medium

### 9.6 Default-macros array (23 entries) private to a View
- **Location:** `MacroMark/Settings/MacroManagerView.swift:220-254` (`defaultMacros`)
- **What:** The 23 default `Macro` seeds live as a computed property inside `MacroManagerView`, used by `prepopulateIfNeeded` and `restoreDefaults`.
- **Why:** Business/persistence concern (seed data) coupled to a SwiftUI View; cannot be unit-tested without spinning up the view. AGENTS.md: "Place view logic into view models or similar, so it can be tested."
- **Action:** Move `defaultMacros` into a `DefaultMacros` type (or static on `Macro`) in MacroMarkKit so kit tests can assert on the count and the duplicate `sortOrder: 1` for "Heading Two"/"Heading To".
- **Severity:** Medium

### 9.7 Dead / unused symbols (verified by repo-wide grep)
- **Locations:**
  - `StoreManager.purchaseState` / `isLoadingProducts` / `PurchaseState` enum — `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:5-10, 18-19` — assigned throughout (`:32, 33, 44, 52, 55, 58, 61, 64, 82, 89, 93`) but read by zero consumers; `SubscriptionPaywallView` gates on `products.isEmpty` instead. The `PurchaseState` enum is therefore also dead.
  - `iCloudStorageManager.isUsingFallbackStorage` — `iCloudStorageManager.swift:8` (set `:39, 42`) — never read by any UI; the doc comment says "Published so UI can observe" but none does.
  - `EntitlementManager.customMacroCount(_:)` — `EntitlementManager.swift:83-86` — zero callers; callers use `isEntitled` + manual `>= maxFreeMacros` comparisons instead.
  - `MacroProcessor.invalidateRegexCache()` — `MacroProcessor.swift:16-18` — zero callers (see §5.3 for the resulting correctness bug).
- **Why:** Dead state increases cognitive load. `purchaseState`/`isLoadingProducts`/`PurchaseState` represent a state machine that provides no user feedback. `isUsingFallbackStorage` means users get no warning when iCloud is unavailable.
- **Action:** Either wire these to UI (paywall spinner/error, fallback banner) or remove them. The previously-suspected `EntitlementManager.isInTrial`, `canAddCustomMacro`, and `ProcessedNote.idString` are already removed — confirmed.
- **Severity:** Medium

### 9.8 Files to delete outright
- `test.swift` (repo root) — untracked scratch file, references `WCSession.sendMessage` with the wrong arity, in no target.
- `MacroMarkWidget/MacroMarkWidgetControl.swift` — Xcode "Start Timer" ControlWidget template, hardcoded `let isRunning = true`, no-op `perform()`, unregistered in `MacroMarkWidgetBundle`.
- `MacroMarkWidget/AppIntent.swift` — Xcode "Favorite Emoji" `ConfigurationAppIntent` template, also unregistered.
- **Severity:** Medium (clean up; ~95 LOC removed)

### 9.9 Oversized files
- **`MacroMark/MacroMarkApp.swift:498`** — App entry + ModelContainer bootstrap + WatchConnectivity wiring + WAL accessors + reprocess-on-launch + text pipeline + audio pipeline + background-task wrapper + 4 WAL round-trips + 2 ACK helpers + save/export pipeline + scene body. Propose extracting a `NotePipeline`/`NoteProcessor` service (the processing + ACK + export logic) and a `PendingItemsStore` (the WAL accessors + `pendingAudioDirectory`). Leaves the App struct as bootstrap + scene. Severity: Medium.
- **`MacroMark/Settings/MacroManagerView.swift:326`** — `MacroManagerView` + `AddMacroView` + the 23-entry `defaultMacros`. Extract `AddMacroView` (§8.1) and `defaultMacros` (§9.6). Severity: Medium.
- **`MacroMark/Shared/WatchConnectivityProvider.swift:301`** (×2) — after §9.1 dedup, consider extracting `ContinuationTimeout` to its own file. Severity: Low.

### 9.10 Magic numeric / file-extension constants
- **Locations:** `50.0` (audio chunk duration) `AudioTranscriber.swift:20`; `12000` (sample rate) `AudioRecorder.swift:31`; `1000` (preferredTimescale) `AudioTranscriber.swift:92`; `1.0` (recorder spin-up sleep) `AudioRecorder.swift:43`; `100` ms (dictation present delay) `SystemCaptureView.swift:16`; `10` × `100` ms (WC activation polling) `WatchConnectivityProvider.swift:252-255`; `15` s (WC fetch timeout) `:265`; `20` × `0.1` s (iCloud download wait) `iCloudStorageManager.swift:151`; `200` (min height) `NoteDetailView.swift:12`; `".m4a"` `AudioTranscriber.swift:89`, `MacroMarkApp.swift:207`, `LocalStore.swift:97`; `".md"` `iCloudStorageManager.swift:47`; `"Notes/"` `FolderSettingsView.swift:120`; `"com.macromark.lifetime.keychain"` `EntitlementManager.swift:29`
- **What:** Hardcoded values scattered across files with no named constants.
- **Why:** Magic numbers obscure intent and must be changed in multiple places.
- **Action:** Name each with a `private static let` (or centralize file extensions / durable-directory names in MacroMarkKit).
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make the ACK truly end-to-end.** §5.1 + §5.2 are the same root cause: the pipeline treats "saved to SwiftData" as "delivered," but the user's definition of delivered is "in the `.md` file." Introduce an "exported" WAL state distinct from "processed," and only ACK (and only clear the WAL) once the configured export target succeeds — with bounded retry for the iCloud-deferred case. This is the single highest-leverage change for the user's stated #1 concern.

2. **Lock + invalidate the regex cache together.** §3.1 (race) and §5.3 (staleness) are the same cache. Fix both in one change: move the cache behind a lock (or actor), invalidate it from every macro-mutation site, and credit §7.1's perf win.

3. **Stop blocking cooperative threads on watchOS.** §3.2 (semaphore) and §3.3 (Thread.sleep on MainActor) are both legacy-sync-over-async patterns. The codebase already has the correct idiom (`ContinuationTimeout` actor + `Task.sleep(for:)`); apply it consistently and delete the `DispatchSemaphore`/`Thread.sleep` uses.

4. **Centralize the shared infrastructure in MacroMarkKit.** §9.1 (WatchConnectivityProvider ×2), §9.2 (date format ×3), §9.3 (WAL round-trips ×4), §9.4 (UserDefaults keys ×18), §9.5 (security-scope ×2). A `UserDefaultsKey` enum, a shared `WatchConnectivityProvider`, a generic WAL helper, and a single date formatter would eliminate the largest duplication surfaces and make the library the single source of truth.

5. **Adopt `os.Logger` repo-wide.** §6.3 ships IAP errors and file paths to release stdout today. A subsystem-scoped `Logger` (`com.macromark`) with per-module categories is production-safe, level-filtered, and removes the kit/app `#if DEBUG` asymmetry entirely.

6. **Single entitlement surface.** §9.7's dead `customMacroCount(_:)` and the inline `>= maxFreeMacros` checks in `MacroManagerView` should collapse to one `isEntitled`/`canAddCustomMacro` API on `EntitlementManager`, so the gate logic can't drift between the button, the row, and the paywall.

---

## 11. What was NOT audited

- `.git`, `.build`, `.swiftpm`, `MacroMarkKit/.build`, `MacroMarkKit/.swiftpm` (build artifacts).
- The untracked `test.swift` scratch file at the repo root (flagged for deletion, not audited).
- Test targets `MacroMarkTests/`, `MacroMarkUITests/`, `MacroMark Watch AppTests/`, `MacroMarkKit/Tests/` — quick scan only; no deep coverage review.
- StoreKit 2 product configuration in any `.storekit` files — file structure only, not whether each product matches App Store Connect.
- Algorithmic correctness of the audio chunking / `AVAssetExportSession` pipeline in `AudioTranscriber.splitAudio()` beyond the chunk-failure handling in §5.5.
- Build settings, Xcode project structure, and scheme configuration beyond what's visible in the shared schemes.
- Third-party SPM dependency internals (the project uses only Apple system frameworks — no external packages).
- Localization — the app appears English-only with no string catalogs; not assessed.
- Performance profiling — no Instruments traces captured. §7 findings are static analysis of hot paths, not measurements.
- The `MacroMarkWidget/` target's entitlements file was not opened; verify it matches the App Group identifier (if any) used by the main app. (The widget bundle's kind string `"com.danfakkeldy.macromark.watchkitapp.MacroMarkWidget"` looks unusual because it nests under the watch app identifier — app is "MacroMark", not "watchkitapp" — but this was not deeply investigated.)

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Each Critical / High finding has an exact line range confirmed by opening the cited file during this audit.

- **§3.1** — open `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift`, line `13` (the `nonisolated(unsafe) var regexCache`) and `:37-43` (read + `regexCache[pattern] = compiled` mutation). The `process` doc at `:26-28` states it is non-isolated.
- **§3.2** — open `MacroMark Watch App/Capture/InstantCaptureView.swift`, lines `57-69`. `Task.detached { performExpiringActivity { ... DispatchSemaphore(value: 0) ... semaphore.wait() } }`, with the signal coming from an inner `Task { await ...processAudioFile(...) }` whose body does `MainActor.run { ... }`.
- **§3.3** — open `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift`, line `3` (`@MainActor`), `:92` (`ensureDownloaded(fileURL)` call from `appendText`), and `:151-154` (`for _ in 0..<20 { ... Thread.sleep(forTimeInterval: 0.1) }`).
- **§5.1** — open `MacroMark/MacroMarkApp.swift`, lines `424-433`. `addProcessedNoteID(noteId)` (`:426`), `removePendingAudio/Processing` (`:428`/`:431`), `acknowledgeFileIfDurable`/`acknowledgeNoteIfDurable` (`:429`/`:432`) all execute before the iCloud append at `:442`. The comment at `:435` admits "failures don't undo the ACK."
- **§5.2** — open `iCloudStorageManager.swift`, lines `111-115`. `cloudCopyExistsButNotDownloaded(url)` branch prints and leaves `writeSucceeded = false`; `appendText` returns `false` at `:128`. The caller at `MacroMarkApp.swift:442` uses the return only to gate `note.isExported`, never to re-queue.
- **§5.3** — grep the repo for `invalidateRegexCache`. Only the declaration at `MacroProcessor.swift:16` matches; zero call sites. Then open `MacroManagerView.swift:204-216` (`deleteMacros`/`moveMacros`) and `:265-273` (`restoreDefaults`) — neither calls it.
- **§5.4** — open `MacroManagerView.swift`, lines `265-273`. `for macro in macros { modelContext.delete(macro) }` deletes all macros including custom ones; no `.confirmationDialog` is attached to the button at `:143-145`.
- **§6.3** — open `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift`, lines `65` and `94` (`print("Purchase failed: \(error)")` / `"Restore purchases failed: \(error)"`) and `:77` (`print("Unverified transaction received")`). None are inside `#if DEBUG`.
- **§9.1** — run `diff "MacroMark/Shared/WatchConnectivityProvider.swift" "MacroMark Watch App/Storage/WatchConnectivityProvider.swift"`. Exits 0 (byte-identical, 301 lines each).
- **§9.4** — grep for `"captureMode"`, `"folderSettings"`, `"customSaveBookmark"`, `"autoExportEnabled"`, `"defaultExportTarget"` — each appears as a raw string literal in 2+ files with no shared constant.

If any finding doesn't reproduce when you visit the line, ping with the specific reference and it will be re-investigated.
