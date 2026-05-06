import { useEffect } from 'react';

/**
 * Attach a keyboard listener that calls `onClose` when the user presses Escape.
 * The listener is only active while `enabled` is true (default: true), so
 * callers can gate it on whether the modal/drawer is currently open without
 * conditionally calling the hook.
 *
 * Usage — replace each ad-hoc useEffect+keydown+Escape block:
 *
 *   // Before (inline, repeated in 35+ files):
 *   useEffect(() => {
 *     const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
 *     document.addEventListener('keydown', handler);
 *     return () => document.removeEventListener('keydown', handler);
 *   }, [onClose]);
 *
 *   // After:
 *   useEscClose(onClose);            // always enabled
 *   useEscClose(onClose, isOpen);    // only while modal is open
 *
 * Options:
 *   enabled  – when false the listener is never added (default: true).
 *   capture  – pass true to use capture phase (useful for nested modals that
 *              need to intercept Esc before a parent handler fires).
 *
 * The handler calls `e.stopPropagation()` by default so only the top-most
 * modal receives the keystroke when modals are stacked. Pass `capture: true`
 * on the outermost layer if you need capture-phase ordering instead.
 *
 * WEB-UIUX-9: canonical hook — new modals, drawers, and popovers should use
 * this instead of duplicating their own keydown logic.
 */
export interface UseEscCloseOptions {
  /** Set to false to skip attaching the listener (e.g. when the modal is closed). */
  enabled?: boolean;
  /** Use capture phase. Useful for nested modals. Default: false. */
  capture?: boolean;
}

export function useEscClose(
  onClose: () => void,
  enabled: boolean = true,
  options: UseEscCloseOptions = {},
): void {
  const { capture = false } = options;

  useEffect(() => {
    if (!enabled) return;

    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
      }
    };

    document.addEventListener('keydown', handler, capture);
    return () => document.removeEventListener('keydown', handler, capture);
  }, [onClose, enabled, capture]);
}
