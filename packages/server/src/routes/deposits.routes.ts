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
  validateId,
} from '../utils/validate.js';
import { parsePage, parsePageSize } from '../utils/pagination.js';

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
  const customerIdRaw = req.query.customer_id;
  const ticketIdRaw = req.query.ticket_id;

  let customerId: number | null = null;
  let ticketId: number | null = null;

  if (customerIdRaw !== undefined && customerIdRaw !== '') {
    customerId = validateId(customerIdRaw, 'customer_id');
  }
  if (ticketIdRaw !== undefined && ticketIdRaw !== '') {
    ticketId = validateId(ticketIdRaw, 'ticket_id');
  }
  const applied = req.query.applied as string | undefined;

  // SCAN-1047: replace hard LIMIT 500 with proper pagination. Legacy clients
  // that just want "everything" still get page 1 (50 rows by default);
  // completeness-assuming clients can walk pages via `page`/`pagesize`.
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize ?? req.query.page_size, 50);
  const offset = (page - 1) * pageSize;

  const where: string[] = [];
  const params: any[] = [];
  if (Number.isFinite(customerId)) { where.push('d.customer_id = ?'); params.push(customerId); }
  if (Number.isFinite(ticketId))   { where.push('d.ticket_id = ?');   params.push(ticketId); }
  if (applied === 'unapplied')     { where.push('d.applied_to_invoice_id IS NULL AND d.refunded_at IS NULL'); }
  if (applied === 'applied')       { where.push('d.applied_to_invoice_id IS NOT NULL'); }

  const whereClause = where.length ? 'WHERE ' + where.join(' AND ') : '';

  const [totalRow, rows] = await Promise.all([
    req.asyncDb.get<{ c: number }>(
      `SELECT COUNT(*) AS c FROM deposits d ${whereClause}`,
      ...params,
    ),
    req.asyncDb.all<Row>(
      `SELECT d.*, c.first_name, c.last_name
         FROM deposits d
         LEFT JOIN customers c ON c.id = d.customer_id
         ${whereClause}
         ORDER BY d.id DESC
         LIMIT ? OFFSET ?`,
      ...params, pageSize, offset,
    ),
  ]);

  const total = totalRow?.c ?? 0;
  res.json({
    success: true,
    data: rows,
    meta: {
      pagination: {
        page,
        per_page: pageSize,
        total,
        total_pages: Math.max(1, Math.ceil(total / pageSize)),
      },
    },
  });
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
// SEC-H25: gate deposit creation behind deposits.create permission. The
// requireManagerOrAdmin() call below is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.post('/', requirePermission('deposits.create'), asyncHandler(async (req: Request, res: Response) => {
  // Defence-in-depth: requirePermission above is authoritative.
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

  const collectedAt = nowIso();
  const txResults = await req.asyncDb.transaction([
    {
      sql: `INSERT INTO deposits (customer_id, ticket_id, amount_cents, collected_at, notes)
            VALUES (?, ?, ?, ?, ?)`,
      params: [customerId, ticketId, amountCents, collectedAt, notes || null],
    },
  ]);
  const result = txResults[0];

  // Audit fire-and-forget after tx commits — audit failure must not roll back
  // a successfully collected deposit.
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
// SEC-H25: applying a deposit affects invoice balance — gate behind deposits.apply.
// The inline requireManagerOrAdmin() call below is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.post('/:id/apply-to-invoice', requirePermission('deposits.apply'), asyncHandler(async (req: Request, res: Response) => {
  // Defence-in-depth: requirePermission above is authoritative.
  requireManagerOrAdmin(req);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const invoiceId = validateIntegerQuantity(req.body?.invoice_id, 'invoice_id');

  // SEC-H64 (C3-005): we still fetch the deposit first so we can (a) return a
  // clean 404 if the id is wrong (vs the ambiguous 409 an atomic UPDATE would
  // emit) and (b) capture `amount_cents` for audit + response. The real
  // race-safety comes from the conditional UPDATE below — two concurrent
  // apply-to-invoice requests that both pass this pre-check will fight over
  // the WHERE clause and only one will see `changes === 1`.
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
  // SEC-H64: atomic conditional UPDATE. TOCTOU-safe — SQLite WAL semantics
  // guarantee the WHERE clause is evaluated in the same transaction as the
  // write, so two concurrent applies cannot both claim the deposit. The
  // loser's UPDATE returns `changes === 0` and we 409 it.
  const updateResult = await req.asyncDb.run(
    `UPDATE deposits
        SET applied_to_invoice_id = ?, applied_at = ?
      WHERE id = ?
        AND applied_to_invoice_id IS NULL
        AND refunded_at IS NULL`,
    invoiceId,
    appliedAt,
    id,
  );
  if (updateResult.changes === 0) {
    throw new AppError('Deposit already applied or refunded', 409);
  }

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
// SEC-H25: refunding a deposit is a financial reversal — gate behind deposits.delete.
// The inline requireAdminDeposits() call below is kept as defence-in-depth.
// ---------------------------------------------------------------------------
router.delete('/:id', requirePermission('deposits.delete'), asyncHandler(async (req: Request, res: Response) => {
  // Defence-in-depth: requirePermission above is authoritative.
  requireAdminDeposits(req);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  // SEC-H64 (C3-006): same pattern as apply-to-invoice above. Pre-check for
  // clean 404 on unknown id, then rely on the conditional UPDATE to serialize
  // concurrent refund attempts.
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
  // SEC-H64: atomic conditional UPDATE. If a concurrent apply-to-invoice or
  // duplicate refund snuck in between the SELECT above and this UPDATE, the
  // WHERE guard rejects the second writer with `changes === 0`.
  const updateResult = await req.asyncDb.run(
    `UPDATE deposits
        SET refunded_at = ?
      WHERE id = ?
        AND refunded_at IS NULL
        AND applied_to_invoice_id IS NULL`,
    refundedAt,
    id,
  );
  if (updateResult.changes === 0) {
    throw new AppError('Deposit already applied or refunded', 409);
  }

  audit(req.db, 'deposit.refund', req.user?.id ?? null, req.ip ?? '', { id });

  res.json({ success: true, data: { id, refunded_at: refundedAt } });
}));

export default router;
