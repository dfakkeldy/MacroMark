# MacroMark v1.1 submission preparation

Prepared 2026-11-15. This is a preparation record, not an Apple submission or release receipt.

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

Unit execution and screenshot capture are pending the shared host's health
gate. The dispatcher capacity tool reported swap above its 8 GB limit; do not
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
