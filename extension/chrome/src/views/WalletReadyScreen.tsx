import { useEffect, useMemo, useRef, useState } from 'react';
import { extensionAsset } from '@/core/extension-asset';
import { useT, L10nKeys } from '@/core/l10n';
import { MeshPrimaryButton } from '@/components/ui/MeshButtons';
import type { Language } from '@/core/types';

interface Props {
  language: Language;
  onStart: () => void;
}

export function WalletReadyScreen({ language, onStart }: Props) {
  const { t } = useT(language);
  const videoRef = useRef<HTMLVideoElement>(null);
  const [videoVisible, setVideoVisible] = useState(false);
  const videoSrc = useMemo(() => extensionAsset('branding/wallet-ready.mp4'), []);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    let revealed = false;
    const reveal = () => {
      if (revealed) return;
      revealed = true;
      void video.play().catch(() => {});
      setVideoVisible(true);
    };

    const fallbackTimer = window.setTimeout(reveal, 600);
    video.addEventListener('loadeddata', reveal, { once: true });
    video.addEventListener('canplay', reveal, { once: true });
    video.addEventListener('error', reveal, { once: true });
    if (video.readyState >= 2) reveal();

    return () => {
      window.clearTimeout(fallbackTimer);
      video.removeEventListener('loadeddata', reveal);
      video.removeEventListener('canplay', reveal);
      video.removeEventListener('error', reveal);
    };
  }, [videoSrc]);

  return (
    <div className="mesh-screen mesh-wallet-ready-screen">
      <div className="mesh-wallet-ready-hero">
        <video
          ref={videoRef}
          className={`mesh-wallet-ready-video ${videoVisible ? 'visible' : ''}`}
          src={videoSrc}
          autoPlay
          loop
          muted
          playsInline
          preload="auto"
        />
        <div className="mesh-wallet-ready-gradient" aria-hidden />
      </div>
      <div className="mesh-wallet-ready-panel">
        <h1 className="mesh-wallet-ready-title">{t(L10nKeys.onboarding.walletReadyTitle)}</h1>
        <p className="mesh-wallet-ready-subtitle">{t(L10nKeys.onboarding.walletReadySubtitle)}</p>
        <div className="mesh-footer-actions mesh-wallet-ready-actions">
          <MeshPrimaryButton title={t(L10nKeys.onboarding.walletReadyOpen)} onClick={onStart} />
        </div>
      </div>
    </div>
  );
}
