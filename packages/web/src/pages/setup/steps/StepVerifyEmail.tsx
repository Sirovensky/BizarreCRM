import { useState } from 'react';
import { Mail, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import type { JSX } from 'react';
import { signupApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import type { StepProps } from '../wizardTypes';

/**
 * Step 2 (SaaS) — Verify email.
 *
 * Mockup: mockups/web-setup-wizard.html `<section id="screen-saas-2">`.
 *
 * Behaviour:
 *  - Echoes back the email captured in Step 1 (`pending.signup_email`).
 *  - Collects a 6-digit code (single field, monospace, numeric inputMode).
 *  - Verifies the pending signup through POST /api/v1/signup/verify-code,
 *    which provisions the tenant and returns an authenticated session.
 *  - Resend sends a fresh single-use link and code, invalidating the old link.
 */
export function StepVerifyEmail({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip: _onSkip,
}: StepProps): JSX.Element {
  const completeLogin = useAuthStore((s) => s.completeLogin);
  const email = pending.signup_email || '';
  let storedSlug = '';
  try {
    storedSlug = sessionStorage.getItem('pending_signup_slug') || '';
  } catch {
    storedSlug = '';
  }
  const slug = pending.signup_slug || storedSlug;

  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [resending, setResending] = useState(false);
  const [verifyError, setVerifyError] = useState<string | null>(null);

  const isSixDigits = /^\d{6}$/.test(code);

  const finishVerifiedSignup = (data: { accessToken?: string; user?: Parameters<typeof completeLogin>[2] }) => {
    if (!data.accessToken || !data.user) {
      throw new Error('Verification succeeded, but sign-in could not be completed. Please sign in from your shop URL.');
    }
    completeLogin(data.accessToken, '', data.user);
    onUpdate({ signup_verified: true });
    onNext();
  };

  const handleVerify = async () => {
    if (!isSixDigits || submitting) return;
    if (!slug || !email) {
      setVerifyError('Signup details are missing. Go back and submit the signup step again.');
      return;
    }
    setSubmitting(true);
    setVerifyError(null);
    try {
      const res = await signupApi.verifyEmailCode({ slug, adminEmail: email, code });
      finishVerifiedSignup(res.data.data);
      toast.success('Email verified');
    } catch (err: unknown) {
      const message =
        (err as { response?: { data?: { message?: string } }; message?: string })?.response?.data?.message ||
        (err as { message?: string })?.message ||
        'Verification failed. Check the code and try again.';
      setVerifyError(message);
    } finally {
      setSubmitting(false);
    }
  };

  const handleResend = async () => {
    if (!slug || !email || resending) {
      setVerifyError('Signup details are missing. Go back and submit the signup step again.');
      return;
    }
    setResending(true);
    setVerifyError(null);
    try {
      await signupApi.resendVerification({ slug, adminEmail: email });
      setCode('');
      toast.success('Verification code sent');
    } catch (err: unknown) {
      const message =
        (err as { response?: { data?: { message?: string } }; message?: string })?.response?.data?.message ||
        (err as { message?: string })?.message ||
        'Could not resend the verification code.';
      setVerifyError(message);
    } finally {
      setResending(false);
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
              setVerifyError(null);
            }}
            inputMode="numeric"
            maxLength={6}
            autoComplete="one-time-code"
            placeholder="000000"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center font-mono text-xl tracking-[0.4em] text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
          {verifyError ? (
            <p className="mt-2 text-sm text-red-600 dark:text-red-400" role="alert">
              {verifyError}
            </p>
          ) : null}
        </div>

        <button
          type="button"
          onClick={handleVerify}
          disabled={!isSixDigits || submitting}
          className="btn btn-lg mt-4 flex w-full items-center justify-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none"
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
          disabled={resending}
          className="btn btn-sm mt-3 inline-flex items-center justify-center gap-1.5 text-sm font-medium text-primary-600 hover:underline disabled:cursor-not-allowed disabled:opacity-50 dark:text-primary-400"
        >
          {resending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
          {resending ? 'Sending...' : 'Resend code'}
        </button>

        <div className="mt-6 flex justify-start">
          <button
            type="button"
            onClick={onBack}
            className="btn btn-xs text-xs font-medium text-surface-500 hover:text-surface-700 hover:underline dark:text-surface-400 dark:hover:text-surface-200"
          >
            ← Back
          </button>
        </div>
      </div>
    </div>
  );
}

export default StepVerifyEmail;
