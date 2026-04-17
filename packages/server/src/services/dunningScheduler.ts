/**
 * Dunning scheduler — audit §52 idea 3, #17 dispatch wire-up.
 *
 * Walks every active dunning_sequence, finds invoices whose `due_date` is
 * `days_offset` days in the past, and records a `dunning_runs` row for each
 * before dispatching the associated SMS or email. The UNIQUE constraint on
 * (invoice_id, sequence_id, step_index) makes the whole run idempotent —
 * restarting the cron, or calling /dunning/run-now manually, can never
 * double-send a reminder.
 *
 * Wiring:
 *   Wired in `index.ts` inside an hourly trackInterval() loop that walks all
 *   active tenants serially and calls `runDunningOnce(tenantDb)` for each.
 *   The loop is guarded by `shouldRunDaily('dunning:<slug>', tenantTz)` so a
 *   given tenant sees AT MOST one evaluation per 24-hour window, independent
 *   of how often the outer interval ticks. Manual trigger is still available
 *   via `POST /api/v1/dunning/run-now` for operator-initiated runs.
 *
 * Rate limiting (three layers):
 *   1. `shouldRunDaily` in-memory guard (index.ts) — primary defense.
 *   2. `runDunningIfDue` durable 20h per-tenant guard — survives restart.
 *   3. `PER_INVOICE_MIN_GAP_MS` (20h) between dispatches to the SAME invoice
 *      regardless of sequence/step. Prevents a misconfigured sequence with
 *      two overlapping steps from spamming one customer.
 *
 * Dispatch (#17):
 *   `executeStep` now actually fires SMS/email through services/notifications
 *   primitives. On provider success the dunning_runs row is written with
 *   outcome='sent'. On failure it is written with outcome='failed' and
 *   error_reason captured in the summary warnings. This function returns a
 *   Promise — the caller MUST await.
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { sendSmsTenant } from './smsProvider.js';
import { sendEmail, isEmailConfigured } from './email.js';

const logger = createLogger('dunning');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DunningStep {
  days_offset: number;
  action: string;     // 'email' | 'sms' | 'call_queue' | 'escalate' | ...
  template_id?: string;
}

export interface DunningSummary {
  sequences_evaluated: number;
  /**
   * Steps that were successfully dispatched through the SMS / email
   * provider. On a happy-path run this is the primary counter operators
   * care about.
   */
  steps_dispatched: number;
  /**
   * Steps that were recorded but NOT actually dispatched — either because
   * the channel was disabled, the customer has no phone/email, or the step
   * action is a non-sending type such as `call_queue` / `escalate`. Callers
   * MUST treat this as "logged for reference, not sent".
   */
  steps_recorded_pending_dispatch: number;
  /**
   * Steps whose provider dispatch threw. A failure row is written to
   * dunning_runs so the UNIQUE constraint still prevents retries next tick;
   * operators can re-run after fixing the provider config and the row will
   * be re-dispatched only if they manually delete it.
   */
  steps_failed: number;
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

/**
 * Minimum elapsed time between two dunning step dispatches for the SAME
 * invoice. Defends against a misconfigured sequence with two overlapping
 * steps (e.g. days_offset=5 and days_offset=6) firing back-to-back. Also
 * stops a stuck cron that somehow bypasses the tenant-level 20h gate from
 * hammering one customer.
 */
const PER_INVOICE_MIN_GAP_MS = 20 * 60 * 60 * 1000;

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

/**
 * Return the timestamp (in ms) of the most recent dispatch for a given
 * invoice across every sequence. NULL if the invoice has never received
 * any step.
 */
function mostRecentInvoiceRunMs(
  db: Database.Database,
  invoiceId: number,
): number | null {
  try {
    const row = db
      .prepare(
        `SELECT MAX(executed_at) AS latest
           FROM dunning_runs
          WHERE invoice_id = ?`,
      )
      .get(invoiceId) as { latest: string | null } | undefined;
    if (!row?.latest) return null;
    const ms = new Date(row.latest).getTime();
    return Number.isFinite(ms) ? ms : null;
  } catch {
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

interface CustomerRow {
  id: number;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  mobile: string | null;
}

interface StoreConfigRow {
  key: string;
  value: string;
}

interface TemplateRow {
  id: number;
  event_key: string;
  subject: string | null;
  email_body: string | null;
  sms_body: string | null;
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

/**
 * Evaluate every active sequence once. Returns a summary counter object
 * suitable for logging + audit trails.
 *
 * ASYNC because the dispatch into services/notifications is async. The
 * eligibility scan itself is still synchronous (one shop has 100-200
 * overdue invoices at most) but we await provider calls in the loop.
 *
 * NOTE: This function does NOT enforce the per-tenant rate limit — it
 * always executes when called. The cron wrapper `runDunningIfDue()` is the
 * rate-limited variant; callers that want the guard (i.e. the background
 * cron in index.ts) should use that instead. `/dunning/run-now` keeps
 * calling this function directly so manual operator runs never get
 * silently suppressed.
 */
export async function runDunningOnce(
  db: Database.Database,
): Promise<DunningSummary> {
  const summary: DunningSummary = {
    sequences_evaluated: 0,
    steps_dispatched: 0,
    steps_recorded_pending_dispatch: 0,
    steps_failed: 0,
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

  // Load store config once per run for template interpolation (store_name,
  // store_phone, etc.). We read all relevant keys in a single query.
  const storeRows = db
    .prepare(
      `SELECT key, value
         FROM store_config
        WHERE key IN ('store_name', 'store_phone', 'store_website', 'store_address')`,
    )
    .all() as StoreConfigRow[];
  const storeConfig: Record<string, string> = {};
  for (const row of storeRows) storeConfig[row.key] = row.value;

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

      const cutoffIso = cutoffDateIso(step.days_offset, getTenantTimezone(db));

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

        // Per-invoice rate limit: skip if another step fired against this
        // invoice inside the minimum gap. We still want to record that we
        // looked at it — a `skipped` row blocks the UNIQUE constraint for
        // this step forever, which is correct: next tick will look at the
        // NEXT step.
        const lastInvoiceMs = mostRecentInvoiceRunMs(db, invoice.id);
        if (
          lastInvoiceMs !== null &&
          Date.now() - lastInvoiceMs < PER_INVOICE_MIN_GAP_MS
        ) {
          try {
            db.prepare(
              `INSERT INTO dunning_runs (invoice_id, sequence_id, step_index, outcome)
               VALUES (?, ?, ?, 'skipped_rate_limited')`,
            ).run(invoice.id, seq.id, stepIndex);
            summary.steps_skipped += 1;
          } catch {
            // UNIQUE collision — another worker already wrote this row.
          }
          continue;
        }

        const dispatchResult = await dispatchStep(
          db,
          step,
          invoice,
          storeConfig,
        );

        try {
          db.prepare(
            `INSERT INTO dunning_runs (invoice_id, sequence_id, step_index, outcome)
             VALUES (?, ?, ?, ?)`,
          ).run(invoice.id, seq.id, stepIndex, dispatchResult.outcome);

          switch (dispatchResult.outcome) {
            case 'sent':
              summary.steps_dispatched += 1;
              break;
            case 'pending_dispatch':
              summary.steps_recorded_pending_dispatch += 1;
              if (dispatchResult.warning) {
                summary.warnings.push(dispatchResult.warning);
              }
              break;
            case 'failed':
              summary.steps_failed += 1;
              summary.failures += 1;
              if (dispatchResult.warning) {
                summary.warnings.push(dispatchResult.warning);
              }
              break;
            case 'skipped':
              summary.steps_skipped += 1;
              break;
            default:
              summary.failures += 1;
          }
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
export async function runDunningIfDue(
  db: Database.Database,
): Promise<DunningSummary> {
  const lastMs = mostRecentRunMs(db);
  if (lastMs !== null && Date.now() - lastMs < DUNNING_MIN_GAP_MS) {
    logger.info('dunning run rate-limited by runDunningIfDue', {
      last_run_ms: lastMs,
      min_gap_ms: DUNNING_MIN_GAP_MS,
    });
    return {
      sequences_evaluated: 0,
      steps_dispatched: 0,
      steps_recorded_pending_dispatch: 0,
      steps_failed: 0,
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

/**
 * Return a YYYY-MM-DD string for (now - daysOffset) in the tenant's
 * configured timezone.
 *
 * SEC-M58: previously UTC-only. A tenant in America/Denver with an
 * invoice due on 2026-04-17 would see the dunning cutoff tick over
 * at 17:00 local (00:00 UTC next day), so a reminder for a 30-day
 * offset could fire 7 hours early / 7 hours late depending on DST.
 * Night sends are embarrassing — customer phones buzz at 11 PM when
 * the shop thought it was 6 PM. Using `en-CA` locale with `timeZone`
 * option gets us a clean `YYYY-MM-DD` in the target zone without
 * pulling in a date lib.
 */
function cutoffDateIso(daysOffset: number, timeZone: string): string {
  const ms = Date.now() - daysOffset * 24 * 60 * 60 * 1000;
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric', month: '2-digit', day: '2-digit',
    }).format(new Date(ms));
  } catch {
    // Bad tz string — fall back to UTC.
    return new Date(ms).toISOString().slice(0, 10);
  }
}

function getTenantTimezone(db: Database.Database): string {
  try {
    const row = db
      .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
      .get() as { value?: string } | undefined;
    return row?.value || 'UTC';
  } catch {
    return 'UTC';
  }
}

/**
 * Look up a template by `event_key` (the value stored as step.template_id
 * in dunning_sequences.steps_json). Returns undefined if the template is
 * missing — the caller falls back to a generic body so a misconfigured
 * template doesn't drop the customer reminder entirely.
 */
function loadTemplate(
  db: Database.Database,
  templateKey: string | undefined,
): TemplateRow | undefined {
  if (!templateKey) return undefined;
  try {
    return db
      .prepare(
        `SELECT id, event_key, subject, email_body, sms_body
           FROM notification_templates
          WHERE event_key = ?`,
      )
      .get(templateKey) as TemplateRow | undefined;
  } catch {
    return undefined;
  }
}

function loadCustomer(
  db: Database.Database,
  customerId: number,
): CustomerRow | undefined {
  if (!customerId) return undefined;
  try {
    return db
      .prepare(
        `SELECT id, first_name, last_name, email, phone, mobile
           FROM customers
          WHERE id = ?`,
      )
      .get(customerId) as CustomerRow | undefined;
  } catch {
    return undefined;
  }
}

/**
 * Render a template string by replacing `{variable}` placeholders with
 * safe values drawn from the invoice, customer, and store config. This is
 * a minimal renderer — we only support flat variable substitution, NOT
 * conditional blocks. More complex logic belongs in services/automations.
 */
function renderTemplate(
  template: string,
  vars: Record<string, string>,
): string {
  return template.replace(/\{(\w+(?:\.\w+)?)\}/g, (_match, key: string) => {
    const val = vars[key];
    return val !== undefined ? val : '';
  });
}

function buildTemplateVars(
  invoice: InvoiceRow,
  customer: CustomerRow | undefined,
  storeConfig: Record<string, string>,
): Record<string, string> {
  const firstName = customer?.first_name ?? 'Customer';
  const lastName = customer?.last_name ?? '';
  const customerName = `${firstName} ${lastName}`.trim() || 'Customer';
  const amountDue = Number(invoice.amount_due ?? 0).toFixed(2);
  return {
    customer_name: customerName,
    'customer.first_name': firstName,
    'customer.last_name': lastName,
    invoice_id: invoice.order_id,
    'invoice.order_id': invoice.order_id,
    amount_due: amountDue,
    due_on: invoice.due_date ?? '',
    store_name: storeConfig.store_name || 'our shop',
    store_phone: storeConfig.store_phone || '',
  };
}

/**
 * Pick the best phone for SMS. Customers can have a `mobile` AND a `phone`
 * — we prefer mobile for reminder texts.
 */
function pickSmsPhone(customer: CustomerRow | undefined): string | null {
  if (!customer) return null;
  return customer.mobile || customer.phone || null;
}

// ---------------------------------------------------------------------------
// dispatchStep — the real send
// ---------------------------------------------------------------------------

type DispatchOutcome =
  | 'sent'
  | 'failed'
  | 'skipped'
  | 'pending_dispatch';

interface DispatchResult {
  outcome: DispatchOutcome;
  /** A one-line explanation surfaced to operators when outcome != 'sent'. */
  warning?: string;
}

/**
 * Dispatch one dunning step for one invoice. Handles SMS via
 * sendSmsTenant, email via sendEmail, and leaves call_queue / escalate
 * as non-dispatch placeholders so admin workflows can pick them up later.
 *
 * Never throws. All provider errors are caught and surfaced as a
 * `failed` outcome plus a warning string — the caller decides how to
 * aggregate them. A throw here would abort the whole tenant's dunning run
 * and leave later invoices stranded.
 */
async function dispatchStep(
  db: Database.Database,
  step: DunningStep,
  invoice: InvoiceRow,
  storeConfig: Record<string, string>,
): Promise<DispatchResult> {
  const action = (step.action || '').toLowerCase();

  // Non-sending actions — operator handles manually.
  if (action === 'call_queue' || action === 'escalate') {
    logger.info('dunning step is non-dispatch action — recorded only', {
      invoice_id: invoice.id,
      order_id: invoice.order_id,
      action,
    });
    return {
      outcome: 'pending_dispatch',
      warning: `Step action '${action}' is non-dispatch; admin must follow up manually.`,
    };
  }

  if (action !== 'sms' && action !== 'email') {
    return {
      outcome: 'pending_dispatch',
      warning: `Unknown dunning action '${step.action}' — step recorded but not dispatched.`,
    };
  }

  const customer = loadCustomer(db, invoice.customer_id);
  if (!customer) {
    return {
      outcome: 'failed',
      warning: `Invoice ${invoice.order_id}: customer ${invoice.customer_id} not found.`,
    };
  }

  const template = loadTemplate(db, step.template_id);
  const vars = buildTemplateVars(invoice, customer, storeConfig);

  if (action === 'sms') {
    const phone = pickSmsPhone(customer);
    if (!phone) {
      return {
        outcome: 'failed',
        warning: `Invoice ${invoice.order_id}: customer has no phone on file.`,
      };
    }

    // Prefer the template sms_body; fall back to a minimal built-in message.
    const bodyTemplate =
      template?.sms_body ??
      'Hi {customer_name}, this is {store_name}. Your invoice {invoice_id} ' +
        'for ${amount_due} is overdue. Please call {store_phone} to resolve.';
    const body = renderTemplate(bodyTemplate, vars);

    try {
      // Tenant slug is not known inside this worker — pass null and let
      // getProviderForDb derive the provider config from the tenant DB.
      const result = await sendSmsTenant(db as any, null, phone, body);
      if (!result || (result as any).success === false) {
        const reason =
          (result as any)?.error || 'provider returned failure';
        return {
          outcome: 'failed',
          warning: `SMS dispatch failed for ${invoice.order_id}: ${reason}`,
        };
      }
      logger.info('dunning SMS dispatched', {
        invoice_id: invoice.id,
        order_id: invoice.order_id,
        to_phone_mask: phone.slice(-4),
      });
      return { outcome: 'sent' };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('dunning SMS dispatch threw', {
        invoice_id: invoice.id,
        order_id: invoice.order_id,
        error: msg,
      });
      return {
        outcome: 'failed',
        warning: `SMS dispatch failed for ${invoice.order_id}: ${msg}`,
      };
    }
  }

  // action === 'email'
  if (!customer.email) {
    return {
      outcome: 'failed',
      warning: `Invoice ${invoice.order_id}: customer has no email on file.`,
    };
  }

  if (!isEmailConfigured(db)) {
    return {
      outcome: 'pending_dispatch',
      warning: `Email for ${invoice.order_id} recorded but SMTP is not configured.`,
    };
  }

  const subjectTemplate =
    template?.subject || 'Invoice {invoice_id} is overdue';
  const bodyTemplate =
    template?.email_body ||
    '<p>Hi {customer_name},</p>' +
      '<p>Your invoice <strong>{invoice_id}</strong> for ${amount_due} ' +
      'is overdue. Please pay at your earliest convenience.</p>' +
      '<p>— {store_name}</p>';
  const subject = renderTemplate(subjectTemplate, vars);
  const html = renderTemplate(bodyTemplate, vars);

  try {
    const sent = await sendEmail(db, {
      to: customer.email,
      subject,
      html,
    });
    if (!sent) {
      return {
        outcome: 'failed',
        warning: `Email dispatch returned false for ${invoice.order_id}.`,
      };
    }
    logger.info('dunning email dispatched', {
      invoice_id: invoice.id,
      order_id: invoice.order_id,
      to: customer.email,
    });
    return { outcome: 'sent' };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.error('dunning email dispatch threw', {
      invoice_id: invoice.id,
      order_id: invoice.order_id,
      error: msg,
    });
    return {
      outcome: 'failed',
      warning: `Email dispatch failed for ${invoice.order_id}: ${msg}`,
    };
  }
}
