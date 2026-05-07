import React, { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Crown, Loader2, AlertCircle, RefreshCw, Search, ChevronLeft, ChevronRight, PauseCircle, PlayCircle, Link as LinkIcon } from 'lucide-react';
import toast from 'react-hot-toast';
import { membershipApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { confirm } from '@/stores/confirmStore';
import { formatCurrency, formatDate } from '@/utils/format';
import { formatApiError } from '@/utils/apiError';

// ─── Types ────────────────────────────────────────────────────────────────────

type SubStatus = 'active' | 'past_due' | 'paused' | 'cancelled';

interface Subscription {
  id: number;
  customer_id: number;
  tier_id: number;
  status: SubStatus;
  current_period_end: string | null;
  last_charge_amount: number | null;
  cancel_at_period_end: number;
  pause_reason: string | null;
  created_at: string;
  // Joined fields
  tier_name: string;
  monthly_price: number;
  color: string;
  first_name: string;
  last_name: string;
  email: string | null;
  phone: string | null;
  blockchyp_token?: string | null;
}

type StatusFilter = 'all' | Exclude<SubStatus, 'cancelled'>;

const PAGE_SIZE = 10;
const STATUS_FILTER_OPTIONS: Array<{ value: StatusFilter; label: string }> = [
  { value: 'all', label: 'All statuses' },
  { value: 'active', label: 'Active' },
  { value: 'past_due', label: 'Past due' },
  { value: 'paused', label: 'Paused' },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

// @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): dropped local `formatCurrency`
// — was hardcoded `$` + `toFixed(2)`, ignoring tenant currency/locale. Now
// delegates to canonical `@/utils/format` so EUR/GBP/CAD tenants render correctly.

function statusBadge(status: SubStatus): string {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300';
    case 'past_due': return 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300';
    case 'paused': return 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300';
    case 'cancelled': return 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-400';
  }
}

function statusLabel(status: SubStatus): string {
  switch (status) {
    case 'active': return 'Active';
    case 'past_due': return 'Past due';
    case 'paused': return 'Paused';
    case 'cancelled': return 'Cancelled';
  }
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

function TableSkeleton() {
  return (
    <div className="animate-pulse space-y-3">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="h-14 bg-surface-100 dark:bg-surface-800 rounded-lg" />
      ))}
    </div>
  );
}

// ─── AdminOnly wrapper ────────────────────────────────────────────────────────

function AdminOnly({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user);
  return user?.role === 'admin' ? <>{children}</> : null;
}

// WEB-UIUX-1061: RunBillingButton (header) was a decoy — it showed a toast
// instead of actually triggering billing. Removed entirely; the per-row
// "Bill now" button (admin-only) remains the manual trigger. Billing otherwise
// runs nightly via cron — a caption near the page title now says so.

// ─── Page ─────────────────────────────────────────────────────────────────────

export function SubscriptionsListPage() {
  const queryClient = useQueryClient();
  const [cancellingId, setCancellingId] = useState<number | null>(null);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [page, setPage] = useState(1);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['subscriptions'],
    queryFn: async () => {
      const res = await membershipApi.getSubscriptions();
      return (res.data as { data: Subscription[] }).data;
    },
    staleTime: 30_000,
  });

  const cancelMutation = useMutation({
    mutationFn: (id: number) => membershipApi.cancel(id, { immediate: true }),
    // WEB-UIUX-1070: also invalidate customer membership cache so CustomerDetailPage stays in sync
    onSuccess: (_data, id) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      const sub = (data ?? []).find((s) => s.id === id);
      if (sub) queryClient.invalidateQueries({ queryKey: ['membership', 'customer', sub.customer_id] });
      toast.success('Subscription cancelled');
      setCancellingId(null);
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
      setCancellingId(null);
    },
  });

  // WEB-W3-020: per-row run-billing mutation
  const [billingId, setBillingId] = useState<number | null>(null);
  const runBillingMut = useMutation({
    mutationFn: (id: number) => membershipApi.runBilling(id, { force: true }),
    // WEB-UIUX-1070: also invalidate customer membership cache; WEB-UIUX-1076: drop unused _data param
    onSuccess: (_result, id) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      const sub = (data ?? []).find((s) => s.id === id);
      if (sub) queryClient.invalidateQueries({ queryKey: ['membership', 'customer', sub.customer_id] });
      toast.success('Billing completed successfully');
      setBillingId(null);
    },
    onError: (err: any) => {
      toast.error(err?.response?.data?.message || 'Billing failed');
      setBillingId(null);
    },
  });

  // WEB-UIUX-1065: pause/resume mutations
  const [pausingId, setPausingId] = useState<number | null>(null);
  const [resumingId, setResumingId] = useState<number | null>(null);
  const pauseMut = useMutation({
    mutationFn: (id: number) => membershipApi.pause(id),
    // WEB-UIUX-1070: invalidate both query keys
    onSuccess: (_result, id) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      const sub = (data ?? []).find((s) => s.id === id);
      if (sub) queryClient.invalidateQueries({ queryKey: ['membership', 'customer', sub.customer_id] });
      toast.success('Subscription paused');
      setPausingId(null);
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
      setPausingId(null);
    },
  });
  const resumeMut = useMutation({
    mutationFn: (id: number) => membershipApi.resume(id),
    // WEB-UIUX-1070: invalidate both query keys
    onSuccess: (_result, id) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      const sub = (data ?? []).find((s) => s.id === id);
      if (sub) queryClient.invalidateQueries({ queryKey: ['membership', 'customer', sub.customer_id] });
      toast.success('Subscription resumed');
      setResumingId(null);
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
      setResumingId(null);
    },
  });

  // WEB-UIUX-1074: send-payment-link mutation for subs without blockchyp_token
  const [paymentLinkId, setPaymentLinkId] = useState<number | null>(null);
  const paymentLinkMut = useMutation({
    mutationFn: (id: number) => membershipApi.createPaymentLink(id),
    onSuccess: (res, id) => {
      const url: string = (res.data as any)?.url ?? '';
      toast(
        (t) => (
          <span>
            Payment link ready.{' '}
            <button
              className="underline font-medium"
              onClick={() => { navigator.clipboard.writeText(url); toast.dismiss(t.id); }}
            >
              Copy
            </button>
          </span>
        ),
        { duration: 8000 },
      );
      setPaymentLinkId(null);
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
      setPaymentLinkId(null);
    },
  });

  async function handleRunBilling(sub: Subscription): Promise<void> {
    try {
      const ok = await confirm(
        `Charge ${sub.first_name} ${sub.last_name}'s card for ${formatCurrency(sub.monthly_price ?? 0)} now? This will bill immediately even if the current period has not ended.`,
        { title: 'Run billing?', confirmLabel: 'Charge card' },
      );
      if (!ok) return;
      setBillingId(sub.id);
      runBillingMut.mutate(sub.id);
    } catch (err) {
      toast.error(formatApiError(err));
    }
  }

  // WEB-UIUX-1065: pause handler
  async function handlePause(sub: Subscription): Promise<void> {
    try {
      const ok = await confirm(
        `Pause ${sub.first_name} ${sub.last_name}'s ${sub.tier_name} membership?`,
        { title: 'Pause subscription?', confirmLabel: 'Pause' },
      );
      if (!ok) return;
      setPausingId(sub.id);
      pauseMut.mutate(sub.id);
    } catch (err) {
      toast.error(formatApiError(err));
    }
  }

  // WEB-UIUX-1065: resume handler
  async function handleResume(sub: Subscription): Promise<void> {
    try {
      const ok = await confirm(
        `Resume ${sub.first_name} ${sub.last_name}'s ${sub.tier_name} membership?`,
        { title: 'Resume subscription?', confirmLabel: 'Resume' },
      );
      if (!ok) return;
      setResumingId(sub.id);
      resumeMut.mutate(sub.id);
    } catch (err) {
      toast.error(formatApiError(err));
    }
  }

  async function handleCancel(sub: Subscription): Promise<void> {
    // WEB-FM-020 — Fixer-C28: try/catch around confirm-modal teardown rejection
    try {
      // WEB-UIUX-1498: surface cancellation impact so staff know what the customer loses
      const chargeAmt = sub.last_charge_amount ?? sub.monthly_price;
      const chargeDate = sub.current_period_end ? formatDate(sub.current_period_end) : null;
      const impactLine = `Customer loses ${sub.tier_name} discount + benefits today.`
        + (chargeDate && chargeAmt != null ? ` Last charge ${chargeDate}, ${formatCurrency(chargeAmt)}.` : '')
        + ' No refund issued — see Refund flow if needed.';
      const ok = await confirm(
        `Cancel ${sub.first_name} ${sub.last_name}'s ${sub.tier_name} membership?\n\n${impactLine}`,
        { title: 'Cancel subscription?', confirmLabel: 'Cancel subscription', danger: true },
      );
      if (!ok) return;
      setCancellingId(sub.id);
      cancelMutation.mutate(sub.id);
    } catch (err) {
      toast.error(formatApiError(err));
    }
  }

  const subs = data ?? [];
  const activeCount = subs.filter((s) => s.status === 'active').length;
  const filteredSubs = useMemo(() => {
    const term = search.trim().toLowerCase();
    return subs.filter((sub) => {
      if (statusFilter !== 'all' && sub.status !== statusFilter) return false;
      if (!term) return true;

      return [
        sub.first_name,
        sub.last_name,
        sub.email,
        sub.phone,
        sub.tier_name,
        statusLabel(sub.status),
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(term);
    });
  }, [search, statusFilter, subs]);
  const filtersActive = search.trim().length > 0 || statusFilter !== 'all';
  const totalPages = Math.max(1, Math.ceil(filteredSubs.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const pagedSubs = useMemo(() => {
    const start = (currentPage - 1) * PAGE_SIZE;
    return filteredSubs.slice(start, start + PAGE_SIZE);
  }, [currentPage, filteredSubs]);
  const pageStart = filteredSubs.length === 0 ? 0 : (currentPage - 1) * PAGE_SIZE + 1;
  const pageEnd = Math.min(filteredSubs.length, currentPage * PAGE_SIZE);

  useEffect(() => {
    setPage(1);
  }, [search, statusFilter]);

  useEffect(() => {
    setPage((current) => Math.min(current, totalPages));
  }, [totalPages]);

  function clearFilters() {
    setSearch('');
    setStatusFilter('all');
    setPage(1);
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header — WEB-UIUX-1061: removed decoy "Run billing now" header button;
          billing runs nightly via cron. Per-row "Bill now" remains the manual trigger. */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Crown className="h-6 w-6 text-primary-600" />
          <div>
            <h1 className="text-xl font-semibold text-surface-900 dark:text-surface-100">Memberships</h1>
            {!isLoading && !isError && (
              <p className="text-sm text-surface-500 dark:text-surface-400">
                {activeCount} active subscription{activeCount !== 1 ? 's' : ''}{' '}
                <span className="text-surface-400 dark:text-surface-500">&middot; Billing runs nightly automatically</span>
              </p>
            )}
          </div>
        </div>
      </div>

      {!isLoading && !isError && (subs.length > 0 || filtersActive) ? (
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="relative w-full sm:max-w-md">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search customer, email, phone, plan"
              aria-label="Search memberships"
              className="w-full rounded-lg border border-surface-200 bg-white py-2 pl-9 pr-3 text-sm text-surface-900 placeholder:text-surface-400 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
            />
          </div>

          <div className="flex items-center gap-2">
            <label htmlFor="subscription-status-filter" className="sr-only">
              Filter memberships by status
            </label>
            <select
              id="subscription-status-filter"
              value={statusFilter}
              onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}
              className="rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-700 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-200"
            >
              {STATUS_FILTER_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      ) : null}

      {/* Content */}
      {isLoading ? (
        <TableSkeleton />
      ) : isError ? (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
          <p className="text-sm text-surface-500">Failed to load subscriptions</p>
        </div>
      ) : filteredSubs.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <Crown className="h-12 w-12 text-surface-400 dark:text-surface-600 mb-4" />
          <p className="text-base font-medium text-surface-600 dark:text-surface-400">
            {filtersActive ? 'No subscriptions match' : 'No active subscriptions'}
          </p>
          <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
            {filtersActive
              ? 'Try a different search or status.'
              : 'Open a customer profile and tap Enroll in Membership'}
          </p>
          {/* WEB-UIUX-1064: old copy pointed to settings tab; enrollment lives on
              customer profile. Added /customers CTA + secondary settings link. */}
          {filtersActive ? (
            <button
              type="button"
              onClick={clearFilters}
              className="mt-4 rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800"
            >
              Clear filters
            </button>
          ) : (
            <div className="mt-4 flex items-center gap-3">
              <Link
                to="/customers"
                className="rounded-lg bg-primary-600 px-3 py-2 text-sm font-medium text-white hover:bg-primary-700"
              >
                Go to Customers
              </Link>
              <Link
                to="/settings/memberships"
                className="rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800"
              >
                Configure tiers
              </Link>
            </div>
          )}
        </div>
      ) : (
        <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Customer</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Plan</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Status</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Next billing</th>
                <th className="text-right px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Amount</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {pagedSubs.map((sub) => (
                <tr key={sub.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/40">
                  <td className="px-4 py-3">
                    <p className="font-medium text-surface-900 dark:text-surface-100">
                      {sub.first_name} {sub.last_name}
                    </p>
                    {sub.email && (
                      <p className="text-xs text-surface-400 truncate max-w-[180px]">{sub.email}</p>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <span className="inline-flex items-center gap-1.5">
                      <span
                        className="inline-block w-2.5 h-2.5 rounded-full flex-shrink-0"
                        style={{ backgroundColor: sub.color }}
                      />
                      <span className="text-surface-700 dark:text-surface-300">{sub.tier_name}</span>
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge(sub.status)}`}>
                      {statusLabel(sub.status)}
                    </span>
                    {/* WEB-W3-030: show cancel date alongside the badge */}
                    {sub.cancel_at_period_end === 1 && (
                      <span className="ml-1.5 text-xs text-amber-500">
                        Cancels {sub.current_period_end ? formatDate(sub.current_period_end) : 'at period end'}
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-surface-500 dark:text-surface-400">
                    {sub.current_period_end ? formatDate(sub.current_period_end) : '—'}
                  </td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">
                    {sub.monthly_price != null ? `${formatCurrency(sub.monthly_price)}/mo` : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      {/* WEB-W3-020: per-row Bill now button — admin only, active subs with token */}
                      {(sub.status === 'active' || sub.status === 'past_due') && sub.blockchyp_token && (
                        <AdminOnly>
                          <button
                            onClick={() => handleRunBilling(sub)}
                            disabled={billingId === sub.id}
                            className="flex items-center gap-1 text-primary-600 hover:text-primary-800 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none text-xs font-medium"
                            title="Charge card now"
                          >
                            {billingId === sub.id
                              ? <Loader2 className="h-3 w-3 animate-spin" />
                              : <RefreshCw className="h-3 w-3" />}
                            Bill now
                          </button>
                        </AdminOnly>
                      )}
                      {/* WEB-UIUX-1074: subs without a token get a "Send payment link" button instead */}
                      {(sub.status === 'active' || sub.status === 'past_due') && !sub.blockchyp_token && (
                        <AdminOnly>
                          <button
                            onClick={() => { setPaymentLinkId(sub.id); paymentLinkMut.mutate(sub.id); }}
                            disabled={paymentLinkId === sub.id}
                            className="flex items-center gap-1 text-surface-500 hover:text-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none text-xs font-medium"
                            title="Send payment link"
                          >
                            {paymentLinkId === sub.id
                              ? <Loader2 className="h-3 w-3 animate-spin" />
                              : <LinkIcon className="h-3 w-3" />}
                            Send payment link
                          </button>
                        </AdminOnly>
                      )}
                      {/* WEB-UIUX-1065: Pause button for active subs, Resume for paused subs */}
                      {sub.status === 'active' && (
                        <AdminOnly>
                          <button
                            onClick={() => handlePause(sub)}
                            disabled={pausingId === sub.id}
                            className="flex items-center gap-1 text-blue-500 hover:text-blue-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none text-xs font-medium"
                            title="Pause membership"
                          >
                            {pausingId === sub.id
                              ? <Loader2 className="h-3 w-3 animate-spin" />
                              : <PauseCircle className="h-3 w-3" />}
                            Pause
                          </button>
                        </AdminOnly>
                      )}
                      {sub.status === 'paused' && (
                        <AdminOnly>
                          <button
                            onClick={() => handleResume(sub)}
                            disabled={resumingId === sub.id}
                            className="flex items-center gap-1 text-green-600 hover:text-green-800 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none text-xs font-medium"
                            title="Resume membership"
                          >
                            {resumingId === sub.id
                              ? <Loader2 className="h-3 w-3 animate-spin" />
                              : <PlayCircle className="h-3 w-3" />}
                            Resume
                          </button>
                        </AdminOnly>
                      )}
                      {/* WEB-UIUX-1062: Cancel was visible to non-admin clerks causing 403s;
                          now gated with AdminOnly to match "Bill now" treatment. */}
                      {sub.status !== 'cancelled' && (
                        <AdminOnly>
                          <button
                            onClick={() => handleCancel(sub)}
                            disabled={cancellingId === sub.id}
                            className="flex items-center gap-1 text-red-500 hover:text-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none text-xs font-medium"
                          >
                            {cancellingId === sub.id && <Loader2 className="h-3 w-3 animate-spin" />}
                            Cancel
                          </button>
                        </AdminOnly>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="flex flex-col gap-3 border-t border-surface-100 px-4 py-3 text-sm text-surface-500 dark:border-surface-800 dark:text-surface-400 sm:flex-row sm:items-center sm:justify-between">
            <p>
              Showing {pageStart}-{pageEnd} of {filteredSubs.length}
            </p>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setPage((current) => Math.max(1, current - 1))}
                disabled={currentPage <= 1}
                className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800"
              >
                <ChevronLeft className="h-4 w-4" />
                Previous
              </button>
              <span className="min-w-[6.5rem] text-center">
                Page {currentPage} of {totalPages}
              </span>
              <button
                type="button"
                onClick={() => setPage((current) => Math.min(totalPages, current + 1))}
                disabled={currentPage >= totalPages}
                className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800"
              >
                Next
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
