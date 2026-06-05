# MacroMark Code Audit

Generated 2026-06-05. Scope: ~42 Swift source files + test files + widget extension across 4 targets (MacroMark iOS, MacroMark Watch App, MacroMarkKit SPM, MacroMarkWidget). `.claude/`, `.build/`, `Pods/`, and `Tests/` directories are excluded. No `Dead/` archive directory exists.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] LocalStore re-sends all pending notes on every call → duplicate entries on iOS** — §5.1 — `MacroMark Watch App/Storage/LocalStore.swift:43-46`. Every new note triggers a full re-transfer of the pending queue; when the iPhone reconnects, the daily note gets repeated content.
2. **[High] UIPasteboard accessed from non-isolated MacroProcessor** — §3.1 — `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:67`. UIKit API called from background thread; undefined behavior in release builds, compile error under Swift 6.
3. **[High] Non-Sendable Macro models passed across actor boundary** — §3.2 — `MacroMark/MacroMarkApp.swift:54-55,119-120`. `[Macro]` fetched on MainActor is passed to non-isolated `process()`; Swift 6 strict concurrency will reject this.
4. **[High] AudioTranscriber recognition task leaks continuation on Task cancellation** — §3.3 — `MacroMark/Engine/AudioTranscriber.swift:27-42`. `SFSpeechRecognitionTask` return value discarded, no `onCancel` handler; produces Swift runtime "leaked continuation" warning.
5. **[High] Duplicate WatchConnectivityProvider source file across targets** — §9.1 — Two identical 212-line files; any fix to one silently misses the other.
6. **[High] sendMessage reply/error handlers violate @MainActor isolation** — §3.4 — `MacroMark/Shared/WatchConnectivityProvider.swift:163-175`. WCSession callbacks run on arbitrary queues but resume a MainActor continuation.
7. **[High] StoreManager finishes transaction before entitlement delivery is confirmed** — §5.4 — `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:71`. Crash between `finish()` and keychain write permanently loses the lifetime unlock.
8. **[High] MacroMarkWidgetControl ships a non-functional timer template** — §8.1 — `MacroMarkWidget/MacroMarkWidgetControl.swift:12-77`. A "Start Timer" control unrelated to dictation, with a typo in the user-facing description.
9. **[High] #if DEBUG paywall bypass has no release-configuration safeguard** — §6.1 — `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:22,48-51,80,88-90,99,108`. If `DEBUG` is defined in any distribution build, all paid features unlock for free.
10. **[High] Duplicate export/processing flow in MacroMarkApp** — §9.3 — `MacroMark/MacroMarkApp.swift:52-105,119-185`. ~60 lines of identical export logic in two closures; already showing signs of divergence.

---

## 2. Quick wins (≤30 min each)

- **Remove `MacroMarkWidgetControl.swift` from the widget target** — `MacroMarkWidget/MacroMarkWidgetControl.swift` — non-functional timer template unrelated to the app. Remove the file and its `AppIntent` registration from `MacroMarkWidgetBundle.swift`.
- **Remove dead `@State private var text` in SystemCaptureView** — `MacroMark Watch App/Capture/SystemCaptureView.swift:5` — set but never read; `finishAndSave` receives the text directly.
- **Remove unused properties** — `EntitlementManager.isInTrial` (line 12), `EntitlementManager.canAddCustomMacro` (line 79), `ProcessedNote.idString` (line 6), `StoreManager.purchaseState` and `isLoadingProducts` (lines 18-19) — all set but never read by any consumer.
- **Fix typo in MacroMarkWidgetControl description** — line 29: `"A an example control that runs a timer."` → remove or fix.
- **Clean up stale developer comment in NoteDetailView** — `MacroMark/Views/NoteDetailView.swift:57-59` — multi-line thinking-out-loud comment that should have been removed before commit.
- **Call `SFSpeechRecognizer.requestAuthorization` once in `MacroMarkApp.init()`** instead of on every `MacroManagerView.onAppear` — avoids redundant no-op calls.
- **Use `AVAudioQuality.high` enum directly** instead of `.rawValue` at `AudioRecorder.swift:33`.
- **Replace hardcoded `"3-macro free limit"` string** in `SubscriptionPaywallView.swift:85` with `"\(EntitlementManager.maxFreeMacros)-macro free limit"`.

---

## 3. Concurrency

### 3.1 UIPasteboard accessed from non-isolated function
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:67`
- **What:** `MacroProcessor.process()` is explicitly documented as NOT actor-isolated (line 11-12), but reads `UIPasteboard.general.string` which requires `@MainActor` in Swift 6.
- **Why:** Accessing UIKit from a background thread is undefined behavior — can crash, return stale data, or trigger Main Thread Checker. Under Swift 6 strict concurrency this is a compile-time error.
- **Action:** Wrap the clipboard read in `await MainActor.run { UIPasteboard.general.string ?? "" }`, or lift the clipboard read to the caller and pass the value as a parameter.
- **Severity:** High

### 3.2 Non-Sendable SwiftData models passed across actor boundary
- **Location:** `MacroMark/MacroMarkApp.swift:54-55,119-120`
- **What:** `[Macro]` arrays fetched on the `@MainActor` via `context.fetch()` are passed to `MacroProcessor.process(text:macros:...)` which runs off the main actor. `Macro` is a `@Model` reference type without `Sendable` conformance.
- **Why:** Swift 6 strict concurrency will emit compile-time errors for passing non-Sendable types across actor isolation boundaries. While the data is read-only in `process()`, the compiler cannot prove this.
- **Action:** Extract the needed values (`trigger`, `replacement`, `notes`) into a Sendable value type (e.g., `struct MacroSnapshot: Sendable`) before crossing the actor boundary, or annotate `process()` as `@MainActor`.
- **Severity:** High

### 3.3 AudioTranscriber recognition task leaks continuation on cancellation
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:27-42`
- **What:** `SFSpeechRecognizer.recognitionTask(with:)` returns an `SFSpeechRecognitionTask` that is discarded at line 29. The enclosing `withCheckedThrowingContinuation` has no `onCancel` handler. If the Swift concurrency `Task` is cancelled, the continuation is never resumed.
- **Why:** Produces "SWIFT TASK CONTINUATION MISUSE: leaked its continuation!" runtime warning. The underlying speech recognition task continues running in the background indefinitely, consuming resources.
- **Action:** Capture the returned `SFSpeechRecognitionTask` and call `.cancel()` on it inside a `withTaskCancellationHandler` or by checking `Task.isCancelled`.
- **Severity:** High

### 3.4 sendMessage reply/error handlers violate @MainActor isolation
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:163-175` (also duplicated in watch counterpart)
- **What:** `WatchConnectivityProvider` is `@MainActor`, but `WCSession.sendMessage` delivers `replyHandler` and `errorHandler` callbacks on arbitrary background queues. Both handlers resume a `CheckedContinuation` created on the main actor.
- **Why:** Resuming a continuation from the wrong executor triggers a Swift runtime warning and risks data races on any captured MainActor-bound state.
- **Action:** Wrap each handler body in `Task { @MainActor in continuation.resume(...) }` or use `MainActor.assumeIsolated` if the handler is guaranteed to return on the main actor.
- **Severity:** High

### 3.5 @unchecked Sendable on iCloudStorageManager suppresses real isolation warnings
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:3`
- **What:** `iCloudStorageManager` is declared `@unchecked Sendable` but its computed properties read mutable state from `UserDefaults` and resolve security-scoped bookmarks without any synchronization. If two callers on different actors invoke `appendText` concurrently, the file writes can interleave.
- **Why:** The `@unchecked` annotation tells the compiler "trust me" but no actual thread safety mechanism exists. Swift 6 strict concurrency would correctly flag the unsynchronized access.
- **Action:** Either add `@MainActor` isolation (all current callers already run on or hop to MainActor) and remove `@unchecked`, or add a private serial `DispatchQueue` for synchronization.
- **Severity:** Medium

### 3.6 Redundant MainActor.run hopping in MacroMarkApp Task blocks
- **Location:** `MacroMark/MacroMarkApp.swift:62-110,128-185`
- **What:** The `onNoteReceived` and `onFileReceived` closures create non-isolated `Task { }` blocks, then scatter `await MainActor.run { ... }` around every SwiftData operation. The entire task body needs main-actor isolation.
- **Why:** Each `await MainActor.run` is an unnecessary suspension-resumption cycle. Code between the `MainActor.run` blocks might inadvertently touch MainActor-bound state.
- **Action:** Change `Task { }` to `Task { @MainActor in }` and remove all inner `await MainActor.run { ... }` wrappers.
- **Severity:** Low

### 3.7 Redundant Task { @MainActor in } wrapping in @MainActor delegate methods
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:83,104,121,138` (also in watch counterpart)
- **What:** The class is annotated `@MainActor`, so its `WCSessionDelegate` methods already execute on MainActor. Yet each method wraps its body in a redundant `Task { @MainActor in }`.
- **Why:** Unnecessary task creation adds overhead; the additional hop delays already-MainActor work by at least one scheduler tick.
- **Action:** Remove the inner `Task { @MainActor in }` wrapping; the class-level `@MainActor` already guarantees isolation.
- **Severity:** Low

### 3.8 NotificationCenter used instead of @Observable observation
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:125` and `MacroMark Watch App/Storage/LocalStore.swift:26`
- **What:** `NotificationCenter` is used to communicate transfer completion between `WatchConnectivityProvider` and `LocalStore`. Both classes are already `@Observable`.
- **Why:** NotificationCenter is stringly-typed, not compile-time checked, and requires manual observer cleanup. A direct method call or `@Observable` published property avoids this.
- **Action:** Replace the NotificationCenter pairing with a direct call from `WatchConnectivityProvider` to `LocalStore.shared.removeNote(withId:)` in the transfer completion handler, or use an `@Observable` published property.
- **Severity:** Low

---

## 4. API modernity

### 4.1 withCheckedContinuation wrapping SFSpeechRecognizer.requestAuthorization
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:7-11`
- **What:** `SFSpeechRecognizer.requestAuthorization` is wrapped in `withCheckedContinuation`. A native async overload `await SFSpeechRecognizer.requestAuthorization()` has been available since iOS 17.
- **Why:** The deployment target is 26.5, so the async overload is guaranteed to exist. The continuation wrapper adds unnecessary boilerplate and risks misuse.
- **Action:** Replace with `let status = await SFSpeechRecognizer.requestAuthorization()`.
- **Severity:** Medium

### 4.2 UIApplication.shared.open completion handler instead of async overload
- **Location:** `MacroMark/MacroMarkApp.swift:92,160` and `MacroMark/Views/NoteDetailView.swift:46`
- **What:** `UIApplication.shared.open(url, options:completionHandler:)` is called with a closure. The async overload `await UIApplication.shared.open(url)` exists since iOS 15.
- **Why:** The closure variant forces extra indentation and manual state management inside the closure; the async variant integrates naturally with the surrounding async flow.
- **Action:** Replace with `let success = await UIApplication.shared.open(url)` in all three locations.
- **Severity:** Low

### 4.3 Dead #available else branch in ContentView
- **Location:** `MacroMark Watch App/ContentView.swift:16,52`
- **What:** `#available(iOS 26, watchOS 11, *)` guards a `GlassEffectContainer` block with a fallback `else` path. The deployment target is 26.5 — the `else` branch is dead code.
- **Why:** Dead code increases maintenance surface and misleads readers into thinking older watchOS versions are supported.
- **Action:** Remove the `#available` / `#else` branches and keep only the `GlassEffectContainer` path.
- **Severity:** Low

### 4.4 beginBackgroundTask legacy pattern
- **Location:** `MacroMark/MacroMarkApp.swift:59,108,125,183`
- **What:** `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)` is used to extend background execution during watch data processing.
- **Why:** While not deprecated, this iOS 7-era API lacks modern integration. For iOS 26.5, `BGProcessingTask` would be more appropriate for the "ProcessNote" / "ProcessAudio" work.
- **Action:** Evaluate `BGProcessingTask` for longer processing work; if keeping `beginBackgroundTask`, ensure all paths call `endBackgroundTask` (currently missing from error paths).
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 LocalStore.syncPendingNotes re-sends all pending notes on every call
- **Location:** `MacroMark Watch App/Storage/LocalStore.swift:43-46`
- **What:** `syncPendingNotes()` iterates ALL `pendingNotes` and calls `transferUserInfo()` for each, every time a new note is added (line 40) or on init (line 25). It does not filter for notes already queued.
- **Why:** When the iPhone is out of range, queued transfers accumulate. When a new note is added, ALL notes (including already-queued ones) are re-sent. When the iPhone reconnects, it receives duplicates, producing repeated text in the daily note.
- **Action:** Track queued note IDs in a `Set<UUID>` and skip notes that have already been transferred. Only remove a note from pending when the transfer completion handler fires.
- **Severity:** High

### 5.2 FileHandle leak on write failure in iCloudStorageManager
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:118-122`
- **What:** When `fileHandle.write(dataToAppend)` throws, execution jumps to the `catch` block at line 123 without calling `fileHandle.closeFile()`.
- **Why:** Each failed write leaks a `FileHandle`, consuming file descriptors. Repeated failures (e.g., disk full) will exhaust the per-process limit, causing all subsequent file I/O to fail.
- **Action:** Add `defer { fileHandle.closeFile() }` immediately after creating the file handle at line 118.
- **Severity:** Medium

### 5.3 Stale security-scoped bookmark never detected or refreshed
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:18-21`
- **What:** `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` stores staleness in `isStale` but never checks the flag. A stale bookmark causes `startAccessingSecurityScopedResource()` to fail silently.
- **Why:** Users who move their iCloud folder after granting access will experience silent write failures with no feedback.
- **Action:** Check `isStale` after resolving; if `true`, recreate the bookmark from a fresh security-scoped URL or prompt the user to re-select the folder.
- **Severity:** Medium

### 5.4 StoreManager finishes transaction before entitlement delivery is confirmed
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:71`
- **What:** `transaction.finish()` is called immediately on verified transactions. `EntitlementManager.refreshEntitlements()` runs separately via `Transaction.updates` stream.
- **Why:** If the app crashes between `finish()` and the keychain persistence of the entitlement, the lifetime purchase is permanently lost — StoreKit has already marked it as delivered. StoreKit best practice is to finish only after entitlement delivery is confirmed.
- **Action:** Move `transaction.finish()` to after `EntitlementManager.persistKeychainFlag()` completes successfully, or call `refreshEntitlements()` synchronously before finishing.
- **Severity:** High

### 5.5 Lifetime unlock not checked in UI entitlement gates
- **Location:** `MacroMark/Settings/MacroManagerView.swift:152` and similar checks throughout
- **What:** The "Add" button checks `!entitlements.isSubscribed` but not `entitlements.hasLifetimeUnlock`. A lifetime unlock user with `isSubscribed == false` (race window before async `refreshEntitlements` completes) sees the paywall.
- **Why:** User who paid for lifetime unlock may be incorrectly paywalled during the window between app launch and entitlement refresh.
- **Action:** Use `!(entitlements.isSubscribed || entitlements.hasLifetimeUnlock)` consistently, or add a single computed property `var isEntitled: Bool` to `EntitlementManager`.
- **Severity:** Medium

### 5.6 iCloud fallback to local documents directory is silent
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:24-32`
- **What:** When `url(forUbiquityContainerIdentifier:)` returns `nil`, the manager silently falls back to `URL.documentsDirectory` (local sandbox). No notification is surfaced to the user.
- **Why:** The user who configured "iCloud Drive" storage has data saved locally without knowing it. If they later sign into iCloud, old data is invisible in the local sandbox while new data goes to iCloud — creating data fragmentation.
- **Action:** Expose the fallback state through a published property so the UI can show a banner ("iCloud unavailable; saving locally"), or attempt periodic reconnection.
- **Severity:** Medium

### 5.7 AudioTranscriber silently drops chunk transcription errors
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:48-50`
- **What:** When a chunk transcription fails, the error is printed and the chunk is skipped. `fullTranscript` accumulates however many chunks completed before the failure, with no indication of data loss.
- **Why:** The user receives a silently truncated transcript. In release builds where `print` is absent, the failure is completely invisible.
- **Action:** Collect chunk errors and either throw a composite error including partial transcript, or attach error metadata to the returned string so the caller can surface it.
- **Severity:** Medium

### 5.8 fatalError in MacroMarkApp.init reachable in production
- **Location:** `MacroMark/MacroMarkApp.swift:36`
- **What:** When both the primary `ModelContainer` init and the in-memory fallback fail, the app calls `fatalError()`, unconditionally crashing on launch.
- **Why:** While unlikely, a launch crash is the worst possible user experience. The app should degrade gracefully — show the `containerError` overlay or use a bare-bones container.
- **Action:** Remove `fatalError`; instead set `containerError` and use a final fallback container configuration. The error overlay already exists (line 195-203) but is only used for the primary init failure.
- **Severity:** Medium

### 5.9 NoteDetailView export runs synchronous file I/O in unstructured Task
- **Location:** `MacroMark/Views/NoteDetailView.swift:56-67`
- **What:** `exportToICloud` creates a `Task` and calls `iCloudStorageManager.shared.appendText(note.text)` which performs synchronous `NSFileCoordinator`-wrapped file I/O inside the task.
- **Why:** Synchronous I/O inside an unstructured `Task` constrains the cooperative thread pool. Errors are not propagated to the UI (no feedback on failure).
- **Action:** Make `appendText` an async method, or explicitly dispatch to a background queue with `Task.detached`. Surface errors to the user via a published error property.
- **Severity:** Low

### 5.10 Default macro insertions don't explicitly save model context
- **Location:** `MacroMark/Settings/MacroManagerView.swift:257-263,265-271`
- **What:** `prepopulateIfNeeded()` and `restoreDefaults()` insert/delete macros without calling `try? modelContext.save()`.
- **Why:** SwiftData auto-saves are periodic. An app termination during the window before auto-save loses the user's default macros or restore action, with no indication of failure.
- **Action:** Call `try? modelContext.save()` after batch mutations; log if the save fails.
- **Severity:** Low

### 5.11 ExportManager ignores URL length limits for long notes
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/ExportManager.swift:6-35`
- **What:** The entire note text is encoded into a URL query string for deep-link export (Drafts, Bear, Obsidian, Day One). Very long dictations can exceed system URL length limits (~8 KB for some schemes).
- **Why:** Long notes will silently fail to export via URL schemes with no user-facing error.
- **Action:** Truncate note text to a safe length (e.g., first 4000 characters) with an ellipsis indicator, or fall back to clipboard export for long notes.
- **Severity:** Low

---

## 6. Security

### 6.1 #if DEBUG paywall bypass has no release-configuration safeguard
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:22,48-51,80,88-90,99,108`
- **What:** Every entitlement check uses `#if DEBUG` to unconditionally return `true`. `init()` sets `isSubscribed = true` inside `#if DEBUG`. `refreshEntitlements()` uses `#if !DEBUG` to prevent overwriting.
- **Why:** If the `DEBUG` flag is defined in any distribution configuration (TestFlight, internal distribution, ad-hoc), all paid features unlock for free with zero StoreKit validation. There is no separate `#if INTERNAL` or `#if STORE_SANDBOX` gate.
- **Action:** Add a separate compilation flag (e.g., `STORE_SANDBOX`) for development bypasses. Audit all build configurations to ensure `DEBUG` is NOT defined in Release or any distribution config. Consider using `EntitlementManager.simulateEntitled` (a runtime flag) instead of compile-time `#if DEBUG`.
- **Severity:** High

### 6.2 Keychain operations block @MainActor in EntitlementManager
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:131,143`
- **What:** `EntitlementManager` is `@MainActor`, but `persistKeychainFlag()` and `checkKeychainFlag()` call synchronous `SecItemAdd` / `SecItemCopyMatching` on the main actor's thread.
- **Why:** Keychain I/O can block for tens of milliseconds, causing UI jank. More importantly, a keychain operation failure blocks the main actor from processing other work.
- **Action:** Move Keychain read/write to a nonisolated helper or a detached background task; call it from the MainActor without blocking.
- **Severity:** Medium

### 6.3 print() calls outside #if DEBUG in library code
- **Location:** 19 `print()` calls across `MacroMarkKit/` and watch app (detailed in §9.4)
- **What:** Library code in MacroMarkKit and the watch app uses `print()` for error logging without `#if DEBUG` guards because the library cannot see the app's compile-time flags.
- **Why:** Release builds log internal errors to stdout. While no PII, bearer tokens, or IAP receipts appear in the logged data, file paths and error descriptions could reveal user-identifiable information.
- **Action:** Replace `print()` with `os_log` (unified logging) in library code, which is production-safe and supports log levels. In app code, wrap `print()` in `#if DEBUG`.
- **Severity:** Low

---

## 7. Performance

### 7.1 NSRegularExpression recompiled per macro per call
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:19-28`
- **What:** `NSRegularExpression(pattern:)` is created for every macro on every call to `process(text:)`. No caching is used.
- **Why:** Regex compilation is CPU-intensive. A user with 22 default macros processing a long dictation creates 22 new `NSRegularExpression` objects per call. Over many calls this is wasteful.
- **Action:** Cache compiled `NSRegularExpression` instances keyed by macro trigger in a dictionary. Invalidate the cache when macros are added, removed, or edited.
- **Severity:** Medium

### 7.2 Duplicate post-processing code between text and audio paths
- **Location:** `MacroMark/MacroMarkApp.swift:52-105` (onNoteReceived) and `:119-185` (onFileReceived)
- **What:** The two closures share ~60 lines of identical export/save logic. Only the first ~15 lines differ (direct text vs. transcription). The `onFileReceived` handler has a `do/catch` around transcription while `onNoteReceived` has no error handling at all — the blocks are already diverging.
- **Why:** Double the maintenance surface; any change to the export flow must be edited in two places. The divergence means bugs fixed in one path may not be fixed in the other.
- **Action:** Extract the shared pipeline into a single `processAndExport(text:timestamp:macros:context:)` method on `MacroMarkApp`.
- **Severity:** Medium

### 7.3 SFSpeechRecognizer.requestAuthorization called on every view appear
- **Location:** `MacroMark/Settings/MacroManagerView.swift:196-198`
- **What:** `SFSpeechRecognizer.requestAuthorization { _ in }` is called on every `.onAppear` of the settings view, even though this API only prompts once per installation.
- **Why:** Subsequent calls are no-ops but the unnecessary API call on every settings visit is wasteful and confusing.
- **Action:** Move the authorization request to `MacroMarkApp.init()` or call it lazily in `AudioTranscriber.transcribe()`.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 MacroMarkWidgetControl is a non-functional timer template
- **Location:** `MacroMarkWidget/MacroMarkWidgetControl.swift:12-77`
- **What:** The control widget displays a "Start Timer" toggle with a `StartTimerIntent`, completely unrelated to macro capture or dictation. The `perform()` method is a no-op. Description reads "A an example control that runs a timer." (typo).
- **Why:** Leftover Xcode template code. If shipped, users see a non-functional "Timer" control in their Control Center / widget gallery with a typo in the description.
- **Action:** Remove the file and its `AppIntent` from `MacroMarkWidgetBundle.swift`, or replace with a relevant MacroMark control (e.g., quick capture).
- **Severity:** High

### 8.2 containerError overlay is never dismissable
- **Location:** `MacroMark/MacroMarkApp.swift:195-203`
- **What:** When ModelContainer init fails and falls back to in-memory storage, a `containerError` banner overlay is shown permanently with no dismiss button or timeout.
- **Why:** The error banner occupies screen space for the entire app session. Once acknowledged, the user cannot hide it.
- **Action:** Add a dismiss button or `onTapGesture` that sets `containerError = nil`.
- **Severity:** Low

### 8.3 MacroMark_Watch_AppApp naming convention violation
- **Location:** `MacroMark Watch App/MacroMarkApp.swift:11`
- **What:** The watch app's main struct is named `MacroMark_Watch_AppApp` — underscores and double "App" violate Swift naming conventions.
- **Why:** Inconsistent with the iOS target's clean `MacroMarkApp` naming. Underscores in type names are non-idiomatic Swift.
- **Action:** Rename to `MacroMarkWatchApp` throughout.
- **Severity:** Low

### 8.4 captureMode uses raw string comparisons
- **Location:** `MacroMark/Settings/MacroManagerView.swift:11,37-43` and `MacroMark Watch App/ContentView.swift:10,113-122`
- **What:** Capture mode is stored and compared as raw strings (`"audio"`, `"system"`) in `@AppStorage` and `switch` statements.
- **Why:** A typo in any string silently breaks functionality with no compiler help.
- **Action:** Define `enum CaptureMode: String, CaseIterable { case audio, system }` in MacroMarkKit and use `.rawValue` for `@AppStorage` storage.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Duplicate WatchConnectivityProvider (212 lines each)
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift` and `MacroMark Watch App/Storage/WatchConnectivityProvider.swift`
- **What:** Two nearly-identical 212-line files compiled into separate targets. The watch copy lives under `Storage/` (misleading — it handles connectivity, not storage).
- **Why:** Any bug fix to WCSession handling must be applied to both files. The copies will inevitably diverge. Every maintainer must discover and remember the duplication.
- **Action:** Move the shared implementation into MacroMarkKit with `#if os(iOS)` / `#if os(watchOS)` conditional compilation for platform-specific code, or add a single source file to both target memberships.
- **Severity:** High

### 9.2 Duplicate date formatting logic (4 copies)
- **Location:**
  - `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:70-92` (`formatDate`)
  - `MacroMarkKit/Sources/MacroMarkKit/Models/FolderSettings.swift:28-40` (`format(date:)`)
  - `MacroMark/Settings/FolderSettingsView.swift:91-105` (`currentDateExample`)
  - `MacroMark/Settings/FolderSettingsView.swift:107-121` (`formatWithSettings`)
- **What:** The same `Calendar.current.dateComponents` + `replacing("yyyy", ...)` / `replacing("MM", ...)` / `replacing("dd", ...)` logic appears in four methods across three files.
- **Why:** A format change or bug fix must be replicated in four spots. Violates DRY.
- **Action:** Use `FolderSettings.format(date:)` as the single source of truth. Remove the duplicate in `iCloudStorageManager` and the two in `FolderSettingsView`.
- **Severity:** High

### 9.3 Magic UserDefaults key strings scattered across files
- **Location:** `"captureMode"` in 2 files, `"folderSettings"` in 2 files, `"customSaveBookmark"` in 2 files, `"autoExportEnabled"` in 2 files, `"defaultExportTarget"` in 2 files
- **What:** Raw string keys for `UserDefaults` and `@AppStorage` are hardcoded with no single constant definition.
- **Why:** A typo in a key name silently degrades functionality with no compiler checking or autocompletion.
- **Action:** Define all keys as `enum UserDefaultsKeys: String { ... }` in MacroMarkKit. Use the enum cases in `@AppStorage` and `UserDefaults` calls.
- **Severity:** Medium

### 9.4 Magic numeric and file-extension constants
- **Location:** Multiple files:
  - `50.0` (audio chunk duration) — `AudioTranscriber.swift:20`
  - `12000` (sample rate) — `AudioRecorder.swift:31`
  - `10` (timeout seconds) — `WatchConnectivityProvider.swift:179`
  - `10` (poll iterations) — `WatchConnectivityProvider.swift:151`
  - `100` (sleep milliseconds) — `WatchConnectivityProvider.swift:153`, `SystemCaptureView.swift:17`
  - `1.0` (sleep after record start) — `AudioRecorder.swift:43`
  - `".m4a"` — `AudioRecorder.swift:27`, `AudioTranscriber.swift:71,77`
  - `".md"` — `iCloudStorageManager.swift:44,46`, `FolderSettingsView.swift:83,85,87`
  - `"Notes/"` — `FolderSettingsView.swift:120`
  - `"com.macromark.lifetime.keychain"` — `EntitlementManager.swift:17`
  - `200` (min height) — `NoteDetailView.swift:12`
- **What:** Hardcoded values scattered across files with no named constants.
- **Why:** Magic numbers obscure intent and must be changed in multiple places.
- **Action:** Name each with a `private static let` constant describing its purpose.
- **Severity:** Low

### 9.5 Unused properties
- **Location:**
  - `EntitlementManager.isInTrial` — `EntitlementManager.swift:12`
  - `EntitlementManager.canAddCustomMacro` — `EntitlementManager.swift:79`
  - `ProcessedNote.idString` — `ProcessedNote.swift:6`
  - `StoreManager.purchaseState` — `StoreManager.swift:18`
  - `StoreManager.isLoadingProducts` — `StoreManager.swift:19`
- **What:** Properties that are set but never read by any consumer code.
- **Why:** Dead code increases cognitive load. `purchaseState` and `isLoadingProducts` represent a state machine that provides no user feedback.
- **Action:** Either wire unused properties to UI elements or remove them.
- **Severity:** Low

### 9.6 Oversized files
- **`MacroMark/Settings/MacroManagerView.swift:325`** — Houses both `MacroManagerView` (273 lines), `AddMacroView` (43 lines), and the 22-item `defaultMacros` array. Extract `AddMacroView` to its own file; consider moving `defaultMacros` to a `MacroProvider` in MacroMarkKit.
- **`MacroMark/MacroMarkApp.swift:209`** — App entry point + ModelContainer setup + two large inline closures. Extract the shared note-processing/export pipeline into a dedicated service type.
- **Severity:** Medium

### 9.7 print() calls outside #if DEBUG
- **Location:** 19 unprotected `print()` calls in `MacroMarkKit/` (3 files, 11 calls), `MacroMark Watch App/` (2 files, 4 calls), `MacroMark/Engine/` (2 files, 2 calls), `MacroMark/Settings/` (1 file, 1 call). 7 additional calls in `MacroMarkApp.swift` and `WatchConnectivityProvider.swift` are properly behind `#if DEBUG`.
- **What:** Release builds log internal errors to stdout.
- **Why:** Noisy in production; file paths in error messages could reveal user-identifiable information.
- **Action:** Wrap in `#if DEBUG` for app code; use `os_log` for library code.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Adopt a single `EntitlementManager.isEntitled` computed property.** Multiple files check `isSubscribed`, `hasLifetimeUnlock`, and `canAddCustomMacro` with inconsistent combinations (§5.5, §6.1). A single `var isEntitled: Bool` would eliminate drift and make the DEBUG bypass check a single point of change.

2. **Extract the note-processing pipeline into a dedicated service.** `MacroMarkApp.swift` has ~60 lines of duplicated export logic (§7.2, §9.6). A `NoteProcessorService` type that takes text + macros + timestamp and handles the full pipeline (macro expansion, SwiftData persistence, iCloud/URL export) would halve the size of `MacroMarkApp` and eliminate the divergence between text and audio paths.

3. **Move shared code into MacroMarkKit.** `WatchConnectivityProvider` is duplicated across targets (§9.1). `LocalStore`'s `CapturedNote` model could live in MacroMarkKit. Date formatting is duplicated 4 times (§9.2). UserDefaults keys are scattered (§9.3). Consolidating these into the shared SPM package would eliminate the duplication surface and make the library the single source of truth.

4. **Add timeout guards on all `withCheckedContinuation` uses.** Three separate continuations (§3.3, §3.4, and `LocationManager`) lack timeout mechanisms. A helper like `withTimeout(seconds:operation:)` applied consistently would prevent permanent hangs if a delegate callback never fires.

5. **Audit DEBUG flag usage in all build configurations.** The `#if DEBUG` paywall bypass (§6.1) is a ticking time bomb for any non-Release distribution. Consider replacing compile-time `#if DEBUG` with a runtime `EntitlementManager.simulateEntitled` flag that can be set via a hidden debug menu or launch argument, making it impossible to leak into distribution builds.

---

## 11. What was NOT audited

- `.claude/` and `.build/` directories (Claude internal + SPM build artifacts).
- Test files under `MacroMarkTests/`, `MacroMarkUITests/`, `MacroMark Watch AppTests/`, and `MacroMarkKit/Tests/` — quick scan only; no deep coverage review.
- The `.claude/worktrees/fix-all-build-errors` directory (embedded worktree snapshot).
- StoreKit 2 product configuration in `.storekit` files — file structure scanned; product IDs and pricing not validated against App Store Connect.
- Algorithmic correctness of the audio chunking / AVAssetExportSession pipeline in `AudioTranscriber.splitAudio()`.
- Build settings, Xcode project structure, and scheme configuration beyond what's visible in shared schemes.
- Third-party SPM dependency internals (the project uses only Apple system frameworks — no external packages).
- Localization — the app appears to be English-only with no string catalogs; not assessed.
- Compiler warnings — build requires Xcode 26 beta (iOS 26.5 deployment target), which was not available in this environment. The concurrency findings in §3 are based on code review rather than compiler diagnostics.
- The `MacroMarkWidget/` target received light coverage. Its entitlements file was not opened; verify it matches the App Group identifier used by the main app.
- Performance profiling — no Instruments traces were captured. The performance findings in §7 are based on static code analysis of hot paths.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Each High-severity finding has an exact line range confirmed by opening the cited file.

- **§3.1** — open `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift`, line 67. `UIPasteboard.general.string` is read inside a function explicitly documented as "NOT isolated to any actor" (line 11-12). No `MainActor.run` wrapper.
- **§3.2** — open `MacroMark/MacroMarkApp.swift`, lines 54-55. `let macros = (try? context.fetch(descriptor)) ?? []` fetches `[Macro]` on the main actor, then passes them to `MacroProcessor.process(text:macros:...)` on line 62 inside a non-isolated `Task`.
- **§3.3** — open `MacroMark/Engine/AudioTranscriber.swift`, lines 27-42. The `recognizer.recognitionTask(with:)` return value at line 29 is discarded; no `onCancel` handler or `withTaskCancellationHandler` wraps the continuation.
- **§3.4** — open `MacroMark/Shared/WatchConnectivityProvider.swift`, lines 163-175. `sendMessage` with `replyHandler` and `errorHandler` closures resume a `CheckedContinuation` without `@MainActor` isolation.
- **§5.1** — open `MacroMark Watch App/Storage/LocalStore.swift`, lines 43-46. `syncPendingNotes()` loops over all `pendingNotes` and calls `transferUserInfo()` for each, called from `addNote()` (line 40) and `init()` (line 25).
- **§5.4** — open `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift`, line 71. `await transaction.finish()` is called before `EntitlementManager` persists the entitlement; verify by tracing the call order in `handleTransaction`.
- **§6.1** — open `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift`, lines 22, 48-51. All `#if DEBUG` blocks that bypass StoreKit verification. Confirm no alternative flag gates non-debug distribution builds.
- **§8.1** — open `MacroMarkWidget/MacroMarkWidgetControl.swift`, lines 29, 45, 73-77. Typo in description, hardcoded `isRunning = true`, no-op `perform()`. Unrelated to dictation functionality.
- **§9.1** — compare `MacroMark/Shared/WatchConnectivityProvider.swift` (212 lines) and `MacroMark Watch App/Storage/WatchConnectivityProvider.swift` (212 lines). Near-identical content; the only differences are `print` message wording.
- **§9.2** — open `MacroMarkKit/Sources/MacroMarkKit/Models/FolderSettings.swift:28-40`. The `format(date:)` method contains the canonical date-format logic. Then open `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:70-92` — the same logic reimplemented under a different method name.
