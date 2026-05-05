import { useState, useEffect, useCallback, useRef } from 'react';
import { Database, FolderOpen, Clock, Trash2, Download, RefreshCw, AlertTriangle, CheckCircle2, Undo2 } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { Sparkline } from '@/components/Sparkline';
import { formatDateTime, formatBytes } from '@/utils/format';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

interface Backup {
  filename: string;
  size: number;
  created: string;
}

/**
 * Server-side `listBackups()` returns rows shaped `{ name, size, date }`
 * (see packages/server/src/services/backup.ts:721). The renderer's
 * `Backup` interface uses `filename` / `created` instead. Previously the
 * page cast directly with `as Backup[]` — at runtime the rendered cells
 * read `b.filename` / `b.created` which were `undefined`, so the file
 * column showed empty text. This normalizer is the single source of the
 * shape conversion and applies to both single-tenant (`admin.*`) and
 * multi-tenant (`superAdmin.tenantBackup*`) responses.
 */
function normalizeBackupRow(row: { name?: string; filename?: string; size: number; date?: string; created?: string }): Backup {
  return {
    filename: row.filename ?? row.name ?? '',
    size: row.size,
    created: row.created ?? row.date ?? '',
  };
}

/**
 * Renderer-side shape after the IPC mapper in management-api.ts has
 * normalized the server's `{ path, retention, encrypt, lastBackup, lastStatus }`
 * into renderer-friendly snake_case. Pre-fix the page read `settings.path`
 * + `settings.lastRun` which never matched either shape and rendered as
 * 'Never' / blank for everyone. See rendererToServerBackupSettings /
 * serverToRendererBackupSettings in the IPC layer.
 */
interface BackupSettings {
  backup_path: string;
  schedule: string;
  retention_days: number;
  encryption_enabled?: boolean;
  last_backup?: string;
  last_status?: string;
}

interface TenantOption {
  slug: string;
  name: string;
  status: string;
}

export function BackupPage() {
  const [backups, setBackups] = useState<Backup[]>([]);
  const [settings, setSettings] = useState<BackupSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [backing, setBacking] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<string | null>(null);
  const [restoring, setRestoring] = useState(false);

  // Multi-tenant mode: super-admins manage backups per-tenant via the
  // /super-admin/api/tenants/:slug/backups routes (the tenant-scoped
  // /api/v1/admin/* path is intentionally hard-blocked in multi-tenant
  // mode so a tenant admin cannot enumerate filesystem drives or sibling
  // tenants). Tenant data export remains available to tenants via
  // /api/v1/data-export — backup files (encrypted, restorable) are not.
  const [isMultiTenant, setIsMultiTenant] = useState<boolean | null>(null);
  const [tenants, setTenants] = useState<TenantOption[]>([]);
  const [selectedSlug, setSelectedSlug] = useState<string | null>(null);

  // DASH-ELEC-256: guard setState calls after component unmounts (e.g. logout
  // while a 5-minute backup or restore is in-flight).
  const isMountedRef = useRef(true);
  useEffect(() => {
    isMountedRef.current = true;
    return () => { isMountedRef.current = false; };
  }, []);

  // Determine runtime mode + (in multi-tenant) load the tenant picker. Runs
  // once. The picker stays visible whenever isMultiTenant=true so operators
  // can switch between tenants without leaving the page.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const setup = await getAPI().management.setupStatus();
        if (cancelled) return;
        const multi = Boolean(setup.success && setup.data?.multiTenant);
        setIsMultiTenant(multi);
        if (multi) {
          const tres = await getAPI().superAdmin.listTenants();
          if (cancelled) return;
          if (tres.success && Array.isArray(tres.data)) {
            const opts = (tres.data as TenantOption[])
              .filter((t) => t.status === 'active' || t.status === 'suspended');
            setTenants(opts);
            if (opts.length > 0) setSelectedSlug(opts[0].slug);
          }
        }
      } catch (err) {
        console.warn('[BackupPage] mode detection failed', err);
        // Fall through — single-tenant assumption + admin.* routes will
        // surface their own error if the server is unreachable.
        setIsMultiTenant(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const refresh = useCallback(async () => {
    try {
      const api = getAPI();
      // Branch by mode. Multi-tenant routes through super-admin.* + slug;
      // single-tenant uses the original admin.* path. In multi-tenant
      // before a slug is picked (very brief), fall through to a no-op so
      // we don't spuriously toast.
      if (isMultiTenant === true) {
        if (!selectedSlug) {
          if (isMountedRef.current) setLoading(false);
          return;
        }
        const [backupsRes, settingsRes] = await Promise.all([
          api.superAdmin.tenantBackupList(selectedSlug),
          api.superAdmin.tenantBackupSettingsGet(selectedSlug),
        ]);
        if (!isMountedRef.current) return;
        if (handleApiResponse(backupsRes) || handleApiResponse(settingsRes)) return;
        if (backupsRes.success && backupsRes.data) {
          setBackups(Array.isArray(backupsRes.data)
            ? (backupsRes.data as Array<Record<string, unknown>>).map((r) => normalizeBackupRow(r as never))
            : []);
        }
        if (settingsRes.success && settingsRes.data) {
          // Server-side getBackupSettings returns { path, schedule, retention, lastRun }
          setSettings(settingsRes.data as unknown as BackupSettings);
        }
      } else {
        const [backupsRes, statusRes] = await Promise.all([
          api.admin.listBackups(),
          api.admin.getStatus(),
        ]);
        if (!isMountedRef.current) return;
        if (handleApiResponse(backupsRes) || handleApiResponse(statusRes)) return;
        if (backupsRes.success && backupsRes.data) {
          setBackups(Array.isArray(backupsRes.data)
            ? (backupsRes.data as Array<Record<string, unknown>>).map((r) => normalizeBackupRow(r as never))
            : []);
        }
        if (statusRes.success && statusRes.data) {
          const d = statusRes.data as { backup?: BackupSettings };
          if (d.backup) setSettings(d.backup);
        }
      }
    } catch (err) {
      // AUDIT-MGT-013: a 403 from the tenant-scoped admin route used to be
      // expected here in multi-tenant mode; with the super-admin routing
      // above that error is no longer expected, so a 403 reaching here is
      // a real problem (super-admin session expired, etc.) and should toast.
      console.warn('[BackupPage] refresh failed', err);
      const msg = err instanceof Error ? err.message : 'Failed to load backup data';
      toast.error(`Backup: ${msg}`);
    } finally {
      if (isMountedRef.current) setLoading(false);
    }
  }, [isMultiTenant, selectedSlug]);

  // Re-run refresh whenever mode is determined or slug changes.
  useEffect(() => {
    if (isMultiTenant === null) return;
    refresh();
  }, [isMultiTenant, selectedSlug, refresh]);

  const handleBackupNow = async () => {
    setBacking(true);
    try {
      const res = isMultiTenant && selectedSlug
        ? await getAPI().superAdmin.tenantBackupRun(selectedSlug)
        : await getAPI().admin.runBackup();
      if (!isMountedRef.current) return;
      if (res.success) {
        toast.success('Backup completed');
        refresh();
      } else {
        toast.error(formatApiError(res));
      }
    } catch {
      if (isMountedRef.current) toast.error('Backup failed');
    } finally {
      if (isMountedRef.current) setBacking(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    const res = isMultiTenant && selectedSlug
      ? await getAPI().superAdmin.tenantBackupDelete(selectedSlug, deleteTarget)
      : await getAPI().admin.deleteBackup(deleteTarget);
    if (res.success) {
      toast.success('Backup deleted');
      setDeleteTarget(null);
      refresh();
    } else {
      toast.error(formatApiError(res));
    }
  };

  const handleRestore = async () => {
    if (!restoreTarget) return;
    setRestoring(true);
    try {
      const res = isMultiTenant && selectedSlug
        ? await getAPI().superAdmin.tenantBackupRestore(selectedSlug, restoreTarget)
        : await getAPI().admin.restoreBackup(restoreTarget);
      if (!isMountedRef.current) return;
      if (res.success) {
        toast.success(
          res.data?.safetyBackup
            ? `Restore complete. Pre-restore snapshot saved as ${res.data.safetyBackup}.`
            : 'Restore complete.',
          { duration: 8000 },
        );
        setRestoreTarget(null);
        // DASH-ELEC-138: restore swaps the master DB file and bounces the
        // server process; calling refresh() immediately races against the
        // bounce and shows the previous (now stale) backup list. Defer the
        // refresh by 2 s so the new server is up and the backup table has
        // been reopened against the restored DB. Operators see the toast
        // duration (8 s) cover the gap.
        setTimeout(() => { if (isMountedRef.current) refresh(); }, 2000);
      } else if (res.offline) {
        // DASH-ELEC-257: the server rebooted mid-restore (expected for large
        // restores that bounce the process). Surface a specific message so
        // the operator knows to wait rather than treating it as a hard failure.
        toast(
          'Restore sent — server may be restarting. Wait a moment, then refresh.',
          { icon: '⏳', duration: 10_000 },
        );
        setTimeout(() => { if (isMountedRef.current) refresh(); }, 5000);
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      if (isMountedRef.current) toast.error(err instanceof Error ? err.message : 'Restore failed');
    } finally {
      if (isMountedRef.current) setRestoring(false);
    }
  };

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  // Health: derive freshness band from the most recent backup. Use the
  // backup file's created timestamp if present (more authoritative than
  // settings.last_backup, which can be stale if the scheduler missed a
  // tick but a manual `Backup Now` ran).
  const lastBackupAt = backups.length > 0 ? backups[0].created : settings?.last_backup ?? null;
  const ageMs = lastBackupAt ? Math.max(0, Date.now() - new Date(lastBackupAt).getTime()) : Infinity;
  const ageHours = ageMs / (1000 * 60 * 60);
  const health: 'fresh' | 'stale' | 'overdue' | 'missing' =
    !lastBackupAt
      ? 'missing'
      : ageHours < 24 ? 'fresh' : ageHours < 72 ? 'stale' : 'overdue';
  const healthMeta: Record<typeof health, { label: string; color: string; icon: React.ElementType; description: string }> = {
    fresh: { label: 'Healthy', color: 'border-emerald-900/60 bg-emerald-950/30 text-emerald-300', icon: CheckCircle2,
      description: `Last backup completed ${humanAge(ageMs)} ago.` },
    stale: { label: 'Stale', color: 'border-amber-900/60 bg-amber-950/40 text-amber-300', icon: AlertTriangle,
      description: `Last backup is ${humanAge(ageMs)} old. Verify the schedule is still firing.` },
    overdue: { label: 'Overdue', color: 'border-red-900/60 bg-red-950/40 text-red-300', icon: AlertTriangle,
      description: `Last backup is ${humanAge(ageMs)} old — well past the 72h threshold. Run a manual backup now and check the scheduler logs.` },
    missing: { label: 'No backups', color: 'border-red-900/60 bg-red-950/40 text-red-300', icon: AlertTriangle,
      description: 'No backups have ever completed on this server. Run a manual backup before relying on this server.' },
  };
  const HealthIcon = healthMeta[health].icon;
  const totalSize = backups.reduce((a, b) => a + b.size, 0);
  // Most-recent first in the API; reverse for sparkline so size grows L→R.
  const sizeSeries = backups.slice(0, 30).map((b) => b.size).reverse();

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <Database className="w-5 h-5 text-accent-400" />
          Backups
        </h1>
        <div className="flex items-center gap-2">
          {/*
            Multi-tenant tenant picker. Visible only when the runtime is
            multi-tenant; super-admin has elevated access to manage every
            tenant's backups. Tenants themselves never reach this page in
            multi-tenant mode (they get the documented data-export flow
            via /api/v1/data-export instead).
          */}
          {isMultiTenant && tenants.length > 0 && (
            <select
              value={selectedSlug ?? ''}
              onChange={(e) => setSelectedSlug(e.target.value || null)}
              className="px-2 py-1.5 text-xs bg-surface-900 border border-surface-700 rounded-lg text-surface-200 focus:outline-none focus:border-accent-500"
              aria-label="Tenant"
            >
              {tenants.map((t) => (
                <option key={t.slug} value={t.slug}>
                  {t.name} ({t.slug}){t.status !== 'active' ? ` — ${t.status}` : ''}
                </option>
              ))}
            </select>
          )}
          <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
            <RefreshCw className="w-4 h-4" />
          </button>
          <button
            onClick={handleBackupNow}
            disabled={backing || (isMultiTenant === true && !selectedSlug)}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium bg-accent-600 text-white rounded-lg hover:bg-accent-700 disabled:opacity-50"
          >
            <Download className="w-3.5 h-3.5" />
            {backing ? 'Backing up...' : 'Backup Now'}
          </button>
        </div>
      </div>
      {/*
        Show an explicit notice in multi-tenant mode so the operator
        knows the listed backups belong to the selected tenant only.
        Removes the surprise of "I clicked the menu item but where are
        the backups for the OTHER tenant?".
      */}
      {isMultiTenant && (
        <div className="text-xs text-surface-500">
          Managing backups for tenant <span className="font-mono text-surface-300">{selectedSlug ?? '—'}</span>.
          Switch tenants with the picker above. Tenant admins cannot access these files;
          tenants export their own data via the in-app data-export flow.
        </div>
      )}

      {/* Health banner */}
      <div className={`flex items-start gap-3 p-4 rounded-lg border ${healthMeta[health].color}`}>
        <HealthIcon className="w-5 h-5 flex-shrink-0 mt-0.5" />
        <div className="flex-1">
          <p className="text-sm font-medium">Backup status: {healthMeta[health].label}</p>
          <p className="text-xs opacity-80 mt-1">{healthMeta[health].description}</p>
        </div>
        {sizeSeries.length >= 2 && (
          <div className="opacity-70">
            <Sparkline data={sizeSeries} width={120} height={32} fill />
          </div>
        )}
      </div>

      {/* Aggregates */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <div className="stat-card">
          <div className="text-[11px] text-surface-500 uppercase tracking-wider mb-2">Total backups</div>
          <div className="text-2xl font-bold text-surface-100">{backups.length}</div>
        </div>
        <div className="stat-card">
          <div className="text-[11px] text-surface-500 uppercase tracking-wider mb-2">Total disk used</div>
          <div className="text-2xl font-bold text-surface-100">{formatBytes(totalSize)}</div>
        </div>
        <div className="stat-card">
          <div className="text-[11px] text-surface-500 uppercase tracking-wider mb-2">Latest size</div>
          <div className="text-2xl font-bold text-surface-100">
            {backups[0] ? formatBytes(backups[0].size) : '—'}
          </div>
        </div>
      </div>

      {/* Settings summary */}
      {settings && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <div className="stat-card">
            <div className="flex items-center gap-2 mb-2">
              <FolderOpen className="w-4 h-4 text-surface-500" />
              <span className="text-[11px] text-surface-500 uppercase tracking-wider">Backup Path</span>
            </div>
            <div className="text-xs font-mono text-surface-300 truncate">{settings.backup_path || 'Not configured'}</div>
          </div>
          <div className="stat-card">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="w-4 h-4 text-surface-500" />
              <span className="text-[11px] text-surface-500 uppercase tracking-wider">Schedule</span>
            </div>
            <div className="text-xs text-surface-300">{settings.schedule || 'Not scheduled'}</div>
          </div>
          <div className="stat-card">
            <div className="flex items-center gap-2 mb-2">
              <Database className="w-4 h-4 text-surface-500" />
              <span className="text-[11px] text-surface-500 uppercase tracking-wider">Last Backup</span>
            </div>
            <div className="text-xs text-surface-300">{settings.last_backup ? formatDateTime(settings.last_backup) : 'Never'}</div>
          </div>
        </div>
      )}

      {/* Backup list */}
      <div>
        <h2 className="text-sm font-semibold text-surface-300 mb-3">Backup History</h2>
        {backups.length === 0 ? (
          <div className="text-center py-8 text-sm text-surface-500">No backups found</div>
        ) : (
          <div className="space-y-2">
            {backups.map((b) => (
              <div key={b.filename} className="flex items-center justify-between p-3 rounded-lg border border-surface-800 bg-surface-900 hover:bg-surface-800/60 transition-colors">
                <div>
                  <div className="font-mono text-xs text-surface-200">{b.filename}</div>
                  <div className="text-xs text-surface-500 mt-0.5">
                    {formatBytes(b.size)} | {formatDateTime(b.created)}
                  </div>
                </div>
                <div className="flex items-center gap-1 flex-shrink-0">
                  <button
                    onClick={() => setRestoreTarget(b.filename)}
                    className="p-1.5 rounded text-surface-500 hover:text-amber-400 hover:bg-surface-700 transition-colors"
                    title="Restore from this backup (current DB is safety-copied first)"
                  >
                    <Undo2 className="w-3.5 h-3.5" />
                  </button>
                  <button
                    onClick={() => setDeleteTarget(b.filename)}
                    className="p-1.5 rounded text-surface-500 hover:text-red-400 hover:bg-surface-700 transition-colors"
                    title="Delete Backup"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <ConfirmDialog
        open={deleteTarget !== null}
        title="Delete Backup"
        message={`Permanently delete "${deleteTarget}"? This cannot be undone.`}
        danger confirmLabel="Delete"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />

      {/*
        DASH-ELEC-130 (Fixer-B26 2026-04-25): suppress onCancel while a
        restore is in flight so the operator can't dismiss the dialog
        (Cancel/Escape/X) and re-trigger another concurrent DB swap from
        the underlying list.

        DASH-ELEC-174 (Fixer-B27 2026-04-25): pair the cancel-suppression
        above with the new `disabled` prop on ConfirmDialog so the primary
        Confirm button is also locked while `restoring` is true. Previously
        the button only de-activated when typing-mismatched, so a mid-
        restore re-click of "Restore" (the typing field still matches the
        filename) would fire `handleRestore` a second time and stack
        concurrent DB swaps. Now `disabled={restoring}` flips `canConfirm`
        false, the button paints with `disabled:cursor-not-allowed`, and
        the click is a no-op until the finally-block clears the flag.
      */}
      <ConfirmDialog
        open={restoreTarget !== null}
        title="Restore backup"
        message={
          `Replace the current database with "${restoreTarget}"?\n\n` +
          `The server will safety-copy the current DB before swapping in. ` +
          `Active tenant sessions may see a brief outage while the switch happens. ` +
          `Type the filename below to confirm.`
        }
        danger
        requireTyping={restoreTarget ?? undefined}
        confirmLabel={restoring ? 'Restoring…' : 'Restore'}
        disabled={restoring}
        onConfirm={handleRestore}
        onCancel={() => { if (!restoring) setRestoreTarget(null); }}
      />
    </div>
  );
}

/** Human-readable elapsed time. "5m", "2h", "1d", "3d 4h" — short on purpose. */
function humanAge(ms: number): string {
  if (!isFinite(ms) || ms < 0) return 'unknown';
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h`;
  const day = Math.floor(hr / 24);
  const remHr = hr % 24;
  return remHr > 0 ? `${day}d ${remHr}h` : `${day}d`;
}
