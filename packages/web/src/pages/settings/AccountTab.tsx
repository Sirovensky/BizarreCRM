/**
 * AccountTab — PROD110 unblock.
 *
 * Self-service "Change my password" surface in Settings. Wraps
 * authApi.changePassword (POST /auth/change-password). Server enforces
 * rate limit (5/hr per user+ip), reuse rejection (last N passwords),
 * length 8-256, and revokes every active session on success — the user
 * is logged out of every device and must sign in again on this one too.
 *
 * 2FA enrollment is handled at login (forced when totp_enabled=0); a
 * dedicated re-enroll-from-settings flow is not exposed here because
 * the current server contract has no /account/2fa/enable equivalent.
 */
import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { Loader2, KeyRound, AlertTriangle } from 'lucide-react';
import toast from 'react-hot-toast';
import { authApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';

const MIN_LEN = 8;
const MAX_LEN = 256;

export function AccountTab() {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [serverErr, setServerErr] = useState<string | null>(null);
  const logout = useAuthStore((s) => s.logout);

  const lengthOk = next.length >= MIN_LEN && next.length <= MAX_LEN;
  const matches = next.length > 0 && next === confirm;
  const differs = next !== current;
  const canSubmit = current.length > 0 && lengthOk && matches && differs;

  const mut = useMutation({
    mutationFn: () => authApi.changePassword(current, next),
    onSuccess: () => {
      toast.success('Password changed — signing you out');
      setCurrent('');
      setNext('');
      setConfirm('');
      setServerErr(null);
      setTimeout(() => {
        logout();
        window.location.href = '/login';
      }, 800);
    },
    onError: (err: unknown) => {
      const msg =
        (err as { response?: { data?: { message?: string } }; message?: string })
          ?.response?.data?.message ??
        (err as { message?: string })?.message ??
        'Password change failed';
      setServerErr(msg);
    },
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit || mut.isPending) return;
    setServerErr(null);
    mut.mutate();
  }

  return (
    <div className="space-y-6 max-w-xl">
      <header className="space-y-1">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          <KeyRound className="w-5 h-5" /> Account
        </h2>
        <p className="text-sm text-surface-500 dark:text-surface-400">
          Change the password you sign in with. All active sessions on every
          device will be revoked when the password changes.
        </p>
      </header>

      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-1">
          <label htmlFor="acct-current" className="text-sm font-medium">
            Current password
          </label>
          <input
            id="acct-current"
            type="password"
            autoComplete="current-password"
            value={current}
            onChange={(e) => setCurrent(e.target.value)}
            className="input w-full"
            required
          />
        </div>

        <div className="space-y-1">
          <label htmlFor="acct-new" className="text-sm font-medium">
            New password
          </label>
          <input
            id="acct-new"
            type="password"
            autoComplete="new-password"
            value={next}
            onChange={(e) => setNext(e.target.value)}
            className="input w-full"
            aria-describedby="acct-new-hint"
            required
          />
          <p id="acct-new-hint" className="text-xs text-surface-500 dark:text-surface-400">
            {MIN_LEN}-{MAX_LEN} characters. Must differ from your last few passwords.
          </p>
        </div>

        <div className="space-y-1">
          <label htmlFor="acct-confirm" className="text-sm font-medium">
            Confirm new password
          </label>
          <input
            id="acct-confirm"
            type="password"
            autoComplete="new-password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            className="input w-full"
            required
          />
          {confirm.length > 0 && !matches && (
            <p className="text-xs text-red-500">Passwords do not match</p>
          )}
        </div>

        {serverErr && (
          <div
            role="alert"
            className="flex items-start gap-2 rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-sm text-red-700 dark:text-red-300"
          >
            <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{serverErr}</span>
          </div>
        )}

        <button
          type="submit"
          disabled={!canSubmit || mut.isPending}
          className="btn-primary inline-flex items-center gap-2"
        >
          {mut.isPending && <Loader2 className="w-4 h-4 animate-spin" />}
          Change password
        </button>
      </form>

      <section className="space-y-2 border-t border-surface-200 dark:border-surface-700 pt-4">
        <h3 className="text-sm font-semibold">Two-factor authentication</h3>
        <p className="text-sm text-surface-500 dark:text-surface-400">
          2FA enrollment runs at login. If you have not yet enrolled, the
          authenticator QR is shown on your next sign-in. To disable 2FA,
          a shop admin can clear it from the Users tab.
        </p>
      </section>
    </div>
  );
}
