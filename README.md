# MacroMark

MacroMark is a zero-friction, voice-to-text capture tool designed for personal knowledge management (PKM) power users. Built by KinNoKi Labs, it provides an unparalleled on-the-go dictation experience for your Apple Watch, syncing to plain-text Markdown files on your iPhone via iCloud Drive by default. Direct Send is an optional v1.1 route on `nightly`: after one-time iPhone setup, watch text can go to GitHub daily Markdown files, an HTTPS webhook, or both. See [Direct Send](docs/DIRECT_SEND.md).

MacroMark 1.0 is free on the App Store: [MacroMark on the App Store](https://apps.apple.com/app/macromark/id6785081218). It was released on 2026-10-23. Direct Send is not in 1.0; it ships in 1.1.

## Features

- **Zero-Friction Capture**: Tap the complication, speak, and lower your wrist. Your note is saved instantly with an accurate, watch-generated timestamp. No fumbling with "Done" buttons or battling system timeouts.
- **Reliability-First Sync**: Watch captures stay queued until delivery is confirmed. On the default phone/iCloud route, that means the iPhone has durably processed them and the configured export path has succeeded or is safely queued for retry. Direct Send keeps each note until every selected destination confirms delivery.
- **Beautiful Watch UI**: A modernized liquid glass interface featuring large, clear microphone and keyboard buttons for instant input selection, plus quick access to "Today's Daily Log" directly from your wrist.
- **The Append Mechanic**: Instead of cluttering your vault with hundreds of tiny files, MacroMark intelligently appends all your captures for a given day to a single `YYYY-MM-DD.md` daily note.
- **Daily Review by Date**: Inspect captures for today, yesterday, or any previous daily note from the phone inbox or Watch daily log.
- **Visible Status and Retry**: Export status labels, needs-attention filtering, partial-transcription warnings, and retry actions make capture state visible instead of mysterious.
- **Open in Another App**: Optionally choose Drafts, Obsidian, Bear, or Day One as the default destination and auto-open it when a note finishes processing (the phone must be unlocked). The Share Sheet is also available from a note.
- **Destination Proof**: Settings show the active export destination and can write a test note so you can verify iCloud or folder setup before relying on Watch capture.
- **Shortcuts Ready**: App Intents expose instant capture, typed capture, daily-log review, and append-text actions to Shortcuts and Siri.
- **Verbal Macros**: Speak trigger words to format your text. Say "Heading One" to output `# `, or "Task" to output `- [ ] `. The 24 built-in macros cover headings, bold/italic/strikethrough, code, quotes, lists, tasks and rules. Custom macros can use `{date}`, `{time}`, `{location}`, `{clipboard}`, `{uuid}`, `{newline}`, `{tab}` and `{backspace}`.
- **Daily Note Formatting**: Configure timestamp style, separators, and an optional append heading for exported Markdown.
- **PKM Friendly**: Saves directly to a dedicated iCloud Documents folder (or a folder you choose, with flat, monthly or year/month subfolders), making it instantly accessible to Obsidian, Logseq, and other Markdown-based tools.
- **Direct Send (v1.1, `nightly`)**: Optional phone-free delivery of watch text to GitHub, an HTTPS webhook, or both. Audio stays on the phone transcription route. The app remains free. Details: [docs/DIRECT_SEND.md](docs/DIRECT_SEND.md).

## v1.0 Roadmap

MacroMark v1.0 is the trust-and-capture release: Apple Watch quick capture for Markdown daily notes, with visible sync/export state, setup proof, daily-note review by date, App Intents, safer transcription waits, and privacy pages and store metadata. Direct Send is v1.1 work on `nightly` ([#125](https://github.com/dfakkeldy/MacroMark/pull/125)); it is not in the 1.0 App Store release.

The full roadmap is in [docs/V1_ROADMAP.md](docs/V1_ROADMAP.md). It turns the competitor-review research in [docs/competitive-analysis.md](docs/competitive-analysis.md) into eight v1.0 milestones:

1. Reliability core.
2. Capture status and recovery.
3. Daily note review by date.
4. App Intents and Shortcuts.
5. Destination setup proof.
6. Daily note formatting.
7. Transcription integrity.
8. Free launch and App Store readiness.

Status as of 2026-10-24: MacroMark 1.0 is live on the App Store. Version 1.0
was released on 2026-10-23 and is free. The public App Store lookup does not
show a build number. The 1.0 release fully unlocks custom macros,
default-macro editing and folder customization. Existing ownership and product
IDs are preserved. The candidate was promoted to weekly in
[#120](https://github.com/dfakkeldy/MacroMark/pull/120) and to main in
[#121](https://github.com/dfakkeldy/MacroMark/pull/121). `nightly` now carries
version 1.1 work: Direct Send ([#125](https://github.com/dfakkeldy/MacroMark/pull/125))
and watch audio retry ([#145](https://github.com/dfakkeldy/MacroMark/pull/145)).
Release evidence is in [readiness](docs/APP_STORE_READINESS.md).

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

1. **Speak**: Tap the Instant Capture complication (`macromark://capture/instant`). The watch starts recording audio right away. Recording does not stop on silence. The System Capture complication (`macromark://capture/system`) opens the standard watch dictation and keyboard instead.
2. **Wrist-Down Save**: When you lower your wrist, the watchOS `scenePhase` changes. The watch stops recording and saves the audio and the origin timestamp to its durable queue.
3. **Sync (default)**: `WatchConnectivity` sends the queued text or audio to your iPhone (even in the background). The watch keeps the note until the phone ACKs durable processing and export safety. An audio transfer that is still unconfirmed after a day is sent again with the same ID.
4. **Process & Store**: The iPhone transcribes audio with Apple Speech (`SFSpeechRecognizer`), expands macros, and appends the note to the daily `YYYY-MM-DD.md` file in iCloud Drive or your chosen folder.
5. **Optional Direct Send (v1.1, `nightly`)**: After one-time iPhone setup, watch text can skip the phone and go to GitHub daily Markdown, an HTTPS webhook, or both. Phone/iCloud remains the default. Audio always uses the phone route. See [Direct Send](docs/DIRECT_SEND.md).
6. **Review by Date**: Open the daily log in the app or through Shortcuts to inspect captures for any chosen day.

## Tips

### Ending Hashtags During Dictation

Apple's dictation doesn't have a built-in way to signal the end of a hashtag — once you say "hashtag," dictation stays in tag mode and keeps listening for more characters. To end a hashtag, **say "new line"** (or "newline"). This inserts a line break, exits hashtag mode, and lets you continue dictating normally.

If you don't want the newline in your final text, say **"backspace"** immediately after. The built-in **Backspace** macro (`{backspace}`) deletes the preceding character, removing the unwanted newline:

> "hashtag topic **new line**" — ends the tag, leaves a newline  
> "hashtag topic **new line backspace**" — ends the tag, newline is deleted

Test builds installed before June 28, 2026 may still have this macro under its original trigger, **Not**. Restoring defaults or renaming it in the **Macros** tab updates it.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Release Engineering - Promotion Ladder

MacroMark uses a one-way promotion ladder: `feature/* -> nightly -> weekly -> main`.
Feature work branches from `nightly`, and pull requests target `nightly` by default.
`nightly` receives fast integration PRs and daily TestFlight builds, `weekly` is promoted
from `nightly` for Monday beta builds, and `main` remains the stable default branch.

GitHub Pages currently publishes from `main /docs`. Website-only changes that need to deploy before the next `nightly -> weekly -> main` promotion may target `main`, but product code should continue through the ladder.

| Branch | Source | Protection |
| --- | --- | --- |
| `nightly` | `feature/*` | Requires `Build gate + tests`; review optional. |
| `weekly` | `nightly` | Requires PR and strict `Build gate + tests`; no review required. |
| `main` | `weekly` | Requires PR and strict `Build gate + tests`; no review required. |

Hotfixes branch from `main`, merge back to `main` by PR, then flow down into `weekly`
and `nightly` so release trains stay consistent.

## License

[MIT](LICENSE)
