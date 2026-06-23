# iOS app

SwiftUI app in `mobile/ios/`.

## Open

```sh
open mobile/ios/Mesh.xcodeproj
```

## Dependencies (SPM)

- **wallet-core** (Trust Wallet) — key derivation and Tron signing

Firebase and AppsFlyer are **not** linked in the open-source tree.

## Schemes

- **Mesh** — main app target, iOS 17+

## Localization

Strings in `Mesh/Localizable.xcstrings` and `Scripts/l10n/`.

## Background sends

`MeshBackgroundSendService` persists in-flight sends and resumes after app restart. Review this module carefully for audit.

## Release

Build and sign locally in Xcode with your Apple Developer account, or use your own CI pipeline. This repository does not include Codemagic or other hosted CI configuration.
