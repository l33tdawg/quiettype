# Local ASR Setup

QuietType is local-first. ASR setup must work without cloud speech APIs, hosted transcription, or network access during dictation.

## Recommended Path

Use two ASR paths while the product matures:

```text
Preferred native future path:
  WhisperKit

Fastest integration path now:
  whisper.cpp command backend
```

WhisperKit is the preferred long-term direction because it is Swift-native, Apple Silicon focused, and fits the macOS app architecture. It should become the primary in-process or package-managed ASR backend once the app has a stable audio pipeline and latency benchmark harness.

The fastest practical integration path is a `whisper.cpp` command backend. It can be discovered locally, called through a narrow adapter, and replaced later by WhisperKit or a persistent native backend without changing the rest of the dictation pipeline.

## Check Local Commands

Run the checker:

```bash
bash scripts/check-asr.sh
```

Or manually check the supported command names:

```bash
command -v whisper-cli
command -v main
command -v whisper
```

Common `whisper.cpp` builds now install or produce `whisper-cli`. Older builds often produced a binary named `main`. Some package managers or wrappers expose `whisper`.

QuietType should treat these as command-backed ASR candidates in this order:

```text
1. whisper-cli
2. main
3. whisper
```

## Common Local Binary Paths

The checker also looks for common executable paths:

```text
/opt/homebrew/bin/whisper-cli
/usr/local/bin/whisper-cli
~/whisper.cpp/build/bin/whisper-cli
~/whisper.cpp/main
./vendor/whisper.cpp/build/bin/whisper-cli
./third_party/whisper.cpp/build/bin/whisper-cli
./build/bin/whisper-cli
```

These are examples, not requirements. A command found through `PATH` is enough for early development.

## Model Choice on M1 and M1 Max

Start with product modes instead of exposing raw model names to users:

```text
Fast:
  base.en or tiny.en
  Best for base M1, 8 GB machines, quick smoke tests, and lowest latency.

Balanced:
  small.en
  Good default for M1 Pro / M1 Max class machines when latency still matters.

Best:
  large-v3-turbo or WhisperKit large-v3-v20240930_turbo
  Best for M1 Max with 32 GB+ unified memory, benchmark runs, and quality testing.
```

For an M1 Max, benchmark `small.en` against `large-v3-turbo` before making a default. For a base M1, default to `base.en` or `small.en` unless the user explicitly chooses best accuracy.

## Common Model Paths

For `whisper.cpp`, look for GGML model files in local paths such as:

```text
./models
./resources/Models
~/Library/Application Support/QuietType/Models
~/.cache/whisper.cpp
~/whisper.cpp/models
```

Typical filenames:

```text
ggml-tiny.en.bin
ggml-base.en.bin
ggml-small.en.bin
ggml-large-v3-turbo.bin
```

The setup checker only reports what already exists. It does not fetch models.

## Example Command Backend Shape

Exact flags can vary by `whisper.cpp` version, but a command-backed adapter should be able to form a local command like:

```bash
whisper-cli -m /path/to/ggml-small.en.bin -f /path/to/audio.wav --no-timestamps
```

Keep this adapter narrow:

- input: local audio file or captured segment
- output: transcript text
- timeout: short and explicit
- network: none
- storage: no raw audio retention by default

## Development Rule

Do not make ASR setup download or install anything implicitly. Developers should choose and install local ASR binaries and models themselves, then use `scripts/check-asr.sh` to verify what QuietType can see.
