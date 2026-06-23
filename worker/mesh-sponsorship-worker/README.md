# Mesh sponsorship relay

Cloudflare Worker that delegates TRX energy for USDT transfers. Clients sign locally; the relay handles network resources and send queue coordination.

## Local development

```sh
npm ci
cp .dev.vars.example .dev.vars
npm run dev
```

Configure secrets in `.dev.vars`. See [SETUP-URL.md](SETUP-URL.md) for pointing clients at a local instance.

## API

| Endpoint | Method | Purpose |
|----------|--------|-------------|
| `/v1/activate` | POST | Activate address |
| `/v1/prepare-sender` | POST | Delegate energy |
| `/v1/register-send-fee` | POST | Register send |
| `/v1/send-status` | GET | Poll status |
| `/v1/continue-queued-send` | POST | Resume queue |
| `/v1/wallet-fee-status` | GET | Fee status |

Full reference: [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)
