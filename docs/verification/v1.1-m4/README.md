# M4 screenshot and smoke evidence

November 15, Xcode 27.2 / iOS Simulator 27.2. These observations supersede the initial device-discovery block in the submission record.

## Screenshot execution

The project screenshot test runs through xcodebuild test-without-building, with an explicit owned destination, parallel testing disabled, and no erase or clone options. Fastlane snapshot itself is not invoked, so its default erase setting does not run. Its screenshot helper uses en-US / en_US cache files.

- iPhone 17e: passed, five images inspected. Direct Send has no secure-settings warning; the full macro list is visible above the tab bar after the framing correction. Built-in macro lock markers are the existing default-macro markers, not a purchase prompt. Note previews intentionally truncate; the incomplete capture is existing sample data. The compact Inbox filter abbreviates Needs Attention, and note-detail export actions continue below the viewport.
- iPhone 17 Pro Max: passed; five settled-run images inspected. First post-boot capture had transient section spacing, so the same booted device was rerun after capacity recovered. The retained Direct Send image has clean spacing; all macro descriptions are visible. Website JPEGs derive from this set at 760 pixels wide.
- iPad Pro 13-inch M5: passed, five images inspected. Direct Send is clean; both custom macros and every built-in description are visible. The settings content above the macro section scrolls under the top toolbar as expected. The New Macro sheet is fully visible.

## Interactive smoke on iPhone 17e

All actions used T3 device_open and its returned agent-device command. The device became discoverable after the authorized project runner booted it. After its checks, the session was closed and device_close shut it down under Dan's explicit sequential-model approval. The host owner subsequently reported that its initial startup included a shutdown at 17:46:52 UTC and restart by 17:47:59 UTC, extending the load spike to 7.5 minutes. This corrects the earlier claim that it booted only once. The initiating command was the project's xcodebuild test runner, not the Fastlane lane; the cause of the intermediate restart is not established.

| Step | Observation |
| --- | --- |
| Normal app launch and Macros navigation | Observed-pass: empty Inbox and settings opened |
| Normal Direct Send setup load | Observed-fail: first wrong step is secure-settings read error; Save disabled in unsigned simulator. See smoke/normal-launch-secure-settings.png. No claim of real Keychain or saving success. |
| Sample note list → note detail | Observed-pass in explicit screenshot fixture mode: Standup text and Exported status shown |
| GitHub controls | Observed-pass in fixture mode: toggle exposed owner, repository, branch, folder and secure token fields; no credentials entered |
| Webhook controls | Observed-pass in fixture mode: toggle exposed URL/header controls |
| Direct mode with no destination → Save | Observed-pass in fixture mode: Choose at least one Direct Send destination |
| HTTP webhook URL → Save | Observed-pass in fixture mode: HTTPS validation message; example.invalid only, no network delivery |
| Custom macro list → editor | Observed-pass in fixture mode: Standup trigger, replacement and preview shown |
| Real setup persistence, Watch transfer, signed-device behavior | Not observable here: unsigned Keychain failure and no paired physical Watch; fixture intentionally cannot save/send |

One tap was refused because the keyboard covered Save. Following the tool's keyboard-enter advice dismissed it; the next tap succeeded. No alternate UI control was used.

## Reproduction

After the host capacity gate passes and no other Apple run is active:

```sh
xcodebuild build-for-testing -project MacroMark.xcodeproj -scheme MacroMark \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$MM_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project MacroMark.xcodeproj -scheme MacroMark \
  -configuration Debug -destination "platform=iOS Simulator,id=$MM_DEVICE_ID" \
  -destination-timeout 600 -derivedDataPath "$MM_DERIVED_DATA" \
  -resultBundlePath "$MM_RESULT_BUNDLE" -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never \
  -only-testing:MacroMarkUITests/MacroMarkScreenshotUITests/testAppStoreScreenshots \
  CODE_SIGNING_ALLOWED=NO
```

Use the three exact Snapfile model types with owned instances. On this host,
first boot through the project runner makes the device visible to T3. Interactive
steps then use device_list, device_open and its returned agent-device command.
Keep each model booted through its checks; close its session before its final
shutdown. The approved sequential run requires load below 20 and at least ten
minutes between first boots. Never erase or clone devices. Screenshot cache
locale is en-US / en_US; preserve originals before cleanup.

## Host cleanup

One initial boot was requested per model, but the host observed an intermediate
17e shutdown/restart as recorded above. No explicit erase or restart command was
issued; no Fastlane lane was invoked. The 17e session was closed before its final
shutdown; all three final shutdowns used device_close under the explicit
sequential-model approval. The Pro Max and iPad project test runners finished
before their final shutdowns. No further boots are planned.
The temporary Pro Max instance was deleted after shutdown; pre-existing devices
were retained. Retained build/results measured about 895 MB before cleanup.
Temporary DerivedData, full result bundles, logs and our Fastlane cache files
were deleted after preserving the evidence below. No other task device was touched.

## Review and retained results

Three independent fresh-context review rounds completed. Round 2 found the iPad top-tab boundary assumption, corrected before its run. Round 3 found no blockers in the final source, iPhone images, website JPEGs or evidence claims; the parent agent subsequently inspected all five iPad images. Store text received independent review. Each model directory contains the original xcresult test-summary.json (one test passed, zero failures). These summaries and 15 PNGs are retained; full build/results are temporary.

## Originals and hashes

| File | Dimensions | SHA256 |
| --- | --- | --- |
| ipad-pro-13-m5/iPad Pro 13-inch (M5)-01-inbox.png | 2064 × 2752 | 660ac07b42513e79500ab55647f5f0cf6a2965586039abcb82a3702e420c2aef |
| ipad-pro-13-m5/iPad Pro 13-inch (M5)-02-note-detail.png | 2064 × 2752 | ebe4deccff6d6dd3c43c7844d9ae71dcdb4fc1c622b4027e5e09b0aeb06ba414 |
| ipad-pro-13-m5/iPad Pro 13-inch (M5)-03-macros.png | 2064 × 2752 | 11ff3a88ad14292061412e5fb91162e0f94303126bfe07de710c2c52b9f5ec83 |
| ipad-pro-13-m5/iPad Pro 13-inch (M5)-04-new-macro.png | 2064 × 2752 | 922b7f872646cb2649f7594266c88c77d785e1655bbaf3833707a55abc394044 |
| ipad-pro-13-m5/iPad Pro 13-inch (M5)-05-direct-send.png | 2064 × 2752 | 5307cb095efb2d8d9619d0615e8e4c8acdb9397b3e28345b6e2936899a2c58c6 |
| iphone-17-pro-max/MM1161-ProMax-01-inbox.png | 1320 × 2868 | ede7d2515d64b5a4bdde36d5e7ad951e4b310b9193d377b30ec3d31cb0a6f9c4 |
| iphone-17-pro-max/MM1161-ProMax-02-note-detail.png | 1320 × 2868 | 4b3f806df8d626b914a31ef67ef1b1d52275a3a17304d856f7e1dbbbf6e432fc |
| iphone-17-pro-max/MM1161-ProMax-03-macros.png | 1320 × 2868 | bd24a2e18ed3343f379be57170f5d3733b9b178dee84ae39070021574c8b0970 |
| iphone-17-pro-max/MM1161-ProMax-04-new-macro.png | 1320 × 2868 | 3e8c1cb06b7467d02d0d98f5a68a07a96889fee74403314f97bf4db1e8bfc4d7 |
| iphone-17-pro-max/MM1161-ProMax-05-direct-send.png | 1320 × 2868 | 129ad30caed982547b057ab552023e663e66a4d33d8ce046a9c1312f8c6a8688 |
| iphone-17e/iPhone 17e-01-inbox.png | 1170 × 2532 | 97d3195ef1eeaed8b752cdb69e26ed75597e6abd78d50ff329eca7ad2ca49a42 |
| iphone-17e/iPhone 17e-02-note-detail.png | 1170 × 2532 | 95e0752154dc6a73fcb011e47b007eb4d4454db355a74775bbc184aecb3940de |
| iphone-17e/iPhone 17e-03-macros.png | 1170 × 2532 | 08b3ebebbe49aab41fff4edcf38f455d5ee0c1c529eb8e356b0b30b94395f30e |
| iphone-17e/iPhone 17e-04-new-macro.png | 1170 × 2532 | deba269d357e31c7643b868ca56ad5a02542c0393e587a849f5b02f77463237e |
| iphone-17e/iPhone 17e-05-direct-send.png | 1170 × 2532 | fb2ce875b579f3b1922a15b5ec96508029df45e97e24111b472066b0e17a967a |
| smoke/fixture-empty-destination.png | 390 × 844 | cf9e639e787f262c695f3e81f805fa9256820d8e31667bcce21c5d889939dc50 |
| smoke/fixture-invalid-http.png | 390 × 844 | 84e04c349de801a110a667b115d9e5041ffcc4de56deb795163caaf1af0122f8 |
| smoke/fixture-macro-editor.png | 390 × 844 | 32be429958821e30130dd5a1fd9e7ae44501974ce2de64568f1b386b8bc31f2e |
| smoke/normal-launch-secure-settings.png | 390 × 844 | a98206ef0c0601324ba301091cc335c39fc4562ac35ef6ba52bc4c0cc901bcc8 |
