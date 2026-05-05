/**
 * DeadToggleAnnotation — wraps a settings toggle (or any row) and decides
 * whether to hide it entirely or render it with a "Coming Soon" badge.
 *
 * The decision is governed by `settingsDeadToggles.shouldHideDeadToggles()`:
 *   - Production: hide the row entirely so users can't flip nothing-switches.
 *   - Development: keep the row visible so engineers can audit coverage,
 *     but overlay the existing ComingSoonBadge so nobody forgets it's dead.
 *
 * Callers pass a `settingKey` matching the curated list in settingsDeadToggles.
 * If the key is NOT in the list (i.e. the toggle is actually live) this
 * component is a transparent passthrough — you can sprinkle it liberally.
 *
 * Composition shape:
 *
 *   <DeadToggleAnnotation settingKey="tcx_host">
 *     <ToggleRow ... />
 *   </DeadToggleAnnotation>
 *
 * Keep this component DUMB — no queries, no mutations, no side effects. It
 * should be safe to wrap any piece of UI without fear of re-render storms.
 */

import type { ReactNode } from 'react';
import { Clock } from 'lucide-react';
import { cn } from '@/utils/cn';
import {
  getDeadToggleEntry,
  isDeadToggle,
  shouldHideDeadToggles,
  type DeadCategory,
} from '../settingsDeadToggles';
import { ComingSoonBadge } from './ComingSoonBadge';

export interface DeadToggleAnnotationProps {
  /** store_config key for the wrapped toggle */
  settingKey: string;
  /** The actual UI (toggle row, input, etc.) */
  children: ReactNode;
  /**
   * Optional override — pass `true` to force-show even in production. Useful
   * for storybook / dev tools panels that deliberately surface everything.
   */
  forceVisible?: boolean;
  /** Extra className applied to the outer wrapper */
  className?: string;
}

export function DeadToggleAnnotation({
  settingKey,
  children,
  forceVisible = false,
  className,
}: DeadToggleAnnotationProps) {
  // Not on the dead list → render untouched. This is the common path.
  if (!isDeadToggle(settingKey)) {
    return <>{children}</>;
  }

  const hide = !forceVisible && shouldHideDeadToggles();
  if (hide) return null;

  const entry = getDeadToggleEntry(settingKey);
  const reason = entry?.reason ?? 'This setting does not yet affect any behavior.';
  const category = entry?.category ?? 'not-wired';

  return (
    <div
      data-dead-toggle={settingKey}
      data-dead-category={category}
      className={cn(
        'relative rounded-lg border border-amber-200/60 bg-amber-50/30 ring-1 ring-inset ring-amber-100/50 dark:border-amber-500/20 dark:bg-amber-500/5',
        className
      )}
    >
      <div className="pointer-events-none absolute right-2 top-2 z-10 flex items-center gap-1">
        <ComingSoonBadge status="coming_soon" compact />
      </div>
      {/* The wrapped UI — still interactive (dev mode), but visually muted */}
      <div className="opacity-75">{children}</div>
      <p className="mx-3 mb-2 mt-1 flex items-center gap-1 text-[10px] italic text-amber-700 dark:text-amber-300">
        <Clock className="h-2.5 w-2.5" />
        <span>{reason}</span>
        <CategoryChip category={category} />
      </p>
    </div>
  );
}

/** Small chip that tags WHY the toggle is dead. */
function CategoryChip({ category }: { category: DeadCategory }) {
  const labels: Record<DeadCategory, string> = {
    'not-wired': 'not wired',
    'partial-backend': 'partial backend',
    'server-only': 'server-only',
    planned: 'planned',
    deprecated: 'deprecated',
  };
  return (
    <span className="ml-auto rounded-full bg-amber-100 px-1.5 py-0.5 font-mono text-[9px] font-semibold uppercase text-amber-700 dark:bg-amber-500/20 dark:text-amber-200">
      {labels[category]}
    </span>
  );
}
