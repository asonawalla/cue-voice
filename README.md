# Cue

Cue is one local dictation loop for macOS:

1. Hold `⌥Space`.
2. Speak.
3. Release.
4. Cue transcribes with FluidAudio and NVIDIA Parakeet, then pastes at the cursor.

Cue has one model and one shortcut. It runs speech recognition locally, keeps no transcript history, and has no account or analytics. Launch at Login is available from the menu bar.

## Requirements

- macOS 26.2 or later
- Xcode 26.3 or later
- About 500 MB of free space for the speech-recognition model
- An internet connection for the initial build dependencies and first model download

Cue is currently tested on Apple silicon. Intel support has not been verified.

## Install from source

Cue does not currently provide a signed release binary. Build and install it with Xcode:

```sh
git clone https://github.com/asonawalla/cue-voice.git
cd cue-voice
open Cue.xcodeproj
```

In Xcode:

1. Select the **Install Cue** scheme and **My Mac** as the destination.
2. Choose **Product → Build**.

Xcode resolves the pinned Swift package dependencies on the first build. The scheme then builds Cue for the current Mac, replaces `/Applications/Cue.app`, and launches the installed copy. This produces a local development build, not a signed release for redistribution.

Cue does not update itself. To update a source installation, pull the latest changes and build the **Install Cue** scheme again.

## First launch

Cue is a menu-bar app. It opens no window and does not appear in the Dock; look for its icon in the menu bar.

Cue asks for the permissions required by its fixed dictation loop:

1. Allow **Microphone** access so Cue can record while the shortcut is held.
2. Allow **Accessibility** access so Cue can paste the finished transcript into the active app.
3. Wait while Cue downloads and prepares the Parakeet model. The model is cached locally for later launches.

If a permission was denied, grant it in **System Settings → Privacy & Security**, then hold `⌥Space` again. Cue retries preparation on the next shortcut press.

## Use

1. Put the cursor where the transcript should go.
2. Hold `⌥Space` and speak.
3. Release the shortcut.
4. Cue transcribes locally and pastes into the app that was active when recording began.

Cue replaces the current clipboard contents with each non-empty transcript. It does not restore the previous clipboard contents.

Use the menu bar icon to view Cue's status, enable Launch at Login, or quit the app.

## Privacy

- Each completed recording is written to a temporary local WAV file and deleted after its transcription attempt finishes.
- Transcripts are copied to the system clipboard and are not stored by Cue.
- Cue uses the network to download the speech-recognition model. It does not send recordings away for transcription.
- Cue has no user account, analytics, or transcript history.

## Troubleshooting

**Cue stays on “Preparing Parakeet…”**

The first launch needs an internet connection and enough free space for the model. Open the menu bar item to check whether Cue is instead waiting for a permission.

**Cue reports that Microphone or Accessibility access is required**

Open **System Settings → Privacy & Security**, grant the requested access to Cue, and press `⌥Space` again.

**The transcript is copied but not pasted**

Confirm that Cue is enabled under **Accessibility**. The transcript remains on the clipboard, so it can still be pasted manually.

**Cue says “Ready” but `⌥Space` does nothing**

Check whether another app or macOS shortcut already uses `⌥Space`. Disable the conflicting shortcut, then quit and relaunch Cue. Cue's shortcut is fixed.

If these steps do not resolve a problem, open a GitHub issue with the Mac model, macOS version, exact Cue status message, and reproduction steps. Do not include recordings or transcript text unless they are necessary and you intend to share them.

## Development

Run the test suite with:

```sh
./scripts/test.sh
```

Cue intentionally keeps one shortcut, one model, and one output path. Settings, transcript history, alternate engines, and other optional surfaces are outside that fixed workflow.

## License

Cue is available under the [MIT License](LICENSE). Its dependencies and speech-recognition model retain their own licenses; see [Third-party software and models](THIRD_PARTY_NOTICES.md).
