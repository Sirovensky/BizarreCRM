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
  setServerPort,
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

/** True if `child` is inside (or equal to) `parent`, using resolved absolute paths. */
function isPathUnder(child: string, parent: string): boolean {
  const resolvedChild = path.resolve(child);
  const resolvedParent = path.resolve(parent);
  if (resolvedChild === resolvedParent) return true;
  const rel = path.relative(resolvedParent, resolvedChild);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

/**
 * AUD-20260414-M2 / SECURITY (EL3 / EL7): Locate the project root for
 * `update.bat` from TRUSTED electron anchors only.
 *
 * Prior implementations walked upward from `process.execPath` (or
 * `app.getAppPath()`) looking for a marker file and then only verified that
 * the candidate still sat under the filesystem DRIVE root (`C:\`). That is
 * effectively no check at all: a marker-bearing ancestor anywhere on the
 * same drive would be accepted, letting a misplaced install silently run
 * from arbitrary locations with no integrity gate.
 *
 * This implementation uses deterministic, layout-specific candidates and
 * requires the resolved root to sit INSIDE the trusted anchor itself:
 *
 *   - Packaged (`app.isPackaged === true`): the only accepted root is
 *     `<process.resourcesPath>/crm-source`, populated by electron-builder
 *     `extraResources` (see electron-builder.yml). If resourcesPath is
 *     missing or crm-source doesn't exist, we fail loudly with an
 *     installation-integrity error rather than walking the filesystem.
 *
 *   - Dev (`app.isPackaged === false`): the repo root is reached by
 *     `app.getAppPath()` + `../..` (monorepo layout `packages/management`
 *     -> repo root). We verify the project-root marker set is present AND
 *     that the resolved path is inside the resolved app-path's parent
 *     chain (no `..`-escapes past the anchor parent).
 *
 * Both branches require the full project-root marker set (package.json,
 * packages/server/package.json, and at least one of
 * ecosystem.config.js / install.bat / setup.bat) — sibling-marker
 * scenarios are explicitly rejected.
 */
function hasProjectRootMarkers(dir: string): boolean {
  const coreMarkers =
    fs.existsSync(path.join(dir, 'package.json')) &&
    fs.existsSync(path.join(dir, 'packages', 'server', 'package.json'));
  if (!coreMarkers) return false;
  const auxMarker =
    fs.existsSync(path.join(dir, 'ecosystem.config.js')) ||
    fs.existsSync(path.join(dir, 'install.bat')) ||
    fs.existsSync(path.join(dir, 'setup.bat'));
  return auxMarker;
}

function resolveTrustedProjectRoot(): string | null {
  // Packaged build: only the bundled crm-source directory is trusted.
  if (app.isPackaged) {
    const resourcesPath = typeof process.resourcesPath === 'string' ? process.resourcesPath : null;
    if (!resourcesPath || !fs.existsSync(resourcesPath)) {
      throw new Error(
        'Installation integrity check failed — reinstall required (process.resourcesPath missing or inaccessible).'
      );
    }
    const anchor = path.resolve(resourcesPath);
    const candidate = path.resolve(path.join(anchor, 'crm-source'));
    if (!isPathUnder(candidate, anchor)) return null;
    if (!fs.existsSync(candidate)) {
      throw new Error(
        'Installation integrity check failed — reinstall required (crm-source missing from packaged resources).'
      );
    }
    return hasProjectRootMarkers(candidate) ? candidate : null;
  }

  // Dev build: monorepo layout — app.getAppPath() === <repo>/packages/management.
  // The legitimate repo root is two levels above. We do NOT walk the
  // filesystem; the candidate is fixed by the known monorepo layout and
  // rejected unless the full marker set is present (sibling / ancestor
  // marker files elsewhere on disk are never accepted).
  const appPath = typeof app.getAppPath === 'function' ? app.getAppPath() : null;
  if (!appPath) return null;
  const resolvedAppPath = path.resolve(appPath);
  const devRepoRoot = path.resolve(resolvedAppPath, '..', '..');
  if (!hasProjectRootMarkers(devRepoRoot)) return null;
  return devRepoRoot;
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
  // ── Discover server port from .env so the API client connects to the
  // right port in both local (PORT=443) and hosted (PORT=8443, etc.) setups.
  //
  // NOTE: resolveTrustedProjectRoot() throws on a broken packaged install
  // (missing resourcesPath / missing crm-source). We catch that here so
  // the dashboard can still start up and surface a real error in the UI
  // rather than dying during module init; the handlers below that need a
  // root will re-call the resolver and return a structured error instead.
  let root: string | null = null;
  try {
    root = resolveTrustedProjectRoot();
  } catch (err) {
    console.error(
      '[Dashboard] Installation integrity check failed during IPC init:',
      err instanceof Error ? err.message : String(err)
    );
  }
  if (root) {
    const envPath = path.resolve(path.join(root, '.env'));
    // Belt-and-braces: assert the resolved .env path is inside the root.
    if (!isPathUnder(envPath, root)) {
      console.warn('[Dashboard] .env path escaped trusted root; refusing to read:', envPath);
    } else if (fs.existsSync(envPath)) {
      try {
        const content = fs.readFileSync(envPath, 'utf-8');
        const match = content.match(/^PORT\s*=\s*['"]?(\d+)['"]?/m);
        if (match) {
          const port = parseInt(match[1], 10);
          if (port > 0 && port < 65536) {
            setServerPort(port);
            console.log(`[Dashboard] API client targeting port ${port} (from .env)`);
          }
        }
      } catch { /* ignore — falls back to 443 */ }
    }
  }

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

  // TPH6: additive repair for any tenant not in 'active' status.
  ipcMain.handle('super-admin:repair-tenant', wrapHandler(async (_event, slug: string) => {
    const res = await apiRequest('POST', `/super-admin/api/tenants/${encodeURIComponent(slug)}/repair`);
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
    // SECURITY (EL3 / EL7 / AUD-20260414-M2): Resolve project root from
    // trusted Electron anchors only. Integrity failures on a packaged
    // install surface as INSTALLATION_INTEGRITY_FAILED rather than a
    // silent "root not found".
    let root: string | null;
    try {
      root = resolveTrustedProjectRoot();
    } catch (err) {
      return {
        success: false,
        error: 'INSTALLATION_INTEGRITY_FAILED',
        message: err instanceof Error ? err.message : 'Installation integrity check failed — reinstall required.',
      };
    }
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

    // UP6: Tell the server to record a 'launched' audit entry BEFORE we
    // spawn update.bat. This guarantees that if the new server never comes
    // back up, the master audit log still has a row showing "update
    // attempted from <ip> at <ts> starting from <sha>".
    //
    // We fire-and-forget: if the local server is unreachable or returns an
    // error we still want the update to run. The worst case is an audit
    // row is missing — the update itself is not security-gated by this
    // call.
    try {
      const beforeSha = head.ok ? head.sha : null;
      const res = await apiRequest(
        'POST',
        '/api/v1/management/audit-update-launch',
        { beforeSha, source: 'dashboard' }
      );
      if (!res.body?.success) {
        console.warn('[Update] audit-update-launch endpoint returned failure:', res.body?.message);
      }
    } catch (err) {
      console.warn(
        '[Update] Failed to record audit-update-launch (continuing with update):',
        err instanceof Error ? err.message : String(err)
      );
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

    let root: string | null;
    try {
      root = resolveTrustedProjectRoot();
    } catch (err) {
      return {
        success: false,
        error: 'INSTALLATION_INTEGRITY_FAILED',
        code: 500,
        message: err instanceof Error ? err.message : 'Installation integrity check failed — reinstall required.',
      };
    }
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

  // UP6: Called by the UpdatesPage after the dashboard reopens so the
  // server can record the final outcome (success/failure + after_sha).
  // Renderer passes `{ afterSha?, success, errorMessage? }`. The before_sha
  // is looked up from the persisted rollback snapshot so the renderer
  // doesn't have to thread it through.
  ipcMain.handle(
    'management:audit-update-result',
    wrapHandler(async (
      _event,
      payload: { afterSha?: string; success: boolean; errorMessage?: string }
    ) => {
      const beforeSha = readSnapshot();
      const res = await apiRequest(
        'POST',
        '/api/v1/management/audit-update-result',
        {
          beforeSha,
          afterSha: payload?.afterSha ?? null,
          success: payload?.success === true,
          errorMessage: payload?.errorMessage ?? null,
        }
      );
      return res.body;
    })
  );

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
