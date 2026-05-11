import { useState, useEffect, useMemo, memo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { settingsApi } from '@/api/endpoints';
import { Loader2, ChevronLeft, ChevronRight, Search, Filter, ShieldCheck, RefreshCw } from 'lucide-react';
import { cn } from '@/utils/cn';
import { formatDateTime } from '@/utils/format';

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

// Cap rendered detail length. Huge title-attr strings stall native tooltip
// rendering and the truncated cell never shows them anyway.
const MAX_DETAIL_LEN = 300;

// WEB-UIUX-906: avoid surfacing hashed PINs / IPs / PII through hover tooltips.
// Browser title= attributes are visible to screen-share, screenshot OCR, and
// accessibility tooling. Redact known-sensitive fields before rendering details.
const REDACTED_KEYS = new Set([
  'pin', 'pin_hash', 'password', 'password_hash', 'token', 'refresh_token',
  'ssn', 'ein', 'tax_id', 'card_number', 'cvv', 'cvc', 'fingerprint',
  'authorization', 'cookie', 'set-cookie',
]);

function isRedactedKey(k: string): boolean {
  const lower = k.toLowerCase();
  if (REDACTED_KEYS.has(lower)) return true;
  // Heuristic: anything ending in _hash / _token / _secret.
  return /_hash$|_token$|_secret$/.test(lower);
}

function formatDetails(details: string | null): string {
  if (!details) return '-';
  let out: string;
  try {
    const obj = JSON.parse(details);
    out = Object.entries(obj)
      .map(([k, v]) => {
        if (isRedactedKey(k)) return `${k}: ‹redacted›`;
        return `${k}: ${typeof v === 'object' ? JSON.stringify(v) : v}`;
      })
      .join(', ');
  } catch {
    out = details;
  }
  return out.length > MAX_DETAIL_LEN ? out.slice(0, MAX_DETAIL_LEN) + '…' : out;
}

const filterControlClassName =
  'rounded border border-surface-200 bg-white px-2 py-1.5 text-sm text-surface-900 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200';

const AuditLogRow = memo(function AuditLogRow({ log }: { log: AuditLog }) {
  const formattedDetails = useMemo(() => formatDetails(log.details), [log.details]);
  const formattedTime = useMemo(
    () => formatDateTime(log.created_at?.replace(' ', 'T')),
    [log.created_at],
  );
  const userDisplay = log.user_name || log.username || (log.user_id ? `User #${log.user_id}` : '-');

  return (
    <tr className="border-b border-surface-100 hover:bg-surface-50 dark:border-surface-800 dark:hover:bg-surface-800/50">
      <td className="py-2 px-3 whitespace-nowrap text-surface-700 dark:text-surface-300">{formattedTime}</td>
      <td className="py-2 px-3">
        <span className="inline-block rounded bg-surface-100 px-2 py-0.5 text-xs font-mono text-surface-700 dark:bg-surface-700 dark:text-surface-200">
          {log.event}
        </span>
      </td>
      <td className="py-2 px-3 text-surface-700 dark:text-surface-300">{userDisplay}</td>
      <td className="py-2 px-3 text-surface-500 dark:text-surface-400 font-mono text-xs">{log.ip_address || '-'}</td>
      <td
        className="py-2 px-3 text-surface-500 dark:text-surface-400 text-xs max-w-xs truncate"
        title={formattedDetails}
      >
        {formattedDetails}
      </td>
    </tr>
  );
});

export function AuditLogsTab() {
  const [page, setPage] = useState(1);
  const [eventFilter, setEventFilter] = useState('');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  // WEB-FG-015 fix: typing into a <input type="date"> emits onChange on every
  // numeric cycle (10 keystrokes for "2026-04-24"), and the audit endpoint is
  // paginated + join-heavy. Debounce the date filters so we only refetch
  // 250 ms after the user stops typing. Event-type select is single-change so
  // it stays bound directly. The debounced values feed the queryKey.
  const [debouncedFrom, setDebouncedFrom] = useState('');
  const [debouncedTo, setDebouncedTo] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setDebouncedFrom(fromDate), 250);
    return () => clearTimeout(t);
  }, [fromDate]);
  useEffect(() => {
    const t = setTimeout(() => setDebouncedTo(toDate), 250);
    return () => clearTimeout(t);
  }, [toDate]);

  // Live tail toggle. When OFF (default), no silent refetches — the user can
  // scroll/inspect without rows shifting under them. When ON, poll every 5 s
  // and pin to page 1 (newer rows arrive at top under DESC ordering).
  const [liveTail, setLiveTail] = useState(false);
  useEffect(() => {
    if (liveTail && page !== 1) setPage(1);
  }, [liveTail, page]);

  // Cache event_types + total across paginations. The server skips the COUNT
  // and DISTINCT-event scans when ?meta=skip, which is the dominant cost on a
  // large audit_logs table. We only refetch meta when filters change.
  const [cachedEventTypes, setCachedEventTypes] = useState<string[]>([]);
  const [cachedTotal, setCachedTotal] = useState<number | null>(null);
  const [cachedTotalPages, setCachedTotalPages] = useState<number | null>(null);
  // Reset cached meta whenever the filter window changes — totals depend on it.
  const filterKey = `${eventFilter}|${debouncedFrom}|${debouncedTo}`;
  const [lastFilterKey, setLastFilterKey] = useState(filterKey);
  useEffect(() => {
    if (filterKey !== lastFilterKey) {
      setCachedTotal(null);
      setCachedTotalPages(null);
      setLastFilterKey(filterKey);
    }
  }, [filterKey, lastFilterKey]);
  // Decide if this request should ask the server for meta. First load, filter
  // change, or live-tail polling skip meta to keep the response cheap.
  const wantsMeta = cachedTotal === null || cachedEventTypes.length === 0;

  const { data, isLoading, isFetching, refetch } = useQuery({
    queryKey: ['audit-logs', page, eventFilter, debouncedFrom, debouncedTo, wantsMeta],
    queryFn: async () => {
      const params: Record<string, string | number> = { page, pagesize: 50 };
      if (eventFilter) params.event = eventFilter;
      if (debouncedFrom) params.from_date = debouncedFrom;
      if (debouncedTo) params.to_date = debouncedTo;
      if (!wantsMeta) params.meta = 'skip';
      const res = await settingsApi.getAuditLogs(params as any);
      return res.data.data as {
        logs: AuditLog[];
        event_types: string[] | null;
        pagination: { page: number; per_page: number; total: number | null; total_pages: number | null };
      };
    },
    refetchOnWindowFocus: false,
    refetchOnMount: false,
    refetchInterval: liveTail ? 5000 : false,
  });

  // Merge fresh meta into cache.
  useEffect(() => {
    if (data?.event_types && data.event_types.length > 0) {
      setCachedEventTypes(data.event_types);
    }
    if (data?.pagination?.total != null) {
      setCachedTotal(data.pagination.total);
      setCachedTotalPages(data.pagination.total_pages);
    }
  }, [data]);

  const logs = data?.logs ?? [];
  const eventTypes = cachedEventTypes;
  const pagination = data?.pagination
    ? {
        page: data.pagination.page,
        per_page: data.pagination.per_page,
        total: data.pagination.total ?? cachedTotal ?? 0,
        total_pages: data.pagination.total_pages ?? cachedTotalPages ?? 1,
      }
    : undefined;

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Audit Logs</h3>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 items-end">
        <div>
          <label className="block text-xs text-surface-600 dark:text-surface-400 mb-1">Event Type</label>
          <select
            value={eventFilter}
            onChange={(e) => { setEventFilter(e.target.value); setPage(1); }}
            className={filterControlClassName}
          >
            <option value="">All Events</option>
            {eventTypes.map((e) => (
              <option key={e} value={e}>{e}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs text-surface-600 dark:text-surface-400 mb-1">From Date</label>
          <input
            type="date"
            value={fromDate}
            onChange={(e) => { setFromDate(e.target.value); setPage(1); }}
            className={filterControlClassName}
          />
        </div>
        <div>
          <label className="block text-xs text-surface-600 dark:text-surface-400 mb-1">To Date</label>
          <input
            type="date"
            value={toDate}
            onChange={(e) => { setToDate(e.target.value); setPage(1); }}
            className={filterControlClassName}
          />
        </div>
        {(eventFilter || fromDate || toDate) && (
          <button
            onClick={() => { setEventFilter(''); setFromDate(''); setToDate(''); setDebouncedFrom(''); setDebouncedTo(''); setPage(1); }}
            className="btn btn-ghost btn-xs !text-orange-600 hover:!text-orange-700 dark:!text-orange-400 dark:hover:!text-orange-300"
          >
            Clear filters
          </button>
        )}
        <div className="ml-auto flex items-end gap-2 pb-1">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="btn btn-ghost btn-xs !text-surface-600 hover:!text-surface-900 dark:!text-surface-300 dark:hover:!text-surface-100"
            aria-label="Refresh logs"
          >
            <RefreshCw className={cn('h-3.5 w-3.5', isFetching && 'animate-spin')} />
            Refresh
          </button>
          <label className="inline-flex items-center gap-1.5 text-xs text-surface-600 dark:text-surface-300 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={liveTail}
              onChange={(e) => setLiveTail(e.target.checked)}
              className="h-3.5 w-3.5"
            />
            Live
            {liveTail && <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" aria-hidden />}
          </label>
        </div>
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
          <div className="overflow-x-auto" style={{ overflowAnchor: 'none' }}>
            {/* WEB-FE-013 (Fixer-OOO 2026-04-25): added <caption> +
                scope="col" so screen readers can associate cell values
                with their column headers. WCAG 1.3.1. */}
            <table className="w-full text-sm">
              <caption className="sr-only">Audit log entries — system events with timestamp, actor, IP address, and detail payload.</caption>
              <thead>
                <tr className="border-b border-surface-200 text-left text-surface-500 dark:border-surface-700 dark:text-surface-400">
                  <th scope="col" className="py-2 px-3 font-medium">Time</th>
                  <th scope="col" className="py-2 px-3 font-medium">Event</th>
                  <th scope="col" className="py-2 px-3 font-medium">User</th>
                  <th scope="col" className="py-2 px-3 font-medium">IP</th>
                  <th scope="col" className="py-2 px-3 font-medium">Details</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((log) => (
                  <AuditLogRow key={log.id} log={log} />
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {pagination && pagination.total_pages > 1 && (
            <div className="flex items-center justify-between pt-2">
              <span className="text-xs text-surface-500 dark:text-surface-400">
                Showing {(pagination.page - 1) * pagination.per_page + 1}-{Math.min(pagination.page * pagination.per_page, pagination.total)} of {pagination.total}
              </span>
              <div className="flex gap-1">
                <button
                  aria-label="Previous page"
                  onClick={() => setPage(Math.max(1, page - 1))}
                  disabled={page <= 1}
                  className="btn-icon btn-xs min-h-[44px] min-w-[44px] md:min-h-[28px] md:min-w-[28px]"
                >
                  <ChevronLeft className="h-4 w-4 text-surface-500 dark:text-surface-300" />
                </button>
                <span className="px-2 py-1 text-xs text-surface-600 dark:text-surface-300">
                  Page {pagination.page} / {pagination.total_pages}
                </span>
                <button
                  aria-label="Next page"
                  onClick={() => setPage(Math.min(pagination.total_pages, page + 1))}
                  disabled={page >= pagination.total_pages}
                  className="btn-icon btn-xs min-h-[44px] min-w-[44px] md:min-h-[28px] md:min-w-[28px]"
                >
                  <ChevronRight className="h-4 w-4 text-surface-500 dark:text-surface-300" />
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
