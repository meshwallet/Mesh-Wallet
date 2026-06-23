import { useState } from 'react';
import { formatUSDT, shortAddress, LINKS } from '@/core/config';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { MeshPrimaryButton, MeshSecondaryButton } from '@/components/ui/MeshButtons';
import { TransactionTechnicalDetail } from '@/components/TransactionTechnicalDetail';
import type { WalletTransaction } from '@/core/types';

interface Props {
  amount: number;
  recipient: string;
  fromAddress: string;
  errorMessage: string;
  onClose: () => void;
}

export function SendFailedView({
  amount,
  recipient,
  fromAddress,
  errorMessage,
  onClose,
}: Props) {
  const { language } = useApp();
  const { t } = useT(language);
  const [showDetails, setShowDetails] = useState(false);

  const displayMessage = errorMessage.trim()
    || 'Network rejected the transaction. Your balance has not changed.';

  const failedTx: WalletTransaction = {
    id: `failed-${Date.now()}`,
    kind: 'sent',
    title: 'Sent',
    subtitle: shortAddress(recipient),
    amountUSDT: amount,
    dayLabel: 'Today',
    txID: '',
    fromAddress,
    toAddress: recipient,
    timestamp: new Date().toISOString(),
    transferStatus: 'failed',
    failureMessage: displayMessage,
  };

  return (
    <>
      <div className="mesh-slide-panel mesh-send-outcome mesh-send-failed">
        <div className="mesh-scroll mesh-send-outcome-body mesh-send-failed-body">
          <div className="mesh-send-failed-icon">×</div>

          <div className="mesh-send-failed-copy">
            <h2 className="mesh-title">{t(L10nKeys.send.failed)}</h2>
            <p className="mesh-send-failed-message">{displayMessage}</p>
            <p className="mesh-send-failed-hint">No USDT left your wallet.</p>
          </div>

          <div className="mesh-send-summary-card">
            <div className="mesh-send-summary-row">
              <span>{t('send.review.total')}</span>
              <strong>{formatUSDT(amount)} USDT</strong>
            </div>
            <div className="mesh-send-summary-divider" />
            <div className="mesh-send-summary-row">
              <span>{t('send.review.to')}</span>
              <strong>{shortAddress(recipient)}</strong>
            </div>
          </div>
        </div>

        <div className="mesh-footer-actions">
          <MeshPrimaryButton title={t('send.transaction.details')} onClick={() => setShowDetails(true)} />
          <MeshSecondaryButton
            title={t('common.contact')}
            onClick={() => window.open(LINKS.support, '_blank', 'noopener,noreferrer')}
          />
          <MeshSecondaryButton title={t(L10nKeys.common.close)} onClick={onClose} />
        </div>
      </div>

      {showDetails && (
        <TransactionTechnicalDetail tx={failedTx} onClose={() => setShowDetails(false)} />
      )}
    </>
  );
}
