import { useState } from 'react';
import {
  Wrench, Unlock, Cloud, RefreshCw, AlertTriangle, CheckCircle2, XCircle,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import toast from 'react-hot-toast';

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

  async function handleReset() {
    if (resetScope === 'single' && !/^[a-z0-9-]{1,64}$/.test(resetTenant)) {
      toast.error('Enter a valid tenant slug (lowercase, hyphens only).');
      return;
    }
    const proceed = window.confirm(
      resetScope === 'all'
        ? `Clear rate-limit rows from the master DB and EVERY tenant DB? ${
            resetCategoriesAll ? 'ALL categories will be wiped.' : 'Only auth categories (login, totp, pin, etc).'
          }`
        : `Clear rate-limit rows for tenant "${resetTenant}"? ${
            resetCategoriesAll ? 'ALL categories.' : 'Only auth categories.'
          }`
    );
    if (!proceed) return;
    setResetBusy(true);
    setResetResult(null);
    try {
      const res = await getAPI().superAdmin.resetRateLimits({
        tenantSlug: resetScope === 'single' ? resetTenant : undefined,
        all: resetCategoriesAll,
      });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const details = res.data.results.map((r) => ({
          label: r.dbLabel,
          status: (r.error ? 'error' : r.skipped ? 'warn' : 'ok') as 'ok' | 'warn' | 'error',
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
      } else {
        setResetResult({ ok: false, summary: res.message ?? 'Reset failed' });
        toast.error(res.message ?? 'Reset failed');
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Reset failed';
      setResetResult({ ok: false, summary: msg });
      toast.error(msg);
    } finally {
      setResetBusy(false);
    }
  }

  async function handleBackfillDns() {
    const proceed = window.confirm(
      'Re-create Cloudflare DNS records for every active tenant that is missing one? ' +
        'Idempotent — tenants that already have a record_id are skipped.'
    );
    if (!proceed) return;
    setDnsBusy(true);
    setDnsResult(null);
    try {
      const res = await getAPI().superAdmin.backfillCloudflareDns();
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const { summary, rows } = res.data;
        const details = rows.map((r) => ({
          label: r.slug,
          status: (r.status === 'error' ? 'error' : r.status === 'created' ? 'ok' : 'warn') as 'ok' | 'warn' | 'error',
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
        toast.error(res.message ?? 'Backfill failed');
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
    <div className="space-y-6 animate-fade-in max-w-3xl">
      <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
        <Wrench className="w-5 h-5 text-accent-400" />
        Admin Tools
      </h1>
      <p className="text-xs text-surface-500 -mt-3">
        Operator-only maintenance scripts. Each call is gated by a step-up TOTP challenge
        and recorded in the master audit log.
      </p>

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
              <input
                type="text"
                placeholder="tenant-slug"
                value={resetTenant}
                disabled={resetScope !== 'single'}
                onChange={(e) => setResetTenant(e.target.value.toLowerCase().trim())}
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
