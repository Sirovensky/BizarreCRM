import { useEffect, useRef } from 'react';

/**
 * F-key quick tabs for the unified POS page (audit §43.10).
 *
 *   F1 → Repairs tab        F4 → Customer search (focuses input)
 *   F2 → Products tab       Shift+F5 → Complete sale (opens checkout)
 *   F3 → Misc tab           F6 → Returns hotkey (scan invoice)
 *
 * Keep the surface small: the hook just binds listeners and calls back into
 * handlers the caller provides. Handlers are the single source of truth for
 * what each F-key actually does — this keeps POS and its tests decoupled.
 *
 * Matches the rule in common-coding-style.md: a tiny, focused module with
 * one public hook and zero side effects besides the listener.
 *
 * WEB-FD-005 (FIXED-by-Fixer-A3 2026-04-25): bare F5 is reserved by every
 * browser as "reload". Binding it as Complete-sale stole the cashier's
 * universal refresh affordance — a frozen POS could not be recovered with
 * F5; pressing it instead popped the checkout modal. We require Shift+F5
 * for Complete-sale so plain F5 still reloads the page. Cashiers who want
 * the keyboard shortcut hold Shift; everyone else gets browser refresh
 * back as a safety valve.
 */
export interface PosKeyboardHandlers {
  onRepairsTab?: () => void;
  onProductsTab?: () => void;
  onMiscTab?: () => void;
  onCustomerSearch?: () => void;
  onCompleteSale?: () => void;
  onReturnsHotkey?: () => void;
}

type HandlerKey = keyof PosKeyboardHandlers;

const KEY_MAP: Record<string, HandlerKey> = {
  F1: 'onRepairsTab',
  F2: 'onProductsTab',
  F3: 'onMiscTab',
  F4: 'onCustomerSearch',
  F6: 'onReturnsHotkey',
};

// WEB-FD-005: keys that require Shift to fire — keeps the bare key
// available for the browser default (F5 = reload).
const SHIFT_KEY_MAP: Record<string, HandlerKey> = {
  F5: 'onCompleteSale',
};

function isTypingInField(target: EventTarget | null): boolean {
  const tag = (target as HTMLElement | null)?.tagName;
  if (!tag) return false;
  // F4 must still fire so the cashier can jump into the search box even
  // from an input, but every other F-key should never steal focus from
  // a live text editor.
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
}

export function usePosKeyboardShortcuts(handlers: PosKeyboardHandlers, enabled = true): void {
  // Keep the latest handlers in a ref so an inline `{ onRepairsTab: ... }`
  // literal from the caller doesn't tear down + re-add the window listener
  // on every render. The listener itself is stable; it reads `handlersRef`
  // at fire time, always getting the freshest callbacks.
  const handlersRef = useRef(handlers);
  useEffect(() => {
    handlersRef.current = handlers;
  }, [handlers]);

  useEffect(() => {
    if (!enabled) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      // WEB-FD-005: Shift+F5 → Complete sale; bare F5 falls through to the
      // browser's reload. Modifier-keyed shortcuts must NOT also match the
      // bare-key map (no F1–F4/F6 with Shift held).
      let handlerKey: HandlerKey | undefined;
      if (event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
        handlerKey = SHIFT_KEY_MAP[event.key];
      } else if (!event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
        handlerKey = KEY_MAP[event.key];
      }
      if (!handlerKey) return;
      // F4 (customer search) is the only one that's safe to fire from inside
      // a field — the rest would be jarring if the cashier is mid-entry.
      if (handlerKey !== 'onCustomerSearch' && isTypingInField(event.target)) return;
      const handler = handlersRef.current[handlerKey];
      if (!handler) return;
      event.preventDefault();
      handler();
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [enabled]);
}
