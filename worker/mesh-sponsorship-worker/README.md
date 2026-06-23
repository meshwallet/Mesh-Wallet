# Mesh sponsorship relay

Cloudflare Worker source: before each USDT transfer it rents **Energy** via TronNRG from the Mesh ops wallet. Clients never need to hold TRX.

> **Open-source policy:** this tree is for **audit and local dev only**. Do **not** deploy to Cloudflare from the public GitHub repo. Production runs on the existing relay URL configured in the apps.

## Local development

```bash
cd worker/mesh-sponsorship-worker
npm ci
npm run dev
```

Use the printed `http://localhost:8787` (or tunnel URL) as `relayUrl` / `MESH_SPONSORSHIP_RELAY_URL` while testing.

For secrets in local dev, use a `.dev.vars` file (gitignored) — never commit keys:

```
MESH_OPS_TRON_PRIVATE_KEY=<hex>
RELAY_AUTH_SECRET=<optional>
TRONGRID_API_KEY=<optional>
```

## API

### `POST /v1/prepare-sender`

```json
{ "address": "TSender…", "toAddress": "TRecipient…" }
```

- `address` — who signs the USDT transfer
- `toAddress` — recipient (used to pick 4 vs 8 TRX Energy)

The worker can activate sender/recipient (1 TRX from ops) if the address is new on Tron.

Success response:

```json
{
  "ok": true,
  "energy": 65000,
  "trxPaid": 4,
  "paymentTx": "…",
  "delegationTx": "…"
}
```

### `GET /v1/health`

Liveness check.

### Send fee enforcement

| Endpoint | Purpose |
|----------|---------|
| `POST /v1/register-send-fee` | Register obligation when send starts |
| `GET /v1/wallet-fee-status?address=` | `delinquent: true` if fee missing |
| `POST /v1/clear-wallet-delinquent` | Clear flag after user pays treasury |

Cron scans KV obligations and TronGrid history. Pre-signed fee txs can be broadcast after the main send confirms.

## Energy (TronNRG)

| Variable | Default |
|----------|---------|
| `TRONNRG_API_BASE` | `https://api.tronnrg.com` |

| Case | TRX | Energy |
|------|-----|--------|
| Recipient already has USDT | 4 | 65,000 |
| First USDT to address | 8 | 130,000 |

## Treasury

USDT fees go to `MESH_FEE_TREASURY_ADDRESS` in the apps — separate from ops TRX.

## Optional client auth

If `RELAY_AUTH_SECRET` is set:

`Authorization: Bearer <secret>`
