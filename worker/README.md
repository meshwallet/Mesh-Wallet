# Worker (source only)

This folder contains the **Mesh sponsorship relay** and **on-chain contracts** as readable source for audit and local development.

## What this repo is for

- Review server-side relay logic alongside the mobile and extension clients
- Run `wrangler dev` locally when testing against a dev relay URL
- Change worker code freely inside this monorepo

## What this repo is **not** for

- **Do not** `wrangler deploy` or publish to Cloudflare from this public tree
- **Do not** commit ops keys, `wrangler secret` values, or production KV namespace IDs

Production relay (`mesh-sponsorship-relay.meshwallet.workers.dev`) is operated separately. Store builds already point at that URL; this repository only ships the source.

## Layout

| Path | Purpose |
|------|---------|
| `mesh-sponsorship-worker/` | Cloudflare Worker relay (TRX energy / send queue) |
| `mesh-contracts/` | Tron `MeshSendRouter` contract sources |

## Local dev

```sh
cd mesh-sponsorship-worker
npm ci
npm run dev
```

Point app `relayUrl` / `RELAY_URL` at the local `wrangler dev` URL — not production.
