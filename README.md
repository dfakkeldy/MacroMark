# MacroMark

MacroMark is a zero-friction, voice-to-text capture tool designed for personal knowledge management (PKM) power users. Built by KinNoKi Labs, it provides an unparalleled on-the-go dictation experience for your Apple Watch, syncing seamlessly to plain-text Markdown files on your iPhone via iCloud Drive.

## Features

- **Zero-Friction Capture**: Tap the complication, speak, and lower your wrist. Your note is saved instantly with an accurate, watch-generated timestamp. No fumbling with "Done" buttons or battling system timeouts.
- **Reliability-First Sync**: Watch captures stay queued until the iPhone has durably processed them and the configured export path has succeeded or is safely queued for retry.
- **Beautiful Watch UI**: A modernized liquid glass interface featuring large, clear microphone and keyboard buttons for instant input selection, plus quick access to "Today's Daily Log" directly from your wrist.
- **The Append Mechanic**: Instead of cluttering your vault with hundreds of tiny files, MacroMark intelligently appends all your captures for a given day to a single `YYYY-MM-DD.md` daily note.
- **Daily Review by Date**: Inspect captures for today, yesterday, or any previous daily note from the phone inbox or Watch daily log.
- **Visible Status and Retry**: Export status labels, needs-attention filtering, partial-transcription warnings, and retry actions make capture state visible instead of mysterious.
- **Destination Proof**: Settings show the active export destination and can write a test note so you can verify iCloud or folder setup before relying on Watch capture.
- **Shortcuts Ready**: App Intents expose instant capture, typed capture, daily-log review, and append-text actions to Shortcuts and Siri.
- **Verbal Macros**: Speak custom trigger words to instantly format your text. Say "Heading One" to output `# `, or use variables like `{date}`, `{time}`, and `{location}` to build clever workflows.
- **Daily Note Formatting**: Configure timestamp style, separators, and an optional append heading for exported Markdown.
- **PKM Friendly**: Saves directly to a dedicated iCloud Documents folder, making it instantly accessible to Obsidian, Logseq, and other Markdown-based tools.

## v1.0 Roadmap

MacroMark v1.0 is the trust-and-capture release: Apple Watch quick capture for Markdown daily notes, with visible sync/export state, setup proof, daily-note review by date, App Intents, safer transcription waits, and App Store-ready privacy and metadata artifacts.

The full roadmap is in [docs/V1_ROADMAP.md](docs/V1_ROADMAP.md). It turns the competitor-review research in [docs/competitive-analysis.md](docs/competitive-analysis.md) into eight v1.0 milestones:

1. Reliability core.
2. Capture status and recovery.
3. Daily note review by date.
4. App Intents and Shortcuts.
5. Destination setup proof.
6. Daily note formatting.
7. Transcription integrity.
8. Launch monetization and App Store readiness.

Status notes: StoreKit products, screenshots, TestFlight upload, and paired iPhone/Watch smoke testing still need release verification before v1.0 can be submitted. The repository now includes launch metadata, privacy pages, and app/watch privacy manifests, but App Store Connect privacy answers and the live GitHub Pages privacy/support URLs must still be checked against the final build.

## Installation

### Prerequisites
- Xcode 26+ (targets iOS 26.5+ and watchOS 26.5+).
- Builds in **Swift 6 language mode** (Swift 6.2 toolchain) with strict concurrency.
- Apple Developer Program account (for iCloud Documents capabilities).

### Setup
1. Clone this repository.
2. Open `MacroMark.xcodeproj` in Xcode.
3. Select the **MacroMark** (iOS) target. Navigate to **Signing & Capabilities** and ensure your Team is selected.
4. Add the **iCloud** capability if it's missing, and check **iCloud Documents**. Ensure the container ID is valid for your developer account.
5. Build and run on your iPhone to create the default macros and trigger the iCloud container creation.
6. Build and run the **MacroMark Watch App** on your Apple Watch. Add the complications to your watch face for instant access.

## How it Works

1. **Speak**: Tap the `macromark://capture/instant` complication. The custom `SFSpeechRecognizer` begins transcribing immediately and *never* times out from silence.
2. **Wrist-Down Save**: When you lower your wrist, the watchOS `scenePhase` changes, immediately saving your text and the precise origin timestamp to local storage.
3. **Sync**: `WatchConnectivity` queues the payload and sends it to your iPhone (even in the background).
4. **Process & Store**: The iOS app processes your text through the Macro Engine and appends it to `YYYY-MM-DD.md` in iCloud Drive.
5. **Review by Date**: Open the daily log in the app or through Shortcuts to inspect captures for any chosen day.

## Tips

### Ending Hashtags During Dictation

Apple's dictation doesn't have a built-in way to signal the end of a hashtag — once you say "hashtag," dictation stays in tag mode and keeps listening for more characters. To end a hashtag, **say "new line"** (or "newline"). This inserts a line break, exits hashtag mode, and lets you continue dictating normally.

If you don't want the newline in your final text, say **"not"** immediately after. The built-in **Not** macro (`{backspace}`) deletes the preceding character, removing the unwanted newline:

> "hashtag topic **new line**" — ends the tag, leaves a newline  
> "hashtag topic **new line not**" — ends the tag, newline is deleted

💡 The "Not" trigger is a common English word, so it may fire accidentally in normal speech. If that happens, rename the macro's trigger to something less common (like "undo newline" or "no break") in **Settings → Macros**.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Release Engineering - Promotion Ladder

MacroMark uses a one-way promotion ladder: `feature/* -> nightly -> weekly -> main`.
Feature work branches from `nightly`, and pull requests target `nightly` by default.
`nightly` receives fast integration PRs and daily TestFlight builds, `weekly` is promoted
from `nightly` for Monday beta builds, and `main` remains the stable default branch.

| Branch | Source | Protection |
| --- | --- | --- |
| `nightly` | `feature/*` | Requires `Build gate + tests`; review optional. |
| `weekly` | `nightly` | Requires PR and strict `Build gate + tests`; no review required. |
| `main` | `weekly` | Requires PR and strict `Build gate + tests`; no review required. |

Hotfixes branch from `main`, merge back to `main` by PR, then flow down into `weekly`
and `nightly` so release trains stay consistent.

## License

[MIT](LICENSE)
