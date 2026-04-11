/**
 * Retention sweeper — deletes old rows from unbounded log/queue tables.
 *
 * Audit issue #23: Multiple tables were growing forever because nothing ever
 * trimmed them. This module runs a per-table sweep using simple `DELETE ...
 * WHERE <date_column> < datetime('now', '-N days')` statements. It is called
 * once per tenant per day from the 2 AM cron block in `index.ts`.
 *
 * Design notes:
 *  - Retention-only, NOT cleanup: we never touch parent rows and never cascade.
 *    The target tables are all leaf logs / queues. If a FK constraint from a
 *    related table ever points at one of these, the sweep will fail loudly
 *    inside the per-rule try/catch and skip that table on the next pass —
 *    exactly the signal we want, rather than silent data corruption.
 *  - `audit_logs` is intentionally NOT in the rules list. Existing prod
 *    retention is handled by a separate block in `index.ts` and the audit
 *    policy (SEC-AL5) mandates ≥1 year. Do not re-add it here.
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
];

export interface RetentionSweepResult {
  /** Total rows deleted across all tables for this tenant. */
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

  return { totalDeleted, perTable };
}
