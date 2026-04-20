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
const { contextBridge, ipcRenderer } = require('electron');

// @audit-fixed: explicit channel allow-list. Adding a new IPC handler
// requires updating BOTH the main-process registration AND this list,
// which makes accidental channel proliferation impossible.
const ALLOWED_CHANNELS: ReadonlySet<string> = new Set([
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
  // super-admin:*
  'super-admin:login',
  'super-admin:2fa-verify',
  'super-admin:2fa-setup',
  'super-admin:set-password',
  'super-admin:get-dashboard',
  'super-admin:list-tenants',
  'super-admin:create-tenant',
  'super-admin:get-tenant',
  'super-admin:suspend-tenant',
  'super-admin:activate-tenant',
  'super-admin:delete-tenant',
  'super-admin:repair-tenant',
  'super-admin:get-audit-log',
  'super-admin:get-sessions',
  'super-admin:revoke-session',
  'super-admin:get-config',
  'super-admin:update-config',
  // admin:* (backup)
  'admin:get-status',
  'admin:list-drives',
  'admin:browse-drive',
  'admin:create-folder',
  'admin:list-backups',
  'admin:run-backup',
  'admin:update-backup-settings',
  'admin:delete-backup',
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
]);

function safeInvoke(channel: string, ...args: unknown[]): Promise<unknown> {
  if (!ALLOWED_CHANNELS.has(channel)) {
    // Reject loudly so a typo or compromised script can't probe channels.
    return Promise.reject(
      new Error(`[preload] Refusing to invoke unknown IPC channel: ${channel}`)
    );
  }
  return ipcRenderer.invoke(channel, ...args);
}

contextBridge.exposeInMainWorld('electronAPI', {
  // ── Management API ─────────────────────────────────────────────
  management: {
    setupStatus: () => safeInvoke('management:setup-status'),
    logout: () => safeInvoke('management:logout'),
    setup: (username: string, password: string) => safeInvoke('management:setup', username, password),
    getStats: () => safeInvoke('management:get-stats'),
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
    auditUpdateResult: (payload: unknown) => safeInvoke('management:audit-update-result', payload),
    restartServer: () => safeInvoke('management:restart-server'),
    stopServer: () => safeInvoke('management:stop-server'),
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
    suspendTenant: (slug: string) => safeInvoke('super-admin:suspend-tenant', slug),
    activateTenant: (slug: string) => safeInvoke('super-admin:activate-tenant', slug),
    deleteTenant: (slug: string) => safeInvoke('super-admin:delete-tenant', slug),
    repairTenant: (slug: string) => safeInvoke('super-admin:repair-tenant', slug),
    // AUDIT-MGT-008: pass typed object; query string built main-side.
    getAuditLog: (params?: unknown) => safeInvoke('super-admin:get-audit-log', params),
    getSessions: () => safeInvoke('super-admin:get-sessions'),
    revokeSession: (id: string) => safeInvoke('super-admin:revoke-session', id),
    getConfig: () => safeInvoke('super-admin:get-config'),
    updateConfig: (updates: unknown) => safeInvoke('super-admin:update-config', updates),
  },

  // ── Admin (Backup) ─────────────────────────────────────────────
  admin: {
    getStatus: () => safeInvoke('admin:get-status'),
    listDrives: () => safeInvoke('admin:list-drives'),
    browseDrive: (path: string) => safeInvoke('admin:browse-drive', path),
    createFolder: (parentPath: string, name: string) =>
      safeInvoke('admin:create-folder', parentPath, name),
    listBackups: () => safeInvoke('admin:list-backups'),
    runBackup: () => safeInvoke('admin:run-backup'),
    updateBackupSettings: (settings: unknown) =>
      safeInvoke('admin:update-backup-settings', settings),
    deleteBackup: (filename: string) => safeInvoke('admin:delete-backup', filename),
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
    getDiskSpace: () => safeInvoke('system:get-disk-space'),
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
  },
});
