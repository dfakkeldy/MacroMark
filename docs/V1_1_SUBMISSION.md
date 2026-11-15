# MacroMark v1.1 submission preparation

Prepared 2026-11-15. This is a preparation record, not an Apple submission or release receipt.

**Current M4 status:** fixture and framing corrections compile; iPhone 17e and
iPhone 17 Pro Max and iPad Pro 13-inch M5 screenshot tests passed. All 15
images were inspected. Interactive smoke ran on the 17e: normal unsigned
Direct Send fails its Keychain read; fixture-mode navigation and validation
pass. Website iPhone images now use the inspected Pro Max set. See
[current evidence](verification/v1.1-m4/README.md). Earlier blocked attempts
below are retained as history. Keep the PR draft: **Needs landing from the Mac**.

## Changes since 1.0

Written before changing listing copy or assets. GitHub returned no tags and no
Releases. The documented 1.0 baseline is main promotion `aeafeda1b649fe8952ce1a7f23ac8a6eabe6c86f`
([#121](https://github.com/dfakkeldy/MacroMark/pull/121)), following weekly
[#120](https://github.com/dfakkeldy/MacroMark/pull/120). The recorded public
release was 1.0 on October 23. The submitted binary's exact source/build has
not been independently established, so this is a source comparison against
the accepted 1.0 candidate, not a binary diff.

Preparation base: nightly `ef6729627b81464243c480b6ae12aaf793640638`.
At inspection, weekly was `78532f20dfe49683bab877adb810d07eaf409f0f` and
main was `7155ea355656989e2fe867d77cc168de078274b3`.

- [#125](https://github.com/dfakkeldy/MacroMark/pull/125): optional Direct Send
  of watch text to GitHub daily Markdown files, an HTTPS webhook, or both;
  one-time iPhone setup, independent destination retries, GitHub replies on
  the watch, and a Replies and deliveries complication. Audio remains on the
  phone route. Direct text does not expand macros. Version changed to 1.1.
- [#145](https://github.com/dfakkeldy/MacroMark/pull/145): resend watch audio
  transfers still unconfirmed after a day using the original capture ID;
  retain the recording until the phone confirms processing.
- Existing free capture, custom macros, folder settings, daily review and
  Shortcuts are 1.0 features, not newly unlocked paid features in 1.1.
- [#124](https://github.com/dfakkeldy/MacroMark/pull/124), #137, #138, #142
  and #144 concern release delivery, simulator provisioning and signing
  automation. They are not customer-facing release notes. Their main
  counterparts include #136, #141 and #143; #150 back-merged main to weekly.
- #126, #139, #146, #147, #149 and #151 update documentation on nightly.
  #140, #148 and #152 update main documentation/site. Agent workflow changes
  #127, #131, #132 and #134 do not change the app's capture features.

Evidence: Git history over `aeafeda1..origin/nightly`, app-source diff, merged
PR records across nightly/weekly/main, and the historical
[readiness record](APP_STORE_READINESS.md). No new claim of live 1.1 availability.

## Scope and remaining evidence

Prepare docs, repository website, English store copy and simulator screenshots.
Do not change signing/release/workflow configuration, archive, upload, submit,
or sign in. Pages publishes main /docs; merging this PR into nightly alone
will not deploy the website. Preserve the published Watch screenshot unless a
new Watch capture can be verified. See [Direct Send privacy](DIRECT_SEND_PRIVACY.md)
for the outstanding provider/privacy worksheet and [paired-device checks](SMOKE_TEST_CHECKLIST.md)
for physical-device evidence that a simulator cannot supply.

Build, screenshot, smoke-test and review results will be recorded below.

## Independent store-text review

Codex fresh-context store-text reviewer, 2026-11-15, approved all four fields
with no blocking findings after checking implementation and field limits.
The optional clarification that GitHub delivery runs while the watch app is
open was incorporated. Review covered text only, not physical-device or
submission readiness. The reviewer did not access live pricing or App Store Connect state.

## Website deployment handoff

This repository owns the metadata marketing URL and publishes main /docs.
KinNoKiLabsSite also has `Content/apps/macromark.md` and
`Content/macromark-help.md`. The separate site's page still describes 1.0;
update it with the Direct Send text/audio/macro distinctions, GitHub replies,
network/foreground requirements, audio retry, and the final reviewed screenshots.
Correct its old “Not” macro example to “Backspace”. Keep the App Store status
at 1.0 until 1.1 is confirmed released. Link this repository's Direct Send guide
and privacy policy. Rebuild its generated output using that repository's own
process. This task leaves that separately maintained site unchanged; its
needed changes are also listed in the PR handoff.

## Public listing and links

Read-only public lookup on November 15 returned version 1.0, price 0 and
release timestamp `2026-10-23T01:45:10Z` for app 6785081218 in Canada.
The [App Store page](https://apps.apple.com/ca/app/macromark/id6785081218)
also shows free availability and the 1.0 description. The marketing homepage,
privacy policy and terms URLs all returned HTTP 200. No App Store Connect
account was accessed or changed. Reconcile the Direct Send privacy worksheet
before Dan saves the 1.1 privacy answers; the current public label is not
proof of the correct answer for new provider destinations.

## Local verification

Environment: Xcode 27.2 build 27B52, iOS Simulator 27.2, en-US screenshot
locale. No signing identity, account sign-in, archive or Apple upload used.
The simulator build-for-testing passed with `CODE_SIGNING_ALLOWED=NO`.
Existing Swift concurrency warnings in screenshot setup remain warnings.
Release automation checks passed: 22 Ruby tests, real Fastlane provisioning
option validation, 43 workflow/simulator Python tests and 14 doc-automation
tests. Metadata character limits and website local links passed local checks.

Unit execution and screenshot capture were blocked by the shared host's health
gate. After more than ten minutes of unhealthy checks, the waiting command
was stopped without starting tests. No screenshot set was generated. The dispatcher capacity tool reported swap above its 8 GB limit; do not
start another Apple build while unhealthy. The screenshot test now includes
Direct Send alongside Inbox, Note detail, Macros and New Macro. Its UI run
must pass before treating newly captured images as approved assets.

Interactive smoke is blocked by T3 device discovery. Dedicated iPhone 17 Pro
Max, iPhone 17e and iPad Pro 13-inch M5 simulators were created for this task.
`device_open` returned “No device … on 'This machine' (hostId local). Call
device_list for current ids.” Refreshing the list and retrying returned the
same error, although Xcode can target the dedicated device. No other thread's
session was reused or closed, and no alternate device-control tool was used.
No app failure screenshot exists because interactive launch did not occur.

Physical watch networking, setup acknowledgement, background webhook retry,
reply delivery and the one-day audio retry remain outside simulator-only
acceptance. Dan still needs those observations and final ASC/privacy/build
checks before submission. This record does not claim submission readiness.

## Resume on a healthy Mac

Keep this PR draft. Needs landing from the Mac after the checks below pass;
the rented host only updates the draft. Recheck current nightly and do not
overwrite other work.
Use the three models from Snapfile: iPhone 17 Pro Max, iPhone 17e and
iPad Pro 13-inch M5, in en-US. On a shared machine, create dedicated devices,
select them explicitly and do not erase someone else's simulator.

On Dan's Mac, run every Apple build and test below through
`/Users/dfakkeldy/.claude/bin/xcode-build-slot.sh -- <command>`, including
Swift package tests and Fastlane snapshot. The wrapper owns scheduling and
resource admission. That wrapper does not exist on mmm-m4. On that host,
run the dispatcher's capacity check before each build, wait while unhealthy,
and run only one Apple build at a time. Preserve the host's simulator ownership,
two-job limit and one-boot rule. Do not use Snapfile's default erase behavior.

1. Check the dispatcher's capacity script and the number of xcodebuild
   processes before each Apple run. Use one Apple run at a time for this task.
2. Build-for-testing with the CI command, an iOS Simulator destination,
   `-derivedDataPath DerivedData` and `CODE_SIGNING_ALLOWED=NO`.
3. Run `xcodebuild test-without-building -project MacroMark.xcodeproj
   -scheme MacroMark -configuration Debug -destination 'platform=iOS Simulator,id=<dedicated-udid>'
   -only-testing:MacroMarkTests -derivedDataPath DerivedData
   -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`.
4. Run `swift test --package-path MacroMarkKit`. The PR gate does not run
   general UI tests; screenshot UI execution is still required here.
5. Run the project's local `bundle exec fastlane snapshot`, using Snapfile
   and overriding `--devices` with dedicated instances of all three listed
   models. Use `--test_without_building true --derived_data_path <absolute-DerivedData>`
   after building, `--erase_simulator false`, and sequential simulators.
   Do not invoke upload, deliver, pilot or release lanes.
6. Inspect every full-resolution PNG for clipping, overlays, unexpected
   placeholders and stale paid UI. Preserve the approved originals and a
   dimensions/SHA256 manifest in git, since fastlane/screenshots is ignored.
   Replace the website images from these originals. The existing Macros image
   was visually inspected and lacks Direct Send while showing old lock icons;
   it is not accepted as a v1.1 screenshot. The other old images have not been
   recertified for v1.1. Existing screenshot fixtures intentionally show one
   incomplete transcript; assess that warning in the actual captures.
7. Use T3 device_list, device_open and its returned agent-device command for
   a short interactive pass. Open Direct Send, check destination controls and
   invalid/empty configuration feedback without credentials or sign-in;
   verify normal note and macro navigation. Save any broken behavior with a
   screenshot. Capture/setup on a physical Watch remains a separate check.
8. Update this record and the PR with actual results, complete independent
   review, and hand back for landing on the Mac with `land_pr.py`. Record the result on the
   preparation issue. Release binary choice, signed-device checks and Apple
   submission remain Dan's steps.

Host-only tooling installed for this run: Ruby 3.3.6, Bundler 2.5.22 and the
existing locked Fastlane 2.236.1 dependency set. The repository requests Ruby
3.3.11; no Ruby version file, Gemfile or lockfile was changed. Ruby 2.6 initially
could not parse newer test syntax; rerunning with Ruby 3.3.6 passed. Native gem
setup initially lacked a working compiler/SDK path; local Xcode compiler links
and SDKROOT resolved it. No new app dependency was added.

## Follow-up verification — November 15

The branch already contains nightly `ef67296`; no merge conflicts required resolution.
A fresh-context GPT-6-Astra reviewer found no blocking source/store-copy issue.
The reviewer requested the build-wrapper and landing-instruction corrections above.

On the follow-up Mac, Xcode 27.2 (27B52) with iOS Simulator 27.0 passed:
- Simulator build-for-testing with signing disabled.
- All 73 package tests and 13 iOS unit tests.
- Screenshot UI execution on dedicated iPhone 17 Pro Max, iPhone 17e and
  iPad Pro 13-inch (M5) simulators: 15 PNGs generated.
- 22 Ruby automation tests, pinned Fastlane provisioning validation,
  43 Python workflow/tooling tests, 14 documentation tests and diff whitespace checks.

Every Apple run used the build-slot wrapper. Dan approved up to 10 GB of
temporary output and the off-hours override. Temporary workspace output stayed
below 1 GB at the measured checkpoints. The first Fastlane attempt incorrectly
selected macOS because dedicated simulator names began with `Mac`; renaming
them to `MM1161-*` fixed destination selection, and the complete rerun passed.

**Still blocked; keep the PR draft:** visual inspection of the Pro Max set
found a secure-settings read error on Direct Send and an inadequately framed
Macros list. Passing navigation assertions did not detect these problems.
The generated originals and dimensions/SHA256 manifest are retained as
[unapproved evidence](verification/v1.1-unapproved/README.md), not release assets.
Existing website screenshots have not been replaced or recertified.

Interactive smoke also remains blocked: T3 could not open the dedicated
simulator, including after the prescribed device-list refresh and retry.
No alternate interactive control was used. No signing/release/workflow
configuration was changed, and nothing was archived, uploaded or submitted.

Agent work remains: resolve the screenshot environment/fixture and framing,
review a clean image set, replace website images, complete interactive smoke
on a discoverable dedicated device, then finish the review and landing gate.
Dan-only release steps remain binary selection, signed-device checks, and
App Store submission including final privacy answers.

## M4 follow-up — November 15

Needs landing from the Mac. PR #153 remains a draft; no merge is authorized
on this rented host. The branch already includes current nightly `ef67296`.

The previous captures expose two fixture/test problems: Direct Send reads the
real Keychain in an unsigned screenshot launch, and the macro scroll helper
accepts accessibility-tree existence even when the row is below the viewport.
The Debug-only explicit `--screenshot-mode` launch now shows empty Direct Send
setup without reading credentials. It still uses real configuration validation,
but cannot save or transfer setup. Normal launches and Release retain the
original Keychain behavior. The screenshot test rejects a disabled Save button
or secure-settings error and scrolls to visible custom macro text.

Fresh-context GPT-6-Astra reviewer `review_screenshot_fix` found no blocking
source or store-copy issue in one round. The reviewer emphasized that visible
text alone does not prove acceptable framing; all new images still need review.
The 14 documentation tests and whitespace check pass. No new screenshot is
approved, and existing website images remain unchanged.

Final unsigned simulator `build-for-testing` passed on Xcode 27.2 with
`-scheme MacroMark -configuration Debug -destination 'generic/platform=iOS Simulator'
CODE_SIGNING_ALLOWED=NO`. Both builds started after a healthy dispatcher check
with no other xcodebuild process. Temporary output peaked at the measured
882 MB checkpoint and was removed after verification. This is compilation
evidence, not UI test execution; the new assertions have not run on a simulator.

Interactive smoke could not start. T3 listed only the devices owned by #1125
and #1015. The unused iPhone 17e existed in CoreSimulator, but `device_open`
returned `No device A63B1B5C-6EA5-458E-B378-BDF264BBB1C6 on 'This machine'
(hostId local). Call device_list for current ids.` After waiting 60 seconds,
refreshing discovery and retrying once, the same error occurred. No alternate
device control was used, and this task booted, erased or shut down no device.

| Smoke step | Observation |
| --- | --- |
| Open app on own iPhone | Not observable here: device_open failed twice as above |
| Open Direct Send and inspect destination controls | Not observable here: app could not be launched through device tools |
| Empty and invalid configuration feedback without credentials | Not observable here: same device-tool error |
| Note list and detail navigation | Not observable here: same device-tool error |
| Macro list and editor navigation | Not observable here: same device-tool error |

Agent work remains: restore dedicated-device discovery, execute the screenshot
test on all three Snapfile models, inspect every image, replace website assets,
complete interactive smoke and hand back to the Mac landing owner. The host's
one-boot rule and two-job cap also need coordination before multiple screenshot
models run. Dan-only release steps remain binary choice, signed-device checks,
and submission with final privacy answers.

### Authorized runner boot and interactive follow-up

The dispatcher subsequently authorized the project's test runner to boot the
owned iPhone 17e once. After that first boot, T3 discovered it and interactive
work could proceed through device_open and its returned agent-device command.
Dan explicitly approved completing and shutting down screenshot models one at
a time, with no repeated boot or erase. The initial discovery block above is
therefore historical, not the current smoke result.

The iPhone 17e screenshot test passed, and visual inspection led to one further
short-drag framing correction so the final macro description clears the tab
bar. Its rerun passed. Fresh-context review round 2 accepted the 17e images
and found an iPad top-tab boundary assumption; that test-only correction is
implemented and the final unsigned build-for-testing passed. Pro Max and iPad
execution remain pending at this checkpoint.

Interactive results distinguish the normal unsigned Keychain failure from
successful fixture-mode navigation and validation. See the per-step observations,
original images and hashes in [M4 evidence](verification/v1.1-m4/README.md).
No physical-device, real Keychain persistence or Watch transfer success is claimed.

### Final M4 capture and review

All three exact Snapfile models passed the screenshot test on the corrected
source. All 15 retained PNGs were inspected; Direct Send has no secure-settings
warning and the complete macro list fits. The website now uses resized Pro Max
captures. Final source/evidence review round 3 found no blockers; three review
rounds total. The 14 documentation tests, metadata limits and diff check pass.
Current origin/nightly remains fully included; no merge was needed.

The interactive smoke result is partial: normal unsigned Direct Send fails at
Keychain loading. Fixture-mode navigation, controls and invalid-input feedback
pass. Real persistence, Watch transfer and delivery remain signed-device checks.
The Mac must land the draft through land_pr.py after its required checks pass.
Dan-only work remains release binary choice, signed-device checks, and submission
with final privacy answers. No release, signing or workflow settings changed.

### Host-observed startup correction

After handback, the host owner reported that the first 17e startup included a
shutdown at 17:46:52 UTC and restart by 17:47:59 UTC (7.5-minute load spike).
This supersedes our earlier claim that every model booted once. We requested
one initial startup through xcodebuild test-without-building, with no erase or
clone options; the Fastlane lane was not invoked. The intermediate restart
cause is not established. The interactive device session was closed before the
17e final shutdown; the later model test runners completed before shutdown.
Screenshot and smoke observations are unchanged. All model work was already
complete when the host report arrived, so no additional boots were attempted.

The host subsequently confirmed that xcodebuild test-without-building shuts
down a Shutdown destination it boots when the test exits. The iPad booted at
18:22:23 UTC and shut down at 18:23:58 UTC, before our later device_close cleanup.
Its five PNGs exist, were inspected, and its retained test summary records one
pass and zero failures. No retry is needed. We withdraw the earlier no-runner-
shutdown claim and do not certify continuous boot state between earlier test
invocations. No Fastlane lane or explicit erase command was used.
