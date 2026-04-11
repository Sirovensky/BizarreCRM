/**
 * MobileAccordionWrapper — replaces the horizontal tab strip with a vertical
 * collapsible menu on narrow viewports. Desktop behaviour is unchanged: the
 * wrapper renders its children untouched. On mobile, tabs become an
 * accordion where the active section is expanded and other tabs are a tap
 * away.
 *
 * The settings page has ~21 tabs. A horizontal tab bar on a phone means
 * either aggressive truncation or a scroll-arrow dance. Both are hostile for
 * a repair technician trying to find "Tax Classes" on a Samsung in a noisy
 * shop. An accordion is much friendlier.
 *
 * This component is a PURE WRAPPER — it does NOT hold tab state. The parent
 * (SettingsPage) still owns `activeTab` + `setActiveTab`. All the wrapper
 * does is decide "desktop: pass through" vs "mobile: render our menu" and
 * calls setActiveTab when a row is tapped.
 *
 * Small and cohesive on purpose — under 200 lines, no network, no context.
 */

import { useEffect, useState, type ReactNode } from 'react';
import { ChevronDown, Lock } from 'lucide-react';
import { cn } from '@/utils/cn';

export interface MobileTabItem {
  key: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  /** Rendered body for the tab (a <div>…</div> or a component) */
  body: ReactNode;
  /** Optional lock state — renders a padlock and disables navigation */
  locked?: boolean;
  /** Optional callback when a locked row is tapped (e.g. open upgrade modal) */
  onLockedTap?: () => void;
}

export interface MobileAccordionWrapperProps {
  /** Whichever tab key is currently active */
  activeKey: string;
  /** Setter for the active tab key */
  onChange: (key: string) => void;
  /** Full list of tabs in display order */
  items: MobileTabItem[];
  /** Desktop-only content — rendered as-is on wide screens */
  desktopTabs: ReactNode;
  /** Desktop-only body (the `activeTab === '...'` switch) */
  desktopBody: ReactNode;
  /** Pixel breakpoint for the switch (default 768, matches Tailwind `md`) */
  breakpointPx?: number;
}

/**
 * Media-query hook — cheap to roll our own rather than pull in a helper lib.
 * Hydrates with the current state synchronously on mount so the first render
 * doesn't flash desktop before switching to mobile.
 */
function useIsNarrow(breakpointPx: number): boolean {
  const getInitial = (): boolean => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia(`(max-width: ${breakpointPx - 1}px)`).matches;
  };
  const [narrow, setNarrow] = useState<boolean>(getInitial);
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const mq = window.matchMedia(`(max-width: ${breakpointPx - 1}px)`);
    const handler = (e: MediaQueryListEvent) => setNarrow(e.matches);
    // Safari < 14 uses addListener/removeListener — guard against that.
    if ('addEventListener' in mq) {
      mq.addEventListener('change', handler);
      return () => mq.removeEventListener('change', handler);
    }
    // @ts-expect-error legacy API
    mq.addListener(handler);
    return () => {
      // @ts-expect-error legacy API
      mq.removeListener(handler);
    };
  }, [breakpointPx]);
  return narrow;
}

export function MobileAccordionWrapper({
  activeKey,
  onChange,
  items,
  desktopTabs,
  desktopBody,
  breakpointPx = 768,
}: MobileAccordionWrapperProps) {
  const narrow = useIsNarrow(breakpointPx);

  if (!narrow) {
    return (
      <>
        {desktopTabs}
        {desktopBody}
      </>
    );
  }

  return (
    <div className="space-y-2" data-testid="settings-mobile-accordion">
      {items.map((item) => {
        const open = activeKey === item.key;
        const Icon = item.icon;
        return (
          <MobileAccordionRow
            key={item.key}
            item={item}
            open={open}
            Icon={Icon}
            onToggle={() => {
              if (item.locked) {
                item.onLockedTap?.();
                return;
              }
              onChange(open ? '' : item.key);
            }}
          />
        );
      })}
    </div>
  );
}

interface RowProps {
  item: MobileTabItem;
  open: boolean;
  Icon: React.ComponentType<{ className?: string }>;
  onToggle: () => void;
}

function MobileAccordionRow({ item, open, Icon, onToggle }: RowProps) {
  return (
    <section
      className={cn(
        'overflow-hidden rounded-xl border bg-white transition-colors dark:bg-surface-800/70',
        open
          ? 'border-primary-300 shadow-sm dark:border-primary-500/40'
          : 'border-surface-200 dark:border-surface-700'
      )}
    >
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        className={cn(
          'flex w-full items-center justify-between gap-2 px-4 py-3 text-left',
          open
            ? 'bg-primary-50/40 dark:bg-primary-500/10'
            : 'hover:bg-surface-50 dark:hover:bg-surface-800'
        )}
      >
        <span className="flex items-center gap-2">
          <Icon className="h-4 w-4 text-surface-500" />
          <span className="text-sm font-medium text-surface-900 dark:text-surface-100">
            {item.label}
          </span>
          {item.locked && (
            <Lock className="h-3 w-3 text-amber-500" aria-label="Locked (upgrade required)" />
          )}
        </span>
        <ChevronDown
          className={cn(
            'h-4 w-4 text-surface-400 transition-transform',
            open && 'rotate-180'
          )}
        />
      </button>

      {open && !item.locked && (
        <div className="border-t border-surface-100 bg-white p-2 dark:border-surface-800 dark:bg-surface-900/40">
          {item.body}
        </div>
      )}
    </section>
  );
}
