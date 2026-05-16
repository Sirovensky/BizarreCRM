import { Router, Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { requirePermission } from '../middleware/auth.js';
import {
  validatePrice,
  validatePositiveAmount,
  validateIsoDate,
  validateJsonPayload,
  validateIntegerQuantity,
  validateId,
  roundCents,
  toCents,
} from '../utils/validate.js';
import { writeCommission, reverseCommission } from '../utils/commissions.js';
import { allocateCounter, allocateUniqueOrderId, formatInvoiceOrderId, formatCreditNoteId } from '../utils/counters.js';
import { sendSmsTenant } from '../services/smsProvider.js';
import { sendEmail, isEmailConfigured } from '../services/email.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { runAutomations } from '../services/automations.js';
import { idempotent } from '../middleware/idempotency.js';
import { audit } from '../utils/audit.js';
import { getInvoicePitSnapshot } from '../utils/invoiceSnapshot.js';
import { fireWebhook } from '../services/webhooks.js';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { accruePaymentPoints } from '../services/notifications.js';
import { recordCustomerInteraction } from '../services/customerHealthScore.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import { logActivity } from '../utils/activityLog.js';
import { trackInterval } from '../utils/trackInterval.js';
import { verifyTenantStripePaymentIntent } from '../services/tenantStripe.js';

const logger = createLogger('invoices');
const router = Router();

/**
 * Transition map keyed by the SOURCE invoice status.
 * Value is an array of allowed DESTINATION statuses.
 *
 * Only standard status names appear as keys; any unrecognised source status
 * (custom tenant state) is not present in the map and therefore bypasses
 * the guard entirely (permissive fall-through).
 */
const LEGAL_INVOICE_TRANSITIONS: Record<string, readonly string[]> = {
  // draft can move to open/unpaid (issued) or void (discarded before sending)
  'draft':    ['open', 'unpaid', 'void'],
  // open/unpaid can receive payments (→ partial/paid) or be voided
  'open':     ['unpaid', 'partial', 'paid', 'overdue', 'void'],
  'unpaid':   ['open', 'partial', 'paid', 'overdue', 'void'],
  // partial payment received — finish paying, go overdue, or void
  'partial':  ['paid', 'overdue', 'void'],
  // paid — can be refunded or voided (dispute / chargeback)
  'paid':     ['refunded', 'void'],
  // overdue — can still be paid, partially paid, or voided
  'overdue':  ['paid', 'partial', 'void'],
  // terminal states — no further transitions allowed
  'void':     [],
  'refunded': [],
};

/**
 * Assert that transitioning an invoice from `from` to `to` is legal.
 * If `from` is not a known standard status the guard is a no-op (permissive
 * fall-through for custom tenant statuses).
 */
function assertInvoiceTransition(from: string, to: string): void {
  const allowed = LEGAL_INVOICE_TRANSITIONS[from];
  if (allowed === undefined) return; // unknown source — permissive fall-through
  if (!allowed.includes(to)) {
    throw new AppError(`Cannot transition invoice from '${from}' to '${to}'`, 400);
  }
}

async function getInvoiceDetail(adb: AsyncDb, id: number | string) {
  const invoice = await adb.get<any>(`
    SELECT inv.*,
      c.first_name, c.last_name, c.email as customer_email, c.phone as customer_phone,
      c.organization,
      u.first_name || ' ' || u.last_name as created_by_name,
      loc.id AS loc_id, loc.name AS loc_name, loc.address_line AS loc_address_line,
      loc.city AS loc_city, loc.state AS loc_state, loc.postcode AS loc_postcode,
      loc.country AS loc_country, loc.phone AS loc_phone, loc.email AS loc_email,
      loc.timezone AS loc_timezone,
      t.is_deleted AS ticket_is_deleted,
      -- WEB-UIUX-805: derive estimate backlink via the ticket. The invoice
      -- carries no estimate_id of its own, but tickets do (set at convert
      -- time). Expose estimate_id + estimate.order_id so the detail page
      -- can render "Created from estimate EST-XXX" without a second fetch.
      t.estimate_id AS source_estimate_id,
      est.order_id AS source_estimate_order_id
    FROM invoices inv
    LEFT JOIN customers c ON c.id = inv.customer_id
    LEFT JOIN users u ON u.id = inv.created_by
    LEFT JOIN locations loc ON loc.id = inv.location_id
    LEFT JOIN tickets t ON t.id = inv.ticket_id
    LEFT JOIN estimates est ON est.id = t.estimate_id
    WHERE inv.id = ?
  `, id);
  if (!invoice) return null;

  const [line_items, payments, deposit_invoices, credit_notes] = await Promise.all([
    adb.all<any>(`
      SELECT li.*, i.name as item_name, i.sku
      FROM invoice_line_items li
      LEFT JOIN inventory_items i ON i.id = li.inventory_item_id
      WHERE li.invoice_id = ?
      ORDER BY li.id ASC
    `, id),
    adb.all<any>(`
      SELECT p.*, u.first_name || ' ' || u.last_name as recorded_by
      FROM payments p
      LEFT JOIN users u ON u.id = p.user_id
      WHERE p.invoice_id = ?
      ORDER BY p.created_at ASC
    `, id),
    // ENR-I2: Fetch related deposit invoices (children if this is a deposit, or parent if this references one)
    adb.all<any>(`
      SELECT id, order_id, is_deposit, deposit_amount, total, amount_paid, status
      FROM invoices
      WHERE parent_invoice_id = ? OR (id = ? AND ? IS NOT NULL)
    `, id, invoice.parent_invoice_id, invoice.parent_invoice_id),
    // WEB-UIUX-707: Fetch credit notes already issued against this invoice.
    // Credit note rows are stored with credit_note_for = original invoice id.
    // They are inserted with status='paid' (negative-total rows); filter by
    // credit_note_for alone to include all of them regardless of status drift.
    adb.all<any>(`
      SELECT id, order_id, total, amount_paid, notes,
             credit_note_code, credit_note_note, created_at
      FROM invoices
      WHERE credit_note_for = ?
      ORDER BY created_at ASC
    `, id),
  ]);

  const {
    loc_id,
    loc_name,
    loc_address_line,
    loc_city,
    loc_state,
    loc_postcode,
    loc_country,
    loc_phone,
    loc_email,
    loc_timezone,
    ...invoiceFields
  } = invoice;

  return {
    ...invoiceFields,
    location: loc_id ? {
      id: loc_id,
      name: loc_name,
      address_line: loc_address_line,
      city: loc_city,
      state: loc_state,
      postcode: loc_postcode,
      country: loc_country,
      phone: loc_phone,
      email: loc_email,
      timezone: loc_timezone,
    } : null,
    line_items,
    payments,
    deposit_invoices,
    credit_notes,
  };
}

interface PostPaymentSideEffectsArgs {
  adb: AsyncDb;
  db: import('better-sqlite3').Database;
  invoice: any;
  paymentId: number;
  paymentAmount: number;
  paymentMethod: string;
  userId: number;
}

/**
 * Fire all post-payment side effects that must run after both single-invoice
 * and bulk mark-paid commits.  Every call is best-effort — failures are logged
 * but never block the response.
 *
 * Covers SCAN-623 (accruePaymentPoints + writeCommission) and
 * SCAN-627 (logActivity + fireWebhook).
 */
async function postPaymentSideEffects({
  adb,
  db,
  invoice,
  paymentId,
  paymentAmount,
  paymentMethod,
  userId,
}: PostPaymentSideEffectsArgs): Promise<void> {
  // Loyalty points accrual
  try {
    await accruePaymentPoints({
      adb,
      customerId: invoice.customer_id,
      invoiceId: Number(invoice.id),
      paymentAmount,
    });
  } catch (err: unknown) {
    logger.warn('[invoices] postPaymentSideEffects: loyalty accrual failed', {
      invoice_id: invoice.id,
      err: err instanceof Error ? err.message : String(err),
    });
  }

  // Commission writing
  if (invoice.created_by) {
    try {
      const createdByRow = await adb.get<{ commission_type: string | null; commission_rate: number | null }>(
        'SELECT commission_type, commission_rate FROM users WHERE id = ?',
        invoice.created_by,
      );
      const cType = createdByRow?.commission_type ?? null;
      const cRate = Number(createdByRow?.commission_rate ?? 0);
      if (cType && cType !== 'none' && cRate > 0) {
        const invTotal = Number(invoice.total ?? 0);
        const invTax = Number(invoice.total_tax ?? 0);
        const invPreTax = roundCents(Math.max(0, invTotal - invTax));
        let shouldWrite = false;
        let paymentPreTaxBaseCents = 0;
        if (cType === 'percent_ticket' || cType === 'percent_service') {
          if (invTotal > 0 && invPreTax > 0) {
            const paymentFraction = Math.min(1, paymentAmount / invTotal);
            const paymentPreTax = roundCents(invPreTax * paymentFraction);
            if (paymentPreTax > 0) {
              shouldWrite = true;
              paymentPreTaxBaseCents = toCents(paymentPreTax);
            }
          }
        } else if (cType === 'flat_per_ticket') {
          const existing = await adb.get<{ id: number }>(
            `SELECT id FROM commissions
               WHERE invoice_id = ?
                 AND COALESCE(type, '') != 'reversal'
               LIMIT 1`,
            invoice.id,
          );
          if (!existing) {
            shouldWrite = true;
            paymentPreTaxBaseCents = 1;
          }
        }
        if (shouldWrite) {
          await writeCommission(adb, {
            userId: invoice.created_by,
            source: 'invoice_payment',
            invoiceId: Number(invoice.id),
            ticketId: invoice.ticket_id ?? null,
            commissionableAmountCents: paymentPreTaxBaseCents,
          });
        }
      }
    } catch (err: unknown) {
      if (err instanceof AppError) throw err;
      const code = (err as NodeJS.ErrnoException & { code?: string }).code;
      if (code !== 'SQLITE_CONSTRAINT_UNIQUE' && code !== 'SQLITE_CONSTRAINT') {
        logger.warn('[invoices] postPaymentSideEffects: commission write failed', {
          invoice_id: invoice.id,
          err: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  // Activity log (fire-and-forget)
  logActivity(adb, {
    actor_user_id: userId,
    entity_kind: 'payment',
    entity_id: paymentId,
    action: 'received',
    metadata: { amount_cents: toCents(paymentAmount), method: paymentMethod },
  }).catch(() => {});

  // Webhook (SCAN-900: fireWebhook internally wraps async errors — no outer .catch needed;
  // SCAN-907: idempotency_key enables consumer-side deduplication on retry)
  fireWebhook(db, 'payment_received', {
    invoice_id: Number(invoice.id),
    amount: paymentAmount,
    method: paymentMethod,
    idempotency_key: `payment:${invoice.id}:${paymentId}`,
  });
}

// GET /invoices
router.get('/', requirePermission('invoices.view'), async (req, res) => {
  const adb = req.asyncDb;
  const { page = '1', pagesize = '20', status, from_date, to_date, keyword, customer_id, location_id, sort_by, sort_dir, include_credit_notes } = req.query as Record<string, string>;
  const p = Math.max(1, parseInt(page));
  const ps = Math.min(250, Math.max(1, parseInt(pagesize)));
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: any[] = [];

  if (status === 'overdue') {
    where += " AND inv.status IN ('unpaid','partial') AND inv.due_on IS NOT NULL AND inv.due_on < DATE('now')";
  } else if (status) { where += ' AND inv.status = ?'; params.push(status); }
  // WEB-UIUX-1209: by default exclude negative-total credit-note rows from
  // the unfiltered listing. AR aging totals + monthly receivables charts no
  // longer surface phantom CN-XXXX entries unless the caller explicitly
  // opts in with `?include_credit_notes=true`. Explicit `status=credit_note`
  // also bypasses the exclusion since the caller is asking for them.
  const wantCreditNotes = include_credit_notes === 'true' || include_credit_notes === '1' || status === 'credit_note';
  if (!wantCreditNotes) {
    where += ' AND inv.credit_note_for IS NULL';
  }
  if (customer_id) { where += ' AND inv.customer_id = ?'; params.push(customer_id); }
  if (from_date) { where += ' AND DATE(inv.created_at) >= ?'; params.push(from_date); }
  if (to_date) { where += ' AND DATE(inv.created_at) <= ?'; params.push(to_date); }
  // SCAN-462 / migration 139: optional location filter (backwards-compat — omitting it returns all)
  if (location_id && /^\d+$/.test(location_id)) { where += ' AND inv.location_id = ?'; params.push(parseInt(location_id, 10)); }
  if (keyword) {
    // Escape %/_/\ so users can't smuggle LIKE wildcards.
    where += " AND (inv.order_id LIKE ? ESCAPE '\\' OR c.first_name LIKE ? ESCAPE '\\' OR c.last_name LIKE ? ESCAPE '\\' OR c.organization LIKE ? ESCAPE '\\')";
    const k = `%${escapeLike(keyword)}%`;
    params.push(k, k, k, k);
  }

  // WEB-W2-032: allowlist sort columns to prevent SQL injection.
  const ALLOWED_SORT_COLS: Record<string, string> = {
    created_at: 'inv.created_at',
    total: 'inv.total',
    amount_due: 'inv.amount_due',
    status: 'inv.status',
    order_id: 'inv.order_id',
    due_on: 'inv.due_on',
    customer: "c.last_name || ' ' || c.first_name",
  };
  const sortCol = ALLOWED_SORT_COLS[sort_by ?? ''] ?? 'inv.created_at';
  const sortDir = sort_dir === 'asc' ? 'ASC' : 'DESC';

  const [totalRow, rawInvoices, agingRows] = await Promise.all([
    adb.get<any>(`
      SELECT COUNT(*) as c FROM invoices inv LEFT JOIN customers c ON c.id = inv.customer_id ${where}
    `, ...params),
    adb.all<any>(`
      SELECT inv.*, c.first_name, c.last_name, c.organization, c.phone as customer_phone,
        t.order_id as ticket_order_id
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      LEFT JOIN tickets t ON t.id = inv.ticket_id
      ${where}
      ORDER BY ${sortCol} ${sortDir}
      LIMIT ? OFFSET ?
    `, ...params, ps, offset),
    adb.all<any>(`
      SELECT
        CASE
          WHEN CAST(JULIANDAY('now') - JULIANDAY(inv.created_at) AS INTEGER) < 30 THEN 'current'
          WHEN CAST(JULIANDAY('now') - JULIANDAY(inv.created_at) AS INTEGER) < 60 THEN '30_days'
          WHEN CAST(JULIANDAY('now') - JULIANDAY(inv.created_at) AS INTEGER) < 90 THEN '60_days'
          ELSE '90_plus'
        END AS bucket,
        COUNT(*) AS count,
        COALESCE(SUM(inv.total), 0) AS total,
        COALESCE(SUM(inv.amount_due), 0) AS amount_due
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      ${where}
      GROUP BY bucket
    `, ...params),
  ]);

  const total = totalRow.c;

  // Compute aging fields for each invoice
  const nowMs = Date.now();
  const invoices = rawInvoices.map((inv: any) => {
    const createdMs = inv.created_at ? Date.parse(inv.created_at) : NaN;
    if (Number.isNaN(createdMs)) {
      logger.warn('invoice has unparseable created_at', { id: inv.id });
    }
    const ageDays = Number.isNaN(createdMs) ? 0 : Math.max(0, Math.floor((nowMs - createdMs) / 86_400_000));
    let agingBucket: string;
    if (ageDays < 30) agingBucket = 'current';
    else if (ageDays < 60) agingBucket = '30_days';
    else if (ageDays < 90) agingBucket = '60_days';
    else agingBucket = '90_plus';
    return { ...inv, age_days: ageDays, aging_bucket: agingBucket };
  });

  const agingSummary: Record<string, { count: number; total: number; amount_due: number }> = {
    current: { count: 0, total: 0, amount_due: 0 },
    '30_days': { count: 0, total: 0, amount_due: 0 },
    '60_days': { count: 0, total: 0, amount_due: 0 },
    '90_plus': { count: 0, total: 0, amount_due: 0 },
  };
  for (const row of agingRows) {
    agingSummary[row.bucket] = { count: row.count, total: row.total, amount_due: row.amount_due };
  }

  res.json({
    success: true,
    data: {
      invoices,
      pagination: { page: p, per_page: ps, total, total_pages: Math.ceil(total / ps) },
      aging_summary: agingSummary,
    },
  });
});

// GET /invoices/stats — KPIs and distribution data for overview
// WEB-W2-022 + WEB-W2-023: accepts the same filter params as GET / so the
// stats panel reflects the current search context.  Filters: status,
// from_date, to_date, customer_id, location_id, keyword.
// Additionally exposes overdue_count + overdue_amount as standalone fields
// (WEB-W2-023 — overdue stats independent of pagination).
router.get('/stats', requirePermission('invoices.view'), async (req, res) => {
  const adb = req.asyncDb;
  const { status, from_date, to_date, customer_id, location_id, keyword } = req.query as Record<string, string>;

  // Build the shared WHERE clause that mirrors the list endpoint filters.
  const conditions: string[] = ['inv.status != \'void\''];
  const params: unknown[] = [];

  if (status === 'overdue') {
    conditions.push("inv.status IN ('unpaid','partial') AND inv.due_on IS NOT NULL AND inv.due_on < DATE('now')");
  } else if (status) {
    conditions.push('inv.status = ?');
    params.push(status);
  }
  if (customer_id) { conditions.push('inv.customer_id = ?'); params.push(customer_id); }
  if (from_date) { conditions.push('DATE(inv.created_at) >= ?'); params.push(from_date); }
  if (to_date) { conditions.push('DATE(inv.created_at) <= ?'); params.push(to_date); }
  if (location_id && /^\d+$/.test(location_id)) {
    conditions.push('inv.location_id = ?');
    params.push(parseInt(location_id, 10));
  }
  if (keyword) {
    const esc = escapeLike(keyword);
    conditions.push(
      "(inv.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR (c.first_name || ' ' || c.last_name) LIKE ?)"
    );
    const pat = `%${esc}%`;
    params.push(pat, pat, pat, pat);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;

  const [kpis, statusDist, methodDist, overdueRow] = await Promise.all([
    adb.get<any>(`
      SELECT
        COALESCE(SUM(inv.total), 0) AS total_sales,
        COUNT(*) AS invoice_count,
        COALESCE(SUM(inv.total_tax), 0) AS tax_collected,
        COALESCE(SUM(CASE WHEN inv.status IN ('unpaid','partial') THEN inv.amount_due ELSE 0 END), 0) AS outstanding_receivables
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      ${where}
    `, ...params),
    adb.all<any>(`
      SELECT inv.status, COUNT(*) AS count
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      ${where}
      GROUP BY inv.status
    `, ...params),
    adb.all<any>(`
      SELECT p.method, COUNT(*) AS count, COALESCE(SUM(p.amount), 0) AS total
      FROM payments p
      JOIN invoices inv ON inv.id = p.invoice_id
      LEFT JOIN customers c ON c.id = inv.customer_id
      ${where}
      GROUP BY p.method
    `, ...params),
    // WEB-W2-023: overdue stats run against the FULL dataset (ignoring status
    // filter) so the overdue badge is always accurate regardless of active tab.
    adb.get<any>(`
      SELECT
        COUNT(*) AS overdue_count,
        COALESCE(SUM(amount_due), 0) AS overdue_amount
      FROM invoices
      WHERE status IN ('unpaid','partial')
        AND due_on IS NOT NULL
        AND due_on < DATE('now')
    `),
  ]);

  res.json({
    success: true,
    data: {
      kpis,
      status_distribution: statusDist,
      method_distribution: methodDist,
      overdue_count: overdueRow?.overdue_count ?? 0,
      overdue_amount: overdueRow?.overdue_amount ?? 0,
    },
  });
});

// GET /invoices/:id
// SCAN-1072: sibling list/stats routes are gated on invoices.view; this handler
// was left open, letting any authenticated user enumerate any invoice by id.
router.get('/:id', requirePermission('invoices.view'), async (req, res) => {
  const adb = req.asyncDb;
  const invoice = await getInvoiceDetail(adb, req.params.id as string);
  if (!invoice) throw new AppError('Invoice not found', 404);
  res.json({ success: true, data: invoice });
});

// POST /invoices
// SEC-H25: creating an invoice is a financial write — gate behind invoices.create.
router.post('/', idempotent, requirePermission('invoices.create'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const {
    customer_id, ticket_id, line_items = [], discount = 0, discount_reason,
    notes, due_date, is_deposit, deposit_amount: reqDepositAmount, parent_invoice_id,
    location_id: bodyLocationId,
  } = req.body;

  if (!customer_id) throw new AppError('Customer is required', 400);

  // SCAN-462 / migration 139: resolve location_id — default to 1 (Main Store) when not provided.
  // Validate that the supplied id references an existing, active location.
  let invoiceLocationId: number = 1;
  if (bodyLocationId !== undefined && bodyLocationId !== null) {
    if (!Number.isInteger(bodyLocationId) || (bodyLocationId as number) <= 0) {
      throw new AppError('location_id must be a positive integer', 400);
    }
    const loc = await adb.get<{ id: number }>(
      'SELECT id FROM locations WHERE id = ? AND is_active = 1',
      bodyLocationId,
    );
    if (!loc) throw new AppError('location_id references an unknown or inactive location', 400);
    invoiceLocationId = bodyLocationId as number;
  }

  // V8: Validate due_date format if provided (accept ISO YYYY-MM-DD or full ISO timestamp)
  const validatedDueDate = validateIsoDate(due_date, 'due_date');

  // ENR-I2: Validate deposit fields
  const depositFlag = is_deposit ? 1 : 0;
  const depositAmount = depositFlag ? validatePrice(reqDepositAmount ?? 0, 'deposit_amount') : 0;
  if (parent_invoice_id) {
    const parentInv = await adb.get<any>('SELECT id, is_deposit FROM invoices WHERE id = ?', parent_invoice_id);
    if (!parentInv) throw new AppError('Parent invoice not found', 404);
    if (!parentInv.is_deposit) throw new AppError('Parent invoice is not a deposit invoice', 400);
  }

  // I5: Atomic counter allocation (fixes MAX-based race + poisoning)
  // Counters table is the single source of truth — seeded by migration 072.
  const nextSeq = allocateUniqueOrderId(db, 'invoice_order_id', 'invoices', 'order_id', 'INV-');
  const orderId = formatInvoiceOrderId(nextSeq);

  // M6: Tax / discount ordering policy — we apply DISCOUNT FIRST, then TAX on the
  // discounted (net) subtotal. This is the "tax on net" / merchant-favoring choice:
  // the customer's discount reduces the tax burden too. Line items are expected
  // to arrive with tax_amount already computed by the client against the net
  // line (unit_price * qty - line_discount). This comment documents the policy
  // explicitly so downstream handlers do not silently flip it.
  let subtotal = 0;
  let total_tax = 0;

  // V9 / M2: Validate each line item BEFORE accumulating totals. Rejects negative
  // unit_price, non-integer quantities, and overlong text. This also protects the
  // subtotal math from NaN / Infinity propagation.
  //
  // SEC-H36: tax_amount is RECOMPUTED server-side from `tax_classes.rate` when
  // a `tax_class_id` is present on the line item. Prior code trusted the
  // client-supplied `tax_amount` which a hostile POS client could send as 0
  // and bypass collection. Matches the pattern already in pos.routes.ts:413.
  // Clients that pass an explicit `tax_amount` WITHOUT a `tax_class_id`
  // (legacy flow for pre-tax-class invoices) are still allowed — that path
  // is out of scope here, only the tax_class_id path is tightened.
  // SEC-H117: non-admin cap — reject obviously runaway line quantities and
  // invoice totals. Admins bypass the cap for legitimate high-volume B2B
  // invoices. Caps are deliberately generous: 10,000 units per line and
  // $1,000,000 per invoice are already far above any realistic repair-shop
  // transaction. Anything bigger should go through an admin-reviewed flow.
  const isAdmin = req.user?.role === 'admin';
  const LINE_QTY_CAP = 10_000;
  const INVOICE_TOTAL_CAP = 1_000_000;
  for (const rawItem of line_items) {
    const qty = validateIntegerQuantity(rawItem?.quantity ?? 1, 'line item quantity');
    if (qty < 1) throw new AppError('line item quantity must be at least 1', 400);
    if (!isAdmin && qty > LINE_QTY_CAP) {
      throw new AppError(`line item quantity exceeds ${LINE_QTY_CAP} (admin override required)`, 400);
    }
    const unitPrice = validatePrice(rawItem?.unit_price ?? 0, 'line item unit_price');
    const lineDiscount = validatePrice(rawItem?.line_discount ?? 0, 'line item line_discount');
    const lineNet = roundCents(qty * unitPrice - lineDiscount);
    if (lineNet < 0) throw new AppError('Line item discount exceeds line total', 400);

    let lineTax = 0;
    if (rawItem?.tax_class_id != null) {
      const taxClassId = validateIntegerQuantity(rawItem.tax_class_id, 'line item tax_class_id');
      const taxClass = await adb.get<{ rate: number }>(
        'SELECT rate FROM tax_classes WHERE id = ?',
        taxClassId,
      );
      const rate = taxClass ? Number(taxClass.rate) / 100 : 0;
      lineTax = roundCents(lineNet * rate);
    } else {
      // Legacy path — pre-tax-class invoices ship tax_amount in the body.
      lineTax = validatePrice(rawItem?.tax_amount ?? 0, 'line item tax_amount');
    }
    subtotal = roundCents(subtotal + lineNet);
    total_tax = roundCents(total_tax + lineTax);
  }
  const appliedDiscount = validatePrice(discount ?? 0, 'discount');
  if (appliedDiscount > subtotal + total_tax) {
    throw new AppError('Discount cannot exceed total', 400);
  }
  const total = roundCents(subtotal + total_tax - appliedDiscount);
  if (!isAdmin && total > INVOICE_TOTAL_CAP) {
    throw new AppError(`invoice total exceeds ${INVOICE_TOTAL_CAP} (admin override required)`, 400);
  }
  const amount_due = total;

  // WEB-UIUX-895: capture customer/store/jurisdiction at create time so a
  // reprint 6 months later doesn't lie about a renamed profile, store
  // banner, or shifted jurisdiction. Print pages prefer the snapshot when
  // populated and fall back to the live row when NULL (legacy invoices).
  const pit = await getInvoicePitSnapshot(adb, customer_id);

  const result = await adb.run(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, discount_reason,
      total_tax, total, amount_paid, amount_due, notes, due_on, created_by,
      is_deposit, deposit_amount, parent_invoice_id, location_id,
      customer_name_snapshot, customer_address_snapshot, store_name_snapshot, tax_jurisdiction_snapshot)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, orderId, customer_id, ticket_id || null, subtotal, appliedDiscount, discount_reason || null,
    total_tax, total, amount_due, notes || null, validatedDueDate, req.user!.id,
    depositFlag, depositAmount, parent_invoice_id || null, invoiceLocationId,
    pit.customer_name_snapshot, pit.customer_address_snapshot, pit.store_name_snapshot, pit.tax_jurisdiction_snapshot);

  const invoiceId = result.lastInsertRowid;

  // SCAN-748: Re-check total cap after per-item re-validation to prevent
  // multi-pass small-item accumulation from breaching INVOICE_TOTAL_CAP.
  let revalidatedTotal = 0;
  for (const item of line_items) {
    // SEC-M12: Destructure only allowed fields (prevents mass assignment)
    const { inventory_item_id, description, quantity, unit_price, line_discount, tax_amount, tax_class_id, notes: itemNotes } = item;
    // V9: Re-validate each field at insert time so the row is clean.
    const safeQty = validateIntegerQuantity(quantity ?? 1, 'line item quantity');
    const safeUnitPrice = validatePrice(unit_price ?? 0, 'line item unit_price');
    const safeLineDiscount = validatePrice(line_discount ?? 0, 'line item line_discount');
    const safeLineTax = validatePrice(tax_amount ?? 0, 'line item tax_amount');
    // SEC-M10: Validate text lengths on line items
    if (typeof description === 'string' && description.length > 500) throw new AppError('Line item description exceeds 500 characters', 400);
    if (typeof itemNotes === 'string' && itemNotes.length > 1000) throw new AppError('Line item notes exceeds 1000 characters', 400);
    const lineTotal = roundCents((safeQty * safeUnitPrice) - safeLineDiscount + safeLineTax);
    revalidatedTotal = roundCents(revalidatedTotal + lineTotal);
    await adb.run(`
      INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, line_discount, tax_amount, tax_class_id, total, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `, invoiceId, inventory_item_id || null, description || '', safeQty,
      safeUnitPrice, safeLineDiscount, safeLineTax, tax_class_id || null,
      lineTotal, itemNotes || null);
  }
  if (!isAdmin && revalidatedTotal > INVOICE_TOTAL_CAP) {
    throw new AppError(`Invoice total exceeds cap (${INVOICE_TOTAL_CAP})`, 400);
  }

  // Link ticket to invoice if provided
  if (ticket_id) {
    await adb.run('UPDATE tickets SET invoice_id = ?, updated_at = datetime(\'now\') WHERE id = ?', invoiceId, ticket_id);
  }
  const invoice = await getInvoiceDetail(adb, invoiceId as number);
  broadcast(WS_EVENTS.INVOICE_CREATED, invoice, req.tenantSlug || null);

  // SCAN-522: fire-and-forget activity log
  logActivity(adb, {
    actor_user_id: req.user!.id,
    entity_kind: 'invoice',
    entity_id: invoiceId as number,
    action: 'created',
    metadata: { amount_cents: toCents(total), status: 'draft' },
  }).catch(() => {});

  // ENR-A6: Fire webhook
  // SA10-1: use the already-computed local `orderId` instead of reading it
  // back off the `invoice` detail row (which was typed `any` via `adb.get<any>`).
  // That removes the `as any` cast at the broadcast boundary without changing
  // semantics — `orderId` is the exact value we just INSERTed.
  // SCAN-900: both fireWebhook and runAutomations wrap async in an internal
  // (async () => { try { ... } catch { logger.warn } })() — errors are already
  // surfaced inside those helpers; no additional .catch needed at the call site.
  fireWebhook(db, 'invoice_created', { invoice_id: invoiceId, order_id: orderId });

  // Fire automations (async, non-blocking)
  const cust = customer_id ? await adb.get<any>('SELECT * FROM customers WHERE id = ?', customer_id) : {};
  runAutomations(db, 'invoice_created', { invoice, customer: cust ?? {} });

  res.status(201).json({ success: true, data: invoice });
});

// PUT /invoices/:id
// SEC-H25: updating an invoice is a financial write — gate behind invoices.edit.
router.put('/:id', requirePermission('invoices.edit'), async (req: Request<{ id: string }>, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Invoice not found', 404);
  if (existing.status === 'void') throw new AppError('Cannot modify a voided invoice', 400);

  const { notes, due_date, due_on, discount, discount_reason, payment_plan, location_id: patchLocationId } = req.body;
  // V8: Validate whichever due date field the client sent
  const rawDueDate = due_date ?? due_on;
  const dueDate = validateIsoDate(rawDueDate, 'due_date');

  // SCAN-462 / migration 139: validate location_id if provided
  let resolvedLocationId: number | null = null;
  if (patchLocationId !== undefined && patchLocationId !== null) {
    if (!Number.isInteger(patchLocationId) || (patchLocationId as number) <= 0) {
      throw new AppError('location_id must be a positive integer', 400);
    }
    const patchLoc = await adb.get<{ id: number }>(
      'SELECT id FROM locations WHERE id = ? AND is_active = 1',
      patchLocationId,
    );
    if (!patchLoc) throw new AppError('location_id references an unknown or inactive location', 400);
    resolvedLocationId = patchLocationId as number;
  }

  // V10 / ENR-I8: Validate payment_plan with structural + size guard so we don't
  // accept circular refs, unbounded blobs, or malformed values.
  let serializedPaymentPlan: string | null = null;
  if (payment_plan !== undefined && payment_plan !== null) {
    if (typeof payment_plan !== 'object' || Array.isArray(payment_plan)) {
      throw new AppError('payment_plan must be an object', 400);
    }
    const pp = payment_plan as Record<string, unknown>;
    if (pp.installments !== undefined && (typeof pp.installments !== 'number' || !Number.isInteger(pp.installments) || pp.installments < 1 || pp.installments > 1000)) {
      throw new AppError('payment_plan.installments must be a positive integer', 400);
    }
    if (pp.frequency !== undefined && !['weekly', 'biweekly', 'monthly'].includes(pp.frequency as string)) {
      throw new AppError('payment_plan.frequency must be weekly, biweekly, or monthly', 400);
    }
    if (pp.amount_per !== undefined) {
      validatePositiveAmount(pp.amount_per, 'payment_plan.amount_per');
    }
    // SEC-L40: cross-validate installments * amount_per ≈ invoice.total so
    // a client can't post a plan that collects either more or less than
    // the amount owed. Tolerance is 1 cent per installment (accumulated
    // rounding) plus $0.01 slack. Prior code validated each field in
    // isolation: pay 6 × $10 on a $100 invoice was accepted.
    if (
      typeof pp.installments === 'number' &&
      typeof pp.amount_per === 'number' &&
      typeof existing.total === 'number'
    ) {
      const scheduleTotal = pp.installments * pp.amount_per;
      const invoiceTotal = existing.total;
      const tolerance = 0.01 + pp.installments * 0.01;
      if (Math.abs(scheduleTotal - invoiceTotal) > tolerance) {
        throw new AppError(
          `payment_plan schedule ${pp.installments} × ${pp.amount_per} = ${scheduleTotal.toFixed(2)} must match invoice total ${invoiceTotal.toFixed(2)} (±${tolerance.toFixed(2)})`,
          400,
        );
      }
    }
    // Deep structural + size validation (catches circular refs, blob DoS)
    serializedPaymentPlan = validateJsonPayload(payment_plan, 'payment_plan', 16384);
  }

  // M6: Recalculate totals using the documented tax-on-net order — discount is
  // deducted from (subtotal + tax). The invoice's stored tax was already computed
  // against the discounted subtotal at creation time, so this subtraction is safe.
  const newDiscount = discount !== undefined ? validatePrice(discount, 'discount') : existing.discount;
  if (newDiscount > existing.subtotal + existing.total_tax) {
    throw new AppError('Discount cannot exceed total', 400);
  }
  const total = roundCents(existing.subtotal + existing.total_tax - newDiscount);
  const amountDue = roundCents(total - existing.amount_paid);

  await adb.run(`
    UPDATE invoices SET
      notes = COALESCE(?, notes),
      due_on = COALESCE(?, due_on),
      discount = ?,
      discount_reason = COALESCE(?, discount_reason),
      total = ?,
      amount_due = ?,
      payment_plan = COALESCE(?, payment_plan),
      location_id = COALESCE(?, location_id),
      updated_at = datetime('now')
    WHERE id = ?
  `,
    notes ?? null, dueDate, newDiscount, discount_reason ?? null,
    total, Math.max(0, amountDue),
    serializedPaymentPlan,
    resolvedLocationId,
    req.params.id,
  );

  const invoice = await getInvoiceDetail(adb, req.params.id);
  broadcast(WS_EVENTS.INVOICE_UPDATED, invoice, req.tenantSlug || null);
  res.json({ success: true, data: invoice });
});

// Payment dedup: prevent double-submit within 5 seconds for same invoice+amount
const recentPayments = new Map<string, number>();
trackInterval(() => { const now = Date.now(); for (const [k, v] of recentPayments) { if (now - v > 30000) recentPayments.delete(k); } }, 30000);

interface RecordInvoicePaymentArgs {
  adb: AsyncDb;
  db: import('better-sqlite3').Database;
  invoiceId: number | string;
  invoice?: any;
  amount: unknown;
  method?: unknown;
  methodDetail?: unknown;
  transactionId?: unknown;
  processor?: unknown;
  reference?: unknown;
  notes?: unknown;
  paymentType?: unknown;
  userId: number;
  tenantSlug?: string | null;
  expectedCustomerId?: unknown;
  deduplicate?: boolean;
  // WEB-UIUX-1525: cashier-confirmed bypass of the same-amount dedup window.
  // When true, the dedup check is skipped and the action is audited so a
  // legitimate split tender (two friends each paying the same amount) can
  // be recorded without falsifying the amount.
  forceDuplicate?: boolean;
}

interface RecordInvoicePaymentResult {
  paymentId: number;
  updatedInvoice: any;
  totalPaid: number;
  amountDue: number;
  status: string;
  overpayment: number;
}

async function getInvoicePositivePaymentTotal(
  adb: AsyncDb,
  invoiceId: number | string,
): Promise<number> {
  // SCAN-757: CASE WHEN filters out NULL/negative rows so corrupt payment rows
  // cannot propagate NaN or negative values into the running total.
  const totalPaidRow = await adb.get<{ t: number }>(
    'SELECT SUM(CASE WHEN amount IS NOT NULL AND amount >= 0 THEN amount ELSE 0 END) as t FROM payments WHERE invoice_id = ?',
    invoiceId,
  );
  return roundCents(totalPaidRow?.t || 0);
}

async function getInvoiceRemainingBalance(
  adb: AsyncDb,
  invoice: any,
): Promise<number> {
  const invoiceTotal = Number(invoice.total ?? 0);
  if (!Number.isFinite(invoiceTotal)) return Number.NaN;
  const totalPaid = await getInvoicePositivePaymentTotal(adb, invoice.id);
  return roundCents(invoiceTotal - totalPaid);
}

async function assertNoRecentDuplicatePayment(
  adb: AsyncDb,
  invoiceId: number | string,
  amount: number,
  userId: number,
): Promise<void> {
  // Double-submit guard: same invoice + amount within 5 seconds = reject
  // SEC-M9: In-memory fast check + DB-backed check (survives restart)
  // WEB-UIUX-1525: emit ERR_PAYMENT_DUPLICATE so the client can offer a
  // "Yes, this is a separate tender" confirmation and retry with force=true
  // instead of forcing the cashier to falsify the amount (e.g. $50.01) or
  // split the same-amount tender into a different method.
  const dedupKey = `${invoiceId}:${amount.toFixed(2)}:${userId}`;
  const lastPayment = recentPayments.get(dedupKey);
  if (lastPayment && Date.now() - lastPayment < 5000) {
    throw new AppError(
      'A payment with this exact amount was just recorded. If this is a separate tender (e.g. two friends each paying the same amount), confirm to record it anyway.',
      409,
      ERROR_CODES.ERR_PAYMENT_DUPLICATE,
    );
  }
  // DB-backed dedup: check for same invoice+amount+user within last 10 seconds
  const recentDbPayment = await adb.get<any>(`
    SELECT id FROM payments
    WHERE invoice_id = ? AND ROUND(amount, 2) = ROUND(?, 2) AND user_id = ?
    AND created_at > datetime('now', '-10 seconds')
    LIMIT 1
  `, invoiceId, amount, userId);
  if (recentDbPayment) {
    throw new AppError(
      'A payment with this exact amount was just recorded. If this is a separate tender (e.g. two friends each paying the same amount), confirm to record it anyway.',
      409,
      ERROR_CODES.ERR_PAYMENT_DUPLICATE,
    );
  }
  recentPayments.set(dedupKey, Date.now());
}

async function recordInvoicePayment({
  adb,
  db,
  invoiceId,
  invoice: providedInvoice,
  amount: rawAmount,
  method = 'cash',
  methodDetail,
  transactionId,
  processor,
  reference,
  notes,
  paymentType = 'payment',
  userId,
  tenantSlug,
  expectedCustomerId,
  deduplicate = true,
  forceDuplicate = false,
}: RecordInvoicePaymentArgs): Promise<RecordInvoicePaymentResult> {
  const invoice = providedInvoice ?? await adb.get<any>('SELECT * FROM invoices WHERE id = ?', invoiceId);
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') throw new AppError('Cannot add payment to voided invoice', 400);

  // SEC-H26: if the client provides customer_id in the body, verify it matches
  // the invoice's customer.
  if (expectedCustomerId !== undefined && expectedCustomerId !== null) {
    const bodyCustomerId = validateId(expectedCustomerId, 'customer_id');
    if (bodyCustomerId !== invoice.customer_id) {
      throw new AppError('customer_id does not match invoice.customer_id', 400);
    }
  }

  const amount = validatePositiveAmount(rawAmount, 'payment amount');
  let paymentMethodDetail = typeof methodDetail === 'string' ? methodDetail : null;
  let paymentTransactionId = typeof transactionId === 'string' ? transactionId.trim() : '';
  let paymentProcessor = typeof processor === 'string' ? processor.trim().toLowerCase() : null;
  let paymentReference = typeof reference === 'string' ? reference.trim() : null;
  let processorTransactionId: string | null = null;
  let processorResponse: string | null = null;

  if (String(method).toLowerCase() === 'stripe' || paymentProcessor === 'stripe') {
    const verified = await verifyTenantStripePaymentIntent(db, paymentTransactionId || paymentReference, toCents(amount), {
      allowedSources: ['invoice'],
      expectedInvoiceId: invoice.id,
      expectedCustomerId: invoice.customer_id ?? null,
    });
    const existingStripePayment = await adb.get<{ id: number }>(`
      SELECT id FROM payments
       WHERE LOWER(COALESCE(processor, '')) = 'stripe'
         AND (
           processor_transaction_id = ?
           OR transaction_id = ?
           OR reference = ?
         )
       LIMIT 1
    `, verified.id, verified.id, verified.id);
    if (existingStripePayment) {
      throw new AppError('Stripe PaymentIntent has already been recorded', 409);
    }
    paymentMethodDetail = paymentMethodDetail || verified.paymentMethodDetail;
    paymentTransactionId = verified.id;
    paymentProcessor = 'stripe';
    paymentReference = verified.latestChargeId ?? verified.id;
    processorTransactionId = verified.id;
    processorResponse = JSON.stringify(verified.raw);
  }

  const validPaymentTypes = ['payment', 'deposit'];
  if (typeof paymentType !== 'string' || !validPaymentTypes.includes(paymentType)) {
    throw new AppError(`Invalid payment_type. Must be one of: ${validPaymentTypes.join(', ')}`, 400);
  }

  if (deduplicate && !forceDuplicate) {
    await assertNoRecentDuplicatePayment(adb, invoice.id, amount, userId);
  }

  const invoiceTotal = Number(invoice.total ?? 0);
  const predictedTotalPaid = roundCents(await getInvoicePositivePaymentTotal(adb, invoice.id) + amount);
  const predictedRawAmountDue = roundCents(invoiceTotal - predictedTotalPaid);
  const predictedStatus = predictedRawAmountDue <= 0 ? 'paid' : predictedTotalPaid > 0 ? 'partial' : 'unpaid';

  // SEC-H113: enforce state-machine transition before writing payment rows.
  assertInvoiceTransition(invoice.status, predictedStatus);

  const paymentResult = await adb.run(`
    INSERT INTO payments (
      invoice_id, amount, method, method_detail, transaction_id, notes, payment_type,
      processor, reference, processor_transaction_id, processor_response, capture_state, user_id
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'captured', ?)
  `, invoice.id, amount, method, paymentMethodDetail || null,
    paymentTransactionId || null, notes || null, paymentType,
    paymentProcessor, paymentReference, processorTransactionId, processorResponse, userId);
  const paymentId = paymentResult.lastInsertRowid as number;

  const totalPaid = await getInvoicePositivePaymentTotal(adb, invoice.id);
  const rawAmountDue = roundCents(invoiceTotal - totalPaid);

  // M9: Detect overpayment — if the customer paid more than the invoice total,
  // record the excess as a store credit. The displayed amount_due is clamped
  // to 0 so the ledger does not go negative.
  const overpayment = rawAmountDue < 0 ? roundCents(-rawAmountDue) : 0;
  const displayAmountDue = Math.max(0, rawAmountDue);
  const status = rawAmountDue <= 0 ? 'paid' : totalPaid > 0 ? 'partial' : 'unpaid';

  await adb.run(`
    UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
  `, totalPaid, displayAmountDue, status, invoice.id);

  // Post-payment side effects: loyalty points, commission, activity log, webhook.
  await postPaymentSideEffects({
    adb,
    db,
    invoice: { ...invoice, id: Number(invoice.id) },
    paymentId,
    paymentAmount: amount,
    paymentMethod: String(method),
    userId,
  });

  // SCAN-524: update customer last_interaction_at + lifetime_value_cents (fire-and-forget)
  if (invoice.customer_id) {
    recordCustomerInteraction(adb, invoice.customer_id, toCents(amount)).catch(() => {});
  }

  if (overpayment > 0 && invoice.customer_id) {
    try {
      // BUGHUNT-2026-05-10-01: atomic UPSERT — previous SELECT-then-UPDATE
      // pattern allowed two concurrent overpayments on the same customer
      // to both read the same pre-state and the second UPDATE clobbered
      // the first. Now use INSERT ON CONFLICT DO UPDATE so the +=
      // happens inside a single SQLite statement (atomic per-row).
      await adb.run(
        `INSERT INTO store_credits (customer_id, amount)
         VALUES (?, ?)
         ON CONFLICT(customer_id) DO UPDATE SET
           amount = ROUND((store_credits.amount + excluded.amount) * 100) / 100,
           updated_at = datetime('now')`,
        invoice.customer_id,
        overpayment,
      );
      // Ledger row for the credit transaction
      await adb.run(`
        INSERT INTO store_credit_transactions
          (customer_id, amount, type, reference_type, reference_id, notes, user_id)
        VALUES (?, ?, 'manual_credit', 'invoice', ?, ?, ?)
      `,
        invoice.customer_id,
        overpayment,
        invoice.id,
        `Overpayment on invoice ${invoice.order_id}`,
        userId,
      );
    } catch (creditErr: unknown) {
      // Do not fail the payment flow if the credit insert fails — log and continue.
      logger.warn(`[invoices] failed to record overpayment store credit`, { err: creditErr });
    }
  }

  const updatedInvoice = await getInvoiceDetail(adb, invoice.id);
  broadcast(WS_EVENTS.PAYMENT_RECEIVED, updatedInvoice, tenantSlug || null);

  return {
    paymentId,
    updatedInvoice,
    totalPaid,
    amountDue: displayAmountDue,
    status,
    overpayment,
  };
}

// POST /invoices/:id/payments
// SEC-H25: recording a payment is a financial write — gate behind invoices.record_payment.
router.post('/:id/payments', idempotent, requirePermission('invoices.record_payment'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { method = 'cash', method_detail, transaction_id, notes, payment_type = 'payment' } = req.body;
  // WEB-UIUX-1525: opt-in dedup bypass after the cashier confirms in the UI
  // that the same-amount second payment is a legitimate separate tender.
  // Body sends `force_duplicate: true` only on the retry of a 409
  // ERR_PAYMENT_DUPLICATE response.
  const forceDuplicate = req.body?.force_duplicate === true;
  const payment = await recordInvoicePayment({
    adb,
    db,
    invoiceId: req.params.id as string,
    amount: req.body.amount,
    method,
    methodDetail: method_detail,
    transactionId: transaction_id,
    processor: req.body?.processor,
    reference: req.body?.reference,
    notes,
    paymentType: payment_type,
    userId: req.user!.id,
    tenantSlug: req.tenantSlug || null,
    expectedCustomerId: req.body?.customer_id,
    deduplicate: true,
    forceDuplicate,
  });
  if (forceDuplicate) {
    audit(db, 'payment_force_duplicate', req.user!.id, req.ip || 'unknown', {
      invoice_id: Number(req.params.id),
      amount: Number(req.body.amount),
      method,
    });
  }

  res.status(201).json({ success: true, data: payment.updatedInvoice });
});

// WEB-UIUX-1526: per-payment reverse. Cashier fat-fingers $5,000 instead of
// $50 — Void Invoice would VOID every payment on the invoice (destroys
// legitimate prior payments + restores stock + reverses commission). This
// route reverses one specific payment row inside a 30-minute window from
// its creation. Manager/admin only; payment must not already carry
// `[VOIDED]` in notes. Recomputes invoice amount_paid + status from the
// remaining positive payment rows after marking the row voided. Refunds /
// credit-notes recorded as separate payment rows are intentionally NOT
// reversible via this route — they have their own lifecycle.
router.patch('/payments/:paymentId/reverse', async (req: Request<{ paymentId: string }>, res) => {
  const adb = req.asyncDb;
  const role = (req as any)?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager required to reverse a payment', 403);
  }
  const paymentId = parseInt(req.params.paymentId, 10);
  if (!Number.isFinite(paymentId) || paymentId <= 0) {
    throw new AppError('Invalid payment id', 400);
  }
  const payment = await adb.get<any>(
    'SELECT id, invoice_id, amount, notes, created_at FROM payments WHERE id = ?',
    paymentId,
  );
  if (!payment) throw new AppError('Payment not found', 404);
  if (typeof payment.notes === 'string' && payment.notes.includes('[VOIDED]')) {
    throw new AppError('Payment is already voided', 409);
  }
  const createdMs = Date.parse(String(payment.created_at).replace(' ', 'T'));
  if (!Number.isFinite(createdMs)) {
    throw new AppError('Payment created_at is unparseable — refuse reverse', 409);
  }
  const ageMs = Date.now() - createdMs;
  const REVERSE_WINDOW_MS = 30 * 60 * 1000;
  if (ageMs > REVERSE_WINDOW_MS) {
    throw new AppError(
      `Reverse window expired (${Math.floor(ageMs / 60000)} min old; window is 30 min). Use Credit Note instead.`,
      409,
    );
  }
  const reasonRaw = typeof req.body?.reason === 'string' ? req.body.reason.trim().slice(0, 500) : '';
  if (!reasonRaw) {
    throw new AppError('reason is required to reverse a payment', 400);
  }

  await adb.run(
    "UPDATE payments SET notes = COALESCE(notes || ' ', '') || '[VOIDED] ' || ? WHERE id = ?",
    reasonRaw, paymentId,
  );
  // Recompute invoice state from the remaining positive (non-VOIDED)
  // payment rows. We use the same positive-payment-total helper the
  // recordInvoicePayment path uses, then re-derive amount_due + status.
  const invoiceRow = await adb.get<any>('SELECT id, total FROM invoices WHERE id = ?', payment.invoice_id);
  if (invoiceRow) {
    const remainingPaid = await adb.get<{ t: number }>(
      "SELECT SUM(CASE WHEN amount IS NOT NULL AND amount >= 0 AND COALESCE(notes,'') NOT LIKE '%[VOIDED]%' THEN amount ELSE 0 END) AS t FROM payments WHERE invoice_id = ?",
      payment.invoice_id,
    );
    const totalPaid = roundCents(remainingPaid?.t || 0);
    const invoiceTotal = Number(invoiceRow.total ?? 0);
    const rawAmountDue = roundCents(invoiceTotal - totalPaid);
    const displayAmountDue = Math.max(0, rawAmountDue);
    const newStatus = rawAmountDue <= 0 ? 'paid' : totalPaid > 0 ? 'partial' : 'unpaid';
    await adb.run(
      "UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?",
      totalPaid, displayAmountDue, newStatus, payment.invoice_id,
    );
  }

  audit(req.db, 'payment_reversed', req.user!.id, req.ip || 'unknown', {
    payment_id: paymentId,
    invoice_id: payment.invoice_id,
    amount: Number(payment.amount),
    age_minutes: Math.floor(ageMs / 60000),
    reason: reasonRaw,
  });

  const updatedInvoice = await getInvoiceDetail(adb, payment.invoice_id);
  res.json({ success: true, data: updatedInvoice });
});

// POST /invoices/:id/void (rate limited: 1 per minute per user)
// SA5-1: rate-limit state lives in the tenant DB `rate_limits` table so
// restarts / crashes / multi-process runs cannot reset the window. Category
// is `invoice_void`, key is the user id as string, window 60s, max 1 attempt.
// SEC-H25: voiding is destructive — gate behind invoices.void permission. The
// inline role check below is kept as defence-in-depth.
router.post('/:id/void', requirePermission('invoices.void'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  // Defence-in-depth: requirePermission above is authoritative; this role check
  // ensures deployments without a custom-role matrix still enforce manager+.
  if (req.user!.role !== 'admin' && req.user!.role !== 'manager') {
    throw new AppError('Only admins and managers can void invoices', 403);
  }
  const userId = req.user!.id;
  if (!checkWindowRate(db, 'invoice_void', String(userId), 1, 60000)) {
    throw new AppError('Can only void one invoice per minute', 429);
  }

  // SCAN-754: Atomic state-machine void — single conditional UPDATE eliminates
  // the TOCTOU window between the prior SELECT-then-UPDATE pattern. The WHERE
  // clause is the authoritative state guard; 'void' is the only terminal state
  // that must be blocked here (paid→void is a legal transition per the map).
  const voidResult = await adb.run(
    "UPDATE invoices SET status = 'void', amount_paid = 0, amount_due = 0, updated_at = datetime('now') WHERE id = ? AND status != 'void'",
    req.params.id,
  );

  if (voidResult.changes === 0) {
    const existing = await adb.get<{ status: string }>('SELECT status FROM invoices WHERE id = ?', req.params.id);
    if (!existing) throw new AppError('Invoice not found', 404);
    throw new AppError(`cannot void invoice in ${existing.status} status`, 409);
  }

  // S7: Restore stock for EVERY voided invoice with inventory line items,
  // regardless of ticket_id. POS invoices attached to tickets previously
  // skipped this branch, leaving stock permanently decremented on void.
  // Iterate all line items with a non-null inventory_item_id and credit stock back.
  const lineItems = await adb.all<any>(
    'SELECT inventory_item_id, quantity FROM invoice_line_items WHERE invoice_id = ? AND inventory_item_id IS NOT NULL',
    req.params.id,
  );
  for (const li of lineItems) {
    const itemExists = await adb.get<{ id: number }>(
      'SELECT id FROM inventory_items WHERE id = ?',
      li.inventory_item_id,
    );
    if (!itemExists) {
      logger.warn('void: stock movement skipped — inventory_item not found', { id: li.inventory_item_id });
      continue;
    }
    await adb.run(
      "UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime('now') WHERE id = ?",
      li.quantity, li.inventory_item_id,
    );
    await adb.run(`
      INSERT INTO stock_movements (inventory_item_id, quantity, type, reason, reference_type, reference_id, user_id)
      VALUES (?, ?, 'adjustment', 'Invoice voided — stock restored', 'invoice', ?, ?)
    `, li.inventory_item_id, li.quantity, req.params.id, req.user!.id);
  }

  // Mark payments as voided (keep records for audit trail)
  await adb.run("UPDATE payments SET notes = COALESCE(notes || ' ', '') || '[VOIDED]' WHERE invoice_id = ?", req.params.id);

  // Reverse commissions for the voided invoice (full reversal, fraction=1).
  // Best-effort: payroll-lock throws AppError which we propagate; other errors
  // are logged but do not roll back the void because the void itself is
  // already committed above.
  try {
    await reverseCommission(adb, {
      sourceType: 'invoice',
      sourceId: Number(req.params.id),
      fraction: 1,
      at: new Date().toISOString().replace('T', ' ').substring(0, 19),
    });
  } catch (err: unknown) {
    if (err instanceof AppError) throw err;
    logger.warn('invoices_reverse_commissions_failed', {
      invoice_id: req.params.id,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  recordWindowFailure(db, 'invoice_void', String(userId), 60000);
  audit(db, 'invoice_voided', req.user!.id, req.ip || 'unknown', { invoice_id: Number(req.params.id) });
  broadcast(WS_EVENTS.INVOICE_UPDATED, { id: Number(req.params.id), status: 'void' }, req.tenantSlug || null);
  res.json({ success: true, data: { message: 'Invoice voided, stock restored' } });
});

// ===================================================================
// POST /bulk-action - Batch invoice actions
// ===================================================================
// SEC-H25: bulk invoice actions (mark_paid, void, send_reminder) are privileged
// — gate behind invoices.bulk_action permission.
router.post('/bulk-action', requirePermission('invoices.bulk_action'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;

  const { invoice_ids, action } = req.body;
  if (!invoice_ids || !Array.isArray(invoice_ids) || invoice_ids.length === 0) {
    throw new AppError('invoice_ids array is required', 400);
  }
  if (invoice_ids.length > 100) {
    throw new AppError('Maximum 100 invoices per batch', 400);
  }

  const validActions = ['send_reminder', 'mark_paid', 'void'];
  if (!validActions.includes(action)) {
    throw new AppError(`Invalid action. Must be one of: ${validActions.join(', ')}`, 400);
  }

  let successCount = 0;
  let failCount = 0;
  const errors: Array<{ invoice_id: number; error: string }> = [];

  for (const id of invoice_ids) {
    try {
      const invoice = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', id);
      if (!invoice) {
        failCount++;
        errors.push({ invoice_id: id, error: 'Invoice not found' });
        continue;
      }

      switch (action) {
        case 'send_reminder': {
          if (invoice.status === 'paid' || invoice.status === 'void') {
            failCount++;
            errors.push({ invoice_id: id, error: `Cannot send reminder for ${invoice.status} invoice` });
            continue;
          }
          // WEB-W2-001: actually dispatch reminder via SMS + email
          const reminderCustomer = invoice.customer_id
            ? await adb.get<{ phone: string | null; mobile: string | null; email: string | null; first_name: string | null }>
                ('SELECT phone, mobile, email, first_name FROM customers WHERE id = ?', invoice.customer_id)
            : null;
          const reminderMsg = `Hi ${reminderCustomer?.first_name || 'there'}, your invoice ${invoice.order_id || `#${invoice.id}`} for $${Number(invoice.amount_due ?? invoice.total).toFixed(2)} is overdue. Please contact us to arrange payment.`;
          const reminderPhone = reminderCustomer?.mobile || reminderCustomer?.phone;
          if (reminderPhone) {
            try {
              await sendSmsTenant(db, (req as any).tenantSlug ?? null, reminderPhone, reminderMsg);
            } catch (smsErr) {
              logger.warn('[invoices] bulk reminder SMS failed', { invoice_id: id, error: smsErr instanceof Error ? smsErr.message : String(smsErr) });
            }
          }
          if (reminderCustomer?.email && isEmailConfigured(db)) {
            try {
              await sendEmail(db, {
                to: reminderCustomer.email,
                subject: `Payment reminder: invoice ${invoice.order_id || invoice.id}`,
                html: `<p>${reminderMsg.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</p>`,
                text: reminderMsg,
              });
            } catch (emailErr) {
              logger.warn('[invoices] bulk reminder email failed', { invoice_id: id, error: emailErr instanceof Error ? emailErr.message : String(emailErr) });
            }
          }
          await adb.run("UPDATE invoices SET reminder_sent_at = datetime('now'), updated_at = datetime('now') WHERE id = ?", id);
          successCount++;
          break;
        }
        case 'mark_paid': {
          if (invoice.status === 'void') {
            failCount++;
            errors.push({ invoice_id: id, error: 'Cannot mark voided invoice as paid' });
            continue;
          }
          if (invoice.status === 'paid') {
            failCount++;
            errors.push({ invoice_id: id, error: 'Already paid' });
            continue;
          }
          // Record a payment for the actual remaining balance. This mirrors
          // POST /:id/payments by deriving amount_paid from payment rows rather
          // than trusting possibly stale invoice.amount_due.
          const remaining = await getInvoiceRemainingBalance(adb, invoice);
          // @audit-fixed: validate the payment amount before insert. Previously a corrupt
          // invoice row with NaN amount_due / total would write NaN into payments.
          if (!Number.isFinite(remaining) || remaining <= 0) {
            failCount++;
            errors.push({ invoice_id: id, error: 'Invalid invoice balance — cannot mark paid' });
            continue;
          }
          await recordInvoicePayment({
            adb,
            db,
            invoiceId: id,
            invoice,
            amount: remaining,
            method: 'cash',
            notes: 'Bulk mark-paid',
            paymentType: 'payment',
            userId: req.user!.id,
            tenantSlug: req.tenantSlug || null,
            deduplicate: true,
          });

          successCount++;
          break;
        }
        case 'void': {
          if (invoice.status === 'void') {
            failCount++;
            errors.push({ invoice_id: id, error: 'Already voided' });
            continue;
          }
          // SEC-H113: assert transition is legal
          const voidAllowed = LEGAL_INVOICE_TRANSITIONS[invoice.status];
          if (voidAllowed !== undefined && !voidAllowed.includes('void')) {
            failCount++;
            errors.push({ invoice_id: id, error: `Cannot transition invoice from '${invoice.status}' to 'void'` });
            continue;
          }
          await adb.run(
            "UPDATE invoices SET status = 'void', amount_paid = 0, amount_due = 0, updated_at = datetime('now') WHERE id = ?",
            id,
          );
          // SEC-H48: bulk-void must restore stock the same way the single
          // /:id/void path (invoices.routes.ts:674 S7) does, otherwise a
          // manager using the bulk path permanently decrements inventory
          // on every voided row. Same line-item iteration + stock-movement
          // audit rows so either void path lands the shop in the same
          // state.
          const voidLineItems = await adb.all<any>(
            'SELECT inventory_item_id, quantity FROM invoice_line_items WHERE invoice_id = ? AND inventory_item_id IS NOT NULL',
            id,
          );
          for (const li of voidLineItems) {
            await adb.run(
              "UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime('now') WHERE id = ?",
              li.quantity, li.inventory_item_id,
            );
            await adb.run(
              `INSERT INTO stock_movements (inventory_item_id, quantity, type, reason, reference_type, reference_id, user_id)
               VALUES (?, ?, 'adjustment', 'Invoice bulk-voided — stock restored', 'invoice', ?, ?)`,
              li.inventory_item_id, li.quantity, id, req.user!.id,
            );
          }
          await adb.run("UPDATE payments SET notes = COALESCE(notes || ' ', '') || '[VOIDED]' WHERE invoice_id = ?", id);
          successCount++;
          break;
        }
      }
    } catch (err: unknown) {
      failCount++;
      const msg = err instanceof Error ? err.message : 'Unknown error';
      errors.push({ invoice_id: id, error: msg });
    }
  }

  audit(db, 'invoice_bulk_action', req.user!.id, req.ip || 'unknown', {
    action,
    invoice_ids,
    success_count: successCount,
    fail_count: failCount,
  });

  // Broadcast updates for affected invoices
  for (const id of invoice_ids) {
    broadcast(WS_EVENTS.INVOICE_UPDATED, { id }, req.tenantSlug || null);
  }

  res.json({
    success: true,
    data: {
      success_count: successCount,
      fail_count: failCount,
      errors: errors.length > 0 ? errors : undefined,
    },
  });
});

// ===================================================================
// POST /:id/credit-note - Generate credit note for an invoice
// ===================================================================
// SEC-H25: credit notes modify the invoice ledger — gate behind invoices.credit_note.
// WEB-UIUX-1294: idempotent middleware coalesces duplicate POSTs (slow-network
// double-click) onto a single CRN row + audit entry + broadcast.
router.post('/:id/credit-note', idempotent, requirePermission('invoices.credit_note'), async (req: Request<{ id: string }>, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  // @audit-fixed: validate id and use radix 10. Previously parseInt("abc") = NaN
  // hit the SELECT and silently returned no row → 404 (which masked the bad input).
  const invoiceId = parseInt(req.params.id, 10);
  if (!Number.isInteger(invoiceId) || invoiceId <= 0) throw new AppError('Invalid invoice ID', 400);

  const original = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', invoiceId);
  if (!original) throw new AppError('Invoice not found', 404);
  if (original.status === 'void') throw new AppError('Cannot create credit note for voided invoice', 400);

  // V7-style: strictly positive amount
  const amount = validatePositiveAmount(req.body.amount, 'credit note amount');
  const { reason } = req.body;
  // WEB-W2-018: structured refund reason code + free-text note (migration 150
  // added credit_note_code / credit_note_note columns to invoices). Both are
  // optional — existing callers that only send `reason` still work fine.
  // WEB-UIUX-1221: code must be one of the RefundReasonCode enum values; the
  // UI sends from a fixed dropdown but curl/integration callers could submit
  // arbitrary strings and pollute reporting aggregations with unbounded
  // cardinality. Reject anything outside the enum.
  // WEB-UIUX-1290: enum widened with the retail-cluster reasons the audit
  // flagged (cancelled service, exchange-no-money, tax adjustment, shipping
  // issue, loyalty/promo retroactive). Each maps cleanly to a downstream
  // report bucket; staff no longer have to fall through to 'other' for the
  // most-frequent real-world cases.
  const REFUND_REASON_CODES = new Set([
    'defective', 'dissatisfaction', 'wrong_item', 'duplicate_charge',
    'price_adjustment', 'failed_repair', 'lost_data', 'extended_delay',
    'goodwill_gesture', 'chargeback_prevention', 'warranty_invocation',
    'cancelled_service', 'exchange_no_refund', 'tax_adjustment',
    'shipping_issue', 'loyalty_promo_retroactive',
    'other',
  ]);
  const cnCodeRaw = typeof req.body.code === 'string' ? req.body.code.trim() : '';
  if (cnCodeRaw && !REFUND_REASON_CODES.has(cnCodeRaw)) {
    throw new AppError(
      `Invalid credit-note code "${cnCodeRaw}". Must be one of: ${[...REFUND_REASON_CODES].join(', ')}`,
      400,
    );
  }
  const cnCode: string | null = cnCodeRaw || null;
  // WEB-UIUX-1217: "other" without a note is useless for downstream reporting
  // (the audit row stores literal "other" with no context). Server enforces
  // the minimum so curl callers can't bypass the client validation.
  if (cnCode === 'other') {
    const noteForOther = typeof req.body.note === 'string' ? req.body.note.trim() : '';
    if (noteForOther.length < 5) {
      throw new AppError(
        'Credit-note code "other" requires a note of at least 5 characters explaining the reason.',
        400,
      );
    }
  }
  const cnNote: string | null = typeof req.body.note === 'string' && req.body.note.trim()
    ? req.body.note.trim()
    : null;
  if (amount > original.total) {
    throw new AppError('Credit note amount cannot exceed original invoice total', 400);
  }
  // @audit-fixed: aggregate prior credit notes against this invoice and refuse to
  // double-credit. Previously you could call POST /:id/credit-note twice for the
  // full amount each time and the original total was not tracked.
  const priorCredits = await adb.get<{ total_credit: number }>(
    'SELECT COALESCE(SUM(-total), 0) AS total_credit FROM invoices WHERE credit_note_for = ?',
    invoiceId,
  );
  const alreadyCredited = roundCents(priorCredits?.total_credit ?? 0);
  if (roundCents(alreadyCredited + amount) > roundCents(original.total)) {
    throw new AppError(
      `Credit note total would exceed invoice total (already credited ${alreadyCredited.toFixed(2)} of ${Number(original.total).toFixed(2)})`,
      400,
    );
  }
  // WEB-UIUX-733: server now derives `reason` from `code` + `note` when the
  // caller ships only the structured fields. Composed-reason callers (legacy
  // clients, curl callers) keep working unchanged. New clients no longer have
  // to duplicate `"code: note"` into a `reason` string.
  let resolvedReason: string;
  if (reason && typeof reason === 'string' && reason.trim().length > 0) {
    resolvedReason = reason.trim();
  } else if (cnCode || cnNote) {
    resolvedReason = [cnCode, cnNote].filter(Boolean).join(': ').trim() || 'Credit note';
  } else {
    throw new AppError('reason (or code + note) is required', 400);
  }

  // I5: Atomic counter for the credit-note ID. Replaces the MAX-based lookup
  // that was both racy and poisonable.
  const cnSeq = allocateCounter(db, 'credit_note_id');
  const orderId = formatCreditNoteId(cnSeq);

  // WEB-UIUX-1277: split the refunded amount into subtotal + tax portions
  // proportionally so the credit-note row mirrors the original invoice's
  // tax composition. Previously `total_tax=0` left state sales-tax filings
  // showing collected tax with no offsetting refund — customers ended up
  // short by the tax amount or the till covered it. Pro-rata against the
  // original invoice's tax/total ratio.
  const origTotal = Number(original.total) || 0;
  const origTax = Number(original.total_tax) || 0;
  const taxFraction = origTotal > 0 ? Math.max(0, Math.min(1, origTax / origTotal)) : 0;
  const cnTaxPortion = roundCents(amount * taxFraction);
  const cnSubtotalPortion = roundCents(amount - cnTaxPortion);

  // WEB-UIUX-895: snapshot for the credit-note invoice so its reprint
  // doesn't bleed live customer/store renames into a historical refund.
  const pitCn = await getInvoicePitSnapshot(adb, original.customer_id);

  // Create the credit note as a negative invoice
  const cnResult = await adb.run(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
      amount_paid, amount_due, notes, credit_note_for, status, created_by, location_id,
      credit_note_code, credit_note_note,
      customer_name_snapshot, customer_address_snapshot, store_name_snapshot, tax_jurisdiction_snapshot)
    VALUES (?, ?, ?, ?, 0, ?, ?, 0, 0, ?, ?, 'paid', ?, ?, ?, ?, ?, ?, ?, ?)
  `,
    orderId,
    original.customer_id,
    original.ticket_id,
    -cnSubtotalPortion,    // negative subtotal (pre-tax portion of refund)
    -cnTaxPortion,         // negative tax (proportional share of refund)
    -amount,               // negative total
    // WEB-UIUX-1225: stop writing `Credit note: ${reason}` into `notes` for
    // new credit-note rows. The dedicated `credit_note_code` +
    // `credit_note_note` columns (set immediately below) are now the
    // single source of truth. Pre-2026-05-12 rows still carry the composed
    // string in `notes` for backwards-compat; reports must prefer
    // `credit_note_code` when present and fall back to `notes` only for
    // legacy rows where `credit_note_code IS NULL`.
    null,
    invoiceId,             // link to original
    req.user!.id,
    original.location_id ?? 1,
    cnCode,
    cnNote,
    pitCn.customer_name_snapshot,
    pitCn.customer_address_snapshot,
    pitCn.store_name_snapshot,
    pitCn.tax_jurisdiction_snapshot,
  );

  const creditNoteId = cnResult.lastInsertRowid;

  // Add a single line item for the credit
  await adb.run(`
    INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, total, notes)
    VALUES (?, ?, 1, ?, ?, ?)
  `, creditNoteId, `Credit note for invoice #${original.order_id}`, -amount, -amount, resolvedReason);

  // WEB-UIUX-1026: also write a refunds row of type='credit_note' so the
  // /refunds reporting surface and "show me all refunds processed today"
  // queries reconcile with the invoices-table credit-note records.
  // Previously credit notes were invisible to refunds reporting and the two
  // surfaces never matched.
  try {
    await adb.run(`
      INSERT INTO refunds (invoice_id, ticket_id, customer_id, amount, type, reason, method, status, approved_by, created_by)
      VALUES (?, ?, ?, ?, 'credit_note', ?, 'store_credit', 'completed', ?, ?)
    `,
      invoiceId,
      original.ticket_id ?? null,
      original.customer_id ?? null,
      amount,
      resolvedReason,
      req.user!.id,
      req.user!.id,
    );
  } catch (refundsErr) {
    logger.warn('invoices_credit_note_refund_row_failed', {
      error: refundsErr instanceof Error ? refundsErr.message : String(refundsErr),
      credit_note_id: Number(creditNoteId),
    });
  }

  // WEB-UIUX-1208: stop inflating `amount_paid` to drive `amount_due` to zero.
  // The credit-note value lands in the dedicated `amount_credited` column
  // (migration 196). `amount_paid` keeps tracking real cash collected; the
  // combined ledger (amount_paid + amount_credited) is what zeroes amount_due.
  //
  // Overflow semantics: when the cumulative credit exceeds (total - amount_paid)
  // we still post the excess to store credit (existing behaviour) so the
  // refund is honoured even on already-collected balances. The overflow
  // calculation is now driven by the remaining ledger gap, not by inflating
  // amount_paid past total.
  const prevAmountPaid = roundCents(original.amount_paid || 0);
  const prevAmountCredited = roundCents(Number((original as { amount_credited?: number }).amount_credited) || 0);
  const total = roundCents(original.total);
  // How much of `amount` is absorbed by the invoice itself vs. parked as
  // store-credit overflow:
  const ledgerSlotRemaining = Math.max(0, roundCents(total - prevAmountPaid - prevAmountCredited));
  const absorbedByInvoice = Math.min(amount, ledgerSlotRemaining);
  const creditOverflow = roundCents(amount - absorbedByInvoice);
  const newAmountCredited = roundCents(prevAmountCredited + absorbedByInvoice);
  const newAmountDue = Math.max(0, roundCents(total - prevAmountPaid - newAmountCredited));

  // WEB-UIUX-708: when the cumulative credit-note total covers the full
  // invoice, mark the source invoice 'refunded' rather than 'paid'. Status
  // ladder now derives from combined ledger so `paid` requires real cash
  // OR offset that fully covers `total`.
  const totalCreditedAfter = roundCents(alreadyCredited + amount);
  const fullyRefunded = totalCreditedAfter >= total;
  const combinedLedger = roundCents(prevAmountPaid + newAmountCredited);
  const newStatus = fullyRefunded
    ? 'refunded'
    : combinedLedger >= total
      ? 'paid'
      : prevAmountPaid > 0
        ? 'partial'
        : 'unpaid';

  // SEC-H113: enforce state-machine transition before writing.
  // 'unpaid' → 'refunded' is not in the standard map; allow it via
  // a defensive intermediate to 'paid' since the combined ledger covers total.
  if (original.status === 'unpaid' && newStatus === 'refunded') {
    assertInvoiceTransition(original.status, 'paid');
  } else {
    assertInvoiceTransition(original.status, newStatus);
  }

  await adb.run(`
    UPDATE invoices SET amount_credited = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
  `, newAmountCredited, newAmountDue, newStatus, invoiceId);

  // Record overflow (the part of the credit that exceeded the remaining balance)
  // as a store credit for this customer.
  if (creditOverflow > 0 && original.customer_id) {
    try {
      // BUGHUNT-2026-05-10-02: atomic UPSERT — previous SELECT-then-UPDATE
      // raced identically to the overpayment path. UNIQUE(customer_id)
      // from migration 109 makes ON CONFLICT DO UPDATE safe.
      await adb.run(
        `INSERT INTO store_credits (customer_id, amount)
         VALUES (?, ?)
         ON CONFLICT(customer_id) DO UPDATE SET
           amount = ROUND((store_credits.amount + excluded.amount) * 100) / 100,
           updated_at = datetime('now')`,
        original.customer_id,
        creditOverflow,
      );
      // SEC-M33: this transaction is specifically the OVERFLOW portion of a
      // credit note that exceeded the invoice balance — not a plain credit
      // applied to the invoice. reference_type previously said 'invoice'
      // which made ledger drill-downs and reconciliation tools treat it as
      // if it credited the invoice directly; it didn't. Use a dedicated
      // reference_type so reports can isolate overflow credits from
      // normal invoice-to-credit moves.
      await adb.run(`
        INSERT INTO store_credit_transactions
          (customer_id, amount, type, reference_type, reference_id, notes, user_id)
        VALUES (?, ?, 'manual_credit', 'credit_note_overflow', ?, ?, ?)
      `,
        original.customer_id,
        creditOverflow,
        invoiceId,
        `Credit note overflow for invoice ${original.order_id}`,
        req.user!.id,
      );
    } catch (creditErr: unknown) {
      const msg = creditErr instanceof Error ? creditErr.message : String(creditErr);
      logger.warn('invoices_credit_note_overflow_store_credit_failed', { error: msg });
    }
  }
  // WEB-UIUX-1022: reverse commissions for the credit-noted portion. The
  // refunds.routes.ts approve path already calls reverseCommission;
  // credit-note (the only currently-reachable refund flow from the web UI)
  // skipped this, so techs kept full commission on returned/credited work
  // and payroll overpaid. Reverse proportional to amount / original.total
  // so partial credits don't claw back the full commission. Both ticket and
  // invoice sources are reversed since commissions can attach to either.
  try {
    const originalTotal = Number(original.total) || 0;
    if (originalTotal > 0) {
      const fraction = Math.min(1, Math.max(0, amount / originalTotal));
      if (fraction > 0) {
        await reverseCommission(adb, {
          sourceType: 'invoice',
          sourceId: invoiceId,
          fraction,
          notes: `Credit note ${orderId} for invoice ${original.order_id}`,
        });
        if (original.ticket_id) {
          await reverseCommission(adb, {
            sourceType: 'ticket',
            sourceId: original.ticket_id,
            fraction,
            notes: `Credit note ${orderId} for invoice ${original.order_id}`,
          });
        }
      }
    }
  } catch (commErr) {
    // Payroll-lock is a 403 we want to surface — otherwise log and continue.
    if (commErr instanceof AppError && commErr.statusCode === 403) throw commErr;
    logger.warn('invoices_credit_note_commission_reversal_failed', {
      error: commErr instanceof Error ? commErr.message : String(commErr),
      invoice_id: invoiceId,
      credit_note_id: Number(creditNoteId),
    });
  }

  const creditNote = await getInvoiceDetail(adb, creditNoteId as number);

  audit(db, 'credit_note_created', req.user!.id, req.ip || 'unknown', {
    credit_note_id: Number(creditNoteId),
    original_invoice_id: invoiceId,
    amount,
    reason: resolvedReason,
    code: cnCode,
  });

  broadcast(WS_EVENTS.INVOICE_CREATED, creditNote, req.tenantSlug || null);
  broadcast(WS_EVENTS.INVOICE_UPDATED, { id: invoiceId }, req.tenantSlug || null);

  // WEB-UIUX-1032: surface the overflow portion so the client can show
  // "Customer now has $X store credit" instead of silently parking the
  // excess on the store_credits row. Also expose the new running balance
  // when there is one, so a single toast can summarise the outcome.
  let store_credit_balance: number | null = null;
  if (creditOverflow > 0 && original.customer_id) {
    try {
      const credit = await adb.get<{ amount: number }>(
        'SELECT amount FROM store_credits WHERE customer_id = ?',
        original.customer_id,
      );
      store_credit_balance = credit ? Number(credit.amount) : null;
    } catch { /* non-fatal */ }
  }

  res.status(201).json({
    success: true,
    data: creditNote,
    meta: {
      credit_overflow: creditOverflow,
      store_credit_balance,
    },
  });
});

// POST /invoices/:id/send-receipt — dispatch the post-sale receipt via SMS
// or email. Called from the POS receipt screen ("SMS" / "Email" buttons).
// Body: { channel: 'sms' | 'email', recipient?: string }
//   - channel selects the transport.
//   - recipient overrides the on-file address; omit to use the invoice
//     customer's mobile (sms) or email.
// SEC: requires `invoices.view` since the receipt mirrors data the operator
// can already see; we audit the dispatch and log only redacted recipient
// info (phone last-4, email domain) so the audit trail isn't a PII honey
// pot. Touches no invoice rows — re-sending a receipt is non-mutating.
router.post('/:id/send-receipt', requirePermission('invoices.view'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const invoiceId = validateId(req.params.id, 'invoice_id');

  const channel = req.body?.channel;
  if (channel !== 'sms' && channel !== 'email') {
    throw new AppError("channel must be 'sms' or 'email'", 400);
  }
  const recipientOverride =
    typeof req.body?.recipient === 'string' ? req.body.recipient.trim() : '';

  const invoice = await adb.get<{
    id: number;
    order_id: string | null;
    total: number;
    customer_id: number | null;
  }>('SELECT id, order_id, total, customer_id FROM invoices WHERE id = ?', invoiceId);
  if (!invoice) throw new AppError('Invoice not found', 404);

  const customer = invoice.customer_id
    ? await adb.get<{
        phone: string | null;
        mobile: string | null;
        email: string | null;
        first_name: string | null;
      }>(
        'SELECT phone, mobile, email, first_name FROM customers WHERE id = ?',
        invoice.customer_id,
      )
    : null;

  const totalStr = Number(invoice.total ?? 0).toFixed(2);
  const orderId = invoice.order_id || `#${invoice.id}`;
  const firstName = customer?.first_name || 'there';
  const tenantSlug = (req as any).tenantSlug ?? null;

  if (channel === 'sms') {
    const to = recipientOverride || customer?.mobile || customer?.phone || '';
    if (!to) {
      throw new AppError('No phone number on file. Pass `recipient` in the body.', 400);
    }
    const msg = `Hi ${firstName}, here's your receipt for ${orderId}: $${totalStr}. Thank you for your business!`;
    let delivered = false;
    try {
      const result = await sendSmsTenant(db, tenantSlug, to, msg);
      delivered = !!result;
    } catch (err) {
      throw new AppError(
        err instanceof Error ? err.message : 'SMS send failed',
        502,
      );
    }
    audit(db, 'receipt_sent', req.user?.id ?? null, req.ip ?? 'unknown', {
      invoice_id: invoiceId,
      channel: 'sms',
      to_last4: to.replace(/\D/g, '').slice(-4),
      delivered,
    });
    res.json({
      success: true,
      data: { delivered, channel: 'sms', to_last4: to.replace(/\D/g, '').slice(-4) },
    });
    return;
  }

  // channel === 'email'
  const to = recipientOverride || customer?.email || '';
  if (!to) {
    throw new AppError('No email on file. Pass `recipient` in the body.', 400);
  }
  if (!isEmailConfigured(db)) {
    throw new AppError('Email transport not configured', 503);
  }
  const escape = (s: string): string =>
    String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const subject = `Receipt ${orderId}`;
  const html =
    `<p>Hi ${escape(firstName)},</p>` +
    `<p>Here's your receipt for <strong>${escape(orderId)}</strong>:</p>` +
    `<p style="font-size:20px;font-weight:bold">$${escape(totalStr)}</p>` +
    `<p>Thank you for your business.</p>`;
  const text = `Hi ${firstName},\n\nHere's your receipt for ${orderId}: $${totalStr}.\n\nThank you for your business.`;
  let delivered = false;
  try {
    delivered = await sendEmail(db, { to, subject, html, text });
  } catch (err) {
    throw new AppError(
      err instanceof Error ? err.message : 'Email send failed',
      502,
    );
  }
  const toDomain = to.includes('@') ? (to.split('@')[1] ?? 'unknown') : 'unknown';
  audit(db, 'receipt_sent', req.user?.id ?? null, req.ip ?? 'unknown', {
    invoice_id: invoiceId,
    channel: 'email',
    to_domain: toDomain,
    delivered,
  });
  res.json({
    success: true,
    data: { delivered, channel: 'email', to_domain: toDomain },
  });
});

export default router;
