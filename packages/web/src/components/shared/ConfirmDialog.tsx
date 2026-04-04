import { useEffect, useRef, useState } from 'react';
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

export function ConfirmDialog({
  open, title, message, confirmLabel = 'Confirm', cancelLabel = 'Cancel',
  danger = false, requireTyping = false, confirmText = '', onConfirm, onCancel,
}: ConfirmDialogProps) {
  const confirmRef = useRef<HTMLButtonElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [typedValue, setTypedValue] = useState('');

  const typingMatch = !requireTyping || typedValue === confirmText;

  useEffect(() => {
    if (open) {
      setTypedValue('');
      if (requireTyping) {
        setTimeout(() => inputRef.current?.focus(), 50);
      } else {
        confirmRef.current?.focus();
      }
    }
  }, [open, requireTyping]);

  useEffect(() => {
    if (!open) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onCancel();
    };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [open, onCancel]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={onCancel}>
      <div className="w-full max-w-sm rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start gap-3">
          {danger && (
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-red-100 dark:bg-red-950/30">
              <AlertTriangle className="h-5 w-5 text-red-600 dark:text-red-400" />
            </div>
          )}
          <div>
            <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100">{title}</h3>
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
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-red-500"
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
