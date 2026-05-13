import { useRef, useEffect, useState, useCallback, useId } from 'react';
import { Eraser, Type } from 'lucide-react';
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
const SIGNATURE_GUIDE_FONT = '12px Jost, Futura, system-ui, sans-serif';
const TYPED_SIGNATURE_FONT_FAMILY = '"Segoe Script", "Brush Script MT", cursive';

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

function drawSignatureGuide(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  penColor: string,
) {
  ctx.clearRect(0, 0, width, height);
  const { baselineColor, hintColor } = getGuideColors();
  ctx.setLineDash([4, 4]);
  ctx.strokeStyle = baselineColor;
  ctx.beginPath();
  ctx.moveTo(20, height - 30);
  ctx.lineTo(width - 20, height - 30);
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.strokeStyle = penColor;
  ctx.fillStyle = hintColor;
  ctx.font = SIGNATURE_GUIDE_FONT;
  ctx.fillText('Sign here', 20, height - 12);
}

function computePenColor(explicit?: string): string {
  if (explicit) return explicit;
  const cssVar = (typeof getComputedStyle !== 'undefined'
    ? getComputedStyle(document.documentElement).getPropertyValue('--signature-pen-color').trim()
    : '');
  if (cssVar) return cssVar;
  return isDarkMode() ? DARK_PEN_COLOR : LIGHT_PEN_COLOR;
}

function canvasSignatureDataUrl(canvas: HTMLCanvasElement): string | null {
  let dataUrl = canvas.toDataURL('image/png');
  if (dataUrl.length > SIGNATURE_MAX_BYTES) {
    dataUrl = canvas.toDataURL('image/jpeg', 0.7);
  }
  if (dataUrl.length > SIGNATURE_MAX_BYTES) {
    dataUrl = canvas.toDataURL('image/jpeg', 0.4);
  }
  return dataUrl.length > SIGNATURE_MAX_BYTES ? null : dataUrl;
}

const STROKE_THRESHOLD = 2; // px — minimum movement before a stroke is committed

export function SignatureCanvas({ onSave, width = 400, height = 150, initialValue, penColor }: SignatureCanvasProps) {
  // WEB-S5-021 (FIXED-by-Fixer-A19 2026-04-25): the original implementation
  // computed `resolvedPenColor` synchronously during render. If the parent
  // mounts SignatureCanvas before the `dark` class lands on <html> (e.g. when
  // the theme listener applies after the first paint, or the canvas is in a
  // modal that opens during the system-theme flip), the first render reads
  // the wrong scheme and bakes the LIGHT pen color into the canvas context
  // for what should be a dark-mode signature. Move the resolution into state
  // updated by an effect so we re-resolve once on mount, plus subscribe to
  // the system color-scheme media query so a runtime flip re-paints the pen.
  const [resolvedPenColor, setResolvedPenColor] = useState<string>(() => computePenColor(penColor));
  useEffect(() => {
    setResolvedPenColor(computePenColor(penColor));
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => setResolvedPenColor(computePenColor(penColor));
    try {
      mql.addEventListener('change', handler);
    } catch {
      return;
    }
    return () => {
      try { mql.removeEventListener('change', handler); } catch { /* legacy */ }
    };
  }, [penColor]);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const typedSignatureId = useId();
  const [isDrawing, setIsDrawing] = useState(false);
  const [hasSignature, setHasSignature] = useState(!!initialValue);
  const [typedSignature, setTypedSignature] = useState('');
  // WEB-UIUX-462: track pending stroke start position so we only commit the
  // stroke once the pointer has moved beyond STROKE_THRESHOLD pixels. A bare
  // tap on the "Sign here" hint area otherwise immediately marks a stroke.
  const pendingStroke = useRef<{ x: number; y: number } | null>(null);

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
      img.onload = () => {
        ctx.clearRect(0, 0, width, height);
        ctx.drawImage(img, 0, 0);
      };
      img.src = initialValue;
    } else {
      drawSignatureGuide(ctx, width, height, resolvedPenColor);
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
    if (!canvasRef.current) return;
    const pos = getPos(e);
    // WEB-UIUX-462: defer the actual stroke begin until movement is confirmed.
    pendingStroke.current = pos;
  }, [getPos]);

  const draw = useCallback((e: React.MouseEvent) => {
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    const pos = getPos(e);
    // WEB-UIUX-462: commit pending stroke once movement exceeds threshold.
    if (pendingStroke.current) {
      const dx = pos.x - pendingStroke.current.x;
      const dy = pos.y - pendingStroke.current.y;
      if (Math.sqrt(dx * dx + dy * dy) > STROKE_THRESHOLD) {
        ctx.beginPath();
        ctx.moveTo(pendingStroke.current.x, pendingStroke.current.y);
        pendingStroke.current = null;
        setIsDrawing(true);
        setHasSignature(true);
        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();
      }
      return;
    }
    if (!isDrawing) return;
    ctx.lineTo(pos.x, pos.y);
    ctx.stroke();
  }, [isDrawing, getPos]);

  // SCAN-1118: `clear` is defined below but endDraw needs to call it on the
  // size-cap rejection path. Use a ref so endDraw can reach the callback
  // without listing it as a dependency (and without hitting TDZ).
  const clearRef = useRef<() => void>(() => {});

  const endDraw = useCallback(() => {
    // WEB-UIUX-462: discard a tap that never moved past the threshold.
    pendingStroke.current = null;
    if (!isDrawing) return;
    setIsDrawing(false);
    if (!canvasRef.current) return;
    const dataUrl = canvasSignatureDataUrl(canvasRef.current);
    if (!dataUrl) {
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

  const applyTypedSignature = useCallback(() => {
    const canvas = canvasRef.current;
    const text = typedSignature.trim();
    if (!canvas || !text) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    drawSignatureGuide(ctx, width, height, resolvedPenColor);
    ctx.fillStyle = resolvedPenColor;
    ctx.textBaseline = 'alphabetic';
    const maxTextWidth = width - 40;
    let fontSize = Math.min(36, Math.max(22, Math.floor(height * 0.28)));
    do {
      ctx.font = fontSize + 'px ' + TYPED_SIGNATURE_FONT_FAMILY;
      fontSize -= 2;
    } while (ctx.measureText(text).width > maxTextWidth && fontSize >= 18);
    ctx.fillText(text, 20, height - 40, maxTextWidth);

    const dataUrl = canvasSignatureDataUrl(canvas);
    if (!dataUrl) {
      toast.error('Signature is too large to save. Please try a shorter typed signature.');
      clearRef.current();
      return;
    }
    setHasSignature(true);
    onSave(dataUrl);
  }, [height, onSave, resolvedPenColor, typedSignature, width]);

  const clear = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    drawSignatureGuide(ctx, width, height, resolvedPenColor);

    setTypedSignature('');
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
    // WEB-UIUX-462: track pending touch start; only commit the stroke once
    // movement exceeds STROKE_THRESHOLD px so a bare tap on the hint text
    // does not register as a stroke start.
    let pendingTouchPos: { x: number; y: number } | null = null;
    let drawingNow = false;
    const handleStart = (e: TouchEvent) => {
      e.preventDefault();
      const pos = getPos(e);
      pendingTouchPos = pos;
    };
    const handleMove = (e: TouchEvent) => {
      e.preventDefault();
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const pos = getPos(e);
      if (pendingTouchPos) {
        const dx = pos.x - pendingTouchPos.x;
        const dy = pos.y - pendingTouchPos.y;
        if (Math.sqrt(dx * dx + dy * dy) > STROKE_THRESHOLD) {
          ctx.beginPath();
          ctx.moveTo(pendingTouchPos.x, pendingTouchPos.y);
          pendingTouchPos = null;
          drawingNow = true;
          setIsDrawing(true);
          setHasSignature(true);
          ctx.lineTo(pos.x, pos.y);
          ctx.stroke();
        }
        return;
      }
      if (!drawingNow) return;
      ctx.lineTo(pos.x, pos.y);
      ctx.stroke();
    };
    const handleEnd = () => {
      pendingTouchPos = null;
      drawingNow = false;
      endDraw();
    };
    const trackStart = (e: TouchEvent) => {
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
      {/* WEB-UIUX-923: typed-signature keyboard alternative. */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center" style={{ maxWidth: width }}>
        <label htmlFor={typedSignatureId} className="sr-only">Type your full name to sign</label>
        <input
          id={typedSignatureId}
          type="text"
          value={typedSignature}
          onChange={(e) => setTypedSignature(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && typedSignature.trim()) {
              e.preventDefault();
              applyTypedSignature();
            }
          }}
          placeholder="Or type your full name to sign"
          autoComplete="name"
          className="min-h-[36px] min-w-0 flex-1 rounded-md border border-surface-300 bg-white px-3 py-1.5 text-sm text-surface-900 placeholder:text-surface-400 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
        />
        <button
          type="button"
          onClick={applyTypedSignature}
          disabled={!typedSignature.trim()}
          className="inline-flex items-center justify-center gap-1 rounded border border-surface-300 bg-surface-50 px-2 py-1 text-xs font-medium text-surface-700 hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
        >
          <Type aria-hidden="true" className="h-3 w-3" /> Use typed signature
        </button>
      </div>
      {hasSignature && (
        <button type="button" onClick={clear} className="btn btn-xs btn-ghost gap-1 text-surface-500 hover:text-red-500">
          <Eraser aria-hidden="true" className="h-3 w-3" /> Clear signature
        </button>
      )}
    </div>
  );
}
