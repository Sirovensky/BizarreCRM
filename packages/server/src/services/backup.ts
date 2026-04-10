import { config } from '../config.js';
import crypto from 'crypto';
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import { execSync } from 'child_process';
import cron from 'node-cron';

// ─── AES-256-GCM backup encryption ─────────────────────────────────
// Derives a 256-bit key from the JWT_SECRET using PBKDF2 with a random salt.
// File format: [16-byte salt][12-byte IV][16-byte auth tag][ciphertext]

const ENCRYPTION_ALGO = 'aes-256-gcm' as const;
const SALT_LEN = 16;
const IV_LEN = 12;
const AUTH_TAG_LEN = 16;
const KEY_LEN = 32;
const PBKDF2_ITERATIONS = 100_000;

function deriveKey(salt: Buffer): Buffer {
  return crypto.pbkdf2Sync(config.jwtSecret, salt, PBKDF2_ITERATIONS, KEY_LEN, 'sha512');
}

export async function encryptFile(inputPath: string): Promise<string> {
  const outputPath = inputPath + '.enc';
  const plaintext = await fsp.readFile(inputPath);

  const salt = crypto.randomBytes(SALT_LEN);
  const iv = crypto.randomBytes(IV_LEN);
  const key = deriveKey(salt);

  const cipher = crypto.createCipheriv(ENCRYPTION_ALGO, key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const authTag = cipher.getAuthTag();

  // Write: salt | iv | authTag | ciphertext
  await fsp.writeFile(outputPath, Buffer.concat([salt, iv, authTag, encrypted]));

  // Remove the unencrypted original
  await fsp.unlink(inputPath);

  return outputPath;
}

export async function decryptFile(encPath: string, outputPath: string): Promise<void> {
  const data = await fsp.readFile(encPath);

  const salt = data.subarray(0, SALT_LEN);
  const iv = data.subarray(SALT_LEN, SALT_LEN + IV_LEN);
  const authTag = data.subarray(SALT_LEN + IV_LEN, SALT_LEN + IV_LEN + AUTH_TAG_LEN);
  const ciphertext = data.subarray(SALT_LEN + IV_LEN + AUTH_TAG_LEN);

  const key = deriveKey(salt);
  const decipher = crypto.createDecipheriv(ENCRYPTION_ALGO, key, iv);
  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  await fsp.writeFile(outputPath, decrypted);
}

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
    encrypt: getConfig(db, 'backup_encrypt', '') === 'true',
    lastBackup: getConfig(db, 'backup_last_run', ''),
    lastStatus: getConfig(db, 'backup_last_status', ''),
  };
}

export function updateBackupSettings(db: any, settings: { path?: string; schedule?: string; retention?: number; encrypt?: boolean }) {
  if (settings.path !== undefined) setConfig(db, 'backup_path', settings.path);
  if (settings.schedule !== undefined) setConfig(db, 'backup_schedule', settings.schedule);
  if (settings.retention !== undefined) setConfig(db, 'backup_retention', String(settings.retention));
  if (settings.encrypt !== undefined) setConfig(db, 'backup_encrypt', String(settings.encrypt));
  scheduleBackup(db); // reschedule with new settings
}

export async function runBackup(
  db: any,
  opts?: { tenantSlug?: string; tenantId?: number; encrypt?: boolean },
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

    // Optional AES-256-GCM encryption of the database backup
    const shouldEncrypt = opts?.encrypt ?? getConfig(db, 'backup_encrypt', '') === 'true';
    let finalDbPath = dbDest;
    if (shouldEncrypt) {
      finalDbPath = await encryptFile(dbDest);
      console.log(`[Backup] Encrypted: ${finalDbPath}`);
    }

    // Prune old backups
    const retention = parseInt(getConfig(db, 'backup_retention', '30'), 10);
    pruneBackups(backupDir, retention);

    setConfig(db, 'backup_last_run', new Date().toISOString());
    setConfig(db, 'backup_last_status', 'success');

    console.log(`[Backup] Completed: ${finalDbPath}`);
    return { success: true, message: 'Backup completed', file: finalDbPath };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    setConfig(db, 'backup_last_status', `failed: ${msg}`);
    console.error(`[Backup] Failed:`, msg);
    return { success: false, message: msg };
  }
}

/** Match both legacy (bizarre-crm-*) and tenant-based (*-t*-*) backup filenames (plain or encrypted) */
function isBackupFile(f: string): boolean {
  const isDb = f.endsWith('.db') || f.endsWith('.db.enc');
  return isDb && (f.startsWith('bizarre-crm-') || /^.+-t\d+-\d{4}-\d{2}/.test(f));
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

// ─── Multi-tenant per-tenant backup ────────────────────────────────────────
// Runs a single global cron at 3am that iterates through Pro tenants and backs up
// each one's tenant DB. Free tenants are skipped (Pro feature).

let multiTenantBackupCron: cron.ScheduledTask | null = null;

/** Schedule per-tenant backups for all active Pro tenants. Runs once daily.
 *  Pass the function `getTenantDb(slug)` so we can avoid a circular import. */
export function scheduleMultiTenantBackups(
  getMasterDb: () => any,
  getTenantDb: (slug: string) => any,
): void {
  if (multiTenantBackupCron) { multiTenantBackupCron.stop(); multiTenantBackupCron = null; }

  // Daily at 3:07 AM (off-minute to avoid the :00 thundering herd)
  multiTenantBackupCron = cron.schedule('7 3 * * *', async () => {
    try {
      const masterDb = getMasterDb();
      if (!masterDb) return;

      // Pro tenants AND Free tenants on active trial both get backups (trial = Pro features)
      const tenants = masterDb.prepare(`
        SELECT id, slug, plan, trial_ends_at FROM tenants
        WHERE status = 'active' AND (
          plan = 'pro'
          OR (trial_ends_at IS NOT NULL AND trial_ends_at > datetime('now'))
        )
      `).all() as Array<{ id: number; slug: string; plan: string; trial_ends_at: string | null }>;

      console.log(`[Backup] Running per-tenant backups for ${tenants.length} Pro tenant(s)`);

      for (const t of tenants) {
        try {
          const tenantDb = getTenantDb(t.slug);
          if (!tenantDb) continue;
          const result = await runBackup(tenantDb, { tenantSlug: t.slug, tenantId: t.id });
          if (result.success) {
            console.log(`[Backup] Tenant ${t.slug}: ${result.message}`);
          } else {
            console.warn(`[Backup] Tenant ${t.slug} failed: ${result.message}`);
          }
        } catch (err) {
          console.error(`[Backup] Tenant ${t.slug} crashed:`, (err as Error).message);
        }
      }
    } catch (err) {
      console.error('[Backup] Multi-tenant backup cron crashed:', (err as Error).message);
    }
  });

  console.log('[Backup] Multi-tenant per-tenant backup cron scheduled (3:07 AM daily, Pro+trial only)');
}
