import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { AlertTriangle, CheckCircle2, ClipboardCheck, Loader2, UserCheck } from 'lucide-react';
import { ticketApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatDateTime, formatTicketId } from '@/utils/format';

interface PendingQcRow {
  id: number;
  order_id: string;
  customer_id: number | null;
  status_id: number;
  assigned_to: number | null;
  total: number | null;
  created_at: string;
  updated_at: string;
  hours_pending: number;
  customer: { id: number | null; first_name: string | null; last_name: string | null };
  status: { id: number; name: string; color: string | null };
  assigned_user: { id: number; first_name: string | null; last_name: string | null } | null;
}

export function TicketPendingQcPage() {
  const [mineOnly, setMineOnly] = useState(true);
  const [stale24h, setStale24h] = useState(false);

  const { data = [], isLoading, isError, refetch } = useQuery({
    queryKey: ['tickets', 'pending-qc', mineOnly, stale24h],
    queryFn: async () => {
      const res = await ticketApi.pendingQc({
        ...(mineOnly ? { assigned_to: 'me' as const } : {}),
        ...(stale24h ? { min_hours: 24 } : {}),
      });
      return (res.data?.data ?? []) as PendingQcRow[];
    },
  });

  return (
    <div className="flex h-full flex-col">
      <div className="mb-4 flex shrink-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold text-surface-900 dark:text-surface-100 md:text-2xl">
            <ClipboardCheck className="h-6 w-6 text-primary-500" />
            Pending QC
          </h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Tickets parked in <span className="font-mono">Repaired - Pending QC</span> waiting for a sign-off.
          </p>
        </div>

        <div className="flex flex-wrap items-center justify-end gap-2">
          <div className="inline-flex rounded-lg border border-surface-200 dark:border-surface-700">
            <Link
              to="/tickets"
              className="rounded-l-lg px-3 py-2 text-sm font-medium text-surface-500 transition-colors hover:bg-surface-50 dark:hover:bg-surface-800"
              title="Show all tickets"
            >
              All Tickets
            </Link>
            <Link
              to="/tickets?assigned_to=me"
              className="inline-flex items-center gap-1 border-l border-surface-200 px-3 py-2 text-sm font-medium text-surface-500 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-800"
              title="Show tickets assigned to me"
            >
              <UserCheck className="h-4 w-4" />
              My Queue
            </Link>
            <span
              className="inline-flex items-center gap-1 rounded-r-lg border-l border-surface-200 bg-primary-50 px-3 py-2 text-sm font-medium text-primary-700 dark:border-surface-700 dark:bg-primary-950/30 dark:text-primary-300"
              aria-current="page"
            >
              <ClipboardCheck className="h-4 w-4" />
              Pending QC
            </span>
          </div>

          <label className="inline-flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
            <input
              type="checkbox"
              checked={mineOnly}
              onChange={(e) => setMineOnly(e.target.checked)}
              className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500 dark:border-surface-600"
            />
            Mine only
          </label>
          <label className="inline-flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
            <input
              type="checkbox"
              checked={stale24h}
              onChange={(e) => setStale24h(e.target.checked)}
              className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500 dark:border-surface-600"
            />
            Pending &gt; 24h
          </label>
        </div>
      </div>

      <div className="card relative flex min-h-0 flex-1 flex-col overflow-hidden !p-0">
        {isLoading && (
          <div className="flex items-center justify-center gap-2 py-16 text-sm text-surface-500 dark:text-surface-400">
            <Loader2 className="h-4 w-4 animate-spin" />
            Loading pending QC...
          </div>
        )}

        {isError && (
          <div className="m-4 flex flex-col gap-3 rounded-lg border border-error-200 bg-error-50 px-4 py-3 text-sm text-error-800 dark:border-error-900 dark:bg-error-950/40 dark:text-error-200 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-2">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <div>
                <p className="font-semibold">Could not load pending QC</p>
                <p className="text-xs text-error-700 dark:text-error-300">Try refreshing the list.</p>
              </div>
            </div>
            <button
              type="button"
              onClick={() => void refetch()}
              className="inline-flex items-center justify-center rounded-lg border border-error-300 bg-white px-3 py-1.5 text-xs font-semibold text-error-700 transition-colors hover:bg-error-100 dark:border-error-800 dark:bg-error-950 dark:text-error-200 dark:hover:bg-error-900"
            >
              Retry
            </button>
          </div>
        )}

        {!isLoading && !isError && data.length === 0 && (
          <div className="flex flex-col items-center justify-center py-20">
            <CheckCircle2 className="mb-4 h-16 w-16 text-success-500 dark:text-success-400" />
            <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">All caught up</h2>
            <p className="text-sm text-surface-400 dark:text-surface-500">
              {mineOnly ? 'No tickets waiting on your QC sign-off.' : 'No tickets currently pending QC.'}
            </p>
          </div>
        )}

        {!isLoading && !isError && data.length > 0 && (
          <div className="overflow-auto">
            <table className="w-full text-left text-[13px]">
              <thead className="sticky top-0 z-10 bg-white dark:bg-surface-900">
                <tr className="border-b border-surface-200 dark:border-surface-700">
                  <th className="px-3 py-2 text-xs font-medium text-surface-500 dark:text-surface-400">Ticket</th>
                  <th className="px-3 py-2 text-xs font-medium text-surface-500 dark:text-surface-400">Customer</th>
                  <th className="px-3 py-2 text-xs font-medium text-surface-500 dark:text-surface-400">Assigned To</th>
                  <th className="px-3 py-2 text-right text-xs font-medium text-surface-500 dark:text-surface-400">Pending</th>
                  <th className="px-3 py-2 text-xs font-medium text-surface-500 dark:text-surface-400">Updated</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                {data.map((ticket) => {
                  const customerName = [ticket.customer.first_name, ticket.customer.last_name].filter(Boolean).join(' ') || '--';
                  const assignedName = ticket.assigned_user
                    ? [ticket.assigned_user.first_name, ticket.assigned_user.last_name].filter(Boolean).join(' ')
                    : '--';
                  const overdue = ticket.hours_pending >= 24;

                  return (
                    <tr key={ticket.id} className="transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/50">
                      <td className="px-3 py-2 font-medium">
                        <Link to={`/tickets/${ticket.id}`} className="text-primary-600 transition-colors hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300">
                          {formatTicketId(ticket.order_id || ticket.id)}
                        </Link>
                      </td>
                      <td className="px-3 py-2 text-surface-700 dark:text-surface-200">{customerName}</td>
                      <td className="px-3 py-2 text-surface-600 dark:text-surface-300">{assignedName}</td>
                      <td
                        className={cn(
                          'px-3 py-2 text-right font-mono tabular-nums',
                          overdue ? 'font-semibold text-error-600 dark:text-error-400' : 'text-surface-600 dark:text-surface-300',
                        )}
                      >
                        {ticket.hours_pending}h
                      </td>
                      <td className="px-3 py-2 text-surface-500 dark:text-surface-400">{formatDateTime(ticket.updated_at)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
