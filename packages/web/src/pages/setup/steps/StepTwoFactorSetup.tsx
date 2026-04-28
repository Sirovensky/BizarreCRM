import { useEffect, useState, type JSX } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Smartphone, Copy, Loader2, ShieldCheck, AlertTriangle } from 'lucide-react';
import { toast } from 'react-hot-toast';
import { authApi } from '@/api/endpoints';
import type { StepProps } from '../wizardTypes';

/**
 * Step 3 — Two-factor authentication setup.
 *
 * Behavior:
 *  - On mount, calls `authApi.setup2fa(challengeToken)` to fetch a fresh TOTP
 *    secret + QR data URL. The wizard runs post-login so we don't have a
 *    challenge from the password stage; we pass an empty token and surface the
 *    server's response. If the server can't issue a secret here, the user can
 *    skip and enrol later from Settings.
 *  - Renders the QR + base32 secret + 6-digit code field, then verifies via
 *    `authApi.verify2fa(challengeToken, code)`.
 *  - On success the verify endpoint returns one-time backup codes; we show
 *    them in a 2-column grid and require an explicit "I've saved these"
 *    confirmation before advancing.
 *  - "Skip 2FA for now" advances without enrolling, with a small warning.
 *
 * Server contract (auth.routes.ts:903 / :937):
 *   setup2fa  → { qr, secret, manualEntry, challengeToken? }
 *   verify2fa → { ...AuthTokens, backupCodes?: string[] }
 *
 * Note: the wizardTypes contract names the QR field `qrCodeDataUrl`, but the
 * actual server returns `qr` — we use the wire shape per the implementation
 * plan ("if it returns differently, adapt").
 */
export function StepTwoFactorSetup({ onNext, onBack, onSkip }: StepProps): JSX.Element {
  // Detect single-tenant vs multi-tenant to pick the right "Step 2" prev label.
  const { data: setupStatusRes } = useQuery({
    queryKey: ['auth-setup-status'],
    queryFn: () => authApi.setupStatus(),
    staleTime: 10_000,
  });
  const isMultiTenant = setupStatusRes?.data?.data?.isMultiTenant ?? false;

  const [challengeToken, setChallengeToken] = useState<string>('');
  const [qrDataUrl, setQrDataUrl] = useState<string>('');
  const [secret, setSecret] = useState<string>('');
  const [code, setCode] = useState<string>('');
  const [showManual, setShowManual] = useState(false);
  const [enrolling, setEnrolling] = useState(true);
  const [enrollError, setEnrollError] = useState<string>('');
  const [verifying, setVerifying] = useState(false);
  const [backupCodes, setBackupCodes] = useState<string[] | null>(null);
  const [savedAck, setSavedAck] = useState(false);

  // Fetch QR + secret on mount.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      setEnrolling(true);
      setEnrollError('');
      try {
        const res = await authApi.setup2fa(challengeToken);
        if (cancelled) return;
        const payload = res.data?.data;
        setQrDataUrl(payload?.qr ?? '');
        setSecret(payload?.secret ?? payload?.manualEntry ?? '');
        if (payload?.challengeToken) setChallengeToken(payload.challengeToken);
      } catch (err: unknown) {
        if (cancelled) return;
        const message =
          (err as { response?: { data?: { message?: string } }; message?: string })?.response?.data
            ?.message ||
          (err as { message?: string })?.message ||
          'Could not start 2FA enrolment. You can skip this step and enable it later from Settings.';
        setEnrollError(message);
      } finally {
        if (!cancelled) setEnrolling(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // Run once on mount — challengeToken is captured at first call only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleCopySecret = async () => {
    if (!secret) return;
    try {
      await navigator.clipboard.writeText(secret);
      toast.success('Secret copied to clipboard');
    } catch {
      toast.error('Could not copy — select and copy manually');
    }
  };

  const handleVerify = async () => {
    if (!/^\d{6}$/.test(code)) {
      toast.error('Enter the 6-digit code from your authenticator');
      return;
    }
    setVerifying(true);
    try {
      const res = await authApi.verify2fa(challengeToken, code);
      const payload = res.data?.data as { backupCodes?: string[] } | undefined;
      const codes = payload?.backupCodes;
      if (codes && codes.length > 0) {
        setBackupCodes(codes);
        toast.success('2FA enabled — save your recovery codes');
      } else {
        toast.success('2FA enabled');
        onNext();
      }
    } catch (err: unknown) {
      const e = err as {
        response?: { data?: { data?: { challengeToken?: string }; message?: string } };
      };
      const newToken = e?.response?.data?.data?.challengeToken;
      if (newToken) setChallengeToken(newToken);
      const msg = e?.response?.data?.message || 'Verification failed. Try again.';
      toast.error(msg);
      setCode('');
    } finally {
      setVerifying(false);
    }
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const prevLabel = isMultiTenant ? 'Step 2 · Verify email' : 'Step 2 · Set password';

  // ── After-verify: backup codes panel ──────────────────────────────
  if (backupCodes) {
    return (
      <div className="mx-auto max-w-2xl">
        <div className="mb-6 flex justify-center">
</div>
        <div className="rounded-2xl border border-amber-200 bg-amber-50 p-6 shadow-xl dark:border-amber-700 dark:bg-amber-900/20">
          <div className="mb-4 flex items-start gap-3">
            <AlertTriangle className="mt-0.5 h-6 w-6 flex-shrink-0 text-amber-600 dark:text-amber-400" />
            <div>
              <h2 className="font-['League_Spartan'] text-2xl font-bold text-amber-900 dark:text-amber-200">
                Save your recovery codes
              </h2>
              <p className="mt-1 text-sm text-amber-800 dark:text-amber-300">
                Each code works once. Store them somewhere safe — a password manager, a printed
                copy in your shop safe, anywhere you can find them if you lose your phone. We
                won't show them again.
              </p>
            </div>
          </div>
          <div className="grid grid-cols-1 gap-x-6 gap-y-2 rounded-xl border border-amber-200 bg-white p-4 font-mono text-sm text-amber-900 sm:grid-cols-2 dark:border-amber-700 dark:bg-surface-900 dark:text-amber-200">
            {backupCodes.map((c) => (
              <code key={c} className="select-all">
                {c}
              </code>
            ))}
          </div>
          <button
            type="button"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(backupCodes.join('\n'));
                toast.success('Codes copied to clipboard');
              } catch {
                toast.error('Could not copy — select and copy manually');
              }
            }}
            className="mt-3 inline-flex items-center gap-1.5 text-xs font-medium text-amber-800 hover:underline dark:text-amber-300"
          >
            <Copy className="h-3.5 w-3.5" />
            Copy all codes
          </button>
          <label className="mt-5 flex items-center gap-2 text-sm text-amber-900 dark:text-amber-200">
            <input
              type="checkbox"
              checked={savedAck}
              onChange={(e) => setSavedAck(e.target.checked)}
              className="rounded border-amber-400 text-primary-600 focus:ring-primary-500"
            />
            I've saved these codes somewhere safe
          </label>
          <div className="mt-6 flex items-center justify-between">
            <button
              type="button"
              onClick={onBack}
              className="text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
            >
              ← Back
            </button>
            <button
              type="button"
              onClick={onNext}
              disabled={!savedAck}
              className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:pointer-events-none disabled:opacity-50"
            >
              I've saved these — continue
              <ShieldCheck className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    );
  }

  // ── Enrolment panel ───────────────────────────────────────────────
  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <ShieldCheck className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Set up two-factor
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Scan with Google Authenticator, Authy, or 1Password.
        </p>
      </div>

      <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {enrollError ? (
          <div className="mb-6 flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800 dark:border-red-800/40 dark:bg-red-900/20 dark:text-red-300">
            <AlertTriangle className="mt-0.5 h-5 w-5 flex-shrink-0" />
            <div>
              <p className="font-semibold">Couldn't start 2FA enrolment</p>
              <p className="mt-1">{enrollError}</p>
              <p className="mt-2">
                You can skip this step and turn on 2FA later from Settings → Security.
              </p>
            </div>
          </div>
        ) : null}

        <div className="grid grid-cols-1 gap-8 md:grid-cols-[220px_1fr]">
          {/* Left: QR code */}
          <div>
            <div className="flex aspect-square w-full items-center justify-center rounded-xl border border-surface-200 bg-white p-3 dark:border-surface-600 dark:bg-surface-700">
              {enrolling ? (
                <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
              ) : qrDataUrl ? (
                <img
                  src={qrDataUrl}
                  alt="Two-factor authentication QR code"
                  width={200}
                  height={200}
                  className="h-full w-full object-contain"
                />
              ) : (
                <Smartphone className="h-12 w-12 text-surface-300 dark:text-surface-500" />
              )}
            </div>
            <p className="mt-2 text-center text-xs text-surface-500 dark:text-surface-400">
              Scan with Authy / Google Authenticator / 1Password
            </p>
          </div>

          {/* Right: instructions + code input */}
          <div>
            <button
              type="button"
              onClick={() => setShowManual((v) => !v)}
              className="text-xs font-semibold uppercase tracking-wide text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
            >
              {showManual ? 'Hide manual entry' : 'Or enter manually'}
            </button>
            {showManual && secret ? (
              <div className="mt-2 flex items-center gap-2">
                <code className="flex-1 select-all break-all rounded bg-surface-100 p-2 font-mono text-sm text-surface-900 dark:bg-surface-700 dark:text-surface-100">
                  {secret}
                </code>
                <button
                  type="button"
                  onClick={handleCopySecret}
                  className="inline-flex items-center gap-1 rounded-md border border-surface-300 px-2 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-200 dark:hover:bg-surface-700"
                  aria-label="Copy secret"
                >
                  <Copy className="h-3.5 w-3.5" />
                  Copy
                </button>
              </div>
            ) : null}

            <label
              htmlFor="totp-code"
              className="mt-5 mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
            >
              6-digit code <span className="text-red-500">*</span>
            </label>
            <input
              id="totp-code"
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="000000"
              disabled={enrolling || verifying || !!enrollError}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center font-mono text-xl tracking-[0.4em] text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />

            <button
              type="button"
              onClick={handleVerify}
              disabled={enrolling || verifying || code.length !== 6 || !!enrollError}
              className="mt-4 flex w-full items-center justify-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:pointer-events-none disabled:opacity-50"
            >
              {verifying ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Verifying…
                </>
              ) : (
                <>
                  <ShieldCheck className="h-4 w-4" />
                  Verify and continue
                </>
              )}
            </button>
          </div>
        </div>

        <div className="mt-8 flex flex-col items-start justify-between gap-3 border-t border-surface-200 pt-5 sm:flex-row sm:items-center dark:border-surface-700">
          <button
            type="button"
            onClick={onBack}
            className="text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
          >
            ← Back
          </button>
          <div className="flex flex-col items-start gap-1 sm:items-end">
            <button
              type="button"
              onClick={handleSkip}
              className="text-sm font-medium text-surface-500 hover:text-surface-800 hover:underline dark:text-surface-400 dark:hover:text-surface-200"
            >
              Skip 2FA for now
            </button>
            <p className="max-w-xs text-xs text-amber-700 sm:text-right dark:text-amber-400">
              We strongly recommend enabling 2FA before using your shop in production.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepTwoFactorSetup;
