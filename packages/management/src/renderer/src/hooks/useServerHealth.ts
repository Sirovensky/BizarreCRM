/**
 * Auto-polling hook with exponential backoff for server health.
 * Polls stats every 5s when online, backs off to 60s when offline.
 */
import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAPI, type ServiceStatus } from '@/api/bridge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { managementQueryKeys } from '@/hooks/managementQueryKeys';

const BASE_INTERVAL = 5_000;  // 5 seconds (was 1s — caused UI freezes)
const MAX_INTERVAL = 60_000;
const BACKOFF_MULTIPLIER = 2;

interface HealthSnapshot {
  statsRes: Awaited<ReturnType<ReturnType<typeof getAPI>['management']['getStats']>> | null;
  statsError: string | null;
  serviceStatus: ServiceStatus | null;
}

function nextBackoffMs(current: number): number {
  // DASH-ELEC-226: Apply ±20% jitter to prevent thundering-herd when
  // multiple dashboard windows reconnect simultaneously.
  return Math.min(current * BACKOFF_MULTIPLIER * (0.8 + Math.random() * 0.4), MAX_INTERVAL);
}

function messageFromError(err: unknown): string {
  return err instanceof Error ? err.message : 'Server not reachable';
}

function isServiceStatus(value: unknown): value is ServiceStatus {
  return (
    value !== null &&
    typeof value === 'object' &&
    'state' in value &&
    'mode' in value
  );
}

export function useServerHealth(): void {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const [pollIntervalMs, setPollIntervalMs] = useState(BASE_INTERVAL);

  const { data, refetch } = useQuery({
    queryKey: managementQueryKeys.serverHealth(),
    enabled: isAuthenticated,
    queryFn: async (): Promise<HealthSnapshot> => {
      if (!useAuthStore.getState().isAuthenticated) {
        return { statsRes: null, statsError: null, serviceStatus: null };
      }

      const api = getAPI();
      const [statsResult, serviceResult] = await Promise.allSettled([
        api.management.getStats(),
        api.service.getStatus(),
      ]);

      return {
        statsRes: statsResult.status === 'fulfilled' ? statsResult.value : null,
        statsError: statsResult.status === 'rejected' ? messageFromError(statsResult.reason) : null,
        serviceStatus: serviceResult.status === 'fulfilled' && isServiceStatus(serviceResult.value)
          ? serviceResult.value
          : null,
      };
    },
    staleTime: 4_000,
    refetchInterval: pollIntervalMs,
    refetchIntervalInBackground: false,
    refetchOnWindowFocus: true,
    retry: false,
    // Each poll updates serverStore.lastUpdated and drives offline backoff, so
    // identical payloads must still publish a fresh snapshot.
    structuralSharing: false,
  });

  useEffect(() => {
    if (!isAuthenticated) return undefined;

    const unsubscribe = getAPI().system.onPowerResume(() => {
      if (!useAuthStore.getState().isAuthenticated) return;
      setPollIntervalMs(BASE_INTERVAL);
      void refetch();
    });

    return unsubscribe;
  }, [isAuthenticated, refetch]);

  useEffect(() => {
    if (!isAuthenticated || !data) return;

    // DASH-ELEC-232: re-check auth after the await — a logout that fires while
    // the request is in-flight must not repopulate the cleared server store.
    if (!useAuthStore.getState().isAuthenticated) return;

    if (data.statsError) {
      useServerStore.getState().setOffline(data.statsError);
      setPollIntervalMs((current) => nextBackoffMs(current));
      return;
    }

    if (data.statsRes) {
      if (handleApiResponse(data.statsRes)) return;

      if (data.statsRes.success && data.statsRes.data) {
        useServerStore.getState().setStats(data.statsRes.data);
        setPollIntervalMs(BASE_INTERVAL);
      } else if (data.statsRes.offline) {
        useServerStore.getState().setOffline(data.statsRes.message ?? 'Server not reachable');
        setPollIntervalMs((current) => nextBackoffMs(current));
      } else {
        setPollIntervalMs(BASE_INTERVAL);
      }
    }

    // DASH-ELEC-096: contextBridge strips TypeScript types — the actual IPC
    // result is `unknown`. Narrow to ServiceStatus before storing; a shape
    // mismatch after a main-process handler change surfaces here rather than
    // propagating a malformed object into the store and crashing UI renders.
    if (data.serviceStatus) {
      useServerStore.getState().setServiceStatus(data.serviceStatus);
    }
  }, [data, isAuthenticated]);
}
