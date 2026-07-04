# Model Strategy

Status: draft recommendation after web research on 2026-07-04.

## Decision

Use a multi-model local stack. Do not look for one model to do everything.

Target hardware floor:

```text
Minimum supported family:
  Apple Silicon M1 series

Practical minimum for MVP quality target:
  M1 Pro / M1 Max with 16 GB+ unified memory

Recommended benchmark floor:
  M1 Max with 32 GB unified memory
```

The M1 Max was announced in October 2021, so as of July 4, 2026 it is about 4 years and 8 months old. Treating it as the main benchmark floor is reasonable for a premium local-AI product. A base M1 should still run the app, but may default to smaller/faster models and may not hit the same latency target.

Default MVP stack:

```text
ASR:
  WhisperKit + large-v3-v20240930_turbo on macOS Apple Silicon

ASR fallback:
  whisper.cpp + large-v3-turbo or small.en/base.en depending on hardware

Semantic editor:
  Ollama + qwen3:4b

Semantic editor low-end:
  Ollama + qwen3:1.7b

Rules always on:
  local vocabulary, ASR confusions, correction commands, app style rules
```

## Why This Stack

### ASR Default: WhisperKit

WhisperKit is the best first ASR integration for this product because it is Swift-native, Apple-focused, and designed for on-device transcription. The Argmax SDK includes WhisperKit as a speech-to-text framework, supports Swift Package Manager integration, and recommends `large-v3-v20240930_turbo` on macOS for maximum speed and accuracy. It also supports microphone streaming from its CLI.

The WhisperKit paper reports on-device real-time ASR with 0.46 second latency and 2.2% WER in its benchmark setup. That is directly aligned with our “text appears within one second after release” goal.

Recommended model tiers:

```text
High quality / default on modern Apple Silicon:
  large-v3-v20240930_turbo

Balanced download / lower memory:
  large-v3-v20240930_626MB

Debug / low-end:
  base.en or tiny.en
```

### ASR Fallback: whisper.cpp

`whisper.cpp` remains valuable because it is mature, portable, and has broad platform support. It is optimized for Apple Silicon through ARM NEON, Accelerate, Metal, and Core ML, and supports quantized models. It is also easy to ship as a bundled binary or sidecar dependency.

Use it when:

- WhisperKit cannot be embedded cleanly.
- We need a command-line backend quickly.
- The user is on older macOS or unusual hardware.
- We want a cross-platform bridge later.

Recommended fallback tiers:

```text
High quality:
  large-v3-turbo

Balanced:
  small.en

Fast/debug:
  base.en or tiny.en
```

### Not MVP Default: NVIDIA Parakeet / Nemotron Speech

NVIDIA Parakeet-TDT-0.6B-v3 is strong on accuracy and multilingual support. The model card reports automatic punctuation/capitalization, word and segment timestamps, 25 languages, and 6.34% average WER on the Hugging Face Open ASR Leaderboard. However, the official deployment target is NVIDIA/NeMo/Linux, not native macOS Apple Silicon.

Recent research identifies NVIDIA Nemotron Speech Streaming as a strong real-time English streaming candidate on CPU after ONNX quantization, with an int4 configuration around 0.67 GB, 8.20% average streaming WER, and 0.56 seconds algorithmic latency. That makes it an R&D candidate, not the fastest MVP path.

Use Parakeet/Nemotron later if:

- A clean ONNX Runtime or Core ML path is available.
- We need true streaming transducer behavior better than Whisper chunking.
- Benchmarks on target Macs beat WhisperKit end-to-end latency and vocabulary accuracy.

### Semantic Editor Default: Qwen3 4B

Use Qwen3 4B as the default local semantic editor through Ollama.

Reasons:

- Good size/quality tradeoff for Apple Silicon.
- Ollama lists `qwen3:4b` at about 2.5 GB with a 256K context window.
- Qwen’s 4B Instruct 2507 model is Apache-2.0, non-thinking only, and explicitly does not emit `<think>` blocks.
- Qwen reports strong gains in instruction following, writing quality, multilingual ability, and long-context understanding.

For our product, the editor prompt should stay short and deterministic:

```text
temperature: 0
top_p: 0.1
num_predict: 256-512
context: keep under 4K unless needed
```

### Semantic Editor Low-End: Qwen3 1.7B

Use Qwen3 1.7B for low-end Macs or battery-sensitive mode. Ollama lists `qwen3:1.7b` at about 1.4 GB with a 40K context window.

This should be enough for:

- punctuation
- filler removal
- short corrections
- simple list formatting
- vocabulary-preserving rewrite

It may be weaker for:

- complex email tone conversion
- app-specific rewriting
- ambiguous correction resolution

### Semantic Backup: Gemma 3 4B

Gemma 3 4B is a good backup model if Qwen underperforms on tone or user preference. Ollama lists `gemma3:4b` at about 3.3 GB with a 128K context window, and the model family supports many languages.

Use it as an A/B comparison, not as default.

## Product Modes

Hide all this from normal users. Expose only simple product modes:

```text
Fast:
  smaller ASR/editor models, lowest latency

Balanced:
  default for most users

Best accuracy:
  larger ASR/editor models, higher memory use
```

Internal mapping:

```text
Fast:
  ASR: WhisperKit base.en or whisper.cpp base.en
  Editor: qwen3:1.7b or rule editor
  Hardware target: base M1 / 8-16 GB

Balanced:
  ASR: WhisperKit large-v3-v20240930_626MB
  Editor: qwen3:4b
  Hardware target: M1 Pro / M1 Max / 16 GB+

Best accuracy:
  ASR: WhisperKit large-v3-v20240930_turbo
  Editor: qwen3:4b, optionally Gemma 3 4B A/B
  Hardware target: M1 Max / 32 GB+ or newer
```

## Benchmark Plan

Before locking defaults, benchmark on target Macs:

```text
ASR:
  first_partial_ms
  first_stable_segment_ms
  final_decode_ms
  raw WER
  vocabulary spelling accuracy

Editor:
  prompt_eval_ms
  generation_ms
  correction accuracy
  list formatting accuracy
  hallucination rate

End-to-end:
  key_release_to_insert_ms
  memory footprint
  cold start time
  warm path latency
```

Benchmark matrix:

```text
Required:
  M1 Max, 32 GB

Strongly recommended:
  base M1, 8 or 16 GB
  M1 Pro, 16 GB
  M2/M3/M4 representative machines
```

Acceptance threshold:

```text
P50 key-release-to-insert < 600 ms
P95 key-release-to-insert < 1000 ms
No cloud calls
No non-loopback model endpoints
```

## Sources

- Argmax Open-Source SDK / WhisperKit: https://github.com/argmaxinc/argmax-oss-swift
- WhisperKit paper: https://arxiv.org/abs/2507.10860
- whisper.cpp: https://github.com/ggml-org/whisper.cpp
- NVIDIA Parakeet-TDT-0.6B-v3 model card: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- On-device streaming ASR / Nemotron Speech Streaming paper: https://arxiv.org/abs/2604.14493
- Qwen3 4B Instruct model card: https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507
- Ollama Qwen3 library: https://ollama.com/library/qwen3
- Ollama Gemma3 library: https://ollama.com/library/gemma3
