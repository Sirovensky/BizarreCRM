import type * as React from 'react';
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { X } from 'lucide-react';
import { settingsApi, authApi } from '@/api/endpoints';

/**
 * TrialBanner — dismissable warning banner for SaaS multi-tenant deployments.
 *
 * Shows ONLY when:
 *  - tenant is on multi-tenant SaaS (isMultiTenant === true)
 *  - trial has 3 or fewer days left, OR is on its expiry day, OR has expired
 *
 * Trial expiry is read from `trial_expires_at` config key (ISO 8601).
 * Dismissal persists in sessionStorage keyed by the expiry timestamp,
 * so a new expiry (e.g. extended trial) re-shows the banner.
 */
export function TrialBanner(): React.JSX.Element | null {
  const setupStatusQuery = useQuery({
    queryKey: ['auth', 'setup-status'],
    queryFn: async () => {
      const res = await authApi.setupStatus();
      return res.data.data;
    },
    staleTime: 5 * 60 * 1000,
  });

  const configQuery = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string> | undefined;
    },
    staleTime: 5 * 60 * 1000,
  });

  const trialExpiresAt = configQuery.data?.trial_expires_at;
  const dismissKey = trialExpiresAt
    ? `trial_banner_dismissed_until_${trialExpiresAt}`
    : null;

  const [dismissed, setDismissed] = useState<boolean>(() => {
    if (!dismissKey || typeof window === 'undefined') return false;
    try {
      return window.sessionStorage.getItem(dismissKey) === '1';
    } catch {
      return false;
    }
  });

  // Self-host single-tenant: never show.
  if (setupStatusQuery.data?.isMultiTenant !== true) return null;

  // No trial expiry configured: nothing to warn about.
  if (!trialExpiresAt) return null;

  const expiry = new Date(trialExpiresAt);
  if (Number.isNaN(expiry.getTime())) return null;

  const daysLeft = Math.ceil((expiry.getTime() - Date.now()) / (1000 * 60 * 60 * 24));

  // More than 3 days left: stay quiet.
  if (daysLeft > 3) return null;

  if (dismissed) return null;

  let message: string;
  if (daysLeft < 0) {
    message =
      'Your free trial has ended. Your shop is read-only — add billing to restore full access.';
  } else if (daysLeft === 0) {
    message = 'Your free trial ends today. Add billing to keep your shop running.';
  } else {
    message = `Your free trial ends in ${daysLeft} day${daysLeft === 1 ? '' : 's'}. Add billing now to keep your shop running.`;
  }

  const handleDismiss = () => {
    if (dismissKey) {
      try {
        window.sessionStorage.setItem(dismissKey, '1');
      } catch {
        // sessionStorage unavailable — dismiss only for this render lifetime.
      }
    }
    setDismissed(true);
  };

  return (
    <div
      role="alert"
      className="flex items-center gap-3 border-b px-4 py-2.5 text-sm bg-amber-50 border-amber-300 text-amber-900 dark:bg-amber-900/20 dark:border-amber-500/30 dark:text-amber-100"
    >
      <span className="flex-1 font-medium">{message}</span>
      <Link
        to="/settings?tab=billing"
        className="rounded-md border border-amber-400 bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-900 hover:bg-amber-200 dark:border-amber-400/40 dark:bg-amber-500/20 dark:text-amber-50 dark:hover:bg-amber-500/30"
      >
        Add billing
      </Link>
      <button
        type="button"
        onClick={handleDismiss}
        aria-label="Dismiss trial banner"
        className="rounded p-1 text-amber-900/70 hover:bg-amber-100 hover:text-amber-900 dark:text-amber-100/70 dark:hover:bg-amber-500/20 dark:hover:text-amber-50"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}

export default TrialBanner;
