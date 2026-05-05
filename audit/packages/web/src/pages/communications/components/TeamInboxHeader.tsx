import { useQuery } from '@tanstack/react-query';
import { Users, Inbox as InboxIcon, Clock } from 'lucide-react';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

/**
 * Team inbox header — audit §51.1 + §51.10.
 *
 * Shows a compact summary above the conversation list:
 *   - Unread count for the current user
 *   - Assigned-to-me filter toggle
 *   - First-response SLA average (last 30 days)
 *
 * Emits a simple callback when the "assigned to me" filter is toggled so
 * the parent (CommunicationPage) can re-query conversations with the
 * matching server-side filter.
 */

interface TeamInboxHeaderProps {
  assignedFilter: 'all' | 'me';
  onFilterChange: (filter: 'all' | 'me') => void;
  className?: string;
}

interface UnreadData {
  unread: number;
}

interface SlaData {
  window_days: number;
  avg_first_response_minutes: number;
  total_inbound: number;
  responded: number;
}

async function fetchUnread(): Promise<UnreadData> {
  const res = await api.get<{ success: boolean; data: UnreadData }>('/inbox/unread-count');
  return res.data.data;
}

async function fetchSla(): Promise<SlaData> {
  const res = await api.get<{ success: boolean; data: SlaData }>('/inbox/sla-stats?days=30');
  return res.data.data;
}

export function TeamInboxHeader({
  assignedFilter,
  onFilterChange,
  className,
}: TeamInboxHeaderProps) {
  const { data: unread } = useQuery({
    queryKey: ['inbox-unread'],
    queryFn: fetchUnread,
    refetchInterval: 20000,
  });

  const { data: sla } = useQuery({
    queryKey: ['inbox-sla', 30],
    queryFn: fetchSla,
    refetchInterval: 60000,
  });

  return (
    <div
      className={cn(
        'flex items-center justify-between gap-2 border-b border-surface-200 bg-surface-50 px-3 py-1.5 dark:border-surface-700 dark:bg-surface-800/60',
        className,
      )}
    >
      <div className="flex items-center gap-1 text-[11px] font-medium text-surface-700 dark:text-surface-300">
        <InboxIcon className="h-3.5 w-3.5 text-primary-500" />
        Team Inbox
        {(unread?.unread ?? 0) > 0 && (
          <span className="ml-1 inline-flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold text-white">
            {unread?.unread}
          </span>
        )}
      </div>
      <div className="flex items-center gap-2">
        <div className="flex items-center gap-1 rounded-md bg-white p-0.5 shadow-sm dark:bg-surface-700">
          <button
            onClick={() => onFilterChange('all')}
            className={cn(
              'rounded px-2 py-0.5 text-[10px] font-medium transition-colors',
              assignedFilter === 'all'
                ? 'bg-primary-100 text-primary-700 dark:bg-primary-900/40 dark:text-primary-300'
                : 'text-surface-500 hover:text-surface-700 dark:text-surface-400',
            )}
          >
            All
          </button>
          <button
            onClick={() => onFilterChange('me')}
            className={cn(
              'flex items-center gap-0.5 rounded px-2 py-0.5 text-[10px] font-medium transition-colors',
              assignedFilter === 'me'
                ? 'bg-primary-100 text-primary-700 dark:bg-primary-900/40 dark:text-primary-300'
                : 'text-surface-500 hover:text-surface-700 dark:text-surface-400',
            )}
          >
            <Users className="h-2.5 w-2.5" />
            Mine
          </button>
        </div>
        {sla && sla.total_inbound > 0 && (
          <div
            title={`Avg first response — ${sla.responded}/${sla.total_inbound} replied in last ${sla.window_days}d`}
            className="hidden items-center gap-0.5 text-[10px] text-surface-500 md:flex"
          >
            <Clock className="h-2.5 w-2.5" />
            {sla.avg_first_response_minutes}m avg
          </div>
        )}
      </div>
    </div>
  );
}
