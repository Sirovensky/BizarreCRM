/**
 * Confirm dialog with optional type-to-confirm for dangerous actions.
 *
 * MGT-024: Accessibility hardening
 *  - role="dialog" + aria-modal="true" + aria-labelledby / aria-describedby
 *  - Escape key → cancel
 *  - Focus trap: container gets focus on mount; Tab cycles first↔last focusable
 */
import { useState, useRef, useEffect, useCallback } from 'react';
import { AlertTriangle, X } from 'lucide-react';
import { cn } from '@/utils/cn';

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  danger?: boolean;
  requireTyping?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

let dialogIdCounter = 0;

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = 'Confirm',
  danger = false,
  requireTyping,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  const [typed, setTyped] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);

  // Stable IDs for aria-labelledby / aria-describedby (per component instance).
  const idRef = useRef<number | null>(null);
  if (idRef.current === null) {
    idRef.current = ++dialogIdCounter;
  }
  const titleId = `confirm-dialog-title-${idRef.current}`;
  const msgId = `confirm-dialog-msg-${idRef.current}`;

  if (!open) return null;

  const canConfirm = requireTyping ? typed === requireTyping : true;

  const handleConfirm = () => {
    if (!canConfirm) return;
    setTyped('');
    onConfirm();
  };

  const handleCancel = () => {
    setTyped('');
    onCancel();
  };

  return (
    <_ConfirmDialogInner
      containerRef={containerRef}
      titleId={titleId}
      msgId={msgId}
      title={title}
      message={message}
      confirmLabel={confirmLabel}
      danger={danger}
      requireTyping={requireTyping}
      typed={typed}
      setTyped={setTyped}
      canConfirm={canConfirm}
      handleConfirm={handleConfirm}
      handleCancel={handleCancel}
    />
  );
}

// Split into inner component so hooks (useEffect/useCallback) can be called
// unconditionally — the outer ConfirmDialog returns null when !open.
interface InnerProps {
  containerRef: React.RefObject<HTMLDivElement | null>;
  titleId: string;
  msgId: string;
  title: string;
  message: string;
  confirmLabel: string;
  danger: boolean;
  requireTyping?: string;
  typed: string;
  setTyped: (v: string) => void;
  canConfirm: boolean;
  handleConfirm: () => void;
  handleCancel: () => void;
}

function _ConfirmDialogInner({
  containerRef,
  titleId,
  msgId,
  title,
  message,
  confirmLabel,
  danger,
  requireTyping,
  typed,
  setTyped,
  canConfirm,
  handleConfirm,
  handleCancel,
}: InnerProps) {
  // MGT-024: Focus the first focusable element inside the dialog on mount.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const focusable = el.querySelectorAll<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );
    const first = focusable[0];
    if (first) {
      first.focus();
    } else {
      el.focus();
    }
  // intentional: containerRef is stable (ref object), effect is mount-only — focus the dialog once on open
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // MGT-024: Keyboard handler — Escape cancels; Tab is trapped inside dialog.
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (e.key === 'Escape') {
        handleCancel();
        return;
      }
      if (e.key === 'Tab') {
        const el = containerRef.current;
        if (!el) return;
        const focusable = Array.from(
          el.querySelectorAll<HTMLElement>(
            'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
          )
        ).filter((n) => !n.hasAttribute('disabled'));
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
      }
    },
    [handleCancel, containerRef]
  );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm animate-fade-in">
      {/* MGT-024: role="dialog" + aria-modal + aria-labelledby + aria-describedby */}
      <div
        ref={containerRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={msgId}
        tabIndex={-1}
        className="w-[420px] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl p-6 outline-none"
        onKeyDown={handleKeyDown}
      >
        {/* Header */}
        <div className="flex items-start justify-between mb-4">
          <div className="flex items-center gap-3">
            {danger && <AlertTriangle className="w-5 h-5 text-red-400" />}
            <h3 id={titleId} className="text-sm font-semibold text-surface-100">{title}</h3>
          </div>
          <button
            onClick={handleCancel}
            className="p-1 rounded hover:bg-surface-800 text-surface-500 hover:text-surface-300"
            aria-label="Cancel"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Message */}
        <p id={msgId} className="text-sm text-surface-400 mb-4">{message}</p>

        {/* Type to confirm */}
        {/* DASH-ELEC-169: explicit id + aria-describedby so screen readers
            announce the instruction (which value the operator must type)
            instead of just the placeholder. */}
        {requireTyping && (
          <div className="mb-4">
            <p id="confirm-typing-instruction" className="text-xs text-surface-500 mb-2">
              Type <span className="font-mono font-bold text-red-400">{requireTyping}</span> to confirm:
            </p>
            <input
              id="confirm-typing-input"
              type="text"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              autoFocus
              aria-label={`Type ${requireTyping} to confirm`}
              aria-describedby="confirm-typing-instruction"
              className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-red-500 focus:outline-none"
              placeholder={requireTyping}
            />
          </div>
        )}

        {/* Actions */}
        <div className="flex justify-end gap-2">
          <button
            onClick={handleCancel}
            className="px-4 py-2 text-sm text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleConfirm}
            disabled={!canConfirm}
            className={cn(
              // DASH-ELEC-143: disabled:opacity-40 drops danger button below 3:1;
              // raise to opacity-50 + darker bg + lighter text to maintain contrast.
              'px-4 py-2 text-sm font-semibold rounded-lg transition-colors disabled:cursor-not-allowed',
              danger
                ? 'bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 disabled:bg-red-800 disabled:text-red-200'
                : 'bg-accent-600 text-white hover:bg-accent-700 disabled:opacity-50'
            )}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
