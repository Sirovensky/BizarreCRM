/**
 * Preload Script — Secure IPC bridge between renderer and main process.
 * All dashboard auth goes through the super admin 2FA flow.
 *
 * MUST be compiled to CommonJS (Electron preload requirement).
 *
 * @audit-fixed: hardened the preload bridge with a channel allow-list and a
 * runtime guard around `ipcRenderer.invoke`. Previously every method here
 * called `safeInvoke('some:channel', ...)` directly, which meant
 * a typo on a channel name would silently no-op (the main process would
 * never register that channel) AND a future maintainer who copy-pasted a
 * method body could accidentally call an arbitrary channel. The wrapper
 * `safeInvoke` rejects any channel that isn't in `ALLOWED_CHANNELS`, so
 * (a) typos fail loudly during development and (b) a renderer compromise
 * cannot enumerate or call channels that the dashboard never intended
 * to expose. We do NOT expose `ipcRenderer`, `require`, `fs`, `path`,
 * or any other Node primitive on the window — only the `electronAPI`
 * facade with hard-coded methods.
 */
const { contextBridge, ipcRenderer, webUtils } = require('electron');

type ApiResponse<T = unknown> = {
  success: boolean;
  data?: T;
  message?: string;
  offline?: boolean;
  code?: string;
  request_id?: string;
  status?: number;
  error?: string;
};

type SetupStatus = {
  needsSetup: boolean;
  managementApiEnabled: boolean;
  multiTenant: boolean;
};

type WatchdogEvent = {
  kind: 'restart' | 'fatal' | 'cascade-abort' | 'extended-grace' | 'cert-expired';
  timestamp: string;
  reason: string;
  longTask?: { kind: string; startedAt: number; expectedDurationMs: number; details?: Record<string, unknown> } | null;
  cascadeAbort?: boolean;
};

type ServiceStatus = {
  state: 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown' | 'not_installed';
  pid: number | null;
  startType: 'auto' | 'demand' | 'disabled' | 'unknown';
  mode: 'service' | 'pm2' | 'direct' | 'none';
};

type DiskDrive = {
  mount: string;
  total: number;
  free: number;
  used: number;
};

type SystemInfo = {
  platform: string;
  arch: string;
  hostname: string;
  totalMemory: number;
  freeMemory: number;
  cpus: number;
  nodeVersion: string;
  electronVersion: string;
  appVersion: string;
  isPackaged: boolean;
};

type CertPinningStatus = {
  enabled: boolean;
  reason?: string;
  validTo?: string;
  daysUntilExpiry?: number;
};

type TenantCreateResult = {
  tenant_id: number;
  slug: string;
  url: string;
  setup_url: string;
};

type TenantUpdatePayload = {
  slug: string;
  plan?: string;
  name?: string;
};

type BackupSettings = {
  backup_path: string;
  schedule: string;
  retention_days: number;
  encryption_enabled: boolean;
  last_backup: string;
  last_status: string;
};

type BackupSettingsPayload = Pick<BackupSettings,
  'backup_path' | 'schedule' | 'retention_days' | 'encryption_enabled'
>;

type EnvConnectionTestTarget = 'captcha' | 'stripe' | 'cloudflare';
type EnvConnectionTestResult = {
  target: EnvConnectionTestTarget;
  status: 'pass' | 'warn' | 'fail';
  summary: string;
  checkedAt: string;
  details: Array<{
    label: string;
    value: string;
    tone?: 'success' | 'warning' | 'danger' | 'muted';
  }>;
};

type ChannelSpec<Args extends unknown[], Result> = {
  args: Args;
  result: Result;
};

type IpcChannelMap = {
  'management:setup-status': ChannelSpec<[], ApiResponse<SetupStatus>>;
  'management:setup': ChannelSpec<[username: string, password: string], ApiResponse>;
  'management:logout': ChannelSpec<[], ApiResponse>;
  'management:get-stats': ChannelSpec<[], ApiResponse<Record<string, unknown>>>;
  'management:get-stats-history': ChannelSpec<[range: string], ApiResponse<Array<Record<string, unknown>>>>;
  'management:get-crashes': ChannelSpec<[], ApiResponse<Array<Record<string, unknown>>>>;
  'management:get-crash-stats': ChannelSpec<[], ApiResponse<Record<string, unknown>>>;
  'management:get-disabled-routes': ChannelSpec<[], ApiResponse<Array<Record<string, unknown>>>>;
  'management:reenable-route': ChannelSpec<[route: string], ApiResponse>;
  'management:clear-crashes': ChannelSpec<[], ApiResponse>;
  'management:get-update-status': ChannelSpec<[], ApiResponse>;
  'management:check-updates': ChannelSpec<[], ApiResponse>;
  'management:perform-update': ChannelSpec<[], ApiResponse>;
  'management:get-rollback-info': ChannelSpec<[], ApiResponse<{ available: boolean; sha?: string }>>;
  'management:rollback-update': ChannelSpec<[], ApiResponse<{ sha: string; stdout: string }>>;
  'management:clear-rollback': ChannelSpec<[], ApiResponse>;
  'management:audit-update-result': ChannelSpec<[payload: { success: boolean; afterSha?: string; errorMessage?: string }], ApiResponse>;
  'management:restart-server': ChannelSpec<[], ApiResponse>;
  'management:stop-server': ChannelSpec<[], ApiResponse>;
  'management:get-watchdog-events': ChannelSpec<[], { ok: boolean; code?: string; message?: string; events: WatchdogEvent[] }>;
  'management:clear-watchdog-events': ChannelSpec<[], { ok: boolean; code?: string; message?: string }>;
  'super-admin:login': ChannelSpec<[username: string, password: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:2fa-verify': ChannelSpec<[challengeToken: string, code: string], ApiResponse<{ token: string }>>;
  'super-admin:2fa-setup': ChannelSpec<[challengeToken: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:set-password': ChannelSpec<[challengeToken: string, password: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:get-dashboard': ChannelSpec<[], ApiResponse>;
  'super-admin:list-tenants': ChannelSpec<[], ApiResponse<{ tenants: Array<Record<string, unknown>> }>>;
  'super-admin:create-tenant': ChannelSpec<[data: unknown], ApiResponse<TenantCreateResult>>;
  'super-admin:get-tenant': ChannelSpec<[slug: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:update-tenant': ChannelSpec<[payload: TenantUpdatePayload], ApiResponse<Record<string, unknown>>>;
  'super-admin:suspend-tenant': ChannelSpec<[slug: string], ApiResponse>;
  'super-admin:activate-tenant': ChannelSpec<[slug: string], ApiResponse>;
  'super-admin:delete-tenant': ChannelSpec<[slug: string], ApiResponse>;
  'super-admin:repair-tenant': ChannelSpec<[slug: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:get-audit-log': ChannelSpec<[params?: unknown], ApiResponse<Array<Record<string, unknown>> | { logs?: Array<Record<string, unknown>> }>>;
  'super-admin:get-sessions': ChannelSpec<[], ApiResponse<Array<Record<string, unknown>> | { sessions?: Array<Record<string, unknown>> }>>;
  'super-admin:revoke-session': ChannelSpec<[id: string], ApiResponse>;
  'super-admin:revoke-all-sessions': ChannelSpec<[], ApiResponse<{ revoked: true; count: number }>>;
  'super-admin:get-config': ChannelSpec<[], ApiResponse<Record<string, string>>>;
  'super-admin:get-config-schema': ChannelSpec<[], ApiResponse<{ fields: Array<Record<string, unknown>> }>>;
  'super-admin:update-config': ChannelSpec<[updates: Record<string, string>], ApiResponse>;
  'super-admin:list-security-alerts': ChannelSpec<[params?: unknown], ApiResponse<Record<string, unknown>>>;
  'super-admin:acknowledge-alert': ChannelSpec<[id: number], ApiResponse<{ message: string }>>;
  'super-admin:acknowledge-all-alerts': ChannelSpec<[], ApiResponse<{ count: number }>>;
  'super-admin:reset-rate-limits': ChannelSpec<[payload: { tenantSlug?: string; all?: boolean; totpCode: string }], ApiResponse<Record<string, unknown>>>;
  'super-admin:list-rate-limits': ChannelSpec<[payload: { lockedOnly?: boolean; limit?: number }], ApiResponse<Record<string, unknown>>>;
  'super-admin:rotate-jwt-secret': ChannelSpec<[purpose: 'access' | 'refresh' | 'both', totpCode: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:backfill-cloudflare-dns': ChannelSpec<[totpCode: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:list-tenant-auth-events': ChannelSpec<[params?: unknown], ApiResponse<Record<string, unknown>>>;
  'super-admin:list-tenant-notifications': ChannelSpec<[params: { slug: string; status?: string; type?: string; limit?: number }], ApiResponse<Record<string, unknown>>>;
  'super-admin:list-tenant-webhook-failures': ChannelSpec<[params: { slug: string; event?: string; limit?: number }], ApiResponse<Record<string, unknown>>>;
  'super-admin:retry-tenant-webhook-failure': ChannelSpec<[params: { slug: string; id: number }], ApiResponse<Record<string, unknown>>>;
  'super-admin:list-tenant-automation-runs': ChannelSpec<[params: { slug: string; status?: string; automationId?: number; limit?: number }], ApiResponse<Record<string, unknown>>>;
  'super-admin:tenant-backup-list': ChannelSpec<[slug: string], ApiResponse<Array<{ name: string; size: number; date: string }>>>;
  'super-admin:tenant-backup-run': ChannelSpec<[slug: string], ApiResponse<{ success: boolean; message: string; file?: string }>>;
  'super-admin:tenant-backup-delete': ChannelSpec<[slug: string, filename: string], ApiResponse>;
  'super-admin:tenant-backup-restore': ChannelSpec<[slug: string, filename: string], ApiResponse<Record<string, unknown>>>;
  'super-admin:tenant-backup-settings-get': ChannelSpec<[slug: string], ApiResponse<BackupSettings>>;
  'super-admin:tenant-backup-settings-update': ChannelSpec<[slug: string, settings: BackupSettingsPayload], ApiResponse<BackupSettings>>;
  'super-admin:backup-drives': ChannelSpec<[], ApiResponse<DiskDrive[]>>;
  'admin:get-status': ChannelSpec<[], ApiResponse>;
  'admin:list-drives': ChannelSpec<[], ApiResponse>;
  'admin:browse-drive': ChannelSpec<[path: string], ApiResponse>;
  'admin:create-folder': ChannelSpec<[parentPath: string, name: string], ApiResponse>;
  'admin:list-backups': ChannelSpec<[], ApiResponse>;
  'admin:download-backup': ChannelSpec<[filename: string], ApiResponse<{ path: string; metadataPath: string | null }>>;
  'admin:upload-backup': ChannelSpec<[payload: { sourcePath: string }], ApiResponse<{ filename: string; metadataCopied: boolean }>>;
  'admin:run-backup': ChannelSpec<[], ApiResponse>;
  'admin:update-backup-settings': ChannelSpec<[settings: BackupSettingsPayload], ApiResponse<BackupSettings>>;
  'admin:delete-backup': ChannelSpec<[filename: string], ApiResponse>;
  'admin:restore-backup': ChannelSpec<[filename: string], ApiResponse<Record<string, unknown>>>;
  'admin:get-env-settings': ChannelSpec<[], ApiResponse<{ fields: Array<Record<string, unknown>> }>>;
  'admin:set-env-settings': ChannelSpec<[updates: Record<string, string>], ApiResponse<{ keysUpdated: string[]; requiresRestart: boolean }>>;
  'admin:test-env-connection': ChannelSpec<[target: EnvConnectionTestTarget], ApiResponse<EnvConnectionTestResult>>;
  'admin:list-logs': ChannelSpec<[], ApiResponse<Record<string, unknown>>>;
  'admin:tail-log': ChannelSpec<[payload: { name: string; lines: number }], ApiResponse<Record<string, unknown>>>;
  'service:get-status': ChannelSpec<[], ServiceStatus>;
  'service:start': ChannelSpec<[], ApiResponse>;
  'service:stop': ChannelSpec<[], ApiResponse>;
  'service:restart': ChannelSpec<[], ApiResponse>;
  'service:emergency-stop': ChannelSpec<[], ApiResponse>;
  'service:kill-all': ChannelSpec<[], ApiResponse>;
  'service:set-auto-start': ChannelSpec<[enabled: boolean], ApiResponse>;
  'service:disable': ChannelSpec<[], ApiResponse>;
  'system:get-disk-space': ChannelSpec<[], ApiResponse<DiskDrive[]>>;
  'system:get-info': ChannelSpec<[], ApiResponse<SystemInfo>>;
  'system:open-browser': ChannelSpec<[], ApiResponse>;
  'system:open-external': ChannelSpec<[url: string], ApiResponse>;
  'system:open-log-file': ChannelSpec<[], ApiResponse>;
  'system:close-dashboard': ChannelSpec<[], ApiResponse>;
  'system:minimize': ChannelSpec<[], ApiResponse>;
  'system:maximize': ChannelSpec<[], ApiResponse>;
  'system:get-cert-pinning-status': ChannelSpec<[], ApiResponse<CertPinningStatus>>;
  'system:get-tag-verify-status': ChannelSpec<[], ApiResponse<{ bypass: boolean }>>;
};

type IpcChannel = keyof IpcChannelMap;
type IpcArgs<C extends IpcChannel> = IpcChannelMap[C]['args'];
type IpcResult<C extends IpcChannel> = IpcChannelMap[C]['result'];
type AnyIpcResult = IpcChannelMap[IpcChannel]['result'];

type IpcEventMap = {
  'system:power-resume': [];
};

type IpcEvent = keyof IpcEventMap;
type IpcEventArgs<C extends IpcEvent> = IpcEventMap[C];

// @audit-fixed: explicit channel allow-list. Adding a new IPC handler
// requires updating BOTH the main-process registration AND this list,
// which makes accidental channel proliferation impossible.
const ALLOWED_CHANNEL_LIST = [
  // management:*
  'management:setup-status',
  'management:setup',
  'management:logout',
  'management:get-stats',
  'management:get-stats-history',
  'management:get-crashes',
  'management:get-crash-stats',
  'management:get-disabled-routes',
  'management:reenable-route',
  'management:clear-crashes',
  'management:get-update-status',
  'management:check-updates',
  'management:perform-update',
  'management:get-rollback-info',
  'management:rollback-update',
  'management:clear-rollback',
  'management:audit-update-result',
  'management:restart-server',
  'management:stop-server',
  'management:get-watchdog-events',
  'management:clear-watchdog-events',
  // super-admin:*
  'super-admin:login',
  'super-admin:2fa-verify',
  'super-admin:2fa-setup',
  'super-admin:set-password',
  'super-admin:get-dashboard',
  'super-admin:list-tenants',
  'super-admin:create-tenant',
  'super-admin:get-tenant',
  'super-admin:update-tenant',
  'super-admin:suspend-tenant',
  'super-admin:activate-tenant',
  'super-admin:delete-tenant',
  'super-admin:repair-tenant',
  'super-admin:get-audit-log',
  'super-admin:get-sessions',
  'super-admin:revoke-session',
  'super-admin:revoke-all-sessions',
  'super-admin:get-config',
  'super-admin:get-config-schema',
  'super-admin:update-config',
  'super-admin:list-security-alerts',
  'super-admin:acknowledge-alert',
  'super-admin:acknowledge-all-alerts',
  'super-admin:reset-rate-limits',
  'super-admin:list-rate-limits',
  'super-admin:rotate-jwt-secret',
  'super-admin:backfill-cloudflare-dns',
  'super-admin:list-tenant-auth-events',
  'super-admin:list-tenant-notifications',
  'super-admin:list-tenant-webhook-failures',
  'super-admin:retry-tenant-webhook-failure',
  'super-admin:list-tenant-automation-runs',
  'super-admin:tenant-backup-list',
  'super-admin:tenant-backup-run',
  'super-admin:tenant-backup-delete',
  'super-admin:tenant-backup-restore',
  'super-admin:tenant-backup-settings-get',
  'super-admin:tenant-backup-settings-update',
  'super-admin:backup-drives',
  // admin:* (backup)
  'admin:get-status',
  'admin:list-drives',
  'admin:browse-drive',
  'admin:create-folder',
  'admin:list-backups',
  'admin:download-backup',
  'admin:upload-backup',
  'admin:run-backup',
  'admin:update-backup-settings',
  'admin:delete-backup',
  'admin:restore-backup',
  // admin:* (env-settings editor — edits .env directly)
  'admin:get-env-settings',
  'admin:set-env-settings',
  'admin:test-env-connection',
  // admin:* (log viewer — reads logs/ files directly via fs)
  'admin:list-logs',
  'admin:tail-log',
  // service:* (sc.exe / pm2)
  'service:get-status',
  'service:start',
  'service:stop',
  'service:restart',
  'service:emergency-stop',
  'service:kill-all',
  'service:set-auto-start',
  'service:disable',
  // system:*
  'system:get-disk-space',
  'system:get-info',
  'system:open-browser',
  'system:open-external',
  'system:open-log-file',
  'system:close-dashboard',
  'system:minimize',
  'system:maximize',
  // AUDIT-MGT-006: cert pinning status for the renderer warning banner
  'system:get-cert-pinning-status',
  // AUDIT-MGT-018: signed-tag verification bypass status for the renderer warning banner
  'system:get-tag-verify-status',
] as const satisfies readonly IpcChannel[];

const ALLOWED_CHANNELS: ReadonlySet<IpcChannel> = new Set(ALLOWED_CHANNEL_LIST);

const ALLOWED_EVENTS_LIST = [
  'system:power-resume',
] as const satisfies readonly IpcEvent[];

const ALLOWED_EVENTS: ReadonlySet<IpcEvent> = new Set(ALLOWED_EVENTS_LIST);

function safeInvoke<C extends IpcChannel>(channel: C, ...args: IpcArgs<C>): Promise<IpcResult<C>> {
  if (!ALLOWED_CHANNELS.has(channel)) {
    // Reject loudly so a typo or compromised script can't probe channels.
    return Promise.reject(
      new Error(`[preload] Refusing to invoke unknown IPC channel: ${channel}`)
    );
  }
  return ipcRenderer.invoke(channel, ...args) as Promise<IpcResult<C>>;
}

function safeOn<C extends IpcEvent>(channel: C, listener: (...args: IpcEventArgs<C>) => void): () => void {
  if (!ALLOWED_EVENTS.has(channel)) {
    throw new Error(`[preload] Refusing to listen on unknown IPC channel: ${channel}`);
  }
  const handler = (_event: unknown, ...args: unknown[]) => {
    listener(...args as IpcEventArgs<C>);
  };
  ipcRenderer.on(channel, handler);
  return () => {
    ipcRenderer.removeListener(channel, handler);
  };
}

// DASH-ELEC-007: deduplication wrapper for hot-path IPC channels (stats,
// disk-space). If a call is already in flight for the same channel+args key,
// callers share the single in-flight Promise instead of spawning N parallel
// requests. Keyed by channel + JSON-serialised args so concurrent calls with
// different arguments still resolve independently.
const _inFlight = new Map<string, Promise<AnyIpcResult>>();

function dedupInvoke<C extends IpcChannel>(channel: C, ...args: IpcArgs<C>): Promise<IpcResult<C>> {
  const key = args.length === 0 ? channel : `${channel}:${JSON.stringify(args)}`;
  const existing = _inFlight.get(key) as Promise<IpcResult<C>> | undefined;
  if (existing) return existing;
  const p = safeInvoke(channel, ...args).finally(() => {
    _inFlight.delete(key);
  });
  _inFlight.set(key, p as Promise<AnyIpcResult>);
  return p;
}

contextBridge.exposeInMainWorld('electronAPI', {
  // ── Management API ─────────────────────────────────────────────
  management: {
    setupStatus: () => safeInvoke('management:setup-status'),
    logout: () => safeInvoke('management:logout'),
    setup: (username: string, password: string) => safeInvoke('management:setup', username, password),
    getStats: () => dedupInvoke('management:get-stats'),
    getStatsHistory: (range: string) => safeInvoke('management:get-stats-history', range),
    getCrashes: () => safeInvoke('management:get-crashes'),
    getCrashStats: () => safeInvoke('management:get-crash-stats'),
    getDisabledRoutes: () => safeInvoke('management:get-disabled-routes'),
    reenableRoute: (route: string) => safeInvoke('management:reenable-route', route),
    clearCrashes: () => safeInvoke('management:clear-crashes'),
    getUpdateStatus: () => safeInvoke('management:get-update-status'),
    checkUpdates: () => safeInvoke('management:check-updates'),
    performUpdate: () => safeInvoke('management:perform-update'),
    getRollbackInfo: () => safeInvoke('management:get-rollback-info'),
    rollbackUpdate: () => safeInvoke('management:rollback-update'),
    clearRollback: () => safeInvoke('management:clear-rollback'),
    // MGT-028: expose audit-update-result so UpdatesPage can record the
    // final outcome (success/fail + afterSha) once the dashboard reopens
    // after a completed update attempt.
    auditUpdateResult: (payload: { success: boolean; afterSha?: string; errorMessage?: string }) =>
      safeInvoke('management:audit-update-result', payload),
    restartServer: () => safeInvoke('management:restart-server'),
    stopServer: () => safeInvoke('management:stop-server'),
    // Watchdog: poll for recent events emitted by packages/server/scripts/watchdog.cjs.
    // Returns at most the last 200 events. ServerControlPage polls this every 5s.
    getWatchdogEvents: () => safeInvoke('management:get-watchdog-events'),
    clearWatchdogEvents: () => safeInvoke('management:clear-watchdog-events'),
  },

  // ── Super-Admin Auth (2FA) ─────────────────────────────────────
  superAdmin: {
    login: (username: string, password: string) =>
      safeInvoke('super-admin:login', username, password),
    verify2fa: (challengeToken: string, code: string) =>
      safeInvoke('super-admin:2fa-verify', challengeToken, code),
    setup2fa: (challengeToken: string) =>
      safeInvoke('super-admin:2fa-setup', challengeToken),
    setPassword: (challengeToken: string, password: string) =>
      safeInvoke('super-admin:set-password', challengeToken, password),
    getDashboard: () => safeInvoke('super-admin:get-dashboard'),
    listTenants: () => safeInvoke('super-admin:list-tenants'),
    createTenant: (data: unknown) => safeInvoke('super-admin:create-tenant', data),
    getTenant: (slug: string) => safeInvoke('super-admin:get-tenant', slug),
    updateTenant: (payload: TenantUpdatePayload) => safeInvoke('super-admin:update-tenant', payload),
    suspendTenant: (slug: string) => safeInvoke('super-admin:suspend-tenant', slug),
    activateTenant: (slug: string) => safeInvoke('super-admin:activate-tenant', slug),
    deleteTenant: (slug: string) => safeInvoke('super-admin:delete-tenant', slug),
    repairTenant: (slug: string) => safeInvoke('super-admin:repair-tenant', slug),
    // AUDIT-MGT-008: pass typed object; query string built main-side.
    getAuditLog: (params?: unknown) => safeInvoke('super-admin:get-audit-log', params),
    getSessions: () => safeInvoke('super-admin:get-sessions'),
    revokeSession: (id: string) => safeInvoke('super-admin:revoke-session', id),
    revokeAllSessions: () => safeInvoke('super-admin:revoke-all-sessions'),
    getConfig: () => safeInvoke('super-admin:get-config'),
    getConfigSchema: () => safeInvoke('super-admin:get-config-schema'),
    updateConfig: (updates: Record<string, string>) => safeInvoke('super-admin:update-config', updates),
    listSecurityAlerts: (params?: unknown) =>
      safeInvoke('super-admin:list-security-alerts', params),
    acknowledgeAlert: (id: number) => safeInvoke('super-admin:acknowledge-alert', id),
    acknowledgeAllAlerts: () => safeInvoke('super-admin:acknowledge-all-alerts'),
    resetRateLimits: (payload: { tenantSlug?: string; all?: boolean; totpCode: string }) =>
      safeInvoke('super-admin:reset-rate-limits', payload),
    listRateLimits: (payload: { lockedOnly?: boolean; limit?: number }) =>
      safeInvoke('super-admin:list-rate-limits', payload),
    rotateJwtSecret: (purpose: 'access' | 'refresh' | 'both', totpCode: string) =>
      safeInvoke('super-admin:rotate-jwt-secret', purpose, totpCode),
    backfillCloudflareDns: (totpCode: string) => safeInvoke('super-admin:backfill-cloudflare-dns', totpCode),
    listTenantAuthEvents: (params?: unknown) =>
      safeInvoke('super-admin:list-tenant-auth-events', params),
    listTenantNotifications: (params: { slug: string; status?: string; type?: string; limit?: number }) =>
      safeInvoke('super-admin:list-tenant-notifications', params),
    listTenantWebhookFailures: (params: { slug: string; event?: string; limit?: number }) =>
      safeInvoke('super-admin:list-tenant-webhook-failures', params),
    retryTenantWebhookFailure: (params: { slug: string; id: number }) =>
      safeInvoke('super-admin:retry-tenant-webhook-failure', params),
    listTenantAutomationRuns: (params: { slug: string; status?: string; automationId?: number; limit?: number }) =>
      safeInvoke('super-admin:list-tenant-automation-runs', params),
    // Per-tenant backup management. Mirrors `admin.*` backup methods but
    // takes a `slug` first argument so super-admins can manage every
    // tenant's backups in multi-tenant mode (the tenant-scoped admin
    // routes are blocked there).
    tenantBackupList: (slug: string) => safeInvoke('super-admin:tenant-backup-list', slug),
    tenantBackupRun: (slug: string) => safeInvoke('super-admin:tenant-backup-run', slug),
    tenantBackupDelete: (slug: string, filename: string) =>
      safeInvoke('super-admin:tenant-backup-delete', slug, filename),
    tenantBackupRestore: (slug: string, filename: string) =>
      safeInvoke('super-admin:tenant-backup-restore', slug, filename),
    tenantBackupSettingsGet: (slug: string) =>
      safeInvoke('super-admin:tenant-backup-settings-get', slug),
    tenantBackupSettingsUpdate: (slug: string, settings: BackupSettingsPayload) =>
      safeInvoke('super-admin:tenant-backup-settings-update', slug, settings),
    backupDrives: () => safeInvoke('super-admin:backup-drives'),
  },

  // ── Admin (Backup + Signup-Captcha Toggle) ─────────────────────
  admin: {
    getStatus: () => safeInvoke('admin:get-status'),
    listDrives: () => safeInvoke('admin:list-drives'),
    browseDrive: (path: string) => safeInvoke('admin:browse-drive', path),
    createFolder: (parentPath: string, name: string) =>
      safeInvoke('admin:create-folder', parentPath, name),
    listBackups: () => safeInvoke('admin:list-backups'),
    getPathForFile: (file: File) => webUtils.getPathForFile(file),
    downloadBackup: (filename: string) => safeInvoke('admin:download-backup', filename),
    uploadBackup: (sourcePath: string) => safeInvoke('admin:upload-backup', { sourcePath }),
    runBackup: () => safeInvoke('admin:run-backup'),
    updateBackupSettings: (settings: BackupSettingsPayload) =>
      safeInvoke('admin:update-backup-settings', settings),
    deleteBackup: (filename: string) => safeInvoke('admin:delete-backup', filename),
    restoreBackup: (filename: string) => safeInvoke('admin:restore-backup', filename),
    getEnvSettings: () => safeInvoke('admin:get-env-settings'),
    setEnvSettings: (updates: Record<string, string>) =>
      safeInvoke('admin:set-env-settings', updates),
    testEnvConnection: (target: EnvConnectionTestTarget) =>
      safeInvoke('admin:test-env-connection', target),
    listLogs: () => safeInvoke('admin:list-logs'),
    tailLog: (payload: { name: string; lines: number }) =>
      safeInvoke('admin:tail-log', payload),
  },

  // ── Service Control (sc.exe/PM2 — works without server) ────────
  service: {
    getStatus: () => safeInvoke('service:get-status'),
    start: () => safeInvoke('service:start'),
    stop: () => safeInvoke('service:stop'),
    restart: () => safeInvoke('service:restart'),
    emergencyStop: () => safeInvoke('service:emergency-stop'),
    killAll: () => safeInvoke('service:kill-all'),
    setAutoStart: (enabled: boolean) => safeInvoke('service:set-auto-start', enabled),
    disable: () => safeInvoke('service:disable'),
  },

  // ── System ─────────────────────────────────────────────────────
  system: {
    getDiskSpace: () => dedupInvoke('system:get-disk-space'),
    getInfo: () => safeInvoke('system:get-info'),
    openBrowser: () => safeInvoke('system:open-browser'),
    openExternal: (url: string) => safeInvoke('system:open-external', url),
    openLogFile: () => safeInvoke('system:open-log-file'),
    closeDashboard: () => safeInvoke('system:close-dashboard'),
    minimize: () => safeInvoke('system:minimize'),
    maximize: () => safeInvoke('system:maximize'),
    // AUDIT-MGT-006: cert pinning status for the renderer warning banner
    getCertPinningStatus: () => safeInvoke('system:get-cert-pinning-status'),
    // AUDIT-MGT-018: signed-tag verification bypass status for warning banner
    getTagVerifyStatus: () => safeInvoke('system:get-tag-verify-status'),
    onPowerResume: (listener: () => void) => safeOn('system:power-resume', listener),
  },
});
