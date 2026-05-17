/**
 * "My queue" tech dashboard — criticalaudit.md §53 idea #2.
 *
 * Shows tickets assigned to the logged-in user, sorted by due date, then age.
 * Each row has start/ready/complete actions that link to the existing ticket
 * detail page (the actual status mutation lives there). The endpoint
 * `GET /api/v1/team/my-queue` does the filtering server-side.
 */
import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Clock, AlertCircle, CheckCircle2, ArrowRight, ArrowUp, ArrowDown } from 'lucide-react';
import { api } from '@/api/client';
import { formatCurrency } from '@/utils/format';

interface QueueTicket {
  id: number;
  order_id: string;
  customer_id: number;
  status_id: number;
  status_name: string | null;
  is_closed: number | null;
  assigned_to: number | null;
  due_on: string | null;
  created_at: string;
  updated_at: string;
  total: number;
  first_name: string | null;
  last_name: string | null;
}

// SQLite timestamps come back as 'YYYY-MM-DD HH:MM:SS' (UTC, no suffix).
// V8 parses that string as LOCAL time, shifting the epoch by the browser's
// UTC offset. Normalize to ISO + 'Z' before parsing.
function parseSqliteTs(value: string): number {
  const normalized = value.includes('T') || value.endsWith('Z') || value.includes('+')
    ? value
    : `${value.replace(' ', 'T')}Z`;
  return new Date(normalized).getTime();
}

function ageBadge(createdAt: string): { label: string; color: string } {
  const ageMs = Date.now() - parseSqliteTs(createdAt);
  const days = Math.floor(ageMs / 86400000);
  if (days >= 14) return { label: `${days}d old`, color: 'bg-error-100 text-error-700 dark:bg-error-950/40 dark:text-error-200' };
  if (days >= 7)  return { label: `${days}d old`, color: 'bg-warning-100 text-warning-800 dark:bg-warning-950/40 dark:text-warning-200' };
  if (days >= 3)  return { label: `${days}d old`, color: 'bg-warning-50 text-warning-700 dark:bg-warning-950/30 dark:text-warning-300' };
  return { label: `${days}d old`, color: 'bg-surface-100 text-surface-700 dark:bg-surface-800 dark:text-surface-300' };
}

function dueBadge(dueOn: string | null): { label: string; color: string } | null {
  if (!dueOn) return null;
  const due = parseSqliteTs(dueOn);
  const now = Date.now();
  const diffDays = Math.floor((due - now) / 86400000);
  if (diffDays < 0)  return { label: `${Math.abs(diffDays)}d overdue`, color: 'bg-error-100 text-error-700 dark:bg-error-950/40 dark:text-error-200' };
  if (diffDays === 0) return { label: 'due today', color: 'bg-warning-100 text-warning-800 dark:bg-warning-950/40 dark:text-warning-200' };
  if (diffDays <= 2)  return { label: `due in ${diffDays}d`, color: 'bg-warning-50 text-warning-700 dark:bg-warning-950/30 dark:text-warning-300' };
  return { label: `due ${new Date(due).toLocaleDateString()}`, color: 'bg-surface-100 text-surface-700 dark:bg-surface-800 dark:text-surface-300' };
}

type SortKey = 'due_on' | 'created_at' | 'updated_at' | 'order_id' | 'total' | '';
type SortOrder = 'asc' | 'desc';

export function MyQueuePage() {
  // WEB-UIUX-543: server now accepts keyword + sort params so the page can
  // narrow/re-sort against the bounded 200-row response without rolling a
  // brittle client-only ordering that disagrees with the default. Empty
  // keyword + empty sort key reproduces the original "due first, NULLs
  // last, then oldest" contract.
  const [keyword, setKeyword] = useState('');
  const [debouncedKeyword, setDebouncedKeyword] = useState('');
  const [sortBy, setSortBy] = useState<SortKey>('');
  const [sortOrder, setSortOrder] = useState<SortOrder>('asc');
  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedKeyword(keyword.trim()), 300);
    return () => window.clearTimeout(t);
  }, [keyword]);

  // WEB-FO-010 (Fixer-426B 2026-04-26): opt back in to refetchOnWindowFocus
  // for this shared-workflow view. The global default is false (main.tsx)
  // to guard POS/form drafts, but the queue shows shared assignment state —
  // a tech returning from their email should see new handoffs immediately.
  const { data, isLoading, error } = useQuery({
    queryKey: ['team', 'my-queue', debouncedKeyword, sortBy, sortOrder],
    queryFn: async () => {
      const params: Record<string, string> = {};
      if (debouncedKeyword) params.keyword = debouncedKeyword;
      if (sortBy) {
        params.sort_by = sortBy;
        params.sort_order = sortOrder;
      }
      const res = await api.get<{ success: boolean; data: QueueTicket[] }>('/team/my-queue', { params });
      return res.data.data;
    },
    refetchInterval: 30_000,
    refetchOnWindowFocus: true,
  });

  const tickets: QueueTicket[] = data || [];

  function toggleSort(col: SortKey) {
    if (sortBy === col) {
      setSortOrder((o) => (o === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortBy(col);
      setSortOrder('asc');
    }
  }
  function sortIcon(col: SortKey) {
    if (sortBy !== col) return null;
    return sortOrder === 'asc' ? <ArrowUp className="w-3 h-3 inline ml-1" /> : <ArrowDown className="w-3 h-3 inline ml-1" />;
  }

  return (
    <div className="p-6 max-w-6xl mx-auto text-surface-900 dark:text-surface-100">
      <header className="mb-6">
        <h1 className="text-2xl font-bold text-surface-800 dark:text-surface-100">My Queue</h1>
        <p className="text-sm text-surface-500 dark:text-surface-400">
          Tickets assigned to you, sorted by due date and age. Updates every 30 seconds.
        </p>
        {/* WEB-UIUX-543: keyword filter (300ms debounce) hits the same
            server route so the bounded 200-row cap behaves like a true
            filter, not a client-side post-trim. */}
        <input
          type="search"
          value={keyword}
          onChange={(e) => setKeyword(e.target.value)}
          placeholder="Filter by order, first name, last name…"
          aria-label="Filter my queue"
          className="mt-3 w-full max-w-sm rounded-md border border-surface-300 bg-white px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
        />
      </header>

      {isLoading && (
        <div className="flex items-center justify-center py-12 text-surface-500 dark:text-surface-400">
          <Clock className="w-5 h-5 animate-spin mr-2" /> Loading queue...
        </div>
      )}

      {error && (
        <div className="bg-error-50 border border-error-200 text-error-700 rounded p-4 flex items-center dark:border-error-900 dark:bg-error-950/40 dark:text-error-200">
          <AlertCircle className="w-5 h-5 mr-2" />
          Failed to load your queue. Try refreshing.
        </div>
      )}

      {!isLoading && tickets.length === 0 && (
        <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-700 rounded-lg p-12 text-center">
          <CheckCircle2 className="w-12 h-12 text-success-500 dark:text-success-400 mx-auto mb-3" />
          <h2 className="text-lg font-semibold text-surface-800 dark:text-surface-100">All caught up</h2>
          <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
            You have no open tickets assigned to you right now.
          </p>
        </div>
      )}

      {tickets.length > 0 && (
        <div className="bg-white dark:bg-surface-900 rounded-lg shadow border border-surface-200 dark:border-surface-700 overflow-x-auto">
          <table className="w-full text-sm text-surface-700 dark:text-surface-200">
            <thead className="bg-surface-50 dark:bg-surface-800 text-surface-600 dark:text-surface-300 text-left text-xs uppercase">
              <tr>
                {/* WEB-UIUX-543: sortable Order / Age / Due / Total headers
                    — click toggles asc/desc, server orders the bounded 200
                    rows. Customer + Status stay un-sortable because the
                    server has no index on the customer name fields and
                    status sort would need to map status_id to display
                    order. */}
                <th className="px-4 py-3 cursor-pointer select-none" onClick={() => toggleSort('order_id')}>Order{sortIcon('order_id')}</th>
                <th className="px-4 py-3">Customer</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3 cursor-pointer select-none" onClick={() => toggleSort('created_at')}>Age{sortIcon('created_at')}</th>
                <th className="px-4 py-3 cursor-pointer select-none" onClick={() => toggleSort('due_on')}>Due{sortIcon('due_on')}</th>
                <th className="px-4 py-3 text-right cursor-pointer select-none" onClick={() => toggleSort('total')}>Total{sortIcon('total')}</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {tickets.map((t) => {
                const age = ageBadge(t.created_at);
                const due = dueBadge(t.due_on);
                return (
                  <tr key={t.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50">
                    <td className="px-4 py-3 font-mono text-xs text-primary-600 dark:text-primary-400">{t.order_id}</td>
                    <td className="px-4 py-3">
                      {t.first_name || ''} {t.last_name || ''}
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-block px-2 py-0.5 rounded-full text-xs bg-primary-50 text-primary-700 dark:bg-primary-950/30 dark:text-primary-300">
                        {t.status_name || '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${age.color}`}>
                        {age.label}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {due ? (
                        <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${due.color}`}>
                          {due.label}
                        </span>
                      ) : (
                        <span className="text-xs text-surface-400 dark:text-surface-500">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-surface-900 dark:text-surface-100">
                      {formatCurrency(Number(t.total || 0))}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <Link
                        to={`/tickets/${t.id}`}
                        className="inline-flex items-center text-primary-600 hover:text-primary-800 dark:text-primary-400 dark:hover:text-primary-300 text-xs font-semibold"
                      >
                        Open <ArrowRight className="w-3 h-3 ml-1" />
                      </Link>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
