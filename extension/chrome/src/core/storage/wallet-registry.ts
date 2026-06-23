import { v4 as uuidv4 } from 'uuid';
import type { StoredWallet, WalletImportKind } from '../types';
import { storageGet, storageSet, storageRemove, StorageKeys } from './storage';
import { PrivacyStore } from './privacy-store';

export const WalletRegistry = {
  async getWallets(): Promise<StoredWallet[]> {
    return (await storageGet<StoredWallet[]>(StorageKeys.walletsList)) ?? [];
  },

  async getActiveWalletId(): Promise<string | null> {
    const wallets = await this.getWallets();
    if (wallets.length === 0) return null;
    const activeId = await storageGet<string>(StorageKeys.activeWalletId);
    if (activeId && wallets.some((w) => w.id === activeId)) return activeId;
    return wallets[0]?.id ?? null;
  },

  async getWallet(id: string): Promise<StoredWallet | undefined> {
    return (await this.getWallets()).find((w) => w.id === id);
  },

  async hasAnyWallet(): Promise<boolean> {
    return (await this.getWallets()).length > 0;
  },

  async setActiveWallet(id: string): Promise<void> {
    const wallets = await this.getWallets();
    if (!wallets.some((w) => w.id === id)) return;
    await storageSet(StorageKeys.activeWalletId, id);
    const wallet = wallets.find((w) => w.id === id);
    if (wallet?.importKind === 'mnemonic') {
      await PrivacyStore.ensureDefaultReceiveSetup(id);
    }
  },

  suggestedName(count: number): string {
    return count === 0 ? 'Main wallet' : `Wallet ${count + 1}`;
  },

  isWalletNameTaken(name: string, excludingWalletId?: string, wallets?: StoredWallet[]): boolean {
    const normalized = name.trim().toLowerCase();
    if (!normalized) return false;
    const list = wallets ?? [];
    return list.some(
      (wallet) => wallet.id !== excludingWalletId
        && wallet.name.trim().toLowerCase() === normalized,
    );
  },

  uniqueAvailableName(existingCount: number, wallets?: StoredWallet[]): string {
    const list = wallets ?? [];
    let count = existingCount;
    const limit = existingCount + 100;
    while (count < limit) {
      const candidate = this.suggestedName(count);
      if (!this.isWalletNameTaken(candidate, undefined, list)) {
        return candidate;
      }
      count += 1;
    }
    return `Wallet ${uuidv4().slice(0, 6)}`;
  },

  resolveDisplayName(name: string | undefined, wallets: StoredWallet[]): string {
    const trimmed = name?.trim().slice(0, 32);
    if (trimmed) {
      if (this.isWalletNameTaken(trimmed, undefined, wallets)) {
        throw new Error('error.wallet.name.taken');
      }
      return trimmed;
    }
    return this.uniqueAvailableName(wallets.length, wallets);
  },

  async registerWallet(params: {
    address: string;
    name?: string;
    importKind: WalletImportKind;
    mnemonic?: string[];
    privateKeyHex?: string;
  }): Promise<string> {
    const wallets = await this.getWallets();
    const existing = wallets.find((w) => w.address === params.address.trim());
    if (existing) {
      await this.applyCredentials(existing.id, params);
      await this.setActiveWallet(existing.id);
      return existing.id;
    }

    const id = uuidv4();
    const name = this.resolveDisplayName(params.name, wallets);
    const entry: StoredWallet = {
      id,
      name,
      address: params.address.trim(),
      createdAt: new Date().toISOString(),
      importKind: params.importKind,
    };

    await this.applyCredentials(id, params);
    wallets.push(entry);
    await storageSet(StorageKeys.walletsList, wallets);
    await this.setActiveWallet(id);
    return id;
  },

  async applyCredentials(
    walletId: string,
    params: {
      importKind: WalletImportKind;
      mnemonic?: string[];
      privateKeyHex?: string;
    },
  ): Promise<void> {
    if (params.importKind === 'mnemonic' && params.mnemonic) {
      await storageRemove(StorageKeys.privateKey(walletId));
      await storageSet(StorageKeys.mnemonic(walletId), params.mnemonic.join(' '));
    } else if (params.importKind === 'privateKey' && params.privateKeyHex) {
      await storageRemove(StorageKeys.mnemonic(walletId));
      await storageSet(StorageKeys.privateKey(walletId), params.privateKeyHex.replace(/^0x/i, ''));
    }
  },

  async updateWalletName(id: string, name: string): Promise<boolean> {
    const trimmed = name.trim().slice(0, 32);
    if (!trimmed) return false;
    const wallets = await this.getWallets();
    if (this.isWalletNameTaken(trimmed, id, wallets)) return false;
    const idx = wallets.findIndex((w) => w.id === id);
    if (idx < 0) return false;
    wallets[idx].name = trimmed;
    await storageSet(StorageKeys.walletsList, wallets);
    return true;
  },

  async removeWallet(id: string): Promise<void> {
    const wallets = (await this.getWallets()).filter((w) => w.id !== id);
    await storageRemove(StorageKeys.mnemonic(id));
    await storageRemove(StorageKeys.privateKey(id));
    await storageRemove(StorageKeys.passphrase(id));
    await storageRemove(StorageKeys.balanceCache(id));
    await PrivacyStore.clearWalletData(id);
    await storageSet(StorageKeys.walletsList, wallets);
    if (wallets.length === 0) {
      await storageRemove(StorageKeys.activeWalletId);
      await storageRemove(StorageKeys.onboardingComplete);
    } else {
      const activeId = await storageGet<string>(StorageKeys.activeWalletId);
      if (activeId === id) await this.setActiveWallet(wallets[0].id);
    }
  },
};

export const WalletSession = {
  async hasActiveWallet(): Promise<boolean> {
    const complete = await storageGet<boolean>(StorageKeys.onboardingComplete);
    return !!complete && (await WalletRegistry.hasAnyWallet());
  },

  async markOnboardingComplete(): Promise<void> {
    await storageSet(StorageKeys.onboardingComplete, true);
  },

  async resetOnboarding(): Promise<void> {
    await storageRemove(StorageKeys.onboardingComplete);
  },
};
