/**
 * WEB-UIUX-1168: Z-Report history.
 *
 * Cashiers and admins frequently need to reprint a Z-report after the
 * close-shift modal was dismissed and the printed paper was lost. The
 * server already cached every closed shift's Z-report on close; this page
 * exposes a paginated list with a per-row "View Z-report" button that
 * reuses the existing `ZReportModal`.
 *
 * Admin / manager only — opening_float + variance leak shop-economic data.
 */
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Loader2, ScrollText, AlertTriangle } from 'lucide-react';
import { api } from '@/api/client';
import { formatCents, formatDateTime } from '@/utils/format';
import { ZReportModal } from '../unified-pos/ZReportModal';

interface ShiftHistoryRow {
  id: number;
  opened_at: string;
  closed_at: string;
  opening_float_cents: number;
  closing_counted_cents: number | null;
  expected_cents: number | null;
  variance_cents: number | null;
  opened_by_name: string | null;
  closed_by_name: string | null;
}

interface ShiftHistoryResponse {
  data: ShiftHistoryRow[];
  pagination: { page: number; per_page: number; total: number; total_pages: number };
}

const PER_PAGE = 25;

export function ShiftHistoryPage() {
  const [page, setPage] = useState(1);
  const [viewShiftId, setViewShiftId] = useState<number | null>(null);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['pos-enrich', 'drawer', 'history', page],
    queryFn: async () => {
      const res = await api.get<ShiftHistoryResponse>(
        `/pos-enrich/drawer/history?page=${page}&per_page=${PER_PAGE}`,
      );
      return res.data;
    },
  });

  const rows = data?.data ?? [];
  const pagination = data?.pagination;

  return (
    <div className="p-6">
      <div className="mb-6">
        <h1 className="flex items-center gap-2 text-2xl font-bold text-surface-900 dark:text-surface-100">
          <ScrollText className="h-6 w-6 text-primary-500" /> Shift history
        </h1>
        <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
          Reprint a Z-report for any closed cash-drawer shift.
        </p>
      </div>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-surface-500 dark:text-surface-400">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading shifts…
        </div>
      )}
      {isError && (
        <div className="flex items-center gap-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300">
          <AlertTriangle className="h-4 w-4" />
          Failed to load shift history.
          <button onClick={() => refetch()} className="ml-2 underline">Retry</button>
        </div>
      )}

      {!isLoading && !isError && rows.length === 0 && (
        <div className="rounded-xl border border-surface-200 bg-white p-8 text-center text-sm text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-500">
          No closed shifts yet.
        </div>
      )}

      {rows.length > 0 && (
        <div className="overflow-x-auto rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
          <table className="min-w-full text-sm">
            <thead className="border-b border-surface-200 bg-surface-50 text-xs uppercase tracking-wide text-surface-500 dark:border-surface-700 dark:bg-surface-900/40 dark:text-surface-400">
              <tr>
                <th className="px-4 py-2 text-left">Shift</th>
                <th className="px-4 py-2 text-left">Opened</th>
                <th className="px-4 py-2 text-left">Closed</th>
                <th className="px-4 py-2 text-right">Opening float</th>
                <th className="px-4 py-2 text-right">Counted</th>
                <th className="px-4 py-2 text-right">Variance</th>
                <th className="px-4 py-2 text-right">Z-report</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
              {rows.map((row) => {
                const variance = row.variance_cents ?? 0;
                const varianceColor = variance === 0
                  ? 'text-surface-500 dark:text-surface-400'
                  : variance > 0
                    ? 'text-emerald-600 dark:text-emerald-400'
                    : 'text-red-600 dark:text-red-400';
                return (
                  <tr key={row.id} className="hover:bg-surface-50 dark:hover:bg-surface-700/40">
                    <td className="px-4 py-2 font-mono">#{row.id}</td>
                    <td className="px-4 py-2">
                      <div>{formatDateTime(row.opened_at)}</div>
                      {row.opened_by_name && (
                        <div className="text-xs text-surface-400 dark:text-surface-500">by {row.opened_by_name}</div>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      <div>{formatDateTime(row.closed_at)}</div>
                      {row.closed_by_name && (
                        <div className="text-xs text-surface-400 dark:text-surface-500">by {row.closed_by_name}</div>
                      )}
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums">{formatCents(row.opening_float_cents)}</td>
                    <td className="px-4 py-2 text-right tabular-nums">
                      {row.closing_counted_cents != null ? formatCents(row.closing_counted_cents) : '—'}
                    </td>
                    <td className={`px-4 py-2 text-right tabular-nums ${varianceColor}`}>
                      {row.variance_cents != null ? formatCents(row.variance_cents) : '—'}
                    </td>
                    <td className="px-4 py-2 text-right">
                      <button
                        onClick={() => setViewShiftId(row.id)}
                        className="rounded-md border border-primary-200 px-3 py-1 text-xs font-medium text-primary-700 hover:bg-primary-50 dark:border-primary-700 dark:text-primary-300 dark:hover:bg-primary-900/30"
                      >
                        View Z-report
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {pagination && pagination.total_pages > 1 && (
        <div className="mt-4 flex items-center justify-between text-sm">
          <span className="text-surface-500 dark:text-surface-400">
            Page {pagination.page} of {pagination.total_pages} · {pagination.total} shifts
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1 || isLoading}
              className="rounded-md border border-surface-200 px-3 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-50 disabled:opacity-50 disabled:cursor-not-allowed dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              Previous
            </button>
            <button
              type="button"
              onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
              disabled={page >= pagination.total_pages || isLoading}
              className="rounded-md border border-surface-200 px-3 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-50 disabled:opacity-50 disabled:cursor-not-allowed dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              Next
            </button>
          </div>
        </div>
      )}

      {viewShiftId != null && (
        <ZReportModal shiftId={viewShiftId} onClose={() => setViewShiftId(null)} />
      )}
    </div>
  );
}
