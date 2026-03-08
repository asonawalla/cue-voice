# Cue Voice

Cue is a native macOS menu bar dictation app built around local Whisper-based transcription.
It is optimized for a fast push-to-talk flow: hold a shortcut, speak, release, and let Cue
paste the transcript into the frontmost app.

## Product goals

Cue is intentionally opinionated. The app focuses on a small set of behaviors that matter most:

- local transcription for privacy and low latency
- a native macOS experience instead of a web wrapper
- minimal setup once microphone and Accessibility permissions are granted
- reliable insertion into the app you are already using
- small surface area with testable behavior

## How it works

Cue currently supports:

- global push-to-talk recording
- local model preparation through WhisperKit
- automatic paste when Accessibility is available
- clipboard fallback when automatic paste is unavailable
- menu bar status and setup guidance for permissions and model state
- UI-test bootstrapping with deterministic fake services

## Project layout

- `Cue/`: app source, workflow coordination, services, and SwiftUI views
- `CueTests/`: focused unit tests for app model, presentation, pasteboard insertion, and transcription
- `CueUITests/`: smoke coverage for app launch and the main window in UI-test mode
- `Config/`: shared Xcode build settings managed through `.xcconfig` files
- `scripts/`: small local and CI entrypoints for build and test commands
- `.github/workflows/`: GitHub Actions workflows

## Local development

Requirements:

- Xcode 26.2 or newer
- macOS 26.2 deployment support

Common commands:

```bash
./scripts/build.sh
./scripts/test.sh
./scripts/test-ui.sh
```

`./scripts/test.sh` runs the portable unit-test path. `./scripts/test-ui.sh` runs the opt-in UI smoke test via the shared `CueUI` scheme and requires a macOS session with UI automation available.

You can also open `Cue.xcodeproj` directly in Xcode and run the shared `Cue` scheme for unit-test work or `CueUI` for the UI smoke test.

## Testing and CI

- Unit tests cover the application workflow, permission states, transcription flow, and insertion behavior.
- UI tests launch the app with `--ui-testing`, which swaps in deterministic fake services and opens the main window.
- GitHub Actions runs the portable build and unit-test entrypoints on `macos-26`.

## NoteTest test 1, 2, 3.s

Cue is primarily a personal project, but the codebase is being shaped like a production app:
clearer state modeling, coordinator-driven workflow logic, focused tests, and automated CI.
