import { useEffect, useState } from 'react';
import { PasscodeStore } from '@/core/storage/passcode';
import { PasswordForm } from '@/components/PasswordForm';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';

type Step = 'current' | 'new' | 'confirm';

export function ChangePasscodeFlow({ onClose }: { onClose: () => void }) {
  const { language } = useApp();
  const { t } = useT(language);
  const [step, setStep] = useState<Step>('current');
  const [passwordDraft, setPasswordDraft] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    void PasscodeStore.isEnabled().then((enabled) => {
      if (!enabled) setStep('new');
    });
  }, []);

  const handleSubmit = async (password: string) => {
    setError('');

    if (step === 'current') {
      if (!(await PasscodeStore.verify(password))) {
        setError(t(L10nKeys.security.passcodeIncorrect));
        return;
      }
      setStep('new');
      return;
    }

    if (step === 'new') {
      if (!PasscodeStore.isValidPassword(password)) {
        setError(t(L10nKeys.security.passwordTooShort));
        return;
      }
      setPasswordDraft(password);
      setStep('confirm');
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
    onClose();
  };

  const title = step === 'current'
    ? t(L10nKeys.security.lockTitle)
    : step === 'new'
      ? t(L10nKeys.security.createPasscode)
      : t(L10nKeys.security.confirmPasscode);

  return (
    <div className="mesh-slide-panel">
      <MeshFlowScreenHeader title={t(L10nKeys.settings.passcodeChange)} onClose={onClose} />
      <PasswordForm
        key={step}
        title={title}
        variant={step === 'current' ? 'unlock' : step === 'new' ? 'create' : 'confirm'}
        error={error}
        submitLabel={step === 'confirm' ? t(L10nKeys.common.done) : t(L10nKeys.common.continue)}
        onSubmit={handleSubmit}
      />
    </div>
  );
}
