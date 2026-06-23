export const CONFIG = {
  relayUrl: import.meta.env.VITE_RELAY_URL || 'https://mesh-sponsorship-relay.meshwallet.workers.dev',
  relayAuthSecret: (import.meta.env.VITE_RELAY_AUTH_SECRET || '').trim(),
  treasuryAddress: 'TWorKRZ5B1awmuHcmprsbTvGJrSSzEbdmd',
  sendRouterAddress: 'TTDAmwJuKWkhjBjkEt3RGej22z1aJagLYK',
  usdtContract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  tronGridBase: 'https://api.trongrid.io',
  tronGridApiKeys: (import.meta.env.VITE_TRONGRID_API_KEYS || '')
    .split(',')
    .map((key) => key.trim())
    .filter(Boolean),
  tokenDecimals: 6,
  defaultFeeLimit: 30_000_000,
  handoffExpirationMs: 10 * 60 * 1000,
  balancePollMs: 15_000,
  walletReceiveSlotCount: 5,
  deepRecoveryScanCount: 1024,
} as const;

export const LINKS = {
  support: 'https://meshwallet.app/support',
  terms: 'https://meshone.app/terms-and-conditions',
  privacy: 'https://meshone.app/privacy-policy',
  tronscanTx: (txId: string) => `https://tronscan.org/#/transaction/${txId}`,
} as const;

export const SEND_FEES = {
  direct: 2,
  chargesOnChainFee: false,
  showsFeeInUI: true,
} as const;

export function networkFee(): number {
  return SEND_FEES.direct;
}

export function collectsSendFee(isPrivateSend = false): boolean {
  if (!SEND_FEES.chargesOnChainFee || !CONFIG.treasuryAddress) return false;
  if (isPrivateSend) return true;
  return usesSendRouter();
}

export function usesSendRouter(): boolean {
  return SEND_FEES.chargesOnChainFee
    && Boolean(CONFIG.treasuryAddress)
    && Boolean(CONFIG.sendRouterAddress);
}

/** Relay register-send-fee payload (iOS: MeshSendFees.workerRegistrationFee). */
export function workerRegistrationFee(isPrivateSend = false): number {
  if (!SEND_FEES.chargesOnChainFee) return 0;
  return isPrivateSend ? 10 : networkFee();
}

/** Total USDT debited from the wallet for this send amount (matches iOS totalDebitUSDT). */
export function sendTotalDebit(amount: number): number {
  if (!SEND_FEES.chargesOnChainFee) return amount;
  return amount + networkFee();
}

export function formattedFee(fee: number): string {
  return `${formatUSDT(fee)} USDT`;
}

export function formatUSDT(amount: number, includeSymbol = false): string {
  const value = amount.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).replace('.', ',');
  return includeSymbol ? `${value} USDT` : value;
}

/** Compact placeholder for hidden balances in lists (iOS slot picker). */
export const HIDDEN_BALANCE_COMPACT = '•••';

export function formatBalanceCompact(amount: number, hidden: boolean): string {
  if (hidden) return HIDDEN_BALANCE_COMPACT;
  return formatUSDT(amount);
}

export function formatBalanceWithUnit(amount: number, hidden: boolean): string {
  if (hidden) return HIDDEN_BALANCE_COMPACT;
  return `${formatUSDT(amount)} USDT`;
}

export function balancePrivacyClass(hidden: boolean): string {
  return hidden ? 'mesh-balance-privacy-hidden' : '';
}

export function shortAddress(address: string): string {
  const trimmed = address.trim();
  if (trimmed.length <= 12) return trimmed;
  return `${trimmed.slice(0, 6)}…${trimmed.slice(-4)}`;
}

/** Single-line address for receive / send-to-self rows (matches iOS). */
export function receiveDisplayAddress(address: string): string {
  const trimmed = address.trim();
  if (trimmed.length <= 16) return trimmed;
  return `${trimmed.slice(0, 5)}...${trimmed.slice(-9)}`;
}

export function isValidTronAddress(address: string): boolean {
  const trimmed = address.trim();
  return trimmed.startsWith('T') && trimmed.length === 34;
}

export function parseAmount(text: string): number | null {
  let normalized = text.trim();
  if (!normalized) return null;
  normalized = normalized.replace(/USDT/gi, '').replace(/\s/g, '');
  if (normalized.includes(',') && normalized.includes('.')) {
    const lastComma = normalized.lastIndexOf(',');
    const lastDot = normalized.lastIndexOf('.');
    if (lastComma > lastDot) {
      normalized = normalized.replace(/\./g, '').replace(',', '.');
    } else {
      normalized = normalized.replace(/,/g, '');
    }
  } else if (normalized.includes(',')) {
    normalized = normalized.replace(',', '.');
  }
  const num = parseFloat(normalized);
  if (isNaN(num) || num <= 0) return null;
  return Math.round(num * 100) / 100;
}

export function sanitizeAmountInput(text: string): string {
  let result = '';
  let hasSep = false;
  let frac = 0;
  for (const ch of text) {
    if (/\d/.test(ch)) {
      if (hasSep) {
        if (frac >= 2) continue;
        frac++;
      }
      result += ch;
    } else if (ch === '.' || ch === ',') {
      if (hasSep) continue;
      hasSep = true;
      result += ch;
    }
  }
  return result;
}
