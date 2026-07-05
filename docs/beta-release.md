# QuietType private beta release

This is the repeatable path for sharing a private beta DMG with trusted testers.

## 1. Build the beta DMG

Use the installed Developer ID Application identity:

```bash
QUIETTYPE_CODESIGN_IDENTITY="Developer ID Application: Dhillon Kannabhiran (2N7GKZ8D8Z)" \
  bash scripts/beta-release.sh
```

This runs tests, builds the arm64 release binary, packages `dist/QuietType.app`, signs the app and bundled helpers, creates a DMG, verifies it, and writes a SHA-256 checksum next to it.

By default the private beta package also bundles the local WhisperKit/Core ML ASR model from:

```text
~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB
```

That makes the DMG much larger, but it gives testers the expected install-and-run experience. To intentionally ship a smaller app that uses an already-installed model, set `QUIETTYPE_BUNDLE_MODELS=0`.

Expected output:

```text
dist/QuietType-0.1.0-beta.1-macOS-arm64.dmg
dist/QuietType-0.1.0-beta.1-macOS-arm64.dmg.sha256
```

## 2. Notarization

For private testers, notarization is required for a normal double-click install experience. Without it, Gatekeeper rejects the DMG as `Unnotarized Developer ID`.

Keep credentials out of the repository. Store them in Keychain or use an App Store Connect API key outside the repo.

Create the Keychain profile once:

```bash
xcrun notarytool store-credentials QUIETTYPE_NOTARY \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "2N7GKZ8D8Z" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then notarize and staple the current DMG:

```bash
bash scripts/notarize-dmg.sh
```

Or run notarization as part of the build:

```bash
QUIETTYPE_NOTARIZE=1 bash scripts/beta-release.sh
```

## 3. Create a private GitHub release

The repository is private, so a GitHub release is private to people with repo access.

```bash
VERSION="v0.1.0-beta.1"
DMG="dist/QuietType-0.1.0-beta.1-macOS-arm64.dmg"

git tag "$VERSION"
git push origin "$VERSION"

gh release create "$VERSION" "$DMG" "$DMG.sha256" \
  --repo l33tdawg/quiettype \
  --prerelease \
  --title "QuietType 0.1.0 beta 1" \
  --notes "Private beta for macOS Apple Silicon. Local dictation, local memory, no cloud processing."
```

## 4. Enable GitHub Pages

Use the repository settings:

```text
Settings -> Pages -> Build and deployment -> Deploy from a branch
Branch: main
Folder: /docs
```

The landing page lives at `docs/index.html`, with Open Graph assets at `docs/og.png` and `docs/og.svg`.
The intended public URL is:

```text
https://l33tdawg.github.io/quiettype/
```

GitHub rejected Pages enablement while the repository is private on the current
plan. The `/docs` site is ready; enable Pages when the repo becomes public for
the 1.0 beta launch, or upgrade to a plan that supports private Pages.

## 5. GitHub Actions release automation

The workflow at `.github/workflows/beta-release.yml` builds, signs, notarizes,
staples and uploads a private beta DMG on pushes to `main`. When the push is a
tag like `v0.1.0-beta.7`, it also creates a GitHub prerelease.

Required repository secrets:

```text
DEVELOPER_ID_CERTIFICATE_BASE64
DEVELOPER_ID_CERTIFICATE_PASSWORD
CI_KEYCHAIN_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
```

`DEVELOPER_ID_CERTIFICATE_BASE64` should be the base64-encoded `.p12` export of
the Developer ID Application certificate. The workflow uses the existing app
bundle identifier `local.quiettype.mac`; do not change it unless you intend to
reset macOS permissions for testers.

The workflow downloads the WhisperKit/Core ML model from the pinned upstream
revision:

```text
argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808
```

This keeps the model out of git while still making CI releases reproducible.

## 6. Tester note

Send testers:

```text
QuietType private beta

Speak freely. Transcribe locally. Nothing leaves your Mac.

Download the DMG from the private GitHub release, drag QuietType to Applications, then open it and follow the setup prompts for Microphone, Accessibility, and voice training.

Contact: Dhillon "l33tdawg" Kannabhiran <dhillon@levelupctf.com>
```
