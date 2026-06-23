import { createContext, useContext, useState, useEffect, useCallback, type ReactNode } from 'react';
import type { StoredWallet, WalletTransaction, PendingSendRecord, Language, ReceiveSlot } from '@/core/types';
import { WalletRegistry, WalletSession } from '@/core/storage/wallet-registry';
import { PasscodeStore } from '@/core/storage/passcode';
import { PrivacyStore } from '@/core/storage/privacy-store';
import { storageGet, storageSet, StorageKeys } from '@/core/storage/storage';
import { PendingSendStore } from '@/services/pending-send-store';
import { SendPollService } from '@/services/send-poll-service';
import { BackgroundSendService } from '@/services/background-send-service';
import { PrivacyService } from '@/services/mesh/privacy-service';
import {
  displayBalance,
  mergeHistoryForSlot,
  pendingRecordsForWallet,
  releaseOrphanPendingHolds,
  withDayLabels,
} from '@/services/wallet-activity-service';
import { TronAPI, tronTxToWalletTransaction } from '@/services/tron/tron-api';
interface AppState {
  isLoading: boolean;
  isUnlocked: boolean;
  hasWallet: boolean;
  wallets: StoredWallet[];
  activeWallet: StoredWallet | null;
  balance: number;
  walletTotalBalance: number;
  receiveSlots: ReceiveSlot[];
  selectedSlotIndex: number;
  showsMultiAccountChrome: boolean;
  balanceHidden: boolean;
  transactions: WalletTransaction[];
  pendingSends: PendingSendRecord[];
  language: Language;
  refreshWallet: () => Promise<void>;
  setUnlocked: (v: boolean) => void;
  setBalanceHidden: (v: boolean) => void;
  setLanguage: (lang: Language) => void;
}

const AppContext = createContext<AppState | null>(null);

export function AppProvider({ children }: { children: ReactNode }) {
  const [isLoading, setIsLoading] = useState(true);
  const [isUnlocked, setUnlocked] = useState(false);
  const [hasWallet, setHasWallet] = useState(false);
  const [wallets, setWallets] = useState<StoredWallet[]>([]);
  const [activeWallet, setActiveWallet] = useState<StoredWallet | null>(null);
  const [balance, setBalance] = useState(0);
  const [walletTotalBalance, setWalletTotalBalance] = useState(0);
  const [receiveSlots, setReceiveSlots] = useState<ReceiveSlot[]>([]);
  const [selectedSlotIndex, setSelectedSlotIndex] = useState(0);
  const [showsMultiAccountChrome, setShowsMultiAccountChrome] = useState(false);
  const [balanceHidden, setBalanceHidden] = useState(false);
  const [transactions, setTransactions] = useState<WalletTransaction[]>([]);
  const [pendingSends, setPendingSends] = useState<PendingSendRecord[]>([]);
  const [language, setLanguageState] = useState<Language>('en');

  const refreshWallet = useCallback(async () => {
    await SendPollService.pollPendingSends();
    await releaseOrphanPendingHolds(
      BackgroundSendService.isHandoffRunning(),
      BackgroundSendService.getActiveSendID(),
    );

    const ws = await WalletRegistry.getWallets();
    setWallets(ws);
    const activeId = await WalletRegistry.getActiveWalletId();
    const active = activeId ? ws.find((w) => w.id === activeId) ?? null : null;
    setActiveWallet(active);

    if (!active) return;

    const [rawSlots, slotIndex, pending] = await Promise.all([
      PrivacyService.listReceiveSlotsWithBalances(active.id),
      PrivacyStore.selectedSlotIndex(active.id),
      PendingSendStore.getAll(),
    ]);

    const walletPending = pendingRecordsForWallet(pending, active.id);
    const nextIndex = rawSlots.some((slot) => slot.index === slotIndex) ? slotIndex : 0;
    const focusedSlot = rawSlots.find((slot) => slot.index === nextIndex) ?? rawSlots[0];
    const focusedAddress = focusedSlot?.address ?? active.address;

    const slots = rawSlots.map((slot) => {
      const chain = slot.balanceUSDT ?? 0;
      return {
        ...slot,
        balanceUSDT: displayBalance(chain, active.id, slot.address, walletPending),
      };
    });

    const totalBal = slots.reduce((sum, slot) => sum + (slot.balanceUSDT ?? 0), 0);
    const focusedBal = slots.find((slot) => slot.index === nextIndex)?.balanceUSDT ?? 0;
    const multiAccount = active.importKind === 'mnemonic' && rawSlots.length > 1;

    const chainTxs = await TronAPI.fetchTransactions(focusedAddress, 50);
    const chainWalletTxs = chainTxs.map((tx) => tronTxToWalletTransaction(tx, focusedAddress));
    const merged = withDayLabels(
      mergeHistoryForSlot(chainWalletTxs, walletPending, focusedAddress),
    );

    setReceiveSlots(slots);
    setSelectedSlotIndex(nextIndex);
    setWalletTotalBalance(totalBal);
    setBalance(focusedBal);
    setShowsMultiAccountChrome(multiAccount);
    setTransactions(merged);
    setPendingSends(
      walletPending.filter((record) => record.fromAddress.trim().toLowerCase()
        === focusedAddress.trim().toLowerCase()
        || !record.fromAddress.trim()),
    );
  }, []);

  useEffect(() => {
    (async () => {
      const lang = await storageGet<Language>(StorageKeys.language);
      if (lang) setLanguageState(lang);
      const hw = await WalletSession.hasActiveWallet();
      setHasWallet(hw);
      if (hw) await refreshWallet();
      setIsLoading(false);
    })();
  }, [refreshWallet]);

  useEffect(() => {
    if (!hasWallet || !isUnlocked) return;
    const interval = setInterval(refreshWallet, 5_000);
    return () => clearInterval(interval);
  }, [hasWallet, isUnlocked, refreshWallet]);

  const setLanguage = async (lang: Language) => {
    setLanguageState(lang);
    await storageSet(StorageKeys.language, lang);
  };

  return (
    <AppContext.Provider
      value={{
        isLoading,
        isUnlocked,
        hasWallet,
        wallets,
        activeWallet,
        balance,
        walletTotalBalance,
        receiveSlots,
        selectedSlotIndex,
        showsMultiAccountChrome,
        balanceHidden,
        transactions,
        pendingSends,
        language,
        refreshWallet,
        setUnlocked,
        setBalanceHidden,
        setLanguage,
      }}
    >
      {children}
    </AppContext.Provider>
  );
}

export function useApp() {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error('useApp must be used within AppProvider');
  return ctx;
}

export { PasscodeStore, WalletSession, WalletRegistry };
