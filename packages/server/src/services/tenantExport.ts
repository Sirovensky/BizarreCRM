/**
 * tenantExport.ts — SEC-H59 / P3-PII-16
 *
 * Full tenant data export service. Produces an AES-256-GCM encrypted ZIP
 * archive containing NDJSON dumps of every exportable DB table plus a copy
 * of the tenant's uploaded files.
 *
 * Encryption scheme (recipient can decrypt with only the passphrase):
 *   Header = [16-byte salt][12-byte IV][16-byte GCM auth tag]
 *   Key    = scrypt(passphrase, salt, { N:32768, r:8, p:1, dkLen:32 })
 *   Body   = AES-256-GCM ciphertext of the raw ZIP bytes
 *   File   = Header || Body
 *
 * The salt and IV are prepended in plaintext so the recipient can re-derive
 * the key and initialise the cipher without any additional metadata file.
 * The GCM tag (stored at bytes 28–43) authenticates the entire ciphertext.
 *
 * Security properties:
 *   - Passphrase is NEVER stored (only held in memory during key derivation).
 *   - The derived key Buffer is zeroed immediately after the cipher is created.
 *   - Temp directory is cleaned up in a finally block regardless of errors.
 *   - All file paths written into the ZIP are validated against an allowlist
 *     base so neither DB table names nor upload filenames can cause zip-slip.
 *   - Rate limit: enforced via `tenant_exports` table (1 pending/running job
 *     per tenant at a time, plus 1-hour cooldown after last completed export).
 *
 * Worker strategy: runs in-process using setImmediate yields between table
 * dumps to avoid blocking the event loop (same pattern as SEC-M26). Piscina
 * worker off-load is future-scope once export volumes justify it.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import zlib from 'node:zlib';
import type { Database } from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('tenant-export');

// ─── Constants ────────────────────────────────────────────────────────────────

const SALT_LEN = 16;
const IV_LEN = 12;
const AUTH_TAG_LEN = 16;
const KEY_LEN = 32;
const SCRYPT_N = 32_768; // 2^15 — minimum per spec
const SCRYPT_R = 8;
const SCRYPT_P = 1;

/** Export files are removed from disk after this many days. */
export const EXPORT_RETENTION_DAYS = 7;

/** Download tokens expire after 1 hour. */
const TOKEN_EXPIRY_MS = 60 * 60 * 1000;

/** 1 export per tenant per hour (cooldown after last completed job). */
const RATE_LIMIT_MS = 60 * 60 * 1000;

/**
 * Tables that are never included in the tenant export.
 * Mirrors the exclusion list in dataExport.routes.ts and extends it with
 * the new `tenant_exports` table itself (tokens are transient auth material).
 */
const EXCLUDED_TABLES = new Set<string>([
  'sqlite_sequence',
  '_migrations',
  'sessions',
  'refresh_tokens',
  'password_history',
  'login_attempts',
  'rate_limits',
  'rate_limit_windows',
  'import_rate_limits',
  'api_key_revocations',
  'admin_tokens',
  'pending_2fa_challenges',
  'recovery_codes_used',
  'idempotency_keys',
  'tenant_exports', // contains download tokens — never exported
]);

/**
 * Per-table columns to redact (replaced with null in the NDJSON output).
 * The tenant owns their data, but we do not hand over password hashes or
 * TOTP secrets — those protect access to the system itself.
 */
const SENSITIVE_FIELDS: ReadonlyMap<string, ReadonlySet<string>> = new Map([
  ['users', new Set(['password_hash', 'totp_secret', 'pin_hash', 'recovery_codes', 'reset_token_hash', 'remember_token_hash'])],
]);

/** store_config keys whose `value` is redacted before export. */
const SENSITIVE_CONFIG_KEYS = new Set<string>([
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'smtp_pass', 'tcx_password', 'stripe_secret_key', 'twilio_auth_token',
]);

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ExportJobRecord {
  readonly id: number;
  readonly tenant_id: number;
  readonly requested_by_user_id: number;
  readonly status: 'pending' | 'running' | 'complete' | 'failed';
  readonly started_at: string;
  readonly completed_at: string | null;
  readonly file_path: string | null;
  readonly byte_size: number | null;
  readonly error_message: string | null;
  readonly download_token: string | null;
  readonly download_token_expires_at: string | null;
  readonly downloaded_at: string | null;
}

// ─── ZIP helpers (pure Node.js, no external lib) ─────────────────────────────
//
// Implements enough of the PKZIP format to produce a valid .zip readable by
// Info-ZIP, Python's zipfile module, macOS Archive Utility, and Windows 11.
//
// Format per PKZIP Application Note (APPNOTE.TXT):
//   For each file:
//     [Local file header][File data (deflate compressed)]
//   Followed by:
//     [Central directory entries]
//     [End of central directory record]

interface ZipEntry {
  readonly name: string;         // relative path inside ZIP (forward slashes)
  readonly data: Buffer;         // compressed data (deflate raw)
  readonly crc32: number;
  readonly uncompressedSize: number;
  readonly compressedSize: number;
  readonly localHeaderOffset: number;
  readonly dosDate: number;
  readonly dosTime: number;
}

function crc32(buf: Buffer): number {
  // Standard CRC-32 table (IEEE 802.3 polynomial 0xEDB88320)
  const table = crc32Table();
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ (table[(crc ^ buf[i]!) & 0xff])!;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

let _crc32Table: Uint32Array | null = null;
function crc32Table(): Uint32Array {
  if (_crc32Table) return _crc32Table;
  _crc32Table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    _crc32Table[i] = c;
  }
  return _crc32Table;
}

function dosDateTime(): { dosDate: number; dosTime: number } {
  const now = new Date();
  const dosDate =
    ((now.getFullYear() - 1980) << 9) |
    ((now.getMonth() + 1) << 5) |
    now.getDate();
  const dosTime =
    (now.getHours() << 11) |
    (now.getMinutes() << 5) |
    Math.floor(now.getSeconds() / 2);
  return { dosDate, dosTime };
}

function writeLocalHeader(entry: ZipEntry): Buffer {
  const nameBytes = Buffer.from(entry.name, 'utf8');
  const hdr = Buffer.alloc(30 + nameBytes.length);
  hdr.writeUInt32LE(0x04034b50, 0);  // signature
  hdr.writeUInt16LE(20, 4);           // version needed (2.0)
  hdr.writeUInt16LE(0x0800, 6);       // flags: UTF-8
  hdr.writeUInt16LE(8, 8);            // compression: deflate
  hdr.writeUInt16LE(entry.dosTime, 10);
  hdr.writeUInt16LE(entry.dosDate, 12);
  hdr.writeUInt32LE(entry.crc32, 14);
  hdr.writeUInt32LE(entry.compressedSize, 18);
  hdr.writeUInt32LE(entry.uncompressedSize, 22);
  hdr.writeUInt16LE(nameBytes.length, 26);
  hdr.writeUInt16LE(0, 28);           // extra field length
  nameBytes.copy(hdr, 30);
  return hdr;
}

function writeCentralDirEntry(entry: ZipEntry): Buffer {
  const nameBytes = Buffer.from(entry.name, 'utf8');
  const cde = Buffer.alloc(46 + nameBytes.length);
  cde.writeUInt32LE(0x02014b50, 0); // signature
  cde.writeUInt16LE(20, 4);          // version made by (2.0)
  cde.writeUInt16LE(20, 6);          // version needed
  cde.writeUInt16LE(0x0800, 8);      // flags: UTF-8
  cde.writeUInt16LE(8, 10);          // compression: deflate
  cde.writeUInt16LE(entry.dosTime, 12);
  cde.writeUInt16LE(entry.dosDate, 14);
  cde.writeUInt32LE(entry.crc32, 16);
  cde.writeUInt32LE(entry.compressedSize, 20);
  cde.writeUInt32LE(entry.uncompressedSize, 24);
  cde.writeUInt16LE(nameBytes.length, 28);
  cde.writeUInt16LE(0, 30);           // extra field
  cde.writeUInt16LE(0, 32);           // file comment
  cde.writeUInt16LE(0, 34);           // disk number start
  cde.writeUInt16LE(0, 36);           // internal attributes
  cde.writeUInt32LE(0, 38);           // external attributes
  cde.writeUInt32LE(entry.localHeaderOffset, 42);
  nameBytes.copy(cde, 46);
  return cde;
}

function writeEndOfCentralDirectory(
  entryCount: number,
  centralDirSize: number,
  centralDirOffset: number,
): Buffer {
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0); // signature
  eocd.writeUInt16LE(0, 4);           // disk number
  eocd.writeUInt16LE(0, 6);           // central dir start disk
  eocd.writeUInt16LE(entryCount, 8);
  eocd.writeUInt16LE(entryCount, 10);
  eocd.writeUInt32LE(centralDirSize, 12);
  eocd.writeUInt32LE(centralDirOffset, 16);
  eocd.writeUInt16LE(0, 20);          // comment length
  return eocd;
}

/**
 * Build a ZIP Buffer from a list of { name, rawData } entries.
 * Compression: deflate raw (zlib.deflateRawSync).
 * Safe against zip-slip: names are validated by callers before passing here.
 */
function buildZip(files: ReadonlyArray<{ name: string; rawData: Buffer }>): Buffer {
  const entries: ZipEntry[] = [];
  const localParts: Buffer[] = [];
  let offset = 0;
  const { dosDate, dosTime } = dosDateTime();

  for (const file of files) {
    const rawData = file.rawData;
    const compressed = zlib.deflateRawSync(rawData, { level: 6 });
    const entry: ZipEntry = {
      name: file.name,
      data: compressed,
      crc32: crc32(rawData),
      uncompressedSize: rawData.length,
      compressedSize: compressed.length,
      localHeaderOffset: offset,
      dosDate,
      dosTime,
    };
    const localHdr = writeLocalHeader(entry);
    localParts.push(localHdr, compressed);
    offset += localHdr.length + compressed.length;
    entries.push(entry);
  }

  const centralParts: Buffer[] = entries.map(writeCentralDirEntry);
  const centralDirSize = centralParts.reduce((s, b) => s + b.length, 0);
  const eocd = writeEndOfCentralDirectory(entries.length, centralDirSize, offset);

  return Buffer.concat([...localParts, ...centralParts, eocd]);
}

// ─── Encryption ───────────────────────────────────────────────────────────────

/**
 * Encrypt `plaintext` with AES-256-GCM using a key derived from `passphrase`
 * via scrypt. Returns a Buffer with the header prepended so the recipient can
 * decrypt with only the passphrase:
 *
 *   [16-byte salt][12-byte IV][16-byte GCM auth tag][ciphertext]
 */
function encryptBuffer(plaintext: Buffer, passphrase: string): Buffer {
  const salt = crypto.randomBytes(SALT_LEN);
  const iv = crypto.randomBytes(IV_LEN);

  // scrypt — key lives only in this scope and is zeroed before return.
  const key = crypto.scryptSync(passphrase, salt, KEY_LEN, {
    N: SCRYPT_N,
    r: SCRYPT_R,
    p: SCRYPT_P,
  });

  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

  // Zero the key immediately — it must not linger in heap after this point.
  key.fill(0);

  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag(); // 16 bytes

  return Buffer.concat([salt, iv, tag, encrypted]);
}

// ─── DB helpers ───────────────────────────────────────────────────────────────

function tableExists(db: Database, table: string): boolean {
  const row = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name = ?")
    .get(table) as { name?: string } | undefined;
  return !!row?.name;
}

function listExportableTables(db: Database): string[] {
  const rows = db
    .prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    .all() as Array<{ name: string }>;
  return rows.map((r) => r.name).filter((n) => !EXCLUDED_TABLES.has(n));
}

function sanitizeRow(
  table: string,
  row: Record<string, unknown>
): Record<string, unknown> {
  // store_config: redact sensitive values by key name
  if (
    table === 'store_config' &&
    typeof row['key'] === 'string' &&
    SENSITIVE_CONFIG_KEYS.has(row['key'])
  ) {
    return { ...row, value: null };
  }

  const fieldBlacklist = SENSITIVE_FIELDS.get(table);
  if (!fieldBlacklist || fieldBlacklist.size === 0) return row;

  const redacted: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    redacted[k] = fieldBlacklist.has(k) ? null : v;
  }
  return redacted;
}

/** Yield to the event loop between heavy operations (SEC-M26 pattern). */
function yieldToEventLoop(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

// ─── Rate limiting ────────────────────────────────────────────────────────────

/**
 * Returns true if the tenant has an in-flight job or completed a job within
 * the last hour. Caller should 429 when this returns true.
 */
function isRateLimited(db: Database, tenantId: number): boolean {
  if (!tableExists(db, 'tenant_exports')) return false;
  // In-flight: any pending/running job blocks a new one regardless of age.
  const inflight = db
    .prepare(
      "SELECT id FROM tenant_exports WHERE tenant_id = ? AND status IN ('pending','running') LIMIT 1"
    )
    .get(tenantId) as { id: number } | undefined;
  if (inflight) return true;

  // Cooldown: last completed/failed export must be > 1 hour ago.
  const recent = db
    .prepare(
      "SELECT id FROM tenant_exports WHERE tenant_id = ? AND started_at > datetime('now', ?) LIMIT 1"
    )
    .get(tenantId, `-${Math.ceil(RATE_LIMIT_MS / 60_000)} minutes`) as { id: number } | undefined;
  return !!recent;
}

// ─── Public API ───────────────────────────────────────────────────────────────

export interface StartExportResult {
  readonly jobId: number;
}

/**
 * Insert a new export job row and kick off the async export in the background.
 * Returns immediately with the job id so the caller can poll for status.
 *
 * @param db         - Tenant SQLite database (better-sqlite3, synchronous).
 * @param tenantId   - Numeric tenant id (0 for single-tenant installs).
 * @param userId     - ID of the requesting admin user.
 * @param passphrase - Encryption passphrase (min 12 chars, validated by caller).
 * @param exportsDir - Absolute path where the .enc file will be written.
 * @param uploadsDir - Absolute path to tenant uploads root (may not exist yet).
 */
export function startExport(
  db: Database,
  tenantId: number,
  userId: number,
  passphrase: string,
  exportsDir: string,
  uploadsDir: string,
): StartExportResult {
  if (!tableExists(db, 'tenant_exports')) {
    throw new Error('tenant_exports table does not exist — run migration 114');
  }

  if (isRateLimited(db, tenantId)) {
    throw new RateLimitError('Export rate limit: at most 1 export per hour per tenant');
  }

  const row = db
    .prepare(
      `INSERT INTO tenant_exports (tenant_id, requested_by_user_id, status, started_at)
       VALUES (?, ?, 'pending', datetime('now'))
       RETURNING id`
    )
    .get(tenantId, userId) as { id: number };

  const jobId = row.id;

  // Fire-and-forget — do not await. runExportJob handles its own error
  // catching and always marks the job terminal (complete | failed).
  setImmediate(() => {
    runExportJob(db, jobId, tenantId, passphrase, exportsDir, uploadsDir).catch(
      (err: unknown) => {
        logger.error('tenant export job crashed outside runExportJob', {
          jobId,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    );
  });

  return { jobId };
}

export class RateLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RateLimitError';
  }
}

// ─── Job runner ───────────────────────────────────────────────────────────────

async function runExportJob(
  db: Database,
  jobId: number,
  tenantId: number,
  passphrase: string,
  exportsDir: string,
  uploadsDir: string,
): Promise<void> {
  // Mark running
  db.prepare(
    "UPDATE tenant_exports SET status = 'running' WHERE id = ?"
  ).run(jobId);

  const scratchDir = path.join(exportsDir, `scratch-${jobId}-${Date.now()}`);

  try {
    await fsp.mkdir(scratchDir, { recursive: true });
    await fsp.mkdir(exportsDir, { recursive: true });

    const zipFiles: Array<{ name: string; rawData: Buffer }> = [];

    // ── 1. Dump each DB table to NDJSON ─────────────────────────────────────
    const tables = listExportableTables(db);
    logger.info('tenant export: dumping tables', { jobId, tableCount: tables.length });

    for (const table of tables) {
      await yieldToEventLoop();

      let rows: Array<Record<string, unknown>>;
      try {
        rows = db
          .prepare(`SELECT * FROM "${table}"`)
          .all() as Array<Record<string, unknown>>;
      } catch (err) {
        logger.warn('tenant export: skipping unreadable table', {
          jobId,
          table,
          error: err instanceof Error ? err.message : String(err),
        });
        continue;
      }

      const ndjson = rows
        .map((r) => JSON.stringify(sanitizeRow(table, r)))
        .join('\n');

      // Safe name: table comes from sqlite_master (controlled), not user input.
      // Sanitise anyway: keep only [a-zA-Z0-9_-] so the name is safe inside a ZIP.
      const safeName = table.replace(/[^a-zA-Z0-9_\-]/g, '_');
      zipFiles.push({
        name: `tables/${safeName}.ndjson`,
        rawData: Buffer.from(ndjson, 'utf8'),
      });
    }

    await yieldToEventLoop();

    // ── 2. Copy uploads (if the directory exists) ────────────────────────────
    const resolvedUploads = path.resolve(uploadsDir);
    if (fs.existsSync(resolvedUploads)) {
      await collectUploads(resolvedUploads, resolvedUploads, zipFiles);
      await yieldToEventLoop();
    }

    // ── 3. README ────────────────────────────────────────────────────────────
    const readmeText = buildReadme();
    zipFiles.push({ name: 'README.txt', rawData: Buffer.from(readmeText, 'utf8') });

    // ── 4. Build ZIP ─────────────────────────────────────────────────────────
    logger.info('tenant export: building zip', { jobId, fileCount: zipFiles.length });
    const zipBuffer = buildZip(zipFiles);
    await yieldToEventLoop();

    // ── 5. Encrypt ───────────────────────────────────────────────────────────
    logger.info('tenant export: encrypting', { jobId, zipBytes: zipBuffer.length });
    const encBuffer = encryptBuffer(zipBuffer, passphrase);
    await yieldToEventLoop();

    // ── 6. Write to disk ─────────────────────────────────────────────────────
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const filename = `tenant-export-${tenantId}-${ts}.enc`;
    const outPath = path.join(exportsDir, filename);
    await fsp.writeFile(outPath, encBuffer);

    // ── 7. Issue signed download token ───────────────────────────────────────
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + TOKEN_EXPIRY_MS).toISOString();

    db.prepare(
      `UPDATE tenant_exports
       SET status = 'complete',
           completed_at = datetime('now'),
           file_path = ?,
           byte_size = ?,
           download_token = ?,
           download_token_expires_at = ?
       WHERE id = ?`
    ).run(outPath, encBuffer.length, token, expiresAt, jobId);

    logger.info('tenant export: complete', {
      jobId,
      tenantId,
      fileBytes: encBuffer.length,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.error('tenant export: job failed', { jobId, error: msg });
    db.prepare(
      "UPDATE tenant_exports SET status = 'failed', completed_at = datetime('now'), error_message = ? WHERE id = ?"
    ).run(msg.slice(0, 1000), jobId);
  } finally {
    // Always remove scratch dir — it may contain partial plaintext data.
    try {
      if (fs.existsSync(scratchDir)) {
        fs.rmSync(scratchDir, { recursive: true, force: true });
      }
    } catch (cleanErr) {
      logger.error('tenant export: scratch dir cleanup failed', {
        jobId,
        scratchDir,
        error: cleanErr instanceof Error ? cleanErr.message : String(cleanErr),
      });
    }
  }
}

/**
 * Recursively collect files from `dir`, adding them to `zipFiles`.
 * ZIP-slip guard: every resolved absolute path must be prefixed by
 * `resolvedBase + path.sep` — any path that escapes the uploads root is
 * logged and skipped rather than included.
 */
async function collectUploads(
  dir: string,
  resolvedBase: string,
  zipFiles: Array<{ name: string; rawData: Buffer }>,
): Promise<void> {
  let entries: fs.Dirent[];
  try {
    entries = await fsp.readdir(dir, { withFileTypes: true });
  } catch {
    return; // Unreadable dir — skip silently.
  }

  for (const entry of entries) {
    const absPath = path.resolve(dir, entry.name);

    // ZIP-slip guard
    if (!absPath.startsWith(resolvedBase + path.sep) && absPath !== resolvedBase) {
      logger.error('tenant export: zip-slip path rejected in uploads', {
        absPath,
        resolvedBase,
      });
      continue;
    }

    if (entry.isDirectory()) {
      await collectUploads(absPath, resolvedBase, zipFiles);
      await yieldToEventLoop();
    } else if (entry.isFile()) {
      let data: Buffer;
      try {
        data = await fsp.readFile(absPath);
      } catch {
        continue; // Skip unreadable file.
      }

      // Build safe relative path for ZIP entry: forward slashes only.
      const rel = path.relative(resolvedBase, absPath).replace(/\\/g, '/');
      zipFiles.push({ name: `uploads/${rel}`, rawData: data });
    }
  }
}

function buildReadme(): string {
  return `Bizarre CRM — Tenant Data Export
=================================

This archive contains a complete export of your tenant's data.

FILE LAYOUT
-----------
  tables/           NDJSON files (one JSON object per line, one file per table)
  uploads/          Binary uploads preserving original relative paths
  README.txt        This file

ENCRYPTION
----------
  Algorithm : AES-256-GCM
  KDF       : scrypt(passphrase, salt, N=32768, r=8, p=1)
  Header    : [16-byte salt][12-byte IV][16-byte GCM auth tag][ciphertext]

DECRYPT WITH PYTHON
-------------------
  import sys, hashlib, struct, base64
  from cryptography.hazmat.primitives.ciphers.aead import AESGCM
  from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
  from cryptography.hazmat.backends import default_backend

  data = open('export.enc', 'rb').read()
  salt, iv, tag, ct = data[:16], data[16:28], data[28:44], data[44:]
  kdf = Scrypt(salt=salt, length=32, n=32768, r=8, p=1, backend=default_backend())
  key = kdf.derive(passphrase.encode())
  pt = AESGCM(key).decrypt(iv, ct + tag, None)
  open('export.zip', 'wb').write(pt)

DECRYPT WITH NODE.JS
--------------------
  const crypto = require('crypto');
  const fs = require('fs');
  const buf = fs.readFileSync('export.enc');
  const salt = buf.slice(0, 16);
  const iv   = buf.slice(16, 28);
  const tag  = buf.slice(28, 44);
  const ct   = buf.slice(44);
  const key  = crypto.scryptSync(passphrase, salt, 32, { N: 32768, r: 8, p: 1 });
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
  fs.writeFileSync('export.zip', pt);

Exported at: ${new Date().toISOString()}
`;
}

// ─── Status / token lookup ────────────────────────────────────────────────────

export function getExportJob(db: Database, jobId: number, tenantId: number): ExportJobRecord | null {
  if (!tableExists(db, 'tenant_exports')) return null;
  const row = db
    .prepare('SELECT * FROM tenant_exports WHERE id = ? AND tenant_id = ?')
    .get(jobId, tenantId) as ExportJobRecord | undefined;
  return row ?? null;
}

/**
 * Look up a download token. Returns the job record if the token is valid,
 * not expired, and not yet used. Returns null otherwise.
 */
export function lookupDownloadToken(db: Database, token: string): ExportJobRecord | null {
  if (!tableExists(db, 'tenant_exports')) return null;

  const row = db
    .prepare(
      `SELECT * FROM tenant_exports
       WHERE download_token = ?
         AND status = 'complete'
         AND download_token_expires_at > datetime('now')
         AND downloaded_at IS NULL
       LIMIT 1`
    )
    .get(token) as ExportJobRecord | undefined;
  return row ?? null;
}

/**
 * Mark a download token as consumed (single-use enforcement).
 * Must be called immediately before streaming the file to the client.
 */
export function consumeDownloadToken(db: Database, jobId: number): void {
  db.prepare(
    "UPDATE tenant_exports SET downloaded_at = datetime('now') WHERE id = ?"
  ).run(jobId);
}

// ─── Retention sweep ──────────────────────────────────────────────────────────

/**
 * Delete export jobs (and their on-disk .enc files) older than
 * EXPORT_RETENTION_DAYS. Called by retentionSweeper.ts as part of the nightly
 * sweep.
 *
 * Returns the number of rows deleted.
 */
export async function sweepOldExports(db: Database): Promise<number> {
  if (!tableExists(db, 'tenant_exports')) return 0;

  interface ExpiredRow {
    id: number;
    file_path: string | null;
  }

  const expired = db
    .prepare(
      `SELECT id, file_path FROM tenant_exports
       WHERE started_at < datetime('now', '-${EXPORT_RETENTION_DAYS} days')`
    )
    .all() as ExpiredRow[];

  if (expired.length === 0) return 0;

  let deleted = 0;
  for (const row of expired) {
    // Remove on-disk file first. If unlink fails we skip deleting the DB row
    // so the file path is not orphaned silently.
    if (row.file_path) {
      try {
        await fsp.unlink(row.file_path);
      } catch (err: unknown) {
        const code = (err as NodeJS.ErrnoException).code;
        if (code !== 'ENOENT') {
          logger.error('sweepOldExports: unlink failed', {
            jobId: row.id,
            filePath: row.file_path,
            error: err instanceof Error ? err.message : String(err),
          });
          continue; // Leave DB row intact — stale reference > orphaned file.
        }
        // ENOENT: already gone — still delete the DB row.
      }
    }

    try {
      db.prepare('DELETE FROM tenant_exports WHERE id = ?').run(row.id);
      deleted++;
    } catch (err) {
      logger.error('sweepOldExports: DB delete failed', {
        jobId: row.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  if (deleted > 0) {
    logger.info(`sweepOldExports: ${deleted} export records deleted`, { deleted });
  }

  return deleted;
}
