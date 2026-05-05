/**
 * ComingSoonBadge — visually flags a setting as "coming soon" so users know
 * it's intentionally non-functional. Directly addresses the critical-audit
 * finding: 65 of 70 toggles silently did nothing, which eroded trust.
 *
 * Rendering this next to a toggle is MUCH better than letting users flip
 * switches that go nowhere.
 */

import { Clock, AlertCircle } from 'lucide-react';
import { cn } from '@/utils/cn';
import type { SettingStatus } from '../settingsMetadata';

export interface ComingSoonBadgeProps {
  /** Full status — 'live' renders nothing, 'beta' and 'coming_soon' render distinct badges */
  status: SettingStatus;
  /** Optional className for positioning */
  className?: string;
  /** When true, renders a smaller version for crowded UIs */
  compact?: boolean;
}

export function ComingSoonBadge({ status, className, compact = false }: ComingSoonBadgeProps) {
  if (status === 'live') return null;

  if (status === 'beta') {
    return (
      <span
        className={cn(
          'inline-flex items-center gap-1 rounded-full border border-amber-300 bg-amber-50 px-2 py-0.5 font-semibold text-amber-700 dark:border-amber-500/40 dark:bg-amber-500/10 dark:text-amber-300',
          compact ? 'text-[10px]' : 'text-xs',
          className
        )}
        title="This setting is in beta — the backend partially enforces it"
      >
        <AlertCircle className={compact ? 'h-2.5 w-2.5' : 'h-3 w-3'} />
        Beta
      </span>
    );
  }

  // status === 'coming_soon'
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full border border-surface-300 bg-surface-100 px-2 py-0.5 font-semibold text-surface-600 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-300',
        compact ? 'text-[10px]' : 'text-xs',
        className
      )}
      title="This setting does not yet affect any behavior. We're being honest instead of pretending it works."
    >
      <Clock className={compact ? 'h-2.5 w-2.5' : 'h-3 w-3'} />
      Coming Soon
    </span>
  );
}
