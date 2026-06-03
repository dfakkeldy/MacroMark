# MacroMark

MacroMark is a zero-friction, voice-to-text capture tool designed for personal knowledge management (PKM) power users. Built by Echo Technologies, it provides an unparalleled on-the-go dictation experience for your Apple Watch, syncing seamlessly to plain-text Markdown files on your iPhone via iCloud Drive.

## Features

- **Zero-Friction Capture**: Tap the complication, speak, and lower your wrist. Your note is saved instantly. No fumbling with "Done" buttons or battling system timeouts.
- **The Append Mechanic**: Instead of cluttering your vault with hundreds of tiny files, MacroMark intelligently appends all your captures for a given day to a single `YYYY-MM-DD.md` daily note.
- **Verbal Macros**: Speak custom trigger words to instantly format your text. Say "Heading One" to output `# `, or use variables like `{date}` and `{time}` to build clever workflows.
- **PKM Friendly**: Saves directly to a dedicated iCloud Documents folder, making it instantly accessible to Obsidian, Logseq, and other Markdown-based tools.

## Installation

### Prerequisites
- Xcode 15+ (Requires targeting iOS 26.0+ and watchOS 10.0+).
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
2. **Wrist-Down Save**: When you lower your wrist, the watchOS `scenePhase` changes, immediately saving your text to local storage.
3. **Sync**: `WatchConnectivity` queues the payload and sends it to your iPhone (even in the background).
4. **Process & Store**: The iOS app processes your text through the Macro Engine and appends it to `YYYY-MM-DD.md` in iCloud Drive.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

[MIT](LICENSE)
