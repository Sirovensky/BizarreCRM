import { useEffect, useRef } from 'react';

/**
 * Trap keyboard focus inside a container element while the trap is active.
 *
 * Implements the ARIA authoring-practices modal focus-trap pattern:
 *   - On activation, focuses the first focusable element (or the container itself
 *     if nothing focusable is found).
 *   - Tab / Shift+Tab cycle through focusable descendants, wrapping at each end.
 *   - On deactivation, restores focus to the element that was focused before the
 *     trap was enabled (e.g. the button that opened a modal).
 *
 * Usage (new modals / dialogs):
 *
 *   const containerRef = useFocusTrap(isOpen);
 *   return <div ref={containerRef} role="dialog" aria-modal="true">…</div>;
 *
 * Options:
 *   initialFocusSelector – CSS selector for the element to focus on open.
 *                          Falls back to the first focusable element, then the
 *                          container itself.
 *   returnFocusOnDeactivate – when false, focus is not restored on close
 *                             (default: true).
 *
 * WEB-UIUX-149: canonical hook — all modals that implement Esc + ARIA must
 * also call this hook to satisfy the WCAG 2.1 SC 2.1.2 focus-trap requirement.
 */
export interface UseFocusTrapOptions {
  /** CSS selector for the element to receive focus on open. */
  initialFocusSelector?: string;
  /** Restore focus to the previously focused element on deactivation. Default: true. */
  returnFocusOnDeactivate?: boolean;
}

/** CSS selector that matches all natively focusable elements. */
const FOCUSABLE_SELECTORS = [
  'a[href]',
  'button:not([disabled])',
  'details',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ');

function getFocusable(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTORS)).filter(
    (el) => !el.closest('[hidden]') && getComputedStyle(el).display !== 'none',
  );
}

export function useFocusTrap(
  active: boolean,
  options: UseFocusTrapOptions = {},
): React.RefObject<HTMLElement | null> {
  const { initialFocusSelector, returnFocusOnDeactivate = true } = options;

  // Ref that callers attach to the dialog/modal container element.
  const containerRef = useRef<HTMLElement | null>(null);
  // Remember what was focused before the trap opened so we can restore it.
  const previouslyFocusedRef = useRef<Element | null>(null);

  useEffect(() => {
    if (!active) return;

    const container = containerRef.current;
    if (!container) return;

    // Capture the currently focused element so we can restore it later.
    previouslyFocusedRef.current = document.activeElement;

    // Move focus into the trap.
    if (initialFocusSelector) {
      const target = container.querySelector<HTMLElement>(initialFocusSelector);
      if (target) {
        target.focus();
      } else {
        (getFocusable(container)[0] ?? container).focus();
      }
    } else {
      (getFocusable(container)[0] ?? container).focus();
    }

    // Handle Tab / Shift+Tab.
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key !== 'Tab') return;

      const focusable = getFocusable(container);
      if (focusable.length === 0) {
        e.preventDefault();
        return;
      }

      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      const active = document.activeElement;

      if (e.shiftKey) {
        // Shift+Tab: wrap from first → last.
        if (active === first || active === container) {
          e.preventDefault();
          last.focus();
        }
      } else {
        // Tab: wrap from last → first.
        if (active === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };

    // Use capture so the trap intercepts Tab before any other handler.
    document.addEventListener('keydown', handleKeyDown, true);

    return () => {
      document.removeEventListener('keydown', handleKeyDown, true);

      // Restore focus when the trap is deactivated.
      if (returnFocusOnDeactivate && previouslyFocusedRef.current instanceof HTMLElement) {
        previouslyFocusedRef.current.focus();
      }
      previouslyFocusedRef.current = null;
    };
  }, [active, initialFocusSelector, returnFocusOnDeactivate]);

  return containerRef;
}
