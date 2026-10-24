# MacroMark Architecture

MacroMark is composed of two primary targets (watchOS and iOS) communicating asynchronously to ensure zero-friction, reliable text capture.

## 1. watchOS Target (Capture & Persist)

The watchOS app is responsible for raw capture. Instant capture records audio on the watch and leaves transcription to the iPhone, so silent pauses do not end the session.

### Components
- **`AudioRecorder`**: An `@Observable`, `@MainActor` wrapper around `AVAudioRecorder`. It records mono AAC (`.m4a`) to a temporary file. The watch does not transcribe audio.
- **`LocalStore`**: An `@Observable` singleton that persists every capture before any transfer. Text captures go to the `TextDeliveryQueue` file (`Application Support/TextDelivery/queue.json`), written atomically. Audio files move to `Application Support`, with their queue metadata in `UserDefaults`. If the Watch is disconnected from the iPhone or the app is killed in the background, no data is lost.
- **Capture Views**:
  - **Main Interface**: Features a modern liquid glass aesthetic. Replaces legacy options with large, clear microphone and keyboard buttons for capture, and a prominent "Today's Daily Log" button at the bottom.
  - `InstantCaptureView`: Starts the `AudioRecorder` immediately on appear. It hooks into the SwiftUI `scenePhase` environment variable to automatically save the session with an accurate point-of-origin timestamp the exact moment the user lowers their wrist (`.background` or `.inactive`).
  - `SystemCaptureView`: A fallback using the system text input controller for scribble, keyboard or standard dictation.
  - `DailyLogView` / `DailyLogFileBrowserView`: Fetch a day's Markdown file, or browse the daily files, from the iPhone.
  - `DeliveryStatusView` / `DirectReplyView`: Direct Send pending deliveries and cached GitHub replies (v1.1, `nightly`).
- **Widget Extension** (watch complications only): Instant Capture (`macromark://capture/instant`) and System Capture (`macromark://capture/system`) deep link into the capture modes with `widgetURL`. On `nightly`, Replies and deliveries opens Direct Send replies and shows the pending count.

## 2. The Bridge (WatchConnectivity)

Because users often capture notes away from their phones, the sync mechanism must be robust.

### Components
- **`WatchConnectivityProvider`**: A shared `@MainActor` singleton wrapping `WCSession`.
  - Phone route: the Watch uses `transferUserInfo` to enqueue notes, including the origin timestamp from dictation. `didFinish` success does not delete the note. The watch waits for the phone's durable ACK (`ack` / `ackFile`) after iPhone processing and export safety. A failed transfer un-queues the id so it can be retried. An audio transfer still unacknowledged after the reconciliation interval is re-sent with the same UUID; the phone deduplicates the replay, and the watch keeps the local file until the durable ACK.
  - Direct Send: watch text is not delivered through WatchConnectivity. Versioned setup (mode, GitHub token or device-code credentials, webhook URL and headers) is sent from the iPhone after a one-time setup; the watch ACKs only after it has saved that snapshot. Endpoint-specific credential repairs travel separately from the current settings context. A phone ACK cannot delete a Direct Send note.
  - On iOS, it receives the `userInfo` payload in the background and triggers the processing pipeline with the correct timestamp.
  - **Isolation (Swift 6):** `WCSession` invokes its delegate callbacks on a background queue, so every `WCSessionDelegate` method is `nonisolated` and hops to the main actor (`Task { @MainActor in … }`) only for state access. Leaving them `@MainActor` traps at launch under Swift 6 language mode — the runtime executor check fires when WCSession calls them off-main. The incoming-file copy is done synchronously inside the callback, before WCSession reclaims its inbox file.

### Direct Send outbox

Direct Send is optional v1.1 work on `nightly`. Phone/iCloud remains the default; audio always uses the phone transcription path. Enabled Direct Send text is stored in `TextDeliveryQueue` (`MacroMarkKit/Sources/MacroMarkKit/Delivery/`). Each capture keeps its route, UUID, configuration id, local date, and UTC offset. Destinations (GitHub, webhook, or both) are tracked independently: one can succeed while the other stays queued. The note is removed only when every selected destination is confirmed.

GitHub appends `<folder>/YYYY-MM-DD.md` on the configured branch with a standalone `<!-- mm:<uuid> -->` marker, reading fresh contents before write. A retry that already sees the marker is treated as delivered. HTTP 409 responses refetch the SHA and retry so intervening edits are preserved. Files larger than 256 KiB stay queued rather than being replaced or truncated. Webhook delivery uses a file-backed background `URLSession` POST with JSON `id`, `text`, `capturedAt`, and `source: "macromark-watch"`, plus an `Idempotency-Key` header set to the same UUID.

GitHub tokens and webhook credentials live in each device's Keychain (`DirectSendSettingsStore`). Direct Send does not expand macros on the watch. The Replies and deliveries complication reads an App Group pending count and opens GitHub `.reply.md` content cached on the watch.

## 3. iOS Target (Process & Store)

The iPhone acts as the processing hub and storage engine.

### Components
- **`Macro` (SwiftData Model)**: Stores the user's text replacements (e.g., "Heading One" -> "# "). The 24 built-in defaults are seeded from `MacroManagerView.defaultMacros` on first launch; restoring defaults replaces only `isDefault` macros.
- **`AudioTranscriber`**: Transcribes received watch audio with `SFSpeechRecognizer` and `SFSpeechURLRecognitionRequest`. Authorization and recognition waits are bounded, and chunk failures mark the note as partially transcribed.
- **`MacroProcessor`**: A stateless, `nonisolated` engine that runs off the main actor. It takes raw transcribed text plus a `[MacroRule]` — a `Sendable` value snapshot of each macro's trigger/replacement, taken from the SwiftData `Macro` models on the main actor — so no SwiftData model crosses an isolation boundary. It:
  1. Applies user-defined macros using case-insensitive Regex (compiled patterns are cached behind an `OSAllocatedUnfairLock` for thread-safe reuse across concurrent calls).
  2. Evaluates dynamic variables: `{date}` (ISO `YYYY-MM-DD`), `{time}` (locale short time), `{newline}`, `{tab}`, `{backspace}`, `{uuid}`, `{clipboard}`, and `{location}` (MapKit reverse geocoding, with a bounded wait).
  3. Cleans up formatting artifacts (e.g., removing spaces inside Markdown wrapping tags like `* bold *`).
- **`iCloudStorageManager`**: Resolves the export folder: a user-chosen folder bookmark, else the app's iCloud Documents container, else local Documents as a fallback. `FolderSettings` builds the file path from the capture date (default `yyyy-MM-dd.md`; flat, `YYYY-MM/` or `YYYY/MM/` subfolders). `DailyNoteFormatter` renders the entry, and `NSFileCoordinator` with `FileHandle` appends it. An iCloud file that exists but is not downloaded returns `deferred` instead of being overwritten.
- **App Intents** (`MacroMark/Intents/MacroMarkAppIntents.swift`): Start Instant Capture, Start Typed Capture, Open Daily Log (optional date), and Append Text to Today. Each opens a `macromark://` route in the app.

## 4. Durability And Export State

MacroMark treats captured notes and recordings as user data, not transient messages. The default (phone) reliability model is:

1. Watch capture persists locally before transfer.
2. WatchConnectivity delivers text or audio to the iPhone.
3. The iPhone processes the payload, expands macros, and saves the processed record.
4. Export status tracks whether the configured target appended successfully, deferred safely, or needs attention.
5. Watch-side data is acknowledged only after iPhone-side durability and export safety are established.

Direct Send text uses the same local persist-first rule, then a watch-side outbox instead of WatchConnectivity delivery. Each selected destination is confirmed independently (GitHub UUID marker / SHA conflict recovery; webhook UUID and `Idempotency-Key`). The capture stays queued until every selected destination is confirmed. Audio remains on the phone path above.

Initial processing, export retry, and audio WAL recovery share one reservation per capture source UUID. A path acquires it before starting work and releases it when that work ends, so a retry or recovery pass cannot append or retranscribe a capture while another path still owns it. A successful export reports that the note was saved to the daily Markdown file.

The public UI mirrors this model through inbox status, needs-attention filtering, note detail status, retry actions, partial transcription warnings, and destination setup proof. Any future sync/storage work must preserve idempotency: replayed notes, audio files, and ACK messages must not duplicate user-visible Markdown exports.

## 5. Product And Monetization Boundaries

The approved launch is fully free. Apple Watch/iPhone capture, daily-note append,
review, unlimited custom macros, default macro editing and folder customization
do not require a purchase. `StoreAccessPolicy.paywallDisabled = true` is the
release policy, as recorded in `docs/APP_STORE_PACKET.md`.

Existing `com.macromark.subscription.annual` and `com.macromark.lifetime`
identifiers, transaction handling and prior ownership remain compatible. They
are not new offers for this free launch; historical paid-tier plans do not
change current access.

The app has no account system and no third-party analytics in v1.0. Privacy disclosures, App Store metadata, and the website must stay consistent with that behavior.

Direct Send (v1.1 on `nightly`) still has no MacroMark account and adds no analytics. When the user enables it, watch text, a UUID, capture timestamp and UTC offset, and a source identifier go to the GitHub repository and/or HTTPS webhook they chose. KinNoKi Labs does not receive those notes. GitHub device-code sign-in, when the iPhone build supplies a public client ID, authorizes GitHub only.

## 6. Release And Documentation Architecture

- Promotion ladder: `feature/* -> nightly -> weekly -> main`.
- GitHub Pages source: `main /docs`.
- Release automation: `.github/workflows/release-trains.yml` ships the scheduled nightly internal TestFlight train; see `fastlane/README.md` for channels and signing.
- Devlog automation: `Scripts/doc_automation/` updates `docs/guides/devlog.md` and `docs/devlog.html` and opens a reviewable PR.
- App Store readiness source: `docs/APP_STORE_READINESS.md`.

As of 2026-10-24, version 1.0 is live on the App Store (released 2026-10-23) from the `main` line. `nightly` is at version 1.1 with Direct Send and watch audio retry. Keep the branch being shipped, the release workflow, README, website, Fastlane metadata, and App Store Connect state aligned before each submission.
