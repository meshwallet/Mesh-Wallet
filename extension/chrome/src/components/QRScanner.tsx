import { useRef, useEffect, useState } from 'react';
import jsQR from 'jsqr';

interface Props {
  onScan: (address: string) => void;
  onClose: () => void;
}

export function QRScanner({ onScan, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let stream: MediaStream | null = null;
    let raf = 0;

    (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' },
        });
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }

        const tick = () => {
          const video = videoRef.current;
          const canvas = canvasRef.current;
          if (!video || !canvas || video.readyState !== video.HAVE_ENOUGH_DATA) {
            raf = requestAnimationFrame(tick);
            return;
          }
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          const ctx = canvas.getContext('2d');
          if (!ctx) return;
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
          const code = jsQR(image.data, image.width, image.height);
          if (code?.data) {
            onScan(code.data.trim());
            onClose();
            return;
          }
          raf = requestAnimationFrame(tick);
        };
        raf = requestAnimationFrame(tick);
      } catch {
        setError('Camera access denied');
      }
    })();

    return () => {
      cancelAnimationFrame(raf);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [onScan, onClose]);

  return (
    <div className="mesh-overlay">
      <div className="mesh-header">
        <button type="button" className="mesh-btn-chrome" onClick={onClose}>×</button>
        <span>Scan QR</span>
        <div style={{ width: 48 }} />
      </div>
      {error ? (
        <p className="mesh-error" style={{ padding: 24, textAlign: 'center' }}>{error}</p>
      ) : (
        <video ref={videoRef} style={{ width: '100%', flex: 1, objectFit: 'cover' }} muted playsInline />
      )}
      <canvas ref={canvasRef} style={{ display: 'none' }} />
    </div>
  );
}
