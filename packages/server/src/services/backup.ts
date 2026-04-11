import { config } from '../config.js';
import { logger } from '../utils/logger.js';
import crypto from 'crypto';
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import { execSync } from 'child_process';
import cron from 'node-cron';
import Database from 'better-sqlite3';

// ─── AES-256-GCM backup encryption ─────────────────────────────────
// File format (v1 — current):
//   [4-byte magic "BZBK"][1-byte version=1][16-byte salt][12-byte IV][16-byte auth tag][ciphertext]
// Legacy format (v0 — backwards compat for files without the magic header):
//   [16-byte salt][12-byte IV][16-byte auth tag][ciphertext]
//
// Key derivation:
//   v1: PBKDF2(BACKUP_ENCRYPTION_KEY || fallback-jwtSecret, salt, 100k iters, SHA-512, 32 bytes)
//   v0: PBKDF2(jwtSecret, salt, 100k iters, SHA-512, 32 bytes)
//
// Adding a dedicated BACKUP_ENCRYPTION_KEY env var decouples backups from
// JWT secret rotation. Rotating JWT_SECRET no longer bricks old backups.

const ENCRYPTION_ALGO = 'aes-256-gcm' as const;
const BACKUP_MAGIC = Buffer.from('BZBK', 'ascii'); // 4 bytes
const CURRENT_KEY_VERSION = 1;
const MAGIC_LEN = 4;
const VERSION_LEN = 1;
const HEADER_LEN = MAGIC_LEN + VERSION_LEN;
const SALT_LEN = 16;
const IV_LEN = 12;
const AUTH_TAG_LEN = 16;
const KEY_LEN = 32;
const PBKDF2_ITERATIONS = 100_000;

/** Get the passphrase for a given key version. v0 = legacy (jwtSecret only). */
function getPassphrase(version: number): string {
  if (version === 0) {
    return config.jwtSecret;
  }
  // v1+: prefer BACKUP_ENCRYPTION_KEY, fall back to jwtSecret with a warning
  const backupKey = process.env.BACKUP_ENCRYPTION_KEY;
  if (backupKey && backupKey.length >= 16) {
    return backupKey;
  }
  logger.warn(
    'BACKUP_ENCRYPTION_KEY not set — falling back to JWT_SECRET. ' +
    'Rotating JWT_SECRET will brick these backups. ' +
    'Set BACKUP_ENCRYPTION_KEY in .env to a dedicated 64-byte hex string.',
    { module: 'backup' },
  );
  return config.jwtSecret;
}

function deriveKey(salt: Buffer, version: number): Buffer {
  const passphrase = getPassphrase(version);
  return crypto.pbkdf2Sync(passphrase, salt, PBKDF2_ITERATIONS, KEY_LEN, 'sha512');
}

export async function encryptFile(inputPath: string): Promise<string> {
  const outputPath = inputPath + '.enc';
  const plaintext = await fsp.readFile(inputPath);

  const salt = crypto.randomBytes(SALT_LEN);
  const iv = crypto.randomBytes(IV_LEN);
  const key = deriveKey(salt, CURRENT_KEY_VERSION);

  const cipher = crypto.createCipheriv(ENCRYPTION_ALGO, key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const authTag = cipher.getAuthTag();

  // v1 format: magic | version | salt | iv | authTag | ciphertext
  const versionByte = Buffer.from([CURRENT_KEY_VERSION]);
  await fsp.writeFile(
    outputPath,
    Buffer.concat([BACKUP_MAGIC, versionByte, salt, iv, authTag, encrypted]),
  );

  // Remove the unencrypted original
  await fsp.unlink(inputPath);

  return outputPath;
}

/** Detect the backup file format version. Returns { version, dataOffset }. */
function detectFormat(data: Buffer): { version: number; dataOffset: number } {
  if (data.length >= HEADER_LEN && data.subarray(0, MAGIC_LEN).equals(BACKUP_MAGIC)) {
    const version = data[MAGIC_LEN];
    return { version, dataOffset: HEADER_LEN };
  }
  // No magic — legacy v0 format
  return { version: 0, dataOffset: 0 };
}

export async function decryptFile(encPath: string, outputPath: string): Promise<void> {
  const data = await fsp.readFile(encPath);
  const { version, dataOffset } = detectFormat(data);

  if (version > CURRENT_KEY_VERSION) {
    throw new Error(`Unsupported backup version ${version}. Upgrade the server to read this backup.`);
  }

  const salt = data.subarray(dataOffset, dataOffset + SALT_LEN);
  const iv = data.subarray(dataOffset + SALT_LEN, dataOffset + SALT_LEN + IV_LEN);
  const authTag = data.subarray(
    dataOffset + SALT_LEN + IV_LEN,
    dataOffset + SALT_LEN + IV_LEN + AUTH_TAG_LEN,
  );
  const ciphertext = data.subarray(dataOffset + SALT_LEN + IV_LEN + AUTH_TAG_LEN);

  const key = deriveKey(salt, version);
  const decipher = crypto.createDecipheriv(ENCRYPTION_ALGO, key, iv);
  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  await fsp.writeFile(outputPath, decrypted);
}

/**
 * Migrate a legacy v0 backup to v1 format. Reads the v0 file (decrypted with
 * jwtSecret), re-encrypts with the current key version. Used for key migration.
 */
export async function migrateBackupToV1(encPath: string): Promise<void> {
  const tempPlain = encPath + '.migrating.tmp';
  try {
    await decryptFile(encPath, tempPlain);
    // Back up the original in case migration fails
    await fsp.rename(encPath, encPath + '.v0.bak');
    await encryptFile(tempPlain); // writes tempPlain + '.enc', removes tempPlain
    await fsp.rename(tempPlain + '.enc', encPath);
    await fsp.unlink(encPath + '.v0.bak');
    logger.info('Backup migrated to v1', { file: path.basename(encPath) });
  } catch (err) {
    // Clean up temp file; leave .v0.bak in place for recovery
    try { await fsp.unlink(tempPlain); } catch {}
    throw err;
  }
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

// ─── Per-tenant backup mutex ────────────────────────────────────────
// Replaces the single global `backupRunning` flag. Each tenant gets its
// own lock so cron + manual backups across tenants don't block each other.
// Key: tenant slug (or "__single__" for single-tenant mode).
const tenantBackupLocks = new Map<string, boolean>();
const SINGLE_TENANT_LOCK_KEY = '__single__';

export function isTenantBackupRunning(tenantSlug?: string): boolean {
  return tenantBackupLocks.get(tenantSlug || SINGLE_TENANT_LOCK_KEY) === true;
}

export function acquireTenantBackupLock(tenantSlug?: string): boolean {
  const key = tenantSlug || SINGLE_TENANT_LOCK_KEY;
  if (tenantBackupLocks.get(key)) return false;
  tenantBackupLocks.set(key, true);
  return true;
}

export function releaseTenantBackupLock(tenantSlug?: string): void {
  tenantBackupLocks.delete(tenantSlug || SINGLE_TENANT_LOCK_KEY);
}

/** Check free disk space at `dir`. Returns free bytes, or -1 if unknown. */
function getFreeDiskSpace(dir: string): number {
  try {
    // Node 18.15+ exposes fs.statfsSync. Fall back to platform commands.
    const statfsFn = (fs as any).statfsSync;
    if (typeof statfsFn === 'function') {
      const stats = statfsFn(dir);
      return Number(stats.bavail) * Number(stats.bsize);
    }
  } catch {
    // fall through
  }
  try {
    if (process.platform === 'win32') {
      const driveLetter = path.parse(path.resolve(dir)).root.replace(/\\/g, '');
      const out = execSync(
        `powershell -Command "(Get-PSDrive -Name '${driveLetter.replace(':', '')}').Free"`,
        { encoding: 'utf8', timeout: 5000 },
      );
      return parseInt(out.trim(), 10) || -1;
    } else {
      const out = execSync(`df -B1 --output=avail "${dir}" | tail -n 1`, { encoding: 'utf8', timeout: 5000 });
      return parseInt(out.trim(), 10) || -1;
    }
  } catch {
    return -1;
  }
}

/** Run PRAGMA integrity_check on a SQLite file. Returns ok=true iff result is "ok". */
function runIntegrityCheck(dbPath: string): { ok: boolean; message: string } {
  let verifyDb: Database.Database | null = null;
  try {
    verifyDb = new Database(dbPath, { readonly: true });
    const row = verifyDb.prepare('PRAGMA integrity_check').get() as { integrity_check?: string } | undefined;
    const result = row?.integrity_check || 'unknown';
    return { ok: result === 'ok', message: result };
  } catch (err) {
    return { ok: false, message: err instanceof Error ? err.message : 'integrity check threw' };
  } finally {
    try { verifyDb?.close(); } catch {}
  }
}

export async function runBackup(
  db: any,
  opts?: { tenantSlug?: string; tenantId?: number; encrypt?: boolean },
): Promise<{ success: boolean; message: string; file?: string }> {
  const lockKey = opts?.tenantSlug || SINGLE_TENANT_LOCK_KEY;
  if (!acquireTenantBackupLock(lockKey)) {
    return { success: false, message: `Backup already running for ${lockKey}` };
  }

  try {
    const backupDir = getConfig(db, 'backup_path', '');
    if (!backupDir) return { success: false, message: 'No backup path configured' };

    if (!fs.existsSync(backupDir)) {
      try { fs.mkdirSync(backupDir, { recursive: true }); }
      catch { return { success: false, message: `Cannot create backup directory: ${backupDir}` }; }
    }

    // Disk-space pre-check (B6): require >= 2x current DB size free.
    // Falls back to allowing the write if stats are unavailable.
    try {
      const sourceDbPath = db.name as string | undefined;
      if (sourceDbPath && fs.existsSync(sourceDbPath)) {
        const dbSize = fs.statSync(sourceDbPath).size;
        const free = getFreeDiskSpace(backupDir);
        if (free >= 0 && free < dbSize * 2) {
          return {
            success: false,
            message: `Insufficient disk space: need ${(dbSize * 2 / 1e6).toFixed(1)}MB, have ${(free / 1e6).toFixed(1)}MB free`,
          };
        }
      }
    } catch (err) {
      logger.warn('Disk space pre-check failed, proceeding anyway', {
        module: 'backup',
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // B7: millisecond-precision timestamp + random suffix so two wipes in the
    // same second don't collide. ISO format with ms: 2025-01-01T00-00-00-000Z
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    const rand = crypto.randomBytes(3).toString('hex'); // 6 hex chars
    const prefix = opts?.tenantSlug
      ? `${opts.tenantSlug}-t${opts.tenantId ?? 0}`
      : 'bizarre-crm';
    const dbDest = path.join(backupDir, `${prefix}-${ts}-${rand}.db`);
    const uploadsDest = path.join(backupDir, `uploads-${ts}-${rand}`);

    // Async SQLite backup (safe while DB is in use)
    await db.backup(dbDest);

    // B4: verify the backup with PRAGMA integrity_check. Delete and fail if corrupt.
    const integrity = runIntegrityCheck(dbDest);
    if (!integrity.ok) {
      try { await fsp.unlink(dbDest); } catch {}
      const msg = `Backup integrity check failed: ${integrity.message}`;
      setConfig(db, 'backup_last_status', `failed: ${msg}`);
      logger.error(msg, { module: 'backup', file: dbDest });
      return { success: false, message: msg };
    }

    // Copy uploads folder (async to avoid blocking the event loop)
    if (fs.existsSync(config.uploadsPath)) {
      await fsp.cp(config.uploadsPath, uploadsDest, { recursive: true });
    }

    // Optional AES-256-GCM encryption of the database backup
    const shouldEncrypt = opts?.encrypt ?? getConfig(db, 'backup_encrypt', '') === 'true';
    let finalDbPath = dbDest;
    if (shouldEncrypt) {
      finalDbPath = await encryptFile(dbDest);
      logger.info('Backup encrypted', { module: 'backup', file: finalDbPath });
    }

    // Prune old backups
    const retention = parseInt(getConfig(db, 'backup_retention', '30'), 10);
    pruneBackups(backupDir, retention);

    setConfig(db, 'backup_last_run', new Date().toISOString());
    setConfig(db, 'backup_last_status', 'success');

    logger.info('Backup completed', { module: 'backup', file: finalDbPath });
    return { success: true, message: 'Backup completed', file: finalDbPath };
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    try { setConfig(db, 'backup_last_status', `failed: ${msg}`); } catch {}
    logger.error('Backup failed', { module: 'backup', error: msg });
    return { success: false, message: msg };
  } finally {
    releaseTenantBackupLock(lockKey);
  }
}

/** Match legacy, tenant, and new ms-precision backup filenames (plain or encrypted) */
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
    // Derive uploads dir: match both second-precision (legacy) and ms-precision (new)
    const tsMatch = file.match(/(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:-\d{3}Z)?(?:-[a-f0-9]{6})?)/);
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
  // Derive uploads dir from the timestamp in the filename (supports both old and new formats)
  const tsMatch = filename.match(/(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:-\d{3}Z)?(?:-[a-f0-9]{6})?)/);
  const uploadsDir = tsMatch
    ? path.join(backupDir, `uploads-${tsMatch[1]}`)
    : path.join(backupDir, filename.replace('.db', '-uploads'));

  // Path traversal protection: verify resolved paths stay inside backupDir
  const resolvedBackupDir = path.resolve(backupDir);
  if (!path.resolve(dbFile).startsWith(resolvedBackupDir + path.sep) ||
      !path.resolve(uploadsDir).startsWith(resolvedBackupDir + path.sep)) {
    logger.error('Path traversal blocked', { module: 'backup', filename });
    return false;
  }

  try { fs.unlinkSync(dbFile); } catch {}
  try { fs.rmSync(uploadsDir, { recursive: true, force: true }); } catch {}
  return true;
}

/**
 * Resolve a backup filename to an absolute path, enforcing that it stays
 * inside the configured backup directory. Returns null on any violation.
 */
export function resolveBackupPath(db: any, filename: string): string | null {
  const backupDir = getConfig(db, 'backup_path', '');
  if (!backupDir || !isBackupFile(filename)) return null;
  if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) return null;

  const full = path.join(backupDir, filename);
  const resolvedDir = path.resolve(backupDir);
  if (!path.resolve(full).startsWith(resolvedDir + path.sep)) return null;
  if (!fs.existsSync(full)) return null;
  return full;
}

/**
 * Restore a backup file over the active DB. Steps:
 *   1. Resolve backup path (rejects traversal, rejects missing).
 *   2. Decrypt if .enc. Stage into a temp file.
 *   3. PRAGMA integrity_check on the staged file.
 *   4. Create a safety backup of the current DB.
 *   5. Close the live DB handle, replace the file, caller reopens.
 *   6. Return the sha-256 hash of the restored file.
 *
 * NOTE: Caller is responsible for reopening the DB pool/handle after this
 * function returns success. For single-tenant, the admin route closes the
 * request DB handle before calling. For tenant restore, the caller should
 * closeTenantDb(slug) first and let the pool re-open lazily.
 */
export async function restoreBackup(
  db: any,
  filename: string,
  opts: {
    targetDbPath: string;
    onBeforeReplace?: () => void; // hook to close live DB handles before the file swap
  },
): Promise<{ success: boolean; message: string; safetyBackup?: string; hash?: string }> {
  const backupFile = resolveBackupPath(db, filename);
  if (!backupFile) {
    return { success: false, message: 'Backup file not found or invalid filename' };
  }

  const tempPlain = path.join(
    path.dirname(opts.targetDbPath),
    `.restore-${crypto.randomBytes(6).toString('hex')}.tmp.db`,
  );

  try {
    // Step 2: decrypt or copy to temp
    if (backupFile.endsWith('.enc')) {
      await decryptFile(backupFile, tempPlain);
    } else {
      await fsp.copyFile(backupFile, tempPlain);
    }

    // Step 3: integrity check on the staged file
    const integrity = runIntegrityCheck(tempPlain);
    if (!integrity.ok) {
      try { await fsp.unlink(tempPlain); } catch {}
      return { success: false, message: `Restore integrity check failed: ${integrity.message}` };
    }

    // Step 4: safety backup of the current DB (timestamp + random suffix)
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    const rand = crypto.randomBytes(3).toString('hex');
    const safetyBackup = `${opts.targetDbPath}.pre-restore-${ts}-${rand}.bak`;
    if (fs.existsSync(opts.targetDbPath)) {
      await fsp.copyFile(opts.targetDbPath, safetyBackup);
    }

    // Step 5: close live handle, replace file
    try { opts.onBeforeReplace?.(); } catch (err) {
      logger.warn('onBeforeReplace hook threw, continuing anyway', {
        module: 'backup',
        error: err instanceof Error ? err.message : String(err),
      });
    }
    // Also clear WAL/SHM sidecar files so the next open starts clean
    for (const suffix of ['-wal', '-shm']) {
      const side = opts.targetDbPath + suffix;
      try { if (fs.existsSync(side)) await fsp.unlink(side); } catch {}
    }
    await fsp.rename(tempPlain, opts.targetDbPath);

    // Step 6: hash the restored file
    const fileBuf = await fsp.readFile(opts.targetDbPath);
    const hash = crypto.createHash('sha256').update(fileBuf).digest('hex');

    logger.info('Backup restored', {
      module: 'backup',
      filename,
      safetyBackup: path.basename(safetyBackup),
      hash,
    });

    return { success: true, message: 'Restore completed', safetyBackup, hash };
  } catch (err) {
    try { if (fs.existsSync(tempPlain)) await fsp.unlink(tempPlain); } catch {}
    const msg = err instanceof Error ? err.message : 'Unknown error';
    logger.error('Restore failed', { module: 'backup', error: msg });
    return { success: false, message: msg };
  }
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

  // BG5 fix: wrap the async call so errors are caught and logged instead of swallowed.
  cronTask = cron.schedule(schedule, () => {
    (async () => {
      try {
        const result = await runBackup(db);
        if (!result.success) {
          logger.error('Scheduled backup failed', { module: 'backup', message: result.message });
        }
      } catch (err) {
        logger.error('Scheduled backup threw', {
          module: 'backup',
          error: err instanceof Error ? err.message : String(err),
        });
      }
    })().catch((err) => {
      logger.error('Scheduled backup outer catch', {
        module: 'backup',
        error: err instanceof Error ? err.message : String(err),
      });
    });
  });
  logger.info('Backup scheduled', { module: 'backup', schedule, backupPath });
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

      logger.info('Running per-tenant backups', { module: 'backup', count: tenants.length });

      for (const t of tenants) {
        try {
          const tenantDb = getTenantDb(t.slug);
          if (!tenantDb) continue;
          const result = await runBackup(tenantDb, { tenantSlug: t.slug, tenantId: t.id });
          if (result.success) {
            logger.info('Tenant backup complete', { module: 'backup', tenant: t.slug, message: result.message });
          } else {
            logger.warn('Tenant backup failed', { module: 'backup', tenant: t.slug, message: result.message });
          }
        } catch (err) {
          logger.error('Tenant backup crashed', {
            module: 'backup',
            tenant: t.slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    } catch (err) {
      logger.error('Multi-tenant backup cron crashed', {
        module: 'backup',
        error: err instanceof Error ? err.message : String(err),
      });
    }
  });

  logger.info('Multi-tenant backup cron scheduled', {
    module: 'backup',
    schedule: '3:07 AM daily, Pro+trial only',
  });
}
