import { useEffect, useState } from 'react';
import { PasswordForm } from '@/components/PasswordForm';
import { PasscodeStore } from '@/core/storage/passcode';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';

interface AppLockProps {
  onUnlock: () => void;
}

export function AppLock({ onUnlock }: AppLockProps) {
  const { language } = useApp();
  const { t } = useT(language);
  const [error, setError] = useState('');

  const verify = async (password: string) => {
    const ok = await PasscodeStore.verify(password);
    if (ok) {
      setError('');
      onUnlock();
    } else {
      setError(t(L10nKeys.security.passcodeIncorrect));
    }
  };

  return (
    <div className="mesh-overlay">
      <PasswordForm
        title={t(L10nKeys.security.lockTitle)}
        subtitle={t(L10nKeys.security.lockSubtitle)}
        variant="unlock"
        error={error}
        submitLabel={t(L10nKeys.common.continue)}
        onSubmit={verify}
      />
    </div>
  );
}

export function SplashScreen({ onDone }: { onDone: () => void }) {
  useEffect(() => {
    const timer = setTimeout(onDone, 1500);
    return () => clearTimeout(timer);
  }, [onDone]);

  return (
    <div className="mesh-splash">
      <img src="/branding/mesh-logo.png" alt="Mesh" className="mesh-logo-wordmark mesh-logo-wordmark-large" />
    </div>
  );
}
