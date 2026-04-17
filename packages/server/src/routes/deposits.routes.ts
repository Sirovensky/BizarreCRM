/**
 * Deposits routes — audit §52 idea 8.
 *
 * "Collect $100 deposit" at repair drop-off. Final invoice auto-references
 * the deposit via `applied_to_invoice_id`.
 *
 * Mounted at /api/v1/deposits with authMiddleware.
 * Response shape: `{ success: true, data: X }`.
 */
import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requirePermission } from '../middleware/auth.js';
import { createLogger } from '../utils/logger.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import {
  validatePositiveAmount,
  validateTextLength,
  validateIntegerQuantity,
} from '../utils/validate.js';

// Post-enrichment audit §9: per-user cap on deposit collection. Every POST
// inserts a money row — a fat-fingered tap-to-collect on a touchscreen POS
// could create 50 duplicate deposit rows in a few seconds. Bound it.
const DEPOSIT_CREATE_CATEGORY = 'deposit_create';
const DEPOSIT_CREATE_MAX = 20;
const DEPOSIT_CREATE_WINDOW_MS = 60_000; // 20 deposits per user per minute

const logger = createLogger('billing-enrich');
const router = Router();

type Row = Record<string, any>;

// SEC (post-enrichment audit §6): applying a deposit to an invoice =
// manager/admin (affects invoice balance); refund = admin only.
function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}
function requireAdminDeposits(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
  }
}

function nowIso(): string {
  return new Date().toISOString();
}

// ---------------------------------------------------------------------------
// GET / — list deposits, filterable by customer_id / ticket_id / applied status
// ---------------------------------------------------------------------------
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const customerId = req.query.customer_id ? parseInt(req.query.customer_id as string, 10) : null;
  const ticketId = req.query.ticket_id ? parseInt(req.query.ticket_id as string, 10) : null;
  const applied = req.query.applied as string | undefined;

  const where: string[] = [];
  const params: any[] = [];
  if (Number.isFinite(customerId)) { where.push('d.customer_id = ?'); params.push(customerId); }
  if (Number.isFinite(ticketId))   { where.push('d.ticket_id = ?');   params.push(ticketId); }
  if (applied === 'unapplied')     { where.push('d.applied_to_invoice_id IS NULL AND d.refunded_at IS NULL'); }
  if (applied === 'applied')       { where.push('d.applied_to_invoice_id IS NOT NULL'); }

  const rows = await req.asyncDb.all<Row>(
    `SELECT d.*, c.first_name, c.last_name
       FROM deposits d
       LEFT JOIN customers c ON c.id = d.customer_id
       ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
       ORDER BY d.id DESC
       LIMIT 500`,
    ...params,
  );

  res.json({ success: true, data: rows });
}));

// ---------------------------------------------------------------------------
// GET /:id — one deposit
// ---------------------------------------------------------------------------
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const row = await req.asyncDb.get<Row>('SELECT * FROM deposits WHERE id = ?', id);
  if (!row) throw new AppError('Deposit not found', 404);

  res.json({ success: true, data: row });
}));

// ---------------------------------------------------------------------------
// POST / — collect a new deposit
// Body: { customer_id, ticket_id?, amount, notes? }
//
// SEC-H25: adds a `requirePermission('inventory.adjust')` middleware on top of
// the existing role check. Deposits touch inventory implicitly — trade-in
// deposits will eventually debit stock when the bench confirms the device,
// and a compromised cashier session with a custom role that strips
// `inventory.adjust` should not be able to plant deposit rows that later
// auto-apply to an invoice. The role check below is kept as defence-in-depth
// for deployments without a custom-role matrix; with a matrix, the
// permission check is authoritative (`requirePermission` handles the
// `users.role='admin'` bypass / custom-role precedence matching SEC-H18).
// ---------------------------------------------------------------------------
router.post('/', requirePermission('inventory.adjust'), asyncHandler(async (req: Request, res: Response) => {
  // SEC-M14: collecting a deposit moves money — gate to manager/admin, matching
  // the apply-to-invoice / refund handlers below.
  requireManagerOrAdmin(req);

  // Post-enrichment audit §9: per-user rate guard BEFORE validation so
  // rejected requests don't even touch the DB.
  const userKey = String(req.user?.id ?? 'anon');
  const rateResult = consumeWindowRate(
    req.db,
    DEPOSIT_CREATE_CATEGORY,
    userKey,
    DEPOSIT_CREATE_MAX,
    DEPOSIT_CREATE_WINDOW_MS,
  );
  if (!rateResult.allowed) {
    throw new AppError(
      `Too many deposits created — wait ${rateResult.retryAfterSeconds}s`,
      429,
    );
  }

  const customerId = validateIntegerQuantity(req.body?.customer_id, 'customer_id');
  // FK: customer must exist (would otherwise silently orphan the deposit).
  const cust = await req.asyncDb.get('SELECT id FROM customers WHERE id = ?', customerId);
  if (!cust) throw new AppError('Customer not found', 404);

  let ticketId: number | null = null;
  if (req.body?.ticket_id !== undefined && req.body?.ticket_id !== null) {
    ticketId = validateIntegerQuantity(req.body.ticket_id, 'ticket_id');
    const ticket = await req.asyncDb.get('SELECT id FROM tickets WHERE id = ?', ticketId);
    if (!ticket) throw new AppError('Ticket not found', 404);
  }
  const amountCents = Math.round(validatePositiveAmount(req.body?.amount) * 100);
  const notes = validateTextLength(
    typeof req.body?.notes === 'string' ? req.body.notes : undefined,
    500,
    'notes',
  );

  const result = await req.asyncDb.run(
    `INSERT INTO deposits (customer_id, ticket_id, amount_cents, collected_at, notes)
     VALUES (?, ?, ?, ?, ?)`,
    customerId,
    ticketId,
    amountCents,
    nowIso(),
    notes || null,
  );

  audit(req.db, 'deposit.collect', req.user?.id ?? null, req.ip ?? '', {
    id: result.lastInsertRowid,
    customer_id: customerId,
    amount_cents: amountCents,
  });

  logger.info('deposit collected', {
    id: result.lastInsertRowid,
    customer_id: customerId,
    cents: amountCents,
  });

  res.status(201).json({
    success: true,
    data: { id: result.lastInsertRowid, amount_cents: amountCents },
  });
}));

// ---------------------------------------------------------------------------
// POST /:id/apply-to-invoice — apply a deposit to a final invoice
// Body: { invoice_id }
// ---------------------------------------------------------------------------
router.post('/:id/apply-to-invoice', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const invoiceId = validateIntegerQuantity(req.body?.invoice_id, 'invoice_id');

  const deposit = await req.asyncDb.get<Row>(
    'SELECT id, amount_cents, applied_to_invoice_id, refunded_at FROM deposits WHERE id = ?',
    id,
  );
  if (!deposit) throw new AppError('Deposit not found', 404);
  if (deposit.applied_to_invoice_id) {
    throw new AppError('Deposit already applied to an invoice', 409);
  }
  if (deposit.refunded_at) {
    throw new AppError('Deposit has been refunded', 409);
  }

  const invoice = await req.asyncDb.get<Row>(
    'SELECT id FROM invoices WHERE id = ?',
    invoiceId,
  );
  if (!invoice) throw new AppError('Invoice not found', 404);

  const appliedAt = nowIso();
  await req.asyncDb.run(
    `UPDATE deposits
        SET applied_to_invoice_id = ?, applied_at = ?
      WHERE id = ?`,
    invoiceId,
    appliedAt,
    id,
  );

  audit(req.db, 'deposit.apply', req.user?.id ?? null, req.ip ?? '', {
    deposit_id: id,
    invoice_id: invoiceId,
    amount_cents: deposit.amount_cents,
  });

  res.json({
    success: true,
    data: {
      id,
      applied_to_invoice_id: invoiceId,
      applied_at: appliedAt,
      amount_cents: deposit.amount_cents,
    },
  });
}));

// ---------------------------------------------------------------------------
// DELETE /:id — mark deposit as refunded (soft — we keep the row for history)
// ---------------------------------------------------------------------------
router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireAdminDeposits(req);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const existing = await req.asyncDb.get<Row>(
    'SELECT id, applied_to_invoice_id, refunded_at FROM deposits WHERE id = ?',
    id,
  );
  if (!existing) throw new AppError('Deposit not found', 404);
  if (existing.refunded_at) throw new AppError('Deposit already refunded', 409);
  if (existing.applied_to_invoice_id) {
    throw new AppError('Cannot refund a deposit that has been applied to an invoice', 409);
  }

  const refundedAt = nowIso();
  await req.asyncDb.run(
    `UPDATE deposits SET refunded_at = ? WHERE id = ?`,
    refundedAt,
    id,
  );

  audit(req.db, 'deposit.refund', req.user?.id ?? null, req.ip ?? '', { id });

  res.json({ success: true, data: { id, refunded_at: refundedAt } });
}));

export default router;
