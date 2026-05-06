/**
 * Canonical <Modal> primitive — WEB-UIUX-436
 *
 * Owns: backdrop, role=dialog, aria-modal, aria-labelledby, Esc-to-close,
 * Tab focus-trap, click-outside-to-close, focus-restore on unmount.
 *
 * ─── Migration pattern ────────────────────────────────────────────────────
 *
 *   // Before (hand-rolled, e.g. ConfirmDialog, PinModal, UpgradeModal …)
 *   <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 …">
 *     <div role="dialog" aria-modal="true" aria-labelledby="dlg-title" ref={dialogRef} …>
 *       …keyboard/esc/focus-trap logic duplicated per component…
 *     </div>
 *   </div>
 *
 *   // After — drop in <Modal>, keep only your content
 *   import { Modal } from '@/components/shared/Modal';
 *
 *   <Modal
 *     open={isOpen}
 *     onClose={handleClose}
 *     labelledById="dlg-title"           // must match your <h2 id="dlg-title">
 *     describedById="dlg-desc"           // optional, matches <p id="dlg-desc">
 *     closeOnBackdrop={true}             // default true — set false for PIN gates
 *     zIndex="z-50"                      // default "z-50"; use "z-[100]" for top-layer
 *     size="md"                          // "sm" | "md" | "lg" | "xl" | "full"
 *     className=""                       // extra classes for the inner card
 *   >
 *     <h2 id="dlg-title">My Modal</h2>
 *     …
 *   </Modal>
 *
 * ─── Focus-trap ───────────────────────────────────────────────────────────
 * Tab cycles through all focusable children; Shift+Tab reverses. The
 * element that was focused when the modal opened is restored on close.
 *
 * ─── Backdrop ─────────────────────────────────────────────────────────────
 * bg-black/50 backdrop-blur-sm with fade-in animation (respects
 * prefers-reduced-motion). Card content stops propagation so clicks inside
 * never bubble to the backdrop handler.
 */

import { useEffect, useRef, useCallback, type ReactNode, type CSSProperties } from 'react';
import { createPortal } from 'react-dom';
import { useBodyScrollLock } from '@/hooks/useBodyScrollLock';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ModalSize = 'sm' | 'md' | 'lg' | 'xl' | 'full';

export interface ModalProps {
  /** Controls visibility. The component renders nothing when false. */
  open: boolean;
  /** Called when the user presses Esc or clicks the backdrop (if allowed). */
  onClose: () => void;
  /** id that matches the heading element inside the modal (aria-labelledby). */
  labelledById?: string;
  /** id that matches the description element inside the modal (aria-describedby). */
  describedById?: string;
  /**
   * Whether clicking the backdrop dismisses the modal.
   * Default: true. Set to false for gated modals (e.g. PIN entry, unsaved-changes
   * warnings) where accidental backdrop clicks must not lose state.
   */
  closeOnBackdrop?: boolean;
  /**
   * Tailwind z-index class applied to the backdrop layer.
   * Default: "z-50". Use "z-[100]" for modals that sit above the AppShell header.
   */
  zIndex?: string;
  /**
   * Pre-set max-width breakpoint for the inner card.
   * - sm  → max-w-sm  (~24rem)
   * - md  → max-w-md  (~28rem, default)
   * - lg  → max-w-lg  (~32rem)
   * - xl  → max-w-xl  (~36rem)
   * - full → max-w-full w-full (sheet / full-screen)
   */
  size?: ModalSize;
  /** Additional classes merged onto the inner card element. */
  className?: string;
  /** Inline styles for the inner card (escape hatch for dynamic heights). */
  style?: CSSProperties;
  children: ReactNode;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const FOCUSABLE_SELECTOR =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), ' +
  'textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

const SIZE_CLASSES: Record<ModalSize, string> = {
  sm:   'max-w-sm',
  md:   'max-w-md',
  lg:   'max-w-lg',
  xl:   'max-w-xl',
  full: 'max-w-full w-full',
};

// ---------------------------------------------------------------------------
// Hooks (private, kept co-located for single-file requirement)
// ---------------------------------------------------------------------------

/** Restore focus to the element that was active when `open` became true. */
function useFocusRestore(open: boolean) {
  const lastFocusedRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (open) {
      lastFocusedRef.current = document.activeElement as HTMLElement | null;
    } else {
      const prev = lastFocusedRef.current;
      lastFocusedRef.current = null;
      if (prev && document.contains(prev) && typeof prev.focus === 'function') {
        try { prev.focus(); } catch { /* best-effort */ }
      }
    }
  }, [open]);
}

/**
 * Trap Tab/Shift+Tab focus inside `ref` element, and call `onEsc` on Escape.
 * Only active while `open` is true.
 */
function useFocusTrapAndEsc(
  ref: React.RefObject<HTMLElement | null>,
  open: boolean,
  onEsc: () => void,
) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (!open) return;

      if (e.key === 'Escape') {
        e.preventDefault();
        onEsc();
        return;
      }

      if (e.key !== 'Tab') return;

      const el = ref.current;
      if (!el) return;
      const focusable = Array.from(el.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR));
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last  = focusable[focusable.length - 1];

      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault();
          last.focus();
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    },
    [open, onEsc, ref],
  );

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function Modal({
  open,
  onClose,
  labelledById,
  describedById,
  closeOnBackdrop = true,
  zIndex = 'z-50',
  size = 'md',
  className = '',
  style,
  children,
}: ModalProps) {
  const dialogRef = useRef<HTMLDivElement>(null);

  useFocusRestore(open);
  useFocusTrapAndEsc(dialogRef, open, onClose);
  useBodyScrollLock(open);

  // Auto-focus first focusable element when modal opens.
  useEffect(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => {
      const el = dialogRef.current;
      if (!el) return;
      const first = el.querySelector<HTMLElement>(FOCUSABLE_SELECTOR);
      first?.focus();
    });
    return () => cancelAnimationFrame(frame);
  }, [open]);

  if (!open) return null;

  const sizeClass = SIZE_CLASSES[size];

  const handleBackdropClick = () => {
    if (closeOnBackdrop) onClose();
  };

  return createPortal(
    <div
      // Backdrop — click-outside handled here
      role="presentation"
      className={[
        'fixed inset-0 flex items-center justify-center',
        zIndex,
        'bg-black/50 backdrop-blur-sm',
        'animate-in fade-in-0 duration-200 motion-reduce:animate-none',
      ].join(' ')}
      onClick={handleBackdropClick}
    >
      {/* Inner card — stops backdrop click propagation */}
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelledById}
        aria-describedby={describedById}
        className={[
          'relative w-full rounded-lg bg-white shadow-xl',
          'dark:bg-zinc-900',
          sizeClass,
          className,
        ].filter(Boolean).join(' ')}
        style={style}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>,
    document.body,
  );
}
