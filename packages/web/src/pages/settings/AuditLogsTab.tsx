import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { settingsApi } from '@/api/endpoints';
import { Loader2, ChevronLeft, ChevronRight, Search, Filter, ShieldCheck } from 'lucide-react';
import { cn } from '@/utils/cn';

interface AuditLog {
  id: number;
  event: string;
  user_id: number | null;
  user_name: string | null;
  username: string | null;
  ip_address: string | null;
  details: string | null;
  created_at: string;
}

export function AuditLogsTab() {
  const [page, setPage] = useState(1);
  const [eventFilter, setEventFilter] = useState('');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['audit-logs', page, eventFilter, fromDate, toDate],
    queryFn: async () => {
      const params: Record<string, string | number> = { page, pagesize: 50 };
      if (eventFilter) params.event = eventFilter;
      if (fromDate) params.from_date = fromDate;
      if (toDate) params.to_date = toDate;
      const res = await settingsApi.getAuditLogs(params as any);
      return res.data.data as {
        logs: AuditLog[];
        event_types: string[];
        pagination: { page: number; per_page: number; total: number; total_pages: number };
      };
    },
  });

  const logs = data?.logs ?? [];
  const eventTypes = data?.event_types ?? [];
  const pagination = data?.pagination;

  function formatDetails(details: string | null): string {
    if (!details) return '-';
    try {
      const obj = JSON.parse(details);
      return Object.entries(obj)
        .map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : v}`)
        .join(', ');
    } catch {
      return details;
    }
  }

  function formatDate(iso: string): string {
    try {
      const d = new Date(iso.replace(' ', 'T'));
      return d.toLocaleString();
    } catch {
      return iso;
    }
  }

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-surface-100">Audit Logs</h3>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 items-end">
        <div>
          <label className="block text-xs text-surface-400 mb-1">Event Type</label>
          <select
            value={eventFilter}
            onChange={(e) => { setEventFilter(e.target.value); setPage(1); }}
            className="bg-surface-800 border border-surface-600 rounded px-2 py-1.5 text-sm text-surface-200"
          >
            <option value="">All Events</option>
            {eventTypes.map((e) => (
              <option key={e} value={e}>{e}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs text-surface-400 mb-1">From Date</label>
          <input
            type="date"
            value={fromDate}
            onChange={(e) => { setFromDate(e.target.value); setPage(1); }}
            className="bg-surface-800 border border-surface-600 rounded px-2 py-1.5 text-sm text-surface-200"
          />
        </div>
        <div>
          <label className="block text-xs text-surface-400 mb-1">To Date</label>
          <input
            type="date"
            value={toDate}
            onChange={(e) => { setToDate(e.target.value); setPage(1); }}
            className="bg-surface-800 border border-surface-600 rounded px-2 py-1.5 text-sm text-surface-200"
          />
        </div>
        {(eventFilter || fromDate || toDate) && (
          <button
            onClick={() => { setEventFilter(''); setFromDate(''); setToDate(''); setPage(1); }}
            className="text-xs text-orange-400 hover:text-orange-300 pb-1.5"
          >
            Clear filters
          </button>
        )}
      </div>

      {isLoading ? (
        <div className="py-12 text-center">
          <Loader2 className="h-6 w-6 animate-spin mx-auto text-surface-400" />
        </div>
      ) : logs.length === 0 ? (
        <div className="flex flex-col items-center py-12 text-center">
          <ShieldCheck className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-3" />
          <p className="text-sm font-medium text-surface-500 dark:text-surface-400">No audit logs found</p>
          <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">Logs appear here as users interact with the system. Try adjusting your filters.</p>
        </div>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-700 text-left text-surface-400">
                  <th className="py-2 px-3 font-medium">Time</th>
                  <th className="py-2 px-3 font-medium">Event</th>
                  <th className="py-2 px-3 font-medium">User</th>
                  <th className="py-2 px-3 font-medium">IP</th>
                  <th className="py-2 px-3 font-medium">Details</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((log) => (
                  <tr key={log.id} className="border-b border-surface-800 hover:bg-surface-800/50">
                    <td className="py-2 px-3 whitespace-nowrap text-surface-300">{formatDate(log.created_at)}</td>
                    <td className="py-2 px-3">
                      <span className="inline-block bg-surface-700 text-surface-200 rounded px-2 py-0.5 text-xs font-mono">
                        {log.event}
                      </span>
                    </td>
                    <td className="py-2 px-3 text-surface-300">
                      {log.user_name || log.username || (log.user_id ? `User #${log.user_id}` : '-')}
                    </td>
                    <td className="py-2 px-3 text-surface-400 font-mono text-xs">{log.ip_address || '-'}</td>
                    <td className="py-2 px-3 text-surface-400 text-xs max-w-xs truncate" title={formatDetails(log.details)}>
                      {formatDetails(log.details)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {pagination && pagination.total_pages > 1 && (
            <div className="flex items-center justify-between pt-2">
              <span className="text-xs text-surface-400">
                Showing {(pagination.page - 1) * pagination.per_page + 1}-{Math.min(pagination.page * pagination.per_page, pagination.total)} of {pagination.total}
              </span>
              <div className="flex gap-1">
                <button
                  aria-label="Previous page"
                  onClick={() => setPage(Math.max(1, page - 1))}
                  disabled={page <= 1}
                  className="inline-flex items-center justify-center rounded hover:bg-surface-700 disabled:opacity-30 min-h-[44px] min-w-[44px] md:min-h-[28px] md:min-w-[28px] md:p-1"
                >
                  <ChevronLeft className="h-4 w-4 text-surface-300" />
                </button>
                <span className="px-2 py-1 text-xs text-surface-300">
                  Page {pagination.page} / {pagination.total_pages}
                </span>
                <button
                  aria-label="Next page"
                  onClick={() => setPage(Math.min(pagination.total_pages, page + 1))}
                  disabled={page >= pagination.total_pages}
                  className="inline-flex items-center justify-center rounded hover:bg-surface-700 disabled:opacity-30 min-h-[44px] min-w-[44px] md:min-h-[28px] md:min-w-[28px] md:p-1"
                >
                  <ChevronRight className="h-4 w-4 text-surface-300" />
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
