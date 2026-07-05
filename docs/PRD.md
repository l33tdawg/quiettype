# PRD: Offline Privacy-First Typeless-Style Dictation Assistant

**Project name:** QuietType  
**Former codename:** LocalType / PrivateDictate  
**Status:** Draft v0.1  
**Owner:** TBD  
**Target platform for MVP:** macOS Apple Silicon  
**Core principle:** Cloud-quality semantic dictation with zero cloud processing.

## 1. Executive Summary

Build an offline, privacy-first dictation assistant that delivers the same “magical” user experience as cloud-based tools like Typeless: the user speaks naturally, including pauses, corrections, fillers, and rough phrasing, and the system inserts polished text into the active application almost instantly.

The product must not behave like a literal transcription tool. It should understand spoken intent and produce usable written output: punctuation, paragraphing, list formatting, correction handling, domain-specific vocabulary, and app-specific tone.

Unlike cloud-first products that use hosted AI providers, this product must run entirely on the user’s device using local speech recognition, local semantic editing, and local personalisation. No audio, transcript, app context, or user dictionary should leave the machine.

The core product is a local streaming speech compiler:

```text
Natural speech
  -> streaming ASR
  -> user-specific correction layer
  -> local semantic editor
  -> app-aware formatted text
  -> instant insertion into active application
```

The first version focuses on macOS because it provides global hotkeys, microphone APIs, Accessibility APIs, local model performance, and reliable text insertion.

## 2. Problem Statement

Current dictation tools are either literal transcription tools, which preserve awkward speech, missing punctuation, false starts, repetition, and poor formatting, or cloud AI dictation tools, which produce better output but send audio, text context, and user data to remote servers.

The target user wants cloud-quality dictation with a stronger privacy model:

- No cloud processing.
- No audio upload.
- No server-side retention.
- No third-party AI APIs.
- Local vocabulary and correction memory.
- Works across normal desktop apps.
- Feels instant.

The hard part is converting messy, natural spoken language into polished written language with near-zero perceived delay.

## 3. Goals

### 3.1 Product Goals

- Press a hotkey, speak naturally, release the hotkey, and insert polished text.
- Work across Slack, Gmail/webmail, Notes, Cursor, VS Code, browsers, documents, and messaging apps.
- Produce non-literal, semantically cleaned text.
- Remove fillers, false starts, and repeated phrases.
- Detect corrections such as “sorry”, “actually”, and “no, make that…”.
- Automatically punctuate and paragraph.
- Convert spoken enumerations into bullet or numbered lists when appropriate.
- Preserve technical terms, names, and acronyms.
- Adapt style based on active app.
- Run entirely offline after model installation.
- Keep all user data local and encrypted.

### 3.2 Technical Goals

- Use streaming speech recognition, not post-hoc whole-file transcription.
- Process stable transcript segments while the user is still speaking.
- Resolve only the final unstable tail after key release.
- Keep local models warm and resident.
- Maintain a user-specific local dictation profile.
- Support onboarding-based personalisation.
- Support correction learning over time.
- Provide deterministic, conservative editing.
- Avoid hallucinating content not spoken by the user.

### 3.3 Privacy Goals

- Never send audio, transcript text, app context, or user dictionary data to a server.
- Never call OpenAI, Gemini, Anthropic, or any remote LLM provider.
- Store personal vocabulary, correction history, and style preferences locally.
- Encrypt all local profile data.
- Allow the user to inspect, export, and delete local data.
- Disable all network access during normal operation.

## 4. Non-Goals

The MVP does not need mobile support, every operating system, local ASR training, local LLM fine-tuning, cloud sync, team collaboration, every language, medical/legal-grade guarantees, a full document editor, or arbitrary voice commands beyond dictation and lightweight formatting intent.

## 5. Target User

Initial users are technical and privacy-sensitive users who dictate emails, Slack messages, notes, and documents. They may be developers, security researchers, engineers, and founders with domain-specific terms.

Example vocabulary:

```text
SAGE
CometBFT
Ollama
Utimaco
CSe100
HSM
Ed25519
Verichains
LevelUpCTF
AutoResearch
Karpathy
val_bpb
Raptor
BinSleuth
```

## 6. Core User Experience

Primary flow:

```text
User presses global hotkey
  -> app starts listening immediately
  -> user speaks naturally
  -> system streams audio to local ASR
  -> stable transcript is cleaned incrementally
  -> user releases hotkey
  -> system resolves final phrase
  -> polished text is inserted into active app
```

Example speech:

```text
tell najwa i reviewed the second article and it looks good but the opening needs to be tighter and maybe make the examples more concrete
```

Slack output:

```text
I reviewed the second article and it looks good, but the opening needs to be tighter. Maybe make the examples more concrete.
```

Notes output:

```text
Feedback for Najwa:
- The second article looks good.
- The opening needs to be tighter.
- The examples should be more concrete.
```

Email output:

```text
Hi Najwa,

I reviewed the second article and it looks good overall. I think the opening needs to be tighter, and the examples could be more concrete.
```

## 7. Key Product Requirements

### 7.1 Push-to-Talk Dictation

- User presses and holds a configurable global hotkey.
- Audio capture begins within 100 ms.
- User releases to complete dictation.
- Text insertion begins within target latency after release.
- User can cancel before insertion.

Later modes may include toggle-to-dictate, VAD mode, and wake word mode.

### 7.2 Streaming ASR

Use a local streaming ASR engine with chunked audio, partial transcripts, stable segments, timestamps/confidence where available, and local vocabulary hints where supported.

Candidate engines:

- NVIDIA Parakeet / Nemotron streaming ASR variants.
- Whisper.cpp as fallback or compatibility mode.
- Apple SpeechAnalyzer as a macOS-specific optional backend.

Backend interface:

```text
ASRBackend
  - start_session(profile, vocabulary)
  - push_audio(frame)
  - get_partial()
  - get_stable_segments()
  - finish()
```

### 7.3 Semantic Editing

Use a local LLM or specialised local model to transform raw transcript into polished written output. It must run locally, support low-latency inference, stay warm, disable reasoning mode, use deterministic settings, return only final text, preserve meaning, understand corrections, format lists, and adapt to app profile.

Candidate starting models:

- Qwen 3.5 2B or similar for speed.
- Qwen 3.5 4B or similar for quality.
- Later: fine-tuned 1B–4B dictation editor model.

The editor should receive incremental stable segments and maintain a rolling polished buffer instead of waiting for the final full transcript.

### 7.4 Incremental Processing

Required flow:

```text
Partial ASR transcript
  -> stable-prefix detector
  -> correction map
  -> incremental semantic editor
  -> rolling polished buffer
  -> final tail resolver
```

Final release only processes the unstable tail and merges it into the already-polished buffer.

### 7.5 App Context Awareness

MVP app profiles:

```text
Slack / Teams / messaging: concise, direct, conversational
Email: polished paragraph format, greeting/signoff inference disabled by default
Notes: structured, bullets when appropriate, headings when useful
Code editor: preserve technical terms, symbols, and identifiers
Browser text field: default balanced style
```

Context collection should use macOS Accessibility APIs where possible and may include active app, focused text field role, selected text, nearby text, window title, and user-configured app style profile. Screenshots are not MVP unless unavoidable.

### 7.6 Text Insertion

Preferred insertion order:

1. Accessibility API direct insertion.
2. Clipboard paste fallback.
3. Simulated keystrokes fallback.

Requirements include preserving clipboard contents, avoiding password fields and secure input mode, supporting app exclusions, and showing a visible or audible error when insertion fails.

## 8. Onboarding and Personalisation

Onboarding target duration is 3–5 minutes:

```text
1. Microphone check
2. Voice/accent calibration
3. Messy dictation examples
4. Personal vocabulary collection
5. Formatting preference selection
6. Optional import of local names/projects
7. Local benchmark
8. Profile generation
```

Microphone check records input device, gain, noise floor, clipping, SNR, and recommended mic settings.

Voice calibration estimates speaking speed, pause behaviour, common phoneme confusions, endpointing, VAD sensitivity, and microphone/room profile.

Messy dictation examples teach correction handling, list detection, punctuation, and pause style.

Personal vocabulary supports manual entry, onboarding script readings, contacts/calendar names, user project lists, optional local document scan, and correction history. Example vocabulary item:

```json
{
  "term": "CometBFT",
  "spoken_forms": ["comet bee eff tee", "comet b f t"],
  "preferred_spelling": "CometBFT",
  "category": "technical_term",
  "confidence_boost": 0.92
}
```

Known-script comparison maps ASR errors to preferred terms, such as “ultimate go” -> “Utimaco”, “see as e one hundred” -> “CSe100”, and “ed twenty five five nineteen” -> “Ed25519”.

Formatting preferences cover bullets, message tone, and technical term cleanup strictness.

## 9. Local Data Model

Use encrypted local storage: SQLite for structured records, local JSON for runtime config, and Keychain-backed encryption key on macOS.

Tables:

```text
profiles(id, created_at, updated_at, language, speech_rate_wpm, pause_threshold_ms,
  vad_sensitivity, mic_noise_floor_db, active_asr_backend, active_editor_model)

vocabulary(id, term, preferred_spelling, spoken_forms_json, category, boost, source,
  created_at, last_used_at)

asr_confusions(id, heard, corrected, context_terms_json, confidence, source,
  created_at, last_used_at)

corrections(id, raw_text, inserted_text, user_corrected_text, app_context, accepted, timestamp)

style_profiles(id, app_name, tone, formatting_rules_json, preserve_terms, prefer_bullets,
  created_at, updated_at)

dictation_sessions(id, started_at, duration_ms, app_name, raw_transcript, final_text,
  latency_ms, user_edited_after_insert)
```

Users must be able to view/delete vocabulary, delete correction history, reset voice profile, export profile, delete all local data, disable learning, disable context collection, and exclude apps.

## 10. Runtime Architecture

```text
Global hotkey
  -> Audio capture (AVAudioEngine)
  -> Streaming ASR (local backend)
  -> Stable prefix detector
  -> User correction and vocabulary map
  -> Local semantic editor via Ollama
  -> Final tail resolver
  -> Text insertion (AX / clipboard)
```

Main components: Audio Capture Service, ASR Service, Stable Prefix Detector, Correction Engine, Semantic Editor, Context Collector, and Insertion Service.

## 11. Latency Requirements

Perceived target: text appears within 1 second of key release. Stretch target: 300–700 ms on supported Apple Silicon machines.

Budget:

```text
Final audio frame flush:        10-40 ms
Final ASR decode:               80-200 ms
Final semantic tail resolve:    100-350 ms
Diff/merge formatting:          20-80 ms
Text insertion:                 10-40 ms
Total target:                   220-710 ms
Maximum acceptable:             <1000 ms
```

Required optimisations: warm ASR/editor models, preloaded profiles, stable-segment processing during speech, final-tail-only release processing, small local models, no cold Ollama loads, short prompts, no chain-of-thought, and no full transcript regeneration at release.

## 12. Quality Requirements

Handle fillers, repetitions, false starts, corrections, replacements, lists, technical terms, names, acronyms, app-specific tone, punctuation, and paragraphing.

The editor must not add facts, invent names, expand acronyms incorrectly, rewrite technical content too aggressively, turn tentative language into certainty, change meaning, or insert greetings/signoffs unless clearly appropriate or configured.

Expected examples:

```text
need to send najwa a note saying the article is good but maybe the intro is too long and the architecture section needs one concrete example
```

```text
The article is good, but the intro may be too long. The architecture section also needs one concrete example.
```

```text
for the shopping list get milk eggs bread bananas actually no bananas apples and greek yogurt
```

```text
- Milk
- Eggs
- Bread
- Apples
- Greek yogurt
```

```text
the sage benchmark needs to rerun the comet bft latency numbers actually say comet bft consensus latency numbers
```

```text
The SAGE benchmark needs to rerun the CometBFT consensus latency numbers.
```

## 13. Evaluation Metrics

Latency metrics:

```text
time_to_audio_start_ms
first_partial_asr_ms
first_stable_segment_ms
key_release_to_insert_ms
total_session_duration_ms
semantic_editor_latency_ms
insertion_latency_ms
```

Accuracy metrics include raw ASR WER, semantic edit accuracy, correction handling accuracy, list formatting accuracy, vocabulary spelling accuracy, user edit distance after insertion, acceptance rate, and hallucination rate.

MVP targets:

- 90%+ correct spelling for user vocabulary after onboarding.
- 85%+ correct handling of simple corrections.
- 80%+ correct list formatting for common shopping/task examples.
- P95 hallucination rate near zero on constrained test set.

UX metrics remain local and opt-in only.

## 14. Security and Privacy Requirements

The product must operate fully offline after installation: no runtime network calls, cloud ASR, cloud LLM, remote analytics by default, audio upload, transcript upload, app context upload, or third-party API keys.

Strict offline mode disables outbound network calls, requires manual model-download approval, disables automatic update checks, sends no telemetry, and clearly shows offline status.

The app must avoid password fields, secure input fields, banking/2FA fields where detectable, excluded apps, and secure input mode.

Encrypt vocabulary database, correction history, dictation history if retained, style profiles, imported names/projects, and onboarding audio if stored. Delete onboarding audio after profile generation by default unless the user opts in.

## 15. Model Strategy

MVP uses existing local models:

- ASR: best available local streaming backend with Whisper.cpp fallback.
- Semantic editor: small Ollama-compatible instruct model, deterministic settings, no reasoning, warm model, concise prompts.

Later versions may develop a specialised local dictation editor model trained on synthetic examples, human-recorded development data, opt-in local correction history, domain vocabulary packs, and distillation from larger models using non-sensitive development data. User data must not be trained on in the cloud.

Optional later local LoRA training:

```text
Correction history
  -> before/after examples
  -> local LoRA training
  -> personal editor adapter
```

## 16. User Correction Loop

After insertion, the app may observe user edits when allowed and store raw transcript, inserted text, corrected text, app context, and timestamp locally.

Explicit commands:

```text
Always spell that as CometBFT.
When I say all llama, write Ollama.
Use bullets when I list more than three things.
Do not make Slack messages too formal.
```

Correction UI includes recent dictations, raw transcript, inserted output, user correction, “Save as preference”, “Forget this”, and “Add term to dictionary”.

## 17. MVP Scope

Must-have:

- macOS desktop app.
- Global push-to-talk hotkey.
- Local microphone capture.
- Local streaming ASR.
- Local Ollama semantic editor.
- Local encrypted profile database.
- Onboarding flow.
- Personal vocabulary.
- Known-script calibration.
- App detection.
- Basic app style profiles.
- Text insertion into active app.
- Clipboard fallback.
- Strict offline mode.
- Local correction map.
- Latency logging.
- Basic settings UI.

Should-have:

- User-editable vocabulary list.
- App exclusion list.
- Recent dictation review.
- Correction learning.
- Import names from contacts/calendar with explicit permission.
- Multiple ASR backend support.
- Model warmup status.
- Debug mode for local benchmarking.

Nice-to-have:

- Local LoRA training.
- Team vocabulary packs.
- Voice command mode.
- Multi-language support.
- Windows support.
- iOS companion app.
- Local-only sync.
- Custom domain packs.

## 18. Technical Implementation Plan

Phase 1: feasibility prototype with macOS menu bar app, push-to-talk, audio capture, local ASR integration, Ollama editor call, and clipboard paste insertion.

Phase 2: streaming pipeline with streaming ASR session, stable-prefix detector, incremental semantic editor, rolling polished buffer, and final tail resolver.

Phase 3: onboarding profile with mic calibration, known-script reading flow, vocabulary extraction, ASR confusion mapping, style preference questions, and encrypted local profile.

Phase 4: app context and style with active app detection, basic context retrieval, app-specific profiles, secure-field detection, and excluded apps.

Phase 5: correction learning with recent dictation history, manual correction capture, explicit vocabulary update commands, correction review UI, and local preference updates.

## 19. Risks and Mitigations

- Local models too slow: stream, keep models resident, use small editor model, process stable text during speech, specialise later, and provide hardware minimums.
- ASR quality worse than cloud: onboarding, vocabulary biasing, correction maps, domain dictionaries, backend selection, and future fine-tuning.
- LLM rewrites too aggressively: conservative prompt, low temperature, fine-tuned editor, app-specific strictness, and meaning-preservation regression tests.
- Text insertion unreliable: multiple insertion methods, app adapters, clipboard fallback, clear errors, and compatibility matrix.
- Privacy concerns around app context: local-only processing, transparent permissions, toggles, excluded apps, secure field detection, and inspectable local data.
- Onboarding too long: keep required onboarding under 3 minutes, make vocabulary optional, show immediate improvement, and allow later completion.

## 20. Open Questions

1. Which local streaming ASR backend gives the best latency/quality tradeoff on Apple Silicon?
2. Should MVP depend on Ollama, bundle its own runtime, or support both?
3. What is the minimum supported hardware?
4. Should onboarding audio be deleted by default after profile generation?
5. How much active text context should be read from the current app?
6. Should the app support preview-before-insert mode?
7. How should strict offline mode be exposed in the UI?
8. What is the first target language?
9. Should model downloads happen inside the app or be user-managed?
10. Should local correction learning be enabled by default?

## 21. Definition of Done for MVP

- Runs on macOS Apple Silicon.
- User can press a hotkey, speak, and release to insert text.
- Full path works offline.
- No cloud APIs are used.
- Produces polished text, not literal transcript.
- Handles basic corrections and lists.
- Preserves user vocabulary from onboarding.
- P95 key-release-to-insert latency is under 1 second.
- User data is stored locally and encrypted.
- User can inspect/delete local vocabulary and correction data.
- App avoids secure fields and excluded applications.
- Local benchmark suite exists for latency and output quality.

## 22. Product Positioning

Do not describe the product as an offline Whisper wrapper.

Describe it as:

```text
A private local AI dictation assistant that turns natural speech into polished writing instantly, without sending your voice or text to the cloud.
```

Differentiator:

```text
Cloud-quality semantic dictation with local-only privacy.
```

Technical differentiator:

```text
Streaming ASR + local personalisation + incremental semantic editing + app-aware insertion.
```

User-facing promise:

```text
Speak freely. Transcribe locally. Nothing leaves your Mac.
```

## 23. Required SAGE Memory Integration

### 23.1 Overview

QuietType should use SAGE as its governed memory store for long-lived user preferences, vocabulary, correction patterns, transcript review notes, and app-specific writing profiles. SAGE is the required memory substrate for the product experience, not an optional upsell or secondary backend.

At startup, check for SAGE at:

```text
/Applications/SAGE
```

or the final agreed macOS application path.

If SAGE is detected, the app should:

```text
1. Register itself as a local MCP agent.
2. Connect to the local SAGE node through the documented SAGE SDK/API.
3. Store eligible dictation memories in SAGE instead of, or in addition to, the local SQLite profile database.
4. Retrieve relevant memories during dictation to improve vocabulary, formatting, and style.
5. Preserve offline/privacy-first guarantees unless the user explicitly enables SAGE network participation.
```

If SAGE is not detected, prompt the user to install it or use the bundled SAGE GUI when present. QuietType should guide the user through SAGE install, launch, vault unlock, setup completion, and `quiettype-agent` registration before dictation is enabled.

### 23.2 Detection Flow

```text
Check /Applications/SAGE
  -> if present:
       validate SAGE app/node availability
       check local SDK/API endpoint
       register dictation assistant as MCP agent
       enable SAGE memory backend
  -> if not present:
       check bundled SAGE GUI in QuietType.app/Contents/Resources/SAGE.app
       if bundled, start bundled SAGE and guide setup
       otherwise show SAGE install prompt
       keep dictation blocked until SAGE is ready
```

### 23.3 User Experience

If SAGE is installed:

```text
SAGE detected. QuietType will use local SAGE governed memory for vocabulary, corrections and writing preferences.
[Register quiettype-agent] [Learn About SAGE]
```

If SAGE is not installed:

```text
SAGE was not found on this Mac.

This app can use SAGE as a governed private memory store for your vocabulary, corrections and writing preferences.

You can install SAGE now. QuietType will start after SAGE is installed, unlocked, and ready.

[Install SAGE] [Learn About SAGE]
```

Settings should explain SAGE status, installed/bundled detection, vault unlock requirements, and `quiettype-agent` registration state.

### 23.4 MCP Agent Registration

When SAGE is available, register as an MCP agent using the documented SAGE SDK and MCP integration pattern.

Agent identity:

```json
{
  "agent_name": "quiettype-agent",
  "agent_type": "local_dictation_assistant",
  "capabilities": [
    "dictation_profile_memory",
    "vocabulary_memory",
    "correction_memory",
    "style_profile_memory",
    "app_contextual_recall"
  ],
  "privacy_mode": "local_first",
  "network_policy": "user_controlled"
}
```

The dictation assistant must not invent a custom memory protocol if SAGE already provides the required SDK interfaces.

### 23.5 Memory Backend Selection

Supported backends:

```text
Default backend:
  Encrypted local SQLite

Optional backend:
  SAGE governed memory store
```

Runtime selection:

```text
If SAGE enabled:
    write memory events to SAGE
    retrieve relevant memory from SAGE
    optionally keep local cache for latency
Else:
    use encrypted SQLite only
```

Thin abstraction:

```text
MemoryStore
  - put(memory)
  - search(query, filters)
  - update(memory_id, patch)
  - delete(memory_id)
  - explain(memory_id)
```

Implementations:

```text
SQLiteMemoryStore
SageMemoryStore
HybridMemoryStore
```

### 23.6 What Should Be Stored in SAGE

Eligible memories include personal vocabulary, preferred spellings, ASR confusion mappings, app-specific style preferences, correction history summaries, formatting preferences, user-approved domain terms, repeated user edits, and per-app tone rules.

Example vocabulary memory:

```json
{
  "type": "dictation.vocabulary",
  "term": "CometBFT",
  "spoken_forms": ["comet bee eff tee", "comet b f t"],
  "preferred_spelling": "CometBFT",
  "contexts": ["SAGE", "consensus", "blockchain", "benchmark"],
  "source": "user_correction",
  "confidence": 0.96,
  "privacy": "local",
  "created_by": "QuietType"
}
```

Example correction memory:

```json
{
  "type": "dictation.correction",
  "raw": "all llama",
  "corrected": "Ollama",
  "contexts": ["local model", "LLM", "offline dictation"],
  "source": "explicit_user_instruction",
  "confidence": 0.94,
  "created_by": "QuietType"
}
```

Example style memory:

```json
{
  "type": "dictation.style_profile",
  "app": "Slack",
  "preference": "concise_direct_casual",
  "rules": [
    "avoid unnecessary greetings",
    "use short paragraphs",
    "do not over-formalise technical comments"
  ],
  "source": "user_preference",
  "created_by": "QuietType"
}
```

### 23.7 What Should Not Be Stored by Default

Do not store full raw dictation sessions in SAGE by default.

Avoid storing:

```text
Raw audio
Full private transcripts
Password-field content
Sensitive app context
Long email bodies
Private document excerpts
Unreviewed background text
```

Default policy:

```text
Store preferences, not private content.
```

### 23.8 SAGE Recall During Dictation

At dictation start, retrieve relevant SAGE memories based on active app, nearby text, detected topic, recognised names, partial ASR transcript, user vocabulary, and recent corrections.

Recall must be low latency. The app may maintain a local hot cache of frequently used SAGE memories.

### 23.9 Privacy and Network Policy

Default behavior:

```text
SAGE local node only.
No external memory sync.
No public network broadcast.
No cloud fallback.
```

If SAGE is configured to participate in a broader network, ask before writing dictation memories to any networked or replicated layer.

Prompt:

```text
Your SAGE node may be connected to a network.

Should dictation memories remain local-only, or may selected memories participate in your SAGE network policy?

[Keep Dictation Memory Local Only] [Use My SAGE Network Policy]
```

Default: keep dictation memory local only.

### 23.10 Installation Prompt

If SAGE is not installed, onboarding must continue. If the user accepts installation, open the SAGE installer, download page, or v11 one-click installer and resume setup after installation. After installation, offer to migrate or mirror existing local profile data into SAGE.

### 23.11 Migration to SAGE

Prompt:

```text
SAGE is now installed.

Would you like to move your local dictation memory into SAGE?

[Move to SAGE] [Mirror to SAGE] [Keep Local Only]
```

Options:

```text
Move to SAGE:
  SAGE becomes primary memory store.
  Local SQLite keeps only cache/minimal operational data.

Mirror to SAGE:
  Local SQLite remains primary.
  Approved memories are copied to SAGE.

Keep Local Only:
  No SAGE memory writes.
```

### 23.12 Updated Architecture With SAGE

```text
Global hotkey
  -> Audio capture
  -> Streaming ASR
  -> Correction engine <-> MemoryStore abstraction
  -> Semantic editor <-> MemoryStore abstraction
  -> Text insertion

MemoryStore
  -> SQLiteMemoryStore
  -> SageMemoryStore
  -> HybridMemoryStore
```

### 23.13 Updated MVP Requirements

Add to MVP should-have:

- Detect SAGE installation at `/Applications/SAGE`.
- Prompt user to install SAGE if not present.
- Register as an MCP agent when SAGE is available.
- Use SAGE SDK/API as the required governed memory backend.
- Store vocabulary, corrections, and style preferences in SAGE.
- Retrieve relevant SAGE memories during dictation.
- Keep dictation memory local-only by default even if SAGE is networked.
- Support migration of legacy local memory into SAGE where legacy builds created local records.

The product must work in two SAGE-backed modes:

```text
Mode 1: Local SAGE governed memory
Mode 2: Hybrid operational cache + SAGE governed memory
```

### 23.14 Updated Definition of Done

- App checks for SAGE at startup.
- App blocks dictation and guides setup when SAGE is missing, locked, or not running.
- If SAGE is installed, app can register as a local MCP agent.
- User can see SAGE memory status and registration state.
- Vocabulary memories can be written to SAGE.
- Relevant SAGE memories can be retrieved during dictation.
- Dictation memories remain local-only by default.
- Legacy local memory can be migrated or mirrored into SAGE when present.

### 23.15 Strategic Rationale

SAGE gives the dictation assistant a stronger long-term memory substrate than a simple local SQLite profile: governed memory, cross-agent interoperability, durable user preference storage, auditable correction history, portable agent memory, MCP-native integration, and future multi-agent workflows.

Positioning:

```text
Works fully offline by default.
Gets governed memory when SAGE is installed.
Registers as an MCP agent.
Stores your dictation preferences as private, reusable agent memory.
```
