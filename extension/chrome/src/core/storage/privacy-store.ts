import { CONFIG } from '../config';
import { storageGet, storageSet, storageRemove, StorageKeys } from './storage';

const SLOT_COUNT = CONFIG.walletReceiveSlotCount;

function key(walletId: string, suffix: string): string {
  return StorageKeys.privacy(walletId, suffix);
}

export const PrivacyStore = {
  slotCount: SLOT_COUNT,

  async ensureDefaultReceiveSetup(walletId: string): Promise<void> {
    const countKey = key(walletId, 'activeReceiveAddressCount');
    const count = await storageGet<number>(countKey);
    if (count == null) await storageSet(countKey, 1);
  },

  async activeReceiveAddressCount(walletId: string): Promise<number> {
    await this.ensureDefaultReceiveSetup(walletId);
    const count = (await storageGet<number>(key(walletId, 'activeReceiveAddressCount'))) ?? 1;
    return Math.max(1, Math.min(count, SLOT_COUNT));
  },

  async setActiveReceiveAddressCount(walletId: string, count: number): Promise<void> {
    await storageSet(key(walletId, 'activeReceiveAddressCount'), Math.max(1, Math.min(count, SLOT_COUNT)));
  },

  async hiddenSlotIndices(walletId: string): Promise<Set<number>> {
    const raw = (await storageGet<number[]>(key(walletId, 'hiddenReceiveSlotIndices'))) ?? [];
    return new Set(raw.filter((i) => i > 0));
  },

  async visibleSlotIndices(walletId: string): Promise<number[]> {
    const count = await this.activeReceiveAddressCount(walletId);
    const hidden = await this.hiddenSlotIndices(walletId);
    return Array.from({ length: count }, (_, i) => i).filter((i) => !hidden.has(i));
  },

  async addReceiveAddress(walletId: string): Promise<number | null> {
    const current = await this.activeReceiveAddressCount(walletId);
    const hidden = await this.hiddenSlotIndices(walletId);
    for (let i = 1; i < current; i++) {
      if (hidden.has(i)) {
        hidden.delete(i);
        await storageSet(key(walletId, 'hiddenReceiveSlotIndices'), [...hidden].sort());
        return i;
      }
    }
    if (current >= SLOT_COUNT) return null;
    await this.setActiveReceiveAddressCount(walletId, current + 1);
    return current;
  },

  async removeReceiveSlot(walletId: string, index: number): Promise<boolean> {
    if (index <= 0) return false;
    const hidden = await this.hiddenSlotIndices(walletId);
    hidden.add(index);
    await storageSet(key(walletId, 'hiddenReceiveSlotIndices'), [...hidden].sort());
    await this.setReceiveSlotName(walletId, index, null);
    const selected = await this.selectedSlotIndex(walletId);
    if (selected === index) await this.setSelectedSlotIndex(walletId, 0);
    return true;
  },

  async receiveSlotName(walletId: string, index: number): Promise<string | null> {
    return storageGet<string>(key(walletId, `receiveSlotName.${index}`));
  },

  async setReceiveSlotName(walletId: string, index: number, name: string | null): Promise<void> {
    const k = key(walletId, `receiveSlotName.${index}`);
    if (name?.trim()) await storageSet(k, name.trim().slice(0, 24));
    else await storageRemove(k);
  },

  slotDisplayTitle(index: number, customName?: string | null): string {
    if (customName?.trim()) return customName.trim();
    return index === 0 ? 'Main address' : `Address ${index + 1}`;
  },

  async selectedSlotIndex(walletId: string): Promise<number> {
    return (await storageGet<number>(key(walletId, 'selectedReceiveSlot'))) ?? 0;
  },

  async setSelectedSlotIndex(walletId: string, index: number): Promise<void> {
    await storageSet(key(walletId, 'selectedReceiveSlot'), index);
  },

  async clearWalletData(walletId: string): Promise<void> {
    const suffixes = [
      'activeReceiveAddressCount',
      'hiddenReceiveSlotIndices',
      'selectedReceiveSlot',
    ];
    for (const s of suffixes) await storageRemove(key(walletId, s));
    for (let i = 0; i < SLOT_COUNT; i++) {
      await storageRemove(key(walletId, `receiveSlotName.${i}`));
    }
  },
};
