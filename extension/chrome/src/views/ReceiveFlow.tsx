import { useState, useEffect, useCallback } from 'react';
import QRCode from 'qrcode';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { PrivacyStore } from '@/core/storage/privacy-store';
import { PrivacyService } from '@/services/mesh/privacy-service';
import { receiveDisplayAddress } from '@/core/config';
import { AddressSlotPicker } from '@/components/AddressSlotPicker';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';
import { MeshSecondaryButton } from '@/components/ui/MeshButtons';
import type { ReceiveSlot } from '@/core/types';

export function ReceiveFlow({ onClose }: { onClose: () => void }) {
  const { activeWallet, balanceHidden, language } = useApp();
  const { t } = useT(language);
  const [slots, setSlots] = useState<ReceiveSlot[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [qrDataUrl, setQrDataUrl] = useState('');
  const [copied, setCopied] = useState(false);

  const loadSlots = useCallback(async () => {
    if (!activeWallet) return;
    const idx = await PrivacyStore.selectedSlotIndex(activeWallet.id);
    const s = await PrivacyService.listReceiveSlotsWithBalances(activeWallet.id);
    setSlots(s);
    const nextIndex = s.some((slot) => slot.index === idx) ? idx : 0;
    setSelectedIndex(nextIndex);
    if (nextIndex !== idx) await PrivacyStore.setSelectedSlotIndex(activeWallet.id, nextIndex);
  }, [activeWallet]);

  useEffect(() => { loadSlots(); }, [loadSlots]);

  const activeSlot = slots.find((s) => s.index === selectedIndex) ?? slots[0];
  const address = activeSlot?.address ?? '';

  useEffect(() => {
    if (!address) return;
    QRCode.toDataURL(address, { width: 220, margin: 1, color: { dark: '#000000', light: '#ffffff' } }).then(setQrDataUrl);
  }, [address]);

  const copy = async () => {
    await navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const share = async () => {
    const text = `${address}\n\n${t(L10nKeys.receive.shareFooter)}`;
    if (navigator.share) {
      try {
        await navigator.share({ title: t(L10nKeys.receive.title), text });
        return;
      } catch { /* fall through */ }
    }
    await copy();
  };

  const selectSlot = async (index: number) => {
    setSelectedIndex(index);
    if (activeWallet) await PrivacyStore.setSelectedSlotIndex(activeWallet.id, index);
  };

  return (
    <div className="mesh-slide-panel">
      <MeshFlowScreenHeader title={t(L10nKeys.receive.title)} onClose={onClose} />
      <div className="mesh-scroll mesh-receive-body">
        <div className="mesh-receive-qr-wrap">
          {qrDataUrl ? (
            <div className="mesh-qr-frame">
              <img src={qrDataUrl} alt="QR code" width={220} height={220} />
            </div>
          ) : (
            <div className="mesh-qr-frame mesh-qr-placeholder" />
          )}
        </div>

        {slots.length <= 1 && (
          <p className="mesh-receive-caption">
            {activeSlot?.index === 0 ? t(L10nKeys.receive.mainAddress) : activeSlot?.title}
          </p>
        )}

        {slots.length > 1 && (
          <AddressSlotPicker
            headerTitle={t('receive.on.address')}
            slots={slots}
            selectedIndex={selectedIndex}
            onSelect={selectSlot}
            language={language}
            balanceHidden={balanceHidden}
          />
        )}

        <div className="mesh-receive-address-block">
          <button type="button" className="mesh-receive-address-pill" onClick={copy} disabled={!address}>
          <span className="mesh-receive-address-pill-text">{receiveDisplayAddress(address)}</span>
          <svg className="mesh-receive-address-pill-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden>
            <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
        <p className={`mesh-receive-copied ${copied ? 'visible' : ''}`}>{t(L10nKeys.common.copied)}</p>

          <p className="mesh-receive-network">Network: Tron (TRC-20)</p>
        </div>

        <div className="mesh-receive-actions">
          <MeshSecondaryButton title={t('receive.share')} disabled={!address} onClick={share} />
        </div>
        <p className="mesh-subtitle mesh-receive-footer">{t(L10nKeys.receive.shareFooter)}</p>
      </div>
    </div>
  );
}
