import { useState } from 'react';
import { formatUSDT, receiveDisplayAddress, HIDDEN_BALANCE_COMPACT } from '@/core/config';
import { useT, L10nKeys } from '@/core/l10n';
import type { Language, ReceiveSlot } from '@/core/types';

interface Props {
  headerTitle: string;
  slots: ReceiveSlot[];
  selectedIndex: number;
  onSelect: (index: number) => void;
  language: Language;
  balanceHidden?: boolean;
  showsBalance?: boolean;
  /** iOS send/receive: stacked preview cards. */
  variant?: 'default' | 'stacked';
}

export function AddressSlotPicker({
  headerTitle,
  slots,
  selectedIndex,
  onSelect,
  language,
  balanceHidden = false,
  showsBalance = true,
  variant = 'default',
}: Props) {
  const { t } = useT(language);
  const [expanded, setExpanded] = useState(false);

  if (slots.length === 0) return null;

  const selected = slots.find((slot) => slot.index === selectedIndex) ?? slots[0];

  const slotTitle = (slot: ReceiveSlot) =>
    slot.index === 0 ? t(L10nKeys.receive.mainAddress) : slot.title;

  const slotBalance = (slot: ReceiveSlot) => {
    if (!showsBalance) return null;
    if (slot.balanceUSDT == null) return '…';
    if (balanceHidden) return HIDDEN_BALANCE_COMPACT;
    return `${formatUSDT(slot.balanceUSDT)} USDT`;
  };

  const pick = (index: number) => {
    onSelect(index);
    setExpanded(false);
  };

  const renderCard = (slot: ReceiveSlot, isSelected: boolean) => (
    <div className={`mesh-slot-card ${isSelected ? 'active' : ''}`}>
      <div className="mesh-slot-card-main">
        <div className="mesh-slot-card-head">
          <span className="mesh-slot-card-title">{slotTitle(slot)}</span>
          {slot.index === 0 && (
            <span className="mesh-slot-card-badge">{t('receive.main.badge')}</span>
          )}
        </div>
        <span className="mesh-slot-card-address">{receiveDisplayAddress(slot.address)}</span>
      </div>
      {showsBalance && (
        <span className="mesh-slot-card-balance">{slotBalance(slot)}</span>
      )}
    </div>
  );

  return (
    <div className={`mesh-slot-picker ${variant === 'stacked' ? 'mesh-slot-picker-stacked' : ''}`}>
      <button type="button" className="mesh-slot-picker-header" onClick={() => setExpanded((v) => !v)}>
        {headerTitle}
      </button>

      {!expanded ? (
        <>
          <button
            type="button"
            className="mesh-slot-card-btn"
            onClick={() => slots.length > 1 && setExpanded(true)}
            disabled={slots.length <= 1}
          >
            {renderCard(selected, true)}
          </button>
          {slots.length > 1 && (
            <button type="button" className="mesh-slot-show-more" onClick={() => setExpanded(true)}>
              <span>{t('receive.show.more')}</span>
              <span className="mesh-slot-show-more-chevron" aria-hidden>⌄</span>
            </button>
          )}
        </>
      ) : (
        <div className="mesh-slot-list">
          {slots.map((slot) => (
            <button
              key={slot.index}
              type="button"
              className="mesh-slot-card-btn"
              onClick={() => pick(slot.index)}
            >
              {renderCard(slot, selectedIndex === slot.index)}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
