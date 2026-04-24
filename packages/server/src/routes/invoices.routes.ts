import { Router, Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
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
import { allocateCounter, formatInvoiceOrderId, formatCreditNoteId } from '../utils/counters.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { runAutomations } from '../services/automations.js';
import { idempotent } from '../middleware/idempotency.js';
import { audit } from '../utils/audit.js';
import { fireWebhook } from '../services/webhooks.js';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { accruePaymentPoints } from '../services/notifications.js';
import { recordCustomerInteraction } from '../services/customerHealthScore.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import { logActivity } from '../utils/activityLog.js';
import { trackInterval } from '../utils/trackInterval.js';

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
      u.first_name || ' ' || u.last_name as created_by_name
    FROM invoices inv
    LEFT JOIN customers c ON c.id = inv.customer_id
    LEFT JOIN users u ON u.id = inv.created_by
    WHERE inv.id = ?
  `, id);
  if (!invoice) return null;

  const [line_items, payments, deposit_invoices] = await Promise.all([
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
  ]);

  return { ...invoice, line_items, payments, deposit_invoices };
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

  // Webhook
  fireWebhook(db, 'payment_received', {
    invoice_id: Number(invoice.id),
    amount: paymentAmount,
    method: paymentMethod,
  });
}

// GET /invoices
router.get('/', requirePermission('invoices.view'), async (req, res) => {
  const adb = req.asyncDb;
  const { page = '1', pagesize = '20', status, from_date, to_date, keyword, customer_id, location_id } = req.query as Record<string, string>;
  const p = Math.max(1, parseInt(page));
  const ps = Math.min(250, Math.max(1, parseInt(pagesize)));
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: any[] = [];

  if (status === 'overdue') {
    where += " AND inv.status IN ('unpaid','partial') AND inv.due_on IS NOT NULL AND inv.due_on < DATE('now')";
  } else if (status) { where += ' AND inv.status = ?'; params.push(status); }
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
      ORDER BY inv.created_at DESC
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
router.get('/stats', requirePermission('invoices.view'), async (req, res) => {
  const adb = req.asyncDb;

  const [kpis, statusDist, methodDist] = await Promise.all([
    adb.get<any>(`
      SELECT
        COALESCE(SUM(total), 0) AS total_sales,
        COUNT(*) AS invoice_count,
        COALESCE(SUM(total_tax), 0) AS tax_collected,
        COALESCE(SUM(CASE WHEN status IN ('unpaid','partial') THEN amount_due ELSE 0 END), 0) AS outstanding_receivables
      FROM invoices WHERE status != 'void'
    `),
    adb.all<any>(`
      SELECT status, COUNT(*) AS count FROM invoices GROUP BY status
    `),
    adb.all<any>(`
      SELECT p.method, COUNT(*) AS count, COALESCE(SUM(p.amount), 0) AS total
      FROM payments p
      JOIN invoices inv ON inv.id = p.invoice_id
      WHERE inv.status != 'void'
      GROUP BY p.method
    `),
  ]);

  res.json({
    success: true,
    data: {
      kpis,
      status_distribution: statusDist,
      method_distribution: methodDist,
    },
  });
});

// GET /invoices/:id
router.get('/:id', async (req, res) => {
  const adb = req.asyncDb;
  const invoice = await getInvoiceDetail(adb, req.params.id);
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
  const nextSeq = allocateCounter(db, 'invoice_order_id');
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

  const result = await adb.run(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, discount_reason,
      total_tax, total, amount_paid, amount_due, notes, due_on, created_by,
      is_deposit, deposit_amount, parent_invoice_id, location_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?)
  `, orderId, customer_id, ticket_id || null, subtotal, appliedDiscount, discount_reason || null,
    total_tax, total, amount_due, notes || null, validatedDueDate, req.user!.id,
    depositFlag, depositAmount, parent_invoice_id || null, invoiceLocationId);

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

// POST /invoices/:id/payments
// SEC-H25: recording a payment is a financial write — gate behind invoices.record_payment.
router.post('/:id/payments', idempotent, requirePermission('invoices.record_payment'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const invoice = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', req.params.id);
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') throw new AppError('Cannot add payment to voided invoice', 400);

  // SEC-H26: if the client provides customer_id in the body, verify it matches
  // the invoice's customer. Prevents a caller from posting a payment against
  // invoice A while declaring customer B — the mismatch could be a UI bug
  // (wrong screen state), a forged request, or an account-mixing attack that
  // shifts credit onto the wrong ledger.
  if (req.body?.customer_id !== undefined && req.body.customer_id !== null) {
    const bodyCustomerId = validateId(req.body.customer_id, 'customer_id');
    if (bodyCustomerId !== invoice.customer_id) {
      throw new AppError('customer_id does not match invoice.customer_id', 400);
    }
  }

  const { method = 'cash', method_detail, transaction_id, notes, payment_type = 'payment' } = req.body;
  // V7: Strictly positive (> 0). Rejects 0, -0.01, NaN, Infinity deterministically.
  const amount = validatePositiveAmount(req.body.amount, 'payment amount');

  // Validate payment_type
  const validPaymentTypes = ['payment', 'deposit'];
  if (!validPaymentTypes.includes(payment_type)) {
    throw new AppError(`Invalid payment_type. Must be one of: ${validPaymentTypes.join(', ')}`, 400);
  }

  // Double-submit guard: same invoice + amount within 5 seconds = reject
  // SEC-M9: In-memory fast check + DB-backed check (survives restart)
  const dedupKey = `${req.params.id}:${amount.toFixed(2)}:${req.user!.id}`;
  const lastPayment = recentPayments.get(dedupKey);
  if (lastPayment && Date.now() - lastPayment < 5000) {
    throw new AppError('Duplicate payment detected. Please wait before retrying.', 409);
  }
  // DB-backed dedup: check for same invoice+amount+user within last 10 seconds
  const recentDbPayment = await adb.get<any>(`
    SELECT id FROM payments
    WHERE invoice_id = ? AND ROUND(amount, 2) = ROUND(?, 2) AND user_id = ?
    AND created_at > datetime('now', '-10 seconds')
    LIMIT 1
  `, req.params.id, amount, req.user!.id);
  if (recentDbPayment) {
    throw new AppError('Duplicate payment detected. Please wait before retrying.', 409);
  }
  recentPayments.set(dedupKey, Date.now());

  const paymentResult = await adb.run(`
    INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id, notes, payment_type, user_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, req.params.id, amount, method, method_detail || null,
    transaction_id || null, notes || null, payment_type, req.user!.id);
  const paymentId = paymentResult.lastInsertRowid as number;

  // SCAN-757: CASE WHEN filters out NULL/negative rows so corrupt payment rows
  // cannot propagate NaN or negative values into the running total.
  const totalPaidRow = await adb.get<{ t: number }>('SELECT SUM(CASE WHEN amount IS NOT NULL AND amount >= 0 THEN amount ELSE 0 END) as t FROM payments WHERE invoice_id = ?', req.params.id);
  const totalPaidRaw = totalPaidRow?.t || 0;
  const totalPaid = roundCents(totalPaidRaw);
  const rawAmountDue = roundCents(invoice.total - totalPaid);

  // M9: Detect overpayment — if the customer paid more than the invoice total,
  // record the excess as a store credit (store_credits table exists per
  // migration 026_refunds_credits.sql). The displayed amount_due is clamped
  // to 0 so the ledger does not go negative.
  const overpayment = rawAmountDue < 0 ? roundCents(-rawAmountDue) : 0;
  const displayAmountDue = Math.max(0, rawAmountDue);
  const status = rawAmountDue <= 0 ? 'paid' : totalPaid > 0 ? 'partial' : 'unpaid';

  // SEC-H113: enforce state-machine transition before writing
  assertInvoiceTransition(invoice.status, status);

  await adb.run(`
    UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
  `, totalPaid, displayAmountDue, status, req.params.id);

  // Post-payment side effects: loyalty points, commission, activity log, webhook.
  // SCAN-623 / SCAN-627: extracted into shared helper so bulk path is identical.
  await postPaymentSideEffects({
    adb,
    db,
    invoice: { ...invoice, id: Number(req.params.id) },
    paymentId,
    paymentAmount: amount,
    paymentMethod: method,
    userId: req.user!.id,
  });

  // SCAN-524: update customer last_interaction_at + lifetime_value_cents (fire-and-forget)
  if (invoice.customer_id) {
    recordCustomerInteraction(adb, invoice.customer_id, toCents(amount)).catch(() => {});
  }

  if (overpayment > 0 && invoice.customer_id) {
    try {
      // Upsert the customer's running store-credit balance
      const existingCredit = await adb.get<{ id: number; amount: number }>(
        'SELECT id, amount FROM store_credits WHERE customer_id = ?',
        invoice.customer_id,
      );
      if (existingCredit) {
        await adb.run(
          "UPDATE store_credits SET amount = ?, updated_at = datetime('now') WHERE id = ?",
          roundCents((existingCredit.amount || 0) + overpayment),
          existingCredit.id,
        );
      } else {
        await adb.run(
          'INSERT INTO store_credits (customer_id, amount) VALUES (?, ?)',
          invoice.customer_id,
          overpayment,
        );
      }
      // Ledger row for the credit transaction
      await adb.run(`
        INSERT INTO store_credit_transactions
          (customer_id, amount, type, reference_type, reference_id, notes, user_id)
        VALUES (?, ?, 'manual_credit', 'invoice', ?, ?, ?)
      `,
        invoice.customer_id,
        overpayment,
        req.params.id,
        `Overpayment on invoice ${invoice.order_id}`,
        req.user!.id,
      );
    } catch (creditErr: unknown) {
      // Do not fail the payment flow if the credit insert fails — log and continue.
      logger.warn(`[invoices] failed to record overpayment store credit`, { err: creditErr });
    }
  }
  const updated = await getInvoiceDetail(adb, req.params.id as string);
  broadcast(WS_EVENTS.PAYMENT_RECEIVED, updated, req.tenantSlug || null);

  res.status(201).json({ success: true, data: updated });
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
// POST /bulk-action - Batch invoice actions (admin-only)
// ===================================================================
// SEC-H25: bulk invoice actions (mark_paid, void, send_reminder) are privileged
// — gate behind invoices.bulk_action permission. The inline role check below is
// kept as defence-in-depth.
router.post('/bulk-action', requirePermission('invoices.bulk_action'), async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;

  // Defence-in-depth: requirePermission above is authoritative.
  if (req.user!.role !== 'admin') {
    throw new AppError('Only admins can perform bulk invoice actions', 403);
  }

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
          // Mark reminder sent (actual email sending is async/external)
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
          // SEC-H113: assert transition is legal
          const allowed = LEGAL_INVOICE_TRANSITIONS[invoice.status];
          if (allowed !== undefined && !allowed.includes('paid')) {
            failCount++;
            errors.push({ invoice_id: id, error: `Cannot transition invoice from '${invoice.status}' to 'paid'` });
            continue;
          }
          // Record a payment for the remaining amount
          const remaining = invoice.amount_due > 0 ? invoice.amount_due : invoice.total;
          // @audit-fixed: validate the payment amount before insert. Previously a corrupt
          // invoice row with NaN amount_due / total would write NaN into payments.
          if (!Number.isFinite(Number(remaining)) || Number(remaining) <= 0) {
            failCount++;
            errors.push({ invoice_id: id, error: 'Invalid invoice balance — cannot mark paid' });
            continue;
          }
          const bulkPayResult = await adb.run(`
            INSERT INTO payments (invoice_id, amount, method, notes, user_id)
            VALUES (?, ?, 'cash', 'Bulk mark-paid', ?)
          `, id, remaining, req.user!.id);
          const bulkPaymentId = bulkPayResult.lastInsertRowid as number;

          await adb.run(`
            UPDATE invoices SET amount_paid = total, amount_due = 0, status = 'paid', updated_at = datetime('now') WHERE id = ?
          `, id);

          // SCAN-623 / SCAN-627: shared post-payment side effects
          await postPaymentSideEffects({
            adb,
            db,
            invoice: { ...invoice, id: Number(id) },
            paymentId: bulkPaymentId,
            paymentAmount: Number(remaining),
            paymentMethod: 'cash',
            userId: req.user!.id,
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
router.post('/:id/credit-note', requirePermission('invoices.credit_note'), async (req: Request<{ id: string }>, res) => {
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
  if (!reason || typeof reason !== 'string' || reason.trim().length === 0) {
    throw new AppError('reason is required', 400);
  }

  // I5: Atomic counter for the credit-note ID. Replaces the MAX-based lookup
  // that was both racy and poisonable.
  const cnSeq = allocateCounter(db, 'credit_note_id');
  const orderId = formatCreditNoteId(cnSeq);

  // Create the credit note as a negative invoice
  const cnResult = await adb.run(`
    INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
      amount_paid, amount_due, notes, credit_note_for, status, created_by, location_id)
    VALUES (?, ?, ?, ?, 0, 0, ?, 0, 0, ?, ?, 'paid', ?, ?)
  `,
    orderId,
    original.customer_id,
    original.ticket_id,
    -amount,       // negative subtotal
    -amount,       // negative total
    `Credit note: ${reason.trim()}`,
    invoiceId,     // link to original
    req.user!.id,
    original.location_id ?? 1,
  );

  const creditNoteId = cnResult.lastInsertRowid;

  // Add a single line item for the credit
  await adb.run(`
    INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, total, notes)
    VALUES (?, ?, 1, ?, ?, ?)
  `, creditNoteId, `Credit note for invoice #${original.order_id}`, -amount, -amount, reason.trim());

  // M5: Adjust the original invoice balance, CLAMPING newAmountPaid at total so
  // amount_due can never go negative. If the credit would push amount_paid past
  // the invoice total (i.e. credit > remaining due), record the overflow as a
  // store credit for the customer instead of silently hiding it in a negative
  // amount_due column.
  const prevAmountPaid = roundCents(original.amount_paid || 0);
  const requested = roundCents(prevAmountPaid + amount);
  const cappedAmountPaid = Math.min(requested, roundCents(original.total));
  const creditOverflow = roundCents(requested - cappedAmountPaid);
  const newAmountDue = Math.max(0, roundCents(original.total - cappedAmountPaid));
  const newStatus = newAmountDue <= 0 ? 'paid' : cappedAmountPaid > 0 ? 'partial' : 'unpaid';

  // SEC-H113: enforce state-machine transition before writing
  assertInvoiceTransition(original.status, newStatus);

  await adb.run(`
    UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
  `, cappedAmountPaid, newAmountDue, newStatus, invoiceId);

  // Record overflow (the part of the credit that exceeded the remaining balance)
  // as a store credit for this customer.
  if (creditOverflow > 0 && original.customer_id) {
    try {
      const existingCredit = await adb.get<{ id: number; amount: number }>(
        'SELECT id, amount FROM store_credits WHERE customer_id = ?',
        original.customer_id,
      );
      if (existingCredit) {
        await adb.run(
          "UPDATE store_credits SET amount = ?, updated_at = datetime('now') WHERE id = ?",
          roundCents((existingCredit.amount || 0) + creditOverflow),
          existingCredit.id,
        );
      } else {
        await adb.run(
          'INSERT INTO store_credits (customer_id, amount) VALUES (?, ?)',
          original.customer_id,
          creditOverflow,
        );
      }
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
  const creditNote = await getInvoiceDetail(adb, creditNoteId as number);

  audit(db, 'credit_note_created', req.user!.id, req.ip || 'unknown', {
    credit_note_id: Number(creditNoteId),
    original_invoice_id: invoiceId,
    amount,
    reason: reason.trim(),
  });

  broadcast(WS_EVENTS.INVOICE_CREATED, creditNote, req.tenantSlug || null);
  broadcast(WS_EVENTS.INVOICE_UPDATED, { id: invoiceId }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: creditNote });
});

export default router;
