import { AlertTriangle, X } from 'lucide-react';
import { usePlanStore } from '@/stores/planStore';
import { useDismissible } from '@/hooks/useDismissible';

/** Returns days remaining until trial ends. Negative for expired, 0 for ending today,
 *  positive for active. Null if no trial set. */
function daysRemaining(trialEndsAt: string | null): number | null {
  if (!trialEndsAt) return null;
  // BUGHUNT-2026-05-16: trial_ends_at is a SQLite 'YYYY-MM-DD HH:MM:SS'
  // (UTC, no 'Z'). V8 parses that as local time, shifting the banner
  // boundary by the operator's UTC offset.
  const normalized = trialEndsAt.includes('T') || trialEndsAt.endsWith('Z') || trialEndsAt.includes('+')
    ? trialEndsAt
    : `${trialEndsAt.replace(' ', 'T')}Z`;
  const end = new Date(normalized).getTime();
  if (Number.isNaN(end)) return null;
  const diffMs = end - Date.now();
  if (diffMs <= 0) return Math.floor(diffMs / (24 * 60 * 60 * 1000));
  return Math.ceil(diffMs / (24 * 60 * 60 * 1000));
}

/**
 * Trial status banner — only shows when the user is within 3 days of trial end,
 * OR after the trial has expired. The long "you're on trial" info bar that
 * previously ran for the full 14 days has been removed — users are told about
 * the trial in the setup wizard (StepTrialInfo) instead, which is a better
 * moment and location.
 *
 * All three banner variants (3-day warning, 1-day urgent, expired) are
 * dismissible via useDismissible, keyed on trialEndsAt so a new trial period
 * produces fresh warnings.
 *
 * NOT shown:
 *   days > 3 — completely silent during the majority of the trial
 *
 * Shown (all dismissible):
 *   days 2-3  : yellow warning, "Upgrade to keep all features"
 *   days 0-1  : red urgent, "Trial ends today/tomorrow"
 *   expired   : red, "Your Pro trial has ended"
 */
export function TrialBanner() {
  const { trialActive, trialEndsAt, plan, openUpgradeModal } = usePlanStore();

  // Keys scope dismissals to the current trial period; a future trial reset
  // will have a different trialEndsAt and the banner reappears.
  //
  // 3-day + urgent warnings keep the default 24h TTL — the trial state is
  // changing daily during that window, so re-surfacing once a day is OK.
  // The "expired" banner is permanent (Infinity TTL): once the operator has
  // acknowledged the trial ended, nagging them every 24h forever is hostile.
  // A future trial reset would update trialEndsAt and key the dismissal to
  // a new value, so the banner returns naturally.
  const [warn3Dismissed, dismissWarn3] = useDismissible(`trial-warn-3day:${trialEndsAt ?? 'none'}`);
  const [warnUrgentDismissed, dismissWarnUrgent] = useDismissible(`trial-warn-urgent:${trialEndsAt ?? 'none'}`);
  const [expiredDismissed, dismissExpired] = useDismissible(
    `trial-banner-expired:${trialEndsAt ?? 'none'}`,
    Infinity,
  );

  // Don't show banner if user is Pro and not on trial
  if (plan === 'pro' && !trialActive) return null;

  const days = daysRemaining(trialEndsAt);

  // ── Expired ─────────────────────────────────────────────────────
  // Trial expired (trial_ends_at exists but is in the past).
  // Dismissible permanently (Infinity TTL on the useDismissible key
  // above) — operators who accept staying on Free shouldn't be nagged
  // forever. A future trial reset re-keys the dismissal and the banner
  // returns naturally.
  if (trialEndsAt && !trialActive && days !== null && days <= 0) {
    if (expiredDismissed) return null;
    return (
      <div className="relative z-0 flex items-center justify-center gap-2 bg-red-600 px-4 py-2 text-sm text-white">
        <AlertTriangle className="h-4 w-4 flex-shrink-0" />
        <span>Your Pro trial has ended. You're now on the Free plan with limited features.</span>
        <button
          onClick={() => openUpgradeModal('advancedReports')}
          className="btn btn-xs ml-2 bg-white/20 font-semibold text-white hover:bg-white/30"
        >
          Upgrade to Pro
        </button>
        <button
          type="button"
          onClick={dismissExpired}
          aria-label="Dismiss trial-ended banner"
          className="btn-icon btn-xs ml-1 !text-white hover:bg-white/25 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  // Active trial — only show banner within the final 3 days
  if (!trialActive || days === null || days <= 0) return null;

  // ── days > 3: intentionally silent (no banner) ──────────────────
  if (days > 3) return null;

  // ── days 2-3: yellow warning, dismissible ───────────────────────
  if (days > 1) {
    if (warn3Dismissed) return null;
    return (
      <div className="relative z-0 flex items-center justify-center gap-2 bg-yellow-500 px-4 py-2 text-sm font-semibold text-white">
        <AlertTriangle className="h-4 w-4 flex-shrink-0" />
        <span>Your Pro trial ends in {days} days. Upgrade now to keep all features.</span>
        <button
          onClick={() => openUpgradeModal('advancedReports')}
          className="btn btn-xs ml-2 bg-white/25 font-bold text-white hover:bg-white/35"
        >
          Upgrade
        </button>
        <button
          type="button"
          onClick={dismissWarn3}
          aria-label="Dismiss trial 3-day warning"
          className="btn-icon btn-xs ml-1 !text-white hover:bg-white/25 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  // ── days 0-1: red urgent, dismissible ───────────────────────────
  if (warnUrgentDismissed) return null;
  return (
    <div className="relative z-0 flex items-center justify-center gap-2 bg-red-600 px-4 py-2 text-sm font-semibold text-white">
      <AlertTriangle className="h-4 w-4 flex-shrink-0" />
      <span>Your Pro trial ends {days === 1 ? 'tomorrow' : 'today'}! Upgrade now to avoid losing Pro features.</span>
      <button
        onClick={() => openUpgradeModal('advancedReports')}
        className="btn btn-xs ml-2 bg-white/25 font-bold text-white hover:bg-white/35"
      >
        Upgrade Now
      </button>
      <button
        type="button"
        onClick={dismissWarnUrgent}
        aria-label="Dismiss trial urgent warning"
        className="btn-icon btn-xs ml-1 !text-white hover:bg-white/25 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/50"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}
