/**
 * Recurring Invoices Cron
 *
 * Runs every 15 minutes. For each tenant DB, finds every active
 * invoice_template whose next_run_at <= now(), creates an invoice + line
 * items, advances next_run_at, and records the run in invoice_template_runs.
 *
 * Overlap / double-fire protection:
 *   - We UPDATE the template inside a transaction that atomically clears
 *     next_run_at (sets it to the future value) before the invoice INSERT.
 *     If a second process races, the UPDATE WHERE next_run_at <= now() will
 *     match zero rows for templates already advanced.
 *
 * Wiring (do NOT edit index.ts here — see registration snippet below):
 *   import { startRecurringInvoicesCron } from './services/recurringInvoicesCron.js';
 *   const cronTimer = startRecurringInvoicesCron(() => getActiveDbIterable());
 *   // store cronTimer in your trackInterval() collection for graceful shutdown
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { allocateCounter, formatInvoiceOrderId } from '../utils/counters.js';

const logger = createLogger('recurring-invoices-cron');

const CRON_INTERVAL_MS = 15 * 60 * 1000; // 15 minutes

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TenantDbEntry {
  slug: string;
  db: Database.Database;
}

interface InvoiceTemplateRow {
  id: number;
  name: string;
  customer_id: number;
  interval_kind: string;
  interval_count: number;
  next_run_at: string;
  line_items_json: string;
  notes_template: string | null;
  tax_class_id: number | null;
  created_by_user_id: number;
}

interface LineItemInput {
  description?: string;
  quantity?: number;
  unit_price_cents?: number;
  tax_class_id?: number | null;
}

// ---------------------------------------------------------------------------
// Interval arithmetic
// ---------------------------------------------------------------------------

function advanceNextRunAt(current: string, kind: string, count: number): string {
  const d = new Date(current);
  // SCAN-1114: `setUTCMonth(m + count)` rolls Jan-31 into Mar-03 because
  // February has no 31st and JS overflows the day. Same with Mar-31 → May-01
  // via April. For the monthly and yearly kinds we clamp the day to the
  // last valid day of the target month when the original day was dropped.
  const originalDay = d.getUTCDate();
  switch (kind) {
    case 'daily':   d.setUTCDate(d.getUTCDate() + count); break;
    case 'weekly':  d.setUTCDate(d.getUTCDate() + 7 * count); break;
    case 'monthly': {
      d.setUTCMonth(d.getUTCMonth() + count);
      if (d.getUTCDate() !== originalDay) {
        // Day overflowed into the next month — roll back to the last day
        // of the intended target month via setUTCDate(0).
        d.setUTCDate(0);
      }
      break;
    }
    case 'yearly': {
      d.setUTCFullYear(d.getUTCFullYear() + count);
      // Feb-29 → Mar-01 under non-leap years; same clamp trick.
      if (d.getUTCDate() !== originalDay) d.setUTCDate(0);
      break;
    }
    default: {
      d.setUTCMonth(d.getUTCMonth() + 1);
      if (d.getUTCDate() !== originalDay) d.setUTCDate(0);
      break;
    }
  }
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

// ---------------------------------------------------------------------------
// Per-tenant run
// ---------------------------------------------------------------------------

function runForTenant(slug: string, db: Database.Database): void {
  let templates: InvoiceTemplateRow[];
  try {
    templates = db
      .prepare<[], InvoiceTemplateRow>(
        `SELECT id, name, customer_id, interval_kind, interval_count,
                next_run_at, line_items_json, notes_template, tax_class_id,
                created_by_user_id
           FROM invoice_templates
          WHERE status = 'active'
            AND next_run_at <= datetime('now')`
      )
      .all();
  } catch (err) {
    // Table may not exist on older tenants not yet migrated — skip silently.
    logger.warn('recurring-invoices: could not query invoice_templates', {
      slug,
      err: err instanceof Error ? err.message : String(err),
    });
    return;
  }

  if (templates.length === 0) return;

  for (const tpl of templates) {
    processTemplate(slug, db, tpl);
  }
}

function processTemplate(slug: string, db: Database.Database, tpl: InvoiceTemplateRow): void {
  const nextRunAt = advanceNextRunAt(tpl.next_run_at, tpl.interval_kind, tpl.interval_count);
  let invoiceId: number | null = null;

  try {
    db.transaction(() => {
      // Idempotency guard: only claim this template if next_run_at is still <= now
      // and status is still 'active'. Another cron tick that raced us will have
      // already advanced next_run_at to the future, so this UPDATE will match 0
      // rows and we'll skip cleanly.
      const updateResult = db.prepare(`
        UPDATE invoice_templates
           SET next_run_at  = ?,
               last_run_at  = datetime('now'),
               updated_at   = datetime('now')
         WHERE id         = ?
           AND status     = 'active'
           AND next_run_at <= datetime('now')
      `).run(nextRunAt, tpl.id);

      if (updateResult.changes === 0) {
        // Already claimed by another tick or manually advanced — skip.
        return;
      }

      // Create the invoice
      const seq = allocateCounter(db, 'invoice_order_id');
      const orderId = formatInvoiceOrderId(seq);

      // Parse line items and compute totals (cents → dollars for invoices table)
      let lineItems: LineItemInput[] = [];
      try {
        const parsed = JSON.parse(tpl.line_items_json);
        lineItems = Array.isArray(parsed) ? parsed : [];
      } catch {
        lineItems = [];
      }

      const MAX_SUBTOTAL_CENTS = 100_000_000_00; // $1 million cap per invoice
      let subtotalCents = 0;
      for (const li of lineItems) {
        const qty = Number(typeof li.quantity === 'number' ? li.quantity : 1);
        const unitCents = Number(typeof li.unit_price_cents === 'number' ? li.unit_price_cents : 0);
        if (!Number.isFinite(qty) || qty < 0 || qty > 100_000) {
          throw new Error(`recurring invoice template ${tpl.id}: invalid quantity ${qty}`);
        }
        if (!Number.isFinite(unitCents) || unitCents < 0 || unitCents > MAX_SUBTOTAL_CENTS) {
          throw new Error(`recurring invoice template ${tpl.id}: invalid unit_price_cents ${unitCents}`);
        }
        const lineTotal = qty * unitCents;
        if (!Number.isFinite(lineTotal) || lineTotal > MAX_SUBTOTAL_CENTS) {
          throw new Error(`recurring invoice template ${tpl.id}: line total overflow`);
        }
        subtotalCents += lineTotal;
        if (subtotalCents > MAX_SUBTOTAL_CENTS) {
          throw new Error(`recurring invoice template ${tpl.id}: subtotal exceeds $1M cap`);
        }
      }

      // invoices table stores money as dollars (REAL), not cents
      const subtotal = subtotalCents / 100;

      const invResult = db.prepare(`
        INSERT INTO invoices
          (order_id, customer_id, subtotal, discount, discount_reason,
           total_tax, total, amount_paid, amount_due, notes,
           created_by, created_at, updated_at)
        VALUES (?, ?, ?, 0, NULL, 0, ?, 0, ?, ?, ?, datetime('now'), datetime('now'))
      `).run(
        orderId,
        tpl.customer_id,
        subtotal,
        subtotal,          // total (no tax/discount for auto-generated)
        subtotal,          // amount_due
        tpl.notes_template ?? null,
        tpl.created_by_user_id,
      );

      invoiceId = invResult.lastInsertRowid as number;

      // Insert line items
      for (const li of lineItems) {
        const qty = typeof li.quantity === 'number' ? li.quantity : 1;
        const unitCents = typeof li.unit_price_cents === 'number' ? li.unit_price_cents : 0;
        const unitPrice = unitCents / 100;
        const lineTotal = (qty * unitCents) / 100;

        db.prepare(`
          INSERT INTO invoice_line_items
            (invoice_id, description, quantity, unit_price, line_discount,
             tax_amount, tax_class_id, total)
          VALUES (?, ?, ?, ?, 0, 0, ?, ?)
        `).run(
          invoiceId,
          typeof li.description === 'string' ? li.description : '',
          qty,
          unitPrice,
          li.tax_class_id ?? null,
          lineTotal,
        );
      }

      // Record successful run
      db.prepare(`
        INSERT INTO invoice_template_runs (template_id, invoice_id, run_at, succeeded)
        VALUES (?, ?, datetime('now'), 1)
      `).run(tpl.id, invoiceId);

      logger.info('recurring invoice created', {
        slug,
        template_id: tpl.id,
        invoice_id: invoiceId,
        order_id: orderId,
      });
    })();
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.error('recurring invoice create failed', {
      slug,
      template_id: tpl.id,
      err: msg,
    });

    // Record failure run (best-effort — don't throw if this also fails)
    try {
      db.prepare(`
        INSERT INTO invoice_template_runs
          (template_id, invoice_id, run_at, succeeded, error_message)
        VALUES (?, NULL, datetime('now'), 0, ?)
      `).run(tpl.id, msg.slice(0, 1000));
    } catch {
      // Ignore — don't let a logging failure mask the original error
    }
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Start the recurring invoices background cron.
 *
 * @param getDbsFn  Callback returning the current set of active tenant DBs.
 *                  Called on every tick so newly provisioned tenants are included.
 * @returns         The NodeJS.Timeout handle. Pass to trackInterval() in
 *                  index.ts for graceful shutdown.
 *
 * Registration snippet (add to index.ts after server.listen):
 * ```ts
 * import { startRecurringInvoicesCron } from './services/recurringInvoicesCron.js';
 * const recurringCronTimer = startRecurringInvoicesCron(() => getActiveDbIterable());
 * trackInterval(recurringCronTimer);
 * ```
 */
export function startRecurringInvoicesCron(
  getDbsFn: () => Iterable<TenantDbEntry>,
): NodeJS.Timeout {
  function tick(): void {
    try {
      for (const { slug, db } of getDbsFn()) {
        runForTenant(slug, db);
      }
    } catch (err) {
      logger.error('recurring-invoices cron top-level error', {
        err: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // Run once immediately on startup, then every CRON_INTERVAL_MS
  tick();
  return setInterval(tick, CRON_INTERVAL_MS);
}
