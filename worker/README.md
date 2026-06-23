# Worker

Sponsorship relay and on-chain contracts for Mesh Wallet.

| Directory | Description |
|-----------|-------------|
| `mesh-sponsorship-worker/` | Cloudflare Worker — energy delegation, send queue, fee tracking |
| `mesh-contracts/` | Tron `MeshSendRouter` contract |

## Local development

```sh
cd mesh-sponsorship-worker
cp .dev.vars.example .dev.vars
npm ci
npm run dev
```

Point client `relayUrl` at the local Wrangler URL.

Production relay: `mesh-sponsorship-relay.meshwallet.workers.dev`
