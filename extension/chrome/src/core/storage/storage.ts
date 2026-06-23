const STORAGE_PREFIX = 'mesh.';

export async function storageGet<T>(key: string): Promise<T | null> {
  const result = await chrome.storage.local.get(STORAGE_PREFIX + key);
  return (result[STORAGE_PREFIX + key] as T) ?? null;
}

export async function storageSet(key: string, value: unknown): Promise<void> {
  await chrome.storage.local.set({ [STORAGE_PREFIX + key]: value });
}

export async function storageRemove(key: string): Promise<void> {
  await chrome.storage.local.remove(STORAGE_PREFIX + key);
}

export async function storageGetRaw<T>(key: string): Promise<T | null> {
  const result = await chrome.storage.local.get(key);
  return (result[key] as T) ?? null;
}

export async function storageSetRaw(key: string, value: unknown): Promise<void> {
  await chrome.storage.local.set({ [key]: value });
}

export async function storageRemoveRaw(key: string): Promise<void> {
  await chrome.storage.local.remove(key);
}

export const StorageKeys = {
  onboardingComplete: 'wallet.onboarding.complete',
  walletsList: 'wallets.list',
  activeWalletId: 'wallets.activeId',
  passcodeEnabled: 'passcode.enabled',
  passcodeHash: 'passcode.hash',
  passcodeSalt: 'passcode.salt',
  language: 'app.language',
  pendingSends: 'pendingSends.v1',
  balanceCache: (walletId: string) => `wallet.balance.cached.${walletId}`,
  mnemonic: (walletId: string) => `tron.mnemonic.${walletId}`,
  privateKey: (walletId: string) => `tron.privatekey.${walletId}`,
  passphrase: (walletId: string) => `tron.passphrase.${walletId}`,
  privacy: (walletId: string, suffix: string) => `privacy.${walletId}.${suffix}`,
} as const;
