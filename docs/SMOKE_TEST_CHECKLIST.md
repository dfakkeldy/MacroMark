# MacroMark Paired-Device Smoke Test Checklist

Last updated: 2026-07-02

Use this checklist on Dan's paired iPhone and Apple Watch before treating the first TestFlight build as launch-ready. Use staged demo notes only; do not capture personal addresses, routes, client data, or private notes during this test.

## Prerequisites

1. [ ] Pass / [ ] Fail - Install the same MacroMark build on the paired iPhone and Apple Watch.
   - Expected result: Both apps launch, the Watch app can open capture, and the iPhone app can open Settings and Inbox.
2. [ ] Pass / [ ] Fail - Configure the export destination to a test folder in iCloud Drive.
   - Expected result: Settings shows the selected destination and a daily-note filename pattern of `YYYY-MM-DD.md`.
3. [ ] Pass / [ ] Fail - Confirm the iPhone and Watch clocks show the correct local time.
   - Expected result: Timestamps can be compared without clock drift confusing the result.

## Offline Capture

4. [ ] Pass / [ ] Fail - Put the Apple Watch in Airplane Mode and confirm the iPhone is not reachable from the Watch.
   - Expected result: The Watch remains usable for capture even while offline.
5. [ ] Pass / [ ] Fail - Capture the voice note "Smoke test offline note one" from the Watch.
   - Expected result: The Watch capture completes without an error or data-loss warning.
6. [ ] Pass / [ ] Fail - Capture the voice note "Smoke test offline note two" from the Watch.
   - Expected result: The second capture also completes while the Watch is offline.
7. [ ] Pass / [ ] Fail - Force-quit the Watch app, reopen it, and inspect pending or daily-log state.
   - Expected result: Both offline captures remain queued or visible as pending/reviewable state; neither note disappears.

## Reconnect And Transfer

8. [ ] Pass / [ ] Fail - Disable Airplane Mode on the Watch and keep the iPhone nearby and unlocked.
   - Expected result: WatchConnectivity resumes without requiring a reinstall or app reset.
9. [ ] Pass / [ ] Fail - Wait for both offline captures to transfer to the iPhone.
   - Expected result: The iPhone Inbox receives both notes exactly once.
10. [ ] Pass / [ ] Fail - Open today's `YYYY-MM-DD.md` file in the configured iCloud Drive folder.
    - Expected result: Both demo notes are appended to today's Markdown file exactly once.
11. [ ] Pass / [ ] Fail - Compare the Inbox, Watch daily log, and Markdown file.
    - Expected result: The same two notes appear in all relevant review surfaces with no duplicate Markdown entries.

## Deferred-Export Retry

12. [ ] Pass / [ ] Fail - Make the destination temporarily unavailable.
    - Suggested method: set the iPhone offline or choose a test iCloud file/folder that is not materialized locally, then capture "Smoke test deferred export".
    - Expected result: The note is not dropped and does not get acknowledged as fully exported.
13. [ ] Pass / [ ] Fail - Open the iPhone Inbox and filter or inspect needs-attention state.
    - Expected result: The deferred note appears as retryable or needs attention, with status copy that does not imply successful export.
14. [ ] Pass / [ ] Fail - Restore destination availability and run the manual retry action.
    - Expected result: Retry succeeds, the note appends to today's Markdown file, and status changes to exported.
15. [ ] Pass / [ ] Fail - Run retry again or refresh the Inbox.
    - Expected result: The Markdown file still contains only one copy of the deferred note.

## Macro Expansion

16. [ ] Pass / [ ] Fail - Capture "Heading One Smoke Test".
    - Expected result: The exported Markdown begins with `# Smoke Test` or the configured Heading One macro output.
17. [ ] Pass / [ ] Fail - Capture a note using the `{date}` macro, such as "Today is date".
    - Expected result: The exported text contains the current local date in the app's configured format.
18. [ ] Pass / [ ] Fail - Capture a note using the `{time}` macro, such as "Time is time".
    - Expected result: The exported text contains the current local time in the app's configured format.
19. [ ] Pass / [ ] Fail - Capture a note using the `{location}` macro with a non-sensitive test phrase.
    - Expected result: The app either expands to a reasonable current location string or marks the capture with a visible, retryable/unavailable location state without hanging.

## Timestamp Correctness

20. [ ] Pass / [ ] Fail - Put the Watch back in Airplane Mode and capture "Smoke test origin timestamp".
    - Expected result: The Watch stores the capture immediately while offline.
21. [ ] Pass / [ ] Fail - Wait at least five minutes before reconnecting the Watch.
    - Expected result: The delayed transfer creates a clear difference between capture time and import/export time.
22. [ ] Pass / [ ] Fail - Reconnect and let the note transfer/export.
    - Expected result: The appended Markdown entry uses the Watch-origin capture time, not the later iPhone import/export time.

## Setup Proof

23. [ ] Pass / [ ] Fail - In iPhone Settings, run the destination test-note feature.
    - Expected result: A test entry is appended to the configured daily note or test file.
24. [ ] Pass / [ ] Fail - Return to Settings and inspect the destination proof details.
    - Expected result: "Last successful export" updates to the new test-note time and destination path.
25. [ ] Pass / [ ] Fail - Open the Markdown file after the setup proof.
    - Expected result: The test note appears once, with no personal data and no duplicate export.

## Result

- Overall result: [ ] Pass / [ ] Fail
- iPhone model and OS:
- Apple Watch model and watchOS:
- Build number:
- Notes or blocking failures:
