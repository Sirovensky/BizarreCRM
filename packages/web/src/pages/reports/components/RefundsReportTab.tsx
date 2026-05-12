/**
 * RefundsReportTab — WEB-UIUX-1397.
 *
 * Reports → Refunds — per-refund breakdown sourced from `GET /refunds`.
 * The Dashboard KPI surfaces an aggregate `kpis.refunds`; the /refunds
 * approval queue surfaces pending rows. Neither answers "show me every
 * approved refund in the report window with customer + invoice + amount
 * + type + creator." This tab fills that gap.
 *
 * Read-only — approve / decline lives on /refunds. Status filter so the
 * report-author can switch between Approved (default; mirrors Dashboard
 * KPI), Pending, Declined, or All. Date filter inherits from the parent
 * report shell so the same from/to drives every tab consistently.
 */
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Receipt, ExternalLink, Loader2 } from 'lucide-react';
import { refundApi } from '@/api/endpoints';
import { formatCurrency, formatDate } from '@/utils/format';
import { cn } from '@/utils/cn';
import { SummaryCard, EmptyState } from './ReportHelpers';

type StatusFilter = 'approved' | 'pending' | 'declined' | 'all';

interface RefundRow {
  id: number;
  invoice_id: number | null;
  customer_id: number | null;
  amount: number;
  type: string;
  status: string;
  method: string | null;
  reason: string | null;
  created_at: string;
  first_name: string | null;
  last_name: string | null;
  invoice_order_id: string | null;
  created_first: string | null;
  created_last: string | null;
}

const STATUS_TABS: Array<{ value: StatusFilter; label: string }> = [
  { value: 'approved', label: 'Approved' },
  { value: 'pending', label: 'Pending' },
  { value: 'declined', label: 'Declined' },
  { value: 'all', label: 'All' },
];

const STATUS_BADGE: Record<string, string> = {
  pending: 'bg-amber-100 text-amber-800 dark:bg-amber-500/20 dark:text-amber-300',
  approved: 'bg-green-100 text-green-800 dark:bg-green-500/20 dark:text-green-300',
  declined: 'bg-red-100 text-red-800 dark:bg-red-500/20 dark:text-red-300',
  completed: 'bg-blue-100 text-blue-800 dark:bg-blue-500/20 dark:text-blue-300',
  cancelled: 'bg-surface-200 text-surface-700 dark:bg-surface-700 dark:text-surface-300',
};

export function RefundsReportTab({ from, to }: { from: string; to: string }) {
  const navigate = useNavigate();
  const [status, setStatus] = useState<StatusFilter>('approved');
  const [page, setPage] = useState(1);
  const PAGE_SIZE = 50;

  const { data, isLoading, isError } = useQuery({
    queryKey: ['reports', 'refunds', status, from, to, page],
    queryFn: async () => {
      const res = await refundApi.list({
        page,
        pagesize: PAGE_SIZE,
        from_date: from,
        to_date: to,
        ...(status === 'all' ? {} : { status }),
      });
      return res.data as {
        success: boolean;
        data: {
          refunds: RefundRow[];
          pagination: { total: number; total_pages: number };
        };
      };
    },
  });

  const refunds = data?.data?.refunds ?? [];
  const totalRows = data?.data?.pagination?.total ?? 0;
  const totalPages = data?.data?.pagination?.total_pages ?? 1;

  // Aggregates for the SummaryCard strip. These are page-local (server
  // pagination caps each fetch at PAGE_SIZE); the totals card therefore
  // says "this page" so operators don't mistake them for window totals.
  // For a true window total operators can fall back to the Dashboard KPI
  // or export the full list once a CSV endpoint exists.
  const pageAggregates = useMemo(() => {
    const sum = refunds.reduce((acc, r) => acc + (Number(r.amount) || 0), 0);
    const cashCount = refunds.filter((r) => (r.method ?? '').toLowerCase() === 'cash').length;
    const cardCount = refunds.filter((r) => (r.method ?? '').toLowerCase() === 'card').length;
    return { sum, cashCount, cardCount, count: refunds.length };
  }, [refunds]);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Refunds (page)"
          value={String(pageAggregates.count)}
          icon={Receipt}
          color="text-red-500"
          bg="bg-red-50 dark:bg-red-950"
          tooltip="Number of refund rows on the current page. Use the Dashboard KPI for the rolling window aggregate."
        />
        <SummaryCard
          label="Total amount (page)"
          value={formatCurrency(pageAggregates.sum)}
          icon={Receipt}
          color="text-amber-500"
          bg="bg-amber-50 dark:bg-amber-950"
          tooltip="Sum of refund amounts on the current page."
        />
        <SummaryCard
          label="Cash / Card split (page)"
          value={`${pageAggregates.cashCount} / ${pageAggregates.cardCount}`}
          icon={Receipt}
          color="text-blue-500"
          bg="bg-blue-50 dark:bg-blue-950"
          tooltip="Refunds on the current page broken out by tender. Store-credit refunds count under neither."
        />
      </div>

      <div className="card">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-surface-100 px-4 py-3 dark:border-surface-800">
          <div role="tablist" aria-label="Refund status filter" className="flex flex-wrap gap-1">
            {STATUS_TABS.map((t) => (
              <button
                key={t.value}
                type="button"
                role="tab"
                aria-selected={status === t.value}
                onClick={() => { setStatus(t.value); setPage(1); }}
                className={cn(
                  'rounded-md px-3 py-1.5 text-xs font-medium transition-colors',
                  status === t.value
                    ? 'bg-primary-100 text-primary-700 dark:bg-primary-500/20 dark:text-primary-300'
                    : 'text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-800',
                )}
              >
                {t.label}
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={() => navigate('/refunds')}
            className="inline-flex items-center gap-1 text-xs text-primary-600 hover:underline dark:text-primary-400"
          >
            Open approval queue <ExternalLink className="h-3 w-3" />
          </button>
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-16">
            <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
          </div>
        ) : isError ? (
          <div role="alert" className="m-4 rounded-md border border-red-200 bg-red-50 p-4 text-sm dark:border-red-500/30 dark:bg-red-500/10">
            <p className="font-medium text-red-700 dark:text-red-300">Failed to load refunds.</p>
          </div>
        ) : refunds.length === 0 ? (
          <EmptyState message={`No ${status === 'all' ? '' : status} refunds in this window.`} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-surface-50 text-xs font-semibold uppercase tracking-wider text-surface-500 dark:bg-surface-800/50 dark:text-surface-400">
                <tr>
                  <th scope="col" className="px-4 py-3 text-left">ID</th>
                  <th scope="col" className="px-4 py-3 text-left">Customer</th>
                  <th scope="col" className="px-4 py-3 text-left">Invoice</th>
                  <th scope="col" className="px-4 py-3 text-right">Amount</th>
                  <th scope="col" className="px-4 py-3 text-left">Type</th>
                  <th scope="col" className="px-4 py-3 text-left">Method</th>
                  <th scope="col" className="px-4 py-3 text-left">Status</th>
                  <th scope="col" className="px-4 py-3 text-left">Reason</th>
                  <th scope="col" className="px-4 py-3 text-left">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                {refunds.map((r) => (
                  <tr key={r.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50">
                    <td className="px-4 py-3 font-mono text-xs">#{r.id}</td>
                    <td className="px-4 py-3">
                      {r.customer_id ? (
                        <button
                          type="button"
                          onClick={() => navigate(`/customers/${r.customer_id}`)}
                          className="text-primary-600 hover:underline dark:text-primary-400"
                        >
                          {[r.first_name, r.last_name].filter(Boolean).join(' ') || `#${r.customer_id}`}
                        </button>
                      ) : (
                        <span className="text-surface-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {r.invoice_id ? (
                        <button
                          type="button"
                          onClick={() => navigate(`/invoices/${r.invoice_id}`)}
                          className="text-primary-600 hover:underline dark:text-primary-400"
                        >
                          {r.invoice_order_id ?? `#${r.invoice_id}`}
                        </button>
                      ) : (
                        <span className="text-surface-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-medium">{formatCurrency(r.amount)}</td>
                    <td className="px-4 py-3 capitalize">{(r.type ?? '').replace(/_/g, ' ')}</td>
                    <td className="px-4 py-3 capitalize">{r.method ?? <span className="text-surface-400">—</span>}</td>
                    <td className="px-4 py-3">
                      <span className={cn('inline-flex rounded-full px-2 py-0.5 text-xs font-medium', STATUS_BADGE[r.status] ?? 'bg-surface-100 text-surface-700')}>
                        {r.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 max-w-xs truncate" title={r.reason ?? ''}>
                      {r.reason ?? <span className="text-surface-400">—</span>}
                    </td>
                    <td className="px-4 py-3 text-xs text-surface-500">
                      {formatDate(r.created_at)}
                      {(r.created_first || r.created_last) && (
                        <div className="text-[10px]">by {[r.created_first, r.created_last].filter(Boolean).join(' ')}</div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {totalPages > 1 && (
          <div className="flex items-center justify-between border-t border-surface-100 px-4 py-3 text-sm dark:border-surface-800">
            <button
              type="button"
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="rounded-md border border-surface-200 px-3 py-1.5 disabled:opacity-50 dark:border-surface-700"
            >
              Previous
            </button>
            <span className="text-surface-500 dark:text-surface-400">
              Page {page} of {totalPages} · {totalRows} total
            </span>
            <button
              type="button"
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages}
              className="rounded-md border border-surface-200 px-3 py-1.5 disabled:opacity-50 dark:border-surface-700"
            >
              Next
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
