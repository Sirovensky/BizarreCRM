/**
 * useInactivityTimeout — WEB-UIUX-747
 *
 * Track keyboard/mouse/touch/visibility activity across the window. Fire
 * `onWarn` at `warnMs` of idleness so the user can decide to keep the
 * session; fire `onLogout` at `idleMs` of total idleness so an unattended
 * kiosk doesn't sit signed-in indefinitely. Both callbacks are stable across
 * renders via refs; activity events reset the idle anchor without
 * re-rendering the host.
 *
 * Defaults: warn at 25 min, logout at 30 min. The 5-minute gap matches the
 * standard "session expiring" UX pattern (banks, healthcare portals).
 */

import { useEffect, useRef } from 'react';

const ACTIVITY_EVENTS = [
  'mousedown',
  'keydown',
  'touchstart',
  'scroll',
  'visibilitychange',
] as const;

export interface UseInactivityTimeoutOptions {
  /** Milliseconds of inactivity before onWarn fires. Default 25 min. */
  warnMs?: number;
  /** Milliseconds of inactivity before onLogout fires. Default 30 min. */
  idleMs?: number;
  /** Whether the timer is armed. Default `true`. Pass `false` to disable. */
  enabled?: boolean;
  /** Fired once when the warn threshold is crossed. */
  onWarn?: () => void;
  /** Fired once when the idle threshold is crossed. */
  onLogout?: () => void;
}

export function useInactivityTimeout(opts: UseInactivityTimeoutOptions = {}): void {
  const {
    warnMs = 25 * 60 * 1000,
    idleMs = 30 * 60 * 1000,
    enabled = true,
    onWarn,
    onLogout,
  } = opts;

  const onWarnRef = useRef(onWarn);
  const onLogoutRef = useRef(onLogout);
  useEffect(() => { onWarnRef.current = onWarn; }, [onWarn]);
  useEffect(() => { onLogoutRef.current = onLogout; }, [onLogout]);

  useEffect(() => {
    if (!enabled) return;
    if (typeof window === 'undefined') return;

    let warnTimer: ReturnType<typeof setTimeout> | null = null;
    let logoutTimer: ReturnType<typeof setTimeout> | null = null;
    let warnFired = false;

    function arm() {
      if (warnTimer) clearTimeout(warnTimer);
      if (logoutTimer) clearTimeout(logoutTimer);
      warnFired = false;
      warnTimer = setTimeout(() => {
        warnFired = true;
        try { onWarnRef.current?.(); } catch { /* listener must not throw */ }
      }, warnMs);
      logoutTimer = setTimeout(() => {
        try { onLogoutRef.current?.(); } catch { /* listener must not throw */ }
      }, idleMs);
    }

    function reset() {
      // BUGHUNT-2026-05-16: previously this returned early after the warn had
      // fired, so the warn toast that says "move your mouse or press a key to
      // stay signed in" was a lie — moving the mouse couldn't extend the
      // session and logout fired 5 min later regardless. Now any activity
      // re-arms (including post-warn), matching the toast's promise.
      arm();
    }

    arm();
    for (const evt of ACTIVITY_EVENTS) {
      window.addEventListener(evt, reset, { passive: true });
    }
    return () => {
      if (warnTimer) clearTimeout(warnTimer);
      if (logoutTimer) clearTimeout(logoutTimer);
      for (const evt of ACTIVITY_EVENTS) {
        window.removeEventListener(evt, reset);
      }
    };
  }, [enabled, warnMs, idleMs]);
}
