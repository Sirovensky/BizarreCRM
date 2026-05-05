/**
 * SA7-1: Persistent import-job checkpoint store.
 *
 * Each long-running import service / script checkpoints its progress to the
 * `import_job_state` table in the tenant DB. On crash/restart the caller
 * reads the row, skips up to `last_processed_id`, and resumes.
 *
 * Usage pattern:
 *
 *   const jobId = buildJobId('repairdesk', 'tickets', tenantSlug);
 *   const state = resumeJobState(db, jobId, { total: rows.length, startFresh });
 *   for (const row of rows) {
 *     if (state.shouldSkip(row.source_id, rowIndex)) continue;
 *     db.transaction(() => {
 *       writeData(row);
 *       state.checkpoint({ step: rowIndex + 1, lastProcessedId: row.source_id });
 *     })();
 *   }
 *   state.complete();
 *
 * Contract:
 *   - `checkpoint` is called from inside a better-sqlite3 transaction that
 *     also does the data writes. That is what makes progress + writes
 *     atomic — partial work never survives a crash.
 *   - `resumeJobState` without `startFresh` returns whatever is stored.
 *     With `startFresh: true` it deletes the row and returns a zeroed
 *     state — operators pick one or the other via CLI flag.
 */

import type { Database as BetterSqlite3Database } from 'better-sqlite3';

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

export type ImportJobStatus =
  | 'pending'
  | 'running'
  | 'paused'
  | 'completed'
  | 'failed';

export interface ImportJobRow {
  readonly job_id: string;
  readonly step: number;
  readonly total: number;
  readonly last_processed_id: string | null;
  readonly status: ImportJobStatus;
  readonly last_error: string | null;
  readonly started_at: string;
  readonly updated_at: string;
}

export interface ResumeOptions {
  /** Total expected records if known. Defaults to 0 (unknown). */
  readonly total?: number;
  /** If true, delete any existing row and start from scratch. */
  readonly startFresh?: boolean;
}

export interface CheckpointArgs {
  /** Cumulative count of records processed (including skipped). */
  readonly step: number;
  /**
   * Cursor value — source id / page number / etc.
   * Anything stringifiable is accepted so callers can reuse page numbers.
   */
  readonly lastProcessedId: string | number | null;
}

/**
 * State handle returned by {@link resumeJobState}. All mutations go through
 * prepared statements bound to the db passed into `resumeJobState`.
 */
export interface ImportJobStateHandle {
  readonly jobId: string;
  readonly db: BetterSqlite3Database;

  /** Snapshot of the row as it was when `resumeJobState` was called. */
  readonly initialRow: ImportJobRow;

  /** True if we're continuing an older run (step > 0). */
  readonly resumed: boolean;

  /** Last checkpoint's step (monotonic — never decreases). */
  currentStep(): number;

  /** Last checkpoint's cursor (source_id / page). */
  currentCursor(): string | null;

  /**
   * Return true if a record should be skipped because we already
   * processed past it in a prior run. Pass whichever cursor form you
   * checkpointed — either the source id, or the row's zero-based index.
   */
  shouldSkip(recordId: string | number | null, rowIndex: number): boolean;

  /**
   * Update step + cursor atomically. MUST be called from inside a
   * better-sqlite3 transaction that also performs the data writes.
   * Callers that don't have a db-level transaction can still call this —
   * it will run in its own statement.
   */
  checkpoint(args: CheckpointArgs): void;

  /** Flip status to 'running' — optional marker for observability. */
  markRunning(): void;

  /** Flip status to 'paused' — used by Ctrl-C handlers. */
  markPaused(): void;

  /** Flip status to 'completed' and record the final step count. */
  complete(finalStep?: number): void;

  /** Flip status to 'failed' and record an error message. */
  fail(error: string): void;
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

/**
 * Build a stable job key. Keep the format consistent across services so
 * operators can grep the DB by tenant or by source.
 */
export function buildJobId(
  source: string,
  entity: string,
  tenantSlug: string = 'default',
): string {
  return `${source}:${entity}:${tenantSlug}`;
}

/**
 * Claim or resume a job row. Returns a handle with prepared statements
 * ready to go. Safe to call repeatedly — idempotent.
 */
export function resumeJobState(
  db: BetterSqlite3Database,
  jobId: string,
  options: ResumeOptions = {},
): ImportJobStateHandle {
  const { total = 0, startFresh = false } = options;

  if (startFresh) {
    db.prepare('DELETE FROM import_job_state WHERE job_id = ?').run(jobId);
  }

  const existing = readRow(db, jobId);

  if (!existing) {
    db.prepare(
      `INSERT INTO import_job_state
         (job_id, step, total, last_processed_id, status, last_error, started_at, updated_at)
       VALUES (?, 0, ?, NULL, 'pending', NULL, datetime('now'), datetime('now'))`,
    ).run(jobId, total);
  } else if (total > 0 && total !== existing.total) {
    // Total may refine between runs — update but don't disturb step/cursor.
    db.prepare(
      `UPDATE import_job_state SET total = ?, updated_at = datetime('now')
        WHERE job_id = ?`,
    ).run(total, jobId);
  }

  const initialRow = readRow(db, jobId);
  if (!initialRow) {
    // Insertion should always succeed — fail loud rather than returning a
    // silently-broken handle.
    throw new Error(`importJobState: failed to claim row for job_id=${jobId}`);
  }

  return createHandle(db, jobId, initialRow);
}

/**
 * Pure read — no claim, no mutation. Used by observability / status tools.
 */
export function readJobState(
  db: BetterSqlite3Database,
  jobId: string,
): ImportJobRow | null {
  return readRow(db, jobId);
}

/**
 * Delete a job's row entirely. Used by `--start-fresh` on CLI entry.
 * Separate from `resumeJobState({ startFresh: true })` so callers can
 * wipe without also recreating.
 */
export function wipeJobState(
  db: BetterSqlite3Database,
  jobId: string,
): void {
  db.prepare('DELETE FROM import_job_state WHERE job_id = ?').run(jobId);
}

// -----------------------------------------------------------------------------
// Internals
// -----------------------------------------------------------------------------

function readRow(
  db: BetterSqlite3Database,
  jobId: string,
): ImportJobRow | null {
  const row = db
    .prepare('SELECT * FROM import_job_state WHERE job_id = ?')
    .get(jobId) as ImportJobRow | undefined;
  return row ?? null;
}

function createHandle(
  db: BetterSqlite3Database,
  jobId: string,
  initialRow: ImportJobRow,
): ImportJobStateHandle {
  // Local mutable mirror — the DB remains the source of truth, we just
  // avoid a round-trip on every shouldSkip() call.
  let stepMirror = initialRow.step;
  let cursorMirror = initialRow.last_processed_id;

  const updateCheckpoint = db.prepare(
    `UPDATE import_job_state
        SET step = ?, last_processed_id = ?, updated_at = datetime('now')
      WHERE job_id = ?`,
  );
  const updateStatus = db.prepare(
    `UPDATE import_job_state
        SET status = ?, updated_at = datetime('now')
      WHERE job_id = ?`,
  );
  const updateComplete = db.prepare(
    `UPDATE import_job_state
        SET status = 'completed', step = ?, last_error = NULL,
            updated_at = datetime('now')
      WHERE job_id = ?`,
  );
  const updateFail = db.prepare(
    `UPDATE import_job_state
        SET status = 'failed', last_error = ?, updated_at = datetime('now')
      WHERE job_id = ?`,
  );

  return {
    jobId,
    db,
    initialRow,
    resumed: initialRow.step > 0,

    currentStep: () => stepMirror,
    currentCursor: () => cursorMirror,

    shouldSkip(recordId, rowIndex) {
      // First run (step=0) never skips.
      if (stepMirror <= 0) return false;
      // Prefer cursor-based skip if we have a recorded cursor AND the
      // caller supplied a comparable value.
      if (cursorMirror !== null && recordId !== null && recordId !== undefined) {
        // Both stringified for comparison — source ids from external APIs
        // come back as strings or numbers interchangeably.
        const cursorStr = String(cursorMirror);
        const idStr = String(recordId);
        // We skip when the row's cursor is <= stored cursor when we can
        // order them numerically; otherwise only equality.
        const cursorNum = Number(cursorStr);
        const idNum = Number(idStr);
        if (Number.isFinite(cursorNum) && Number.isFinite(idNum)) {
          return idNum <= cursorNum;
        }
        return idStr === cursorStr;
      }
      // Fallback: skip by zero-based index.
      return rowIndex < stepMirror;
    },

    checkpoint(args) {
      const nextStep = Math.max(args.step, stepMirror);
      const nextCursor =
        args.lastProcessedId === null || args.lastProcessedId === undefined
          ? cursorMirror
          : String(args.lastProcessedId);
      updateCheckpoint.run(nextStep, nextCursor, jobId);
      stepMirror = nextStep;
      cursorMirror = nextCursor;
    },

    markRunning() {
      updateStatus.run('running', jobId);
    },

    markPaused() {
      updateStatus.run('paused', jobId);
    },

    complete(finalStep) {
      const step = finalStep === undefined ? stepMirror : finalStep;
      updateComplete.run(step, jobId);
      stepMirror = step;
    },

    fail(error) {
      const truncated = error.length > 2000 ? error.slice(0, 2000) : error;
      updateFail.run(truncated, jobId);
    },
  };
}

// -----------------------------------------------------------------------------
// CLI helpers — shared across reimport-notes.ts / full-import.ts
// -----------------------------------------------------------------------------

export interface ResumeCliFlags {
  readonly resume: boolean;
  readonly startFresh: boolean;
}

/**
 * Parse `--resume` / `--start-fresh` (mutually exclusive) from argv.
 * Defaults: neither — behaves like --start-fresh to preserve backwards
 * compatibility with the original "always start from 0" behavior.
 */
export function parseResumeFlags(argv: readonly string[]): ResumeCliFlags {
  let resume = false;
  let startFresh = false;
  for (const arg of argv) {
    if (arg === '--resume') resume = true;
    else if (arg === '--start-fresh') startFresh = true;
  }
  if (resume && startFresh) {
    throw new Error('--resume and --start-fresh are mutually exclusive');
  }
  // If neither flag was passed we default to start-fresh so existing
  // operator muscle memory doesn't silently pick up stale state.
  if (!resume && !startFresh) startFresh = true;
  return { resume, startFresh };
}
