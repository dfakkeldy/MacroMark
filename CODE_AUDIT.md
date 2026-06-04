# MacroMark Code Audit

Generated 2026-06-03. Scope: ~40 Swift files across 5 targets (MacroMark iOS, MacroMark Watch App, MacroMarkWidgetExtension, MacroMarkKit SPM package, and test targets). No excluded directories.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[Critical] Stored `CheckedContinuation` overwrite in LocationManager causes hangs and crashes** — §5.1 — `MacroMark Watch App/Capture/LocationManager.swift:11-12,33-36`. Concurrent calls silently leak continuations; leaked continuations crash at dealloc.
2. **[Critical] `fatalError` on ModelContainer init prevents any graceful recovery** — §5.2 — `MacroMark/MacroMarkApp.swift:23`. Corrupted SwiftData store → hard crash at launch with no user recovery path.
3. **[High] Fire-and-forget Tasks in StoreKit managers with no cancellation** — §3.1 — `StoreManager.swift:31-36`, `EntitlementManager.swift:21-27`. Orphaned transaction-listener Tasks run for process lifetime with no cancellation.
4. **[High] EntitlementManager.updateEntitlements() is fire-and-forget, causing stale-state reads** — §3.2 — `EntitlementManager.swift:29-33`. Paywall calls `updateEntitlements()` then synchronously reads `isSubscribed` before the async refresh completes.
5. **[High] CPU-bound work annotated `@MainActor` blocks UI thread** — §3.3 — `MacroProcessor.swift:10-11`, `MacroMarkApp.swift:39-43,52-63`. Regex processing, file I/O, and audio transcription all run on the main actor.
6. **[High] Synchronous file I/O on main actor in iCloudStorageManager** — §3.4 — `iCloudStorageManager.swift:94-137,139-166`. Can cause UI hangs during iCloud document coordination.
7. **[High] Note text, UUIDs, and file URLs logged to console in release builds** — §6.1 — 23 `print()` calls across 7 files, several logging PII. Captured by sysdiagnose and crash reporters.
8. **[High] SWIFT_VERSION = 5.0 despite iOS 26.5 target** — §4.1 — `project.pbxproj:738`. Concurrency checking runs in minimal mode; Swift 6 errors are only warnings. Inconsistent with MacroMarkKit's swift-tools-version 6.2.
9. **[High] Audio session never deactivated after recording stops** — §5.4 — `AudioRecorder.swift:57-61`. Blocks other audio on watch after recording.
10. **[High] Paywall does not auto-dismiss after successful purchase** — §5.3 — `SubscriptionPaywallView.swift:37-41`. Entitlement state is checked synchronously before the async refresh completes.

---

## 2. Quick wins (≤30 min each)

- **Delete three stub files from MacroMark target.** — `MacroMark/Models/Macro.swift`, `MacroMark/Engine/MacroProcessor.swift`, `MacroMark/Storage/iCloudStorageManager.swift`. Each contains only a migration comment; they're dead compilation units.
- **Delete `ContentView.swift` from iOS target.** — `MacroMark/ContentView.swift:1-24`. Unused Xcode template ("Hello, world!") — the app routes directly to `MacroManagerView`.
- **Replace `SFSpeechRecognizer.requestAuthorization { _ in }` with async overload.** — `MacroMark/Settings/MacroManagerView.swift:177`. iOS 17+ async variant is available (deployment target is 26.5).
- **Replace `SFSpeechRecognizer.requestAuthorization` callback with async overload in AudioTranscriber.** — `MacroMark/Engine/AudioTranscriber.swift:6-11`. Same — direct `await` is available.
- **Replace `.foregroundColor` with `.foregroundStyle` in InstantCaptureView.** — `MacroMark Watch App/Capture/InstantCaptureView.swift:14`. Deprecated since iOS 15.
- **Fix navigation title mismatch in SystemCaptureView.** — `MacroMark Watch App/Capture/SystemCaptureView.swift:13`. Shows "System" but the picker calls it "Standard (Dictation)".
- **Remove `@Observable` from LocationManager.** — `MacroMark Watch App/Capture/LocationManager.swift:6`. No properties are observed by SwiftUI — the annotation is unused.
- **Extract `maxFreeMacros = 3` into a named constant.** — `EntitlementManager.swift:81`, `MacroManagerView.swift:116,132`. Three separate hardcoded `3` literals.
- **Add `.textSelection(.enabled)` to DailyLogView.** — `MacroMark Watch App/Capture/DailyLogView.swift:14`. Users can't copy log content.

---

## 3. Concurrency

### 3.1 Fire-and-forget Tasks in StoreKit managers with no cancellation
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:31-36`, `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:21-27`
- **What:** Both `StoreManager.init()` and `EntitlementManager.init()` spawn unstructured `Task { for await result in Transaction.updates { ... } }` with no stored reference and no cancellation. The Tasks iterate infinite async sequences for the process lifetime.
- **Why:** If the manager is ever re-created (tests, SwiftUI previews), multiple listener Tasks accumulate. The EntitlementManager Task also calls `@MainActor` methods from a non-main-actor context without explicit isolation. If the `Transaction.updates` stream throws, the listener dies silently and subscription status becomes stale until app restart.
- **Action:** Store each Task as a `private var updatesTask: Task<Void, Never>?` property; cancel in `deinit`. Add retry-with-backoff inside the loop. Ensure the EntitlementManager Task runs on `@MainActor`.
- **Severity:** High

### 3.2 EntitlementManager.updateEntitlements() is fire-and-forget, causing stale-state reads
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:29-33`
- **What:** `updateEntitlements()` spawns `Task { await refreshEntitlements() }` and returns immediately. Callers then synchronously check `entitlements.isSubscribed` and read the pre-refresh value.
- **Why:** `SubscriptionPaywallView` line 38 calls `entitlements.updateEntitlements()` then checks `entitlements.isSubscribed` on line 39 — the async refresh hasn't executed yet, so the paywall never auto-dismisses. `MacroMarkApp.init()` line 27-29 has the same pattern for StoreKit product loading (the product list may be empty when the first view appears).
- **Action:** Either make `updateEntitlements()` an `async` method that directly calls `await refreshEntitlements()`, or return the Task so callers can `await` it. Apply the same pattern to `StoreManager.loadProducts()`.
- **Severity:** High

### 3.3 CPU-bound work annotated `@MainActor` blocks UI thread
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:10-11`, `MacroMark/MacroMarkApp.swift:39-43,52-63`
- **What:** `MacroProcessor.process()` is `@MainActor` but does regex compilation, string replacement, and reverse-geocoding — all CPU/IO work. `MacroMarkApp` wraps both `onNoteReceived` and `onFileReceived` pipelines in `Task { @MainActor in }`, forcing transcription, macro processing, and synchronous file I/O onto the main actor.
- **Why:** For large text bodies or many macros, the main thread is blocked during processing. The reverse-geocoding call at `MacroProcessor.swift:67` (`request.mapItems`) is a network call that blocks the main actor. Combined with `iCloudStorageManager` synchronous I/O (§3.4), this causes visible UI hangs.
- **Action:** Remove `@MainActor` from `MacroProcessor.process()`. Remove `@MainActor` from the `Task` closures in `MacroMarkApp`. Only hop to the main actor when updating UI state (none of the current closure bodies touch UI).
- **Severity:** High

### 3.4 Synchronous file I/O on main actor in iCloudStorageManager
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:94-137,139-166`
- **What:** `appendText(_:)` and `readText(_:)` perform synchronous `NSFileCoordinator` coordination, `FileHandle` writes, and `String(contentsOf:)` reads. These are called from `@MainActor` contexts in `MacroMarkApp` and `WatchConnectivityProvider`.
- **Why:** iCloud document coordination can block for seconds. On the main actor, this freezes the UI — especially problematic during app launch when the watch syncs pending notes.
- **Action:** Make these methods `async` and bridge the `NSFileCoordinator` callbacks with `withCheckedContinuation` so the I/O runs off the main actor. Cache a single `NSFileCoordinator` instance instead of allocating one per call.
- **Severity:** High

### 3.5 iCloudStorageManager has no actor isolation
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:3-167`
- **What:** `iCloudStorageManager` is a plain `final class` singleton accessed from `@MainActor` contexts (WatchConnectivityProvider, MacroMarkApp) and potentially from background tasks. It has no `@MainActor`, no `actor` isolation, and no Sendable conformance.
- **Why:** Without isolation, concurrent access to `folderSettings` (computed from `UserDefaults`), bookmark resolution, and file coordination is data-race unsafe. The `baseDirectoryURL` computed property re-resolves the security-scoped bookmark on every access, creating a new URL that may not match the one used for `startAccessingSecurityScopedResource`.
- **Action:** Mark the entire class `@MainActor` (all current callers are main-actor-bound), or convert to an `actor`. At minimum, resolve the bookmark once per method and pass the resolved URL through rather than re-resolving in `fileURL(for:)`.
- **Severity:** High

### 3.6 LocalStore NotificationCenter closure produces Swift 6 warning
- **Location:** `MacroMark Watch App/Storage/LocalStore.swift:28-34`
- **What:** Compiler warning: "reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode." The `[weak self]` capture inside a `NotificationCenter` closure is then accessed inside a `Task { @MainActor in }`.
- **Why:** This will become a hard error under Swift 6. Since `LocalStore` is `@MainActor` and the notification is delivered on `.main` queue, the `Task` wrapper is unnecessary — the ambient main-actor context already provides isolation.
- **Action:** Remove the `Task { @MainActor in }` wrapper and call `self?.removeNote(withId: id)` directly in the notification closure.
- **Severity:** High

### 3.7 Missing `@preconcurrency` imports for frameworks with incomplete Sendable annotations
- **Location:** All files importing `WatchConnectivity`, `AVFoundation`, `Speech`, `StoreKit`, `CoreLocation`
- **What:** None of the source files use `@preconcurrency import` for frameworks known to have incomplete Sendable annotations.
- **Why:** When the project migrates to Swift 6 (see §4.1), every import of these frameworks will trigger strict-concurrency errors for types not yet annotated as Sendable.
- **Action:** Add `@preconcurrency import` to all imports of `WatchConnectivity`, `AVFoundation`, `Speech`, `StoreKit`, and `CoreLocation`.
- **Severity:** Medium

### 3.8 `withCheckedContinuation` in fetchDailyFile may hang indefinitely
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:177-188`
- **What:** `WCSession.sendMessage` is bridged via `withCheckedThrowingContinuation`. Under rapid-disconnect edge cases, neither the reply handler nor error handler fires, leaving the continuation unresolved.
- **Why:** The continuation hangs forever; the runtime emits a warning when the continuation is deallocated without resume, but the Task leaks.
- **Action:** Add a timeout using `Task.sleep` with `withThrowingTaskGroup` to race the sendMessage against a deadline.
- **Severity:** Medium

### 3.9 `withCheckedContinuation` for SFSpeechRecognizer — async overload available
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:6-11`
- **What:** `SFSpeechRecognizer.requestAuthorization` is invoked with a callback inside `withCheckedContinuation`. The async variant `SFSpeechRecognizer.requestAuthorization()` (iOS 17+) is available.
- **Why:** Deployment target is iOS 26.5 — unnecessary continuation boilerplate.
- **Action:** Replace with `let status = await SFSpeechRecognizer.requestAuthorization()`.
- **Severity:** Low

---

## 4. API modernity

### 4.1 SWIFT_VERSION = 5.0 — should be 6.0
- **Location:** `MacroMark.xcodeproj/project.pbxproj` (all targets)
- **What:** The Xcode project sets `SWIFT_VERSION = 5.0` while the SPM Package.swift uses `swift-tools-version: 6.2`. Deployment targets are iOS 26.5 and watchOS 26.5.
- **Why:** Swift 5 language mode means the compiler only emits warnings for concurrency violations, not errors. No `SWIFT_STRICT_CONCURRENCY` build setting is configured. The SPM package compiles under Swift 6, creating an inconsistency where the same source file has different checking levels depending on the target.
- **Action:** Bump `SWIFT_VERSION` to 6.0 project-wide. Set `SWIFT_STRICT_CONCURRENCY` to `complete` after fixing §3.1–§3.6.
- **Severity:** High

### 4.2 watchOS deployment target mismatch between Xcode and Package.swift
- **Location:** `MacroMarkKit/Package.swift:10` vs `MacroMark.xcodeproj/project.pbxproj`
- **What:** Package.swift declares `.watchOS("11.0")`; the Xcode project sets `WATCHOS_DEPLOYMENT_TARGET = 26.5`.
- **Why:** The massive discrepancy (11 vs 26) suggests a configuration error. While API-availability wise this is safe (11.0 APIs are available at 26.5), it should be intentional and documented.
- **Action:** Verify the intended watchOS deployment target with the project maintainer and align both configurations.
- **Severity:** Low

### 4.3 `WKExtension.shared().visibleInterfaceController?.presentTextInputController` — fragile pattern
- **Location:** `MacroMark Watch App/Capture/SystemCaptureView.swift:23-35`
- **What:** Dictation is triggered via the legacy `WKExtension` completion-handler API rather than a SwiftUI-native approach.
- **Why:** This pattern assumes the visible interface controller is correct for presentation, which is not guaranteed in all navigation states. It bypasses the SwiftUI presentation hierarchy.
- **Action:** Investigate whether watchOS 26 offers a SwiftUI-native dictation/text input API. If not, bridge with `withCheckedContinuation` to move result handling out of the callback closure.
- **Severity:** Medium

### 4.4 `UIPasteboard.general` — consider PasteButton for user-initiated paste
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:53`
- **What:** `{clipboard}` variable reads `UIPasteboard.general.string` programmatically.
- **Why:** iOS 16+ prefers `PasteButton` for user-initiated paste to avoid the paste permission prompt. However, `MacroProcessor` reads clipboard programmatically as a macro expansion, which is a valid use case for `UIPasteboard`. No change needed — just document why the older API is used.
- **Severity:** Low (informational)

---

## 5. Bugs / logic errors

### 5.1 Stored `CheckedContinuation` overwrite in LocationManager causes hangs and crashes
- **Location:** `MacroMark Watch App/Capture/LocationManager.swift:11-12,33-36`
- **What:** `activeContinuation` is a single mutable instance property. If `getCurrentLocation()` is called twice before the first `CLLocationManagerDelegate` callback fires, the first continuation is silently overwritten at line 34 and never resumed. The same pattern exists for `authContinuation` at lines 22-25.
- **Why:** Leaked continuations produce a runtime warning, then crash when deallocated without resume. This triggers on any rapid double-tap of the capture button, or if the user backgrounds and re-opens the app quickly. The auth continuation is also vulnerable to `locationManagerDidChangeAuthorization` firing multiple times (e.g., user toggles location permission in Settings, then returns).
- **Action:** Guard against re-entrant calls by checking `activeContinuation == nil` at the top of `getCurrentLocation()` and returning/throwing if a request is already in flight. Alternatively, cancel the prior request and replace. Consider replacing the stored-continuation pattern with `AsyncStream` or the modern async `CLLocationUpdate` APIs.
- **Severity:** Critical

### 5.2 `fatalError` on ModelContainer init prevents graceful recovery
- **Location:** `MacroMark/MacroMarkApp.swift:23`
- **What:** `fatalError("Could not initialize ModelContainer")` crashes the app unconditionally if SwiftData container initialization fails.
- **Why:** A corrupted store, unhandled schema migration, or filesystem error causes a hard crash at launch with no error screen and no user-facing recovery path. On iOS 18+, SwiftData can throw during `ModelContainer(for:)` for schema mismatches.
- **Action:** Replace `fatalError` with a `do/catch` that sets an error-state flag shown in the root view. Provide a "Reset Data" option or contact-support prompt.
- **Severity:** Critical

### 5.3 Paywall does not auto-dismiss after successful purchase
- **Location:** `MacroMark/Settings/SubscriptionPaywallView.swift:37-41`
- **What:** After `storeManager.purchase(product)` and `entitlements.updateEntitlements()`, line 39 checks `entitlements.isSubscribed` synchronously — but `updateEntitlements()` fires an async Task (§3.2) that hasn't executed yet. The check always reads the pre-purchase value.
- **Why:** Users who successfully pay must manually tap "Maybe Later" to dismiss the paywall. The purchase succeeds, money is taken, but the paywall stays visible. This is a broken UX for paying users.
- **Action:** See §3.2 — make `updateEntitlements()` properly awaitable, then `await entitlements.refreshEntitlements()` before checking `isSubscribed`.
- **Severity:** High

### 5.4 Audio session never deactivated after recording stops
- **Location:** `MacroMark Watch App/Capture/AudioRecorder.swift:57-61`
- **What:** `startRecording()` calls `session.setActive(true)` at line 24. `stopRecording()` never calls `session.setActive(false)`.
- **Why:** After recording, the watch audio session remains active, preventing other audio (alarms, phone calls, other apps) from playing or recording. The system may eventually reclaim the session, but behavior is unpredictable.
- **Action:** Add `try? AVAudioSession.sharedInstance().setActive(false)` in `stopRecording()` and in the `onDisappear` cleanup path of `InstantCaptureView.swift:50`.
- **Severity:** High

### 5.5 Location never fetched on watchOS system capture — `{location}` always resolves to "Unknown Location"
- **Location:** `MacroMark Watch App/Capture/SystemCaptureView.swift:42-46`
- **What:** `if text.contains("{location}")` checks the raw dictation text for the literal string. Dictation never produces curly braces, but macro-triggered expansions like a "Dropoff" trigger (→ `{location} - `) will need location. This check always fails for macro-generated `{location}` tokens since the raw text is replaced by triggers before location is needed.
- **Why:** System Capture notes that use the `{location}` variable always produce "Unknown Location" even with location permission granted. Instant Capture (audio) always fetches location unconditionally — the inconsistency is a real data-quality bug.
- **Action:** Either always fetch location for system capture (matching InstantCaptureView behavior), or move the location-fetch decision to the iOS macro-processing side where the need is actually known.
- **Severity:** High

### 5.6 Chunk transcription errors silently produce partial results
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:48-50`
- **What:** Within the chunk-transcription loop, `catch { print("Failed to transcribe chunk: \(error)") }` swallows the error and continues to the next chunk. The caller gets a truncated transcript with no indication of failure.
- **Why:** A long recording with one corrupt segment produces a silently truncated transcript. The user trusts the output is complete but it may be missing content.
- **Action:** Track whether any chunk failed and either append a placeholder like `[...transcription lost...]`, or throw if any chunk fails. At minimum, propagate partial-failure information alongside the transcript.
- **Severity:** High

### 5.7 `restorePurchases` sets `.purchased` state even when no transactions exist
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:86-95`
- **What:** After `AppStore.sync()` (which returns `Void` and succeeds even with no purchases), `purchaseState` is unconditionally set to `.purchased`. A user who never bought anything could briefly see "purchased" UI state.
- **Why:** `AppStore.sync()` succeeds for users with zero purchases. The "purchased" visual state (green checkmark) is misleading. The actual entitlement check would still return false, but the visual state is wrong.
- **Action:** After `AppStore.sync()`, call `EntitlementManager.refreshEntitlements()` and only set `purchaseState = .purchased` if `isSubscribed` or `hasLifetimeUnlock` is now true.
- **Severity:** Medium

### 5.8 `CapturedNote` notes can be duplicated when sync retriggers before delivery completes
- **Location:** `MacroMark Watch App/Storage/LocalStore.swift:43-49`
- **What:** `addNote` appends to `pendingNotes` then calls `syncPendingNotes()` which iterates ALL pending notes and resends them. Until `noteTransferDidComplete` fires, every new `addNote` retransmits the entire queue.
- **Why:** A slow connection or offline period causes duplicate deliveries. Each `addNote` resends every queued note.
- **Action:** Track per-note send state (`isQueued` flag) so `syncPendingNotes` only sends notes not yet transmitted. Separate sent-but-unconfirmed notes from unsent notes.
- **Severity:** Medium

### 5.9 `PurchaseState.Equatable` treats all `.failed` cases as equal
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:15`
- **What:** Manual `Equatable` conformance matches `case (.failed, .failed): return true` without comparing the associated `Error` values.
- **Why:** `failed(URLError.timedOut)` equals `failed(StoreProductError.invalidProduct)`. This breaks expected `Equatable` semantics and can cause SwiftUI to skip necessary view updates when the error type changes.
- **Action:** Either avoid making `PurchaseState` Equatable, or compare error `localizedDescription`s as a best-effort approach.
- **Severity:** Medium

### 5.10 `EntitlementManager.checkLifetimePurchase()` is a circular no-op
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:67-71`
- **What:** `checkLifetimePurchase()` simply returns `hasLifetimeUnlock` — the same in-memory flag set by a prior refresh. It never queries StoreKit directly.
- **Why:** The method name implies a StoreKit check, but it's circular. Called from `init()` line 24 as `checkLifetimePurchase()` but the return value is unused — it's a dead call.
- **Action:** Either remove the method entirely, or make it actually query `Transaction.currentEntitlements` for lifetime purchase status.
- **Severity:** Medium

### 5.11 No validation for duplicate trigger names in AddMacroView
- **Location:** `MacroMark/Settings/MacroManagerView.swift:283-287`
- **What:** `AddMacroView.save` inserts a new `Macro` without checking if `trigger` already exists.
- **Why:** Users can create duplicate triggers. At processing time, the first macro by sort order wins, but the duplicate is confusing and wastes a macro slot for free-tier users.
- **Action:** Query existing macros for a matching trigger before saving and show a warning.
- **Severity:** Low

### 5.12 `restoreDefaults()` discards creation dates
- **Location:** `MacroMark/Settings/MacroManagerView.swift:243-249`
- **What:** `restoreDefaults()` deletes all existing `Macro` objects then inserts new ones. The `createdAt` property is initialized to `Date()` in `Macro.init`, so all restored macros get the current timestamp.
- **Why:** After restore, all macros appear to have been created "now" — cosmetic but discards history for any timeline view sorted by `createdAt`.
- **Action:** Preserve `createdAt` for default macros being restored, or annotate restored macros with a flag.
- **Severity:** Low

### 5.13 `prepopulateIfNeeded` uses `macros.isEmpty` before `@Query` may be populated
- **Location:** `MacroMark/Settings/MacroManagerView.swift:235-241`
- **What:** The `@Query` list may not be populated on the first `onAppear`. Checking `macros.isEmpty` risks a false-positive empty read and duplicate insertion.
- **Why:** In practice, SwiftData `@Query` populates before the first render pass, so this is unlikely to trigger. But a future SwiftData timing change could cause double-insertion.
- **Action:** Add a `private var didPrepopulate = false` flag set to `true` after the first attempt.
- **Severity:** Low

### 5.14 Hardcoded date `"2026-06-03"` fallback in FolderSettingsView
- **Location:** `MacroMark/Settings/FolderSettingsView.swift:96`
- **What:** If `Calendar.current.dateComponents` fails, the fallback is a literal `"2026-06-03"` string.
- **Why:** The date is baked into source code and will appear stale in future years. Should compute dynamically.
- **Action:** Replace with a dynamically-formatted fallback from `Date()`.
- **Severity:** Low

---

## 6. Security

### 6.1 Note text, UUIDs, and file URLs logged to console in release builds
- **Location:** 23 `print()` calls across 7 files:
  - `MacroMark/MacroMarkApp.swift:33` — full note text
  - `MacroMark/Shared/WatchConnectivityProvider.swift:73,93,114` — note UUIDs and full note text
  - `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:124,130,135,162` — iCloud file paths and errors
  - `MacroMark Watch App/Storage/LocalStore.swift:61,70` — pending-notes save/load errors
  - `MacroMark/Engine/AudioTranscriber.swift:49` — transcription errors
  - `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift:47,73,82,94` — purchase errors
  - `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:28,82,101` — regex/geocoding errors
- **What:** All 23 `print()` calls are emitted unconditionally in Release builds. Several log user note text, UUID identifiers, audio file URLs, and iCloud document paths.
- **Why:** stdout is captured by device crash reporters (MetricKit, Crashlytics) and sysdiagnose logs. User note content in these logs constitutes a PII leak. UUIDs and file paths are device-identifying.
- **Action:** Wrap every `print()` in `#if DEBUG`. Better: replace with `os_log` using `%{private}@` format specifiers for sensitive values. Prioritize the 10 calls that log user content or identifiers.
- **Severity:** High

### 6.2 Security-scoped bookmark resolution creates mismatch between access grant and file operation
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:16-22,94-107`
- **What:** `baseDirectoryURL` is a computed property that re-resolves `customSaveBookmark` each time. In `appendText`, one resolution is used for `startAccessingSecurityScopedResource`, while `fileURL(for:)` accesses `self.baseDirectoryURL` again, potentially resolving to a different URL.
- **Why:** If bookmark resolution is not perfectly deterministic after filesystem changes, `startAccessingSecurityScopedResource()` grants access to URL_A but file I/O uses URL_B — causing sandbox violations or file-access failures.
- **Action:** Resolve the bookmark once per method call and pass that URL through to `fileURL(for:)` as a parameter.
- **Severity:** Medium

### 6.3 `SubscriptionPaywallView` uses `introOffer.period.debugDescription` in UI
- **Location:** `MacroMark/Settings/SubscriptionPaywallView.swift:96`
- **What:** `introOffer.period.debugDescription` is used in user-facing text. `debugDescription` is for debugging, not UI.
- **Why:** The output format is not guaranteed to be user-friendly or localized. On some OS versions it may show internal type descriptions.
- **Action:** Use the `Product.SubscriptionPeriod` formatting APIs or the `localizedDescription` extension already defined in the same file (line 143) for the period unit.
- **Severity:** Medium

---

## 7. Performance

### 7.1 `String.replacing()` creates O(n*m) intermediate copies per macro pass
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:15-30,38-41,57,87,94`
- **What:** Each macro iteration compiles an `NSRegularExpression` and calls `stringByReplacingMatches` which creates a new String. Each `{date}`, `{time}`, `{newline}`, `{tab}` variable replacement calls `replacing(_:with:)` creating another copy. The wrapping-tag regex creates yet another copy.
- **Why:** For large text bodies with many macros, this creates measurable memory churn. Combined with main-actor execution (§3.3), it causes UI hangs.
- **Action:** Pre-compile regex patterns once (cache them). Use mutating `replace(_:with:)` on a `var` String instead of copying `replacing(_:with:)`, or use `NSMutableString` for in-place replacement.
- **Severity:** Medium

### 7.2 `NSFileCoordinator` re-allocated per call
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:116,158`
- **What:** `NSFileCoordinator()` creates a new instance on every `appendText` and `readText` call.
- **Why:** `NSFileCoordinator` is intended to be long-lived for proper queue-based file coordination. Repeated allocation adds overhead per call.
- **Action:** Store a single `NSFileCoordinator` instance as a lazy property.
- **Severity:** Medium

### 7.3 `{time}` variable hardcodes 24-hour format ignoring user locale
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:36`
- **What:** `date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))` forces 24-hour time regardless of device region.
- **Why:** Users in 12-hour regions (US, Canada, Australia) get "14:30" instead of "2:30 PM", contradicting their system preferences.
- **Action:** Use `date.formatted(date: .omitted, time: .shortened)` which respects locale, or add a 12h/24h user preference.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 Deprecated `.foregroundColor` instead of `.foregroundStyle`
- **Location:** `MacroMark Watch App/Capture/InstantCaptureView.swift:14`
- **What:** `.foregroundColor(recorder.isRecording ? .red : .gray)` uses the deprecated modifier.
- **Why:** `foregroundColor` was superseded by `foregroundStyle` in iOS 15. The app targets iOS 26.5.
- **Action:** Replace with `.foregroundStyle(recorder.isRecording ? .red : .gray)`.
- **Severity:** Low

### 8.2 `MacroManagerView` contains two top-level View types — should be split
- **Location:** `MacroMark/Settings/MacroManagerView.swift:1-298`
- **What:** The file contains `MacroManagerView` (lines 7-251), `AddMacroView` (lines 255-292), an `enum PaywallReason`, and a `#Preview`. At 298 lines with two full view definitions.
- **Why:** Convention is one primary type per file. `AddMacroView` at 43 lines is substantial enough to warrant its own file.
- **Action:** Extract `AddMacroView` into `MacroMark/Settings/AddMacroView.swift`.
- **Severity:** Low

### 8.3 `SubscriptionPaywallView` contains `ProductCardView` and `SubscriptionPeriodUnit` extension
- **Location:** `MacroMark/Settings/SubscriptionPaywallView.swift:104-152`
- **What:** Two additional top-level types in the same file as the paywall.
- **Why:** Same as §8.2 — one-type-per-file convention.
- **Action:** Extract `ProductCardView` into a separate file if the paywall grows.
- **Severity:** Low

### 8.4 Navigation title "System" doesn't match user-facing label "Standard (Dictation)"
- **Location:** `MacroMark Watch App/Capture/SystemCaptureView.swift:13`
- **What:** `.navigationTitle("System")` while the watch home screen picker says "Standard (Dictation)".
- **Why:** Inconsistent naming confuses users switching between the picker and the capture screen.
- **Action:** Change to `.navigationTitle("Dictation")` or `"Standard"`.
- **Severity:** Low

### 8.5 No `.textSelection(.enabled)` on log content
- **Location:** `MacroMark Watch App/Capture/DailyLogView.swift:14`
- **What:** `Text(logContent)` renders the daily log without text selection support.
- **Why:** Users can't select and copy content from the daily log on watchOS.
- **Action:** Add `.textSelection(.enabled)` (available watchOS 10+).
- **Severity:** Low

### 8.6 Hardcoded widget URL schemes — fragile to rebranding
- **Location:** `MacroMarkWidget/MacroMarkWidget.swift:14,24`
- **What:** `URL(string: "macromark://capture/instant")` and `"macromark://capture/system"` are hardcoded strings.
- **Why:** If the URL scheme changes, widgets silently become no-ops with no compile-time check.
- **Action:** Define URL scheme constants in MacroMarkKit and reference them from both the widget and the watch `onOpenURL` handler.
- **Severity:** Low

### 8.7 `MacroMarkWidgetControl` contains placeholder Timer code unrelated to MacroMark
- **Location:** `MacroMarkWidget/MacroMarkWidgetControl.swift:1-78`
- **What:** The control widget implements "Start Timer" toggle, `TimerConfiguration`, and `StartTimerIntent` — completely unrelated to the app's note-capture functionality.
- **Why:** This appears to be Xcode template boilerplate that was never customized. Users see a "Start Timer" control widget that has no connection to MacroMark.
- **Action:** Replace with a MacroMark-relevant control (e.g., quick-capture button, or a toggle for capture mode).
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Files to delete outright
- **Location:** `MacroMark/Models/Macro.swift`, `MacroMark/Engine/MacroProcessor.swift`, `MacroMark/Storage/iCloudStorageManager.swift`
- **What:** Three files containing only migration comments ("X is now defined in MacroMarkKit"). They are dead compilation units.
- **Action:** Remove from the MacroMark target in Xcode and delete from disk.
- **Severity:** High

### 9.2 Unused `ContentView.swift` in iOS target
- **Location:** `MacroMark/ContentView.swift:1-24`
- **What:** Xcode template "Hello, world!" view. The app routes directly to `MacroManagerView`.
- **Action:** Delete the file.
- **Severity:** Medium

### 9.3 Duplicate `WatchConnectivityProvider` across iOS and watchOS targets (symlink)
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift` (iOS target), `MacroMark Watch App/Storage/WatchConnectivityProvider.swift` (watchOS target — actually a symlink)
- **What:** The watchOS file is a symlink to the iOS file. This is acceptable but fragile — if the symlink breaks, the targets diverge.
- **Action:** Consider moving `WatchConnectivityProvider` into MacroMarkKit so both targets reference it as a package dependency, eliminating the symlink.
- **Severity:** Low (informational — current symlink approach works)

### 9.4 Duplicated date-format logic across four sites
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:83-89` (`formatDate`), `MacroMark/Settings/FolderSettingsView.swift:91-105` (`currentDateExample`), `MacroMark/Settings/FolderSettingsView.swift:107-121` (`formatWithSettings`), `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:35-36` (date formatting)
- **What:** The pattern of extracting year/month/day and replacing `yyyy`/`MM`/`dd` tokens is implemented four times with near-identical logic across three files.
- **Why:** Any change to date-format parsing (e.g., adding `{DOW}`) must be applied in four places.
- **Action:** Extract a shared `FolderSettings.format(date:using:)` method in MacroMarkKit and use it from all call sites.
- **Severity:** Medium

### 9.5 `EntitlementManager.canAddCustomMacro` is defined but never called
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:75`
- **What:** The computed property `canAddCustomMacro` returns `isSubscribed || hasLifetimeUnlock`, but no call site reads it. `MacroManagerView` uses its own inline checks.
- **Action:** Either wire views to use `canAddCustomMacro`, or remove it to avoid confusion.
- **Severity:** Low

### 9.6 `isInTrial` is set but never read by any UI
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:12,64`
- **What:** `isInTrial` is computed in `refreshEntitlements()` but never checked by any view or logic layer.
- **Action:** Add trial-banner UI, or remove the property until needed.
- **Severity:** Low

### 9.7 Oversized files
No file exceeds 500 lines. The largest is `MacroManagerView.swift` at 298 lines — see §8.2 for the recommended split.

### 9.8 Unresolved TODO/FIXME markers
No `TODO:`, `FIXME:`, `HACK:`, `XXX:`, or `#warning` directives exist in the codebase. The project has no explicit debt-tracking mechanism — add `#warning` or `// TODO:` comments for known issues.

### 9.9 Magic constants — free tier limit `3`
- **Location:** `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift:81`, `MacroMark/Settings/MacroManagerView.swift:116,132`
- **What:** The number `3` for free-tier macro limit appears as a magic literal in three places.
- **Action:** Define `public static let maxFreeMacros = 3` in `EntitlementManager` and reference it from all call sites.
- **Severity:** Medium

### 9.10 Magic constants — audio sample rate `12000`
- **Location:** `MacroMark Watch App/Capture/AudioRecorder.swift:35`
- **What:** `AVSampleRateKey: 12000` — literal with no named constant or comment explaining the choice.
- **Action:** Define `static let audioSampleRate: Double = 12000` with a comment about the quality-vs-size trade-off.
- **Severity:** Low

### 9.11 Magic constants — audio chunk duration `50.0`
- **Location:** `MacroMark/Engine/AudioTranscriber.swift:31`
- **What:** `maxDuration: 50.0` passed as a literal to the audio split.
- **Action:** Define a named constant with a comment explaining why 50 seconds is the chunk size.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Audit every `@MainActor` annotation.** `MacroProcessor.process`, `AudioRecorder`, `LocationManager`, and `WatchConnectivityProvider` are all `@MainActor` but perform I/O or CPU work that doesn't require it. Reserve `@MainActor` for UI-touching code and use the global cooperative pool for everything else.

2. **Adopt a unified logging strategy.** Replace all 23 `print()` calls with `os_log` and `Logger`, gating sensitive values with `%{private}@`. Wrap debug-only logs in `#if DEBUG`. This is a one-pass change across 7 files.

3. **Move shared types to MacroMarkKit.** `WatchConnectivityProvider` currently lives in the iOS target and is symlinked into the watch target. Moving it (and any future shared logic) into MacroMarkKit gives both targets a single source of truth and eliminates the symlink fragility.

4. **Extract shared date-format and string-replacement logic.** Four copies of date-token replacement and two copies of the `replacing(yyyy/MM/dd)` logic exist across the project. A single `FolderSettings.format(date:using:)` method in MacroMarkKit would serve all callers.

5. **Make StoreKit lifecycle explicit.** Both `StoreManager` and `EntitlementManager` start fire-and-forget Tasks in `init()`. Extract lifecycle into explicit `start()`/`stop()` methods, or tie Task lifetimes to a SwiftUI `.task {}` modifier on the root view so cancellation is automatic.

6. **Bump to Swift 6.** The gap between `SWIFT_VERSION = 5.0` (Xcode project) and `swift-tools-version: 6.2` (Package.swift) means the same code is checked at different strictness levels depending on the target. After fixing the concurrency issues in §3, bump to Swift 6 and set `SWIFT_STRICT_CONCURRENCY = complete`.

---

## 11. What was NOT audited

- Build settings, scheme configuration, Xcode project structure — beyond the `SWIFT_VERSION` observation in §4.1.
- Third-party SPM dependency internals — MacroMarkKit is the only package; its dependency tree was not analyzed.
- Test coverage — `MacroMarkTests/`, `MacroMarkUITests/`, `MacroMark Watch AppTests/`, `MacroMark Watch AppUITests/`, and `MacroMarkKit/Tests/` were scanned but not deeply reviewed.
- StoreKit 2 product configuration in App Store Connect — only the in-code `ProductIdentifiers` and StoreKit integration were reviewed.
- Localization and string catalogs — not assessed. All user-facing strings are hardcoded English.
- Widget extension entitlements — the widget target's entitlements file was not opened.
- Deep algorithmic review of the regex-based macro processor — patterns were checked for obvious bugs but regex correctness was not exhaustively verified.
- watchOS-specific lifecycle (background tasks, complications) — only the Swift code was reviewed.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference in this report — it should land on the cited line. Each Critical finding below has been spot-verified by reading the cited lines.

- **§5.1** — open `MacroMark Watch App/Capture/LocationManager.swift`, lines 33-36. Confirm `activeContinuation` is a mutable stored property overwritten on each `getCurrentLocation()` call. No reentrancy guard exists. The same pattern repeats for `authContinuation` at lines 22-25.
- **§5.2** — open `MacroMark/MacroMarkApp.swift`, line 23. Confirm `fatalError` is the only branch for `ModelContainer` init failure. There is no `catch` block, no error-state flag, and no user-facing recovery path.
- **§3.1** — open `MacroMarkKit/Sources/MacroMarkKit/Store/StoreManager.swift`, lines 31-36. Confirm the `Task { }` is not stored in a property and has no cancellation path. Same pattern at `EntitlementManager.swift:21-27`.
- **§3.3** — open `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift`, line 10. Confirm `@MainActor` annotation on `process()`. Then open `MacroMarkApp.swift`, lines 39-43 and 52-63, confirming the `Task { @MainActor in }` wrappers that chain main-actor execution.
- **§6.1** — open `MacroMark/MacroMarkApp.swift`, line 33. Confirm `print("MacroMark iOS Received Note: \(text)")` emits user note content with no `#if DEBUG` guard. Then open `WatchConnectivityProvider.swift`, lines 73, 93, 114 — confirm three more unguarded PII-emitting `print()` calls.

- **§3.2** — open `MacroMarkKit/Sources/MacroMarkKit/Store/EntitlementManager.swift`, lines 29-33. Confirm `updateEntitlements()` spawns `Task { await refreshEntitlements() }` and returns `Void` immediately — no way for callers to await the result.
- **§5.4** — open `MacroMark Watch App/Capture/AudioRecorder.swift`, lines 57-61. Confirm `stopRecording()` stops the audio engine but never calls `setActive(false)` on the shared audio session.
- **§9.1** — open `MacroMark/Models/Macro.swift`. Confirm the file contains only a migration comment and no executable code. Repeat for `MacroMark/Engine/MacroProcessor.swift` and `MacroMark/Storage/iCloudStorageManager.swift`.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
