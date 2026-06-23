import { useState } from 'react';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { PasscodeStore } from '@/core/storage/passcode';
import { WalletCredentials } from '@/services/tron/wallet-service';
import { WalletRegistry } from '@/core/storage/wallet-registry';
import { PasswordForm } from '@/components/PasswordForm';
import { ChangePasscodeFlow } from '@/views/ChangePasscodeFlow';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';
import { LINKS } from '@/core/config';
import { getExtensionVersion } from '@/core/extension-asset';
import type { Language } from '@/core/types';

interface Props {
  onClose: () => void;
}

export function SecurityView({ onClose }: Props) {
  const { activeWallet, wallets, language, setLanguage, refreshWallet } = useApp();
  const { t } = useT(language);
  const [showChangePasscode, setShowChangePasscode] = useState(false);
  const [recoveryStep, setRecoveryStep] = useState<'idle' | 'verify' | 'show'>('idle');
  const [phraseWords, setPhraseWords] = useState<string[]>([]);
  const [phraseUnavailable, setPhraseUnavailable] = useState(false);
  const [verifyError, setVerifyError] = useState('');
  const [copied, setCopied] = useState(false);
  const [showRemoveConfirm, setShowRemoveConfirm] = useState(false);

  const loadRecoveryPhrase = async () => {
    if (!activeWallet) {
      setPhraseUnavailable(true);
      setPhraseWords([]);
      setRecoveryStep('show');
      return;
    }

    try {
      const creds = await WalletCredentials.resolve(activeWallet.id);
      if (!creds.mnemonic?.length) {
        setPhraseUnavailable(true);
        setPhraseWords([]);
      } else {
        setPhraseUnavailable(false);
        setPhraseWords(creds.mnemonic);
      }
      setRecoveryStep('show');
    } catch {
      setPhraseUnavailable(true);
      setPhraseWords([]);
      setRecoveryStep('show');
    }
  };

  const closeRecovery = () => {
    setRecoveryStep('idle');
    setPhraseWords([]);
    setPhraseUnavailable(false);
    setVerifyError('');
    setCopied(false);
  };

  const openRecoveryVerify = async () => {
    setVerifyError('');
    const enabled = await PasscodeStore.isEnabled();
    if (!enabled) {
      await loadRecoveryPhrase();
      return;
    }
    setRecoveryStep('verify');
  };

  if (showChangePasscode) {
    return <ChangePasscodeFlow onClose={() => setShowChangePasscode(false)} />;
  }

  if (recoveryStep === 'verify') {
    return (
      <div className="mesh-slide-panel mesh-screen">
        <MeshFlowScreenHeader title={t(L10nKeys.settings.viewRecoveryPhrase)} onClose={closeRecovery} />
        <PasswordForm
          title={t(L10nKeys.security.lockTitle)}
          subtitle={t('settings.view.recovery.subtitle')}
          error={verifyError}
          submitLabel={t(L10nKeys.common.continue)}
          onSubmit={async (password) => {
            setVerifyError('');
            if (!(await PasscodeStore.verify(password))) {
              setVerifyError(t(L10nKeys.security.passcodeIncorrect));
              return;
            }
            await loadRecoveryPhrase();
          }}
          onCancel={closeRecovery}
        />
      </div>
    );
  }

  if (recoveryStep === 'show') {
    const phraseText = phraseWords.join(' ');
    return (
      <div className="mesh-slide-panel">
        <MeshFlowScreenHeader title={t(L10nKeys.settings.recoveryPhrase)} onClose={closeRecovery} />
        <div className="mesh-scroll" style={{ padding: 'var(--mesh-padding)' }}>
          {phraseUnavailable ? (
            <p className="mesh-subtitle" style={{ textAlign: 'center', padding: 24 }}>
              {t('settings.recovery.unavailable')}
            </p>
          ) : (
            <>
              <p className="mesh-subtitle" style={{ marginBottom: 16 }}>
                {t('onboarding.recovery.never.share')}
              </p>
              <div className="mesh-seed-grid">
                {phraseWords.map((word, i) => (
                  <div key={i} className="mesh-seed-word">{i + 1}. {word}</div>
                ))}
              </div>
              <button
                type="button"
                className="mesh-btn-secondary"
                style={{ marginTop: 16 }}
                onClick={async () => {
                  await navigator.clipboard.writeText(phraseText);
                  setCopied(true);
                  setTimeout(() => setCopied(false), 2000);
                }}
              >
                {copied ? t(L10nKeys.common.copied) : t('onboarding.recovery.copy')}
              </button>
            </>
          )}
        </div>
      </div>
    );
  }

  const removeWallet = async () => {
    if (!activeWallet || wallets.length < 2) return;
    await WalletRegistry.removeWallet(activeWallet.id);
    await refreshWallet();
    onClose();
  };

  return (
    <div className="mesh-slide-panel">
      <MeshFlowScreenHeader title={t(L10nKeys.settings.title)} onClose={onClose} />
      <div className="mesh-scroll" style={{ padding: 'var(--mesh-padding)' }}>
        <div className="mesh-settings-row">
          <span>{t('language.title')}</span>
          <select
            value={language}
            onChange={(e) => setLanguage(e.target.value as Language)}
            className="mesh-select"
          >
            <option value="en">English</option>
            <option value="tr">Türkçe</option>
            <option value="vi">Tiếng Việt</option>
            <option value="id">Indonesia</option>
            <option value="es">Español</option>
          </select>
        </div>

        <button type="button" className="mesh-settings-row" style={{ width: '100%' }} onClick={() => setShowChangePasscode(true)}>
          <span>{t(L10nKeys.settings.passcodeChange)}</span><span>→</span>
        </button>

        <button type="button" className="mesh-settings-row" style={{ width: '100%' }} onClick={openRecoveryVerify}>
          <span>{t(L10nKeys.settings.viewRecoveryPhrase)}</span><span>→</span>
        </button>

        {wallets.length >= 2 && (
          <>
            {showRemoveConfirm ? (
              <div className="mesh-card" style={{ marginTop: 24 }}>
                <p style={{ marginBottom: 12 }}>{t('settings.remove.confirm.phrase')}</p>
                <button type="button" className="mesh-btn-secondary" style={{ color: '#ff6b6b', marginBottom: 8 }} onClick={removeWallet}>
                  {t('settings.remove.action')}
                </button>
                <button type="button" className="mesh-btn-secondary" onClick={() => setShowRemoveConfirm(false)}>
                  {t(L10nKeys.common.cancel)}
                </button>
              </div>
            ) : (
              <button type="button" className="mesh-btn-secondary" style={{ marginTop: 24, color: '#ff6b6b' }} onClick={() => setShowRemoveConfirm(true)}>
                {t(L10nKeys.settings.removeWallet)}
              </button>
            )}
          </>
        )}

        <div style={{ marginTop: 32 }}>
          <a href={LINKS.support} target="_blank" rel="noreferrer">{t(L10nKeys.settings.contactSupport)}</a>
          <p className="mesh-subtitle" style={{ marginTop: 8 }}>Mesh Wallet v{getExtensionVersion()}</p>
        </div>
      </div>
    </div>
  );
}
