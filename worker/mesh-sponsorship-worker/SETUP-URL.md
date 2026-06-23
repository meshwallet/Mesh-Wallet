# Local relay setup

## Start worker

```sh
cd worker/mesh-sponsorship-worker
npm ci
cp .dev.vars.example .dev.vars
npm run dev
```

Note the local URL (typically `http://127.0.0.1:8787`).

## Point clients

| Platform | Config |
|----------|--------|
| Chrome | `VITE_RELAY_URL` in `extension/chrome/.env` |
| Android | `RELAY_URL` in `app/build.gradle.kts` |
| iOS | `MESH_SPONSORSHIP_RELAY_URL` in `Info.plist` |

## Secrets

Fill in `.dev.vars`:

```
MESH_OPS_TRON_PRIVATE_KEY=
RELAY_AUTH_SECRET=
TRONGRID_API_KEY=
```
