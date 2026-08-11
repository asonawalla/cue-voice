# Third-party software and models

Cue's MIT License covers Cue's own source code and assets. This repository does not vendor third-party source code or model files. The software and models resolved when Cue is built retain their respective licenses.

This document identifies Cue's direct dependencies and runtime model. It is not a complete binary-redistribution license bundle.

## Direct dependencies

### FluidAudio

Cue uses [FluidAudio](https://github.com/FluidInference/FluidAudio) for local speech recognition.

- Pinned version: 0.12.6
- License: [Apache License 2.0](https://github.com/FluidInference/FluidAudio/blob/aa800cb9630dc14727507ac0c955fa4d7ca415ec/LICENSE)

### KeyboardShortcuts

Cue uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the global push-to-talk shortcut.

- Pinned version: 1.9.4
- Copyright © Sindre Sorhus
- License: [MIT License](https://github.com/sindresorhus/KeyboardShortcuts/blob/8c90a95cb9f94d5c26182cb7d447c54ba5416984/license)

Swift Package Manager also resolves EventSource, swift-asn1, swift-atomics, swift-collections, swift-crypto, swift-huggingface, swift-jinja, swift-nio, swift-system, swift-transformers, and yyjson. Those packages are pinned in the project lockfile and retain the licenses published by their respective authors.

Before distributing a compiled binary, inspect the produced application, generate a complete dependency inventory, and include every license text and upstream notice it requires. FluidAudio itself includes separately licensed third-party components that must be included in that review.

## Speech-recognition model

Cue downloads the [FluidInference Core ML conversion](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) of [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) on first use. NVIDIA publishes the base model under the [Creative Commons Attribution 4.0 International license](https://creativecommons.org/licenses/by/4.0/). The Core ML conversion is provided by FluidInference and is not pinned to an immutable model revision by Cue.

As checked on August 11, 2026, the conversion repository's metadata labels it CC BY 4.0 while its model-card license section says Apache 2.0. This document does not resolve that conflict. Cue distributions do not include model files; if you mirror, prefetch, bundle, or otherwise redistribute those artifacts, verify and comply with their governing terms.
