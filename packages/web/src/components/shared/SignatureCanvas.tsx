import { useRef, useEffect, useState, useCallback } from 'react';
import { Eraser } from 'lucide-react';
import toast from 'react-hot-toast';

interface SignatureCanvasProps {
  onSave: (dataUrl: string) => void;
  width?: number;
  height?: number;
  initialValue?: string;
  /** Pen stroke color. Defaults to CSS variable --signature-pen-color or dark slate. */
  penColor?: string;
}

const LIGHT_PEN_COLOR = '#1e293b';
const DARK_PEN_COLOR = '#e2e8f0';

/**
 * PDF3 fix: hard cap on the signature base64 payload. Writing a 500 KB
 * canvas into every ticket row is cruel to SQLite and exposes a memory
 * amplification vector if an attacker can replay the ticket through
 * html-pdf. 100 KB is enough for a 300px wide signature at reasonable
 * quality.
 */
const SIGNATURE_MAX_BYTES = 100 * 1024;

function isDarkMode(): boolean {
  return document.documentElement.classList.contains('dark');
}

function getGuideColors() {
  const dark = isDarkMode();
  return {
    baselineColor: dark ? '#475569' : '#cbd5e1',  // surface-600 / surface-300
    hintColor: dark ? '#64748b' : '#94a3b8',       // surface-500 / surface-400
  };
}

export function SignatureCanvas({ onSave, width = 400, height = 150, initialValue, penColor }: SignatureCanvasProps) {
  const resolvedPenColor = penColor
    || (typeof getComputedStyle !== 'undefined'
      ? getComputedStyle(document.documentElement).getPropertyValue('--signature-pen-color').trim()
      : '')
    || (isDarkMode() ? DARK_PEN_COLOR : LIGHT_PEN_COLOR);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [hasSignature, setHasSignature] = useState(!!initialValue);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Set up canvas
    ctx.strokeStyle = resolvedPenColor;
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // Draw initial value if provided — restrict to `data:image/` URIs so a
    // server-supplied path can't trigger arbitrary network requests or other
    // unexpected image loads.
    if (initialValue && typeof initialValue === 'string' && initialValue.startsWith('data:image/')) {
      const img = new Image();
      img.onload = () => ctx.drawImage(img, 0, 0);
      img.src = initialValue;
    } else {
      // Draw baseline with theme-aware colors
      const { baselineColor, hintColor } = getGuideColors();
      ctx.setLineDash([4, 4]);
      ctx.strokeStyle = baselineColor;
      ctx.beginPath();
      ctx.moveTo(20, height - 30);
      ctx.lineTo(width - 20, height - 30);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.strokeStyle = resolvedPenColor;

      // "Sign here" text
      ctx.fillStyle = hintColor;
      ctx.font = '12px Inter, sans-serif';
      ctx.fillText('Sign here', 20, height - 12);
    }
  }, [initialValue, width, height, resolvedPenColor]);

  // Accept both React synthetic mouse events and native TouchEvents so the
  // native touch listener installed below can reuse the same coordinate
  // extraction logic.
  const getPos = useCallback((e: React.MouseEvent | TouchEvent) => {
    const canvas = canvasRef.current!;
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;

    if ('touches' in e) {
      return {
        x: (e.touches[0].clientX - rect.left) * scaleX,
        y: (e.touches[0].clientY - rect.top) * scaleY,
      };
    }
    return {
      x: (e.clientX - rect.left) * scaleX,
      y: (e.clientY - rect.top) * scaleY,
    };
  }, []);

  // SCAN-1167: React synthesises touchstart/touchmove listeners as passive
  // by default, so `e.preventDefault()` inside the React handler is silently
  // dropped AND Chrome logs "Unable to preventDefault inside passive event
  // listener". The `touch-none` class handles scroll-lock, but some iOS
  // Safari builds still fire page-pinch gestures if preventDefault is
  // missing. Attach the listeners natively with `{ passive: false }` in a
  // useEffect below; React handlers only cover mouse events now.
  const startDraw = useCallback((e: React.MouseEvent) => {
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    const pos = getPos(e);
    ctx.beginPath();
    ctx.moveTo(pos.x, pos.y);
    setIsDrawing(true);
    setHasSignature(true);
  }, [getPos]);

  const draw = useCallback((e: React.MouseEvent) => {
    if (!isDrawing) return;
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    const pos = getPos(e);
    ctx.lineTo(pos.x, pos.y);
    ctx.stroke();
  }, [isDrawing, getPos]);

  // SCAN-1118: `clear` is defined below but endDraw needs to call it on the
  // size-cap rejection path. Use a ref so endDraw can reach the callback
  // without listing it as a dependency (and without hitting TDZ).
  const clearRef = useRef<() => void>(() => {});

  const endDraw = useCallback(() => {
    if (!isDrawing) return;
    setIsDrawing(false);
    if (!canvasRef.current) return;
    // Start at full-quality PNG; if that blows the size cap, fall back to
    // progressively lower-quality JPEG, then reject outright.
    let dataUrl = canvasRef.current.toDataURL('image/png');
    if (dataUrl.length > SIGNATURE_MAX_BYTES) {
      dataUrl = canvasRef.current.toDataURL('image/jpeg', 0.7);
    }
    if (dataUrl.length > SIGNATURE_MAX_BYTES) {
      dataUrl = canvasRef.current.toDataURL('image/jpeg', 0.4);
    }
    if (dataUrl.length > SIGNATURE_MAX_BYTES) {
      toast.error('Signature is too large to save. Please try a simpler signature.');
      // SCAN-1118: previously `hasSignature` stayed `true` after a size-cap
      // rejection — ink on screen with nothing actually saved, so the "Save"
      // button stayed enabled and the parent form could believe a signature
      // was captured. Reset the canvas + flag so UI state matches saved state.
      clearRef.current();
      return;
    }
    onSave(dataUrl);
  }, [isDrawing, onSave]);

  const clear = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Redraw baseline with theme-aware colors
    const { baselineColor, hintColor } = getGuideColors();
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = baselineColor;
    ctx.beginPath();
    ctx.moveTo(20, height - 30);
    ctx.lineTo(width - 20, height - 30);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.strokeStyle = resolvedPenColor;
    ctx.fillStyle = hintColor;
    ctx.font = '12px Inter, sans-serif';
    ctx.fillText('Sign here', 20, height - 12);

    setHasSignature(false);
    onSave('');
  }, [height, width, onSave, resolvedPenColor]);

  // SCAN-1118: keep the ref pointing at the latest `clear` so endDraw's
  // size-cap rejection branch invokes the current version even across
  // re-renders where deps change.
  useEffect(() => {
    clearRef.current = clear;
  }, [clear]);

  // SCAN-1167: install native touch listeners with `{ passive: false }` so
  // `preventDefault()` actually runs. React's synthetic touch listeners are
  // passive by default; calling preventDefault inside them is silently
  // dropped and logs a console warning. Keep the mouse path on React
  // props — mouse events don't have this passive-default problem.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const handleStart = (e: TouchEvent) => {
      e.preventDefault();
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const pos = getPos(e);
      ctx.beginPath();
      ctx.moveTo(pos.x, pos.y);
      setIsDrawing(true);
      setHasSignature(true);
    };
    // Grab the live drawing state via ref so the move/end listeners don't
    // need to be re-installed on every isDrawing flip.
    let drawingNow = false;
    const handleMove = (e: TouchEvent) => {
      if (!drawingNow) return;
      e.preventDefault();
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const pos = getPos(e);
      ctx.lineTo(pos.x, pos.y);
      ctx.stroke();
    };
    const handleEnd = () => {
      drawingNow = false;
      endDraw();
    };
    const trackStart = (e: TouchEvent) => {
      drawingNow = true;
      handleStart(e);
    };
    canvas.addEventListener('touchstart', trackStart, { passive: false });
    canvas.addEventListener('touchmove', handleMove, { passive: false });
    canvas.addEventListener('touchend', handleEnd);
    canvas.addEventListener('touchcancel', handleEnd);
    return () => {
      canvas.removeEventListener('touchstart', trackStart);
      canvas.removeEventListener('touchmove', handleMove);
      canvas.removeEventListener('touchend', handleEnd);
      canvas.removeEventListener('touchcancel', handleEnd);
    };
  }, [getPos, endDraw]);

  return (
    <div className="space-y-2">
      <div className="relative rounded-lg border-2 border-dashed border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 overflow-hidden"
        style={{ width, maxWidth: '100%' }}>
        <canvas
          ref={canvasRef}
          width={width}
          height={height}
          className="cursor-crosshair touch-none w-full"
          style={{ height }}
          onMouseDown={startDraw}
          onMouseMove={draw}
          onMouseUp={endDraw}
          onMouseLeave={endDraw}
        />
      </div>
      {hasSignature && (
        <button type="button" onClick={clear} className="inline-flex items-center gap-1 text-xs text-surface-500 hover:text-red-500 transition-colors">
          <Eraser aria-hidden="true" className="h-3 w-3" /> Clear signature
        </button>
      )}
    </div>
  );
}
