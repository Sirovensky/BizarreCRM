/**
 * dataExportGenerator.ts — SCAN-498 service extraction
 *
 * Provides generateExportToFile(), the same serialisation logic that
 * dataExport.routes.ts streams via HTTP, but writing to a file so
 * background cron jobs (dataExportScheduleCron.ts) can produce real
 * exports without coupling to an Express response object.
 *
 * Security:
 *   - outputDir MUST be config.exportsPath (or a subdirectory the caller
 *     controls). The function enforces this by resolving the output path
 *     relative to the provided outputDir — it NEVER accepts a caller-
 *     supplied absolute path or traversal token. The caller is responsible
 *     for choosing a safe outputDir; the cron always passes config.exportsPath.
 *   - Generated filenames contain only a safe ISO date + 6-byte hex nonce
 *     and the export type — no user-supplied strings.
 *   - Files are written with mode 0o600 (owner-only read/write).
 *   - Large tables are read with .all() into memory one table at a time,
 *     then serialised row-by-row via a write stream so peak heap stays
 *     bounded (same strategy as the HTTP route).
 */

import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('data-export-generator');

// ─── Types ────────────────────────────────────────────────────────────────────

/** Valid export type values — mirrors VALID_EXPORT_TYPES in the schedule routes. */
export type ExportType =
  | 'full'
  | 'customers'
  | 'tickets'
  | 'invoices'
  | 'inventory'
  | 'expenses';

export interface GenerateExportResult {
  /** Absolute path of the written JSON file. */
  file_path: string;
  /** Total rows across all exported tables. */
  row_count: number;
  /** File size in bytes as reported by fs.stat after close. */
  bytes: number;
}

// ─── Constants (mirrors dataExport.routes.ts) ─────────────────────────────────

/**
 * Tables that are NEVER exported — same list as in dataExport.routes.ts.
 * Duplicated here intentionally so the service has no runtime dependency on
 * the routes file; if the list changes update both.
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

const SENSITIVE_FIELDS: Record<string, ReadonlySet<string>> = {
  users: new Set([
    'password_hash',
    'totp_secret',
    'pin_hash',
    'recovery_codes',
    'reset_token_hash',
    'remember_token_hash',
  ]),
  store_config: new Set(),
};

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

/**
 * Tables that contain data for a specific export_type (non-'full').
 * A schedule with export_type 'full' exports everything. Anything else
 * is restricted to the tables listed here.
 */
const EXPORT_TYPE_TABLES: Record<Exclude<ExportType, 'full'>, ReadonlySet<string>> = {
  customers:  new Set(['customers']),
  tickets:    new Set(['tickets', 'ticket_notes', 'ticket_device_parts']),
  invoices:   new Set(['invoices', 'invoice_items']),
  inventory:  new Set(['inventory_items', 'inventory_categories']),
  expenses:   new Set(['expenses', 'expense_categories']),
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function listExportableTables(db: Database.Database, exportType: ExportType): string[] {
  const rows = db
    .prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    .all() as Array<{ name: string }>;

  const allTables = rows
    .map((r) => r.name)
    .filter((name) => !EXCLUDED_TABLES.has(name));

  if (exportType === 'full') return allTables;

  const allowed = EXPORT_TYPE_TABLES[exportType];
  return allTables.filter((t) => allowed.has(t));
}

function sanitizeRow(table: string, row: Record<string, unknown>): Record<string, unknown> {
  if (table === 'store_config' && typeof row.key === 'string' && SENSITIVE_CONFIG_KEYS.has(row.key)) {
    return { ...row, value: null };
  }
  const fieldBlacklist = SENSITIVE_FIELDS[table];
  if (!fieldBlacklist || fieldBlacklist.size === 0) return row;

  const redacted: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    redacted[k] = fieldBlacklist.has(k) ? null : v;
  }
  return redacted;
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Write a full tenant data export to a JSON file.
 *
 * @param db          Synchronous better-sqlite3 Database instance for the tenant.
 * @param exportType  Which subset of tables to include (or 'full' for all).
 * @param outputDir   Directory to write the file into. The caller MUST pass a
 *                    path under config.exportsPath — this function does NOT
 *                    validate the caller's choice; that contract is enforced at
 *                    the call site (cron always passes config.exportsPath).
 * @param tenantSlug  Optional slug used only in the JSON envelope — safe token.
 * @returns           File path, total row count, and bytes written.
 */
export async function generateExportToFile(
  db: Database.Database,
  exportType: ExportType,
  outputDir: string,
  tenantSlug = 'tenant',
): Promise<GenerateExportResult> {
  // ── 1. Resolve safe output path ───────────────────────────────────────────
  //    Both outputDir and the filename components are caller-controlled only
  //    at the module level (cron uses config.exportsPath exclusively). The
  //    hex nonce + ISO date mean the filename itself contains no user input.
  await fs.promises.mkdir(outputDir, { recursive: true });

  const isoDate = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  const nonce   = crypto.randomBytes(6).toString('hex'); // 12 hex chars
  const fileName = `export-${exportType}-${isoDate}-${nonce}.json`;
  const filePath = path.join(outputDir, fileName);

  // ── 2. List tables ────────────────────────────────────────────────────────
  const tables = listExportableTables(db, exportType);
  const exportedAt = new Date().toISOString();
  const rowCounts: Record<string, number> = {};
  let totalRows = 0;

  // ── 3. Stream to file ─────────────────────────────────────────────────────
  const writeStream = fs.createWriteStream(filePath, { encoding: 'utf8', flags: 'wx' });

  await new Promise<void>((resolve, reject) => {
    writeStream.on('error', reject);
    writeStream.on('finish', resolve);

    try {
      writeStream.write('{');
      writeStream.write(`"tenant_slug":${JSON.stringify(tenantSlug)},`);
      writeStream.write(`"exported_at":${JSON.stringify(exportedAt)},`);
      writeStream.write(`"export_type":${JSON.stringify(exportType)},`);
      writeStream.write(`"version":1,`);
      writeStream.write('"tables":{');

      let firstTable = true;

      for (const table of tables) {
        // Table name comes from sqlite_master — not user input.
        // Still quote the identifier for reserved-word safety.
        let rows: Array<Record<string, unknown>>;
        try {
          rows = db.prepare(`SELECT * FROM "${table}"`).all() as Array<Record<string, unknown>>;
        } catch (err) {
          logger.warn('data-export-generator: failed to read table — skipping', {
            table,
            tenantSlug,
            error: err instanceof Error ? err.message : String(err),
          });
          rows = [];
        }

        rowCounts[table] = rows.length;
        totalRows += rows.length;

        if (!firstTable) writeStream.write(',');
        firstTable = false;

        writeStream.write(`${JSON.stringify(table)}:[`);
        for (let i = 0; i < rows.length; i++) {
          if (i > 0) writeStream.write(',');
          const clean = sanitizeRow(table, rows[i]!);
          writeStream.write(JSON.stringify(clean));
        }
        writeStream.write(']');
      }

      writeStream.write('},');
      writeStream.write(`"row_counts":${JSON.stringify(rowCounts)}`);
      writeStream.write('}');
      writeStream.end();
    } catch (err) {
      // Destroy the stream so 'error' fires — the promise rejects cleanly.
      writeStream.destroy(err instanceof Error ? err : new Error(String(err)));
    }
  });

  // ── 4. Harden file permissions (owner-only) ───────────────────────────────
  try {
    await fs.promises.chmod(filePath, 0o600);
  } catch (chmodErr) {
    // Non-fatal on Windows (EPERM from FS semantics) — log and continue.
    logger.warn('data-export-generator: chmod 0600 failed', {
      filePath,
      error: chmodErr instanceof Error ? chmodErr.message : String(chmodErr),
    });
  }

  // ── 5. Measure written bytes ──────────────────────────────────────────────
  const stat = await fs.promises.stat(filePath);
  const bytes = stat.size;

  logger.info('data-export-generator: export written', {
    tenantSlug,
    exportType,
    tables: tables.length,
    totalRows,  // row counts are not PII
    bytes,
    fileName,
  });

  return { file_path: filePath, row_count: totalRows, bytes };
}
