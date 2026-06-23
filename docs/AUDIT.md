# Audit guide

This document helps reviewers scope a security audit of the Mesh open-source release.

## Audit objectives

1. Verify that **private keys and mnemonics never leave the device** through app code paths.
2. Confirm **transaction integrity**: amount, recipient, and fee shown to the user match signed transactions.
3. Review **sponsorship relay** interactions for fee manipulation or unauthorized signing.
4. Review network calls: only TronGrid, sponsorship relay, and documented public endpoints.

## Recommended review order

### 1. Cryptography & key management

| Platform | Primary paths |
|----------|----------------|
| iOS | `mobile/ios/Mesh/Core/MeshWalletService.swift`, `MeshPasscodeStore.swift`, `MeshSecureStorage.swift` |
| Android | `mobile/android/app/src/main/java/com/mesh/wallet/core/session/`, `data/` |
| Chrome | `extension/chrome/src/services/tron/wallet-service.ts`, `core/storage/` |

Check: BIP-39 derivation, Tron address generation, secure erase, passcode hashing.

### 2. Transaction signing

| Platform | Primary paths |
|----------|----------------|
| iOS | `MeshBackgroundSendService.swift`, `MeshTronTransactionService.swift` |
| Android | `domain/tron/`, `ui/send/` |
| Chrome | `services/send-handoff-service.ts`, `services/tron/transaction-service.ts` |

Check: USDT contract calls, fee deduction, multi-hop privacy sends, replay protection.

### 3. Network & relay

| Component | Path |
|-----------|------|
| Relay client (Chrome) | `extension/chrome/src/services/mesh/relay-client.ts` |
| Relay client (iOS) | `mobile/ios/Mesh/Core/MeshRelayClient.swift` (or equivalent) |
| Worker | `worker/mesh-sponsorship-worker/src/` |

Check: TLS-only endpoints, auth header handling, no sensitive payloads in relay requests.

### 4. UI confirmation flows

Ensure every send path passes through a review/confirm step with explicit amount and recipient.

## Build reproducibility

See [BUILD-REPRODUCIBILITY.md](BUILD-REPRODUCIBILITY.md) for version-pinned builds.

## Contact

Audit questions: **support@meshwallet.app**
