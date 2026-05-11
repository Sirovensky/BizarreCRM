/**
 * CookieConsentBanner — LEGAL-COOKIE-CONSENT-1.
 *
 * Shown on the first visit (when `hasDecided` is false) and reachable later
 * via the "Cookie preferences" link in the footer. Categories: necessary
 * (locked on), preferences, analytics, marketing. CCPA "Do Not Sell My
 * Personal Information" toggle ships in the same banner since US shops will
 * end up under CCPA before EU expansion ships.
 *
 * Backed by consentStore. Other code paths read `useConsentStore.isAllowed`
 * before writing analytics/marketing cookies. The banner does not interact
 * with the auth/csrf/theme cookies because those fall under the "strictly
 * necessary" / "explicitly requested" ePrivacy exemptions.
 */
import { useState } from 'react';
import { X, Cookie } from 'lucide-react';
import { useConsentStore } from '@/stores/consentStore';

export function CookieConsentBanner() {
  const hasDecided = useConsentStore((s) => s.hasDecided);
  const preferences = useConsentStore((s) => s.preferences);
  const analytics = useConsentStore((s) => s.analytics);
  const marketing = useConsentStore((s) => s.marketing);
  const ccpaDoNotSell = useConsentStore((s) => s.ccpaDoNotSell);
  const acceptAll = useConsentStore((s) => s.acceptAll);
  const rejectNonEssential = useConsentStore((s) => s.rejectNonEssential);
  const saveCustom = useConsentStore((s) => s.saveCustom);
  const setDoNotSell = useConsentStore((s) => s.setDoNotSell);

  const [customizing, setCustomizing] = useState(false);
  const [draft, setDraft] = useState({ preferences, analytics, marketing });

  if (hasDecided) return null;

  function openCustomize() {
    setDraft({ preferences, analytics, marketing });
    setCustomizing(true);
  }

  function commitCustom() {
    saveCustom(draft);
    setCustomizing(false);
  }

  return (
    <div
      role="region"
      aria-label="Cookie preferences"
      className="fixed inset-x-0 bottom-0 z-50 border-t border-surface-200 bg-surface-0 shadow-2xl dark:border-surface-700 dark:bg-surface-900"
    >
      <div className="mx-auto max-w-5xl px-4 py-4 sm:px-6">
        {!customizing ? (
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3">
              <Cookie className="w-5 h-5 mt-0.5 shrink-0 text-primary-500" aria-hidden="true" />
              <div className="text-sm">
                <p className="font-semibold">We use cookies</p>
                <p className="text-surface-600 dark:text-surface-400">
                  Strictly-necessary cookies (sign-in, CSRF) are always on. Preferences,
                  analytics, and marketing cookies are off until you opt in.{' '}
                  <a
                    href="/legal/cookies"
                    className="underline hover:text-primary-500"
                  >
                    Learn more
                  </a>
                  .
                </p>
              </div>
            </div>
            <div className="flex flex-wrap gap-2 sm:flex-nowrap">
              <button
                type="button"
                onClick={openCustomize}
                className="rounded-md border border-surface-300 px-3 py-1.5 text-sm hover:bg-surface-100 dark:border-surface-600 dark:hover:bg-surface-800"
              >
                Customize
              </button>
              <button
                type="button"
                onClick={rejectNonEssential}
                className="rounded-md border border-surface-300 px-3 py-1.5 text-sm hover:bg-surface-100 dark:border-surface-600 dark:hover:bg-surface-800"
              >
                Reject non-essential
              </button>
              <button
                type="button"
                onClick={acceptAll}
                className="rounded-md bg-primary-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-primary-700"
              >
                Accept all
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-3">
            <div className="flex items-start justify-between gap-3">
              <h2 className="text-base font-semibold flex items-center gap-2">
                <Cookie className="w-5 h-5 text-primary-500" aria-hidden="true" />
                Cookie preferences
              </h2>
              <button
                type="button"
                onClick={() => setCustomizing(false)}
                aria-label="Close customization"
                className="text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
              >
                <X className="w-5 h-5" />
              </button>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <Row
                title="Strictly necessary"
                description="Sign-in, CSRF, security. Always on."
                checked
                disabled
              />
              <Row
                title="Preferences"
                description="Theme, sidebar collapse, language. Improves your experience."
                checked={draft.preferences}
                onChange={(v) => setDraft((d) => ({ ...d, preferences: v }))}
              />
              <Row
                title="Analytics"
                description="Anonymous usage telemetry so we can fix the parts that break most."
                checked={draft.analytics}
                onChange={(v) => setDraft((d) => ({ ...d, analytics: v }))}
              />
              <Row
                title="Marketing"
                description="Referral attribution, retargeting pixels. Off by default."
                checked={draft.marketing}
                onChange={(v) => setDraft((d) => ({ ...d, marketing: v }))}
              />
            </div>
            <label className="flex items-start gap-2 rounded-md border border-surface-200 px-3 py-2 text-sm dark:border-surface-700">
              <input
                type="checkbox"
                checked={ccpaDoNotSell}
                onChange={(e) => setDoNotSell(e.target.checked)}
                className="mt-0.5"
              />
              <span>
                <span className="font-medium">Do Not Sell or Share My Personal Information</span>{' '}
                <span className="text-surface-500 dark:text-surface-400">
                  (California / CCPA opt-out — applies even if you allow analytics or
                  marketing cookies above)
                </span>
              </span>
            </label>
            <div className="flex flex-wrap justify-end gap-2">
              <button
                type="button"
                onClick={rejectNonEssential}
                className="rounded-md border border-surface-300 px-3 py-1.5 text-sm hover:bg-surface-100 dark:border-surface-600 dark:hover:bg-surface-800"
              >
                Reject non-essential
              </button>
              <button
                type="button"
                onClick={commitCustom}
                className="rounded-md bg-primary-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-primary-700"
              >
                Save preferences
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

interface RowProps {
  title: string;
  description: string;
  checked: boolean;
  disabled?: boolean;
  onChange?: (next: boolean) => void;
}

function Row({ title, description, checked, disabled, onChange }: RowProps) {
  return (
    <label className="flex items-start gap-2 rounded-md border border-surface-200 px-3 py-2 text-sm dark:border-surface-700">
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange?.(e.target.checked)}
        className="mt-0.5"
        aria-label={title}
      />
      <span>
        <span className="font-medium">{title}</span>
        <span className="block text-surface-500 dark:text-surface-400">{description}</span>
      </span>
    </label>
  );
}
