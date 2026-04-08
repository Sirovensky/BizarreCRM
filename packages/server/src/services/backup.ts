import { config } from '../config.js';
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import { execSync } from 'child_process';
import cron from 'node-cron';

type AnyRow = Record<string, any>;

function getConfig(db: any, key: string, fallback = ''): string {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as AnyRow | undefined;
  return row?.value ?? fallback;
}

function setConfig(db: any, key: string, value: string): void {
  db.prepare('INSERT INTO store_config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?').run(key, value, value);
}

export function getBackupSettings(db: any) {
  return {
    path: getConfig(db, 'backup_path', ''),
    schedule: getConfig(db, 'backup_schedule', '0 3 * * *'), // default 3 AM daily
    retention: parseInt(getConfig(db, 'backup_retention', '30'), 10),
    lastBackup: getConfig(db, 'backup_last_run', ''),
    lastStatus: getConfig(db, 'backup_last_status', ''),
  };
}

export function updateBackupSettings(db: any, settings: { path?: string; schedule?: string; retention?: number }) {
  if (settings.path !== undefined) setConfig(db, 'backup_path', settings.path);
  if (settings.schedule !== undefined) setConfig(db, 'backup_schedule', settings.schedule);
  if (settings.retention !== undefined) setConfig(db, 'backup_retention', String(settings.retention));
  scheduleBackup(db); // reschedule with new settings
}

export async function runBackup(
  db: any,
  opts?: { tenantSlug?: string; tenantId?: number },
): Promise<{ success: boolean; message: string; file?: string }> {
  const backupDir = getConfig(db, 'backup_path', '');
  if (!backupDir) return { success: false, message: 'No backup path configured' };

  if (!fs.existsSync(backupDir)) {
    try { fs.mkdirSync(backupDir, { recursive: true }); }
    catch { return { success: false, message: `Cannot create backup directory: ${backupDir}` }; }
  }

  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const prefix = opts?.tenantSlug
    ? `${opts.tenantSlug}-t${opts.tenantId ?? 0}`
    : 'bizarre-crm';
  const dbDest = path.join(backupDir, `${prefix}-${ts}.db`);
  const uploadsDest = path.join(backupDir, `uploads-${ts}`);

  try {
    // Async SQLite backup (safe while DB is in use)
    await db.backup(dbDest);

    // Copy uploads folder (async to avoid blocking the event loop)
    if (fs.existsSync(config.uploadsPath)) {
      await fsp.cp(config.uploadsPath, uploadsDest, { recursive: true });
    }

    // Prune old backups
    const retention = parseInt(getConfig(db, 'backup_retention', '30'), 10);
    pruneBackups(backupDir, retention);

    setConfig(db, 'backup_last_run', new Date().toISOString());
    setConfig(db, 'backup_last_status', 'success');

    console.log(`[Backup] Completed: ${dbDest}`);
    return { success: true, message: 'Backup completed', file: dbDest };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    setConfig(db, 'backup_last_status', `failed: ${msg}`);
    console.error(`[Backup] Failed:`, msg);
    return { success: false, message: msg };
  }
}

/** Match both legacy (bizarre-crm-*) and tenant-based (*-t*-*) backup filenames */
function isBackupFile(f: string): boolean {
  return f.endsWith('.db') && (f.startsWith('bizarre-crm-') || /^.+-t\d+-\d{4}-\d{2}/.test(f));
}

function pruneBackups(dir: string, keep: number) {
  const files = fs.readdirSync(dir)
    .filter(isBackupFile)
    .sort()
    .reverse();

  for (const file of files.slice(keep)) {
    const dbFile = path.join(dir, file);
    // Derive uploads dir: strip the prefix up to the timestamp portion
    const tsMatch = file.match(/(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})/);
    if (tsMatch) {
      const uploadsDir = path.join(dir, `uploads-${tsMatch[1]}`);
      try { fs.rmSync(uploadsDir, { recursive: true, force: true }); } catch {}
    }
    try { fs.unlinkSync(dbFile); } catch {}
  }
}

export function listBackups(db: any): { name: string; size: number; date: string }[] {
  const backupDir = getConfig(db, 'backup_path', '');
  if (!backupDir || !fs.existsSync(backupDir)) return [];

  return fs.readdirSync(backupDir)
    .filter(isBackupFile)
    .map(f => {
      const stat = fs.statSync(path.join(backupDir, f));
      return { name: f, size: stat.size, date: stat.mtime.toISOString() };
    })
    .sort((a, b) => b.date.localeCompare(a.date));
}

export function deleteBackup(db: any, filename: string): boolean {
  const backupDir = getConfig(db, 'backup_path', '');
  if (!backupDir || !isBackupFile(filename)) return false;

  const dbFile = path.join(backupDir, filename);
  // Derive uploads dir from the timestamp in the filename
  const tsMatch = filename.match(/(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})/);
  const uploadsDir = tsMatch
    ? path.join(backupDir, `uploads-${tsMatch[1]}`)
    : path.join(backupDir, filename.replace('.db', '-uploads'));

  // Path traversal protection: verify resolved paths stay inside backupDir
  const resolvedBackupDir = path.resolve(backupDir);
  if (!path.resolve(dbFile).startsWith(resolvedBackupDir + path.sep) ||
      !path.resolve(uploadsDir).startsWith(resolvedBackupDir + path.sep)) {
    console.error(`[Backup] Path traversal blocked: ${filename}`);
    return false;
  }

  try { fs.unlinkSync(dbFile); } catch {}
  try { fs.rmSync(uploadsDir, { recursive: true, force: true }); } catch {}
  return true;
}

// Cross-platform drive detection (includes network drives)
export function listDrives(): { path: string; label: string; free: number; total: number }[] {
  const isWin = process.platform === 'win32';
  try {
    if (isWin) {
      const out = execSync(
        'powershell -Command "Get-PSDrive -PSProvider FileSystem | Select-Object Name,Free,Used,Root | ConvertTo-Csv -NoTypeInformation"',
        { encoding: 'utf8', timeout: 10000 },
      );
      return out.split('\n').slice(1).filter(l => l.trim()).map(line => {
        const cols = line.replace(/"/g, '').split(',');
        if (cols.length < 4 || !cols[0]) return null;
        const [name, free, used, root] = cols;
        const freeBytes = parseInt(free) || 0;
        const usedBytes = parseInt(used) || 0;
        return { path: root.trim(), label: name.trim() + ':', free: freeBytes, total: freeBytes + usedBytes };
      }).filter(Boolean) as any[];
    } else {
      const out = execSync("df -B1 --output=target,avail,size 2>/dev/null | tail -n +2", { encoding: 'utf8', timeout: 5000 });
      return out.split('\n').filter(l => l.trim()).map(line => {
        const parts = line.trim().split(/\s+/);
        if (parts.length < 3) return null;
        const [mount, avail, size] = parts;
        if (mount.startsWith('/snap') || mount.startsWith('/boot')) return null;
        return { path: mount, label: mount, free: parseInt(avail) || 0, total: parseInt(size) || 0 };
      }).filter(Boolean) as any[];
    }
  } catch {
    return [{ path: isWin ? 'C:\\' : '/', label: 'Default', free: 0, total: 0 }];
  }
}

// Cron management
let cronTask: cron.ScheduledTask | null = null;

export function scheduleBackup(db: any) {
  if (cronTask) { cronTask.stop(); cronTask = null; }
  const schedule = getConfig(db, 'backup_schedule', '0 3 * * *');
  const backupPath = getConfig(db, 'backup_path', '');
  if (!backupPath || !cron.validate(schedule)) return;

  cronTask = cron.schedule(schedule, () => { runBackup(db); });
  console.log(`[Backup] Scheduled: "${schedule}" -> ${backupPath}`);
}
