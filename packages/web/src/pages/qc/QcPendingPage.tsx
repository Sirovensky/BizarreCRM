/**
 * WEB-UIUX-1088: Tickets pending QC sign-off worklist.
 *
 * Tickets parked in `Repaired - Pending QC` without a passing
 * `qc_sign_offs` row. Tech sees own backlog (assigned_to=me filter);
 * manager sees the whole queue + an aging-filter chip ("> 24h pending").
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { ClipboardCheck, Loader2, AlertTriangle } from 'lucide-react';
import { api } from '@/api/client';
import { useAuthStore } from '@/stores/authStore';
import { formatDateTime } from '@/utils/format';

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

interface PendingQcResponse {
  success: boolean;
  data: PendingQcRow[];
}

export function QcPendingPage() {
  const user = useAuthStore((s) => s.user);
  const [mineOnly, setMineOnly] = useState(true);
  const [stale24h, setStale24h] = useState(false);

  const params = new URLSearchParams();
  if (mineOnly && user?.id) params.set('assigned_to', String(user.id));
  if (stale24h) params.set('min_hours', '24');

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['tickets', 'pending-qc', mineOnly ? user?.id : null, stale24h],
    queryFn: async () => {
      const res = await api.get<PendingQcResponse>(`/tickets/pending-qc?${params.toString()}`);
      return res.data.data;
    },
  });

  return (
    <div className="p-6">
      <div className="mb-6 flex items-center justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-surface-900 dark:text-surface-100">
            <ClipboardCheck className="h-6 w-6 text-primary-500" /> Pending QC
          </h1>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
            Tickets parked in <span className="font-mono">Repaired - Pending QC</span> waiting for a sign-off.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <label className="inline-flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
            <input
              type="checkbox"
              checked={mineOnly}
              onChange={(e) => setMineOnly(e.target.checked)}
              className="h-4 w-4 rounded border-surface-300 dark:border-surface-600"
            />
            Mine only
          </label>
          <label className="inline-flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
            <input
              type="checkbox"
              checked={stale24h}
              onChange={(e) => setStale24h(e.target.checked)}
              className="h-4 w-4 rounded border-surface-300 dark:border-surface-600"
            />
            Pending &gt; 24h
          </label>
        </div>
      </div>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-surface-500 dark:text-surface-400">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading…
        </div>
      )}
      {isError && (
        <div className="flex items-center gap-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300">
          <AlertTriangle className="h-4 w-4" />
          Failed to load pending QC list.
          <button onClick={() => refetch()} className="ml-2 underline">Retry</button>
        </div>
      )}

      {!isLoading && !isError && (data?.length ?? 0) === 0 && (
        <div className="rounded-xl border border-surface-200 bg-white p-8 text-center text-sm text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-500">
          {mineOnly ? 'No tickets waiting on your QC sign-off.' : 'No tickets currently pending QC.'}
        </div>
      )}

      {(data?.length ?? 0) > 0 && (
        <div className="overflow-x-auto rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
          <table className="min-w-full text-sm">
            <thead className="border-b border-surface-200 bg-surface-50 text-xs uppercase tracking-wide text-surface-500 dark:border-surface-700 dark:bg-surface-900/40 dark:text-surface-400">
              <tr>
                <th className="px-4 py-2 text-left">Ticket</th>
                <th className="px-4 py-2 text-left">Customer</th>
                <th className="px-4 py-2 text-left">Assigned to</th>
                <th className="px-4 py-2 text-right">Pending</th>
                <th className="px-4 py-2 text-left">Updated</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
              {(data ?? []).map((t) => {
                const customer = [t.customer.first_name, t.customer.last_name].filter(Boolean).join(' ') || '—';
                const assigned = t.assigned_user
                  ? [t.assigned_user.first_name, t.assigned_user.last_name].filter(Boolean).join(' ')
                  : '—';
                const overdue = t.hours_pending >= 24;
                return (
                  <tr key={t.id} className="hover:bg-surface-50 dark:hover:bg-surface-700/40">
                    <td className="px-4 py-2 font-mono">
                      <Link to={`/tickets/${t.id}`} className="text-primary-600 dark:text-primary-400 hover:underline">
                        {t.order_id}
                      </Link>
                    </td>
                    <td className="px-4 py-2">{customer}</td>
                    <td className="px-4 py-2">{assigned}</td>
                    <td className={`px-4 py-2 text-right tabular-nums ${overdue ? 'text-red-600 dark:text-red-400 font-semibold' : 'text-surface-600 dark:text-surface-300'}`}>
                      {t.hours_pending}h
                    </td>
                    <td className="px-4 py-2 text-surface-500 dark:text-surface-400">{formatDateTime(t.updated_at)}</td>
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
