# M4 screenshot and smoke evidence

November 15, Xcode 27.2 / iOS Simulator 27.2. These observations supersede the initial device-discovery block in the submission record.

## Screenshot execution

The project screenshot test runs through xcodebuild test-without-building, with an explicit owned destination, parallel testing disabled, and no erase or clone options. Fastlane snapshot itself is not invoked, so its default erase setting does not run. Its screenshot helper uses en-US / en_US cache files.

- iPhone 17e: passed, five images inspected. Direct Send has no secure-settings warning; the full macro list is visible above the tab bar after the framing correction. Built-in macro lock markers are the existing default-macro markers, not a purchase prompt. Note previews intentionally truncate; the incomplete capture is existing sample data. The compact Inbox filter abbreviates Needs Attention, and note-detail export actions continue below the viewport.
- iPhone 17 Pro Max: pending.
- iPad Pro 13-inch M5: pending.

## Interactive smoke on iPhone 17e

All actions used T3 device_open and its returned agent-device command. The device became discoverable after the authorized project runner booted it. It was booted once; after its checks, the session was closed and device_close shut it down under Dan's explicit sequential-model approval. No automatic erase/shutdown script ran.

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

## Originals and hashes

| File | Dimensions | SHA256 |
| --- | --- | --- |
| iphone-17e/iPhone 17e-01-inbox.png | 1170 × 2532 | 97d3195ef1eeaed8b752cdb69e26ed75597e6abd78d50ff329eca7ad2ca49a42 |
| iphone-17e/iPhone 17e-02-note-detail.png | 1170 × 2532 | 95e0752154dc6a73fcb011e47b007eb4d4454db355a74775bbc184aecb3940de |
| iphone-17e/iPhone 17e-03-macros.png | 1170 × 2532 | 08b3ebebbe49aab41fff4edcf38f455d5ee0c1c529eb8e356b0b30b94395f30e |
| iphone-17e/iPhone 17e-04-new-macro.png | 1170 × 2532 | deba269d357e31c7643b868ca56ad5a02542c0393e587a849f5b02f77463237e |
| iphone-17e/iPhone 17e-05-direct-send.png | 1170 × 2532 | fb2ce875b579f3b1922a15b5ec96508029df45e97e24111b472066b0e17a967a |
| smoke/fixture-empty-destination.png | 390 × 844 | cf9e639e787f262c695f3e81f805fa9256820d8e31667bcce21c5d889939dc50 |
| smoke/fixture-invalid-http.png | 390 × 844 | 84e04c349de801a110a667b115d9e5041ffcc4de56deb795163caaf1af0122f8 |
| smoke/fixture-macro-editor.png | 390 × 844 | 32be429958821e30130dd5a1fd9e7ae44501974ce2de64568f1b386b8bc31f2e |
| smoke/normal-launch-secure-settings.png | 390 × 844 | a98206ef0c0601324ba301091cc335c39fc4562ac35ef6ba52bc4c0cc901bcc8 |
