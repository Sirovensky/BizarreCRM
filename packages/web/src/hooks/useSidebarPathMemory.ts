/**
 * useSidebarPathMemory — remember last-visited URL per top-level list page so
 * sidebar NavLinks restore the operator's filter/sort/page state instead of
 * stripping it.
 *
 * WEB-UIUX-667: clicking "Tickets" in the side nav while on
 * `/tickets?status=in_progress&page=3` previously navigated to bare `/tickets`,
 * wiping the filter context. This hook (mounted at App-shell level) writes the
 * current `pathname + search` for each tracked prefix to sessionStorage on
 * every location change, and `resolveSidebarPath()` reads the saved version at
 * click time so the NavLink target carries the operator's last view.
 *
 * Scope: read-only — does not alter App behaviour beyond persisting a small
 * key per tracked prefix. Wipes on tab close (sessionStorage), so filter
 * state doesn't bleed across users on a shared kiosk login.
 */
import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';

// Top-level paths whose query state we want to preserve when the operator
// re-clicks them in the sidebar. New list-page routes should be added here as
// they ship.
const TRACKED_PREFIXES = [
  '/tickets',
  '/customers',
  '/invoices',
  '/inventory',
  '/leads',
  '/memberships',
  '/subscriptions',
  '/refunds',
  '/credit-notes',
  '/reports',
  '/gift-cards',
  '/communications',
  '/voice',
  '/timesheets',
  '/employees',
  '/appointments',
];

const STORAGE_PREFIX = 'sidebar-last:';

function isTrackedPrefix(pathname: string): string | null {
  for (const prefix of TRACKED_PREFIXES) {
    if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
      return prefix;
    }
  }
  return null;
}

export function useSidebarPathMemory(): void {
  const location = useLocation();

  useEffect(() => {
    const prefix = isTrackedPrefix(location.pathname);
    if (!prefix) return;
    // Only remember pathname-equals-prefix (i.e. the list view itself) — we
    // don't want clicking "Tickets" to jump back to `/tickets/123` if the
    // operator was on a detail row.
    if (location.pathname !== prefix) return;
    try {
      sessionStorage.setItem(
        `${STORAGE_PREFIX}${prefix}`,
        location.pathname + (location.search || ''),
      );
    } catch {
      // sessionStorage unavailable (rare; private mode quota). Silent.
    }
  }, [location.pathname, location.search]);
}

/**
 * Resolve a sidebar nav target to the last-seen URL for that prefix, if any.
 * Falls back to the original target when no memory exists or the prefix
 * isn't tracked.
 */
export function resolveSidebarPath(target: string): string {
  const prefix = isTrackedPrefix(target);
  if (!prefix || target !== prefix) return target;
  try {
    const saved = sessionStorage.getItem(`${STORAGE_PREFIX}${prefix}`);
    if (saved && (saved === prefix || saved.startsWith(`${prefix}?`))) {
      return saved;
    }
  } catch {
    // Silent — fall through to default target.
  }
  return target;
}
