# Direct Send in v1.1

Direct Send delivers watch text to a GitHub daily Markdown file, an HTTPS
webhook, or both. Phone and iCloud remain the default. Audio recordings always
use the phone transcription path. Direct text keeps the captured wording;
macros are not expanded on the watch. GitHub and iCloud files stay separate.

Direct Send is v1.1 work. It landed on `nightly` in
[#125](https://github.com/dfakkeldy/MacroMark/pull/125) and is not in the 1.0
App Store release (live since 2026-10-23). It reaches `weekly` and `main` only
through the normal promotion ladder. No physical watch, live bot routine,
GitHub OAuth registration, Apple signing change or App Store update is implied
by the code or its automated checks.

## Setup

On iPhone, open Macros, then Direct Send. Choose Phone or Direct Send and enable
the destinations you want. GitHub needs an owner, repository, existing branch,
optional folder and token. A fine-grained personal access token can grant
Contents read and write access to only that repository. Credentials and webhook
headers are stored in each device's Keychain.

Save and send setup to the watch. The phone shows confirmation only after the
watch has saved it. After that, direct text delivery does not use the phone.
WatchConnectivity activation retries the latest setup if it was not active when
you saved. Saving again resends setup. Previously queued notes retain their
original route and configuration version, even if you change destinations.

GitHub device-code sign-in is implemented but is shown only when the iPhone
build supplies the public `MACROMARK_GITHUB_CLIENT_ID` build setting. Register an
OAuth app with device flow enabled before setting it. Never bundle a client
secret. OAuth `repo` scope can cover more repositories than a fine-grained token.
Expired/revoked credentials leave notes queued for retry; sign-in never silently
switches them to another destination.
Saving rotated credentials also repairs queued notes to that same endpoint,
branch and folder, even after a later destination change. Webhook credential
repair preserves non-authentication headers. Old endpoint/route snapshots remain
immutable; authentication refresh does not move a capture to another service.

The Replies and deliveries complication needs the App Group
`group.com.danfakkeldy.macromark` enabled for both the Watch App and its widget
extension in signing profiles. The source entitlements are included; Apple-side
registration/profile updates have not been performed by this implementation.

## Delivery contract

GitHub writes `<folder>/YYYY-MM-DD.md` on the configured branch. The date and UTC
offset are fixed at capture, including offline notes sent after midnight or
travel. Each capture includes a standalone `<!-- mm:uuid -->` marker. A retry
reads fresh contents and skips a marker already present. Conflicts refetch the
SHA and preserve intervening edits. Files larger than 256 KiB stay queued with
an error rather than being replaced or truncated.
Direct dictation that finishes after midnight uses the actual result timestamp,
even if the input screen opened the previous day. Phone captures retain the
existing selected-day behavior. The phone's Daily Log preview includes only
notes routed to the phone.

Webhook uploads use a durable file and a background URLSession. JSON contains
`id`, `text`, `capturedAt` with the capture-time UTC offset, and
`source: "macromark-watch"`. The `Idempotency-Key` header contains the same UUID.
The endpoint must persist and deduplicate UUIDs before starting an action.
Sending a UUID does not, by itself, make an arbitrary webhook exactly once.
Any 2xx response confirms endpoint acceptance, not completion of a bot's work.
Confirmation requires a final POST response from the configured URL. Use the
endpoint's final HTTPS URL. Background URLSession follows redirects automatically;
a redirected landing-page response does not remove the capture.

Progress and exponential backoff are saved for each destination independently.
If a server confirms delivery while local confirmation storage is temporarily
unwritable, MacroMark keeps that receipt in memory and retries the local write
without repeatedly sending the same upload. A relaunch after such a failure
still relies on GitHub markers or receiver UUID deduplication.
When both destinations are selected, one can succeed while the other remains
queued. Retries reconnect to existing background upload tasks before scheduling
more. Foreground activation retries eligible notes. Background refreshes schedule
webhooks when watchOS grants execution time. GitHub's GET/PUT transaction runs
while foregrounded. Network availability and background timing remain controlled
by watchOS; pending notes remain visible in Deliveries and the complication.

Legacy queued text notes migrate to Phone with their existing UUIDs/timestamps.
Only a durable phone ACK removes Phone notes. A phone ACK cannot delete Direct
notes. Text capture reports success only after the outbox is written atomically;
if saving fails, the capture view retains the text for another save attempt.

## Replies and Grok Bot

Replies reads `<folder>/YYYY-MM-DD.reply.md` from GitHub using uncached contents
requests. Replies are cached locally for offline reading and labeled when stale.
The complication opens this view. Reply authoring belongs to the configured bot
or automation. MacroMark does not write reply files or send conversation messages.

A Grok Bot routine can receive the webhook body, deduplicate its `id`, write the
full response to the capture day's `.reply.md` file on the configured branch, then
post a short message in its conversation. The phone's normal notification routing
may show that message on the watch. Routine creation, wake/commit permissions,
Auto Review behavior and notifications have not been tested here. Dan explicitly
deferred the live webhook setup. Do not use an unofficial messaging gateway.

## Privacy and release evidence

The v1.1 policy source discloses optional GitHub/webhook transmission and local
credential/reply storage. Developer note servers, tracking and analytics are not
added. The App Store privacy worksheet must account for user content, UUIDs,
timestamps and each configured provider's processing under Apple's definitions.
The local manifest does not save or determine the App Store privacy label.
No live privacy label, sign-in registration or public policy deployment was changed.

The automated tests exercise atomic-save failure, queue restart/migration,
partial fan-out, capture dates, backoff, webhook identity, GitHub conflicts and
ambiguous writes, and device-code polling. Hosted CI builds iOS/watchOS and runs
package/iOS tests using the existing pipeline. The Watch test source includes an
ACK/fan-out regression; the existing hosted pipeline does not execute Watch tests.
Phone-off networking, suspension recovery on a physical watch and bot reply/
notification delivery remain unobserved. These are evidence limits, not claims
that a real-device test has passed.

## Primary references

- [Apple TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
  describes HTTP support and why NWPathMonitor is not a normal watch connectivity signal.
- [Apple background URLSession](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
  explains session reconnection, delegates and file-backed uploads.
- [GitHub contents API](https://docs.github.com/en/rest/repos/contents)
  defines base64/SHA writes and conflict responses.
- [GitHub device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow)
  defines client registration, device codes and polling intervals.
- [Grok Bot routines](https://cursor.com/help/grok-bot/routines)
  documents bearer-authenticated webhooks and acceptance versus completed runs.
- [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
  defines disclosure requirements separately from privacy manifests.
