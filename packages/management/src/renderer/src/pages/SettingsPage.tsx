import { useState, useEffect, useMemo, useCallback } from 'react';
import {
  Settings, Moon, Monitor, Info, Shield, AlertTriangle, RefreshCw,
  CreditCard, Cloud, Globe, PowerOff, Save, Eye, EyeOff, Sliders,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type {
  SystemInfo, DiskDrive, EnvSettingField, EnvFieldCategory, PlatformConfigField,
} from '@/api/bridge';
import { formatBytes } from '@/utils/format';
import toast from 'react-hot-toast';

// @audit-fixed: removed unused `theme` / `setTheme` zustand selectors and the
// `Sun` icon import — the dashboard is dark-mode only and the toggle was never
// wired up. The dead imports caused TS6133 (declared but never read) under
// `noUnusedLocals`.

// Category metadata for sectioning the env editor. Order here drives the
// render order so the kill switches surface above billing/DNS configuration.
const CATEGORY_META: Record<
  EnvFieldCategory,
  { label: string; description: string; icon: React.ElementType; iconColor: string }
> = {
  killswitch: {
    label: 'Outbound Kill Switches',
    description: 'Emergency suppression of outbound channels system-wide. Use during incident response — every suppressed send is logged for audit.',
    icon: PowerOff,
    iconColor: 'text-red-400',
  },
  captcha: {
    label: 'Bot Protection (hCaptcha)',
    description: 'Tenant signup endpoint hCaptcha enforcement. Disable only when an upstream bot filter (Cloudflare Turnstile, WAF) protects the endpoint.',
    icon: Shield,
    iconColor: 'text-amber-400',
  },
  stripe: {
    label: 'Stripe Billing',
    description: 'Required for paid-plan upgrades. /billing routes return errors until all three keys are set.',
    icon: CreditCard,
    iconColor: 'text-violet-400',
  },
  cloudflare: {
    label: 'Cloudflare DNS Auto-provisioning',
    description: 'Required for tenant subdomain auto-creation. Without these values, new tenant signups succeed in the master DB but no DNS record is created.',
    icon: Cloud,
    iconColor: 'text-orange-400',
  },
  cors: {
    label: 'CORS Allowed Origins',
    description: 'Production-mode rejects RFC1918/CGNAT LAN origins unless explicitly listed.',
    icon: Globe,
    iconColor: 'text-sky-400',
  },
};

const CATEGORY_ORDER: readonly EnvFieldCategory[] = [
  'killswitch', 'captcha', 'stripe', 'cloudflare', 'cors',
];

export function SettingsPage() {
  const [systemInfo, setSystemInfo] = useState<SystemInfo | null>(null);
  const [disks, setDisks] = useState<DiskDrive[] | null>(null);
  const [diskLoading, setDiskLoading] = useState(false);

  const [envFields, setEnvFields] = useState<EnvSettingField[] | null>(null);
  const [envLoading, setEnvLoading] = useState(true);
  const [pending, setPending] = useState<Record<string, string>>({});
  const [revealed, setRevealed] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState(false);
  const [restartPending, setRestartPending] = useState(false);
  const [restarting, setRestarting] = useState(false);

  // Platform config (DB-backed runtime toggles, applied without restart)
  const [pcSchema, setPcSchema] = useState<PlatformConfigField[] | null>(null);
  const [pcValues, setPcValues] = useState<Record<string, string>>({});
  const [pcSaving, setPcSaving] = useState<string | null>(null);

  useEffect(() => {
    getAPI().system.getInfo()
      .then((res) => { if (res.success && res.data) setSystemInfo(res.data); })
      .catch((err) => console.warn('[SettingsPage] system.getInfo failed', err));
  }, []);

  const refreshEnv = useCallback(async () => {
    setEnvLoading(true);
    try {
      const res = await getAPI().admin.getEnvSettings();
      if (res.success && res.data) {
        setEnvFields(res.data.fields);
        setPending({});
      } else if (res.message) {
        toast.error(res.message);
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to load env settings');
    } finally {
      setEnvLoading(false);
    }
  }, []);

  useEffect(() => { refreshEnv(); }, [refreshEnv]);

  const refreshPlatformConfig = useCallback(async () => {
    try {
      const [schemaRes, valuesRes] = await Promise.all([
        getAPI().superAdmin.getConfigSchema(),
        getAPI().superAdmin.getConfig(),
      ]);
      if (schemaRes.success && schemaRes.data) {
        setPcSchema(schemaRes.data.fields);
      }
      if (valuesRes.success && valuesRes.data) {
        setPcValues(valuesRes.data);
      }
    } catch (err) {
      console.warn('[SettingsPage] platform-config refresh failed', err);
    }
  }, []);

  useEffect(() => { refreshPlatformConfig(); }, [refreshPlatformConfig]);

  function pcDisplayValue(f: PlatformConfigField): string {
    return pcValues[f.key] ?? f.default;
  }

  async function handlePlatformConfigToggle(f: PlatformConfigField, next: string) {
    setPcSaving(f.key);
    try {
      const res = await getAPI().superAdmin.updateConfig({ [f.key]: next });
      if (res.success) {
        setPcValues((prev) => ({ ...prev, [f.key]: next }));
        toast.success(`${f.label} updated`);
      } else {
        toast.error(res.message ?? 'Update failed');
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Update failed');
    } finally {
      setPcSaving(null);
    }
  }

  const dirtyKeys = useMemo(() => Object.keys(pending), [pending]);
  const isDirty = dirtyKeys.length > 0;

  function fieldDisplayValue(f: EnvSettingField): string {
    if (Object.prototype.hasOwnProperty.call(pending, f.key)) return pending[f.key];
    return f.value ?? '';
  }

  function setPendingValue(key: string, value: string) {
    setPending((prev) => ({ ...prev, [key]: value }));
  }

  function discardPending(key: string) {
    setPending((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
  }

  async function handleSave() {
    if (!isDirty) return;
    // Pre-flight: warn if user is enabling SIGNUP_CAPTCHA_REQUIRED while
    // HCAPTCHA_SECRET is empty (would FATAL the next boot).
    const captchaField = envFields?.find((f) => f.key === 'HCAPTCHA_SECRET');
    const requireField = envFields?.find((f) => f.key === 'SIGNUP_CAPTCHA_REQUIRED');
    const captchaSecretAfter =
      pending['HCAPTCHA_SECRET'] !== undefined ? pending['HCAPTCHA_SECRET'].trim() : (captchaField?.hasValue ? '__UNCHANGED__' : '');
    const requireAfter =
      pending['SIGNUP_CAPTCHA_REQUIRED'] !== undefined
        ? pending['SIGNUP_CAPTCHA_REQUIRED']
        : (requireField?.value ?? 'true');
    if (requireAfter === 'true' && captchaSecretAfter === '') {
      const ok = window.confirm(
        'You are leaving HCAPTCHA_SECRET empty while requiring hCaptcha on signup. ' +
          'The server will refuse to boot. Continue anyway?'
      );
      if (!ok) return;
    }
    setSaving(true);
    try {
      const res = await getAPI().admin.setEnvSettings(pending);
      if (res.success) {
        toast.success(`${dirtyKeys.length} setting${dirtyKeys.length === 1 ? '' : 's'} saved. Restart required.`);
        setRestartPending(true);
        await refreshEnv();
      } else {
        toast.error(res.message ?? 'Save failed');
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  async function handleRestartServer() {
    setRestarting(true);
    try {
      const res = await getAPI().service.restart();
      if (res.success) {
        setRestartPending(false);
        toast.success('Server restart requested. May take up to a minute to come back online.');
      } else {
        toast.error(res.message ?? 'Server restart failed');
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Server restart failed');
    } finally {
      setRestarting(false);
    }
  }

  function renderField(f: EnvSettingField) {
    const value = fieldDisplayValue(f);
    const dirty = Object.prototype.hasOwnProperty.call(pending, f.key);
    const isRevealed = revealed[f.key];

    if (f.kind === 'flag') {
      const checked = value === 'true';
      return (
        <label key={f.key} className="flex items-start gap-3 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={checked}
            onChange={(e) => setPendingValue(f.key, e.target.checked ? 'true' : 'false')}
            className="mt-0.5 w-4 h-4 rounded border-surface-700 bg-surface-900 cursor-pointer"
          />
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <span className="text-sm text-surface-200">{f.label}</span>
              <code className="text-[10px] font-mono text-surface-600">{f.key}</code>
              {dirty && <span className="text-[10px] text-amber-400">(modified)</span>}
            </div>
            {f.description && (
              <p className="text-xs text-surface-500 mt-1 leading-relaxed">{f.description}</p>
            )}
          </div>
        </label>
      );
    }

    return (
      <div key={f.key} className="space-y-1.5">
        <div className="flex items-center justify-between gap-2">
          <label htmlFor={`env-${f.key}`} className="text-sm text-surface-300">
            {f.label}
            <code className="ml-2 text-[10px] font-mono text-surface-600">{f.key}</code>
            {dirty && <span className="ml-2 text-[10px] text-amber-400">(modified)</span>}
          </label>
          {f.kind === 'secret' && f.hasValue && !dirty && (
            <span className="text-[11px] text-emerald-500/80">
              {f.length}-char secret set
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <input
            id={`env-${f.key}`}
            type={f.kind === 'secret' && !isRevealed ? 'password' : 'text'}
            value={value}
            placeholder={f.placeholder ?? (f.kind === 'secret' && f.hasValue ? '(leave blank to keep current)' : '')}
            onChange={(e) => setPendingValue(f.key, e.target.value)}
            className="flex-1 px-3 py-1.5 text-sm bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-600 focus:border-accent-600 focus:outline-none font-mono"
          />
          {f.kind === 'secret' && (
            <button
              type="button"
              onClick={() => setRevealed((r) => ({ ...r, [f.key]: !r[f.key] }))}
              className="p-1.5 text-surface-500 hover:text-surface-300"
              title={isRevealed ? 'Hide' : 'Reveal'}
            >
              {isRevealed ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          )}
          {dirty && (
            <button
              type="button"
              onClick={() => discardPending(f.key)}
              className="text-[11px] text-surface-500 hover:text-surface-300 px-2"
            >
              undo
            </button>
          )}
        </div>
        {f.description && (
          <p className="text-xs text-surface-500 leading-relaxed">{f.description}</p>
        )}
      </div>
    );
  }

  function renderSection(category: EnvFieldCategory) {
    if (!envFields) return null;
    const meta = CATEGORY_META[category];
    const fields = envFields.filter((f) => f.category === category);
    if (fields.length === 0) return null;
    const Icon = meta.icon;
    return (
      <section key={category}>
        <h2 className="text-sm font-semibold text-surface-300 mb-1 flex items-center gap-2">
          <Icon className={`w-4 h-4 ${meta.iconColor}`} />
          {meta.label}
        </h2>
        <p className="text-xs text-surface-500 mb-3 leading-relaxed">{meta.description}</p>
        <div className="space-y-4 pl-6">
          {fields.map(renderField)}
        </div>
      </section>
    );
  }

  return (
    <div className="space-y-4 lg:space-y-6 animate-fade-in max-w-3xl">
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

      {/* Server env editor — sticky save bar appears below sections when dirty */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-sm font-semibold text-surface-200">Server Configuration</h2>
          <button
            onClick={refreshEnv}
            disabled={envLoading || saving}
            className="p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
            title="Reload from .env"
          >
            <RefreshCw className={`w-4 h-4 ${envLoading ? 'animate-spin' : ''}`} />
          </button>
        </div>
        {envLoading && !envFields ? (
          <p className="text-xs text-surface-500">Loading server .env…</p>
        ) : !envFields ? (
          <p className="text-xs text-red-400">Failed to load .env. Check that the server install integrity is intact.</p>
        ) : (
          <div className="space-y-5 lg:space-y-7">
            {CATEGORY_ORDER.map(renderSection)}
          </div>
        )}
      </div>

      {/* Sticky save / restart bar */}
      {(isDirty || restartPending) && (
        <div className="sticky bottom-2 z-10 flex items-center justify-between gap-3 px-4 py-3 rounded-lg border border-amber-900/60 bg-amber-950/40 backdrop-blur">
          <div className="flex items-center gap-2 text-xs text-amber-200">
            {isDirty ? (
              <>
                <AlertTriangle className="w-4 h-4" />
                {dirtyKeys.length} unsaved change{dirtyKeys.length === 1 ? '' : 's'}
              </>
            ) : (
              <>
                <RefreshCw className="w-4 h-4" />
                Restart the server to apply saved changes.
              </>
            )}
          </div>
          <div className="flex items-center gap-2">
            {isDirty && (
              <button
                onClick={() => setPending({})}
                disabled={saving}
                className="px-3 py-1.5 text-xs font-medium text-surface-300 bg-surface-900 border border-surface-700 rounded hover:bg-surface-800 disabled:opacity-50"
              >
                Discard
              </button>
            )}
            {isDirty ? (
              <button
                onClick={handleSave}
                disabled={saving}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-amber-100 bg-amber-900/60 border border-amber-700 rounded hover:bg-amber-900/80 disabled:opacity-50"
              >
                <Save className={`w-3.5 h-3.5 ${saving ? 'animate-pulse' : ''}`} />
                {saving ? 'Saving…' : 'Save to .env'}
              </button>
            ) : (
              <button
                onClick={handleRestartServer}
                disabled={restarting}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-amber-100 bg-amber-900/60 border border-amber-700 rounded hover:bg-amber-900/80 disabled:opacity-50"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${restarting ? 'animate-spin' : ''}`} />
                {restarting ? 'Restarting…' : 'Restart Server'}
              </button>
            )}
          </div>
        </div>
      )}

      {/* Runtime platform config — DB-backed, applied without restart */}
      {pcSchema && pcSchema.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-surface-200 mb-1 flex items-center gap-2">
            <Sliders className="w-4 h-4 text-emerald-400" />
            Runtime Platform Config
          </h2>
          <p className="text-xs text-surface-500 mb-3 leading-relaxed">
            Database-backed toggles applied immediately, no server restart required.
          </p>
          <div className="space-y-4 pl-6">
            {pcSchema.map((f) => {
              const current = pcDisplayValue(f);
              const busy = pcSaving === f.key;
              if (f.kind === 'flag') {
                const checked = current === 'true';
                return (
                  <label key={f.key} className="flex items-start gap-3 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={busy}
                      onChange={(e) => handlePlatformConfigToggle(f, e.target.checked ? 'true' : 'false')}
                      className="mt-0.5 w-4 h-4 rounded border-surface-700 bg-surface-900 cursor-pointer disabled:opacity-50"
                    />
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-surface-200">{f.label}</span>
                        <code className="text-[10px] font-mono text-surface-600">{f.key}</code>
                        {busy && <span className="text-[10px] text-amber-400">saving…</span>}
                      </div>
                      <p className="text-xs text-surface-500 mt-1 leading-relaxed">{f.description}</p>
                    </div>
                  </label>
                );
              }
              // value-kind — single text input that saves on blur.
              return (
                <div key={f.key} className="space-y-1.5">
                  <div className="flex items-center justify-between gap-2">
                    <label htmlFor={`pc-${f.key}`} className="text-sm text-surface-300">
                      {f.label}
                      <code className="ml-2 text-[10px] font-mono text-surface-600">{f.key}</code>
                      {busy && <span className="ml-2 text-[10px] text-amber-400">saving…</span>}
                    </label>
                  </div>
                  <input
                    id={`pc-${f.key}`}
                    type="text"
                    defaultValue={current}
                    disabled={busy}
                    onBlur={(e) => {
                      const next = e.target.value;
                      if (next !== current) handlePlatformConfigToggle(f, next);
                    }}
                    className="w-full px-3 py-1.5 text-sm bg-surface-950 border border-surface-700 rounded text-surface-200 focus:border-accent-600 focus:outline-none font-mono disabled:opacity-50"
                  />
                  <p className="text-xs text-surface-500 leading-relaxed">{f.description}</p>
                </div>
              );
            })}
          </div>
        </section>
      )}

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

          {/* Disk space */}
          <div className="mt-4 space-y-2">
            <button
              onClick={async () => {
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
