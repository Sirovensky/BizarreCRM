/**
 * Credit Notes routes
 * Mounted at: /api/v1/credit-notes
 * Auth: authMiddleware applied at parent mount — NOT repeated here.
 *
 * Role gates:
 *   POST /:id/apply — requireManagerOrAdmin
 *   POST /:id/void  — requireManagerOrAdmin
 *   GET, POST (create) — any authenticated user
 *
 * Table: credit_notes (created in migration 123_recurring_invoices.sql)
 *   id, customer_id, original_invoice_id, amount_cents, reason,
 *   status CHECK IN ('open','applied','voided'),
 *   applied_to_invoice_id, applied_at, voided_at,
 *   created_by_user_id, created_at
 */
import { Router, Request } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { allocateCounter, formatCreditNoteId } from '../utils/counters.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('credit-notes');

// ---------------------------------------------------------------------------
// Rate limit constants
// ---------------------------------------------------------------------------
const RL_WRITE_MAX = 30;
const RL_WRITE_WINDOW_MS = 60_000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireManagerOrAdmin(req: Request): void {
  if (!req.user) throw new AppError('Not authenticated', 401);
  if (req.user.role !== 'admin' && req.user.role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function validateId(raw: unknown, field = 'id'): number {
  const str = typeof raw === 'string' ? raw : Array.isArray(raw) ? raw[0] ?? '' : '';
  const n = parseInt(str, 10);
  if (!Number.isInteger(n) || n < 1) throw new AppError(`${field} must be a positive integer`, 400);
  return n;
}

function writeRateLimit(req: Request): void {
  const rlKey = String(req.user!.id);
  const rl = consumeWindowRate(req.db, 'credit_note_write', rlKey, RL_WRITE_MAX, RL_WRITE_WINDOW_MS);
  if (!rl.allowed) {
    throw new AppError('Too many credit note operations — please slow down', 429);
  }
}

// ---------------------------------------------------------------------------
// GET /
// ---------------------------------------------------------------------------
router.get('/', asyncHandler(async (req, res) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const {
    page = '1',
    pagesize = '20',
    status,
    customer_id,
  } = req.query as Record<string, string>;

  const p  = Math.max(1, parseInt(page, 10));
  const ps = Math.min(100, Math.max(1, parseInt(pagesize, 10)));
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: unknown[] = [];

  if (status) {
    const allowed = ['open', 'applied', 'voided'];
    if (!allowed.includes(status)) throw new AppError(`status must be one of: ${allowed.join(', ')}`, 400);
    where += ' AND cn.status = ?';
    params.push(status);
  }

  if (customer_id) {
    const cid = parseInt(customer_id, 10);
    if (!Number.isInteger(cid) || cid < 1) throw new AppError('customer_id must be a positive integer', 400);
    where += ' AND cn.customer_id = ?';
    params.push(cid);
  }

  const [totalRow, notes] = await Promise.all([
    adb.get<{ c: number }>(`
      SELECT COUNT(*) AS c
      FROM credit_notes cn
      ${where}
    `, ...params),
    adb.all<Record<string, unknown>>(`
      SELECT
        cn.*,
        c.first_name || ' ' || c.last_name AS customer_name,
        orig.order_id AS original_invoice_order_id,
        applied.order_id AS applied_to_invoice_order_id,
        u.first_name || ' ' || u.last_name AS created_by_name
      FROM credit_notes cn
      LEFT JOIN customers c ON c.id = cn.customer_id
      LEFT JOIN invoices orig ON orig.id = cn.original_invoice_id
      LEFT JOIN invoices applied ON applied.id = cn.applied_to_invoice_id
      LEFT JOIN users u ON u.id = cn.created_by_user_id
      ${where}
      ORDER BY cn.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, ps, offset),
  ]);

  res.json({
    success: true,
    data: {
      credit_notes: notes,
      pagination: {
        page: p,
        per_page: ps,
        total: totalRow?.c ?? 0,
        total_pages: Math.ceil((totalRow?.c ?? 0) / ps),
      },
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /:id
// ---------------------------------------------------------------------------
router.get('/:id', asyncHandler(async (req, res) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const id = validateId(req.params.id);

  const note = await adb.get<Record<string, unknown>>(`
    SELECT
      cn.*,
      c.first_name || ' ' || c.last_name AS customer_name,
      orig.order_id AS original_invoice_order_id,
      applied.order_id AS applied_to_invoice_order_id,
      u.first_name || ' ' || u.last_name AS created_by_name
    FROM credit_notes cn
    LEFT JOIN customers c ON c.id = cn.customer_id
    LEFT JOIN invoices orig ON orig.id = cn.original_invoice_id
    LEFT JOIN invoices applied ON applied.id = cn.applied_to_invoice_id
    LEFT JOIN users u ON u.id = cn.created_by_user_id
    WHERE cn.id = ?
  `, id);

  if (!note) throw new AppError('Credit note not found', 404);

  res.json({ success: true, data: note });
}));

// ---------------------------------------------------------------------------
// POST /  — create a credit note
// ---------------------------------------------------------------------------
router.post('/', asyncHandler(async (req, res) => {
  if (!req.user) throw new AppError('Not authenticated', 401);
  writeRateLimit(req);

  const adb = req.asyncDb;
  const {
    customer_id,
    original_invoice_id,
    amount_cents,
    reason,
  } = req.body as Record<string, unknown>;

  // Validate inputs
  const safeCustomerId = typeof customer_id === 'number' ? customer_id : parseInt(String(customer_id), 10);
  if (!Number.isInteger(safeCustomerId) || safeCustomerId < 1) {
    throw new AppError('customer_id must be a positive integer', 400);
  }

  const safeCents = typeof amount_cents === 'number' ? amount_cents : parseInt(String(amount_cents ?? 0), 10);
  if (!Number.isInteger(safeCents) || safeCents <= 0) {
    throw new AppError('amount_cents must be a positive integer (cents)', 400);
  }

  if (reason != null && typeof reason === 'string' && reason.length > 2000) {
    throw new AppError('reason exceeds 2000 characters', 400);
  }

  // Verify customer exists
  const cust = await adb.get<{ id: number }>('SELECT id FROM customers WHERE id = ?', safeCustomerId);
  if (!cust) throw new AppError('Customer not found', 404);

  // Verify original invoice if provided
  if (original_invoice_id != null) {
    const invoiceId = parseInt(String(original_invoice_id), 10);
    if (!Number.isInteger(invoiceId) || invoiceId < 1) throw new AppError('original_invoice_id must be a positive integer', 400);
    const inv = await adb.get<{ id: number }>('SELECT id FROM invoices WHERE id = ?', invoiceId);
    if (!inv) throw new AppError('Original invoice not found', 404);
  }

  // Allocate CN-N order id
  const seq = allocateCounter(req.db, 'credit_note_id');
  const cnOrderId = formatCreditNoteId(seq);

  const result = await adb.run(`
    INSERT INTO credit_notes
      (customer_id, original_invoice_id, amount_cents, reason, status,
       created_by_user_id, created_at)
    VALUES (?, ?, ?, ?, 'open', ?, datetime('now'))
  `,
    safeCustomerId,
    original_invoice_id != null ? parseInt(String(original_invoice_id), 10) : null,
    safeCents,
    (typeof reason === 'string' ? reason : null),
    req.user.id,
  );

  const newId = result.lastInsertRowid as number;

  audit(req.db, 'credit_note.created', req.user.id, req.ip ?? '', {
    credit_note_id: newId,
    cn_order_id: cnOrderId,
    customer_id: safeCustomerId,
    amount_cents: safeCents,
  });

  logger.info('credit note created', { credit_note_id: newId, cn_order_id: cnOrderId });

  const note = await adb.get<Record<string, unknown>>('SELECT * FROM credit_notes WHERE id = ?', newId);
  res.status(201).json({ success: true, data: { ...note, order_id: cnOrderId } });
}));

// ---------------------------------------------------------------------------
// POST /:id/apply  — apply credit to an invoice (reduces invoice amount_due)
// ---------------------------------------------------------------------------
router.post('/:id/apply', asyncHandler(async (req, res) => {
  requireManagerOrAdmin(req);
  writeRateLimit(req);

  const adb = req.asyncDb;
  const id = validateId(req.params.id);
  const { invoice_id } = req.body as Record<string, unknown>;

  const invoiceIdNum = typeof invoice_id === 'number' ? invoice_id : parseInt(String(invoice_id ?? ''), 10);
  if (!Number.isInteger(invoiceIdNum) || invoiceIdNum < 1) {
    throw new AppError('invoice_id must be a positive integer', 400);
  }

  // Run apply in a transaction
  const applyTx = req.db.transaction(() => {
    const note = req.db.prepare(
      'SELECT * FROM credit_notes WHERE id = ?'
    ).get(id) as Record<string, unknown> | undefined;

    if (!note) throw new AppError('Credit note not found', 404);
    if (note.status !== 'open') throw new AppError(`Credit note is already ${note.status}`, 400);

    const inv = req.db.prepare(
      "SELECT id, amount_due, status FROM invoices WHERE id = ?"
    ).get(invoiceIdNum) as { id: number; amount_due: number; status: string } | undefined;

    if (!inv) throw new AppError('Invoice not found', 404);
    if (inv.status === 'void') throw new AppError('Cannot apply credit to a voided invoice', 400);
    if (inv.status === 'paid') throw new AppError('Cannot apply credit to a fully paid invoice', 400);

    const amountCents = note.amount_cents as number;
    // Convert cents to dollars for amount_due column (invoices use dollars)
    const creditDollars = amountCents / 100;
    const newAmountDue = Math.max(0, inv.amount_due - creditDollars);

    req.db.prepare(`
      UPDATE invoices
         SET amount_due = ?,
             updated_at = datetime('now')
       WHERE id = ?
    `).run(newAmountDue, invoiceIdNum);

    req.db.prepare(`
      UPDATE credit_notes
         SET status = 'applied',
             applied_to_invoice_id = ?,
             applied_at = datetime('now')
       WHERE id = ?
    `).run(invoiceIdNum, id);
  });

  applyTx();

  audit(req.db, 'credit_note.applied', req.user!.id, req.ip ?? '', {
    credit_note_id: id,
    invoice_id: invoiceIdNum,
  });

  logger.info('credit note applied', { credit_note_id: id, invoice_id: invoiceIdNum });

  const note = await adb.get<Record<string, unknown>>('SELECT * FROM credit_notes WHERE id = ?', id);
  res.json({ success: true, data: note });
}));

// ---------------------------------------------------------------------------
// POST /:id/void
// ---------------------------------------------------------------------------
router.post('/:id/void', asyncHandler(async (req, res) => {
  requireManagerOrAdmin(req);
  writeRateLimit(req);

  const adb = req.asyncDb;
  const id = validateId(req.params.id);

  // First check existence so we can emit a clean 404 instead of generic 409.
  const existing = await adb.get<{ id: number; status: string }>('SELECT id, status FROM credit_notes WHERE id = ?', id);
  if (!existing) throw new AppError('Credit note not found', 404);

  // Conditional update: transitions only happen when status is still `open`.
  // Eliminates the SELECT+UPDATE TOCTOU race where two concurrent void calls
  // (or void+apply) could both pass the pre-check and double-flip the row.
  const result = await adb.run(
    "UPDATE credit_notes SET status = 'voided', voided_at = datetime('now') WHERE id = ? AND status = 'open'",
    id,
  );
  if (result.changes === 0) {
    if (existing.status === 'voided') throw new AppError('Credit note is already voided', 400);
    if (existing.status === 'applied') throw new AppError('Cannot void an already-applied credit note', 400);
    // Fallback — status was valid at SELECT time but changed between SELECT
    // and UPDATE (concurrent writer won). Surface as 409 Conflict.
    throw new AppError('Credit note state changed; refresh and retry', 409);
  }

  audit(req.db, 'credit_note.voided', req.user!.id, req.ip ?? '', { credit_note_id: id });

  logger.info('credit note voided', { credit_note_id: id });

  const note = await adb.get<Record<string, unknown>>('SELECT * FROM credit_notes WHERE id = ?', id);
  res.json({ success: true, data: note });
}));

export default router;
