# Local relay URL (dev only)

This guide is for **local development** with `wrangler dev`. Production deploy is **out of scope** for the public repository.

## 1. Start the worker locally

```bash
cd worker/mesh-sponsorship-worker
npm ci
npm run dev
```

Wrangler prints a local URL, typically `http://127.0.0.1:8787`.

## 2. Point the app at local relay

**Chrome** — `extension/chrome/src/core/config.ts`:

```ts
relayUrl: 'http://127.0.0.1:8787',
```

**Android** — `RELAY_URL` in `app/build.gradle.kts` (debug flavor) or local override.

**iOS** — `MESH_SPONSORSHIP_RELAY_URL` in `Info.plist` for debug builds.

## 3. Secrets for local dev

Create `.dev.vars` in `mesh-sponsorship-worker/` (gitignored):

```
MESH_OPS_TRON_PRIVATE_KEY=<64 hex, test ops wallet only>
RELAY_AUTH_SECRET=<optional>
TRONGRID_API_KEY=<optional>
```

Restart `npm run dev` after changing `.dev.vars`.

## Production

Store and extension builds use the deployed relay at `mesh-sponsorship-relay.meshwallet.workers.dev`. That environment is **not** updated from this GitHub repo.
