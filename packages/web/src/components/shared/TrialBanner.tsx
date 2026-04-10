import { Sparkles, AlertTriangle, X } from 'lucide-react';
import { usePlanStore } from '@/stores/planStore';
import { useDismissible } from '@/hooks/useDismissible';

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

  // Dismissibility is keyed on trialEndsAt so a new trial period (e.g. after
  // an admin resets or a plan change) starts with a fresh banner. Separate
  // keys for "info" (> 3 days, casual) and "expired" (trial ended, on Free)
  // variants so dismissing one doesn't affect the other. The urgent warning
  // variants (1-3 days remaining) are intentionally NOT dismissible — they're
  // genuine calls to action while the user can still do something about it.
  const [infoDismissed, dismissInfo] = useDismissible(`trial-banner-info:${trialEndsAt ?? 'none'}`);
  const [expiredDismissed, dismissExpired] = useDismissible(`trial-banner-expired:${trialEndsAt ?? 'none'}`);

  // Don't show banner if user is Pro and not on trial
  if (plan === 'pro' && !trialActive) return null;

  const days = daysRemaining(trialEndsAt);

  // Trial expired (trial_ends_at exists but is in the past).
  // We rely on trialActive=false + days<=0 because the backend sets the effective plan
  // back to 'free' once the trial expires. Dismissible: users who accept staying on
  // Free shouldn't see this on every page load forever.
  if (trialEndsAt && !trialActive && days !== null && days <= 0) {
    if (expiredDismissed) return null;
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
        <button
          type="button"
          onClick={dismissExpired}
          aria-label="Dismiss trial expired notice"
          className="ml-1 rounded p-1 transition-colors hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-white/50"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  // Active trial — show banner based on days remaining
  if (!trialActive || days === null || days <= 0) return null;

  if (days > 3) {
    // Subtle info banner for active trial with plenty of time.
    // Dismissible: info-level messaging, user may not want the reminder.
    if (infoDismissed) return null;
    return (
      <div className="relative z-0 flex items-center justify-center gap-2 bg-indigo-600 px-4 py-1.5 text-xs text-white">
        <Sparkles className="h-3.5 w-3.5" />
        <span>
          You're on a Pro trial — {days} days remaining
        </span>
        <button
          type="button"
          onClick={dismissInfo}
          aria-label="Dismiss trial info"
          className="ml-1 rounded p-0.5 transition-colors hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-white/50"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>
    );
  }

  if (days > 1) {
    // Warning: 2-3 days left. NOT dismissible -- urgent action window.
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

  // Urgent: 1 day left (today or tomorrow). NOT dismissible -- last chance.
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
