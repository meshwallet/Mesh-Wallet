import { defineManifest } from '@crxjs/vite-plugin';

export default defineManifest({
  manifest_version: 3,
  name: 'Mesh: USDT Wallet',
  version: '1.0.3',
  description: 'Self-custody USDT wallet on Tron — Mesh for Chrome',
  permissions: ['storage', 'alarms', 'sidePanel'],
  host_permissions: [
    'https://api.trongrid.io/*',
    'https://mesh-sponsorship-relay.meshwallet.workers.dev/*',
  ],
  action: {
    default_popup: 'src/popup/index.html',
    default_title: 'Mesh: USDT Wallet',
    default_icon: {
      '16': 'public/icons/icon16.png',
      '48': 'public/icons/icon48.png',
      '128': 'public/icons/icon128.png',
    },
  },
  side_panel: {
    default_path: 'src/sidepanel/index.html',
  },
  background: {
    service_worker: 'src/background/index.ts',
    type: 'module',
  },
  icons: {
    '16': 'public/icons/icon16.png',
    '48': 'public/icons/icon48.png',
    '128': 'public/icons/icon128.png',
  },
});
