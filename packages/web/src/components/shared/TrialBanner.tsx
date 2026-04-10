import { Sparkles, AlertTriangle } from 'lucide-react';
import { usePlanStore } from '@/stores/planStore';

/** Returns days remaining until trial ends. Negative for expired, 0 for ending today,
 *  positive for active. Null if no trial set. */
function daysRemaining(trialEndsAt: string | null): number | null {
  if (!trialEndsAt) return null;
  const end = new Date(trialEndsAt).getTime();
  if (Number.isNaN(end)) return null;
  const diffMs = end - Date.now();
  // Use floor for expired (negative) and ceil for active (positive) so:
  // -  expired returns negative
  // -  exactly at end returns 0 (today)
  // -  > 0 ms returns 1+ for active days
  if (diffMs <= 0) return Math.floor(diffMs / (24 * 60 * 60 * 1000));
  return Math.ceil(diffMs / (24 * 60 * 60 * 1000));
}

export function TrialBanner() {
  const { trialActive, trialEndsAt, plan, openUpgradeModal } = usePlanStore();

  // Don't show banner if user is Pro and not on trial
  if (plan === 'pro' && !trialActive) return null;

  const days = daysRemaining(trialEndsAt);

  // Trial expired (trial_ends_at exists but is in the past)
  // We rely on trialActive=false + days<=0 because the backend sets the effective plan
  // back to 'free' once the trial expires.
  if (trialEndsAt && !trialActive && days !== null && days <= 0) {
    return (
      <div className="relative z-0 flex items-center justify-center gap-2 bg-red-600 px-4 py-2 text-sm text-white">
        <AlertTriangle className="h-4 w-4 flex-shrink-0" />
        <span>Your Pro trial has ended. You're now on the Free plan with limited features.</span>
        <button
          onClick={() => openUpgradeModal('advancedReports')}
          className="ml-2 rounded bg-white/20 px-3 py-1 text-xs font-semibold transition-colors hover:bg-white/30"
        >
          Upgrade to Pro
        </button>
      </div>
    );
  }

  // Active trial — show banner based on days remaining
  if (!trialActive || days === null || days <= 0) return null;

  if (days > 3) {
    // Subtle info banner for active trial with plenty of time
    return (
      <div className="relative z-0 flex items-center justify-center gap-2 bg-indigo-600 px-4 py-1.5 text-xs text-white">
        <Sparkles className="h-3.5 w-3.5" />
        <span>
          You're on a Pro trial — {days} days remaining
        </span>
      </div>
    );
  }

  if (days > 1) {
    // Warning: 2-3 days left
    return (
      <div className="relative z-0 flex items-center justify-center gap-2 bg-yellow-500 px-4 py-2 text-sm font-semibold text-white">
        <AlertTriangle className="h-4 w-4 flex-shrink-0" />
        <span>Your Pro trial ends in {days} days. Upgrade now to keep all features.</span>
        <button
          onClick={() => openUpgradeModal('advancedReports')}
          className="ml-2 rounded bg-white/25 px-3 py-1 text-xs font-bold transition-colors hover:bg-white/35"
        >
          Upgrade
        </button>
      </div>
    );
  }

  // Urgent: 1 day left (today or tomorrow)
  return (
    <div className="relative z-0 flex items-center justify-center gap-2 bg-red-600 px-4 py-2 text-sm font-semibold text-white">
      <AlertTriangle className="h-4 w-4 flex-shrink-0" />
      <span>Your Pro trial ends {days === 1 ? 'tomorrow' : 'today'}! Upgrade now to avoid losing Pro features.</span>
      <button
        onClick={() => openUpgradeModal('advancedReports')}
        className="ml-2 rounded bg-white/25 px-3 py-1 text-xs font-bold transition-colors hover:bg-white/35"
      >
        Upgrade Now
      </button>
    </div>
  );
}
