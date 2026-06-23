import { useState } from 'react';
import type { WalletTransaction } from '@/core/types';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { TransferProofCard } from '@/components/TransferProofCard';
import { MeshPrimaryButton, MeshSecondaryButton } from '@/components/ui/MeshButtons';
import { proofHeadline, proofShareText, proofSubtitle, tronscanUrl } from '@/utils/transaction-proof';

interface Props {
  tx: WalletTransaction;
  onClose: () => void;
  usesSheetChrome?: boolean;
}

export function TransferProofExperience({ tx, onClose, usesSheetChrome = true }: Props) {
  const { language } = useApp();
  const { t } = useT(language);
  const [copiedTx, setCopiedTx] = useState(false);
  const [isPreparingShare, setIsPreparingShare] = useState(false);

  const copyTx = async () => {
    if (!tx.txID) return;
    await navigator.clipboard.writeText(tx.txID);
    setCopiedTx(true);
    setTimeout(() => setCopiedTx(false), 2000);
  };

  const shareProof = async () => {
    setIsPreparingShare(true);
    await new Promise((resolve) => setTimeout(resolve, 340));
    const text = proofShareText(tx, language);
    try {
      if (navigator.share) {
        await navigator.share({ title: proofHeadline(tx, t), text });
      } else {
        await navigator.clipboard.writeText(text);
      }
    } catch { /* cancelled */ }
    setIsPreparingShare(false);
  };

  const scanUrl = tronscanUrl(tx.txID);
  const isProcessing = tx.transferStatus === 'processing';

  return (
    <div className={`mesh-transfer-proof-screen ${usesSheetChrome ? 'mesh-sheet' : 'mesh-slide-panel'}`}>
      {usesSheetChrome && <div className="mesh-sheet-backdrop" onClick={onClose} />}
      <div className={`${usesSheetChrome ? 'mesh-sheet-content mesh-transfer-proof-sheet' : 'mesh-transfer-proof-full'}`}>
        {isPreparingShare && <div className="mesh-transfer-proof-share-overlay" aria-hidden />}

        <header className="mesh-transfer-proof-header">
          {usesSheetChrome && <div className="mesh-sheet-handle" aria-hidden />}
          <div className="mesh-transfer-proof-header-row">
            <span />
            <button type="button" className="mesh-transfer-proof-done" onClick={onClose} disabled={isPreparingShare}>
              {t(L10nKeys.common.done)}
            </button>
          </div>
        </header>

        <div className="mesh-scroll mesh-transfer-proof-body">
          <div className={`mesh-transfer-proof-intro ${isPreparingShare ? 'dimmed' : ''}`}>
            <h2 className="mesh-transfer-proof-title">{proofHeadline(tx, t)}</h2>
            <p className="mesh-transfer-proof-subtitle">{proofSubtitle(tx, t)}</p>
          </div>

          <div className={`mesh-transfer-proof-card-wrap ${isPreparingShare ? 'share-ready' : ''}`}>
            <TransferProofCard tx={tx} lang={language} />
          </div>
        </div>

        {!isProcessing && (
          <div className={`mesh-footer-actions ${isPreparingShare ? 'hidden' : ''}`}>
            <MeshPrimaryButton title={t('transfer.proof.share')} onClick={shareProof} />
            <MeshSecondaryButton
              title={copiedTx ? t(L10nKeys.common.copied) : t('transfer.proof.copy.tx')}
              onClick={copyTx}
              disabled={!tx.txID}
            />
            {scanUrl && (
              <MeshSecondaryButton
                title={t('transfer.proof.view.tronscan')}
                onClick={() => window.open(scanUrl, '_blank', 'noopener,noreferrer')}
              />
            )}
          </div>
        )}
      </div>
    </div>
  );
}
