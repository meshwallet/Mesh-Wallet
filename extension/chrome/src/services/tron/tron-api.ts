import { CONFIG } from '@/core/config';
import type { WalletTransaction } from '@/core/types';

let keyIndex = 0;
const cooledKeys = new Map<string, number>();

function nextApiKey(): string {
  const keys = [...CONFIG.tronGridApiKeys];
  if (keys.length === 0) return '';
  const now = Date.now();
  for (let i = 0; i < keys.length; i++) {
    const idx = (keyIndex + i) % keys.length;
    const key = keys[idx];
    const cooled = cooledKeys.get(key) ?? 0;
    if (now >= cooled) {
      keyIndex = (idx + 1) % keys.length;
      return key;
    }
  }
  keyIndex = (keyIndex + 1) % keys.length;
  return keys[keyIndex];
}

function markRateLimited(key: string): void {
  cooledKeys.set(key, Date.now() + 45_000);
}

async function tronRequest<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const apiKey = nextApiKey();
  const headers: Record<string, string> = {
    Accept: 'application/json',
    ...(options.headers as Record<string, string>),
  };
  if (apiKey) headers['TRON-PRO-API-KEY'] = apiKey;

  const url = path.startsWith('http') ? path : `${CONFIG.tronGridBase}${path}`;
  const response = await fetch(url, { ...options, headers });

  if (response.status === 429) {
    if (apiKey) markRateLimited(apiKey);
    throw new Error('Rate limited');
  }
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`TronGrid error ${response.status}: ${text.slice(0, 200)}`);
  }
  return response.json() as Promise<T>;
}

interface Trc20HistoryItem {
  transaction_id: string;
  from: string;
  to: string;
  value: string;
  block_timestamp: number;
  token_info?: { symbol?: string };
}

export interface TronTx {
  txID: string;
  fromAddress: string;
  toAddress: string;
  amount: number;
  timestamp: Date;
  direction: 'incoming' | 'outgoing';
}

function parseUSDTBalanceFromTokenMaps(
  tokenMaps: Record<string, string>[] | undefined,
): number | null {
  if (!tokenMaps?.length) return 0;
  for (const tokenMap of tokenMaps) {
    const raw = tokenMap[CONFIG.usdtContract] ?? tokenMap.balance;
    if (raw == null) continue;
    const trimmed = raw.trim();
    if (!trimmed) continue;
    const units = Number.parseInt(trimmed, 10);
    if (Number.isNaN(units)) continue;
    return units / 10 ** CONFIG.tokenDecimals;
  }
  return 0;
}

export const TronAPI = {
  async fetchUSDTBalance(address: string): Promise<number | null> {
    try {
      const data = await tronRequest<{ data?: Record<string, string>[] }>(
        `/v1/accounts/${address}/trc20/balance?contract_address=${CONFIG.usdtContract}&limit=1`,
      );
      return parseUSDTBalanceFromTokenMaps(data.data);
    } catch {
      try {
        const account = await tronRequest<{ data?: { trc20?: Record<string, string>[] }[] }>(
          `/v1/accounts/${address}`,
        );
        return parseUSDTBalanceFromTokenMaps(account.data?.[0]?.trc20);
      } catch {
        return null;
      }
    }
  },

  async isAccountActivated(address: string): Promise<boolean> {
    try {
      const data = await tronRequest<{ data?: Record<string, unknown>[] }>(
        `/v1/accounts/${address}`,
      );
      const account = data.data?.[0];
      if (!account) return false;
      if (account.create_time != null && Number(account.create_time) > 0) return true;
      const balanceSun = Number(account.balance ?? 0);
      return balanceSun >= 1_000_000;
    } catch {
      try {
        const account = await tronRequest<Record<string, unknown>>('/wallet/getaccount', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ address, visible: true }),
        });
        if (!account || Object.keys(account).length === 0) return false;
        if (account.create_time != null && Number(account.create_time) > 0) return true;
        return Number(account.balance ?? 0) >= 1_000_000;
      } catch {
        return false;
      }
    }
  },

  async fetchTRXBalance(address: string): Promise<number> {
    try {
      const account = await tronRequest<Record<string, unknown>>('/wallet/getaccount', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ address, visible: true }),
      });
      return Number(account.balance ?? 0) / 1_000_000;
    } catch {
      return 0;
    }
  },

  async fetchAccountResources(address: string): Promise<{
    energyRemaining: number;
    bandwidthRemaining: number;
    trxBalance: number;
  }> {
    try {
      const [resources, trxBalance] = await Promise.all([
        tronRequest<{
          EnergyLimit?: number;
          EnergyUsed?: number;
          freeNetLimit?: number;
          freeNetUsed?: number;
          NetLimit?: number;
          NetUsed?: number;
        }>('/wallet/getaccountresource', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ address, visible: true }),
        }),
        this.fetchTRXBalance(address),
      ]);

      const energy = Math.max(0, (resources.EnergyLimit ?? 0) - (resources.EnergyUsed ?? 0));
      const freeNet = Math.max(0, (resources.freeNetLimit ?? 0) - (resources.freeNetUsed ?? 0));
      const net = Math.max(0, (resources.NetLimit ?? 0) - (resources.NetUsed ?? 0));
      return {
        energyRemaining: energy,
        bandwidthRemaining: Math.max(freeNet, net),
        trxBalance,
      };
    } catch {
      return { energyRemaining: 0, bandwidthRemaining: 0, trxBalance: 0 };
    }
  },

  async fetchTransactions(address: string, limit = 20): Promise<TronTx[]> {
    try {
      const data = await tronRequest<{ data?: Trc20HistoryItem[] }>(
        `/v1/accounts/${address}/transactions/trc20?limit=${limit}&contract_address=${CONFIG.usdtContract}&only_confirmed=true`,
      );
      const items = data.data ?? [];
      return items.map((item) => {
        const amount = parseInt(item.value, 10) / 10 ** CONFIG.tokenDecimals;
        const from = item.from;
        const to = item.to;
        return {
          txID: item.transaction_id,
          fromAddress: from,
          toAddress: to,
          amount,
          timestamp: new Date(item.block_timestamp),
          direction: to.toLowerCase() === address.toLowerCase() ? 'incoming' : 'outgoing',
        };
      });
    } catch {
      return [];
    }
  },

  async broadcastTransaction(signedTx: object): Promise<string> {
    const result = await tronRequest<{ result?: boolean; txid?: string; message?: string }>(
      '/wallet/broadcasttransaction',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(signedTx),
      },
    );
    if (result.result && result.txid) return result.txid;
    throw new Error(result.message ?? 'Broadcast failed');
  },

  async getLatestBlock(): Promise<{ timestamp: number; refBlockBytes: string; refBlockHash: string }> {
    const data = await tronRequest<{
      block_header?: {
        raw_data?: {
          timestamp?: number;
          number?: number;
        };
      };
      blockID?: string;
    }>('/wallet/getnowblock', { method: 'POST' });

    const timestamp = data.block_header?.raw_data?.timestamp ?? Date.now();
    const blockId = data.blockID ?? '';
    return {
      timestamp,
      refBlockBytes: blockId.slice(16, 20),
      refBlockHash: blockId.slice(16, 32),
    };
  },
};

export function tronTxToWalletTransaction(tx: TronTx, accountAddress: string): WalletTransaction {
  const isReceived = tx.direction === 'incoming';
  const counterparty = isReceived ? tx.fromAddress : tx.toAddress;
  return {
    id: tx.txID,
    kind: isReceived ? 'received' : 'sent',
    title: isReceived ? 'Received' : 'Sent',
    subtitle: counterparty.slice(0, 6) + '…' + counterparty.slice(-4),
    amountUSDT: tx.amount,
    dayLabel: dayLabel(tx.timestamp),
    txID: tx.txID,
    fromAddress: tx.fromAddress,
    toAddress: tx.toAddress,
    timestamp: tx.timestamp.toISOString(),
    transferStatus: 'confirmed',
  };
}

function dayLabel(date: Date): string {
  const now = new Date();
  if (date.toDateString() === now.toDateString()) return 'Today';
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday';
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'long' });
}

export function addressesMatch(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}
