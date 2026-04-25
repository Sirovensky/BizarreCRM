import { useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Sparkles, Check, ExternalLink, Loader2, Crown } from 'lucide-react';
import toast from 'react-hot-toast';
import { usePlanStore } from '@/stores/planStore';
import { api } from '@/api/client';
import { PLAN_DEFINITIONS, FEATURE_NAMES } from '@bizarre-crm/shared';
import { useState } from 'react';
import { formatDate } from '@/utils/format';

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function BillingTab() {
  const location = useLocation();
  const navigate = useNavigate();
  const { plan, planName, priceCents, trialActive, trialEndsAt, usage, fetchPlan, hasFetched } = usePlanStore();
  const [checkoutLoading, setCheckoutLoading] = useState(false);
  const [portalLoading, setPortalLoading] = useState(false);

  // Detect ?upgraded=1 query param after Stripe redirect — refresh plan immediately
  useEffect(() => {
    const params = new URLSearchParams(location.search);
    if (params.get('upgraded') === '1') {
      toast.success('Upgrade successful! Your account is now on the Pro plan.');
      fetchPlan();
      // Strip query params from URL
      navigate('/settings/billing', { replace: true });
    } else if (params.get('cancelled') === '1') {
      toast('Upgrade cancelled. You can try again any time.');
      navigate('/settings/billing', { replace: true });
    }
  }, [location.search, navigate, fetchPlan]);

  // Refresh plan info on mount
  useEffect(() => {
    fetchPlan();
  }, [fetchPlan]);

  const handleUpgrade = async () => {
    setCheckoutLoading(true);
    try {
      const res = await api.post('/billing/checkout');
      const url = res.data?.data?.url;
      if (url) {
        window.location.href = url;
      } else {
        toast.error('Unable to start checkout. Please contact support.');
        setCheckoutLoading(false);
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Failed to start checkout');
      setCheckoutLoading(false);
    }
  };

  const handleManageBilling = async () => {
    setPortalLoading(true);
    try {
      const res = await api.get('/billing/portal');
      const url = res.data?.data?.url;
      if (url) {
        window.location.href = url;
      } else {
        toast.error('Unable to open billing portal.');
        setPortalLoading(false);
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Failed to open billing portal');
      setPortalLoading(false);
    }
  };

  if (!hasFetched) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-6 w-6 animate-spin text-surface-400" />
      </div>
    );
  }

  const isPro = plan === 'pro';
  const proDef = PLAN_DEFINITIONS.pro;
  const freeDef = PLAN_DEFINITIONS.free;

  return (
    <div className="space-y-6">
      {/* Current Plan Card */}
      <div className="card p-6">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              {isPro && <Crown className="h-5 w-5 text-amber-500" />}
              <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
                Current Plan: {planName}
              </h2>
            </div>
            {trialActive && (
              <p className="mt-1 text-sm text-primary-600 dark:text-primary-400">
                Pro Trial — ends {formatDate(trialEndsAt)}
              </p>
            )}
            {!trialActive && isPro && (
              <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
                ${(priceCents / 100).toFixed(0)}/month
              </p>
            )}
            {!trialActive && !isPro && (
              <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
                Free forever
              </p>
            )}
          </div>
          <div className="flex gap-2">
            {!isPro && (
              <button
                onClick={handleUpgrade}
                disabled={checkoutLoading}
                className="rounded-lg bg-gradient-to-r from-primary-500 to-primary-700 px-4 py-2 text-sm font-semibold text-white shadow transition-all hover:shadow-lg disabled:opacity-50"
              >
                {checkoutLoading ? 'Loading…' : 'Upgrade to Pro'}
              </button>
            )}
            {isPro && !trialActive && (
              <button
                onClick={handleManageBilling}
                disabled={portalLoading}
                className="inline-flex items-center gap-1.5 rounded-lg border border-surface-300 bg-white px-4 py-2 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 disabled:opacity-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
              >
                {portalLoading ? 'Loading…' : (<>Manage Billing <ExternalLink className="h-3.5 w-3.5" /></>)}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Usage Card */}
      {usage && (
        <div className="card p-6">
          <h3 className="mb-4 text-sm font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
            This Month's Usage
          </h3>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <UsageMeter
              label="Tickets Created"
              current={usage.tickets_created}
              limit={usage.tickets_limit}
            />
            <UsageMeter
              label="Active Users"
              current={usage.active_users}
              limit={usage.users_limit}
            />
            <UsageMeter
              label="Storage Used"
              current={usage.storage_bytes}
              limit={usage.storage_limit_mb != null ? usage.storage_limit_mb * 1024 * 1024 : null}
              format="bytes"
            />
          </div>
        </div>
      )}

      {/* Plan Comparison (only show for free users) */}
      {!isPro && (
        <div className="card p-6">
          <div className="mb-4 flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-primary-500" />
            <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
              What you get with Pro
            </h3>
          </div>
          <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {Object.entries(FEATURE_NAMES).map(([key, label]) => (
              <li key={key} className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
                <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
                <span>{label}</span>
              </li>
            ))}
            <li className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
              <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
              <span>Unlimited tickets &amp; users</span>
            </li>
            <li className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
              <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
              <span>{proDef.limits.storageLimitMb! / 1024} GB storage (vs {freeDef.limits.storageLimitMb} MB)</span>
            </li>
          </ul>
          <button
            onClick={handleUpgrade}
            disabled={checkoutLoading}
            className="mt-6 w-full rounded-lg bg-gradient-to-r from-primary-500 to-primary-700 px-4 py-3 text-sm font-semibold text-white shadow-lg transition-all hover:shadow-xl disabled:opacity-50"
          >
            {checkoutLoading ? 'Starting checkout…' : `Upgrade to Pro — $${(proDef.priceCents / 100).toFixed(0)}/mo`}
          </button>
        </div>
      )}
    </div>
  );
}

interface UsageMeterProps {
  label: string;
  current: number;
  limit: number | null;
  format?: 'count' | 'bytes';
}

function UsageMeter({ label, current, limit, format = 'count' }: UsageMeterProps) {
  const percent = limit != null && limit > 0 ? Math.min(100, (current / limit) * 100) : 0;
  const isOver = limit != null && current >= limit;
  const isNear = !isOver && percent >= 80;

  const fmt = (n: number) => format === 'bytes' ? formatBytes(n) : n.toLocaleString();

  return (
    <div>
      <div className="mb-1.5 flex items-baseline justify-between">
        <span className="text-xs font-medium text-surface-500 dark:text-surface-400">{label}</span>
        <span className={`text-xs font-semibold ${isOver ? 'text-red-600' : isNear ? 'text-amber-600' : 'text-surface-700 dark:text-surface-300'}`}>
          {fmt(current)}{limit != null ? ` / ${fmt(limit)}` : ' (unlimited)'}
        </span>
      </div>
      {limit != null && (
        <div className="h-1.5 w-full rounded-full bg-surface-200 dark:bg-surface-700">
          <div
            className={`h-full rounded-full transition-all ${isOver ? 'bg-red-500' : isNear ? 'bg-amber-500' : 'bg-primary-500'}`}
            style={{ width: `${percent}%` }}
          />
        </div>
      )}
    </div>
  );
}
