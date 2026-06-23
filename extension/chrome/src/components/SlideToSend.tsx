import { useRef, useState, useCallback } from 'react';

interface SlideToSendProps {
  label?: string;
  onComplete: () => void;
  disabled?: boolean;
}

export function SlideToSend({ label = 'Slide to send', onComplete, disabled }: SlideToSendProps) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [offset, setOffset] = useState(0);
  const [dragging, setDragging] = useState(false);
  const startX = useRef(0);

  const maxOffset = useCallback(() => {
    const track = trackRef.current;
    if (!track) return 200;
    return track.clientWidth - 56;
  }, []);

  const handleStart = (clientX: number) => {
    if (disabled) return;
    setDragging(true);
    startX.current = clientX - offset;
  };

  const handleMove = (clientX: number) => {
    if (!dragging || disabled) return;
    const next = Math.max(0, Math.min(clientX - startX.current, maxOffset()));
    setOffset(next);
  };

  const handleEnd = () => {
    if (!dragging) return;
    setDragging(false);
    if (offset >= maxOffset() * 0.85) {
      setOffset(maxOffset());
      onComplete();
    } else {
      setOffset(0);
    }
  };

  return (
    <div
      ref={trackRef}
      className="mesh-slide-send"
      onMouseMove={(e) => handleMove(e.clientX)}
      onMouseUp={handleEnd}
      onMouseLeave={handleEnd}
      onTouchMove={(e) => handleMove(e.touches[0].clientX)}
      onTouchEnd={handleEnd}
    >
      <div className="mesh-slide-send-track">{label}</div>
      <div
        className="mesh-slide-send-thumb"
        style={{ transform: `translateX(${offset}px)` }}
        onMouseDown={(e) => handleStart(e.clientX)}
        onTouchStart={(e) => handleStart(e.touches[0].clientX)}
      >
        →
      </div>
    </div>
  );
}
