# QuietType

Offline, privacy-first voice input for coding agents and macOS apps.

QuietType is for people who want to talk to Codex, Claude Code, ChatGPT, Cursor,
terminals, editors, notes, and email without sending their voice or raw prompts
to a cloud transcription service.

The product goal is not literal transcription. It is a local streaming speech compiler:

```text
natural speech -> streaming ASR -> correction layer -> local semantic editor -> app-aware text insertion
```

See [docs/PRD.md](docs/PRD.md) for the product requirements.
See [docs/macos-signing.md](docs/macos-signing.md) for local app signing notes.
See [docs/beta-release.md](docs/beta-release.md) for local and GitHub Actions release notes.

## Current Prototype

This initial scaffold contains:

- Swift Package core interfaces for ASR, semantic editing, context collection, and text insertion.
- Development vocabulary and ASR confusion mappings from the PRD.
- Correction engine.
- Stable-prefix detector.
- Dictation session controller for the future push-to-talk app loop.
- Rule-based semantic editor fallback for tests and local harness work.
- Ollama semantic editor adapter restricted to loopback HTTP.
- Optional SAGE memory backend abstraction with SQLite, SAGE, and hybrid modes.
- CLI harnesses for raw text and full session experiments.

## Run

```bash
swift test
swift run localtype "the sage benchmark needs to rerun the comet b f t latency numbers"
swift run localtype-session "the sage benchmark needs to rerun the comet b f t latency numbers"
```

The production MVP path will replace the rule-based editor with a local Ollama-backed editor and add the macOS AppKit/SwiftUI shell for hotkey capture, AVAudioEngine capture, app context, and insertion.

In the current Rosetta/mixed-architecture shell, use the commands in [docs/dev-setup.md](docs/dev-setup.md).
