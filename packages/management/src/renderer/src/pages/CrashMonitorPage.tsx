import { Fragment, useState, useMemo } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { AlertTriangle, RefreshCw, Trash2, RotateCw, TrendingUp, ChevronDown, ChevronRight, Download } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { CrashEntry } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { Sparkline } from '@/components/Sparkline';
import { formatDateTime, formatRelativeTime } from '@/utils/format';
import { downloadCsv, toCsv } from '@/utils/csv';
import { cn } from '@/utils/cn';
import { managementQueryKeys } from '@/hooks/managementQueryKeys';
import { useCrashMonitorQuery } from '@/hooks/useManagementQueries';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

const STAT_CARD_CLASS = 'relative overflow-hidden rounded-lg border border-surface-800 bg-surface-900 p-3 lg:p-4 transition-colors hover:border-surface-700';
const ERROR_GROUP_PREFIX_LENGTH = 120;

interface CrashGroup {
  id: string;
  route: string;
  errorPrefix: string;
  count: number;
  latest: string;
  firstSeen: string;
  latestReport: CrashEntry;
  reports: CrashEntry[];
}

function timestampValue(timestamp: string) {
  const value = new Date(timestamp).getTime();
  return isFinite(value) ? value : 0;
}

function normalizeErrorMessagePrefix(message: string) {
  const normalized = (message || '(no message)')
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi, ':uuid')
    .replace(/\b[0-9a-f]{24,}\b/gi, ':hex')
    .replace(/\b\d{4,}\b/g, ':number');
  return (normalized || '(no message)').slice(0, ERROR_GROUP_PREFIX_LENGTH);
}

function capturedValue(value: string | undefined): string {
  return value && value.trim() ? value : 'Not captured';
}

function formatCrashSource(crash: CrashEntry): string {
  if (crash.source === 'dashboard') return 'Dashboard';
  if (crash.source === 'server') return 'Server';
  return 'Legacy row';
}

function formatCrashOs(context: CrashEntry['context']): string {
  const osContext = context?.os;
  const name = osContext?.type || osContext?.platform;
  const parts = [name, osContext?.release, osContext?.arch].filter((part): part is string => Boolean(part));
  return parts.length > 0 ? parts.join(' ') : 'Not captured';
}

function formatCrashApp(context: CrashEntry['context']): string {
  const appContext = context?.app;
  const version = capturedValue(appContext?.version);
  const name = appContext?.name ? `${appContext.name} ` : '';
  const packageState = typeof appContext?.isPackaged === 'boolean'
    ? ` (${appContext.isPackaged ? 'packaged' : 'dev'})`
    : '';
  return `${name}${version}${packageState}`;
}

function crashContextRows(crash: CrashEntry): Array<{ label: string; value: string }> {
  const context = crash.context;
  return [
    { label: 'Source', value: formatCrashSource(crash) },
    { label: 'OS', value: formatCrashOs(context) },
    { label: 'Node', value: capturedValue(context?.versions?.node) },
    { label: 'Electron', value: capturedValue(context?.versions?.electron) },
    { label: 'App build', value: formatCrashApp(context) },
  ];
}

export function CrashMonitorPage() {
  const queryClient = useQueryClient();
  const {
    data,
    isLoading,
    isFetching,
    isError,
    error,
    refetch,
  } = useCrashMonitorQuery();
  const crashes = data?.crashes ?? [];
  const crashStats = data?.crashStats ?? null;
  const disabledRoutes = data?.disabledRoutes ?? [];
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [expandedGroupId, setExpandedGroupId] = useState<string | null>(null);
  const [expandedReportId, setExpandedReportId] = useState<string | null>(null);

  // DASH-ELEC-071: show all toggle. MUST be declared above any early return
  // (e.g. the loading spinner branch below) — React hooks must be called in
  // the same order every render. Previous placement after the `if (loading)`
  // return triggered "Rendered more hooks than during the previous render"
  // and crashed the section under the ErrorBoundary on every first paint.
  const [showAll, setShowAll] = useState(false);

  const handleReenableRoute = async (route: string) => {
    const res = await getAPI().management.reenableRoute(route);
    if (handleApiResponse(res)) return;
    if (res.success) {
      toast.success('Route re-enabled');
      await queryClient.invalidateQueries({ queryKey: managementQueryKeys.crashMonitor() });
    } else {
      toast.error(formatApiError(res));
    }
  };

  const handleClearCrashes = async () => {
    // @audit-fixed: previously this lied — it called clearCrashes() and then
    // unconditionally cleared local state and showed a success toast even
    // when the IPC failed (server offline, route disabled, auth expired).
    // Now we respect the response shape and only clear/notify on real success.
    try {
      const res = await getAPI().management.clearCrashes();
      if (handleApiResponse(res)) return;
      if (res.success) {
        setShowClearConfirm(false);
        toast.success('Crash log cleared');
        setExpandedGroupId(null);
        setExpandedReportId(null);
        await queryClient.invalidateQueries({ queryKey: managementQueryKeys.crashMonitor() });
      } else {
        toast.error(formatApiError(res));
        setShowClearConfirm(false);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to clear crash log');
      setShowClearConfirm(false);
    }
  };

  // Last 30 days crash rate — per-day bucket for a sparkline trend chart.
  // Uses crashes rather than crashStats because we need the per-event timestamps.
  // MUST stay above the `if (loading)` early return so hook order is stable.
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
  // MUST stay above the `if (loading)` early return so hook order is stable.
  const topRoutes = useMemo(() => {
    const counts = new Map<string, number>();
    for (const c of crashes) {
      counts.set(c.route, (counts.get(c.route) ?? 0) + 1);
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5);
  }, [crashes]);

  const crashGroups = useMemo(() => {
    const groups = new Map<string, CrashGroup>();
    const newestFirst = [...crashes].sort((a, b) => timestampValue(b.timestamp) - timestampValue(a.timestamp));

    for (const crash of newestFirst) {
      const route = crash.route || '(unknown route)';
      const errorPrefix = normalizeErrorMessagePrefix(crash.errorMessage);
      const id = `${route}\u0000${errorPrefix.toLocaleLowerCase()}`;
      const existing = groups.get(id);

      if (!existing) {
        groups.set(id, {
          id,
          route,
          errorPrefix,
          count: 1,
          latest: crash.timestamp,
          firstSeen: crash.timestamp,
          latestReport: crash,
          reports: [crash],
        });
        continue;
      }

      existing.count += 1;
      existing.reports.push(crash);

      if (timestampValue(crash.timestamp) > timestampValue(existing.latest)) {
        existing.latest = crash.timestamp;
        existing.latestReport = crash;
      }
      if (timestampValue(crash.timestamp) < timestampValue(existing.firstSeen)) {
        existing.firstSeen = crash.timestamp;
      }
    }

    return [...groups.values()].sort((a, b) => timestampValue(b.latest) - timestampValue(a.latest));
  }, [crashes]);

  if (isLoading && !data) {
    return (
      <div className="flex items-center justify-center py-20">
        <RefreshCw className="w-5 h-5 text-surface-500 animate-spin" />
      </div>
    );
  }

  if (isError && !data) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 py-20 text-sm text-surface-400">
        <AlertTriangle className="w-5 h-5 text-amber-400" />
        <p>{error instanceof Error ? error.message : 'Failed to load crash data'}</p>
        <button
          onClick={() => { void refetch(); }}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs text-surface-300 border border-surface-700 rounded hover:bg-surface-800"
        >
          <RefreshCw className="w-3.5 h-3.5" />
          Retry
        </button>
      </div>
    );
  }

  // Plain derived values (no hooks) — safe below the early return.
  const visibleCrashGroups = showAll ? crashGroups : crashGroups.slice(0, 50);

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-base lg:text-lg font-bold text-surface-100">Crash Monitor</h1>
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              if (crashes.length === 0) { toast('No crashes to export'); return; }
              // Exclude errorStack: stacks may contain absolute paths, SQL
              // fragments with customer PII, and full request context.
              // The file is unencrypted on disk and may land in support
              // tickets — safer to omit by default (DASH-ELEC-118).
              const csvRows = crashes.map(({ timestamp, route, type, recovered, errorMessage }) => ({
                timestamp,
                route,
                type,
                recovered,
                errorMessage,
              }));
              const csv = toCsv(
                ['timestamp', 'route', 'type', 'recovered', 'errorMessage'],
                csvRows,
              );
              const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
              downloadCsv(`crashes-${stamp}.csv`, csv);
              toast.success(`Exported ${crashes.length} rows`);
            }}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs text-surface-400 border border-surface-700 rounded hover:bg-surface-800"
            title="Export all loaded crash entries to CSV"
          >
            <Download className="w-3.5 h-3.5" />
            Export CSV
          </button>
          <button onClick={() => { void refetch(); }} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800 transition-colors">
            <RefreshCw className={`w-4 h-4 ${isFetching ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* Stats row + per-day sparkline so the operator sees trend, not just
          a snapshot. Hour bucketing would be too noisy at low volume; days
          let a slow leak ("10 crashes/day for 2 weeks") be visible. */}
      {crashStats && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 md:gap-3">
          <div className={STAT_CARD_CLASS}>
            <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1">Total crashes</div>
            <div className="text-lg lg:text-2xl font-bold text-surface-100">{crashStats.totalCrashes}</div>
          </div>
          <div className={STAT_CARD_CLASS}>
            <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1">Disabled routes</div>
            <div className={cn('text-lg lg:text-2xl font-bold', crashStats.disabledCount > 0 ? 'text-red-400' : 'text-surface-100')}>
              {crashStats.disabledCount}
            </div>
          </div>
          <div className={STAT_CARD_CLASS}>
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
                  <code className="font-mono text-amber-400 max-w-[20rem] truncate" title={route}>{route}</code>
                  <div className="flex-1 h-5 bg-surface-900 border border-surface-800 rounded overflow-hidden">
                    <div
                      className="h-full bg-red-500/30 border-r border-red-500/60"
                      data-width-pct={Math.round(Math.max(5, (count / maxCount) * 100))}
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
                    Disabled <span title={formatDateTime(r.disabledAt)}>{formatRelativeTime(r.disabledAt)}</span> | {r.crashCount} crashes | {r.lastError.slice(0, 80)}
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
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold text-surface-300">Crash Log</h2>
            {/* DASH-ELEC-071: count label + show-all toggle */}
            {crashGroups.length > 50 && (
              <span className="text-xs text-surface-500">
                Showing {visibleCrashGroups.length} of {crashGroups.length} groups from {crashes.length} reports
              </span>
            )}
          </div>
          <div className="flex items-center gap-2">
            {crashGroups.length > 50 && (
              <button
                onClick={() => setShowAll(v => !v)}
                className="text-xs text-accent-400 hover:text-accent-300 transition-colors"
              >
                {showAll ? 'Show less' : 'Show all'}
              </button>
            )}
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
        </div>

        {visibleCrashGroups.length === 0 ? (
          <div className="text-center py-8 text-sm text-surface-500">No crashes recorded</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-surface-800">
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Latest</th>
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Route</th>
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Error</th>
                  <th className="text-left py-2 px-3 text-surface-500 font-medium">Reports</th>
                </tr>
              </thead>
              <tbody>
                {visibleCrashGroups.map((group) => {
                  const isGroupOpen = expandedGroupId === group.id;
                  return (
                    <Fragment key={group.id}>
                      {/* DASH-ELEC-065: tabIndex/role/onKeyDown for keyboard accessibility */}
                      <tr
                        className="border-b border-surface-800/50 hover:bg-surface-800/30 cursor-pointer focus:outline-none focus:bg-surface-800/50"
                        onClick={() => {
                          setExpandedGroupId(isGroupOpen ? null : group.id);
                          if (isGroupOpen) setExpandedReportId(null);
                        }}
                        tabIndex={0}
                        role="button"
                        aria-expanded={isGroupOpen}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' || e.key === ' ') {
                            e.preventDefault();
                            setExpandedGroupId(isGroupOpen ? null : group.id);
                            if (isGroupOpen) setExpandedReportId(null);
                          }
                        }}
                      >
                        <td className="py-1.5 px-2 text-surface-500 whitespace-nowrap">
                          <span className="inline-flex items-center gap-1">
                            {isGroupOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                            {formatDateTime(group.latest)}
                          </span>
                        </td>
                        <td className="py-1.5 px-2 font-mono text-amber-400">{group.route}</td>
                        <td className="py-1.5 px-2 text-red-400 max-w-xs">
                          <div className="truncate" title={group.errorPrefix}>{group.errorPrefix}</div>
                          <div className="mt-0.5 text-[10px] text-surface-500">
                            First seen <span title={formatDateTime(group.firstSeen)}>{formatRelativeTime(group.firstSeen)}</span>
                          </div>
                        </td>
                        <td className="py-1.5 px-2 whitespace-nowrap">
                          <span className="font-mono text-surface-200">{group.count}</span>
                          {group.latestReport.recovered && (
                            <span className="ml-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-emerald-900/40 text-emerald-300">
                              recovered
                            </span>
                          )}
                        </td>
                      </tr>
                      {isGroupOpen && group.reports.map((c) => {
                        const isReportOpen = expandedReportId === c.id;
                        return (
                          <Fragment key={c.id}>
                            <tr
                              className="border-b border-surface-800/30 bg-surface-950/40 hover:bg-surface-800/30 cursor-pointer focus:outline-none focus:bg-surface-800/50"
                              onClick={() => setExpandedReportId(isReportOpen ? null : c.id)}
                              tabIndex={0}
                              role="button"
                              aria-expanded={isReportOpen}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter' || e.key === ' ') {
                                  e.preventDefault();
                                  setExpandedReportId(isReportOpen ? null : c.id);
                                }
                              }}
                            >
                              <td className="py-1.5 px-2 pl-6 text-surface-500 whitespace-nowrap">
                                <span className="inline-flex items-center gap-1">
                                  {isReportOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
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
                            {isReportOpen && (
                              <tr className="border-b border-surface-800">
                                <td colSpan={4} className="px-2 pb-2 pt-0">
                                  <div className="mb-2 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
                                    {crashContextRows(c).map((row) => (
                                      <div key={row.label} className="rounded border border-surface-800 bg-surface-950 px-2 py-1.5">
                                        <div className="text-[10px] uppercase tracking-wider text-surface-500">{row.label}</div>
                                        <div className="mt-0.5 break-words font-mono text-[11px] text-surface-300">{row.value}</div>
                                      </div>
                                    ))}
                                  </div>
                                  {!c.context && (
                                    <div className="mb-2 rounded border border-amber-900/40 bg-amber-950/20 px-2 py-1.5 text-[11px] text-amber-200">
                                      Runtime context was not captured for this older crash row.
                                    </div>
                                  )}
                                  <pre className="text-[11px] text-surface-400 bg-surface-950 border border-surface-800 rounded p-2 overflow-x-auto whitespace-pre-wrap break-all max-h-64 overflow-y-auto">
                                    {c.errorStack || c.errorMessage || '(no stack captured)'}
                                  </pre>
                                </td>
                              </tr>
                            )}
                          </Fragment>
                        );
                      })}
                      {isGroupOpen && group.reports.length === 0 && (
                        <tr className="border-b border-surface-800">
                          <td colSpan={4} className="px-2 pb-2 pt-0 text-surface-500">
                            No reports in this group
                          </td>
                        </tr>
                      )}
                    </Fragment>
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
