# Cue Values and Metrics

Three things matter: **Fast. Reliable. Local.**

---

## Fast

Cue should feel instant. That means reacting the moment you press, and getting text into your app fast.

"Fast" isn't one number. It's four moments:

- You press — Cue acknowledges immediately
- You release — something visible happens right away
- Text appears in your app quickly
- The slow cases don't pile up

### Metrics

- `press_to_ack_p95` — time from PTT press to any visible/audible confirmation
- `release_to_proof_of_life_p95` — time from PTT release to first sign Cue is working
- `release_to_insert_p50` — typical end-to-end latency (release → text in app)
- `release_to_insert_p95` — tail latency (the runs that feel slow)
- `slow_run_rate_over_1s` — % of dictations taking >1s
- `slow_run_rate_over_2s` — % of dictations taking >2s

Always break speed metrics down by: warm vs cold model, utterance length, target app, first-run vs steady state.

### What we already track

We already record `recordingDuration`, `transcriptionDuration`, `pasteDuration`, `totalDuration`, `modelLoadDuration`, and `backendPipelineDuration` per run. Useful, but they don't directly map to user-felt latency. Press-to-ack, release-to-proof-of-life, and release-to-insert need to be first-class.

### Rules

- Don't include speaking time in the speed headline — that's on the user, not us.
- Don't judge speed by average alone. Slow tail runs are what people remember.

---

## Reliable

Cue should transcribe what you said and put it where you want it. Every time. When it can't, it should fail loudly and clearly instead of silently doing the wrong thing.

Reliability is primarily an **eval problem**. Runtime metrics matter, but they're secondary — they catch blind spots the eval set misses, not the other way around.

### Metrics

- `eval_pass_rate` — % of curated eval cases that pass the current acceptance rule
- `eval_regression_count` — new failures vs the last baseline
- `insertion_success_rate` — % of dictations where the transcript actually lands in the target app
- `non_empty_transcript_rate` — % of non-empty recordings that produce a non-empty transcript
- `failure_rate_by_stage` — breakdowns for recording, transcription, and insertion failures

Runtime checks (secondary to evals):
- crash-free session rate
- retry-required rate
- dropped-transcript incident count
- permission-related failure rate

### Eval corpus should cover

- short and long utterances
- multi-sentence dictation
- punctuation and capitalization
- proper nouns and technical terms you'd actually dictate
- varied pause patterns and speaking rates
- the target apps we care most about

### Rules

- Let evals drive reliability decisions. Runtime checks catch eval blind spots — they don't replace evals.
- If a reliability change touches onboarding, permissions, or paste behavior, document the user-visible change explicitly.

---

## Local

Everything in the core dictation path runs on-device. No cloud inference, no server round-trip, no subscription required.

Local is a hard constraint, not a dial.

### Release gates

Core dictation only counts as "local" if ALL of these stay true:

- Audio stays on-device
- Transcription runs on-device
- Insertion runs on-device
- No network connection required to dictate
- No account or subscription required to use core dictation

### Checks

- `offline_dictation_smoke_test` — must pass
- `outbound_network_requests_during_dictation` — must be zero for the core path
- `remote_dependency_in_critical_path` — must be false for the core path
- `local_model_ready_rate` — % of launches where the local model loads successfully

### Rules

- Local is a product constraint, not a score. Don't dilute it.
- Features that add a remote dependency are additive and non-core by default — they don't affect core dictation.

---

## How we measure

**Lab** (regressions and repeatability): fixed benchmark corpus, controlled machine state, version-to-version comparison.

**Field** (real-world truth): local-only per-run diagnostics, p50/p95/p99 distributions, real target app mix, warm and cold state behavior.

---

## Priority order

1. Make **Fast** measurable in concrete terms — start with release-to-insert latency.
2. Make **Reliable** measurable through a curated eval corpus with regression tracking.
3. Preserve **Local** with explicit release gates and offline smoke tests.

---

## References

- [Apple HIG: Loading](https://developer.apple.com/design/human-interface-guidelines/loading)
- [web.dev RAIL model](https://web.dev/articles/rail)
- [web.dev INP](https://web.dev/articles/inp)
- [web.dev User-Centric Performance Metrics](https://web.dev/articles/user-centric-performance-metrics)

---

When this doc changes, update it in the same PR so it reflects what we actually decided.
