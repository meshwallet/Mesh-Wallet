import { SEND_FEES, networkFee } from '@/core/config';
import type { PendingSendRecord, WalletTransaction } from '@/core/types';
import { addressesMatch } from '@/services/tron/tron-api';
import { pendingSendToTransaction } from '@/utils/transaction-proof';
import { PendingSendStore } from '@/services/pending-send-store';

const BALANCE_TOLERANCE = 0.000001;
const ORPHAN_FAIL_AFTER_MS = 90_000;
const ORPHAN_HOLD_GRACE_MS = 200_000;

function isPlausibleTronTransactionID(txID: string): boolean {
  const hex = txID.trim().toLowerCase();
  return hex.length === 64 && /^[0-9a-f]+$/.test(hex);
}

function rawPendingBalanceHold(record: PendingSendRecord): number {
  if (record.status === 'failed') return 0;
  if (record.status === 'processing') {
    if (!SEND_FEES.chargesOnChainFee) {
      return record.amountUSDT;
    }
    const fee = networkFee();
    return record.amountUSDT + fee;
  }
  return 0;
}

function effectivePendingBalanceHold(
  record: PendingSendRecord,
  chainBalance?: number | null,
): number {
  const raw = rawPendingBalanceHold(record);
  if (raw <= 0 || chainBalance == null) return raw;
  if (record.status !== 'processing') return raw;
  const snapshot = record.chainUSDTAtStart != null
    ? Number.parseFloat(record.chainUSDTAtStart)
    : NaN;
  if (Number.isNaN(snapshot)) return raw;
  const expectedAfterSend = snapshot - record.amountUSDT;
  if (chainBalance <= expectedAfterSend + BALANCE_TOLERANCE) {
    return 0;
  }
  return raw;
}

export function pendingBalanceHold(
  records: PendingSendRecord[],
  walletId: string,
  spendFromAddress = '',
  chainBalance?: number | null,
): number {
  const normalized = spendFromAddress.trim().toLowerCase();
  return records
    .filter((record) => record.walletID === walletId)
    .filter((record) => !normalized
      || addressesMatch(record.fromAddress, normalized))
    .reduce(
      (sum, record) => sum + effectivePendingBalanceHold(record, chainBalance),
      0,
    );
}

export function displayBalance(
  chainBalance: number,
  walletId: string,
  spendFromAddress: string,
  records: PendingSendRecord[],
): number {
  const hold = pendingBalanceHold(records, walletId, spendFromAddress, chainBalance);
  return Math.max(0, chainBalance - hold);
}

function activityPendingDedupeKey(item: WalletTransaction): string {
  const recipient = item.toAddress.trim().toLowerCase();
  const sender = item.fromAddress.trim().toLowerCase();
  return `${sender}|${recipient}|${item.amountUSDT}`;
}

function dedupeTransactionsWithoutTxID(items: WalletTransaction[]): WalletTransaction[] {
  const best = new Map<string, WalletTransaction>();
  for (const item of items) {
    const key = activityPendingDedupeKey(item);
    const existing = best.get(key);
    if (!existing || new Date(item.timestamp) > new Date(existing.timestamp)) {
      best.set(key, item);
    }
  }
  return [...best.values()];
}

function dedupeChainTransactions(chain: WalletTransaction[]): WalletTransaction[] {
  const byTxID = new Map<string, WalletTransaction>();
  const withoutTxID: WalletTransaction[] = [];

  for (const item of chain) {
    const txID = item.txID.trim();
    if (!txID) {
      withoutTxID.push(item);
      continue;
    }
    const existing = byTxID.get(txID);
    if (!existing || new Date(item.timestamp) > new Date(existing.timestamp)) {
      byTxID.set(txID, item);
    }
  }

  return [...dedupeTransactionsWithoutTxID(withoutTxID), ...byTxID.values()];
}

export function dedupeActivityPending(pending: WalletTransaction[]): WalletTransaction[] {
  const grouped = new Map<string, WalletTransaction[]>();

  for (const item of pending) {
    const txID = item.txID.trim();
    const key = txID ? `tx|${txID.toLowerCase()}` : activityPendingDedupeKey(item);
    const list = grouped.get(key) ?? [];
    list.push(item);
    grouped.set(key, list);
  }

  const deduped: WalletTransaction[] = [];
  for (const items of grouped.values()) {
    const processing = items
      .filter((item) => item.transferStatus === 'processing')
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())[0];
    if (processing) {
      deduped.push(processing);
      continue;
    }
    const confirmed = items
      .filter((item) => item.transferStatus === 'confirmed')
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())[0];
    if (confirmed) {
      deduped.push(confirmed);
      continue;
    }
    const failed = items
      .filter((item) => item.transferStatus === 'failed')
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())[0];
    if (failed) deduped.push(failed);
  }

  return deduped;
}

export function pendingSupersededByChain(
  pending: WalletTransaction,
  chain: WalletTransaction[],
): boolean {
  if (pending.kind !== 'sent') return false;
  const pendingTxID = pending.txID.trim();
  if (pendingTxID && chain.some((tx) => tx.txID === pendingTxID)) {
    return true;
  }

  const recipient = pending.toAddress.trim();
  if (!recipient) return false;

  return chain.some((chainTx) => {
    if (chainTx.kind !== 'received') return false;
    if (!addressesMatch(chainTx.toAddress, recipient)) return false;
    const delta = chainTx.amountUSDT - pending.amountUSDT;
    if (delta < -BALANCE_TOLERANCE || delta > BALANCE_TOLERANCE) return false;
    if (!pendingTxID) {
      const deltaMs = Math.abs(
        new Date(chainTx.timestamp).getTime() - new Date(pending.timestamp).getTime(),
      );
      return deltaMs < 900_000;
    }
    return chainTx.txID === pendingTxID;
  });
}

export function mergeActivityHistory(
  chain: WalletTransaction[],
  pending: WalletTransaction[],
): WalletTransaction[] {
  const dedupedChain = dedupeChainTransactions(chain);
  const chainTxIDs = new Set(dedupedChain.map((tx) => tx.txID).filter(Boolean));
  const filteredPending = pending.filter((item) => {
    if (pendingSupersededByChain(item, dedupedChain)) return false;
    if (!item.txID) return true;
    return !chainTxIDs.has(item.txID);
  });
  const dedupedPending = dedupeActivityPending(filteredPending);

  const byTxID = new Map<string, WalletTransaction>();
  const withoutTxID: WalletTransaction[] = [];

  for (const item of [...dedupedPending, ...dedupedChain]) {
    const txID = item.txID.trim();
    if (!txID) {
      withoutTxID.push(item);
    } else {
      byTxID.set(txID, item);
    }
  }

  return [...dedupeTransactionsWithoutTxID(withoutTxID), ...byTxID.values()]
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
}

function chainTransactionsForSlot(
  chain: WalletTransaction[],
  slotAddress: string,
): WalletTransaction[] {
  return chain.filter(
    (tx) => addressesMatch(tx.fromAddress, slotAddress)
      || addressesMatch(tx.toAddress, slotAddress),
  );
}

function pendingActivityForSlot(
  pending: WalletTransaction[],
  slotAddress: string,
): WalletTransaction[] {
  return pending.flatMap((tx) => {
    const fromHere = addressesMatch(tx.fromAddress, slotAddress);
    const toHere = addressesMatch(tx.toAddress, slotAddress);
    if (!fromHere && !toHere) return [];

    if (fromHere) return [tx];

    if (tx.transferStatus === 'failed') return [];
    if (tx.transferStatus === 'processing') {
      if (!isPlausibleTronTransactionID(tx.txID)) return [];
    }
    return [tx];
  });
}

export function mergeHistoryForSlot(
  chain: WalletTransaction[],
  pendingRecords: PendingSendRecord[],
  slotAddress: string,
): WalletTransaction[] {
  const pending = pendingRecords.map((record) => pendingSendToTransaction(record));
  const filteredChain = chainTransactionsForSlot(chain, slotAddress);
  const filteredPending = pendingActivityForSlot(pending, slotAddress);
  return mergeActivityHistory(filteredChain, filteredPending);
}

export function pendingRecordsForWallet(
  records: PendingSendRecord[],
  walletId: string,
): PendingSendRecord[] {
  return records.filter((record) => record.walletID === walletId);
}

/** iOS: releaseOrphanPendingHolds — fail sends that never registered with worker. */
export async function releaseOrphanPendingHolds(
  isHandoffRunning: boolean,
  activeSendID: string | null = null,
): Promise<void> {
  if (isHandoffRunning) return;

  const records = await PendingSendStore.getAll();
  const now = Date.now();
  let changed = false;

  for (const record of records) {
    if (record.status !== 'processing') continue;
    if (record.handoffRegistered || record.workerQueued) continue;
    if (record.txID.trim()) continue;

    const ageMs = now - new Date(record.startedAt).getTime();
    if (record.id === activeSendID && ageMs < ORPHAN_HOLD_GRACE_MS) continue;
    if (ageMs < ORPHAN_HOLD_GRACE_MS && ageMs < ORPHAN_FAIL_AFTER_MS) continue;

    record.status = 'failed';
    record.failedMessage = record.failedMessage
      ?? 'Send did not finish in time. If your USDT balance is unchanged, you can try again.';
    changed = true;
  }

  if (changed) {
    await PendingSendStore.save(records);
  }
}

export function dayLabelFromTimestamp(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) return 'Today';
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'long' });
}

export function withDayLabels(transactions: WalletTransaction[]): WalletTransaction[] {
  return transactions.map((tx) => ({
    ...tx,
    dayLabel: dayLabelFromTimestamp(tx.timestamp),
  }));
}
