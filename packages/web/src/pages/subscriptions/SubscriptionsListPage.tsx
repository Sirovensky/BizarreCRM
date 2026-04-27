import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Crown, Loader2, AlertCircle, PlayCircle, RefreshCw } from 'lucide-react';
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

// @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): dropped local `formatCurrency`
// — was hardcoded `$` + `toFixed(2)`, ignoring tenant currency/locale. Now
// delegates to canonical `@/utils/format` so EUR/GBP/CAD tenants render correctly.

function statusBadge(status: SubStatus): string {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300';
    case 'past_due': return 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300';
    case 'paused': return 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300';
    case 'cancelled': return 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400';
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

// ─── Run Billing Button (admin-only, dev/admin convenience) ──────────────────

function RunBillingButton() {
  const user = useAuthStore((s) => s.user);
  // Only show to admins — mirrors how other admin-only controls are gated
  if (user?.role !== 'admin') return null;

  return (
    <button
      onClick={() => toast('Billing cron runs nightly automatically. Use server console to trigger manually.', { icon: 'ℹ️' })}
      className="flex items-center gap-2 px-3 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
      title="Run billing cron (admin only)"
    >
      <PlayCircle className="h-4 w-4" />
      Run billing now
    </button>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export function SubscriptionsListPage() {
  const queryClient = useQueryClient();
  const [cancellingId, setCancellingId] = useState<number | null>(null);

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
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      toast.success('Subscription cancelled');
      setCancellingId(null);
    },
    onError: () => {
      toast.error('Failed to cancel subscription');
      setCancellingId(null);
    },
  });

  // WEB-W3-020: per-row run-billing mutation
  const [billingId, setBillingId] = useState<number | null>(null);
  const runBillingMut = useMutation({
    mutationFn: (id: number) => membershipApi.runBilling(id),
    onSuccess: (_data, id) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      toast.success('Billing completed successfully');
      setBillingId(null);
    },
    onError: (err: any, _id) => {
      toast.error(err?.response?.data?.message || 'Billing failed');
      setBillingId(null);
    },
  });

  async function handleRunBilling(sub: Subscription): Promise<void> {
    try {
      const ok = await confirm(
        `Charge ${sub.first_name} ${sub.last_name}'s card for ${formatCurrency(sub.monthly_price ?? 0)}/mo now?`,
        { title: 'Run billing?', confirmLabel: 'Charge card' },
      );
      if (!ok) return;
      setBillingId(sub.id);
      runBillingMut.mutate(sub.id);
    } catch (err) {
      toast.error(formatApiError(err));
    }
  }

  async function handleCancel(sub: Subscription): Promise<void> {
    // WEB-FM-020 — Fixer-C28: try/catch around confirm-modal teardown rejection
    try {
      const ok = await confirm(
        `Cancel ${sub.first_name} ${sub.last_name}'s ${sub.tier_name} membership immediately?`,
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

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Crown className="h-6 w-6 text-primary-600" />
          <div>
            <h1 className="text-xl font-semibold text-surface-900 dark:text-surface-100">Memberships</h1>
            {!isLoading && !isError && (
              <p className="text-sm text-surface-500 dark:text-surface-400">
                {activeCount} active subscription{activeCount !== 1 ? 's' : ''}
              </p>
            )}
          </div>
        </div>
        <RunBillingButton />
      </div>

      {/* Content */}
      {isLoading ? (
        <TableSkeleton />
      ) : isError ? (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
          <p className="text-sm text-surface-500">Failed to load subscriptions</p>
        </div>
      ) : subs.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <Crown className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-4" />
          <p className="text-base font-medium text-surface-600 dark:text-surface-400">No active subscriptions</p>
          <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
            Enroll customers from the Memberships settings tab.
          </p>
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
              {subs.map((sub) => (
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
                      {sub.status === 'active' && sub.blockchyp_token && (
                        <AdminOnly>
                          <button
                            onClick={() => handleRunBilling(sub)}
                            disabled={billingId === sub.id}
                            className="flex items-center gap-1 text-primary-600 hover:text-primary-800 disabled:opacity-50 text-xs font-medium"
                            title="Charge card now"
                          >
                            {billingId === sub.id
                              ? <Loader2 className="h-3 w-3 animate-spin" />
                              : <RefreshCw className="h-3 w-3" />}
                            Bill now
                          </button>
                        </AdminOnly>
                      )}
                      {sub.status !== 'cancelled' && (
                        <button
                          onClick={() => handleCancel(sub)}
                          disabled={cancellingId === sub.id}
                          className="flex items-center gap-1 text-red-500 hover:text-red-700 disabled:opacity-50 text-xs font-medium"
                        >
                          {cancellingId === sub.id && <Loader2 className="h-3 w-3 animate-spin" />}
                          Cancel
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
