# MacroMark: Dated Notes Picker

**Date:** 2026-06-25
**Status:** Approved for implementation by continuation

## Overview

Add date picking on iPhone and Apple Watch so users can browse a selected day's notes and create notes for future days. The implementation keeps MacroMark's reliability-first capture pipeline intact: selected dates flow through as timestamps, and watch-side data remains queued until iPhone-side processing and export succeed.

The feature uses a conservative interpretation of "create future notes": selecting a future date lets the user create content stamped for that day. MacroMark does not create empty Markdown files merely because a future date was viewed.

## Goals

- iPhone users can pick a day and see notes from that local calendar day.
- Apple Watch users can pick a day and see that day's exported Markdown daily note, plus same-day pending watch notes.
- If the selected date is in the future, iPhone and watch capture actions create notes with that future date as their target day.
- Existing watch durability, WAL, pending-export retry, idempotency, and ACK rules remain unchanged.
- No SwiftData schema migration is introduced.

## Non-Goals

- No calendar heatmap, month agenda, or multi-day search.
- No automatic creation of empty Markdown daily files.
- No schema changes to `ProcessedNote`.
- No replacement of iCloud Drive daily files with CloudKit or another sync backend.

## Architecture

### Shared Date Logic

Create a small shared helper in `MacroMarkKit` for local-day calculations. It owns:

- start/end bounds for a local calendar day,
- testing whether a selected day is in the future,
- building a capture timestamp for a selected day while preserving the current time-of-day.

This keeps date math out of SwiftUI bodies and avoids divergent iPhone/watch behavior.

### iPhone Experience

`InboxView` becomes day-focused:

- A compact `DatePicker` controls `selectedDate`.
- Notes are filtered by `createdAt` within the selected local day.
- The navigation title reflects the selected day, while the list remains the primary screen.
- For future selected dates, a "New Note" action opens a lightweight text-entry sheet.
- Saving a future note inserts a `ProcessedNote` stamped with the selected day plus the current time-of-day, then calls `iCloudStorageManager.appendText(_:for:)` for the same timestamp.

For current and past dates, capture remains the normal watch-first workflow; the iPhone future-note composer is only shown for future days to satisfy the requested future-note path without growing the app into a full editor.

### Apple Watch Experience

`DailyLogView` gains a small date picker and uses the selected day for fetches. It remains a simple scroll view because watchOS should stay glanceable and shallow.

When the selected day changes:

- the watch sends `["request": "dailyFile", "date": selectedDate.timeIntervalSince1970]`,
- the phone reads `iCloudStorageManager.shared.readText(for: selectedDate)`,
- the watch caches the response under a per-day cache key,
- pending watch notes are filtered to the selected local day.

For future selected dates, watch capture views receive a `targetDate` and pass a timestamp for that selected day into `LocalStore`. The existing `transferUserInfo` and `transferFile` payloads already include timestamps, so the iPhone processing/export pipeline writes to the future daily file when the note is delivered.

### Watch Navigation

`ContentView` keeps its existing `NavigationStack` and three destinations. The selected daily-log date is owned by the root watch view so the capture buttons and daily-log screen share the same target day. The "Today's Log" button label changes to "Daily Log" because the log is no longer always today.

### Watch Connectivity

Daily-log reads remain live `sendMessage` requests because they are refreshable display data. Capture delivery remains queued `transferUserInfo` / `transferFile` because every capture must arrive exactly once and survive disconnection.

`fetchDailyFile` changes to `fetchDailyFile(for date: Date)`. The iOS message handler uses the supplied timestamp and falls back to `Date()` only if the watch sends an old payload without a date.

## Error Handling

- If the watch cannot reach the phone, it falls back to the selected day's cached daily-log content.
- If no daily file exists for the selected date, the watch shows the existing empty-state copy.
- If a future note export returns `.deferred` or `.failed`, the iPhone keeps the note in the existing pending-export WAL and does not ACK the watch until export succeeds.
- The iPhone future-note sheet keeps the draft text when export fails; the note is still stored in SwiftData and can be retried by the existing pending-export machinery if it entered that path.

## Testing

Add `MacroMarkKit` unit tests for the shared date helper:

- day ranges include notes on the selected day and exclude adjacent days,
- future detection compares by day, not exact time,
- capture timestamp preserves selected year/month/day and current hour/minute/second.

Add app-side tests where practical:

- iPhone note filtering uses the shared date helper.
- Watch cache keys differ by selected date.

Build gates:

```bash
swift test --package-path MacroMarkKit
xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build
xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build
```

## Reliability Rationale

The selected date becomes data on the existing note timestamp rather than a new queue or schema. That fits MacroMark's capture workflow: the watch still durably stores raw notes/audio first, the phone still expands macros with the original timestamp, iCloud export still targets the date-derived Markdown file, and ACKs still wait for confirmed durable delivery.
