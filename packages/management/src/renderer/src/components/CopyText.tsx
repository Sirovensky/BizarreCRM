import { useState, useEffect, useRef } from 'react';
import { Check, Copy } from 'lucide-react';
import { cn } from '@/utils/cn';
import toast from 'react-hot-toast';

interface CopyTextProps {
  /** The value that gets copied. Falls back to `children` as a string when absent. */
  value?: string;
  children: React.ReactNode;
  /** Extra classes on the wrapper. Inline label/value styling stays on children. */
  className?: string;
  /** Hide the copy icon until hover. Default true — icon is ambient until hover. */
  hideIconUntilHover?: boolean;
  /** Toast text on success. Default "Copied {value}". */
  toastLabel?: string;
}

/**
 * Click-to-copy wrapper. Wraps inline text and surfaces a copy icon on
 * hover; on click, writes `value` (or the plain-text children) to the
 * system clipboard and briefly swaps the icon to a check-mark. Toast
 * keeps the feedback accessible for screen readers and for operators
 * who overshoot the hover area.
 */
export function CopyText({
  value, children, className, hideIconUntilHover = true, toastLabel,
}: CopyTextProps) {
  const [just, setJust] = useState(false);
  const resetTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Clear the reset timer on unmount to prevent setState on an unmounted component.
  useEffect(() => {
    return () => {
      if (resetTimerRef.current !== null) clearTimeout(resetTimerRef.current);
    };
  }, []);

  async function doCopy(e: React.MouseEvent) {
    e.stopPropagation();
    const text = value ?? (typeof children === 'string' ? children : '');
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setJust(true);
      toast.success(toastLabel ?? `Copied ${text.length > 32 ? text.slice(0, 32) + '…' : text}`);
      if (resetTimerRef.current !== null) clearTimeout(resetTimerRef.current);
      resetTimerRef.current = setTimeout(() => setJust(false), 1400);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Clipboard write failed');
    }
  }

  return (
    <span className={cn('group inline-flex items-center gap-1', className)}>
      <span>{children}</span>
      <button
        type="button"
        onClick={doCopy}
        aria-label={just ? 'Copied' : 'Copy to clipboard'}
        className={cn(
          'p-0.5 rounded text-surface-500 hover:text-surface-200 transition-opacity',
          'focus-visible:opacity-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent-500',
          hideIconUntilHover && !just && 'opacity-0 group-hover:opacity-100',
        )}
      >
        {just ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
      </button>
    </span>
  );
}
