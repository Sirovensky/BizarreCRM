import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { validatePrice } from '../utils/validate.js';
import { generateOrderId } from '../utils/format.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { runAutomations } from '../services/automations.js';
import { idempotent } from '../middleware/idempotency.js';
import { audit } from '../utils/audit.js';
import { fireWebhook } from '../services/webhooks.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

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

// GET /invoices
router.get('/', async (req, res) => {
  const adb = req.asyncDb;
  const { page = '1', pagesize = '20', status, from_date, to_date, keyword, customer_id } = req.query as Record<string, string>;
  const p = Math.max(1, parseInt(page));
  const ps = Math.min(250, Math.max(1, parseInt(pagesize)));
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: any[] = [];

  if (status === 'overdue') {
    where += " AND inv.status IN ('unpaid','partial') AND inv.due_date IS NOT NULL AND inv.due_date < DATE('now')";
  } else if (status) { where += ' AND inv.status = ?'; params.push(status); }
  if (customer_id) { where += ' AND inv.customer_id = ?'; params.push(customer_id); }
  if (from_date) { where += ' AND DATE(inv.created_at) >= ?'; params.push(from_date); }
  if (to_date) { where += ' AND DATE(inv.created_at) <= ?'; params.push(to_date); }
  if (keyword) {
    where += ' AND (inv.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR c.organization LIKE ?)';
    const k = `%${keyword}%`;
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
    const createdMs = new Date(inv.created_at).getTime();
    const ageDays = Math.max(0, Math.floor((nowMs - createdMs) / 86_400_000));
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
router.get('/stats', async (req, res) => {
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
  res.json({ success: true, data: { invoice } });
});

// POST /invoices
router.post('/', idempotent, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const {
    customer_id, ticket_id, line_items = [], discount = 0, discount_reason,
    notes, due_date, is_deposit, deposit_amount: reqDepositAmount, parent_invoice_id,
  } = req.body;

  if (!customer_id) throw new AppError('Customer is required', 400);

  // ENR-I2: Validate deposit fields
  const depositFlag = is_deposit ? 1 : 0;
  const depositAmount = depositFlag ? validatePrice(reqDepositAmount ?? 0, 'deposit_amount') : 0;
  if (parent_invoice_id) {
    const parentInv = await adb.get<any>('SELECT id, is_deposit FROM invoices WHERE id = ?', parent_invoice_id);
    if (!parentInv) throw new AppError('Parent invoice not found', 404);
    if (!parentInv.is_deposit) throw new AppError('Parent invoice is not a deposit invoice', 400);
  }

  // Get next order_id from existing order_ids (safe across deletions)
  const seqRow = await adb.get<any>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices");
  const orderId = generateOrderId('INV', seqRow.next_num);

  const createInvoice = db.transaction(() => {
    let subtotal = 0;
    let total_tax = 0;

    // Calculate totals
    for (const item of line_items) {
      const lineTotal = (item.quantity || 1) * (item.unit_price || 0);
      const lineDiscount = item.line_discount || 0;
      const lineTax = item.tax_amount || 0;
      subtotal += lineTotal - lineDiscount;
      total_tax += lineTax;
    }
    const appliedDiscount = discount || 0;
    if (appliedDiscount > subtotal + total_tax) {
      throw new AppError('Discount cannot exceed total', 400);
    }
    const total = subtotal + total_tax - appliedDiscount;
    const amount_due = total;

    const result = db.prepare(`
      INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, discount_reason,
        total_tax, total, amount_paid, amount_due, notes, due_date, created_by,
        is_deposit, deposit_amount, parent_invoice_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?)
    `).run(orderId, customer_id, ticket_id || null, subtotal, discount || 0, discount_reason || null,
      total_tax, total, amount_due, notes || null, due_date || null, req.user!.id,
      depositFlag, depositAmount, parent_invoice_id || null);

    const invoiceId = result.lastInsertRowid;

    for (const item of line_items) {
      // SEC-M12: Destructure only allowed fields (prevents mass assignment)
      const { inventory_item_id, description, quantity, unit_price, line_discount, tax_amount, tax_class_id, notes: itemNotes } = item;
      validatePrice(unit_price ?? 0, 'line item unit_price');
      // SEC-M10: Validate text lengths on line items
      if (typeof description === 'string' && description.length > 500) throw new AppError('Line item description exceeds 500 characters', 400);
      if (typeof itemNotes === 'string' && itemNotes.length > 1000) throw new AppError('Line item notes exceeds 1000 characters', 400);
      const lineTotal = ((quantity || 1) * (unit_price || 0)) - (line_discount || 0) + (tax_amount || 0);
      db.prepare(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, line_discount, tax_amount, tax_class_id, total, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(invoiceId, inventory_item_id || null, description || '', quantity || 1,
        unit_price || 0, line_discount || 0, tax_amount || 0, tax_class_id || null,
        lineTotal, itemNotes || null);
    }

    // Link ticket to invoice if provided
    if (ticket_id) {
      db.prepare('UPDATE tickets SET invoice_id = ?, updated_at = datetime(\'now\') WHERE id = ?').run(invoiceId, ticket_id);
    }

    return invoiceId;
  });

  const invoiceId = createInvoice();
  const invoice = await getInvoiceDetail(adb, invoiceId as number);
  broadcast(WS_EVENTS.INVOICE_CREATED, invoice, req.tenantSlug || null);

  // ENR-A6: Fire webhook
  fireWebhook(db, 'invoice_created', { invoice_id: invoiceId, order_id: (invoice as any)?.order_id });

  // Fire automations (async, non-blocking)
  const cust = customer_id ? await adb.get<any>('SELECT * FROM customers WHERE id = ?', customer_id) : {};
  runAutomations(db, 'invoice_created', { invoice, customer: cust ?? {} });

  res.status(201).json({ success: true, data: { invoice } });
});

// PUT /invoices/:id
router.put('/:id', async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Invoice not found', 404);
  if (existing.status === 'void') throw new AppError('Cannot modify a voided invoice', 400);

  const { notes, due_date, due_on, discount, discount_reason, payment_plan } = req.body;
  const dueDate = due_date ?? due_on; // accept both field names

  // ENR-I8: Validate payment_plan JSON structure if provided
  if (payment_plan !== undefined && payment_plan !== null) {
    if (typeof payment_plan !== 'object') throw new AppError('payment_plan must be an object', 400);
    const pp = payment_plan;
    if (pp.installments !== undefined && (typeof pp.installments !== 'number' || pp.installments < 1)) {
      throw new AppError('payment_plan.installments must be a positive number', 400);
    }
    if (pp.frequency && !['weekly', 'monthly'].includes(pp.frequency)) {
      throw new AppError('payment_plan.frequency must be weekly or monthly', 400);
    }
    if (pp.amount_per !== undefined && (typeof pp.amount_per !== 'number' || pp.amount_per <= 0)) {
      throw new AppError('payment_plan.amount_per must be a positive number', 400);
    }
  }

  // Recalculate totals when discount changes
  const newDiscount = discount ?? existing.discount;
  if (newDiscount > existing.subtotal + existing.total_tax) {
    throw new AppError('Discount cannot exceed total', 400);
  }
  const total = existing.subtotal + existing.total_tax - newDiscount;
  const amountDue = total - existing.amount_paid;

  await adb.run(`
    UPDATE invoices SET
      notes = COALESCE(?, notes),
      due_on = COALESCE(?, due_on),
      discount = ?,
      discount_reason = COALESCE(?, discount_reason),
      total = ?,
      amount_due = ?,
      payment_plan = COALESCE(?, payment_plan),
      updated_at = datetime('now')
    WHERE id = ?
  `,
    notes ?? null, dueDate ?? null, newDiscount, discount_reason ?? null,
    total, Math.max(0, amountDue),
    payment_plan !== undefined ? JSON.stringify(payment_plan) : null,
    req.params.id,
  );

  const invoice = await getInvoiceDetail(adb, req.params.id);
  broadcast(WS_EVENTS.INVOICE_UPDATED, invoice, req.tenantSlug || null);
  res.json({ success: true, data: { invoice } });
});

// Payment dedup: prevent double-submit within 5 seconds for same invoice+amount
const recentPayments = new Map<string, number>();
setInterval(() => { const now = Date.now(); for (const [k, v] of recentPayments) { if (now - v > 30000) recentPayments.delete(k); } }, 30000);

// POST /invoices/:id/payments
router.post('/:id/payments', idempotent, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const invoice = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', req.params.id);
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') throw new AppError('Cannot add payment to voided invoice', 400);

  const { method = 'cash', method_detail, transaction_id, notes, payment_type = 'payment' } = req.body;
  const amount = validatePrice(req.body.amount, 'payment amount');
  if (amount <= 0) throw new AppError('Payment amount must be positive', 400);

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

  const recordPayment = db.transaction(() => {
    db.prepare(`
      INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id, notes, payment_type, user_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(req.params.id, amount, method, method_detail || null,
      transaction_id || null, notes || null, payment_type, req.user!.id);

    const totalPaid = (db.prepare('SELECT SUM(amount) as t FROM payments WHERE invoice_id = ?').get(req.params.id) as any).t || 0;
    const amountDue = invoice.total - totalPaid;
    const status = amountDue <= 0 ? 'paid' : totalPaid > 0 ? 'partial' : 'unpaid';

    db.prepare(`
      UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
    `).run(totalPaid, Math.max(0, amountDue), status, req.params.id);
  });

  recordPayment();
  const updated = await getInvoiceDetail(adb, req.params.id as string);
  broadcast(WS_EVENTS.PAYMENT_RECEIVED, updated, req.tenantSlug || null);

  // ENR-A6: Fire webhook for payment received
  fireWebhook(db, 'payment_received', {
    invoice_id: Number(req.params.id),
    amount: parseFloat(req.body.amount),
    method,
  });

  res.status(201).json({ success: true, data: { invoice: updated } });
});

// POST /invoices/:id/void (rate limited: 1 per minute per user)
const voidTimestamps = new Map<number, number>();
router.post('/:id/void', async (req, res) => {
  const db = req.db;
  // Only admins and managers can void invoices
  if (req.user!.role !== 'admin' && req.user!.role !== 'manager') {
    throw new AppError('Only admins and managers can void invoices', 403);
  }
  const userId = req.user!.id;
  const lastVoid = voidTimestamps.get(userId);
  if (lastVoid && Date.now() - lastVoid < 60000) {
    throw new AppError('Can only void one invoice per minute', 429);
  }

  const voidInvoice = db.transaction(() => {
    // Atomic void: UPDATE with WHERE status != 'void' prevents TOCTOU race condition
    const result = db.prepare(
      "UPDATE invoices SET status = 'void', amount_paid = 0, amount_due = 0, updated_at = datetime('now') WHERE id = ? AND status != 'void'"
    ).run(req.params.id);

    if (result.changes === 0) {
      // Either not found or already voided — check which
      const exists = db.prepare('SELECT status FROM invoices WHERE id = ?').get(req.params.id) as any;
      if (!exists) throw new AppError('Invoice not found', 404);
      throw new AppError('Already voided', 400);
    }

    // Only restore stock for direct invoices (no ticket_id).
    // Ticket-originated invoices had stock deducted by the ticket, not the invoice.
    const invoice = db.prepare('SELECT ticket_id FROM invoices WHERE id = ?').get(req.params.id) as any;
    if (!invoice.ticket_id) {
      const lineItems = db.prepare('SELECT inventory_item_id, quantity FROM invoice_line_items WHERE invoice_id = ? AND inventory_item_id IS NOT NULL').all(req.params.id) as any[];
      for (const li of lineItems) {
        db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime(\'now\') WHERE id = ?').run(li.quantity, li.inventory_item_id);
        db.prepare(`
          INSERT INTO stock_movements (inventory_item_id, quantity, type, reason, reference_type, reference_id, user_id)
          VALUES (?, ?, 'adjustment', 'Invoice voided — stock restored', 'invoice', ?, ?)
        `).run(li.inventory_item_id, li.quantity, req.params.id, req.user!.id);
      }
    }

    // Mark payments as voided (keep records for audit trail)
    db.prepare("UPDATE payments SET notes = COALESCE(notes || ' ', '') || '[VOIDED]' WHERE invoice_id = ?").run(req.params.id);
  });

  voidInvoice();
  voidTimestamps.set(userId, Date.now());
  audit(db, 'invoice_voided', req.user!.id, req.ip || 'unknown', { invoice_id: Number(req.params.id) });
  broadcast(WS_EVENTS.INVOICE_UPDATED, { id: Number(req.params.id), status: 'void' }, req.tenantSlug || null);
  res.json({ success: true, data: { message: 'Invoice voided, stock restored' } });
});

// ===================================================================
// POST /bulk-action - Batch invoice actions (admin-only)
// ===================================================================
router.post('/bulk-action', async (req, res) => {
  const db = req.db;

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

  const doBulk = db.transaction(() => {
    for (const id of invoice_ids) {
      try {
        const invoice = db.prepare('SELECT * FROM invoices WHERE id = ?').get(id) as any;
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
            db.prepare("UPDATE invoices SET reminder_sent_at = datetime('now'), updated_at = datetime('now') WHERE id = ?").run(id);
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
            // Record a payment for the remaining amount
            const remaining = invoice.amount_due > 0 ? invoice.amount_due : invoice.total;
            db.prepare(`
              INSERT INTO payments (invoice_id, amount, method, notes, user_id)
              VALUES (?, ?, 'cash', 'Bulk mark-paid', ?)
            `).run(id, remaining, req.user!.id);

            db.prepare(`
              UPDATE invoices SET amount_paid = total, amount_due = 0, status = 'paid', updated_at = datetime('now') WHERE id = ?
            `).run(id);
            successCount++;
            break;
          }
          case 'void': {
            if (invoice.status === 'void') {
              failCount++;
              errors.push({ invoice_id: id, error: 'Already voided' });
              continue;
            }
            db.prepare(
              "UPDATE invoices SET status = 'void', amount_paid = 0, amount_due = 0, updated_at = datetime('now') WHERE id = ?"
            ).run(id);
            db.prepare("UPDATE payments SET notes = COALESCE(notes || ' ', '') || '[VOIDED]' WHERE invoice_id = ?").run(id);
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
  });

  doBulk();

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
router.post('/:id/credit-note', async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const invoiceId = parseInt(req.params.id);

  const original = await adb.get<any>('SELECT * FROM invoices WHERE id = ?', invoiceId);
  if (!original) throw new AppError('Invoice not found', 404);
  if (original.status === 'void') throw new AppError('Cannot create credit note for voided invoice', 400);

  const { amount, reason } = req.body;
  if (!amount || typeof amount !== 'number' || amount <= 0) {
    throw new AppError('amount must be a positive number', 400);
  }
  if (amount > original.total) {
    throw new AppError('Credit note amount cannot exceed original invoice total', 400);
  }
  if (!reason || typeof reason !== 'string' || reason.trim().length === 0) {
    throw new AppError('reason is required', 400);
  }

  const createCreditNote = db.transaction(() => {
    // Generate order_id for credit note
    const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices").get() as any;
    const orderId = generateOrderId('INV', seqRow.next_num);

    // Create the credit note as a negative invoice
    const result = db.prepare(`
      INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
        amount_paid, amount_due, notes, credit_note_for, status, created_by)
      VALUES (?, ?, ?, ?, 0, 0, ?, 0, 0, ?, ?, 'paid', ?)
    `).run(
      orderId,
      original.customer_id,
      original.ticket_id,
      -amount,       // negative subtotal
      -amount,       // negative total
      `Credit note: ${reason.trim()}`,
      invoiceId,     // link to original
      req.user!.id,
    );

    const creditNoteId = result.lastInsertRowid;

    // Add a single line item for the credit
    db.prepare(`
      INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, total, notes)
      VALUES (?, ?, 1, ?, ?, ?)
    `).run(creditNoteId, `Credit note for invoice #${original.order_id}`, -amount, -amount, reason.trim());

    // Adjust the original invoice balance
    const newAmountPaid = original.amount_paid + amount;
    const newAmountDue = Math.max(0, original.total - newAmountPaid);
    const newStatus = newAmountDue <= 0 ? 'paid' : newAmountPaid > 0 ? 'partial' : 'unpaid';

    db.prepare(`
      UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
    `).run(newAmountPaid, newAmountDue, newStatus, invoiceId);

    return creditNoteId;
  });

  const creditNoteId = createCreditNote();
  const creditNote = await getInvoiceDetail(adb, creditNoteId as number);

  audit(db, 'credit_note_created', req.user!.id, req.ip || 'unknown', {
    credit_note_id: Number(creditNoteId),
    original_invoice_id: invoiceId,
    amount,
    reason: reason.trim(),
  });

  broadcast(WS_EVENTS.INVOICE_CREATED, creditNote, req.tenantSlug || null);
  broadcast(WS_EVENTS.INVOICE_UPDATED, { id: invoiceId }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: { credit_note: creditNote } });
});

export default router;
