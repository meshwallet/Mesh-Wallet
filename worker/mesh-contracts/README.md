# Mesh Send Router (Tron)

One on-chain call splits USDT: **amount → recipient**, **fee → treasury**.

Source in this repo is for **audit**. Contract deploy to Tron mainnet is handled outside the public GitHub tree.

## User flow

1. One-time (per wallet): `USDT.approve(router, unlimited)` — Mesh sponsors energy.
2. Each send: `router.sendWithFee(recipient, amount, fee)` — one sponsored transaction.

## USDT mainnet

`TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`

## Compile (local)

```bash
cd worker/mesh-contracts
npm install
node scripts/compile.js
```

Output: `build/MeshSendRouter.json`
