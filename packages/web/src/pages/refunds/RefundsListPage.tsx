/**
 * RefundsListPage — WEB-UIUX-1018 / WEB-UIUX-1019 unblock.
 *
 * Paginated list of refunds with a status tab strip (Pending / Approved /
 * Declined / All). Admins with `refunds.approve` see inline Approve / Decline
 * buttons on each pending row. The server already implements the dual-control
 * flow (refunds.routes.ts: PATCH /:id/approve + PATCH /:id/decline with
 * requirePermission + atomic status flip + invoice decrement + commission
 * reversal + store-credit upsert); this page is the missing UI.
 */
import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { Check, X, Loader2, Receipt } from 'lucide-react';
import { refundApi } from '@/api/endpoints';
import { useHasPermission } from '@/hooks/useHasPermission';
import { formatCurrency, formatDate } from '@/utils/format';
import { cn } from '@/utils/cn';

type StatusTab = 'pending' | 'approved' | 'declined' | 'all';

interface RefundRow {
  id: number;
  invoice_id: number | null;
  customer_id: number | null;
  amount: number;
  type: string;
  status: string;
  reason: string | null;
  method: string | null;
  created_at: string;
  first_name: string | null;
  last_name: string | null;
  invoice_order_id: string | null;
  created_first: string | null;
  created_last: string | null;
}

const TABS: Array<{ value: StatusTab; label: string }> = [
  { value: 'pending', label: 'Pending' },
  { value: 'approved', label: 'Approved' },
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

export function RefundsListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const canApprove = useHasPermission('refunds.approve');
  // WEB-UIUX-1047: honor URL search params so drill-downs from Z-Report
  // (`/refunds?from=…&to=…&status=approved`) land on the right window.
  const initialStatus = (() => {
    const s = searchParams.get('status');
    return s === 'pending' || s === 'approved' || s === 'declined' || s === 'all'
      ? (s as StatusTab) : 'pending';
  })();
  const [tab, setTab] = useState<StatusTab>(initialStatus);
  const [page, setPage] = useState(1);
  const fromParam = searchParams.get('from');
  const toParam = searchParams.get('to');
  const PAGE_SIZE = 25;

  const { data, isLoading, isError } = useQuery({
    queryKey: ['refunds', tab, page, fromParam, toParam],
    queryFn: async () => {
      const res = await refundApi.list({
        page,
        pagesize: PAGE_SIZE,
        ...(tab === 'all' ? {} : { status: tab }),
        ...(fromParam ? { from_date: fromParam } : {}),
        ...(toParam ? { to_date: toParam } : {}),
      });
      return res.data as {
        success: boolean;
        data: { refunds: RefundRow[]; pagination: { total: number; total_pages: number } };
      };
    },
  });

  // Keep the URL in sync when the operator switches tabs so the drill-down
  // window stays sticky on reload but tab toggles still feel responsive.
  const handleTabChange = (next: StatusTab) => {
    setTab(next);
    setPage(1);
    const params = new URLSearchParams(searchParams);
    if (next === 'pending') params.delete('status');
    else params.set('status', next);
    setSearchParams(params, { replace: true });
  };

  // WEB-UIUX-712 / WEB-UIUX-703 follow-up: manager liability summary so an
  // admin opening the queue can instantly see outstanding store-credit
  // exposure. Hidden for non-admin users — the endpoint is admin-only too.
  const { data: liabilityData } = useQuery({
    queryKey: ['refunds', 'liability'],
    enabled: canApprove,
    queryFn: async () => {
      const res = await refundApi.getCreditsLiability();
      return res.data as { success: boolean; data: { total: number; credits: unknown[] } };
    },
  });

  const approveMut = useMutation({
    mutationFn: (id: number) => refundApi.approve(id),
    onSuccess: (res) => {
      toast.success('Refund approved');
      // WEB-UIUX-1402: surface server's commission_reversal_skipped flag so
      // the operator knows commissions stayed paid because the payroll
      // period is locked. Without this, the refund silently completes and
      // the tech keeps a commission they should have given back.
      const skipped = res.data?.data?.commission_reversal_skipped;
      const reversalErr = res.data?.data?.commission_reversal_error;
      if (skipped) {
        toast(
          'Commission reversal skipped — payroll period is locked. Reverse the commission manually once the period unlocks.',
          { duration: 8000, icon: '⚠️' },
        );
      } else if (reversalErr) {
        toast(
          `Commission reversal failed: ${reversalErr}. Reverse manually from Payroll.`,
          { duration: 8000, icon: '⚠️' },
        );
      }
      queryClient.invalidateQueries({ queryKey: ['refunds'] });
    },
    onError: (err: unknown) => {
      // WEB-UIUX-1401: distinguish 409 race / state-drift errors from 400
      // operator-fixable input so the manager gets actionable recovery
      // copy instead of a flat "Approval failed". 409 from refunds.routes
      // covers "exceeds available balance (concurrent refund conflict)"
      // and "no longer pending"; both resolve with a refetch.
      const e = err as { response?: { status?: number; data?: { message?: string } } };
      const status = e?.response?.status;
      const serverMsg = e?.response?.data?.message;
      if (status === 409) {
        toast.error(
          `${serverMsg ?? 'State changed since you opened this row.'} Refreshing list…`,
          { duration: 6000 },
        );
        queryClient.invalidateQueries({ queryKey: ['refunds'] });
        return;
      }
      toast.error(serverMsg ?? 'Approval failed');
    },
  });

  const declineMut = useMutation({
    mutationFn: (id: number) => refundApi.decline(id),
    onSuccess: () => {
      toast.success('Refund declined');
      queryClient.invalidateQueries({ queryKey: ['refunds'] });
    },
    onError: (err: unknown) => {
      // WEB-UIUX-1401: same 409 race branch as approveMut — server can
      // return "no longer pending" if another admin acted between page
      // load + click; refetch puts the operator on real state.
      const e = err as { response?: { status?: number; data?: { message?: string } } };
      const status = e?.response?.status;
      const serverMsg = e?.response?.data?.message;
      if (status === 409) {
        toast.error(
          `${serverMsg ?? 'State changed since you opened this row.'} Refreshing list…`,
          { duration: 6000 },
        );
        queryClient.invalidateQueries({ queryKey: ['refunds'] });
        return;
      }
      toast.error(serverMsg ?? 'Decline failed');
    },
  });

  const refunds = data?.data?.refunds ?? [];
  const totalPages = data?.data?.pagination?.total_pages ?? 1;

  return (
    <div className="mx-auto max-w-6xl space-y-4 px-4 py-6">
      <header className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold flex items-center gap-2">
            <Receipt className="h-6 w-6 text-primary-500" /> Refunds
          </h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Approval queue for refunds, credit notes, and store credits.
          </p>
        </div>
      </header>

      {/* WEB-UIUX-1047: drill-down window indicator. Visible when caller
          (typically Z-Report) passed `from`+`to` URL params; one-click clear
          puts the operator back on the unfiltered queue. */}
      {(fromParam || toParam) && (
        <div className="flex items-center justify-between rounded-md border border-primary-200 bg-primary-50 px-3 py-2 text-xs dark:border-primary-500/30 dark:bg-primary-500/10">
          <span className="text-primary-700 dark:text-primary-300">
            Filtered window: {fromParam ? new Date(fromParam).toLocaleString() : '…'} → {toParam ? new Date(toParam).toLocaleString() : '…'}
          </span>
          <button
            type="button"
            onClick={() => {
              const params = new URLSearchParams(searchParams);
              params.delete('from');
              params.delete('to');
              setSearchParams(params, { replace: true });
            }}
            className="rounded px-2 py-0.5 text-primary-700 hover:bg-primary-100 dark:text-primary-300 dark:hover:bg-primary-500/20"
          >
            Clear filter
          </button>
        </div>
      )}

      {/* Manager liability snapshot — admins only. Hidden when zero so it doesn't add noise on fresh tenants. */}
      {canApprove && liabilityData?.data?.total && liabilityData.data.total > 0 && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm dark:border-amber-500/30 dark:bg-amber-500/10">
          <p className="font-medium text-amber-800 dark:text-amber-200">
            Outstanding store-credit liability: {formatCurrency(liabilityData.data.total)}
          </p>
          <p className="text-xs text-amber-700/80 dark:text-amber-300/80">
            {liabilityData.data.credits.length} customer{liabilityData.data.credits.length === 1 ? '' : 's'} hold unredeemed credit. Surfaced from <code className="font-mono">GET /refunds/credits/liability</code>.
          </p>
        </div>
      )}

      <div role="tablist" aria-label="Refund status filter" className="flex flex-wrap gap-1 border-b border-surface-200 dark:border-surface-700">
        {TABS.map((t) => (
          <button
            key={t.value}
            role="tab"
            aria-selected={tab === t.value}
            onClick={() => handleTabChange(t.value)}
            className={cn(
              'px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
              tab === t.value
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
        </div>
      ) : isError ? (
        <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm dark:border-red-500/30 dark:bg-red-500/10">
          <p className="font-medium text-red-700 dark:text-red-300">Failed to load refunds.</p>
          <p className="mt-1 text-red-700/80 dark:text-red-300/80">Try reloading the page.</p>
        </div>
      ) : refunds.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-surface-400">
          <Receipt className="mb-3 h-10 w-10" />
          <p className="text-sm">No {tab === 'all' ? '' : tab} refunds</p>
        </div>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-surface-200 dark:border-surface-700">
          <table className="w-full text-sm">
            <thead className="bg-surface-50 text-xs font-semibold uppercase tracking-wider text-surface-500 dark:bg-surface-800/50 dark:text-surface-400">
              <tr>
                <th scope="col" className="px-4 py-3 text-left">ID</th>
                <th scope="col" className="px-4 py-3 text-left">Customer</th>
                <th scope="col" className="px-4 py-3 text-left">Invoice</th>
                <th scope="col" className="px-4 py-3 text-right">Amount</th>
                <th scope="col" className="px-4 py-3 text-left">Type</th>
                <th scope="col" className="px-4 py-3 text-left">Status</th>
                <th scope="col" className="px-4 py-3 text-left">Created</th>
                {canApprove && tab !== 'declined' && tab !== 'approved' && (
                  <th scope="col" className="px-4 py-3 text-right">Actions</th>
                )}
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
                  <td className="px-4 py-3 capitalize">{r.type?.replace(/_/g, ' ')}</td>
                  <td className="px-4 py-3">
                    <span className={cn('inline-flex rounded-full px-2 py-0.5 text-xs font-medium', STATUS_BADGE[r.status] ?? 'bg-surface-100 text-surface-700')}>
                      {r.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-xs text-surface-500">
                    {formatDate(r.created_at)}
                    {(r.created_first || r.created_last) && (
                      <div className="text-[10px]">by {[r.created_first, r.created_last].filter(Boolean).join(' ')}</div>
                    )}
                  </td>
                  {canApprove && tab !== 'declined' && tab !== 'approved' && (
                    <td className="px-4 py-3 text-right">
                      {r.status === 'pending' ? (
                        <div className="inline-flex gap-1">
                          <button
                            type="button"
                            disabled={approveMut.isPending}
                            onClick={() => {
                              if (window.confirm(`Approve refund #${r.id} for ${formatCurrency(r.amount)}?`)) {
                                approveMut.mutate(r.id);
                              }
                            }}
                            aria-label={`Approve refund ${r.id}`}
                            className="rounded p-1 text-green-600 hover:bg-green-50 disabled:opacity-50 dark:hover:bg-green-900/20"
                          >
                            <Check className="h-4 w-4" />
                          </button>
                          <button
                            type="button"
                            disabled={declineMut.isPending}
                            onClick={() => {
                              if (window.confirm(`Decline refund #${r.id}?`)) {
                                declineMut.mutate(r.id);
                              }
                            }}
                            aria-label={`Decline refund ${r.id}`}
                            className="rounded p-1 text-red-600 hover:bg-red-50 disabled:opacity-50 dark:hover:bg-red-900/20"
                          >
                            <X className="h-4 w-4" />
                          </button>
                        </div>
                      ) : (
                        <span className="text-xs text-surface-400">—</span>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {totalPages > 1 && (
        <div className="flex items-center justify-between text-sm">
          <button
            type="button"
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="rounded-md border border-surface-200 px-3 py-1.5 disabled:opacity-50 dark:border-surface-700"
          >
            Previous
          </button>
          <span className="text-surface-500 dark:text-surface-400">Page {page} of {totalPages}</span>
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
  );
}
