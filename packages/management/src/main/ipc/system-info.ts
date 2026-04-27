/**
 * IPC handlers for system-level info (disk space, OS, etc.).
 * Runs in Electron main process — no server dependency.
 */
import { ipcMain, shell, app } from 'electron';
import { execSync, spawn } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { assertRendererOrigin } from './management-api.js';

/** Loopback hostnames allowed by `system:open-external`. */
const LOOPBACK_EXTERNAL_HOSTS = new Set<string>([
  'localhost',
  '127.0.0.1',
  '::1',
]);

/**
 * EL5: Parse the URL with `new URL()` and check its hostname and scheme.
 * Prefix matching is insecure — `http://localhost@attacker.com` starts with
 * `http://localhost` but has hostname `attacker.com`.
 */
function isSafeLocalUrl(raw: string): boolean {
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return false;
    }
    // URL.hostname for `[::1]` returns `[::1]`; strip brackets before check.
    const host = parsed.hostname.toLowerCase().replace(/^\[|\]$/g, '');
    return LOOPBACK_EXTERNAL_HOSTS.has(host);
  } catch {
    return false;
  }
}

/**
 * EL4: Locate the pm2 binary without shelling out to `which`/`where` with a
 * user-controlled string. We check the common install locations and PATH
 * candidates directly from Node and return an absolute path. Returns null if
 * pm2 isn't installed.
 */
function resolvePm2Binary(): string | null {
  const pathEnv = process.env.PATH ?? '';
  const pathExt = (process.env.PATHEXT ?? '.CMD;.EXE;.BAT').split(';');
  const candidatesExe = ['pm2.cmd', 'pm2.exe', 'pm2.bat', 'pm2'];

  for (const dir of pathEnv.split(path.delimiter)) {
    if (!dir) continue;
    for (const name of candidatesExe) {
      const candidate = path.join(dir, name);
      try {
        if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
          return candidate;
        }
      } catch {
        /* ignore unreadable dirs */
      }
    }
  }

  // Fall back to npm global prefix if set.
  const npmPrefix = process.env.APPDATA
    ? path.join(process.env.APPDATA, 'npm')
    : null;
  if (npmPrefix) {
    for (const name of candidatesExe) {
      const candidate = path.join(npmPrefix, name);
      try {
        if (fs.existsSync(candidate)) return candidate;
      } catch {
        /* ignore */
      }
    }
  }
  // pathExt is just a hint — referenced so the symbol isn't unused.
  void pathExt;
  return null;
}

interface DiskDrive {
  mount: string;
  total: number;
  free: number;
  used: number;
}

function getDiskSpace(): DiskDrive[] {
  // @audit-fixed: previously this only used `wmic logicaldisk`, which is
  // deprecated and has been REMOVED from fresh Windows 11 24H2+ installs.
  // On those systems the call threw and the user silently saw an empty disk
  // list. We now try wmic first (still present on older / Server SKUs and
  // it's the fastest non-admin path), then fall back to PowerShell's
  // Get-PSDrive on the modern boxes. Both are invoked with `execSync` and
  // an explicit timeout, and any failure is logged so the dashboard
  // operator can tell *why* the disks list is empty instead of guessing.
  const wmic = tryWmicDiskSpace();
  if (wmic.length > 0) return wmic;

  const powershell = tryPowershellDiskSpace();
  if (powershell.length > 0) return powershell;

  return [];
}

function tryWmicDiskSpace(): DiskDrive[] {
  try {
    const raw = execSync(
      'wmic logicaldisk get caption,freespace,size /format:csv',
      { encoding: 'utf-8', timeout: 10_000 }
    );

    const lines = raw.trim().split('\n').filter(l => l.trim() && !l.startsWith('Node'));
    const drives: DiskDrive[] = [];

    for (const line of lines) {
      const parts = line.trim().split(',');
      if (parts.length < 4) continue;

      const mount = parts[1];
      const free = parseInt(parts[2], 10);
      const total = parseInt(parts[3], 10);

      if (!mount || isNaN(free) || isNaN(total) || total === 0) continue;

      drives.push({
        mount,
        total,
        free,
        used: total - free,
      });
    }

    return drives;
  } catch (err) {
    // wmic.exe is missing on Windows 11 24H2+. Don't spam the log on every
    // poll — log once and let the powershell fallback take over.
    console.warn(
      '[system-info] wmic logicaldisk failed (probably removed from this Windows build):',
      err instanceof Error ? err.message : String(err)
    );
    return [];
  }
}

function tryPowershellDiskSpace(): DiskDrive[] {
  try {
    // @audit-fixed: PowerShell fallback for modern Windows builds. We use
    // an explicit absolute path to powershell.exe (resolved from
    // %SystemRoot%) so a hostile PATH entry can't substitute its own
    // pwsh shim. The script is hard-coded — no caller-supplied input.
    const systemRoot = process.env.SystemRoot ?? 'C:\\Windows';
    const psExe = path.join(systemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    if (!fs.existsSync(psExe)) return [];

    // DASH-ELEC-004: execSync is acceptable here because the script is a
    // hardcoded literal — no caller-supplied input reaches this shell string.
    // Do NOT use this pattern with dynamic input; use spawnSync with an
    // explicit argv array instead to avoid shell injection.
    const script = `Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object { "$($_.Root),$($_.Free),$($_.Used + $_.Free)" }`;
    const raw = execSync(`"${psExe}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "${script}"`, {
      encoding: 'utf-8',
      timeout: 10_000,
      windowsHide: true,
    });

    const drives: DiskDrive[] = [];
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      const [rawMount, rawFree, rawTotal] = trimmed.split(',');
      const mount = (rawMount ?? '').replace(/[\\:]+$/, '').replace(/\\$/, '');
      const free = parseInt(rawFree ?? '', 10);
      const total = parseInt(rawTotal ?? '', 10);
      if (!mount || isNaN(free) || isNaN(total) || total === 0) continue;
      drives.push({ mount: `${mount}:`, total, free, used: total - free });
    }
    return drives;
  } catch (err) {
    console.warn(
      '[system-info] PowerShell Get-PSDrive fallback failed:',
      err instanceof Error ? err.message : String(err)
    );
    return [];
  }
}

export function registerSystemInfoIpc(): void {
  // AUDIT-MGT-005: assertRendererOrigin guards every system:* handler.
  ipcMain.handle('system:get-disk-space', async (event) => {
    assertRendererOrigin(event);
    return { success: true, data: getDiskSpace() };
  });

  ipcMain.handle('system:get-info', async (event) => {
    assertRendererOrigin(event);
    return {
      success: true,
      data: {
        platform: os.platform(),
        arch: os.arch(),
        hostname: os.hostname(),
        totalMemory: os.totalmem(),
        freeMemory: os.freemem(),
        cpus: os.cpus().length,
        nodeVersion: process.version,
        electronVersion: process.versions.electron,
        appVersion: app.getVersion(),
        isPackaged: app.isPackaged,
      },
    };
  });

  // EL5: Only allow loopback URLs via explicit URL parsing + hostname check.
  // String prefix checks are unsafe (`http://localhost@attacker.com`).
  ipcMain.handle('system:open-external', async (event, url: unknown) => {
    assertRendererOrigin(event);
    if (typeof url !== 'string' || !isSafeLocalUrl(url)) {
      return {
        success: false,
        error: 'URL_NOT_ALLOWED',
        code: 400,
        message: 'Only loopback URLs (localhost, 127.0.0.1, ::1) are allowed.',
      };
    }
    try {
      await shell.openExternal(url);
      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return {
        success: false,
        error: 'OPEN_EXTERNAL_FAILED',
        code: 500,
        message,
      };
    }
  });

  // DASH-ELEC-206: Add `event` parameter so assertRendererOrigin can verify the
  // caller is the renderer (not an injected script from a rogue webview).
  ipcMain.handle('system:open-log-file', async (event) => {
    assertRendererOrigin(event);
    // EL4: No more `exec(string)`. We resolve the pm2 binary to an absolute
    // path from PATH / APPDATA, then `spawn` with explicit args. If pm2
    // isn't installed we fall back to opening the server data folder.
    const pm2Binary = resolvePm2Binary();

    if (!pm2Binary) {
      // @audit-fixed: previously this hand-rolled `path.join(appPath, '..', '..', 'packages', 'server', 'data')`
      // which works in the dev monorepo layout but resolves OUTSIDE the
      // installed app's resourcesPath in a packaged build, ending up in
      // some unrelated folder under Program Files (or worse, returning a
      // non-existent location). Now we walk a list of trusted candidates:
      //   1) `<resourcesPath>/crm-source/packages/server/data` (the
      //      packaged extraResources copy from electron-builder.yml)
      //   2) The dev monorepo layout, only when not packaged
      //   3) The Electron `userData` directory as a last-resort fallback
      // Each candidate is `path.resolve`d and verified to exist before
      // we hand it to `shell.openPath`. We also verify the resolved path
      // does not escape its trusted anchor via `..`-traversal.
      const candidates: { anchor: string; sub: string[] }[] = [];
      if (typeof process.resourcesPath === 'string' && process.resourcesPath.length > 0) {
        candidates.push({
          anchor: process.resourcesPath,
          sub: ['crm-source', 'packages', 'server', 'data'],
        });
      }
      if (!app.isPackaged) {
        candidates.push({
          anchor: app.getAppPath(),
          sub: ['..', '..', 'packages', 'server', 'data'],
        });
      }
      candidates.push({
        anchor: app.getPath('userData'),
        sub: [],
      });

      let resolvedDir: string | null = null;
      for (const c of candidates) {
        const dir = path.resolve(path.join(c.anchor, ...c.sub));
        // Reject any traversal that escapes the anchor.
        const anchorAbs = path.resolve(c.anchor);
        const rel = path.relative(anchorAbs, dir);
        if (rel.startsWith('..') || path.isAbsolute(rel)) continue;
        if (fs.existsSync(dir)) {
          resolvedDir = dir;
          break;
        }
      }

      if (!resolvedDir) {
        return {
          success: false,
          error: 'NO_DATA_DIR',
          code: 500,
          message: 'Could not locate the CRM data directory.',
        };
      }

      try {
        const result = await shell.openPath(resolvedDir);
        if (result) {
          // shell.openPath resolves to an error string on failure.
          return {
            success: false,
            error: 'OPEN_DATA_DIR_FAILED',
            code: 500,
            message: result,
          };
        }
        return { success: true, data: { mode: 'folder', path: resolvedDir } };
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Unknown error';
        return {
          success: false,
          error: 'OPEN_DATA_DIR_FAILED',
          code: 500,
          message,
        };
      }
    }

    try {
      // Open a visible cmd window that runs `pm2 logs`. We use `spawn` with
      // an explicit args array (no shell string interpolation). cmd.exe is
      // resolved via %SystemRoot% which is set by Windows itself.
      const systemRoot = process.env.SystemRoot ?? 'C:\\Windows';
      const cmdExe = path.join(systemRoot, 'System32', 'cmd.exe');
      const args = [
        '/c',
        'start',
        '""',
        cmdExe,
        '/k',
        pm2Binary,
        'logs',
        'bizarre-crm',
        '--lines',
        '100',
      ];
      const child = spawn(cmdExe, args, {
        detached: true,
        stdio: 'ignore',
      });
      child.unref();
      return { success: true, data: { mode: 'pm2', binary: pm2Binary } };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return {
        success: false,
        error: 'OPEN_LOG_FAILED',
        code: 500,
        message,
      };
    }
  });
}
