/**
 * Preload Script — Secure IPC bridge between renderer and main process.
 * All dashboard auth goes through the super admin 2FA flow.
 *
 * MUST be compiled to CommonJS (Electron preload requirement).
 */
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // ── Management API ─────────────────────────────────────────────
  management: {
    setupStatus: () => ipcRenderer.invoke('management:setup-status'),
    logout: () => ipcRenderer.invoke('management:logout'),
    getStats: () => ipcRenderer.invoke('management:get-stats'),
    getStatsHistory: (range: string) => ipcRenderer.invoke('management:get-stats-history', range),
    getCrashes: () => ipcRenderer.invoke('management:get-crashes'),
    getCrashStats: () => ipcRenderer.invoke('management:get-crash-stats'),
    getDisabledRoutes: () => ipcRenderer.invoke('management:get-disabled-routes'),
    reenableRoute: (route: string) => ipcRenderer.invoke('management:reenable-route', route),
    clearCrashes: () => ipcRenderer.invoke('management:clear-crashes'),
    getUpdateStatus: () => ipcRenderer.invoke('management:get-update-status'),
    checkUpdates: () => ipcRenderer.invoke('management:check-updates'),
    performUpdate: () => ipcRenderer.invoke('management:perform-update'),
    restartServer: () => ipcRenderer.invoke('management:restart-server'),
    stopServer: () => ipcRenderer.invoke('management:stop-server'),
  },

  // ── Super-Admin Auth (2FA) ─────────────────────────────────────
  superAdmin: {
    login: (username: string, password: string) =>
      ipcRenderer.invoke('super-admin:login', username, password),
    verify2fa: (challengeToken: string, code: string) =>
      ipcRenderer.invoke('super-admin:2fa-verify', challengeToken, code),
    setup2fa: (challengeToken: string) =>
      ipcRenderer.invoke('super-admin:2fa-setup', challengeToken),
    setPassword: (challengeToken: string, password: string) =>
      ipcRenderer.invoke('super-admin:set-password', challengeToken, password),
    getDashboard: () => ipcRenderer.invoke('super-admin:get-dashboard'),
    listTenants: () => ipcRenderer.invoke('super-admin:list-tenants'),
    createTenant: (data: unknown) => ipcRenderer.invoke('super-admin:create-tenant', data),
    getTenant: (slug: string) => ipcRenderer.invoke('super-admin:get-tenant', slug),
    suspendTenant: (slug: string) => ipcRenderer.invoke('super-admin:suspend-tenant', slug),
    activateTenant: (slug: string) => ipcRenderer.invoke('super-admin:activate-tenant', slug),
    deleteTenant: (slug: string) => ipcRenderer.invoke('super-admin:delete-tenant', slug),
    getAuditLog: (params?: string) => ipcRenderer.invoke('super-admin:get-audit-log', params),
    getSessions: () => ipcRenderer.invoke('super-admin:get-sessions'),
    revokeSession: (id: string) => ipcRenderer.invoke('super-admin:revoke-session', id),
    getConfig: () => ipcRenderer.invoke('super-admin:get-config'),
    updateConfig: (updates: unknown) => ipcRenderer.invoke('super-admin:update-config', updates),
  },

  // ── Admin (Backup) ─────────────────────────────────────────────
  admin: {
    getStatus: () => ipcRenderer.invoke('admin:get-status'),
    listDrives: () => ipcRenderer.invoke('admin:list-drives'),
    browseDrive: (path: string) => ipcRenderer.invoke('admin:browse-drive', path),
    createFolder: (parentPath: string, name: string) =>
      ipcRenderer.invoke('admin:create-folder', parentPath, name),
    listBackups: () => ipcRenderer.invoke('admin:list-backups'),
    runBackup: () => ipcRenderer.invoke('admin:run-backup'),
    updateBackupSettings: (settings: unknown) =>
      ipcRenderer.invoke('admin:update-backup-settings', settings),
    deleteBackup: (filename: string) => ipcRenderer.invoke('admin:delete-backup', filename),
  },

  // ── Service Control (sc.exe/PM2 — works without server) ────────
  service: {
    getStatus: () => ipcRenderer.invoke('service:get-status'),
    start: () => ipcRenderer.invoke('service:start'),
    stop: () => ipcRenderer.invoke('service:stop'),
    restart: () => ipcRenderer.invoke('service:restart'),
    emergencyStop: () => ipcRenderer.invoke('service:emergency-stop'),
    killAll: () => ipcRenderer.invoke('service:kill-all'),
    setAutoStart: (enabled: boolean) => ipcRenderer.invoke('service:set-auto-start', enabled),
    disable: () => ipcRenderer.invoke('service:disable'),
  },

  // ── System ─────────────────────────────────────────────────────
  system: {
    getDiskSpace: () => ipcRenderer.invoke('system:get-disk-space'),
    getInfo: () => ipcRenderer.invoke('system:get-info'),
    openBrowser: () => ipcRenderer.invoke('system:open-browser'),
    openExternal: (url: string) => ipcRenderer.invoke('system:open-external', url),
    openLogFile: () => ipcRenderer.invoke('system:open-log-file'),
    closeDashboard: () => ipcRenderer.invoke('system:close-dashboard'),
    minimize: () => ipcRenderer.invoke('system:minimize'),
    maximize: () => ipcRenderer.invoke('system:maximize'),
  },
});
