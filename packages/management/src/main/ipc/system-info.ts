/**
 * IPC handlers for system-level info (disk space, OS, etc.).
 * Runs in Electron main process — no server dependency.
 */
import { ipcMain, shell, app } from 'electron';
import { execSync, spawn } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';

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
  } catch {
    return [];
  }
}

export function registerSystemInfoIpc(): void {
  ipcMain.handle('system:get-disk-space', async () => {
    return { success: true, data: getDiskSpace() };
  });

  ipcMain.handle('system:get-info', async () => {
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
  ipcMain.handle('system:open-external', async (_event, url: unknown) => {
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

  ipcMain.handle('system:open-log-file', async () => {
    // EL4: No more `exec(string)`. We resolve the pm2 binary to an absolute
    // path from PATH / APPDATA, then `spawn` with explicit args. If pm2
    // isn't installed we fall back to opening the server data folder.
    const pm2Binary = resolvePm2Binary();

    if (!pm2Binary) {
      const dataDir = path.join(
        app.getAppPath(),
        '..',
        '..',
        'packages',
        'server',
        'data',
      );
      try {
        const result = await shell.openPath(dataDir);
        if (result) {
          // shell.openPath resolves with an error message on failure
          await shell.openPath(path.dirname(app.getAppPath()));
        }
        return { success: true, data: { mode: 'folder' } };
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
