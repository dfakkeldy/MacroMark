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
- **`WatchConnectivityProvider`**: A shared singleton wrapping `WCSession`. 
  - On the Watch, it uses `transferUserInfo` to enqueue notes, ensuring the payload includes the exact origin timestamp generated at the moment of dictation. It listens to the `didFinish` delegate callback to confirm the iPhone received the payload before deleting the note from `LocalStore`.
  - On iOS, it receives the `userInfo` payload in the background and triggers the processing pipeline with the correct timestamp.

## 3. iOS Target (Process & Store)

The iPhone acts as the processing hub and storage engine.

### Components
- **`Macro` (SwiftData Model)**: Stores the user's custom text replacements (e.g., "Heading One" -> "# ").
- **`MacroProcessor`**: A stateless engine that takes raw transcribed text and:
  1. Applies user-defined macros using case-insensitive Regex.
  2. Evaluates dynamic variables (`{date}`, `{time}`, `{newline}`, `{location}` using MapKit reverse geocoding).
  3. Cleans up formatting artifacts (e.g., removing spaces inside Markdown wrapping tags like `* bold *`).
- **`iCloudStorageManager`**: Resolves the app's ubiquitous iCloud Documents container. It formats the current date to locate `YYYY-MM-DD.md` and uses `NSFileCoordinator` and `FileHandle` to safely append the processed string to the end of the file.
