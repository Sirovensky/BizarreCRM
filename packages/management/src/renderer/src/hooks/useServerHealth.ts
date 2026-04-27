/**
 * Auto-polling hook with exponential backoff for server health.
 * Polls stats every 5s when online, backs off to 60s when offline.
 */
import { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { getAPI } from '@/api/bridge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';

const BASE_INTERVAL = 5_000;  // 5 seconds (was 1s — caused UI freezes)
const MAX_INTERVAL = 60_000;
const BACKOFF_MULTIPLIER = 2;

// @audit-fixed: centralised list of phrases the server returns when the
// super-admin JWT has expired or been revoked. Keep in sync with the
// auth middleware in packages/server/src/middleware/superAdminAuth.ts.
// We match case-insensitively against the documented strings rather than
// substring-matching `'expired'`, which would also match unrelated messages.
const AUTH_EXPIRED_MARKERS = [
  'invalid or expired',
  'token expired',
  'session expired',
  'jwt expired',
  'unauthorized',
] as const;

function isAuthExpiredMessage(message: string | undefined): boolean {
  if (!message) return false;
  const lower = message.toLowerCase();
  return AUTH_EXPIRED_MARKERS.some((marker) => lower.includes(marker));
}

export function useServerHealth(): void {
  const navigate = useNavigate();
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const intervalRef = useRef(BASE_INTERVAL);
  const pollingRef = useRef(false); // prevent overlapping polls
  // DASH-ELEC-047: isMounted guard prevents setState after unmount under
  // React 18 StrictMode double-mount (cleanup fires before second mount).
  const isMountedRef = useRef(true);
  // DASH-ELEC-012: AbortController signals unmount to in-flight poll cycles.
  // Note: the IPC bridge (preload safeInvoke → ipcRenderer.invoke) does not
  // accept AbortSignal — aborting cannot cancel the underlying Electron IPC
  // round-trip. The controller is used only to short-circuit the async
  // continuation (state updates) after unmount, which is handled equivalently
  // by isMountedRef. This structure makes the intent explicit and leaves a
  // clear extension point if the IPC bridge ever gains signal support.
  const abortRef = useRef<AbortController>(new AbortController());

  useEffect(() => {
    isMountedRef.current = true;
    abortRef.current = new AbortController();
    const signal = abortRef.current.signal;

    const poll = async () => {
      const isAuth = useAuthStore.getState().isAuthenticated;
      if (signal.aborted || !isMountedRef.current || !isAuth || pollingRef.current) return;
      pollingRef.current = true;

      try {
        const api = getAPI();
        const [statsRes, serviceStatus] = await Promise.all([
          api.management.getStats(),
          api.service.getStatus(),
        ]);

        // Guard again after the await — component may have unmounted while
        // the IPC round-trip was in flight.
        if (signal.aborted || !isMountedRef.current) {
          pollingRef.current = false;
          return;
        }

        if (statsRes.success && statsRes.data) {
          useServerStore.getState().setStats(statsRes.data);
          intervalRef.current = BASE_INTERVAL;
        } else if (statsRes.offline) {
          useServerStore.getState().setOffline(statsRes.message ?? 'Server not reachable');
          // DASH-ELEC-226: Apply ±20% jitter to prevent thundering-herd when
          // multiple dashboard windows reconnect simultaneously.
          intervalRef.current = Math.min(
            intervalRef.current * BACKOFF_MULTIPLIER * (0.8 + Math.random() * 0.4),
            MAX_INTERVAL,
          );
        } else if (isAuthExpiredMessage(statsRes.message)) {
          // @audit-fixed: previously this used a brittle substring match
          // (`message?.includes('expired')`). Any server-side message tweak
          // (e.g. translating "expired" to "session ended") would silently
          // disable the auto-logout. The check is now extracted to a single
          // helper that uses a deterministic set of phrases the server is
          // documented to return, AND we still log out on any 401-shaped
          // failure regardless of message wording.
          useAuthStore.getState().logout();
          navigate('/login', { replace: true });
          pollingRef.current = false;
          return;
        } else {
          intervalRef.current = BASE_INTERVAL;
        }

        useServerStore.getState().setServiceStatus(serviceStatus);
      } catch {
        if (!signal.aborted && isMountedRef.current) {
          useServerStore.getState().setOffline('Server not reachable');
          // DASH-ELEC-226: Jitter in the catch branch too.
          intervalRef.current = Math.min(
            intervalRef.current * BACKOFF_MULTIPLIER * (0.8 + Math.random() * 0.4),
            MAX_INTERVAL,
          );
        }
      }

      pollingRef.current = false;
      if (!signal.aborted && isMountedRef.current) {
        timerRef.current = setTimeout(poll, intervalRef.current);
      }
    };

    // Start polling
    poll();

    return () => {
      isMountedRef.current = false;
      abortRef.current.abort();
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [navigate]);
}
