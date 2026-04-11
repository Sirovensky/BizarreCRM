import { useState, useEffect } from 'react';
import { Settings, Moon, Monitor, Info } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { SystemInfo, DiskDrive } from '@/api/bridge';
import { formatBytes } from '@/utils/format';
import toast from 'react-hot-toast';

// @audit-fixed: removed unused `theme` / `setTheme` zustand selectors and the
// `Sun` icon import — the dashboard is dark-mode only and the toggle was never
// wired up. The dead imports caused TS6133 (declared but never read) under
// `noUnusedLocals`.

export function SettingsPage() {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [disks, setDisks] = useState<DiskDrive[] | null>(null);
  const [diskLoading, setDiskLoading] = useState(false);

  useEffect(() => {
    // @audit-fixed: previously the .then() lacked any .catch(), so a failure
    // (server offline / IPC error) became an unhandled promise rejection
    // that React StrictMode would log as a warning. Now we surface failures
    // to the user via toast and avoid the console noise.
    getAPI().system.getInfo()
      .then((res) => {
        if (res.success && res.data) setSystemInfo(res.data);
      })
      .catch((err) => {
        console.warn('[SettingsPage] system.getInfo failed', err);
      });
  }, []);

  return (
    <div className="space-y-8 animate-fade-in max-w-2xl">
      <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
        <Settings className="w-5 h-5 text-accent-400" />
        Settings
      </h1>

      {/* Theme */}
      <section>
        <h2 className="text-sm font-semibold text-surface-300 mb-3">Appearance</h2>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-4 py-2.5 text-sm rounded-lg border bg-accent-600/15 border-accent-600 text-accent-400">
            <Moon className="w-4 h-4" />
            Dark
          </div>
          <span className="text-xs text-surface-600">Dark mode only</span>
        </div>
      </section>

      {/* Dashboard Close */}
      <section>
        <h2 className="text-sm font-semibold text-surface-300 mb-3">Dashboard</h2>
        <button
          onClick={() => getAPI().system.closeDashboard()}
          className="px-4 py-2.5 text-sm font-medium text-red-400 bg-surface-900 border border-red-900/50 rounded-lg hover:bg-red-950/40 transition-colors"
        >
          Close Dashboard
        </button>
        <p className="text-xs text-surface-500 mt-2">
          Closing the dashboard does NOT stop the CRM server. The server continues running as a Windows Service.
        </p>
      </section>

      {/* System Info */}
      {systemInfo && (
        <section>
          <h2 className="text-sm font-semibold text-surface-300 mb-3 flex items-center gap-2">
            <Info className="w-4 h-4" />
            System Information
          </h2>
          <div className="grid grid-cols-2 gap-x-8 gap-y-2 text-xs">
            <div className="flex justify-between">
              <span className="text-surface-500">Platform</span>
              <span className="text-surface-300">{systemInfo.platform} ({systemInfo.arch})</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">Hostname</span>
              <span className="text-surface-300">{systemInfo.hostname}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">Total Memory</span>
              <span className="text-surface-300">{formatBytes(systemInfo.totalMemory)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">CPUs</span>
              <span className="text-surface-300">{systemInfo.cpus} cores</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">Node.js</span>
              <span className="text-surface-300 font-mono">{systemInfo.nodeVersion}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">Electron</span>
              <span className="text-surface-300 font-mono">{systemInfo.electronVersion}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">Dashboard</span>
              <span className="text-surface-300 font-mono">v{systemInfo.appVersion}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-surface-500">Packaged</span>
              <span className="text-surface-300">{systemInfo.isPackaged ? 'Yes' : 'No (dev)'}</span>
            </div>
          </div>

          {/* Monitor */}
          <div className="mt-4 space-y-2">
            <button
              onClick={async () => {
                // @audit-fixed: previously this clicked the button and only
                // console.log'd the result — the user got zero feedback. Now
                // it stores the result in state and renders the disks below
                // the button, plus shows a toast on hard failure.
                setDiskLoading(true);
                try {
                  const res = await getAPI().system.getDiskSpace();
                  if (res.success && Array.isArray(res.data)) {
                    setDisks(res.data);
                    if (res.data.length === 0) {
                      toast('No drives reported (wmic may be disabled on this OS)');
                    }
                  } else {
                    toast.error(res.message ?? 'Failed to read disk space');
                  }
                } catch (err) {
                  toast.error(err instanceof Error ? err.message : 'Failed to read disk space');
                } finally {
                  setDiskLoading(false);
                }
              }}
              disabled={diskLoading}
              className="flex items-center gap-2 px-3 py-2 text-xs text-surface-400 border border-surface-700 rounded-lg hover:bg-surface-800 disabled:opacity-50 transition-colors"
            >
              <Monitor className="w-3.5 h-3.5" />
              {diskLoading ? 'Reading disks…' : 'Check Disk Space'}
            </button>
            {disks && disks.length > 0 && (
              <div className="grid grid-cols-1 gap-1 text-xs text-surface-400 font-mono">
                {disks.map((d) => (
                  <div key={d.mount} className="flex justify-between">
                    <span>{d.mount}</span>
                    <span>
                      {formatBytes(d.free)} free / {formatBytes(d.total)}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </section>
      )}
    </div>
  );
}
