import type { AuditLogParams } from '@/api/bridge';

export const managementQueryKeys = {
  all: ['management'] as const,
  serverHealth: () => [...managementQueryKeys.all, 'server-health'] as const,
  statsHistory: (range: string) => [...managementQueryKeys.all, 'stats-history', range] as const,
  statsHistorySeed: () => [...managementQueryKeys.all, 'stats-history-seed'] as const,
  crashMonitor: () => [...managementQueryKeys.all, 'crash-monitor'] as const,
  crashes: () => managementQueryKeys.crashMonitor(),
  auditLog: (params: AuditLogParams) => [...managementQueryKeys.all, 'audit-log', params] as const,
  recentActivity: () => [...managementQueryKeys.all, 'recent-activity'] as const,
  watchdogEvents: () => [...managementQueryKeys.all, 'watchdog-events'] as const,
} as const;
