import { useState, useEffect, useCallback } from 'react';
import { KeyRound, RefreshCw, XCircle } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';

interface Session {
  id: string;
  username: string;
  ip_address: string;
  user_agent: string;
  created_at: string;
  expires_at: string;
}

export function SessionsPage() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [loading, setLoading] = useState(true);
  const [revokeTarget, setRevokeTarget] = useState<Session | null>(null);

  const refresh = useCallback(async () => {
    try {
      const res = await getAPI().superAdmin.getSessions();
      // AUDIT-MGT-010: detect 401 and trigger global auto-logout.
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const list = Array.isArray(res.data) ? res.data : (res.data as { sessions: Session[] }).sessions ?? [];
        setSessions(list as Session[]);
      }
    } catch {
      toast.error('Failed to load sessions');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  const handleRevoke = async () => {
    if (!revokeTarget) return;
    const res = await getAPI().superAdmin.revokeSession(revokeTarget.id);
    if (res.success) {
      toast.success('Session revoked');
      setRevokeTarget(null);
      refresh();
    } else {
      toast.error(res.message ?? 'Failed');
    }
  };

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <KeyRound className="w-5 h-5 text-accent-400" />
          Active Sessions ({sessions.length})
        </h1>
        <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {sessions.length === 0 ? (
        <div className="text-center py-12 text-sm text-surface-500">No active sessions</div>
      ) : (
        <div className="space-y-2">
          {sessions.map((s) => (
            <div key={s.id} className="flex items-center justify-between p-4 rounded-lg border border-surface-800 bg-surface-900">
              <div>
                <div className="text-sm font-medium text-surface-200">{s.username}</div>
                <div className="text-xs text-surface-500 mt-1 space-x-3">
                  <span>IP: {s.ip_address}</span>
                  <span>Created: {formatDateTime(s.created_at)}</span>
                  <span>Expires: {formatDateTime(s.expires_at)}</span>
                </div>
                <div className="text-xs text-surface-600 mt-0.5 truncate max-w-md">{s.user_agent}</div>
              </div>
              <button
                onClick={() => setRevokeTarget(s)}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-red-400 border border-red-900/50 rounded-md hover:bg-red-950/40 transition-colors"
              >
                <XCircle className="w-3 h-3" />
                Revoke
              </button>
            </div>
          ))}
        </div>
      )}

      <ConfirmDialog
        open={revokeTarget !== null}
        title="Revoke Session"
        message={`Revoke the session for "${revokeTarget?.username}"? They will be logged out immediately.`}
        danger confirmLabel="Revoke"
        onConfirm={handleRevoke}
        onCancel={() => setRevokeTarget(null)}
      />
    </div>
  );
}
