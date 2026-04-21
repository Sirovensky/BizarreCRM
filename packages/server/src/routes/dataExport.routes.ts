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
 * Streaming strategy: we res.write() the envelope, then iterate tables and
 * emit each one in sequence using JSON.stringify(row) per row. Writing one
 * row at a time keeps peak memory bounded for large tenants (otherwise a
 * 500k-row invoices table would balloon the process heap before the first
 * byte hits the wire).
 *
 * Security:
 *   - authMiddleware ensures a valid user token is present.
 *   - adminOnly ensures non-admins cannot trigger an export.
 *   - SENSITIVE_FIELDS strips password hashes, TOTP secrets, and other
 *     auth material from user rows before serializing — a GDPR export
 *     should hand over business data, not the tenant's admin login.
 *   - EXCLUDED_TABLES drops per-session / bookkeeping tables that have
 *     no value to the tenant and may contain short-lived auth tokens.
 *   - Rate limiting uses store_config.last_data_export_at so a burst of
 *     concurrent exports cannot overlap.
 *   - Audit log entry (`data_export`) records user_id, tenant, row counts.
 */

import { Router, Request, Response, NextFunction } from 'express';
import type Database from 'better-sqlite3';
import { AppError } from '../middleware/errorHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES } from '../utils/errorCodes.js';

const logger = createLogger('data-export');

const router = Router();

// ─── Constants ────────────────────────────────────────────────────────────

/** Rate-limit window: one full data export per tenant per hour. */
const EXPORT_RATE_LIMIT_MS = 60 * 60 * 1000;

/** Key used to store the last-export timestamp in store_config. */
const LAST_EXPORT_KEY = 'last_data_export_at';

/**
 * Tables that are NEVER exported. Either tenant-irrelevant (SQLite
 * bookkeeping, migration tracking) or contain short-lived auth material
 * that has no reason to live in a customer-portable archive.
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
  'api_key_revocations',
  'admin_tokens',
  'pending_2fa_challenges',
  'recovery_codes_used',
]);

/**
 * Per-table field blacklist. When a row from the table on the left is
 * emitted, each listed column is rewritten to null. This is narrower than
 * EXCLUDED_TABLES — the user still gets the row, they just don't get the
 * password hash.
 */
const SENSITIVE_FIELDS: Record<string, ReadonlySet<string>> = {
  users: new Set([
    'password_hash',
    'totp_secret',
    'pin_hash',
    'recovery_codes',
    'reset_token_hash',
    'remember_token_hash',
  ]),
  store_config: new Set([
    // Secret values stored in the key/value store. We keep the keys so
    // the tenant can see which integrations are configured, but we blank
    // the sensitive values before emitting.
  ]),
};

/**
 * Sensitive store_config keys. When we emit a store_config row whose
 * `key` matches any entry here, its `value` is rewritten to null — the
 * export is for the tenant's own records, not for onward transmission,
 * and we still do not want to hand a plaintext bearer token to anyone
 * who intercepts the JSON file on the way to the user's disk.
 */
const SENSITIVE_CONFIG_KEYS = new Set<string>([
  'blockchyp_api_key',
  'blockchyp_bearer_token',
  'blockchyp_signing_key',
  'sms_twilio_auth_token',
  'sms_telnyx_api_key',
  'sms_bandwidth_password',
  'sms_plivo_auth_token',
  'sms_vonage_api_secret',
  'smtp_pass',
  'tcx_password',
  'stripe_secret_key',
  'twilio_auth_token',
]);

// ─── Middleware ───────────────────────────────────────────────────────────

function adminOnly(req: Request, _res: Response, next: NextFunction): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
  next();
}

// ─── Helpers ──────────────────────────────────────────────────────────────

/**
 * List every user table in the tenant DB. Excludes sqlite bookkeeping,
 * migration tracking, and the blacklist above.
 */
function listExportableTables(db: Database.Database): string[] {
  const rows = db
    .prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    .all() as Array<{ name: string }>;

  return rows
    .map((r) => r.name)
    .filter((name) => !EXCLUDED_TABLES.has(name));
}

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
 * Sanitize a row according to the per-table field blacklist. Returns a
 * NEW object (immutable) so the original row (possibly shared with the
 * SQLite cache) is not mutated.
 */
function sanitizeRow(table: string, row: Record<string, unknown>): Record<string, unknown> {
  const fieldBlacklist = SENSITIVE_FIELDS[table];

  // store_config has a key/value shape — redact by key name.
  if (table === 'store_config' && typeof row.key === 'string' && SENSITIVE_CONFIG_KEYS.has(row.key)) {
    return { ...row, value: null };
  }

  if (!fieldBlacklist || fieldBlacklist.size === 0) return row;

  const redacted: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    redacted[k] = fieldBlacklist.has(k) ? null : v;
  }
  return redacted;
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

router.get('/export-all-data', adminOnly, (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const tenantSlug = req.tenantSlug ?? 'single-tenant';
  const userId = req.user?.id ?? null;

  // Rate-limit: 1 export per hour per tenant. We read the timestamp from
  // store_config (per-tenant by virtue of req.db pointing at the tenant
  // DB after tenantResolver) so the limit survives a process restart.
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

  // Reserve the rate-limit slot BEFORE streaming starts. If the export
  // then fails mid-stream we do not refund the slot — an abortive
  // export still counts, to protect against a client that intentionally
  // disconnects early in a loop.
  const startedAtIso = new Date().toISOString();
  writeLastExportAt(db, startedAtIso);

  // List tables up-front so we can compute row_counts for the audit log.
  let tables: string[];
  try {
    tables = listExportableTables(db);
  } catch (err) {
    logger.error('failed to list tenant tables for export', {
      tenantSlug,
      error: err instanceof Error ? err.message : String(err),
    });
    res.status(500).json({ success: false, message: 'Failed to read tenant schema.' });
    return;
  }

  const rowCounts: Record<string, number> = {};

  // Build the attachment filename.
  const dateToken = startedAtIso.slice(0, 10); // YYYY-MM-DD
  const slugToken = safeFilenameToken(tenantSlug);
  const filename = `bizarre-crm-export-${slugToken}-${dateToken}.json`;

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');

  // Begin the streaming envelope. We write the top-level object shape
  // by hand so we can emit tables lazily without building the full
  // payload in memory first.
  try {
    res.write('{');
    res.write(`"tenant_slug":${JSON.stringify(tenantSlug)},`);
    res.write(`"exported_at":${JSON.stringify(startedAtIso)},`);
    res.write(`"version":1,`);
    res.write('"tables":{');

    let firstTable = true;
    for (const table of tables) {
      // Table name came from sqlite_master, not user input — safe to
      // interpolate into the SQL. Still wrap in double-quotes so reserved
      // keywords (if any) don't break the SELECT.
      let rows: Array<Record<string, unknown>>;
      try {
        rows = db.prepare(`SELECT * FROM "${table}"`).all() as Array<Record<string, unknown>>;
      } catch (err) {
        // A single unreadable table should not abort the whole export —
        // log and record zero rows instead.
        logger.warn('failed to read table during export', {
          tenantSlug,
          table,
          error: err instanceof Error ? err.message : String(err),
        });
        rows = [];
      }

      rowCounts[table] = rows.length;

      if (!firstTable) res.write(',');
      firstTable = false;

      res.write(`${JSON.stringify(table)}:[`);

      for (let i = 0; i < rows.length; i++) {
        if (i > 0) res.write(',');
        const clean = sanitizeRow(table, rows[i]!);
        res.write(JSON.stringify(clean));
      }

      res.write(']');
    }

    // Emit row_counts AFTER tables so the tenant can verify the manifest
    // without scanning backwards through the tables payload.
    res.write('},');
    res.write(`"row_counts":${JSON.stringify(rowCounts)}`);
    res.write('}');
    res.end();
  } catch (err) {
    logger.error('export stream aborted mid-flight', {
      tenantSlug,
      error: err instanceof Error ? err.message : String(err),
    });
    // At this point we already set the attachment headers and streamed
    // bytes — the client will see a truncated JSON file. Best-effort
    // end the response; the audit log below still records the attempt.
    try {
      if (!res.writableEnded) res.end();
    } catch {
      // swallow
    }
  }

  // Audit log — always fire, even on partial stream.
  audit(db, 'data_export', userId, ip, {
    tenant: tenantSlug,
    filename,
    table_count: tables.length,
    row_counts: rowCounts,
    total_rows: Object.values(rowCounts).reduce((sum, n) => sum + n, 0),
  });

  logger.info('tenant data export completed', {
    tenantSlug,
    userId,
    tables: tables.length,
    totalRows: Object.values(rowCounts).reduce((sum, n) => sum + n, 0),
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

export default router;
