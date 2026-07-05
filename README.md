# QuietType

Private, local voice input for coding agents and macOS apps.

QuietType lets you talk to Codex, Claude Code, ChatGPT, Cursor, terminals,
editors, notes and email without sending your voice or raw prompts to a cloud
transcription service.

> Speak freely. Transcribe locally. Nothing leaves your Mac.

![QuietType app onboarding screen](docs/screenshots/quiettype-onboarding.png)

## Why

Coding agents work best when you give them rich context: what to inspect, what
to change, how to test it, what to avoid and what tradeoffs to explain. Typing
that much context is slow. Cloud dictation is fast, but it can expose exactly
the material builders and security teams care about: source paths, bug details,
client context, unreleased plans, private prompts and voice samples.

Voice is also biometric data. In the age of fake AI video and voice cloning, a
dictation tool should not treat raw voice samples as harmless telemetry.

QuietType is built for the opposite default:

- no cloud speech recognition
- no uploaded voice samples
- no uploaded transcripts
- no uploaded prompt text
- no remote LLM cleanup path
- no telemetry by default
- local correction and vocabulary memory
- optional local SAGE governed memory

## Main Features

### Fast voice input for agents

Use QuietType anywhere you can type:

- Codex
- Claude Code
- ChatGPT
- Cursor
- VS Code
- terminals
- GitHub issues
- Slack and email
- notes and docs

The goal is not literal transcription. QuietType turns natural speech into
usable written instructions:

```text
natural speech
  -> streaming local ASR
  -> correction and vocabulary layer
  -> local semantic cleanup
  -> app-aware formatted text
  -> insertion into the active app
```

### Local-only speech processing

The beta bundles a local WhisperKit/Core ML speech model for Apple Silicon.
Normal dictation does not require OpenAI, Gemini, Anthropic or any hosted ASR
provider.

### Encrypted memory

QuietType keeps local memory encrypted at rest using AES-GCM with a
Keychain-backed key. Memory is used to improve transcription quality: preferred
spellings, technical vocabulary, correction patterns, app-specific style and
training hints.

When SAGE is installed, QuietType registers as `quiettype-agent` and can use
SAGE as an optional governed local memory store. SAGE memories remain
local-first by default.

### Voice training without cloud training

The setup flow asks users to read short scripts. QuietType uses those local
samples to improve cadence, vocabulary and spelling hints. Samples stay on the
user's machine.

![QuietType guided setup screenshot](docs/screenshots/quiettype-guide-focus.png)

### Mac-native workflow

- Fn-first global shortcut with a configurable fallback
- active-app insertion
- clipboard fallback
- microphone and Accessibility setup guidance
- setup progress and local activity status
- SAGE memory search/review UI
- signed and notarized beta DMG

## Privacy Model

QuietType is designed around a simple rule: private voice and prompt material
should not leave the Mac.

| Area | Default |
| --- | --- |
| Voice audio | Local only |
| Voice training samples | Local only |
| Raw transcript text | Local only |
| Prompt cleanup | Local only |
| Vocabulary memory | Encrypted local store |
| SAGE memory | Optional, local-first |
| Cloud fallback | None |

Network participation is not required for normal dictation. If a future SAGE
network policy is enabled, dictation memories should remain local-only unless
the user explicitly changes that policy.

## Status

QuietType is in private beta for macOS Apple Silicon. The repository will remain
private until the 1.0 beta milestone, after a few more hardening releases around
setup, permissions, memory review, packaging and accuracy.

Landing page target:

```text
https://l33tdawg.github.io/quiettype/
```

The GitHub Pages site is ready in `docs/` and should be enabled when the repo
goes public for the 1.0 beta launch.

Private releases:

```text
https://github.com/l33tdawg/quiettype/releases
```

## Development

See [docs/PRD.md](docs/PRD.md) for product requirements.
See [docs/dev-setup.md](docs/dev-setup.md) for local development setup.
See [docs/macos-signing.md](docs/macos-signing.md) for signing notes.
See [docs/beta-release.md](docs/beta-release.md) for local and GitHub Actions
release notes.

Run tests:

```bash
swift test
```

Try the core text pipeline:

```bash
swift run localtype "the sage benchmark needs to rerun the comet b f t latency numbers"
swift run localtype-session "ask codex to review the auth flow and preserve the ed twenty five five nineteen terminology"
```

## Author

QuietType is by Dhillon "l33tdawg" Kannabhiran.

Contact: [dhillon@levelupctf.com](mailto:dhillon@levelupctf.com)
