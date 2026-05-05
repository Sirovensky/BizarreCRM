/**
 * dataExport.routes.ts — PROD58. Per-tenant "download all my data"
 * capability for GDPR/CCPA compliance.
 *
 * Endpoints:
 *   GET /api/v1/data-export/export-all-data
 *     Dump every user-owned table in the tenant DB as a streamed JSON
 *     response with a filename attachment header. Admin-role-gated,
 *     rate-limited to 1 export per tenant per hour.
 *
 * Streaming strategy: delegates to services/dataExportGenerator.ts which
 * writes the JSON to a temp file in config.exportsPath, then pipes it back
 * to the HTTP response via createReadStream. The temp file is unlinked
 * after the response finishes. This keeps the serialisation logic shared
 * with the cron scheduler (dataExportScheduleCron.ts).
 *
 * Security:
 *   - authMiddleware ensures a valid user token is present.
 *   - adminOnly ensures non-admins cannot trigger an export.
 *   - SENSITIVE_FIELDS / EXCLUDED_TABLES redaction lives in the service.
 *   - Rate limiting uses store_config.last_data_export_at so a burst of
 *     concurrent exports cannot overlap.
 *   - Audit log entry (`data_export`) records user_id, tenant, row counts.
 */

import fs from 'fs';
import { Router, Request, Response, NextFunction } from 'express';
import type Database from 'better-sqlite3';
import { AppError } from '../middleware/errorHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { config } from '../config.js';
import { generateExportToFile } from '../services/dataExportGenerator.js';

const logger = createLogger('data-export');

const router = Router();

// ─── Constants ────────────────────────────────────────────────────────────

/** Rate-limit window: one full data export per tenant per hour. */
const EXPORT_RATE_LIMIT_MS = 60 * 60 * 1000;

/** Key used to store the last-export timestamp in store_config. */
const LAST_EXPORT_KEY = 'last_data_export_at';

// ─── Middleware ───────────────────────────────────────────────────────────

function adminOnly(req: Request, _res: Response, next: NextFunction): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
  next();
}

// ─── Helpers ──────────────────────────────────────────────────────────────

/**
 * Read the last-export timestamp (ISO string) from store_config. Returns
 * null when the row does not exist yet.
 */
function readLastExportAt(db: Database.Database): string | null {
  try {
    const row = db
      .prepare('SELECT value FROM store_config WHERE key = ?')
      .get(LAST_EXPORT_KEY) as { value?: string } | undefined;
    return row?.value ?? null;
  } catch {
    return null;
  }
}

/**
 * Upsert the last-export timestamp. Wrapped in try/catch because we do
 * not want a config-write failure to abort an in-progress export — the
 * audit log already records the attempt either way.
 */
function writeLastExportAt(db: Database.Database, iso: string): void {
  try {
    db.prepare(
      'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)'
    ).run(LAST_EXPORT_KEY, iso);
  } catch (err) {
    logger.warn('failed to persist last_data_export_at', {
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Parse an ISO timestamp to epoch ms, tolerating garbage input.
 */
function parseIsoMs(iso: string | null): number {
  if (!iso) return 0;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? t : 0;
}

/**
 * Escape a tenant slug / date fragment for safe inclusion in the
 * Content-Disposition filename. Anything outside [a-z0-9-_] collapses
 * to '-' so an exotic slug cannot inject header-breaking characters.
 */
function safeFilenameToken(raw: string): string {
  return raw.toLowerCase().replace(/[^a-z0-9-_]+/g, '-').slice(0, 64) || 'tenant';
}

// ─── GET /export-all-data ─────────────────────────────────────────────────

router.get('/export-all-data', adminOnly, async (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const tenantSlug = req.tenantSlug ?? 'single-tenant';
  const userId = req.user?.id ?? null;

  // Rate-limit: 1 export per hour per tenant.
  const lastExportIso = readLastExportAt(db);
  const lastExportMs = parseIsoMs(lastExportIso);
  const elapsedMs = Date.now() - lastExportMs;
  if (lastExportMs > 0 && elapsedMs < EXPORT_RATE_LIMIT_MS) {
    const retryAfterSeconds = Math.ceil((EXPORT_RATE_LIMIT_MS - elapsedMs) / 1000);
    res.setHeader('Retry-After', String(retryAfterSeconds));
    res.status(429).json({
      success: false,
      message: `Data export rate limit: one export per hour. Try again in ${Math.ceil(retryAfterSeconds / 60)} minutes.`,
      data: { last_export_at: lastExportIso, retry_after_seconds: retryAfterSeconds },
    });
    return;
  }

  // Reserve the rate-limit slot BEFORE generating. An abortive export still
  // counts to prevent rapid-fire calls that disconnect early.
  const startedAtIso = new Date().toISOString();
  writeLastExportAt(db, startedAtIso);

  // Build the attachment filename from safe tokens only.
  const dateToken = startedAtIso.slice(0, 10); // YYYY-MM-DD
  const slugToken = safeFilenameToken(tenantSlug);
  const filename = `bizarre-crm-export-${slugToken}-${dateToken}.json`;

  let exportResult: Awaited<ReturnType<typeof generateExportToFile>> | undefined;

  try {
    // Delegate to the shared service which writes the JSON to a temp file.
    // outputDir is config.exportsPath — never caller-supplied.
    exportResult = await generateExportToFile(db, 'full', config.exportsPath, tenantSlug);
  } catch (err) {
    logger.error('export generation failed', {
      tenantSlug,
      error: err instanceof Error ? err.message : String(err),
    });
    res.status(500).json({ success: false, message: 'Export generation failed.' });
    return;
  }

  const { file_path: filePath, row_count: totalRows } = exportResult;

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');

  // Stream the generated file back to the client, then clean up the temp file.
  const readStream = fs.createReadStream(filePath);

  readStream.on('error', (err) => {
    logger.error('export read-stream error', {
      tenantSlug,
      error: err.message,
    });
    if (!res.writableEnded) res.end();
  });

  res.on('finish', () => {
    // Best-effort cleanup of the temp export file after delivery.
    fs.unlink(filePath, (unlinkErr) => {
      if (unlinkErr) {
        logger.warn('export temp file cleanup failed', {
          filePath,
          error: unlinkErr.message,
        });
      }
    });
  });

  readStream.pipe(res);

  // Audit log — always fire.
  audit(db, 'data_export', userId, ip, {
    tenant: tenantSlug,
    filename,
    total_rows: totalRows,
  });

  logger.info('tenant data export completed', {
    tenantSlug,
    userId,
    totalRows,
  });
});

// ─── GET /export-all-data/status ──────────────────────────────────────────
// Read-only status endpoint so the UI can render "last exported at" and
// "next allowed at" without having to catch the 429 from a real attempt.

router.get('/export-all-data/status', adminOnly, (req: Request, res: Response) => {
  const db = req.db;
  const lastExportIso = readLastExportAt(db);
  const lastExportMs = parseIsoMs(lastExportIso);
  const elapsedMs = Date.now() - lastExportMs;
  const allowed = lastExportMs === 0 || elapsedMs >= EXPORT_RATE_LIMIT_MS;
  const retryAfterSeconds = allowed ? 0 : Math.ceil((EXPORT_RATE_LIMIT_MS - elapsedMs) / 1000);

  res.json({
    success: true,
    data: {
      last_export_at: lastExportIso,
      next_allowed_in_seconds: retryAfterSeconds,
      allowed,
      rate_limit_window_seconds: EXPORT_RATE_LIMIT_MS / 1000,
    },
  });
});

// ─── POST /erase-customer-pii ─────────────────────────────────────────────
// GDPR right-to-erasure: NULLs out PII fields on the customer row and marks
// is_deleted=1. Business records (tickets, invoices) are intentionally kept
// — they are the shop's own business data, not the subject's personal data.
// Requires admin role + confirm_name match (same confirm pattern as SEC-H23).

router.post('/erase-customer-pii', adminOnly, (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const userId = req.user?.id ?? null;

  const rawId = req.body?.customer_id;
  const confirmName: unknown = req.body?.confirm_name;

  if (!rawId || !Number.isInteger(Number(rawId))) {
    res.status(400).json({ success: false, message: 'customer_id must be a valid integer' });
    return;
  }
  const customerId = Number(rawId);

  if (typeof confirmName !== 'string' || confirmName.trim() === '') {
    res.status(400).json({ success: false, message: 'confirm_name is required' });
    return;
  }

  const customer = db
    .prepare('SELECT id, first_name, last_name FROM customers WHERE id = ? AND is_deleted = 0')
    .get(customerId) as { id: number; first_name: string | null; last_name: string | null } | undefined;

  if (!customer) {
    res.status(404).json({ success: false, message: 'Customer not found' });
    return;
  }

  const expected = `${customer.first_name ?? ''} ${customer.last_name ?? ''}`.trim();
  if (confirmName.trim() !== expected) {
    res.status(400).json({
      success: false,
      message: 'confirm_name must exactly match the customer\'s full name',
    });
    return;
  }

  // NULL out all PII fields; keep the row so FK-linked tickets/invoices stay valid.
  db.prepare(`
    UPDATE customers
    SET first_name = NULL,
        last_name  = NULL,
        email      = NULL,
        phone      = NULL,
        mobile     = NULL,
        address1   = NULL,
        address2   = NULL,
        city       = NULL,
        state      = NULL,
        postcode   = NULL,
        country    = NULL,
        comments   = NULL,
        is_deleted = 1,
        updated_at = datetime('now')
    WHERE id = ?
  `).run(customerId);

  audit(db, 'gdpr_customer_pii_erased', userId, ip, {
    customer_id: customerId,
    erased_fields: ['first_name', 'last_name', 'email', 'phone', 'mobile', 'address1', 'address2', 'city', 'state', 'postcode', 'country', 'comments'],
  });

  logger.info('GDPR PII erasure completed', { customerId, adminUserId: userId });

  res.json({
    success: true,
    data: { message: `PII for customer ${customerId} has been erased per GDPR right-to-be-forgotten` },
  });
});

export default router;
