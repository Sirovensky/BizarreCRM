/**
 * Server store — tracks server online/offline status and last-known stats.
 * Supports graceful degradation: stats show "--" when server is unreachable.
 */
import { create } from 'zustand';
import type { ServerStats, ServiceStatus } from '@/api/bridge';

interface ServerState {
  isOnline: boolean;
  stats: ServerStats | null;
  serviceStatus: ServiceStatus | null;
  lastError: string | null;
  lastUpdated: number | null;

  // Actions
  setStats: (stats: ServerStats) => void;
  setOffline: (error: string) => void;
  setServiceStatus: (status: ServiceStatus) => void;
  /**
   * DASH-ELEC-054: clear stats/serviceStatus/multiTenant flag on logout so
   * post-logout components don't read leftover tenant counts. setOffline by
   * itself preserves last-known stats for graceful degradation, which is
   * wrong on logout (different security posture).
   */
  reset: () => void;
}

export const useServerStore = create<ServerState>((set) => ({
  isOnline: false,
  stats: null,
  serviceStatus: null,
  lastError: null,
  lastUpdated: null,

  setStats: (stats) =>
    set({
      isOnline: true,
      stats,
      lastError: null,
      lastUpdated: Date.now(),
    }),

  setOffline: (error) =>
    set((state) => ({
      isOnline: false,
      lastError: error,
      // Preserve last known stats for graceful degradation
      stats: state.stats,
    })),

  setServiceStatus: (status) =>
    set({ serviceStatus: status }),

  // DASH-ELEC-054
  reset: () =>
    set({
      isOnline: false,
      stats: null,
      serviceStatus: null,
      lastError: null,
      lastUpdated: null,
    }),
}));
