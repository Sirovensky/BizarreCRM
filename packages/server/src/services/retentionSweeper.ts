/**
 * Retention sweeper — deletes old rows from unbounded log/queue tables and
 * enforces PII retention windows for customer communications.
 *
 * Audit issue #23 (original): Multiple log/queue tables were growing forever
 * because nothing ever trimmed them. The RULES array handles those — simple
 * `DELETE ... WHERE <date_column> < datetime('now', '-N days')` per table.
 *
 * Audit issue SEC-H57 / P3-PII-08 (added 2026-04-17): Customer communications
 * tables (`sms_messages`, `call_logs`, `email_messages`, `ticket_notes`) were
 * unbounded too, but they're PII, not ops telemetry. GDPR / CCPA require a
 * stated retention purpose. A new second phase in this module enforces a
 * 24-month (tenant-configurable) retention window on those four tables:
 *
 *   * sms_messages / call_logs / email_messages: DELETE (the message IS the
 *     record — redacting the body leaves an orphan row nobody can use).
 *   * ticket_notes: REDACT (blank `content`, stamp `redacted_at`). We keep
 *     the row because ticket_notes.parent_id is a self-FK and deleting a
 *     parent would cascade-orphan replies, and because the audit trail
 *     (who/when) still has operational value even after the body is gone.
 *
 * Each non-zero PII batch writes a single `audit_logs` breadcrumb so
 * compliance has a paper trail without a row-per-deleted-row explosion.
 *
 * Design notes:
 *  - Retention-only, NOT cleanup: we never touch parent rows and never cascade.
 *    The target tables are all leaf logs / queues / comms. If a FK constraint
 *    from a related table ever points at one of these, the sweep will fail
 *    loudly inside the per-rule try/catch and skip that table on the next
 *    pass — exactly the signal we want, rather than silent data corruption.
 *  - `audit_logs` is intentionally NOT in any of the sweep lists. Existing
 *    prod retention is handled by a separate block in `index.ts` and the
 *    audit policy (SEC-AL5) mandates >=1 year. Do not re-add it here.
 *  - `cost_price_history` / `catalog_price_history` are indefinite retention
 *    by product decision and are also excluded.
 *  - Every rule runs inside its own try/catch so a missing column, schema
 *    drift, or a locked row on one table cannot abort the sweep for the rest.
 *  - Tables that don't exist yet (fresh tenant, mid-migration) are skipped
 *    silently via a `sqlite_master` probe — no noisy errors in that case.
 */

import fs from 'fs';
import path from 'path';
import type { Database } from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { sweepOldExports } from './tenantExport.js';

const logger = createLogger('retentionSweeper');

interface SweepRule {
  /** Physical table name to sweep. */
  readonly table: string;
  /** Column used to decide age. Must be an ISO-8601 / SQLite datetime string. */
  readonly dateColumn: string;
  /** How many days of history to keep. Anything older is deleted. */
  readonly retentionDays: number;
  /**
   * Optional extra WHERE clause (already safe — we control this literal, no
   * user input is interpolated anywhere in this file). Used for notifications
   * where we only want to purge terminal states and not in-flight rows.
   */
  readonly whereExtra?: string;
}

/**
 * Rule table: one entry per target log/queue table. Adding a new table here is
 * a one-line change — update this array and the hourly cron will pick it up on
 * the next 2 AM run.
 *
 * Ordering is deterministic (not alphabetical) so the log output follows a
 * stable, reviewable sequence during post-mortems.
 */
const RULES: readonly SweepRule[] = [
  { table: 'automation_run_log', dateColumn: 'created_at', retentionDays: 90 },
  { table: 'webhook_delivery_failures', dateColumn: 'created_at', retentionDays: 30 },
  { table: 'rate_limits', dateColumn: 'first_attempt', retentionDays: 1 },
  { table: 'sms_retry_queue', dateColumn: 'created_at', retentionDays: 14 },
  {
    table: 'notification_queue',
    dateColumn: 'created_at',
    retentionDays: 14,
    // Only purge terminal states. In-flight rows (queued/sending/retrying)
    // must NOT be swept or we'd drop messages that are about to be delivered.
    whereExtra: "status IN ('sent','failed','cancelled')",
  },
  { table: 'notification_retry_queue', dateColumn: 'created_at', retentionDays: 30 },
  { table: 'report_snapshots', dateColumn: 'created_at', retentionDays: 365 },
  { table: 'import_rate_limits', dateColumn: 'first_attempt', retentionDays: 7 },
  // SEC-H71: idempotency keys are only needed within the replay window (24 h).
  // Rows with response_status IS NULL (abandoned in-flight requests) are also
  // swept here rather than accumulating forever.
  { table: 'idempotency_keys', dateColumn: 'created_at', retentionDays: 1 },
];

/**
 * SEC-H57: PII retention rules. Separate from `RULES` because:
 *   (1) window is configured per-tenant via `store_config` (not hardcoded);
 *   (2) the unit is months, not days, to match how customer-data retention
 *       is usually stated in privacy policies (and to avoid humans doing
 *       `24*30` math in their head when reading the UI);
 *   (3) `ticket_notes` uses REDACT semantics, not DELETE, so the code path
 *       diverges from the simple DELETE loop above.
 *
 * The default of 24 months is baked in here AND seeded into store_config via
 * migration 108 — the hardcoded default is the safety net for older tenants
 * that predate the migration or for any tenant where the row somehow gets
 * deleted. `Number.isFinite` + range clamp prevents a corrupted config value
 * from turning the sweep into either a no-op (months=0 → delete everything
 * newer than now, i.e. nothing older) or a runaway.
 */
interface PiiRule {
  readonly table: string;
  readonly dateColumn: string;
  readonly configKey: string;
  readonly mode: 'delete' | 'redact';
  /** Only used when mode === 'redact'. Column to blank out. */
  readonly redactColumn?: string;
}

const PII_RULES: readonly PiiRule[] = [
  { table: 'sms_messages', dateColumn: 'created_at', configKey: 'retention_sms_months', mode: 'delete' },
  { table: 'call_logs', dateColumn: 'created_at', configKey: 'retention_calls_months', mode: 'delete' },
  { table: 'email_messages', dateColumn: 'created_at', configKey: 'retention_email_months', mode: 'delete' },
  {
    table: 'ticket_notes',
    dateColumn: 'created_at',
    configKey: 'retention_ticket_notes_months',
    mode: 'redact',
    redactColumn: 'content',
  },
];

// Default-OFF policy: no deletion unless the operator explicitly opts in.
// Shop owners on a self-hosted single-tenant install often want to keep
// data forever (small repair shop with finite customer count, no GDPR
// pressure). Setting an aggressive default makes the system feel hostile
// — operators want to be in charge of their own data lifecycle.
// 0 = disabled / no deletion (canonical "infinite retention" sentinel).
const DEFAULT_PII_MONTHS = 0;
// SCAN-1136 / SCAN-1132: 0 is the valid sentinel meaning "disabled for
// this table" — also the new default. Negative values get clamped to 0
// so a fat-fingered `-1` doesn't wipe the table on the next run.
const MIN_PII_MONTHS = 0;
const MAX_PII_MONTHS = 120; // 10 years — anything past this is almost certainly a typo.

/**
 * SEC-H58: Unlink on-disk files for `ticket_photos` rows whose parent ticket
 * has been closed for more than 12 months.
 *
 * Join path: ticket_photos → ticket_devices → tickets → ticket_statuses.is_closed.
 * The 12-month window uses `tickets.updated_at` (the last status-change timestamp).
 *
 * On-disk path formula (mirrors tickets.routes.ts):
 *   <uploadsPath>/<tenantSlug>/<photo.file_path>
 *
 * One `audit_logs` row is written per non-zero batch with {rows_deleted, bytes_freed}.
 * ENOENT on unlink is silently swallowed (file already gone); all other unlink
 * errors are logged per-file and the sweep continues.
 *
 * @param db          - Tenant SQLite database (better-sqlite3, synchronous).
 * @param uploadsPath - Absolute path to the root uploads directory (config.uploadsPath).
 * @param tenantSlug  - Tenant slug string (empty string for single-tenant installs).
 * @returns           Number of `ticket_photos` rows deleted from the database.
 */
function sweepClosedTicketPhotos(
  db: Database,
  uploadsPath: string,
  tenantSlug: string,
): number {
  if (!tableExists(db, 'ticket_photos')) return 0;
  if (!tableExists(db, 'ticket_devices')) return 0;
  if (!tableExists(db, 'tickets')) return 0;
  if (!tableExists(db, 'ticket_statuses')) return 0;

  interface PhotoRow {
    id: number;
    file_path: string;
  }

  let photos: PhotoRow[];
  try {
    photos = db.prepare(`
      SELECT tp.id, tp.file_path
      FROM ticket_photos tp
      JOIN ticket_devices td ON td.id = tp.ticket_device_id
      JOIN tickets t         ON t.id  = td.ticket_id
      JOIN ticket_statuses s ON s.id  = t.status_id
      WHERE s.is_closed = 1
        AND t.updated_at < datetime('now', '-12 months')
    `).all() as PhotoRow[];
  } catch (err) {
    logger.error('sweepClosedTicketPhotos: query failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }

  if (photos.length === 0) return 0;

  const uploadsBase = tenantSlug
    ? path.join(uploadsPath, tenantSlug)
    : uploadsPath;

  let rowsDeleted = 0;
  let bytesFreed = 0;

  // Resolve the base once so the containment check below is cheap.
  const resolvedBase = path.resolve(uploadsBase);

  for (const photo of photos) {
    const absPath = path.resolve(path.join(uploadsBase, photo.file_path));

    // SEC: Guard against a path-traversal escape stored in file_path.
    // If the resolved path doesn't sit under uploadsBase, skip and log — never
    // unlink arbitrary filesystem locations.
    if (!absPath.startsWith(resolvedBase + path.sep) && absPath !== resolvedBase) {
      logger.error('sweepClosedTicketPhotos: path traversal rejected', {
        photoId: photo.id,
        filePath: photo.file_path,
      });
      continue;
    }

    // Measure size before unlink so we can report bytes_freed even if the
    // stat call fails (we log and continue rather than aborting the batch).
    let fileSize = 0;
    try {
      const stat = fs.statSync(absPath);
      fileSize = stat.size;
    } catch {
      // File already gone or inaccessible — proceed to DB cleanup anyway.
    }

    try {
      fs.unlinkSync(absPath);
      bytesFreed += fileSize;
    } catch (err: unknown) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== 'ENOENT') {
        logger.error('sweepClosedTicketPhotos: unlink failed', {
          photoId: photo.id,
          filePath: photo.file_path,
          error: err instanceof Error ? err.message : String(err),
        });
        // Do NOT delete the DB row when we could not remove the file — a
        // stray reference is better than a deleted row pointing to a live file.
        continue;
      }
      // ENOENT: already gone — fall through to delete the DB row.
    }

    try {
      db.prepare('DELETE FROM ticket_photos WHERE id = ?').run(photo.id);
      rowsDeleted++;
    } catch (err) {
      logger.error('sweepClosedTicketPhotos: DB delete failed', {
        photoId: photo.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Audit breadcrumb — only when something was actually removed.
  if (rowsDeleted > 0 && tableExists(db, 'audit_logs')) {
    try {
      const details = JSON.stringify({
        rows_deleted: rowsDeleted,
        bytes_freed: bytesFreed,
        ran_at: new Date().toISOString(),
      });
      db.prepare(
        'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, NULL, ?, ?)',
      ).run('retention_sweep_ticket_photos', 'system', details);
    } catch (err) {
      logger.error('sweepClosedTicketPhotos: audit write failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  return rowsDeleted;
}

export interface RetentionSweepResult {
  /** Total rows affected (deleted + redacted) across all tables for this tenant. */
  readonly totalDeleted: number;
  /** Per-table row counts — missing tables are simply omitted from the map. */
  readonly perTable: Readonly<Record<string, number>>;
}

/**
 * Returns true if retention sweeps are disabled for this tenant. Default-OFF
 * policy: missing row == disabled. Operator must explicitly opt IN by setting
 * `retention_sweep_enabled = '1'`.
 *
 * Rationale: shop owners want to control their own data lifecycle. A small
 * repair shop with 200 customers/year doesn't need GDPR-grade purges by
 * default — they want history. The retention UI lets owners turn this on
 * if/when they need to comply with a specific privacy regime or storage
 * cap.
 */
function isSweepDisabledForTenant(db: Database): boolean {
  try {
    const row = db
      .prepare("SELECT value FROM store_config WHERE key = 'retention_sweep_enabled'")
      .get() as { value?: string } | undefined;
    // Only `'1'` enables the sweep. Missing row, '0', or anything else = disabled.
    return row?.value !== '1';
  } catch {
    // If store_config doesn't exist yet (fresh tenant, pre-seed), treat as
    // disabled — owner hasn't had a chance to opt in.
    return true;
  }
}

/**
 * Checks whether a table exists in this SQLite database. Cheap — single
 * indexed lookup against `sqlite_master`.
 */
function tableExists(db: Database, table: string): boolean {
  const row = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name = ?")
    .get(table) as { name?: string } | undefined;
  return !!row?.name;
}

/**
 * Checks whether a specific column exists on a table. Used to gracefully
 * skip the ticket_notes redaction path when migration 108 hasn't run yet on
 * this tenant (fresh tenant, mid-provision, or post-restore reconciliation).
 */
function columnExists(db: Database, table: string, column: string): boolean {
  try {
    const rows = db.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name?: string }>;
    return rows.some((r) => r.name === column);
  } catch {
    return false;
  }
}

/**
 * Read a PII retention window from `store_config`, falling back to the 24mo
 * default. Clamped to [MIN_PII_MONTHS, MAX_PII_MONTHS] so a fat-fingered admin
 * setting of "0" or "99999" cannot either (a) wipe the entire table on the
 * next run or (b) silently disable the sweep.
 *
 * Returns months as a positive integer.
 */
function readPiiRetentionMonths(db: Database, configKey: string): number {
  try {
    const row = db
      .prepare('SELECT value FROM store_config WHERE key = ?')
      .get(configKey) as { value?: string } | undefined;
    const parsed = row?.value !== undefined ? Number.parseInt(row.value, 10) : NaN;
    if (!Number.isFinite(parsed) || parsed < MIN_PII_MONTHS) {
      return DEFAULT_PII_MONTHS;
    }
    if (parsed > MAX_PII_MONTHS) return MAX_PII_MONTHS;
    return parsed;
  } catch {
    return DEFAULT_PII_MONTHS;
  }
}

/**
 * Write a single audit_logs breadcrumb row for a PII retention batch. The
 * event is a fixed literal; details carry the per-batch metrics. Failures
 * here are swallowed (we already did the underlying work; an audit write
 * failure should not throw us out of the sweep loop and abort remaining
 * tables).
 */
function writeRetentionAudit(
  db: Database,
  table: string,
  mode: 'delete' | 'redact',
  rowsAffected: number,
  retentionMonths: number,
): void {
  if (rowsAffected === 0) return;
  if (!tableExists(db, 'audit_logs')) return;
  try {
    const details = JSON.stringify({
      table,
      mode,
      rows_affected: rowsAffected,
      retention_months: retentionMonths,
      ran_at: new Date().toISOString(),
    });
    db.prepare(
      'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, NULL, ?, ?)',
    ).run('retention_sweep_pii', 'system', details);
  } catch (err) {
    logger.error('retention sweep audit write failed', {
      table,
      mode,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Apply a single sweep rule. Isolated so one bad rule can't poison the loop.
 * Returns the number of rows deleted, or 0 if the table doesn't exist / the
 * rule failed (failures are logged, not thrown).
 */
// Defense-in-depth allowlist: every SQL identifier we splice into a retention
// query must match this pattern. The RULES array is static today but adding
// the assert here means a future maintainer who sources rule config from
// elsewhere can't accidentally open a SQL-injection vector via table/column
// name interpolation.
const SQL_IDENT_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
function assertSqlIdent(name: string, field: string): void {
  if (!SQL_IDENT_RE.test(name)) {
    throw new Error(`retentionSweeper: rejected non-identifier ${field}: ${name}`);
  }
}

function applyRule(db: Database, rule: SweepRule): number {
  if (!tableExists(db, rule.table)) return 0;

  // Identifier allowlist (SCAN-1057) — see comment on assertSqlIdent.
  assertSqlIdent(rule.table, 'table');
  assertSqlIdent(rule.dateColumn, 'dateColumn');

  // `retentionDays` is an integer baked into the RULES array — never user
  // input — so interpolating it into the SQL is safe. SQLite requires the
  // modifier string to be a literal, not a parameter, hence the template.
  const cutoff = `datetime('now', '-${rule.retentionDays} days')`;
  const whereExtra = rule.whereExtra ? ` AND ${rule.whereExtra}` : '';
  const sql = `DELETE FROM ${rule.table} WHERE ${rule.dateColumn} < ${cutoff}${whereExtra}`;

  const result = db.prepare(sql).run();
  return result.changes ?? 0;
}

/**
 * Apply a single PII retention rule. For `delete` mode this is a plain
 * `DELETE` with the per-tenant cutoff. For `redact` mode it runs an `UPDATE`
 * that blanks the content column and stamps `redacted_at` — the row survives
 * for FK integrity + audit. Both modes write an `audit_logs` breadcrumb on
 * non-zero batches.
 *
 * Returns rows affected, or 0 on skip / failure.
 */
function applyPiiRule(db: Database, rule: PiiRule): number {
  if (!tableExists(db, rule.table)) return 0;

  // Identifier allowlist (SCAN-1057).
  assertSqlIdent(rule.table, 'table');
  assertSqlIdent(rule.dateColumn, 'dateColumn');
  if (rule.redactColumn) assertSqlIdent(rule.redactColumn, 'redactColumn');

  const months = readPiiRetentionMonths(db, rule.configKey);
  // SCAN-1132 / SCAN-1136: per-table disable — operators who want to keep
  // (say) ticket_notes indefinitely while still sweeping other tables can
  // set the tenant's store_config for this rule's key to `0`. Skip both
  // the DELETE and redact branches; return 0 rows touched.
  if (months === 0) return 0;
  // `months` is already validated + clamped by readPiiRetentionMonths, so
  // interpolating it into the SQL modifier literal is safe.
  const cutoff = `datetime('now', '-${months} months')`;

  if (rule.mode === 'delete') {
    const sql = `DELETE FROM ${rule.table} WHERE ${rule.dateColumn} < ${cutoff}`;
    const result = db.prepare(sql).run();
    const changes = result.changes ?? 0;
    writeRetentionAudit(db, rule.table, 'delete', changes, months);
    return changes;
  }

  // redact mode — ticket_notes only for now.
  if (!rule.redactColumn) return 0;
  // If migration 108 hasn't been applied to this tenant yet (no redacted_at
  // column), skip rather than half-redact. The next sweep picks it up once
  // migration runs on tenant startup.
  if (!columnExists(db, rule.table, 'redacted_at')) return 0;

  const sql =
    `UPDATE ${rule.table} SET ${rule.redactColumn} = '', redacted_at = datetime('now') ` +
    `WHERE ${rule.dateColumn} < ${cutoff} AND redacted_at IS NULL`;
  const result = db.prepare(sql).run();
  const changes = result.changes ?? 0;
  writeRetentionAudit(db, rule.table, 'redact', changes, months);
  return changes;
}

/**
 * Run the full retention sweep for a single tenant database.
 *
 * Callers should pass one tenant DB per invocation — the function does NOT
 * iterate tenants. That responsibility belongs to the cron wiring in
 * `index.ts`, which uses `forEachDbAsync` so one slow tenant cannot block the
 * others.
 *
 * This is async so the caller can `await` it inside an async `forEachDbAsync`
 * loop. The body is synchronous (better-sqlite3 is sync) — there's no actual
 * I/O concurrency to gain, but the async signature keeps the cron wiring
 * shape consistent with the other tenant-scoped jobs in the server.
 */
export async function runRetentionSweep(
  db: Database,
  uploadsPath?: string,
  tenantSlug?: string,
): Promise<RetentionSweepResult> {
  // Master switch (`retention_sweep_enabled`) gates ONLY customer-data
  // sweeps — PII tables, ticket photos, tenant exports. Operational
  // hygiene (rate_limits, idempotency_keys, retry queues, etc.) runs
  // always: those tables fill up by design and must be capped to keep
  // the indexes sane. The owner's "keep customer data forever" choice
  // doesn't extend to "let internal queues balloon."
  const piiSweepEnabled = !isSweepDisabledForTenant(db);

  const perTable: Record<string, number> = {};
  let totalDeleted = 0;

  // Phase 1: operational hygiene — always runs.
  for (const rule of RULES) {
    try {
      const deleted = applyRule(db, rule);
      if (deleted > 0) {
        perTable[rule.table] = deleted;
        totalDeleted += deleted;
        // Only log when we actually deleted something — a no-op sweep on a
        // quiet tenant should not spam the logs every night.
        logger.info(`retention sweep ${rule.table}: ${deleted} rows deleted`, {
          table: rule.table,
          retentionDays: rule.retentionDays,
          deleted,
        });
      }
    } catch (err) {
      // One bad table must not abort the rest. Log with enough context to
      // debug (which rule, which table, what error) and move on.
      logger.error(`retention sweep failed for ${rule.table}`, {
        table: rule.table,
        retentionDays: rule.retentionDays,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Phase 2: customer-data PII sweep — gated by master switch.
  // SEC-H57: PII phase — runs after the ops-log phase so a failure in the
  // ops sweep cannot skip the (arguably more important) compliance-driven
  // PII retention. Each PII rule is individually isolated for the same
  // reason as the ops loop.
  if (!piiSweepEnabled) {
    return { totalDeleted, perTable };
  }
  for (const rule of PII_RULES) {
    try {
      const affected = applyPiiRule(db, rule);
      if (affected > 0) {
        perTable[rule.table] = affected;
        totalDeleted += affected;
        // verb: "deleted" for delete mode, "redacted" for redact mode.
        const verb = rule.mode === 'delete' ? 'deleted' : 'redacted';
        logger.info(`retention sweep ${rule.table}: ${affected} rows ${verb}`, {
          table: rule.table,
          mode: rule.mode,
          affected,
        });
      }
    } catch (err) {
      logger.error(`PII retention sweep failed for ${rule.table}`, {
        table: rule.table,
        mode: rule.mode,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // SEC-H58: Photo retention — unlink on-disk files for closed tickets > 12 months.
  // Runs last so a file-system error cannot abort the DB-only phases above.
  // Only attempted when the caller supplied an uploadsPath (cron wiring in index.ts
  // always does; callers that omit it — e.g. unit tests — skip this phase cleanly).
  if (uploadsPath !== undefined) {
    try {
      const photoDeleted = sweepClosedTicketPhotos(db, uploadsPath, tenantSlug ?? '');
      if (photoDeleted > 0) {
        perTable['ticket_photos'] = photoDeleted;
        totalDeleted += photoDeleted;
        logger.info(`retention sweep ticket_photos: ${photoDeleted} photos unlinked`, {
          table: 'ticket_photos',
          deleted: photoDeleted,
        });
      }
    } catch (err) {
      logger.error('retention sweep failed for ticket_photos', {
        table: 'ticket_photos',
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // SEC-H59: Tenant export retention — delete .enc export files + DB rows older
  // than 7 days. Runs after photo retention so a filesystem error in the upload
  // sweep cannot skip this compliance-driven cleanup. sweepOldExports is async
  // (fsp.unlink) but this function is already async, so we await it.
  try {
    const exportDeleted = await sweepOldExports(db);
    if (exportDeleted > 0) {
      perTable['tenant_exports'] = exportDeleted;
      totalDeleted += exportDeleted;
      logger.info(`retention sweep tenant_exports: ${exportDeleted} export records deleted`, {
        table: 'tenant_exports',
        deleted: exportDeleted,
      });
    }
  } catch (err) {
    logger.error('retention sweep failed for tenant_exports', {
      table: 'tenant_exports',
      error: err instanceof Error ? err.message : String(err),
    });
  }

  return { totalDeleted, perTable };
}
