import { useState, useEffect, useCallback } from 'react';
import { Database, FolderOpen, Clock, Trash2, Download, RefreshCw, AlertTriangle, CheckCircle2, Undo2 } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { Sparkline } from '@/components/Sparkline';
import { formatDateTime, formatBytes } from '@/utils/format';
import toast from 'react-hot-toast';

interface Backup {
  filename: string;
  size: number;
  created: string;
}

interface BackupSettings {
  path: string;
  schedule: string;
  retention: number;
  lastRun: string | null;
}

export function BackupPage() {
  const [backups, setBackups] = useState<Backup[]>([]);
  const [settings, setSettings] = useState<BackupSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [backing, setBacking] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<string | null>(null);
  const [restoring, setRestoring] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const api = getAPI();
      const [backupsRes, statusRes] = await Promise.all([
        api.admin.listBackups(),
        api.admin.getStatus(),
      ]);
      // AUDIT-MGT-010: detect 401 on either response and trigger global auto-logout.
      if (handleApiResponse(backupsRes) || handleApiResponse(statusRes)) return;
      if (backupsRes.success && backupsRes.data) {
        setBackups(Array.isArray(backupsRes.data) ? backupsRes.data as Backup[] : []);
      }
      if (statusRes.success && statusRes.data) {
        const d = statusRes.data as { backup?: BackupSettings };
        if (d.backup) setSettings(d.backup);
      }
    } catch (err) {
      // AUDIT-MGT-013: Differentiate expected 403 (multi-tenant mode disables
      // admin backup routes) from genuine failures (server down, disk error,
      // IPC bridge wedged). Expected 403 is suppressed silently; anything else
      // surfaces as a user-visible toast so operators know something is wrong.
      const isExpected =
        (err as { response?: { status?: number } }).response?.status === 403 ||
        (err instanceof Error &&
          (err.message.includes('FORBIDDEN') || err.message.includes('multi-tenant')));

      console.warn('[BackupPage] refresh failed', err);

      if (!isExpected) {
        const msg = err instanceof Error ? err.message : 'Failed to load backup data';
        toast.error(`Backup: ${msg}`);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  const handleBackupNow = async () => {
    setBacking(true);
    try {
      const res = await getAPI().admin.runBackup();
      if (res.success) {
        toast.success('Backup completed');
        refresh();
      } else {
        toast.error(res.message ?? 'Backup failed');
      }
    } catch {
      toast.error('Backup failed');
    } finally {
      setBacking(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    const res = await getAPI().admin.deleteBackup(deleteTarget);
    if (res.success) {
      toast.success('Backup deleted');
      setDeleteTarget(null);
      refresh();
    } else {
      toast.error(res.message ?? 'Failed');
    }
  };

  const handleRestore = async () => {
    if (!restoreTarget) return;
    setRestoring(true);
    try {
      const res = await getAPI().admin.restoreBackup(restoreTarget);
      if (res.success) {
        toast.success(
          res.data?.safetyBackup
            ? `Restore complete. Pre-restore snapshot saved as ${res.data.safetyBackup}.`
            : 'Restore complete.',
          { duration: 8000 },
        );
        setRestoreTarget(null);
        refresh();
      } else {
        toast.error(res.message ?? 'Restore failed');
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Restore failed');
    } finally {
      setRestoring(false);
    }
  };

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  // Health: derive freshness band from the most recent backup. Use the
  // backup file's created timestamp if present (more authoritative than
  // settings.lastRun, which can be stale if the scheduler missed a tick
  // but a manual `Backup Now` ran).
  const lastBackupAt = backups.length > 0 ? backups[0].created : settings?.lastRun ?? null;
  const ageMs = lastBackupAt ? Date.now() - new Date(lastBackupAt).getTime() : Infinity;
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
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <Database className="w-5 h-5 text-accent-400" />
          Backups
        </h1>
        <div className="flex items-center gap-2">
          <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
            <RefreshCw className="w-4 h-4" />
          </button>
          <button
            onClick={handleBackupNow}
            disabled={backing}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium bg-accent-600 text-white rounded-lg hover:bg-accent-700 disabled:opacity-50"
          >
            <Download className="w-3.5 h-3.5" />
            {backing ? 'Backing up...' : 'Backup Now'}
          </button>
        </div>
      </div>

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
      <div className="grid grid-cols-3 gap-3">
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
        <div className="grid grid-cols-3 gap-3">
          <div className="stat-card">
            <div className="flex items-center gap-2 mb-2">
              <FolderOpen className="w-4 h-4 text-surface-500" />
              <span className="text-[11px] text-surface-500 uppercase tracking-wider">Backup Path</span>
            </div>
            <div className="text-xs font-mono text-surface-300 truncate">{settings.path || 'Not configured'}</div>
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
            <div className="text-xs text-surface-300">{settings.lastRun ? formatDateTime(settings.lastRun) : 'Never'}</div>
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
                    title="Delete backup"
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
        onConfirm={handleRestore}
        onCancel={() => setRestoreTarget(null)}
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
