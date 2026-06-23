import { useState } from 'react';
import { useApp } from '@/core/context/AppContext';
import { WalletSelectSheet } from '@/views/WalletSelectSheet';

interface Props {
  onWalletChange?: () => void;
}

export function WalletAccountPicker({ onWalletChange }: Props) {
  const { activeWallet, refreshWallet } = useApp();
  const [open, setOpen] = useState(false);

  if (!activeWallet) return null;

  const close = async () => {
    setOpen(false);
    await refreshWallet();
    onWalletChange?.();
  };

  return (
    <>
      <div className="mesh-flow-wallet-bar">
        <button type="button" className="mesh-account-pill" onClick={() => setOpen(true)}>
          {activeWallet.name} ▾
        </button>
      </div>
      {open && <WalletSelectSheet onClose={close} />}
    </>
  );
}
