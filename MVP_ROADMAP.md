# Cue MVP Roadmap

## MVP Goal

The MVP should prove one thing: Cue can turn speech into text and insert that
text into another macOS app with low enough latency to feel useful.

The narrow user flow is:

1. User focuses a text field in another app.
2. User holds a global push-to-talk hotkey.
3. Cue records microphone audio while the hotkey is held.
4. Cue transcribes the audio locally with Parakeet or whispr.
5. Cue pastes the transcript into the focused app.

If that loop works reliably in a few common apps, the core product is validated.

## MVP Scope

### In scope

- Local speech-to-text with Parakeet or whispr
- Global push-to-talk hotkey
- Microphone capture
- Cross-app paste pipeline
- Permissions onboarding for the required system access
- Basic menu bar app shell
- Basic logging and error states

### Out of scope

- AI rewrite or refinement
- Formatting commands
- Transcript history or storage
- Cloud sync
- Full accessibility-driven direct text insertion
- App Store distribution
- Broad app compatibility guarantees beyond a small tested set

## Milestones

### Milestone 1: Local Transcription Spike

Goal: prove that local transcription works on the target machine with acceptable
latency.

Work:

- Pick the first backend: Parakeet or whispr
- Define the boundary between Swift app code and the transcription runtime
- Capture a short microphone clip from the app
- Run the clip through the transcription backend
- Display the raw transcript inside Cue
- Add timing logs for record duration, transcription duration, and total latency

Deliverable:

- A local test flow where spoken audio returns a transcript in the app

Exit criteria:

- 5-10 second utterances transcribe successfully
- Total turnaround is fast enough to feel plausible for push-to-talk use
- We understand the integration shape well enough to productize it

Risks:

- Runtime integration may require a wrapper layer if the model code is not
  Swift-native
- Latency may force us to adjust model choice or audio chunking strategy

### Milestone 2: App Shell and Global Hotkey

Goal: turn the transcription spike into a usable background utility.

Work:

- Convert the app into a menu bar-oriented experience
- Define the app state machine: `idle`, `recording`, `transcribing`, `error`
- Add a global push-to-talk hotkey
- Start recording on key down and stop on key up
- Add a minimal status UI: menu bar icon, recording indicator, and last error

Deliverable:

- A menu bar app that can record and transcribe from a global hotkey

Exit criteria:

- Hotkey works while another app is focused
- Record start and stop are reliable
- State transitions are visible and debuggable

Risks:

- Some hotkey implementations require more system access than we want
- We need to avoid building the app around UI assumptions that break once it
  mostly runs in the background

### Milestone 3: Paste Pipeline

Goal: get text into the currently focused app with the simplest reliable
approach.

Work:

- Implement a pasteboard-based insertion flow
- Save the current clipboard contents
- Write the transcript to the pasteboard
- Synthesize `Cmd-V` into the focused app
- Restore the previous clipboard if that is reliable enough
- Add app compatibility testing for a small target set:
  - TextEdit
  - Notes
  - Slack
  - Chrome

Deliverable:

- End-to-end voice-to-text insertion into another app

Exit criteria:

- Paste works in the target app set
- Clipboard restore is either working or deliberately disabled with a known
  limitation
- Failure modes are understood and surfaced to the user

Risks:

- Clipboard restore can be flaky if the timing is wrong
- Some apps may accept paste differently or not at all

### Milestone 4: Permissions and Onboarding

Goal: make a fresh install understandable and usable without manual detective
work.

Work:

- Add microphone permission checks and request flow
- Add accessibility permission checks and guidance
- Detect missing permissions at startup and before first use
- Build a simple onboarding screen or menu state explaining what is blocked
- Add deep links or clear instructions into the relevant System Settings panes

Deliverable:

- A first-run experience that gets the user to a working state

Exit criteria:

- A fresh machine can get the app working without guesswork
- Missing permissions produce actionable instructions, not silent failure

Notes:

- Microphone permission is definitely required
- Accessibility permission is required for synthetic paste / key events
- Input Monitoring should be avoided for the MVP if a proper global hotkey
  library path lets us avoid it
- App Sandbox is likely the wrong default for this utility in early
  development

### Milestone 5: Prototype Polish

Goal: make the prototype usable enough for daily internal testing.

Work:

- Add configurable hotkey settings
- Add model selection or model path configuration if needed
- Improve status feedback during recording and transcription
- Add structured logging for failures and latency
- Add basic safeguards around repeated triggers and canceled recordings
- Decide on a few MVP-quality defaults for audio format and clip length

Deliverable:

- A stable internal prototype suitable for repeated real use

Exit criteria:

- The app feels predictable in normal use
- We can observe latency and failure modes without attaching a debugger
- Core settings no longer require code changes

## Suggested Build Order

1. Make local transcription work in-app.
2. Add the global hotkey and recording state machine.
3. Add paste into other apps.
4. Add permissions onboarding around the working core.
5. Polish only what is needed to make the prototype testable day to day.

This order matters. The paste pipeline and permissions work are only worth doing
once the transcription core is real.

## Testing Strategy for MVP

We do not need an elaborate test matrix yet, but we do need a small explicit
one.

### Functional checks

- Can Cue start and stop recording from the hotkey?
- Can Cue transcribe short utterances reliably?
- Can Cue paste into TextEdit, Notes, Slack, and Chrome?
- Does Cue recover from a failed transcription or canceled recording?

### Latency checks

- Time to start recording after hotkey press
- Time from hotkey release to transcript availability
- End-to-end time from release to pasted text

### Permission checks

- Fresh launch with no permissions granted
- Microphone granted, accessibility missing
- Accessibility granted, microphone missing

## Open Decisions

- Which transcription backend is first: Parakeet or whispr?
- Do we restore the clipboard in the MVP, or accept temporary clipboard
  mutation?
- Which hotkey implementation gives us the right balance of reliability and
  permission footprint?
- Do we keep the prototype sandboxed or disable App Sandbox immediately?

## Tomorrow's Starting Point

Start with Milestone 1.

Concrete first steps:

1. Decide the first transcription backend.
2. Add a thin transcription service boundary in Swift.
3. Add microphone capture for a short local clip.
4. Get that clip through the backend and show the transcript in the app.
5. Measure latency before touching the paste pipeline.
