# **Mesh** · [meshwallet.app](https://meshwallet.app)

**Send USDT without TRX.** A safe, self-custodial **USDT wallet** for [**TRON**](https://trondao.org/) — native mobile (iOS & Android) and **Chrome extension**. One recovery phrase, separate accounts for everyday use.

<p align="center">
  <img src="https://raw.githubusercontent.com/meshwallet/Mesh-Wallet/main/public/banner.png" alt="Mesh — Send USDT without TRX" width="100%" />
</p>

You keep full control: we **do not** have access to your funds, keys, or data. **Mesh** is built for **clarity** and **reliability**, with a minimal dependency footprint and **zero telemetry** in this open-source tree.

---

## Why **Mesh**?

**🪙 USDT only**  
No token discovery, no swap aggregator, no NFT tab. The wallet has one job: move USDT on TRC-20.

**⚡ Send without holding TRX**  
Mesh covers TRX gas behind the scenes. You send USDT; network resources are handled for you. Fees are shown line-by-line before you sign.

**🔐 Separate accounts**  
Create dedicated receive/spend accounts inside one wallet. Each account has its own TRON address and balance. Your recovery phrase backs them all up.

**📱 Use it wherever you are**  
**Mesh** works as a native iOS app, Android app, and Chrome extension — so your wallet is always within reach.

**🛡️ Non-custodial by design**  
Seed phrase generated on-device. Keys never leave your device. No account system, no KYC, no email signup.

**🔍 Audit-ready open source**  
Crypto and signing logic is public. This repository ships without analytics SDKs, remote config exfiltration, or server-side key upload code.

**🧰 Focused feature set**  
Receive, send, activity history, passcode/biometric lock, multi-account privacy, and background send recovery — without casino-style clutter.

---

## 🔗 Links

- 🌐 **Website**: [meshwallet.app](https://meshwallet.app)
- 📲 **App Store**: [Mesh: USDT Wallet](https://apps.apple.com/us/app/mesh-usdt-wallet/id6773052229)
- 🧩 **Chrome extension**: [Mesh: USDT Wallet](https://chromewebstore.google.com/detail/mesh-usdt-wallet/dahjpanhlinmadhfkamhmlcegppdcpcf)
- 🛟 **Support**: [meshwallet.app/support](https://meshwallet.app/support)
- 🔒 **Security**: [docs/SECURITY.md](docs/SECURITY.md)

---

## 🛠️ For developers

### 📑 Table of contents

- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Local setup](#local-setup)
- [Chrome extension](#chrome-extension)
- [iOS](#ios)
- [Android](#android)
- [Cloudflare worker](#cloudflare-worker)
- [Security & audit](#security--audit)

### Repository layout

```
mesh/
├── mobile/
│   ├── ios/          # SwiftUI iOS app
│   └── android/      # Kotlin / Jetpack Compose app
├── extension/
│   └── chrome/       # Chrome MV3 extension (Vite + React)
├── worker/
│   ├── mesh-sponsorship-worker/   # Relay source (audit / local dev — not deployed from this repo)
│   └── mesh-contracts/            # On-chain contract sources
├── docs/             # Security, build, and audit notes
└── public/           # README assets
```

### Requirements

- **macOS** recommended for iOS builds
- **Node.js** 20+ for the Chrome extension
- **Android Studio** / JDK 17 for Android
- **Xcode** 16+ for iOS
- **Wrangler** (optional) — local worker dev only

### Local setup

Clone the repository and open the platform you need:

```sh
git clone https://github.com/meshwallet/mesh.git
cd mesh
```

### Chrome extension

```sh
cd extension/chrome
npm ci
npm run dev      # development build with HMR
npm run build    # production build → dist/
```

Load `extension/chrome/dist` as an unpacked extension in `chrome://extensions`.

See [docs/extension.md](docs/extension.md) for architecture notes.

### iOS

```sh
open mobile/ios/Mesh.xcodeproj
```

Build and run the **Mesh** scheme on a device or simulator (iOS 17+).

See [docs/mobile-ios.md](docs/mobile-ios.md).

### Android

```sh
cd mobile/android
cp local.properties.example local.properties   # set sdk.dir
./gradlew assembleDebug
```

See [docs/mobile-android.md](docs/mobile-android.md).

### Sponsorship worker (source only)

```sh
cd worker/mesh-sponsorship-worker
npm ci
npm run dev
```

Relay source lives in the repo for audit. **Do not deploy to Cloudflare from this repository** — production already uses `mesh-sponsorship-relay.meshwallet.workers.dev`. See [docs/worker.md](docs/worker.md).

### Security & audit

- [SECURITY.md](docs/SECURITY.md) — threat model and responsible disclosure
- [AUDIT.md](docs/AUDIT.md) — scope guide for reviewers
- [BUILD-REPRODUCIBILITY.md](docs/BUILD-REPRODUCIBILITY.md) — reproducible release builds

---

## What this repo deliberately excludes

The public tree **does not** include:

- Firebase / Remote Config clients
- AppsFlyer or other attribution/analytics SDKs
- Server endpoints that upload recovery phrases or private keys
- Proprietary API keys (use `.env.example` / `local.properties.example`)

Production store builds may ship through separate release channels; verify behavior against this source before trusting a binary.

---

## License

[MIT](LICENSE)
