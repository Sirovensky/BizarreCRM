import { useState, useEffect, useMemo, useCallback } from 'react';
import {
  Settings, Moon, Monitor, Info, Shield, AlertTriangle, RefreshCw,
  CreditCard, Cloud, Globe, PowerOff, Save, Eye, EyeOff, Sliders, Search,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { useUiStore } from '@/stores/uiStore';
import type {
  SystemInfo, DiskDrive, EnvSettingField, EnvFieldCategory, PlatformConfigField,
  EnvConnectionTestResult, EnvConnectionTestStatus, EnvConnectionTestTarget,
} from '@/api/bridge';
import { formatBytes } from '@/utils/format';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';

type RuntimePlatformConfigField = Omit<PlatformConfigField, 'kind'> & {
  kind: PlatformConfigField['kind'] | 'secret' | 'text';
  hasValue?: boolean;
  length?: number;
  placeholder?: string;
};

type PlatformConfigStatus = NonNullable<PlatformConfigField['status']>;
type InactivePlatformConfigStatus = Exclude<PlatformConfigStatus, 'active'>;

const PLATFORM_CONFIG_STATUS_META: Record<
  InactivePlatformConfigStatus,
  { label: string; className: string; fallbackReason: string }
> = {
  coming_soon: {
    label: 'Coming soon',
    className: 'bg-amber-500/10 text-amber-300 border-amber-500/30',
    fallbackReason: 'This setting is planned but not active yet.',
  },
  dead: {
    label: 'No effect',
    className: 'bg-red-500/10 text-red-300 border-red-500/30',
    fallbackReason: 'This setting is visible for audit only and currently has no runtime effect.',
  },
};

function platformConfigStatus(f: RuntimePlatformConfigField): PlatformConfigStatus {
  return f.status ?? 'active';
}

function inactivePlatformConfigMeta(f: RuntimePlatformConfigField) {
  const status = platformConfigStatus(f);
  if (status === 'active') return null;
  const meta = PLATFORM_CONFIG_STATUS_META[status];
  return {
    ...meta,
    reason: f.statusReason ?? meta.fallbackReason,
  };
}

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

const TESTABLE_ENV_CATEGORIES = new Set<EnvConnectionTestTarget>([
  'captcha', 'stripe', 'cloudflare',
]);

const CONNECTION_STATUS_META: Record<EnvConnectionTestStatus, {
  label: string;
  className: string;
  detailClassName: string;
}> = {
  pass: {
    label: 'Passed',
    className: 'border-emerald-900/60 bg-emerald-950/30 text-emerald-100',
    detailClassName: 'text-emerald-300',
  },
  warn: {
    label: 'Warning',
    className: 'border-amber-900/60 bg-amber-950/30 text-amber-100',
    detailClassName: 'text-amber-300',
  },
  fail: {
    label: 'Failed',
    className: 'border-red-900/60 bg-red-950/30 text-red-100',
    detailClassName: 'text-red-300',
  },
};

function isTestableEnvCategory(category: EnvFieldCategory): category is EnvConnectionTestTarget {
  return TESTABLE_ENV_CATEGORIES.has(category as EnvConnectionTestTarget);
}

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
  const [pcSchema, setPcSchema] = useState<RuntimePlatformConfigField[] | null>(null);
  const [pcValues, setPcValues] = useState<Record<string, string>>({});
  const [pcPending, setPcPending] = useState<Record<string, string>>({});
  const [pcRevealed, setPcRevealed] = useState<Record<string, boolean>>({});
  const [pcSaving, setPcSaving] = useState<string | null>(null);

  // Free-text filter across env + platform config — narrows the displayed
  // fields by key / label / description / category. Pending edits still
  // commit regardless of the filter view (the dirty-state survives).
  const [filter, setFilter] = useState('');
  const [connectionTests, setConnectionTests] = useState<Partial<Record<
    EnvConnectionTestTarget,
    { loading: boolean; result?: EnvConnectionTestResult }
  >>>({});

  // DASH-ELEC-180 + DASH-ELEC-194: ConfirmDialog state for destructive actions
  // that previously used window.confirm (blocked in sandboxed renderer).
  const [confirmTarget, setConfirmTarget] = useState<null | 'hcaptcha' | 'closeDashboard'>(null);

  useEffect(() => {
    getAPI().system.getInfo()
      .then((res) => { if (res.success && res.data) setSystemInfo(res.data); })
      .catch((err) => console.warn('[SettingsPage] system.getInfo failed', err));
  }, []);

  const refreshEnv = useCallback(async () => {
    setEnvLoading(true);
    try {
      const res = await getAPI().admin.getEnvSettings();
      // DASH-ELEC-279: detect 401 → global auto-logout instead of silently
      // leaving envFields empty when the JWT has expired.
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setEnvFields(res.data.fields);
        setPending({});
      } else if (res.message) {
        toast.error(formatApiError(res));
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
      // DASH-ELEC-279: detect 401 on either response — short-circuit before
      // the !success branches silently leave pcSchema/pcValues stale.
      if (handleApiResponse(schemaRes)) return;
      if (handleApiResponse(valuesRes)) return;
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

  function pcDisplayValue(f: RuntimePlatformConfigField): string {
    return pcValues[f.key] ?? f.default;
  }

  function pcInputValue(f: RuntimePlatformConfigField): string {
    const pendingValue = pcPending[f.key];
    return pendingValue ?? pcDisplayValue(f);
  }

  function setPlatformConfigPendingValue(f: RuntimePlatformConfigField, value: string) {
    if (platformConfigStatus(f) !== 'active') return;
    setPcPending((prev) => {
      const next = { ...prev };
      if (value === pcDisplayValue(f)) {
        delete next[f.key];
      } else {
        next[f.key] = value;
      }
      return next;
    });
  }

  function discardPlatformConfigPending(key: string) {
    setPcPending((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
  }

  async function handlePlatformConfigToggle(f: RuntimePlatformConfigField, next: string) {
    if (platformConfigStatus(f) !== 'active') return;
    setPcSaving(f.key);
    try {
      const res = await getAPI().superAdmin.updateConfig({ [f.key]: next });
      if (res.success) {
        setPcValues((prev) => ({ ...prev, [f.key]: next }));
        toast.success(`${f.label} updated`);
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Update failed');
    } finally {
      setPcSaving(null);
    }
  }

  async function handlePlatformConfigValueSave(f: RuntimePlatformConfigField) {
    if (platformConfigStatus(f) !== 'active') return;
    if (!Object.prototype.hasOwnProperty.call(pcPending, f.key)) return;
    const nextValue = pcPending[f.key];
    if (nextValue === undefined) return;
    setPcSaving(f.key);
    try {
      const res = await getAPI().superAdmin.updateConfig({ [f.key]: nextValue });
      if (res.success) {
        setPcValues((prev) => ({ ...prev, [f.key]: nextValue }));
        discardPlatformConfigPending(f.key);
        toast.success(`${f.label} updated`);
      } else {
        toast.error(formatApiError(res));
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

  const hasPendingChangesForCategory = useCallback((category: EnvConnectionTestTarget) => (
    envFields?.some((f) => f.category === category && Object.prototype.hasOwnProperty.call(pending, f.key)) ?? false
  ), [envFields, pending]);

  async function handleTestConnection(category: EnvConnectionTestTarget) {
    if (hasPendingChangesForCategory(category)) {
      toast.error('Save or discard this section before testing saved configuration.');
      return;
    }
    setConnectionTests((prev) => ({
      ...prev,
      [category]: { loading: true, result: prev[category]?.result },
    }));
    try {
      const res = await getAPI().admin.testEnvConnection(category);
      if (res.success && res.data) {
        setConnectionTests((prev) => ({
          ...prev,
          [category]: { loading: false, result: res.data },
        }));
        if (res.data.status === 'pass') {
          toast.success(res.data.summary);
        } else if (res.data.status === 'warn') {
          toast(res.data.summary, { icon: '!' });
        } else {
          toast.error(res.data.summary);
        }
      } else {
        toast.error(formatApiError(res));
        setConnectionTests((prev) => ({
          ...prev,
          [category]: { loading: false, result: prev[category]?.result },
        }));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Connection test failed');
      setConnectionTests((prev) => ({
        ...prev,
        [category]: { loading: false, result: prev[category]?.result },
      }));
    }
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
      // DASH-ELEC-180: window.confirm is blocked in the sandboxed renderer.
      // Show a ConfirmDialog and resume saving when operator confirms.
      setConfirmTarget('hcaptcha');
      return;
    }
    await executeSave();
  }

  async function executeSave() {
    setSaving(true);
    try {
      const res = await getAPI().admin.setEnvSettings(pending);
      if (res.success) {
        toast.success(`${dirtyKeys.length} setting${dirtyKeys.length === 1 ? '' : 's'} saved. Restart required.`);
        setRestartPending(true);
        await refreshEnv();
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  async function handleRestartServer() {
    setRestarting(true);
    const startedAt = Date.now();
    let toastId: string | undefined;
    try {
      const res = await getAPI().service.restart();
      if (!res.success) {
        toast.error(formatApiError(res));
        return;
      }
      toastId = toast.loading('Server restart requested. Waiting for server to come back online…');
      // Poll the liveness endpoint until it returns 200 or we time out.
      // PM2 graceful-stop + cold-start is normally <30s; we cap the wait
      // at 90s to match the watchdog's failure threshold. After the
      // server is reachable the SPA's own JS bundle is still loaded and
      // doesn't need a hard reload — but env values shown in the editor
      // ARE stale (we cached the pre-restart fields), so we trigger a
      // soft refresh via refreshEnv() and clear the restart banner.
      const TIMEOUT_MS = 90_000;
      const POLL_MS = 1500;
      let online = false;
      while (Date.now() - startedAt < TIMEOUT_MS) {
        await new Promise((r) => setTimeout(r, POLL_MS));
        try {
          // Use absolute path — same-origin fetch means no CORS, and the
          // liveness endpoint is auth-free per its design.
          const ping = await fetch('/api/v1/health/live', { credentials: 'omit' });
          if (ping.ok) {
            online = true;
            break;
          }
        } catch {
          // connection refused / network error during restart window —
          // expected, keep polling
        }
      }
      if (online) {
        if (toastId) toast.dismiss(toastId);
        toast.success('Server is back online. Settings refreshed.');
        setRestartPending(false);
        await refreshEnv();
      } else {
        if (toastId) toast.dismiss(toastId);
        toast.error(`Server did not come back online within ${TIMEOUT_MS / 1000}s. Check pm2 logs.`);
      }
    } catch (err) {
      if (toastId) toast.dismiss(toastId);
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
      const checkboxId = `env-flag-${f.key}`;
      return (
        <div key={f.key} className="flex items-start gap-3">
          <input
            id={checkboxId}
            type="checkbox"
            checked={checked}
            onChange={(e) => setPendingValue(f.key, e.target.checked ? 'true' : 'false')}
            className="mt-0.5 w-4 h-4 rounded border-surface-700 bg-surface-900 cursor-pointer"
          />
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <label htmlFor={checkboxId} className="text-sm text-surface-200 cursor-pointer select-none">{f.label}</label>
              {f.description && (
                <span
                  className="inline-flex items-center text-surface-500 hover:text-surface-300 cursor-help"
                  title={f.description}
                  aria-label={`Help: ${f.description}`}
                >
                  <Info className="w-3.5 h-3.5" />
                </span>
              )}
              <code className="text-[10px] font-mono text-surface-600" aria-hidden="true">{f.key}</code>
              {dirty && <span className="text-[10px] text-amber-400">(modified)</span>}
            </div>
            {f.description && (
              <p className="text-xs text-surface-500 mt-1 leading-relaxed">{f.description}</p>
            )}
          </div>
        </div>
      );
    }

    return (
      <div key={f.key} className="space-y-1.5">
        <div className="flex items-center justify-between gap-2">
          <label htmlFor={`env-${f.key}`} className="text-sm text-surface-300 inline-flex items-center gap-2">
            <span>{f.label}</span>
            {f.description && (
              <span
                className="inline-flex items-center text-surface-500 hover:text-surface-300 cursor-help"
                title={f.description}
                aria-label={`Help: ${f.description}`}
              >
                <Info className="w-3.5 h-3.5" />
              </span>
            )}
            <code className="text-[10px] font-mono text-surface-600">{f.key}</code>
            {dirty && <span className="text-[10px] text-amber-400">(modified)</span>}
          </label>
          {f.kind === 'secret' && f.hasValue && !dirty && (
            <span className="text-[11px] text-emerald-500/80">
              {f.length}-char secret set
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {/* DASH-ELEC-172: cap input length so MB-large pastes don't sail through to
              the IPC layer (which fails with a generic error). 512 covers the longest
              real-world secret (e.g. Cloudflare API tokens ~40, Stripe keys ~100); 2048
              for plain text fields like CORS_ORIGINS that may list multiple URLs. */}
          {/* DASH-ELEC-199: CORS origins field gets a textarea so multiple origins
              can be entered on separate lines without horizontal scrolling. */}
          {f.category === 'cors' ? (
            <textarea
              id={`env-${f.key}`}
              value={value}
              rows={3}
              maxLength={2048}
              placeholder={f.placeholder ?? ''}
              onChange={(e) => setPendingValue(f.key, e.target.value)}
              className="flex-1 px-3 py-1.5 text-sm bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-400 focus:border-accent-600 focus:outline-none font-mono resize-y"
            />
          ) : (
          <input
            id={`env-${f.key}`}
            type={f.kind === 'secret' && !isRevealed ? 'password' : 'text'}
            value={value}
            maxLength={f.kind === 'secret' ? 512 : 2048}
            placeholder={f.placeholder ?? (f.kind === 'secret' && f.hasValue ? '(leave blank to keep current)' : '')}
            onChange={(e) => setPendingValue(f.key, e.target.value)}
            className="flex-1 px-3 py-1.5 text-sm bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-400 focus:border-accent-600 focus:outline-none font-mono"
          />
          )}
          {f.kind === 'secret' && (
            <button
              type="button"
              onClick={() => setRevealed((r) => ({ ...r, [f.key]: !r[f.key] }))}
              className="p-1.5 text-surface-500 hover:text-surface-300"
              title={isRevealed ? 'Hide password' : 'Show password'}
              aria-label={isRevealed ? 'Hide password' : 'Show password'}
              aria-pressed={isRevealed}
            >
              {isRevealed ? <EyeOff className="w-4 h-4" aria-hidden="true" /> : <Eye className="w-4 h-4" aria-hidden="true" />}
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

  function matchesFilter(haystack: string): boolean {
    if (!filter.trim()) return true;
    return haystack.toLowerCase().includes(filter.toLowerCase());
  }

  function renderConnectionTestResult(result: EnvConnectionTestResult) {
    const meta = CONNECTION_STATUS_META[result.status];
    const checkedAt = new Date(result.checkedAt).toLocaleString();
    const toneClass: Record<NonNullable<EnvConnectionTestResult['details'][number]['tone']>, string> = {
      success: 'text-emerald-300',
      warning: 'text-amber-300',
      danger: 'text-red-300',
      muted: 'text-surface-400',
    };
    return (
      <div
        role={result.status === 'fail' ? 'alert' : 'status'}
        className={`mb-4 ml-6 rounded-lg border px-3 py-2.5 text-xs ${meta.className}`}
      >
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="font-medium">{meta.label}: {result.summary}</p>
            <p className="mt-1 text-[11px] text-surface-400">Checked {checkedAt}</p>
          </div>
        </div>
        <dl className="mt-2 grid grid-cols-1 gap-1">
          {result.details.map((detail) => (
            <div key={`${detail.label}-${detail.value}`} className="flex items-start justify-between gap-3">
              <dt className="text-surface-500">{detail.label}</dt>
              <dd className={`text-right break-words ${detail.tone ? toneClass[detail.tone] : meta.detailClassName}`}>
                {detail.value}
              </dd>
            </div>
          ))}
        </dl>
      </div>
    );
  }

  function renderSection(category: EnvFieldCategory) {
    if (!envFields) return null;
    const meta = CATEGORY_META[category];
    const fields = envFields.filter((f) => {
      if (f.category !== category) return false;
      const hay = `${f.key} ${f.label} ${f.description ?? ''} ${category} ${meta.label}`;
      return matchesFilter(hay);
    });
    if (fields.length === 0) return null;
    const Icon = meta.icon;
    const headingId = `settings-section-${category}`;
    const testable = isTestableEnvCategory(category);
    const testState = testable ? connectionTests[category] : undefined;
    return (
      // DASH-ELEC-204: aria-labelledby so the <section> landmark has a
      // computed accessible name for screen reader navigation.
      <section key={category} aria-labelledby={headingId}>
        <h2 id={headingId} className="text-sm font-semibold text-surface-300 mb-1 flex items-center gap-2">
          <Icon className={`w-4 h-4 ${meta.iconColor}`} aria-hidden="true" />
          <span>{meta.label}</span>
          {testable && (
            <button
              type="button"
              onClick={() => void handleTestConnection(category)}
              disabled={Boolean(testState?.loading) || envLoading || saving}
              className="ml-auto inline-flex items-center gap-1.5 px-2 py-1 text-[11px] font-medium text-surface-300 bg-surface-900 border border-surface-700 rounded hover:bg-surface-800 hover:text-surface-100 disabled:opacity-50"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${testState?.loading ? 'animate-spin' : ''}`} aria-hidden="true" />
              {testState?.loading ? 'Testing…' : 'Test Connection'}
            </button>
          )}
        </h2>
        <p className="text-xs text-surface-500 mb-3 leading-relaxed">{meta.description}</p>
        {testState?.result && renderConnectionTestResult(testState.result)}
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

      {/* Theme + density */}
      {/* DASH-ELEC-204: aria-labelledby landmarks for static sections */}
      <section aria-labelledby="settings-section-appearance">
        <h2 id="settings-section-appearance" className="text-sm font-semibold text-surface-300 mb-3">Appearance</h2>
        <div className="flex items-center gap-3 flex-wrap">
          <div className="flex items-center gap-2 px-4 py-2.5 text-sm rounded-lg border bg-accent-600/15 border-accent-600 text-accent-400">
            <Moon className="w-4 h-4" />
            Dark
          </div>
          <span className="text-xs text-surface-600">Dark mode only</span>
          <div className="ml-auto flex items-center gap-1 text-xs">
            <span id="density-label" className="text-surface-500 mr-1">Density:</span>
            <div role="radiogroup" aria-labelledby="density-label" className="flex items-center gap-1">
              <DensityOption value="default" label="Default" />
              <DensityOption value="compact" label="Compact" />
            </div>
          </div>
        </div>
      </section>

      {/* Dashboard Close */}
      <section aria-labelledby="settings-section-dashboard">
        <h2 id="settings-section-dashboard" className="text-sm font-semibold text-surface-300 mb-3">Dashboard</h2>
        {/* DASH-ELEC-194: was calling closeDashboard() directly with no confirmation. */}
        <button
          onClick={() => setConfirmTarget('closeDashboard')}
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
        <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
          <h2 className="text-sm font-semibold text-surface-200">Server Configuration</h2>
          <div className="flex items-center gap-2 flex-1 max-w-sm ml-auto">
            <div className="relative flex-1">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-surface-500" />
              <input
                type="text"
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                placeholder="Filter settings (key, label, description)"
                aria-label="Filter server configuration settings"
                className="w-full pl-7 pr-2 py-1 text-xs bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-400"
              />
            </div>
            <button
              onClick={refreshEnv}
              disabled={envLoading || saving}
              className="p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
              title="Reload from .env"
              aria-label="Reload server configuration from .env file"
            >
              <RefreshCw className={`w-4 h-4 ${envLoading ? 'animate-spin' : ''}`} aria-hidden="true" />
            </button>
          </div>
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
      {/* DASH-ELEC-202: z-10 was insufficient — toasts/portals + later popovers
          can render above and bury the save bar. z-30 keeps it under modals
          (z-50) but always above page content. */}
      {(isDirty || restartPending) && (
        <div className="sticky bottom-2 z-30 flex items-center justify-between gap-3 px-4 py-3 rounded-lg border border-amber-900/60 bg-amber-950/40 backdrop-blur">
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
              <>
                <button
                  onClick={handleRestartServer}
                  disabled={restarting}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-amber-100 bg-amber-900/60 border border-amber-700 rounded hover:bg-amber-900/80 disabled:opacity-50"
                >
                  <RefreshCw className={`w-3.5 h-3.5 ${restarting ? 'animate-spin' : ''}`} />
                  {restarting ? 'Restarting…' : 'Restart Server'}
                </button>
                {/* DASH-ELEC-203: when the operator restarts the server out-of-band
                    (Server Control page, OS-level service restart), the in-app
                    `restartPending` flag has no auto-clear path and the banner
                    sticks forever. A manual Dismiss covers that case until a
                    boot-token poll lands. */}
                <button
                  onClick={() => setRestartPending(false)}
                  disabled={restarting}
                  aria-label="Dismiss restart-pending banner"
                  title="Dismiss (server already restarted out-of-band)"
                  className="px-3 py-1.5 text-xs font-medium text-surface-400 bg-surface-900 border border-surface-700 rounded hover:bg-surface-800 hover:text-surface-200 disabled:opacity-50"
                >
                  Dismiss
                </button>
              </>
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
            Database-backed configuration applied without a server restart.
          </p>
          <div className="space-y-4 pl-6">
            {pcSchema
              .filter((f) => matchesFilter(`${f.key} ${f.label} ${f.description} ${f.status ?? 'active'} ${f.statusReason ?? ''}`))
              .map((f) => {
              const current = pcDisplayValue(f);
              const busy = pcSaving === f.key;
              const inactiveMeta = inactivePlatformConfigMeta(f);
              const inactive = inactiveMeta !== null;
              if (f.kind === 'flag') {
                const checked = current === 'true';
                return (
                  // DASH-ELEC-200: aria-busy signals save in-progress to AT
                  // so screen readers don't announce an intermediate "off"
                  // checked-state while the server is still processing.
                  <label
                    key={f.key}
                    aria-busy={busy}
                    title={inactiveMeta?.reason}
                    className={`flex items-start gap-3 select-none ${inactive ? 'cursor-not-allowed opacity-75' : 'cursor-pointer'}`}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={busy || inactive}
                      onChange={(e) => handlePlatformConfigToggle(f, e.target.checked ? 'true' : 'false')}
                      className="mt-0.5 w-4 h-4 rounded border-surface-700 bg-surface-900 cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
                    />
                    <div className="flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm text-surface-200">{f.label}</span>
                        <code className="text-[10px] font-mono text-surface-600">{f.key}</code>
                        {inactiveMeta && (
                          <span className={`text-[10px] font-medium px-1.5 py-0.5 rounded border ${inactiveMeta.className}`}>
                            {inactiveMeta.label}
                          </span>
                        )}
                        {busy && <span className="text-[10px] text-amber-400">saving…</span>}
                      </div>
                      <p className="text-xs text-surface-500 mt-1 leading-relaxed">{f.description}</p>
                      {inactiveMeta && (
                        <p className="mt-1 flex items-start gap-1.5 text-[11px] leading-relaxed text-amber-300/90">
                          <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" aria-hidden="true" />
                          {inactiveMeta.reason}
                        </p>
                      )}
                    </div>
                  </label>
                );
              }
              const inputValue = pcInputValue(f);
              const dirty = !inactive && Object.prototype.hasOwnProperty.call(pcPending, f.key);
              const isSecret = f.kind === 'secret';
              const isRevealed = pcRevealed[f.key];
              return (
                <div key={f.key} aria-busy={busy} className="space-y-1.5">
                  <div className="flex items-center justify-between gap-2">
                    <label htmlFor={`pc-${f.key}`} className={`text-sm text-surface-300 ${inactive ? 'opacity-75' : ''}`}>
                      {f.label}
                      <code className="ml-2 text-[10px] font-mono text-surface-600">{f.key}</code>
                      {inactiveMeta && (
                        <span className={`ml-2 text-[10px] font-medium px-1.5 py-0.5 rounded border ${inactiveMeta.className}`}>
                          {inactiveMeta.label}
                        </span>
                      )}
                      {dirty && <span className="ml-2 text-[10px] text-amber-400">(modified)</span>}
                      {busy && <span className="ml-2 text-[10px] text-amber-400">saving…</span>}
                    </label>
                    {isSecret && f.hasValue && !dirty && (
                      <span className="text-[11px] text-emerald-500/80">
                        {f.length ? `${f.length}-char secret set` : 'secret set'}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      id={`pc-${f.key}`}
                      type={isSecret && !isRevealed ? 'password' : 'text'}
                      value={inputValue}
                      disabled={busy || inactive}
                      maxLength={isSecret ? 512 : 2048}
                      placeholder={f.placeholder ?? (isSecret && f.hasValue ? '(leave blank to keep current)' : '')}
                      title={inactiveMeta?.reason}
                      onChange={(e) => setPlatformConfigPendingValue(f, e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Escape') {
                          discardPlatformConfigPending(f.key);
                          return;
                        }
                        if (e.key === 'Enter' && dirty && !busy) {
                          void handlePlatformConfigValueSave(f);
                        }
                      }}
                      className="min-w-0 flex-1 px-3 py-1.5 text-sm bg-surface-950 border border-surface-700 rounded text-surface-200 focus:border-accent-600 focus:outline-none font-mono disabled:opacity-50"
                    />
                    {isSecret && (
                      <button
                        type="button"
                        onClick={() => setPcRevealed((r) => ({ ...r, [f.key]: !r[f.key] }))}
                        disabled={busy || inactive}
                        className="p-1.5 text-surface-500 hover:text-surface-300 disabled:opacity-50"
                        title={isRevealed ? 'Hide password' : 'Show password'}
                        aria-label={isRevealed ? 'Hide password' : 'Show password'}
                        aria-pressed={isRevealed}
                      >
                        {isRevealed ? <EyeOff className="w-4 h-4" aria-hidden="true" /> : <Eye className="w-4 h-4" aria-hidden="true" />}
                      </button>
                    )}
                    {dirty && (
                      <>
                        <button
                          type="button"
                          onClick={() => discardPlatformConfigPending(f.key)}
                          disabled={busy}
                          className="px-2 py-1.5 text-[11px] font-medium text-surface-400 bg-surface-900 border border-surface-700 rounded hover:bg-surface-800 hover:text-surface-200 disabled:opacity-50"
                        >
                          Discard
                        </button>
                        <button
                          type="button"
                          onClick={() => void handlePlatformConfigValueSave(f)}
                          disabled={busy}
                          className="flex items-center gap-1.5 px-2 py-1.5 text-[11px] font-medium text-emerald-100 bg-emerald-900/60 border border-emerald-700 rounded hover:bg-emerald-900/80 disabled:opacity-50"
                        >
                          <Save className={`w-3.5 h-3.5 ${busy ? 'animate-pulse' : ''}`} aria-hidden="true" />
                          {busy ? 'Saving…' : 'Save'}
                        </button>
                      </>
                    )}
                  </div>
                  <p className="text-xs text-surface-500 leading-relaxed">{f.description}</p>
                  {inactiveMeta && (
                    <p className="flex items-start gap-1.5 text-[11px] leading-relaxed text-amber-300/90">
                      <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" aria-hidden="true" />
                      {inactiveMeta.reason}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* System Info */}
      {/* DASH-ELEC-180: hCaptcha misconfiguration warning — replaces window.confirm. */}
      <ConfirmDialog
        open={confirmTarget === 'hcaptcha'}
        title="hCaptcha misconfiguration"
        message={
          'You are leaving HCAPTCHA_SECRET empty while requiring hCaptcha on signup. ' +
          'The server will refuse to boot. Continue saving anyway?'
        }
        confirmLabel="Save anyway"
        danger
        onConfirm={() => { setConfirmTarget(null); void executeSave(); }}
        onCancel={() => setConfirmTarget(null)}
      />
      {/* DASH-ELEC-194: Close Dashboard confirmation. */}
      <ConfirmDialog
        open={confirmTarget === 'closeDashboard'}
        title="Close Dashboard?"
        message="The CRM server will continue running as a Windows Service. Only the dashboard window will close."
        confirmLabel="Close Dashboard"
        onConfirm={() => { setConfirmTarget(null); getAPI().system.closeDashboard(); }}
        onCancel={() => setConfirmTarget(null)}
      />

      {systemInfo && (
        <section>
          <h2 className="text-sm font-semibold text-surface-300 mb-3 flex items-center gap-2">
            <Info className="w-4 h-4" />
            System Information
          </h2>
          {/* DASH-ELEC-183: collapse to a single column on the narrowest panel
              widths (compact density / sidebar-expanded settings) so long
              hostnames + version strings don't overflow the 32px gap.
              DASH-ELEC-179 (Fixer-B28 2026-04-25): tighter gap-x-4 + break-words
              on values so a long hostname or pre-release version string wraps
              instead of overflowing past the column edge into the neighbour. */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 text-xs">
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Platform</span>
              <span className="text-surface-300 text-right break-words min-w-0">{systemInfo.platform} ({systemInfo.arch})</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Hostname</span>
              <span className="text-surface-300 text-right break-all min-w-0">{systemInfo.hostname}</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Total Memory</span>
              <span className="text-surface-300 text-right break-words min-w-0">{formatBytes(systemInfo.totalMemory)}</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">CPUs</span>
              <span className="text-surface-300 text-right break-words min-w-0">{systemInfo.cpus} cores</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Node.js</span>
              <span className="text-surface-300 font-mono text-right break-all min-w-0">{systemInfo.nodeVersion}</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Electron</span>
              <span className="text-surface-300 font-mono text-right break-all min-w-0">{systemInfo.electronVersion}</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Dashboard</span>
              <span className="text-surface-300 font-mono text-right break-all min-w-0">v{systemInfo.appVersion}</span>
            </div>
            <div className="flex justify-between gap-2">
              <span className="text-surface-500 shrink-0">Packaged</span>
              <span className="text-surface-300 text-right break-words min-w-0">{systemInfo.isPackaged ? 'Yes' : 'No (dev)'}</span>
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
                    toast.error(formatApiError(res));
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

function DensityOption({ value, label }: { value: 'default' | 'compact'; label: string }) {
  const density = useUiStore((s) => s.density);
  const setDensity = useUiStore((s) => s.setDensity);
  const active = density === value;
  return (
    <button
      role="radio"
      aria-checked={active}
      onClick={() => setDensity(value)}
      className={`px-2 py-1 rounded border transition-colors ${
        active
          ? 'bg-accent-600/20 border-accent-600 text-accent-300'
          : 'border-surface-700 text-surface-400 hover:text-surface-200 hover:border-surface-600'
      }`}
    >
      {label}
    </button>
  );
}
