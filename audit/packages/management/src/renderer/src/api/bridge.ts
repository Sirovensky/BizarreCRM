/**
 * Type-safe wrapper around window.electronAPI exposed by the preload script.
 * All renderer-side API calls go through this module.
 */

// ── Response types ────────────────────────────────────────────────

export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  message?: string;
  offline?: boolean;
  /** Stable ERR_* identifier from the server's errorBody helper. */
  code?: string;
  /** Server-supplied correlation id (matches an X-Request-Id log entry). */
  request_id?: string;
  /**
   * DASH-ELEC-060: HTTP status code propagated from the main-process IPC
   * handler via bodyOf(). Use `status === 401` as the primary auth-expiry
   * signal in handleApiResponse() rather than substring-matching messages.
   * Absent for IPC errors that never reached the server (network failures).
   */
  status?: number;
}

// ── Server stats ──────────────────────────────────────────────────

export interface ServerStats {
  uptime: number;
  memory: { rss: number; heapUsed: number; heapTotal: number };
  cpu: { user: number; system: number };
  dbSizeBytes: number;
  dbSizeMB: number;
  uploadsSizeBytes: number;
  uploadsSizeMB: number;
  activeConnections: number;
  requestsPerSecond: number;
  requestsPerSecondAvg: number;
  requestsPerSecondPeak: number;
  requestsPerMinute: number;
  avgResponseMs: number;
  p95ResponseMs: number;
  nodeVersion: string;
  platform: string;
  hostname: string;
  pm2Managed: boolean;
  multiTenant?: boolean;
  nodeEnv?: string;
  unacknowledgedSecurityAlerts?: number;
  /** Short git SHA the server was built from — surfaced in Overview sys-info. */
  gitSha?: string;
  /** ISO timestamp of process boot — lets the dashboard show "started at …". */
  startedAt?: string;
}

// ── Crash types ───────────────────────────────────────────────────

export interface CrashEntry {
  id: string;
  timestamp: string;
  route: string;
  errorMessage: string;
  errorStack: string;
  type: 'uncaughtException' | 'unhandledRejection';
  recovered: boolean;
}

export interface CrashStats {
  totalCrashes: number;
  disabledCount: number;
  recentCrashes: CrashEntry[];
}

export interface DisabledRoute {
  route: string;
  disabledAt: string;
  crashCount: number;
  lastError: string;
}

// ── Service types ─────────────────────────────────────────────────

export interface ServiceStatus {
  state: 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown' | 'not_installed';
  pid: number | null;
  startType: 'auto' | 'demand' | 'disabled' | 'unknown';
  mode: 'service' | 'pm2' | 'direct' | 'none';
}

// ── Tenant types ──────────────────────────────────────────────────

export interface Tenant {
  id: number;
  slug: string;
  name: string;
  status: 'active' | 'suspended';
  plan: string;
  db_size_bytes?: number;
  created_at: string;
}

export interface TenantCreateResult {
  tenant_id: number;
  slug: string;
  url: string;
  setup_url: string;
}

/**
 * DASH-ELEC-268 (Fixer-C24 2026-04-25): payload shape for `superAdmin.createTenant`.
 * Mirrors the form fields collected on TenantsPage. Parameterised so the call
 * site doesn't have to fall back to `unknown` + cast on the response.
 */
export interface TenantCreatePayload {
  slug: string;
  shop_name: string;
  admin_email: string;
  plan: string;
}

// ── Metrics types ─────────────────────────────────────────────────

export interface MetricsDataPoint {
  timestamp: string;
  rps_avg: number;
  rps_peak: number;
  rpm: number;
  avg_response_ms: number;
  p95_response_ms: number;
  active_connections: number;
  memory_mb: number;
}

// ── System types ──────────────────────────────────────────────────

export interface DiskDrive {
  mount: string;
  total: number;
  free: number;
  used: number;
}

export interface SystemInfo {
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
}

// ── Audit log params (AUDIT-MGT-008) ─────────────────────────────

/** Typed audit-log query parameters passed to the IPC handler. */
export interface AuditLogParams {
  limit?: number;
  offset?: number;
  action?: string;
  startDate?: string;
  endDate?: string;
}

// ── Security alerts ──────────────────────────────────────────────

export type SecurityAlertSeverity = 'info' | 'warning' | 'critical';

export interface SecurityAlert {
  id: number;
  type: string;
  severity: SecurityAlertSeverity;
  tenant_id: number | null;
  tenant_slug: string | null;
  ip_address: string | null;
  details: string | null;
  acknowledged: 0 | 1;
  created_at: string;
}

export interface SecurityAlertListParams {
  severity?: SecurityAlertSeverity;
  acknowledged?: 0 | 1;
  page?: number;
  limit?: number;
}

export interface SecurityAlertListResult {
  alerts: SecurityAlert[];
  pagination: {
    page: number;
    limit: number;
    total: number;
    total_pages: number;
  };
}

// ── Platform config (DB-backed runtime toggles) ──────────────────

export type PlatformConfigKind = 'flag' | 'value';

export interface PlatformConfigField {
  key: string;
  kind: PlatformConfigKind;
  label: string;
  description: string;
  default: string;
}

// ── Env settings editor ──────────────────────────────────────────

export type EnvFieldKind = 'flag' | 'value' | 'secret';
// DASH-ELEC-269 (Fixer-C26 2026-04-25): mirrored in
// packages/management/src/main/ipc/management-api.ts — Electron main+renderer
// build to separate bundles with no shared types folder yet, so this union
// is intentionally duplicated. Edit BOTH files in the same commit when adding
// or removing a category. See the parallel comment in management-api.ts.
export type EnvFieldCategory = 'killswitch' | 'captcha' | 'stripe' | 'cloudflare' | 'cors';

export interface EnvSettingField {
  key: string;
  kind: EnvFieldKind;
  category: EnvFieldCategory;
  label: string;
  description?: string;
  placeholder?: string;
  hasValue: boolean;
  /** Secrets: present, value omitted. Non-secrets: actual value (may be empty). */
  value?: string;
  /** Secrets only: character length so the UI can say "16-char secret set". */
  length?: number;
}

// ── Bridge accessor ───────────────────────────────────────────────

export interface SetupStatus {
  needsSetup: boolean;
  managementApiEnabled: boolean;
  multiTenant: boolean;
}

interface ElectronAPI {
  management: {
    setupStatus(): Promise<ApiResponse<SetupStatus>>;
    setup(username: string, password: string): Promise<ApiResponse>;
    logout(): Promise<ApiResponse>;
    getStats(): Promise<ApiResponse<ServerStats>>;
    getStatsHistory(range: string): Promise<ApiResponse<MetricsDataPoint[]>>;
    getCrashes(): Promise<ApiResponse<CrashEntry[]>>;
    getCrashStats(): Promise<ApiResponse<CrashStats>>;
    getDisabledRoutes(): Promise<ApiResponse<DisabledRoute[]>>;
    reenableRoute(route: string): Promise<ApiResponse>;
    clearCrashes(): Promise<ApiResponse>;
    getUpdateStatus(): Promise<ApiResponse>;
    checkUpdates(): Promise<ApiResponse>;
    performUpdate(): Promise<ApiResponse>;
    getRollbackInfo(): Promise<ApiResponse<{ available: boolean; sha?: string }>>;
    rollbackUpdate(): Promise<ApiResponse<{ sha: string; stdout: string }>>;
    clearRollback(): Promise<ApiResponse>;
    /** MGT-028: Record the final update outcome once the dashboard reopens. */
    auditUpdateResult(payload: { success: boolean; afterSha?: string; errorMessage?: string }): Promise<ApiResponse>;
    restartServer(): Promise<ApiResponse>;
    stopServer(): Promise<ApiResponse>;
  };
  superAdmin: {
    /** DASH-ELEC-267 (Fixer-C24 2026-04-25): parameterise the success shapes
     *  so LoginPage doesn't need `as { … }` casts. The server may return any
     *  of these depending on whether password setup or 2FA setup is required. */
    login(username: string, password: string): Promise<ApiResponse<{
      challengeToken?: string;
      requiresPasswordSetup?: boolean;
      requires2faSetup?: boolean;
      totpEnabled?: boolean;
    }>>;
    verify2fa(challengeToken: string, code: string): Promise<ApiResponse<{ token: string }>>;
    /** DASH-ELEC-267: parameterise — server returns the QR data URL,
     *  next-step challenge token, and (after first setup) recovery codes. */
    setup2fa(challengeToken: string): Promise<ApiResponse<{
      qr?: string;
      challengeToken?: string;
      recoveryCodes?: string[];
    }>>;
    /** DASH-ELEC-267: server returns next-step challengeToken once the
     *  password is accepted (so the flow can roll into 2FA setup/verify). */
    setPassword(challengeToken: string, password: string): Promise<ApiResponse<{
      challengeToken?: string;
    }>>;
    getDashboard(): Promise<ApiResponse>;
    listTenants(): Promise<ApiResponse<{ tenants: Tenant[] }>>;
    createTenant(data: TenantCreatePayload): Promise<ApiResponse<TenantCreateResult>>;
    /** DASH-ELEC-189: server returns Tenant + denormalised counts/db_size_mb;
     *  consumers (TenantsPage drill-in) need both. */
    getTenant(slug: string): Promise<ApiResponse<Tenant & {
      user_count?: number;
      ticket_count?: number;
      customer_count?: number;
      db_size_mb?: number;
    }>>;
    suspendTenant(slug: string): Promise<ApiResponse>;
    activateTenant(slug: string): Promise<ApiResponse>;
    deleteTenant(slug: string): Promise<ApiResponse>;
    repairTenant(slug: string): Promise<ApiResponse<{ message: string; steps: Array<{ step: string; message: string }>; setup_url?: string }>>;
    getAuditLog(params?: AuditLogParams): Promise<ApiResponse>;
    getSessions(): Promise<ApiResponse>;
    revokeSession(id: string): Promise<ApiResponse>;
    getConfig(): Promise<ApiResponse<Record<string, string>>>;
    getConfigSchema(): Promise<ApiResponse<{ fields: PlatformConfigField[] }>>;
    updateConfig(updates: Record<string, string>): Promise<ApiResponse>;
    /** List security alerts with optional filters + pagination. */
    listSecurityAlerts(params?: SecurityAlertListParams): Promise<ApiResponse<SecurityAlertListResult>>;
    /** Acknowledge a single alert by id. */
    acknowledgeAlert(id: number): Promise<ApiResponse<{ message: string }>>;
    /** Acknowledge every currently-unacknowledged alert. Returns the count cleared. */
    acknowledgeAllAlerts(): Promise<ApiResponse<{ count: number }>>;
    /** Clear `rate_limits` rows that lock out auth/2FA/PIN flows. Optional tenant filter. */
    resetRateLimits(payload: { tenantSlug?: string; all?: boolean }): Promise<ApiResponse<{
      totalDeleted: number;
      scope: 'all' | 'single-tenant';
      results: Array<{ dbLabel: string; deleted: number; skipped: boolean; error?: string }>;
    }>>;
    /** Idempotent: re-create Cloudflare DNS records for any tenant missing one. */
    backfillCloudflareDns(): Promise<ApiResponse<{
      summary: { total: number; created: number; skipped: number; errors: number };
      rows: Array<{ slug: string; status: 'created' | 'reused' | 'skipped' | 'error'; recordId?: string; message?: string }>;
    }>>;
    /** Read-only inspector for the rate_limits table across master + every tenant DB. */
    listRateLimits(payload: { lockedOnly?: boolean; limit?: number }): Promise<ApiResponse<{
      rows: Array<{ db: string; id: number; category: string; key: string; count: number; first_attempt: number; locked_until: number | null }>;
      summary: { total: number; locked: number; dbsTouched: number };
      now: number;
    }>>;
    /** Generate a new JWT signing secret. Value is returned once; operator must paste into .env. */
    rotateJwtSecret(purpose: 'access' | 'refresh' | 'both'): Promise<ApiResponse<{
      purpose: 'access' | 'refresh' | 'both';
      nextJwtSecret?: string;
      nextJwtRefreshSecret?: string;
      instructions: string[];
    }>>;
    listTenantAuthEvents(params?: { tenant_slug?: string; ip?: string; event?: string; page?: number; limit?: number }): Promise<ApiResponse<{
      events: Array<{ id: number; tenant_slug: string; event: string; ip_address: string; user_agent?: string; details?: string; created_at: string }>;
      pagination: { page: number; limit: number; total: number; total_pages: number };
    }>>;
    /** Per-tenant outbound comms log (email/SMS/push queue). */
    listTenantNotifications(params: { slug: string; status?: string; type?: string; limit?: number }): Promise<ApiResponse<{
      rows: Array<{
        id: number;
        type: 'sms' | 'email' | 'push';
        recipient: string;
        subject: string | null;
        status: 'pending' | 'sent' | 'failed' | 'cancelled';
        error: string | null;
        retry_count: number;
        scheduled_at: string | null;
        sent_at: string | null;
        created_at: string;
      }>;
      summary: { total: number; pending: number; sent: number; failed: number; cancelled: number };
    }>>;
    /** Per-tenant webhook delivery failures (dead-letter queue). */
    listTenantWebhookFailures(params: { slug: string; event?: string; limit?: number }): Promise<ApiResponse<{
      rows: Array<{
        id: number;
        endpoint: string;
        event: string;
        attempts: number;
        last_error: string | null;
        last_status: number | null;
        created_at: string;
      }>;
      summary: { total: number; byEvent: Array<{ event: string; count: number }> };
    }>>;
    /** Operator-triggered retry of a single dead-lettered webhook delivery. */
    retryTenantWebhookFailure(params: { slug: string; id: number }): Promise<ApiResponse<
      | { ok: true; status: number | null }
      | { ok: false; status: number | null; error: string; attempts: number }
    >>;
    /** Per-tenant automation execution history. */
    listTenantAutomationRuns(params: { slug: string; status?: string; automationId?: number; limit?: number }): Promise<ApiResponse<{
      rows: Array<{
        id: number;
        automation_id: number;
        automation_name: string | null;
        trigger_event: string;
        action_type: string | null;
        target_entity_type: string | null;
        target_entity_id: number | null;
        status: 'success' | 'failure' | 'skipped' | 'loop_rejected';
        error_message: string | null;
        depth: number;
        created_at: string;
      }>;
      summary: { total: number; success: number; failure: number; skipped: number; loop_rejected: number };
    }>>;
  };
  admin: {
    getStatus(): Promise<ApiResponse>;
    listDrives(): Promise<ApiResponse>;
    browseDrive(path: string): Promise<ApiResponse>;
    createFolder(parentPath: string, name: string): Promise<ApiResponse>;
    listBackups(): Promise<ApiResponse>;
    runBackup(): Promise<ApiResponse>;
    updateBackupSettings(settings: unknown): Promise<ApiResponse>;
    deleteBackup(filename: string): Promise<ApiResponse>;
    /** Restore a backup — server safety-copies the current DB first, then swaps in. */
    restoreBackup(filename: string): Promise<ApiResponse<{ message?: string; safetyBackup?: string }>>;
    /** Read every whitelisted env field. Secrets return only `hasValue`+`length`. */
    getEnvSettings(): Promise<ApiResponse<{ fields: EnvSettingField[] }>>;
    /** Bulk-write env keys to .env. Caller must restart the server to apply. */
    setEnvSettings(updates: Record<string, string>): Promise<ApiResponse<{ keysUpdated: string[]; requiresRestart: boolean }>>;
    /** Enumerate whitelisted log files with size + mtime. */
    listLogs(): Promise<ApiResponse<{ files: Array<{ name: string; path: string | null; size: number; mtime: string | null; exists: boolean; error?: string }> }>>;
    /** Tail the last N lines of a whitelisted log file. */
    tailLog(payload: { name: string; lines: number }): Promise<ApiResponse<{ content: string; size: number; mtime: string | null; truncated: boolean }>>;
  };
  service: {
    getStatus(): Promise<ServiceStatus>;
    start(): Promise<ApiResponse>;
    stop(): Promise<ApiResponse>;
    restart(): Promise<ApiResponse>;
    emergencyStop(): Promise<ApiResponse>;
    killAll(): Promise<ApiResponse>;
    setAutoStart(enabled: boolean): Promise<ApiResponse>;
    disable(): Promise<ApiResponse>;
  };
  system: {
    getDiskSpace(): Promise<ApiResponse<DiskDrive[]>>;
    getInfo(): Promise<ApiResponse<SystemInfo>>;
    // @audit-fixed: previously every system:* method was typed `Promise<void>`,
    // even though every IPC handler in src/main/ipc/system-info.ts and
    // src/main/ipc/management-api.ts returns
    // { success: true } | { success: false, error, code, message }.
    // The lying signature meant renderer call sites silently dropped the
    // failure envelope (e.g. SettingsPage.openLogFile, TenantsPage's
    // openExternal click — both of which had no error feedback). The types
    // now match the runtime shape so the next call site that ignores
    // failures will at least get a TS warning when accessing `.success`.
    openBrowser(): Promise<ApiResponse>;
    openExternal(url: string): Promise<ApiResponse>;
    openLogFile(): Promise<ApiResponse>;
    closeDashboard(): Promise<ApiResponse>;
    minimize(): Promise<ApiResponse>;
    maximize(): Promise<ApiResponse>;
    // AUDIT-MGT-006: exposes whether TLS cert pinning is active
    getCertPinningStatus(): Promise<ApiResponse<{ enabled: boolean; reason?: string }>>;
    // AUDIT-MGT-018: exposes whether UPDATE_SKIP_TAG_VERIFY bypass is active
    getTagVerifyStatus(): Promise<ApiResponse<{ bypass: boolean }>>;
  };
}

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}

/**
 * Get the electron API bridge. Throws in non-Electron environments.
 */
export function getAPI(): ElectronAPI {
  if (!window.electronAPI) {
    throw new Error('electronAPI not available — not running in Electron');
  }
  return window.electronAPI;
}
