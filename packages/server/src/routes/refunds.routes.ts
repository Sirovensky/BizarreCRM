import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List refunds
router.get('/', asyncHandler(async (req, res) => {
  const db = req.db;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const pageSize = Math.min(100, parseInt(req.query.pagesize as string) || 25);
  const offset = (page - 1) * pageSize;

  const total = (db.prepare('SELECT COUNT(*) as c FROM refunds').get() as any).c;
  const refunds = db.prepare(`
    SELECT r.*, c.first_name, c.last_name, i.order_id AS invoice_order_id,
           u.first_name AS created_first, u.last_name AS created_last
    FROM refunds r
    LEFT JOIN customers c ON c.id = r.customer_id
    LEFT JOIN invoices i ON i.id = r.invoice_id
    LEFT JOIN users u ON u.id = r.created_by
    ORDER BY r.created_at DESC LIMIT ? OFFSET ?
  `).all(pageSize, offset);

  res.json({ success: true, data: { refunds, pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) } } });
}));

// POST / — Create refund
router.post('/', asyncHandler(async (req, res) => {
  const db = req.db;
  const { invoice_id, ticket_id, customer_id, amount, type = 'refund', reason, method } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);
  if (!customer_id) throw new AppError('customer_id required', 400);

  const result = db.prepare(`
    INSERT INTO refunds (invoice_id, ticket_id, customer_id, amount, type, reason, method, status, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
  `).run(invoice_id || null, ticket_id || null, customer_id, amount, type, reason || null, method || null, req.user!.id, now(), now());

  const refundId = Number(result.lastInsertRowid);
  audit(db, 'refund_created', req.user!.id, req.ip || 'unknown', { refund_id: refundId, amount, type });

  res.status(201).json({ success: true, data: { id: refundId } });
}));

// PATCH /:id/approve — Approve refund (admin only)
router.patch('/:id/approve', asyncHandler(async (req, res) => {
  const db = req.db;
  if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
  const id = parseInt(req.params.id);
  const refund = db.prepare('SELECT * FROM refunds WHERE id = ?').get(id) as any;
  if (!refund) throw new AppError('Refund not found', 404);
  if (refund.status !== 'pending') throw new AppError('Refund is not pending', 400);

  const process = db.transaction(() => {
    db.prepare('UPDATE refunds SET status = ?, approved_by = ?, updated_at = ? WHERE id = ?')
      .run('completed', req.user!.id, now(), id);

    // Update invoice amount_paid if refund is linked to an invoice
    if (refund.invoice_id) {
      db.prepare('UPDATE invoices SET amount_paid = MAX(0, amount_paid - ?), updated_at = ? WHERE id = ?')
        .run(refund.amount, now(), refund.invoice_id);
      // Recalculate invoice status
      const inv = db.prepare('SELECT total, amount_paid FROM invoices WHERE id = ?').get(refund.invoice_id) as any;
      if (inv) {
        const newStatus = inv.amount_paid <= 0 ? 'unpaid' : inv.amount_paid >= inv.total ? 'paid' : 'partial';
        const newDue = Math.max(0, inv.total - inv.amount_paid);
        db.prepare('UPDATE invoices SET status = ?, amount_due = ?, updated_at = ? WHERE id = ?')
          .run(newStatus, newDue, now(), refund.invoice_id);
      }
    }

    // If type is store_credit, add to customer's credit balance
    if (refund.type === 'store_credit') {
      const existing = db.prepare('SELECT id, amount FROM store_credits WHERE customer_id = ?').get(refund.customer_id) as any;
      if (existing) {
        db.prepare('UPDATE store_credits SET amount = amount + ?, updated_at = ? WHERE id = ?')
          .run(refund.amount, now(), existing.id);
      } else {
        db.prepare('INSERT INTO store_credits (customer_id, amount, created_at, updated_at) VALUES (?, ?, ?, ?)')
          .run(refund.customer_id, refund.amount, now(), now());
      }
      db.prepare(`
        INSERT INTO store_credit_transactions (customer_id, amount, type, reference_type, reference_id, notes, user_id, created_at)
        VALUES (?, ?, 'refund_credit', 'refund', ?, ?, ?, ?)
      `).run(refund.customer_id, refund.amount, id, refund.reason || 'Refund to store credit', req.user!.id, now());
    }
  });
  process();

  audit(db, 'refund_approved', req.user!.id, req.ip || 'unknown', { refund_id: id, amount: refund.amount });
  res.json({ success: true, data: { id } });
}));

// PATCH /:id/decline — Decline refund
router.patch('/:id/decline', asyncHandler(async (req, res) => {
  const db = req.db;
  if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
  const id = parseInt(req.params.id);
  db.prepare('UPDATE refunds SET status = ?, updated_at = ? WHERE id = ?').run('declined', now(), id);
  res.json({ success: true, data: { id } });
}));

// GET /credits/:customerId — Get customer store credit balance + history
router.get('/credits/:customerId', asyncHandler(async (req, res) => {
  const db = req.db;
  const customerId = parseInt(req.params.customerId);
  const credit = db.prepare('SELECT * FROM store_credits WHERE customer_id = ?').get(customerId) as any;
  const transactions = db.prepare(
    'SELECT * FROM store_credit_transactions WHERE customer_id = ? ORDER BY created_at DESC LIMIT 50'
  ).all(customerId);
  res.json({ success: true, data: { balance: credit?.amount || 0, transactions } });
}));

// POST /credits/:customerId/use — Use store credit on invoice
router.post('/credits/:customerId/use', asyncHandler(async (req, res) => {
  const db = req.db;
  const customerId = parseInt(req.params.customerId);
  const { amount, invoice_id } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);

  const useCredit = db.transaction(() => {
    const credit = db.prepare('SELECT id, amount FROM store_credits WHERE customer_id = ?').get(customerId) as any;
    if (!credit || credit.amount < amount) throw new AppError('Insufficient store credit', 400);

    db.prepare('UPDATE store_credits SET amount = amount - ?, updated_at = ? WHERE id = ?').run(amount, now(), credit.id);
    db.prepare(`
      INSERT INTO store_credit_transactions (customer_id, amount, type, reference_type, reference_id, notes, user_id, created_at)
      VALUES (?, ?, 'usage', 'invoice', ?, 'Store credit applied', ?, ?)
    `).run(customerId, -amount, invoice_id || null, req.user!.id, now());

    return credit.amount - amount;
  });

  const newBalance = useCredit();
  res.json({ success: true, data: { new_balance: newBalance } });
}));

export default router;
