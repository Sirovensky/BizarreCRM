import { useState, useEffect, useCallback, useMemo } from 'react';
import { AlertTriangle, RefreshCw, Trash2, RotateCw, TrendingUp, ChevronDown, ChevronRight } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { CrashEntry, CrashStats, DisabledRoute } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { Sparkline } from '@/components/Sparkline';
import { formatDateTime, formatRelativeTime } from '@/utils/format';
import { cn } from '@/utils/cn';
import toast from 'react-hot-toast';

export function CrashMonitorPage() {
  const [crashes, setCrashes] = useState<CrashEntry[]>([]);
  const [crashStats, setCrashStats] = useState<CrashStats | null>(null);
  const [disabledRoutes, setDisabledRoutes] = useState<DisabledRoute[]>([]);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const api = getAPI();
      const [crashRes, statsRes, routesRes] = await Promise.all([
        api.management.getCrashes(),
        api.management.getCrashStats(),
        api.management.getDisabledRoutes(),
      ]);
      // MGT-023: pipe each authenticated response through handleApiResponse
      // so a 401 (token expired) triggers auto-logout across all pages.
      if (handleApiResponse(crashRes)) return;
      if (handleApiResponse(statsRes)) return;
      if (handleApiResponse(routesRes)) return;
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
    if (handleApiResponse(res)) return;
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

  // Last 30 days crash rate — per-day bucket for a sparkline trend chart.
  // Uses crashes rather than crashStats because we need the per-event timestamps.
  const dailyCounts = useMemo(() => {
    const now = Date.now();
    const DAYS = 30;
    const buckets = new Array<number>(DAYS).fill(0);
    for (const c of crashes) {
      const t = new Date(c.timestamp).getTime();
      if (!isFinite(t)) continue;
      const dayIdx = DAYS - 1 - Math.floor((now - t) / (24 * 60 * 60 * 1000));
      if (dayIdx >= 0 && dayIdx < DAYS) buckets[dayIdx]++;
    }
    return buckets;
  }, [crashes]);

  // Group by route for the "top offending routes" bar — helps spot patterns.
  const topRoutes = useMemo(() => {
    const counts = new Map<string, number>();
    for (const c of crashes) {
      counts.set(c.route, (counts.get(c.route) ?? 0) + 1);
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5);
  }, [crashes]);

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-base lg:text-lg font-bold text-surface-100">Crash Monitor</h1>
        <div className="flex items-center gap-2">
          <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800 transition-colors">
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Stats row + per-day sparkline so the operator sees trend, not just
          a snapshot. Hour bucketing would be too noisy at low volume; days
          let a slow leak ("10 crashes/day for 2 weeks") be visible. */}
      {crashStats && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 md:gap-3">
          <div className="stat-card">
            <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1">Total crashes</div>
            <div className="text-lg lg:text-2xl font-bold text-surface-100">{crashStats.totalCrashes}</div>
          </div>
          <div className="stat-card">
            <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1">Disabled routes</div>
            <div className={cn('text-lg lg:text-2xl font-bold', crashStats.disabledCount > 0 ? 'text-red-400' : 'text-surface-100')}>
              {crashStats.disabledCount}
            </div>
          </div>
          <div className="stat-card">
            <div className="flex items-center justify-between mb-1">
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider">Last 30 days</div>
              <TrendingUp className="w-3 h-3 text-surface-500" />
            </div>
            <div className="flex items-end justify-between gap-2">
              <span className="text-lg lg:text-2xl font-bold text-surface-100">
                {dailyCounts.reduce((a, b) => a + b, 0)}
              </span>
              <div className="text-red-400/70 opacity-80">
                <Sparkline data={dailyCounts} width={64} height={22} fill />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Top offending routes — pattern-finding for repeated crashes. Skipped
          when there are fewer than 2 distinct routes; one route's count is
          already in the table below and the visualization wouldn't help. */}
      {topRoutes.length >= 2 && (
        <div>
          <h2 className="text-sm font-semibold text-surface-300 mb-2">Top offending routes</h2>
          <div className="space-y-1">
            {(() => {
              const maxCount = topRoutes[0][1];
              return topRoutes.map(([route, count]) => (
                <div key={route} className="flex items-center gap-2 text-xs">
                  <code className="font-mono text-amber-400 w-48 truncate" title={route}>{route}</code>
                  <div className="flex-1 h-5 bg-surface-900 border border-surface-800 rounded overflow-hidden">
                    <div
                      className="h-full bg-red-500/30 border-r border-red-500/60"
                      style={{ width: `${Math.max(5, (count / maxCount) * 100)}%` }}
                    />
                  </div>
                  <span className="font-mono text-surface-300 w-10 text-right">{count}</span>
                </div>
              ));
            })()}
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
                {recentCrashes.map((c) => {
                  const isOpen = expandedId === c.id;
                  return (
                    <>
                      <tr
                        key={c.id}
                        className="border-b border-surface-800/50 hover:bg-surface-800/30 cursor-pointer"
                        onClick={() => setExpandedId(isOpen ? null : c.id)}
                      >
                        <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">
                          <span className="inline-flex items-center gap-1">
                            {isOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                            {formatDateTime(c.timestamp)}
                          </span>
                        </td>
                        <td className="py-1.5 px-2 font-mono text-amber-400">{c.route}</td>
                        <td className="py-1.5 px-2 text-red-400 max-w-xs truncate" title={c.errorMessage}>{c.errorMessage}</td>
                        <td className="py-1.5 px-2">
                          <span className={cn(
                            'px-1.5 py-0.5 rounded text-[10px] font-medium',
                            c.type === 'uncaughtException' ? 'bg-red-900/40 text-red-300' : 'bg-amber-900/40 text-amber-300'
                          )}>
                            {c.type === 'uncaughtException' ? 'Exception' : 'Rejection'}
                          </span>
                          {c.recovered && (
                            <span className="ml-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-emerald-900/40 text-emerald-300">
                              recovered
                            </span>
                          )}
                        </td>
                      </tr>
                      {isOpen && (
                        <tr key={c.id + '-stack'} className="border-b border-surface-800">
                          <td colSpan={4} className="px-2 pb-2 pt-0">
                            <pre className="text-[11px] text-surface-400 bg-surface-950 border border-surface-800 rounded p-2 overflow-x-auto whitespace-pre-wrap break-all max-h-64 overflow-y-auto">
                              {c.errorStack || c.errorMessage || '(no stack captured)'}
                            </pre>
                          </td>
                        </tr>
                      )}
                    </>
                  );
                })}
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
