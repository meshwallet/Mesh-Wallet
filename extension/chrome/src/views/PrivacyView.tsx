import { useState } from 'react';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { PrivacyService } from '@/services/mesh/privacy-service';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';
import { MeshPrimaryButton, MeshSecondaryButton } from '@/components/ui/MeshButtons';
import type { DeepRecoveryState } from '@/core/types';

interface Props {
  onClose: () => void;
  onDeepRecovery?: () => void;
  deepRecovery?: DeepRecoveryState;
}

export function PrivacyView({ onClose, onDeepRecovery, deepRecovery }: Props) {
  const { activeWallet, refreshWallet, language } = useApp();
  const { t } = useT(language);
  const [consolidating, setConsolidating] = useState(false);
  const [progress, setProgress] = useState('');
  const [error, setError] = useState('');

  const consolidate = async () => {
    if (!activeWallet) return;
    setConsolidating(true);
    setError('');
    setProgress('');
    try {
      const count = await PrivacyService.consolidateSlotsToMain(
        activeWallet.id,
        (current, total) => setProgress(`${current}/${total}`),
      );
      setProgress(count > 0 ? t('privacy.consolidate.done', count) : t('privacy.consolidate.done', 0));
      await refreshWallet();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Consolidation failed');
    } finally {
      setConsolidating(false);
    }
  };

  return (
    <div className="mesh-slide-panel">
      <MeshFlowScreenHeader title={t(L10nKeys.privacy.title)} onClose={onClose} />
      <div className="mesh-scroll" style={{ padding: 'var(--mesh-padding)' }}>
        <div className="mesh-privacy-card">
          <h2 style={{ fontSize: 18, marginBottom: 8 }}>{t(L10nKeys.privacy.receiveTitle)}</h2>
          <p className="mesh-subtitle">{t(L10nKeys.privacy.receiveBody)}</p>
        </div>

        <h2 style={{ fontSize: 18, margin: '24px 0 12px' }}>{t(L10nKeys.privacy.protectionTitle)}</h2>
        <ul style={{ paddingLeft: 20, color: 'var(--mesh-text-secondary)', marginBottom: 24 }}>
          <li style={{ marginBottom: 8 }}>{t(L10nKeys.privacy.protectionItem1)}</li>
          <li style={{ marginBottom: 8 }}>{t(L10nKeys.privacy.protectionItem2)}</li>
          <li>{t(L10nKeys.privacy.protectionItem3)}</li>
        </ul>

        <h2 style={{ fontSize: 18, marginBottom: 8 }}>{t(L10nKeys.privacy.consolidateTitle)}</h2>
        <p className="mesh-subtitle" style={{ marginBottom: 16 }}>{t(L10nKeys.privacy.consolidateHint)}</p>
        <MeshSecondaryButton
          title={consolidating ? t('privacy.consolidate.running') : t(L10nKeys.privacy.consolidateButton)}
          disabled={consolidating}
          onClick={consolidate}
        />
        {progress && <p className="mesh-subtitle" style={{ marginTop: 12 }}>{progress}</p>}

        {onDeepRecovery && (
          <>
            <h2 style={{ fontSize: 18, margin: '32px 0 8px' }}>{t('send.deep.recovery.title')}</h2>
            <p className="mesh-subtitle" style={{ marginBottom: 16 }}>{t('send.deep.recovery.hint')}</p>
            <MeshPrimaryButton
              title={deepRecovery?.isRunning ? t('send.deep.recovery.scanning') : t('send.deep.recovery.button')}
              disabled={deepRecovery?.isRunning}
              onClick={onDeepRecovery}
            />
            {deepRecovery?.statusMessage && (
              <p className="mesh-subtitle" style={{ marginTop: 12 }}>{deepRecovery.statusMessage}</p>
            )}
          </>
        )}

        {error && <p className="mesh-error" style={{ marginTop: 12 }}>{error}</p>}
        {deepRecovery?.errorMessage && <p className="mesh-error" style={{ marginTop: 12 }}>{deepRecovery.errorMessage}</p>}
      </div>
    </div>
  );
}
