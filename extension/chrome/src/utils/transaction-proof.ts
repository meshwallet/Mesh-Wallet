import { formatUSDT, LINKS, shortAddress } from '@/core/config';
import type { Language, WalletTransaction } from '@/core/types';
import { translate } from '@/core/l10n';

export function isProofEligible(tx: WalletTransaction): boolean {
  return tx.transferStatus === 'confirmed' || tx.transferStatus === 'processing';
}

export function formatTxDateTime(timestamp: string): string {
  return new Date(timestamp).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function amountDetailText(amountUSDT: number): string {
  return `${formatUSDT(Math.abs(amountUSDT))} USDT`;
}

export function proofHeadline(tx: WalletTransaction, t: (key: string) => string): string {
  return tx.kind === 'sent'
    ? t('transfer.proof.transfer.sent')
    : t('transfer.proof.transfer.received');
}

export function proofSubtitle(tx: WalletTransaction, t: (key: string) => string): string {
  if (tx.transferStatus === 'confirmed') return t('transfer.proof.confirmed.on.network');
  if (tx.transferStatus === 'processing') return t('transfer.proof.processing.on.network');
  return '';
}

export function proofStatusText(tx: WalletTransaction, t: (key: string) => string): string {
  if (tx.transferStatus === 'confirmed') return t('transfer.proof.confirmed');
  if (tx.transferStatus === 'processing') return t('transaction.processing');
  return t('send.failed');
}

export function proofShareText(tx: WalletTransaction, lang: Language): string {
  const status = proofStatusText(tx, (key) => translate(lang, key));
  const counterpartyTitle = tx.kind === 'sent'
    ? translate(lang, 'transfer.proof.to')
    : translate(lang, 'transfer.proof.from');
  const counterparty = shortAddress(tx.kind === 'sent' ? tx.toAddress : tx.fromAddress);
  const brandLine = tx.kind === 'sent'
    ? translate(lang, 'transfer.proof.sent.with.mesh')
    : translate(lang, 'transfer.proof.received.with.mesh');

  return [
    proofHeadline(tx, (key) => translate(lang, key)),
    '',
    amountDetailText(tx.amountUSDT),
    '',
    `${translate(lang, 'transfer.proof.status')}: ${status}`,
    `${translate(lang, 'transfer.proof.network.label')}: ${translate(lang, 'transfer.proof.network')}`,
    `${counterpartyTitle}: ${counterparty}`,
    `${translate(lang, 'transfer.proof.tx')}: ${tx.txID ? shortAddress(tx.txID) : '—'}`,
    formatTxDateTime(tx.timestamp),
    '',
    brandLine,
    translate(lang, 'transfer.proof.tagline'),
  ].join('\n');
}

export function pendingSendToTransaction(record: {
  id: string;
  amountUSDT: number;
  recipientAddress: string;
  fromAddress: string;
  toAddress: string;
  startedAt: string;
  txID: string;
  status: WalletTransaction['transferStatus'];
  failedMessage?: string;
}): WalletTransaction {
  return {
    id: record.id,
    kind: 'sent',
    title: 'Sent',
    subtitle: shortAddress(record.recipientAddress),
    amountUSDT: record.amountUSDT,
    dayLabel: 'Today',
    txID: record.txID,
    fromAddress: record.fromAddress,
    toAddress: record.toAddress,
    timestamp: record.startedAt,
    transferStatus: record.status,
    failureMessage: record.failedMessage,
  };
}

export function tronscanUrl(txID: string): string | null {
  const trimmed = txID.trim();
  return trimmed ? LINKS.tronscanTx(trimmed) : null;
}
