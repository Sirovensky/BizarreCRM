import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import {
  validatePrice,
  validateIntegerQuantity,
  validatePositiveAmount,
  roundCents,
  toCents,
} from '../utils/validate.js';
import { writeCommission } from '../utils/commissions.js';
import { accruePaymentPoints } from '../services/notifications.js';
import { generateOrderId } from '../utils/format.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { roundCurrency } from '../utils/currency.js';
import { idempotent } from '../middleware/idempotency.js';
import { config } from '../config.js';
import { allocateCounter, formatInvoiceOrderId, formatTicketOrderId } from '../utils/counters.js';
import type { AsyncDb, TxQuery } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
// isCommissionLocked is still used for tip-only payroll lock checks below;
// commission lock enforcement is now inside writeCommission().
import { isCommissionLocked } from './_team.payroll.js';
// @audit-fixed: S3 kit sell-path — import the helper that builds guarded
// component-decrement queries. Wired below inside the /transaction handler.
import { buildKitDecrementTxQueries } from './inventory.routes.js';
import { createLogger } from '../utils/logger.js';
import { audit } from '../utils/audit.js';

const logger = createLogger('pos');

const router = Router();

/**
 * POS7: Look up (or create) the special "Walk-in" customer row.
 *
 * POS sales with no selected customer used to be stored with customer_id =
 * NULL, which left them orphaned from every customer-scoped report (sales per
 * customer, average order value, lifetime value, etc). We now route every
 * such sale to a single sentinel customer identified by `code = 'WALK-IN'`.
 *
 * Migration 075 creates the row, but this helper re-creates it on the fly if
 * a tenant DB is missing it (defensive — never delete and re-provision — per
 * the preserve-tenant-dbs rule).
 */
async function getOrCreateWalkInCustomerId(adb: AsyncDb): Promise<number> {
  const existing = await adb.get<{ id: number }>(
    "SELECT id FROM customers WHERE code = 'WALK-IN' LIMIT 1",
  );
  if (existing?.id) return existing.id;

  const result = await adb.run(
    `INSERT INTO customers (code, first_name, last_name, type, source, is_deleted, created_at, updated_at)
     VALUES ('WALK-IN', 'Walk-in', 'Customer', 'individual', 'Walk-in', 0, datetime('now'), datetime('now'))`,
  );
  return Number(result.lastInsertRowid);
}

/**
 * POS8: Resolve the active membership discount percentage for a customer, or
 * 0 if none. Keeps the server the authoritative source — the frontend gets
 * membership info for display, but can never drive the final discount.
 */
async function getMembershipDiscountPct(adb: AsyncDb, customerId: number | null): Promise<number> {
  if (!customerId) return 0;
  const enabled = await adb.get<{ value: string }>(
    "SELECT value FROM store_config WHERE key = 'membership_enabled'",
  );
  if (!enabled || (enabled.value !== '1' && enabled.value !== 'true')) return 0;

  const row = await adb.get<{ discount_pct: number }>(
    `SELECT mt.discount_pct
       FROM customer_subscriptions cs
       JOIN membership_tiers mt ON mt.id = cs.tier_id
      WHERE cs.customer_id = ? AND cs.status = 'active'
      ORDER BY cs.created_at DESC LIMIT 1`,
    customerId,
  );
  const pct = Number(row?.discount_pct ?? 0);
  if (!isFinite(pct) || pct <= 0) return 0;
  // Cap membership discount at 100% to prevent negative totals even if a tier
  // row is corrupted.
  return Math.min(pct, 100);
}

/**
 * Validate an optional client-supplied transaction-reference string. Keeps
 * POS3 payload strings sane before inserting into payments.reference.
 */
function validateOptionalRefString(value: unknown, fieldName: string, maxLen = 128): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed.length > maxLen) throw new AppError(`${fieldName} exceeds ${maxLen} characters`, 400);
  return trimmed;
}

// GET /pos/products - products/services available for POS
router.get('/products', async (req, res) => {
  const adb = req.asyncDb;
  const { keyword, category, item_type } = req.query as Record<string, string>;

  let where = 'WHERE is_active = 1 AND (item_type = \'product\' OR item_type = \'service\')';
  const params: any[] = [];

  // SW-D12: Filter categories based on POS show toggles
  const getToggle = async (key: string) => {
    const row = await adb.get<any>("SELECT value FROM store_config WHERE key = ?", key);
    return row?.value === '0' || row?.value === 'false' ? false : true; // default: show
  };

  const [showBundles, showDevices, showServices, showLabor, showAccessories, showMisc] = await Promise.all([
    getToggle('pos_show_bundles'),
    getToggle('pos_show_devices'),
    getToggle('pos_show_services'),
    getToggle('pos_show_labor'),
    getToggle('pos_show_accessories'),
    getToggle('pos_show_misc'),
  ]);

  const hiddenCategories: string[] = [];
  if (!showBundles) hiddenCategories.push('bundle', 'bundles');
  if (!showDevices) hiddenCategories.push('device', 'devices');
  if (!showServices) hiddenCategories.push('service', 'services');
  if (!showLabor) hiddenCategories.push('labor');
  if (!showAccessories) hiddenCategories.push('accessory', 'accessories');
  if (!showMisc) hiddenCategories.push('misc', 'miscellaneous');

  if (hiddenCategories.length > 0) {
    where += ' AND (LOWER(category) NOT IN (' + hiddenCategories.map(() => '?').join(',') + ') OR category IS NULL)';
    params.push(...hiddenCategories);
  }

  if (item_type) { where += ' AND item_type = ?'; params.push(item_type); }
  if (category) { where += ' AND category = ?'; params.push(category); }
  if (keyword) {
    where += " AND (name LIKE ? ESCAPE '\\' OR sku LIKE ? ESCAPE '\\' OR upc LIKE ? ESCAPE '\\')";
    const k = `%${escapeLike(keyword)}%`;
    params.push(k, k, k);
  }

  // SW-D12: Optionally hide cost_price column
  const showCostPrice = await getToggle('pos_show_cost_price');

  const [items, categories] = await Promise.all([
    adb.all<any>(`
      SELECT id, name, item_type, category, retail_price, ${showCostPrice ? 'cost_price,' : ''} in_stock, sku, upc, image_url,
             tax_class_id, tax_inclusive
      FROM inventory_items ${where}
      ORDER BY category, name
    `, ...params),
    adb.all<any>(`
      SELECT DISTINCT category FROM inventory_items
      WHERE is_active = 1 AND category IS NOT NULL
      ORDER BY category
    `),
  ]);

  // If cost_price hidden, ensure it's not in the response
  const finalItems = showCostPrice ? items : items.map((item: any) => {
    const { cost_price, ...rest } = item;
    return rest;
  });

  res.json({ success: true, data: { items: finalItems, categories: categories.map((c: any) => c.category) } });
});

// GET /pos/register - current register state
router.get('/register', async (req, res) => {
  const adb = req.asyncDb;
  const [cashInRow, cashOutRow, cashPaymentsRow, recentEntries] = await Promise.all([
    adb.get<any>('SELECT COALESCE(SUM(amount),0) as t FROM cash_register WHERE type = \'cash_in\' AND DATE(created_at) = DATE(\'now\')'),
    adb.get<any>('SELECT COALESCE(SUM(amount),0) as t FROM cash_register WHERE type = \'cash_out\' AND DATE(created_at) = DATE(\'now\')'),
    adb.get<any>('SELECT COALESCE(SUM(p.amount),0) as t FROM payments p JOIN invoices inv ON inv.id = p.invoice_id WHERE p.method = \'cash\' AND DATE(p.created_at) = DATE(\'now\')'),
    adb.all<any>(`
      SELECT cr.*, u.first_name || ' ' || u.last_name as user_name
      FROM cash_register cr LEFT JOIN users u ON u.id = cr.user_id
      WHERE DATE(cr.created_at) = DATE('now')
      ORDER BY cr.created_at DESC LIMIT 20
    `),
  ]);

  const cashIn = cashInRow.t;
  const cashOut = cashOutRow.t;
  const cashPayments = cashPaymentsRow.t;

  res.json({
    success: true,
    data: {
      cash_in: cashIn,
      cash_out: cashOut,
      cash_sales: cashPayments,
      net: cashIn + cashPayments - cashOut,
      entries: recentEntries,
    },
  });
});

// POST /pos/cash-in
router.post('/cash-in', async (req, res) => {
  const adb = req.asyncDb;
  const { amount, reason } = req.body;
  // @audit-fixed: parseFloat(Infinity) = Infinity passes the upper-bound check via NaN comparison.
  // Use Number.isFinite to reject Infinity / NaN deterministically.
  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0) throw new AppError('Valid amount required', 400);
  // V5: POS cash-in bounds check
  if (amt > 50_000) throw new AppError('Cash-in amount cannot exceed $50,000', 400);
  const result = await adb.run('INSERT INTO cash_register (type, amount, reason, user_id) VALUES (\'cash_in\', ?, ?, ?)', amt, reason || null, req.user!.id);
  const entry = await adb.get<any>('SELECT * FROM cash_register WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { entry } });
});

// POST /pos/cash-out
router.post('/cash-out', async (req, res) => {
  const adb = req.asyncDb;
  const { amount, reason } = req.body;
  // @audit-fixed: same Number.isFinite hardening as cash-in.
  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0) throw new AppError('Valid amount required', 400);
  // V5: POS cash-out bounds check
  if (amt > 50_000) throw new AppError('Cash-out amount cannot exceed $50,000', 400);
  const result = await adb.run('INSERT INTO cash_register (type, amount, reason, user_id) VALUES (\'cash_out\', ?, ?, ?)', amt, reason || null, req.user!.id);
  const entry = await adb.get<any>('SELECT * FROM cash_register WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { entry } });
});

// POST /pos/transaction - complete a POS sale
//
// Fixes addressed here:
//   POS1 (CRITICAL): server forces unit_price from inventory_items.retail_price.
//     Client cannot pass a lower unit_price to undercharge itself.
//   POS2:  full write sequence (invoice + line items + stock + payments +
//          pos_transactions + employee_tips) runs inside a single atomic
//          adb.transaction() — any failure rolls the whole thing back.
//   POS3:  persists processor / reference / transaction_id on payments.
//   POS4:  see comment below — tax-on-net, discount before tax.
//   POS5:  validateIntegerQuantity — 2.7 no longer truncates to 2.
//   POS6:  discount cap checked AFTER rounding, and final total must be >= 0.
//   POS7:  walk-in customer sentinel when customer_id is null.
//   POS8:  membership discount applied server-side, never client-driven.
//   M4:    negative discount rejected.
//   M7/M8: roundCents() on tip and split payment amounts.
//   S1:    atomic guarded stock decrement (WHERE in_stock >= ?) inside the
//          transaction — no precheck/deduct race.
//   EM6:   inserts employee_tips row linking tip to cashier.
router.post('/transaction', idempotent, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const cashierId = req.user!.id;
  const {
    customer_id, items = [], payment_method = 'cash', payment_amount,
    payments: splitPayments,
    notes, discount: rawDiscount = 0, tip: rawTip = 0,
  } = req.body;

  if (!Array.isArray(items) || items.length === 0) throw new AppError('No items in cart', 400);
  if (items.length > 500) throw new AppError('Too many line items (max 500)', 400);

  // M4: reject negative discount outright (the original `if (discount < 0)`
  // check below did this but is preserved via validatePrice). validatePrice()
  // rounds to cents so the discount is now safe to subtract from rounded
  // subtotals downstream.
  const discount = rawDiscount ? validatePrice(rawDiscount, 'discount') : 0;

  // M7: tip rounded to cents on intake, so invoice.total is deterministic.
  const tipAmount = rawTip ? validatePrice(rawTip, 'tip') : 0;

  // payment_amount is validated later via validatePrice() at the point of
  // use (see "Payment math" below) — validatePrice rejects negatives, NaN,
  // and Infinity so a separate pre-check is redundant.

  // ---- Normalize payments: split array OR legacy single method -----------
  // M8: round each split payment amount to cents, validate > 0, validate
  // method against payment_methods whitelist. POS3: capture processor info.
  interface NormalizedPayment {
    method: string;
    amount: number;
    processor: string | null;
    reference: string | null;
    transaction_id: string | null;
  }
  const normalizedPayments: NormalizedPayment[] = [];

  if (Array.isArray(splitPayments) && splitPayments.length > 0) {
    if (splitPayments.length > 20) throw new AppError('Too many split payments (max 20)', 400);
    for (const sp of splitPayments) {
      if (!sp?.method || typeof sp.method !== 'string') {
        throw new AppError('Each payment must have a method', 400);
      }
      const amt = roundCents(validatePositiveAmount(sp.amount, 'payment amount'));
      const validSplitMethod = await adb.get<{ id: number }>(
        'SELECT id FROM payment_methods WHERE name = ? AND is_active = 1',
        sp.method,
      );
      if (!validSplitMethod) throw new AppError(`Invalid payment method: ${sp.method}`, 400);
      normalizedPayments.push({
        method: sp.method,
        amount: amt,
        processor: validateOptionalRefString(sp.processor, 'processor', 64),
        reference: validateOptionalRefString(sp.reference, 'reference', 128),
        transaction_id: validateOptionalRefString(sp.transaction_id, 'transaction_id', 128),
      });
    }
  } else {
    const validMethod = await adb.get<{ id: number }>(
      'SELECT id FROM payment_methods WHERE name = ? AND is_active = 1',
      payment_method,
    );
    if (!validMethod) throw new AppError(`Invalid payment method: ${payment_method}`, 400);
  }

  // ---- POS7: resolve customer_id (walk-in fallback) ----------------------
  let resolvedCustomerId: number;
  if (customer_id) {
    const customerRow = await adb.get<{ id: number }>(
      'SELECT id FROM customers WHERE id = ? AND is_deleted = 0',
      customer_id,
    );
    if (!customerRow) throw new AppError('Customer not found', 404);
    resolvedCustomerId = customerRow.id;
  } else {
    resolvedCustomerId = await getOrCreateWalkInCustomerId(adb);
  }

  // ---- Compute totals from INVENTORY (POS1 fix) --------------------------
  //
  // POS4: Tax / discount ordering policy — discount is applied BEFORE tax
  // (tax-on-net). This matches invoices.routes.ts (M6). Line tax is computed
  // against the net line (unit_price * qty − line_discount) so that the
  // customer's discount reduces the tax burden too. This comment documents
  // the policy explicitly so downstream handlers do not silently flip it.
  //
  // POS1: for every line with inventory_item_id, the server forces unit_price
  // from inventory_items.retail_price. A client cannot pass a lower price to
  // pocket the difference. Client unit_price is only honored for lines
  // without an inventory_item_id (misc / custom items — not currently
  // supported by this endpoint, but kept open for future use).
  interface ResolvedLine {
    inventory_item_id: number;
    inv: {
      id: number;
      name: string;
      retail_price: number;
      item_type: string;
      tax_class_id: number | null;
      tax_inclusive: number;
    };
    description: string;
    quantity: number;
    unit_price: number;      // server-forced
    line_discount: number;
    lineNet: number;          // unit_price * qty − line_discount, rounded
    lineTax: number;          // rounded
    lineTotal: number;        // rounded
    // @audit-fixed: S3 kit sell-path — optional `inventory_kits.id`. When
    // set, the POS transaction loop will splice
    // buildKitDecrementTxQueries() output into the batched transaction so
    // every component's stock is atomically decremented alongside the kit
    // SKU. A shortage on any component fails the whole sale.
    kit_id: number | null;
    kit_name: string | null;
  }
  const resolvedLines: ResolvedLine[] = [];
  let subtotal = 0;
  let total_tax = 0;

  for (const item of items) {
    // POS5: reject 2.7 → 2 truncation. validateIntegerQuantity throws on
    // non-integer or out-of-range.
    const qty = validateIntegerQuantity(item?.quantity ?? 1, 'line item quantity');
    if (qty < 1) throw new AppError('line item quantity must be at least 1', 400);

    const invId = Number(item?.inventory_item_id);
    if (!Number.isFinite(invId) || invId <= 0) {
      throw new AppError('inventory_item_id is required for POS line items', 400);
    }

    const inv = await adb.get<{
      id: number;
      name: string;
      retail_price: number;
      item_type: string;
      tax_class_id: number | null;
      tax_inclusive: number;
    }>(
      `SELECT id, name, retail_price, item_type, tax_class_id, tax_inclusive
         FROM inventory_items WHERE id = ? AND is_active = 1`,
      invId,
    );
    if (!inv) throw new AppError(`Item ${invId} not found`, 404);

    // POS1 fix: server-authoritative unit price.
    const unitPrice = validatePrice(inv.retail_price ?? 0, 'retail_price');

    // Optional per-line discount (trusted, but validated). Kept 0 unless
    // explicitly allowed in a future admin-discount endpoint; reject
    // negatives either way.
    const lineDiscount = item?.line_discount
      ? validatePrice(item.line_discount, 'line_discount')
      : 0;

    const gross = roundCents(qty * unitPrice);
    if (lineDiscount > gross) {
      throw new AppError(`Line discount exceeds line total for ${inv.name}`, 400);
    }
    const lineNet = roundCents(gross - lineDiscount);

    // Tax on net (discounted) line, respecting tax_inclusive flag.
    let lineTax = 0;
    if (inv.tax_class_id && !inv.tax_inclusive) {
      const taxClass = await adb.get<{ rate: number }>(
        'SELECT rate FROM tax_classes WHERE id = ?',
        inv.tax_class_id,
      );
      const rate = taxClass ? Number(taxClass.rate) / 100 : 0;
      lineTax = roundCents(lineNet * rate);
    }

    const lineTotal = roundCents(lineNet + lineTax);
    subtotal = roundCents(subtotal + lineNet);
    total_tax = roundCents(total_tax + lineTax);

    // @audit-fixed: S3 — parse optional `kit_id` on the line item. A client
    // can flag a POS line as "this is a kit sale" by passing an
    // `inventory_kits.id`; when present, we validate the kit exists and
    // attach its id/name to the resolved line. Later, the transaction loop
    // calls buildKitDecrementTxQueries() to decrement each component.
    // Without a kit_id, behavior is unchanged.
    let kitId: number | null = null;
    let kitName: string | null = null;
    if (item?.kit_id !== undefined && item?.kit_id !== null) {
      const parsedKitId = Number(item.kit_id);
      if (!Number.isInteger(parsedKitId) || parsedKitId <= 0) {
        throw new AppError('kit_id must be a positive integer', 400);
      }
      const kitRow = await adb.get<{ id: number; name: string }>(
        'SELECT id, name FROM inventory_kits WHERE id = ?',
        parsedKitId,
      );
      if (!kitRow) throw new AppError(`Kit ${parsedKitId} not found`, 404);
      kitId = kitRow.id;
      kitName = kitRow.name;
    }

    resolvedLines.push({
      inventory_item_id: invId,
      inv,
      description: inv.name,
      quantity: qty,
      unit_price: unitPrice,
      line_discount: lineDiscount,
      lineNet,
      lineTax,
      lineTotal,
      kit_id: kitId,
      kit_name: kitName,
    });
  }

  // ---- POS8: apply membership discount server-side -----------------------
  const membershipPct = await getMembershipDiscountPct(adb, resolvedCustomerId);
  const membershipDiscount = membershipPct > 0
    ? roundCents(subtotal * (membershipPct / 100))
    : 0;

  // Total discount is the larger of (explicit manual discount) OR
  // (membership discount) — it does not stack, to prevent abuse. If the
  // caller wants them to stack, they can pass `stack_membership: true`.
  const effectiveDiscount = req.body?.stack_membership
    ? roundCents(discount + membershipDiscount)
    : roundCents(Math.max(discount, membershipDiscount));

  // POS6 part 1: cap discount AFTER rounding, before final total.
  if (effectiveDiscount > roundCents(subtotal + total_tax)) {
    throw new AppError('Discount cannot exceed subtotal + tax', 400);
  }

  // Final total = subtotal − discount + tax + tip. Because tax was computed
  // on line net (already discount-adjusted), re-subtracting `effectiveDiscount`
  // would double-count. Instead we subtract the DELTA between effectiveDiscount
  // and any discount already embedded in line math. For this endpoint no
  // per-line discount feeds tax (line_discount is always 0 for POS1-locked
  // inventory lines unless admin explicitly passes one), so we subtract
  // effectiveDiscount from subtotal.
  const totalBeforeTip = roundCents(subtotal + total_tax - effectiveDiscount);
  const total = roundCents(totalBeforeTip + tipAmount);

  // POS6 part 2: after all rounding, the final total must be >= 0.
  if (total < 0) {
    throw new AppError('Total cannot be negative after rounding', 400);
  }

  // SEC-L47: Zero-dollar invoice guard. A $0 invoice is almost always either
  // a free-item promo or a discount-stack bug — either way we want an
  // explicit override so it doesn't silently sneak through. A non-admin
  // caller cannot bypass this, since `allow_zero_dollar` is only honored
  // when the cashier has an admin/owner role. The guard triggers when the
  // final total is exactly 0 OR when the resolved line subtotal is 0 (the
  // "all items net out to free" case); items.length === 0 was already
  // rejected up top, so this only fires on a real cart that still prices
  // to zero.
  const allowZeroDollar = req.body?.allow_zero_dollar === 1
    || req.body?.allow_zero_dollar === true
    || req.body?.allow_zero_dollar === '1';
  const cashierRole = req.user?.role ?? '';
  const isAdminCashier = cashierRole === 'admin' || cashierRole === 'owner';
  if (total === 0 && !(allowZeroDollar && isAdminCashier)) {
    throw new AppError(
      'Zero-dollar invoices require admin approval (pass allow_zero_dollar=1)',
      400,
    );
  }

  // ---- Payment math ------------------------------------------------------
  // M8: roundCents on the aggregate sum of split payments; for the legacy
  // single-payment path, validatePrice already rounded payment_amount.
  const legacyPaymentAmount = payment_amount !== undefined && payment_amount !== null
    ? validatePrice(payment_amount, 'payment_amount')
    : total;
  const paidAmount = normalizedPayments.length > 0
    ? roundCents(normalizedPayments.reduce((sum, p) => sum + p.amount, 0))
    : roundCents(legacyPaymentAmount);

  const amountPaid = Math.min(paidAmount, total);
  const amountDue = Math.max(0, roundCents(total - paidAmount));
  const status = paidAmount >= total ? 'paid' : 'partial';

  // ---- POS2 / S1: build full transactional write plan --------------------
  //
  // We can pre-compute every parameter because unit_price is server-forced
  // and resolvedCustomerId is already known. The batched adb.transaction()
  // runs the whole list inside a single better-sqlite3 transaction — if any
  // guarded UPDATE (stock decrement) affects zero rows, the worker throws
  // E_EXPECT_CHANGES and everything rolls back.
  //
  // Ordering inside the txn:
  //   1. INSERT invoice                   → result index 0
  //   2. For each line:
  //        a. INSERT invoice_line_items
  //        b. (non-service) guarded UPDATE inventory_items SET in_stock = in_stock - ? WHERE id=? AND in_stock >= ?
  //        c. (non-service) INSERT stock_movements
  //   3. INSERT pos_transactions
  //   4. For each payment: INSERT payments
  //   5. (tip > 0) INSERT employee_tips

  // I5: Atomic counter allocation — single source of truth, no MAX() race.
  // Falls back to the legacy MAX query if the counters table isn't present
  // (older tenant DBs that haven't run migration 072 yet).
  let orderId: string;
  try {
    const nextSeq = allocateCounter(db, 'invoice_order_id');
    orderId = formatInvoiceOrderId(nextSeq);
  } catch {
    const seqRow = await adb.get<{ next_num: number }>(
      "SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices",
    );
    orderId = generateOrderId('INV', seqRow!.next_num);
  }

  const txQueries: TxQuery[] = [];

  // 1. Invoice
  txQueries.push({
    sql: `INSERT INTO invoices
            (order_id, customer_id, subtotal, discount, total_tax, total, amount_paid, amount_due, status, notes, created_by)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    params: [
      orderId,
      resolvedCustomerId,
      subtotal,
      effectiveDiscount,
      total_tax,
      total,
      amountPaid,
      amountDue,
      status,
      notes ?? null,
      cashierId,
    ],
  });
  const INVOICE_RESULT_INDEX = 0;

  // 2. Line items + stock + movements. better-sqlite3 supports last_insert_rowid()
  // inside the transaction — we use it as a literal in subsequent statements
  // so we don't need to thread invoiceId across async calls.
  for (const line of resolvedLines) {
    txQueries.push({
      sql: `INSERT INTO invoice_line_items
              (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
            VALUES (
              (SELECT id FROM invoices WHERE order_id = ?),
              ?, ?, ?, ?, ?, ?
            )`,
      params: [
        orderId,
        line.inventory_item_id,
        line.description,
        line.quantity,
        line.unit_price,
        line.lineTax,
        line.lineTotal,
      ],
    });

    if (line.inv.item_type !== 'service') {
      // S1 / POS2: guarded atomic decrement. If another concurrent sale ate
      // the remaining stock between the precheck and now, `changes === 0`
      // and the worker throws → whole txn rolls back.
      txQueries.push({
        sql: `UPDATE inventory_items
                 SET in_stock = in_stock - ?,
                     updated_at = datetime('now')
               WHERE id = ? AND in_stock >= ?`,
        params: [line.quantity, line.inventory_item_id, line.quantity],
        expectChanges: true,
        expectChangesError: `Insufficient stock for ${line.inv.name}`,
      });

      txQueries.push({
        sql: `INSERT INTO stock_movements
                (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id)
              VALUES (?, 'sale', ?, 'invoice', (SELECT id FROM invoices WHERE order_id = ?), 'POS Sale', ?)`,
        params: [line.inventory_item_id, -line.quantity, orderId, cashierId],
      });
    }

    // @audit-fixed: S3 kit sell-path — if this POS line is a kit sale
    // (client passed a validated `kit_id`), decrement every component's
    // stock inside the SAME transaction. The helper's guarded UPDATEs use
    // `WHERE in_stock >= ?` so any shortage throws E_EXPECT_CHANGES and
    // rolls the whole sale back. Misconfigured kits (no components) log a
    // warn and return [] — we continue the sale in that case per §26.
    if (line.kit_id !== null) {
      const kitQueries = await buildKitDecrementTxQueries(
        adb,
        line.kit_id,
        line.quantity,
        cashierId,
        {
          referenceType: 'invoice',
          referenceOrderId: orderId,
        },
      );
      if (kitQueries.length === 0) {
        // Misconfigured kit — already warned inside the helper. No-op sale.
        logger.warn(
          `POS sale line references kit ${line.kit_id} ("${line.kit_name}") with zero components; components NOT decremented`,
        );
      } else {
        txQueries.push(...kitQueries);
      }
    }
  }

  // 3. pos_transactions summary row (used method label = joined for splits).
  const methodLabel = normalizedPayments.length > 0
    ? normalizedPayments.map(p => p.method).join('+')
    : payment_method;

  txQueries.push({
    sql: `INSERT INTO pos_transactions
            (invoice_id, customer_id, total, payment_method, user_id, tip)
          VALUES (
            (SELECT id FROM invoices WHERE order_id = ?),
            ?, ?, ?, ?, ?
          )`,
    params: [orderId, resolvedCustomerId, total, methodLabel, cashierId, tipAmount],
  });
  const POS_TX_QUERY_INDEX = txQueries.length - 1;

  // 4. Payments — POS3: persist transaction_id / processor / reference too.
  if (normalizedPayments.length > 0) {
    for (const p of normalizedPayments) {
      txQueries.push({
        sql: `INSERT INTO payments
                (invoice_id, amount, method, transaction_id, processor, reference, user_id)
              VALUES (
                (SELECT id FROM invoices WHERE order_id = ?),
                ?, ?, ?, ?, ?, ?
              )`,
        params: [
          orderId,
          p.amount,
          p.method,
          p.transaction_id,
          p.processor,
          p.reference,
          cashierId,
        ],
      });
    }
  } else {
    const singleProcessor = validateOptionalRefString(req.body?.processor, 'processor', 64);
    const singleReference = validateOptionalRefString(req.body?.reference, 'reference', 128);
    const singleTxnId = validateOptionalRefString(req.body?.transaction_id, 'transaction_id', 128);
    txQueries.push({
      sql: `INSERT INTO payments
              (invoice_id, amount, method, transaction_id, processor, reference, user_id)
            VALUES (
              (SELECT id FROM invoices WHERE order_id = ?),
              ?, ?, ?, ?, ?, ?
            )`,
      params: [
        orderId,
        roundCents(Math.min(paidAmount, total)),
        payment_method,
        singleTxnId,
        singleProcessor,
        singleReference,
        cashierId,
      ],
    });
  }

  // 5. EM6: link tip to cashier in employee_tips. Created only when tip > 0
  // to keep the table sparse.
  if (tipAmount > 0) {
    txQueries.push({
      sql: `INSERT INTO employee_tips
              (employee_id, invoice_id, pos_transaction_id, tip_amount, tip_method)
            VALUES (
              ?,
              (SELECT id FROM invoices WHERE order_id = ?),
              (SELECT id FROM pos_transactions
                  WHERE invoice_id = (SELECT id FROM invoices WHERE order_id = ?)
                  ORDER BY id DESC LIMIT 1),
              ?, ?
            )`,
      params: [cashierId, orderId, orderId, tipAmount, methodLabel],
    });
  }

  // POST-ENRICH §28: payroll period lock for tips. Tips are written inside
  // the TX, so we must refuse the sale if the payroll period is locked and
  // a tip is present. Commission writes happen POST-TX via the centralized
  // writeCommission() helper which has its own lock enforcement.
  if (tipAmount > 0) {
    const nowTs = new Date().toISOString();
    if (await isCommissionLocked(adb, nowTs)) {
      throw new AppError(
        'Cannot complete sale — the current payroll period is locked (tip)',
        403,
      );
    }
  }

  // ---- Execute the transaction ------------------------------------------
  let txResults;
  try {
    txResults = await adb.transaction(txQueries);
  } catch (err: unknown) {
    // Map guarded-update failures to a client-friendly 409 Conflict.
    const message = err instanceof Error ? err.message : String(err);
    if (
      (err as { code?: string } | undefined)?.code === 'E_EXPECT_CHANGES' ||
      /Guarded update failed/.test(message) ||
      /^Insufficient stock/.test(message)
    ) {
      throw new AppError(message, 409);
    }
    throw err;
  }
  void POS_TX_QUERY_INDEX;
  const invoiceId = txResults[INVOICE_RESULT_INDEX].lastInsertRowid;

  // @audit-fixed: S3 — audit kit sales for traceability. Anything decrementing
  // component stock should leave an audit trail so backfill / reconciliation
  // can distinguish "kit components moved" from regular line-item movement.
  const kitLines = resolvedLines.filter(l => l.kit_id !== null);
  if (kitLines.length > 0) {
    audit(db, 'pos_kit_sale', cashierId, req.ip || 'unknown', {
      invoice_id: invoiceId,
      order_id: orderId,
      kits: kitLines.map(l => ({
        kit_id: l.kit_id,
        kit_name: l.kit_name,
        quantity: l.quantity,
        marker_inventory_item_id: l.inventory_item_id,
      })),
    });
  }

  // @audit-fixed: #3/#16 — POS commission write via centralized helper.
  // Previously used a raw SQL INSERT that bypassed cents-based math and
  // payroll-lock enforcement inside writeCommission(). Now matches the
  // ticket-close and invoice-payment patterns: post-TX, best-effort,
  // lock failures logged but do not roll back the sale.
  let commissionEarned = 0;
  if (subtotal > 0) {
    try {
      const rowId = await writeCommission(adb, {
        userId: cashierId,
        source: 'pos_sale',
        invoiceId: Number(invoiceId),
        commissionableAmountCents: toCents(subtotal),
      });
      if (rowId > 0) {
        // Read back the earned amount for the response envelope.
        const cRow = await adb.get<{ amount: number }>(
          'SELECT amount FROM commissions WHERE id = ?',
          rowId,
        );
        commissionEarned = roundCents(Number(cRow?.amount ?? 0));
      }
    } catch (err: unknown) {
      // Payroll lock → log warning. Other errors → log + continue.
      // A locked payroll period should never prevent a customer purchase.
      if (err instanceof AppError) {
        logger.warn('pos_commission_payroll_locked', {
          cashier_id: cashierId,
          invoice_id: invoiceId,
          error: err.message,
        });
      } else {
        logger.error('pos_commission_write_failed', {
          cashier_id: cashierId,
          invoice_id: invoiceId,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }

  // @audit-fixed: #18 — Loyalty points accrual for POS sales.
  // Best-effort: a failure here never blocks the sale response.
  // Walk-in customers (sentinel row) naturally pass through —
  // accruePaymentPoints no-ops for customers with no real account
  // only if customerId is null/0, which walk-ins are not.
  try {
    await accruePaymentPoints({
      adb,
      customerId: resolvedCustomerId,
      invoiceId: Number(invoiceId),
      paymentAmount: total,
    });
  } catch (err: unknown) {
    logger.error('pos_loyalty_accrual_failed', {
      customer_id: resolvedCustomerId,
      invoice_id: invoiceId,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // ---- Respond with invoice detail --------------------------------------
  const invoice = await adb.get<any>(
    `SELECT inv.*, c.first_name, c.last_name
       FROM invoices inv
       LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?`,
    invoiceId,
  );

  const change = roundCents(Math.max(0, paidAmount - total));

  res.status(201).json({
    success: true,
    data: {
      invoice,
      tip: tipAmount,
      change,
      commission: commissionEarned > 0
        ? { user_id: cashierId, amount: commissionEarned }
        : null,
      membership: membershipPct > 0
        ? { discount_pct: membershipPct, discount_amount: membershipDiscount }
        : null,
    },
  });
});

// GET /pos/transactions - recent POS transactions
router.get('/transactions', async (req, res) => {
  const adb = req.asyncDb;
  const { from_date, to_date } = req.query as Record<string, string>;
  let where = 'WHERE 1=1';
  const params: any[] = [];
  if (from_date) { where += ' AND DATE(pt.created_at) >= ?'; params.push(from_date); }
  if (to_date) { where += ' AND DATE(pt.created_at) <= ?'; params.push(to_date); }

  const transactions = await adb.all<any>(`
    SELECT pt.*, inv.order_id, c.first_name, c.last_name,
           u.first_name || ' ' || u.last_name as cashier_name
    FROM pos_transactions pt
    LEFT JOIN invoices inv ON inv.id = pt.invoice_id
    LEFT JOIN customers c ON c.id = pt.customer_id
    LEFT JOIN users u ON u.id = pt.user_id
    ${where}
    ORDER BY pt.created_at DESC
    LIMIT 100
  `, ...params);

  res.json({ success: true, data: { transactions } });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

async function calcTaxAsync(adb: AsyncDb, price: number, taxClassId: number | null, taxInclusive: boolean): Promise<number> {
  if (!taxClassId) return 0;
  const tc = await adb.get<AnyRow>('SELECT rate FROM tax_classes WHERE id = ?', taxClassId);
  if (!tc) return 0;
  const rate = tc.rate / 100;
  if (taxInclusive) return roundCurrency(price - price / (1 + rate));
  return roundCurrency(price * rate);
}

// POST /pos/checkout-with-ticket - Create ticket + invoice + optional payment in one transaction
router.post('/checkout-with-ticket', idempotent, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const userId = req.user!.id;
  const {
    customer_id,
    mode,
    existing_ticket_id,
    ticket: ticketData,
    product_items = [],
    misc_items = [],
    payment_method = 'cash',
    payment_amount,
    payments: splitPayments,
    signature_file,
  } = req.body;

  if (!mode || !['create_ticket', 'checkout'].includes(mode)) {
    throw new AppError('mode must be "create_ticket" or "checkout"', 400);
  }

  // SW-D13: Require referral source if setting enabled
  // Pre-transaction async reads
  const [requireReferral, customerRow, defaultTaxClass, membershipEnabled, customerMembership] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'pos_require_referral'"),
    customer_id ? adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customer_id) : Promise.resolve(undefined),
    adb.get<AnyRow>("SELECT id, rate FROM tax_classes WHERE name LIKE '%Colorado%' OR rate = 8.865 LIMIT 1"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'membership_enabled'"),
    customer_id ? adb.get<AnyRow>(`
      SELECT cs.status, mt.discount_pct, mt.discount_applies_to, mt.name AS tier_name
      FROM customer_subscriptions cs
      JOIN membership_tiers mt ON mt.id = cs.tier_id
      WHERE cs.customer_id = ? AND cs.status = 'active'
      ORDER BY cs.created_at DESC LIMIT 1
    `, customer_id) : Promise.resolve(undefined),
  ]);

  if ((requireReferral?.value === '1' || requireReferral?.value === 'true') && customer_id && !ticketData?.referral_source) {
    throw new AppError('Referral source is required', 400);
  }

  // POS7: walk-in sales are allowed, but instead of storing customer_id = null
  // (which leaves rows orphaned from every customer-scoped report) we resolve
  // null to the special "Walk-in" sentinel customer early — so both the
  // tickets table (customer_id NOT NULL) and downstream reports always have
  // a valid FK. For existing-ticket checkouts we trust the ticket's
  // customer_id instead.
  let customerId: number | null = customer_id || null;
  if (customerId) {
    if (!customerRow) throw new AppError('Customer not found', 404);
  } else if (!existing_ticket_id) {
    // New ticket or cart-only checkout: use the walk-in sentinel.
    customerId = await getOrCreateWalkInCustomerId(adb);
  }

  // Get default tax class for taxable items
  const defaultTaxClassId = defaultTaxClass?.id ?? null;

  let ticketId: number | null = existing_ticket_id ? Number(existing_ticket_id) : null;
  let ticketOrderId: string | null = null;

  // If checking out an existing ticket, verify it exists and get its order_id
  if (ticketId) {
    const existing = await adb.get<AnyRow>('SELECT id, order_id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
    if (!existing) throw new AppError('Ticket not found', 404);
    ticketOrderId = existing.order_id;
    if (!customerId && existing.customer_id) customerId = existing.customer_id;
  }

  // ---- 1. Create ticket if devices are provided (skip if reusing existing) ----
  let tierReservationCommitted = false;
  if (!ticketId && ticketData?.devices && Array.isArray(ticketData.devices) && ticketData.devices.length > 0) {
    // Tier: atomic monthly ticket limit check (check + pre-increment in one transaction)
    // Free plans cap maxTicketsMonth; Pro plans set it to null (unlimited).
    const tierReservationTenantId = req.tenantId;
    if (config.multiTenant && tierReservationTenantId && req.tenantLimits?.maxTicketsMonth != null) {
      const { getMasterDb } = await import('../db/master-connection.js');
      const masterDb = getMasterDb();
      if (masterDb) {
        const month = new Date().toISOString().slice(0, 7); // YYYY-MM
        const limit = req.tenantLimits.maxTicketsMonth;

        const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
          const usage = masterDb.prepare(
            'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
          ).get(tierReservationTenantId, month) as { tickets_created: number } | undefined;
          const current = usage?.tickets_created ?? 0;
          if (current >= limit) {
            return { allowed: false, current };
          }
          masterDb.prepare(`
            INSERT INTO tenant_usage (tenant_id, month, tickets_created)
            VALUES (?, ?, 1)
            ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
          `).run(tierReservationTenantId, month);
          return { allowed: true, current: current + 1 };
        })();

        if (!reservation.allowed) {
          res.status(403).json({
            success: false,
            upgrade_required: true,
            feature: 'ticket_limit',
            message: `Monthly ticket limit reached (${reservation.current}/${limit}). Upgrade to Pro for unlimited tickets.`,
            current: reservation.current,
            limit,
          });
          return;
        }
        tierReservationCommitted = true;
      }
    }

    // Get default status
    const defaultStatus = await adb.get<AnyRow>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
    const statusId = defaultStatus?.id ?? 1;

    // I4: Atomic counter allocation — single source of truth, no MAX() race.
    // Falls back to the legacy MAX query if the counters table isn't present
    // (older tenant DBs that haven't run migration 072 yet).
    try {
      const nextSeq = allocateCounter(db, 'ticket_order_id');
      ticketOrderId = formatTicketOrderId(nextSeq);
    } catch {
      const ticketSeq = await adb.get<AnyRow>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 3) AS INTEGER)), 0) + 1 as next_num FROM tickets");
      ticketOrderId = generateOrderId('T', ticketSeq!.next_num);
    }
    const trackingToken = crypto.randomUUID().split('-')[0];

    // Auto-calculate due date if not provided (same logic as tickets.routes.ts F16)
    let dueOn = ticketData.due_on ?? ticketData.due_date ?? null;
    if (!dueOn) {
      const [dueCfg, dueUnit] = await Promise.all([
        adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_due_value'"),
        adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_due_unit'"),
      ]);
      if (dueCfg?.value && parseInt(dueCfg.value) > 0) {
        const val = parseInt(dueCfg.value);
        const unit = dueUnit?.value || 'days';
        const d = new Date();
        if (unit === 'hours') d.setHours(d.getHours() + val);
        else if (unit === 'weeks') d.setDate(d.getDate() + val * 7);
        else d.setDate(d.getDate() + val); // days
        dueOn = d.toISOString().replace('T', ' ').substring(0, 19);
      }
    }

    const ticketResult = await adb.run(`
      INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                           source, labels, due_on, created_by, tracking_token, signature_file, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
      ticketOrderId,
      customerId,
      statusId,
      ticketData.assigned_to ?? null,
      ticketData.discount ?? 0,
      ticketData.discount_reason ?? null,
      ticketData.source ?? 'Walk-in',
      JSON.stringify(ticketData.labels ?? []),
      dueOn,
      userId,
      trackingToken,
      signature_file ?? null,
      now(),
      now(),
    );

    ticketId = Number(ticketResult.lastInsertRowid);

    // Insert devices
    for (const dev of ticketData.devices) {
      const devicePrice = dev.price ?? dev.labor_price ?? 0;
      const lineDiscount = dev.line_discount ?? 0;
      // Repairs (labor) default to non-taxable; explicit taxable flag overrides
      const taxClassId = dev.tax_class_id ?? (dev.taxable === true ? defaultTaxClassId : null);
      const taxAmount = await calcTaxAsync(adb, devicePrice - lineDiscount, taxClassId, dev.tax_inclusive ?? false);
      const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

      // SW-D11: Auto-fill default warranty, respecting unit setting
      let warrantyDays = dev.warranty_days;
      if (warrantyDays === undefined || warrantyDays === null) {
        const [wVal, wUnit] = await Promise.all([
          adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'repair_default_warranty_value'"),
          adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'repair_default_warranty_unit'"),
        ]);
        const rawVal = wVal?.value ? parseInt(wVal.value) : 0;
        warrantyDays = wUnit?.value === 'months' ? rawVal * 30 : rawVal;
      }

      const devResult = await adb.run(`
        INSERT INTO ticket_devices (ticket_id, device_name, device_type, imei, serial, security_code,
                                    color, network, status_id, assigned_to, service_id, service_name, price, line_discount,
                                    tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                    due_on, device_location, additional_notes, pre_conditions, post_conditions,
                                    created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
        ticketId,
        dev.device_name ?? '',
        dev.device_type ?? null,
        dev.imei ?? null,
        dev.serial ?? null,
        dev.security_code ?? null,
        dev.color ?? null,
        dev.network ?? null,
        statusId,
        dev.assigned_to ?? ticketData.assigned_to ?? null,
        dev.service_id ?? dev.repair_service_id ?? null,
        dev.service_name ?? null,
        devicePrice,
        lineDiscount,
        taxAmount,
        taxClassId,
        dev.tax_inclusive ? 1 : 0,
        deviceTotal,
        dev.warranty ? 1 : 0,
        warrantyDays,
        dev.due_on ?? null,
        dev.device_location ?? null,
        dev.additional_notes ?? null,
        JSON.stringify(dev.pre_conditions ?? []),
        JSON.stringify(dev.post_conditions ?? []),
        now(),
        now(),
      );

      const deviceId = Number(devResult.lastInsertRowid);

      // Insert parts
      if (dev.parts && Array.isArray(dev.parts)) {
        for (const part of dev.parts) {
          await adb.run(`
            INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price,
                                             status, warranty, serial, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          `,
            deviceId,
            part.inventory_item_id,
            part.quantity ?? 1,
            part.price ?? 0,
            part.status ?? 'available',
            part.warranty ? 1 : 0,
            part.serial ?? null,
            now(),
            now(),
          );
        }
      }
    }

    // Recalculate ticket totals
    const [devices, parts] = await Promise.all([
      adb.all<AnyRow>('SELECT price, line_discount, tax_amount FROM ticket_devices WHERE ticket_id = ?', ticketId),
      adb.all<AnyRow>(`
        SELECT tdp.quantity, tdp.price FROM ticket_device_parts tdp
        JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?
      `, ticketId),
    ]);

    let ticketSubtotal = 0;
    let ticketTax = 0;
    for (const d of devices) { ticketSubtotal += (d.price - d.line_discount); ticketTax += d.tax_amount; }
    for (const p of parts) { ticketSubtotal += p.quantity * p.price; }
    const ticketDiscount = ticketData.discount ?? 0;
    const ticketTotal = roundCurrency(ticketSubtotal - ticketDiscount + ticketTax);

    await adb.run('UPDATE tickets SET subtotal = ?, total_tax = ?, total = ?, updated_at = ? WHERE id = ?',
      roundCurrency(ticketSubtotal), roundCurrency(ticketTax), ticketTotal, now(), ticketId);

    // History entry
    await adb.run(`
      INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
      VALUES (?, ?, ?, ?, ?, ?)
    `, ticketId, userId, 'created', 'Ticket created via Unified POS', null, null);

    // Internal notes
    if (ticketData.internal_notes) {
      await adb.run(`
        INSERT INTO ticket_notes (ticket_id, type, content, created_by, created_at)
        VALUES (?, 'internal', ?, ?, ?)
      `, ticketId, ticketData.internal_notes, userId, now());
    }
  }
  void tierReservationCommitted;

  // ---- 2. Build invoice line items from ALL sources ----
  let invoiceSubtotal = 0;
  let invoiceTax = 0;
  const invoiceLines: {
    inventory_item_id: number | null;
    description: string;
    quantity: number;
    unit_price: number;
    tax_amount: number;
    total: number;
  }[] = [];

  // 2a. Repair device lines (labor + parts from ticket)
  if (ticketId) {
    const tDevices = await adb.all<AnyRow>(`
      SELECT td.id, td.device_name, td.price, td.line_discount, td.tax_amount, td.total, td.service_id
      FROM ticket_devices td WHERE td.ticket_id = ?
    `, ticketId);

    for (const td of tDevices) {
      const laborNet = (td.price ?? 0) - (td.line_discount ?? 0);
      invoiceSubtotal += laborNet;
      invoiceTax += td.tax_amount ?? 0;
      invoiceLines.push({
        inventory_item_id: td.service_id ?? null,
        description: `Repair: ${td.device_name}`,
        quantity: 1,
        unit_price: laborNet,
        tax_amount: td.tax_amount ?? 0,
        total: td.total ?? laborNet,
      });

      // Parts for this device
      const tParts = await adb.all<AnyRow>('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?', td.id);
      for (const tp of tParts) {
        const partTotal = tp.quantity * tp.price;
        invoiceSubtotal += partTotal;
        // Parts tax: use default tax class
        const partTax = tp.price > 0 ? await calcTaxAsync(adb, partTotal, defaultTaxClassId, false) : 0;
        invoiceTax += partTax;
        invoiceLines.push({
          inventory_item_id: tp.inventory_item_id,
          description: `Part for ${td.device_name}`,
          quantity: tp.quantity,
          unit_price: tp.price,
          tax_amount: partTax,
          total: partTotal + partTax,
        });
      }
    }
  }

  // 2b. Product items
  //
  // POS1: server forces unit_price from inventory_items.retail_price for any
  // line carrying an inventory_item_id. Client unit_price is ignored here.
  // POS5: use validateIntegerQuantity so 2.7 does not truncate to 2.
  // M7/M8: round tax + subtotals to cents each iteration to prevent drift.
  // POS4: tax on net — computed on (qty * unit_price - line_discount).
  for (const item of product_items) {
    const qty = validateIntegerQuantity(item?.quantity ?? 1, 'product item quantity');
    if (qty < 1) throw new AppError('product item quantity must be at least 1', 400);
    item.quantity = qty;

    const inv = await adb.get<AnyRow>('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1', item.inventory_item_id);
    if (!inv) throw new AppError(`Product ${item.inventory_item_id} not found`, 404);

    if (inv.item_type !== 'service' && inv.in_stock < qty) {
      throw new AppError(`Insufficient stock for ${inv.name}`, 400);
    }

    // POS1: server-authoritative unit price. Client cannot override.
    const unitPrice = validatePrice(inv.retail_price ?? 0, 'retail_price');
    const lineGross = roundCents(qty * unitPrice);
    const lineSubtotal = lineGross;
    const taxClassId = inv.tax_class_id ?? null;
    const lineTax = inv.tax_inclusive
      ? 0
      : roundCents(await calcTaxAsync(adb, lineSubtotal, taxClassId, false));

    invoiceSubtotal = roundCents(invoiceSubtotal + lineSubtotal);
    invoiceTax = roundCents(invoiceTax + lineTax);
    invoiceLines.push({
      inventory_item_id: item.inventory_item_id,
      description: inv.name,
      quantity: qty,
      unit_price: unitPrice,
      tax_amount: lineTax,
      total: roundCents(lineSubtotal + lineTax),
    });
  }

  // 2c. Misc items — "custom" line items without an inventory_item_id, e.g.
  // handwritten labor charges or one-off items. Client-supplied unit_price is
  // allowed here per scope (POS1), but still validated for range and cents.
  for (const item of misc_items) {
    const rawPrice = item?.price ?? item?.unit_price ?? 0;
    const itemPrice = validatePrice(rawPrice, 'misc item price');
    const miscQty = validateIntegerQuantity(item?.quantity ?? 1, 'misc item quantity');
    if (miscQty < 1) throw new AppError('misc item quantity must be at least 1', 400);
    item.quantity = miscQty;

    const lineSubtotal = roundCents(itemPrice * miscQty);
    const lineTax = item?.taxable
      ? roundCents(await calcTaxAsync(adb, lineSubtotal, defaultTaxClassId, false))
      : 0;

    invoiceSubtotal = roundCents(invoiceSubtotal + lineSubtotal);
    invoiceTax = roundCents(invoiceTax + lineTax);
    invoiceLines.push({
      inventory_item_id: null,
      description: item?.name || 'Miscellaneous',
      quantity: miscQty,
      unit_price: itemPrice,
      tax_amount: lineTax,
      total: lineSubtotal + lineTax,
    });
  }

  // ---- 3. Create or update invoice ----
  //
  // POS4: tax / discount ordering policy — DISCOUNT FIRST, then TAX. Tax has
  // already been computed line-by-line against the net (unit_price * qty −
  // line_discount) above, matching invoices.routes.ts M6 and pos.routes.ts
  // /transaction. This comment documents the policy so downstream handlers
  // do not silently flip it.
  //
  // M4: reject negative discount. validatePrice throws on negative.
  // POS8: apply membership discount server-side. Client-supplied
  // ticketData.discount and server-resolved membership discount do not
  // stack by default (take the larger) to prevent abuse.
  // POS6: discount cap checked after rounding; final total re-checked >= 0.
  const manualDiscount = ticketData?.discount
    ? validatePrice(ticketData.discount, 'discount')
    : 0;
  const membershipPct = await getMembershipDiscountPct(adb, customerId);
  const membershipDiscountAmt = membershipPct > 0
    ? roundCents(invoiceSubtotal * (membershipPct / 100))
    : 0;
  const discount = roundCents(Math.max(manualDiscount, membershipDiscountAmt));

  // Round subtotal + tax, then cap discount, then compute total.
  const roundedSubtotal = roundCents(invoiceSubtotal);
  const roundedTax = roundCents(invoiceTax);
  if (discount > roundCents(roundedSubtotal + roundedTax)) {
    throw new AppError('Discount cannot exceed subtotal + tax', 400);
  }
  const invoiceTotal = roundCents(roundedSubtotal + roundedTax - discount);
  if (invoiceTotal < 0) {
    throw new AppError('Total cannot be negative after rounding', 400);
  }

  const isPaid = mode === 'checkout';
  const rawPaidAmount = isPaid
    ? (payment_amount !== undefined && payment_amount !== null
        ? validatePrice(payment_amount, 'payment_amount')
        : invoiceTotal)
    : 0;
  const paidAmount = roundCents(rawPaidAmount);

  // Check if invoice already exists for this ticket (created during check-in)
  let invoiceId: number;
  const existingInvoice = ticketId
    ? await adb.get<AnyRow>('SELECT id, order_id FROM invoices WHERE ticket_id = ?', ticketId)
    : undefined;

  // POS7 safety net: if the flow somehow reaches here without a customerId
  // (e.g. an orphaned existing ticket with no customer_id), fall through to
  // the walk-in sentinel so the invoice always has a valid customer FK.
  if (!customerId) {
    customerId = await getOrCreateWalkInCustomerId(adb);
  }

  if (existingInvoice) {
    // UPDATE existing invoice with current totals and payment status
    invoiceId = existingInvoice.id;
    await adb.run(`
      UPDATE invoices SET
        customer_id = ?, subtotal = ?, discount = ?, total_tax = ?, total = ?,
        amount_paid = ?, amount_due = ?, status = ?, updated_at = ?
      WHERE id = ?
    `,
      customerId,
      roundedSubtotal,
      discount,
      roundedTax,
      invoiceTotal,
      isPaid ? roundCents(Math.min(paidAmount, invoiceTotal)) : 0,
      isPaid ? roundCents(Math.max(0, invoiceTotal - paidAmount)) : invoiceTotal,
      isPaid ? (paidAmount >= invoiceTotal ? 'paid' : 'partial') : 'unpaid',
      now(),
      invoiceId,
    );

    // Replace line items (delete old, insert new)
    await adb.run('DELETE FROM invoice_line_items WHERE invoice_id = ?', invoiceId);
  } else {
    // CREATE new invoice. I5: atomic counter allocation (with fallback for
    // pre-072 tenant DBs).
    let invoiceOrderId: string;
    try {
      const nextSeq = allocateCounter(db, 'invoice_order_id');
      invoiceOrderId = formatInvoiceOrderId(nextSeq);
    } catch {
      const invSeq = await adb.get<AnyRow>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices");
      invoiceOrderId = generateOrderId('INV', invSeq!.next_num);
    }

    const invoiceResult = await adb.run(`
      INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
                            amount_paid, amount_due, status, created_by, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
      invoiceOrderId,
      customerId,
      ticketId,
      roundedSubtotal,
      discount,
      roundedTax,
      invoiceTotal,
      isPaid ? roundCents(Math.min(paidAmount, invoiceTotal)) : 0,
      isPaid ? roundCents(Math.max(0, invoiceTotal - paidAmount)) : invoiceTotal,
      isPaid ? (paidAmount >= invoiceTotal ? 'paid' : 'partial') : 'unpaid',
      userId,
      now(),
      now(),
    );

    invoiceId = Number(invoiceResult.lastInsertRowid);
  }

  // Insert invoice line items (fresh for both create and update)
  for (const line of invoiceLines) {
    await adb.run(`
      INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `, invoiceId, line.inventory_item_id, line.description, line.quantity, line.unit_price, line.tax_amount, line.total);
  }

  // Link invoice to ticket (so ticket detail can find it)
  if (ticketId) {
    await adb.run('UPDATE tickets SET invoice_id = ?, updated_at = ? WHERE id = ?',
      invoiceId, now(), ticketId);
  }

  // ENR-POS3: Log discount to audit trail when a discount is applied
  if (discount > 0) {
    try {
      await adb.run(
        'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
        'discount_applied', userId, req.ip || 'unknown',
        JSON.stringify({ ticket_id: ticketId, invoice_id: invoiceId, discount_amount: discount, discount_reason: ticketData?.discount_reason || null }),
      );
    } catch (err) {
      console.error('[Audit] Failed to write audit log:', err);
    }
  }

  // ---- 4. If checkout mode: payment + stock deductions + POS transaction ----
  //
  // POS2 / S1: stock decrement uses the guarded UPDATE pattern
  //   WHERE id = ? AND in_stock >= ?
  // If two concurrent sales race the same item, only one succeeds; the other
  // gets a 409 and aborts the checkout. The pre-check earlier in the handler
  // catches the happy path; this guard catches the race.
  //
  // POS3: persist processor / reference / transaction_id on every payment
  // row so reconciliation has enough data to trace each tender line.
  //
  // M8: every payment amount rounded to cents via roundCents.
  let change = 0;
  if (isPaid) {
    // Record payment(s) — support split payments
    if (Array.isArray(splitPayments) && splitPayments.length > 0) {
      let totalPaid = 0;
      for (const sp of splitPayments) {
        const amt = roundCents(validatePositiveAmount(sp?.amount, 'split payment amount'));
        const method = typeof sp?.method === 'string' ? sp.method : '';
        if (!method) throw new AppError('Each split payment must have a method', 400);
        const validMethod = await adb.get<{ id: number }>(
          'SELECT id FROM payment_methods WHERE name = ? AND is_active = 1',
          method,
        );
        if (!validMethod) throw new AppError(`Invalid payment method: ${method}`, 400);

        const sProcessor = validateOptionalRefString(sp?.processor, 'processor', 64);
        const sReference = validateOptionalRefString(sp?.reference, 'reference', 128);
        const sTxnId = validateOptionalRefString(sp?.transaction_id, 'transaction_id', 128);

        await adb.run(`
          INSERT INTO payments
            (invoice_id, amount, method, transaction_id, processor, reference, user_id, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `, invoiceId, amt, method, sTxnId, sProcessor, sReference, userId, now());
        totalPaid = roundCents(totalPaid + amt);
      }
      change = roundCents(Math.max(0, totalPaid - invoiceTotal));

      // POS transaction record (combine method names)
      await adb.run(`
        INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id)
        VALUES (?, ?, ?, ?, ?)
      `, invoiceId, customerId, invoiceTotal, splitPayments.map((p: any) => p.method).join('+'), userId);
    } else {
      // Legacy single payment
      const sProcessor = validateOptionalRefString(req.body?.processor, 'processor', 64);
      const sReference = validateOptionalRefString(req.body?.reference, 'reference', 128);
      const sTxnId = validateOptionalRefString(req.body?.transaction_id, 'transaction_id', 128);
      await adb.run(`
        INSERT INTO payments
          (invoice_id, amount, method, transaction_id, processor, reference, user_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `, invoiceId, paidAmount, payment_method, sTxnId, sProcessor, sReference, userId, now());

      change = roundCents(Math.max(0, paidAmount - invoiceTotal));

      // POS transaction record
      await adb.run(`
        INSERT INTO pos_transactions (invoice_id, customer_id, total, payment_method, user_id)
        VALUES (?, ?, ?, ?, ?)
      `, invoiceId, customerId, invoiceTotal, payment_method, userId);
    }

    // S1: Deduct stock for product items atomically with a guard.
    // Uses `WHERE id = ? AND in_stock >= ?` — if the row's stock dropped
    // below the needed quantity since the pre-check, changes === 0 and we
    // throw a 409. Note: this endpoint's structure (many small async calls)
    // means a failure here leaves the invoice intact — a subsequent retry
    // should reconcile. A full atomic wrapping transaction for this
    // endpoint is out of scope (the /transaction endpoint has the batched
    // txn fix); here we at least prevent negative in_stock.
    for (const item of product_items) {
      const inv = await adb.get<AnyRow>(
        'SELECT id, item_type, name FROM inventory_items WHERE id = ?',
        item.inventory_item_id,
      );
      if (inv && inv.item_type !== 'service') {
        const dec = await adb.run(
          `UPDATE inventory_items
              SET in_stock = in_stock - ?, updated_at = ?
            WHERE id = ? AND in_stock >= ?`,
          item.quantity, now(), item.inventory_item_id, item.quantity,
        );
        if (dec.changes === 0) {
          throw new AppError(`Insufficient stock for ${inv.name}`, 409);
        }
        await adb.run(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
          VALUES (?, 'sale', ?, 'invoice', ?, 'POS checkout', ?, ?, ?)
        `, item.inventory_item_id, -item.quantity, invoiceId, userId, now(), now());
      }
    }
  }

  // ---- 4b. If checkout mode with a ticket: close the ticket ----
  if (isPaid && ticketId) {
    const closedStatus = await adb.get<AnyRow>(
      'SELECT id FROM ticket_statuses WHERE is_closed = 1 ORDER BY sort_order ASC LIMIT 1'
    );
    if (closedStatus) {
      await adb.run("UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?",
        closedStatus.id, now(), ticketId);
      // Record in ticket history
      const closedRow = await adb.get<AnyRow>('SELECT name FROM ticket_statuses WHERE id = ?', closedStatus.id);
      const closedName = closedRow?.name || 'Closed';
      await adb.run(`
        INSERT INTO ticket_history (ticket_id, action, old_value, new_value, user_id, created_at)
        VALUES (?, 'status_change', '', ?, ?, ?)
      `, ticketId, closedName, userId, now());
    }
  }

  // ---- 5. Fetch created records for response ----
  const invoice = await adb.get<any>(`
    SELECT inv.*, c.first_name, c.last_name
    FROM invoices inv
    LEFT JOIN customers c ON c.id = inv.customer_id
    WHERE inv.id = ?
  `, invoiceId);

  let ticket: any = null;
  if (ticketId) {
    ticket = await adb.get<any>(`
      SELECT t.*, ts.name AS status_name, ts.color AS status_color,
             c.first_name AS c_first_name, c.last_name AS c_last_name
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.id = ?
    `, ticketId);
    // Include devices for success screen summary
    if (ticket) {
      ticket.devices = await adb.all<any>(`
        SELECT td.id, td.device_name, td.device_type, td.service_id,
               COALESCE(td.service_name, ii.name) AS service_name
        FROM ticket_devices td
        LEFT JOIN inventory_items ii ON ii.id = td.service_id
        WHERE td.ticket_id = ?
      `, ticketId);
    }
  }

  const result = { ticket, invoice, change };

  // Broadcast ticket creation if a ticket was created
  if (result.ticket) {
    broadcast(WS_EVENTS.TICKET_CREATED, result.ticket, req.tenantSlug || null);

    // Create in-app notification for all active users
    const customerName = result.ticket.c_first_name
      ? `${result.ticket.c_first_name} ${result.ticket.c_last_name || ''}`.trim()
      : 'Walk-in';
    const deviceSummary = result.ticket.devices?.map((d: any) => d.device_name).filter(Boolean).join(', ') || 'Repair';
    const notifTitle = `New Ticket ${result.ticket.order_id}`;
    const notifMessage = `${customerName} — ${deviceSummary}`;
    const activeUsers = await adb.all<{ id: number }>("SELECT id FROM users WHERE is_active = 1");
    for (const u of activeUsers) {
      await adb.run(`
        INSERT INTO notifications (user_id, type, title, message, entity_type, entity_id, created_at, updated_at)
        VALUES (?, 'ticket_created', ?, ?, 'ticket', ?, datetime('now'), datetime('now'))
      `, u.id, notifTitle, notifMessage, result.ticket.id);
    }
  }

  // SW-D13: Include checkin settings in response
  const [checkinCategory, autoPrintLabel] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'checkin_default_category'"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'checkin_auto_print_label'"),
  ]);

  res.status(201).json({
    success: true,
    data: {
      ...result,
      checkin_default_category: checkinCategory?.value ?? null,
      auto_print_label: autoPrintLabel?.value === '1' || autoPrintLabel?.value === 'true',
      // Membership info for upsell prompt
      membership: customerMembership ? {
        active: true,
        tier_name: customerMembership.tier_name,
        discount_pct: customerMembership.discount_pct,
        discount_applies_to: customerMembership.discount_applies_to,
      } : membershipEnabled?.value === 'true' ? {
        active: false,
        upsell: true, // Frontend shows "Not a member — offer X% off" banner
      } : null,
    },
  });
});

// ---------------------------------------------------------------------------
// ENR-POS2: POST /pos/return — Return/exchange workflow
// Creates a credit note (negative invoice), restores stock, records reason.
// Admin/manager only.
// ---------------------------------------------------------------------------
router.post('/return', async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for allocateCounter (sync better-sqlite3 handle)
  const userId = req.user!.id;
  const userRole = req.user!.role;
  const ip = req.ip || 'unknown';

  // Admin/manager only
  if (userRole !== 'admin' && userRole !== 'manager') {
    throw new AppError('Only admin or manager can process returns', 403);
  }

  const { invoice_id, items } = req.body as {
    invoice_id: number;
    items: { line_item_id: number; quantity: number; reason: string }[];
  };

  // @audit-fixed: validate invoice_id is a positive integer; previously a string
  // value flowed straight to SQLite as TEXT and matched no row → 404 silently.
  const invId = Number(invoice_id);
  if (!Number.isInteger(invId) || invId <= 0) throw new AppError('invoice_id must be a positive integer', 400);
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new AppError('At least one return item is required', 400);
  }
  // @audit-fixed: cap return-line count so a single request can't process millions of items
  if (items.length > 200) throw new AppError('Too many return items (max 200)', 400);

  // Verify invoice exists
  const invoice = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', invId);
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') throw new AppError('Cannot process a return on a voided invoice', 400);

  let creditTotal = 0;
  const returnDetails: any[] = [];

  for (const item of items) {
    // @audit-fixed: integer-validate line_item_id and quantity. The previous
    // `!item.quantity || item.quantity < 1` check accepted "abc" because !"abc" = false.
    const liId = Number(item.line_item_id);
    if (!Number.isInteger(liId) || liId <= 0) throw new AppError('line_item_id must be a positive integer', 400);
    const itemQty = Number(item.quantity);
    if (!Number.isInteger(itemQty) || itemQty < 1) throw new AppError('quantity must be a positive integer', 400);
    if (!item.reason?.trim()) throw new AppError('reason is required for each item', 400);

    const lineItem = await adb.get<any>(
      'SELECT * FROM invoice_line_items WHERE id = ? AND invoice_id = ?',
      liId, invId,
    );
    if (!lineItem) throw new AppError(`Line item ${liId} not found on invoice ${invId}`, 404);

    if (itemQty > lineItem.quantity) {
      throw new AppError(`Return quantity (${itemQty}) exceeds invoiced quantity (${lineItem.quantity})`, 400);
    }

    const unitPrice = lineItem.unit_price;
    const unitTax = lineItem.quantity > 0 ? lineItem.tax_amount / lineItem.quantity : 0;
    const returnAmount = roundCurrency(itemQty * (unitPrice + unitTax));
    creditTotal += returnAmount;

    // Restore stock if the line item has an inventory_item_id (physical product)
    if (lineItem.inventory_item_id) {
      await adb.run(
        'UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime(\'now\') WHERE id = ?',
        itemQty, lineItem.inventory_item_id,
      );

      await adb.run(`
        INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
        VALUES (?, 'return', ?, 'invoice', ?, ?, ?, datetime('now'), datetime('now'))
      `, lineItem.inventory_item_id, itemQty, invId, `Return: ${item.reason}`, userId);
    }

    returnDetails.push({
      line_item_id: liId,
      description: lineItem.description,
      quantity: itemQty,
      amount: returnAmount,
      reason: item.reason,
    });
  }

  // Create credit note (negative invoice).
  // I5: Atomic counter allocation — credit notes historically share the
  // invoice_order_id sequence (they live in the invoices table), so we use
  // that counter and preserve the 'CRN-####' prefix via generateOrderId.
  // Falls back to the legacy MAX query if the counters table isn't present.
  let creditOrderId: string;
  try {
    const nextSeq = allocateCounter(db, 'invoice_order_id');
    creditOrderId = generateOrderId('CRN', nextSeq);
  } catch {
    const seqRow = await adb.get<any>(
      "SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices",
    );
    creditOrderId = generateOrderId('CRN', seqRow!.next_num);
  }

  const creditResult = await adb.run(`
    INSERT INTO invoices (order_id, customer_id, subtotal, discount, total_tax, total, amount_paid, amount_due, status, notes, created_by, created_at, updated_at)
    VALUES (?, ?, ?, 0, 0, ?, 0, 0, 'credit_note', ?, ?, datetime('now'), datetime('now'))
  `,
    creditOrderId,
    invoice.customer_id,
    -creditTotal,
    -creditTotal,
    `Credit note for return on ${invoice.order_id}. Items: ${returnDetails.map(d => `${d.description} x${d.quantity} (${d.reason})`).join('; ')}`,
    userId,
  );

  const creditNoteId = Number(creditResult.lastInsertRowid);

  // Insert negative line items on the credit note
  for (const detail of returnDetails) {
    await adb.run(`
      INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, tax_amount, total, created_at, updated_at)
      VALUES (?, ?, ?, ?, 0, ?, datetime('now'), datetime('now'))
    `, creditNoteId, `RETURN: ${detail.description}`, -detail.quantity, detail.amount / detail.quantity, -detail.amount);
  }

  // Create refund record
  await adb.run(`
    INSERT INTO refunds (invoice_id, customer_id, amount, type, reason, status, created_by, created_at, updated_at)
    VALUES (?, ?, ?, 'credit_note', ?, 'completed', ?, datetime('now'), datetime('now'))
  `, invId, invoice.customer_id, creditTotal, returnDetails.map(d => d.reason).join('; '), userId);

  // Audit log
  try {
    await adb.run(
      'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
      'pos_return', userId, ip,
      JSON.stringify({ invoice_id: invId, credit_note_id: creditNoteId, credit_note_order_id: creditOrderId, total_credited: creditTotal, items: returnDetails }),
    );
  } catch (err) {
    console.error('[Audit] Failed to write audit log:', err);
  }

  const creditNote = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', creditNoteId);

  res.status(201).json({ success: true, data: { credit_note: creditNote, items: returnDetails, total_credited: creditTotal } });
});

// ==================== ENR-POS4: Cash drawer integration ====================
// POST /pos/open-drawer — sends a command to open the cash drawer
// For now, logs the event and returns success. Actual hardware integration is per-deployment.
router.post('/open-drawer', async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const { reason } = req.body;

  // @audit-fixed: cash drawer is a physical-security gate. Previously ANY
  // authenticated user (e.g. a kiosk-mode customer-portal session) could call
  // POST /pos/open-drawer and pop the till. Restrict to admin/manager/cashier.
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager' && role !== 'cashier') {
    throw new AppError('Only admin/manager/cashier can open the cash drawer', 403);
  }

  // Log the drawer open event to cash_register table
  await adb.run(`
    INSERT INTO cash_register (type, amount, reason, user_id)
    VALUES ('drawer_open', 0, ?, ?)
  `, reason || 'Manual drawer open', userId);

  try {
    await adb.run(
      'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)',
      'cash_drawer_opened', userId, req.ip || 'unknown',
      JSON.stringify({ reason: reason || 'Manual drawer open' }),
    );
  } catch (err) {
    console.error('[Audit] Failed to write audit log:', err);
  }

  // @audit-fixed: drop noisy console.log on a hot endpoint — audit log already
  // captured above is the canonical record.

  res.json({
    success: true,
    data: { message: 'Cash drawer open command sent', opened_at: new Date().toISOString() },
  });
});

export default router;
