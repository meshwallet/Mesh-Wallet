# Cloudflare sponsorship worker

Source for the Mesh sponsorship relay — included for **audit and local testing**. This public repository does **not** deploy to Cloudflare.

## API surface (used by clients)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v1/activate` | POST | Activate new Tron address |
| `/v1/prepare-sender` | POST | Delegate resources to sender |
| `/v1/register-send-fee` | POST | Register queued send + fee |
| `/v1/send-status` | GET | Poll send progress |
| `/v1/continue-queued-send` | POST | Resume stalled queue item |
| `/v1/wallet-fee-status` | GET | Delinquent fee check |

Clients authenticate with `Authorization: Bearer <relayAuthSecret>`.

Production URL (already in apps): `https://mesh-sponsorship-relay.meshwallet.workers.dev`

## Local development only

```sh
cd worker/mesh-sponsorship-worker
npm ci
npm run dev
```

Point app `relayUrl` / `RELAY_URL` at the local URL. See [worker/mesh-sponsorship-worker/SETUP-URL.md](../worker/mesh-sponsorship-worker/SETUP-URL.md).

Use `.dev.vars` for local secrets — never commit ops keys or run `wrangler deploy` from this repo.

## Contracts

`worker/mesh-contracts/` — Tron `MeshSendRouter` sources for review. On-chain deploy is handled outside this public tree.

## Audit focus

Review `worker/mesh-sponsorship-worker/src/` for:

- Relay auth and request validation
- Fee obligation / delinquency logic
- Energy delegation and queue handling
- No collection of user keys or mnemonics
