# Cue Values and Metrics

Cue should be **fast, reliable, and local**.

## Fast

The Last Run card reports the measurements Cue currently records:

- `pressToAck`: push-to-talk press to immediate audible and visual feedback
- `releaseToProofOfLife`: release to the first indication Cue is processing
- `releaseToInsert`: release to the paste command
- `transcriptionDuration`
- `pasteDuration`

Speaking time is not part of the latency headline. Individual readings are diagnostic; Cue does not currently aggregate percentiles or slow-run rates.

## Reliable

Cue must either insert the transcript into the intended app or present a clear failure. The current proof consists of unit tests for permission gates, recording lifecycle, transcription errors, clipboard preservation, paste ownership, and early shortcut release.

User-enabled debug captures save audio and transcription results for investigating failures. Cue does not currently maintain an evaluation corpus or field reliability metrics.

## Local

Recording, transcription, and insertion run on-device. The model may require a one-time download; after it is cached, dictation does not require a server, account, subscription, or cloud inference.

These are product constraints, not telemetry targets. Add measurement machinery only when the project actually collects and uses it.
