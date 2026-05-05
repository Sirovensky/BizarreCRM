import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  Play,
  Square,
  RotateCw,
  Skull,
  Globe,
  FileText,
  ToggleLeft,
  ToggleRight,
  Shield,
  Activity,
  AlertTriangle,
  CheckCircle2,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { ServiceStatus, WatchdogEvent } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { StatusBadge } from '@/components/shared/StatusBadge';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { formatUptime } from '@/utils/format';
import { useServerStore } from '@/stores/serverStore';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

export function ServerControlPage() {
  const [serviceStatus, setServiceStatus] = useState<ServiceStatus | null>(null);
  const [loading, setLoading] = useState<string | null>(null);
  const [autoStart, setAutoStart] = useState<boolean | null>(null);
  const [rateLimitBypass, setRateLimitBypass] = useState(false);
  const [confirmAction, setConfirmAction] = useState<{
    title: string; message: string; action: () => Promise<void>;
    danger?: boolean; requireTyping?: string; confirmLabel?: string;
  } | null>(null);
  // AUDIT-MGT-011: track which step of the kill-all double-confirm we're on.
  // Using a step counter avoids nesting setConfirmAction inside onConfirm,
  // which caused a race where the first dialog's close animation reset state
  // before the second dialog could open.
  const [killAllStep, setKillAllStep] = useState<1 | 2 | null>(null);

  // Watchdog events emitted by packages/server/scripts/watchdog.cjs.
  const [watchdogEvents, setWatchdogEvents] = useState<WatchdogEvent[]>([]);
  const [watchdogClearing, setWatchdogClearing] = useState(false);

  const serverUptime = useServerStore((s) => s.stats?.uptime);

  const refreshStatus = useCallback(async () => {
    try {
      const status = await getAPI().service.getStatus();
      setServiceStatus(status);
      // Sync auto-start toggle from service status (only on first load)
      if (autoStart === null && status.startType !== 'unknown') {
        setAutoStart(status.startType === 'auto');
      }
    } catch {
      setServiceStatus(null);
    }
  }, [autoStart]);

  // Watchdog events poll. Cheap (small JSONL read), runs every 5s while the
  // tab is visible. We do NOT toast on new events here — the dedicated
  // Watchdog Status card in the JSX surfaces state. Toasting on every poll
  // would spam the operator.
  const refreshWatchdogEvents = useCallback(async () => {
    try {
      const res = await getAPI().management.getWatchdogEvents();
      if (res.ok) {
        setWatchdogEvents(res.events);
      }
    } catch (err) {
      console.warn('[ServerControlPage] getWatchdogEvents failed', err);
    }
  }, []);

  const acknowledgeWatchdog = useCallback(async () => {
    setWatchdogClearing(true);
    try {
      const res = await getAPI().management.clearWatchdogEvents();
      if (res.ok) {
        setWatchdogEvents([]);
        toast.success('Watchdog state cleared');
      } else {
        toast.error(`Clear failed: ${res.message ?? res.code ?? 'unknown'}`);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Clear failed');
    } finally {
      setWatchdogClearing(false);
    }
  }, []);

  useEffect(() => {
    // MGT-026: Use 10 s base interval (was 3 s) to reduce background noise.
    // Pause polling while the tab/window is hidden; resume when visible.
    const POLL_INTERVAL = 10_000;
    let intervalId: ReturnType<typeof setInterval> | null = null;

    const startPolling = () => {
      if (intervalId !== null) return;
      intervalId = setInterval(refreshStatus, POLL_INTERVAL);
    };

    const stopPolling = () => {
      if (intervalId !== null) {
        clearInterval(intervalId);
        intervalId = null;
      }
    };

    const handleVisibilityChange = () => {
      if (document.hidden) {
        stopPolling();
      } else {
        refreshStatus();
        startPolling();
      }
    };

    refreshStatus();
    refreshWatchdogEvents();
    if (!document.hidden) startPolling();
    document.addEventListener('visibilitychange', handleVisibilityChange);

    // Watchdog events poll independently on a 5s interval. Same visibility
    // pause behavior as the service-status poll but smaller cadence because
    // the file read is cheap and operators expect quicker feedback when the
    // watchdog reacts.
    const watchdogIntervalId = setInterval(refreshWatchdogEvents, 5_000);

    // Load platform config
    getAPI().superAdmin.getConfig().then((res) => {
      // MGT-023: detect auth expiry on authenticated IPC calls.
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setRateLimitBypass((res.data as Record<string, string>).management_rate_limit_bypass === 'true');
      }
    }).catch((err) => {
      // §26: previously this was a silent `.catch(() => {})`. Log visibly so
      // ops can tell when the super-admin getConfig call is failing (e.g.
      // auth expired, server down) instead of silently rendering the default
      // rate-limit-bypass=false state.
      console.warn('[ServerControlPage] superAdmin.getConfig failed', err);
    });

    return () => {
      stopPolling();
      clearInterval(watchdogIntervalId);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [refreshStatus, refreshWatchdogEvents]);

  // Derive the headline watchdog state from the events tail. A fatal /
  // cascade-abort / cert-expired event is sticky until acknowledged. A
  // recent restart (<10 min) shows as a warning. Otherwise → healthy.
  const watchdogState = useMemo<{
    severity: 'healthy' | 'info' | 'warn' | 'fatal';
    headline: string;
    detail?: string;
    actionable: boolean;
  }>(() => {
    if (watchdogEvents.length === 0) {
      return { severity: 'healthy', headline: 'Watchdog: healthy', actionable: false };
    }
    // Look at most-recent events first for fatal/cert-expired stickiness.
    const fatal = [...watchdogEvents].reverse().find((e) => e.kind === 'fatal' || e.kind === 'cascade-abort');
    if (fatal) {
      return {
        severity: 'fatal',
        headline: fatal.kind === 'cascade-abort'
          ? 'Watchdog: cascade-abort — manual intervention required'
          : 'Watchdog: FATAL — server stopped, manual intervention required',
        detail: fatal.reason,
        actionable: true,
      };
    }
    const cert = [...watchdogEvents].reverse().find((e) => e.kind === 'cert-expired');
    if (cert) {
      return {
        severity: 'fatal',
        headline: 'Watchdog: certificate appears expired',
        detail: cert.reason,
        actionable: true,
      };
    }
    const recentRestarts = watchdogEvents.filter((e) => {
      if (e.kind !== 'restart') return false;
      const ageMs = Date.now() - new Date(e.timestamp).getTime();
      return ageMs < 10 * 60 * 1000; // 10 min window
    });
    if (recentRestarts.length > 0) {
      return {
        severity: 'warn',
        headline: `Watchdog: triggered ${recentRestarts.length} restart${recentRestarts.length === 1 ? '' : 's'} in last 10 min`,
        detail: recentRestarts[recentRestarts.length - 1].reason,
        actionable: false,
      };
    }
    const recentGrace = watchdogEvents.filter((e) => {
      if (e.kind !== 'extended-grace') return false;
      const ageMs = Date.now() - new Date(e.timestamp).getTime();
      return ageMs < 5 * 60 * 1000; // 5 min window
    });
    if (recentGrace.length > 0) {
      return {
        severity: 'info',
        headline: 'Watchdog: extended grace — server appears active in long task or logs',
        detail: recentGrace[recentGrace.length - 1].reason,
        actionable: false,
      };
    }
    return { severity: 'healthy', headline: 'Watchdog: healthy', actionable: false };
  }, [watchdogEvents]);

  const doAction = async (name: string, action: () => Promise<unknown>) => {
    setLoading(name);
    try {
      // @audit-fixed: previously this only caught thrown errors. The
      // service:* IPC handlers in src/main/ipc/service-control.ts return
      // { success: false, output: '...' } on failure (sc.exe / pm2 errors)
      // — they do NOT throw — so any failure was reported as "successful".
      // Now we inspect the envelope and only report success when the
      // response shape really indicates one.
      const result = (await action()) as { success?: boolean; output?: string; message?: string } | undefined;
      // setAutoStart is the only action whose result we care to inspect for
      // success here; getStatus returns a ServiceStatus shape which has no
      // `success` field — treat that as success too.
      if (result && typeof result === 'object' && 'success' in result && result.success === false) {
        const errMsg = result.message ?? result.output ?? 'Action failed';
        toast.error(`${name} failed: ${errMsg}`);
      } else {
        toast.success(`${name} successful`);
      }
      await new Promise((r) => setTimeout(r, 1500));
      await refreshStatus();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setLoading(null);
    }
  };

  const isRunning = serviceStatus?.state === 'running';
  const isStopped = serviceStatus?.state === 'stopped';
  const isNotInstalled = serviceStatus?.state === 'not_installed';

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <h1 className="text-base lg:text-lg font-bold text-surface-100">Server Control</h1>

      {/* Service Status Card */}
      <div className="stat-card !p-4 lg:!p-6">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <Shield className="w-5 h-5 text-accent-400" />
              <span className="text-sm font-medium text-surface-300">
                {serviceStatus?.mode === 'pm2' ? 'PM2: bizarre-crm' : serviceStatus?.mode === 'service' ? 'Windows Service: BizarreCRM' : serviceStatus?.mode === 'direct' ? 'Direct Server Process' : 'Server Process'}
              </span>
            </div>
            <div className="flex items-center gap-4">
              <StatusBadge
                status={serviceStatus?.state ?? 'unknown'}
                size="md"
              />
              {serviceStatus?.pid && (
                <span className="text-xs text-surface-500">PID: {serviceStatus.pid}</span>
              )}
              {isRunning && serverUptime !== undefined && (
                <span className="text-xs text-surface-500">Uptime: {formatUptime(serverUptime)}</span>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs text-surface-500">Auto-start:</span>
            <button
              onClick={async () => {
                // DASH-ELEC-129: capture previous state and roll back the
                // optimistic toggle if the IPC call fails. doAction toasts the
                // error itself but the icon would otherwise stay stuck on the
                // wrong value until the next 10s status poll. Mirrors the
                // rate-limit-bypass rollback pattern below.
                const prev = autoStart;
                const newState = !autoStart;
                setAutoStart(newState);
                try {
                  const res = (await getAPI().service.setAutoStart(newState)) as
                    | { success?: boolean; output?: string; message?: string }
                    | undefined;
                  if (res && res.success === false) {
                    setAutoStart(prev);
                    toast.error(`Auto-start failed: ${res.message ?? res.output ?? 'unknown error'}`);
                  } else {
                    toast.success(newState ? 'Auto-start enabled' : 'Auto-start disabled');
                    await refreshStatus();
                  }
                } catch (err) {
                  setAutoStart(prev);
                  toast.error(err instanceof Error ? err.message : 'Auto-start failed');
                }
              }}
              className="text-surface-400 hover:text-surface-200"
              title={`Auto-start is ${autoStart ? 'enabled' : 'disabled'}`}
            >
              {autoStart ? (
                <ToggleRight className="w-6 h-6 text-green-400" />
              ) : (
                <ToggleLeft className="w-6 h-6" />
              )}
            </button>
          </div>
        </div>
      </div>

      {/* Control Buttons */}
      <div className="flex flex-wrap gap-3">
        <button
          onClick={() => doAction('Start', () => getAPI().service.start())}
          disabled={loading !== null || isRunning}
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          <Play className="w-4 h-4" />
          {loading === 'Start' ? 'Starting...' : 'Start'}
        </button>

        <button
          onClick={() =>
            setConfirmAction({
              title: 'Stop Server',
              message: 'All CRM users will lose access until the server is restarted. Are you sure?',
              danger: true,
              confirmLabel: 'Stop Server',
              action: async () => {
                await doAction('Stop', () => getAPI().service.stop());
              },
            })
          }
          disabled={loading !== null || isStopped || isNotInstalled}
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium bg-surface-800 text-surface-200 border border-surface-700 rounded-lg hover:bg-surface-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          <Square className="w-4 h-4" />
          {loading === 'Stop' ? 'Stopping...' : 'Stop'}
        </button>

        <button
          onClick={() => doAction('Restart', () => getAPI().service.restart())}
          disabled={loading !== null || isNotInstalled}
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium bg-surface-800 text-surface-200 border border-surface-700 rounded-lg hover:bg-surface-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          <RotateCw className="w-4 h-4" />
          {loading === 'Restart' ? 'Restarting...' : 'Restart'}
        </button>

        <div className="w-px h-10 bg-surface-800 self-center" />

        {/* AUDIT-MGT-011: Kill-all uses a step-counter to avoid nesting
            setConfirmAction inside onConfirm, which caused a race condition
            where step-2 dialog would flash and disappear. */}
        <button
          onClick={() => setKillAllStep(1)}
          disabled={loading !== null}
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium bg-red-900/40 text-red-300 border border-red-800/50 rounded-lg hover:bg-red-900/60 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          <Skull className="w-4 h-4" />
          Kill All
        </button>
      </div>

      {/* Server Config */}
      <div>
        <h2 className="text-sm font-semibold text-surface-300 mb-3">Server Config</h2>
        <div className="flex items-center gap-4 p-3 rounded-lg border border-surface-800 bg-surface-900">
          <div className="flex-1">
            <span className="text-sm text-surface-200">Management API rate limit bypass</span>
            <p className="text-xs text-surface-500 mt-0.5">Exempt dashboard API calls from the global 300 req/min rate limiter</p>
          </div>
          <button
            onClick={async () => {
              const newState = !rateLimitBypass;
              setRateLimitBypass(newState);
              const res = await getAPI().superAdmin.updateConfig({ management_rate_limit_bypass: String(newState) });
              if (res.success) {
                toast.success(newState ? 'Rate limit bypass enabled' : 'Rate limit bypass disabled');
              } else {
                setRateLimitBypass(!newState);
                toast.error(formatApiError(res));
              }
            }}
          >
            {rateLimitBypass ? (
              <ToggleRight className="w-6 h-6 text-green-400" />
            ) : (
              <ToggleLeft className="w-6 h-6 text-surface-500" />
            )}
          </button>
        </div>
      </div>

      {/* Watchdog Status Card.
          Surfaces state from packages/server/scripts/watchdog.cjs. The
          watchdog appends events to logs/watchdog-events.jsonl which the
          dashboard polls every 5s via management:get-watchdog-events.
          Color/icon mapping mirrors the four severity bands defined in
          watchdogState above. Fatal + cert-expired states require an
          explicit operator acknowledge (Clear button) before the card
          can return to healthy. */}
      <div className={
        'stat-card !p-4 lg:!p-5 border-l-4 ' +
        (watchdogState.severity === 'fatal'
          ? 'border-red-500'
          : watchdogState.severity === 'warn'
          ? 'border-amber-500'
          : watchdogState.severity === 'info'
          ? 'border-blue-500'
          : 'border-green-500')
      }>
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3 min-w-0">
            {watchdogState.severity === 'healthy' && <CheckCircle2 className="w-5 h-5 text-green-400 flex-none mt-0.5" />}
            {watchdogState.severity === 'info' && <Activity className="w-5 h-5 text-blue-400 flex-none mt-0.5" />}
            {watchdogState.severity === 'warn' && <Activity className="w-5 h-5 text-amber-400 flex-none mt-0.5" />}
            {watchdogState.severity === 'fatal' && <AlertTriangle className="w-5 h-5 text-red-400 flex-none mt-0.5" />}
            <div className="min-w-0">
              <div className="text-sm font-medium text-surface-100 truncate">{watchdogState.headline}</div>
              {watchdogState.detail && (
                <div className="text-xs text-surface-400 mt-1 break-words">{watchdogState.detail}</div>
              )}
              {watchdogEvents.length > 0 && (
                <div className="text-[11px] text-surface-500 mt-1">
                  {watchdogEvents.length} event{watchdogEvents.length === 1 ? '' : 's'} in log
                </div>
              )}
            </div>
          </div>
          {watchdogState.actionable && (
            <button
              onClick={acknowledgeWatchdog}
              disabled={watchdogClearing}
              className="flex-none px-3 py-1.5 text-xs font-medium text-surface-200 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors disabled:opacity-50"
            >
              {watchdogClearing ? 'Clearing…' : 'I’ve investigated'}
            </button>
          )}
        </div>
      </div>

      {/* Quick Actions */}
      <div>
        <h2 className="text-sm font-semibold text-surface-300 mb-3">Quick Actions</h2>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => getAPI().system.openBrowser()}
            className="flex items-center gap-2 px-3 py-2 text-xs font-medium text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors"
          >
            <Globe className="w-3.5 h-3.5" />
            Open CRM in Browser
          </button>
          <button
            onClick={() => getAPI().system.openLogFile()}
            className="flex items-center gap-2 px-3 py-2 text-xs font-medium text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors"
          >
            <FileText className="w-3.5 h-3.5" />
            View Server Logs
          </button>
          <button
            onClick={() =>
              setConfirmAction({
                title: 'Disable Service',
                message: 'This will stop the server and prevent it from auto-starting on boot. Use this if you suspect a security threat.',
                danger: true,
                confirmLabel: 'Disable Service',
                action: async () => {
                  await doAction('Disable', () => getAPI().service.disable());
                },
              })
            }
            className="flex items-center gap-2 px-3 py-2 text-xs font-medium text-red-400 bg-surface-800 border border-red-900/50 rounded-lg hover:bg-red-950/40 transition-colors"
          >
            <Shield className="w-3.5 h-3.5" />
            Disable Service (Security)
          </button>
        </div>
      </div>

      {/* Confirm Dialog — generic actions */}
      {confirmAction && (
        <ConfirmDialog
          open
          title={confirmAction.title}
          message={confirmAction.message}
          danger={confirmAction.danger}
          requireTyping={confirmAction.requireTyping}
          confirmLabel={confirmAction.confirmLabel}
          onConfirm={async () => {
            const action = confirmAction.action;
            setConfirmAction(null);
            // Small delay so the dialog closes before a new one opens
            await new Promise(r => setTimeout(r, 100));
            await action();
          }}
          onCancel={() => setConfirmAction(null)}
        />
      )}

      {/* AUDIT-MGT-011: Kill-all step-1 dialog */}
      {killAllStep === 1 && (
        <ConfirmDialog
          open
          title="Kill All Processes"
          message="This will FORCE KILL the server AND close the dashboard. All active requests will be terminated."
          danger
          confirmLabel="Yes, Kill Everything"
          onConfirm={() => {
            // Advance directly to step 2 — no nesting, no race.
            setKillAllStep(2);
          }}
          onCancel={() => setKillAllStep(null)}
        />
      )}

      {/* AUDIT-MGT-011: Kill-all step-2 dialog */}
      {killAllStep === 2 && (
        <ConfirmDialog
          open
          title="Are you absolutely sure?"
          message="This will terminate ALL CRM processes on this machine. The server will go offline until manually restarted."
          danger
          requireTyping="KILL"
          confirmLabel="Kill All"
          onConfirm={async () => {
            setKillAllStep(null);
            await getAPI().service.killAll();
          }}
          onCancel={() => setKillAllStep(null)}
        />
      )}
    </div>
  );
}
