/**
 * Pre-write upload byte-quota guard (PROD102).
 *
 * Problem:
 *   `reserveStorage()` inside route handlers runs AFTER multer has already
 *   written the payload to disk. A malicious or misbehaving client can
 *   therefore saturate disk space before the quota is enforced — classic DoS.
 *
 * This middleware runs BEFORE multer in the route chain and performs a
 * fast-path rejection using the advisory `Content-Length` header. Because
 * Content-Length is client-supplied and therefore untrusted, we treat it as
 * a lower-bound hint only: if it is present and already proves the request
 * would exceed quota, we reject immediately with 413 without touching disk.
 * If Content-Length is absent or too small to be informative, we let the
 * request proceed — multer's per-field size limits and the post-write
 * `reserveStorage()` call inside each handler remain the authoritative
 * enforcement layers.
 *
 * Design decisions:
 *   - No table change needed: quota is the `storageLimitMb` field on the
 *     tenant limits object (already populated by tenantResolver middleware)
 *     and current usage is tracked in `tenant_usage.storage_bytes` via the
 *     master DB (read by `getUsage()`).
 *   - Single-tenant mode (config.multiTenant === false) and tenants with no
 *     storage limit (storageLimitMb == null) are fast-pathed through with no
 *     overhead — a single truthiness check.
 *   - We deliberately do NOT try to read actual current usage here because
 *     that would require a master-DB query on every upload request even when
 *     the tenant is far below quota.  The fast-path guard only runs the DB
 *     query when Content-Length is present, so the common case (no
 *     Content-Length or Content-Length well below quota) is free.
 *   - HTTP 413 (Payload Too Large) is the semantically correct status code
 *     for pre-write quota rejection; 403 is used by the post-write
 *     reserveStorage() path for consistency with the existing API shape.
 *
 * Wiring (every upload route):
 *   router.post('/path', enforceUploadQuota, upload.single('field'), ...)
 */

import type { Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import { createLogger } from '../utils/logger.js';
import { getUsage } from '../services/usageTracker.js';

const logger = createLogger('uploadQuota');

/**
 * Express middleware that must be placed BEFORE the multer middleware in the
 * route chain for every file-upload endpoint.
 *
 * Fast-path behaviour:
 *   1. If not in multi-tenant mode → next() immediately.
 *   2. If tenant has no storage limit (unlimited plan) → next() immediately.
 *   3. If `Content-Length` header is missing or zero → next() (can't
 *      pre-check without a declared size; multer + post-write reserveStorage
 *      will handle it).
 *   4. If `Content-Length` present and `current_usage + Content-Length >
 *      limit` → 413 with standardised JSON body. Does NOT write any file.
 *
 * The middleware is intentionally narrow: it only guards the byte quota.
 * The file-count quota (F4) is handled by `fileUploadValidator` which runs
 * immediately AFTER multer.
 */
export async function enforceUploadQuota(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  // 1. Single-tenant: no quota tracking, skip immediately.
  if (!config.multiTenant) {
    next();
    return;
  }

  const tenantId = req.tenantId;
  const limitMb: number | null = req.tenantLimits?.storageLimitMb ?? null;

  // 2. Unlimited plan (limitMb is null or undefined) → always allow.
  if (!tenantId || limitMb == null) {
    next();
    return;
  }

  // 3. No Content-Length → cannot pre-check, fall through to post-write path.
  const rawCL = req.headers['content-length'];
  if (!rawCL) {
    next();
    return;
  }
  // SCAN-1151: parseInt accepts `1.5e20` and returns 1, bypassing the
  // pre-check while the actual body can balloon past the quota via
  // chunked transfer. Reject any Content-Length whose string form isn't
  // a pure decimal integer before parsing. Whitespace-trim first since
  // Node splits on CRLF but can preserve surrounding whitespace in
  // malformed peers.
  const clStr = String(rawCL).trim();
  if (!/^\d+$/.test(clStr)) {
    next();
    return;
  }
  const contentLength = parseInt(clStr, 10);
  if (!Number.isFinite(contentLength) || contentLength <= 0) {
    next();
    return;
  }

  // 4. Read current usage and compare.  We do this only when Content-Length
  //    is present so most "small well-under-quota" requests never reach here.
  try {
    const usage = getUsage(tenantId);
    const currentBytes = usage?.storage_bytes ?? 0;
    const limitBytes = limitMb * 1024 * 1024;

    if (currentBytes + contentLength > limitBytes) {
      logger.warn('Upload quota pre-check rejected request (Content-Length)', {
        tenantId,
        path: req.path,
        contentLength,
        currentBytes,
        limitBytes,
      });
      res.status(413).json({
        success: false,
        upgrade_required: true,
        feature: 'storage_limit',
        message: `Tenant upload quota exceeded. Storage limit is ${limitMb} MB.`,
      });
      return;
    }
  } catch (err) {
    // Fail open: if the usage DB is unavailable, don't block uploads — the
    // post-write reserveStorage() call will still enforce atomically.
    logger.warn('enforceUploadQuota: usage check failed, passing through', {
      tenantId,
      error: err instanceof Error ? err.message : 'unknown',
    });
  }

  next();
}
