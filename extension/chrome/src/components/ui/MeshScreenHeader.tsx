import { MeshChromeButton } from './MeshButtons';

interface Props {
  title: string;
  onClose?: () => void;
  onBack?: () => void;
  trailing?: string;
}

export function MeshFlowScreenHeader({ title, onClose, onBack, trailing }: Props) {
  return (
    <div className="mesh-header">
      {onBack ? (
        <MeshChromeButton onClick={onBack} aria-label="Back">←</MeshChromeButton>
      ) : onClose ? (
        <MeshChromeButton onClick={onClose} aria-label="Close">×</MeshChromeButton>
      ) : (
        <div style={{ width: 48 }} />
      )}
      <span className="mesh-header-title">{title}</span>
      {trailing ? (
        <span className="mesh-subtitle" style={{ fontSize: 14 }}>{trailing}</span>
      ) : (
        <div style={{ width: 48 }} />
      )}
    </div>
  );
}

export function MeshSlidePanel({ children, onClose }: { children: React.ReactNode; onClose?: () => void }) {
  return (
    <div className="mesh-slide-panel">
      {children}
    </div>
  );
}
