/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_TRONGRID_API_KEYS?: string;
  readonly VITE_RELAY_URL?: string;
  readonly VITE_RELAY_AUTH_SECRET?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
