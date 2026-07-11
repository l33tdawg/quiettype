# QuietType public beta release

This is the repeatable path for publishing a signed, notarized public beta DMG.

## 1. Build the beta DMG

Use the installed Developer ID Application identity:

```bash
QUIETTYPE_VERSION="1.0.0" \
QUIETTYPE_BUILD="28" \
QUIETTYPE_RELEASE_LABEL="rc.1" \
QUIETTYPE_NOTARIZE="1" \
SAGE_RELEASE_TAG="v11.4.11" \
QUIETTYPE_CODESIGN_IDENTITY="Developer ID Application: Dhillon Kannabhiran (2N7GKZ8D8Z)" \
  bash scripts/beta-release.sh
```

This runs tests, builds the arm64 release binary, packages `dist/QuietType.app`, signs the app and bundled helpers, creates a DMG, verifies it, and writes a SHA-256 checksum next to it.

Run this script on Apple Silicon or an arm64 macOS CI runner. It invokes Swift
under `arch -arm64` so tests and the app binary match the arm64-only beta DMG.

By default the public beta package also bundles the local WhisperKit/Core ML ASR model from:

```text
~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB
```

That makes the DMG much larger, but it gives testers the expected install-and-run experience. To intentionally ship a smaller app that uses an already-installed model, set `QUIETTYPE_BUNDLE_MODELS=0`.

The beta package also bundles `SAGE.app` when available at:

```text
vendor/SAGE.app
```

QuietType checks a user-installed SAGE first, then the bundled SAGE GUI inside
the app bundle. To prepare that bundle from the pinned/current SAGE release:

```bash
bash scripts/download-sage-gui.sh
```

By default this script downloads the latest release from
`https://github.com/l33tdawg/sage`. Current beta builds pin SAGE to `v11.4.11`
for reproducibility:

```bash
SAGE_RELEASE_TAG="v11.4.11" bash scripts/download-sage-gui.sh
```

For stricter release reproducibility, pass the expected release asset checksum:

```bash
SAGE_RELEASE_TAG="v11.4.11" \
SAGE_ASSET_SHA256="EXPECTED_DMG_OR_ZIP_SHA256" \
  bash scripts/download-sage-gui.sh
```

The downloader and packager both validate that the bundled app is
`com.sage.brain`, matches the pinned SAGE version when one is provided, contains
an arm64 `sage-gui` executable, and can be re-signed inside QuietType before the
DMG is built.

To intentionally ship without bundled SAGE for a developer-only build, set
`QUIETTYPE_BUNDLE_SAGE=0`. Public tester builds should keep SAGE
bundled because QuietType requires SAGE governed local memory.

Expected output:

```text
dist/QuietType-1.0.0-rc.1-macOS-arm64.dmg
dist/QuietType-1.0.0-rc.1-macOS-arm64.dmg.sha256
```

## 2. Validate the signed artifact

Before sharing a beta, validate the exact DMG artifact that testers will
install:

```bash
bash scripts/validate-release-artifact.sh dist/QuietType-1.0.0-rc.1-macOS-arm64.dmg
```

The validator mounts the DMG read-only, checks that `CFBundleExecutable` exists
and is executable, verifies the outer app, main executable, bundled helper
binaries, and bundled `SAGE.app`, then runs Gatekeeper assessment on the mounted
app and the DMG. For clean-machine Launch Services validation, run the same
command with:

```bash
QUIETTYPE_VALIDATE_LAUNCH=1 bash scripts/validate-release-artifact.sh dist/QuietType-1.0.0-rc.1-macOS-arm64.dmg
```

## 3. Notarization

For public testers, notarization is required for a normal double-click install experience. Without it, Gatekeeper rejects the DMG as `Unnotarized Developer ID`.

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

## 4. Create a public GitHub prerelease

The repository is public, so the prerelease and its assets are visible to everyone.

```bash
VERSION="v1.0.0-rc.1"
DMG="dist/QuietType-1.0.0-rc.1-macOS-arm64.dmg"

git tag -a "$VERSION" -m "QuietType 1.0.0 RC1"
git push origin "$VERSION"

gh release create "$VERSION" "$DMG" "$DMG.sha256" \
  --repo l33tdawg/quiettype \
  --verify-tag \
  --prerelease \
  --title "QuietType 1.0.0 RC1" \
  --notes "Public beta for macOS Apple Silicon. Local dictation, local memory, no cloud processing."
```

## 5. Enable GitHub Pages

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

The Pages site includes cookie-free GoatCounter analytics:

```html
<script data-goatcounter="https://quiettype.goatcounter.com/count" async src="https://gc.zgo.at/count.js"></script>
```

Create the GoatCounter site code `quiettype` before public launch. This tracks
page engagement on GitHub Pages only; the macOS app does not call home. Release
download counts remain on GitHub Releases and are surfaced on the landing page
with the GitHub downloads badge.

GitHub Pages is enabled from `main:/docs` and deploys after pushes to `main`.

## 6. GitHub Actions release automation

The workflow at `.github/workflows/beta-release.yml` builds, signs, notarizes,
staples and uploads a public beta DMG on pushes to `main`. When the push is a
tag like `v1.0.0-beta.1`, it also creates a GitHub prerelease.

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
It also downloads the SAGE GUI release into `vendor/SAGE.app` before packaging.
`SAGE_RELEASE_TAG` is currently pinned to `v11.4.11` to avoid version drift.

If these secrets are not configured, the workflow records a notice and skips
the signed build, artifact upload and prerelease steps. In that case, use the
local notarized build and manual `gh release create` flow above; a green skipped
workflow is not proof that a release artifact was produced.

## 7. Tester note

Send testers:

```text
QuietType public beta

Speak freely. Transcribe locally. Nothing leaves your Mac.

Download the DMG from the GitHub prerelease, drag QuietType to Applications, then open it and follow the setup prompts for Microphone and Accessibility. Voice training is optional.

Contact: Dhillon "l33tdawg" Kannabhiran <dhillon@levelupctf.com>
```
