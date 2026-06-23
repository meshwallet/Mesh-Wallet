# Chrome extension

Mesh Chrome extension — MV3, React + Vite, `@crxjs/vite-plugin`.

## Architecture

```
extension/chrome/src/
├── background/       # Service worker: send polling, alarms
├── popup/            # Toolbar popup entry
├── sidepanel/        # Side panel entry (primary UI)
├── core/             # Config, storage, types, l10n
├── services/
│   ├── tron/         # TronGrid, wallet, transactions
│   └── mesh/         # Relay client, privacy sends, energy broker
└── views/            # React screens
```

## Key flows

- **Onboarding**: BIP-39 wallet create/restore → local encrypted storage
- **Send**: Build TRC-20 transfer → optional privacy hops → relay registration → poll status
- **Receive**: HD slot addresses from privacy service

## Config

`src/core/config.ts` — relay URL, treasury, router contract, TronGrid keys. For local dev, point `relayUrl` at `wrangler dev` tunnel.

## Permissions

Manifest host permissions are limited to:

- `https://api.trongrid.io/*`
- `https://mesh-sponsorship-relay.meshwallet.workers.dev/*` (or your staging relay)

No analytics or remote-config domains.

## Build

```sh
npm ci
npm run dev     # HMR development
npm run build   # dist/ for store submission
```

Load unpacked from `dist/` in Chrome.
