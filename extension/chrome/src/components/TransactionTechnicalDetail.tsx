import { useState } from 'react';
import type { WalletTransaction } from '@/core/types';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { MeshPrimaryButton } from '@/components/ui/MeshButtons';
import {
  amountDetailText,
  formatTxDateTime,
  proofStatusText,
  tronscanUrl,
} from '@/utils/transaction-proof';
import { shortAddress } from '@/core/config';

interface Props {
  tx: WalletTransaction;
  onClose: () => void;
}

export function TransactionTechnicalDetail({ tx, onClose }: Props) {
  const { language } = useApp();
  const { t } = useT(language);
  const [copiedField, setCopiedField] = useState<'from' | 'to' | 'tx' | null>(null);

  const isFailed = tx.transferStatus === 'failed';
  const isIncoming = tx.kind === 'received';
  const accentClass = isFailed ? 'failed' : isIncoming ? 'incoming' : 'outgoing';

  const copyValue = async (value: string, field: 'from' | 'to' | 'tx') => {
    if (!value) return;
    await navigator.clipboard.writeText(value);
    setCopiedField(field);
    setTimeout(() => setCopiedField(null), 2000);
  };

  const failureDetails = isFailed
    ? (tx.txID
      ? `Transaction ID: ${shortAddress(tx.txID)}`
      : 'No transaction was broadcast to the Tron network.')
    : t('transfer.proof.confirmed.on.network');

  const scanUrl = tronscanUrl(tx.txID);

  return (
    <div className="mesh-sheet">
      <div className="mesh-sheet-backdrop" onClick={onClose} />
      <div className="mesh-sheet-content mesh-transfer-proof-sheet">
        <header className="mesh-transfer-proof-header">
          <div className="mesh-sheet-handle" aria-hidden />
          <div className="mesh-transfer-proof-header-row mesh-transfer-proof-header-row-title">
            <div>
              <h2 className="mesh-transfer-proof-details-title">{t('transfer.proof.details.title')}</h2>
              <p className={`mesh-transfer-proof-details-caption ${accentClass}`}>
                TRC-20 · {tx.failureMessage ?? proofStatusText(tx, t)}
              </p>
            </div>
            <button type="button" className="mesh-transfer-proof-done" onClick={onClose}>
              {t(L10nKeys.common.done)}
            </button>
          </div>
        </header>

        <div className="mesh-scroll mesh-transfer-proof-body">
          <div className="mesh-tx-detail-hero">
            <div className={`mesh-tx-detail-icon ${accentClass}`}>
              {isFailed ? '×' : isIncoming ? '↙' : '↗'}
            </div>
            <p className={`mesh-tx-detail-amount ${isIncoming ? 'incoming' : ''}`}>
              {isIncoming ? '+' : '-'}{amountDetailText(tx.amountUSDT)}
            </p>
            <div className="mesh-tx-detail-meta">
              <span>{tx.title}</span>
              <span>USDT</span>
              <span>Tron</span>
            </div>
            <p className="mesh-tx-detail-date">{formatTxDateTime(tx.timestamp)}</p>
          </div>

          <div className="mesh-tx-detail-fields">
            <DetailField label={t('transfer.proof.status')} value={tx.failureMessage ?? proofStatusText(tx, t)} />
            <DetailField label={t('transfer.proof.details.field')} value={failureDetails} />
            <DetailField
              label={t('transfer.proof.from')}
              value={tx.fromAddress}
              copied={copiedField === 'from'}
              onCopy={() => copyValue(tx.fromAddress, 'from')}
            />
            <DetailField
              label={t('transfer.proof.to')}
              value={tx.toAddress}
              copied={copiedField === 'to'}
              onCopy={() => copyValue(tx.toAddress, 'to')}
            />
            <DetailField
              label={t('transfer.proof.tx')}
              value={tx.txID || '—'}
              mono
              copied={copiedField === 'tx'}
              onCopy={tx.txID ? () => copyValue(tx.txID, 'tx') : undefined}
            />
          </div>
        </div>

        {scanUrl && tx.transferStatus === 'confirmed' && (
          <div className="mesh-footer-actions">
            <MeshPrimaryButton
              title={t('transfer.proof.view.tronscan')}
              onClick={() => window.open(scanUrl, '_blank', 'noopener,noreferrer')}
            />
          </div>
        )}
      </div>
    </div>
  );
}

function DetailField({
  label,
  value,
  mono,
  copied,
  onCopy,
}: {
  label: string;
  value: string;
  mono?: boolean;
  copied?: boolean;
  onCopy?: () => void;
}) {
  return (
    <div className="mesh-tx-detail-field">
      <div className="mesh-tx-detail-field-main">
        <span className="mesh-tx-detail-field-label">{label}</span>
        <span className={`mesh-tx-detail-field-value ${mono ? 'mono' : ''}`}>{value}</span>
      </div>
      {onCopy && (
        <button type="button" className="mesh-tx-detail-copy" onClick={onCopy}>
          {copied ? '✓' : '⧉'}
        </button>
      )}
    </div>
  );
}
