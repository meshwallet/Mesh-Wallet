import { useEffect, useRef } from 'react';

interface MeshPromptDialogProps {
  title: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  confirmLabel: string;
  cancelLabel: string;
  error?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export function MeshPromptDialog({
  title,
  value,
  onChange,
  placeholder,
  confirmLabel,
  cancelLabel,
  error,
  onConfirm,
  onCancel,
}: MeshPromptDialogProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
    inputRef.current?.select();
  }, []);

  return (
    <div className="mesh-alert-backdrop" onClick={onCancel}>
      <div
        className="mesh-alert"
        role="dialog"
        aria-modal="true"
        aria-labelledby="mesh-alert-title"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 id="mesh-alert-title" className="mesh-alert-title">{title}</h3>
        <input
          ref={inputRef}
          className="mesh-field mesh-alert-input"
          value={value}
          placeholder={placeholder}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') onConfirm();
            if (e.key === 'Escape') onCancel();
          }}
        />
        {error && <p className="mesh-alert-message mesh-alert-error">{error}</p>}
        <div className="mesh-alert-actions">
          <button type="button" className="mesh-alert-btn mesh-alert-btn-secondary" onClick={onCancel}>
            {cancelLabel}
          </button>
          <button type="button" className="mesh-alert-btn mesh-alert-btn-primary" onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

interface MeshConfirmDialogProps {
  title: string;
  message?: string;
  confirmLabel: string;
  cancelLabel: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export function MeshConfirmDialog({
  title,
  message,
  confirmLabel,
  cancelLabel,
  destructive = false,
  onConfirm,
  onCancel,
}: MeshConfirmDialogProps) {
  return (
    <div className="mesh-alert-backdrop" onClick={onCancel}>
      <div
        className="mesh-alert"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="mesh-alert-title"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 id="mesh-alert-title" className="mesh-alert-title">{title}</h3>
        {message && <p className="mesh-alert-message">{message}</p>}
        <div className="mesh-alert-actions">
          <button type="button" className="mesh-alert-btn mesh-alert-btn-secondary" onClick={onCancel}>
            {cancelLabel}
          </button>
          <button
            type="button"
            className={`mesh-alert-btn ${destructive ? 'mesh-alert-btn-destructive' : 'mesh-alert-btn-primary'}`}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
