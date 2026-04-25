import { useEffect, useRef, useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { Zap, Loader2, KeyRound, CheckCircle2 } from 'lucide-react';
import { authApi } from '@/api/endpoints';

export function ResetPasswordPage() {
  const { token: tokenFromUrl } = useParams<{ token: string }>();
  const navigate = useNavigate();

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
  const [success, setSuccess] = useState(false);

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

    const token = tokenRef.current;
    if (!token) {
      setError('Invalid or missing reset token.');
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
      setTimeout(() => {
        navigate('/login', { replace: true });
      }, 3000);
    } catch (err: unknown) {
      // SEC-WEB-FA-005: avoid revealing whether the token was valid, expired,
      // or otherwise malformed. A generic message keeps probing attackers
      // from distinguishing failure modes via UX text.
      const e = err as { response?: { status?: number; data?: { message?: string } } } | undefined;
      const status = e?.response?.status;
      // Surface server-provided message ONLY for explicit validation errors
      // (400) where the server already controls disclosure; otherwise stay
      // generic.
      const msg = status === 400 && e?.response?.data?.message
        ? e.response.data.message
        : 'Failed to reset password. Please request a new reset link.';
      setError(msg);
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
                Your password has been successfully updated. You will be redirected to the login page shortly.
              </p>
              <Link to="/login" className="inline-block mt-4 text-primary-600 hover:text-primary-700 font-medium">
                Return to Login
              </Link>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="flex items-center gap-3 rounded-lg bg-primary-50 p-3 dark:bg-primary-950/30">
                <KeyRound className="h-5 w-5 shrink-0 text-primary-600" />
                <p className="text-xs text-primary-800 dark:text-primary-300">
                  Enter securely a new password for your account.
                </p>
              </div>

              <div>
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">New Password</label>
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoFocus
                  required
                  minLength={8}
                  placeholder="Min 8 characters"
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>

              <div>
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Confirm Password</label>
                <input
                  type="password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                  minLength={8}
                  placeholder="Confirm new password"
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>

              {error && (
                <div className="rounded-lg bg-red-50 p-3 dark:bg-red-950/30">
                  <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
                </div>
              )}

              <button
                type="submit"
                disabled={loading || password.length < 8}
                className="w-full rounded-lg bg-primary-600 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50"
              >
                {loading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : 'Reset Password'}
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
