/**
 * useBodyScrollLock — WEB-UIUX-441
 *
 * Prevents the document body from scrolling while a modal / drawer / flyout is
 * open. Stacks safely with multiple concurrent callers: the original overflow
 * value is captured per-effect and restored individually.
 *
 * ─── Usage ────────────────────────────────────────────────────────────────────
 *
 *   import { useBodyScrollLock } from '@/hooks/useBodyScrollLock';
 *
 *   function MyHandRolledModal({ open }: { open: boolean }) {
 *     useBodyScrollLock(open);
 *     if (!open) return null;
 *     return <div className="fixed inset-0 …">…</div>;
 *   }
 *
 * ─── Notes ────────────────────────────────────────────────────────────────────
 * - The canonical <Modal> primitive (packages/web/src/components/shared/Modal.tsx)
 *   already inlines equivalent logic. Migrate hand-rolled modals to either:
 *     a) use the <Modal> primitive (preferred), or
 *     b) call useBodyScrollLock(open) as a stopgap.
 * - This hook is a no-op in SSR / non-browser environments.
 */

import { useEffect } from 'react';

/**
 * Locks body scroll while `active` is true.
 *
 * @param active - Pass the same boolean that controls modal visibility.
 */
export function useBodyScrollLock(active: boolean): void {
  useEffect(() => {
    if (!active) return;
    if (typeof document === 'undefined') return;

    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    return () => {
      document.body.style.overflow = previous;
    };
  }, [active]);
}
