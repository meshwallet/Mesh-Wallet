import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { crx } from '@crxjs/vite-plugin';
import manifest from './manifest.config';

import manifest from './manifest.config';

export default defineConfig({
  plugins: [react(), crx({ manifest })],
  resolve: {
    alias: {
      '@': '/src',
      buffer: 'buffer/',
    },
  },
  define: {
    global: 'globalThis',
    'import.meta.env.VITE_EXTENSION_VERSION': JSON.stringify(manifest.version),
  },
  optimizeDeps: {
    include: ['buffer'],
  },
  build: {
    rollupOptions: {
      input: {
        sidepanel: 'src/sidepanel/index.html',
        popup: 'src/popup/index.html',
      },
    },
  },
});
