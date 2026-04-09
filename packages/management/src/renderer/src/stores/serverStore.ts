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
}));
