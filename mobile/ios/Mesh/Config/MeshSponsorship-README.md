# Mesh network sponsorship (USDT-only UX)

Users see fixed **send fees in USDT**. Mesh pays Tron **Energy** from the ops wallet via TronNRG rental.

## iOS (`Info.plist`)

| Key | Status | Purpose |
|-----|--------|---------|
| `MESH_FEE_TREASURY_ADDRESS` | Set | USDT send fees (2 / 5 / 10) |
| `MESH_SEND_ROUTER_ADDRESS` | After deploy | `MeshSendRouter` for direct sends (98 + 2 in one tx) |
| `MESH_SPONSORSHIP_RELAY_URL` | **Set after deploy** | Worker base URL |
| `MESH_RELAY_AUTH_SECRET` | Optional | Bearer token if worker uses `RELAY_AUTH_SECRET` |

## Deploy worker

See `mesh-sponsorship-worker/README.md`:

```bash
cd mesh-sponsorship-worker
npm install
npx wrangler secret put MESH_OPS_TRON_PRIVATE_KEY
npx wrangler deploy
```

Paste deploy URL into `MESH_SPONSORSHIP_RELAY_URL`.

## Ops wallet

- **Not** the treasury USDT address and **not** the user's wallet.
- Keep **liquid TRX** on ops for TronNRG rentals (~4–8 TRX per prepare), account activation (1 TRX), and bandwidth top-up (3 TRX) when needed.
- Private key only in `wrangler secret` — never in the iOS app.
- **Direct send ($2):** when `MESH_SEND_ROUTER_ADDRESS` is set, one router tx splits USDT to recipient + treasury (no second fee transfer).
- **Private send** still uses the legacy multi-hop path.

## User-visible fees (`MeshSendFees.swift`)

| Mode | Fee |
|------|-----|
| Direct | 2 USDT |
| Standard | 5 USDT |
| Maximum | 10 USDT |
