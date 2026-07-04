# ADR 0001: Local Runtime and ASR for MVP

## Status

Accepted for MVP.

## Context

Typeless Secure is an offline, privacy-first macOS dictation assistant. The MVP must support push-to-talk dictation, local streaming speech recognition, local semantic cleanup, app-aware formatting, encrypted local profile storage, secure-field avoidance, and text insertion with a P95 key-release-to-insert latency under 1 second for typical short utterances.

The primary target is Apple Silicon macOS. The system must remain usable without network access and must avoid sending audio, transcripts, prompts, profile data, telemetry, or application context to external services.

## Decision

Build the MVP as a native macOS app with a Swift/SwiftUI shell and AppKit integrations where required.

Use `AVAudioEngine` for microphone capture. Capture should be session-scoped to the push-to-talk hold, stream audio frames into the ASR layer, and tear down cleanly on release. Keep capture format conversion inside a small audio pipeline module so ASR backends can request their preferred sample rate and channel layout without leaking backend-specific logic into UI or hotkey handling.

Use a global hotkey implementation based on Carbon `RegisterEventHotKey` for the MVP. It is stable, low-latency, and avoids a heavier event-tap path for the initial push-to-talk trigger. Add an event-tap fallback only if later requirements need richer key-chord behavior or per-app key suppression. Hotkey state transitions must be explicit: idle, pressed, capturing, finalizing, inserting, and failed.

Introduce an ASR backend abstraction immediately:

```text
ASRSession.start(audioFormat, partialHandler)
ASRSession.accept(buffer)
ASRSession.finish() async throws -> Transcript
ASRSession.cancel()
```

The practical initial fallback should be a bundled or user-installed local `whisper.cpp`-compatible backend invoked through a narrow adapter. Prefer a persistent local process or native library binding once latency measurements require it, but allow a command-backed adapter for early integration and testing. Do not use cloud ASR or Apple's server-backed speech APIs in the MVP because offline behavior must be enforceable and auditable.

Use Ollama as the first local semantic editor integration. Treat it as an optional local runtime dependency discovered on startup. The editor layer should call a local HTTP endpoint only on loopback, with a short timeout and a deterministic bypass path when Ollama is unavailable. Prompts must be small, task-scoped, and include only the transcript plus minimal formatting context, such as target app category and field role. The semantic editor may fix casing, punctuation, and command-like dictation patterns, but it must not invent content.

Use an app-aware formatting layer between ASR/editor output and insertion. The layer should classify the focused target into coarse profiles such as chat, email, code editor, browser text field, terminal, and unknown. Formatting decisions should be local, explainable rules first, with the local editor used only where rules are insufficient.

Store user profile data in an encrypted local database. Use SQLite for the profile store and encrypt either through SQLCipher or a file-level encryption strategy backed by Keychain-managed keys. The MVP profile should include only settings needed for latency, formatting, hotkeys, model selection, and local correction preferences. Avoid storing raw audio by default.

For text insertion, use Accessibility APIs as the primary path when the target supports direct text insertion. Fall back to a clipboard-preserving paste flow when AX insertion is unavailable. The clipboard fallback must save and restore the prior clipboard contents, avoid unnecessary delays, and never run for secure input fields.

Implement secure-field avoidance before capture finalization and before insertion. If the focused element appears to be a password, secure text field, system credential prompt, or otherwise inaccessible sensitive control, cancel insertion and discard the transcript. The app should surface a local-only status notification instead of inserting.

Enforce strict offline mode as an application invariant. The app should not contain production code paths to external network services. Loopback calls to Ollama are allowed. Future local runtimes must use loopback, Unix domain sockets, XPC, or in-process APIs. Add network-deny assumptions to packaging and tests, and treat any non-loopback egress attempt as a release blocker.

## Consequences

Native Swift keeps the permissions, hotkey, audio, Accessibility, Keychain, and UI surfaces aligned with macOS conventions. It also reduces latency and packaging risk compared with an Electron shell.

An ASR abstraction lets the MVP start with the fastest practical local integration while preserving room to move to a lower-latency native binding later. The tradeoff is that the abstraction must be measured carefully; process startup, model warmup, and finalization time can easily consume the 1 second P95 budget.

Ollama is a pragmatic local editor runtime for MVP development, but it is a dependency outside the app bundle unless we later ship a managed runtime. The app must remain useful without it by inserting raw or lightly rule-formatted ASR output.

Clipboard fallback improves compatibility but increases privacy and correctness risk. It must be narrowly scoped, clipboard-preserving, and bypassed for secure fields.

## Risks

- Local ASR finalization may miss the P95 latency target unless models are preloaded and streaming partials are used.
- `whisper.cpp` quality and speed vary by model size, hardware, quantization, and language.
- Ollama model availability is user-managed in the MVP, so semantic cleanup must degrade cleanly.
- Accessibility permissions and per-app behavior can cause insertion failures that require clear local status reporting.
- Secure-field detection is imperfect across applications; conservative refusal is preferable to accidental insertion.
- Loopback-only editor calls still require tests or runtime guards to prevent accidental external egress.
- App-aware formatting can become unpredictable if too much behavior is delegated to the semantic editor.

## Open Questions

- Which local ASR model is the default for first-run Apple Silicon performance testing?
- Should the MVP ship a managed ASR binary, require user installation, or support both?
- What is the minimum acceptable behavior when Accessibility permission is denied?
- Should encrypted profile storage use SQLCipher directly or wrap a plain SQLite file in an app-managed encrypted container?
- Which target applications define the first app-aware formatting test matrix?
