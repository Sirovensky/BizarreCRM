import { useState } from 'react';
import type { JSX, FormEvent } from 'react';
import { User, Lock, Loader2 } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { authApi } from '@/api/endpoints';

/**
 * Step 1 (self-host) — First login.
 *
 * Mirrors `#screen-1` in `docs/setup-wizard-preview.html`. The shop owner
 * arrives at `https://shop.local/login` with the seeded `admin / admin123`
 * credentials. The form posts to `authApi.login`, then queries
 * `authApi.setupStatus()` to read the `force_password_change` flag (when
 * present). Either way the shell advances — `forcePassword` is the next
 * phase in `WIZARD_ORDER_SELF` and is skipped through automatically when the
 * flag is false.
 *
 * The amber warning above the form makes the default-credential state
 * explicit so the owner expects the upcoming password change.
 */
export function StepFirstLogin({ onNext }: StepProps): JSX.Element {
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (submitting) return;
    setError(null);
    setSubmitting(true);
    try {
      await authApi.login(username, password);
      // Best-effort read of the force_password_change flag from setup status.
      // The shell handles the actual phase routing — we just advance, and the
      // linear WIZARD_ORDER_SELF passes through forcePassword either way.
      try {
        const statusRes = await authApi.setupStatus();
        const data = statusRes.data?.data as Record<string, unknown> | undefined;
        // Touch the flag so it shows up in network logs / future-proof reads;
        // routing decision is intentionally identical for true/false.
        void data?.force_password_change;
      } catch {
        // ignore — failing to read setup status shouldn't block advancement
      }
      onNext();
    } catch (err: unknown) {
      const ax = err as { response?: { data?: { message?: string } }; message?: string };
      const msg =
        ax?.response?.data?.message ||
        ax?.message ||
        'Sign-in failed. Check your username and password.';
      setError(msg);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="mx-auto w-full max-w-md">
      <div className="mb-6 flex justify-center">
</div>

      <div className="bg-white dark:bg-surface-800 rounded-2xl border border-surface-200 dark:border-surface-700 p-8 max-w-md mx-auto shadow-lg">
        {/* Avatar / step icon */}
        <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <User className="h-7 w-7 text-primary-600 dark:text-primary-400" aria-hidden="true" />
        </div>

        <h1 className="text-center font-['League_Spartan'] text-2xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Welcome to BizarreCRM
        </h1>
        <p className="mt-1 mb-6 text-center text-sm text-surface-500 dark:text-surface-400">
          Sign in to your shop
        </p>

        {/* Default-credentials warning */}
        <div
          role="status"
          className="mb-5 rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-700 dark:bg-amber-900/20"
        >
          <p className="text-sm text-amber-900 dark:text-amber-200">
            <strong className="font-semibold">Default credentials in use.</strong>{' '}
            You'll be required to change them before continuing.
          </p>
        </div>

        <form onSubmit={handleSubmit} noValidate>
          {/* Username */}
          <div className="mb-4">
            <label
              htmlFor="wizard-firstlogin-username"
              className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
            >
              Username
            </label>
            <div className="relative">
              <User
                className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400"
                aria-hidden="true"
              />
              <input
                id="wizard-firstlogin-username"
                type="text"
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                disabled={submitting}
                className="w-full rounded-lg border border-surface-300 bg-surface-50 py-3 pl-9 pr-4 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 disabled:opacity-60 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>
          </div>

          {/* Password */}
          <div className="mb-5">
            <label
              htmlFor="wizard-firstlogin-password"
              className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
            >
              Password
            </label>
            <div className="relative">
              <Lock
                className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400"
                aria-hidden="true"
              />
              <input
                id="wizard-firstlogin-password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={submitting}
                placeholder="admin123"
                className="w-full rounded-lg border border-surface-300 bg-surface-50 py-3 pl-9 pr-4 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 disabled:opacity-60 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>
          </div>

          {/* Inline error */}
          {error ? (
            <div
              role="alert"
              className="mb-4 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-700 dark:bg-red-900/20 dark:text-red-300"
            >
              {error}
            </div>
          ) : null}

          {/* Sign in (Back is hidden on first step) */}
          <button
            type="submit"
            disabled={submitting || password.length === 0 || username.trim().length === 0}
            className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-500 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {submitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Signing in…
              </>
            ) : (
              'Sign in'
            )}
          </button>
        </form>
      </div>
    </div>
  );
}

export default StepFirstLogin;
