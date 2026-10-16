# Direct Send for v1.1

Dan's October 16 specification adds phone-free HTTPS delivery for watch text
captures. Phone delivery remains the default. Audio always uses the existing
phone transcription and export path. The app stays free.

## Release boundary

Build on a feature branch from nightly. Do not merge this feature into a lane
that can ship the v1.0 candidate until its submission gate is verified. The KB
records a feature freeze before launch; the supplied specification allows
isolated v1.1 development and requires keeping v1.0 separate until submission.
Submission, merge, CI, TestFlight and public release are separate facts.

## Capture and delivery

The user chooses Phone or Direct in iPhone settings. Direct can target GitHub,
a webhook, or both. Capture freezes the route, configuration version, destination
set, local date and UTC offset. Changing settings cannot reroute old notes.
GitHub and iCloud files stay separate. Direct notes use captured text without
macro expansion. These resolve the spec's open choices provisionally; Dan can
change them before delivery. Google Drive and watch audio transcription stay out
of scope.

Persist text queue changes atomically before reporting capture or delivery
success. Migrate legacy text notes to Phone, preserving IDs and timestamps.
Track success and exponential retry state independently for each direct
destination. A phone ACK cannot delete a direct note. Remove a direct note only
when every selected destination has succeeded. Keep old configuration versions
in the local Keychain so outstanding captures can use their original endpoint.

GitHub uses the REST contents API, an explicit branch, fresh uncached reads,
base64 content and SHA-checked writes. Preserve the capture-day filename across
time-zone changes. Add a UUID marker and check it before appending. Refetch after
a conflict. Keep notes queued after timeouts, auth failures and invalid responses.

Webhook delivery uploads a durable JSON file using a background URLSession.
Payload: id, text, capturedAt with its capture-time offset, and source
macromark-watch. Include Idempotency-Key as well as the payload UUID. Any 2xx
confirms delivery to the endpoint, not completion of an automation. The receiver
must deduplicate UUIDs to guarantee one logical action after ambiguous failures.
Reconnect to outstanding OS upload tasks on launch before scheduling retries.

Foreground activation retries both destinations. Watch background refreshes
schedule eligible webhook uploads; the multi-request GitHub transaction runs
while foregrounded. Do not use NWPathMonitor as a connectivity guarantee.

## Setup, replies and watch UI

Store tokens, webhook URL/headers and versioned setup in each device's Keychain.
Transfer setup over WatchConnectivity and acknowledge only after watch Keychain
persistence. Keep capture-mode synchronization intact. GitHub device-code login
uses a registered OAuth app's public client ID, never a client secret. Also accept
a user-created repository-scoped token. No credential enters logs or queue JSON.

Show pending deliveries, route and errors on the watch. Keep capture input visible
if persistence fails. Read GitHub YYYY-MM-DD.reply.md with the same fresh-read
policy; cache replies for offline reading with a visible cached state. A separate
complication opens Replies and shows the pending count using an App Group shared
by the watch app and widget. App Group signing setup is a distribution prerequisite.

## Verification

Focused tests cover queue restart/migration, partial completion, persistence
failure, immutable routes/dates, phone ACK isolation, backoff, webhook request
identity, GitHub conflicts/ambiguous writes and device-code polling. Run package
tests plus iOS and watchOS builds through the machine build wrapper or hosted CI.
Do not claim a real-watch phone-off test or Grok Bot reply/notification without
observing it. The live routine and GitHub app registration are external inputs.
