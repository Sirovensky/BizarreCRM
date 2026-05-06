/**
 * Toggle / Switch primitive — canonical shared component.
 *
 * Replaces 8 local variants in settings pages (AutomationsTab, BlockChypSettings,
 * MembershipSettings, NotificationTemplatesTab, PosSettings, ReceiptSettings,
 * SmsVoiceSettings, TicketsRepairsSettings). Call sites can migrate incrementally.
 *
 * Sizes
 *   sm  — h-5 w-9  thumb h-3.5 w-3.5  (AutomationsTab / NotificationTemplatesTab style)
 *   md  — h-6 w-11 thumb h-4 w-4      (BlockChyp / Membership / POS / Tickets style)
 *
 * Color
 *   primary — bg-primary-600 (default)
 *   teal    — bg-teal-500   (ReceiptSettings style)
 *   green   — bg-green-500  (BlockChypSettings style)
 *
 * Layout variants
 *   • <Toggle checked onChange /> — bare switch only
 *   • <Toggle checked onChange label="…" /> — switch + label inline
 *   • <Toggle checked onChange label="…" description="…" /> — switch + stacked label/description
 *   • <Toggle checked onChange disabled /> — disabled (opacity-50, pointer-events-none)
 *   • <Toggle checked onChange comingSoon /> — alias for disabled with "Coming soon" badge
 */

import { cn } from '@/utils/cn';

export type ToggleSize = 'sm' | 'md';
export type ToggleColor = 'primary' | 'teal' | 'green';

export interface ToggleProps {
  checked: boolean;
  onChange: (value: boolean) => void;
  label?: string;
  description?: string;
  size?: ToggleSize;
  color?: ToggleColor;
  disabled?: boolean;
  /** Convenience alias: disabled + "Coming soon" badge */
  comingSoon?: boolean;
  className?: string;
  id?: string;
}

const trackSizes: Record<ToggleSize, string> = {
  sm: 'h-5 w-9',
  md: 'h-6 w-11',
};

const thumbSizes: Record<ToggleSize, { base: string; on: string; off: string }> = {
  sm: {
    base: 'h-3.5 w-3.5',
    on:  'translate-x-[18px]',
    off: 'translate-x-[2px]',
  },
  md: {
    base: 'h-4 w-4',
    on:  'translate-x-6',
    off: 'translate-x-1',
  },
};

const trackColors: Record<ToggleColor, string> = {
  primary: 'bg-primary-600',
  teal:    'bg-teal-500',
  green:   'bg-green-500',
};

export function Toggle({
  checked,
  onChange,
  label,
  description,
  size = 'md',
  color = 'primary',
  disabled = false,
  comingSoon = false,
  className,
  id,
}: ToggleProps) {
  const isDisabled = disabled || comingSoon;
  const thumb = thumbSizes[size];

  const button = (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      id={id}
      disabled={isDisabled}
      onClick={() => !isDisabled && onChange(!checked)}
      className={cn(
        'relative inline-flex shrink-0 items-center rounded-full border-2 border-transparent',
        'transition-colors duration-200',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-1',
        trackSizes[size],
        checked ? trackColors[color] : 'bg-surface-300 dark:bg-surface-600',
        isDisabled && 'cursor-not-allowed opacity-50',
        !label && className,
      )}
    >
      <span
        className={cn(
          'pointer-events-none inline-block rounded-full bg-white shadow-sm transition-transform duration-200',
          thumb.base,
          checked ? thumb.on : thumb.off,
        )}
      />
    </button>
  );

  if (!label) return button;

  return (
    <label
      className={cn(
        'flex items-start gap-3',
        isDisabled ? 'cursor-not-allowed' : 'cursor-pointer',
        className,
      )}
    >
      <span className="mt-0.5 shrink-0">{button}</span>
      <span className="min-w-0">
        <span className="flex items-center gap-2">
          <span className="text-sm font-medium text-surface-900 dark:text-surface-100">
            {label}
          </span>
          {comingSoon && (
            <span className="rounded bg-surface-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-surface-500 dark:bg-surface-700 dark:text-surface-400">
              Coming soon
            </span>
          )}
        </span>
        {description && (
          <span className="mt-0.5 block text-xs text-surface-400 dark:text-surface-500">
            {description}
          </span>
        )}
      </span>
    </label>
  );
}

export default Toggle;
