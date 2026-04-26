import { useState, useEffect } from 'react';
import { Download, RefreshCw, Check, ArrowUpCircle, Undo2, AlertTriangle } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

interface UpdateStatus {
  available: boolean;
  commitMessage?: string;
  currentCommit?: string;
  remoteCommit?: string;
  lastChecked?: string;
}

interface RollbackInfo {
  available: boolean;
  sha?: string;
}

export function UpdatesPage() {
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [statusLoading, setStatusLoading] = useState(true);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const [updating, setUpdating] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [rollback, setRollback] = useState<RollbackInfo>({ available: false });
  const [showRollbackConfirm, setShowRollbackConfirm] = useState(false);
  const [rollingBack, setRollingBack] = useState(false);

  useEffect(() => {
    // DASH-ELEC-034: explicit loading + error states so the page never renders nothing.
    getAPI().management.getUpdateStatus()
      .then((res) => {
        if (res.success && res.data) {
          setStatus(res.data as UpdateStatus);
        } else {
          setStatusError('Could not fetch update status from server.');
        }
      })
      .catch((err) => {
        console.warn('[UpdatesPage] getUpdateStatus failed', err);
        setStatusError('Server unreachable — check that the CRM server is running.');
      })
      .finally(() => setStatusLoading(false));
    // UP5: After a failed update, the dashboard reopens and sees the snapshot
    // left behind by the main process. Surface the rollback option.
    // MGT-028: If a snapshot exists (update was launched), record the audit
    // result so the server's audit log reflects the outcome of the update
    // attempt. We determine success by checking current server health via
    // getUpdateStatus (if the server responds, the new build is running).
    getAPI().management.getRollbackInfo()
      .then(async (res) => {
        if (res.success && res.data) {
          setRollback(res.data);
          // MGT-028: snapshot present → update was launched. Audit the result.
          if (res.data.available && res.data.sha) {
            // Optimistically check server health: if getUpdateStatus succeeds,
            // the server came back up — treat as success; otherwise failure.
            let updateSucceeded = false;
            try {
              const healthRes = await getAPI().management.getUpdateStatus();
              updateSucceeded = healthRes.success === true;
            } catch {
              updateSucceeded = false;
            }
            getAPI().management.auditUpdateResult({
              success: updateSucceeded,
              afterSha: undefined, // server resolves current HEAD server-side
            }).catch((err) => {
              console.warn('[UpdatesPage] auditUpdateResult failed', err);
            });
            // Clear the snapshot after auditing so we don't audit again next open.
            getAPI().management.clearRollback().catch(() => {/* best-effort */});
          }
        }
      })
      .catch((err) => console.warn('[UpdatesPage] getRollbackInfo failed', err));
  }, []);

  const handleCheck = async () => {
    setChecking(true);
    try {
      const res = await getAPI().management.checkUpdates();
      if (res.success && res.data) {
        setStatus(res.data as UpdateStatus);
        if ((res.data as UpdateStatus).available) {
          toast.success('Update available');
        } else {
          toast.success('Already up to date');
        }
      } else {
        toast.error(formatApiError(res));
      }
    } catch {
      toast.error('Update check failed');
    } finally {
      setChecking(false);
    }
  };

  const handleUpdate = async () => {
    setShowConfirm(false);
    setUpdating(true);
    try {
      const res = await getAPI().management.performUpdate();
      // UP4: The main process now returns { success: false, error, message }
      // when the spawn itself fails. Respect that before inspecting `data`.
      if (!res.success) {
        toast.error(formatApiError(res));
        return;
      }
      const result = res.data as { success?: boolean; output?: string } | undefined;
      if (result?.success) {
        toast.success('Update started. Dashboard will reopen after rebuild.');
        setStatus((prev) => (prev ? { ...prev, available: false } : null));
        if (result.output) console.log('[Update output]\n' + result.output);
      } else {
        toast.error('Update failed - check logs');
        if (result?.output) console.error('[Update output]\n' + result.output);
      }
    } catch (err) {
      toast.error('Update failed: ' + (err instanceof Error ? err.message : 'Unknown error'));
    } finally {
      setUpdating(false);
    }
  };

  const handleRollback = async () => {
    setShowRollbackConfirm(false);
    setRollingBack(true);
    try {
      const res = await getAPI().management.rollbackUpdate();
      if (res.success) {
        toast.success('Rolled back to previous commit. Restart the server to apply.');
        setRollback({ available: false });
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error('Rollback failed: ' + (err instanceof Error ? err.message : 'Unknown error'));
    } finally {
      setRollingBack(false);
    }
  };

  const handleDismissRollback = async () => {
    // @audit-fixed: previously the catch arm was missing — only a `finally`
    // that set local state. If `clearRollback` rejected (server down, disk
    // permissions on userData), the snapshot stayed on disk forever and the
    // dashboard would re-show the rollback banner on the next launch even
    // though the user had explicitly dismissed it. We now surface the
    // failure to the operator so they know the persisted snapshot is still
    // there and can manually delete it from the dashboard.log directory.
    try {
      const res = await getAPI().management.clearRollback();
      setRollback({ available: false });
      if (!res.success) {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      setRollback({ available: false });
      toast.error(
        err instanceof Error
          ? `Failed to clear rollback snapshot: ${err.message}`
          : 'Failed to clear rollback snapshot'
      );
    }
  };

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
        <Download className="w-5 h-5 text-accent-400" />
        Updates
      </h1>

      {/* DASH-ELEC-034: loading / error states */}
      {statusLoading && (
        <p className="text-sm text-surface-500 animate-pulse">Loading update status…</p>
      )}
      {!statusLoading && statusError && (
        <div className="flex items-start gap-3 p-4 rounded-lg bg-red-950/20 border border-red-900/50">
          <AlertTriangle className="w-4 h-4 mt-0.5 text-red-400 flex-shrink-0" />
          <p className="text-sm text-red-300">{statusError}</p>
        </div>
      )}

      {/* Rollback banner (UP5) — shown after a previous update was launched */}
      {rollback.available && rollback.sha && (
        <div className="p-4 rounded-lg border border-red-900/50 bg-red-950/20">
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="text-xs text-red-300 font-semibold mb-1 flex items-center gap-1.5">
                <Undo2 className="w-3.5 h-3.5" />
                Rollback available
              </div>
              <p className="text-sm text-surface-300">
                A previous update was launched from commit{' '}
                <span className="font-mono text-surface-200">{rollback.sha.slice(0, 8)}</span>.
                If the new build isn't working, you can restore that commit.
              </p>
            </div>
            <div className="flex gap-2 shrink-0">
              <button
                onClick={() => setShowRollbackConfirm(true)}
                disabled={rollingBack}
                className="px-3 py-2 text-xs font-semibold bg-red-600 text-white rounded-md hover:bg-red-700 disabled:opacity-50 transition-colors"
              >
                {rollingBack ? 'Rolling back...' : 'Roll back'}
              </button>
              <button
                onClick={handleDismissRollback}
                disabled={rollingBack}
                className="px-3 py-2 text-xs font-medium bg-surface-800 text-surface-300 border border-surface-700 rounded-md hover:bg-surface-700 disabled:opacity-50 transition-colors"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Current version */}
      <div className="stat-card !p-5">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[11px] text-surface-500 uppercase tracking-wider mb-1">Current Version</div>
            <div className="font-mono text-sm text-surface-200">
              {status?.currentCommit?.slice(0, 8) ?? 'Unknown'}
            </div>
          </div>
          {status?.available ? (
            <div className="flex items-center gap-2 text-amber-400">
              <ArrowUpCircle className="w-5 h-5" />
              <span className="text-sm font-medium">Update Available</span>
            </div>
          ) : (
            <div className="flex items-center gap-2 text-green-400">
              <Check className="w-5 h-5" />
              <span className="text-sm font-medium">Up to date</span>
            </div>
          )}
        </div>
      </div>

      {/* Update details */}
      {status?.available && status.commitMessage && (
        <div className="p-4 rounded-lg border border-amber-900/50 bg-amber-950/20">
          <div className="text-xs text-amber-400 font-medium mb-1">What's new:</div>
          <p className="text-sm text-surface-300">{status.commitMessage}</p>
        </div>
      )}

      {/* Action buttons */}
      <div className="flex gap-3">
        <button
          onClick={handleCheck}
          disabled={checking}
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium bg-surface-800 text-surface-200 border border-surface-700 rounded-lg hover:bg-surface-700 disabled:opacity-50 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 ${checking ? 'animate-spin' : ''}`} />
          {checking ? 'Checking...' : 'Check for Updates'}
        </button>
        <span className="self-center text-[11px] text-surface-600">Requires Git installed</span>

        {status?.available && (
          <button
            onClick={() => setShowConfirm(true)}
            disabled={updating}
            className="flex items-center gap-2 px-4 py-2.5 text-sm font-semibold bg-accent-600 text-white rounded-lg hover:bg-accent-700 disabled:opacity-50 transition-colors"
          >
            <Download className="w-4 h-4" />
            {updating ? 'Updating...' : 'Update Now'}
          </button>
        )}
      </div>

      {updating && (
        <div className="p-4 rounded-lg border border-accent-900/50 bg-accent-950/20">
          <div className="flex items-center gap-3">
            <RefreshCw className="w-4 h-4 text-accent-400 animate-spin" />
            <span className="text-sm text-accent-300">Pulling latest code, rebuilding, and restarting server...</span>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={showConfirm}
        title="Update Server"
        message={
          'This will:\n' +
          '  1. Record the current git commit so you can roll back if the update fails.\n' +
          '  2. Pull the latest code and rebuild the frontend and server.\n' +
          '  3. Kill the running server and the dashboard, then relaunch.\n\n' +
          'There will be a brief downtime (typically 30-90 seconds). If the build ' +
          'fails the dashboard will reopen with a "Roll back" option.\n\n' +
          'Do you want to continue?'
        }
        confirmLabel="Update Now"
        onConfirm={handleUpdate}
        onCancel={() => setShowConfirm(false)}
      />

      <ConfirmDialog
        open={showRollbackConfirm}
        title="Roll back update"
        message={
          `This will run 'git reset --hard ${rollback.sha?.slice(0, 8) ?? ''}' in the project directory. ` +
          'Any uncommitted changes will be lost. You will need to restart the server afterwards.'
        }
        confirmLabel="Roll back"
        onConfirm={handleRollback}
        onCancel={() => setShowRollbackConfirm(false)}
      />
    </div>
  );
}
