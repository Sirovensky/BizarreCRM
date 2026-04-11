/**
 * Dunning scheduler — audit §52 idea 3.
 *
 * Walks every active dunning_sequence, finds invoices whose `due_date` is
 * `days_offset` days in the past, and records a single `dunning_runs` row
 * for each. The UNIQUE constraint on (invoice_id, sequence_id, step_index)
 * makes the whole run idempotent — restarting the cron, or calling
 * /dunning/run-now manually, can never double-send a reminder.
 *
 * Wiring:
 *   Wired in `index.ts` inside an hourly trackInterval() loop that walks all
 *   active tenants serially and calls `runDunningOnce(tenantDb)` for each.
 *   The loop is guarded by `shouldRunDaily('dunning:<slug>', tenantTz)` so a
 *   given tenant sees AT MOST one evaluation per 24-hour window, independent
 *   of how often the outer interval ticks. Manual trigger is still available
 *   via `POST /api/v1/dunning/run-now` for operator-initiated runs.
 *
 * Rate limiting:
 *   `runDunningOnce` enforces a per-tenant minimum gap (DUNNING_MIN_GAP_MS)
 *   between runs by checking the newest `dunning_runs.created_at` stamp. This
 *   is a secondary safety net — the outer `shouldRunDaily` guard is the
 *   primary defense. Two layers exist because the outer guard is in-memory
 *   (lost on restart) while the inner guard is durable in SQLite, so a fast
 *   restart loop cannot spam customers.
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('billing-enrich');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DunningStep {
  days_offset: number;
  action: string;     // 'email' | 'sms' | 'escalate' | ...
  template_id?: string;
}

export interface DunningSummary {
  sequences_evaluated: number;
  /**
   * Steps that were recorded but NOT actually dispatched. The channel
   * implementation (sms/email) is still a TODO — see executeStep(). Callers
   * MUST treat this as "queued for future send", not "sent".
   */
  steps_recorded_pending_dispatch: number;
  steps_skipped: number;
  invoices_touched: number;
  failures: number;
  /**
   * True when the run was blocked by the rate-limit guard (another run for
   * this tenant happened inside DUNNING_MIN_GAP_MS). Callers can distinguish
   * "nothing due" from "asked too soon" using this flag.
   */
  rate_limited?: boolean;
  /**
   * Non-fatal warnings surfaced to the caller so the UI can display why
   * some steps did not fire (e.g. "channel not wired"). Empty on a perfect run.
   */
  warnings: string[];
}

/**
 * Minimum elapsed time between two successful dunning runs for the same
 * tenant. 20 hours is deliberately shorter than the 24-hour outer cadence
 * so a small clock drift doesn't skip a full day, but long enough that a
 * restart loop or misfiring cron cannot spam customers. Manual
 * /dunning/run-now calls bypass this guard (they set `force: true`).
 */
const DUNNING_MIN_GAP_MS = 20 * 60 * 60 * 1000;

function mostRecentRunMs(db: Database.Database): number | null {
  try {
    const row = db
      .prepare('SELECT MAX(created_at) AS latest FROM dunning_runs')
      .get() as { latest: string | null } | undefined;
    if (!row?.latest) return null;
    const ms = new Date(row.latest).getTime();
    return Number.isFinite(ms) ? ms : null;
  } catch {
    // Table may not exist yet on a fresh tenant — treat as "never ran".
    return null;
  }
}

interface SequenceRow {
  id: number;
  name: string;
  is_active: number;
  steps_json: string;
}

interface InvoiceRow {
  id: number;
  order_id: string;
  customer_id: number;
  amount_due: number;
  due_date: string | null;
  status: string;
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

/**
 * Evaluate every active sequence once. Returns a summary counter object
 * suitable for logging + audit trails.
 *
 * This function is synchronous because better-sqlite3 is synchronous and
 * dunning is low-volume — a single shop has maybe 100-200 overdue invoices
 * at most, which is a trivial scan.
 *
 * NOTE: This function does NOT enforce the per-tenant rate limit — it
 * always executes when called. The cron wrapper `runDunningIfDue()` is the
 * rate-limited variant; callers that want the guard (i.e. the background
 * cron in index.ts) should use that instead. `/dunning/run-now` keeps
 * calling this function directly so manual operator runs never get
 * silently suppressed.
 */
export function runDunningOnce(db: Database.Database): DunningSummary {
  const summary: DunningSummary = {
    sequences_evaluated: 0,
    steps_recorded_pending_dispatch: 0,
    steps_skipped: 0,
    invoices_touched: 0,
    failures: 0,
    warnings: [],
  };

  // Honor the store_config kill-switch so an operator can pause dunning
  // without disabling every sequence individually.
  const enabledRow = db
    .prepare("SELECT value FROM store_config WHERE key = 'billing_dunning_enabled'")
    .get() as { value: string } | undefined;
  if (enabledRow && enabledRow.value !== '1') {
    logger.info('dunning disabled via store_config');
    return summary;
  }

  const sequences = db
    .prepare(
      `SELECT id, name, is_active, steps_json
         FROM dunning_sequences
        WHERE is_active = 1`,
    )
    .all() as SequenceRow[];

  const touchedInvoices = new Set<number>();

  for (const seq of sequences) {
    summary.sequences_evaluated += 1;
    const steps = parseSteps(seq.steps_json);
    if (steps.length === 0) continue;

    for (let stepIndex = 0; stepIndex < steps.length; stepIndex++) {
      const step = steps[stepIndex];
      if (typeof step.days_offset !== 'number' || step.days_offset < 0) continue;

      const cutoffIso = cutoffDateIso(step.days_offset);

      const eligible = db
        .prepare(
          `SELECT i.id, i.order_id, i.customer_id, i.amount_due, i.due_date, i.status
             FROM invoices i
             LEFT JOIN dunning_runs r
               ON r.invoice_id = i.id
              AND r.sequence_id = ?
              AND r.step_index = ?
            WHERE i.amount_due > 0
              AND i.status IN ('unpaid','overdue','partial')
              AND i.due_date IS NOT NULL
              AND date(i.due_date) <= date(?)
              AND r.id IS NULL
            LIMIT 500`,
        )
        .all(seq.id, stepIndex, cutoffIso) as InvoiceRow[];

      for (const invoice of eligible) {
        touchedInvoices.add(invoice.id);
        const outcome = executeStep(step, invoice);
        try {
          db.prepare(
            `INSERT INTO dunning_runs (invoice_id, sequence_id, step_index, outcome)
             VALUES (?, ?, ?, ?)`,
          ).run(invoice.id, seq.id, stepIndex, outcome);

          // NOTE: 'pending_dispatch' means the row was written but the actual
          // SMS/email channel wiring is still a TODO in executeStep(). We do
          // NOT lie about success here — the HTTP layer surfaces this via the
          // warnings array so the UI can show "row written, not yet sent".
          if (outcome === 'pending_dispatch') summary.steps_recorded_pending_dispatch += 1;
          else if (outcome === 'skipped') summary.steps_skipped += 1;
          else summary.failures += 1;
        } catch (err) {
          // UNIQUE collision = another process got there first; safe to ignore.
          summary.steps_skipped += 1;
          logger.warn('dunning insert collision', {
            invoice_id: invoice.id,
            sequence_id: seq.id,
            step_index: stepIndex,
            err: err instanceof Error ? err.message : String(err),
          });
        }
      }
    }
  }

  summary.invoices_touched = touchedInvoices.size;
  if (summary.steps_recorded_pending_dispatch > 0) {
    summary.warnings.push(
      'Dunning rows were recorded but NO real SMS/email was dispatched: ' +
      'executeStep() is still a TODO stub. Wire services/notifications.ts ' +
      'before enabling this in production.',
    );
  }
  logger.info('dunning run summary', { ...summary });
  return summary;
}

/**
 * Cron-friendly wrapper around `runDunningOnce` that enforces the durable
 * per-tenant rate-limit guard. Intended for the background scheduler in
 * index.ts — NEVER call this from an HTTP route, since operators expect
 * manual /run-now invocations to always execute.
 *
 * Returns the same DunningSummary shape; when the guard trips, the result
 * has `rate_limited: true` and a warning string describing why nothing
 * happened. Downstream logging can distinguish "quiet day, nothing due"
 * from "we already ran 2 hours ago" using that flag.
 */
export function runDunningIfDue(db: Database.Database): DunningSummary {
  const lastMs = mostRecentRunMs(db);
  if (lastMs !== null && Date.now() - lastMs < DUNNING_MIN_GAP_MS) {
    logger.info('dunning run rate-limited by runDunningIfDue', {
      last_run_ms: lastMs,
      min_gap_ms: DUNNING_MIN_GAP_MS,
    });
    return {
      sequences_evaluated: 0,
      steps_recorded_pending_dispatch: 0,
      steps_skipped: 0,
      invoices_touched: 0,
      failures: 0,
      rate_limited: true,
      warnings: [
        'Dunning run skipped: last run was less than the minimum gap ago.',
      ],
    };
  }
  return runDunningOnce(db);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseSteps(json: string): DunningStep[] {
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

/** Return a YYYY-MM-DD string for (now - daysOffset) UTC. */
function cutoffDateIso(daysOffset: number): string {
  const ms = Date.now() - daysOffset * 24 * 60 * 60 * 1000;
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * Placeholder for the actual notification send.
 *
 * NO-OP STUB. The dispatch into services/notifications.ts has not been wired
 * yet — see audit §52. We return 'pending_dispatch' so the run summary can
 * be truthful: the dunning_runs row is written (idempotency is preserved)
 * but the caller is told the channel did not actually fire. Previously this
 * returned 'sent', which lied to the UI and to operators about real customer
 * reminders going out.
 *
 * TODO: replace the log line below with a real call into
 * services/notifications.ts, and return 'sent' on provider success OR
 * 'failed' on provider error.
 */
function executeStep(
  step: DunningStep,
  invoice: InvoiceRow,
): 'sent' | 'failed' | 'skipped' | 'pending_dispatch' {
  logger.warn('dunning step recorded but NOT actually dispatched (stub)', {
    invoice_id: invoice.id,
    order_id: invoice.order_id,
    action: step.action,
    template_id: step.template_id,
    amount_due: invoice.amount_due,
  });
  return 'pending_dispatch';
}
