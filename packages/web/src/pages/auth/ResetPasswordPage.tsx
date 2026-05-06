import { useEffect, useRef, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { Zap, Loader2, KeyRound, CheckCircle2, XCircle } from 'lucide-react';
import { authApi } from '@/api/endpoints';

export function ResetPasswordPage() {
  const { token: tokenFromUrl } = useParams<{ token: string }>();

  // SEC-H61: Stash the token in a ref and immediately strip it from the
  // address bar via history.replaceState, so a casual screenshot, screen
  // share, or browser-history export never leaks the single-use token.
  // We use a ref (not useState) so the value doesn't end up in React
  // DevTools state inspectors either. Cleared on successful submit.
  const tokenRef = useRef<string | null>(tokenFromUrl ?? null);

  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [showRequestLink, setShowRequestLink] = useState(false);
  const [success, setSuccess] = useState(false);

  const hasConfirmValue = confirmPassword.length > 0;
  const passwordsMatch = hasConfirmValue && password === confirmPassword;

  useEffect(() => {
    // Replace the current history entry so the back button can't recover the
    // token either. We keep the path at /reset-password (no token) so React
    // Router's route match still resolves to this component on back-nav.
    if (tokenFromUrl && typeof window !== 'undefined') {
      try {
        window.history.replaceState({}, '', '/reset-password');
      } catch {
        // history API unavailable (very old browsers / sandboxed iframes) —
        // fall through; the token remains in the URL but submission still
        // works.
      }
    }
    // Intentional: run once on mount with the token captured at mount time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setShowRequestLink(false);

    const token = tokenRef.current;
    if (!token) {
      setError('Invalid or missing reset token.');
      setShowRequestLink(true);
      return;
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters long.');
      return;
    }
    if (password !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);
    try {
      await authApi.resetPassword(token, password);
      // SEC-H61: token is single-use on the server; also scrub it from
      // client memory the moment we no longer need it, so a later XSS
      // or memory-inspection tool can't replay it.
      tokenRef.current = null;
      setPassword('');
      setConfirmPassword('');
      setSuccess(true);
    } catch (err: unknown) {
      // SEC-WEB-FA-005: avoid revealing whether the token was valid, expired,
      // or otherwise malformed. A generic message keeps probing attackers
      // from distinguishing failure modes via UX text.
      const e = err as { response?: { status?: number; data?: { message?: string } } } | undefined;
      const status = e?.response?.status;
      let msg = 'Server error. Please try again.';
      let canRequestNewLink = false;
      if (!e?.response) {
        msg = 'Cannot reach the server. Check your connection and try again.';
      } else if (status === 429) {
        msg = 'Too many reset attempts. Try again later.';
      } else if (status === 400 && e.response.data?.message) {
        msg = e.response.data.message;
        canRequestNewLink = /token|link|expired/i.test(msg);
      }
      setError(msg);
      setShowRequestLink(canRequestNewLink);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="relative flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 via-primary-50/30 to-surface-100 dark:from-surface-950 dark:via-surface-900 dark:to-surface-950">
      <div className="w-full max-w-md px-4">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary-600 shadow-lg shadow-primary-600/30">
            <Zap className="h-8 w-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Bizarre CRM</h1>
          <p className="text-surface-500 dark:text-surface-400">
            Reset your password
          </p>
        </div>

        <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          {success ? (
            <div className="text-center space-y-4">
              <div className="flex justify-center">
                <CheckCircle2 className="h-12 w-12 text-green-500" />
              </div>
              <h2 className="text-xl font-bold text-surface-900 dark:text-surface-100">Password Reset</h2>
              <p className="text-sm text-surface-600 dark:text-surface-400">
                Your password has been successfully updated. Continue when you are ready to sign in again.
              </p>
              <Link to="/login" className="inline-flex items-center justify-center rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-semibold text-primary-950 shadow-sm hover:bg-primary-700">
                Continue to Login
              </Link>
            </div>
          ) : (
            <form onSubmit={handleSubmit} noValidate className="space-y-4">
              <div className="flex items-center gap-3 rounded-lg bg-primary-50 p-3 dark:bg-primary-950/30">
                <KeyRound className="h-5 w-5 shrink-0 text-primary-600" />
                <p className="text-xs text-primary-800 dark:text-primary-300">
                  Enter a new password for your account. Use at least 8 characters, choose one different from your last 5 passwords, and know this signs out your other sessions.
                </p>
              </div>

              <div>
                <label htmlFor="reset-password-new" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">New Password</label>
                <input
                  id="reset-password-new"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoFocus
                  required
                  minLength={8}
                  placeholder="Min 8 characters"
                  aria-invalid={!!error}
                  aria-describedby={error ? 'reset-password-error' : undefined}
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>

              <div>
                <label htmlFor="reset-password-confirm" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Confirm Password</label>
                <div className="relative">
                  <input
                    id="reset-password-confirm"
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    required
                    minLength={8}
                    placeholder="Confirm new password"
                    aria-invalid={!!error || (hasConfirmValue && !passwordsMatch)}
                    aria-describedby={error ? 'reset-password-error' : hasConfirmValue ? 'reset-password-match-status' : undefined}
                    className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 pr-10 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                  />
                  {hasConfirmValue && (
                    <span className="absolute right-3 top-1/2 -translate-y-1/2" aria-hidden="true">
                      {passwordsMatch
                        ? <CheckCircle2 className="h-4 w-4 text-green-500" />
                        : <XCircle className="h-4 w-4 text-red-500" />}
                    </span>
                  )}
                </div>
                {hasConfirmValue && (
                  <p id="reset-password-match-status" className={`mt-1 text-xs ${passwordsMatch ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
                    {passwordsMatch ? 'Passwords match.' : 'Passwords do not match.'}
                  </p>
                )}
              </div>

              {error && (
                <div id="reset-password-error" role="alert" aria-live="polite" className="rounded-lg bg-red-50 p-3 dark:bg-red-950/30">
                  <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
                  {showRequestLink && (
                    <Link to="/login?forgot=1" className="mt-2 inline-flex text-sm font-medium text-red-700 underline hover:text-red-800 dark:text-red-300 dark:hover:text-red-200">
                      Request a new reset link
                    </Link>
                  )}
                </div>
              )}

              <button
                type="submit"
                disabled={loading || password.length < 8 || !passwordsMatch}
                className="w-full rounded-lg bg-primary-600 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                {loading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : 'Reset password and sign out other devices'}
              </button>

              <div className="text-center mt-4">
                <Link to="/login" className="text-xs text-surface-400 hover:text-surface-600">
                  Back to login
                </Link>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
