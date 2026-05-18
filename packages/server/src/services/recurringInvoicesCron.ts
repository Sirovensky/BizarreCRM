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
import { allocateCounter, allocateUniqueOrderId, formatInvoiceOrderId } from '../utils/counters.js';
import { audit } from '../utils/audit.js';

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
  // BUGHUNT-2026-05-16: `current` is SQLite 'YYYY-MM-DD HH:MM:SS' (UTC) with
  // no 'Z' suffix. V8 parses that as LOCAL time, so subsequent setUTCMonth /
  // setUTCDate arithmetic operates on the wrong base date and the monthly
  // clamp can misfire on a non-UTC server.
  const normalized = current.includes('T') || current.endsWith('Z') || current.includes('+')
    ? current
    : `${current.replace(' ', 'T')}Z`;
  const d = new Date(normalized);
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

// BUGHUNT-2026-05-10-56: collapse missed periods after downtime into a single
// invoice. The cron previously advanced next_run_at by ONE interval per tick,
// so an N-day outage of a daily template fired N back-to-back invoices over
// the following N ticks. Now we advance until next_run_at is strictly in the
// future; the missed periods are logged as `backfill_skipped` and a single
// invoice is minted for "this period."
function advanceUntilFuture(
  current: string,
  kind: string,
  count: number,
): { next: string; skipped: number } {
  const nowIso = new Date().toISOString().replace('T', ' ').slice(0, 19);
  let next = advanceNextRunAt(current, kind, count);
  let skipped = 0;
  // Safety bound: 10000 iterations is enough for daily templates after a 27-year
  // outage; protects against pathological interval_kind values.
  let guard = 0;
  while (next <= nowIso && guard < 10_000) {
    next = advanceNextRunAt(next, kind, count);
    skipped++;
    guard++;
  }
  return { next, skipped };
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
  const { next: nextRunAt, skipped: backfillSkipped } = advanceUntilFuture(
    tpl.next_run_at,
    tpl.interval_kind,
    tpl.interval_count,
  );
  if (backfillSkipped > 0) {
    logger.warn('recurring invoice: collapsing missed periods after downtime', {
      slug,
      template_id: tpl.id,
      interval_kind: tpl.interval_kind,
      interval_count: tpl.interval_count,
      last_next_run_at: tpl.next_run_at,
      collapsed_next_run_at: nextRunAt,
      backfill_skipped: backfillSkipped,
    });
  }
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

      // SCAN-1122: verify the customer still exists + isn't soft-deleted
      // before minting an invoice. Templates live on after a customer is
      // deleted/archived; the cron was happily inserting new invoices
      // referencing a dead customer_id, leaving the shop with an orphan
      // invoice that no one could collect on. Skip the template run and
      // leave it active so a future manual reassignment can resume it.
      const cust = db.prepare(
        'SELECT 1 FROM customers WHERE id = ? AND is_deleted = 0',
      ).get(tpl.customer_id) as { 1: number } | undefined;
      if (!cust) {
        logger.warn('recurring invoice: customer missing or soft-deleted — skipping', {
          template_id: tpl.id,
          customer_id: tpl.customer_id,
        });
        throw new Error(
          `recurring invoice template ${tpl.id}: customer ${tpl.customer_id} not found or soft-deleted`,
        );
      }

      // SCAN-1159: verify the template's `created_by_user_id` is still active
      // so a deactivated employee's recurring templates don't keep minting
      // invoices credited to a ghost user. When the creator is gone we null
      // the `created_by` on the new invoice — it's a foreign key to users
      // with ON DELETE SET NULL-equivalent semantics expected by the UI, so
      // this is safer than failing the run hard.
      const creator = db.prepare(
        'SELECT 1 FROM users WHERE id = ? AND is_active = 1',
      ).get(tpl.created_by_user_id) as { 1: number } | undefined;
      const resolvedCreatedBy = creator ? tpl.created_by_user_id : null;
      if (!creator) {
        logger.warn('recurring invoice: template creator missing/deactivated — crediting as system', {
          template_id: tpl.id,
          stale_user_id: tpl.created_by_user_id,
        });
      }

      // Create the invoice
      const seq = allocateUniqueOrderId(db, 'invoice_order_id', 'invoices', 'order_id', 'INV-');
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
        resolvedCreatedBy,
      );

      invoiceId = invResult.lastInsertRowid as number;

      // Insert line items
      for (const li of lineItems) {
        const qty = typeof li.quantity === 'number' ? li.quantity : 1;
        const unitCents = typeof li.unit_price_cents === 'number' ? li.unit_price_cents : 0;
        const unitPrice = unitCents / 100;
        // BUGHUNT-2026-05-16: round to cents so a fractional qty (or any
        // float intermediate) doesn't leave a sub-cent residue that drifts
        // the stored line total away from the integer-cents subtotal.
        const lineTotal = Math.round(qty * unitCents) / 100;

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

      // BUGHUNT-2026-05-17 [missing audit]: every other invoice-creating
      // path writes an audit_logs breadcrumb (see invoices.routes.ts).
      // Recurring-template-driven invoices were a silent gap, so a tenant
      // auditor could not tell from audit_logs why their invoice count
      // jumped at midnight. Record one row per minted invoice with the
      // template + resolved-creator context. user_id=null + ip=system tag
      // the row as cron-originated (matches dunningScheduler audit style
      // before SCAN-1173 moved 'system' into details JSON).
      try {
        audit(db, 'recurring_invoice_created', resolvedCreatedBy, 'system', {
          slug,
          template_id: tpl.id,
          invoice_id: invoiceId,
          order_id: orderId,
          customer_id: tpl.customer_id,
          subtotal,
        });
      } catch {
        // Audit-write failure must not abort the mint — the invoice row is
        // committed via the surrounding transaction.
      }

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
    // BUGHUNT-2026-05-17: wrap EACH tenant in its own try/catch so a
    // single poisoned tenant DB (corrupt row, missing column on legacy
    // schema, prepared-statement failure) doesn't bubble out and abort
    // the whole sweep, silently denying recurring invoices to every
    // tenant that comes later in the iterator.
    for (const { slug, db } of getDbsFn()) {
      try {
        runForTenant(slug, db);
      } catch (err) {
        logger.error('recurring-invoices cron tenant iteration failed', {
          tenantSlug: slug,
          err: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  // Run once immediately on startup, then every CRON_INTERVAL_MS
  tick();
  return setInterval(tick, CRON_INTERVAL_MS);
}
