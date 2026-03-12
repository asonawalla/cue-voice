# Dropped Sentence Investigation

## Symptom

Intermittently, Cue drops a full sentence from a multi-sentence dictation, often the last sentence, even though the user reports they were still holding the push-to-talk shortcut and the audio was not obviously cut off.

## Current Leading Hypothesis

For the validated March 12 capture below, the loss happens during WhisperKit decode, not during audio capture.

Cue currently:

1. Starts WhisperKit live recording.
2. Stops recording on hotkey release.
3. Snapshots `audioProcessor.audioSamples`.
4. Sends that snapshot to WhisperKit for transcription as a single clip.

In this reproduced case, the saved `clip.wav` still contains the second sentence, but WhisperKit `0.16.0` with Cue's `base.en` model returns only the first sentence when decoding the full 8.7s clip in one pass.

The strongest current hypothesis is:

- short clips that still contain a meaningful pause between utterances can terminate early during full-clip decode
- WhisperKit then emits an end-of-transcript after the first sentence instead of continuing into the post-pause speech
- when the same audio is split at the pause boundary and each part is decoded separately, the missing second sentence is recovered

## Evidence

### Cue code path

- `Cue/WhisperKitTranscriptionService.swift`
  - `stopRecording()` calls `whisperKitClient.stopRecording()`
  - then immediately reads `whisperKitClient.audioSamples`
  - then transcribes that array

### WhisperKit code path

- `AudioProcessor.startRecordingLive(...)` installs an `AVAudioEngine` tap.
- The tap callback converts buffers and appends them into `audioSamples`.
- `AudioProcessor.stopRecording()` removes taps and stops the engine, but the shared `audioSamples` buffer is not handed off through a lock, actor, or immutable finalization step.

### Validated capture: `2026-03-12T10-50-23.568-04-00-a8442c6a-5c06-4649-b7db-e6e76c73a980`

User report:

- spoken first sentence: "can you attempt to use the G Cloud CLI to access the security command center?"
- spoken second sentence: "is that something that's even possible"
- Cue transcript dropped the entire second sentence

Saved debug artifacts:

- `clip.wav`
  - 8.70s, 16 kHz mono PCM
- `result.json`
  - final transcript: `"can you attempt to use the G Cloud CLI to access the security command center?"`
  - raw segments: one segment only, matching the first sentence

Observed audio shape:

- the saved clip contains a clear non-silent region after a pause near `6.85s`
- the trailing region is about `1.85s` long, which is sentence-sized and not just a clipped syllable tail

Reproduction against the same local stack:

- WhisperKit version: `0.16.0`
- model: `openai_whisper-base.en`
- full clip, single-pass decode:
  - output: `"can you attempt to use the G Cloud CLI to access the security command center?"`
- trailing clip only (`6.85s` to end):
  - output: `"Is that something that's even possible?"`
- full clip with forced split at `6.85s` using `clipTimestamps`:
  - output: `"can you attempt to use the G Cloud CLI to access the security command center? Is that something that's even possible?"`

This is the key result:

- the missing sentence is present in the saved audio
- the same sentence is recoverable by WhisperKit when decoded separately
- the failure mode is specific to full-clip decoding across the pause

### Model experiment: `small.en`

We also tested whether changing the WhisperKit model changes the outcome for this same saved clip.

Observed behavior:

- `base.en` with Cue's current/default compute path:
  - still drops the second sentence
- `base.en` with `cpuAndGPU` compute units for both audio encoder and text decoder:
  - still drops the second sentence
- `small.en` with the default Apple Neural Engine path:
  - stalls during model initialization on this machine while CoreML compiles for ANE
- `small.en` with `cpuAndGPU` compute units for both audio encoder and text decoder:
  - successfully transcribes both sentences from the full clip in one pass

Recovered full transcript with `small.en` plus `cpuAndGPU`:

- `"Can you attempt to use the GCloud CLI to access the security command center? Is that something that's even possible?"`

What this means:

- the improvement is not explained only by moving off ANE
- `base.en` still fails on `cpuAndGPU`
- `small.en` on `cpuAndGPU` succeeds on the same audio
- for this capture, changing the WhisperKit model does make a material difference

## Why this hypothesis fits the user report

- The bug is intermittent rather than deterministic.
- The missing content is often the trailing sentence after a pause.
- There is no Cue-side logic that intentionally drops later WhisperKit segments after transcription.
- Pasteboard insertion also does not truncate text; it pastes whatever transcript Cue receives.
- This specific capture proves the audio tail was preserved but the full-clip decode still ended early.

## Other Plausible Explanations

### Full-clip segmentation/seek behavior around pauses

This is now the leading explanation for the validated capture. When the entire clip fits inside a single Whisper window, WhisperKit does not apply VAD chunking. In this mode, a pause between sentences appears able to cause early decode termination even though later speech is still present.

This explanation fits the reproduction better than the original stop-time race.

### Capture/stop-time handoff race

This is still a plausible risk in general because Cue snapshots `audioSamples` immediately after stop with no explicit synchronization.

However, this March 12 capture does not support that theory:

- the saved `clip.wav` already contains the missing sentence
- the sentence can be transcribed when the saved audio is split and retried

So this hypothesis remains unvalidated for this specific failure.

## Current debug capture implementation

The current debug instrumentation stays intentionally simple:

1. Save the exact audio snapshot that Cue sends into WhisperKit for transcription.
2. Save the raw WhisperKit transcription results for that snapshot.
3. Save the final flattened transcript that Cue produces.

That is enough to answer the next question:

- If the saved audio file itself is missing the sentence, the problem is in capture or stop-time handoff.
- If the saved audio contains the sentence but WhisperKit output does not, the problem is in decoding.

## Current debug artifact layout

When `Cue.debugCapturesEnabled` is enabled, Cue writes debug captures under the app container caches directory:

- `~/Library/Containers/dev.sonawalla.Cue/Data/Library/Caches/dev.sonawalla.Cue/DebugCaptures/<yyyy-mm-dd>/<capture-id>/`

There is currently no separate `debug.jsonl` index in `Library/Logs`.

Each capture currently includes:

- `clip.wav`
- `result.json`
  - capture id
  - sample count
  - recording duration
  - WhisperKit raw segment texts
  - final Cue transcript

## Current status

The original stop-time capture-race theory is falsified for capture `2026-03-12T10-50-23.568-04-00-a8442c6a-5c06-4649-b7db-e6e76c73a980`.

What is now validated:

- Cue saved the full audio including the second sentence.
- WhisperKit dropped that second sentence when decoding the full clip in one pass.
- WhisperKit recovered the second sentence when the same saved audio was decoded as a separate tail clip or as two seek clips split at the pause.
- WhisperKit `small.en` with `cpuAndGPU` compute units recovered the full transcript without any pause-aware splitting.
- WhisperKit `small.en` on the default ANE path stalled during model initialization on this machine.

Current app configuration on this branch:

- Cue is now hardcoded to `small.en`.
- Cue now requests `cpuAndGPU` for both the WhisperKit audio encoder and text decoder.
- Cue ignores a cached model folder if it points at an older model variant such as `openai_whisper-base.en`.

What remains unvalidated:

- whether `small.en` plus `cpuAndGPU` eliminates the issue in normal day-to-day dictation
- whether other dropped-sentence reports share the same root cause as this capture
