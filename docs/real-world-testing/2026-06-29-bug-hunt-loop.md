# MacroMark bug hunt loop - issue + fix log - 2026-06-29

## Current access snapshot

- Repo: `dfakkeldy/MacroMark`
- Integration branch: `nightly`
- Base commit at start: `f6c5b31a039ab9411d991844bc5efe10f998581a`
- Cycle branch: `bug-hunt-loop/2026-06-29-cycle-1`
- Dirty state: clean at cycle start
- Build under test: Xcode 26.6 (17F113), iOS/watchOS 26.5 simulator runtimes
- Device / OS: iPhone 17 Pro and iPhone 17 booted; watchOS 26.5 simulators available
- Live service: GitHub authenticated as `dfakkeldy`; iCloud and WatchConnectivity tested through code/build/test surfaces unless noted
- Credentials policy: no secrets, tokens, signed URLs, or private account details recorded
- Local tool gaps: none known at start; `/opt/local/bin/gtimeout` available for capped probes

## Cycle log

| Cycle | Start | Base nightly commit | Issues filed | PR | CI result | Merge | Quiet-timer at close |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2026-06-29 01:04 ADT | `f6c5b31a039ab9411d991844bc5efe10f998581a` | MM-051...MM-058 / #79...#86 | Pending | Pending | Pending | Pending |

## Verification run log

| Time | Command / check | Result | Notes |
| --- | --- | --- | --- |
| 2026-06-29 01:04 ADT | `git fetch origin`; branch from `origin/nightly` | Passed | Cycle branch created from fresh nightly base. |
| 2026-06-29 01:04 ADT | `xcodebuild -version` | Passed | Xcode 26.6 (17F113). |
| 2026-06-29 01:04 ADT | `xcrun simctl list devices available` | Passed | iOS 26.5 and watchOS 26.5 simulators available. |
| 2026-06-29 01:04 ADT | Project settings review | Passed | Xcode targets use iOS/watchOS 26.5 deployment settings and Swift 6.0; `MacroMarkKit` uses Swift tools 6.2 with language mode v6. |
| 2026-06-29 01:05 ADT | `swift test --package-path MacroMarkKit` | Passed | Baseline package tests: 38 tests in 13 suites. |
| 2026-06-29 01:06 ADT | `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build` | Passed | Baseline iOS generic build succeeded. |
| 2026-06-29 01:07 ADT | `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build` | Passed | Baseline watchOS generic build succeeded; device-service warning only. |
| 2026-06-29 01:08 ADT | `xcodebuild test -project MacroMark.xcodeproj -scheme "MacroMark" -destination 'platform=iOS Simulator,id=911C3FE7-CEF8-4EBF-8F74-287CFB0AEAAA' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` | Passed | Baseline iOS app/UI tests succeeded. |
| 2026-06-29 01:10 ADT | `xcodebuild test -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` | Passed | Baseline watch tests succeeded; SwiftUI runtime warnings captured for later triage. |
| 2026-06-29 01:11 ADT | `python3 -m unittest discover -s Scripts/doc_automation/tests -t Scripts -v` | Passed | Baseline doc automation tests: 14 tests. |
| 2026-06-29 01:29 ADT | `swift test --package-path MacroMarkKit` | Passed | Post-fix package tests: 39 tests in 14 suites, including invalid bookmark cleanup. |
| 2026-06-29 01:29 ADT | `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark" -configuration Debug -destination 'generic/platform=iOS' build` | Passed | Post-fix iOS generic build succeeded. |
| 2026-06-29 01:30 ADT | `xcodebuild -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -configuration Debug -destination 'generic/platform=watchOS' build` | Passed | Post-fix watchOS generic build succeeded. |
| 2026-06-29 01:32 ADT | `xcodebuild test -project MacroMark.xcodeproj -scheme "MacroMark" -destination 'platform=iOS Simulator,id=911C3FE7-CEF8-4EBF-8F74-287CFB0AEAAA' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` | Passed | Post-fix iOS app/unit tests (9) and UI tests (7) succeeded. |
| 2026-06-29 01:35 ADT | `xcodebuild test -project MacroMark.xcodeproj -scheme "MacroMark Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1` | Passed | Post-fix watch tests: 8 tests, including mixed WatchKit text input extraction. Same SwiftUI runtime warnings as baseline. |
| 2026-06-29 01:35 ADT | `python3 -m unittest discover -s Scripts/doc_automation/tests -t Scripts -v` | Passed | Post-fix doc automation tests: 14 tests. |
| 2026-06-29 01:35 ADT | `git diff --check` | Passed | No whitespace errors. |

## Real asset inventory

- Total items checked: 8 newly filed issues plus baseline verification across package, iOS, watchOS, UI, and doc-automation surfaces
- Representative small asset: watch text input result payloads and custom bookmark data
- Representative large asset: watch audio delivery file handoff during active transcription
- Missing metadata / cover: Not applicable unless file export/import assets are added
- Mixed media: text capture WAL and audio capture file/WAL handoffs
- Multi-file: watch-to-iPhone delivery, pending export retry, and macro settings persistence
- Document-only: Markdown daily-note export/read fallback behavior
- Long-running / edge case: stale pending export cleanup, stale input WAL replay, cancelled daily-log loads, and invalid folder bookmarks

## Issue + fix log

| ID | Cycle | Time | Area | Severity | Status | GitHub | Fix commit / PR | Summary | Evidence | Suspected code area |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MM-051 | 1 | 2026-06-29 01:28 ADT | Custom folder export | High | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/79 | Pending | Invalid custom-folder bookmarks remain stored and can make fallback exports/read fail. | `resolvedBaseDirectory()` left unresolvable bookmark data in `UserDefaults`; append/read then treated fallback storage as security-scoped. | `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift` |
| MM-052 | 1 | 2026-06-29 01:28 ADT | Watch capture durability | High | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/80 | Pending | Text WAL write failure leaves a watch note stuck in the in-flight set until restart. | `handleIncomingNote` inserted into `inFlightIDs` before `writePendingProcessing` could throw. | `MacroMark/MacroMarkApp.swift` |
| MM-053 | 1 | 2026-06-29 01:28 ADT | Watch audio delivery | High | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/81 | Pending | Duplicate audio delivery can replace the file being transcribed and then skip reprocessing. | Duplicate guard lived in `processAudio`, after `handleIncomingAudio` had already replaced the durable destination file. | `MacroMark/MacroMarkApp.swift` |
| MM-054 | 1 | 2026-06-29 01:28 ADT | Watch replay / WAL cleanup | Medium | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/82 | Pending | Already-processed watch replays leave stale input WAL entries behind. | Already-processed branches ACKed and returned without clearing stale `pendingProcessing` / `pendingAudio` rows. | `MacroMark/MacroMarkApp.swift` |
| MM-055 | 1 | 2026-06-29 01:28 ADT | Export retry idempotency | High | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/83 | Pending | Stale pending-export records can append an already-exported note again. | Retry loop did not skip `processedNoteIDs` or exported stored notes before calling `performExport`. | `MacroMark/MacroMarkApp.swift` |
| MM-056 | 1 | 2026-06-29 01:28 ADT | watchOS standard capture | Medium | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/84 | Pending | Standard watch dictation drops non-string text input results. | Completion handler cast `result` directly to `[String]`, treating mixed `[Any]` payloads as cancellation. | `MacroMark Watch App/Capture/SystemCaptureView.swift` |
| MM-057 | 1 | 2026-06-29 01:28 ADT | Watch daily log | Medium | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/85 | Pending | Cancelled watch daily-log loads can publish stale content for the wrong selected day. | `.task(id:)` cancelled old loads, but `loadLog()` used mutable `selectedDate` after awaits and did not check cancellation. | `MacroMark Watch App/Capture/DailyLogView.swift` |
| MM-058 | 1 | 2026-06-29 01:28 ADT | Macro settings durability | Medium | Fixed locally; verification passed | https://github.com/dfakkeldy/MacroMark/issues/86 | Pending | Macro add/edit/reorder/delete paths rely on autosave instead of making Save durable. | Add/edit dismissed without `modelContext.save()`; delete/reorder mutated models without explicit save. | `MacroMark/Settings/AddMacroView.swift`, `MacroMark/Settings/MacroEditView.swift`, `MacroMark/Settings/MacroManagerView.swift` |
