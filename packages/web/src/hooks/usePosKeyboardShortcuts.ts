import { useEffect } from 'react';

/**
 * F-key quick tabs for the unified POS page (audit §43.10).
 *
 *   F1 → Repairs tab        F4 → Customer search (focuses input)
 *   F2 → Products tab       F5 → Complete sale (opens checkout)
 *   F3 → Misc tab           F6 → Returns hotkey (scan invoice)
 *
 * Keep the surface small: the hook just binds listeners and calls back into
 * handlers the caller provides. Handlers are the single source of truth for
 * what each F-key actually does — this keeps POS and its tests decoupled.
 *
 * Matches the rule in common-coding-style.md: a tiny, focused module with
 * one public hook and zero side effects besides the listener.
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
  F5: 'onCompleteSale',
  F6: 'onReturnsHotkey',
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
  useEffect(() => {
    if (!enabled) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      const handlerKey = KEY_MAP[event.key];
      if (!handlerKey) return;
      // F4 (customer search) is the only one that's safe to fire from inside
      // a field — the rest would be jarring if the cashier is mid-entry.
      if (handlerKey !== 'onCustomerSearch' && isTypingInField(event.target)) return;
      const handler = handlers[handlerKey];
      if (!handler) return;
      event.preventDefault();
      handler();
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handlers, enabled]);
}
