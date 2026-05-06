import { useState } from 'react';
import type { JSX } from 'react';
import { Eye, EyeOff, Loader2, Lock } from 'lucide-react';
import { authApi } from '@/api/endpoints';
import { api } from '@/api/client';
import { assessSignupPassword } from '@/utils/passwordSecurity';
import type { StepProps } from '../wizardTypes';

/**
 * Wizard Step 2 (self-host only) — Force password change.
 *
 * The fresh self-host installer ships with the default `admin / admin123`
 * credentials. After Step 1 (first login) we drop the user here so they
 * cannot continue until those defaults are gone. Calls
 * `POST /auth/change-password` with the known default current password
 * (`admin123`) and whatever new password the user chose, then advances.
 *
 * `authApi.changePassword` is not (yet) defined on the shared `authApi`
 * object — rather than mutate that file from this single-file step we call
 * the endpoint directly through the shared `api` axios client. The server
 * route accepts snake_case (`current_password`, `new_password`).
 */

export function StepForcePassword({ onNext, onBack }: StepProps): JSX.Element {
  const [pwd, setPwd] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPwd, setShowPwd] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const strength = assessSignupPassword(pwd);
  const mismatch = confirm.length > 0 && pwd !== confirm;
  const canSubmit =
    !submitting &&
    pwd.length >= 10 &&
    confirm.length > 0 &&
    pwd === confirm;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;
    setError(null);
    setSubmitting(true);
    try {
      // Try the typed wrapper first if a future agent has added it.
      const maybeChange = (authApi as unknown as {
        changePassword?: (d: { currentPassword: string; newPassword: string }) => Promise<unknown>;
      }).changePassword;
      if (typeof maybeChange === 'function') {
        await maybeChange({ currentPassword: 'admin123', newPassword: pwd });
      } else {
        await api.post('/auth/change-password', {
          current_password: 'admin123',
          new_password: pwd,
        });
      }
      onNext();
    } catch (err) {
      const msg =
        (err as { response?: { data?: { message?: string } }; message?: string })?.response
          ?.data?.message ??
        (err as { message?: string })?.message ??
        'Could not change password. Please try again.';
      setError(msg);
    } finally {
      setSubmitting(false);
    }
  };

  // 5 pips, scores 0-4. Color per score level.
  const SCORE_COLORS = ['bg-red-500', 'bg-orange-500', 'bg-amber-500', 'bg-lime-500', 'bg-green-500'] as const;
  const strengthBars = Array.from({ length: 5 }, (_, i) =>
    strength.score === 0 || i >= strength.score ? 'bg-surface-200 dark:bg-surface-700' : SCORE_COLORS[strength.score]
  );
  const strengthTextClass = [
    'text-red-600 dark:text-red-400',
    'text-orange-600 dark:text-orange-400',
    'text-amber-600 dark:text-amber-400',
    'text-lime-700 dark:text-lime-400',
    'text-green-700 dark:text-green-400',
  ][strength.score];

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
</div>

      <form
        onSubmit={handleSubmit}
        className="bg-white dark:bg-surface-800 rounded-2xl border border-surface-200 dark:border-surface-700 p-8 max-w-md mx-auto shadow-lg"
      >
        <div className="mb-6 flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary-100 dark:bg-primary-500/10">
            <Lock className="h-5 w-5 text-primary-600 dark:text-primary-400" />
          </div>
          <div>
            <h2 className="font-['League_Spartan'] text-2xl font-bold text-surface-900 dark:text-surface-50">
              Pick a new password
            </h2>
            <p className="text-sm text-surface-500 dark:text-surface-400">
              Default credentials are insecure.
            </p>
          </div>
        </div>

        {/* New password */}
        <div className="mb-5">
          <label
            htmlFor="new-pwd"
            className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
          >
            New password <span className="text-red-500">*</span>
          </label>
          <div className="relative">
            <input
              id="new-pwd"
              type={showPwd ? 'text' : 'password'}
              value={pwd}
              onChange={(e) => setPwd(e.target.value)}
              autoFocus
              autoComplete="new-password"
              maxLength={256}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 pr-11 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
            <button
              type="button"
              onClick={() => setShowPwd((v) => !v)}
              className="absolute inset-y-0 right-0 flex items-center px-3 text-surface-500 hover:text-surface-700 dark:hover:text-surface-200"
              aria-label={showPwd ? 'Hide password' : 'Show password'}
              tabIndex={-1}
            >
              {showPwd ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </div>

          {/* Strength meter — 5 pips, scores 0-4 */}
          <div className="mt-2 flex gap-1">
            {strengthBars.map((cls, i) => (
              <span
                key={i}
                className={`h-1 flex-1 rounded-full ${cls} dark:opacity-90`}
              />
            ))}
          </div>
          <p className={`mt-1 text-xs font-medium ${strengthTextClass}`}>
            {pwd.length === 0 ? 'At least 10 characters' : strength.label}
          </p>
        </div>

        {/* Confirm */}
        <div className="mb-5">
          <label
            htmlFor="confirm-pwd"
            className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
          >
            Confirm new password <span className="text-red-500">*</span>
          </label>
          <div className="relative">
            <input
              id="confirm-pwd"
              type={showConfirm ? 'text' : 'password'}
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              autoComplete="new-password"
              maxLength={256}
              className={`w-full rounded-lg border bg-surface-50 px-4 py-3 pr-11 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
                mismatch
                  ? 'border-red-400 focus-visible:border-red-500 focus-visible:ring-red-500/20 dark:border-red-500'
                  : 'border-surface-300 focus-visible:border-primary-500 focus-visible:ring-primary-500/20 dark:border-surface-600'
              }`}
            />
            <button
              type="button"
              onClick={() => setShowConfirm((v) => !v)}
              className="absolute inset-y-0 right-0 flex items-center px-3 text-surface-500 hover:text-surface-700 dark:hover:text-surface-200"
              aria-label={showConfirm ? 'Hide password' : 'Show password'}
              tabIndex={-1}
            >
              {showConfirm ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </div>
          {mismatch ? (
            <p className="mt-1 text-xs font-medium text-red-600 dark:text-red-400">
              Passwords don't match
            </p>
          ) : null}
        </div>

        {error ? (
          <div
            role="alert"
            className="mb-4 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-700 dark:bg-red-900/20 dark:text-red-300"
          >
            {error}
          </div>
        ) : null}

        <button
          type="submit"
          disabled={!canSubmit}
          className="btn btn-lg flex w-full items-center justify-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-500 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none"
        >
          {submitting ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" />
              Saving…
            </>
          ) : (
            'Save and continue'
          )}
        </button>

        <div className="mt-3 flex justify-start">
          <button
            type="button"
            onClick={onBack}
            className="btn btn-sm text-sm font-medium text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
          >
            ← Back
          </button>
        </div>
      </form>
    </div>
  );
}

export default StepForcePassword;
