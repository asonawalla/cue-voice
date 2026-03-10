# Dropped Sentence Investigation

## Symptom

Intermittently, Cue drops a full sentence from a multi-sentence dictation, often the last sentence, even though the user reports they were still holding the push-to-talk shortcut and the audio was not obviously cut off.

## Current Leading Hypothesis

The most likely bug is a stop-time handoff race around WhisperKit's live audio buffer.

Cue currently:

1. Starts WhisperKit live recording.
2. Stops recording on hotkey release.
3. Immediately snapshots `audioProcessor.audioSamples`.
4. Sends that snapshot to WhisperKit for transcription.

WhisperKit currently appends incoming microphone buffers into `audioSamples` from the audio tap callback thread, while Cue reads the same buffer immediately after stop without any explicit synchronization.

If the buffer is still being mutated or has not fully drained at the moment Cue snapshots it, the transcribed audio can be missing the tail of the utterance. That would present exactly as "sometimes the last sentence is gone."

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

## Why this hypothesis fits the user report

- The bug is intermittent rather than deterministic.
- The missing content is often at the end of the utterance.
- There is no Cue-side logic that intentionally drops trailing segments after transcription.
- Pasteboard insertion also does not truncate text; it pastes whatever transcript Cue receives.

## Other Plausible Explanations

### Whisper decode quality issue

WhisperKit may sometimes return an incomplete transcript even when the audio buffer is intact, especially for lower-confidence trailing content. Cue currently accepts WhisperKit's output as-is and does not validate transcript coverage against the clip.

This remains plausible, but it does not explain the shared-buffer risk.

### Long-clip chunking edge cases

WhisperKit has chunking behavior for longer clips, but this looks less likely unless the affected dictations are unusually long.

## What we should log next

The first useful debug instrumentation should stay simple:

1. Save the exact audio snapshot that Cue sends into WhisperKit for transcription.
2. Save the raw WhisperKit transcription results for that snapshot.
3. Save the final flattened transcript that Cue pastes.

That is enough to answer the next question:

- If the saved audio file itself is missing the sentence, the problem is in capture or stop-time handoff.
- If the saved audio contains the sentence but WhisperKit output does not, the problem is in decoding.

## Suggested debug artifact layout

- Saved audio artifacts:
  - `~/Library/Containers/dev.sonawalla.Cue/Data/Library/Application Support/Cue/DebugCaptures/<capture-id>/`
- Tail-able debug index:
  - `~/Library/Containers/dev.sonawalla.Cue/Data/Library/Logs/Cue/debug.jsonl`

Each capture should include:

- `clip.wav`
- `result.json`
  - capture id
  - sample count
  - recording duration
  - WhisperKit raw segment texts
  - final Cue transcript

## Current status

This is still a hypothesis, not a validated root cause.

The next time the bug reproduces, the saved `clip.wav` plus WhisperKit output should tell us whether the sentence was lost before or during transcription.
