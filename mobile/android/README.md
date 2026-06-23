# Mesh Wallet — Android

Android app (`com.mesh.wallet`) — self-custody Tron USDT wallet, parity target: iOS app in `mobile/ios`.

## Stack

- Kotlin + Jetpack Compose
- Trust Wallet Core (HD + Tron TRC-20 signing)
- TronGrid API
- Mesh sponsorship relay (Cloudflare Worker)
- Encrypted storage (mnemonic, keys, passcode)

## One-time setup: Trust Wallet Core

Android uses `com.trustwallet:wallet-core` from **GitHub Packages** (version 4.6.9). You need a GitHub token with `read:packages`:

1. Create token: [github.com/settings/tokens/new?scopes=read:packages](https://github.com/settings/tokens/new?scopes=read:packages)
2. Run in project root:

```bash
chmod +x scripts/setup-trustwallet.sh
./scripts/setup-trustwallet.sh YOUR_GITHUB_USERNAME ghp_xxxxxxxx
```

Or add to `local.properties` manually (see `local.properties.example`).

## Run

1. Open `mobile/android` in Android Studio (Ladybug+), JDK 17
2. Sync Gradle → Run on API 26+ device/emulator

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :app:assembleDebug
```

## Config

Relay URL, treasury, send router, and TronGrid keys are in `app/build.gradle.kts` `buildConfigField` entries. Override for staging via product flavors if needed.

## Worker

Use the shared `worker/mesh-sponsorship-worker` relay — do not embed worker logic in the app.
