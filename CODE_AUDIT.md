# MacroMark PR #1 Code Audit

Generated 2026-06-25. Scope: PR #1 (`codex/dated-notes-picker`, head `2eb484e`) against `main`: 15 changed files across the iOS app, watch app, `MacroMarkKit`, and tests. Repository scope at audit time: 47 Swift files (~3,616 LOC), 0 Metal files. This audit is PR-scoped; it does not replace a whole-product security, StoreKit, localization, or profiling pass.

Findings cite the PR #1 file/line snapshot so the review comments map to the feature as opened. Remediation for the highest-value items is tracked in `REMEDIATION_PLAN.md`.

Build ground truth captured from PR #1:
- `swift test --package-path MacroMarkKit` passed with one Swift warning in `MacroMarkKitTests.swift:47`.
- `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build` passed with AppIntents metadata warnings only.
- `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build` passed with AppIntents metadata warnings only.

---

## 1. Executive summary

Top items to address, in priority order:

1. **[High] Future-note iCloud failures are not queued for automatic retry** — §5.1 — `MacroMark/Views/FutureNoteComposerView.swift:79-91`. A failed/deferred append leaves only a status message, so the promised reliability model is not satisfied for iPhone-created future notes.
2. **[High] Manual iCloud export ignores the note date** — §5.2 — `MacroMark/Views/NoteDetailView.swift:62-65`. Re-exporting a future note writes to today's daily file instead of the note's selected day.
3. **[Medium] Watch daily log can show stale content after rapid date changes** — §3.1 — `MacroMark Watch App/Capture/DailyLogView.swift:35-50`. The cancelled `.task(id:)` can still resume from the uncancellable `WCSession.sendMessage` continuation and overwrite the new selection.
4. **[Medium] Retry state is private to the watch pipeline** — §9.1 — `MacroMark/MacroMarkApp.swift:36-45,590-619`. The new iPhone composer needs the same pending-export WAL, but cannot safely reuse it while the model is private to `MacroMarkApp`.
5. **[Low] Watch capture buttons are icon-only labels** — §8.1 — `MacroMark Watch App/ContentView.swift:22-38`. VoiceOver gets SF Symbol names instead of capture actions.
6. **[Low] Changed watch root reintroduces a raw settings key** — §9.2 — `MacroMark Watch App/ContentView.swift:10`. This bypasses the existing `UserDefaultsKey` safety net.
7. **[Low] Package tests emit an avoidable warning** — §2.1 — `MacroMarkKit/Tests/MacroMarkKitTests/MacroMarkKitTests.swift:47`. This obscures future compiler warning regressions.
8. **[Low] App test target still has a placeholder no-op test** — §9.3 — `MacroMarkTests/MacroMarkTests.swift:15-19`. The PR adds useful behavior coverage but leaves generated noise behind.

---

## 2. Quick wins

### 2.1 Remove the mutable test variable warning
- **Location:** `MacroMarkKit/Tests/MacroMarkKitTests/MacroMarkKitTests.swift:47`
- **What:** `var settings` is never mutated.
- **Why:** The package gate otherwise stays noisy after this PR, making new warnings easier to miss.
- **Action:** Change `var` to `let`.
- **Severity:** Low

### 2.2 Delete the placeholder app test
- **Location:** `MacroMarkTests/MacroMarkTests.swift:15-19`
- **What:** The generated `example()` test has no assertion.
- **Why:** It dilutes the signal from the real `InboxDateFilter` test added by the PR.
- **Action:** Remove the placeholder test.
- **Severity:** Low

---

## 3. Concurrency

### 3.1 Cancelled watch log loads can still publish stale content
- **Location:** `MacroMark Watch App/Capture/DailyLogView.swift:30-50`, `MacroMark/Shared/WatchConnectivityProvider.swift:266-292`
- **What:** `.task(id: selectedDate)` cancels the old task when the user picks another day, but `fetchDailyFile(for:)` uses `withCheckedContinuation` around `WCSession.sendMessage`; that continuation is not cancellation-aware. The old task can still resume and assign `logContent` for the previous date.
- **Why:** A watch user spinning the date picker can see the wrong day's note text under the new date, which is especially risky for future-note verification.
- **Action:** Capture `requestedDate` at the start of `loadLog()`, fetch with that value, and check `!Task.isCancelled` plus same-day selection before assigning `logContent`.
- **Severity:** Medium

### 3.2 `fetchDailyFile` timeout task is not cancelled on success
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:269-292`
- **What:** The timeout `Task` sleeps for 15 seconds even when the reply handler wins.
- **Why:** Low-impact resource churn on watchOS if the log is refreshed repeatedly.
- **Action:** Capture and cancel the timeout task from reply/error handlers, or convert the method to a cancellation handler.
- **Severity:** Low

---

## 4. API modernity

_No PR-specific deprecation warnings were emitted by the iOS or watchOS builds._

---

## 5. Bugs / logic errors

### 5.1 Future-note iCloud failures are not queued for automatic retry
- **Location:** `MacroMark/Views/FutureNoteComposerView.swift:79-91`
- **What:** On `.deferred` or `.failed`, the composer sets `didSave` and a message, but it does not add the note to the pending-export WAL used by `MacroMarkApp.retryDeferredExports`.
- **Why:** The note is saved to SwiftData, but the daily Markdown file may never receive it unless the user manually opens the detail view and retries. That violates MacroMark's "export succeeded or safely queued for retry" reliability rule.
- **Action:** Move the pending-export entry/store into shared code and enqueue iPhone-created future notes with `requiresWatchAcknowledgement == false` when append is deferred or failed.
- **Severity:** High

### 5.2 Manual iCloud export ignores the note's date
- **Location:** `MacroMark/Views/NoteDetailView.swift:62-65`
- **What:** `exportToICloud()` calls `appendText(note.text + "\n\n")` with no `for:` date, so `iCloudStorageManager` defaults to `Date()`.
- **Why:** A future note created for July 4 and manually re-exported from detail is appended to today's file, not July 4's file.
- **Action:** Call `appendText(note.text, for: note.createdAt)`, and enqueue deferred/failed attempts through the same pending-export store.
- **Severity:** High

### 5.3 Manual iCloud export can double-space note payloads
- **Location:** `MacroMark/Views/NoteDetailView.swift:64`
- **What:** The detail export passes `note.text + "\n\n"` into `appendText`, but `appendText` already wraps the note with blank lines and a time heading.
- **Why:** Manual exports can produce extra spacing compared with watch and future-note exports.
- **Action:** Pass only `note.text` to `appendText`.
- **Severity:** Low

---

## 6. Security

_No PR-specific security findings. The date picker, watch transfer timestamp, and future-note composer do not introduce secrets, credentials, or new network endpoints._

---

## 7. Performance

### 7.1 Watch daily-log refresh can pay the full 15-second timeout per stale request
- **Location:** `MacroMark/Shared/WatchConnectivityProvider.swift:269-292`
- **What:** Multiple date changes can leave multiple in-flight `sendMessage` requests racing the timeout.
- **Why:** The user can make the watch feel sluggish while browsing days, although the UI remains cancellable.
- **Action:** Same as §3.1/§3.2: guard stale results and cancel timeout racers where practical.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Watch capture buttons are icon-only labels
- **Location:** `MacroMark Watch App/ContentView.swift:22-38`
- **What:** The mic and keyboard buttons use only `Image(systemName:)` labels.
- **Why:** VoiceOver and Switch Control may announce symbol names rather than user actions, and the project guide asks for text with image button labels.
- **Action:** Use `Label("Instant Capture", systemImage: "mic.fill")` and `Label("Dictation", systemImage: "keyboard.fill")`, preserving the compact visual layout with `.labelStyle(.iconOnly)`.
- **Severity:** Low

### 8.2 Conditional toolbar items may shift the Inbox controls
- **Location:** `MacroMark/Views/InboxView.swift:68-81`
- **What:** The toolbar conditionally inserts "New Note" and `EditButton` based on selected date and filtered notes.
- **Why:** This is acceptable for a small surface, but it can cause toolbar re-layout when switching between empty and non-empty days.
- **Action:** Consider stable toolbar items if this view grows, using disabled/hidden state rather than rebuilding the toolbar.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Pending-export WAL is private to `MacroMarkApp`
- **Location:** `MacroMark/MacroMarkApp.swift:36-45,590-619`
- **What:** The retry entry and its UserDefaults serialization live as private types/methods in the app entry point.
- **Why:** The future-note composer and detail export need to enqueue the same retry state, but duplicating the serialization would be error-prone.
- **Action:** Extract a small `PendingExportEntry` + `PendingExportStore` into `MacroMarkKit`, preserving backward decode behavior for existing watch pending exports.
- **Severity:** Medium

### 9.2 Watch root uses a raw `@AppStorage` key
- **Location:** `MacroMark Watch App/ContentView.swift:10`
- **What:** The changed watch root still uses `@AppStorage("captureMode")`.
- **Why:** The repo already has `UserDefaultsKey.captureMode`; raw strings are easy to typo and silently break cross-device settings.
- **Action:** Import `MacroMarkKit` and use `@AppStorage(UserDefaultsKey.captureMode.rawValue)`.
- **Severity:** Low

### 9.3 Placeholder test remains in the app test target
- **Location:** `MacroMarkTests/MacroMarkTests.swift:15-19`
- **What:** The generated `example()` test remains alongside the new date-filter test.
- **Why:** It adds noise with no coverage.
- **Action:** Delete it.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Treat iPhone-created notes like watch-originated notes after SwiftData save.** Once any note is not yet in its final export target, it should enter a retryable state. Watch notes additionally need ACK cleanup; manual/future notes do not.
2. **Snapshot selected dates before async boundaries.** Date pickers drive async fetches on both iOS and watchOS; capture the input date before `await` and reject stale results before publishing UI.
3. **Keep compiler output quiet.** The PR's functional gates are strong; small test warnings should be cleaned immediately so future warnings are actionable.

---

## 11. What was NOT audited

- Full historical codebase findings from the June 20 audit, except where PR #1 intersects them.
- App Store Connect / StoreKit product configuration.
- Entitlements, signing, provisioning profiles, and iCloud container setup.
- Localization/string catalog completeness.
- Instruments-based performance profiling.
- Xcode project structure beyond the watch target's new `MacroMarkKit` linkage.
- Widget behavior and complications beyond ensuring PR #1 did not modify them.

---

## 12. Verification

High/Medium findings were spot-checked directly:

- **§5.1** — open `MacroMark/Views/FutureNoteComposerView.swift`, lines 79-91 in PR #1. The `.deferred` and `.failed` arms only set UI state; no retry entry is written.
- **§5.2** — open `MacroMark/Views/NoteDetailView.swift`, lines 62-65 in PR #1. `appendText` is called without `for: note.createdAt`, so it defaults to today's date.
- **§3.1** — open `MacroMark Watch App/Capture/DailyLogView.swift`, lines 30-50, and `MacroMark/Shared/WatchConnectivityProvider.swift`, lines 266-292. The UI task is keyed by date, but the underlying continuation cannot observe cancellation before assignment.
- **§9.1** — open `MacroMark/MacroMarkApp.swift`, lines 36-45 and 590-619 in PR #1. The pending-export model and store are private, preventing the future composer from using the existing retry path.
