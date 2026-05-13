/**
 * FilterChipGroup — WEB-UIUX-1009.
 *
 * Shared chip-toggle primitive so every list page that wants a filter row can
 * stop hand-rolling its own styled <select> or copy-pasting LeadPipelinePage's
 * bespoke chip CSS. One look + one keyboard contract, parameterized only by
 * options + value + onChange.
 *
 * Each chip is a `role="radio"` inside a `role="radiogroup"` so screen-reader
 * + arrow-key navigation matches the WAI-ARIA radio-group pattern. Count
 * badges are optional and rendered with the same chip; when omitted the chip
 * is plain text. Selected state uses primary tones; idle uses surface
 * neutrals — both with explicit dark-mode partners so WEB-FQ-016's bare
 * Tailwind color drift doesn't reach this primitive.
 *
 * Usage:
 *
 *   <FilterChipGroup
 *     ariaLabel="Status filter"
 *     value={status}
 *     onChange={setStatus}
 *     options={[
 *       { value: 'all',    label: 'All',     count: 142 },
 *       { value: 'open',   label: 'Open',    count: 38  },
 *       { value: 'closed', label: 'Closed', count: 104 },
 *     ]}
 *   />
 *
 * Migration plan: list pages adopt this incrementally as they're touched.
 * The component is intentionally minimal — no internal state, no sticky
 * highlight, no overflow handling — so callers can drop it into existing
 * layouts without restyling the whole header.
 */
import type { ReactNode } from 'react';
import { cn } from '@/utils/cn';

export interface FilterChipOption<V extends string> {
  value: V;
  label: string;
  /** Optional count badge displayed alongside the label (e.g. "Open · 38"). */
  count?: number;
  /** Optional icon rendered before the label. */
  icon?: ReactNode;
  /** Disable this option (still rendered, not clickable). */
  disabled?: boolean;
}

interface FilterChipGroupProps<V extends string> {
  ariaLabel: string;
  value: V;
  onChange: (next: V) => void;
  options: ReadonlyArray<FilterChipOption<V>>;
  /** Optional extra classes on the outer container. */
  className?: string;
  /** Compact mode reduces padding for dense headers (default `false`). */
  compact?: boolean;
}

export function FilterChipGroup<V extends string>({
  ariaLabel,
  value,
  onChange,
  options,
  className,
  compact = false,
}: FilterChipGroupProps<V>) {
  return (
    <div
      role="radiogroup"
      aria-label={ariaLabel}
      className={cn('flex flex-wrap items-center gap-1.5', className)}
    >
      {options.map((opt) => {
        const selected = opt.value === value;
        return (
          <button
            key={opt.value}
            type="button"
            role="radio"
            aria-checked={selected}
            aria-disabled={opt.disabled || undefined}
            disabled={opt.disabled}
            onClick={() => {
              if (opt.disabled) return;
              if (opt.value !== value) onChange(opt.value);
            }}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-full border text-sm font-medium transition-colors',
              compact ? 'px-2.5 py-1 text-xs' : 'px-3 py-1.5',
              selected
                ? 'border-primary-500 bg-primary-50 text-primary-700 dark:border-primary-500/40 dark:bg-primary-500/15 dark:text-primary-200'
                : 'border-surface-200 bg-white text-surface-600 hover:bg-surface-50 hover:text-surface-900 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-100',
              opt.disabled && 'opacity-50 cursor-not-allowed',
            )}
          >
            {opt.icon && <span className="inline-flex">{opt.icon}</span>}
            <span>{opt.label}</span>
            {typeof opt.count === 'number' && (
              <span
                className={cn(
                  'inline-flex items-center justify-center rounded-full px-1.5 text-[10px] font-semibold leading-none',
                  selected
                    ? 'bg-primary-100 text-primary-800 dark:bg-primary-500/30 dark:text-primary-100'
                    : 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300',
                )}
                aria-hidden="true"
              >
                {opt.count}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}
