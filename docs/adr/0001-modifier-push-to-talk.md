# ADR 0001: Modifier-only push-to-talk backend

## Status

Accepted

## Context

Cue currently models push-to-talk as a configurable keyboard shortcut backed by `KeyboardShortcuts`.

That abstraction no longer matches the desired product direction:

- Cue should support only bare modifier hold-to-talk.
- Supported triggers are `fn`, `control`, `option`, and `command`.
- Cue should not support arbitrary shortcut chords.
- Cue should not keep two input backends alive.
- Cue should present a simple binary readiness model to the user: ready or not ready.

The existing dictation pipeline already consumes semantic press and release events, so the input layer can change without rewriting recording or transcription.

## Decision

Cue will replace the shortcut-based input layer with a single Cue-owned modifier monitor built on `CGEventTap`.

- Use one global `CGEventTap` configured as session-scoped and listen-only.
- Observe only `flagsChanged` events.
- Persist a single selected modifier in app-owned storage.
- Translate modifier flag transitions into semantic `pressed` and `released` events.
- Forward those events into the existing dictation workflow.
- Remove `KeyboardShortcuts` from the product and code path.

Cue readiness will require all three permissions that the shipping app needs:

- Microphone
- Input Monitoring for global modifier listening
- Accessibility/Post Event access for paste automation

Internally those permissions remain distinct because macOS exposes them separately. User-facing setup remains binary: Cue is either fully ready or not ready.

## Consequences

### Positive

- The input architecture matches the product directly.
- Cue owns its push-to-talk model instead of adapting a chord library.
- There is only one input backend.
- The existing dictation workflow remains intact.
- Settings UI becomes a simple modifier picker instead of a shortcut recorder.

### Negative

- Global modifier listening requires Input Monitoring in addition to the existing paste permission.
- `CGEventTap` introduces tap lifecycle concerns such as re-enabling after timeout or user disable events.
- Secure input can block event delivery in protected contexts.
- `fn` shares the same architecture as the other modifiers, but behavior must still be validated on laptop and external keyboards.

## Rejected alternatives

### Keep `KeyboardShortcuts`

Rejected because it is a chord-oriented abstraction and does not cleanly support bare modifier hold behavior.

### Hybrid backend: chords plus modifier monitoring

Rejected because it keeps two input systems alive for one feature area and complicates product behavior.

### `RegisterEventHotKey` / Carbon only

Rejected because it is appropriate for standard shortcuts, not bare modifier press and release.

### `NSEvent.addGlobalMonitorForEvents`

Rejected because it is not the supported sandboxed path for this requirement. For sandboxed apps that need global keyboard monitoring, Apple guidance points to `CGEventTap` plus Input Monitoring.

### `IOHID`-based monitoring

Rejected because it is more complex than `CGEventTap` and does not simplify the permission story.

## Implementation notes

- Keep the input callback minimal and move app work onto the main actor.
- Treat tap disable and session interruption as backend lifecycle concerns.
- Do not reintroduce fallback input modes.
- Do not expose chord recording UI anywhere in Cue.
