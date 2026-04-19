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

import type { Database } from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

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

const DEFAULT_PII_MONTHS = 24;
const MIN_PII_MONTHS = 1;
const MAX_PII_MONTHS = 120; // 10 years — anything past this is almost certainly a typo.

export interface RetentionSweepResult {
  /** Total rows affected (deleted + redacted) across all tables for this tenant. */
  readonly totalDeleted: number;
  /** Per-table row counts — missing tables are simply omitted from the map. */
  readonly perTable: Readonly<Record<string, number>>;
}

/**
 * Returns true if the tenant has explicitly disabled retention sweeps via the
 * `retention_sweep_enabled` key in `store_config`. Missing row == enabled
 * (default-on), `'0'` == disabled, anything else == enabled.
 *
 * The sweep is intentionally default-on: operators opt out per tenant, they
 * don't have to opt in. Letting log tables grow unbounded is the bug we're
 * fixing; silent opt-in would preserve the bug.
 */
function isSweepDisabledForTenant(db: Database): boolean {
  try {
    const row = db
      .prepare("SELECT value FROM store_config WHERE key = 'retention_sweep_enabled'")
      .get() as { value?: string } | undefined;
    return row?.value === '0';
  } catch {
    // If store_config doesn't exist yet (fresh tenant, pre-seed), treat as
    // enabled. The sweep itself handles missing target tables gracefully.
    return false;
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
function applyRule(db: Database, rule: SweepRule): number {
  if (!tableExists(db, rule.table)) return 0;

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

  const months = readPiiRetentionMonths(db, rule.configKey);
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
export async function runRetentionSweep(db: Database): Promise<RetentionSweepResult> {
  if (isSweepDisabledForTenant(db)) {
    return { totalDeleted: 0, perTable: {} };
  }

  const perTable: Record<string, number> = {};
  let totalDeleted = 0;

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

  // SEC-H57: PII phase — runs after the ops-log phase so a failure in the
  // ops sweep cannot skip the (arguably more important) compliance-driven
  // PII retention. Each PII rule is individually isolated for the same
  // reason as the ops loop.
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

  return { totalDeleted, perTable };
}
