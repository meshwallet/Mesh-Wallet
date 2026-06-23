import { useEffect, useState, useCallback } from 'react';
import type { WalletTransaction } from '@/core/types';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { SendPollService } from '@/services/send-poll-service';
import {
  BackgroundSendService,
  type SendExecutionContext,
} from '@/services/background-send-service';
import { TransferProofCard } from '@/components/TransferProofCard';
import { MeshPrimaryButton, MeshSecondaryButton } from '@/components/ui/MeshButtons';
import { LINKS } from '@/core/config';
import { pendingSendToTransaction } from '@/utils/transaction-proof';

interface Props {
  sendId: string;
  sendContext: SendExecutionContext;
  onClose: () => void;
}

export function SendSubmittedView({ sendId, sendContext, onClose }: Props) {
  const { language, refreshWallet } = useApp();
  const { t } = useT(language);
  const [tx, setTx] = useState<WalletTransaction | null>(null);
  const [handoffRegistered, setHandoffRegistered] = useState(false);

  const refresh = useCallback(async () => {
    await SendPollService.pollPendingSends();
    const record = await BackgroundSendService.resolveRecord(sendId);
    if (!record) return;

    const ctx = BackgroundSendService.getExecutionContext(sendId)
      ?? sendContext;

    setHandoffRegistered(record.handoffRegistered);
    setTx(pendingSendToTransaction(record));

    if (
      !record.handoffRegistered
      && record.status === 'processing'
      && !BackgroundSendService.isHandoffRunning()
    ) {
      BackgroundSendService.startHandoffForPendingSend(sendId, ctx);
    }

    if (record.status === 'confirmed' || record.status === 'failed') {
      await refreshWallet();
    }
  }, [sendContext, sendId, refreshWallet]);

  useEffect(() => {
    void refresh();
    const interval = setInterval(refresh, 2000);
    return () => clearInterval(interval);
  }, [refresh]);

  if (!tx) {
    return (
      <div className="mesh-slide-panel mesh-flow-center">
        <div className="mesh-spinner" />
      </div>
    );
  }

  const isFailed = tx.transferStatus === 'failed';
  const isConfirmed = tx.transferStatus === 'confirmed';
  const isPreparing = !handoffRegistered && !isFailed && !isConfirmed;

  const headline = isFailed
    ? t(L10nKeys.send.failed)
    : handoffRegistered || isConfirmed
      ? t('transfer.proof.transfer.sent')
      : t('send.processing.preparing');

  const subtitle = isFailed
    ? (tx.failureMessage ?? t('send.failed'))
    : isConfirmed
      ? t('transfer.proof.confirmed.on.network')
      : handoffRegistered
        ? t('send.processing.background.safe')
        : t('send.processing.preparing.hint');

  const displayTx: WalletTransaction = {
    ...tx,
    transferStatus: isConfirmed ? 'confirmed' : isFailed ? 'failed' : 'processing',
  };

  return (
    <div className="mesh-slide-panel mesh-send-outcome">
      <div className="mesh-scroll mesh-send-outcome-body">
        <div className={`mesh-send-status-hero ${isFailed ? 'failed' : handoffRegistered || isConfirmed ? 'success' : 'processing'}`}>
          {isFailed ? '×' : handoffRegistered || isConfirmed ? '✓' : <span className="mesh-spinner" />}
        </div>

        <div className="mesh-transfer-proof-intro">
          <h2 className="mesh-transfer-proof-title">{headline}</h2>
          <p className="mesh-transfer-proof-subtitle">{subtitle}</p>
        </div>

        <TransferProofCard tx={displayTx} lang={language} />

        {isPreparing && (
          <div className="mesh-send-keep-open">
            <p>{t('send.processing.activating.keepOpen')}</p>
          </div>
        )}
      </div>

      <div className="mesh-footer-actions">
        {isFailed && (
          <MeshSecondaryButton
            title={t('common.contact')}
            onClick={() => window.open(LINKS.support, '_blank', 'noopener,noreferrer')}
          />
        )}
        {!isPreparing && (
          <MeshPrimaryButton title={t(L10nKeys.common.done)} onClick={onClose} />
        )}
      </div>
    </div>
  );
}
