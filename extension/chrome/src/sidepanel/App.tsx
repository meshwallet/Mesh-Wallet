import { useState, useEffect } from 'react';
import { AppProvider, useApp, PasscodeStore } from '@/core/context/AppContext';
import { SplashScreen, AppLock } from '@/views/AppLock';
import { OnboardingFlow } from '@/views/OnboardingFlow';
import { WalletHome } from '@/views/WalletHome';
import '@/styles/global.css';

type Phase = 'splash' | 'lock' | 'onboarding' | 'wallet';

function RootApp() {
  const { isLoading, isUnlocked, hasWallet, setUnlocked, refreshWallet } = useApp();
  const [phase, setPhase] = useState<Phase>('splash');
  const [needsLock, setNeedsLock] = useState(false);

  useEffect(() => {
    if (isLoading) return;
    if (phase !== 'splash') return;

    (async () => {
      const passcode = await PasscodeStore.isEnabled();
      setNeedsLock(passcode && hasWallet);
    })();
  }, [isLoading, hasWallet, phase]);

  const finishSplash = () => {
    if (!hasWallet) {
      setPhase('onboarding');
      return;
    }
    if (needsLock && !isUnlocked) {
      setPhase('lock');
      return;
    }
    setPhase('wallet');
  };

  if (isLoading || phase === 'splash') {
    return <SplashScreen onDone={finishSplash} />;
  }

  if (phase === 'onboarding') {
    return (
      <OnboardingFlow
        onComplete={() => {
          setUnlocked(true);
          refreshWallet();
          setPhase('wallet');
        }}
      />
    );
  }

  if (phase === 'lock') {
    return (
      <AppLock
        onUnlock={() => {
          setUnlocked(true);
          setPhase('wallet');
        }}
      />
    );
  }

  return <WalletHome />;
}

export default function App() {
  return (
    <AppProvider>
      <RootApp />
    </AppProvider>
  );
}
