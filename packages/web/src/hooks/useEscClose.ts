import { useEffect, useRef } from 'react';

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
 * WEB-UIUX-561: a module-level stack ensures only the topmost registered
 * callback fires when Esc is pressed. Stacking modals no longer causes every
 * open layer to close simultaneously.
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

/** Module-level stack of active Esc callbacks. Last entry is the topmost layer. */
const escStack: Array<() => void> = [];

/** Single document-level handler shared by all hook instances. */
function globalEscHandler(e: KeyboardEvent): void {
  if (e.key !== 'Escape') return;
  const top = escStack[escStack.length - 1];
  if (top) {
    e.stopPropagation();
    top();
  }
}

// BUGHUNT-2026-05-16: remember the capture flag we used when registering the
// global handler. Without this, a first consumer mounting with capture=false
// adds (handler, false), a second with capture=true adds nothing (stack
// non-empty), and the last consumer to unmount removes with ITS capture
// value — which may not match the registered listener, leaking it forever.
let registeredCapture: boolean | null = null;

export function useEscClose(
  onClose: () => void,
  enabled: boolean = true,
  options: UseEscCloseOptions = {},
): void {
  const { capture = false } = options;

  // Keep a stable ref to the latest onClose so the stack entry stays current
  // even if the caller passes a new function reference on each render.
  const onCloseRef = useRef(onClose);
  useEffect(() => {
    onCloseRef.current = onClose;
  });

  useEffect(() => {
    if (!enabled) return;

    // Stable wrapper so push/pop identity matches across renders.
    const callback = () => onCloseRef.current();

    // Register the global handler on first consumer.
    if (escStack.length === 0) {
      document.addEventListener('keydown', globalEscHandler, capture);
      registeredCapture = capture;
    }

    escStack.push(callback);

    return () => {
      const idx = escStack.lastIndexOf(callback);
      if (idx !== -1) escStack.splice(idx, 1);

      // Remove the global handler when the last consumer unregisters. Use the
      // capture flag we recorded at registration time, not this consumer's
      // local capture — the two can differ across overlapping consumers.
      if (escStack.length === 0 && registeredCapture !== null) {
        document.removeEventListener('keydown', globalEscHandler, registeredCapture);
        registeredCapture = null;
      }
    };
  }, [enabled, capture]);
}
