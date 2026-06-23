# Security policy

## Reporting a vulnerability

If you believe you have found a security issue in Mesh, please report it responsibly:

1. **Do not** open a public GitHub issue for exploitable vulnerabilities.
2. Email **support@meshwallet.app** with:
   - Description of the issue
   - Steps to reproduce
   - Impact assessment
   - Proof of concept (if available)

We aim to acknowledge reports within **72 hours**.

## Scope

In scope for this repository:

- Key generation, storage, and signing (`mobile/ios`, `mobile/android`, `extension/chrome`)
- Send/receive flows and transaction construction
- Passcode / biometric gate
- Sponsorship relay API surface (`worker/mesh-sponsorship-worker`)

Out of scope:

- Social engineering against individual users
- Physical device compromise
- Third-party infrastructure (TronGrid, App Store review process)

## Design principles

- **Non-custodial**: Mesh cannot access user keys or funds from this codebase.
- **Zero telemetry in OSS tree**: No analytics SDKs, no remote phrase upload, no Firebase/AppsFlyer in the public source.
- **User confirmation**: Every transfer is shown on a review screen before signing.
- **Minimal attack surface**: USDT on TRC-20 only; no arbitrary contract execution UI.

## Key material

- Mnemonics and private keys are generated and stored on-device.
- iOS: Secure Enclave / Keychain where available.
- Android: Encrypted preferences + hardware-backed keystore when available.
- Chrome: `chrome.storage.local` with extension-isolated origin.

Never commit real mnemonics, private keys, or production relay secrets to this repository.

## Status

Security review and responsible disclosure process are documented at [meshwallet.app/security](https://meshwallet.app/security).
