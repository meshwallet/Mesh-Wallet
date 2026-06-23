import { CONFIG } from '@/core/config';
import type { ReceiveSlot, PrivacySpendSource } from '@/core/types';
import { PrivacyStore } from '@/core/storage/privacy-store';
import {
  WalletCredentials,
  WalletService,
  receiveDerivationPath,
} from '@/services/tron/wallet-service';
import { TronAPI } from '@/services/tron/tron-api';
import { TransactionService } from '@/services/tron/transaction-service';
import { EnergyBroker } from '@/services/mesh/relay-client';

export const PrivacyService = {
  async listReceiveSlots(walletId?: string): Promise<ReceiveSlot[]> {
    const creds = await WalletCredentials.resolve(walletId);
    const hd = await WalletService.supportsHDFeatures(creds.walletId);

    if (!hd) {
      return [{
        index: 0,
        address: creds.address,
        title: 'Main address',
        derivationPath: receiveDerivationPath(0),
        balanceUSDT: null,
      }];
    }

    await PrivacyStore.ensureDefaultReceiveSetup(creds.walletId);
    const indices = await PrivacyStore.visibleSlotIndices(creds.walletId);
    const slots: ReceiveSlot[] = [];

    for (const index of indices) {
      const address = WalletService.deriveReceiveAddress(creds.mnemonic!, index);
      const customName = await PrivacyStore.receiveSlotName(creds.walletId, index);
      slots.push({
        index,
        address,
        title: PrivacyStore.slotDisplayTitle(index, customName),
        derivationPath: receiveDerivationPath(index),
        balanceUSDT: null,
      });
    }
    return slots;
  },

  async listReceiveSlotsWithBalances(walletId?: string): Promise<ReceiveSlot[]> {
    const slots = await this.listReceiveSlots(walletId);
    const updated = await Promise.all(
      slots.map(async (slot) => ({
        ...slot,
        balanceUSDT: await TronAPI.fetchUSDTBalance(slot.address),
      })),
    );
    return updated.sort((a, b) => a.index - b.index);
  },

  async totalUSDTBalance(walletId?: string): Promise<number> {
    const slots = await this.listReceiveSlotsWithBalances(walletId);
    return slots.reduce((sum, s) => sum + (s.balanceUSDT ?? 0), 0);
  },

  async resolveSpendSourceFromSlot(
    slotIndex: number,
    requiredAmount: number,
    walletId?: string,
    options?: { skipBalanceVerification?: boolean },
  ): Promise<PrivacySpendSource> {
    const creds = await WalletCredentials.resolve(walletId);
    const index = Math.min(Math.max(slotIndex, 0), CONFIG.walletReceiveSlotCount - 1);
    const address = creds.mnemonic
      ? WalletService.deriveReceiveAddress(creds.mnemonic, index)
      : creds.address;
    if (!options?.skipBalanceVerification) {
      const balance = await TronAPI.fetchUSDTBalance(address);
      if (balance == null) throw new Error('Could not verify USDT balance.');
      if (balance < requiredAmount) {
        throw new Error(`Not enough USDT on ${PrivacyStore.slotDisplayTitle(index)}.`);
      }
    }
    return {
      address,
      derivationPath: receiveDerivationPath(index),
      accountIndex: index,
      isPrivateSpend: index > 0,
    };
  },

  async fetchActivityHistory(walletId?: string, limit = 50) {
    const creds = await WalletCredentials.resolve(walletId);
    const hd = await WalletService.supportsHDFeatures(creds.walletId);

    if (!hd) {
      return TronAPI.fetchTransactions(creds.address, limit);
    }

    const indices = await PrivacyStore.visibleSlotIndices(creds.walletId);
    const perAddr = Math.min(20, Math.max(6, Math.floor(limit / indices.length) + 2));
    const batches = await Promise.all(
      indices.map(async (index) => {
        const address = WalletService.deriveReceiveAddress(creds.mnemonic!, index);
        try {
          return await TronAPI.fetchTransactions(address, perAddr);
        } catch {
          return [];
        }
      }),
    );

    const seen = new Set<string>();
    return batches
      .flat()
      .filter((tx) => {
        if (seen.has(tx.txID)) return false;
        seen.add(tx.txID);
        return true;
      })
      .sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime())
      .slice(0, limit);
  },

  async consolidateSlotsToMain(
    walletId?: string,
    onProgress?: (current: number, total: number) => void,
  ): Promise<number> {
    const creds = await WalletCredentials.resolve(walletId);
    if (!creds.mnemonic) throw new Error('HD wallet required');
    const mainAddress = WalletService.deriveReceiveAddress(creds.mnemonic, 0);
    const donors: { index: number; balance: number }[] = [];

    for (let index = 1; index < CONFIG.walletReceiveSlotCount; index++) {
      const address = WalletService.deriveReceiveAddress(creds.mnemonic, index);
      const balance = await TronAPI.fetchUSDTBalance(address);
      if (balance && balance > 0) donors.push({ index, balance });
    }

    donors.sort((a, b) => b.balance - a.balance);
    onProgress?.(0, donors.length);

    let count = 0;
    for (const donor of donors) {
      const source = await this.resolveSpendSourceFromSlot(donor.index, donor.balance, creds.walletId);
      const pk = await WalletCredentials.signingKey(source.derivationPath, creds.walletId);
      await EnergyBroker.ensureSenderReady(source.address, mainAddress);
      await TransactionService.sendUSDT({
        privateKeyHex: pk,
        fromAddress: source.address,
        toAddress: mainAddress,
        amount: donor.balance,
        skipPrepare: true,
      });
      count++;
      onProgress?.(count, donors.length);
      await sleep(1200);
    }
    return count;
  },

  async recoverDeepFundsToMainWallet(
    walletId?: string,
    onProgress?: (progress: { phase: 'scanning'; checked: number; total: number } | { phase: 'transferring'; current: number; total: number }) => void,
  ): Promise<number> {
    const creds = await WalletCredentials.resolve(walletId);
    if (!creds.mnemonic) throw new Error('HD wallet required');
    const total = CONFIG.deepRecoveryScanCount;
    const funded: { index: number; balance: number }[] = [];

    for (let index = 0; index < total; index++) {
      if (index > 0 && index % 4 === 0) await sleep(120);
      const address = WalletService.deriveReceiveAddress(creds.mnemonic, index);
      const balance = await TronAPI.fetchUSDTBalance(address);
      if (balance && balance > 0 && index > 0) {
        funded.push({ index, balance });
      }
      if (index % 4 === 0 || index === total - 1) {
        onProgress?.({ phase: 'scanning', checked: index + 1, total });
      }
    }

    const mainAddress = WalletService.deriveReceiveAddress(creds.mnemonic, 0);
    funded.sort((a, b) => b.balance - a.balance);
    onProgress?.({ phase: 'transferring', current: 0, total: funded.length });

    let count = 0;
    for (const donor of funded) {
      const source = await this.resolveSpendSourceFromSlot(donor.index, donor.balance, creds.walletId);
      const pk = await WalletCredentials.signingKey(source.derivationPath, creds.walletId);
      await EnergyBroker.ensureSenderReady(source.address, mainAddress);
      await TransactionService.sendUSDT({
        privateKeyHex: pk,
        fromAddress: source.address,
        toAddress: mainAddress,
        amount: donor.balance,
        skipPrepare: true,
      });
      count++;
      onProgress?.({ phase: 'transferring', current: count, total: funded.length });
      await sleep(1200);
    }
    return count;
  },

  async resolveSpendSource(requiredAmount: number, walletId?: string): Promise<PrivacySpendSource> {
    const creds = await WalletCredentials.resolve(walletId);
    if (!creds.mnemonic) {
      return this.resolveSpendSourceFromSlot(0, requiredAmount, walletId);
    }

    for (let index = CONFIG.walletReceiveSlotCount - 1; index >= 0; index--) {
      const address = WalletService.deriveReceiveAddress(creds.mnemonic, index);
      const balance = await TronAPI.fetchUSDTBalance(address);
      if (balance != null && balance >= requiredAmount) {
        return {
          address,
          derivationPath: receiveDerivationPath(index),
          accountIndex: index,
          isPrivateSpend: index > 0,
        };
      }
    }

    await this.consolidateSlotsToMain(walletId);
    return this.resolveSpendSourceFromSlot(0, requiredAmount, walletId);
  },
};

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}
