import { useState, useCallback, useEffect } from 'react';
import { useAuthStore } from '@/stores/authStore';

/**
 * Track the dismissal state of a UI element (banner, alert, announcement, etc.)
 * with persistence in the browser's localStorage. Returns a [dismissed, dismiss]
 * tuple for use in components.
 *
 * Usage:
 *   const [dismissed, dismiss] = useDismissible('dev-banner');
 *   if (dismissed) return null;
 *   return <Banner><CloseButton onClick={dismiss} /></Banner>;
 *
 * Storage layout:
 *   localStorage key: "bizarrecrm:dismiss:u{userId}:{key}"  (per-user namespaced)
 *   value: "true"  (only written on dismissal; absence == not dismissed)
 *
 * WEB-FI-023: keys are now scoped by the current user id so a banner dismissed
 * by user A on a shared browser does NOT stay dismissed for user B (different
 * tenant or same-tenant teammate). Pre-login dismissals are namespaced under
 * "anon" so they don't bleed into a logged-in user's slot.
 *
 * Keys may include variant info so different states of the same banner track
 * separately. Example: `trial-banner-info:${trialEndsAt}` — a new trial period
 * produces a different key and the banner reappears for the new trial.
 *
 * Resilience: localStorage access is wrapped in try/catch so the hook works
 * in environments where storage is blocked (Safari private mode, strict
 * cookie blockers, iframes with no storage access). In those cases dismissal
 * still works for the current session but won't persist across reloads.
 *
 * @param key - A unique identifier for this dismissible element. Will be
 *              prefixed with "bizarrecrm:dismiss:" when stored.
 */
export function useDismissible(key: string): readonly [boolean, () => void] {
  // Subscribe to the user-id slot so dismissals re-key automatically on
  // login / switchUser / logout. Selector keeps re-renders to id changes only.
  const userId = useAuthStore((s) => s.user?.id ?? null);
  const userScope = userId == null ? 'anon' : `u${userId}`;
  const storageKey = `bizarrecrm:dismiss:${userScope}:${key}`;

  const [dismissed, setDismissed] = useState<boolean>(() => {
    try {
      return localStorage.getItem(storageKey) === 'true';
    } catch {
      return false;
    }
  });

  // SCAN-1154: useState initializer runs once on mount, so keys that embed
  // a version suffix (e.g. `trial-banner-info:${trialEndsAt}`) — which the
  // JSDoc above actively encourages — never re-read storage when the suffix
  // changes. A new trial period would keep the old dismissed:true in state
  // until a reload. Re-sync from storage whenever `storageKey` changes.
  useEffect(() => {
    try {
      setDismissed(localStorage.getItem(storageKey) === 'true');
    } catch {
      setDismissed(false);
    }
  }, [storageKey]);

  const dismiss = useCallback(() => {
    setDismissed(true);
    try {
      localStorage.setItem(storageKey, 'true');
    } catch {
      // localStorage unavailable — dismissal still works for this session
    }
  }, [storageKey]);

  return [dismissed, dismiss] as const;
}
