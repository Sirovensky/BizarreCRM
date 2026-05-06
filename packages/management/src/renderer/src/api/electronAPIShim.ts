/**
 * Browser shim for window.electronAPI.
 * ====================================
 *
 * Polyfills the Electron preload bridge so the same renderer SPA runs in:
 *   - Electron (desktop): real `window.electronAPI` is exposed by preload
 *   - Browser tab (served at /super-admin by the BizarreCRM server):
 *     this shim is installed instead, mapping every call to a same-origin
 *     `fetch` against the server's REST API.
 *
 * Loaded FIRST in main.tsx. Idempotent: if `window.electronAPI` already
 * exists (Electron context), the shim is a no-op.
 *
 * Why a shim instead of refactoring the renderer to call fetch directly:
 * the renderer has ~50 call sites that go through `getAPI().foo.bar()`.
 * A shim is one file; refactoring is fifty. Future cleanup can flatten
 * later. For now, the priority is parity with Electron at minimum lift.
 *
 * Coverage notes:
 *   - Most super-admin / management / admin calls are pure server REST
 *     passthroughs and map directly to fetch.
 *   - A handful (env editor, log tail, disk space, system info) require
 *     server endpoints that did NOT exist as REST routes — those routes
 *     are added under /super-admin/api/management/* (server side; see
 *     this commit's server changes).
 *   - Electron-only UX (window controls, open-external) becomes either
 *     a no-op or a browser equivalent (window.open).
 *   - Service control was previously `sc.exe` / `pm2` shelled out from
 *     Electron main; in browser context, this routes through new
 *     /super-admin/api/management/service/* endpoints.
 */

declare global {
  interface Window {
    electronAPI?: unknown;
  }
}

interface FetchOpts {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
  body?: unknown;
  query?: Record<string, string | number | boolean | undefined>;
}

/**
 * Super-admin JWT cache. Mirrors the Electron main process's
 * `getSuperAdminToken()` cache. Stored in sessionStorage so the token
 * survives a page reload (operator hits F5) but is cleared when the tab
 * closes — same TTL semantics as Electron's renderer-session-bound auth.
 *
 * The token is set after successful 2FA verify (the `/login/2fa-verify`
 * response includes `data.token`). Subsequent calls add it as a Bearer
 * Authorization header. A 401 response clears the token so the renderer
 * redirects to the login flow.
 */
const TOKEN_KEY = 'bizarrecrm.superAdminToken';
function getToken(): string | null {
  try { return sessionStorage.getItem(TOKEN_KEY); } catch { return null; }
}
function setToken(token: string | null): void {
  try {
    if (token) sessionStorage.setItem(TOKEN_KEY, token);
    else sessionStorage.removeItem(TOKEN_KEY);
  } catch { /* sessionStorage may be disabled — degrade silently */ }
}

interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  message?: string;
  code?: string;
  error?: string;
  offline?: boolean;
}

/**
 * Build a query string from a record. Skips undefined values so callers
 * can spread optional params without checking each one.
 */
function qs(params?: Record<string, string | number | boolean | undefined>): string {
  if (!params) return '';
  const usp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null) continue;
    usp.set(k, String(v));
  }
  const s = usp.toString();
  return s ? `?${s}` : '';
}

/**
 * Single fetch wrapper. Same-origin (no CORS), credentials:'include' so
 * the super-admin session cookie rides every call. Returns the JSON body
 * directly, normalizing into `ApiResponse` shape so the renderer doesn't
 * have to branch.
 *
 * Network errors and non-2xx responses are converted into ApiResponse
 * objects (success:false) rather than thrown — matches the existing
 * IPC behaviour where the main process catch wrapped errors into
 * `{ success: false, message }`.
 */
async function api<T = unknown>(url: string, opts: FetchOpts = {}): Promise<ApiResponse<T>> {
  const fullUrl = url + qs(opts.query);
  try {
    const headers: Record<string, string> = {};
    if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
    const token = getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const init: RequestInit = {
      method: opts.method || 'GET',
      credentials: 'include',
      headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    };
    const res = await fetch(fullUrl, init);
    // 401 means our cached token expired or was invalidated. Clear it so
    // the renderer's existing 401-detection / auto-logout flow triggers
    // a redirect to login (see handleApiResponse in renderer/utils).
    if (res.status === 401) setToken(null);
    if (res.status === 0) {
      return { success: false, offline: true, message: 'Network unreachable' };
    }
    let body: unknown = null;
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      body = await res.json().catch(() => null);
    } else {
      // Server may return plain text on 4xx/5xx. Wrap in a fake envelope.
      const text = await res.text().catch(() => '');
      body = { success: res.ok, message: text || `HTTP ${res.status}` };
    }
    if (!res.ok) {
      const env = (body as ApiResponse<T>) || {};
      return { success: false, ...env, code: env.code || `HTTP_${res.status}` };
    }
    return body as ApiResponse<T>;
  } catch (err) {
    // Most likely TypeError from fetch (DNS / connect refused / TLS).
    return {
      success: false,
      offline: true,
      message: err instanceof Error ? err.message : 'Network error',
    };
  }
}

/**
 * Build the shim. Lazy + idempotent: only installs if window.electronAPI
 * is missing. Returns void; the side effect IS the shim install.
 */
export function installBrowserShim(): void {
  if (typeof window === 'undefined') return;
  if (window.electronAPI) return; // Electron exposes the real bridge.

  const shim = {
    // ─── management:* ────────────────────────────────────────────
    management: {
      setupStatus: () => api('/api/v1/management/setup-status'),
      setup: (username: string, password: string) =>
        api('/api/v1/management/setup', { method: 'POST', body: { username, password } }),
      logout: () => api('/api/v1/management/logout', { method: 'POST' }),
      getStats: () => api('/api/v1/management/stats'),
      getStatsHistory: (range: string) => api('/api/v1/management/stats/history', { query: { range } }),
      getCrashes: () => api('/api/v1/management/crashes'),
      getCrashStats: () => api('/api/v1/management/crash-stats'),
      getDisabledRoutes: () => api('/api/v1/management/disabled-routes'),
      reenableRoute: (route: string) => api('/api/v1/management/reenable-route', { method: 'POST', body: { route } }),
      clearCrashes: () => api('/api/v1/management/clear-crashes', { method: 'POST' }),
      getUpdateStatus: () => api('/api/v1/management/update-status'),
      checkUpdates: () => api('/api/v1/management/check-updates', { method: 'POST' }),
      performUpdate: () => api('/api/v1/management/perform-update', { method: 'POST' }),
      getRollbackInfo: () => api('/api/v1/management/rollback-info'),
      rollbackUpdate: () => api('/api/v1/management/rollback-update', { method: 'POST' }),
      clearRollback: () => api('/api/v1/management/clear-rollback', { method: 'POST' }),
      auditUpdateResult: (payload: unknown) => api('/api/v1/management/audit-update-result', { method: 'POST', body: payload }),
      restartServer: () => api('/api/v1/management/restart', { method: 'POST' }),
      stopServer: () => api('/api/v1/management/stop', { method: 'POST' }),
      // Watchdog events handlers added in this session at /super-admin/api/management/
      getWatchdogEvents: () => api('/super-admin/api/management/watchdog-events'),
      clearWatchdogEvents: () => api('/super-admin/api/management/watchdog-events', { method: 'DELETE' }),
    },

    // ─── super-admin:* ───────────────────────────────────────────
    superAdmin: {
      login: (username: string, password: string) =>
        api('/super-admin/api/login', { method: 'POST', body: { username, password } }),
      // 2FA verify is the success terminus — response.data.token is the
      // super-admin JWT. Cache it for subsequent authenticated calls.
      verify2fa: async (challengeToken: string, code: string) => {
        const res = await api<{ token?: string }>('/super-admin/api/login/2fa-verify', { method: 'POST', body: { challengeToken, code } });
        if (res.success && res.data && typeof res.data.token === 'string') {
          setToken(res.data.token);
        }
        return res;
      },
      // 2FA setup also returns a token if the operator just completed
      // first-time setup (see super-admin.routes.ts `2fa-setup` flow).
      setup2fa: async (challengeToken: string) => {
        const res = await api<{ token?: string }>('/super-admin/api/login/2fa-setup', { method: 'POST', body: { challengeToken } });
        if (res.success && res.data && typeof res.data.token === 'string') {
          setToken(res.data.token);
        }
        return res;
      },
      setPassword: async (challengeToken: string, password: string) => {
        const res = await api<{ token?: string }>('/super-admin/api/login/set-password', { method: 'POST', body: { challengeToken, password } });
        if (res.success && res.data && typeof res.data.token === 'string') {
          setToken(res.data.token);
        }
        return res;
      },
      getDashboard: () => api('/super-admin/api/dashboard'),
      listTenants: () => api('/super-admin/api/tenants'),
      createTenant: (data: unknown) => api('/super-admin/api/tenants', { method: 'POST', body: data }),
      getTenant: (slug: string) => api(`/super-admin/api/tenants/${encodeURIComponent(slug)}`),
      suspendTenant: (slug: string) => api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/suspend`, { method: 'POST' }),
      activateTenant: (slug: string) => api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/activate`, { method: 'POST' }),
      deleteTenant: (slug: string) => api(`/super-admin/api/tenants/${encodeURIComponent(slug)}`, { method: 'DELETE' }),
      repairTenant: (slug: string) => api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/repair`, { method: 'POST' }),
      getAuditLog: (params?: Record<string, string | number | boolean | undefined>) => api('/super-admin/api/audit-log', { query: params }),
      getSessions: () => api('/super-admin/api/sessions'),
      revokeSession: (id: string) => api(`/super-admin/api/sessions/${encodeURIComponent(id)}`, { method: 'DELETE' }),
      getConfig: () => api('/super-admin/api/config'),
      getConfigSchema: () => api('/super-admin/api/config-schema'),
      updateConfig: (updates: unknown) => api('/super-admin/api/config', { method: 'PUT', body: updates }),
      listSecurityAlerts: (params?: Record<string, string | number | boolean | undefined>) => api('/super-admin/api/security-alerts', { query: params }),
      acknowledgeAlert: (id: number) => api(`/super-admin/api/security-alerts/${id}/acknowledge`, { method: 'POST' }),
      acknowledgeAllAlerts: () => api('/super-admin/api/security-alerts/acknowledge-all', { method: 'POST' }),
      resetRateLimits: () => api('/super-admin/api/rate-limits/reset', { method: 'POST' }),
      listRateLimits: () => api('/super-admin/api/rate-limits'),
      rotateJwtSecret: (purpose?: 'access' | 'refresh' | 'both') => api('/super-admin/api/rotate-jwt-secret', { method: 'POST', body: { purpose: purpose ?? 'both' } }),
      backfillCloudflareDns: () => api('/super-admin/api/backfill-cloudflare-dns', { method: 'POST' }),
      listTenantAuthEvents: (params: { slug: string; [k: string]: unknown }) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(params.slug)}/auth-events`, { query: params as never }),
      listTenantNotifications: (params: { slug: string; [k: string]: unknown }) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(params.slug)}/notifications`, { query: params as never }),
      listTenantWebhookFailures: (params: { slug: string; [k: string]: unknown }) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(params.slug)}/webhook-failures`, { query: params as never }),
      retryTenantWebhookFailure: (params: { slug: string; id: number }) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(params.slug)}/webhook-failures/${params.id}/retry`, { method: 'POST' }),
      listTenantAutomationRuns: (params: { slug: string; [k: string]: unknown }) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(params.slug)}/automation-runs`, { query: params as never }),
      // Per-tenant backup management (added earlier this session)
      tenantBackupList: (slug: string) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/backups`),
      tenantBackupRun: (slug: string) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/backups`, { method: 'POST' }),
      tenantBackupDelete: (slug: string, filename: string) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/backups/${encodeURIComponent(filename)}`, { method: 'DELETE' }),
      tenantBackupRestore: (slug: string, filename: string) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/backups/${encodeURIComponent(filename)}/restore`, { method: 'POST' }),
      tenantBackupSettingsGet: (slug: string) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/backup-settings`),
      tenantBackupSettingsUpdate: (slug: string, settings: unknown) =>
        api(`/super-admin/api/tenants/${encodeURIComponent(slug)}/backup-settings`, { method: 'PUT', body: settings }),
      backupDrives: () => api('/super-admin/api/backup-drives'),
    },

    // ─── admin:* (single-tenant backup + env editor + log viewer) ──
    admin: {
      getStatus: () => api('/api/v1/admin/status'),
      listDrives: () => api('/api/v1/admin/drives'),
      browseDrive: (drivePath: string) => api('/api/v1/admin/drives/browse', { query: { path: drivePath } }),
      createFolder: (parentPath: string, name: string) =>
        api('/api/v1/admin/drives/mkdir', { method: 'POST', body: { path: parentPath, name } }),
      listBackups: () => api('/api/v1/admin/backups'),
      runBackup: () => api('/api/v1/admin/backup', { method: 'POST' }),
      updateBackupSettings: (settings: unknown) => api('/api/v1/admin/backup-settings', { method: 'PUT', body: settings }),
      deleteBackup: (filename: string) => api(`/api/v1/admin/backups/${encodeURIComponent(filename)}`, { method: 'DELETE' }),
      restoreBackup: (filename: string) => api(`/api/v1/admin/backups/${encodeURIComponent(filename)}/restore`, { method: 'POST' }),
      // Env editor + log viewer hit new server endpoints under
      // /super-admin/api/management/env and /super-admin/api/management/logs.
      // The IPC names stay 'admin:get-env-settings' for renderer compat;
      // the underlying URL is super-admin-gated.
      getEnvSettings: () => api('/super-admin/api/management/env'),
      setEnvSettings: (updates: unknown) => api('/super-admin/api/management/env', { method: 'PUT', body: updates }),
      listLogs: () => api('/super-admin/api/management/logs'),
      tailLog: (params: { name: string; lines?: number }) =>
        api('/super-admin/api/management/logs/tail', { query: params }),
    },

    // ─── service:* (PM2 / Windows Service control) ──────────────────
    service: {
      getStatus: () => api('/super-admin/api/management/service/status'),
      start: () => api('/super-admin/api/management/service/start', { method: 'POST' }),
      stop: () => api('/super-admin/api/management/service/stop', { method: 'POST' }),
      restart: () => api('/super-admin/api/management/service/restart', { method: 'POST' }),
      emergencyStop: () => api('/super-admin/api/management/service/emergency-stop', { method: 'POST' }),
      killAll: () => api('/super-admin/api/management/service/kill-all', { method: 'POST' }),
      setAutoStart: (enabled: boolean) => api('/super-admin/api/management/service/auto-start', { method: 'POST', body: { enabled } }),
      disable: () => api('/super-admin/api/management/service/disable', { method: 'POST' }),
    },

    // ─── system:* — host info + window controls + URL opening ─────
    system: {
      getDiskSpace: () => api('/super-admin/api/management/system/disk-space'),
      getInfo: () => api('/super-admin/api/management/system/info'),
      // Open links in a new browser tab. window.open with noopener is the
      // browser equivalent of Electron's shell.openExternal.
      openBrowser: () => {
        // The Electron version opened the CRM root in the system browser.
        // From a browser tab, that's the current site root.
        try { window.open('/', '_blank', 'noopener'); } catch { /* popup blocker */ }
        return Promise.resolve({ success: true });
      },
      openExternal: (url: string) => {
        try { window.open(url, '_blank', 'noopener'); } catch { /* popup blocker */ }
        return Promise.resolve({ success: true });
      },
      openLogFile: () => {
        // No filesystem access from browser. Surface logs page instead.
        try { window.location.hash = '#/server-logs'; } catch { /* ignore */ }
        return Promise.resolve({ success: true });
      },
      // Electron-only UX. Browser-served dashboards have no native window
      // chrome; these become no-ops. Dashboard UI hides them when
      // `window.isElectron` is false (we set this below).
      closeDashboard: () => Promise.resolve({ success: true }),
      minimize: () => Promise.resolve({ success: true }),
      maximize: () => Promise.resolve({ success: true }),
      // Cert pinning + tag verification are Electron-specific (they protect
      // the IPC channel between renderer + main process binary). Browser
      // context uses the OS TLS chain; report an explicit "not applicable"
      // status so the renderer's banner UI can hide the warnings.
      getCertPinningStatus: () => Promise.resolve({ success: true, data: { pinned: true, mode: 'browser' } }),
      getTagVerifyStatus: () => Promise.resolve({ success: true, data: { verified: true, mode: 'browser' } }),
    },
  };

  Object.defineProperty(window, 'electronAPI', { value: shim, writable: false, configurable: false });
  // Renderer code can branch on this if needed. Most code doesn't need to.
  Object.defineProperty(window, 'isElectron', { value: false, writable: false, configurable: false });
}
