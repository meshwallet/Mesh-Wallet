# Security Policy

## Reporting

Email **support@meshwallet.app** with:

- Description of the vulnerability
- Steps to reproduce
- Impact assessment
- Proof of concept, if available

Do not disclose exploitable issues in public GitHub issues.

We aim to acknowledge reports within 72 hours.

## Scope

**In scope**

- Key generation, storage, and signing (`mobile/`, `extension/`)
- Send and receive transaction construction
- Passcode and biometric gate
- Sponsorship relay API (`worker/mesh-sponsorship-worker/`)

**Out of scope**

- Social engineering
- Compromised user devices
- Third-party infrastructure (TronGrid, app stores)

## Principles

- Non-custodial: this codebase cannot access user keys or funds.
- Every send is confirmed on a review screen before signing.
- USDT on TRC-20 only — no arbitrary contract execution surface.

More: [meshwallet.app/security](https://meshwallet.app/security)

Release versions: [versions.json](versions.json).
