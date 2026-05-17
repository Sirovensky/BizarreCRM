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
  roundCents,
  validateTextLength,
  validateIntegerQuantity,
  validateId,
} from '../utils/validate.js';
import { parsePage, parsePageSize } from '../utils/pagination.js';
import { isBlockChypEnabled, processRefund } from '../services/blockchyp.js';

// Post-enrichment audit §9: per-user cap on deposit collection. Every POST
// inserts a money row — a fat-fingered tap-to-collect on a touchscreen POS
// could create 50 duplicate deposit rows in a few seconds. Bound it.
const DEPOSIT_CREATE_CATEGORY = 'deposit_create';
const DEPOSIT_CREATE_MAX = 20;
const DEPOSIT_CREATE_WINDOW_MS = 60_000; // 20 deposits per user per minute

const logger = createLogger('billing-enrich');
const router = Router();

type Row = Record<string, any>;

// SEC (post-enrichment audit §6): applying/deleting a deposit affects invoice
// balance. The permission middleware is authoritative; the role helper remains
// for those higher-risk endpoints where seeded non-manager roles have no grant.
function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}
function nowIso(): string {
  return new Date().toISOString();
}

function nowSql(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function dollarsFromCents(cents: number): number {
  return roundCents(Number(cents || 0) / 100);
}

function invoiceStatus(total: number, paid: number): string {
  if (paid <= 0) return 'unpaid';
  if (paid >= total) return 'paid';
  return 'partial';
}

function normalizeProcessor(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim().toLowerCase();
  return trimmed || null;
}

// ---------------------------------------------------------------------------
// GET / — list deposits, filterable by customer_id / ticket_id / applied status
// ---------------------------------------------------------------------------
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  // BUGHUNT-2026-05-16: deposits are financial records. The write endpoints
  // (POST/PATCH/DELETE) are gated by deposits.create / .apply / .delete,
  // but the list/detail reads were open to every authenticated user — a
  // technician or cashier could enumerate all customer deposits + amounts.
  // Gate behind any of the existing deposit permissions so anyone with
  // legitimate need (creators / appliers) keeps access.
  if (!(req as any).user || !((req as any).user.permissions?.['deposits.create']
      || (req as any).user.permissions?.['deposits.apply']
      || (req as any).user.permissions?.['deposits.delete']
      || (req as any).user.role === 'admin'
      || (req as any).user.role === 'manager')) {
    throw new AppError('Insufficient permission to view deposits', 403);
  }
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
  // SCAN-1125: `Number.isFinite(null)` returns false, so this branch worked
  // by accident — but it's ambiguous with "passed 0" (impossible since
  // validateId rejects that, yet the intent isn't self-evident). Switch to
  // explicit `!== null` for readability; the validator above guarantees
  // the value is a positive integer when non-null.
  if (customerId !== null) { where.push('d.customer_id = ?'); params.push(customerId); }
  if (ticketId !== null)   { where.push('d.ticket_id = ?');   params.push(ticketId); }
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
  // BUGHUNT-2026-05-16: same gate as list — restrict deposit detail reads
  // to roles that can manage deposits.
  if (!(req as any).user || !((req as any).user.permissions?.['deposits.create']
      || (req as any).user.permissions?.['deposits.apply']
      || (req as any).user.permissions?.['deposits.delete']
      || (req as any).user.role === 'admin'
      || (req as any).user.role === 'manager')) {
    throw new AppError('Insufficient permission to view deposits', 403);
  }
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
// SEC-H25: gate deposit creation behind deposits.create permission.
// ---------------------------------------------------------------------------
router.post('/', requirePermission('deposits.create'), asyncHandler(async (req: Request, res: Response) => {
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

  let linkedPayment: Row | null = null;
  if (req.body?.payment_id !== undefined && req.body?.payment_id !== null) {
    const paymentId = validateIntegerQuantity(req.body.payment_id, 'payment_id');
    linkedPayment = await req.asyncDb.get<Row>(
      `SELECT id, amount, method, processor, transaction_id, processor_transaction_id,
              processor_response, capture_state
         FROM payments
        WHERE id = ?`,
      paymentId,
    ) ?? null;
    if (!linkedPayment) throw new AppError('Payment not found', 404);

    const linkedAmountCents = Math.round(Number(linkedPayment.amount || 0) * 100);
    if (linkedAmountCents !== amountCents) {
      throw new AppError('Linked payment amount must match deposit amount', 400);
    }
    const linkedProcessor = normalizeProcessor(linkedPayment.processor)
      ?? normalizeProcessor(linkedPayment.method);
    if (linkedProcessor === 'blockchyp' && linkedPayment.capture_state !== 'captured') {
      throw new AppError('Linked BlockChyp payment must be captured before it can back a deposit', 400);
    }
  }

  const linkedProcessor = linkedPayment
    ? (normalizeProcessor(linkedPayment.processor) ?? normalizeProcessor(linkedPayment.method))
    : null;
  const linkedProcessorTransactionId = linkedPayment
    ? (linkedPayment.processor_transaction_id ?? linkedPayment.transaction_id ?? null)
    : null;
  const collectedAt = nowIso();
  const txResults = await req.asyncDb.transaction([
    {
      sql: `INSERT INTO deposits (
              customer_id, ticket_id, amount_cents, collected_at, notes,
              payment_id, processor, processor_transaction_id, processor_response
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      params: [
        customerId,
        ticketId,
        amountCents,
        collectedAt,
        notes || null,
        linkedPayment?.id ?? null,
        linkedProcessor,
        linkedProcessorTransactionId,
        linkedPayment?.processor_response ?? null,
      ],
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
    `SELECT id, customer_id, amount_cents, applied_to_invoice_id, applied_payment_id,
            refunded_at, payment_id, processor, processor_transaction_id, processor_response
       FROM deposits
      WHERE id = ?`,
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
    'SELECT id, customer_id, total, amount_paid, status FROM invoices WHERE id = ?',
    invoiceId,
  );
  if (!invoice) throw new AppError('Invoice not found', 404);
  if (invoice.status === 'void') {
    throw new AppError('Cannot apply a deposit to a voided invoice', 400);
  }
  if (invoice.customer_id != null && Number(invoice.customer_id) !== Number(deposit.customer_id)) {
    throw new AppError('Invoice does not belong to the deposit customer', 400);
  }

  const appliedAt = nowIso();
  const appliedAtSql = nowSql();
  const amount = dollarsFromCents(Number(deposit.amount_cents));
  const priorPaid = roundCents(Number(invoice.amount_paid || 0));
  const total = roundCents(Number(invoice.total || 0));
  const newPaid = roundCents(priorPaid + amount);
  const newDue = roundCents(Math.max(0, total - newPaid));
  const newStatus = invoiceStatus(total, newPaid);
  const paymentReference = `deposit-${id}`;

  // SEC-H64: atomic conditional UPDATE. TOCTOU-safe — SQLite WAL semantics
  // guarantee the WHERE clause is evaluated in the same transaction as the
  // write, so two concurrent applies cannot both claim the deposit. The
  // loser's UPDATE returns `changes === 0` and we 409 it.
  try {
    await req.asyncDb.transaction([
      {
        sql: `UPDATE deposits
                SET applied_to_invoice_id = ?, applied_at = ?
              WHERE id = ?
                AND applied_to_invoice_id IS NULL
                AND refunded_at IS NULL`,
        params: [invoiceId, appliedAt, id],
        expectChanges: true,
        expectChangesError: 'Deposit already applied or refunded',
      },
      {
        sql: `INSERT INTO payments (
                invoice_id, amount, method, method_detail, transaction_id, notes,
                payment_type, processor, reference, processor_transaction_id,
                processor_response, capture_state, user_id, created_at, updated_at
              )
              VALUES (?, ?, 'deposit', 'Applied deposit', ?, ?, 'deposit', ?, ?, ?, ?, 'captured', ?, ?, ?)`,
        params: [
          invoiceId,
          amount,
          deposit.processor_transaction_id ?? null,
          `Applied deposit #${id}`,
          deposit.processor ?? null,
          paymentReference,
          deposit.processor_transaction_id ?? null,
          deposit.processor_response ?? null,
          req.user!.id,
          appliedAtSql,
          appliedAtSql,
        ],
      },
      {
        sql: `UPDATE deposits
                SET applied_payment_id = (
                  SELECT id
                    FROM payments
                   WHERE invoice_id = ? AND reference = ?
                   ORDER BY id DESC
                   LIMIT 1
                )
              WHERE id = ? AND applied_payment_id IS NULL`,
        params: [invoiceId, paymentReference, id],
        expectChanges: true,
        expectChangesError: 'Deposit application payment link failed',
      },
      {
        sql: `UPDATE invoices
                SET amount_paid = ?,
                    amount_due = ?,
                    status = ?,
                    updated_at = ?
              WHERE id = ?`,
        params: [newPaid, newDue, newStatus, appliedAtSql, invoiceId],
      },
    ]);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('already applied') || message.includes('payment link failed')) {
      throw new AppError(message, 409);
    }
    throw err;
  }

  const appliedPayment = await req.asyncDb.get<{ id: number }>(
    'SELECT id FROM payments WHERE invoice_id = ? AND reference = ? ORDER BY id DESC LIMIT 1',
    invoiceId,
    paymentReference,
  );
  if (!appliedPayment) {
    throw new AppError('Deposit applied but payment link could not be loaded', 500);
  }

  audit(req.db, 'deposit.apply', req.user?.id ?? null, req.ip ?? '', {
    deposit_id: id,
    invoice_id: invoiceId,
    amount_cents: deposit.amount_cents,
    payment_id: appliedPayment.id,
  });

  res.json({
    success: true,
    data: {
      id,
      applied_to_invoice_id: invoiceId,
      applied_payment_id: appliedPayment.id,
      applied_at: appliedAt,
      amount_cents: deposit.amount_cents,
    },
  });
}));

// ---------------------------------------------------------------------------
// DELETE /:id — mark deposit as refunded (soft — we keep the row for history)
// SEC-H25: refunding a deposit is a financial reversal — gate behind deposits.delete.
// ---------------------------------------------------------------------------
router.delete('/:id', requirePermission('deposits.delete'), asyncHandler(async (req: Request, res: Response) => {
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  // SEC-H64 (C3-006): same pattern as apply-to-invoice above. Pre-check for
  // clean 404 on unknown id, then rely on the conditional UPDATE to serialize
  // concurrent refund attempts.
  const existing = await req.asyncDb.get<Row>(
    `SELECT d.id, d.amount_cents, d.applied_to_invoice_id, d.refunded_at,
            d.refund_pending_at, d.payment_id, d.processor, d.processor_transaction_id,
            p.method AS payment_method,
            p.processor AS payment_processor,
            p.transaction_id AS payment_transaction_id,
            p.processor_transaction_id AS payment_processor_transaction_id,
            p.capture_state AS payment_capture_state
       FROM deposits d
       LEFT JOIN payments p ON p.id = d.payment_id
      WHERE d.id = ?`,
    id,
  );
  if (!existing) throw new AppError('Deposit not found', 404);
  if (existing.refunded_at) throw new AppError('Deposit already refunded', 409);
  if (existing.refund_pending_at) throw new AppError('Deposit refund is already in progress', 409);
  if (existing.applied_to_invoice_id) {
    throw new AppError('Cannot refund a deposit that has been applied to an invoice', 409);
  }

  const refundedAt = nowIso();
  const pendingAt = nowSql();
  const amount = dollarsFromCents(Number(existing.amount_cents));
  const processor = normalizeProcessor(existing.processor)
    ?? normalizeProcessor(existing.payment_processor)
    ?? normalizeProcessor(existing.payment_method);
  const originalTransactionId = existing.processor_transaction_id
    ?? existing.payment_processor_transaction_id
    ?? existing.payment_transaction_id
    ?? null;

  // SEC-H64: atomic conditional UPDATE. If a concurrent apply-to-invoice or
  // duplicate refund snuck in between the SELECT above and this UPDATE, the
  // WHERE guard rejects the second writer with `changes === 0`.
  const claimResult = await req.asyncDb.run(
    `UPDATE deposits
        SET refund_pending_at = ?,
            refund_error = NULL
      WHERE id = ?
        AND refunded_at IS NULL
        AND applied_to_invoice_id IS NULL
        AND refund_pending_at IS NULL`,
    pendingAt,
    id,
  );
  if (claimResult.changes === 0) {
    throw new AppError('Deposit already applied or refunded', 409);
  }

  let processorRefund: Awaited<ReturnType<typeof processRefund>> | null = null;
  if (processor === 'blockchyp') {
    if (!isBlockChypEnabled(req.db)) {
      await req.asyncDb.run(
        `UPDATE deposits
            SET refund_pending_at = NULL,
                refund_error = ?
          WHERE id = ?`,
        'BlockChyp terminal is not enabled',
        id,
      );
      throw new AppError('BlockChyp terminal is not enabled', 400);
    }
    if (!originalTransactionId) {
      await req.asyncDb.run(
        `UPDATE deposits
            SET refund_pending_at = NULL,
                refund_error = ?
          WHERE id = ?`,
        'Missing originating BlockChyp transaction id',
        id,
      );
      throw new AppError('Missing originating BlockChyp transaction id for deposit refund', 400);
    }
    if (existing.payment_capture_state && existing.payment_capture_state !== 'captured') {
      await req.asyncDb.run(
        `UPDATE deposits
            SET refund_pending_at = NULL,
                refund_error = ?
          WHERE id = ?`,
        `Linked payment is not captured (${existing.payment_capture_state})`,
        id,
      );
      throw new AppError('Linked payment is not captured; cannot refund through BlockChyp', 400);
    }

    processorRefund = await processRefund(req.db, amount, originalTransactionId, `deposit-${id}`);
    if (!processorRefund.success) {
      await req.asyncDb.run(
        `UPDATE deposits
            SET refund_pending_at = NULL,
                refund_error = ?,
                processor_response = COALESCE(?, processor_response)
          WHERE id = ?`,
        processorRefund.error ?? 'BlockChyp refund failed',
        processorRefund.receiptSuggestions ? JSON.stringify(processorRefund.receiptSuggestions) : null,
        id,
      );
      audit(req.db, 'deposit.blockchyp_refund_failed', req.user?.id ?? null, req.ip ?? '', {
        id,
        amount_cents: existing.amount_cents,
        original_transaction_id: originalTransactionId,
        transaction_ref: processorRefund.transactionRef,
        error: processorRefund.error,
      });
      throw new AppError(processorRefund.error || 'BlockChyp refund failed', 400);
    }
  }

  const finalizeResult = await req.asyncDb.run(
    `UPDATE deposits
        SET refunded_at = ?,
            refunded_by_user_id = ?,
            refund_pending_at = NULL,
            refund_error = NULL,
            processor = COALESCE(?, processor),
            processor_refund_transaction_id = ?,
            processor_response = COALESCE(?, processor_response),
            refund_signature_file = ?,
            refund_signature_file_path = ?,
            accepted_terms_name = ?,
            accepted_terms_text = ?,
            accepted_terms_hash = ?,
            accepted_terms_accepted_at = ?
      WHERE id = ?
        AND refunded_at IS NULL`,
    refundedAt,
    req.user!.id,
    processorRefund ? 'blockchyp' : processor,
    processorRefund?.transactionId ?? null,
    processorRefund?.receiptSuggestions ? JSON.stringify(processorRefund.receiptSuggestions) : null,
    processorRefund?.signatureFile ?? null,
    processorRefund?.signatureFilePath ?? null,
    processorRefund?.acceptedTerms?.name ?? null,
    processorRefund?.acceptedTerms?.content ?? null,
    processorRefund?.acceptedTerms?.contentHash ?? null,
    processorRefund?.acceptedTerms?.acceptedAt ?? null,
    id,
  );
  if (finalizeResult.changes === 0) {
    throw new AppError('Deposit already refunded', 409);
  }

  audit(req.db, 'deposit.refund', req.user?.id ?? null, req.ip ?? '', {
    id,
    amount_cents: existing.amount_cents,
    processor: processorRefund ? 'blockchyp' : processor,
    processor_transaction_id: processorRefund?.transactionId ?? undefined,
  });

  res.json({
    success: true,
    data: {
      id,
      refunded_at: refundedAt,
      processor: processorRefund ? 'blockchyp' : processor,
      processor_transaction_id: processorRefund?.transactionId ?? null,
    },
  });
}));

export default router;
