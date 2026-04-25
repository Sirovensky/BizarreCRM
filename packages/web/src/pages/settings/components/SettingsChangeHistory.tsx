/**
 * SettingsChangeHistory — in-tab audit log snippet showing who changed what,
 * when. Reads from the existing /settings/audit-logs endpoint filtered by
 * settings_* event types. Addresses the critical-audit request to surface
 * change history inline rather than sending users to a separate tab.
 */

import { useQuery } from '@tanstack/react-query';
import { History, Loader2, User } from 'lucide-react';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatDateTime } from '@/utils/format';

interface AuditLogRow {
  id: number;
  event: string;
  user_name?: string | null;
  user_id?: number | null;
  meta?: string | null;
  created_at: string;
}

export interface SettingsChangeHistoryProps {
  /** Optional tab filter — only show logs related to this tab */
  tab?: string;
  /** Max rows to render */
  limit?: number;
  /** Layout variant */
  variant?: 'inline' | 'card';
  /** Extra className */
  className?: string;
}

const SETTINGS_EVENTS = [
  'settings_updated',
  'settings_reset',
  'settings_imported',
  'settings_exported',
  'store_updated',
  'user_created',
  'user_updated',
  'user_deleted',
];

export function SettingsChangeHistory({
  tab,
  limit = 10,
  variant = 'card',
  className,
}: SettingsChangeHistoryProps) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'audit-logs', tab],
    queryFn: async () => {
      const res = await settingsApi.getAuditLogs({ pagesize: limit });
      // { success, data: { logs: [...], meta: {...} } } is the most likely
      // shape; we also accept a plain array for older backends.
      const rawData: unknown = res.data?.data;
      let rows: AuditLogRow[] = [];
      if (Array.isArray(rawData)) {
        rows = rawData as AuditLogRow[];
      } else if (rawData && typeof rawData === 'object' && 'logs' in rawData) {
        const maybeLogs = (rawData as { logs?: unknown }).logs;
        if (Array.isArray(maybeLogs)) {
          rows = maybeLogs as AuditLogRow[];
        }
      }
      return rows
        .filter((r) => SETTINGS_EVENTS.includes(r.event) || r.event?.startsWith?.('settings'))
        .slice(0, limit);
    },
    staleTime: 30_000,
  });

  const rows = data ?? [];

  const content = (
    <div className="space-y-2">
      {isLoading && (
        <div className="flex items-center justify-center py-4 text-surface-400">
          <Loader2 className="h-4 w-4 animate-spin" />
        </div>
      )}
      {isError && (
        <p className="py-2 text-center text-xs text-surface-400">
          Unable to load change history.
        </p>
      )}
      {!isLoading && !isError && rows.length === 0 && (
        <p className="py-2 text-center text-xs text-surface-400">
          No recent changes recorded.
        </p>
      )}
      {rows.map((row) => (
        <div
          key={row.id}
          className="flex items-start gap-2 rounded-lg border border-surface-100 bg-surface-50 px-3 py-2 dark:border-surface-800 dark:bg-surface-800/30"
        >
          <User className="mt-0.5 h-3 w-3 flex-shrink-0 text-surface-400" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-xs font-medium text-surface-700 dark:text-surface-200">
              {row.user_name || `User #${row.user_id ?? '?'}`}
              <span className="ml-1 font-normal text-surface-500">{row.event}</span>
            </p>
            <p className="text-[10px] text-surface-400">
              {formatDateTime(row.created_at)}
            </p>
          </div>
        </div>
      ))}
    </div>
  );

  if (variant === 'inline') {
    return <div className={className}>{content}</div>;
  }

  return (
    <div
      className={cn(
        'rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800/60',
        className
      )}
    >
      <div className="mb-3 flex items-center gap-2">
        <History className="h-4 w-4 text-surface-500" />
        <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
          Recent Changes
        </h4>
      </div>
      {content}
    </div>
  );
}
