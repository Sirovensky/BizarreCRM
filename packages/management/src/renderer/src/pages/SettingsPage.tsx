import { useState, useEffect } from 'react';
import { Settings, Moon, Sun, Monitor, Info } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { SystemInfo } from '@/api/bridge';
import { useUiStore } from '@/stores/uiStore';
import { formatBytes } from '@/utils/format';

export function SettingsPage() {
  const theme = useUiStore((s) => s.theme);
  const setTheme = useUiStore((s) => s.setTheme);
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);

  useEffect(() => {
    getAPI().system.getInfo().then((res) => {
      if (res.success && res.data) setSystemInfo(res.data);
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
        <div className="flex gap-3">
          <button
            onClick={() => setTheme('dark')}
            className={`flex items-center gap-2 px-4 py-2.5 text-sm rounded-lg border transition-colors ${
              theme === 'dark'
                ? 'bg-accent-600/15 border-accent-600 text-accent-400'
                : 'bg-surface-900 border-surface-700 text-surface-400 hover:bg-surface-800'
            }`}
          >
            <Moon className="w-4 h-4" />
            Dark
          </button>
          <button
            onClick={() => setTheme('light')}
            className={`flex items-center gap-2 px-4 py-2.5 text-sm rounded-lg border transition-colors ${
              theme === 'light'
                ? 'bg-accent-600/15 border-accent-600 text-accent-400'
                : 'bg-surface-900 border-surface-700 text-surface-400 hover:bg-surface-800'
            }`}
          >
            <Sun className="w-4 h-4" />
            Light
          </button>
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
          <div className="mt-4">
            <button
              onClick={async () => {
                const res = await getAPI().system.getDiskSpace();
                if (res.success && res.data) {
                  // Display disk info in a simple alert for now
                  const info = (res.data as Array<{ mount: string; total: number; free: number }>)
                    .map((d) => `${d.mount} — ${formatBytes(d.free)} free of ${formatBytes(d.total)}`)
                    .join('\n');
                  console.log('Disk space:', info);
                }
              }}
              className="flex items-center gap-2 px-3 py-2 text-xs text-surface-400 border border-surface-700 rounded-lg hover:bg-surface-800 transition-colors"
            >
              <Monitor className="w-3.5 h-3.5" />
              Check Disk Space
            </button>
          </div>
        </section>
      )}
    </div>
  );
}
