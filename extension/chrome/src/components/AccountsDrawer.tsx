import { useState, useEffect, useCallback } from 'react';
import { CONFIG, formatUSDT, formatBalanceCompact } from '@/core/config';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { PrivacyStore } from '@/core/storage/privacy-store';
import { MeshConfirmDialog, MeshPromptDialog } from '@/components/ui/MeshPromptDialog';
import type { ReceiveSlot } from '@/core/types';

interface Props {
  onClose: () => void;
}

export function AccountsDrawer({ onClose }: Props) {
  const { activeWallet, balanceHidden, language, refreshWallet, receiveSlots, selectedSlotIndex } = useApp();
  const { t } = useT(language);
  const [menuIndex, setMenuIndex] = useState<number | null>(null);
  const [renameIndex, setRenameIndex] = useState<number | null>(null);
  const [renameDraft, setRenameDraft] = useState('');
  const [removeIndex, setRemoveIndex] = useState<number | null>(null);

  const load = useCallback(async () => {
    await refreshWallet();
  }, [refreshWallet]);

  useEffect(() => { void load(); }, [load]);

  if (!activeWallet) return null;

  const slots = receiveSlots;
  const selectedIndex = selectedSlotIndex;

  const selectSlot = async (index: number) => {
    await PrivacyStore.setSelectedSlotIndex(activeWallet.id, index);
    await refreshWallet();
    onClose();
  };

  const addAccount = async () => {
    const created = await PrivacyStore.addReceiveAddress(activeWallet.id);
    if (created != null) {
      await PrivacyStore.setSelectedSlotIndex(activeWallet.id, created);
      await refreshWallet();
    }
  };

  const openRename = (slot: ReceiveSlot) => {
    setMenuIndex(null);
    setRenameIndex(slot.index);
    setRenameDraft(slot.index === 0 ? '' : slot.title);
  };

  const saveRename = async () => {
    if (renameIndex == null) return;
    await PrivacyStore.setReceiveSlotName(activeWallet.id, renameIndex, renameDraft);
    setRenameIndex(null);
    setRenameDraft('');
    await refreshWallet();
  };

  const removeAccount = async () => {
    if (removeIndex == null || removeIndex <= 0) return;
    await PrivacyStore.removeReceiveSlot(activeWallet.id, removeIndex);
    setRemoveIndex(null);
    await refreshWallet();
  };

  const canAdd =
    activeWallet.importKind === 'mnemonic' &&
    slots.length < CONFIG.walletReceiveSlotCount;

  const slotTitle = (slot: ReceiveSlot) =>
    slot.index === 0 ? t(L10nKeys.receive.mainAddress) : slot.title;

  const formatBalance = (slot: ReceiveSlot) => {
    if (slot.balanceUSDT == null) return '…';
    return formatBalanceCompact(slot.balanceUSDT, balanceHidden);
  };

  const removeTarget = removeIndex != null ? slots.find((slot) => slot.index === removeIndex) : null;

  return (
    <>
      <div className="mesh-accounts-drawer">
        <div className="mesh-accounts-drawer-backdrop" onClick={onClose} aria-hidden />
        <div className="mesh-accounts-drawer-panel">
          <div className="mesh-accounts-drawer-header">
            <span className="mesh-accounts-drawer-icon" aria-hidden>☰</span>
            <span>{t('wallet.address.drawer.title')}</span>
          </div>

          <div className="mesh-accounts-drawer-list">
            {slots.map((slot) => {
              const isSelected = slot.index === selectedIndex;
              return (
                <div key={slot.index} className={`mesh-account-row ${isSelected ? 'active' : ''}`}>
                  <button
                    type="button"
                    className="mesh-account-row-main"
                    onClick={() => selectSlot(slot.index)}
                  >
                    <span className="mesh-account-row-title">{slotTitle(slot)}</span>
                    <span className="mesh-account-row-balance">{formatBalance(slot)}</span>
                  </button>
                  {slot.index > 0 && (
                    <div className="mesh-account-row-actions">
                      <button
                        type="button"
                        className="mesh-account-row-menu"
                        aria-label={t('wallet.select.menu.rename')}
                        aria-expanded={menuIndex === slot.index}
                        onClick={(e) => {
                          e.stopPropagation();
                          setMenuIndex(menuIndex === slot.index ? null : slot.index);
                        }}
                      >
                        ⋯
                      </button>
                      {menuIndex === slot.index && (
                        <div className="mesh-context-menu mesh-account-context-menu">
                          <button
                            type="button"
                            className="mesh-context-menu-item"
                            onClick={() => openRename(slot)}
                          >
                            {t('wallet.select.menu.rename')}
                          </button>
                          <button
                            type="button"
                            className="mesh-context-menu-item mesh-context-menu-item-destructive"
                            onClick={() => {
                              setMenuIndex(null);
                              setRemoveIndex(slot.index);
                            }}
                          >
                            {t('wallet.select.menu.remove')}
                          </button>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}

            {canAdd && (
              <button type="button" className="mesh-account-add" onClick={addAccount} aria-label={t('wallet.address.drawer.create.action')}>
                +
              </button>
            )}
          </div>

          <p className="mesh-accounts-drawer-footer">{t('wallet.address.drawer.subtitle')}</p>
        </div>
      </div>

      {renameIndex != null && (
        <MeshPromptDialog
          title={t('wallet.address.drawer.rename.title')}
          value={renameDraft}
          onChange={setRenameDraft}
          placeholder={t('wallet.address.drawer.create.placeholder')}
          confirmLabel={t('wallet.address.drawer.rename.action')}
          cancelLabel={t(L10nKeys.common.cancel)}
          onConfirm={saveRename}
          onCancel={() => {
            setRenameIndex(null);
            setRenameDraft('');
          }}
        />
      )}

      {removeTarget && (
        <MeshConfirmDialog
          title={t('receive.delete.address.title')}
          message={t('receive.delete.address.message', slotTitle(removeTarget))}
          confirmLabel={t('wallet.select.menu.remove')}
          cancelLabel={t(L10nKeys.common.cancel)}
          destructive
          onConfirm={removeAccount}
          onCancel={() => setRemoveIndex(null)}
        />
      )}
    </>
  );
}
