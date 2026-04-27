import { Sparkles, ArrowRight, ArrowLeft, Check } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { usePlanStore } from '@/stores/planStore';

/**
 * Step 3 — Your Pro Trial (informational).
 *
 * Pure information display, no form. Explains that the new shop has 14 days
 * of Pro features before automatically dropping to Free. Reads the trial end
 * date from planStore (which is populated by the same /setup-status query
 * that drives the wizard gate, plus /account/me for plan + limits).
 *
 * This replaces the persistent "14 days remaining" banner from the header —
 * the info is shown once here, at the right moment, instead of nagging the
 * user on every page load for two weeks.
 */
export function StepTrialInfo({ onNext, onBack }: StepProps) {
  const { trialEndsAt, trialActive } = usePlanStore();

  // Trial end date formatted for display. If planStore hasn't loaded yet
  // (edge case), fall back to "in 14 days" copy.
  const endDateLabel = trialEndsAt
    ? new Date(trialEndsAt).toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' })
    : null;

  const benefits: Array<{ title: string; body: string }> = [
    { title: 'Unlimited tickets', body: 'Free is capped at 50 tickets/month. Pro is unlimited during your trial.' },
    { title: 'Advanced reports', body: 'Sales, labor, inventory, and tax breakdowns.' },
    { title: 'Automated SMS workflows', body: 'Auto-updates when ticket status changes, review requests, estimate follow-ups.' },
    { title: 'Customer portal', body: 'Customers can check repair status + view estimates from their phone.' },
    { title: 'Multi-user access', body: 'Add technicians, cashiers, and admins — each with their own login.' },
    { title: 'Full data export', body: 'CSV or JSON export of any module anytime.' },
  ];

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Sparkles className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          You have 14 days of Pro features — free
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          {endDateLabel
            ? <>All Pro features unlocked through <strong className="text-surface-700 dark:text-surface-200">{endDateLabel}</strong>. No credit card required.</>
            : <>All Pro features unlocked for your first 14 days. No credit card required.</>
          }
        </p>
      </div>

      <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {benefits.map((b) => (
            <div key={b.title} className="flex items-start gap-3 rounded-xl border border-surface-100 bg-surface-50/50 p-4 dark:border-surface-700/50 dark:bg-surface-700/20">
              <div className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-green-100 dark:bg-green-500/20">
                <Check className="h-4 w-4 text-green-600 dark:text-green-400" />
              </div>
              <div>
                <div className="text-sm font-semibold text-surface-900 dark:text-surface-100">
                  {b.title}
                </div>
                <div className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">
                  {b.body}
                </div>
              </div>
            </div>
          ))}
        </div>

        <div className="mt-6 rounded-lg bg-surface-50 p-4 text-xs text-surface-600 dark:bg-surface-700/30 dark:text-surface-400">
          <strong className="text-surface-800 dark:text-surface-200">What happens after 14 days?</strong>{' '}
          You'll automatically move to our Free plan (50 tickets/month, limited features). You can upgrade
          to Pro ($69/mo) any time from Settings &rarr; Billing, or stay on Free forever — no surprise charges.
        </div>

        {!trialActive && trialEndsAt && (
          <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300">
            Note: your trial status shows as inactive. This is unusual for a brand-new shop — if you created
            the shop just now, refresh the page in a moment. Otherwise, contact support.
          </div>
        )}

        <div className="mt-6 flex items-center justify-between">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-1 text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <button
            type="button"
            onClick={onNext}
            className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
          >
            Continue to setup
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
