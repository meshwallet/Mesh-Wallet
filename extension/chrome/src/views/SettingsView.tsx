import { useState } from 'react';
import { LINKS } from '@/core/config';
import { getExtensionVersion } from '@/core/extension-asset';
import { useApp, PasscodeStore } from '@/core/context/AppContext';
import { WalletCredentials } from '@/services/tron/wallet-service';
import { WalletRegistry } from '@/core/storage/wallet-registry';
import { PasswordForm } from '@/components/PasswordForm';
import type { Language } from '@/core/types';

interface SettingsViewProps {
  onClose: () => void;
  onOpenPrivacy: () => void;
}

export function SettingsView({ onClose, onOpenPrivacy }: SettingsViewProps) {
  const { activeWallet, wallets, language, setLanguage, refreshWallet } = useApp();
  const [showVerify, setShowVerify] = useState(false);
  const [phrase, setPhrase] = useState<string | null>(null);
  const [verifyError, setVerifyError] = useState('');

  const revealPhrase = async (password: string) => {
    const enabled = await PasscodeStore.isEnabled();
    if (enabled) {
      const ok = await PasscodeStore.verify(password);
      if (!ok) {
        setVerifyError('Incorrect password');
        return;
      }
    }
    if (!activeWallet) return;
    const creds = await WalletCredentials.resolve(activeWallet.id);
    setPhrase(creds.mnemonic?.join(' ') ?? 'Private key wallet — no recovery phrase');
    setShowVerify(false);
    setVerifyError('');
  };

  const openRecovery = async () => {
    const enabled = await PasscodeStore.isEnabled();
    if (enabled) {
      setShowVerify(true);
      return;
    }
    if (!activeWallet) return;
    const creds = await WalletCredentials.resolve(activeWallet.id);
    setPhrase(creds.mnemonic?.join(' ') ?? 'Private key wallet — no recovery phrase');
  };

  const removeWallet = async () => {
    if (!activeWallet || wallets.length < 2) return;
    if (!confirm('Remove this wallet from this device?')) return;
    await WalletRegistry.removeWallet(activeWallet.id);
    await refreshWallet();
    onClose();
  };

  if (showVerify) {
    return (
      <div className="mesh-slide-panel">
        <PasswordForm
          title="Enter password"
          subtitle="Required to view recovery phrase"
          error={verifyError}
          submitLabel="Continue"
          onSubmit={revealPhrase}
          onCancel={() => setShowVerify(false)}
        />
      </div>
    );
  }

  return (
    <div className="mesh-slide-panel">
      <div className="mesh-header">
        <button type="button" className="mesh-btn-chrome" onClick={onClose}>×</button>
        <span className="mesh-header-title">Settings</span>
        <div style={{ width: 48 }} />
      </div>
      <div className="mesh-scroll" style={{ padding: 'var(--mesh-padding)' }}>
        <div className="mesh-settings-row">
          <span>Language</span>
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

        <button type="button" className="mesh-settings-row" style={{ width: '100%' }} onClick={onOpenPrivacy}>
          <span>Privacy</span>
          <span>→</span>
        </button>

        <button type="button" className="mesh-settings-row" style={{ width: '100%' }} onClick={openRecovery}>
          <span>Recovery phrase</span>
          <span>→</span>
        </button>

        {phrase && (
          <div className="mesh-card" style={{ marginTop: 16 }}>
            <p className="mesh-subtitle" style={{ marginBottom: 8 }}>Recovery phrase</p>
            <p style={{ lineHeight: 1.6 }}>{phrase}</p>
          </div>
        )}

        {wallets.length >= 2 && (
          <button type="button" className="mesh-btn-secondary" style={{ marginTop: 24, color: '#ff6b6b' }} onClick={removeWallet}>
            Remove wallet
          </button>
        )}

        <div style={{ marginTop: 32 }}>
          <a href={LINKS.support} target="_blank" rel="noreferrer" className="mesh-subtitle">Support</a>
          <p className="mesh-subtitle" style={{ marginTop: 8 }}>Mesh Wallet v{getExtensionVersion()}</p>
        </div>
      </div>
    </div>
  );
}
