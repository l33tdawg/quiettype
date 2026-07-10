# Offline voice-flow evaluation

QuietType's speech benchmark and runtime flow metrics are local development
tools. They have no cloud transport, API-key support, hosted telemetry, or
non-loopback endpoint option.

The design borrows useful realtime speech principles—incremental processing,
adaptive speech detection, short context hints, and separate first-run and
steady-state latency measurement—without using a hosted speech service.

## Trust boundary

- Audio is read from a local WAV file and sent only to QuietType's native
  WhisperKit service at `127.0.0.1`.
- Expected and recognized text exist in process memory only while a case runs.
- Reports contain timings, WER, required-term accuracy, counts, and neutral case
  IDs. They exclude expected text, hypotheses, transcript text, and audio paths.
- Runtime flow logging is off by default and writes only content-free fields to
  an owner-readable local file when explicitly enabled.
- There is no cloud fallback. If the loopback engine is unavailable, a run
  fails locally.

Do not commit personal recordings or their reference transcripts. The
`benchmarks/private/` and `benchmark-results/` directories are ignored by Git.

## Capture the guided private suite

Launch the local capture app:

```bash
scripts/run-voice-capture.sh
```

macOS asks for microphone access the first time because the recorder has its
own stable local bundle identity and microphone usage description. The app
guides you through 25 purpose-written prompts covering clean speech, technical
terms, corrections, pauses, delivery variation, background noise, numbers, and
long form dictation. Existing recordings are detected, so the suite can be
completed over multiple sessions or individual prompts can be recorded again.

Recordings and their manifest are stored outside the repository at:

```text
~/Library/Application Support/QuietType/Benchmarks/
```

The directories use owner-only `0700` permissions; WAV files and the manifest
use `0600`. The generated manifest creates paired baseline and short-keyword
cases for vocabulary prompts while reusing the exact same local recording.

## Build a private suite manually

Copy `benchmarks/voice-flow.example.json` to
`benchmarks/private/voice-flow.json`, then add local WAV recordings and edit the
case metadata. Audio paths are resolved relative to the manifest.

Each case has:

- `id`: a neutral, non-sensitive identifier.
- `audioPath`: a local WAV path.
- `expectedText`: the exact local reference transcription.
- `durationSeconds`: recording duration, used for real-time factor.
- `requiredTerms`: spellings whose recognition accuracy should be tracked.
- `promptKeywords`: optional short vocabulary hints for the local model.

Keep `promptKeywords` short. To measure whether hinting genuinely helps, create
paired cases for the same audio: one with an empty array and one with only the
terms being evaluated. Never use the full reference transcript as the prompt.

Include representative samples for:

- first use after install or upgrade and subsequent warm runs;
- laptop and external microphones;
- short commands and three-to-five-minute dictations;
- natural pauses, restarts, and self-corrections;
- quiet speech, fans, keyboard noise, cafés, and music leakage;
- accents and speaking rates seen among real users;
- product names, acronyms, identifiers, numbers, and punctuation instructions.

## Run it

Start QuietType so its native local speech engine is ready, then run:

```bash
scripts/benchmark-voice-flow.sh \
  "$HOME/Library/Application Support/QuietType/Benchmarks/voice-flow.json" \
  --iterations 5 \
  --output benchmark-results/baseline.json
```

The ordered samples retain iteration 1 separately from the steady-state median.
For a cold-start measurement, fully stop QuietType and its speech helper, launch
the build under test, and begin the suite immediately. Keep a consistent case
order when comparing builds because model warmup affects the earliest sample.

The report file is created with owner-only permissions (`0600`). A non-zero exit
means the local engine or at least one case failed; successful measurements are
still written so failures can be diagnosed without rerunning the entire suite.

## Compare a candidate

Run the same manifest, hardware, microphone recordings, case order, and engine
startup state for the candidate build:

```bash
scripts/benchmark-voice-flow.sh \
  "$HOME/Library/Application Support/QuietType/Benchmarks/voice-flow.json" \
  --iterations 5 \
  --output benchmark-results/candidate.json
```

Then compare the two content-free reports:

```bash
scripts/benchmark-voice-flow.sh compare \
  benchmark-results/baseline.json \
  benchmark-results/candidate.json \
  --output benchmark-results/comparison.json
```

The comparator exits non-zero if a case is missing, has insufficient data,
changes iteration count, duration, or reference shape, adds failures, regresses
WER by more than 0.5 percentage points, reduces required-term accuracy, or makes
first-run, median, or p95 latency more than 5% slower. It labels a case improved
when accuracy improves beyond tolerance or latency drops by at least 15%. The
comparison report contains neutral IDs and numeric deltas only.

## Opt-in runtime flow metrics

The app can record content-free lifecycle timings from real dictation sessions.
Enable the hidden development switch:

```bash
defaults write local.quiettype.mac quiettype.voiceFlowMetricsLoggingEnabled -bool true
```

Restart QuietType. Records are appended locally to:

```text
~/Library/Logs/QuietType/voice-flow-metrics.jsonl
```

The file records duration, speech/pause measurements, streaming chunk and queue
counts, time to first partial, preview revision count, release-to-final and
release-to-completion latency, final word count, and outcome. It does not record
audio, transcript text, filenames, target-app identity, document context, SAGE
memory, or prompts.

Disable the switch when a measurement session is complete:

```bash
defaults delete local.quiettype.mac quiettype.voiceFlowMetricsLoggingEnabled
```

## Change gates

Use the same corpus, hardware, microphone placement, and app state when
comparing builds. A voice-path optimization should ship only when it:

- does not regress aggregate WER or required-term accuracy;
- improves first-run or release-to-completion latency for its intended case;
- does not increase preview churn or streaming queue depth materially;
- preserves quiet speech and words adjacent to natural pauses;
- does not increase false inserts from noise-only recordings;
- keeps all audio, text, prompts, and measurements on the Mac.

These measurements establish the baseline for safely tuning adaptive VAD,
pre-roll, hangover, chunk timing, prompt biasing, and final-tail decoding. The
current runtime tracker is diagnostic only: it does not discard audio or end a
dictation automatically.

## Design references

These hosted-service documents are used as design research only; QuietType does
not call the APIs they describe:

- [Introducing GPT-Live](https://openai.com/index/introducing-gpt-live/) for
  continuous speech processing, responsiveness, and natural conversational
  timing as product principles.
- [Realtime VAD](https://developers.openai.com/api/docs/guides/realtime-vad) for
  threshold, prefix-padding, and silence-duration concepts that map to
  QuietType's local adaptive floor, future pre-roll, and hangover tuning.
- [Realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription)
  for incremental-versus-final transcript handling and compact prompt hints.
