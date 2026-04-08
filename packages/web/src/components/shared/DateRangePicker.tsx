import { useState, useRef, useEffect } from 'react';
import { Calendar, ChevronDown } from 'lucide-react';
import { cn } from '@/utils/cn';

// ─── Types ───────────────────────────────────────────────────────────

interface DateRangeValue {
  from?: string;
  to?: string;
  preset?: string;
}

interface Preset {
  label: string;
  value: string;
}

interface DateRangePickerProps {
  value: DateRangeValue;
  onChange: (value: DateRangeValue) => void;
  presets?: Preset[];
}

// ─── Default presets ─────────────────────────────────────────────────

const DEFAULT_PRESETS: Preset[] = [
  { label: 'Today', value: 'today' },
  { label: 'Yesterday', value: 'yesterday' },
  { label: 'Last 7 Days', value: 'last_7' },
  { label: 'Last 30 Days', value: 'last_30' },
  { label: 'This Month', value: 'this_month' },
  { label: 'Last Month', value: 'last_month' },
  { label: 'Custom', value: 'custom' },
];

// ─── Helpers ─────────────────────────────────────────────────────────

function getPresetLabel(presets: Preset[], value: DateRangeValue): string {
  if (value.preset && value.preset !== 'custom') {
    const match = presets.find((p) => p.value === value.preset);
    if (match) return match.label;
  }
  if (value.from && value.to) {
    return `${value.from} – ${value.to}`;
  }
  if (value.from) return `From ${value.from}`;
  if (value.to) return `Until ${value.to}`;
  return 'Select dates';
}

// ─── Component ───────────────────────────────────────────────────────

export function DateRangePicker({
  value,
  onChange,
  presets = DEFAULT_PRESETS,
}: DateRangePickerProps) {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const isCustom = value.preset === 'custom';
  const displayLabel = getPresetLabel(presets, value);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [open]);

  const handlePresetClick = (preset: Preset) => {
    if (preset.value === 'custom') {
      onChange({ ...value, preset: 'custom' });
    } else {
      onChange({ preset: preset.value, from: undefined, to: undefined });
      setOpen(false);
    }
  };

  const handleFromChange = (from: string) => {
    onChange({ ...value, preset: 'custom', from });
  };

  const handleToChange = (to: string) => {
    onChange({ ...value, preset: 'custom', to });
  };

  return (
    <div ref={containerRef} className="relative">
      {/* Trigger button */}
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        className={cn(
          'inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm transition-colors',
          'border-surface-200 bg-white text-surface-700 hover:bg-surface-50',
          'dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700',
          open && 'ring-2 ring-primary-500/40',
        )}
      >
        <Calendar className="h-4 w-4 text-surface-400" />
        <span className="truncate max-w-[180px]">{displayLabel}</span>
        <ChevronDown className={cn('h-3.5 w-3.5 text-surface-400 transition-transform', open && 'rotate-180')} />
      </button>

      {/* Dropdown */}
      {open && (
        <div className={cn(
          'absolute top-full left-0 z-50 mt-1 w-64 rounded-xl border shadow-xl',
          'border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800',
        )}>
          {/* Preset list */}
          <div className="p-1.5">
            {presets.map((preset) => (
              <button
                key={preset.value}
                onClick={() => handlePresetClick(preset)}
                className={cn(
                  'w-full rounded-lg px-3 py-2 text-left text-sm transition-colors',
                  value.preset === preset.value
                    ? 'bg-primary-50 text-primary-700 dark:bg-primary-950/30 dark:text-primary-400'
                    : 'text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700',
                )}
              >
                {preset.label}
              </button>
            ))}
          </div>

          {/* Custom date inputs */}
          {isCustom && (
            <div className="border-t border-surface-200 dark:border-surface-700 p-3 space-y-2">
              <div>
                <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">
                  From
                </label>
                <input
                  type="date"
                  value={value.from ?? ''}
                  onChange={(e) => handleFromChange(e.target.value)}
                  className={cn(
                    'w-full rounded-lg border px-3 py-2 text-sm',
                    'border-surface-200 bg-white text-surface-900',
                    'dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100',
                    'focus:outline-none focus:ring-2 focus:ring-primary-500/40',
                  )}
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">
                  To
                </label>
                <input
                  type="date"
                  value={value.to ?? ''}
                  onChange={(e) => handleToChange(e.target.value)}
                  min={value.from ?? undefined}
                  className={cn(
                    'w-full rounded-lg border px-3 py-2 text-sm',
                    'border-surface-200 bg-white text-surface-900',
                    'dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100',
                    'focus:outline-none focus:ring-2 focus:ring-primary-500/40',
                  )}
                />
              </div>
              <button
                onClick={() => setOpen(false)}
                disabled={!value.from || !value.to}
                className={cn(
                  'w-full rounded-lg px-3 py-2 text-sm font-medium text-white transition-colors',
                  value.from && value.to
                    ? 'bg-primary-600 hover:bg-primary-700'
                    : 'bg-surface-300 dark:bg-surface-600 cursor-not-allowed',
                )}
              >
                Apply
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
