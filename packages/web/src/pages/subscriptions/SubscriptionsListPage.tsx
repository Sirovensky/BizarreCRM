import React, { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Crown, Loader2, AlertCircle, RefreshCw, Search, ChevronLeft, ChevronRight, PauseCircle, PlayCircle, XCircle, Link as LinkIcon, UserPlus, X as XIcon, Copy as CopyIcon } from 'lucide-react';
import toast from 'react-hot-toast';
import { customerApi, membershipApi } from '@/api/endpoints';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { MembershipSettings } from '@/pages/settings/MembershipSettings';
import { useHasRole } from '@/hooks/useHasRole';
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
type MembershipView = 'subscriptions' | 'tiers';

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
  // WEB-UIUX-902: canonical role gate via useHasRole.
  const isAdmin = useHasRole('admin');
  return isAdmin ? <>{children}</> : null;
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
  const [view, setView] = useState<MembershipView>('subscriptions');
  // WEB-UIUX-1075: inline enrolment modal — customer picker → tier picker → confirm.
  const [showEnrollModal, setShowEnrollModal] = useState(false);
  // WEB-UIUX-1500: opt-in surfacing of cancelled subs so admins can audit churn.
  const [showCancelled, setShowCancelled] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['subscriptions', { includeCancelled: showCancelled }],
    queryFn: async () => {
      const res = await membershipApi.getSubscriptions({ includeCancelled: showCancelled });
      return (res.data as { data: Subscription[] }).data;
    },
    staleTime: 30_000,
  });

  const cancelMutation = useMutation({
    // WEB-UIUX-827: pass `immediate` through so the operator can choose
    // immediate vs end-of-period cancellation. Server already supports both.
    // WEB-UIUX-1067: cancellation_reason + free-text note ride along so the
    // churn analytics column gets populated.
    mutationFn: (vars: { id: number; immediate: boolean; reason: string; note: string }) =>
      membershipApi.cancel(vars.id, { immediate: vars.immediate, reason: vars.reason, note: vars.note || undefined }),
    // WEB-UIUX-1070: also invalidate customer membership cache so CustomerDetailPage stays in sync
    onSuccess: (response, vars) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      const sub = (data ?? []).find((s) => s.id === vars.id);
      if (sub) {
        queryClient.invalidateQueries({ queryKey: ['membership', 'customer', sub.customer_id] });
        // WEB-UIUX-1499: invalidate the customer's store-credit cache so the
        // CustomerDetailPage credit balance reflects the prorated grant.
        queryClient.invalidateQueries({ queryKey: ['customer-credits', sub.customer_id] });
        queryClient.invalidateQueries({ queryKey: ['store-credit', sub.customer_id] });
      }
      // WEB-UIUX-1499: surface the prorated store-credit grant in the toast
      // so the operator can mention the amount to the customer at cancel time
      // ("$X.XX credited to your account for unused days").
      const proration = (response?.data as { data?: { proration_credit?: { amount: number } } })
        ?.data?.proration_credit;
      const credited = proration?.amount;
      if (vars.immediate && credited && credited > 0) {
        toast.success(
          `Subscription cancelled — ${formatCurrency(credited)} credited to customer's store credit for unused days`,
          { duration: 7000 },
        );
      } else {
        toast.success(vars.immediate ? 'Subscription cancelled immediately' : 'Subscription will cancel at period end');
      }
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
      // WEB-UIUX-834: surface a specific reason when the server (or
      // upstream processor) returns a structured error code. Maps the
      // BlockChyp / Stripe + native variants to operator-actionable copy.
      const code: string | undefined =
        err?.response?.data?.code ?? err?.response?.data?.error_code;
      const serverMsg: string | undefined = err?.response?.data?.message;
      let msg: string;
      switch (code) {
        case 'card_expired':
        case 'expired_card':
          msg = 'Card on file is expired. Ask the customer for a new card and update Payment Method.';
          break;
        case 'insufficient_funds':
          msg = 'Card declined: insufficient funds. Retry later or ask for a different card.';
          break;
        case 'invalid_token':
        case 'card_not_present':
          msg = 'Saved card token is no longer valid. Re-tokenize the card via Payment Method.';
          break;
        case 'terminal_offline':
        case 'processor_offline':
          msg = 'Payment terminal is offline. Check the terminal, retry, or take cash and record manually.';
          break;
        case 'card_declined':
          msg = serverMsg || 'Card declined. Ask the customer for a different card.';
          break;
        default:
          msg = serverMsg || 'Billing failed';
      }
      toast.error(msg);
      setBillingId(null);
    },
  });

  // WEB-UIUX-1065: pause/resume mutations
  const [pausingId, setPausingId] = useState<number | null>(null);
  const [resumingId, setResumingId] = useState<number | null>(null);
  // BUGHUNT-2026-05-16: replaced window.prompt chain with an inline modal so
  // iOS PWA / sandboxed-iframe staff can still cancel subscriptions.
  const [cancelModalSub, setCancelModalSub] = useState<Subscription | null>(null);
  const pauseMut = useMutation({
    // WEB-UIUX-1066: capture a free-form pause reason so the win-back report
    // can categorise paused-vs-cancelled cohorts. Server stores `pause_reason`.
    mutationFn: (vars: { id: number; reason: string | null }) =>
      membershipApi.pause(vars.id, vars.reason ? { reason: vars.reason } : undefined),
    // WEB-UIUX-1070: invalidate both query keys
    onSuccess: (_result, vars) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      const sub = (data ?? []).find((s) => s.id === vars.id);
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

  // WEB-UIUX-1074: send-payment-link mutation for subs without blockchyp_token.
  // Endpoint takes a {tier_id, customer_id} pair (no per-subscription hosted-
  // link route exists); row-level callers pass the source subscription so we
  // can pluck both, plus the sub id for in-flight UI state.
  const [paymentLinkId, setPaymentLinkId] = useState<number | null>(null);
  const paymentLinkMut = useMutation({
    mutationFn: (vars: { tier_id: number; customer_id: number; subscription_id?: number }) =>
      membershipApi.createPaymentLink({ tier_id: vars.tier_id, customer_id: vars.customer_id }),
    onSuccess: (res, _vars) => {
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

  // WEB-UIUX-1065 + WEB-UIUX-1066: pause handler — also prompts for a reason so
  // pause_reason gets populated (used by win-back analytics).
  async function handlePause(sub: Subscription): Promise<void> {
    try {
      const ok = await confirm(
        `Pause ${sub.first_name} ${sub.last_name}'s ${sub.tier_name} membership?`,
        { title: 'Pause subscription?', confirmLabel: 'Pause' },
      );
      if (!ok) return;
      // BUGHUNT-2026-05-16: window.prompt is suppressed in iOS PWA. The reason
      // here was always optional — pause without a reason and let the operator
      // edit it later from the detail page if needed.
      setPausingId(sub.id);
      pauseMut.mutate({ id: sub.id, reason: null });
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

  function handleCancel(sub: Subscription): void {
    // BUGHUNT-2026-05-16: open the inline cancel modal instead of a
    // window.prompt chain (suppressed in iOS PWA + a11y broken).
    setCancelModalSub(sub);
  }

  function submitCancel(vars: { immediate: boolean; reason: string; note: string }): void {
    const sub = cancelModalSub;
    if (!sub) return;
    setCancelModalSub(null);
    setCancellingId(sub.id);
    cancelMutation.mutate({ id: sub.id, ...vars });
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

  const viewButtonClass = (target: MembershipView) =>
    [
      'rounded-lg px-3 py-2 text-sm font-medium transition-colors',
      view === target
        ? 'bg-primary-500 text-on-primary'
        : 'text-surface-500 hover:bg-surface-100 hover:text-surface-900 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-100',
    ].join(' ');

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header — WEB-UIUX-1061: removed decoy "Run billing now" header button;
          billing runs nightly via cron. Per-row "Bill now" remains the manual trigger. */}
      <div className="flex flex-col gap-4 mb-6 sm:flex-row sm:items-center sm:justify-between">
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
        <div className="flex items-center gap-2">
          {/* WEB-UIUX-1075: inline Enroll-customer modal — customer picker →
              tier picker → submit. Free tiers create the subscription
              immediately via POST /membership/subscribe. Paid tiers route to
              POST /membership/payment-link (hosted card-capture URL) since
              the server requires a BlockChyp token on paid tiers and we
              don't yet have a card-on-file UI in this modal (UIUX-826). */}
          <AdminOnly>
            <button
              type="button"
              onClick={() => setShowEnrollModal(true)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-primary-500 bg-primary-500 px-3 py-2 text-sm font-medium text-on-primary transition-colors hover:bg-primary-400"
            >
              <UserPlus className="h-4 w-4" />
              Enroll customer
            </button>
          </AdminOnly>
        <div
          className="inline-flex w-fit rounded-xl border border-surface-200 bg-white p-1 dark:border-surface-800 dark:bg-surface-900"
          role="tablist"
          aria-label="Membership view"
        >
          <button
            type="button"
            role="tab"
            aria-selected={view === 'subscriptions'}
            onClick={() => setView('subscriptions')}
            className={viewButtonClass('subscriptions')}
          >
            Subscriptions
          </button>
          <AdminOnly>
            <button
              type="button"
              role="tab"
              aria-selected={view === 'tiers'}
              onClick={() => setView('tiers')}
              className={viewButtonClass('tiers')}
            >
              Tiers
            </button>
          </AdminOnly>
        </div>
        </div>
      </div>

      {view === 'tiers' ? (
        <MembershipSettings showActiveSubscribers={false} />
      ) : (
        <>
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
            {/* WEB-UIUX-1500: opt-in churn-history toggle. Server filter widens to include 'cancelled'. */}
            <label className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-700 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-200">
              <input
                type="checkbox"
                checked={showCancelled}
                onChange={(e) => setShowCancelled(e.target.checked)}
              />
              Show cancelled
            </label>
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
          {/* WEB-UIUX-1064: enrollment lives on customer profiles; tier setup
              stays inline on this page instead of detouring through Settings. */}
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
                className="rounded-lg bg-primary-500 px-3 py-2 text-sm font-semibold text-on-primary hover:bg-primary-400"
              >
                Go to Customers
              </Link>
              <AdminOnly>
                <button
                  type="button"
                  onClick={() => setView('tiers')}
                  className="rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800"
                >
                  Configure tiers
                </button>
              </AdminOnly>
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
                            onClick={() => { setPaymentLinkId(sub.id); paymentLinkMut.mutate({ tier_id: sub.tier_id, customer_id: sub.customer_id, subscription_id: sub.id }); }}
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
                          {/* WEB-UIUX-1495: explicit "Cancel membership" so a
                              cashier doesn't read it as "cancel dialog".
                              WEB-UIUX-1501: XCircle icon to match Pause icon. */}
                          <button
                            onClick={() => handleCancel(sub)}
                            disabled={cancellingId === sub.id}
                            className="flex items-center gap-1 text-red-500 hover:text-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none text-xs font-medium"
                            title="Cancel membership (terminal — see confirm)"
                          >
                            {cancellingId === sub.id
                              ? <Loader2 className="h-3 w-3 animate-spin" />
                              : <XCircle className="h-3 w-3" />}
                            Cancel membership
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
        </>
      )}

      {/* WEB-UIUX-1075: Enrolment modal. */}
      {showEnrollModal && (
        <EnrollSubscriptionModal
          onClose={() => setShowEnrollModal(false)}
          onSuccess={() => {
            setShowEnrollModal(false);
            queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
          }}
        />
      )}

      {/* BUGHUNT-2026-05-16: Cancel-subscription modal (replaces window.prompt chain). */}
      {cancelModalSub && (
        <CancelSubscriptionModal
          sub={cancelModalSub}
          onClose={() => setCancelModalSub(null)}
          onSubmit={submitCancel}
        />
      )}
    </div>
  );
}

interface CancelSubscriptionModalProps {
  sub: Subscription;
  onClose: () => void;
  onSubmit: (vars: { immediate: boolean; reason: string; note: string }) => void;
}

function CancelSubscriptionModal({ sub, onClose, onSubmit }: CancelSubscriptionModalProps): React.ReactElement {
  const [mode, setMode] = useState<'end' | 'now'>('end');
  const [reason, setReason] = useState<string>('low_value');
  const [note, setNote] = useState('');

  const chargeAmt = sub.last_charge_amount ?? sub.monthly_price;
  const chargeDate = sub.current_period_end ? formatDate(sub.current_period_end) : null;
  const immediate = mode === 'now';
  const impactLine = immediate
    ? `Customer loses ${sub.tier_name} benefits today.`
      + (chargeDate && chargeAmt != null ? ` Last charge ${chargeDate}, ${formatCurrency(chargeAmt)}.` : '')
      + ' No refund issued — see Refund flow if needed.'
    : `Customer keeps ${sub.tier_name} benefits until ${chargeDate ?? 'period end'}. No further charges.`;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" role="presentation" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="cancel-sub-title"
        className="w-full max-w-md rounded-lg bg-white p-5 shadow-xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 id="cancel-sub-title" className="mb-1 text-lg font-semibold text-surface-900 dark:text-surface-100">
          Cancel {sub.first_name} {sub.last_name}'s membership
        </h3>
        <p className="mb-4 text-xs text-surface-500 dark:text-surface-400">{sub.tier_name}</p>

        <fieldset className="mb-4">
          <legend className="mb-1 text-xs font-medium text-surface-700 dark:text-surface-300">When?</legend>
          <label className="flex cursor-pointer items-start gap-2 rounded-md border border-surface-200 px-3 py-2 dark:border-surface-700">
            <input type="radio" name="cancel-mode" value="end" checked={mode === 'end'} onChange={() => setMode('end')} />
            <span className="flex-1 text-sm">
              <span className="block font-medium">End of current period</span>
              <span className="text-xs text-surface-500">Customer keeps paid days.</span>
            </span>
          </label>
          <label className="mt-1 flex cursor-pointer items-start gap-2 rounded-md border border-surface-200 px-3 py-2 dark:border-surface-700">
            <input type="radio" name="cancel-mode" value="now" checked={mode === 'now'} onChange={() => setMode('now')} />
            <span className="flex-1 text-sm">
              <span className="block font-medium">Cancel immediately</span>
              <span className="text-xs text-surface-500">Customer forfeits remaining days.</span>
            </span>
          </label>
        </fieldset>

        <label className="mb-3 block text-xs font-medium text-surface-700 dark:text-surface-300">
          Reason (analytics + retention)
          <select
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="mt-1 w-full rounded-md border border-surface-300 px-2 py-1 text-sm dark:border-surface-600 dark:bg-surface-900"
          >
            <option value="">(skip)</option>
            <option value="too_expensive">Too expensive</option>
            <option value="missing_features">Missing features</option>
            <option value="switched_service">Switched to another service</option>
            <option value="low_value">Not getting enough value</option>
            <option value="customer_service">Customer service / experience</option>
            <option value="business_closed">Business closed / moved</option>
            <option value="no_longer_needed">No longer needed</option>
            <option value="other">Other</option>
          </select>
        </label>

        {reason === 'other' && (
          <label className="mb-3 block text-xs font-medium text-surface-700 dark:text-surface-300">
            Note (max 500 chars)
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value.slice(0, 500))}
              rows={3}
              className="mt-1 w-full rounded-md border border-surface-300 px-2 py-1 text-sm dark:border-surface-600 dark:bg-surface-900"
            />
          </label>
        )}

        <p className={`mb-4 rounded-md p-2 text-xs ${immediate ? 'bg-red-50 text-red-700 dark:bg-red-900/30 dark:text-red-300' : 'bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300'}`}>
          {impactLine}
        </p>

        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="rounded-md border border-surface-200 px-3 py-1.5 text-sm dark:border-surface-700">
            Back
          </button>
          <button
            type="button"
            onClick={() => onSubmit({ immediate, reason, note: reason === 'other' ? note : '' })}
            className={`rounded-md px-3 py-1.5 text-sm font-medium text-white ${immediate ? 'bg-red-600 hover:bg-red-700' : 'bg-amber-600 hover:bg-amber-700'}`}
          >
            {immediate ? 'Cancel now' : 'Cancel at period end'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Enrol-subscription modal (WEB-UIUX-1075) ────────────────────────────────

interface EnrollCustomerHit {
  id: number;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
}

interface EnrollTier {
  id: number;
  name: string;
  monthly_price: number;
  color?: string | null;
  discount_pct?: number | null;
  is_active?: number;
}

function EnrollSubscriptionModal({
  onClose,
  onSuccess,
}: {
  onClose: () => void;
  onSuccess: () => void;
}) {
  const dialogRef = useFocusTrap<HTMLDivElement>(true);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<EnrollCustomerHit[]>([]);
  const [searching, setSearching] = useState(false);
  const [selectedCustomer, setSelectedCustomer] = useState<EnrollCustomerHit | null>(null);
  const [selectedTierId, setSelectedTierId] = useState<number | null>(null);
  const [paymentLinkUrl, setPaymentLinkUrl] = useState<string | null>(null);

  // Esc closes — only when no link is on display (link state needs explicit
  // ack before dismissal so the URL isn't lost).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape' && !paymentLinkUrl) onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, paymentLinkUrl]);

  const { data: tiersRaw } = useQuery({
    queryKey: ['membership', 'tiers', 'enroll'],
    queryFn: async () => {
      const res = await membershipApi.getTiers();
      return (res.data as { data: EnrollTier[] }).data;
    },
    staleTime: 60_000,
  });
  const tiers: EnrollTier[] = (tiersRaw ?? []).filter((t) => t.is_active !== 0);

  // Debounced search — 2-char minimum, abort on retype.
  useEffect(() => {
    if (query.trim().length < 2) {
      setResults([]);
      return;
    }
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      setSearching(true);
      try {
        const res = await customerApi.search(query.trim(), controller.signal);
        const raw = (res.data as { data?: unknown })?.data;
        const list: EnrollCustomerHit[] = Array.isArray(raw)
          ? (raw as EnrollCustomerHit[])
          : Array.isArray((raw as { customers?: EnrollCustomerHit[] })?.customers)
            ? (raw as { customers: EnrollCustomerHit[] }).customers
            : [];
        setResults(list.slice(0, 25));
      } catch {
        // Aborted searches fire here too — silent failure is fine.
      } finally {
        setSearching(false);
      }
    }, 250);
    return () => {
      controller.abort();
      clearTimeout(timer);
    };
  }, [query]);

  const subscribeMut = useMutation({
    mutationFn: (vars: { customer_id: number; tier_id: number }) =>
      membershipApi.subscribe(vars),
    onSuccess: () => {
      toast.success('Subscription created');
      onSuccess();
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  const paymentLinkMut = useMutation({
    mutationFn: (vars: { customer_id: number; tier_id: number }) =>
      membershipApi.paymentLink(vars),
    onSuccess: (res) => {
      const url: string = (res.data as { url?: string; data?: { url?: string } })?.url
        ?? (res.data as { data?: { url?: string } })?.data?.url
        ?? '';
      if (!url) {
        toast.error('Server returned no payment link URL');
        return;
      }
      setPaymentLinkUrl(url);
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  const selectedTier = tiers.find((t) => t.id === selectedTierId) ?? null;
  const isPaidTier = selectedTier ? Number(selectedTier.monthly_price) > 0 : false;
  const submitting = subscribeMut.isPending || paymentLinkMut.isPending;

  function handleSubmit() {
    if (!selectedCustomer || !selectedTierId) return;
    const vars = { customer_id: selectedCustomer.id, tier_id: selectedTierId };
    // Free tiers create the sub directly. Paid tiers route through the
    // hosted payment-link endpoint so the customer enters card details
    // (server requires a BlockChyp token for paid tiers; we don't tokenize
    // in-modal — that ships with UIUX-826).
    if (isPaidTier) {
      paymentLinkMut.mutate(vars);
    } else {
      subscribeMut.mutate(vars);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={(e) => { if (e.target === e.currentTarget && !paymentLinkUrl) onClose(); }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="enroll-sub-title"
        className="w-full max-w-lg rounded-xl bg-white p-5 shadow-xl dark:bg-surface-900"
      >
        <div className="mb-3 flex items-center justify-between">
          <h2 id="enroll-sub-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
            Enroll customer in membership
          </h2>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="rounded p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          >
            <XIcon className="h-5 w-5" />
          </button>
        </div>

        {paymentLinkUrl ? (
          <div className="space-y-3">
            <p className="text-sm text-surface-700 dark:text-surface-300">
              Hosted payment link ready. Send to <strong>{selectedCustomer?.first_name} {selectedCustomer?.last_name}</strong>; the subscription activates once they enter card details and confirm.
            </p>
            <div className="flex items-center gap-2 rounded-md border border-surface-200 bg-surface-50 p-2 dark:border-surface-700 dark:bg-surface-800">
              <code className="flex-1 truncate text-xs text-surface-700 dark:text-surface-200">{paymentLinkUrl}</code>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard.writeText(paymentLinkUrl);
                  toast.success('Link copied');
                }}
                className="inline-flex items-center gap-1 rounded bg-primary-500 px-2 py-1 text-xs font-medium text-on-primary hover:bg-primary-400"
              >
                <CopyIcon className="h-3.5 w-3.5" /> Copy
              </button>
            </div>
            <div className="flex justify-end">
              <button
                type="button"
                onClick={onSuccess}
                className="rounded-lg border border-surface-300 px-3 py-2 text-sm hover:bg-surface-100 dark:border-surface-700 dark:hover:bg-surface-800"
              >
                Done
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            {/* Step 1: customer picker. */}
            <div>
              <label htmlFor="enroll-customer-search" className="block text-xs font-medium uppercase tracking-wide text-surface-500">
                Customer
              </label>
              {selectedCustomer ? (
                <div className="mt-1 flex items-center justify-between rounded-md border border-primary-200 bg-primary-50 px-3 py-2 dark:border-primary-500/30 dark:bg-primary-500/10">
                  <div className="text-sm">
                    <div className="font-medium text-surface-900 dark:text-surface-100">
                      {selectedCustomer.first_name} {selectedCustomer.last_name}
                    </div>
                    <div className="text-xs text-surface-500">
                      {selectedCustomer.email ?? selectedCustomer.phone ?? `#${selectedCustomer.id}`}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => { setSelectedCustomer(null); setQuery(''); }}
                    className="text-xs text-primary-600 hover:underline dark:text-primary-400"
                  >
                    Change
                  </button>
                </div>
              ) : (
                <div className="relative">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                  <input
                    id="enroll-customer-search"
                    type="search"
                    autoFocus
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder="Search name, email or phone"
                    className="mt-1 w-full rounded-md border border-surface-300 py-2 pl-9 pr-3 text-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-700 dark:bg-surface-800"
                  />
                  {searching && (
                    <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-surface-400" />
                  )}
                  {results.length > 0 && (
                    <ul
                      role="listbox"
                      className="mt-1 max-h-48 overflow-auto rounded-md border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-900"
                    >
                      {results.map((c) => (
                        <li key={c.id}>
                          <button
                            type="button"
                            role="option"
                            aria-selected={false}
                            onClick={() => { setSelectedCustomer(c); setResults([]); }}
                            className="block w-full px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-800"
                          >
                            <div className="font-medium">{c.first_name} {c.last_name}</div>
                            <div className="text-xs text-surface-500">{c.email ?? c.phone ?? `#${c.id}`}</div>
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              )}
            </div>

            {/* Step 2: tier picker. */}
            {selectedCustomer && (
              <div>
                <div className="block text-xs font-medium uppercase tracking-wide text-surface-500">Tier</div>
                {tiers.length === 0 ? (
                  <p className="mt-1 text-sm text-surface-500">No active tiers — create one in Settings → Memberships first.</p>
                ) : (
                  <div className="mt-1 grid grid-cols-1 gap-2 sm:grid-cols-2">
                    {tiers.map((t) => {
                      const isSelected = t.id === selectedTierId;
                      return (
                        <button
                          key={t.id}
                          type="button"
                          onClick={() => setSelectedTierId(t.id)}
                          className={`rounded-md border px-3 py-2 text-left text-sm transition ${
                            isSelected
                              ? 'border-primary-500 bg-primary-50 dark:bg-primary-500/10'
                              : 'border-surface-200 hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600'
                          }`}
                        >
                          <div className="font-medium text-surface-900 dark:text-surface-100">{t.name}</div>
                          <div className="text-xs text-surface-500">
                            {Number(t.monthly_price) > 0
                              ? `${formatCurrency(Number(t.monthly_price))}/mo`
                              : 'Free'}
                            {t.discount_pct ? ` · ${t.discount_pct}% off` : ''}
                          </div>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Submission hint for paid tiers. */}
            {selectedCustomer && selectedTier && isPaidTier && (
              <p className="rounded-md border border-amber-200 bg-amber-50 p-2 text-xs text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200">
                Paid tiers require a card on file. Submitting will generate a hosted payment link to send to the customer — the subscription activates after they enter card details. (Card-on-file capture inside this modal is tracked by WEB-UIUX-826.)
              </p>
            )}

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-surface-300 px-3 py-2 text-sm hover:bg-surface-100 dark:border-surface-700 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={!selectedCustomer || !selectedTierId || submitting}
                onClick={handleSubmit}
                className="inline-flex items-center gap-1.5 rounded-lg bg-primary-500 px-3 py-2 text-sm font-medium text-on-primary hover:bg-primary-400 disabled:opacity-50"
              >
                {submitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                {isPaidTier ? 'Generate payment link' : 'Enroll now'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
