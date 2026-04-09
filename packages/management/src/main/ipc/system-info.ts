/**
 * IPC handlers for system-level info (disk space, OS, etc.).
 * Runs in Electron main process — no server dependency.
 */
import { ipcMain, shell, app } from 'electron';
import { execSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';

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

  ipcMain.handle('system:open-external', async (_event, url: string) => {
    // Only allow localhost URLs and https
    if (url.startsWith('https://localhost') || url.startsWith('http://localhost')) {
      shell.openExternal(url);
      return { success: true };
    }
    return { success: false, message: 'Only localhost URLs are allowed' };
  });

  ipcMain.handle('system:open-log-file', async () => {
    const { exec } = await import('node:child_process');
    try {
      // Try PM2 first, fall back to opening the data directory
      exec('pm2 --version', (err) => {
        if (err) {
          // PM2 not installed — open the server data folder instead
          const dataDir = path.join(app.getAppPath(), '..', '..', 'packages', 'server', 'data');
          shell.openPath(dataDir).catch(() => {
            shell.openPath(path.dirname(app.getAppPath()));
          });
        } else {
          exec('start cmd /k "pm2 logs bizarre-crm --lines 100"');
        }
      });
      return { success: true };
    } catch {
      return { success: false, message: 'Could not open log viewer' };
    }
  });
}
