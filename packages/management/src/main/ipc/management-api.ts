/**
 * IPC handlers for the server dashboard.
 * Authentication uses the super admin 2FA flow exclusively.
 * Management API calls use the super admin JWT as Bearer token.
 */
import { ipcMain, shell } from 'electron';
import {
  apiRequest,
  setSuperAdminToken,
} from '../services/api-client.js';
import { allowClose, getMainWindow } from '../window.js';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function wrapHandler(fn: (...args: any[]) => Promise<any>) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return async (...args: any[]) => {
    try {
      return await fn(...args);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, message: `Server not reachable: ${message}`, offline: true };
    }
  };
}

export function registerManagementIpc(): void {
  // ── Setup Status (no auth needed) ──────────────────────────────

  ipcMain.handle('management:setup-status', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/management/setup-status', null, 'none');
    return res.body;
  }));

  // ── Super-Admin Auth (2FA flow) ────────────────────────────────

  ipcMain.handle('super-admin:login', wrapHandler(async (_event, username: string, password: string) => {
    const res = await apiRequest('POST', '/super-admin/api/login', { username, password }, 'none');
    return res.body;
  }));

  ipcMain.handle('super-admin:2fa-verify', wrapHandler(async (_event, challengeToken: string, code: string) => {
    const res = await apiRequest('POST', '/super-admin/api/login/2fa-verify', { challengeToken, code }, 'none');
    if (res.body.success && (res.body.data as { token?: string })?.token) {
      setSuperAdminToken((res.body.data as { token: string }).token);
    }
    return res.body;
  }));

  ipcMain.handle('super-admin:2fa-setup', wrapHandler(async (_event, challengeToken: string) => {
    const res = await apiRequest('POST', '/super-admin/api/login/2fa-setup', { challengeToken }, 'none');
    return res.body;
  }));

  ipcMain.handle('super-admin:set-password', wrapHandler(async (_event, challengeToken: string, password: string) => {
    const res = await apiRequest('POST', '/super-admin/api/login/set-password', { challengeToken, password }, 'none');
    return res.body;
  }));

  ipcMain.handle('management:logout', wrapHandler(async () => {
    setSuperAdminToken(null);
    return { success: true };
  }));

  // ── Stats (management API — needs super admin JWT) ─────────────

  ipcMain.handle('management:setup', wrapHandler(async (_event, username: string, password: string) => {
    const res = await apiRequest('POST', '/api/v1/management/setup', { username, password }, 'none');
    return res.body;
  }));

  ipcMain.handle('management:get-stats', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/management/stats');
    return res.body;
  }));

  ipcMain.handle('management:get-stats-history', wrapHandler(async (_event, range: string) => {
    const res = await apiRequest('GET', `/api/v1/management/stats/history?range=${encodeURIComponent(range)}`);
    return res.body;
  }));

  // ── Super-Admin Dashboard ──────────────────────────────────────

  ipcMain.handle('super-admin:get-dashboard', wrapHandler(async () => {
    const res = await apiRequest('GET', '/super-admin/api/dashboard');
    return res.body;
  }));

  // ── Tenants (super-admin API) ──────────────────────────────────

  ipcMain.handle('super-admin:list-tenants', wrapHandler(async () => {
    const res = await apiRequest('GET', '/super-admin/api/tenants');
    return res.body;
  }));

  ipcMain.handle('super-admin:create-tenant', wrapHandler(async (_event, data: unknown) => {
    const res = await apiRequest('POST', '/super-admin/api/tenants', data);
    return res.body;
  }));

  ipcMain.handle('super-admin:get-tenant', wrapHandler(async (_event, slug: string) => {
    const res = await apiRequest('GET', `/super-admin/api/tenants/${encodeURIComponent(slug)}`);
    return res.body;
  }));

  ipcMain.handle('super-admin:suspend-tenant', wrapHandler(async (_event, slug: string) => {
    const res = await apiRequest('POST', `/super-admin/api/tenants/${encodeURIComponent(slug)}/suspend`);
    return res.body;
  }));

  ipcMain.handle('super-admin:activate-tenant', wrapHandler(async (_event, slug: string) => {
    const res = await apiRequest('POST', `/super-admin/api/tenants/${encodeURIComponent(slug)}/activate`);
    return res.body;
  }));

  ipcMain.handle('super-admin:delete-tenant', wrapHandler(async (_event, slug: string) => {
    const res = await apiRequest('DELETE', `/super-admin/api/tenants/${encodeURIComponent(slug)}`);
    return res.body;
  }));

  // ── Platform Config ────────────────────────────────────────────

  ipcMain.handle('super-admin:get-config', wrapHandler(async () => {
    const res = await apiRequest('GET', '/super-admin/api/config');
    return res.body;
  }));

  ipcMain.handle('super-admin:update-config', wrapHandler(async (_event, updates: unknown) => {
    const res = await apiRequest('PUT', '/super-admin/api/config', updates);
    return res.body;
  }));

  // ── Audit Log ──────────────────────────────────────────────────

  ipcMain.handle('super-admin:get-audit-log', wrapHandler(async (_event, params?: string) => {
    const qs = params ? `?${params}` : '';
    const res = await apiRequest('GET', `/super-admin/api/audit-log${qs}`);
    return res.body;
  }));

  // ── Sessions ───────────────────────────────────────────────────

  ipcMain.handle('super-admin:get-sessions', wrapHandler(async () => {
    const res = await apiRequest('GET', '/super-admin/api/sessions');
    return res.body;
  }));

  ipcMain.handle('super-admin:revoke-session', wrapHandler(async (_event, id: string) => {
    const res = await apiRequest('DELETE', `/super-admin/api/sessions/${encodeURIComponent(id)}`);
    return res.body;
  }));

  // ── Crashes (management API) ───────────────────────────────────

  ipcMain.handle('management:get-crashes', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/management/crashes');
    return res.body;
  }));

  ipcMain.handle('management:get-crash-stats', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/management/crash-stats');
    return res.body;
  }));

  ipcMain.handle('management:get-disabled-routes', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/management/disabled-routes');
    return res.body;
  }));

  ipcMain.handle('management:reenable-route', wrapHandler(async (_event, route: string) => {
    const res = await apiRequest('POST', '/api/v1/management/reenable-route', { route });
    return res.body;
  }));

  ipcMain.handle('management:clear-crashes', wrapHandler(async () => {
    const res = await apiRequest('POST', '/api/v1/management/clear-crashes');
    return res.body;
  }));

  // ── Updates ────────────────────────────────────────────────────

  ipcMain.handle('management:get-update-status', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/management/update-status');
    return res.body;
  }));

  ipcMain.handle('management:check-updates', wrapHandler(async () => {
    const res = await apiRequest('POST', '/api/v1/management/check-updates');
    return res.body;
  }));

  ipcMain.handle('management:perform-update', wrapHandler(async () => {
    const res = await apiRequest('POST', '/api/v1/management/perform-update');
    return res.body;
  }));

  // ── Server Control (REST fallback) ─────────────────────────────

  ipcMain.handle('management:restart-server', wrapHandler(async () => {
    const res = await apiRequest('POST', '/api/v1/management/restart');
    return res.body;
  }));

  ipcMain.handle('management:stop-server', wrapHandler(async () => {
    const res = await apiRequest('POST', '/api/v1/management/stop');
    return res.body;
  }));

  // ── Backup ─────────────────────────────────────────────────────

  ipcMain.handle('admin:get-status', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/admin/status');
    return res.body;
  }));

  ipcMain.handle('admin:list-drives', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/admin/drives');
    return res.body;
  }));

  ipcMain.handle('admin:browse-drive', wrapHandler(async (_event, drivePath: string) => {
    const res = await apiRequest('GET', `/api/v1/admin/drives/browse?path=${encodeURIComponent(drivePath)}`);
    return res.body;
  }));

  ipcMain.handle('admin:create-folder', wrapHandler(async (_event, parentPath: string, name: string) => {
    const res = await apiRequest('POST', '/api/v1/admin/drives/mkdir', { path: parentPath, name });
    return res.body;
  }));

  ipcMain.handle('admin:list-backups', wrapHandler(async () => {
    const res = await apiRequest('GET', '/api/v1/admin/backups');
    return res.body;
  }));

  ipcMain.handle('admin:run-backup', wrapHandler(async () => {
    const res = await apiRequest('POST', '/api/v1/admin/backup');
    return res.body;
  }));

  ipcMain.handle('admin:update-backup-settings', wrapHandler(async (_event, settings: unknown) => {
    const res = await apiRequest('PUT', '/api/v1/admin/backup-settings', settings);
    return res.body;
  }));

  ipcMain.handle('admin:delete-backup', wrapHandler(async (_event, filename: string) => {
    const res = await apiRequest('DELETE', `/api/v1/admin/backups/${encodeURIComponent(filename)}`);
    return res.body;
  }));

  // ── Utilities ──────────────────────────────────────────────────

  ipcMain.handle('system:open-browser', () => {
    shell.openExternal('https://localhost');
    return { success: true };
  });

  ipcMain.handle('system:close-dashboard', () => {
    allowClose();
    const win = getMainWindow();
    if (win) win.close();
    return { success: true };
  });

  ipcMain.handle('system:minimize', () => {
    getMainWindow()?.minimize();
    return { success: true };
  });

  ipcMain.handle('system:maximize', () => {
    const win = getMainWindow();
    if (win?.isMaximized()) {
      win.unmaximize();
    } else {
      win?.maximize();
    }
    return { success: true };
  });
}
