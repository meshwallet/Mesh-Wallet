# Architecture

## Components

| Component | Stack | Role |
|-----------|-------|------|
| `mobile/ios` | SwiftUI, Wallet Core | Native iOS wallet |
| `mobile/android` | Kotlin, Compose, Wallet Core | Native Android wallet |
| `extension/chrome` | React, Vite, MV3 | Browser wallet |
| `worker/mesh-sponsorship-worker` | Cloudflare Workers, TronWeb | Energy delegation, send queue |
| `worker/mesh-contracts` | Solidity | On-chain USDT send router |

All clients share the same logical model: BIP-39 seed → HD accounts → local signing → TronGrid for chain reads → relay for resource sponsorship.

## Send flow

1. User enters recipient and amount on the review screen.
2. Client builds a TRC-20 `transfer` (direct or via send router).
3. Transaction is signed with the account private key on-device.
4. Relay prepares sender energy (`POST /v1/prepare-sender`) if needed.
5. Signed transaction is broadcast; relay tracks status (`GET /v1/send-status`).
6. Background service polls until confirmed or failed.

Privacy sends route USDT through intermediate HD-derived addresses before reaching the recipient.

## Key modules

### iOS

| Path | Purpose |
|------|---------|
| `Mesh/Services/Tron/` | TronGrid, USDT, transaction signing |
| `Mesh/Core/MeshBackgroundSendService.swift` | Persistent send queue |
| `Mesh/Services/MeshPrivacyService.swift` | Multi-account privacy routing |
| `Mesh/Services/MeshEnergyBrokerService.swift` | Relay integration |

### Android

| Path | Purpose |
|------|---------|
| `data/tron/` | Wallet Core integration, TronGrid |
| `data/relay/` | Sponsorship relay client |
| `ui/send/` | Send flow and confirmation |

### Chrome

| Path | Purpose |
|------|---------|
| `services/tron/` | Wallet, API, transactions |
| `services/mesh/` | Relay, privacy, energy broker |
| `services/background-send-service.ts` | Send persistence |

### Worker

| Path | Purpose |
|------|---------|
| `src/index.js` | HTTP API |
| `src/sendQueue.js` | Queued send orchestration |
| `src/feeObligations.js` | Fee tracking and delinquency |
| `src/energyProvider.js` | TronNRG energy rental |

## Relay API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/activate` | POST | Activate a new Tron address |
| `/v1/prepare-sender` | POST | Delegate energy to sender |
| `/v1/register-send-fee` | POST | Register send and fee obligation |
| `/v1/send-status` | GET | Poll send progress |
| `/v1/continue-queued-send` | POST | Resume stalled queue item |
| `/v1/wallet-fee-status` | GET | Fee delinquency check |

Clients authenticate with `Authorization: Bearer` when configured.

## Configuration

Secrets are not committed. Each platform loads keys from local config:

| Platform | Config |
|----------|--------|
| iOS | `Mesh/Info.plist` |
| Android | `app/build.gradle.kts` / `local.properties` |
| Chrome | `.env` |
| Worker | `.dev.vars` |

See `.env.example`, `Info.plist.example`, and `.dev.vars.example` in each subproject.
