# Mesh Wallet

**Send USDT on TRON without holding TRX.**

Mesh is a self-custody wallet for TRC-20 USDT — native apps for iOS and Android, plus a Chrome extension. One recovery phrase, multiple accounts, signing on-device.

<p align="center">
  <img src="https://raw.githubusercontent.com/meshwallet/Mesh-Wallet/main/public/banner.png" alt="Mesh Wallet" width="100%" />
</p>

<p align="center">
  <a href="https://meshwallet.app"><img src="https://img.shields.io/badge/Website-meshwallet.app-111111?style=for-the-badge" alt="Website"></a>
  <a href="https://apps.apple.com/us/app/mesh-usdt-wallet/id6773052229"><img src="https://img.shields.io/badge/App_Store-Download-000000?style=for-the-badge&logo=apple&logoColor=white" alt="App Store"></a>
  <a href="https://chromewebstore.google.com/detail/mesh-usdt-wallet/dahjpanhlinmadhfkamhmlcegppdcpcf"><img src="https://img.shields.io/badge/Chrome-Extension-4285F4?style=for-the-badge&logo=googlechrome&logoColor=white" alt="Chrome extension"></a>
  <a href="https://meshwallet.app/support"><img src="https://img.shields.io/badge/Support-Help-333333?style=for-the-badge" alt="Support"></a>
</p>

---

## Overview

| | |
|---|---|
| **Network** | TRON (TRC-20) |
| **Asset** | USDT |
| **Custody** | Non-custodial — keys on device |
| **Platforms** | iOS 17+, Android 8+, Chrome (MV3) |

Mesh handles TRX energy and bandwidth through a sponsorship relay so everyday USDT transfers do not require a separate gas balance. Fees are itemized before you sign.

---

## Features

- **Gasless USDT sends** — no TRX balance required for typical transfers
- **Multi-account HD wallet** — separate receive/spend addresses under one seed
- **Privacy routing** — optional multi-hop sends from dedicated accounts
- **Background send recovery** — in-flight transfers resume after app restart
- **Passcode & biometrics** — app lock with secure enclave / keystore where available
- **Eight languages** — EN, ES, TR, VI, ID, AR, RU, ZH-Hans

---

## Architecture

```mermaid
flowchart LR
  subgraph clients [Clients]
    iOS[iOS]
    Android[Android]
    Chrome[Chrome]
  end

  subgraph chain [TRON]
    TronGrid[TronGrid]
    USDT[USDT TRC-20]
  end

  subgraph relay [Sponsorship relay]
    Worker[Cloudflare Worker]
  end

  iOS --> TronGrid
  Android --> TronGrid
  Chrome --> TronGrid
  iOS --> Worker
  Android --> Worker
  Chrome --> Worker
  Worker --> USDT
  clients --> USDT
```

Clients sign transactions locally. The relay delegates network resources (energy, activation) and coordinates queued sends — it never holds user keys.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for module layout and send flow.

---

## Repository structure

```
Mesh-Wallet/
├── mobile/
│   ├── ios/                 SwiftUI · Trust Wallet Core
│   └── android/             Kotlin · Jetpack Compose · Trust Wallet Core
├── extension/
│   └── chrome/              React · Vite · MV3
├── worker/
│   ├── mesh-sponsorship-worker/   Sponsorship relay (Cloudflare Workers)
│   └── mesh-contracts/            Tron send-router contract
├── docs/
│   └── ARCHITECTURE.md
├── public/                  Brand assets
├── LICENSE
└── SECURITY.md
```

---

## Development

### Prerequisites

| Tool | Version |
|------|---------|
| Xcode | 16+ (iOS) |
| Android Studio | Ladybug+ / JDK 17 |
| Node.js | 20+ |
| Wrangler | optional, worker local dev |

### Clone

```sh
git clone https://github.com/meshwallet/Mesh-Wallet.git
cd Mesh-Wallet
```

### iOS

```sh
open mobile/ios/Mesh.xcodeproj
```

Run the **Mesh** scheme. Configure TronGrid keys in `mobile/ios/Mesh/Info.plist` (see `Info.plist.example`).

### Android

```sh
cd mobile/android
cp local.properties.example local.properties
./gradlew assembleDebug
```

Trust Wallet Core requires a GitHub Packages token — see `mobile/android/README.md`.

### Chrome extension

```sh
cd extension/chrome
cp .env.example .env
npm ci
npm run dev
```

Load `extension/chrome/dist` as an unpacked extension. Configure keys in `.env`.

### Worker (local)

```sh
cd worker/mesh-sponsorship-worker
cp .dev.vars.example .dev.vars
npm ci
npm run dev
```

Source for the sponsorship relay and on-chain router. See `worker/README.md`.

---

## Security

Report vulnerabilities to **support@meshwallet.app** — do not open public issues for exploitable findings.

Full policy: [SECURITY.md](SECURITY.md)

---

## License

[MIT](LICENSE)
