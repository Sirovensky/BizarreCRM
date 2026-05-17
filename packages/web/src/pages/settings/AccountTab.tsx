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
import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2, KeyRound, AlertTriangle, Smartphone, Trash2, QrCode } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import toast from 'react-hot-toast';
import { authApi, posHandoffApi, type PairedDevice } from '@/api/endpoints';
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

      <PairedDevicesSection />
    </div>
  );
}

function formatRelative(iso: string | null): string {
  if (!iso) return 'never';
  // BUGHUNT-2026-05-16: last_seen_at is a SQLite datetime('now') string
  // (UTC, no 'Z' suffix). V8 parses as local time, shifting "x ago"
  // computations by the browser's UTC offset.
  const normalized = iso.includes('T') || iso.endsWith('Z') || iso.includes('+')
    ? iso
    : `${iso.replace(' ', 'T')}Z`;
  const ms = Date.now() - new Date(normalized).getTime();
  if (Number.isNaN(ms) || ms < 0) return 'just now';
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function PairedDevicesSection() {
  const qc = useQueryClient();
  const [pairing, setPairing] = useState<{ code: string; expiresAt: number } | null>(null);
  const [, forceTick] = useState(0);

  const devicesQ = useQuery({
    queryKey: ['paired-devices'],
    queryFn: () => posHandoffApi.listDevices().then((r) => r.data.data),
    staleTime: 15_000,
  });

  // Tick once per second while the pairing code is live so the countdown
  // re-renders without keeping a separate timer hook on every section.
  useEffect(() => {
    if (!pairing) return;
    const t = window.setInterval(() => {
      if (Date.now() >= pairing.expiresAt) {
        setPairing(null);
      } else {
        forceTick((n) => n + 1);
      }
    }, 1000);
    return () => window.clearInterval(t);
  }, [pairing]);

  const startMut = useMutation({
    mutationFn: () => posHandoffApi.startPairing(),
    onSuccess: (res) => {
      const code = res.data.data.code;
      const ttl = res.data.data.expires_in_seconds * 1000;
      setPairing({ code, expiresAt: Date.now() + ttl });
    },
    onError: (err: unknown) => {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ??
        'Could not start pairing';
      toast.error(msg);
    },
  });

  const removeMut = useMutation({
    mutationFn: (id: number) => posHandoffApi.removeDevice(id),
    onSuccess: () => {
      toast.success('Device unpaired');
      qc.invalidateQueries({ queryKey: ['paired-devices'] });
    },
    onError: (err: unknown) => {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ??
        'Could not remove device';
      toast.error(msg);
    },
  });

  const devices: PairedDevice[] = devicesQ.data ?? [];
  const remainingSeconds = pairing ? Math.max(0, Math.ceil((pairing.expiresAt - Date.now()) / 1000)) : 0;

  return (
    <section className="space-y-3 border-t border-surface-200 dark:border-surface-700 pt-4">
      <header className="space-y-1">
        <h3 className="text-sm font-semibold flex items-center gap-2">
          <Smartphone className="w-4 h-4" /> Paired devices
        </h3>
        <p className="text-sm text-surface-500 dark:text-surface-400">
          A paired phone can take over Call / SMS actions tapped from POS or
          the ticket list. Pair once on a device you trust; the pairing code
          expires in 10 minutes and is single-use.
        </p>
      </header>

      {pairing ? (
        <div className="rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-500/10 dark:border-amber-500/30 p-4 space-y-3">
          <div className="flex items-start gap-4">
            <div className="bg-white p-2 rounded-md shrink-0">
              <QRCodeSVG value={pairing.code} size={120} />
            </div>
            <div className="space-y-1 text-sm">
              <p className="font-semibold">On the paired phone, enter:</p>
              <p className="font-mono text-2xl tracking-widest">{pairing.code}</p>
              <p className="text-xs text-amber-700 dark:text-amber-300">
                Code expires in {Math.floor(remainingSeconds / 60)}:
                {String(remainingSeconds % 60).padStart(2, '0')}. Single-use; a
                new code is required for a second device.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => setPairing(null)}
            className="btn-secondary text-xs"
          >
            Cancel
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => startMut.mutate()}
          disabled={startMut.isPending}
          className="btn-primary inline-flex items-center gap-2 text-sm"
        >
          {startMut.isPending ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            <QrCode className="w-4 h-4" />
          )}
          Pair a phone
        </button>
      )}

      <div className="space-y-2">
        <h4 className="text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400">
          Currently paired
        </h4>
        {devicesQ.isLoading ? (
          <p className="text-sm text-surface-500 dark:text-surface-400">Loading…</p>
        ) : devices.length === 0 ? (
          <p className="text-sm text-surface-500 dark:text-surface-400">
            No paired devices.
          </p>
        ) : (
          <ul className="divide-y divide-surface-200 dark:divide-surface-700 rounded-md border border-surface-200 dark:border-surface-700">
            {devices.map((d) => (
              <li
                key={d.id}
                className="flex items-center justify-between gap-3 px-3 py-2 text-sm"
              >
                <div className="min-w-0">
                  <p className="font-medium truncate">
                    {d.device_label || `Device #${d.id}`}
                  </p>
                  <p className="text-xs text-surface-500 dark:text-surface-400">
                    {d.platform || 'unknown platform'} · last seen {formatRelative(d.last_seen_at)}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    if (confirm(`Unpair ${d.device_label || `device #${d.id}`}?`)) {
                      removeMut.mutate(d.id);
                    }
                  }}
                  disabled={removeMut.isPending}
                  className="btn-ghost text-red-600 dark:text-red-400 inline-flex items-center gap-1 text-xs"
                  aria-label={`Unpair ${d.device_label || `device ${d.id}`}`}
                >
                  <Trash2 className="w-3.5 h-3.5" />
                  Unpair
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
