/** Resolve a public/ asset URL inside the Chrome extension (or dev server). */
export function extensionAsset(path: string): string {
  const normalized = path.replace(/^\//, '');
  if (typeof chrome !== 'undefined' && chrome.runtime?.getURL) {
    return chrome.runtime.getURL(normalized);
  }
  return `/${normalized}`;
}

/** Version from manifest.json (single source of truth for UI). */
export function getExtensionVersion(): string {
  if (typeof chrome !== 'undefined' && chrome.runtime?.getManifest) {
    return chrome.runtime.getManifest().version;
  }
  return import.meta.env.VITE_EXTENSION_VERSION ?? '0.0.0';
}
