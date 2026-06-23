import { useEffect, useRef, useState } from 'react';
import { LINKS } from '@/core/config';
import type { OnboardingStep } from '@/core/types';
import { WalletService } from '@/services/tron/wallet-service';
import { WalletRegistry, WalletSession } from '@/core/storage/wallet-registry';
import { PasscodeStore } from '@/core/storage/passcode';
import { PasswordForm } from '@/components/PasswordForm';
import { SeedPhraseSecuritySheet } from '@/views/SeedPhraseSecuritySheet';
import { WalletReadyScreen } from '@/views/WalletReadyScreen';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { MeshPrimaryButton, MeshSecondaryButton } from '@/components/ui/MeshButtons';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';

interface OnboardingFlowProps {
  onComplete: () => void;
  onCancel?: () => void;
  initialStep?: OnboardingStep;
}

export function OnboardingFlow({ onComplete, onCancel, initialStep = 'welcome' }: OnboardingFlowProps) {
  const { language } = useApp();
  const { t } = useT(language);
  const [step, setStep] = useState<OnboardingStep>(initialStep);
  const isAddWalletFlow = initialStep !== 'welcome';

  const backFromAddExisting = () => {
    if (isAddWalletFlow) onCancel?.();
    else setStep('welcome');
  };
  const [mnemonic, setMnemonic] = useState<string[]>([]);
  const [passwordDraft, setPasswordDraft] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [restoreWords, setRestoreWords] = useState('');
  const [privateKey, setPrivateKey] = useState('');
  const [walletName, setWalletName] = useState('');
  const [showSeedSecurity, setShowSeedSecurity] = useState(false);
  const [onboardingFlow, setOnboardingFlow] = useState<'created' | 'restored'>('restored');
  const createStartedRef = useRef(false);

  const formatWalletError = (e: unknown, fallback: string) => {
    if (e instanceof Error && e.message.startsWith('error.')) {
      return t(e.message);
    }
    return e instanceof Error ? e.message : fallback;
  };

  const finishWallet = async (
    words: string[],
    addr: string,
    importKind: 'mnemonic' | 'privateKey',
    pk?: string,
    flow: 'created' | 'restored' = 'restored',
  ) => {
    const wallets = await WalletRegistry.getWallets();
    const isNewWallet = !wallets.some((w) => w.address === addr.trim());

    await WalletRegistry.registerWallet({
      address: addr,
      name: walletName.trim() || undefined,
      importKind,
      mnemonic: importKind === 'mnemonic' ? words : undefined,
      privateKeyHex: pk,
    });

    setOnboardingFlow(flow);
    setMnemonic(words);

    const passwordEnabled = await PasscodeStore.isEnabled();
    if (!passwordEnabled) {
      setStep('setupPassword');
      return;
    }

    if (initialStep !== 'welcome') {
      if (flow === 'created') {
        setStep('walletReady');
      } else {
        onComplete();
      }
      return;
    }

    if (flow === 'created') {
      setStep('walletReady');
      return;
    }

    await finishOnboarding();
  };

  const startCreateWallet = async () => {
    setLoading(true);
    setError('');
    try {
      const { mnemonic: words } = WalletService.createWallet();
      const addr = WalletService.importMnemonic(words);
      await finishWallet(words, addr, 'mnemonic', undefined, 'created');
    } catch (e) {
      setError(formatWalletError(e, 'Could not create wallet'));
    } finally {
      setLoading(false);
    }
  };

  const savePassword = async (password: string) => {
    if (step === 'setupPassword') {
      if (!PasscodeStore.isValidPassword(password)) {
        setError(t(L10nKeys.security.passwordTooShort));
        return;
      }
      setPasswordDraft(password);
      setError('');
      setStep('confirmPassword');
      return;
    }

    if (password !== passwordDraft) {
      setError(t(L10nKeys.security.passwordMismatch));
      return;
    }

    const saved = await PasscodeStore.setPasscode(password);
    if (!saved) {
      setError(t(L10nKeys.security.passwordTooShort));
      return;
    }

    setError('');
    if (onboardingFlow === 'created') {
      setStep('walletReady');
    } else {
      await finishOnboarding();
    }
  };

  useEffect(() => {
    if (step !== 'createLaunch') {
      createStartedRef.current = false;
      return;
    }
    if (createStartedRef.current || loading) return;
    createStartedRef.current = true;
    void startCreateWallet();
  }, [step, loading]);

  const restorePhrase = async () => {
    setError('');
    const words = restoreWords.trim().split(/\s+/).filter(Boolean);
    if (words.length !== 12) {
      setError(t('error.invalid.recovery.phrase'));
      return;
    }
    setLoading(true);
    try {
      const addr = WalletService.importMnemonic(words);
      await finishWallet(words, addr, 'mnemonic');
    } catch (e) {
      setError(formatWalletError(e, t('error.invalid.recovery.phrase')));
    } finally {
      setLoading(false);
    }
  };

  const restoreKey = async () => {
    setError('');
    setLoading(true);
    try {
      const addr = WalletService.importPrivateKey(privateKey);
      await finishWallet([], addr, 'privateKey', privateKey.replace(/^0x/i, ''));
    } catch (e) {
      setError(formatWalletError(e, 'Invalid private key'));
    } finally {
      setLoading(false);
    }
  };

  const finishOnboarding = async () => {
    if (initialStep === 'welcome') {
      await WalletSession.markOnboardingComplete();
    }
    onComplete();
  };

  if (showSeedSecurity) {
    return (
      <SeedPhraseSecuritySheet
        onContinue={() => { setShowSeedSecurity(false); setStep('restorePhrase'); }}
        onClose={() => setShowSeedSecurity(false)}
      />
    );
  }

  if (step === 'welcome') {
    return (
      <div className="mesh-screen">
        <div className="mesh-scroll mesh-welcome-screen">
          <img src="/branding/mesh-logo.png" alt="Mesh" className="mesh-logo-wordmark mesh-logo-wordmark-large" />
          <p className="mesh-subtitle">{t(L10nKeys.welcome.tagline)}</p>
        </div>
        <div className="mesh-footer-actions">
          <MeshSecondaryButton title={t(L10nKeys.welcome.restore)} onClick={() => setStep('addExisting')} />
          <MeshPrimaryButton title={t(L10nKeys.welcome.create)} onClick={() => setStep('createLaunch')} />
        </div>
        <p style={{ textAlign: 'center', fontSize: 12, color: 'var(--mesh-text-tertiary)', padding: '0 24px 16px' }}>
          {t(L10nKeys.welcome.legalPrefix)}{' '}
          <a href={LINKS.terms} target="_blank" rel="noreferrer">{t(L10nKeys.welcome.terms)}</a>{' '}
          {t(L10nKeys.common.and)}{' '}
          <a href={LINKS.privacy} target="_blank" rel="noreferrer">{t(L10nKeys.welcome.privacy)}</a>
        </p>
      </div>
    );
  }

  if (step === 'createLaunch') {
    const backFromCreate = () => {
      createStartedRef.current = false;
      setError('');
      if (isAddWalletFlow) onCancel?.();
      else setStep('welcome');
    };

    return (
      <div className="mesh-screen mesh-create-launch">
        {error ? (
          <div className="mesh-create-launch-error">
            <p className="mesh-error">{error}</p>
            <MeshSecondaryButton title={t(L10nKeys.common.close)} onClick={backFromCreate} />
          </div>
        ) : (
          <div className="mesh-spinner" aria-label={t('common.generating')} />
        )}
      </div>
    );
  }

  if (step === 'addExisting') {
    return (
      <div className="mesh-screen">
        <MeshFlowScreenHeader title={t('onboarding.add.existing.title')} onBack={backFromAddExisting} />
        <div style={{ padding: 'var(--mesh-padding)' }}>
          <MeshSecondaryButton title={t('onboarding.restore.phrase.title')} onClick={() => setShowSeedSecurity(true)} style={{ marginBottom: 12 }} />
          <MeshSecondaryButton title={t('onboarding.restore.key.title')} onClick={() => setStep('restorePrivateKey')} />
        </div>
      </div>
    );
  }

  if (step === 'restorePhrase') {
    return (
      <div className="mesh-screen">
        <MeshFlowScreenHeader title={t(L10nKeys.onboarding.restorePhraseTitle)} onBack={() => setStep('addExisting')} />
        <div style={{ padding: 'var(--mesh-padding)' }}>
          <input className="mesh-field" placeholder="Wallet name (optional)" value={walletName} onChange={(e) => setWalletName(e.target.value)} style={{ marginBottom: 12 }} />
          <textarea className="mesh-field" rows={4} placeholder={t(L10nKeys.onboarding.restorePhrasePlaceholder)} value={restoreWords} onChange={(e) => setRestoreWords(e.target.value)} />
          {error && <p className="mesh-error">{error}</p>}
        </div>
        <div className="mesh-footer-actions">
          <MeshPrimaryButton title={t(L10nKeys.common.continue)} disabled={loading} onClick={restorePhrase} />
        </div>
      </div>
    );
  }

  if (step === 'restorePrivateKey') {
    return (
      <div className="mesh-screen">
        <MeshFlowScreenHeader title={t('onboarding.restore.key.title')} onBack={() => setStep('addExisting')} />
        <div style={{ padding: 'var(--mesh-padding)' }}>
          <input className="mesh-field" placeholder={t('onboarding.restore.key.placeholder')} value={privateKey} onChange={(e) => setPrivateKey(e.target.value)} />
          {error && <p className="mesh-error">{error}</p>}
        </div>
        <div className="mesh-footer-actions">
          <MeshPrimaryButton title={t(L10nKeys.common.continue)} disabled={loading} onClick={restoreKey} />
        </div>
      </div>
    );
  }

  if (step === 'setupPassword' || step === 'confirmPassword') {
    return (
      <div className="mesh-screen">
        <PasswordForm
          key={step}
          title={step === 'setupPassword'
            ? t(L10nKeys.security.createPasscode)
            : t(L10nKeys.security.confirmPasscode)}
          variant={step === 'setupPassword' ? 'create' : 'confirm'}
          error={error}
          submitLabel={t(L10nKeys.common.continue)}
          onSubmit={savePassword}
        />
      </div>
    );
  }

  if (step === 'walletReady') {
    const screen = (
      <WalletReadyScreen language={language} onStart={finishOnboarding} />
    );
    if (isAddWalletFlow) return screen;
    return <div className="mesh-overlay">{screen}</div>;
  }

  return null;
}
