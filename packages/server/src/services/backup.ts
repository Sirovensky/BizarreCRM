import { config } from '../config.js';
import { logger } from '../utils/logger.js';
import crypto from 'crypto';
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import { execFile as execFileCallback, spawnSync } from 'child_process';
import { promisify } from 'util';

const execFile = promisify(execFileCallback);

// D3-1: Reject any shell metacharacters before a path is passed anywhere near
// child_process. Belt-and-suspenders: even though execFile / spawnSync are
// called with shell:false, a compromised admin or SQLi cannot stuff
// "; rm -rf /" into backup_path config and have it evaluated.
function assertSafePath(p: string): void {
  if (typeof p !== 'string' || p.length === 0 || p.length > 4096) {
    throw new Error('Invalid path');
  }
  // eslint-disable-next-line no-control-regex
  if (/[;&|`$\n\r\t\x00<>*?"']/.test(p)) {
    throw new Error('Path contains disallowed characters');
  }
}
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

// ─── SEC-H60: HMAC-signed backup metadata sidecar ──────────────────────────
// On backup write we emit a `<name>.db.enc.meta.json` sidecar containing the
// tenant slug, tenant_id, backup version, written_at timestamp, and an HMAC
// computed over those fields. On restore we recompute the HMAC and reject
// any file where it doesn't match OR where slug / tenant_id don't match the
// target tenant. This closes the "swap tenant A's backup into tenant B's
// slot" attack — the HMAC binds the ciphertext to its intended tenant.
const METADATA_VERSION = 1 as const;
const METADATA_SUFFIX = '.meta.json';
const SIDECAR_HMAC_ALGO = 'sha256' as const;

interface BackupMetadata {
  readonly slug: string;
  readonly tenant_id: number;
  readonly backup_version: number;
  readonly written_at: string; // ISO-8601
  readonly hmac: string; // hex-encoded HMAC-SHA256
}

/** Lazy-derived sidecar HMAC key. Computed once per process. */
let cachedSidecarKey: Buffer | null = null;

function getSidecarKey(): Buffer {
  if (cachedSidecarKey !== null) return cachedSidecarKey;
  const raw = config.backupMetadataKey;
  if (raw && raw.length >= 32) {
    // Use the raw env-var value directly as IKM for HKDF-expand so we get a
    // uniform 32-byte key regardless of hex / base64 / utf-8 encoding of the
    // env var. salt + info give domain separation.
    const derived = crypto.hkdfSync(
      'sha256',
      Buffer.from(raw),
      Buffer.from('bizarre-backup-meta-salt-v1'),
      Buffer.from('backup-metadata-hmac-v1'),
      32,
    );
    cachedSidecarKey = Buffer.from(derived);
    return cachedSidecarKey;
  }
  // No dedicated key — derive via HKDF over the other backup-relevant
  // secrets. Rotating JWT_SECRET or BACKUP_ENCRYPTION_KEY will invalidate
  // existing sidecars and force restores onto the --allow-unsigned path.
  // SEC-H103: use config.backupEncryptionKey (already normalised/derived).
  const ikmParts: string[] = [config.jwtSecret, config.backupEncryptionKey];
  const derived = crypto.hkdfSync(
    'sha256',
    Buffer.from(ikmParts.join('|')),
    Buffer.from('bizarre-backup-meta-salt-v1'),
    Buffer.from('backup-metadata-hmac-v1-fallback'),
    32,
  );
  cachedSidecarKey = Buffer.from(derived);
  return cachedSidecarKey;
}

/** Canonical string that the sidecar HMAC covers. Do NOT change the order or
 *  separator without bumping METADATA_VERSION — the HMAC would cease to match. */
function canonicalSidecarInput(
  slug: string,
  tenantId: number,
  backupVersion: number,
  writtenAt: string,
): string {
  return `${slug}|${tenantId}|${backupVersion}|${writtenAt}`;
}

function computeSidecarHmac(
  slug: string,
  tenantId: number,
  backupVersion: number,
  writtenAt: string,
): string {
  const h = crypto.createHmac(SIDECAR_HMAC_ALGO, getSidecarKey());
  h.update(canonicalSidecarInput(slug, tenantId, backupVersion, writtenAt));
  return h.digest('hex');
}

function sidecarPathFor(encPath: string): string {
  return encPath + METADATA_SUFFIX;
}

async function writeBackupMetadata(
  encPath: string,
  slug: string,
  tenantId: number,
): Promise<BackupMetadata> {
  const writtenAt = new Date().toISOString();
  const hmac = computeSidecarHmac(slug, tenantId, METADATA_VERSION, writtenAt);
  const meta: BackupMetadata = {
    slug,
    tenant_id: tenantId,
    backup_version: METADATA_VERSION,
    written_at: writtenAt,
    hmac,
  };
  await fsp.writeFile(sidecarPathFor(encPath), JSON.stringify(meta, null, 2), 'utf8');
  return meta;
}

interface VerifyResult {
  readonly ok: boolean;
  readonly reason?: string;
  readonly meta?: BackupMetadata;
  readonly unsigned?: boolean; // true when no sidecar exists at all
}

/** Read + verify a backup sidecar. Returns ok:false with a reason on any
 *  integrity failure (missing file counts as unsigned, NOT as invalid). */
async function verifyBackupMetadata(
  encPath: string,
  expectedSlug: string,
  expectedTenantId: number,
): Promise<VerifyResult> {
  const sidecar = sidecarPathFor(encPath);
  let raw: string;
  try {
    raw = await fsp.readFile(sidecar, 'utf8');
  } catch (err) {
    // ENOENT = legacy unsigned backup. Any other error (permission, IO) we
    // treat as a hard failure — corrupt meta that exists but can't be read
    // should NOT downgrade to the unsigned path.
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
      return { ok: false, unsigned: true, reason: 'Sidecar does not exist (legacy backup)' };
    }
    return { ok: false, reason: `Failed to read sidecar: ${err instanceof Error ? err.message : String(err)}` };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    return { ok: false, reason: `Sidecar JSON malformed: ${err instanceof Error ? err.message : String(err)}` };
  }

  if (!parsed || typeof parsed !== 'object') {
    return { ok: false, reason: 'Sidecar is not an object' };
  }
  const m = parsed as Record<string, unknown>;
  const slug = typeof m.slug === 'string' ? m.slug : null;
  const tenantId = typeof m.tenant_id === 'number' ? m.tenant_id : null;
  const backupVersion = typeof m.backup_version === 'number' ? m.backup_version : null;
  const writtenAt = typeof m.written_at === 'string' ? m.written_at : null;
  const hmacHex = typeof m.hmac === 'string' ? m.hmac : null;
  if (!slug || tenantId === null || backupVersion === null || !writtenAt || !hmacHex) {
    return { ok: false, reason: 'Sidecar is missing required fields' };
  }
  if (backupVersion !== METADATA_VERSION) {
    return { ok: false, reason: `Unsupported sidecar version ${backupVersion}` };
  }

  // Recompute HMAC and timing-safe compare.
  const expectedHex = computeSidecarHmac(slug, tenantId, backupVersion, writtenAt);
  const providedBuf = Buffer.from(hmacHex, 'hex');
  const expectedBuf = Buffer.from(expectedHex, 'hex');
  if (providedBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(providedBuf, expectedBuf)) {
    return { ok: false, reason: 'Sidecar HMAC mismatch — file may have been tampered with' };
  }

  // Now bind to the caller's target tenant — this is the attack we're
  // actually preventing.
  if (slug !== expectedSlug) {
    return {
      ok: false,
      reason: `Sidecar slug "${slug}" does not match target tenant "${expectedSlug}"`,
      meta: { slug, tenant_id: tenantId, backup_version: backupVersion, written_at: writtenAt, hmac: hmacHex },
    };
  }
  if (tenantId !== expectedTenantId) {
    return {
      ok: false,
      reason: `Sidecar tenant_id ${tenantId} does not match target tenant_id ${expectedTenantId}`,
      meta: { slug, tenant_id: tenantId, backup_version: backupVersion, written_at: writtenAt, hmac: hmacHex },
    };
  }

  return {
    ok: true,
    meta: { slug, tenant_id: tenantId, backup_version: backupVersion, written_at: writtenAt, hmac: hmacHex },
  };
}

/** Extract the leading slug from a backup filename. Filenames look like:
 *   `<slug>-t<tenantId>-<timestamp>-<rand>.db[.enc]`
 *   `bizarre-crm-<timestamp>-<rand>.db[.enc]` (single-tenant)
 *  Returns null when the filename doesn't match a known pattern. */
export function extractSlugFromBackupFilename(filename: string): string | null {
  if (!isBackupFile(filename)) return null;
  if (filename.startsWith('bizarre-crm-')) {
    return 'bizarre-crm';
  }
  // Match `<slug>-t<digits>-<ISO-ish timestamp>`
  const m = filename.match(/^(.+?)-t\d+-\d{4}-\d{2}/);
  return m ? m[1] : null;
}

// @audit-fixed: #15 — emit the JWT_SECRET fallback warning ONCE per process,
// not on every encrypt/decrypt call. Previously the warning fired on every
// backup run which spammed logs without adding information.
let fallbackWarned = false;

/** Get the passphrase for a given key version. v0 = legacy (jwtSecret only). */
function getPassphrase(version: number): string {
  if (version === 0) {
    // v0 legacy: encrypted with raw jwtSecret (pre-BACKUP_ENCRYPTION_KEY era).
    return config.jwtSecret;
  }
  // v1+: SEC-H103: use config.backupEncryptionKey, which is either the
  // explicit BACKUP_ENCRYPTION_KEY env var (validated/prod-fatal in config.ts)
  // or a stable HKDF derivation from JWT_SECRET (dev only). The config-level
  // prod-fatal check means we never reach this point in production without a
  // real key — the earlier guard in config.ts already exited. The check below
  // is belt-and-suspenders for any future code path that bypasses config.ts.
  const backupKey = config.backupEncryptionKey;
  if (backupKey && backupKey.length >= 16) {
    if (!fallbackWarned && !process.env.BACKUP_ENCRYPTION_KEY) {
      logger.warn(
        '[SEC-H103] BACKUP_ENCRYPTION_KEY not set — using HKDF-derived key. ' +
        'Set BACKUP_ENCRYPTION_KEY in .env to a dedicated 64-byte hex string.',
        { module: 'backup' },
      );
      fallbackWarned = true;
    }
    return backupKey;
  }
  // Unreachable in normal operation (config.ts always populates backupEncryptionKey),
  // but provide a safe fallback to prevent silent data loss.
  if (config.nodeEnv === 'production') {
    throw new Error(
      '[SEC-H103] BACKUP_ENCRYPTION_KEY is required in production. Set it in .env to a dedicated 64-byte hex string.',
    );
  }
  if (!fallbackWarned) {
    logger.warn(
      '[SEC-H103] Backup key derivation failed — falling back to JWT_SECRET. ' +
      'Set BACKUP_ENCRYPTION_KEY in .env.',
      { module: 'backup' },
    );
    fallbackWarned = true;
  }
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

function getConfig(db: Database.Database, key: string, fallback = ''): string {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as AnyRow | undefined;
  return row?.value ?? fallback;
}

function setConfig(db: Database.Database, key: string, value: string): void {
  db.prepare('INSERT INTO store_config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?').run(key, value, value);
}

export function getBackupSettings(db: Database.Database) {
  return {
    path: getConfig(db, 'backup_path', ''),
    schedule: getConfig(db, 'backup_schedule', '0 3 * * *'), // default 3 AM daily
    retention: parseInt(getConfig(db, 'backup_retention', '30'), 10),
    encrypt: getConfig(db, 'backup_encrypt', '') === 'true',
    lastBackup: getConfig(db, 'backup_last_run', ''),
    lastStatus: getConfig(db, 'backup_last_status', ''),
  };
}

export function updateBackupSettings(db: Database.Database, settings: { path?: string; schedule?: string; retention?: number; encrypt?: boolean }) {
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

/**
 * Recursively sum file sizes under `dir`. Returns bytes. Silent on
 * individual stat/read failures so a transient permission blip on one
 * file doesn't abort the whole pre-check — the caller falls back to
 * dbSize-only guard in that case which is strictly safer than skipping.
 */
function getDirectorySize(dir: string): number {
  let total = 0;
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return 0;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    try {
      if (entry.isDirectory()) {
        total += getDirectorySize(full);
      } else if (entry.isFile()) {
        total += fs.statSync(full).size;
      }
    } catch {
      // skip unreadable entry
    }
  }
  return total;
}

/**
 * Check free disk space at `dir`. Returns free bytes, or -1 if unknown.
 *
 * SEC-H76 / REL-007: Previously used spawnSync which blocked the Node.js
 * event loop for up to 5 s on every backup pre-check. Now uses promisified
 * execFile (no shell, 5 s timeout, 16 KiB maxBuffer).
 *
 * Fail-closed policy: any timeout, non-zero exit, or parse failure returns -1
 * so the caller treats the result as "unknown" and allows the backup to
 * proceed (the existing caller already treats free >= 0 && free < needed as
 * the blocking condition, so -1 skips the block — which is the intended
 * conservative behaviour for an unreachable OS command).
 */
async function getFreeDiskSpace(dir: string): Promise<number> {
  // Node 18.15+ exposes fs.statfsSync. Use it synchronously — it is a single
  // kernel stat(2) call with negligible latency, not an external process.
  try {
    const statfsFn = (fs as any).statfsSync;
    if (typeof statfsFn === 'function') {
      const stats = statfsFn(dir);
      return Number(stats.bavail) * Number(stats.bsize);
    }
  } catch {
    // fall through to async child_process path
  }

  // SEC-H76: async execFile path — no shell, args are hard-coded literals
  // (drive letter is validated by regex before interpolation; dir is passed
  // as a positional argv element, never shell-expanded).
  const EXEC_OPTS = { timeout: 5_000, maxBuffer: 1024 * 16 } as const;
  try {
    assertSafePath(dir);

    if (process.platform === 'win32') {
      const driveLetter = path.parse(path.resolve(dir)).root.replace(/\\/g, '').replace(':', '');
      // D3-1: reject non-alpha drive letters before any interpolation so the
      // single-quoted PowerShell argument cannot escape its quotes.
      if (!/^[A-Za-z]$/.test(driveLetter)) {
        logger.warn('getFreeDiskSpace: unexpected drive letter, returning pessimistic -1', {
          module: 'backup', driveLetter,
        });
        return -1;
      }
      // All args are literals or the single validated alpha char — no injection surface.
      const { stdout } = await execFile(
        'powershell',
        ['-NoProfile', '-Command', `(Get-PSDrive -Name '${driveLetter}').Free`],
        EXEC_OPTS,
      );
      return parseInt((stdout || '').trim(), 10) || -1;
    } else {
      // dir is passed as a positional argv element — never shell-interpreted.
      const { stdout } = await execFile(
        'df',
        ['-B1', '--output=avail', dir],
        EXEC_OPTS,
      );
      // Last non-empty line is the available-bytes value (skip header).
      const lines = (stdout || '').split('\n').map((l: string) => l.trim()).filter(Boolean);
      const last = lines[lines.length - 1];
      return parseInt(last, 10) || -1;
    }
  } catch (err) {
    // Timeout, ENOENT (command not found), or parse failure — fail closed.
    logger.warn('getFreeDiskSpace: OS command failed, returning pessimistic -1', {
      module: 'backup',
      error: err instanceof Error ? err.message : String(err),
    });
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
  db: Database.Database,
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

    // Disk-space pre-check (B6 + SEC-L19): require >= 2x (DB size +
    // uploads size) free. Prior version only accounted for DB size, which
    // meant a shop with a big uploads folder (photos / attachments) could
    // pass the check, start the DB backup, and then blow out the disk
    // during `fsp.cp(config.uploadsPath, ...)` — leaving half a backup
    // and a full disk behind. Now we measure both up-front.
    // Falls back to allowing the write if stats are unavailable.
    try {
      const sourceDbPath = db.name as string | undefined;
      if (sourceDbPath && fs.existsSync(sourceDbPath)) {
        const dbSize = fs.statSync(sourceDbPath).size;
        let uploadsSize = 0;
        try {
          if (fs.existsSync(config.uploadsPath)) {
            uploadsSize = getDirectorySize(config.uploadsPath);
          }
        } catch {
          // best-effort; if uploads sizing fails we fall back to dbSize-only
          // which is strictly safer than skipping the check entirely.
          uploadsSize = 0;
        }
        const neededBytes = (dbSize + uploadsSize) * 2;
        const free = await getFreeDiskSpace(backupDir);
        if (free >= 0 && free < neededBytes) {
          return {
            success: false,
            message: `Insufficient disk space: need ${(neededBytes / 1e6).toFixed(1)}MB (DB ${(dbSize / 1e6).toFixed(1)}MB + uploads ${(uploadsSize / 1e6).toFixed(1)}MB, ×2 safety margin), have ${(free / 1e6).toFixed(1)}MB free`,
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
    // SCAN-574: defence-in-depth — validate slug even though it's regex-checked upstream.
    const rawSlug = opts?.tenantSlug;
    const safeSlug = rawSlug && /^[a-z0-9-]+$/.test(rawSlug) ? rawSlug : 'tenant';
    const prefix = opts?.tenantSlug
      ? `${safeSlug}-t${opts.tenantId ?? 0}`
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

    // Optional AES-256-GCM encryption of the database backup.
    // PROD55: in production, encryption is MANDATORY — plaintext `.db`
    // must never land on disk under backup_path. `shouldEncrypt` is
    // forced to true regardless of the admin opt-out. Dev / self-hosted
    // test installs still honour the opt-in flag so engineers can
    // eyeball a dev DB without re-running the decrypt.
    const rawEncryptOpt = opts?.encrypt ?? getConfig(db, 'backup_encrypt', '') === 'true';
    const shouldEncrypt = config.nodeEnv === 'production' ? true : rawEncryptOpt;
    let finalDbPath = dbDest;
    if (shouldEncrypt) {
      finalDbPath = await encryptFile(dbDest);
      logger.info('Backup encrypted', { module: 'backup', file: finalDbPath });
    }

    // SEC-H60: write the HMAC-signed metadata sidecar beside the final file.
    // We derive a stable (slug, tenant_id) pair — single-tenant installs use
    // `bizarre-crm` / `0` so the verification code has a consistent contract.
    try {
      const metaSlug = opts?.tenantSlug || 'bizarre-crm';
      const metaTenantId = opts?.tenantId ?? 0;
      await writeBackupMetadata(finalDbPath, metaSlug, metaTenantId);
      logger.info('Backup metadata sidecar written', {
        module: 'backup',
        slug: metaSlug,
        tenantId: metaTenantId,
        file: path.basename(finalDbPath),
      });
    } catch (err) {
      // Sidecar write failed — don't fail the whole backup (the ciphertext
      // is already on disk and is usable via --allow-unsigned), but log
      // loud so operators notice. A later restore will refuse this file
      // unless explicitly opted into with the unsigned flag.
      logger.error('Backup sidecar write failed — backup exists but is unsigned', {
        module: 'backup',
        file: path.basename(finalDbPath),
        error: err instanceof Error ? err.message : String(err),
      });
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
    // SEC-H60: also remove the signed-metadata sidecar alongside the file.
    // Leaving orphan sidecars behind would gradually accumulate in the
    // backup dir and could masquerade as integrity evidence for a non-
    // existent backup.
    try { fs.unlinkSync(dbFile + METADATA_SUFFIX); } catch {}
  }
}

export function listBackups(db: Database.Database): { name: string; size: number; date: string }[] {
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

export function deleteBackup(db: Database.Database, filename: string): boolean {
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
  // SEC-H60: drop the HMAC sidecar alongside the backup file.
  try { fs.unlinkSync(dbFile + METADATA_SUFFIX); } catch {}
  return true;
}

/**
 * Resolve a backup filename to an absolute path, enforcing that it stays
 * inside the configured backup directory. Returns null on any violation.
 */
export function resolveBackupPath(db: Database.Database, filename: string): string | null {
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
export interface RestoreBackupOptions {
  readonly targetDbPath: string;
  readonly onBeforeReplace?: () => void; // hook to close live DB handles before the file swap
  // SEC-H60: tenant identity the restore is being applied to. Required so
  // the sidecar HMAC/slug/tenant_id binding can be verified against the real
  // destination. In single-tenant mode pass `{slug: 'bizarre-crm', tenantId: 0}`
  // — runBackup emits sidecars with those stable placeholders.
  readonly expectedSlug: string;
  readonly expectedTenantId: number;
  // When true, a missing sidecar is permitted (old backup from before
  // SEC-H60 landed). Verified sidecars that FAIL verification still reject
  // regardless of this flag — `allowUnsigned` only waives the "no sidecar
  // at all" case. Defaults to false so callers must explicitly opt in.
  readonly allowUnsigned?: boolean;
}

export async function restoreBackup(
  db: Database.Database,
  filename: string,
  opts: RestoreBackupOptions,
): Promise<{ success: boolean; message: string; safetyBackup?: string; hash?: string; unsigned?: boolean }> {
  const backupFile = resolveBackupPath(db, filename);
  if (!backupFile) {
    return { success: false, message: 'Backup file not found or invalid filename' };
  }

  // SEC-H60: verify the filename's leading slug matches the target BEFORE we
  // even decrypt — cheap sanity check that catches the common "operator
  // picked the wrong file" case without touching crypto.
  const filenameSlug = extractSlugFromBackupFilename(filename);
  if (filenameSlug !== null && filenameSlug !== opts.expectedSlug) {
    return {
      success: false,
      message: `Backup filename slug "${filenameSlug}" does not match target tenant "${opts.expectedSlug}"`,
    };
  }

  // SEC-H60: read + verify the HMAC-signed sidecar. Reject on tampering,
  // reject on cross-tenant swap, accept only `unsigned` cases when the
  // caller explicitly opted in.
  const verify = await verifyBackupMetadata(backupFile, opts.expectedSlug, opts.expectedTenantId);
  if (!verify.ok) {
    if (verify.unsigned) {
      if (!opts.allowUnsigned) {
        logger.warn('Backup restore refused — sidecar missing, --allow-unsigned not set', {
          module: 'backup',
          file: path.basename(backupFile),
          expectedSlug: opts.expectedSlug,
        });
        return {
          success: false,
          message: 'Backup has no signed metadata sidecar (pre-SEC-H60 backup). Retry with allow_unsigned=true if you trust the source.',
          unsigned: true,
        };
      }
      logger.warn('Restoring unsigned backup — operator explicitly opted in', {
        module: 'backup',
        file: path.basename(backupFile),
        expectedSlug: opts.expectedSlug,
      });
    } else {
      logger.error('Backup sidecar verification failed — REFUSING restore', {
        module: 'backup',
        file: path.basename(backupFile),
        reason: verify.reason,
        metaSlug: verify.meta?.slug,
        metaTenantId: verify.meta?.tenant_id,
        expectedSlug: opts.expectedSlug,
        expectedTenantId: opts.expectedTenantId,
      });
      return { success: false, message: `Sidecar verification failed: ${verify.reason}` };
    }
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
      unsigned: Boolean(verify.unsigned),
      expectedSlug: opts.expectedSlug,
      expectedTenantId: opts.expectedTenantId,
    });

    return { success: true, message: 'Restore completed', safetyBackup, hash, unsigned: Boolean(verify.unsigned) };
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
      // D3-1: spawnSync (shell:false) — fixed command, no user input.
      const res = spawnSync(
        'powershell',
        ['-NoProfile', '-Command', 'Get-PSDrive -PSProvider FileSystem | Select-Object Name,Free,Used,Root | ConvertTo-Csv -NoTypeInformation'],
        { encoding: 'utf8', timeout: 10000, shell: false },
      );
      const out = res.status === 0 ? (res.stdout || '') : '';
      return out.split('\n').slice(1).filter((l: string) => l.trim()).map((line: string) => {
        const cols = line.replace(/"/g, '').split(',');
        if (cols.length < 4 || !cols[0]) return null;
        const [name, free, used, root] = cols;
        const freeBytes = parseInt(free) || 0;
        const usedBytes = parseInt(used) || 0;
        return { path: root.trim(), label: name.trim() + ':', free: freeBytes, total: freeBytes + usedBytes };
      }).filter(Boolean) as any[];
    } else {
      // D3-1: spawnSync (shell:false) — fixed argv, no user input.
      const res = spawnSync('df', ['-B1', '--output=target,avail,size'], { encoding: 'utf8', timeout: 5000, shell: false });
      const raw = res.status === 0 ? (res.stdout || '') : '';
      // Drop header row manually (we removed the shell pipe to tail).
      const out = raw.split('\n').slice(1).join('\n');
      return out.split('\n').filter((l: string) => l.trim()).map((line: string) => {
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

/**
 * Schedule the main-DB backup cron.
 *
 * Accepts either a `Database.Database` handle for backwards compatibility or
 * a `getDb: () => Database.Database` factory. SCAN-1055: the old signature
 * captured the handle at registration time, so after a restore/reconnect the
 * cron kept writing against a stale (possibly closed) connection. Pass a
 * factory for robust long-running processes.
 */
export function scheduleBackup(dbOrFactory: Database.Database | (() => Database.Database)) {
  const getDb: () => Database.Database =
    typeof dbOrFactory === 'function' ? dbOrFactory : () => dbOrFactory;
  if (cronTask) { cronTask.stop(); cronTask = null; }
  const initialDb = getDb();
  const schedule = getConfig(initialDb, 'backup_schedule', '0 3 * * *');
  const backupPath = getConfig(initialDb, 'backup_path', '');
  if (!backupPath || !cron.validate(schedule)) return;

  // BG5 fix: wrap the async call so errors are caught and logged instead of swallowed.
  cronTask = cron.schedule(schedule, () => {
    (async () => {
      try {
        // Resolve the handle on every tick so a restore/reopen picks up cleanly.
        const result = await runBackup(getDb());
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
  releaseTenantDb: (slug: string) => void,
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
        let tenantDb: any;
        try {
          tenantDb = await getTenantDb(t.slug);
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
        } finally {
          if (tenantDb !== undefined) releaseTenantDb(t.slug);
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
