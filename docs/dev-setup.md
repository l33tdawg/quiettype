# Development Setup

This repository is a Swift Package for QuietType, a local-first macOS dictation prototype. It currently builds a `LocalTypeCore` library, a `localtype` CLI executable, the `LocalTypeMac` app executable, and XCTest-based `LocalTypeCoreTests`.

## Requirements

- macOS 13 or newer.
- Xcode Command Line Tools with Swift 5.9 or newer.
- Apple Silicon is the intended development target.
- Optional: Rosetta when working from a mixed-architecture or x86_64 shell.
- Optional: Ollama listening on loopback only.
- Required for app-level dictation flows: SAGE installed at `/Applications/SAGE` or bundled at `QuietType.app/Contents/Resources/SAGE.app`.

## Local Build and Test Caches

Use package and Clang module caches inside the repository so SwiftPM does not depend on user-global cache paths in this managed environment:

```bash
env \
  SWIFTPM_HOME=/Users/l33tdawg/nodejs-projects/typeless-secure/.swiftpm-home \
  CLANG_MODULE_CACHE_PATH=/Users/l33tdawg/nodejs-projects/typeless-secure/.clang-module-cache \
  swift build
```

## Intended Apple Silicon Test Command

From a native Apple Silicon shell, run tests without forcing an architecture:

```bash
env \
  SWIFTPM_HOME=/Users/l33tdawg/nodejs-projects/typeless-secure/.swiftpm-home \
  CLANG_MODULE_CACHE_PATH=/Users/l33tdawg/nodejs-projects/typeless-secure/.clang-module-cache \
  swift test --disable-swift-testing
```

The test suite is XCTest-based. `--disable-swift-testing` keeps the run on XCTest and avoids Swift Testing discovery behavior that is not needed for this package.

## Rosetta or Mixed-Architecture Test Command

In this environment, a mixed Apple Silicon/Rosetta setup can build one architecture and try to load tests under another. Use the known-good x86_64 command when the shell or SwiftPM process is running under Rosetta:

```bash
env \
  SWIFTPM_HOME=/Users/l33tdawg/nodejs-projects/typeless-secure/.swiftpm-home \
  CLANG_MODULE_CACHE_PATH=/Users/l33tdawg/nodejs-projects/typeless-secure/.clang-module-cache \
  swift test --arch x86_64 --disable-swift-testing
```

## CLI Smoke Test

The CLI target is `localtype`. It accepts raw dictation text as command-line arguments and prints the edited text:

```bash
env \
  SWIFTPM_HOME=/Users/l33tdawg/nodejs-projects/typeless-secure/.swiftpm-home \
  CLANG_MODULE_CACHE_PATH=/Users/l33tdawg/nodejs-projects/typeless-secure/.clang-module-cache \
  swift run localtype "the sage benchmark needs to rerun the comet b f t latency numbers"
```

For a Rosetta or mixed-architecture shell, pin the run to x86_64:

```bash
env \
  SWIFTPM_HOME=/Users/l33tdawg/nodejs-projects/typeless-secure/.swiftpm-home \
  CLANG_MODULE_CACHE_PATH=/Users/l33tdawg/nodejs-projects/typeless-secure/.clang-module-cache \
  swift run --arch x86_64 localtype "the sage benchmark needs to rerun the comet b f t latency numbers"
```

Expected output is a polished version of the input, preserving domain vocabulary such as `SAGE` and `CometBFT`.

## App Bundle

Build and package the visible macOS app:

```bash
env \
  SWIFTPM_HOME=/Users/l33tdawg/nodejs-projects/typeless-secure/.swiftpm-home \
  CLANG_MODULE_CACHE_PATH=/Users/l33tdawg/nodejs-projects/typeless-secure/.clang-module-cache \
  swift build --arch x86_64 --product LocalTypeMac

bash scripts/package-app.sh
open dist/QuietType.app
```

The Swift target is still named `LocalTypeMac` internally. The app name shown to users is `QuietType`.

## Local-Only Constraints

The product invariant is local-first operation:

- Do not add cloud ASR, cloud LLM, hosted telemetry, or external network dependencies to the development path.
- Audio, transcript text, app context, vocabulary, correction history, and writing preferences should stay on the machine.
- Loopback runtimes are allowed for local development.
- Non-loopback Ollama and SAGE endpoints should be treated as invalid unless a future explicit user policy says otherwise.
- QuietType requires local SAGE governed memory for app operation. Tests may still exercise legacy store types, but product paths should guide users to install, launch, unlock, and register SAGE instead of falling back to a standalone local memory store.

## Optional Ollama

Ollama is an optional local semantic editor runtime. The current adapter defaults to:

```text
http://127.0.0.1:11434/api/generate
```

Only loopback hosts are acceptable: `127.0.0.1`, `localhost`, or `::1`. If Ollama is unavailable, development and tests should continue through deterministic rule-based behavior.

## Required SAGE

SAGE is the required governed memory backend. The expected local installation path is:

```text
/Applications/SAGE
```

Beta packages may also bundle SAGE at:

```text
QuietType.app/Contents/Resources/SAGE.app
```

The default local SAGE endpoint is:

```text
http://127.0.0.1:8080
```

SAGE integration should register `quiettype-agent` and communicate through the documented local SAGE SDK/API. If SAGE is missing, locked, or not running, QuietType should guide the user through install/start/unlock/setup rather than silently continuing without governed memory. Dictation memories remain local-only by default.
