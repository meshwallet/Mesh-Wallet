import { useState } from 'react';
import { shortAddress } from '@/core/config';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { WalletRegistry } from '@/core/storage/wallet-registry';
import { WalletCredentials } from '@/services/tron/wallet-service';
import { PasswordForm } from '@/components/PasswordForm';
import { PasscodeStore } from '@/core/storage/passcode';
import { OnboardingFlow } from '@/views/OnboardingFlow';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';
import { MeshConfirmDialog, MeshPromptDialog } from '@/components/ui/MeshPromptDialog';
import type { StoredWallet } from '@/core/types';

interface Props {
  onClose: () => void;
  presentation?: 'sheet' | 'drawer';
}

export function WalletSelectSheet({ onClose, presentation = 'sheet' }: Props) {
  const { wallets, activeWallet, language, refreshWallet } = useApp();
  const { t } = useT(language);
  const [menuWalletId, setMenuWalletId] = useState<string | null>(null);
  const [renameWalletId, setRenameWalletId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [renameError, setRenameError] = useState('');
  const [removeWalletId, setRemoveWalletId] = useState<string | null>(null);
  const [backupWalletId, setBackupWalletId] = useState<string | null>(null);
  const [backupVerifyError, setBackupVerifyError] = useState('');
  const [phrase, setPhrase] = useState<string | null>(null);
  const [phraseCopied, setPhraseCopied] = useState(false);
  const [addFlow, setAddFlow] = useState<'existing' | 'create' | null>(null);

  const switchWallet = async (walletId: string) => {
    if (activeWallet?.id !== walletId) {
      await WalletRegistry.setActiveWallet(walletId);
      await refreshWallet();
    }
    onClose();
  };

  const openRename = (wallet: StoredWallet) => {
    setMenuWalletId(null);
    setRenameWalletId(wallet.id);
    setRenameDraft(wallet.name);
    setRenameError('');
  };

  const saveRename = async () => {
    if (!renameWalletId) return;
    const ok = await WalletRegistry.updateWalletName(renameWalletId, renameDraft);
    if (!ok) {
      setRenameError(t('error.wallet.name.taken'));
      return;
    }
    setRenameWalletId(null);
    setRenameDraft('');
    setRenameError('');
    await refreshWallet();
  };

  const removeWallet = async () => {
    if (!removeWalletId || wallets.length < 2) return;
    await WalletRegistry.removeWallet(removeWalletId);
    setRemoveWalletId(null);
    setMenuWalletId(null);
    await refreshWallet();
    const remaining = await WalletRegistry.getWallets();
    if (remaining.length === 0) {
      onClose();
    }
  };

  const removeTarget = removeWalletId ? wallets.find((w) => w.id === removeWalletId) : null;
  const removeMessage = removeTarget?.importKind === 'privateKey'
    ? t('settings.remove.confirm.key')
    : t('settings.remove.confirm.phrase');

  const openBackup = async (walletId: string) => {
    setMenuWalletId(null);
    setBackupWalletId(walletId);
    setPhrase(null);
    setBackupVerifyError('');
    const enabled = await PasscodeStore.isEnabled();
    if (!enabled) {
      const creds = await WalletCredentials.resolve(walletId);
      setPhrase(creds.mnemonic?.join(' ') ?? t('settings.recovery.unavailable'));
    }
  };

  const closeBackup = () => {
    setBackupWalletId(null);
    setBackupVerifyError('');
    setPhrase(null);
    setPhraseCopied(false);
  };

  if (addFlow) {
    return (
      <div className="mesh-overlay">
        <OnboardingFlow
          initialStep={addFlow === 'existing' ? 'addExisting' : 'createLaunch'}
          onComplete={() => { setAddFlow(null); refreshWallet(); onClose(); }}
          onCancel={() => setAddFlow(null)}
        />
      </div>
    );
  }

  if (backupWalletId) {
    return (
      <div className="mesh-overlay">
        <div className="mesh-slide-panel">
          <MeshFlowScreenHeader title={t('wallet.select.menu.backup')} onClose={closeBackup} />
          {!phrase ? (
            <PasswordForm
              title={t(L10nKeys.security.lockTitle)}
              error={backupVerifyError}
              submitLabel={t(L10nKeys.common.continue)}
              onSubmit={async (password) => {
                if (!(await PasscodeStore.verify(password))) {
                  setBackupVerifyError(t(L10nKeys.security.passcodeIncorrect));
                  return;
                }
                const creds = await WalletCredentials.resolve(backupWalletId);
                setPhrase(creds.mnemonic?.join(' ') ?? t('settings.recovery.unavailable'));
              }}
              onCancel={closeBackup}
            />
          ) : (
            <div className="mesh-scroll" style={{ padding: 'var(--mesh-padding)' }}>
              <p className="mesh-subtitle" style={{ marginBottom: 16 }}>
                {t('onboarding.recovery.never.share')}
              </p>
              <div className="mesh-seed-grid">
                {phrase.split(' ').map((word, i) => (
                  <div key={i} className="mesh-seed-word">{i + 1}. {word}</div>
                ))}
              </div>
              <button
                type="button"
                className="mesh-btn-secondary"
                style={{ marginTop: 16 }}
                onClick={async () => {
                  await navigator.clipboard.writeText(phrase);
                  setPhraseCopied(true);
                  setTimeout(() => setPhraseCopied(false), 2000);
                }}
              >
                {phraseCopied ? t(L10nKeys.common.copied) : t('onboarding.recovery.copy')}
              </button>
            </div>
          )}
        </div>
      </div>
    );
  }

  const list = (
    <>
      <MeshFlowScreenHeader title={t('wallet.select.title')} onClose={onClose} />
      <div className="mesh-wallet-select-list">
        {wallets.map((w) => {
          const isSelected = activeWallet?.id === w.id;
          return (
            <div key={w.id} className={`mesh-wallet-card ${isSelected ? 'selected' : ''}`}>
              <button type="button" className="mesh-wallet-card-main" onClick={() => switchWallet(w.id)}>
                <div className="mesh-wallet-card-icon" aria-hidden>M</div>
                <div className="mesh-wallet-card-body">
                  <span className="mesh-wallet-card-name">{w.name}</span>
                  <span className="mesh-wallet-card-subtitle">Tron · {shortAddress(w.address)}</span>
                </div>
              </button>
              <div className="mesh-wallet-card-menu-wrap">
                <button
                  type="button"
                  className="mesh-wallet-card-menu"
                  aria-label={t('wallet.select.menu.more')}
                  aria-expanded={menuWalletId === w.id}
                  onClick={(e) => {
                    e.stopPropagation();
                    setMenuWalletId(menuWalletId === w.id ? null : w.id);
                  }}
                >
                  ⋯
                </button>
                {menuWalletId === w.id && (
                  <div className="mesh-context-menu mesh-wallet-context-menu">
                    <button type="button" className="mesh-context-menu-item" onClick={() => openRename(w)}>
                      {t('wallet.select.menu.rename')}
                    </button>
                    {w.importKind === 'mnemonic' && (
                      <button
                        type="button"
                        className="mesh-context-menu-item"
                        onClick={() => {
                          setMenuWalletId(null);
                          void openBackup(w.id);
                        }}
                      >
                        {t('wallet.select.menu.backup')}
                      </button>
                    )}
                    {wallets.length > 1 && (
                      <button
                        type="button"
                        className="mesh-context-menu-item mesh-context-menu-item-destructive"
                        onClick={() => {
                          setMenuWalletId(null);
                          setRemoveWalletId(w.id);
                        }}
                      >
                        {t('wallet.select.menu.remove')}
                      </button>
                    )}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
      <div className="mesh-wallet-select-footer">
        <button type="button" className="mesh-btn-secondary" onClick={() => setAddFlow('existing')}>
          {t('wallet.select.add.existing')}
        </button>
        <button type="button" className="mesh-btn-primary" onClick={() => setAddFlow('create')}>
          {t('wallet.select.create.new')}
        </button>
      </div>
    </>
  );

  const dialogs = (
    <>
      {renameWalletId && (
        <MeshPromptDialog
          title={t('wallet.select.menu.rename')}
          value={renameDraft}
          onChange={(value) => {
            setRenameDraft(value);
            if (renameError) setRenameError('');
          }}
          error={renameError}
          placeholder={t('wallet.select.rename.placeholder')}
          confirmLabel={t(L10nKeys.common.ok)}
          cancelLabel={t(L10nKeys.common.cancel)}
          onConfirm={saveRename}
          onCancel={() => {
            setRenameWalletId(null);
            setRenameDraft('');
            setRenameError('');
          }}
        />
      )}
      {removeTarget && (
        <MeshConfirmDialog
          title={t('settings.remove.confirm.title')}
          message={removeMessage}
          confirmLabel={t('wallet.select.menu.remove')}
          cancelLabel={t(L10nKeys.common.cancel)}
          destructive
          onConfirm={removeWallet}
          onCancel={() => setRemoveWalletId(null)}
        />
      )}
    </>
  );

  if (presentation === 'drawer') {
    return (
      <>
        <div className="mesh-drawer">
          <div className="mesh-drawer-panel mesh-wallet-select-drawer">{list}</div>
          <div className="mesh-drawer-backdrop" onClick={onClose} aria-hidden />
        </div>
        {dialogs}
      </>
    );
  }

  return (
    <>
      <div className="mesh-sheet mesh-wallet-select-sheet">
        <div className="mesh-sheet-backdrop" onClick={onClose} />
        <div className="mesh-sheet-content mesh-wallet-select-content">{list}</div>
      </div>
      {dialogs}
    </>
  );
}
