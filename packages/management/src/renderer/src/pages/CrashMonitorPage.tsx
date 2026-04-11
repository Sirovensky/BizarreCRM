import { useState, useEffect, useCallback } from 'react';
import { AlertTriangle, RefreshCw, Trash2, RotateCw } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { CrashEntry, CrashStats, DisabledRoute } from '@/api/bridge';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { formatDateTime, formatRelativeTime } from '@/utils/format';
import { cn } from '@/utils/cn';
import toast from 'react-hot-toast';

export function CrashMonitorPage() {
  const [crashes, setCrashes] = useState<CrashEntry[]>([]);
  const [crashStats, setCrashStats] = useState<CrashStats | null>(null);
  const [disabledRoutes, setDisabledRoutes] = useState<DisabledRoute[]>([]);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    try {
      const api = getAPI();
      const [crashRes, statsRes, routesRes] = await Promise.all([
        api.management.getCrashes(),
        api.management.getCrashStats(),
        api.management.getDisabledRoutes(),
      ]);
      if (crashRes.success && crashRes.data) setCrashes(crashRes.data as CrashEntry[]);
      if (statsRes.success && statsRes.data) setCrashStats(statsRes.data as CrashStats);
      if (routesRes.success && routesRes.data) setDisabledRoutes(routesRes.data as DisabledRoute[]);
    } catch {
      toast.error('Failed to load crash data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    const interval = setInterval(refresh, 30_000);
    return () => clearInterval(interval);
  }, [refresh]);

  const handleReenableRoute = async (route: string) => {
    const res = await getAPI().management.reenableRoute(route);
    if (res.success) {
      toast.success('Route re-enabled');
      refresh();
    } else {
      toast.error(res.message ?? 'Failed');
    }
  };

  const handleClearCrashes = async () => {
    // @audit-fixed: previously this lied — it called clearCrashes() and then
    // unconditionally cleared local state and showed a success toast even
    // when the IPC failed (server offline, route disabled, auth expired).
    // Now we respect the response shape and only clear/notify on real success.
    try {
      const res = await getAPI().management.clearCrashes();
      if (res.success) {
        setCrashes([]);
        setCrashStats(null);
        setShowClearConfirm(false);
        toast.success('Crash log cleared');
      } else {
        toast.error(res.message ?? 'Failed to clear crash log');
        setShowClearConfirm(false);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to clear crash log');
      setShowClearConfirm(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <RefreshCw className="w-5 h-5 text-surface-500 animate-spin" />
      </div>
    );
  }

  const recentCrashes = [...crashes].reverse().slice(0, 50);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-bold text-surface-100">Crash Monitor</h1>
        <div className="flex items-center gap-2">
          <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800 transition-colors">
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Stats row */}
      {crashStats && (
        <div className="flex gap-4">
          <div className="stat-card flex-1">
            <div className="text-[11px] text-surface-500 uppercase tracking-wider mb-1">Total Crashes</div>
            <div className="text-2xl font-bold text-surface-100">{crashStats.totalCrashes}</div>
          </div>
          <div className="stat-card flex-1">
            <div className="text-[11px] text-surface-500 uppercase tracking-wider mb-1">Disabled Routes</div>
            <div className={cn('text-2xl font-bold', crashStats.disabledCount > 0 ? 'text-red-400' : 'text-surface-100')}>
              {crashStats.disabledCount}
            </div>
          </div>
        </div>
      )}

      {/* Disabled Routes */}
      {disabledRoutes.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold text-red-400 mb-3 flex items-center gap-2">
            <AlertTriangle className="w-4 h-4" />
            Disabled Routes ({disabledRoutes.length})
          </h2>
          <div className="space-y-2">
            {disabledRoutes.map((r) => (
              <div key={r.route} className="flex items-center justify-between p-3 rounded-lg border border-red-900/50 bg-red-950/20">
                <div>
                  <div className="font-mono text-sm text-red-300">{r.route}</div>
                  <div className="text-xs text-surface-500 mt-1">
                    Disabled {formatRelativeTime(r.disabledAt)} | {r.crashCount} crashes | {r.lastError.slice(0, 80)}
                  </div>
                </div>
                <button
                  onClick={() => handleReenableRoute(r.route)}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors"
                >
                  <RotateCw className="w-3 h-3" />
                  Re-enable
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Crash Log */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-sm font-semibold text-surface-300">Crash Log</h2>
          {crashes.length > 0 && (
            <button
              onClick={() => setShowClearConfirm(true)}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs text-surface-400 border border-surface-700 rounded-md hover:bg-surface-800 transition-colors"
            >
              <Trash2 className="w-3 h-3" />
              Clear
            </button>
          )}
        </div>

        {recentCrashes.length === 0 ? (
          <div className="text-center py-8 text-sm text-surface-500">No crashes recorded</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-surface-800">
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Time</th>
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Route</th>
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Error</th>
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Type</th>
                </tr>
              </thead>
              <tbody>
                {recentCrashes.map((c) => (
                  <tr key={c.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                    <td className="py-2 px-3 text-surface-500 whitespace-nowrap">{formatDateTime(c.timestamp)}</td>
                    <td className="py-2 px-3 font-mono text-amber-400">{c.route}</td>
                    <td className="py-2 px-3 text-red-400 max-w-xs truncate" title={c.errorMessage}>{c.errorMessage}</td>
                    <td className="py-2 px-3">
                      <span className={cn(
                        'px-1.5 py-0.5 rounded text-[10px] font-medium',
                        c.type === 'uncaughtException' ? 'bg-red-900/40 text-red-300' : 'bg-amber-900/40 text-amber-300'
                      )}>
                        {c.type === 'uncaughtException' ? 'Exception' : 'Rejection'}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <ConfirmDialog
        open={showClearConfirm}
        title="Clear Crash Log"
        message="This will permanently delete all crash entries. This cannot be undone."
        confirmLabel="Clear Log"
        danger
        onConfirm={handleClearCrashes}
        onCancel={() => setShowClearConfirm(false)}
      />
    </div>
  );
}
