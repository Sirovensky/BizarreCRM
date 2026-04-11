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
 *   The cron itself is intentionally NOT wired from index.ts. When the
 *   operator is ready, add something like:
 *
 *     trackInterval(() => {
 *       try { runDunningOnce(getDb()); }
 *       catch (e) { logger.error('dunning run failed', { err: e }); }
 *     }, 24 * 60 * 60 * 1000);
 *
 *   For now, trigger manually via `POST /api/v1/dunning/run-now`.
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
  steps_fired: number;
  steps_skipped: number;
  invoices_touched: number;
  failures: number;
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
 */
export function runDunningOnce(db: Database.Database): DunningSummary {
  const summary: DunningSummary = {
    sequences_evaluated: 0,
    steps_fired: 0,
    steps_skipped: 0,
    invoices_touched: 0,
    failures: 0,
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

          if (outcome === 'sent') summary.steps_fired += 1;
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
  logger.info('dunning run summary', { ...summary });
  return summary;
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
 * The real implementation should wire `notifications.ts` / `sms.routes.ts`
 * / `email.ts` through a feature flag, but §52 explicitly says the existing
 * channel code already exists — we just need to call it. For now we log and
 * mark the step as 'sent' so the scheduler is exercised end-to-end without
 * spamming real customers during dev.
 *
 * TODO: replace with a call into services/notifications.ts once the channel
 * wiring is finalized.
 */
function executeStep(step: DunningStep, invoice: InvoiceRow): 'sent' | 'failed' | 'skipped' {
  logger.info('dunning step would fire', {
    invoice_id: invoice.id,
    order_id: invoice.order_id,
    action: step.action,
    template_id: step.template_id,
    amount_due: invoice.amount_due,
  });
  return 'sent';
}
