# Cue

Cue is one local dictation loop for macOS:

1. Hold `⌥Space`.
2. Speak.
3. Release.
4. Cue transcribes with FluidAudio and NVIDIA Parakeet, then pastes at the cursor.

Cue has one model and one shortcut. Transcripts replace the clipboard and are not stored. The app needs Microphone and Accessibility access; the first launch also downloads the Parakeet model. Launch at Login is available from the menu bar.

Speech recognition is powered by NVIDIA Parakeet and FluidAudio.

## Install on this Mac

In Xcode, select the **Install Cue** scheme and choose **Product → Build**. The scheme builds Cue for this Mac, replaces `/Applications/Cue.app`, and launches the installed copy.
