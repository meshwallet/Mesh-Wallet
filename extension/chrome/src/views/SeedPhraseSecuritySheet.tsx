import { useState } from 'react';
import { useApp } from '@/core/context/AppContext';
import { useT, L10nKeys } from '@/core/l10n';
import { MeshPrimaryButton } from '@/components/ui/MeshButtons';
import { MeshFlowScreenHeader } from '@/components/ui/MeshScreenHeader';

const ITEMS = [
  'Only you know this secret phrase.',
  'This secret phrase was NOT given to you by anyone, e.g. a company representative.',
  'If someone else has seen it, they can steal your funds.',
];

interface Props {
  onContinue: () => void;
  onClose: () => void;
}

export function SeedPhraseSecuritySheet({ onContinue, onClose }: Props) {
  const { language } = useApp();
  const { t } = useT(language);
  const [checked, setChecked] = useState<Set<number>>(new Set());

  const toggle = (i: number) => {
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(i)) next.delete(i);
      else next.add(i);
      return next;
    });
  };

  const allChecked = checked.size === ITEMS.length;

  return (
    <div className="mesh-slide-panel mesh-seed-security-screen">
      <MeshFlowScreenHeader title="" onClose={onClose} />
      <div className="mesh-scroll mesh-seed-security-scroll">
        <img
          src="/branding/secret-phrase-security-hero.png"
          alt=""
          className="mesh-seed-security-hero"
        />
        <h1 className="mesh-seed-security-title">Check your secret phrase is safe</h1>
        <div className="mesh-seed-security-list">
          {ITEMS.map((text, i) => {
            const isChecked = checked.has(i);
            return (
              <button
                key={i}
                type="button"
                className={`mesh-seed-security-item ${isChecked ? 'checked' : ''}`}
                onClick={() => toggle(i)}
              >
                <span className="mesh-seed-security-check" aria-hidden>
                  {isChecked ? (
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="10" fill="currentColor" opacity="0.18" />
                      <path
                        d="M8 12.5l2.5 2.5L16 9.5"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                  ) : (
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="9.5" stroke="currentColor" strokeWidth="1.5" />
                    </svg>
                  )}
                </span>
                <span className="mesh-seed-security-text">{text}</span>
              </button>
            );
          })}
        </div>
      </div>
      <div className="mesh-footer-actions">
        <MeshPrimaryButton
          title={t(L10nKeys.common.continue)}
          disabled={!allChecked}
          onClick={onContinue}
        />
      </div>
    </div>
  );
}
