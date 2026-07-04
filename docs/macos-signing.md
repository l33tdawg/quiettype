# macOS signing

QuietType should be tested from a stable signed `.app` bundle. Changing bundle identifiers, paths, or signing identities can reset macOS TCC permissions for Microphone and Accessibility.

## Local development signing

The package script accepts a signing identity through `QUIETTYPE_CODESIGN_IDENTITY`.

```bash
swift build --arch arm64 --product LocalTypeMac
QUIETTYPE_CODESIGN_IDENTITY="Developer ID Application: Your Team Name (TEAMID)" \
  bash scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 dist/QuietType.app
```

For ad-hoc development builds, omit the variable. The script will sign with `-`.

## Recommended identities

Use `Developer ID Application` for distribution outside the Mac App Store. Use `Apple Development` for local development when testing on machines registered to the Apple Developer account.

Check installed identities with:

```bash
security find-identity -v -p codesigning
```

Do not commit certificates, private keys, provisioning profiles, `.p12` files, notarization credentials, or App Store Connect API keys.

## Future release path

1. Sign the app and bundled helper binaries with a stable Developer ID identity.
2. Add hardened runtime entitlements once the app moves beyond local prototypes.
3. Notarize the app with Apple notary tooling.
4. Staple the notarization ticket before publishing a DMG.
