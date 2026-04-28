import { useState } from 'react';
import { Mail, AlertTriangle, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import type { JSX } from 'react';
import type { StepProps } from '../wizardTypes';

/**
 * Step 2 (SaaS) — Verify email.
 *
 * Mockup: docs/setup-wizard-preview.html `<section id="screen-saas-2">`.
 *
 * Behaviour:
 *  - Echoes back the email captured in Step 1 (`pending.signup_email`).
 *  - Collects a 6-digit code (single field, monospace, numeric inputMode).
 *  - The real verification endpoint isn't wired yet, so "Verify" just
 *    calls onNext() once the user has typed exactly 6 digits, and a
 *    toast nudges them that SMTP is pending.
 *  - "Resend code" is a placeholder toast for the same reason.
 *  - In dev (`import.meta.env.DEV === true`), an extra yellow button
 *    hits `POST /api/v1/signup/verify/dev-skip` to bypass verification.
 *    The route is only mounted when the server is running with
 *    `NODE_ENV != production` AND `WIZARD_DEV_SKIP_EMAIL=1`, so 404 is
 *    surfaced as a helpful toast pointing at the env-var requirement.
 */
export function StepVerifyEmail({
  pending,
  onUpdate: _onUpdate,
  onNext,
  onBack,
  onSkip: _onSkip,
}: StepProps): JSX.Element {
  const email = pending.signup_email || '';

  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [devSkipping, setDevSkipping] = useState(false);
  const [devSkipError, setDevSkipError] = useState<string | null>(null);

  const isSixDigits = /^\d{6}$/.test(code);
  const isDev = import.meta.env.DEV === true;

  const handleVerify = () => {
    if (!isSixDigits) return;
    setSubmitting(true);
    // Real endpoint not ready — keep behaviour consistent with the
    // "wired-up" UX (button shows a brief loading state) before
    // advancing.
    toast('Verification will work once SMTP is wired.', { icon: '✉️' });
    onNext();
    setSubmitting(false);
  };

  const handleResend = () => {
    toast('Resend will work once SMTP is wired.', { icon: '✉️' });
  };

  const handleDevSkip = async () => {
    setDevSkipping(true);
    setDevSkipError(null);

    // Slug isn't part of PendingWrites yet — Agent 3 may stash it in
    // sessionStorage. Read defensively so this file works regardless.
    let slug: string | null = null;
    try {
      slug = sessionStorage.getItem('pending_signup_slug');
    } catch {
      slug = null;
    }

    try {
      const res = await fetch('/api/v1/signup/verify/dev-skip', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify({ slug, adminEmail: email }),
      });

      if (res.status === 404) {
        toast.error(
          'Dev-skip not enabled. Set NODE_ENV != production AND WIZARD_DEV_SKIP_EMAIL=1 server-side.',
        );
        setDevSkipping(false);
        return;
      }

      if (!res.ok) {
        let message = `Dev-skip failed (HTTP ${res.status})`;
        try {
          const body = (await res.json()) as { error?: string; message?: string };
          message = body.error || body.message || message;
        } catch {
          /* swallow — non-JSON body */
        }
        setDevSkipError(message);
        setDevSkipping(false);
        return;
      }

      // Success — advance to twoFactorSetup.
      onNext();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Network error';
      setDevSkipError(message);
    } finally {
      setDevSkipping(false);
    }
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-4 flex justify-center">
</div>

      <div className="mx-auto max-w-md rounded-2xl border border-surface-200 bg-white p-8 text-center shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Mail className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>

        <h1 className="font-['League_Spartan'] text-2xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Check your email
        </h1>
        <p className="mt-2 text-sm text-surface-600 dark:text-surface-400">
          We sent a 6-digit code to{' '}
          <strong className="text-surface-900 dark:text-surface-100">
            {email || 'your email'}
          </strong>
          .
        </p>

        <div className="mt-6 text-left">
          <label
            htmlFor="verify-code"
            className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
          >
            6-digit code <span className="text-red-500">*</span>
          </label>
          <input
            id="verify-code"
            type="text"
            value={code}
            onChange={(e) => {
              const next = e.target.value.replace(/\D/g, '').slice(0, 6);
              setCode(next);
            }}
            inputMode="numeric"
            maxLength={6}
            autoComplete="one-time-code"
            placeholder="000000"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center font-mono text-xl tracking-[0.4em] text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
        </div>

        <button
          type="button"
          onClick={handleVerify}
          disabled={!isSixDigits || submitting}
          className="mt-4 flex w-full items-center justify-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none"
        >
          {submitting ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Verifying…
            </>
          ) : (
            'Verify'
          )}
        </button>

        <button
          type="button"
          onClick={handleResend}
          className="mt-3 text-sm font-medium text-primary-600 hover:underline dark:text-primary-400"
        >
          Resend code
        </button>

        {isDev ? (
          <div className="mt-6 border-t border-surface-200 pt-4 dark:border-surface-700">
            <button
              type="button"
              onClick={handleDevSkip}
              disabled={devSkipping}
              className="inline-flex items-center gap-2 rounded-lg border border-yellow-400 bg-yellow-100 px-4 py-2 text-sm font-medium text-yellow-900 hover:bg-yellow-200 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-yellow-900/30 dark:text-yellow-200"
            >
              {devSkipping ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <AlertTriangle className="h-4 w-4" />
              )}
              Skip email check (dev only)
            </button>
            {devSkipError ? (
              <p className="mt-2 text-xs text-red-600 dark:text-red-400">
                {devSkipError}
              </p>
            ) : null}
          </div>
        ) : null}

        <div className="mt-6 flex justify-start">
          <button
            type="button"
            onClick={onBack}
            className="text-xs font-medium text-surface-500 hover:text-surface-700 hover:underline dark:text-surface-400 dark:hover:text-surface-200"
          >
            ← Back
          </button>
        </div>
      </div>
    </div>
  );
}

export default StepVerifyEmail;
