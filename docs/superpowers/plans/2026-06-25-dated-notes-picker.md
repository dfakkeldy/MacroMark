# Dated Notes Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add date pickers on iPhone and Apple Watch to browse a selected day's notes and create future-dated notes without weakening MacroMark's durable capture pipeline.

**Architecture:** Put shared local-day math in `MacroMarkKit`, then use it from the iPhone inbox, watch daily-log viewer, and watch capture timestamp creation. Daily-log browsing stays a live WatchConnectivity request; capture delivery continues through the existing queued transfer + WAL + ACK flow.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, WatchConnectivity, MacroMarkKit, Swift Testing, iCloud Drive file coordination.

## Global Constraints

- Preserve iOS/watchOS deployment targets; do not lower iOS 26.5/watchOS 26.5 app settings or MacroMarkKit platform declarations.
- Do not introduce third-party frameworks.
- Use SwiftUI `NavigationStack`, `Button`, `foregroundStyle`, `clipShape(.rect(cornerRadius:))`, `Task.sleep(for:)`, and modern Foundation APIs.
- Keep watch-side notes/audio queued until iPhone-side processing and configured export succeeds or is safely queued for retry.
- Do not add a SwiftData schema migration for this feature.
- Use TDD for new shared logic and testable behavior.

---

## File Structure

- `MacroMarkKit/Sources/MacroMarkKit/Support/DaySelection.swift`  
  Shared local-day bounds, future-day detection, and selected-day timestamp creation.
- `MacroMarkKit/Tests/MacroMarkKitTests/DaySelectionTests.swift`  
  Tests for day boundaries, future detection, and future capture timestamps.
- `MacroMark/Views/InboxView.swift`  
  iPhone day picker, selected-day filtering, and future-note sheet trigger.
- `MacroMark/Views/FutureNoteComposerView.swift`  
  Small sheet for future note text entry and export status.
- `MacroMark/Shared/WatchConnectivityProvider.swift` and `MacroMark Watch App/Storage/WatchConnectivityProvider.swift`  
  Add `fetchDailyFile(for:)`, dated cache keys, and dated iOS read replies. Both copies must be updated identically until the existing duplicate-provider remediation lands.
- `MacroMark Watch App/ContentView.swift`  
  Root selected date state and target-date routing to capture/daily-log destinations.
- `MacroMark Watch App/Capture/DailyLogView.swift`  
  Watch date picker, dated fetch, and same-day pending-note filtering.
- `MacroMark Watch App/Capture/InstantCaptureView.swift` and `MacroMark Watch App/Capture/SystemCaptureView.swift`  
  Accept `targetDate` and enqueue captures stamped for the selected day.
- `MacroMark Watch App/Storage/LocalStore.swift`  
  Add `addNote(_:timestamp:)` while keeping existing `addNote(_:)` behavior.

---

### Task 1: Shared Date Helper

**Files:**
- Create: `MacroMarkKit/Sources/MacroMarkKit/Support/DaySelection.swift`
- Create: `MacroMarkKit/Tests/MacroMarkKitTests/DaySelectionTests.swift`

**Interfaces:**
- Produces: `public enum DaySelection`
- Produces: `public static func dayInterval(for:calendar:) -> DateInterval`
- Produces: `public static func isFutureDay(_:relativeTo:calendar:) -> Bool`
- Produces: `public static func timestamp(onSelectedDay:now:calendar:) -> Date`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import MacroMarkKit

struct DaySelectionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func dayIntervalCoversOnlySelectedLocalDay() throws {
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 14)))
        let interval = DaySelection.dayInterval(for: selected, calendar: calendar)

        let sameDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 23, minute: 59)))
        let previousDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 23, minute: 59)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 26)))

        #expect(interval.contains(sameDay))
        #expect(!interval.contains(previousDay))
        #expect(!interval.contains(nextDay))
    }

    @Test
    func futureDetectionComparesByDay() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 23)))
        let laterToday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 23, minute: 30)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 26, hour: 1)))

        #expect(!DaySelection.isFutureDay(laterToday, relativeTo: now, calendar: calendar))
        #expect(DaySelection.isFutureDay(tomorrow, relativeTo: now, calendar: calendar))
    }

    @Test
    func timestampUsesSelectedDateAndCurrentTime() throws {
        let selected = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 9)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 16, minute: 30, second: 45)))

        let timestamp = DaySelection.timestamp(onSelectedDay: selected, now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: timestamp)

        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 4)
        #expect(components.hour == 16)
        #expect(components.minute == 30)
        #expect(components.second == 45)
    }
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --package-path MacroMarkKit --filter DaySelectionTests`

Expected: compile failure because `DaySelection` does not exist.

- [ ] **Step 3: Add minimal implementation**

```swift
import Foundation

public enum DaySelection {
    public static func dayInterval(
        for date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    public static func isFutureDay(
        _ selectedDate: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: selectedDate) > calendar.startOfDay(for: now)
    }

    public static func timestamp(
        onSelectedDay selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let selectedComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)

        var combined = DateComponents()
        combined.calendar = calendar
        combined.timeZone = calendar.timeZone
        combined.year = selectedComponents.year
        combined.month = selectedComponents.month
        combined.day = selectedComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second
        combined.nanosecond = timeComponents.nanosecond

        return calendar.date(from: combined) ?? calendar.startOfDay(for: selectedDate)
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `swift test --package-path MacroMarkKit --filter DaySelectionTests`

Expected: all `DaySelectionTests` pass.

- [ ] **Step 5: Commit**

```bash
git add MacroMarkKit/Sources/MacroMarkKit/Support/DaySelection.swift MacroMarkKit/Tests/MacroMarkKitTests/DaySelectionTests.swift
git commit -m "feat: add shared day selection helper"
```

---

### Task 2: iPhone Day Filter and Future Composer

**Files:**
- Modify: `MacroMark/Views/InboxView.swift`
- Create: `MacroMark/Views/FutureNoteComposerView.swift`

**Interfaces:**
- Consumes: `DaySelection.dayInterval(for:)`
- Consumes: `DaySelection.isFutureDay(_:relativeTo:)`
- Consumes: `DaySelection.timestamp(onSelectedDay:)`
- Produces: iPhone selected-day filtering and future-note save action.

- [ ] **Step 1: Add testable filtering helper to `InboxView.swift`**

Add this private helper outside the `InboxView` type:

```swift
private enum InboxDateFilter {
    static func notes(_ notes: [ProcessedNote], on selectedDate: Date, calendar: Calendar = .current) -> [ProcessedNote] {
        let interval = DaySelection.dayInterval(for: selectedDate, calendar: calendar)
        return notes.filter { interval.contains($0.createdAt) }
    }
}
```

- [ ] **Step 2: Update `InboxView` state and list source**

Use `@State private var selectedDate = Date()` and compute `filteredNotes` with `InboxDateFilter.notes(notes, on: selectedDate)`. Replace empty-state and `ForEach(notes)` usage with `filteredNotes`.

- [ ] **Step 3: Add date picker and future action**

Add a `DatePicker("Day", selection: $selectedDate, displayedComponents: .date)` above the list content or in a compact section. Add a toolbar `Button("New Note", systemImage: "square.and.pencil")` only when `DaySelection.isFutureDay(selectedDate)` is true.

- [ ] **Step 4: Create `FutureNoteComposerView`**

Implement a sheet view with `TextEditor`, Cancel, and Save. Save should:

```swift
let timestamp = DaySelection.timestamp(onSelectedDay: selectedDate)
let note = ProcessedNote(text: trimmedText, createdAt: timestamp)
modelContext.insert(note)
try modelContext.save()
let result = await iCloudStorageManager.shared.appendText(trimmedText, for: timestamp)
if result == .appended {
    note.isExported = true
    note.exportTarget = ExportTarget.iCloud.rawValue
    try? modelContext.save()
}
```

If append fails or defers, keep the SwiftData note visible and show a short status message. Do not invent a second WAL in this view.

- [ ] **Step 5: Build iOS target**

Run: `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MacroMark/Views/InboxView.swift MacroMark/Views/FutureNoteComposerView.swift
git commit -m "feat: add iPhone dated note browsing"
```

---

### Task 3: Dated Daily-File Fetch Over WatchConnectivity

**Files:**
- Modify: `MacroMark/Shared/WatchConnectivityProvider.swift`
- Modify: `MacroMark Watch App/Storage/WatchConnectivityProvider.swift`

**Interfaces:**
- Consumes: `iCloudStorageManager.shared.readText(for:)`
- Produces: `func fetchDailyFile(for date: Date) async -> String`

- [ ] **Step 1: Change fetch signature in both provider copies**

Replace `func fetchDailyFile() async -> String` with `func fetchDailyFile(for date: Date = Date()) async -> String`.

- [ ] **Step 2: Use per-date cache keys**

Add:

```swift
private func dailyLogCacheKey(for date: Date) -> String {
    let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
    return "\(UserDefaultsKey.cachedDailyLog.rawValue)-\(day)"
}
```

If a provider file cannot import `MacroMarkKit` on watchOS, use the literal `"cachedDailyLog"` in the helper and leave a follow-up for provider deduplication.

- [ ] **Step 3: Send selected date to iPhone**

Change the message payload to:

```swift
session.sendMessage(
    ["request": "dailyFile", "date": date.timeIntervalSince1970],
    replyHandler: ...
)
```

Read and write fallback cache using `dailyLogCacheKey(for: date)`.

- [ ] **Step 4: Read the selected day on iOS**

In `session(_:didReceiveMessage:replyHandler:)`, parse:

```swift
let timestamp = message["date"] as? TimeInterval ?? Date().timeIntervalSince1970
let date = Date(timeIntervalSince1970: timestamp)
let content = iCloudStorageManager.shared.readText(for: date) ?? ""
replyHandler(["content": content])
```

- [ ] **Step 5: Build both targets**

Run the iOS and watchOS generic build commands.

Expected: both builds succeed.

- [ ] **Step 6: Commit**

```bash
git add MacroMark/Shared/WatchConnectivityProvider.swift "MacroMark Watch App/Storage/WatchConnectivityProvider.swift"
git commit -m "feat: fetch watch daily logs by date"
```

---

### Task 4: Watch Date Picker and Future Capture Timestamps

**Files:**
- Modify: `MacroMark Watch App/ContentView.swift`
- Modify: `MacroMark Watch App/Capture/DailyLogView.swift`
- Modify: `MacroMark Watch App/Capture/InstantCaptureView.swift`
- Modify: `MacroMark Watch App/Capture/SystemCaptureView.swift`
- Modify: `MacroMark Watch App/Storage/LocalStore.swift`

**Interfaces:**
- Consumes: `DaySelection.timestamp(onSelectedDay:)`
- Consumes: `WatchConnectivityProvider.shared.fetchDailyFile(for:)`
- Produces: watch root selected-date state shared by capture and daily log.

- [ ] **Step 1: Add target-date LocalStore API**

In `LocalStore`, change `addNote(_:)` to delegate to:

```swift
func addNote(_ text: String, timestamp: Date = Date()) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let note = CapturedNote(text: trimmed, timestamp: timestamp)
    pendingNotes.append(note)
    syncPendingNotes()
}
```

- [ ] **Step 2: Own selected date in watch root**

In `ContentView`, add `@State private var selectedDate = Date()`. Pass it to `InstantCaptureView(targetDate: selectedDate)`, `SystemCaptureView(targetDate: selectedDate)`, and `DailyLogView(selectedDate: $selectedDate)`. Change the log button label to `Daily Log`.

- [ ] **Step 3: Add watch date picker and dated fetch**

Change `DailyLogView` to accept `@Binding var selectedDate: Date`. Add:

```swift
DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
    .labelsHidden()
```

Use `.task(id: selectedDate) { await loadLog() }` because the async work depends exactly on the selected date. In `loadLog`, call `fetchDailyFile(for: selectedDate)` and filter pending notes with `DaySelection.dayInterval(for: selectedDate)`.

- [ ] **Step 4: Stamp audio captures with selected day**

Add `let targetDate: Date` to `InstantCaptureView`. In `finishAndSave`, compute:

```swift
let timestamp = DaySelection.timestamp(onSelectedDay: targetDate)
Task {
    await InstantCaptureView.processAudioFile(fileURL: fileURL, timestamp: timestamp)
}
```

- [ ] **Step 5: Stamp text captures with selected day**

Add `let targetDate: Date` to `SystemCaptureView`. In `finishAndSave`, accept `timestamp` and call `LocalStore.shared.addNote(text, timestamp: timestamp)`.

- [ ] **Step 6: Build watch target**

Run: `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add "MacroMark Watch App/ContentView.swift" "MacroMark Watch App/Capture/DailyLogView.swift" "MacroMark Watch App/Capture/InstantCaptureView.swift" "MacroMark Watch App/Capture/SystemCaptureView.swift" "MacroMark Watch App/Storage/LocalStore.swift"
git commit -m "feat: add watch dated log and capture"
```

---

### Task 5: Verification and PR

**Files:**
- No source files unless verification exposes a required fix.

- [ ] **Step 1: Run full package tests**

Run: `swift test --package-path MacroMarkKit`

Expected: all tests pass.

- [ ] **Step 2: Run iOS build gate**

Run: `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run watchOS build gate**

Run: `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Inspect changes**

Run: `git status --short` and `git diff --stat origin/HEAD...HEAD` if origin ref is available. Confirm only the feature docs/source/tests are included.

- [ ] **Step 5: Push and open PR**

Run:

```bash
git push -u origin codex/dated-notes-picker
gh pr create --title "Add dated note browsing and future capture" --body "Adds date pickers on iPhone and Apple Watch for day-specific notes, with future-date capture routed through the existing durable pipeline."
```

Expected: PR URL returned by GitHub CLI.

---

## Self-Review

- Spec coverage: Tasks cover shared date logic, iPhone browsing, future note creation, watch browsing, future watch capture, WatchConnectivity dated fetch, tests, builds, and PR.
- Placeholder scan: No TBD/TODO/fill-in placeholders.
- Type consistency: `DaySelection` method names are consistent across tasks.
- Scope check: The plan avoids schema migration and keeps audit/remediation as the next phase after the feature PR, matching the user's requested sequence.
