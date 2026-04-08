import { X } from 'lucide-react';
import { cn } from '@/utils/cn';

// ─── Types ───────────────────────────────────────────────────────────

interface BulkAction {
  label: string;
  icon?: React.ReactNode;
  onClick: (selectedIds: (string | number)[]) => void;
  variant?: 'default' | 'danger';
}

interface BulkActionBarProps {
  selectedCount: number;
  selectedIds: (string | number)[];
  onClearSelection: () => void;
  actions: BulkAction[];
}

// ─── Component ───────────────────────────────────────────────────────

export function BulkActionBar({
  selectedCount,
  selectedIds,
  onClearSelection,
  actions,
}: BulkActionBarProps) {
  if (selectedCount === 0) return null;

  return (
    <div
      className={cn(
        'fixed bottom-0 left-0 right-0 z-40',
        'flex items-center justify-between gap-4 px-6 py-3',
        'border-t border-surface-200 bg-white shadow-lg',
        'dark:border-surface-700 dark:bg-surface-800',
        'animate-in slide-in-from-bottom duration-200',
      )}
    >
      {/* Left: count + clear */}
      <div className="flex items-center gap-3">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700 dark:bg-primary-950/30 dark:text-primary-400">
          {selectedCount} selected
        </span>
        <button
          type="button"
          onClick={onClearSelection}
          className="inline-flex items-center gap-1 rounded-lg px-2 py-1.5 text-sm text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-700 dark:hover:text-surface-200"
        >
          <X className="h-3.5 w-3.5" />
          Clear
        </button>
      </div>

      {/* Right: action buttons */}
      <div className="flex items-center gap-2">
        {actions.map((action) => (
          <button
            key={action.label}
            type="button"
            onClick={() => action.onClick(selectedIds)}
            className={cn(
              'inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
              action.variant === 'danger'
                ? 'bg-red-600 text-white hover:bg-red-700'
                : 'bg-primary-600 text-white hover:bg-primary-700',
            )}
          >
            {action.icon}
            {action.label}
          </button>
        ))}
      </div>
    </div>
  );
}
