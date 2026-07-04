# Dictation Evaluation Fixtures

This directory contains static fixtures for evaluating the semantic editor and correction pipeline. Fixtures are data only; tests should load them and compare pipeline output against the expected fields without requiring network access.

## Schema

`dictation_cases.json` has this shape:

- `schema_version`: integer version for fixture consumers.
- `description`: human-readable purpose of the fixture set.
- `cases`: ordered list of representative dictation scenarios.

Each case contains:

- `id`: stable identifier for test names and failure messages.
- `context`: app, surface, audience, style, privacy mode, and optional language metadata.
- `input.raw_transcript`: unprocessed dictation text from speech recognition.
- `input.selected_text`: selected text available to the semantic editor, if any.
- `input.cursor_context`: surrounding editor context that may influence formatting.
- `expected.edited_text`: canonical output after semantic editing and corrections.
- `expected.corrections`: explicit correction operations that should be honored.
- `expected.preserve_terms`: domain vocabulary that must retain exact casing and spelling.
- `assertions.must_include`: substrings expected in the final output.
- `assertions.must_not_include`: substrings that should not remain after editing.
- `assertions.format`: expected output class, such as `email`, `markdown_bullets`, `code_comment`, or `code`.

## Usage

Tests should treat these fixtures as regression cases for offline, privacy-first behavior:

- Do not call cloud services while evaluating these cases.
- Preserve domain vocabulary exactly, especially `SAGE`, `CometBFT`, `Ollama`, `Utimaco`, `CSe100`, and `Ed25519`.
- Apply spoken corrections, such as replacing `Thursday` with `Friday`, before final formatting assertions.
- Match context-aware formatting for Slack, email, notes, and code editor surfaces.
- Keep fixture IDs stable so failures can be traced across semantic editor and correction pipeline tests.
