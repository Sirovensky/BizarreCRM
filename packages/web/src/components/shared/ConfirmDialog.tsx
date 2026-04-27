import { useEffect, useRef, useState, useCallback } from 'react';
import { AlertTriangle } from 'lucide-react';

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
  /** When true, user must type `confirmText` to enable the confirm button */
  requireTyping?: boolean;
  /** Text the user must type to confirm (shown as hint). Required when requireTyping is true. */
  confirmText?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function ConfirmDialog({
  open, title, message, confirmLabel = 'Confirm', cancelLabel = 'Cancel',
  danger = false, requireTyping = false, confirmText = '', onConfirm, onCancel,
}: ConfirmDialogProps) {
  const confirmRef = useRef<HTMLButtonElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  // WEB-FD-010 (Fixer-AAA 2026-04-25): capture the element that was focused
  // when the dialog opened so keyboard users land back on the originating
  // delete/edit button instead of <body> after dismiss.
  const lastFocusedRef = useRef<HTMLElement | null>(null);
  const [typedValue, setTypedValue] = useState('');

  const typingMatch = !requireTyping || typedValue === confirmText;

  useEffect(() => {
    if (open) {
      lastFocusedRef.current = (document.activeElement as HTMLElement | null) ?? null;
      setTypedValue('');
      if (requireTyping) {
        requestAnimationFrame(() => inputRef.current?.focus());
      } else {
        requestAnimationFrame(() => confirmRef.current?.focus());
      }
      return () => {
        // Restore focus on close (cleanup runs when `open` flips back to
        // false or component unmounts). Guard against the originating
        // element having been unmounted in the interim.
        const prev = lastFocusedRef.current;
        if (prev && document.contains(prev) && typeof prev.focus === 'function') {
          try { prev.focus(); } catch { /* best-effort */ }
        }
        lastFocusedRef.current = null;
      };
    }
    return undefined;
  }, [open, requireTyping]);

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (!open) return;
    if (e.key === 'Escape') {
      onCancel();
      return;
    }
    if (e.key !== 'Tab') return;
    const dialog = dialogRef.current;
    if (!dialog) return;
    const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE));
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
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
  }, [open, onCancel]);

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm" role="presentation" onClick={onCancel}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby="confirm-dialog-title" className="w-full max-w-sm rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start gap-3">
          {danger && (
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-red-100 dark:bg-red-950/30">
              <AlertTriangle className="h-5 w-5 text-red-600 dark:text-red-400" />
            </div>
          )}
          <div>
            <h3 id="confirm-dialog-title" className="text-base font-semibold text-surface-900 dark:text-surface-100">{title}</h3>
            <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">{message}</p>
          </div>
        </div>

        {requireTyping && confirmText && (
          <div className="mt-4">
            <p className="text-xs text-surface-500 dark:text-surface-400 mb-1.5">
              Type <span className="font-mono font-semibold text-surface-700 dark:text-surface-300">{confirmText}</span> to confirm
            </p>
            <input
              ref={inputRef}
              type="text"
              value={typedValue}
              onChange={(e) => setTypedValue(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && typingMatch) onConfirm(); }}
              placeholder={confirmText}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
              autoComplete="off"
              spellCheck={false}
            />
          </div>
        )}

        <div className="mt-5 flex justify-end gap-2">
          <button onClick={onCancel} className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800">
            {cancelLabel}
          </button>
          <button
            ref={confirmRef}
            onClick={onConfirm}
            disabled={!typingMatch}
            className={`rounded-lg px-4 py-2 text-sm font-medium text-white transition-colors ${
              !typingMatch
                ? 'bg-surface-300 dark:bg-surface-600 cursor-not-allowed'
                : danger ? 'bg-red-600 hover:bg-red-700' : 'bg-primary-600 hover:bg-primary-700'
            }`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
