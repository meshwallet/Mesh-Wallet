import { formatUSDT, receiveDisplayAddress, HIDDEN_BALANCE_COMPACT } from '@/core/config';
import { useT, L10nKeys } from '@/core/l10n';
import type { Language, ReceiveSlot } from '@/core/types';

interface Props {
  slots: ReceiveSlot[];
  language: Language;
  balanceHidden?: boolean;
  onSelect: (slot: ReceiveSlot) => void;
  onClose: () => void;
}

export function SendToSelfSheet({ slots, language, balanceHidden, onSelect, onClose }: Props) {
  const { t } = useT(language);

  const slotTitle = (slot: ReceiveSlot) =>
    slot.index === 0 ? t(L10nKeys.receive.mainAddress) : slot.title;

  const slotBalance = (slot: ReceiveSlot) => {
    if (slot.balanceUSDT == null) return '…';
    if (balanceHidden) return HIDDEN_BALANCE_COMPACT;
    return `${formatUSDT(slot.balanceUSDT)} USDT`;
  };

  return (
    <div className="mesh-sheet mesh-send-to-self-sheet">
      <div className="mesh-sheet-backdrop" onClick={onClose} />
      <div className="mesh-sheet-content mesh-send-to-self-content">
        <h2 className="mesh-send-to-self-title">{t(L10nKeys.send.sendToSelf)}</h2>
        <div className="mesh-send-to-self-list">
          {slots.map((slot) => (
            <button
              key={slot.index}
              type="button"
              className="mesh-send-to-self-row"
              onClick={() => {
                onSelect(slot);
                onClose();
              }}
            >
              <div className="mesh-send-to-self-row-main">
                <div className="mesh-send-to-self-row-head">
                  <span className="mesh-send-to-self-row-title">{slotTitle(slot)}</span>
                  {slot.index === 0 && (
                    <span className="mesh-send-to-self-badge">{t('receive.main.badge')}</span>
                  )}
                </div>
                <span className="mesh-send-to-self-row-address">
                  {receiveDisplayAddress(slot.address)}
                </span>
              </div>
              <div className="mesh-send-to-self-row-meta">
                <span className="mesh-send-to-self-row-balance">{slotBalance(slot)}</span>
                <span className="mesh-send-to-self-chevron" aria-hidden>›</span>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
