import { useState, useMemo, useCallback, useEffect } from 'react';
import { formatUSDT, balancePrivacyClass } from '@/core/config';
import type { ActivityFilter, WalletTransaction, DeepRecoveryState } from '@/core/types';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { PrivacyService } from '@/services/mesh/privacy-service';
import { SendFlow } from './SendFlow';
import { ReceiveFlow } from './ReceiveFlow';
import { SecurityView } from './SecurityView';
import { PrivacyView } from './PrivacyView';
import { TransactionDetail } from './TransactionDetail';
import { AccountsDrawer } from '@/components/AccountsDrawer';
import { WalletSelectSheet } from './WalletSelectSheet';

function txListTitle(tx: WalletTransaction, t: (k: string) => string): string {
  if (tx.transferStatus === 'processing') {
    return tx.kind === 'sent' ? t('transaction.processing') : t('transaction.received');
  }
  if (tx.transferStatus === 'failed') return t('send.failed');
  return tx.title;
}

export function WalletHome() {
  const {
    activeWallet,
    balance,
    walletTotalBalance,
    receiveSlots,
    selectedSlotIndex,
    showsMultiAccountChrome,
    balanceHidden,
    setBalanceHidden,
    transactions,
    refreshWallet,
    language,
  } = useApp();
  const { t } = useT(language);

  const focusedSlot = receiveSlots.find((slot) => slot.index === selectedSlotIndex) ?? receiveSlots[0];
  const focusedAccountTitle = focusedSlot
    ? (focusedSlot.index === 0 ? t(L10nKeys.receive.mainAddress) : focusedSlot.title)
    : '';

  const [filter, setFilter] = useState<ActivityFilter>('all');
  const [showSend, setShowSend] = useState(false);
  const [showReceive, setShowReceive] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showPrivacy, setShowPrivacy] = useState(false);
  const [showAccountsDrawer, setShowAccountsDrawer] = useState(false);
  const [showWalletPicker, setShowWalletPicker] = useState(false);
  const [selectedTx, setSelectedTx] = useState<WalletTransaction | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [deepRecovery, setDeepRecovery] = useState<DeepRecoveryState>({
    isRunning: false,
    progressChecked: 0,
    progressTotal: 1024,
    isTransferring: false,
    statusMessage: null,
    errorMessage: null,
  });

  const openAccountsDrawer = useCallback(() => setShowAccountsDrawer(true), []);
  const openWalletPicker = useCallback(() => setShowWalletPicker(true), []);

  const pullRefresh = async () => {
    setRefreshing(true);
    try {
      await refreshWallet();
    } finally {
      setRefreshing(false);
    }
  };

  const runDeepRecovery = async () => {
    if (!activeWallet || deepRecovery.isRunning) return;
    setDeepRecovery((s) => ({ ...s, isRunning: true, errorMessage: null, statusMessage: t('send.deep.recovery.scanning') }));
    try {
      const count = await PrivacyService.recoverDeepFundsToMainWallet(activeWallet.id, (p) => {
        if (p.phase === 'scanning') {
          setDeepRecovery((s) => ({
            ...s,
            progressChecked: p.checked,
            progressTotal: p.total,
            statusMessage: `${t('send.deep.recovery.scanning')} ${p.checked}/${p.total}`,
          }));
        } else {
          setDeepRecovery((s) => ({
            ...s,
            isTransferring: true,
            statusMessage: `${p.current}/${p.total}`,
          }));
        }
      });
      setDeepRecovery((s) => ({
        ...s,
        isRunning: false,
        isTransferring: false,
        statusMessage: count > 0 ? t('send.deep.recovery.done', count) : t('privacy.consolidate.done', 0),
      }));
      await refreshWallet();
    } catch (e) {
      setDeepRecovery((s) => ({
        ...s,
        isRunning: false,
        isTransferring: false,
        errorMessage: e instanceof Error ? e.message : 'Recovery failed',
      }));
    }
  };

  const filteredTxs = useMemo(() => {
    if (filter === 'received') return transactions.filter((tx) => tx.kind === 'received');
    if (filter === 'sent') return transactions.filter((tx) => tx.kind === 'sent');
    return transactions;
  }, [transactions, filter]);

  const grouped = useMemo(() => {
    const map = new Map<string, WalletTransaction[]>();
    filteredTxs.forEach((tx) => {
      const list = map.get(tx.dayLabel) ?? [];
      list.push(tx);
      map.set(tx.dayLabel, list);
    });
    return [...map.entries()];
  }, [filteredTxs]);

  const showFundBanner = transactions.length === 0;

  if (!activeWallet) return null;

  return (
    <div className="mesh-screen mesh-home">
      <div className="mesh-header">
        <button type="button" className="mesh-btn-chrome" onClick={openAccountsDrawer} aria-label={t('wallet.address.drawer.title')}>☰</button>
        <button type="button" className="mesh-home-wallet-picker" onClick={openWalletPicker}>
          <span className="mesh-home-wallet-name">{activeWallet.name} ▾</span>
          {showsMultiAccountChrome && (
            <span className={`mesh-home-total-caption ${balancePrivacyClass(balanceHidden)}`}>
              {t(L10nKeys.wallet.homeTotal)} {formatUSDT(walletTotalBalance)} USDT
            </span>
          )}
        </button>
        <button type="button" className="mesh-btn-chrome mesh-btn-settings" onClick={() => setShowSettings(true)} aria-label="Settings">⚙</button>
      </div>

      {deepRecovery.isRunning && (
        <div className="mesh-deep-recovery-banner">
          {deepRecovery.statusMessage ?? t('send.deep.recovery.scanning')}
        </div>
      )}

      <div className="mesh-home-balance-section">
        <button type="button" className="mesh-home-balance-toggle" onClick={() => setBalanceHidden(!balanceHidden)}>
          {showsMultiAccountChrome && (
            <p className={`mesh-home-account-caption ${balancePrivacyClass(balanceHidden)}`}>{focusedAccountTitle}</p>
          )}
          <p className={`mesh-balance-hero ${balancePrivacyClass(balanceHidden)}`}>{formatUSDT(balance)}</p>
          <p className="mesh-subtitle mesh-home-balance-unit">USDT</p>
        </button>

        <div className="mesh-home-actions">
          <div className="mesh-home-action">
            <button type="button" className="mesh-circle-action" onClick={() => setShowReceive(true)} aria-label={t(L10nKeys.wallet.receive)}>↓</button>
            <span>{t(L10nKeys.wallet.receive)}</span>
          </div>
          <div className="mesh-home-action">
            <button type="button" className="mesh-circle-action" onClick={() => setShowSend(true)} aria-label={t(L10nKeys.wallet.send)}>↑</button>
            <span>{t(L10nKeys.wallet.send)}</span>
          </div>
        </div>
      </div>

      <div className="mesh-filter-bar">
        {(['all', 'received', 'sent'] as ActivityFilter[]).map((f) => (
          <button
            key={f}
            type="button"
            className={`mesh-filter-chip ${filter === f ? 'active' : ''}`}
            onClick={() => setFilter(f)}
          >
            {f === 'all' ? t(L10nKeys.wallet.filterAll) : f === 'received' ? t(L10nKeys.wallet.filterReceived) : t(L10nKeys.wallet.filterSent)}
          </button>
        ))}
        <button type="button" className="mesh-filter-chip" onClick={pullRefresh} disabled={refreshing}>
          {refreshing ? '…' : '↻'}
        </button>
      </div>

      <div className={`mesh-scroll mesh-home-scroll${showFundBanner ? ' mesh-home-scroll-fund' : ''}`} style={{ padding: '0 var(--mesh-padding)' }}>
        {grouped.length > 0 ? (
          grouped.map(([day, items]) => (
            <div key={day}>
              <p style={{ fontSize: 14, color: 'var(--mesh-text-secondary)', margin: '16px 0 8px' }}>{day}</p>
              {items.map((tx) => (
                <button
                  key={tx.id}
                  type="button"
                  className="mesh-tx-row"
                  style={{ width: '100%', textAlign: 'left' }}
                  onClick={() => setSelectedTx(tx)}
                >
                  <div className="mesh-tx-icon">{tx.kind === 'received' ? '↓' : '↑'}</div>
                  <div style={{ flex: 1 }}>
                    <p>{txListTitle(tx, t)}</p>
                    <p className="mesh-subtitle" style={{ fontSize: 14 }}>{tx.subtitle}</p>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <p style={{ color: tx.kind === 'received' ? 'var(--mesh-success)' : undefined }}>
                      {tx.kind === 'received' ? '+' : '-'}{formatUSDT(tx.amountUSDT)} USDT
                    </p>
                    <p className="mesh-subtitle" style={{ fontSize: 12 }}>
                      {new Date(tx.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </p>
                  </div>
                </button>
              ))}
            </div>
          ))
        ) : showFundBanner ? (
          <div className="mesh-fund-center">
            <p className="mesh-subtitle mesh-fund-center-hint">{t('wallet.fund.hint')}</p>
            <button type="button" className="mesh-btn-primary mesh-fund-center-btn" onClick={() => setShowReceive(true)}>
              {t(L10nKeys.wallet.fund)}
            </button>
          </div>
        ) : (
          <p className="mesh-subtitle" style={{ textAlign: 'center', padding: 32 }}>{t(L10nKeys.wallet.activityEmpty)}</p>
        )}
      </div>

      {showSend && <SendFlow onClose={() => { setShowSend(false); refreshWallet(); }} />}
      {showReceive && <ReceiveFlow onClose={() => { setShowReceive(false); refreshWallet(); }} />}
      {showSettings && <SecurityView onClose={() => setShowSettings(false)} />}
      {showPrivacy && <PrivacyView onClose={() => { setShowPrivacy(false); refreshWallet(); }} onDeepRecovery={runDeepRecovery} deepRecovery={deepRecovery} />}

      {showAccountsDrawer && (
        <AccountsDrawer onClose={() => setShowAccountsDrawer(false)} />
      )}

      {showWalletPicker && (
        <WalletSelectSheet onClose={() => setShowWalletPicker(false)} />
      )}

      {selectedTx && <TransactionDetail tx={selectedTx} onClose={() => setSelectedTx(null)} />}
    </div>
  );
}
