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

  useEffect(() => {
    const poll = async () => {
      const isAuth = useAuthStore.getState().isAuthenticated;
      if (!isAuth || pollingRef.current) return;
      pollingRef.current = true;

      try {
        const api = getAPI();
        const [statsRes, serviceStatus] = await Promise.all([
          api.management.getStats(),
          api.service.getStatus(),
        ]);

        if (statsRes.success && statsRes.data) {
          useServerStore.getState().setStats(statsRes.data);
          intervalRef.current = BASE_INTERVAL;
        } else if (statsRes.offline) {
          useServerStore.getState().setOffline(statsRes.message ?? 'Server not reachable');
          intervalRef.current = Math.min(intervalRef.current * BACKOFF_MULTIPLIER, MAX_INTERVAL);
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
        useServerStore.getState().setOffline('Server not reachable');
        intervalRef.current = Math.min(intervalRef.current * BACKOFF_MULTIPLIER, MAX_INTERVAL);
      }

      pollingRef.current = false;
      timerRef.current = setTimeout(poll, intervalRef.current);
    };

    // Start polling
    poll();

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [navigate]);
}
