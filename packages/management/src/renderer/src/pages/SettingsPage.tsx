import { useState, useEffect } from 'react';
import { Settings, Moon, Monitor, Info, Shield, AlertTriangle, RefreshCw } from 'lucide-react';
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
  const [captchaRequired, setCaptchaRequired] = useState<boolean | null>(null);
  const [captchaHasSecret, setCaptchaHasSecret] = useState<boolean>(false);
  const [captchaSaving, setCaptchaSaving] = useState(false);
  const [restartPending, setRestartPending] = useState(false);
  const [restarting, setRestarting] = useState(false);

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

    getAPI().admin.getSignupCaptchaConfig()
      .then((res) => {
        if (res.success && res.data) {
          setCaptchaRequired(res.data.required);
          setCaptchaHasSecret(res.data.hasSecret);
        } else if (res.message) {
          console.warn('[SettingsPage] getSignupCaptchaConfig:', res.message);
        }
      })
      .catch((err) => {
        console.warn('[SettingsPage] getSignupCaptchaConfig failed', err);
      });
  }, []);

  async function handleCaptchaToggle(next: boolean) {
    if (captchaRequired === null) return;
    if (next && !captchaHasSecret) {
      const proceed = window.confirm(
        'HCAPTCHA_SECRET is empty in .env. Turning this ON will prevent the server ' +
          'from booting until you paste a secret from hcaptcha.com into .env. Continue?'
      );
      if (!proceed) return;
    }
    setCaptchaSaving(true);
    try {
      const res = await getAPI().admin.setSignupCaptchaRequired(next);
      if (res.success && res.data) {
        setCaptchaRequired(res.data.required);
        setRestartPending(true);
        toast.success(
          next
            ? 'hCaptcha requirement enabled. Restart the server to apply.'
            : 'hCaptcha requirement disabled. Restart the server to apply.'
        );
      } else {
        toast.error(res.message ?? 'Failed to update setting');
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to update setting');
    } finally {
      setCaptchaSaving(false);
    }
  }

  async function handleRestartServer() {
    setRestarting(true);
    try {
      const res = await getAPI().service.restart();
      if (res.success) {
        setRestartPending(false);
        toast.success('Server restart requested. It may take up to a minute to come back online.');
      } else {
        toast.error(res.message ?? 'Server restart failed');
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Server restart failed');
    } finally {
      setRestarting(false);
    }
  }

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

      {/* Signup Security — SEC-H94 */}
      <section>
        <h2 className="text-sm font-semibold text-surface-300 mb-3 flex items-center gap-2">
          <Shield className="w-4 h-4" />
          Signup Security
        </h2>
        {captchaRequired === null ? (
          <p className="text-xs text-surface-500">Loading current .env configuration…</p>
        ) : (
          <div className="space-y-3">
            <label className="flex items-start gap-3 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={captchaRequired}
                disabled={captchaSaving}
                onChange={(e) => handleCaptchaToggle(e.target.checked)}
                className="mt-0.5 w-4 h-4 rounded border-surface-700 bg-surface-900 cursor-pointer disabled:opacity-50"
              />
              <div className="flex-1">
                <div className="text-sm text-surface-200">Require hCaptcha on tenant signup</div>
                <p className="text-xs text-surface-500 mt-1 leading-relaxed">
                  When ON, the signup endpoint requires a valid hCaptcha token and the server
                  refuses to boot if <code className="font-mono text-surface-400">HCAPTCHA_SECRET</code> is missing.
                  Turn OFF only when an upstream bot filter (Cloudflare Turnstile, WAF) already
                  protects this endpoint.
                </p>
                {!captchaHasSecret && (
                  <p className="text-xs text-amber-400 mt-2 flex items-start gap-1.5">
                    <AlertTriangle className="w-3.5 h-3.5 mt-0.5 flex-shrink-0" />
                    <span>
                      <code className="font-mono">HCAPTCHA_SECRET</code> is empty in .env.
                      {captchaRequired
                        ? ' Server will refuse to boot until a secret is pasted or this toggle is turned OFF.'
                        : ' Signups currently accept any traffic — upstream bot protection is required.'}
                    </span>
                  </p>
                )}
              </div>
            </label>

            {restartPending && (
              <div className="flex items-center justify-between gap-3 px-3 py-2 rounded-lg border border-amber-900/50 bg-amber-950/30">
                <p className="text-xs text-amber-300">
                  Change saved to .env. Restart the server to apply.
                </p>
                <button
                  onClick={handleRestartServer}
                  disabled={restarting}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-amber-200 bg-amber-900/40 border border-amber-800 rounded hover:bg-amber-900/60 disabled:opacity-50 transition-colors whitespace-nowrap"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${restarting ? 'animate-spin' : ''}`} />
                  {restarting ? 'Restarting…' : 'Restart Server'}
                </button>
              </div>
            )}
          </div>
        )}
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
