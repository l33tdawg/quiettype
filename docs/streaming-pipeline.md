# Streaming Pipeline

Status: intended implementation shape for QuietType MVP.

QuietType should feel like a real-time speech compiler, not a batch transcription tool. The first implementation can use a command-backed `whisper.cpp` ASR process, but the rest of the architecture should already behave like a streaming pipeline so it can move cleanly to native WhisperKit later.

## Pipeline

```text
Microphone frames
  -> rolling audio buffer
  -> 1-second rolling WAV chunks
  -> command ASR backend initially
  -> partial ASR transcript
  -> stable prefix detector
  -> vocabulary and correction layer
  -> semantic editor
  -> rolling polished buffer
  -> final tail resolver on stop
  -> insertion
```

The user-facing flow remains push-to-talk:

```text
Press hotkey
  -> capture starts
  -> partial text becomes available while speaking
  -> stable text is cleaned while speaking
  -> release hotkey
  -> only the unstable tail is finalized
  -> polished text is inserted
```

## Microphone Frames

Audio capture should start immediately when the hotkey is pressed. `AVAudioEngine` should deliver small microphone frames into a session-scoped rolling buffer. Capture should normalize the audio into the ASR backend's preferred format, typically mono 16 kHz PCM, without leaking backend-specific conversion details into hotkey handling or UI state.

Raw audio should be treated as transient session data. Do not persist it by default.

## Rolling WAV Chunks

For the initial command-backed path, QuietType should write 1-second rolling WAV chunks from the microphone buffer and pass those chunks to the local ASR command.

The chunker should keep a small overlap between chunks so words at chunk boundaries are not lost. The ASR layer can decode the newest rolling window, compare it with prior results, and emit partial transcript updates. This is not true native streaming, but it gives the rest of the product a streaming-shaped interface before the native backend lands.

Initial command-backed behavior:

```text
Every ~1 second:
  write latest rolling WAV window
  run or feed local whisper.cpp backend
  parse transcript text
  update partial transcript
  mark stable prefix where repeated decodes agree
```

If process startup or model loading is too slow, move from one-command-per-chunk to a persistent local process or native binding while keeping the same ASR session contract.

## Partial ASR

Partial ASR is the best current transcript for the active dictation session. It may change as more audio arrives, especially near the end of the current speech tail.

Partial output should be used for:

- early UI status
- stable-prefix detection
- incremental correction handling
- incremental semantic editing

Partial output should not be inserted directly into the target app. Insertion should happen only after finalization, unless a later explicit live-insertion mode is designed.

## Stable Prefix

The stable prefix is the portion of the transcript that is unlikely to change. A simple initial detector can compare consecutive partial ASR results and mark the longest shared prefix as stable, with word-boundary cleanup and a short hold period before promotion.

Example:

```text
Partial 1: tell najwa i reviewed the second article and it looks
Partial 2: tell najwa i reviewed the second article and it looks good but
Stable:   tell najwa i reviewed the second article and it looks
Tail:     good but
```

Only stable text should be sent to the semantic editor for durable polishing. The unstable tail should remain cheap to revise.

## Semantic Editor

The semantic editor receives stable transcript spans and produces a rolling polished buffer. It should preserve meaning, apply user vocabulary and correction preferences, clean fillers and false starts, add punctuation, and apply app-aware formatting.

The editor should not regenerate the full transcript on every update. It should process newly stable spans, update a small amount of surrounding context when needed, and keep a mergeable polished buffer.

Inputs should stay small:

```text
stable span
nearby polished context
app profile
local vocabulary and correction hints
```

This keeps local editor latency low and prevents late-session dictation from becoming slower as the transcript grows.

## Final Tail On Stop

When the user releases the hotkey, capture stops and the ASR backend receives the remaining audio tail. QuietType should finalize only the unstable tail, then merge it into the already-polished buffer.

Release-time work should be limited to:

```text
flush final audio frames
decode final unstable tail
resolve tail corrections
run semantic editor on tail plus small context
merge with rolling polished buffer
insert final text
```

This is the core latency strategy. Most of the text was already recognized and edited while the user was speaking, so release only resolves the part that genuinely could not be trusted yet.

## Initial Dictation Cap

The MVP should enforce a 60-second maximum dictation duration per push-to-talk session.

Reasons:

- bounds memory and temporary audio growth
- keeps command-backed ASR practical during early development
- prevents runaway capture if a key state is missed
- keeps semantic editor prompts small and predictable
- gives benchmarking a clear latency and quality envelope

When the cap is reached, QuietType should stop capture, finalize the current tail, and insert or present the result according to the normal completion path.

This cap is an initial product constraint, not a permanent architecture limit. Native streaming and stronger incremental editing can support longer sessions later.

## Why Streaming Improves Perceived Latency

Whole-file transcription makes the user wait after speaking because ASR and semantic editing both start at the end. That creates a visible pause exactly when the user expects the text to appear.

Streaming shifts most work into the time while the user is already talking:

```text
While speaking:
  decode chunks
  identify stable prefixes
  apply corrections
  polish stable spans

After release:
  finish only the unstable tail
  merge
  insert
```

The total compute may be similar, but the perceived latency is much lower because release-time work is smaller and bounded.

## Transition To WhisperKit

The initial backend can use command `whisper.cpp` because it is easy to discover locally and test through a narrow adapter. The product should still expose an ASR session API shaped for streaming:

```text
ASRSession.start(audioFormat, partialHandler)
ASRSession.accept(buffer)
ASRSession.finish() async throws -> Transcript
ASRSession.cancel()
```

With `whisper.cpp`, `accept(buffer)` can append frames to the rolling buffer and schedule 1-second WAV chunk decodes. With native WhisperKit, the same method should feed audio directly into the Swift-native ASR engine and receive lower-latency partials without temporary WAV files.

Migration path:

```text
Phase 1:
  command whisper.cpp over rolling WAV chunks

Phase 2:
  persistent whisper.cpp process or native binding if command startup is too slow

Phase 3:
  native WhisperKit backend using the same ASRSession contract

Phase 4:
  tune stable-prefix and final-tail behavior using native timestamps and confidence data
```

The pipeline above should not depend on command execution, WAV files, or `whisper.cpp`-specific output. Those are adapter details. Stable prefixes, semantic editing, final-tail resolution, and insertion should remain backend-independent.
