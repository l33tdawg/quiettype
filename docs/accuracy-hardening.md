# QuietType accuracy hardening plan

Status: research notes for beta.8 and beta.9.

Goal: improve real-world dictation accuracy without sending audio, transcripts, prompts, vocabulary, or voice samples to cloud services.

## Summary

We should not start with local fine-tuning. The faster, safer path is to harden the local pipeline around proven ASR production techniques:

1. Better audio frontend.
2. Hybrid VAD and endpointing.
3. Overlapped streaming chunks.
4. ASR prompt/vocabulary biasing.
5. Deterministic inverse text normalization.
6. Fuzzy vocabulary repair.
7. A larger local regression corpus.

This keeps the UX Apple-simple while moving accuracy materially.

## Sources reviewed

- Argmax WhisperKit / Argmax OSS Swift: on-device Whisper for Apple Silicon, local server, OpenAI-compatible transcription endpoint, `prompt`, `temperature`, word/segment timestamp options, and streaming support.
- whisper.cpp CLI: supports beam search settings, entropy/logprob/no-speech thresholds, initial prompt, word timestamps, JSON output, grammar-guided decoding, and suppress-regex.
- Silero VAD: established voice activity detector with ONNX runtime option.
- RNNoise: C library for recurrent-neural-network noise suppression.
- Vosk: offline streaming ASR with small models, reconfigurable vocabulary, and speaker identification.
- NVIDIA NeMo text processing: production-oriented text normalization and inverse text normalization.
- Whisper paper: Whisper is robust out of the box and explicitly treats ASR as more than just raw word prediction.

## Recommended beta.8 work

### 1. Use ASR prompt biasing every time

WhisperKit local server supports a `prompt` parameter. QuietType should compile a compact prompt from:

- active app profile
- user vocabulary
- SAGE memories
- recent corrections
- current training-set terms
- app-specific technical terms

Example prompt:

```text
Vocabulary and spellings: QuietType, SAGE, CometBFT, Ed25519, CSe100, Ollama.
Preserve code identifiers and acronyms. The speaker may say shopping lists, numbered steps, or coding-agent instructions.
```

Constraints:

- Keep prompt short.
- Do not include private nearby document text unless explicitly enabled.
- Use only high-confidence vocabulary/correction memories.
- A/B test with and without prompt because over-biasing can cause false positives.

### 2. Add overlapped chunking

Current chunking should not cut hard at exact one-second boundaries. Use a small overlap so words crossing a boundary are not lost.

Recommended:

- chunk size: 1.5-2.0 seconds
- overlap: 300-500 ms
- merge by stable prefix / timestamp-aware de-duplication
- final tail: decode full trailing window after key release

This is a common streaming ASR pattern and should improve perceived immediacy without losing boundary words.

### 3. Hybrid VAD before ASR

Use a cheap energy gate first, then a stronger speech detector when needed.

Recommended beta.8 path:

- Keep RMS/energy gate for low overhead.
- Add hysteresis so we do not flap between speech/non-speech.
- Add a speech-start pre-roll buffer, e.g. 250-400 ms.
- Add speech-end hangover, e.g. 500-800 ms.

Recommended beta.9 path:

- Evaluate Silero VAD through ONNX Runtime or a small helper binary.
- Compare against WebRTC VAD and current RMS gate.

Important behavior:

- Do not discard quiet speech too aggressively.
- Do not pass music-only chunks as speech.
- Show users a live mic level/speech indicator during training and dictation.

### 4. Turn on macOS voice-processing capture where it helps

Investigate `AVAudioInputNode` voice-processing support for echo cancellation/noise suppression. This may help with cafés, fans, speaker playback, and laptop mics.

Implementation shape:

- Add a user-hidden default: `voiceProcessingMode = auto`.
- Record evaluation samples with voice processing on/off.
- Prefer the better path per microphone if we can detect it.

Do not ship this blindly. Voice processing can sometimes damage ASR input, especially for high-quality external microphones.

### 5. Add optional denoise stage, not mandatory denoise

RNNoise is attractive because it is local, C-based, small, and designed for real-time noise suppression.

Recommended:

- Build a benchmark harness first.
- Evaluate RNNoise on noisy café samples, keyboard noise, music leakage, fan noise, and quiet speech.
- Only use denoise when it improves WER or confidence.

Risk:

- Denoising can remove consonants or distort technical terms.
- Do not apply it globally until measured.

### 6. Add deterministic vocabulary repair

After ASR, before semantic editing, run a conservative vocabulary repair pass:

- known spoken form -> preferred spelling
- ASR confusion map -> preferred spelling
- fuzzy match near known vocabulary
- preserve case for acronyms and identifiers

Use a strict score threshold and local context. For example:

```text
"comet bee eff tee" -> "CometBFT"
"ed twenty five five nineteen" -> "Ed25519"
"all llama" -> "Ollama"
```

RapidFuzz is a good reference for fast fuzzy matching, but for the app we should probably implement a small Swift-native matcher instead of embedding Python.

### 7. Expand deterministic ITN rules

NeMo’s ITN work confirms that production systems still use deterministic WFST-style rules because text normalization has low tolerance for unrecoverable errors.

For QuietType, implement a targeted Swift ITN layer:

- numbers: `three` -> `3` when list quantity/context says so
- ordinals: `first`, `second`, `third`
- times: `three PM` -> `3:00 PM`
- dates: `July fifth`
- measurements: `16 gigabytes`, `twenty milliseconds`
- code-ish symbols: `slash`, `dash`, `underscore`, `dot`

Avoid broad conversion in prose. Example: do not turn every `one` into `1`.

## Recommended beta.9 work

### 1. Build the accuracy corpus

Create local fixtures for:

- coding-agent instructions
- grocery lists
- numbered task lists
- app-specific Slack/email/notes outputs
- correction phrases
- noisy café/music samples
- technical vocabulary
- long-winded 3-5 minute dictations
- quiet speech
- external mic vs laptop mic

Track:

- raw ASR WER
- vocabulary spelling accuracy
- list formatting accuracy
- correction handling accuracy
- semantic edit distance
- key-release-to-insert latency
- false insertion / empty result rate

### 2. Add local "teach from correction"

When the user edits inserted text, offer a simple correction save path:

```text
Always write this as CometBFT.
```

Behind the scenes, store:

- spoken/raw ASR fragment
- corrected text
- app context
- confidence
- source: user-approved

Do not auto-promote raw transcript notes to high-confidence correction facts.

### 3. Consider Vosk as a special fallback, not primary ASR

Vosk is offline, streaming, small, and supports reconfigurable vocabulary. It is likely not better than WhisperKit for general dictation, but it may be useful for:

- command phrases
- constrained grammar modes
- low-resource fallback
- future multi-language packs

Do not replace WhisperKit with Vosk for primary dictation without benchmarks.

## Implementation priority

1. ASR prompt biasing.
2. Overlapped chunk merge.
3. VAD hysteresis + pre-roll/hangover.
4. Expand ITN and vocabulary repair.
5. Accuracy corpus and benchmark dashboard.
6. Optional RNNoise benchmark.
7. Silero VAD benchmark.
8. Vosk constrained-mode experiment.

## Sources

- Argmax OSS Swift / WhisperKit: https://github.com/argmaxinc/argmax-oss-swift
- whisper.cpp CLI: https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/examples/cli/README.md
- Silero VAD: https://github.com/snakers4/silero-vad
- RNNoise: https://github.com/xiph/rnnoise
- Vosk API: https://github.com/alphacep/vosk-api
- NeMo text processing: https://github.com/NVIDIA/NeMo-text-processing
- NeMo ITN paper: https://arxiv.org/abs/2104.05055
- Whisper paper: https://cdn.openai.com/papers/whisper.pdf
