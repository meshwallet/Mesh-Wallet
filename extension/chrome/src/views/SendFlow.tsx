import { useState, useEffect, useCallback } from 'react';
import {
  formatUSDT,
  formatBalanceWithUnit,
  formattedFee,
  isValidTronAddress,
  networkFee,
  parseAmount,
  sanitizeAmountInput,
  sendTotalDebit,
  shortAddress,
  SEND_FEES,
} from '@/core/config';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { PrivacyStore } from '@/core/storage/privacy-store';
import { PrivacyService } from '@/services/mesh/privacy-service';
import { BackgroundSendService } from '@/services/background-send-service';
import { MeshRelay } from '@/services/mesh/relay-client';
import { AddressSlotPicker } from '@/components/AddressSlotPicker';
import { SendToSelfSheet } from '@/components/SendToSelfSheet';
import { SlideToSend } from '@/components/SlideToSend';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';
import { MeshPrimaryButton } from '@/components/ui/MeshButtons';
import { SendSubmittedView } from '@/views/SendSubmittedView';
import { SendFailedView } from '@/views/SendFailedView';
import type { ReceiveSlot } from '@/core/types';

type Step = 'address' | 'review' | 'submitted' | 'failed';

export function SendFlow({ onClose }: { onClose: () => void }) {
  const { activeWallet, balanceHidden, language } = useApp();
  const { t } = useT(language);
  const [step, setStep] = useState<Step>('address');
  const [recipient, setRecipient] = useState('');
  const [amountText, setAmountText] = useState('');
  const [error, setError] = useState('');
  const [addressError, setAddressError] = useState('');
  const [amountError, setAmountError] = useState('');
  const [showSendToSelf, setShowSendToSelf] = useState(false);
  const [formKey, setFormKey] = useState(0);
  const [slots, setSlots] = useState<ReceiveSlot[]>([]);
  const [selectedSlotIndex, setSelectedSlotIndex] = useState(0);
  const [slotBalance, setSlotBalance] = useState(0);
  const [sentSendId, setSentSendId] = useState('');
  const [sentFromAddress, setSentFromAddress] = useState('');

  const loadSlots = useCallback(async () => {
    if (!activeWallet) return;
    const idx = await PrivacyStore.selectedSlotIndex(activeWallet.id);
    const nextSlots = await PrivacyService.listReceiveSlotsWithBalances(activeWallet.id);
    setSlots(nextSlots);
    const nextIndex = nextSlots.some((slot) => slot.index === idx) ? idx : 0;
    setSelectedSlotIndex(nextIndex);
    const active = nextSlots.find((slot) => slot.index === nextIndex) ?? nextSlots[0];
    setSlotBalance(active?.balanceUSDT ?? 0);
  }, [activeWallet]);

  useEffect(() => { loadSlots(); }, [loadSlots]);

  const selectSlot = async (index: number) => {
    setSelectedSlotIndex(index);
    const slot = slots.find((item) => item.index === index);
    setSlotBalance(slot?.balanceUSDT ?? 0);
    if (activeWallet) await PrivacyStore.setSelectedSlotIndex(activeWallet.id, index);
  };

  const availableBalance = slots.length > 1 ? slotBalance : slots[0]?.balanceUSDT ?? 0;
  const amount = parseAmount(amountText) ?? 0;
  const fee = networkFee();
  const totalDebit = sendTotalDebit(amount);

  const isHdWallet = activeWallet?.importKind === 'mnemonic';
  const availableLabel = formatBalanceWithUnit(availableBalance, balanceHidden);
  const availableText = slots.length > 1
    ? t('send.available.on.slot', availableLabel)
    : t('send.available', availableLabel);

  const validate = (): boolean => {
    setAddressError('');
    setAmountError('');
    setError('');
    if (!isValidTronAddress(recipient)) {
      setAddressError(t('send.address.invalid'));
      return false;
    }
    if (amount <= 0) {
      setAmountError(t('send.amount.invalid'));
      return false;
    }
    if (SEND_FEES.showsFeeInUI && fee > 0 && amount <= fee) {
      setAmountError(t('error.amount.below.fee', formattedFee(fee)));
      return false;
    }
    if (totalDebit > availableBalance) {
      setAmountError(t('error.amount.exceeds'));
      return false;
    }
    return true;
  };

  const selfTransferDestinationSlots = slots.filter(
    (slot) => slot.index !== selectedSlotIndex && slot.address.trim().length > 0,
  );
  const canSendToSelf = selfTransferDestinationSlots.length > 0;

  const applySelfTransferRecipient = (slot: ReceiveSlot) => {
    setRecipient(slot.address);
    setAddressError('');
  };

  const useMax = () => {
    if (availableBalance > 0) {
      setAmountText(formatUSDT(availableBalance).replace(',', '.'));
    }
  };

  const beginSendFromReview = async () => {
    if (!activeWallet || !validate()) return;
    if (!MeshRelay.isConfigured) {
      setError('Send service is temporarily unavailable. Please try again in a few minutes.');
      setStep('failed');
      return;
    }

    const slotIndex = slots.length > 1 ? selectedSlotIndex : (slots[0]?.index ?? 0);
    const activeSlot = slots.find((slot) => slot.index === slotIndex) ?? slots[0];
    setSentFromAddress(activeSlot?.address ?? activeWallet.address);

    const sendId = await BackgroundSendService.prepareForHandoff({
      walletId: activeWallet.id,
      recipient: recipient.trim(),
      amount,
      amountText,
      slotIndex,
    });

    setSentSendId(sendId);
    setStep('submitted');

    BackgroundSendService.startHandoffForPendingSend(sendId, {
      walletId: activeWallet.id,
      recipient: recipient.trim(),
      amount,
      amountText,
      slotIndex,
    });
  };

  if (step === 'address') {
    return (
      <div className="mesh-slide-panel" key={formKey}>
        <MeshFlowScreenHeader
          title={t(L10nKeys.send.title)}
          onClose={onClose}
          trailing={t('send.step.address')}
        />
        <div className="mesh-scroll mesh-send-form">
          {isHdWallet && slots.length > 0 && (
            <section className="mesh-send-section-block">
              <AddressSlotPicker
                headerTitle={t(L10nKeys.send.fromAddress)}
                slots={slots}
                selectedIndex={selectedSlotIndex}
                onSelect={selectSlot}
                language={language}
                balanceHidden={balanceHidden}
                variant="stacked"
              />
            </section>
          )}

          <section className="mesh-send-section-block">
            <label className="mesh-send-section-label">{t('send.step.recipient')}</label>
            <input
              className="mesh-field mesh-send-recipient-field"
              placeholder={t('send.address.placeholder')}
              value={recipient}
              onChange={(e) => {
                setRecipient(e.target.value);
                setAddressError('');
              }}
            />
            {addressError && <p className="mesh-send-inline-error">{addressError}</p>}
            {canSendToSelf && (
              <div className="mesh-send-recipient-actions">
                <button type="button" className="mesh-send-field-btn" onClick={() => setShowSendToSelf(true)}>
                  {t(L10nKeys.send.sendToSelf)}
                </button>
              </div>
            )}
          </section>

          <section className="mesh-send-section-block">
            <label className="mesh-send-section-label">{t('send.step.amount')}</label>
            <div className="mesh-send-amount-row">
              <input
                className="mesh-send-amount-input"
                placeholder="0"
                value={amountText}
                onChange={(e) => {
                  setAmountText(sanitizeAmountInput(e.target.value));
                  setAmountError('');
                }}
                inputMode="decimal"
              />
              <span className="mesh-send-amount-unit">USDT</span>
            </div>
            {amountError && <p className="mesh-send-inline-error">{amountError}</p>}
            <div className="mesh-send-amount-meta">
              <button type="button" className="mesh-send-max-chip" onClick={useMax}>
                {t(L10nKeys.send.useMax)}
              </button>
              <span className="mesh-send-available-caption">{availableText}</span>
            </div>
          </section>

          <section className="mesh-send-section-block">
            <label className="mesh-send-section-label">{t('send.review.network')}</label>
            <div className="mesh-send-protection-card">
              <p className="mesh-send-network-line">{t('send.no.trx.needed')}</p>
              <p className="mesh-send-network-line">{t('send.network.resources')}</p>
              {SEND_FEES.showsFeeInUI && (
                <div className="mesh-send-protection-row">
                  <span>{t('send.fee.label')}</span>
                  <span>{formattedFee(fee)}</span>
                </div>
              )}
            </div>
          </section>
        </div>
        <div className="mesh-footer-actions">
          <MeshPrimaryButton title={t(L10nKeys.common.next)} onClick={() => validate() && setStep('review')} />
        </div>
        {showSendToSelf && (
          <SendToSelfSheet
            slots={selfTransferDestinationSlots}
            language={language}
            balanceHidden={balanceHidden}
            onSelect={applySelfTransferRecipient}
            onClose={() => setShowSendToSelf(false)}
          />
        )}
      </div>
    );
  }

  if (step === 'review') {
    return (
      <div className="mesh-slide-panel">
        <MeshFlowScreenHeader title={t(L10nKeys.send.reviewTitle)} onBack={() => setStep('address')} />
        <div className="mesh-scroll mesh-send-review">
          {slots.length > 1 && (
            <div className="mesh-flow-card">
              <p className="mesh-subtitle">{t(L10nKeys.send.fromAddress)}</p>
              <p className="mesh-flow-card-value">
                {(slots.find((slot) => slot.index === selectedSlotIndex) ?? slots[0])?.title ?? t(L10nKeys.receive.mainAddress)}
              </p>
            </div>
          )}
          <div className="mesh-flow-card">
            <p className="mesh-subtitle">{t('send.review.to')}</p>
            <p className="mesh-flow-card-value">{shortAddress(recipient)}</p>
          </div>
          <div className="mesh-flow-card">
            <p className="mesh-subtitle">{t('send.review.total')}</p>
            <p className="mesh-send-review-amount">{formatUSDT(totalDebit)} USDT</p>
          </div>
          <div className="mesh-flow-card">
            <p className="mesh-subtitle">{t('send.fee.label')}</p>
            <p className="mesh-flow-card-value">{formattedFee(fee)}</p>
          </div>
        </div>
        <div className="mesh-footer-actions">
          <SlideToSend label={t(L10nKeys.send.slideConfirm)} onComplete={beginSendFromReview} />
        </div>
      </div>
    );
  }

  if (step === 'submitted' && sentSendId) {
    return (
      <SendSubmittedView
        sendId={sentSendId}
        sendContext={{
          walletId: activeWallet!.id,
          recipient: recipient.trim(),
          amount,
          amountText,
          slotIndex: slots.length > 1 ? selectedSlotIndex : (slots[0]?.index ?? 0),
        }}
        onClose={onClose}
      />
    );
  }

  if (step === 'failed') {
    return (
      <SendFailedView
        amount={amount}
        recipient={recipient.trim()}
        fromAddress={sentFromAddress || activeWallet?.address || ''}
        errorMessage={error}
        onClose={onClose}
      />
    );
  }

  return null;
}
