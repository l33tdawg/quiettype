# QuietType private beta release

This is the repeatable path for sharing a private beta DMG with trusted testers.

## 1. Build the beta DMG

Use the installed Developer ID Application identity:

```bash
QUIETTYPE_CODESIGN_IDENTITY="Developer ID Application: Dhillon Kannabhiran (2N7GKZ8D8Z)" \
  bash scripts/beta-release.sh
```

This runs tests, builds the arm64 release binary, packages `dist/QuietType.app`, signs the app and bundled helpers, creates a DMG, verifies it, and writes a SHA-256 checksum next to it.

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

## 5. Tester note

Send testers:

```text
QuietType private beta

Speak freely. Transcribe locally. Nothing leaves your Mac.

Download the DMG from the private GitHub release, drag QuietType to Applications, then open it and follow the setup prompts for Microphone, Accessibility, and voice training.

Contact: Dhillon "l33tdawg" Kannabhiran <dhillon@levelupctf.com>
```
