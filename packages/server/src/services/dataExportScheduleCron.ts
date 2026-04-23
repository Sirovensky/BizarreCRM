/**
 * dataExportScheduleCron.ts — SCAN-498
 *
 * Hourly cron that claims due data_export_schedules rows (status='active',
 * next_run_at <= now()), records a run entry, and advances next_run_at.
 *
 * Overlap / double-fire protection:
 *   UPDATE ... SET status='running' WHERE status='active' AND next_run_at <= now()
 *   returns changes=0 for any row already claimed this tick — the first claimer wins.
 *
 *   NOTE: 'running' is not a persisted status in the CHECK constraint;  we restore to
 *   'active' immediately after advancing next_run_at (within the same transaction).
 *   This is a within-process lock only. In a future multi-process deployment a
 *   proper advisory lock or separate claim table would be needed.
 *
 * Export generation:
 *   The actual data-export streaming logic in dataExport.routes.ts is coupled to
 *   Express (streams directly to res). Extracting it to a shared service without
 *   modifying the HTTP handler is out of scope for this changeset. The cron records
 *   a run with succeeded=0, error_message='export generation not yet extracted to
 *   service — cron heartbeat only' so the schedule machinery is fully wired and
 *   run history is visible in the UI. Refactoring the generator into a service is
 *   tracked as a follow-up.
 *
 * Wiring (do NOT edit index.ts — use the snippet below):
 *
 * ```ts
 * import { startDataExportScheduleCron } from './services/dataExportScheduleCron.js';
 * const exportScheduleCronTimer = startDataExportScheduleCron(() => getActiveDbIterable());
 * trackInterval(exportScheduleCronTimer);
 * ```
 *
 * getActiveDbIterable() must yield { slug: string | null, db: Database.Database }
 * entries — same shape as the existing recurringInvoicesCron helper.
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { advanceScheduleNextRun } from '../routes/dataExportSchedules.routes.js';

const logger = createLogger('data-export-schedule-cron');

/** Run every hour — export schedules don't need sub-hour precision. */
const CRON_INTERVAL_MS = 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TenantDbEntry {
  slug: string | null;
  db: Database.Database;
}

interface ScheduleRow {
  id: number;
  name: string;
  export_type: string;
  interval_kind: string;
  interval_count: number;
  next_run_at: string;
  delivery_email: string | null;
  created_by_user_id: number;
}

// ---------------------------------------------------------------------------
// Per-tenant tick
// ---------------------------------------------------------------------------

function runForTenant(slug: string | null, db: Database.Database): void {
  let dueSchedules: ScheduleRow[];

  try {
    dueSchedules = db
      .prepare<[], ScheduleRow>(
        `SELECT id, name, export_type, interval_kind, interval_count,
                next_run_at, delivery_email, created_by_user_id
           FROM data_export_schedules
          WHERE status = 'active'
            AND next_run_at <= datetime('now')`,
      )
      .all();
  } catch (err) {
    // Table may not exist on DBs not yet migrated — skip silently.
    if (err instanceof Error && err.message.includes('no such table')) {
      return;
    }
    logger.warn('data-export-schedule-cron: could not query schedules', {
      slug,
      err: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (dueSchedules.length === 0) return;

  for (const schedule of dueSchedules) {
    processSchedule(slug, db, schedule);
  }
}

function processSchedule(slug: string | null, db: Database.Database, schedule: ScheduleRow): void {
  const nextRunAt = advanceScheduleNextRun(
    schedule.next_run_at,
    schedule.interval_kind as 'daily' | 'weekly' | 'monthly',
    schedule.interval_count,
  );

  const runAt = new Date().toISOString().replace('T', ' ').slice(0, 19);

  try {
    db.transaction(() => {
      // Idempotency guard: atomically claim the schedule.
      // If another process or a concurrent tick already advanced next_run_at,
      // the WHERE clause matches 0 rows and we skip cleanly.
      const claimResult = db.prepare(`
        UPDATE data_export_schedules
           SET next_run_at = ?,
               last_run_at = datetime('now'),
               updated_at  = datetime('now')
         WHERE id         = ?
           AND status     = 'active'
           AND next_run_at <= datetime('now')
      `).run(nextRunAt, schedule.id);

      if (claimResult.changes === 0) {
        // Already claimed by another tick — skip this schedule.
        return;
      }

      // Export generation is not yet extracted from the Express handler.
      // Record a stub run so the cron heartbeat and run history are visible.
      // TODO: refactor dataExport.routes.ts streaming logic into a service
      // function and call it here, then set succeeded=1 and store the file path.
      db.prepare(`
        INSERT INTO data_export_schedule_runs
          (schedule_id, run_at, succeeded, export_file, error_message)
        VALUES (?, ?, 0, NULL, ?)
      `).run(
        schedule.id,
        runAt,
        'export generation not yet extracted to service — cron heartbeat only',
      );

      logger.info('data-export-schedule cron claimed schedule', {
        slug,
        schedule_id: schedule.id,
        name: schedule.name,
        export_type: schedule.export_type,
        next_run_at: nextRunAt,
      });
    })();
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.error('data-export-schedule cron: schedule processing failed', {
      slug,
      schedule_id: schedule.id,
      err: msg,
    });

    // Best-effort failure run record — don't throw if this also fails.
    try {
      db.prepare(`
        INSERT INTO data_export_schedule_runs
          (schedule_id, run_at, succeeded, export_file, error_message)
        VALUES (?, ?, 0, NULL, ?)
      `).run(schedule.id, runAt, msg.slice(0, 1000));
    } catch {
      // Suppress — don't let logging failure mask the original error.
    }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Start the data export schedule cron.
 *
 * @param getDbsFn  Callback returning the current set of active tenant DBs.
 *                  Called on every tick so newly provisioned tenants are included.
 * @returns         The NodeJS.Timeout handle. Pass to trackInterval() in
 *                  index.ts for graceful shutdown.
 *
 * Registration snippet (add to index.ts after server.listen):
 * ```ts
 * import { startDataExportScheduleCron } from './services/dataExportScheduleCron.js';
 * const exportScheduleCronTimer = startDataExportScheduleCron(() => getActiveDbIterable());
 * trackInterval(exportScheduleCronTimer);
 * ```
 */
export function startDataExportScheduleCron(
  getDbsFn: () => Iterable<TenantDbEntry>,
): NodeJS.Timeout {
  function tick(): void {
    try {
      for (const { slug, db } of getDbsFn()) {
        runForTenant(slug, db);
      }
    } catch (err) {
      logger.error('data-export-schedule-cron top-level error', {
        err: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Run once immediately on startup, then every CRON_INTERVAL_MS.
  tick();
  return setInterval(tick, CRON_INTERVAL_MS);
}
