import { useEffect, useRef, useState } from 'react';
import { Percent, X } from 'lucide-react';
import { createPortal } from 'react-dom';

/**
 * Inline line-item discount menu (audit §43.3).
 *
 * Small popover with a short list of reason codes and a percent input.
 * Consumers decide what to do with the result — this component is a pure
 * "pick a discount" primitive. The popover is portal-rendered so it can
 * escape overflow:hidden POS panels and always sit above the cart.
 *
 * Reason codes are borrowed from the audit description: loyalty, bulk,
 * employee, damaged. Custom reason is allowed as a free-text fallback.
 */

export type LineDiscountReason = 'loyalty' | 'bulk' | 'employee' | 'damaged' | 'custom';

export interface LineDiscount {
  percent: number;
  reason: LineDiscountReason;
  note: string;
}

const REASONS: Array<{ value: LineDiscountReason; label: string; color: string }> = [
  { value: 'loyalty', label: 'Loyalty', color: 'bg-pink-100 text-pink-700 dark:bg-pink-500/10 dark:text-pink-300' },
  { value: 'bulk', label: 'Bulk', color: 'bg-blue-100 text-blue-700 dark:bg-blue-500/10 dark:text-blue-300' },
  { value: 'employee', label: 'Employee', color: 'bg-green-100 text-green-700 dark:bg-green-500/10 dark:text-green-300' },
  { value: 'damaged', label: 'Damaged', color: 'bg-amber-100 text-amber-700 dark:bg-amber-500/10 dark:text-amber-300' },
  { value: 'custom', label: 'Custom', color: 'bg-surface-100 text-surface-700 dark:bg-surface-700 dark:text-surface-300' },
];

interface LineItemDiscountMenuProps {
  anchor: { x: number; y: number };
  initial?: LineDiscount | null;
  onApply: (discount: LineDiscount) => void;
  onClear: () => void;
  onClose: () => void;
}

export function LineItemDiscountMenu({
  anchor,
  initial,
  onApply,
  onClear,
  onClose,
}: LineItemDiscountMenuProps) {
  const [percent, setPercent] = useState(initial?.percent?.toString() ?? '10');
  const [reason, setReason] = useState<LineDiscountReason>(initial?.reason ?? 'loyalty');
  const [note, setNote] = useState(initial?.note ?? '');
  const ref = useRef<HTMLDivElement>(null);

  // Click outside dismisses. Escape also dismisses.
  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('mousedown', handleClick);
    document.addEventListener('keydown', handleKey);
    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('keydown', handleKey);
    };
  }, [onClose]);

  const handleApply = () => {
    const p = Math.max(0, Math.min(100, parseFloat(percent) || 0));
    if (p === 0) {
      onClear();
      return;
    }
    onApply({ percent: p, reason, note: note.trim() });
  };

  // Clamp popover inside viewport (right edge, bottom edge).
  const style: React.CSSProperties = {
    top: Math.min(anchor.y, window.innerHeight - 320),
    left: Math.min(anchor.x, window.innerWidth - 280),
  };

  return createPortal(
    <div
      ref={ref}
      style={style}
      className="fixed z-[100] w-72 rounded-xl border border-surface-200 bg-white p-3 shadow-2xl dark:border-surface-700 dark:bg-surface-900"
    >
      <div className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-surface-600 dark:text-surface-400">
          <Percent className="h-3 w-3" />
          Line Discount
        </div>
        <button
          onClick={onClose}
          aria-label="Close"
          className="rounded p-0.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="mb-2 flex flex-wrap gap-1">
        {REASONS.map((r) => (
          <button
            key={r.value}
            onClick={() => setReason(r.value)}
            className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${r.color} ${
              reason === r.value ? 'ring-2 ring-offset-1 ring-teal-500 dark:ring-offset-surface-900' : ''
            }`}
          >
            {r.label}
          </button>
        ))}
      </div>

      <label className="mb-2 block">
        <span className="mb-0.5 block text-[11px] font-medium text-surface-500">Percent (%)</span>
        <input
          type="number"
          min="0"
          max="100"
          step="1"
          value={percent}
          onChange={(e) => setPercent(e.target.value)}
          className="w-full rounded-md border border-surface-300 px-2 py-1 text-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
          autoFocus
        />
      </label>

      {reason === 'custom' && (
        <label className="mb-2 block">
          <span className="mb-0.5 block text-[11px] font-medium text-surface-500">Note</span>
          <input
            type="text"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Reason"
            className="w-full rounded-md border border-surface-300 px-2 py-1 text-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
          />
        </label>
      )}

      <div className="flex gap-2">
        <button
          onClick={() => {
            onClear();
          }}
          className="flex-1 rounded-md border border-surface-300 px-2 py-1.5 text-xs font-medium text-surface-600 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
        >
          Clear
        </button>
        <button
          onClick={handleApply}
          className="flex-1 rounded-md bg-teal-600 px-2 py-1.5 text-xs font-semibold text-white hover:bg-teal-700"
        >
          Apply
        </button>
      </div>
    </div>,
    document.body,
  );
}
