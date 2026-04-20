import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requirePermission } from '../middleware/auth.js';
import { idempotent } from '../middleware/idempotency.js';
import { audit } from '../utils/audit.js';
import { validatePositiveAmount, validateEnum, roundCents, validatePaginationOffset } from '../utils/validate.js';
import type { AsyncDb, TxQuery } from '../db/async-db.js';
// @audit-fixed: payroll-period lock now enforced inside reverseCommission().
import { reverseCommission } from '../utils/commissions.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';

const router = Router();

const REFUND_TYPES = ['refund', 'store_credit', 'credit_note'] as const;
type RefundType = typeof REFUND_TYPES[number];

// Payment methods that represent external card processors (BlockChyp / Stripe).
// Refunds originated against a card invoice cannot exceed the card amount received.
const CARD_METHODS = new Set(['card', 'credit', 'debit', 'blockchyp', 'stripe']);

function isCardMethod(method: string | null | undefined): boolean {
  if (!method) return false;
  return CARD_METHODS.has(method.toLowerCase());
}

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

interface InvoiceRow {
  id: number;
  customer_id: number | null;
  total: number;
  amount_paid: number;
}

interface RefundRow {
  id: number;
  invoice_id: number | null;
  ticket_id: number | null;
  customer_id: number;
  amount: number;
  type: RefundType;
  reason: string | null;
  method: string | null;
  status: string;
}

interface StoreCreditRow {
  id: number;
  amount: number;
}

// GET / — List refunds
router.get('/', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset = validatePaginationOffset((page - 1) * pageSize, 'offset');

  const [countRow, refunds] = await Promise.all([
    adb.get<{ c: number }>('SELECT COUNT(*) as c FROM refunds'),
    adb.all(`
      SELECT r.*, c.first_name, c.last_name, i.order_id AS invoice_order_id,
             u.first_name AS created_first, u.last_name AS created_last
      FROM refunds r
      LEFT JOIN customers c ON c.id = r.customer_id
      LEFT JOIN invoices i ON i.id = r.invoice_id
      LEFT JOIN users u ON u.id = r.created_by
      ORDER BY r.created_at DESC LIMIT ? OFFSET ?
    `, pageSize, offset),
  ]);
  const total = countRow!.c;

  res.json({ success: true, data: { refunds, pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) } } });
}));

// POST / — Create refund
// M1: cap refund amount against invoice.amount_paid - previously_refunded, and
// if the original payment was by card, cap at the card-collected amount too.
// SEC-H29: role gate (admin/manager) + idempotent middleware. A double-click
// or retry used to insert two pending refund rows against the same invoice;
// the idempotent middleware now short-circuits the second submit. Role gate
// ensures a cashier-tier user cannot queue a bogus refund for a manager to
// rubber-stamp.
// SEC-H25: gate behind refunds.create permission. The inline role check below
// is kept as defence-in-depth.
router.post('/', idempotent, requirePermission('refunds.create'), asyncHandler(async (req, res) => {
  // Defence-in-depth: requirePermission above is authoritative.
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required to create refunds', 403);
  }

  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const { invoice_id, ticket_id, customer_id, reason, method } = req.body;
  const type = validateEnum(req.body.type ?? 'refund', REFUND_TYPES, 'type') as RefundType;
  const amount = validatePositiveAmount(req.body.amount, 'amount');
  if (!customer_id) throw new AppError('customer_id required', 400);

  // M1: Validate the refund amount against invoice caps when an invoice is attached.
  if (invoice_id) {
    const inv = await adb.get<InvoiceRow>(
      'SELECT id, customer_id, total, amount_paid FROM invoices WHERE id = ?',
      invoice_id,
    );
    if (!inv) throw new AppError('Invoice not found', 404);
    // Customer must match — blocks attaching a refund to another customer's invoice.
    if (inv.customer_id != null && Number(inv.customer_id) !== Number(customer_id)) {
      throw new AppError('Invoice does not belong to this customer', 400);
    }

    // SEC-M44: block refund when ANY payment on this invoice isn't fully
    // captured. An auth-only payment hasn't actually moved money — refunding
    // it would credit the customer funds the shop never collected. Voided
    // payments also have nothing to refund. If even one payment row on the
    // invoice is non-captured, require the operator to reconcile it first.
    // Uses COALESCE on capture_state so pre-migration rows (if any survived)
    // still behave as 'captured'.
    const nonCapturedRow = await adb.get<{ count: number; states: string | null }>(
      `SELECT COUNT(*) AS count,
              GROUP_CONCAT(DISTINCT COALESCE(capture_state, 'captured')) AS states
         FROM payments
        WHERE invoice_id = ?
          AND COALESCE(capture_state, 'captured') != 'captured'`,
      invoice_id,
    );
    if (nonCapturedRow && nonCapturedRow.count > 0) {
      throw new AppError(
        `Cannot refund — ${nonCapturedRow.count} payment(s) on this invoice are not captured (state: ${nonCapturedRow.states}). Capture or void the authorization first.`,
        400,
      );
    }

    // Sum of already-processed refunds against this invoice (approved/completed only).
    const refundedAgg = await adb.get<{ total: number | null }>(
      `SELECT COALESCE(SUM(amount), 0) AS total
         FROM refunds
        WHERE invoice_id = ?
          AND status IN ('approved', 'completed')`,
      invoice_id,
    );
    const alreadyRefunded = roundCents(refundedAgg?.total ?? 0);
    const available = roundCents((inv.amount_paid ?? 0) - alreadyRefunded);
    if (available <= 0) {
      throw new AppError('Invoice has already been fully refunded', 400);
    }
    if (amount > available + 0.004) {
      throw new AppError(
        `Refund exceeds available balance. Maximum refundable: ${available.toFixed(2)}`,
        400,
      );
    }

    // M1: If the original payment(s) were card-based, the refund cannot exceed the
    // total amount actually collected on card payments for this invoice.
    if (method && isCardMethod(method)) {
      const cardAgg = await adb.get<{ total: number | null }>(
        `SELECT COALESCE(SUM(amount), 0) AS total
           FROM payments
          WHERE invoice_id = ?
            AND LOWER(method) IN ('card','credit','debit','blockchyp','stripe')`,
        invoice_id,
      );
      const cardRefundedAgg = await adb.get<{ total: number | null }>(
        `SELECT COALESCE(SUM(amount), 0) AS total
           FROM refunds
          WHERE invoice_id = ?
            AND status IN ('approved', 'completed')
            AND LOWER(COALESCE(method, '')) IN ('card','credit','debit','blockchyp','stripe')`,
        invoice_id,
      );
      const cardCollected = roundCents(cardAgg?.total ?? 0);
      const cardAlreadyRefunded = roundCents(cardRefundedAgg?.total ?? 0);
      const cardAvailable = roundCents(cardCollected - cardAlreadyRefunded);
      if (amount > cardAvailable + 0.004) {
        throw new AppError(
          `Card refund exceeds card amount collected. Maximum refundable on card: ${cardAvailable.toFixed(2)}`,
          400,
        );
      }
    }
  }

  const result = await adb.run(`
    INSERT INTO refunds (invoice_id, ticket_id, customer_id, amount, type, reason, method, status, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
  `, invoice_id || null, ticket_id || null, customer_id, amount, type, reason || null, method || null, req.user!.id, now(), now());

  const refundId = Number(result.lastInsertRowid);
  audit(db, 'refund_created', req.user!.id, req.ip || 'unknown', { refund_id: refundId, amount, type, invoice_id: invoice_id || null, method: method || null });

  res.status(201).json({ success: true, data: { id: refundId } });
}));

// PATCH /:id/approve — Approve refund (admin only)
// SC1: Replace SQLite MAX(0, ...) scalar inside UPDATE SET with a safe two-step
//      SELECT-then-UPDATE. Even though sqlite supports MAX() as a variadic scalar
//      we avoid version/parser flakiness by computing the clamped value in JS.
// EM1: On completion, reverse proportional commissions for the original invoice.
// SEC-H28: The refund status flip + invoice amount_paid decrement now runs
//      inside a single atomic transaction with `WHERE status='pending'` guarding
//      the refund UPDATE. This blocks the double-approve race: two concurrent
//      admins used to both pass the precheck, then both fire UPDATEs, causing
//      the invoice to be decremented twice.
// SEC-H25: gate behind refunds.approve permission. The inline role check below
// is kept as defence-in-depth.
router.patch('/:id/approve', requirePermission('refunds.approve'), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  // Defence-in-depth: requirePermission above is authoritative.
  if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid refund id', 400);

  const refund = await adb.get<RefundRow>('SELECT * FROM refunds WHERE id = ?', id);
  if (!refund) throw new AppError('Refund not found', 404);
  if (refund.status !== 'pending') throw new AppError('Refund is not pending', 400);

  // Snapshot invoice totals up-front so we can compute the new balance in JS
  // (SEC-H28: within a transaction we cannot interleave SELECTs, so the
  // snapshot + compute happens here and the UPDATE enforces the prior-status
  // guard atomically).
  let invoiceUpdate: TxQuery | null = null;
  if (refund.invoice_id) {
    const inv = await adb.get<InvoiceRow>(
      'SELECT id, total, amount_paid FROM invoices WHERE id = ?',
      refund.invoice_id,
    );
    if (inv) {
      const newPaid = roundCents(Math.max(0, (inv.amount_paid ?? 0) - refund.amount));
      const newDue = roundCents(Math.max(0, (inv.total ?? 0) - newPaid));
      const newStatus = newPaid <= 0 ? 'unpaid' : newPaid >= (inv.total ?? 0) ? 'paid' : 'partial';
      invoiceUpdate = {
        // Prior-status guard on amount_paid UPDATE: only decrement when the row
        // still matches the snapshot we just read. If another refund beat us to
        // it, the UPDATE matches zero rows and expectChanges rolls the tx back.
        sql: 'UPDATE invoices SET amount_paid = ?, amount_due = ?, status = ?, updated_at = ? WHERE id = ? AND amount_paid = ?',
        params: [newPaid, newDue, newStatus, now(), refund.invoice_id, inv.amount_paid ?? 0],
        expectChanges: true,
        expectChangesError: 'Invoice balance changed concurrently; refund not applied',
      };
    }
  }

  // SEC-H28: atomic status flip + invoice decrement. `WHERE status='pending'`
  // on the refunds UPDATE + expectChanges forces the whole tx to roll back if
  // another admin already flipped the refund to 'completed'.
  const tx: TxQuery[] = [
    {
      sql: "UPDATE refunds SET status = ?, approved_by = ?, updated_at = ? WHERE id = ? AND status = 'pending'",
      params: ['completed', req.user!.id, now(), id],
      expectChanges: true,
      expectChangesError: 'Refund is no longer pending',
    },
  ];
  if (invoiceUpdate) tx.push(invoiceUpdate);
  try {
    await adb.transaction(tx);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('no longer pending') || msg.includes('balance changed concurrently')) {
      throw new AppError(msg, 409);
    }
    throw err;
  }

  // Post-transaction hooks — commission reversal + store credit are best-effort
  // and intentionally outside the tx so a downstream failure does not roll back
  // the approved refund. (They still log their own audit entries.)
  if (refund.invoice_id) {
    const inv = await adb.get<InvoiceRow>(
      'SELECT id, total, amount_paid FROM invoices WHERE id = ?',
      refund.invoice_id,
    );
    if (inv) {
      // EM1 / @audit-fixed: Audit #3 — delegate reversal to the shared
      // `reverseCommission` helper in utils/commissions.ts. Same proportional
      // behavior and payroll-lock check, but now refunds + any future
      // cancel/void path share one implementation.
      const totalInvoice = inv.total ?? 0;
      const refundFraction = totalInvoice > 0
        ? Math.min(1, refund.amount / totalInvoice)
        : 1;
      const reversedCount = await reverseCommission(adb, {
        sourceType: 'invoice',
        sourceId: refund.invoice_id,
        fraction: refundFraction,
        at: now(),
      });
      if (reversedCount > 0) {
        audit(db, 'commissions_reversed', req.user!.id, req.ip || 'unknown', {
          refund_id: id,
          invoice_id: refund.invoice_id,
          reversal_fraction: refundFraction,
          commission_rows_reversed: reversedCount,
        });
      }
    }
  }

  // If type is store_credit, add to customer's credit balance.
  // SEC-H67: single atomic UPSERT — the UNIQUE index on customer_id (migration
  // 109) + ON CONFLICT DO UPDATE guarantee one row per customer even under
  // concurrent writers. No preceding SELECT needed.
  if (refund.type === 'store_credit') {
    await adb.run(
      `INSERT INTO store_credits (customer_id, amount, created_at, updated_at)
       VALUES (?, ?, datetime('now'), datetime('now'))
       ON CONFLICT(customer_id) DO UPDATE SET
         amount     = amount + excluded.amount,
         updated_at = datetime('now')`,
      refund.customer_id, refund.amount,
    );
    await adb.run(`
      INSERT INTO store_credit_transactions (customer_id, amount, type, reference_type, reference_id, notes, user_id, created_at)
      VALUES (?, ?, 'refund_credit', 'refund', ?, ?, ?, ?)
    `, refund.customer_id, refund.amount, id, refund.reason || 'Refund to store credit', req.user!.id, now());
  }

  audit(db, 'refund_approved', req.user!.id, req.ip || 'unknown', {
    refund_id: id,
    amount: refund.amount,
    type: refund.type,
    invoice_id: refund.invoice_id,
  });
  res.json({ success: true, data: { id } });
}));

// PATCH /:id/decline — Decline refund
// SEC-H25: declining a refund requires admin-tier access — gate behind
// refunds.approve (same elevated permission as approve). The inline role check
// below is kept as defence-in-depth.
router.patch('/:id/decline', requirePermission('refunds.approve'), asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  // Defence-in-depth: requirePermission above is authoritative.
  if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid refund id', 400);

  const result = await adb.run(
    "UPDATE refunds SET status = ?, updated_at = ? WHERE id = ? AND status = 'pending'",
    'declined', now(), id,
  );
  if (result.changes === 0) throw new AppError('Refund not found or not pending', 404);
  audit(req.db, 'refund_declined', req.user!.id, req.ip || 'unknown', { refund_id: id });
  res.json({ success: true, data: { id } });
}));

// GET /credits/:customerId — Get customer store credit balance + history
// Tenant isolation: req.asyncDb is already scoped to the active tenant DB — SC2 verified.
router.get('/credits/:customerId', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const customerId = parseInt(req.params.customerId as string, 10);
  if (!Number.isFinite(customerId) || customerId <= 0) {
    throw new AppError('Invalid customer id', 400);
  }

  const [credit, transactions] = await Promise.all([
    adb.get<StoreCreditRow>('SELECT id, amount FROM store_credits WHERE customer_id = ?', customerId),
    adb.all(
      'SELECT * FROM store_credit_transactions WHERE customer_id = ? ORDER BY created_at DESC LIMIT 50',
      customerId,
    ),
  ]);
  res.json({ success: true, data: { balance: credit?.amount || 0, transactions } });
}));

// POST /credits/:customerId/use — Use store credit on invoice
// SC3: Guarded UPDATE prevents parallel double-spend.
// SC9: Re-read balance AFTER commit.
// SC10: Validate invoice_id exists and belongs to the customer before linking.
// SEC-H25: using store credit is a financial write — gate behind
// invoices.record_payment (store credit is applied like a payment).
router.post('/credits/:customerId/use', requirePermission('invoices.record_payment'), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const customerId = parseInt(req.params.customerId as string, 10);
  if (!Number.isFinite(customerId) || customerId <= 0) {
    throw new AppError('Invalid customer id', 400);
  }

  const amount = validatePositiveAmount(req.body.amount, 'amount');
  const invoiceIdRaw = req.body.invoice_id;
  let invoiceId: number | null = null;
  if (invoiceIdRaw !== undefined && invoiceIdRaw !== null && invoiceIdRaw !== '') {
    invoiceId = Number(invoiceIdRaw);
    if (!Number.isInteger(invoiceId) || invoiceId <= 0) {
      throw new AppError('invoice_id must be a positive integer', 400);
    }
    // SC10: Verify invoice exists AND belongs to this customer.
    const inv = await adb.get<{ id: number; customer_id: number | null }>(
      'SELECT id, customer_id FROM invoices WHERE id = ?',
      invoiceId,
    );
    if (!inv) throw new AppError('Invoice not found', 404);
    if (inv.customer_id != null && Number(inv.customer_id) !== customerId) {
      throw new AppError('Invoice does not belong to this customer', 400);
    }
  }

  // SC3: Guarded atomic decrement — only succeeds if sufficient credit exists.
  // Prevents two parallel requests from both passing a naive SELECT-then-UPDATE check.
  const credit = await adb.get<StoreCreditRow>(
    'SELECT id, amount FROM store_credits WHERE customer_id = ?',
    customerId,
  );
  if (!credit) throw new AppError('Insufficient store credit', 400);

  const dec = await adb.run(
    'UPDATE store_credits SET amount = amount - ?, updated_at = ? WHERE id = ? AND amount >= ?',
    amount, now(), credit.id, amount,
  );
  if (dec.changes === 0) {
    throw new AppError('Insufficient store credit', 409);
  }

  await adb.run(`
    INSERT INTO store_credit_transactions (customer_id, amount, type, reference_type, reference_id, notes, user_id, created_at)
    VALUES (?, ?, 'usage', 'invoice', ?, 'Store credit applied', ?, ?)
  `, customerId, -amount, invoiceId, req.user!.id, now());

  // SC9: Re-read the committed balance instead of returning a computed stale value.
  const latest = await adb.get<StoreCreditRow>(
    'SELECT amount FROM store_credits WHERE id = ?',
    credit.id,
  );
  const newBalance = roundCents(latest?.amount ?? 0);

  audit(db, 'store_credit_used', req.user!.id, req.ip || 'unknown', {
    customer_id: customerId,
    amount,
    invoice_id: invoiceId,
    new_balance: newBalance,
  });

  res.json({ success: true, data: { new_balance: newBalance } });
}));

export default router;
