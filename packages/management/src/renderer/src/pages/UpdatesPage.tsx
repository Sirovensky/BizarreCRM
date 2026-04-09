import { useState, useEffect } from 'react';
import { Download, RefreshCw, Check, ArrowUpCircle } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import toast from 'react-hot-toast';

interface UpdateStatus {
  available: boolean;
  commitMessage?: string;
  currentCommit?: string;
  remoteCommit?: string;
  lastChecked?: string;
}

export function UpdatesPage() {
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [checking, setChecking] = useState(false);
  const [updating, setUpdating] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  useEffect(() => {
    getAPI().management.getUpdateStatus().then((res) => {
      if (res.success && res.data) setStatus(res.data as UpdateStatus);
    });
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
        toast.error(res.message ?? 'Check failed');
      }
    } catch {
      toast.error('Failed to check for updates');
    } finally {
      setChecking(false);
    }
  };

  const handleUpdate = async () => {
    setShowConfirm(false);
    setUpdating(true);
    try {
      const res = await getAPI().management.performUpdate();
      if (res.success) {
        toast.success('Update complete! Server restarting...');
        setStatus((prev) => prev ? { ...prev, available: false } : null);
      } else {
        toast.error(res.message ?? 'Update failed');
      }
    } catch {
      toast.error('Update failed');
    } finally {
      setUpdating(false);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
        <Download className="w-5 h-5 text-accent-400" />
        Updates
      </h1>

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
        message="This will pull the latest code, rebuild the frontend and server, and restart the service. There will be a brief downtime."
        confirmLabel="Update Now"
        onConfirm={handleUpdate}
        onCancel={() => setShowConfirm(false)}
      />
    </div>
  );
}
