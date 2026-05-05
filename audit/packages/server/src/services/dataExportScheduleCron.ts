/**
 * dataExportScheduleCron.ts — SCAN-498
 *
 * Hourly cron that claims due data_export_schedules rows (status='active',
 * next_run_at <= now()), generates the export file via dataExportGenerator,
 * records a run entry with the real file path + byte count, and advances
 * next_run_at.
 *
 * Overlap / double-fire protection:
 *   UPDATE ... SET next_run_at = ? WHERE status='active' AND next_run_at <= now()
 *   returns changes=0 for any row already claimed this tick — the first claimer wins.
 *
 *   NOTE: This is a within-process lock only. In a future multi-process deployment a
 *   proper advisory lock or separate claim table would be needed.
 *
 * Email delivery:
 *   When delivery_email is set, a notification email is sent after a successful
 *   export using the tenant's SMTP config (services/email.ts). The email
 *   references the file by path; it does NOT attach the file (large JSON
 *   attachments would likely exceed SMTP size limits). A download link via
 *   a signed URL would require an additional endpoint; that is deferred — see
 *   TODO below.
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

import path from 'path';
import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { config } from '../config.js';
import { advanceScheduleNextRun } from '../routes/dataExportSchedules.routes.js';
import { generateExportToFile, type ExportType } from './dataExportGenerator.js';
import { sendEmail } from './email.js';

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

async function runForTenant(slug: string | null, db: Database.Database): Promise<void> {
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

  // Process schedules sequentially per tenant to avoid parallel DB writes.
  for (const schedule of dueSchedules) {
    await processSchedule(slug, db, schedule);
  }
}

async function processSchedule(slug: string | null, db: Database.Database, schedule: ScheduleRow): Promise<void> {
  const nextRunAt = advanceScheduleNextRun(
    schedule.next_run_at,
    schedule.interval_kind as 'daily' | 'weekly' | 'monthly',
    schedule.interval_count,
  );

  const runAt = new Date().toISOString().replace('T', ' ').slice(0, 19);

  // ── 1. Idempotency claim ────────────────────────────────────────────────
  // Atomically advance next_run_at. If another process already claimed this
  // row (changes=0) we skip cleanly with no run record.
  let claimed = false;
  try {
    const claimResult = db.prepare(`
      UPDATE data_export_schedules
         SET next_run_at = ?,
             last_run_at = datetime('now'),
             updated_at  = datetime('now')
       WHERE id         = ?
         AND status     = 'active'
         AND next_run_at <= datetime('now')
    `).run(nextRunAt, schedule.id);

    claimed = claimResult.changes > 0;
  } catch (err) {
    logger.error('data-export-schedule cron: claim query failed', {
      slug,
      schedule_id: schedule.id,
      err: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (!claimed) {
    // Already claimed by another tick — skip.
    return;
  }

  logger.info('data-export-schedule cron: claimed schedule, starting export', {
    slug,
    schedule_id: schedule.id,
    name: schedule.name,
    export_type: schedule.export_type,
    next_run_at: nextRunAt,
  });

  // ── 2. Generate the export file ─────────────────────────────────────────
  // outputDir is always config.exportsPath — never user-supplied.
  // Use a per-slug subdirectory so files from different tenants don't mix.
  const safeSlug = (slug ?? 'default').toLowerCase().replace(/[^a-z0-9-_]/g, '-').slice(0, 64);
  const outputDir = path.join(config.exportsPath, safeSlug);

  // Validate export_type before passing to the generator.
  const VALID_EXPORT_TYPES: ReadonlySet<string> = new Set([
    'full', 'customers', 'tickets', 'invoices', 'inventory', 'expenses',
  ]);
  const exportType: ExportType = VALID_EXPORT_TYPES.has(schedule.export_type)
    ? (schedule.export_type as ExportType)
    : 'full';

  let filePath: string | null = null;
  let rowCount = 0;
  let bytes = 0;
  let exportError: string | null = null;

  try {
    const result = await generateExportToFile(db, exportType, outputDir, safeSlug);
    filePath = result.file_path;
    rowCount = result.row_count;
    bytes = result.bytes;
  } catch (err) {
    exportError = err instanceof Error ? err.message : String(err);
    logger.error('data-export-schedule cron: export generation failed', {
      slug,
      schedule_id: schedule.id,
      export_type: exportType,
      err: exportError,
    });
  }

  // ── 3. Record run result ─────────────────────────────────────────────────
  const succeeded = exportError === null ? 1 : 0;

  try {
    db.prepare(`
      INSERT INTO data_export_schedule_runs
        (schedule_id, run_at, succeeded, export_file, error_message)
      VALUES (?, ?, ?, ?, ?)
    `).run(
      schedule.id,
      runAt,
      succeeded,
      filePath,
      exportError ? exportError.slice(0, 1000) : null,
    );
  } catch (err) {
    // Best-effort — don't let a logging failure mask the export result.
    logger.warn('data-export-schedule cron: failed to insert run record', {
      slug,
      schedule_id: schedule.id,
      err: err instanceof Error ? err.message : String(err),
    });
  }

  if (succeeded) {
    logger.info('data-export-schedule cron: export succeeded', {
      slug,
      schedule_id: schedule.id,
      export_type: exportType,
      rows: rowCount,   // counts only, no PII
      bytes,
    });
  }

  // ── 4. Delivery email (if configured) ───────────────────────────────────
  // TODO(CROSS): Add a signed download-link endpoint so the email can include
  // a link like /api/v1/data-export/downloads/<signed-token> rather than
  // just the raw file-system path. Until that endpoint exists, the email
  // contains the filename only (safe — no PII in the path).
  if (succeeded && schedule.delivery_email) {
    const fileName = filePath ? path.basename(filePath) : 'export.json';
    try {
      await sendEmail(db, {
        to: schedule.delivery_email,
        subject: `Data export ready — ${schedule.name}`,
        html: [
          `<p>Your scheduled data export "<strong>${schedule.name}</strong>" has completed.</p>`,
          `<ul>`,
          `<li>Export type: ${exportType}</li>`,
          `<li>Rows exported: ${rowCount.toLocaleString()}</li>`,
          `<li>File: ${fileName}</li>`,
          `</ul>`,
          `<p>Contact your administrator to retrieve the file from the server exports directory.</p>`,
        ].join(''),
      });
    } catch (emailErr) {
      // Email failure must NOT break the cron — log and continue.
      logger.warn('data-export-schedule cron: delivery email failed', {
        slug,
        schedule_id: schedule.id,
        err: emailErr instanceof Error ? emailErr.message : String(emailErr),
      });
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
  async function tick(): Promise<void> {
    try {
      for (const { slug, db } of getDbsFn()) {
        // Sequential across tenants — avoids thundering-herd on shared DB pool.
        await runForTenant(slug, db);
      }
    } catch (err) {
      logger.error('data-export-schedule-cron top-level error', {
        err: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Run once immediately on startup (fire-and-forget), then every CRON_INTERVAL_MS.
  void tick();
  return setInterval(() => { void tick(); }, CRON_INTERVAL_MS);
}
