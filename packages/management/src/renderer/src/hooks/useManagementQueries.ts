import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { getAPI } from '@/api/bridge';
import type {
  ApiResponse,
  AuditEntry,
  AuditLogParams,
  CrashEntry,
  CrashStats,
  DisabledRoute,
  MetricsDataPoint,
  SecurityAlert,
  WatchdogEvent,
} from '@/api/bridge';
import { formatApiError } from '@/utils/apiError';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { managementQueryKeys } from '@/hooks/managementQueryKeys';

export const CRASH_MONITOR_REFETCH_MS = 30_000;
export const AUDIT_LOG_REFETCH_MS = 60_000;
export const RECENT_ACTIVITY_REFETCH_MS = 60_000;
export const STATS_HISTORY_REFETCH_MS = 60_000;
export const WATCHDOG_EVENTS_REFETCH_MS = 5_000;

interface CrashMonitorData {
  crashes: CrashEntry[];
  crashStats: CrashStats | null;
  disabledRoutes: DisabledRoute[];
}

interface AuditLogPageData {
  entries: AuditEntry[];
  nextOffset: number;
  hasMore: boolean;
}

interface RecentActivityData {
  audit: AuditEntry[];
  alerts: SecurityAlert[];
}

class AuthHandledQueryError extends Error {
  constructor() {
    super('Authentication expired');
    this.name = 'AuthHandledQueryError';
  }
}

function apiData<T>(res: ApiResponse<T>, fallbackMessage: string): T {
  if (handleApiResponse(res)) {
    throw new AuthHandledQueryError();
  }
  if (res.success && res.data !== undefined) {
    return res.data;
  }
  throw new Error(res.message ? formatApiError(res) : fallbackMessage);
}

function assertApiSuccess(res: ApiResponse<unknown>, fallbackMessage: string): void {
  if (handleApiResponse(res)) {
    throw new AuthHandledQueryError();
  }
  if (!res.success) {
    throw new Error(res.message ? formatApiError(res) : fallbackMessage);
  }
}

function parseAuditEntries(data: unknown): AuditEntry[] {
  if (Array.isArray(data)) return data as AuditEntry[];
  if (data && typeof data === 'object' && 'logs' in data) {
    const logs = (data as { logs?: unknown }).logs;
    if (Array.isArray(logs)) return logs as AuditEntry[];
  }
  return [];
}

function normalizeWatchdogEventsResponse(res: unknown): WatchdogEvent[] {
  if (res && typeof res === 'object' && 'success' in res) {
    const apiRes = res as ApiResponse<{ events?: WatchdogEvent[] } | WatchdogEvent[]>;
    const data = apiData(apiRes, 'Failed to load watchdog events');
    if (Array.isArray(data)) return data;
    if (data && Array.isArray(data.events)) return data.events;
    return [];
  }

  if (res && typeof res === 'object' && 'ok' in res) {
    const watchdogRes = res as { ok: boolean; code?: string; message?: string; events?: WatchdogEvent[] };
    if (watchdogRes.ok) return watchdogRes.events ?? [];
    if (handleApiResponse({ success: false, code: watchdogRes.code, message: watchdogRes.message })) {
      throw new AuthHandledQueryError();
    }
    throw new Error(watchdogRes.message ?? watchdogRes.code ?? 'Failed to load watchdog events');
  }

  throw new Error('Failed to load watchdog events');
}

export function useCrashMonitorQuery() {
  return useQuery({
    queryKey: managementQueryKeys.crashMonitor(),
    queryFn: async (): Promise<CrashMonitorData> => {
      const api = getAPI();
      const [crashRes, statsRes, routesRes] = await Promise.all([
        api.management.getCrashes(),
        api.management.getCrashStats(),
        api.management.getDisabledRoutes(),
      ]);

      return {
        crashes: apiData(crashRes, 'Failed to load crash log'),
        crashStats: apiData(statsRes, 'Failed to load crash stats'),
        disabledRoutes: apiData(routesRes, 'Failed to load disabled routes'),
      };
    },
    staleTime: 15_000,
    refetchInterval: CRASH_MONITOR_REFETCH_MS,
    retry: false,
  });
}

export function useAuditLogQuery(params: AuditLogParams, pageSize: number) {
  return useInfiniteQuery({
    queryKey: managementQueryKeys.auditLog(params),
    initialPageParam: params.offset ?? 0,
    queryFn: async ({ pageParam }): Promise<AuditLogPageData> => {
      const offset = Number(pageParam) || 0;
      const res = await getAPI().superAdmin.getAuditLog({ ...params, offset });
      assertApiSuccess(res, 'Failed to load audit log');
      const entries = parseAuditEntries(res.data);
      return {
        entries,
        nextOffset: offset + entries.length,
        hasMore: entries.length === pageSize,
      };
    },
    getNextPageParam: (lastPage) => lastPage.hasMore ? lastPage.nextOffset : undefined,
    staleTime: 30_000,
    refetchInterval: AUDIT_LOG_REFETCH_MS,
    retry: false,
  });
}

export function useRecentActivityQuery(enabled: boolean) {
  return useQuery({
    queryKey: managementQueryKeys.recentActivity(),
    enabled,
    queryFn: async (): Promise<RecentActivityData> => {
      const [auditRes, alertsRes] = await Promise.all([
        getAPI().superAdmin.getAuditLog({ limit: 5 }),
        getAPI().superAdmin.listSecurityAlerts({ acknowledged: 0, limit: 3 }),
      ]);

      const audit = parseAuditEntries(apiData(auditRes, 'Failed to load audit log')).slice(0, 3);
      const alerts = apiData(alertsRes, 'Failed to load security alerts').alerts.slice(0, 3);
      return { audit, alerts };
    },
    staleTime: 30_000,
    refetchInterval: RECENT_ACTIVITY_REFETCH_MS,
    retry: false,
  });
}

export function useStatsHistoryQuery(range: string, enabled: boolean) {
  return useQuery({
    queryKey: managementQueryKeys.statsHistory(range),
    enabled,
    queryFn: async (): Promise<MetricsDataPoint[]> => {
      const res = await getAPI().management.getStatsHistory(range);
      return apiData(res, 'Failed to load stats history');
    },
    staleTime: 30_000,
    refetchInterval: STATS_HISTORY_REFETCH_MS,
    retry: false,
  });
}

export function useStatsHistorySeedQuery(enabled: boolean) {
  return useQuery({
    queryKey: managementQueryKeys.statsHistorySeed(),
    enabled,
    queryFn: async (): Promise<MetricsDataPoint[]> => {
      for (const range of ['1h', '6h', '1d']) {
        const res = await getAPI().management.getStatsHistory(range);
        const data = apiData(res, `Failed to load ${range} stats history`);
        if (data.length >= 3 || range === '1d') {
          return data;
        }
      }
      return [];
    },
    staleTime: 60_000,
    refetchInterval: false,
    retry: false,
  });
}

export function useWatchdogEventsQuery() {
  return useQuery({
    queryKey: managementQueryKeys.watchdogEvents(),
    queryFn: async (): Promise<WatchdogEvent[]> => {
      const res = await getAPI().management.getWatchdogEvents();
      return normalizeWatchdogEventsResponse(res);
    },
    staleTime: 2_000,
    refetchInterval: WATCHDOG_EVENTS_REFETCH_MS,
    retry: false,
  });
}
