import { useState, type FormEvent } from 'react';
import { PasscodeStore } from '@/core/storage/passcode';

interface PasswordFormProps {
  title: string;
  subtitle?: string;
  error?: string;
  submitLabel?: string;
  variant?: 'create' | 'confirm' | 'unlock';
  onSubmit: (password: string) => void | Promise<void>;
  onCancel?: () => void;
  autoFocus?: boolean;
}

export function PasswordForm({
  title,
  subtitle,
  error,
  submitLabel = 'Continue',
  variant = 'unlock',
  onSubmit,
  onCancel,
  autoFocus = true,
}: PasswordFormProps) {
  const [password, setPassword] = useState('');
  const [visible, setVisible] = useState(false);
  const [localError, setLocalError] = useState('');

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setLocalError('');

    if (!PasscodeStore.isValidPassword(password)) {
      setLocalError(`Password must be at least ${PasscodeStore.minLength} characters`);
      return;
    }

    await onSubmit(password);
  };

  const displayError = error || localError;
  const autoComplete = variant === 'confirm'
    ? 'off'
    : variant === 'create'
      ? 'new-password'
      : 'current-password';

  return (
    <div className="mesh-password-screen">
      <div className="mesh-password-body">
        <h1 className="mesh-title mesh-password-title">{title}</h1>
        {subtitle && <p className="mesh-subtitle mesh-password-subtitle">{subtitle}</p>}

        <form className="mesh-password-form" onSubmit={handleSubmit}>
          <div className="mesh-password-field-wrap">
            <input
              className="mesh-field mesh-password-input"
              type={visible ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Password"
              autoFocus={autoFocus}
              autoComplete={autoComplete}
              maxLength={PasscodeStore.maxLength}
            />
            <button
              type="button"
              className="mesh-password-toggle"
              onClick={() => setVisible((v) => !v)}
              aria-label={visible ? 'Hide password' : 'Show password'}
            >
              {visible ? 'Hide' : 'Show'}
            </button>
          </div>

          {displayError && <p className="mesh-error mesh-password-error">{displayError}</p>}

          <button type="submit" className="mesh-btn-primary mesh-password-submit" disabled={!password}>
            {submitLabel}
          </button>

          {onCancel && (
            <button type="button" className="mesh-btn-secondary mesh-password-cancel" onClick={onCancel}>
              Cancel
            </button>
          )}
        </form>
      </div>
    </div>
  );
}
