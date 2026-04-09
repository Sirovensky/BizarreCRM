/**
 * Confirm dialog with optional type-to-confirm for dangerous actions.
 */
import { useState } from 'react';
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm animate-fade-in">
      <div className="w-[420px] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl p-6">
        {/* Header */}
        <div className="flex items-start justify-between mb-4">
          <div className="flex items-center gap-3">
            {danger && <AlertTriangle className="w-5 h-5 text-red-400" />}
            <h3 className="text-sm font-semibold text-surface-100">{title}</h3>
          </div>
          <button
            onClick={handleCancel}
            className="p-1 rounded hover:bg-surface-800 text-surface-500 hover:text-surface-300"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Message */}
        <p className="text-sm text-surface-400 mb-4">{message}</p>

        {/* Type to confirm */}
        {requireTyping && (
          <div className="mb-4">
            <p className="text-xs text-surface-500 mb-2">
              Type <span className="font-mono font-bold text-red-400">{requireTyping}</span> to confirm:
            </p>
            <input
              type="text"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              autoFocus
              className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-600 focus:border-red-500 focus:outline-none"
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
              'px-4 py-2 text-sm font-semibold rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed',
              danger
                ? 'bg-red-600 text-white hover:bg-red-700'
                : 'bg-accent-600 text-white hover:bg-accent-700'
            )}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
