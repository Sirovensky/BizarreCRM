import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Wrench, Unlock, Cloud, RefreshCw, AlertTriangle, CheckCircle2, XCircle, Lock, Key,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { CopyText } from '@/components/CopyText';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

interface RateLimitRow {
  db: string;
  id: number;
  category: string;
  key: string;
  count: number;
  first_attempt: number;
  locked_until: number | null;
}

interface ToolResult {
  ok: boolean;
  summary?: string;
  details?: Array<{ label: string; status: 'ok' | 'warn' | 'error'; message?: string }>;
}

export function AdminToolsPage() {
  const [resetScope, setResetScope] = useState<'all' | 'single'>('all');
  const [resetTenant, setResetTenant] = useState('');
  const [resetCategoriesAll, setResetCategoriesAll] = useState(false);
  const [resetBusy, setResetBusy] = useState(false);
  const [resetResult, setResetResult] = useState<ToolResult | null>(null);

  const [dnsBusy, setDnsBusy] = useState(false);
  const [dnsResult, setDnsResult] = useState<ToolResult | null>(null);

  const [jwtBusy, setJwtBusy] = useState(false);
  const [jwtPurpose, setJwtPurpose] = useState<'access' | 'refresh' | 'both'>('both');
  const [jwtAccess, setJwtAccess] = useState<string | null>(null);
  const [jwtRefresh, setJwtRefresh] = useState<string | null>(null);
  const [jwtInstructions, setJwtInstructions] = useState<string[] | null>(null);

  // DASH-ELEC-057: track which destructive action needs the current
  // super-admin TOTP code before the request leaves the renderer.
  const [confirmTarget, setConfirmTarget] = useState<null | 'reset' | 'rotateJwt' | 'backfillDns'>(null);
  const [stepUpTotpCode, setStepUpTotpCode] = useState('');
  const [stepUpError, setStepUpError] = useState<string | null>(null);

  // Rate-limit inspector
  const [rlRows, setRlRows] = useState<RateLimitRow[]>([]);
  const [rlSummary, setRlSummary] = useState<{ total: number; locked: number; dbsTouched: number } | null>(null);
  const [rlServerNow, setRlServerNow] = useState<number>(Date.now());
  const [rlLockedOnly, setRlLockedOnly] = useState(true);
  const [rlBusy, setRlBusy] = useState(false);

  const refreshRateLimits = useCallback(async () => {
    setRlBusy(true);
    try {
      const res = await getAPI().superAdmin.listRateLimits({ lockedOnly: rlLockedOnly, limit: 200 });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setRlRows(res.data.rows);
        setRlSummary(res.data.summary);
        setRlServerNow(res.data.now);
      }
    } catch (err) {
      console.warn('[AdminTools] listRateLimits failed', err);
    } finally {
      setRlBusy(false);
    }
  }, [rlLockedOnly]);

  useEffect(() => { refreshRateLimits(); }, [refreshRateLimits]);

  // DASH-ELEC-261: advance rlServerNow at 1 Hz so the countdown ticks even
  // when the operator leaves the page open and doesn't manually refresh.
  useEffect(() => {
    const id = setInterval(() => {
      setRlServerNow((t) => t + 1000);
    }, 1000);
    return () => clearInterval(id);
  }, []);

  function handleReset() {
    if (resetScope === 'single' && !/^[a-z0-9-]{1,64}$/.test(resetTenant)) {
      toast.error('Enter a valid tenant slug (lowercase, hyphens only).');
      return;
    }
    openStepUpChallenge('reset');
  }

  function openStepUpChallenge(target: 'reset' | 'rotateJwt' | 'backfillDns') {
    setStepUpTotpCode('');
    setStepUpError(null);
    setConfirmTarget(target);
  }

  function closeStepUpChallenge() {
    setConfirmTarget(null);
    setStepUpTotpCode('');
    setStepUpError(null);
  }

  function handleStepUpConfirm() {
    const code = stepUpTotpCode.trim();
    if (!/^\d{6}$/.test(code)) {
      setStepUpError('Enter the current 6-digit TOTP code.');
      return;
    }
    if (confirmTarget === 'reset') {
      performReset(code);
    } else if (confirmTarget === 'rotateJwt') {
      performRotateJwt(code);
    } else if (confirmTarget === 'backfillDns') {
      performBackfillDns(code);
    }
  }

  async function performReset(totpCode: string) {
    setConfirmTarget(null);
    setResetBusy(true);
    setResetResult(null);
    try {
      const res = await getAPI().superAdmin.resetRateLimits({
        tenantSlug: resetScope === 'single' ? resetTenant : undefined,
        all: resetCategoriesAll,
        totpCode,
      });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        // DASH-ELEC-272: ternary already narrows to the literal union; the
        // explicit `as` cast was redundant noise. TS infers correctly.
        const details = res.data.results.map((r): { label: string; status: 'ok' | 'warn' | 'error'; message: string } => ({
          label: r.dbLabel,
          status: r.error ? 'error' : r.skipped ? 'warn' : 'ok',
          message: r.error
            ? r.error
            : r.skipped
              ? 'no rate_limits table'
              : `${r.deleted} row${r.deleted === 1 ? '' : 's'} deleted`,
        }));
        setResetResult({
          ok: true,
          summary: `${res.data.totalDeleted} total row${res.data.totalDeleted === 1 ? '' : 's'} deleted across ${details.length} DB${details.length === 1 ? '' : 's'}`,
          details,
        });
        toast.success('Rate limits cleared');
        // Refresh the inspector so the operator sees the rows disappear immediately.
        refreshRateLimits();
      } else {
        setResetResult({ ok: false, summary: res.message ?? 'Reset failed' });
        toast.error(formatApiError(res));
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Reset failed';
      setResetResult({ ok: false, summary: msg });
      toast.error(msg);
    } finally {
      setResetBusy(false);
    }
  }

  function handleRotateJwt() {
    openStepUpChallenge('rotateJwt');
  }

  async function performRotateJwt(totpCode: string) {
    setConfirmTarget(null);
    setJwtBusy(true);
    try {
      const res = await getAPI().superAdmin.rotateJwtSecret(jwtPurpose, totpCode);
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setJwtAccess(res.data.nextJwtSecret ?? null);
        setJwtRefresh(res.data.nextJwtRefreshSecret ?? null);
        setJwtInstructions(res.data.instructions);
        toast.success('New secret(s) generated — copy before closing');
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'JWT rotation failed');
    } finally {
      setJwtBusy(false);
    }
  }

  function handleBackfillDns() {
    openStepUpChallenge('backfillDns');
  }

  async function performBackfillDns(totpCode: string) {
    setConfirmTarget(null);
    setDnsBusy(true);
    setDnsResult(null);
    try {
      const res = await getAPI().superAdmin.backfillCloudflareDns(totpCode);
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const { summary, rows } = res.data;
        // DASH-ELEC-272: drop redundant `as` cast — return-type annotation pins the union.
        const details = rows.map((r): { label: string; status: 'ok' | 'warn' | 'error'; message: string } => ({
          label: r.slug,
          status: r.status === 'error' ? 'error' : r.status === 'created' ? 'ok' : 'warn',
          message: r.message ?? (r.recordId ? `record_id ${r.recordId.slice(0, 12)}…` : r.status),
        }));
        setDnsResult({
          ok: true,
          summary: `${summary.created} created, ${summary.skipped} skipped, ${summary.errors} errors (of ${summary.total} active tenants)`,
          details,
        });
        toast.success(`DNS backfill complete (${summary.created} new records)`);
      } else {
        setDnsResult({ ok: false, summary: res.message ?? 'Backfill failed' });
        toast.error(formatApiError(res));
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Backfill failed';
      setDnsResult({ ok: false, summary: msg });
      toast.error(msg);
    } finally {
      setDnsBusy(false);
    }
  }

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in max-w-3xl">
      <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
        <Wrench className="w-5 h-5 text-accent-400" />
        Admin Tools
      </h1>
      <p className="text-xs text-surface-500 -mt-3">
        Operator-only maintenance scripts. Each call is gated by a step-up TOTP challenge
        and recorded in the master audit log.
      </p>

      {/* Rotate JWT secret */}
      <ToolCard
        icon={Key}
        iconColor="text-amber-400"
        title="Rotate JWT signing secret"
        description="Generates a new cryptographic key for signing session tokens. The server does not apply it automatically — paste the value into .env and restart. Use during incident response or regular rotation (SA1-1)."
      >
        <div className="space-y-3">
          <div className="flex items-center gap-2 text-xs flex-wrap">
            <span className="text-surface-500">Scope:</span>
            {(['access', 'refresh', 'both'] as const).map((p) => (
              <label key={p} className="inline-flex items-center gap-1 cursor-pointer text-surface-300">
                <input
                  type="radio"
                  name="jwt-purpose"
                  value={p}
                  checked={jwtPurpose === p}
                  onChange={() => setJwtPurpose(p)}
                  className="cursor-pointer"
                />
                <span>{p}</span>
              </label>
            ))}
          </div>
          <ActionButton onClick={handleRotateJwt} busy={jwtBusy} label="Generate new secret" busyLabel="Generating…" />
          {(jwtAccess || jwtRefresh) && (
            <div className="space-y-2 p-3 rounded border border-amber-900/60 bg-amber-950/30">
              <div className="flex items-start gap-2 text-xs text-amber-200">
                <AlertTriangle className="w-3.5 h-3.5 flex-shrink-0 mt-0.5" />
                <span>Shown ONCE. Copy before closing this panel. The server never stores these.</span>
              </div>
              {jwtAccess && (
                <div>
                  <div className="text-[10px] font-mono text-surface-500 uppercase tracking-wider mb-1">JWT_SECRET</div>
                  <div className="font-mono text-[11px] text-surface-200 break-all bg-surface-950 border border-surface-800 rounded p-2">
                    <CopyText value={jwtAccess} hideIconUntilHover={false}>{jwtAccess}</CopyText>
                  </div>
                </div>
              )}
              {jwtRefresh && (
                <div>
                  <div className="text-[10px] font-mono text-surface-500 uppercase tracking-wider mb-1">JWT_REFRESH_SECRET</div>
                  <div className="font-mono text-[11px] text-surface-200 break-all bg-surface-950 border border-surface-800 rounded p-2">
                    <CopyText value={jwtRefresh} hideIconUntilHover={false}>{jwtRefresh}</CopyText>
                  </div>
                </div>
              )}
              {jwtInstructions && (
                <ol className="text-[11px] text-surface-400 space-y-0.5 list-decimal pl-4">
                  {jwtInstructions.map((i, idx) => <li key={idx}>{i.replace(/^\d+\.\s*/, '')}</li>)}
                </ol>
              )}
            </div>
          )}
        </div>
      </ToolCard>

      {/* Rate-limit inspector */}
      <ToolCard
        icon={Lock}
        iconColor="text-violet-400"
        title="Rate-limit inspector"
        description="Read-only view of currently throttled keys across master + every active tenant DB. Use this before deciding whether the wholesale 'Reset rate limits' below is necessary, or to identify a single offending IP that just needs to wait out its lockout."
      >
        <div className="space-y-3">
          <div className="flex items-center gap-2 flex-wrap text-xs">
            <label className="flex items-center gap-2 cursor-pointer text-surface-300">
              <input
                type="checkbox"
                checked={rlLockedOnly}
                onChange={(e) => setRlLockedOnly(e.target.checked)}
                className="cursor-pointer"
              />
              <span>Locked only (skip cool-down counters)</span>
            </label>
            <button
              onClick={refreshRateLimits}
              disabled={rlBusy}
              className="ml-auto p-1 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800"
              title="Refresh"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${rlBusy ? 'animate-spin' : ''}`} />
            </button>
          </div>

          {rlSummary && (
            <div className="flex items-center gap-2 flex-wrap text-xs">
              <span className="px-2 py-0.5 rounded border border-surface-700 text-surface-300">
                <span className="font-mono">{rlSummary.total}</span>
                <span className="text-surface-500 ml-1">total</span>
              </span>
              <span className={`px-2 py-0.5 rounded border ${rlSummary.locked > 0 ? 'border-red-900/60 bg-red-950/30 text-red-300' : 'border-surface-700 text-surface-400'}`}>
                <span className="font-mono">{rlSummary.locked}</span>
                <span className="ml-1 opacity-80">locked now</span>
              </span>
              <span className="px-2 py-0.5 rounded border border-surface-700 text-surface-400">
                <span className="font-mono">{rlSummary.dbsTouched}</span>
                <span className="text-surface-500 ml-1">DBs</span>
              </span>
              {/* DASH-ELEC-137: server caps results at 200; surface this so the
                  operator knows the table isn't the whole picture when the
                  summary total exceeds what's actually rendered. */}
              {rlRows.length < rlSummary.total && (
                <span className="px-2 py-0.5 rounded border border-amber-900/60 bg-amber-950/30 text-amber-300">
                  Showing <span className="font-mono">{rlRows.length}</span> of{' '}
                  <span className="font-mono">{rlSummary.total}</span> — narrow filter to see more
                </span>
              )}
            </div>
          )}

          {rlRows.length === 0 ? (
            <p className="text-xs text-surface-500 py-2">
              {rlBusy ? 'Loading…' : rlLockedOnly ? 'No keys are currently locked.' : 'No rate-limit entries.'}
            </p>
          ) : (
            <div className="overflow-x-auto max-h-96 overflow-y-auto rounded border border-surface-800">
              <table className="w-full text-[11px]">
                <thead className="sticky top-0 bg-surface-900/80 backdrop-blur">
                  <tr>
                    <th className="text-left py-1.5 px-2 text-surface-500 font-medium">DB</th>
                    <th className="text-left py-1.5 px-2 text-surface-500 font-medium">Category</th>
                    <th className="text-left py-1.5 px-2 text-surface-500 font-medium">Key</th>
                    <th className="text-right py-1.5 px-2 text-surface-500 font-medium">Hits</th>
                    <th className="text-left py-1.5 px-2 text-surface-500 font-medium">Locked until</th>
                  </tr>
                </thead>
                <tbody>
                  {rlRows.map((r) => {
                    const lockedFor = r.locked_until ? r.locked_until - rlServerNow : 0;
                    const stillLocked = lockedFor > 0;
                    return (
                      <tr key={`${r.db}-${r.id}`} className="border-t border-surface-800/50 hover:bg-surface-800/30">
                        <td className="py-1 px-2 font-mono text-surface-400">{r.db}</td>
                        <td className="py-1 px-2 font-mono text-surface-300">{r.category}</td>
                        <td className="py-1 px-2 font-mono text-surface-200 break-all">{r.key}</td>
                        <td className="py-1 px-2 text-right text-surface-400 font-mono">{r.count}</td>
                        <td className="py-1 px-2 font-mono">
                          {stillLocked ? (
                            <span className="text-red-400">{Math.ceil(lockedFor / 1000)}s</span>
                          ) : r.locked_until ? (
                            <span className="text-surface-500">expired</span>
                          ) : (
                            <span className="text-surface-600">—</span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </ToolCard>

      {/* Reset rate limits */}
      <ToolCard
        icon={Unlock}
        iconColor="text-emerald-400"
        title="Reset rate limits"
        description="Clears the rate_limits table to unlock accounts that are stuck in login / TOTP / PIN cool-down. Use after a customer reports being locked out, or when the same IP is repeatedly throttled during legitimate testing."
      >
        <div className="space-y-3">
          <fieldset className="space-y-2">
            <legend className="text-xs text-surface-500 mb-1">Scope</legend>
            <label className="flex items-center gap-2 cursor-pointer text-sm text-surface-300">
              <input
                type="radio"
                name="reset-scope"
                value="all"
                checked={resetScope === 'all'}
                onChange={() => setResetScope('all')}
                className="cursor-pointer"
              />
              <span>All tenants + master DB</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer text-sm text-surface-300">
              <input
                type="radio"
                name="reset-scope"
                value="single"
                checked={resetScope === 'single'}
                onChange={() => setResetScope('single')}
                className="cursor-pointer"
              />
              <span>Single tenant</span>
              {/* DASH-ELEC-170 (Fixer-B27 2026-04-25): the previous handler ran
                  `.toLowerCase().trim()` on every keystroke. `.trim()` strips
                  any whitespace the user just typed, which causes the caret
                  to jump to the front of the field if they paste a value with
                  a leading space, and silently discards trailing whitespace
                  mid-edit before the user is finished. Whitespace handling is
                  now performed once at submit (`handleReset` already enforces
                  the `^[a-z0-9-]{1,64}$` regex). For per-keystroke normalisation
                  we only lowercase + strip internal whitespace, matching what
                  the slug regex permits without yanking the cursor. */}
              <input
                type="text"
                placeholder="tenant-slug"
                value={resetTenant}
                disabled={resetScope !== 'single'}
                onChange={(e) => setResetTenant(e.target.value.toLowerCase().replace(/\s/g, ''))}
                className="ml-2 px-2 py-1 text-xs bg-surface-950 border border-surface-700 rounded text-surface-200 disabled:opacity-40 font-mono w-48"
              />
            </label>
          </fieldset>
          <label className="flex items-center gap-2 cursor-pointer text-sm text-surface-300">
            <input
              type="checkbox"
              checked={resetCategoriesAll}
              onChange={(e) => setResetCategoriesAll(e.target.checked)}
              className="cursor-pointer"
            />
            <span>Wipe ALL categories</span>
            <span className="text-xs text-surface-500">(unchecked = auth-only: login_ip, login_user, totp, pin, setup, forgot_password)</span>
          </label>
          <ActionButton onClick={handleReset} busy={resetBusy} label="Reset rate limits" busyLabel="Resetting…" />
          <ResultPanel result={resetResult} />
        </div>
      </ToolCard>

      {/* Backfill DNS */}
      <ToolCard
        icon={Cloud}
        iconColor="text-orange-400"
        title="Backfill Cloudflare DNS"
        description="Idempotent — creates a Cloudflare DNS record for every active tenant that does not yet have a cloudflare_record_id in the master DB. Safe to re-run; tenants with an existing record id are skipped. Requires the Cloudflare credentials in Settings → Cloudflare DNS."
      >
        <ActionButton onClick={handleBackfillDns} busy={dnsBusy} label="Run backfill" busyLabel="Running…" />
        <ResultPanel result={dnsResult} />
      </ToolCard>

      {/* DASH-ELEC-057: preserve the confirmation copy, but require a fresh
          TOTP code before dispatching any destructive Admin Tools request. */}
      <StepUpConfirmDialog
        open={confirmTarget === 'reset'}
        title="Clear rate-limit rows?"
        message={
          resetScope === 'all'
            ? `This will clear rate-limit rows from the master DB and EVERY tenant DB. ${
                resetCategoriesAll ? 'ALL categories will be wiped.' : 'Only auth categories (login, totp, pin, etc).'
              }`
            : `Clear rate-limit rows for tenant "${resetTenant}"? ${
                resetCategoriesAll ? 'ALL categories.' : 'Only auth categories.'
              }`
        }
        confirmLabel="Clear rate limits"
        danger
        code={stepUpTotpCode}
        error={stepUpError}
        onCodeChange={(value) => {
          setStepUpTotpCode(value);
          setStepUpError(null);
        }}
        onConfirm={handleStepUpConfirm}
        onCancel={closeStepUpChallenge}
      />
      <StepUpConfirmDialog
        open={confirmTarget === 'rotateJwt'}
        title="Generate a new JWT secret?"
        message={
          `Generate a new JWT ${jwtPurpose === 'both' ? 'access + refresh' : jwtPurpose} secret. ` +
          'The new value is shown ONCE on this screen — copy it before closing. ' +
          'Paste into .env as the new primary and keep the old value as ' +
          '{JWT,JWT_REFRESH}_SECRET_PREVIOUS until existing sessions expire.'
        }
        confirmLabel="Generate secret"
        danger
        code={stepUpTotpCode}
        error={stepUpError}
        onCodeChange={(value) => {
          setStepUpTotpCode(value);
          setStepUpError(null);
        }}
        onConfirm={handleStepUpConfirm}
        onCancel={closeStepUpChallenge}
      />
      <StepUpConfirmDialog
        open={confirmTarget === 'backfillDns'}
        title="Backfill Cloudflare DNS records?"
        message={
          'Re-create Cloudflare DNS records for every active tenant that is missing one. ' +
          'Idempotent — tenants that already have a record_id are skipped.'
        }
        confirmLabel="Run backfill"
        code={stepUpTotpCode}
        error={stepUpError}
        onCodeChange={(value) => {
          setStepUpTotpCode(value);
          setStepUpError(null);
        }}
        onConfirm={handleStepUpConfirm}
        onCancel={closeStepUpChallenge}
      />
    </div>
  );
}

interface ToolCardProps {
  icon: React.ElementType;
  iconColor: string;
  title: string;
  description: string;
  children: React.ReactNode;
}

function ToolCard({ icon: Icon, iconColor, title, description, children }: ToolCardProps) {
  return (
    <section className="rounded-lg border border-surface-800 bg-surface-900/40 p-4 space-y-3">
      <div>
        <h2 className="text-sm font-semibold text-surface-200 flex items-center gap-2">
          <Icon className={`w-4 h-4 ${iconColor}`} />
          {title}
        </h2>
        <p className="text-xs text-surface-500 mt-1 leading-relaxed">{description}</p>
      </div>
      {children}
    </section>
  );
}

interface StepUpConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  danger?: boolean;
  code: string;
  error: string | null;
  onCodeChange: (value: string) => void;
  onConfirm: () => void;
  onCancel: () => void;
}

function StepUpConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  danger = false,
  code,
  error,
  onCodeChange,
  onConfirm,
  onCancel,
}: StepUpConfirmDialogProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const canConfirm = /^\d{6}$/.test(code.trim());

  useEffect(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => inputRef.current?.focus());
    return () => cancelAnimationFrame(frame);
  }, [open]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLDivElement>) => {
      if (e.key === 'Escape') {
        onCancel();
        return;
      }
      if (e.key === 'Enter' && canConfirm) {
        e.preventDefault();
        onConfirm();
        return;
      }
      if (e.key !== 'Tab') return;

      const el = containerRef.current;
      if (!el) return;
      const focusable = Array.from(
        el.querySelectorAll<HTMLElement>('button, input, [tabindex]:not([tabindex="-1"])')
      ).filter((n) => !n.hasAttribute('disabled'));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    },
    [canConfirm, onCancel, onConfirm],
  );

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm animate-fade-in">
      <div
        ref={containerRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="step-up-dialog-title"
        aria-describedby="step-up-dialog-message step-up-dialog-code-help"
        tabIndex={-1}
        className="w-[420px] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl p-6 outline-none"
        onKeyDown={handleKeyDown}
      >
        <div className="flex items-start gap-3 mb-4">
          {danger && <AlertTriangle className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />}
          <div>
            <h3 id="step-up-dialog-title" className="text-sm font-semibold text-surface-100">{title}</h3>
            <p id="step-up-dialog-message" className="text-sm text-surface-400 mt-3">{message}</p>
          </div>
        </div>

        <label htmlFor="step-up-totp-code" className="block text-xs text-surface-500 mb-2">
          Current super-admin TOTP code
        </label>
        <input
          ref={inputRef}
          id="step-up-totp-code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]*"
          maxLength={6}
          value={code}
          onChange={(e) => onCodeChange(e.target.value.replace(/\D/g, '').slice(0, 6))}
          aria-describedby="step-up-dialog-code-help"
          aria-invalid={error ? 'true' : 'false'}
          className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 font-mono tracking-[0.3em] focus:border-accent-500 focus:outline-none"
        />
        <p id="step-up-dialog-code-help" className={`text-xs mt-2 ${error ? 'text-red-300' : 'text-surface-500'}`}>
          {error ?? 'Required before this destructive action is sent to the server.'}
        </p>

        <div className="flex justify-end gap-2 mt-5">
          <button
            type="button"
            onClick={onCancel}
            className="px-4 py-2 text-sm text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={!canConfirm}
            className={
              danger
                ? 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors bg-red-600 text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:bg-red-800 disabled:text-red-200'
                : 'px-4 py-2 text-sm font-semibold rounded-lg transition-colors bg-accent-600 text-white hover:bg-accent-700 disabled:cursor-not-allowed disabled:opacity-50'
            }
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function ActionButton({
  onClick, busy, label, busyLabel,
}: { onClick: () => void; busy: boolean; label: string; busyLabel: string }) {
  return (
    <button
      onClick={onClick}
      disabled={busy}
      className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-accent-200 bg-accent-950/40 border border-accent-900/60 rounded hover:bg-accent-950/60 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
    >
      <RefreshCw className={`w-3.5 h-3.5 ${busy ? 'animate-spin' : ''}`} />
      {busy ? busyLabel : label}
    </button>
  );
}

function ResultPanel({ result }: { result: ToolResult | null }) {
  if (!result) return null;
  return (
    <div className={`rounded border p-3 ${result.ok ? 'border-emerald-900/50 bg-emerald-950/30' : 'border-red-900/50 bg-red-950/30'}`}>
      <div className={`text-xs font-medium ${result.ok ? 'text-emerald-300' : 'text-red-300'} flex items-center gap-2`}>
        {result.ok ? <CheckCircle2 className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
        {result.summary}
      </div>
      {result.details && result.details.length > 0 && (
        <div className="mt-2 space-y-1 text-[11px]">
          {result.details.map((d, idx) => (
            <div key={idx} className="flex items-center gap-2">
              {d.status === 'ok' && <CheckCircle2 className="w-3 h-3 text-emerald-500/80 flex-shrink-0" />}
              {d.status === 'warn' && <AlertTriangle className="w-3 h-3 text-amber-500/80 flex-shrink-0" />}
              {d.status === 'error' && <XCircle className="w-3 h-3 text-red-500/80 flex-shrink-0" />}
              <span className="font-mono text-surface-300">{d.label}</span>
              {d.message && <span className="text-surface-500">— {d.message}</span>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
