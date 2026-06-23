import type { WalletTransaction } from '@/core/types';
import { useT } from '@/core/l10n';
import type { Language } from '@/core/types';
import {
  amountDetailText,
  formatTxDateTime,
  proofStatusText,
} from '@/utils/transaction-proof';
import { shortAddress } from '@/core/config';

interface Props {
  tx: WalletTransaction;
  lang: Language;
  variant?: 'standard' | 'share';
}

export function TransferProofCard({ tx, lang, variant = 'standard' }: Props) {
  const { t } = useT(lang);
  const counterparty = tx.kind === 'sent' ? tx.toAddress : tx.fromAddress;

  return (
    <div className={`mesh-transfer-proof ${variant === 'share' ? 'mesh-transfer-proof-share' : ''}`}>
      {variant === 'share' ? (
        <p className="mesh-transfer-proof-share-headline">
          {tx.kind === 'sent'
            ? t('transfer.proof.amount.sent', amountDetailText(tx.amountUSDT))
            : t('transfer.proof.amount.received', amountDetailText(tx.amountUSDT))}
        </p>
      ) : (
        <p className="mesh-transfer-proof-amount">{amountDetailText(tx.amountUSDT)}</p>
      )}

      <ProofRow label={t('transfer.proof.status')} value={proofStatusText(tx, t)} />
      <ProofRow label={t('transfer.proof.network.label')} value={t('transfer.proof.network')} />
      <ProofRow
        label={tx.kind === 'sent' ? t('transfer.proof.to') : t('transfer.proof.from')}
        value={shortAddress(counterparty)}
      />
      {tx.txID && (
        <ProofRow label={t('transfer.proof.tx')} value={shortAddress(tx.txID)} mono />
      )}
      <ProofRow label={t('transfer.proof.date')} value={formatTxDateTime(tx.timestamp)} />

      <div className="mesh-transfer-proof-brand">
        <img src="/branding/mesh-logo.png" alt="Mesh" className="mesh-transfer-proof-logo" />
        <p className="mesh-transfer-proof-tagline">{t('transfer.proof.tagline')}</p>
      </div>
    </div>
  );
}

function ProofRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <>
      <div className="mesh-proof-row">
        <span className="mesh-proof-row-label">{label}</span>
        <span className={`mesh-proof-row-value ${mono ? 'mono' : ''}`}>{value}</span>
      </div>
    </>
  );
}
