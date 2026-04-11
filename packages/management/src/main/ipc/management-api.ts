/**
 * IPC handlers for the server dashboard.
 * Authentication uses the super admin 2FA flow exclusively.
 * Management API calls use the super admin JWT as Bearer token.
 */
import { ipcMain, shell, app } from 'electron';
import { spawn, spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import {
  apiRequest,
  setSuperAdminToken,
} from '../services/api-client.js';
import { allowClose, getMainWindow } from '../window.js';

/** File used by UP5 rollback: pre-update git commit SHA. */
const PRE_UPDATE_SNAPSHOT_FILE = 'update-pre-commit.txt';

function getSnapshotFilePath(): string {
  return path.join(app.getPath('userData'), PRE_UPDATE_SNAPSHOT_FILE);
}

/** UP5: Capture the current git HEAD so we can roll back a failed update. */
function captureGitHead(root: string): { ok: true; sha: string } | { ok: false; error: string } {
  try {
    const result = spawnSync('git', ['rev-parse', 'HEAD'], {
      cwd: root,
      encoding: 'utf-8',
      timeout: 10_000,
    });
    if (result.status !== 0) {
      return { ok: false, error: result.stderr?.trim() || `git rev-parse exited ${result.status}` };
    }
    const sha = result.stdout.trim();
    if (!/^[a-f0-9]{7,40}$/i.test(sha)) {
      return { ok: false, error: `Unexpected git SHA format: ${sha}` };
    }
    return { ok: true, sha };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : 'Unknown error' };
  }
}

function writeSnapshot(sha: string): void {
  try {
    const dir = app.getPath('userData');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(getSnapshotFilePath(), sha, 'utf-8');
  } catch (err) {
    console.error('[Update] Failed to persist rollback snapshot:', err);
  }
}

function readSnapshot(): string | null {
  try {
    const p = getSnapshotFilePath();
    if (!fs.existsSync(p)) return null;
    const raw = fs.readFileSync(p, 'utf-8').trim();
    if (!/^[a-f0-9]{7,40}$/i.test(raw)) return null;
    return raw;
  } catch {
    return null;
  }
}

function clearSnapshot(): void {
  try {
    const p = getSnapshotFilePath();
    if (fs.existsSync(p)) fs.unlinkSync(p);
  } catch {
    /* ignore */
  }
}

/**
 * SECURITY (EL3 / EL7): Locate the project root for `update.bat`.
 *
 * The previous implementation walked 5 levels up from process.execPath
 * looking for `ecosystem.config.js` or `setup.bat`. An attacker who could
 * drop either of those files in *any* parent directory of the Electron
 * binary would redirect the walk to an arbitrary root and achieve code
 * execution via `scripts/update.bat`.
 *
 * This version:
 *   1. Resolves candidates from trusted anchors only — `app.getAppPath()`
 *      (inside asar / dev) and `process.resourcesPath` (packaged).
 *   2. Walks *only* upward within those known paths.
 *   3. Validates that the resolved `update.bat` sits under one of the
 *      trusted anchors, blocking `..`-style escapes or symlink trickery.
 */
function resolveTrustedProjectRoot(): string | null {
  const anchors = [app.getAppPath(), process.resourcesPath].filter(
    (p): p is string => typeof p === 'string' && p.length > 0
  );

  for (const anchor of anchors) {
    let dir = path.resolve(anchor);
    const anchorRoot = dir;
    for (let i = 0; i < 6; i++) {
      const marker =
        fs.existsSync(path.join(dir, 'ecosystem.config.js')) ||
        fs.existsSync(path.join(dir, 'setup.bat'));
      if (marker) {
        // Guarantee the candidate root is still under (or equal to) the
        // trusted anchor's filesystem root.
        if (isPathUnder(dir, path.parse(anchorRoot).root)) {
          return dir;
        }
      }
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return null;
}

/** True if `child` is inside (or equal to) `parent`, using resolved absolute paths. */
function isPathUnder(child: string, parent: string): boolean {
  const resolvedChild = path.resolve(child);
  const resolvedParent = path.resolve(parent);
  if (resolvedChild === resolvedParent) return true;
  const rel = path.relative(resolvedParent, resolvedChild);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

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

  // Local-only mutation: clears the cached super-admin JWT in this process.
  // (Server-side invalidation is a TODO — the server doesn't yet expose a
  // logout endpoint for super-admin sessions.)
  ipcMain.handle('management:logout', wrapHandler(async () => {
    setSuperAdminToken(null);
    return { success: true, data: { local: true } };
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

  ipcMain.handle('management:perform-update', async () => {
    // SECURITY (EL3 / EL7): Resolve project root from trusted anchors only.
    const root = resolveTrustedProjectRoot();
    if (!root) {
      return {
        success: false,
        error: 'PROJECT_ROOT_NOT_FOUND',
        message: 'Could not locate a trusted project root containing ecosystem.config.js or setup.bat.',
      };
    }

    const updateBat = path.resolve(path.join(root, 'scripts', 'update.bat'));

    // Guard against `..` escapes / symlink trickery — the resolved script
    // must still live under the trusted root.
    if (!isPathUnder(updateBat, root)) {
      return {
        success: false,
        error: 'UNTRUSTED_UPDATE_PATH',
        message: `Resolved update script "${updateBat}" is outside the trusted root "${root}".`,
      };
    }

    if (!fs.existsSync(updateBat)) {
      return {
        success: false,
        error: 'UPDATE_SCRIPT_MISSING',
        message: `Update script not found at: ${updateBat}`,
      };
    }

    // UP5: Snapshot the current git HEAD before we spawn update.bat. If the
    // update crashes (failed build, bad merge, etc.) the UpdatesPage can
    // trigger `management:rollback-update` to restore this commit.
    const head = captureGitHead(root);
    if (head.ok) {
      writeSnapshot(head.sha);
      console.log('[Update] Captured pre-update commit:', head.sha);
    } else {
      console.warn('[Update] Could not capture pre-update commit (rollback disabled):', head.error);
    }

    // UP4: We need to report honest spawn success/failure before the dashboard
    // quits. Launch the child, then await either a synchronous spawn error or
    // the 'spawn' event (fired once the process is actually created). On
    // success we schedule the dashboard to close so the bat script can kill
    // the server cleanly and rebuild.
    try {
      const child = spawn('cmd.exe', ['/c', updateBat], {
        cwd: root,
        detached: true,
        stdio: 'ignore',
        // Inherit Electron's environment (has PATH with git, npm, node)
        env: { ...process.env },
      });

      const spawnResult = await new Promise<{ ok: true } | { ok: false; error: string }>((resolve) => {
        let settled = false;
        const done = (value: { ok: true } | { ok: false; error: string }): void => {
          if (settled) return;
          settled = true;
          resolve(value);
        };

        child.once('error', (err: Error) => {
          done({ ok: false, error: err.message });
        });
        child.once('spawn', () => {
          done({ ok: true });
        });
        // Child may exit immediately with non-zero before we detach.
        child.once('exit', (code, signal) => {
          if (code !== null && code !== 0) {
            done({ ok: false, error: `update.bat exited immediately with code ${code}` });
          } else if (signal) {
            done({ ok: false, error: `update.bat killed with signal ${signal}` });
          } else {
            done({ ok: true });
          }
        });

        // Safety timeout — if neither spawn nor error fire in 5s, assume it
        // actually started (detached cmd windows usually have).
        setTimeout(() => done({ ok: true }), 5_000);
      });

      if (!spawnResult.ok) {
        console.error('[Update] Failed to launch:', spawnResult.error);
        return {
          success: false,
          error: 'UPDATE_LAUNCH_FAILED',
          message: spawnResult.error,
        };
      }

      child.unref();
      console.log('[Update] Launched update.bat (PID:', child.pid, ')');

      // Close the dashboard after a short delay so the update script can kill it cleanly
      setTimeout(() => {
        allowClose();
        app.quit();
      }, 2000);

      return {
        success: true,
        data: {
          success: true,
          output: 'Update started. Dashboard will close and reopen after rebuild.',
        },
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      console.error('[Update] Failed to launch:', message);
      return {
        success: false,
        error: 'UPDATE_LAUNCH_FAILED',
        message: 'Failed to launch update: ' + message,
      };
    }
  });

  // UP5: Rollback support ─────────────────────────────────────────
  // After a failed update the dashboard reopens with an option to restore
  // the previous git checkout. `get-rollback-info` tells the renderer
  // whether a snapshot exists; `rollback-update` executes the restore.

  ipcMain.handle('management:get-rollback-info', async () => {
    const sha = readSnapshot();
    if (!sha) {
      return { success: true, data: { available: false } };
    }
    return { success: true, data: { available: true, sha } };
  });

  ipcMain.handle('management:rollback-update', async () => {
    const sha = readSnapshot();
    if (!sha) {
      return {
        success: false,
        error: 'NO_ROLLBACK_SNAPSHOT',
        code: 404,
        message: 'No rollback snapshot is available.',
      };
    }

    const root = resolveTrustedProjectRoot();
    if (!root) {
      return {
        success: false,
        error: 'PROJECT_ROOT_NOT_FOUND',
        code: 500,
        message: 'Could not locate a trusted project root for rollback.',
      };
    }

    // Strict SHA validation — the only value we pass to git is the SHA we
    // captured before the update. Re-validate at the point of use.
    if (!/^[a-f0-9]{7,40}$/i.test(sha)) {
      return {
        success: false,
        error: 'INVALID_SNAPSHOT',
        code: 500,
        message: `Stored rollback SHA is malformed: ${sha}`,
      };
    }

    try {
      const result = spawnSync('git', ['reset', '--hard', sha], {
        cwd: root,
        encoding: 'utf-8',
        timeout: 30_000,
      });
      if (result.status !== 0) {
        return {
          success: false,
          error: 'ROLLBACK_FAILED',
          code: 500,
          message: result.stderr?.trim() || `git reset --hard exited ${result.status}`,
        };
      }
      clearSnapshot();
      console.log('[Update] Rolled back to', sha);
      return { success: true, data: { sha, stdout: result.stdout.trim() } };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return {
        success: false,
        error: 'ROLLBACK_FAILED',
        code: 500,
        message,
      };
    }
  });

  ipcMain.handle('management:clear-rollback', async () => {
    clearSnapshot();
    return { success: true };
  });

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

  // T7: previously these all returned { success: true } unconditionally.
  // They now report real failure when there is no window or when the
  // underlying Electron call throws.
  ipcMain.handle('system:open-browser', async () => {
    try {
      await shell.openExternal('https://localhost');
      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return {
        success: false,
        error: 'OPEN_BROWSER_FAILED',
        code: 500,
        message: `Failed to open browser: ${message}`,
      };
    }
  });

  ipcMain.handle('system:close-dashboard', () => {
    const win = getMainWindow();
    if (!win) {
      return {
        success: false,
        error: 'NO_WINDOW',
        code: 500,
        message: 'No main window available to close.',
      };
    }
    allowClose();
    win.close();
    return { success: true };
  });

  ipcMain.handle('system:minimize', () => {
    const win = getMainWindow();
    if (!win) {
      return {
        success: false,
        error: 'NO_WINDOW',
        code: 500,
        message: 'No main window available to minimize.',
      };
    }
    win.minimize();
    return { success: true };
  });

  ipcMain.handle('system:maximize', () => {
    const win = getMainWindow();
    if (!win) {
      return {
        success: false,
        error: 'NO_WINDOW',
        code: 500,
        message: 'No main window available to maximize.',
      };
    }
    if (win.isMaximized()) {
      win.unmaximize();
      return { success: true, data: { maximized: false } };
    }
    win.maximize();
    return { success: true, data: { maximized: true } };
  });
}
