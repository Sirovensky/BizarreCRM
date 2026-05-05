import { useEffect, useRef, useState } from 'react';
import { Clock } from 'lucide-react';
import { useUnifiedPosStore } from './store';

/**
 * Active sale inactivity timer (audit §43.13).
 *
 * Shows a small floating chip in the corner counting down the remaining
 * idle minutes. Resets on any mousedown/keydown/touchstart — these are the
 * same events the main inactivity reset in UnifiedPosPage listens to, so
 * the chip stays in sync without hoisting timer state globally.
 *
 * Only renders when a source ticket is loaded (i.e. we are editing an
 * existing ticket checkout) OR when the cart has at least one item. This
 * matches the audit rule: "auto-reset after 10 min of inactivity if ticket
 * is NOT yet created. Incomplete tickets stay open."
 */

interface InactivityTimerProps {
  enabled: boolean;
  timeoutMs: number;
}

export function InactivityTimer({ enabled, timeoutMs }: InactivityTimerProps) {
  const sourceTicketId = useUnifiedPosStore((s) => s.sourceTicketId);
  const cartItems = useUnifiedPosStore((s) => s.cartItems);
  const [secondsLeft, setSecondsLeft] = useState(Math.floor(timeoutMs / 1000));
  const deadlineRef = useRef<number>(Date.now() + timeoutMs);

  const shouldShow = enabled && (!!sourceTicketId || cartItems.length > 0);

  useEffect(() => {
    if (!shouldShow) return;

    const reset = () => {
      deadlineRef.current = Date.now() + timeoutMs;
    };
    reset();

    const tick = setInterval(() => {
      const remaining = Math.max(0, Math.floor((deadlineRef.current - Date.now()) / 1000));
      setSecondsLeft(remaining);
    }, 1000);

    const events: Array<keyof WindowEventMap> = ['mousedown', 'keydown', 'scroll', 'touchstart'];
    events.forEach((e) => window.addEventListener(e, reset, { passive: true }));

    return () => {
      clearInterval(tick);
      events.forEach((e) => window.removeEventListener(e, reset));
    };
  }, [shouldShow, timeoutMs]);

  if (!shouldShow || secondsLeft <= 0) return null;

  // Only show the chip when we're in the last 2 minutes — otherwise it's noise.
  if (secondsLeft > 120) return null;

  const minutes = Math.floor(secondsLeft / 60);
  const seconds = secondsLeft % 60;
  const label = `${minutes}:${seconds.toString().padStart(2, '0')}`;

  return (
    <div className="pointer-events-none fixed bottom-20 right-4 z-40 flex items-center gap-1.5 rounded-full bg-amber-100 px-3 py-1.5 text-xs font-semibold text-amber-800 shadow-lg ring-1 ring-amber-300 dark:bg-amber-500/20 dark:text-amber-300 dark:ring-amber-500/40">
      <Clock className="h-3 w-3" />
      Idle reset in {label}
    </div>
  );
}
