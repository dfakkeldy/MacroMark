# MacroMark real-world test plan and issue log - 2026-06-28

## Current access snapshot

- Repo: `/Users/dfakkeldy/.codex/worktrees/6ab2/MacroMark`
- Remote: `https://github.com/dfakkeldy/MacroMark.git`
- Branch / commit: detached `HEAD` at `3bba8a244848ce04066ec84a1854d50f0646ed5b` (`origin/nightly`)
- Dirty state at start: clean
- Build under test: local Debug builds from current source
- Deployment targets: Xcode project iOS 26.5, watchOS 26.5; `MacroMarkKit` iOS 26.0, watchOS 11.0, macOS 14.0
- Swift / Xcode: Xcode 26.6 build 17F113; Apple Swift 6.3.3; `MacroMarkKit` tools 6.2 and Swift language mode v6
- Device / OS inventory: booted iPhone 17 simulator on iOS 26.5; available watchOS 26.5 simulators include Series 11, Ultra 3, and SE 3
- Live service: iCloud Documents, StoreKit, Speech, CoreLocation, and WatchConnectivity. Treat live-service operations as read-only unless mutation is explicitly approved.
- Credentials policy: no secrets, tokens, signed URLs, private account details, or personal identifiers in this ledger, issue bodies, or logs
- GitHub issue baseline: `gh issue list --state all --limit 200` returned no issues
- Local tool gaps: no Xcode MCP build/read tools exposed; use repo-documented `xcodebuild` and `swift test` gates serially

## Coverage matrix

| Area | Real-world checks planned |
| --- | --- |
| First launch and permissions | Speech authorization, location authorization, iCloud availability, watch connectivity activation, offline starts |
| Capture inputs | Typed notes, dictated notes, recorded audio, empty captures, emoji/moji, long recordings, interruption/backgrounding |
| Durability pipeline | Watch `LocalStore`, queued note IDs, queued audio IDs, WAL pending note/audio maps, ACK loss, duplicate replay, app restart replay |
| Processing | Macro expansion, macro edit/delete/restore behavior, `{date}`, `{time}`, `{newline}`, `{location}`, formatting cleanup, concurrent processing |
| Export | iCloud daily-note append, unmaterialized placeholders, custom folder security scope, URL export, export state persistence, fallback storage |
| Targets | iOS app build/tests, watch app build/tests, widget build, shared package tests, release/screenshot/metadata automation |
| Accessibility/layout | Dynamic Type, dark/light mode, contrast, tappable controls, watch small sizes, iPad/wide layouts, missing labels |
| Independent validation | `swift test`, serialized `xcodebuild`, `plutil`, `jq`, source-backed tests, simulator/device logs where useful |

## Verification run log

| Time | Command / check | Result | Notes |
| --- | --- | --- | --- |
| 2026-06-28 20:23 ADT | `git status --short --branch` | Passed | Detached clean `HEAD`; commit matches `origin/nightly`. |
| 2026-06-28 20:23 ADT | `ps -axo pid,command | rg '[x]codebuild|[s]wift test|[s]wift-build'` | Passed | No active build/test processes; serialized build gate is safe to start. |
| 2026-06-28 20:23 ADT | `xcodebuild -version`; `swift --version` | Passed | Xcode 26.6 / Swift 6.3.3. |
| 2026-06-28 20:23 ADT | `rg` deployment/language settings | Passed | Project uses iOS/watchOS 26.5, Swift 6.0 build setting, MainActor default isolation on app/watch/test targets; package uses tools 6.2 and `swiftLanguageModes: [.v6]`. |
| 2026-06-28 20:23 ADT | `gh issue list --state all --limit 200 --json ...` | Passed | No open or closed GitHub issues found, so validated findings can become new issues if the user wants issue creation. |
| 2026-06-28 20:23 ADT | `xcrun simctl list devices available` | Passed | Booted iPhone 17 iOS 26.5 simulator; watchOS 26.5 simulators available but shutdown. |
| 2026-06-28 20:25 ADT | `swift test --package-path MacroMarkKit` | Passed | 26 package tests passed; log: `/tmp/macromark-swift-test-20260628.log`. |
| 2026-06-28 20:26 ADT | `xcodebuild ... -scheme "MacroMark" -destination 'generic/platform=iOS' build` | Passed | iOS Debug generic build succeeded; log: `/tmp/macromark-ios-build-20260628.log`. |
| 2026-06-28 20:26 ADT | `xcodebuild ... -scheme "MacroMark Watch App" -destination 'generic/platform=watchOS' build` | Passed | watchOS Debug generic build succeeded; log: `/tmp/macromark-watch-build-20260628.log`. |
| 2026-06-28 20:27 ADT | `xcodebuild test ... -scheme "MacroMark" -destination 'platform=iOS Simulator,id=0512CA9A-6DE9-46AC-8D90-EBB6ED8656EB'` | Failed | 5 failed tests, 0 passed. Result bundle: `/tmp/MacroMark-iOS-Tests-20260628.xcresult`; log: `/tmp/macromark-ios-tests-20260628.log`. |
| 2026-06-28 20:30 ADT | Crash report inspection | Failed | `MacroMark-2026-06-28-203003.ips` shows `EXC_BREAKPOINT` / `SIGTRAP` on `com.apple.coredata.cloudkit.queue` in `PFCloudKitContainerProvider`. |
| 2026-06-28 20:34 ADT | URL query encoding probe | Failed | `String.addingPercentEncoding(.urlQueryAllowed)` left `&`, `=`, and `+` unescaped inside query values. |
| 2026-06-28 20:40 ADT | `xcodebuild test ... -scheme "MacroMark Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5'` | Passed | 3 watch tests passed; runtime emitted watch UI warnings but no test failures. Result bundle: `/tmp/MacroMark-Watch-Tests-20260628.xcresult`; log: `/tmp/macromark-watch-tests-20260628.log`. |

## Real asset inventory

- Total items checked: 50 validated bug scenarios across app launch, tests, watch capture, export retry, macros, iCloud storage, App Intents/shortcuts, widgets, CI, and fastlane.
- Representative small asset: text note and macro strings containing `&`, `=`, `+`, punctuation triggers, whitespace triggers, and common-word macro triggers.
- Representative large asset: watch audio capture and transcription paths, including multi-chunk speech recognition and pending audio queue behavior.
- Missing metadata / permission edge: CloudKit entitlement/background mode mismatch, security-scoped folder access, speech/location permission fallback, and capture-mode WatchConnectivity sync.
- Mixed media: typed notes, watch audio, iCloud Markdown daily notes, URL-scheme exports, widgets/complications, and screenshot automation.
- Multi-file: Xcode app/watch/widget targets, `MacroMarkKit`, UI tests, fastlane, GitHub Actions, entitlements, and Info.plist.
- Document-only: release metadata and automation reviewed for screenshots, TestFlight release trains, and CI gate coverage.
- Long-running / edge case: pending export retry, launch reprocessing, background task expiration, watch ACK loss/replay, and speech-recognition hangs.

## GitHub issue filing

Filed 50 GitHub issues from this ledger on 2026-06-28. The repository had no existing open or closed issues before filing.

| Audit ID | GitHub issue |
| --- | --- |
| MM-001 | https://github.com/dfakkeldy/MacroMark/issues/23 |
| MM-002 | https://github.com/dfakkeldy/MacroMark/issues/24 |
| MM-003 | https://github.com/dfakkeldy/MacroMark/issues/25 |
| MM-004 | https://github.com/dfakkeldy/MacroMark/issues/26 |
| MM-005 | https://github.com/dfakkeldy/MacroMark/issues/27 |
| MM-006 | https://github.com/dfakkeldy/MacroMark/issues/28 |
| MM-007 | https://github.com/dfakkeldy/MacroMark/issues/29 |
| MM-008 | https://github.com/dfakkeldy/MacroMark/issues/30 |
| MM-009 | https://github.com/dfakkeldy/MacroMark/issues/31 |
| MM-010 | https://github.com/dfakkeldy/MacroMark/issues/32 |
| MM-011 | https://github.com/dfakkeldy/MacroMark/issues/33 |
| MM-012 | https://github.com/dfakkeldy/MacroMark/issues/34 |
| MM-013 | https://github.com/dfakkeldy/MacroMark/issues/35 |
| MM-014 | https://github.com/dfakkeldy/MacroMark/issues/36 |
| MM-015 | https://github.com/dfakkeldy/MacroMark/issues/37 |
| MM-016 | https://github.com/dfakkeldy/MacroMark/issues/38 |
| MM-017 | https://github.com/dfakkeldy/MacroMark/issues/39 |
| MM-018 | https://github.com/dfakkeldy/MacroMark/issues/40 |
| MM-019 | https://github.com/dfakkeldy/MacroMark/issues/41 |
| MM-020 | https://github.com/dfakkeldy/MacroMark/issues/42 |
| MM-021 | https://github.com/dfakkeldy/MacroMark/issues/43 |
| MM-022 | https://github.com/dfakkeldy/MacroMark/issues/44 |
| MM-023 | https://github.com/dfakkeldy/MacroMark/issues/45 |
| MM-024 | https://github.com/dfakkeldy/MacroMark/issues/46 |
| MM-025 | https://github.com/dfakkeldy/MacroMark/issues/47 |
| MM-026 | https://github.com/dfakkeldy/MacroMark/issues/48 |
| MM-027 | https://github.com/dfakkeldy/MacroMark/issues/49 |
| MM-028 | https://github.com/dfakkeldy/MacroMark/issues/50 |
| MM-029 | https://github.com/dfakkeldy/MacroMark/issues/51 |
| MM-030 | https://github.com/dfakkeldy/MacroMark/issues/52 |
| MM-031 | https://github.com/dfakkeldy/MacroMark/issues/53 |
| MM-032 | https://github.com/dfakkeldy/MacroMark/issues/54 |
| MM-033 | https://github.com/dfakkeldy/MacroMark/issues/55 |
| MM-034 | https://github.com/dfakkeldy/MacroMark/issues/56 |
| MM-035 | https://github.com/dfakkeldy/MacroMark/issues/57 |
| MM-036 | https://github.com/dfakkeldy/MacroMark/issues/58 |
| MM-037 | https://github.com/dfakkeldy/MacroMark/issues/59 |
| MM-038 | https://github.com/dfakkeldy/MacroMark/issues/60 |
| MM-039 | https://github.com/dfakkeldy/MacroMark/issues/61 |
| MM-040 | https://github.com/dfakkeldy/MacroMark/issues/62 |
| MM-041 | https://github.com/dfakkeldy/MacroMark/issues/63 |
| MM-042 | https://github.com/dfakkeldy/MacroMark/issues/64 |
| MM-043 | https://github.com/dfakkeldy/MacroMark/issues/65 |
| MM-044 | https://github.com/dfakkeldy/MacroMark/issues/66 |
| MM-045 | https://github.com/dfakkeldy/MacroMark/issues/67 |
| MM-046 | https://github.com/dfakkeldy/MacroMark/issues/68 |
| MM-047 | https://github.com/dfakkeldy/MacroMark/issues/69 |
| MM-048 | https://github.com/dfakkeldy/MacroMark/issues/70 |
| MM-049 | https://github.com/dfakkeldy/MacroMark/issues/71 |
| MM-050 | https://github.com/dfakkeldy/MacroMark/issues/72 |

## Issue log

| ID | Time | Area | Severity | Asset | Environment | Status | Summary | Evidence | Suspected code area |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MM-001 | 2026-06-28 20:30 ADT | Launch / SwiftData | Critical | Production iOS app | iPhone 17 simulator, iOS 26.5 | Validated | Production launch can trap because SwiftData starts CloudKit mirroring while the app entitlement only declares CloudDocuments. | iOS test crash `EXC_BREAKPOINT` on `com.apple.coredata.cloudkit.queue`; log reports missing CloudKit entitlement. | `MacroMark/MacroMarkApp.swift:101`, `MacroMark/MacroMark.entitlements:9` |
| MM-002 | 2026-06-28 20:30 ADT | Launch / CloudKit | High | Production iOS app | iPhone 17 simulator, iOS 26.5 | Validated | If CloudKit mirroring is intended, the app also lacks the `remote-notification` background mode required for CloudKit push notifications. | iOS log: `BUG IN CLIENT OF CLOUDKIT: CloudKit push notifications require the 'remote-notification' background mode`. | `MacroMark/Info.plist:44`, `MacroMark/MacroMarkApp.swift:110` |
| MM-003 | 2026-06-28 20:30 ADT | Launch resilience | High | SwiftData fallback | Source review | Validated | The last-resort storage fallback says the app "must not crash" but still uses `try!`, so a final container failure remains fatal. | Source has `resolvedContainer = try! ModelContainer(...)` inside the unrecoverable fallback. | `MacroMark/MacroMarkApp.swift:124` |
| MM-004 | 2026-06-28 20:30 ADT | UI tests | High | iOS scheme | iPhone 17 simulator, iOS 26.5 | Validated | The normal UI tests launch the production app with live storage instead of an isolated test/screenshot mode, making the test suite crash on CloudKit setup. | xcresult: 5 failed tests, 0 passed; template UI tests call `app.launch()` without isolation arguments. | `MacroMarkUITests/MacroMarkUITests.swift:25`, `MacroMarkUITests/MacroMarkUITestsLaunchTests.swift:20` |
| MM-005 | 2026-06-28 20:28 ADT | Screenshots | High | App Store screenshot test | iPhone 17 simulator, iOS 26.5 | Validated | Screenshot mode does not deterministically seed visible data before the screenshot test waits for `Standup`. | `testAppStoreScreenshots` failed at `XCTAssertTrue` waiting for `Standup`; seeding happens later in `AppTabView.task`. | `MacroMarkUITests/MacroMarkScreenshotUITests.swift:18`, `MacroMark/Views/AppTabView.swift:23`, `MacroMark/Shared/ScreenshotMode.swift:30` |
| MM-006 | 2026-06-28 20:28 ADT | Screenshots / release | High | fastlane screenshot lane | Source plus failed UI test | Validated | The fastlane screenshot and screenshot release lanes are wired to the currently failing screenshot UI test, so screenshot generation/upload is blocked. | Fastfile `only_testing` points at `MacroMarkScreenshotUITests/testAppStoreScreenshots`, which failed locally. | `fastlane/Fastfile:188`, `fastlane/Snapfile:25` |
| MM-007 | 2026-06-28 20:37 ADT | Release automation | High | Release Trains workflow | GitHub Actions source review | Validated | Release trains can upload to TestFlight after only build and package-test gates; they skip app-hosted iOS tests and UI tests that currently expose a launch crash. | Workflow runs build-for-testing, watch build, and package tests before upload; no `xcodebuild test` step. | `.github/workflows/release-trains.yml:135`, `.github/workflows/release-trains.yml:157`, `.github/workflows/release-trains.yml:167` |
| MM-008 | 2026-06-28 20:37 ADT | Release automation | Medium | fastlane beta lane | Source review | Validated | The `beta` lane builds and uploads without invoking the test lane or any build gate first. | `lane :beta` goes from signing/build number/build_app directly to `upload_to_testflight`. | `fastlane/Fastfile:106` |
| MM-009 | 2026-06-28 20:33 ADT | Export retry | High | Pending exports | Source review | Validated | Pending export entries do not persist the destination target that originally failed, so retries are redirected to whatever destination is currently selected. | `PendingExport` has note text/date/audio fields only; retry reads `defaultExportTarget` each time. | `MacroMark/MacroMarkApp.swift:36`, `MacroMark/MacroMarkApp.swift:708` |
| MM-010 | 2026-06-28 20:33 ADT | Export retry | High | Pending exports | Source review | Validated | `ProcessedNote` has no durable source/watch UUID, forcing retry logic to infer identity from timestamp and text. | Model fields omit source ID; retry fetch uses exact `createdAt` and `text`. | `MacroMarkKit/Sources/MacroMarkKit/Models/ProcessedNote.swift:4`, `MacroMark/MacroMarkApp.swift:767` |
| MM-011 | 2026-06-28 20:33 ADT | Export retry | High | Edited queued note | Source review | Validated | Editing a note while its export is queued can make retry export stale WAL text and fail to update the edited SwiftData row. | Detail editor changes `note.text`; retry later matches old `entry.processedText`. | `MacroMark/Views/NoteDetailView.swift:17`, `MacroMark/MacroMarkApp.swift:721`, `MacroMark/MacroMarkApp.swift:767` |
| MM-012 | 2026-06-28 20:33 ADT | Export retry | High | Missing SwiftData row | Source review | Validated | If the stored row is missing, retry creates an uninserted `ProcessedNote`, may export successfully, then ACK/cleanup without restoring the Inbox record. | Fallback `ProcessedNote(...)` is passed to `performExport` but not inserted; cleanup still runs on success. | `MacroMark/MacroMarkApp.swift:720`, `MacroMark/MacroMarkApp.swift:731` |
| MM-013 | 2026-06-28 20:33 ADT | Shortcuts / export | Medium | Append text shortcut | Source review | Validated | Shortcut-created pending exports use a fresh UUID that is not stored on the `ProcessedNote`, so retry relies entirely on fragile timestamp/text matching. | `shortcutNoteID = UUID()` is separate from the inserted note. | `MacroMark/MacroMarkApp.swift:788`, `MacroMark/MacroMarkApp.swift:823` |
| MM-014 | 2026-06-28 20:33 ADT | Export state | High | Third-party targets | Source review | Validated | With a non-iCloud target and auto-export disabled, captures are marked exported even though no delivery occurred. | `performExport` calls `markExported` after "nothing to do". | `MacroMark/MacroMarkApp.swift:600`, `MacroMark/MacroMarkApp.swift:611` |
| MM-015 | 2026-06-28 20:33 ADT | Export state | High | Third-party targets | Source review | Validated | URL-scheme exports are marked saved when `UIApplication.open` succeeds, but opening the target app is not confirmation that the note was created. | Both automatic export and manual detail export use the `open` Boolean as final delivery. | `MacroMark/MacroMarkApp.swift:601`, `MacroMark/Views/NoteDetailView.swift:88` |
| MM-016 | 2026-06-28 20:34 ADT | URL export | High | Third-party targets | Swift probe plus source review | Validated | Export URL query values are incorrectly percent-encoded; `&`, `=`, and `+` inside note text can split or mutate the destination query. | Swift probe showed `Title & details` stays `Title%20&%20details`; code uses `.urlQueryAllowed`. | `MacroMarkKit/Sources/MacroMarkKit/Engine/ExportManager.swift:5` |
| MM-017 | 2026-06-28 20:33 ADT | Manual export | High | Note detail retry | Source review | Validated | Manual iCloud export from the detail screen marks `.deferred` or `.failed` but does not create a `PendingExport`, so background retry has nothing to process. | Failure path updates status and saves only. | `MacroMark/Views/NoteDetailView.swift:105` |
| MM-018 | 2026-06-28 20:33 ADT | Future notes | High | Future note composer | Source review | Validated | Future-note iCloud export failure/defer also writes no `PendingExport`, so the note is not actually queued for retry. | Failure/defer paths save status only. | `MacroMark/Views/FutureNoteComposerView.swift:80` |
| MM-019 | 2026-06-28 20:33 ADT | Future notes | Medium | Future note composer | Source review | Validated | Future-note failure text says "The original capture is still queued for retry", but future notes have no original watch capture WAL. | Message is set in `.failed` without adding a retry queue entry. | `MacroMark/Views/FutureNoteComposerView.swift:99` |
| MM-020 | 2026-06-28 20:33 ADT | WAL durability | High | Pending processing/audio/export WAL | Source review | Validated | WAL write helpers silently ignore JSON encoding or UserDefaults write failure and processing proceeds as if durable state exists. | Each writer only sets UserDefaults inside `if let data = try? ...` with no failure return. | `MacroMark/MacroMarkApp.swift:454`, `MacroMark/MacroMarkApp.swift:470`, `MacroMark/MacroMarkApp.swift:694` |
| MM-021 | 2026-06-28 20:33 ADT | WAL atomicity | High | Watch capture retry | Source review | Validated | A crash after SwiftData save but before `PendingExport` is added leaves the input WAL intact; next launch can create a duplicate SwiftData note. | `context.save()` happens before export and before pending export insertion. | `MacroMark/MacroMarkApp.swift:519`, `MacroMark/MacroMarkApp.swift:553` |
| MM-022 | 2026-06-28 20:33 ADT | ACK / persistence | High | Export success path | Source review | Validated | `markExported` and `markExportPending` swallow SwiftData save errors; callers can continue toward ACK/cleanup while the visible status was not persisted. | Save errors are only debug-printed. | `MacroMark/MacroMarkApp.swift:627`, `MacroMark/MacroMarkApp.swift:642` |
| MM-023 | 2026-06-28 20:33 ADT | Deduplication | Medium | Processed note ID cache | Source review | Validated | The processed-ID cap is documented as LRU but evicts arbitrary `Set.first`, which can drop recent IDs and allow duplicate replay sooner than intended. | `while processed.count > ... let first = processed.first`. | `MacroMark/MacroMarkApp.swift:198` |
| MM-024 | 2026-06-28 20:33 ADT | Launch retry | Medium | App startup | Source review | Validated | Pending items are reprocessed once in `init` and again from the scene `.task`, creating a duplicate launch retry path. | `init` calls `reprocessPendingItems`; `.task` calls `reprocessAndRetry`, which calls it again. | `MacroMark/MacroMarkApp.swift:149`, `MacroMark/MacroMarkApp.swift:247`, `MacroMark/MacroMarkApp.swift:900` |
| MM-025 | 2026-06-28 20:33 ADT | Backgrounding | High | Watch capture processing | Source review | Validated | Background task expiration removes the note ID from `inFlightIDs` while the processing task can still continue, allowing a resend/reprocess to start concurrently. | Expiration handler removes `inFlightIDs` but does not cancel the task. | `MacroMark/MacroMarkApp.swift:336` |
| MM-026 | 2026-06-28 20:35 ADT | Custom folder export | High | Security-scoped bookmarks | Source review | Validated | Custom-folder export/read ignores `startAccessingSecurityScopedResource()` failure and still tries to access the URL. | Return value is assigned to `_` in both append and read paths. | `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:118`, `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:221` |
| MM-027 | 2026-06-28 20:35 ADT | iCloud export performance | Medium | Daily note append | Source review | Validated | iCloud coordination, `FileHandle` writes, and new-file writes run on the `@MainActor`, which can freeze UI during slow iCloud/file coordination. | Class is `@MainActor`; synchronous file work happens inside `appendText`. | `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:18`, `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:148` |
| MM-028 | 2026-06-28 20:35 ADT | Daily log read | Low | iCloud read | Source review | Validated | Reading a daily note can create monthly/yearly directories as a side effect because `readText` calls `fileURL`, which creates folders. | `fileURL` calls `createDirectory`; `readText` calls `fileURL`. | `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:82`, `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:231` |
| MM-029 | 2026-06-28 20:36 ADT | Settings UI | Medium | Folder Settings preview | Source review | Validated | Folder Settings examples show paths that do not match actual export paths and duplicate the formatted date as a folder. | Preview prefixes `Notes/<formatted date>/...`; storage uses structure folders plus filename. | `MacroMark/Settings/FolderSettingsView.swift:75`, `MacroMarkKit/Sources/MacroMarkKit/Storage/iCloudStorageManager.swift:82` |
| MM-030 | 2026-06-28 20:36 ADT | Settings / file naming | Medium | Folder Settings date format | Source review | Validated | Date format input is saved without validation or sanitization, so users can create empty/unsafe/ambiguous filenames or accidental folder-like names. | Text field accepts arbitrary text; `FolderSettings.format` returns raw replaced output. | `MacroMark/Settings/FolderSettingsView.swift:36`, `MacroMarkKit/Sources/MacroMarkKit/Models/FolderSettings.swift:28` |
| MM-031 | 2026-06-28 20:36 ADT | Watch audio capture | High | Instant capture | Source review | Validated | During the first second of recording, `recordingURL` is still nil; if the user finishes/backgrounds then, the file is stopped but never enqueued. | Recorder starts at line 38, sleeps, then sets URL at line 50; finish returns nil and dismisses. | `MacroMark Watch App/Capture/AudioRecorder.swift:38`, `MacroMark Watch App/Capture/InstantCaptureView.swift:53` |
| MM-032 | 2026-06-28 20:36 ADT | Speech transcription | Critical | Long audio / Speech framework | Source review | Validated | A speech recognition task that never returns final text or error can hang forever; there is no timeout around each chunk recognition continuation. | Handler ignores non-final/no-error results and no sleeper resumes the continuation. | `MacroMark/Engine/AudioTranscriber.swift:64` |
| MM-033 | 2026-06-28 20:36 ADT | Location macro | Medium | Concurrent captures with `{location}` | Source review | Validated | Concurrent location requests cause all but the first caller to immediately get nil, so simultaneous notes can expand `{location}` to Unknown Location. | `guard !isRequestingLocation else { return nil }`. | `MacroMark/Engine/LocationManager.swift:26` |
| MM-034 | 2026-06-28 20:36 ADT | Watch queue durability | High | `LocalStore` cold launch | Source review | Validated | Loading `pendingNotes` triggers `didSet save()` before queued IDs/audio are restored, which can overwrite persisted queued state with empty sets. | `pendingNotes` didSet saves; `load()` assigns it before restoring queued IDs and audio. | `MacroMark Watch App/Storage/LocalStore.swift:23`, `MacroMark Watch App/Storage/LocalStore.swift:207` |
| MM-035 | 2026-06-28 20:36 ADT | Watch audio queue | High | Pending audio | Source review | Validated | If a pending audio metadata row points to a missing file, sync just skips it forever instead of pruning or surfacing a recoverable error. | `guard FileManager.default.fileExists(...) else { continue }`. | `MacroMark Watch App/Storage/LocalStore.swift:140` |
| MM-036 | 2026-06-28 20:36 ADT | Watch sync | Medium | ACK loss reconciliation | Source review | Validated | After a queued item is older than 24 hours, every sync calls `queryProcessed` again without backoff or updating the query timestamp. | Reconciliation branches query then immediately continue. | `MacroMark Watch App/Storage/LocalStore.swift:77`, `MacroMark Watch App/Storage/LocalStore.swift:140` |
| MM-037 | 2026-06-28 20:36 ADT | Watch audio queue | Medium | Pending audio | Source review | Validated | `enqueueAudio` appends a `PendingAudio` row every time for a UUID, so duplicate enqueue calls can create duplicate metadata entries for one durable file. | Existing destination is removed, then a new row is appended without replacing older rows. | `MacroMark Watch App/Storage/LocalStore.swift:114` |
| MM-038 | 2026-06-28 20:36 ADT | Watch daily log | Medium | Offline audio captures | Source review | Validated | The watch daily log includes pending text notes but not pending audio captures, so offline recordings are invisible until the phone transcribes them. | `DailyLogView` only iterates `LocalStore.shared.pendingNotes`. | `MacroMark Watch App/Capture/DailyLogView.swift:39`, `MacroMark Watch App/Storage/LocalStore.swift:31` |
| MM-039 | 2026-06-28 20:36 ADT | WatchConnectivity | Medium | Malformed transfer metadata | Source review | Validated | Incoming userInfo/file payloads with missing or bad IDs are assigned new UUIDs, so ACK/dedup can never match the watch-side original. | ID parsing falls back to `UUID()`. | `MacroMark/Shared/WatchConnectivityProvider.swift:166`, `MacroMark/Shared/WatchConnectivityProvider.swift:189` |
| MM-040 | 2026-06-28 20:36 ADT | Watch daily log cache | Medium | Phone daily-file read failure | Source review | Validated | A transient phone-side read failure returns an empty string and the watch caches it, overwriting a previously useful cached daily log. | iOS reply uses `readText(...) ?? ""`; watch caches every reply. | `MacroMark/Shared/WatchConnectivityProvider.swift:306`, `MacroMark/Shared/WatchConnectivityProvider.swift:338` |
| MM-041 | 2026-06-28 20:36 ADT | Watch daily log cache | Low | Daily-file fetch | Source review | Validated | The 15-second timeout task in `fetchDailyFile` is not cancelled when a reply/error completes first, leaving unnecessary sleeper tasks after successful fetches. | Timeout task is created and never cancelled. | `MacroMark/Shared/WatchConnectivityProvider.swift:295` |
| MM-042 | 2026-06-28 20:36 ADT | Settings sync | Medium | Watch double tap mode | Source review | Validated | Capture-mode changes are dropped if `WCSession` is not activated at that instant; there is no retry or local pending application-context update. | `updateSettings` returns when activation is not `.activated`. | `MacroMark/Shared/WatchConnectivityProvider.swift:139`, `MacroMark/Settings/MacroManagerView.swift:46` |
| MM-043 | 2026-06-28 20:36 ADT | Accessibility | Medium | Watch capture buttons | Source review | Validated | The primary watch capture buttons are image-only SwiftUI buttons without explicit accessible labels, so VoiceOver gets symbol-derived labels instead of the app actions. | Buttons use only `Image(systemName:)`. | `MacroMark Watch App/ContentView.swift:23`, `MacroMark Watch App/ContentView.swift:33` |
| MM-044 | 2026-06-28 20:36 ADT | Accessibility | Medium | Widget / complication | Source review | Validated | Widget views are image-only and do not set accessibility labels for Instant vs System capture. | Body is only `Image(systemName:)` plus `widgetURL`. | `MacroMarkWidget/MacroMarkWidget.swift:12`, `MacroMarkWidget/MacroMarkWidget.swift:22` |
| MM-045 | 2026-06-28 20:36 ADT | Macro defaults | High | Default macros | Source review | Validated | The default `Not` macro maps a common dictated word to `{backspace}`, so ordinary sentences containing "not" can delete preceding content. | Default macro notes admit accidental firing; processor applies triggers case-insensitively anywhere on word boundaries. | `MacroMark/Settings/MacroManagerView.swift:293`, `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:73` |
| MM-046 | 2026-06-28 20:36 ADT | Macro defaults | Low | Default macro ordering | Source review | Validated | `Heading Two` and `Heading To` both use `sortOrder: 1`, making initial ordering unstable or store-dependent. | Adjacent defaults share the same sort order. | `MacroMark/Settings/MacroManagerView.swift:264` |
| MM-047 | 2026-06-28 20:36 ADT | Macro editing | High | Custom macros | Source review | Validated | Add/edit screens do not prevent duplicate triggers, so two macros can fire for the same phrase and produce ambiguous or double replacements. | Save paths insert/apply trigger text without checking existing macros; model has no stable uniqueness. | `MacroMark/Settings/AddMacroView.swift:48`, `MacroMark/Settings/MacroEditView.swift:76`, `MacroMarkKit/Sources/MacroMarkKit/Models/Macro.swift:4` |
| MM-048 | 2026-06-28 20:36 ADT | Macro editing | Medium | Custom macros | Source review | Validated | Add/edit screens validate a trimmed trigger but save the untrimmed string, so accidental leading/trailing spaces create hard-to-trigger macros. | Disabled checks trim, but `Macro(trigger: trigger, ...)` and edits assign raw state. | `MacroMark/Settings/AddMacroView.swift:49`, `MacroMark/Settings/MacroEditView.swift:77` |
| MM-049 | 2026-06-28 20:36 ADT | Macro processing | Medium | Punctuation triggers | Source review | Validated | Macro triggers that begin or end with non-word characters, such as hashtags, `C++`, emoji, or punctuation commands, will not match reliably because every trigger is wrapped in `\b`. | Pattern is `\b<escaped trigger>\b` for all triggers. | `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:36` |
| MM-050 | 2026-06-28 20:36 ADT | Macro processing | Medium | Plain text/math/code captures | Source review | Validated | The wrapping-tag cleanup regex runs over the full processed note, so dictated math/code or literal punctuation like `3 * 4 * 5` can be rewritten as Markdown emphasis. | Global regex `([\*\_\~]+)\s+(.+?)\s+\1` is applied to every capture. | `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:23`, `MacroMarkKit/Sources/MacroMarkKit/Engine/MacroProcessor.swift:123` |
