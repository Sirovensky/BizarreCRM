import { X, Check, Sparkles } from 'lucide-react';
import { usePlanStore } from '@/stores/planStore';
import { FEATURE_NAMES, PLAN_DEFINITIONS } from '@bizarre-crm/shared';
import { api } from '@/api/client';
import { useState, useEffect } from 'react';
import toast from 'react-hot-toast';

export function UpgradeModal() {
  const { upgradeModalOpen, upgradeModalFeature, closeUpgradeModal, plan } = usePlanStore();
  const [loading, setLoading] = useState(false);

  // Close on Escape key
  useEffect(() => {
    if (!upgradeModalOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeUpgradeModal();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [upgradeModalOpen, closeUpgradeModal]);

  if (!upgradeModalOpen) return null;

  const featureLabel =
    upgradeModalFeature === 'ticket_limit'
      ? 'Unlimited Tickets'
      : upgradeModalFeature && upgradeModalFeature in FEATURE_NAMES
        ? FEATURE_NAMES[upgradeModalFeature as keyof typeof FEATURE_NAMES]
        : 'Pro Features';

  const proPlan = PLAN_DEFINITIONS.pro;
  const proFeatures: Array<{ key: keyof typeof FEATURE_NAMES; label: string }> = [
    { key: 'advancedReports', label: FEATURE_NAMES.advancedReports },
    { key: 'scheduledReports', label: FEATURE_NAMES.scheduledReports },
    { key: 'customFields', label: FEATURE_NAMES.customFields },
    { key: 'memberships', label: FEATURE_NAMES.memberships },
    { key: 'automations', label: FEATURE_NAMES.automations },
    { key: 'apiKeys', label: FEATURE_NAMES.apiKeys },
    { key: 'customBranding', label: FEATURE_NAMES.customBranding },
    { key: 'automatedBackups', label: FEATURE_NAMES.automatedBackups },
    { key: 'exportReports', label: FEATURE_NAMES.exportReports },
  ];

  const handleUpgrade = async () => {
    setLoading(true);
    try {
      const res = await api.post('/billing/checkout');
      const url = res.data?.data?.url;
      // Validate the checkout URL before navigating — without the guard, a
      // poisoned or misrouted response delivering `javascript:…` would fire
      // script in the user's origin the moment we assigned `location.href`.
      let safeUrl: string | null = null;
      if (typeof url === 'string' && url.length > 0) {
        try {
          const parsed = new URL(url);
          if (parsed.protocol === 'https:' || parsed.protocol === 'http:') {
            safeUrl = parsed.href;
          }
        } catch { /* ignore — treated as invalid below */ }
      }
      if (safeUrl) {
        window.location.href = safeUrl;
        // Reset loading in case the navigation is blocked (popup blocker,
        // beforeunload handler) so the button doesn't stay disabled forever.
        setLoading(false);
      } else {
        toast.error('Unable to start checkout. Please contact support.');
        setLoading(false);
      }
    } catch (e: unknown) {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Failed to start checkout');
      setLoading(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 p-4"
      onClick={closeUpgradeModal}
    >
      <div
        className="relative w-full max-w-2xl overflow-hidden rounded-2xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <button
          onClick={closeUpgradeModal}
          className="absolute right-4 top-4 rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          aria-label="Close"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="bg-gradient-to-br from-primary-500 via-primary-600 to-primary-700 px-8 py-6 text-white">
          <div className="flex items-center gap-2">
            <Sparkles className="h-6 w-6" />
            <span className="text-sm font-semibold uppercase tracking-wider">Upgrade to Pro</span>
          </div>
          <h2 className="mt-2 text-2xl font-bold">Unlock {featureLabel}</h2>
          <p className="mt-1 text-sm text-white/90">
            Your current plan: <strong>{plan === 'free' ? 'Free' : 'Pro'}</strong>
          </p>
        </div>

        <div className="px-8 py-6">
          <div className="mb-4 flex items-baseline gap-2">
            <span className="text-4xl font-bold text-surface-900 dark:text-surface-100">
              ${(proPlan.priceCents / 100).toFixed(0)}
            </span>
            <span className="text-surface-500 dark:text-surface-400">/month</span>
          </div>

          <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
            Everything in Free, plus:
          </h3>
          <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {proFeatures.map((f) => (
              <li key={f.key} className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
                <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
                <span>{f.label}</span>
              </li>
            ))}
            <li className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
              <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
              <span>Unlimited tickets &amp; users</span>
            </li>
            <li className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
              <Check className="mt-0.5 h-4 w-4 flex-shrink-0 text-green-500" />
              <span>30 GB storage</span>
            </li>
          </ul>

          <div className="mt-6 flex gap-3">
            <button
              onClick={handleUpgrade}
              disabled={loading || plan === 'pro'}
              className="flex-1 rounded-lg bg-gradient-to-r from-primary-500 to-primary-700 px-4 py-3 text-sm font-semibold text-white shadow-lg transition-all hover:shadow-xl disabled:cursor-not-allowed disabled:opacity-50"
            >
              {loading ? 'Starting checkout…' : plan === 'pro' ? 'Already on Pro' : 'Upgrade to Pro'}
            </button>
            <button
              onClick={closeUpgradeModal}
              className="rounded-lg border border-surface-300 bg-white px-4 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              Maybe later
            </button>
          </div>

          <p className="mt-3 text-center text-xs text-surface-500 dark:text-surface-400">
            Cancel anytime. No long-term commitment.
          </p>
        </div>
      </div>
    </div>
  );
}
