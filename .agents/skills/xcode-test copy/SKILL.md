---
name: xcode-test
description: Guide agents on building/testing targets (iOS, watchOS, macOS) using xcodebuild and diagnosing database/FK constraint failures.
---

# Xcode Build, Test, and Database Triage Skill

Use this skill when compiling project targets, executing unit/UI tests, or resolving test failures related to database integrity constraints.

## Compilation and Testing Commands

Orbit AudioBooks uses multiple targets sharing core code via `Shared/`. Run these commands using the `run_command` tool.

### Finding Available Simulators Dynamically

Simulators installed on the host system change across environments. To list the available destination platforms and simulator names, run:
```bash
xcodebuild -project "Orbit Audiobooks.xcodeproj" -showdestinations -scheme "Orbit Audiobooks"
```
Or query simulators using:
```bash
xcrun simctl list devices available
```

### Xcode Build Invocations

Use `-quiet` to suppress verbose compiler logs unless debugging compile-time issues.

1. **iOS Target (Main App)**:
   ```bash
   xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
   ```

2. **macOS Target**:
   ```bash
   xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks macOS" -destination 'platform=macOS' -quiet
   ```

3. **watchOS Target**:
   ```bash
   xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks Watch App" -destination 'generic/platform=watchOS Simulator' -quiet
   ```

4. **Widget Target**:
   Confirm whether the widget is included in the iOS target or built as a sub-scheme:
   ```bash
   xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks Widget" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
   ```

### Executing Tests

To run unit and integration tests:
```bash
xcodebuild test -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

To run a specific test suite or class, add `-only-testing:<target>/<test-class>`:
```bash
xcodebuild test -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OrbitAudioBooksTests/DatabaseTests
```

---

## Diagnosing & Triaging Database Foreign Key failures

Orbit AudioBooks uses GRDB / SQLite with `FOREIGN KEY` constraints enabled. 

### Symptom: `SQLite error 19: FOREIGN KEY constraint failed`

If a unit test fails with a foreign key constraint violation, it means that a record was inserted into a dependent table (e.g. `track`, `chapter`, `bookmark`, `flashcard`, `timeline_item`, `playback_event`, `playback_state`) with an `audiobook_id` that does not exist in the parent `audiobook` table.

### Triage Steps

1. **Identify the violating table and column**:
   Look at the test code or assertion failure. If it inserts a mock record (such as `TimelineItem` or `BookmarkRecord`), note its `audiobook_id`.
   
2. **Review the schema reference**:
   - `timeline_item` (introduced in V4 Schema) has foreign keys referencing `audiobook.id`.
   - `bookmark` has `audiobook_id` referencing `audiobook.id`.
   - `flashcard` has `audiobook_id` referencing `audiobook.id`.
   - `track` has `audiobook_id` referencing `audiobook.id`.

3. **Remediation**:
   Ensure the test's `setUp()` or database initialization block inserts a parent `Audiobook` record **before** inserting any dependent child records.
   
   **Example Fix in Swift Test Cases:**
   ```swift
   let dbQueue = try DatabaseQueue()
   try Schema_V1.migrate(dbQueue)
   // ... apply other migrations V2, V3, V4, V5 ...
   
   try dbQueue.write { db in
       // 1. Insert parent Audiobook first!
       let audiobook = Audiobook(id: "test-audiobook-id", title: "Test Title", author: "Test Author", duration: 600)
       try audiobook.insert(db)
       
       // 2. Now it is safe to insert dependent records referencing "test-audiobook-id"
       let bookmark = Bookmark(id: "bookmark-1", audiobookId: "test-audiobook-id", title: "Sample Bookmark", mediaTimestamp: 120.0)
       try bookmark.insert(db)
   }
   ```
