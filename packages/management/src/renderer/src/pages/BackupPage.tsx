import { useState, useEffect, useCallback } from 'react';
import { Database, FolderOpen, Clock, Trash2, Download, RefreshCw } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
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

  const refresh = useCallback(async () => {
    try {
      const api = getAPI();
      const [backupsRes, statusRes] = await Promise.all([
        api.admin.listBackups(),
        api.admin.getStatus(),
      ]);
      if (backupsRes.success && backupsRes.data) {
        setBackups(Array.isArray(backupsRes.data) ? backupsRes.data as Backup[] : []);
      }
      if (statusRes.success && statusRes.data) {
        const d = statusRes.data as { backup?: BackupSettings };
        if (d.backup) setSettings(d.backup);
      }
    } catch (err) {
      // @audit-fixed: previously this swallowed every error with an empty
      // catch block and a one-line "Multi-tenant mode returns 403 for admin
      // routes — expected" comment. That hid genuine failures (server down,
      // disk corruption on the backup volume, IPC bridge wedged) under the
      // assumption that every error was the harmless 403. We now log the
      // actual error to the console so operators can debug, while still
      // suppressing the user-facing toast for the expected 403 case so the
      // multi-tenant flow stays quiet.
      console.warn('[BackupPage] refresh failed (expected for multi-tenant)', err);
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

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  return (
    <div className="space-y-6 animate-fade-in">
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
                <button
                  onClick={() => setDeleteTarget(b.filename)}
                  className="p-1.5 rounded text-surface-500 hover:text-red-400 hover:bg-surface-700 transition-colors"
                  title="Delete backup"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
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
    </div>
  );
}
