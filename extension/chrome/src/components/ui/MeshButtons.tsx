interface BtnProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  title: string;
}

export function MeshPrimaryButton({ title, disabled, className = '', ...props }: BtnProps) {
  return (
    <button type="button" className={`mesh-btn-primary ${className}`} disabled={disabled} {...props}>
      {title}
    </button>
  );
}

export function MeshSecondaryButton({ title, disabled, className = '', ...props }: BtnProps) {
  return (
    <button type="button" className={`mesh-btn-secondary ${className}`} disabled={disabled} {...props}>
      {title}
    </button>
  );
}

export function MeshChromeButton({ children, className = '', ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button type="button" className={`mesh-btn-chrome ${className}`} {...props}>
      {children}
    </button>
  );
}
