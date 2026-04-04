import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { validatePrice } from '../utils/validate.js';
import { generateOrderId } from '../utils/format.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { runAutomations } from '../services/automations.js';
import { idempotent } from '../middleware/idempotency.js';

const router = Router();

function getInvoiceDetail(id: number | string) {
  const invoice = db.prepare(`
    SELECT inv.*,
      c.first_name, c.last_name, c.email as customer_email, c.phone as customer_phone,
      c.organization,
      u.first_name || ' ' || u.last_name as created_by_name
    FROM invoices inv
    LEFT JOIN customers c ON c.id = inv.customer_id
    LEFT JOIN users u ON u.id = inv.created_by
    WHERE inv.id = ?
  `).get(id) as any;
  if (!invoice) return null;

  invoice.line_items = db.prepare(`
    SELECT li.*, i.name as item_name, i.sku
    FROM invoice_line_items li
    LEFT JOIN inventory_items i ON i.id = li.inventory_item_id
    WHERE li.invoice_id = ?
    ORDER BY li.id ASC
  `).all(id);

  invoice.payments = db.prepare(`
    SELECT p.*, u.first_name || ' ' || u.last_name as recorded_by
    FROM payments p
    LEFT JOIN users u ON u.id = p.user_id
    WHERE p.invoice_id = ?
    ORDER BY p.created_at ASC
  `).all(id);

  return invoice;
}

// GET /invoices
router.get('/', (req, res) => {
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

  const total = (db.prepare(`
    SELECT COUNT(*) as c FROM invoices inv LEFT JOIN customers c ON c.id = inv.customer_id ${where}
  `).get(...params) as any).c;

  const invoices = db.prepare(`
    SELECT inv.*, c.first_name, c.last_name, c.organization, c.phone as customer_phone,
      t.order_id as ticket_order_id
    FROM invoices inv
    LEFT JOIN customers c ON c.id = inv.customer_id
    LEFT JOIN tickets t ON t.id = inv.ticket_id
    ${where}
    ORDER BY inv.created_at DESC
    LIMIT ? OFFSET ?
  `).all(...params, ps, offset);

  res.json({
    success: true,
    data: {
      invoices,
      pagination: { page: p, per_page: ps, total, total_pages: Math.ceil(total / ps) },
    },
  });
});

// GET /invoices/stats — KPIs and distribution data for overview
router.get('/stats', (_req, res) => {
  const kpis = db.prepare(`
    SELECT
      COALESCE(SUM(total), 0) AS total_sales,
      COUNT(*) AS invoice_count,
      COALESCE(SUM(total_tax), 0) AS tax_collected,
      COALESCE(SUM(CASE WHEN status IN ('unpaid','partial') THEN amount_due ELSE 0 END), 0) AS outstanding_receivables
    FROM invoices WHERE status != 'void'
  `).get() as any;

  const statusDist = db.prepare(`
    SELECT status, COUNT(*) AS count FROM invoices GROUP BY status
  `).all();

  const methodDist = db.prepare(`
    SELECT p.method, COUNT(*) AS count, COALESCE(SUM(p.amount), 0) AS total
    FROM payments p
    JOIN invoices inv ON inv.id = p.invoice_id
    WHERE inv.status != 'void'
    GROUP BY p.method
  `).all();

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
router.get('/:id', (req, res) => {
  const invoice = getInvoiceDetail(req.params.id);
  if (!invoice) throw new AppError('Invoice not found', 404);
  res.json({ success: true, data: { invoice } });
});

// POST /invoices
router.post('/', idempotent, (req, res) => {
  const {
    customer_id, ticket_id, line_items = [], discount = 0, discount_reason,
    notes, due_date,
  } = req.body;

  if (!customer_id) throw new AppError('Customer is required', 400);

  // Get next order_id from existing order_ids (safe across deletions)
  const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices").get() as any;
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
    const total = subtotal + total_tax - (discount || 0);
    const amount_due = total;

    const result = db.prepare(`
      INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, discount_reason,
        total_tax, total, amount_paid, amount_due, notes, due_date, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
    `).run(orderId, customer_id, ticket_id || null, subtotal, discount || 0, discount_reason || null,
      total_tax, total, amount_due, notes || null, due_date || null, req.user!.id);

    const invoiceId = result.lastInsertRowid;

    for (const item of line_items) {
      validatePrice(item.unit_price ?? 0, 'line item unit_price');
      const lineTotal = ((item.quantity || 1) * (item.unit_price || 0)) - (item.line_discount || 0) + (item.tax_amount || 0);
      db.prepare(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price, line_discount, tax_amount, tax_class_id, total, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(invoiceId, item.inventory_item_id || null, item.description || '', item.quantity || 1,
        item.unit_price || 0, item.line_discount || 0, item.tax_amount || 0, item.tax_class_id || null,
        lineTotal, item.notes || null);
    }

    // Link ticket to invoice if provided
    if (ticket_id) {
      db.prepare('UPDATE tickets SET invoice_id = ?, updated_at = datetime(\'now\') WHERE id = ?').run(invoiceId, ticket_id);
    }

    return invoiceId;
  });

  const invoiceId = createInvoice();
  const invoice = getInvoiceDetail(invoiceId as number);
  broadcast(WS_EVENTS.INVOICE_CREATED, invoice);

  // Fire automations (async, non-blocking)
  const cust = customer_id ? db.prepare('SELECT * FROM customers WHERE id = ?').get(customer_id) as any : {};
  runAutomations('invoice_created', { invoice, customer: cust ?? {} });

  res.status(201).json({ success: true, data: { invoice } });
});

// PUT /invoices/:id
router.put('/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM invoices WHERE id = ?').get(req.params.id) as any;
  if (!existing) throw new AppError('Invoice not found', 404);
  if (existing.status === 'void') throw new AppError('Cannot modify a voided invoice', 400);

  const { notes, due_date, discount, discount_reason } = req.body;

  // Recalculate totals when discount changes
  const newDiscount = discount ?? existing.discount;
  const total = existing.subtotal + existing.total_tax - newDiscount;
  const amountDue = total - existing.amount_paid;

  db.prepare(`
    UPDATE invoices SET
      notes = COALESCE(?, notes),
      due_date = COALESCE(?, due_date),
      discount = ?,
      discount_reason = COALESCE(?, discount_reason),
      total = ?,
      amount_due = ?,
      updated_at = datetime('now')
    WHERE id = ?
  `).run(notes ?? null, due_date ?? null, newDiscount, discount_reason ?? null, total, Math.max(0, amountDue), req.params.id);

  const invoice = getInvoiceDetail(req.params.id);
  broadcast(WS_EVENTS.INVOICE_UPDATED, invoice);
  res.json({ success: true, data: { invoice } });
});

// Payment dedup: prevent double-submit within 5 seconds for same invoice+amount
const recentPayments = new Map<string, number>();
setInterval(() => { const now = Date.now(); for (const [k, v] of recentPayments) { if (now - v > 30000) recentPayments.delete(k); } }, 30000);

// POST /invoices/:id/payments
router.post('/:id/payments', idempotent, (req, res) => {
  const invoice = db.prepare('SELECT * FROM invoices WHERE id = ?').get(req.params.id) as any;
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') throw new AppError('Cannot add payment to voided invoice', 400);

  const { method = 'cash', method_detail, transaction_id, notes } = req.body;
  const amount = validatePrice(req.body.amount, 'payment amount');
  if (amount <= 0) throw new AppError('Payment amount must be positive', 400);

  // Double-submit guard: same invoice + amount within 5 seconds = reject
  const dedupKey = `${req.params.id}:${parseFloat(amount).toFixed(2)}:${req.user!.id}`;
  const lastPayment = recentPayments.get(dedupKey);
  if (lastPayment && Date.now() - lastPayment < 5000) {
    throw new AppError('Duplicate payment detected. Please wait before retrying.', 409);
  }
  recentPayments.set(dedupKey, Date.now());

  const recordPayment = db.transaction(() => {
    db.prepare(`
      INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id, notes, user_id)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(req.params.id, parseFloat(amount), method, method_detail || null,
      transaction_id || null, notes || null, req.user!.id);

    const totalPaid = (db.prepare('SELECT SUM(amount) as t FROM payments WHERE invoice_id = ?').get(req.params.id) as any).t || 0;
    const amountDue = invoice.total - totalPaid;
    const status = amountDue <= 0 ? 'paid' : totalPaid > 0 ? 'partial' : 'unpaid';

    db.prepare(`
      UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now') WHERE id = ?
    `).run(totalPaid, Math.max(0, amountDue), status, req.params.id);
  });

  recordPayment();
  const updated = getInvoiceDetail(req.params.id);
  broadcast(WS_EVENTS.PAYMENT_RECEIVED, updated);
  res.status(201).json({ success: true, data: { invoice: updated } });
});

// POST /invoices/:id/void (rate limited: 1 per minute per user)
const voidTimestamps = new Map<number, number>();
router.post('/:id/void', (req, res) => {
  // Only admins and managers can void invoices
  if (req.user!.role !== 'admin' && req.user!.role !== 'manager') {
    throw new AppError('Only admins and managers can void invoices', 403);
  }
  const userId = req.user!.id;
  const lastVoid = voidTimestamps.get(userId);
  if (lastVoid && Date.now() - lastVoid < 60000) {
    throw new AppError('Can only void one invoice per minute', 429);
  }

  const invoice = db.prepare('SELECT * FROM invoices WHERE id = ?').get(req.params.id) as any;
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') throw new AppError('Already voided', 400);

  const voidInvoice = db.transaction(() => {
    // Void the invoice
    db.prepare("UPDATE invoices SET status = 'void', amount_paid = 0, amount_due = 0, updated_at = datetime('now') WHERE id = ?").run(req.params.id);

    // Only restore stock for direct invoices (no ticket_id).
    // Ticket-originated invoices had stock deducted by the ticket, not the invoice.
    if (!invoice.ticket_id) {
      const lineItems = db.prepare('SELECT inventory_item_id, quantity FROM invoice_line_items WHERE invoice_id = ? AND inventory_item_id IS NOT NULL').all(req.params.id) as any[];
      for (const li of lineItems) {
        db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime(\'now\') WHERE id = ?').run(li.quantity, li.inventory_item_id);
      }
    }

    // Mark payments as voided (keep records for audit trail)
    db.prepare("UPDATE payments SET notes = COALESCE(notes || ' ', '') || '[VOIDED]' WHERE invoice_id = ?").run(req.params.id);
  });

  voidInvoice();
  voidTimestamps.set(userId, Date.now());
  broadcast(WS_EVENTS.INVOICE_UPDATED, { id: Number(req.params.id), status: 'void' });
  res.json({ success: true, data: { message: 'Invoice voided, stock restored' } });
});

export default router;
