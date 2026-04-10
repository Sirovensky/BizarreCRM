import { useState, useCallback } from 'react';

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
 *   localStorage key: "bizarrecrm:dismiss:{key}"  (prefixed to avoid collisions)
 *   value: "true"  (only written on dismissal; absence == not dismissed)
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
  const storageKey = `bizarrecrm:dismiss:${key}`;

  const [dismissed, setDismissed] = useState<boolean>(() => {
    try {
      return localStorage.getItem(storageKey) === 'true';
    } catch {
      return false;
    }
  });

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
