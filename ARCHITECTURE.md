# MacroMark Architecture

MacroMark is composed of two primary targets (watchOS and iOS) communicating asynchronously to ensure zero-friction, reliable text capture.

## 1. watchOS Target (Capture & Persist)

The watchOS app is responsible for the raw capture of user dictation. It bypasses the standard Apple shortcuts and dictation UI limitations by using a custom pipeline.

### Components
- **`SpeechRecognizer`**: An `@Observable`, `@MainActor` class wrapping `SFSpeechRecognizer`. It is configured with `shouldReportPartialResults = true` and `requiresOnDeviceRecognition = true` (where supported) to prevent the OS from automatically timing out during silent pauses.
- **`LocalStore`**: An `@Observable` singleton that immediately persists captured text to `UserDefaults`. If the Watch is disconnected from the iPhone or the app is killed in the background, no data is lost.
- **Capture Views**:
  - **Main Interface**: Features a modern liquid glass aesthetic. Replaces legacy options with large, clear microphone and keyboard buttons for capture, and a prominent "Today's Daily Log" button at the bottom.
  - `InstantCaptureView`: Starts the `SpeechRecognizer` immediately on appear. It hooks into the SwiftUI `scenePhase` environment variable to automatically save the session with an accurate point-of-origin timestamp the exact moment the user lowers their wrist (`.background` or `.inactive`).
  - `SystemCaptureView`: A fallback using the native `TextField` for scribble or standard dictation.
- **Widget Extension**: Exposes complications that use `widgetURL` to deep link directly into the specific capture modes (`macromark://capture/instant`).

## 2. The Bridge (WatchConnectivity)

Because users often capture notes away from their phones, the sync mechanism must be robust.

### Components
- **`WatchConnectivityProvider`**: A shared `@MainActor` singleton wrapping `WCSession`. 
  - On the Watch, it uses `transferUserInfo` to enqueue notes, ensuring the payload includes the exact origin timestamp generated at the moment of dictation. It listens to the `didFinish` delegate callback to confirm the iPhone received the payload before deleting the note from `LocalStore`.
  - On iOS, it receives the `userInfo` payload in the background and triggers the processing pipeline with the correct timestamp.
  - **Isolation (Swift 6):** `WCSession` invokes its delegate callbacks on a background queue, so every `WCSessionDelegate` method is `nonisolated` and hops to the main actor (`Task { @MainActor in … }`) only for state access. Leaving them `@MainActor` traps at launch under Swift 6 language mode — the runtime executor check fires when WCSession calls them off-main. The incoming-file copy is done synchronously inside the callback, before WCSession reclaims its inbox file.

## 3. iOS Target (Process & Store)

The iPhone acts as the processing hub and storage engine.

### Components
- **`Macro` (SwiftData Model)**: Stores the user's custom text replacements (e.g., "Heading One" -> "# ").
- **`MacroProcessor`**: A stateless, `nonisolated` engine that runs off the main actor. It takes raw transcribed text plus a `[MacroRule]` — a `Sendable` value snapshot of each macro's trigger/replacement, taken from the SwiftData `Macro` models on the main actor — so no SwiftData model crosses an isolation boundary. It:
  1. Applies user-defined macros using case-insensitive Regex (compiled patterns are cached behind an `OSAllocatedUnfairLock` for thread-safe reuse across concurrent calls).
  2. Evaluates dynamic variables (`{date}`, `{time}`, `{newline}`, `{location}` using MapKit reverse geocoding).
  3. Cleans up formatting artifacts (e.g., removing spaces inside Markdown wrapping tags like `* bold *`).
- **`iCloudStorageManager`**: Resolves the app's ubiquitous iCloud Documents container. It formats the current date to locate `YYYY-MM-DD.md` and uses `NSFileCoordinator` and `FileHandle` to safely append the processed string to the end of the file.

## 4. Durability And Export State

MacroMark treats captured notes and recordings as user data, not transient messages. The reliability model is:

1. Watch capture persists locally before transfer.
2. WatchConnectivity delivers text or audio to the iPhone.
3. The iPhone processes the payload, expands macros, and saves the processed record.
4. Export status tracks whether the configured target appended successfully, deferred safely, or needs attention.
5. Watch-side data is acknowledged only after iPhone-side durability and export safety are established.

The public UI mirrors this model through inbox status, needs-attention filtering, note detail status, retry actions, partial transcription warnings, and destination setup proof. Any future sync/storage work must preserve idempotency: replayed notes, audio files, and ACK messages must not duplicate user-visible Markdown exports.

## 5. Product And Monetization Boundaries

The launch model is free download plus MacroMark Pro:

- Free tier: core Apple Watch/iPhone capture, daily-note append, and review.
- Pro: unlimited macros, default macro editing, folder customization, and advanced formatting/customization where shipped.
- StoreKit products: `com.macromark.subscription.annual` and `com.macromark.lifetime`.

The app has no account system and no third-party analytics in the v1.0 plan. Privacy disclosures, App Store metadata, and the website must stay consistent with that behavior.

## 6. Release And Documentation Architecture

- Promotion ladder: `feature/* -> nightly -> weekly -> main`.
- GitHub Pages source: `main /docs`.
- Release automation source: current workflow on `main`, narrowed to nightly internal TestFlight as of PR #90.
- Devlog automation: `Scripts/doc_automation/` updates `docs/guides/devlog.md` and `docs/devlog.html` and opens a reviewable PR.
- App Store readiness source: `docs/APP_STORE_READINESS.md`.

As of 2026-07-01, `origin/main` and `origin/nightly` are split: `main` has newer release automation, while `nightly` has newer v1 product/docs work. Resolve that split before final App Store submission so the branch being shipped, the release workflow, README, website, Fastlane metadata, and App Store Connect state all describe the same product.
