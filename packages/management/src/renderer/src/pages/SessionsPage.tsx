import { useState, useEffect, useCallback, useMemo } from 'react';
import { KeyRound, RefreshCw, XCircle, Clock, User } from 'lucide-react';
import { Link } from 'react-router-dom';
import { getAPI } from '@/api/bridge';
import { useAuthStore } from '@/stores/authStore';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { CopyText } from '@/components/CopyText';
import { formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

interface Session {
  id: string;
  username: string;
  ip_address: string;
  user_agent: string;
  created_at: string;
  expires_at: string;
}

/**
 * Short human-friendly relative string: "5m", "2h 14m", "3d". Used for
 * session duration and expiry-countdown chips.
 */
function compactDuration(ms: number): string {
  if (!isFinite(ms) || ms <= 0) return '—';
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  const rem = min % 60;
  if (hr < 24) return rem > 0 ? `${hr}h ${rem}m` : `${hr}h`;
  const day = Math.floor(hr / 24);
  const dh = hr % 24;
  return dh > 0 ? `${day}d ${dh}h` : `${day}d`;
}

/**
 * Shorten a user-agent string to a readable device/browser summary.
 * Strips the long Mozilla/X.Y preamble that dominates the raw UA but
 * keeps the name and version that operators actually care about.
 */
function shortUserAgent(ua: string | undefined): string {
  if (!ua) return '—';
  // Prefer the last parenthesised device segment when present (Electron
  // builds show "(Electron ...)" after the Chrome signature).
  const chrome = ua.match(/Chrome\/(\d+\.\d+)/);
  const electron = ua.match(/Electron\/(\d+\.\d+\.\d+)/);
  const firefox = ua.match(/Firefox\/(\d+\.\d+)/);
  const safari = ua.match(/Version\/(\d+\.\d+).+Safari/);
  if (electron) return `Electron ${electron[1]}`;
  if (chrome) return `Chrome ${chrome[1]}`;
  if (firefox) return `Firefox ${firefox[1]}`;
  if (safari) return `Safari ${safari[1]}`;
  return ua.slice(0, 48);
}

export function SessionsPage() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [loading, setLoading] = useState(true);
  const [revokeTarget, setRevokeTarget] = useState<Session | null>(null);
  const currentUsername = useAuthStore((s) => s.username);

  // Force a re-render once per 30s so countdown/duration chips tick.
  const [, forceTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => forceTick((t) => t + 1), 30_000);
    return () => clearInterval(id);
  }, []);

  const refresh = useCallback(async () => {
    try {
      const res = await getAPI().superAdmin.getSessions();
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
      toast.error(formatApiError(res));
    }
  };

  // Summary: expired-soon count to highlight rotation needs.
  const summary = useMemo(() => {
    const now = Date.now();
    let expiringSoon = 0;
    for (const s of sessions) {
      const ms = new Date(s.expires_at).getTime() - now;
      if (ms > 0 && ms < 15 * 60 * 1000) expiringSoon++;
    }
    return { expiringSoon };
  }, [sessions]);

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  const now = Date.now();

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-base lg:text-lg font-bold text-surface-100 flex items-center gap-2">
          <KeyRound className="w-5 h-5 text-accent-400" />
          Active Sessions ({sessions.length})
          {summary.expiringSoon > 0 && (
            <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-amber-950/60 text-amber-300 border border-amber-900/60">
              {summary.expiringSoon} expiring &lt;15m
            </span>
          )}
        </h1>
        <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {sessions.length === 0 ? (
        // DASH-ELEC-132: empty-state recovery cue — operator may have just revoked
        // their own session (no server-side self-revoke guard), and we don't want
        // them stuck on this page with no link back to the auth flow.
        <div className="text-center py-12 text-sm text-surface-500 space-y-2">
          <div>No active sessions</div>
          <Link to="/login" className="inline-block text-xs text-accent-400 hover:text-accent-300 underline">
            Back to Login
          </Link>
        </div>
      ) : (
        <div className="space-y-2">
          {sessions.map((s) => {
            const isSelf = currentUsername && s.username === currentUsername;
            const createdMs = new Date(s.created_at).getTime();
            const expiresMs = new Date(s.expires_at).getTime();
            const age = compactDuration(now - createdMs);
            const remaining = expiresMs > now ? compactDuration(expiresMs - now) : 'expired';
            const expiringSoon = expiresMs > now && expiresMs - now < 15 * 60 * 1000;
            return (
              <div
                key={s.id}
                className={`flex items-center justify-between gap-3 p-3 lg:p-4 rounded-lg border ${
                  isSelf ? 'border-accent-700/60 bg-accent-950/20' : 'border-surface-800 bg-surface-900'
                }`}
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm font-medium text-surface-200 inline-flex items-center gap-1">
                      <User className="w-3.5 h-3.5 text-surface-500" />
                      {s.username}
                    </span>
                    {isSelf && (
                      <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-accent-900/60 text-accent-300 border border-accent-800">
                        this is you
                      </span>
                    )}
                    <span className="text-[11px] text-surface-500 font-mono">
                      <CopyText value={s.ip_address}>{s.ip_address}</CopyText>
                    </span>
                    <span className="text-[11px] text-surface-500">{shortUserAgent(s.user_agent)}</span>
                  </div>
                  <div className="flex items-center gap-2 flex-wrap mt-1 text-[11px] text-surface-500">
                    <span className="inline-flex items-center gap-1" title={`Created ${formatDateTime(s.created_at)}`}>
                      <Clock className="w-3 h-3" />
                      age <span className="font-mono text-surface-400">{age}</span>
                    </span>
                    <span className="text-surface-700">·</span>
                    <span title={`Expires ${formatDateTime(s.expires_at)}`} className={expiringSoon ? 'text-amber-400' : ''}>
                      expires in <span className="font-mono">{remaining}</span>
                    </span>
                  </div>
                </div>
                <button
                  onClick={() => setRevokeTarget(s)}
                  className="flex-shrink-0 flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-red-400 border border-red-900/50 rounded-md hover:bg-red-950/40 transition-colors"
                  title={isSelf ? 'Revoking this session will log you out immediately' : undefined}
                >
                  <XCircle className="w-3 h-3" />
                  Revoke
                </button>
              </div>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={revokeTarget !== null}
        title="Revoke Session"
        message={
          revokeTarget && currentUsername && revokeTarget.username === currentUsername
            ? `This is YOUR current session. Revoking it will log you out immediately. Continue?`
            : `Revoke the session for "${revokeTarget?.username}"? They will be logged out immediately.`
        }
        danger confirmLabel="Revoke"
        onConfirm={handleRevoke}
        onCancel={() => setRevokeTarget(null)}
      />
    </div>
  );
}
