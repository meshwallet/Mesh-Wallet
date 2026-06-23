# Build reproducibility

Mesh release builds should be reproducible from tagged commits in this repository.

## Version pinning

| Component | Pin location |
|-----------|----------------|
| Chrome extension | `extension/chrome/package-lock.json` |
| iOS | Xcode project + Swift Package resolved versions |
| Android | `mobile/android/gradle/libs.versions.toml` or `build.gradle.kts` |
| Worker | `worker/mesh-sponsorship-worker/package-lock.json` |

## Chrome extension

```sh
cd extension/chrome
npm ci
npm run build
```

Output: `extension/chrome/dist/`. Compare SHA-256 of `dist/` against published Chrome Web Store package (unpacked).

## iOS

1. Checkout release tag
2. `xcodebuild -scheme Mesh -configuration Release -destination 'generic/platform=iOS' archive`
3. Compare embedded `WalletCore` and app binary hashes with App Store IPA (after fairplay strip for crypto libs only).

## Android

```sh
cd mobile/android
./gradlew :app:assembleRelease
```

Compare APK/AAB signing certificate and `classes.dex` hashes with Play Store artifact.

## Worker (local verification)

```sh
cd worker/mesh-sponsorship-worker
npm ci
npm run dev
```

Compare local bundle behavior with the documented API. Production deploy and secrets are **out of scope** for this open-source repository.

## Secrets

Production relay auth, TronGrid API keys, and signing keys are **not** in git. Document required env vars in each subproject's `.env.example`.
