/**
 * Post-multer upload validation middleware (audit section 10, bugs F1/F2/F4).
 *
 * This is a single choke-point that every multer-backed route should run
 * immediately after `upload.single()` / `upload.array()`. The middleware:
 *
 *   1. F1 — Re-checks the real file content with magic-byte inspection
 *           (`validateFileMagicBytes`). If the bytes don't match the declared
 *           MIME, the file is deleted from disk and the request is rejected
 *           with 400. This defeats the "rename .exe to .jpg" bypass of
 *           multer's header-only whitelist.
 *
 *   2. F2 — Runs the `scanFileForViruses` stub. By default this always returns
 *           clean; operators can enable ClamAV by setting `CLAMAV_HOST`. If a
 *           threat is reported, the file is deleted and the request fails 400.
 *
 *   3. F4 — Enforces a per-tenant file-count quota. The quota value lives in
 *           `store_config.file_count_quota` (seeded by migration 085) and the
 *           running count is kept in a sentinel file `.file_count` inside the
 *           tenant's uploads directory. Using a sentinel file avoids a relational
 *           write on every upload and also avoids an expensive
 *           `fs.readdirSync(...).length` walk for every request (which on a
 *           large tenant could stat tens of thousands of files).
 *
 * Design constraints (from the audit-fix scope rules):
 *   - Don't touch business logic in route handlers.
 *   - Minimal surface area — single exported middleware factory.
 *   - Preserve `{ success: true, data: X }` response shape on success by NOT
 *     writing to `res` on success; we simply call `next()`.
 *   - Never throw from the middleware — surface errors as JSON responses so
 *     the existing error handler does not wrap them in an HTML 500.
 */

import type { Request, Response, NextFunction } from 'express';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';
import { createLogger } from '../utils/logger.js';
import { validateFileOnDisk, scanFileForViruses } from '../utils/fileValidation.js';

const logger = createLogger('fileUploadValidator');

/** Name of the sentinel counter file kept inside every tenant upload dir. */
const COUNTER_FILENAME = '.file_count';

/** Default ceiling if store_config is missing a row (should never happen post-migration 085). */
const DEFAULT_FILE_COUNT_QUOTA = 100_000;

interface RowConfig {
  value: string;
}

export interface FileUploadValidatorOptions {
  /**
   * Optional override of the tenant upload directory. When omitted we default
   * to `config.uploadsPath/<tenantSlug>` (or `config.uploadsPath` if the slug
   * is missing — single-tenant dev mode).
   */
  getTenantDir?: (req: Request) => string;
  /**
   * Optional list of MIME types allowed specifically for this route. If
   * supplied, any file whose detected type does not satisfy one of these
   * declared MIMEs is rejected even if the magic-byte check would have
   * accepted it. This is how routes opt into a narrower whitelist than the
   * library default (e.g. images only vs. images + PDF).
   */
  allowedMimes?: readonly string[];
}

/**
 * Collect the files from the request into a flat array regardless of whether
 * multer used `.single()` (populates `req.file`), `.array()` (populates
 * `req.files` as an array), or `.fields()` (populates `req.files` as an
 * object keyed by field name).
 */
function collectFiles(req: Request): Express.Multer.File[] {
  const out: Express.Multer.File[] = [];
  const single = (req as any).file as Express.Multer.File | undefined;
  if (single) out.push(single);
  const many = (req as any).files as
    | Express.Multer.File[]
    | Record<string, Express.Multer.File[]>
    | undefined;
  if (Array.isArray(many)) {
    out.push(...many);
  } else if (many && typeof many === 'object') {
    for (const key of Object.keys(many)) {
      const arr = many[key];
      if (Array.isArray(arr)) out.push(...arr);
    }
  }
  return out;
}

/** Best-effort removal — never throw during cleanup. */
function safeUnlink(filePath: string | undefined): void {
  if (!filePath) return;
  try { fs.unlinkSync(filePath); } catch { /* ignored */ }
}

function resolveTenantDir(req: Request, override?: (req: Request) => string): string {
  if (override) return override(req);
  const slug = req.tenantSlug;
  return slug ? path.join(config.uploadsPath, slug) : config.uploadsPath;
}

/**
 * Read (or lazily create) the sentinel counter file for a tenant directory.
 * Returns the current count as a non-negative integer.
 */
function readFileCounter(tenantDir: string): number {
  try {
    if (!fs.existsSync(tenantDir)) return 0;
    const counterPath = path.join(tenantDir, COUNTER_FILENAME);
    if (!fs.existsSync(counterPath)) {
      // First call — seed the counter by walking the directory once. This
      // only pays the full directory-walk cost once per tenant.
      const seed = countExistingFiles(tenantDir);
      // DA-2: tmp+rename for the one-time seed write too.
      try {
        const tmpPath = counterPath + '.tmp.' + process.pid + '.' + Date.now();
        fs.writeFileSync(tmpPath, String(seed), 'utf8');
        fs.renameSync(tmpPath, counterPath);
      } catch { /* best effort */ }
      return seed;
    }
    const raw = fs.readFileSync(counterPath, 'utf8').trim();
    const n = Number.parseInt(raw, 10);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  } catch (err) {
    logger.warn('Unable to read file counter', {
      tenantDir,
      error: err instanceof Error ? err.message : 'unknown',
    });
    return 0;
  }
}

/** One-time seed scan — counts every file in tenantDir and its subdirs. */
function countExistingFiles(dir: string): number {
  let total = 0;
  const stack: string[] = [dir];
  while (stack.length > 0) {
    const cur = stack.pop()!;
    let entries: fs.Dirent[] = [];
    try { entries = fs.readdirSync(cur, { withFileTypes: true }); } catch { continue; }
    for (const ent of entries) {
      if (ent.name === COUNTER_FILENAME) continue;
      const full = path.join(cur, ent.name);
      if (ent.isDirectory()) stack.push(full);
      else if (ent.isFile()) total += 1;
    }
  }
  return total;
}

/** Atomically bump the counter by `delta` (may be negative on rollback). */
function adjustFileCounter(tenantDir: string, delta: number): void {
  try {
    if (!fs.existsSync(tenantDir)) fs.mkdirSync(tenantDir, { recursive: true });
    const counterPath = path.join(tenantDir, COUNTER_FILENAME);
    const current = readFileCounter(tenantDir);
    const next = Math.max(0, current + delta);
    // DA-2: tmp+rename instead of direct writeFileSync. A power failure or
    // native abort mid-write would otherwise leave a 0-byte counter file and
    // permanently desync the upload quota. rename is atomic on POSIX and
    // near-atomic on Windows NTFS.
    const tmpPath = counterPath + '.tmp.' + process.pid + '.' + Date.now();
    fs.writeFileSync(tmpPath, String(next), 'utf8');
    fs.renameSync(tmpPath, counterPath);
  } catch (err) {
    logger.error('Failed to adjust file counter', {
      tenantDir,
      delta,
      error: err instanceof Error ? err.message : 'unknown',
    });
  }
}

/** Pull the tenant's file-count quota out of store_config. */
function getFileCountQuota(req: Request): number {
  try {
    const db = (req as any).db;
    if (!db) return DEFAULT_FILE_COUNT_QUOTA;
    const row = db.prepare("SELECT value FROM store_config WHERE key = 'file_count_quota'").get() as RowConfig | undefined;
    if (!row?.value) return DEFAULT_FILE_COUNT_QUOTA;
    const n = Number.parseInt(row.value, 10);
    return Number.isFinite(n) && n > 0 ? n : DEFAULT_FILE_COUNT_QUOTA;
  } catch {
    return DEFAULT_FILE_COUNT_QUOTA;
  }
}

/**
 * Factory that returns the express middleware. Pass route-specific options
 * (like the allowed MIME whitelist) if the defaults aren't a match.
 */
export function fileUploadValidator(options: FileUploadValidatorOptions = {}) {
  return async function validate(req: Request, res: Response, next: NextFunction): Promise<void> {
    const files = collectFiles(req);
    if (files.length === 0) {
      // No files attached — nothing to validate, let the route handler deal
      // with the "no file uploaded" case (it already does).
      next();
      return;
    }

    const tenantDir = resolveTenantDir(req, options.getTenantDir);

    // F4 — per-tenant file-count ceiling. Enforce BEFORE magic-byte work so
    // we fail fast when the tenant is already at the cap.
    const quota = getFileCountQuota(req);
    const currentCount = readFileCounter(tenantDir);
    if (currentCount + files.length > quota) {
      for (const f of files) safeUnlink(f.path);
      logger.warn('File count quota exceeded', {
        tenantSlug: req.tenantSlug,
        currentCount,
        incoming: files.length,
        quota,
      });
      res.status(403).json({
        success: false,
        error: 'File count quota exceeded',
        message: `File count quota (${quota}) exceeded. Delete unused files or upgrade your plan.`,
      });
      return;
    }

    // F1 — magic-byte check for every file. Reject on the first mismatch and
    // clean up everything we already wrote to disk (multer has already saved
    // all files by the time this middleware runs).
    for (const f of files) {
      const declaredMime = f.mimetype;
      const result = validateFileOnDisk(f.path, declaredMime);
      if (!result.valid) {
        logger.warn('Magic byte validation failed', {
          tenantSlug: req.tenantSlug,
          filename: f.filename,
          declaredMime,
          error: result.error,
        });
        for (const other of files) safeUnlink(other.path);
        res.status(400).json({
          success: false,
          error: 'Invalid file content',
          message: result.error || 'File content does not match declared type',
        });
        return;
      }
      if (options.allowedMimes && options.allowedMimes.length > 0 && !options.allowedMimes.includes(declaredMime)) {
        for (const other of files) safeUnlink(other.path);
        res.status(400).json({
          success: false,
          error: 'Disallowed file type',
          message: `File type '${declaredMime}' is not permitted for this endpoint`,
        });
        return;
      }
    }

    // F2 — virus scan. Stub returns clean unless CLAMAV_HOST is wired up.
    for (const f of files) {
      try {
        const scan = await scanFileForViruses(f.path);
        if (!scan.clean) {
          logger.error('Virus scan rejected upload', {
            tenantSlug: req.tenantSlug,
            filename: f.filename,
            threat: scan.threat,
          });
          for (const other of files) safeUnlink(other.path);
          res.status(400).json({
            success: false,
            error: 'File failed virus scan',
            message: `Uploaded file was rejected by the virus scanner${scan.threat ? ` (${scan.threat})` : ''}`,
          });
          return;
        }
      } catch (err) {
        logger.error('Virus scanner errored', {
          tenantSlug: req.tenantSlug,
          filename: f.filename,
          error: err instanceof Error ? err.message : 'unknown',
        });
        // Fail closed if the scanner itself explodes — safer than accepting
        // unchecked files when the scanner is expected to be available.
        for (const other of files) safeUnlink(other.path);
        res.status(500).json({
          success: false,
          error: 'Upload validation failed',
          message: 'Internal validation error — please try again',
        });
        return;
      }
    }

    // Everything passed — bump the counter and hand off to the route handler.
    adjustFileCounter(tenantDir, files.length);
    next();
  };
}

/**
 * Decrement helper exposed for callers that roll back an upload after the
 * middleware has already incremented the counter (e.g. storage-bytes quota
 * failure inside the route handler). Keeping the helper here so there is
 * exactly one place that writes the counter file.
 */
export function releaseFileCount(req: Request, count: number): void {
  const tenantDir = resolveTenantDir(req);
  adjustFileCounter(tenantDir, -Math.abs(count));
}
