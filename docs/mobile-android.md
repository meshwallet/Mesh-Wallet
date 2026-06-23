# Android app

Kotlin + Compose in `mobile/android/`.

## Setup

See [mobile/android/README.md](../mobile/android/README.md) for Trust Wallet Core GitHub Packages token.

## Modules

- `app/` — UI, domain logic, Tron integration
- `core/` — session, secure storage, config
- `data/` — wallet registry, encrypted persistence

## Firebase / AppsFlyer

Removed from the open-source tree. `MeshApplication` only loads Trust Wallet Core and initializes `WalletSession`.

## Release

```sh
./gradlew :app:bundleRelease
```

Sign with your release keystore (never commit keystore files).
