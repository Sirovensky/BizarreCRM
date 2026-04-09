/**
 * Auto-polling hook with exponential backoff for server health.
 * Polls stats every 5s when online, backs off to 60s when offline.
 */
import { useEffect, useRef, useCallback } from 'react';
import { getAPI } from '@/api/bridge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';

const BASE_INTERVAL = 5_000;
const MAX_INTERVAL = 60_000;
const BACKOFF_MULTIPLIER = 2;

export function useServerHealth(): void {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const setStats = useServerStore((s) => s.setStats);
  const setOffline = useServerStore((s) => s.setOffline);
  const setServiceStatus = useServerStore((s) => s.setServiceStatus);
  const intervalRef = useRef(BASE_INTERVAL);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const poll = useCallback(async () => {
    if (!isAuthenticated) return;

    const api = getAPI();

    try {
      // Poll stats and service status in parallel
      const [statsRes, serviceStatus] = await Promise.all([
        api.management.getStats(),
        api.service.getStatus(),
      ]);

      if (statsRes.success && statsRes.data) {
        setStats(statsRes.data);
        intervalRef.current = BASE_INTERVAL; // Reset on success
      } else if (statsRes.offline) {
        // Actual network failure — server unreachable
        setOffline(statsRes.message ?? 'Server not reachable');
        intervalRef.current = Math.min(
          intervalRef.current * BACKOFF_MULTIPLIER,
          MAX_INTERVAL
        );
      } else {
        // Server responded but with an error (429 rate limit, 401 auth, etc.)
        // Keep last known stats, don't mark offline — server IS running
        intervalRef.current = BASE_INTERVAL;
      }

      setServiceStatus(serviceStatus);
    } catch {
      setOffline('Server not reachable');
      intervalRef.current = Math.min(
        intervalRef.current * BACKOFF_MULTIPLIER,
        MAX_INTERVAL
      );
    }

    // Schedule next poll
    timerRef.current = setTimeout(poll, intervalRef.current);
  }, [isAuthenticated, setStats, setOffline, setServiceStatus]);

  useEffect(() => {
    if (!isAuthenticated) {
      if (timerRef.current) clearTimeout(timerRef.current);
      return;
    }

    // Initial poll
    poll();

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [isAuthenticated, poll]);
}
