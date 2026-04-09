import { useState, useEffect, useCallback } from 'react';
import {
  Play,
  Square,
  RotateCw,
  OctagonX,
  Skull,
  Globe,
  FileText,
  ToggleLeft,
  ToggleRight,
  Shield,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { ServiceStatus } from '@/api/bridge';
import { StatusBadge } from '@/components/shared/StatusBadge';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { formatUptime } from '@/utils/format';
import { useServerStore } from '@/stores/serverStore';
import toast from 'react-hot-toast';

export function ServerControlPage() {
  const [serviceStatus, setServiceStatus] = useState<ServiceStatus | null>(null);
  const [loading, setLoading] = useState<string | null>(null);
  const [autoStart, setAutoStart] = useState<boolean | null>(null);
  const [confirmAction, setConfirmAction] = useState<{
    title: string; message: string; action: () => Promise<void>;
    danger?: boolean; requireTyping?: string; confirmLabel?: string;
  } | null>(null);

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

  useEffect(() => {
    refreshStatus();
    const interval = setInterval(refreshStatus, 3000);
    return () => clearInterval(interval);
  }, [refreshStatus]);

  const doAction = async (name: string, action: () => Promise<unknown>) => {
    setLoading(name);
    try {
      await action();
      toast.success(`${name} successful`);
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
    <div className="space-y-6 animate-fade-in">
      <h1 className="text-lg font-bold text-surface-100">Server Control</h1>

      {/* Service Status Card */}
      <div className="stat-card !p-6">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <Shield className="w-5 h-5 text-accent-400" />
              <span className="text-sm font-medium text-surface-300">
                {serviceStatus?.mode === 'pm2' ? 'PM2: bizarre-crm' : serviceStatus?.mode === 'service' ? 'Windows Service: BizarreCRM' : 'Server Process'}
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
                const newState = !autoStart;
                setAutoStart(newState);
                await doAction(
                  newState ? 'Enable auto-start' : 'Disable auto-start',
                  () => getAPI().service.setAutoStart(newState)
                );
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

        <button
          onClick={() =>
            setConfirmAction({
              title: 'Kill All Processes',
              message: 'This will FORCE KILL the server AND close the dashboard. All active requests will be terminated.',
              danger: true,
              confirmLabel: 'Yes, Kill Everything',
              action: async () => {
                setConfirmAction({
                  title: 'Are you absolutely sure?',
                  message: 'This will terminate ALL CRM processes on this machine. The server will go offline until manually restarted.',
                  danger: true,
                  requireTyping: 'KILL',
                  confirmLabel: 'Kill All',
                  action: async () => {
                    await getAPI().service.killAll();
                  },
                });
              },
            })
          }
          disabled={loading !== null}
          className="flex items-center gap-2 px-4 py-2.5 text-sm font-medium bg-red-900/40 text-red-300 border border-red-800/50 rounded-lg hover:bg-red-900/60 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          <Skull className="w-4 h-4" />
          Kill All
        </button>
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

      {/* Confirm Dialog */}
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
    </div>
  );
}
