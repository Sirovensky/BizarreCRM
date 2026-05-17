/**
 * Installment Plans routes — WEB-W2-002
 * Mounted at /api/v1/installments with authMiddleware.
 * Response shape: `{ success: true, data: X }`.
 *
 * Tables: installment_plans, installment_schedule (migration 095_billing_enrichment.sql)
 *
 * Endpoints:
 *   POST /                   — create plan + schedule rows
 *   GET  /                   — list plans (optionally filter by customer_id or invoice_id)
 *   GET  /:id                — plan detail with schedule rows
 *   POST /:id/cancel         — cancel a pending/active plan
 */
import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import { lastInsertRowidFrom } from '../db/async-db.js';
import type { TxQuery } from '../db/async-db.js';

const logger = createLogger('installments');
const router = Router();

// ─── Rate limit: 20 plan creates per user per minute ─────────────────────────
const RL_CREATE_MAX = 20;
const RL_CREATE_WINDOW = 60_000;

// ─── Helpers ──────────────────────────────────────────────────────────────────

function parseId(raw: unknown, field = 'id'): number {
  const n = parseInt(String(raw ?? ''), 10);
  if (!Number.isInteger(n) || n < 1) throw new AppError(`${field} must be a positive integer`, 400);
  return n;
}

// ─── POST / — create installment plan + schedule ─────────────────────────────

router.post('/', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;

  // SEC: gate plan creation to manager/admin. Matches the cancel endpoint
  // and prevents a cashier/technician from minting arbitrary-value plans
  // (which become enforceable payment schedules).
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
    throw new AppError('Admin or manager role required to create a plan', 403);
  }

  // Rate limit
  const rlResult = consumeWindowRate(db, 'installment_create', String(req.user!.id), RL_CREATE_MAX, RL_CREATE_WINDOW);
  if (!rlResult.allowed) {
    throw new AppError('Too many plan creates — please slow down', 429);
  }

  const {
    customer_id,
    invoice_id = null,
    total_cents,
    installment_count,
    frequency_days,
    acceptance_token,
    acceptance_signed_at,
    schedule,
  } = req.body ?? {};

  // ── Validate inputs ────────────────────────────────────────────────────────
  if (!Number.isInteger(customer_id) || customer_id < 1) {
    throw new AppError('customer_id must be a positive integer', 400);
  }
  if (!Number.isInteger(total_cents) || total_cents < 1) {
    throw new AppError('total_cents must be a positive integer', 400);
  }
  if (!Number.isInteger(installment_count) || installment_count < 2 || installment_count > 120) {
    throw new AppError('installment_count must be between 2 and 120', 400);
  }
  if (!Number.isInteger(frequency_days) || frequency_days < 1 || frequency_days > 365) {
    throw new AppError('frequency_days must be between 1 and 365', 400);
  }
  if (typeof acceptance_token !== 'string' || acceptance_token.trim().length < 3) {
    throw new AppError('acceptance_token (customer name) is required (min 3 chars)', 400);
  }
  if (typeof acceptance_signed_at !== 'string' || !acceptance_signed_at) {
    throw new AppError('acceptance_signed_at is required', 400);
  }
  if (!Array.isArray(schedule) || schedule.length !== installment_count) {
    throw new AppError(`schedule must be an array of exactly ${installment_count} rows`, 400);
  }

  // Verify schedule rows sum to total_cents
  const scheduleSum = schedule.reduce((acc: number, row: any) => acc + (Number(row.amount_cents) || 0), 0);
  if (scheduleSum !== total_cents) {
    throw new AppError(
      `schedule amounts sum to ${scheduleSum} but total_cents is ${total_cents}. They must match exactly.`,
      400,
    );
  }

  // FK checks
  // BUGHUNT-2026-05-17: include is_deleted = 0 so a soft-deleted customer
  // can't have a new installment plan attached (which the auto-charge cron
  // would then keep billing forever). The whole plan + schedule write is
  // already inside an adb.transaction so a /DELETE landing between this
  // SELECT and the tx commit would still produce a stale plan; the tx
  // could be tightened with a WHERE EXISTS subquery on the plan INSERT
  // but that requires more refactoring — flag here for follow-up.
  const customerExists = await adb.get<{ id: number }>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customer_id);
  if (!customerExists) throw new AppError('Customer not found', 404);

  let invoiceIdClean: number | null = null;
  if (invoice_id !== null && invoice_id !== undefined) {
    invoiceIdClean = parseId(invoice_id, 'invoice_id');
    const invExists = await adb.get<{ id: number; amount_due: number }>(
      'SELECT id, amount_due FROM invoices WHERE id = ?',
      invoiceIdClean,
    );
    if (!invExists) throw new AppError('Invoice not found', 404);
    // SEC: server-authoritative check that the plan's total doesn't exceed
    // the invoice's outstanding balance. Without this a low-privilege user
    // could submit total_cents=1 (or 999999) and the schedule sum check
    // alone wouldn't catch the invoice mismatch.
    const dueCents = Math.round(Number(invExists.amount_due ?? 0) * 100);
    if (total_cents > dueCents) {
      throw new AppError('total_cents exceeds invoice balance', 400);
    }
  }

  // Pre-validate every schedule row BEFORE inserting the plan, so a bad row
  // doesn't leave an orphan `installment_plans` record with no schedule.
  const normalizedSchedule: Array<{ amountCents: number; dueDate: string }> = [];
  for (const row of schedule) {
    const amountCents = Number(row.amount_cents);
    if (!Number.isInteger(amountCents) || amountCents < 1) {
      throw new AppError('Each schedule row must have a positive integer amount_cents', 400);
    }
    const dueDate = String(row.due_date ?? '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) {
      throw new AppError('Each schedule row must have a due_date in YYYY-MM-DD format', 400);
    }
    normalizedSchedule.push({ amountCents, dueDate });
  }

  // ── Insert plan + schedule rows atomically ──────────────────────────────
  // BUGHUNT-2026-05-17: previously the plan INSERT and each schedule INSERT
  // were sequential adb.run() calls. A crash mid-loop left the customer
  // bound to an installment_plans row (status='active') with a partial or
  // missing schedule — they'd see a plan in their portal with the wrong
  // total or missing due dates and could be over- or under-charged on auto-bill.
  // Wrap in adb.transaction(). lastInsertRowidFrom(0) so every schedule row
  // pins to the plan's rowid (each schedule INSERT bumps last_insert_rowid()).
  // BUGHUNT-2026-05-17: include the customer-still-active guard inside the
  // tx via INSERT...WHERE EXISTS + expectChanges. If a /DELETE soft-deletes
  // the customer between the precheck above and this tx commit, the plan
  // INSERT yields 0 rows and the whole tx rolls back — no orphan plan or
  // schedule rows, no auto-charge cron picking up a deleted customer.
  const planTxQueries: TxQuery[] = [
    {
      sql: `INSERT INTO installment_plans
              (invoice_id, customer_id, total_cents, installment_count, frequency_days,
               acceptance_token, acceptance_signed_at, status)
              SELECT ?, ?, ?, ?, ?, ?, ?, 'active'
               WHERE EXISTS (SELECT 1 FROM customers WHERE id = ? AND is_deleted = 0)`,
      params: [
        invoiceIdClean,
        customer_id,
        total_cents,
        installment_count,
        frequency_days,
        acceptance_token.trim(),
        acceptance_signed_at,
        customer_id,
      ],
      expectChanges: true,
      expectChangesError: 'CUSTOMER_DELETED_RACE',
    },
  ];
  for (const { amountCents, dueDate } of normalizedSchedule) {
    planTxQueries.push({
      sql: `INSERT INTO installment_schedule (plan_id, due_date, amount_cents, status)
            VALUES (?, ?, ?, 'pending')`,
      params: [lastInsertRowidFrom(0), dueDate, amountCents],
    });
  }
  let planTxResults: Awaited<ReturnType<typeof adb.transaction>>;
  try {
    planTxResults = await adb.transaction(planTxQueries);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('CUSTOMER_DELETED_RACE')) {
      throw new AppError('Customer was just deleted; refresh and retry', 409);
    }
    throw err;
  }
  const planId = Number(planTxResults[0].lastInsertRowid);

  audit(db, 'installment_plan.create', req.user!.id, req.ip ?? '', {
    plan_id: planId,
    customer_id,
    invoice_id: invoiceIdClean,
    total_cents,
    installment_count,
  });

  logger.info('installment plan created', { planId, customerId: customer_id, totalCents: total_cents });

  const plan = await adb.get<any>('SELECT * FROM installment_plans WHERE id = ?', planId);
  const scheduleRows = await adb.all<any>('SELECT * FROM installment_schedule WHERE plan_id = ? ORDER BY due_date', planId);

  res.status(201).json({ success: true, data: { ...plan, schedule: scheduleRows } });
}));

// ─── GET / — list plans ───────────────────────────────────────────────────────

router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const { customer_id, invoice_id, status } = req.query as Record<string, string>;

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (customer_id) {
    // BUGHUNT-2026-05-16: previously `parseInt("abc")` returned NaN and was
    // bound as a SQL param, silently no-opping the filter on malformed input.
    const cid = parseInt(customer_id, 10);
    if (!Number.isInteger(cid) || cid <= 0) {
      throw new AppError('customer_id must be a positive integer', 400);
    }
    conditions.push('ip.customer_id = ?');
    params.push(cid);
  }
  if (invoice_id) {
    const iid = parseInt(invoice_id, 10);
    if (!Number.isInteger(iid) || iid <= 0) {
      throw new AppError('invoice_id must be a positive integer', 400);
    }
    conditions.push('ip.invoice_id = ?');
    params.push(iid);
  }
  if (status) {
    conditions.push('ip.status = ?');
    params.push(status);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const plans = await adb.all<any>(
    `SELECT ip.*,
            c.first_name AS customer_first_name, c.last_name AS customer_last_name
       FROM installment_plans ip
       LEFT JOIN customers c ON c.id = ip.customer_id
       ${where}
       ORDER BY ip.id DESC
       LIMIT 500`,
    ...params,
  );

  res.json({ success: true, data: plans });
}));

// ─── GET /:id — plan detail ───────────────────────────────────────────────────

router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const id = parseId(req.params.id);

  const plan = await adb.get<any>(
    `SELECT ip.*,
            c.first_name AS customer_first_name, c.last_name AS customer_last_name
       FROM installment_plans ip
       LEFT JOIN customers c ON c.id = ip.customer_id
      WHERE ip.id = ?`,
    id,
  );
  if (!plan) throw new AppError('Installment plan not found', 404);

  const scheduleRows = await adb.all<any>(
    'SELECT * FROM installment_schedule WHERE plan_id = ? ORDER BY due_date',
    id,
  );

  res.json({ success: true, data: { ...plan, schedule: scheduleRows } });
}));

// ─── POST /:id/cancel — cancel plan ──────────────────────────────────────────

router.post('/:id/cancel', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;

  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
    throw new AppError('Admin or manager role required to cancel a plan', 403);
  }

  const id = parseId(req.params.id);
  const existing = await adb.get<{ status: string }>('SELECT status FROM installment_plans WHERE id = ?', id);
  if (!existing) throw new AppError('Installment plan not found', 404);

  if (existing.status === 'completed' || existing.status === 'cancelled') {
    throw new AppError(`Cannot cancel a plan in '${existing.status}' status`, 409);
  }

  // BUGHUNT-2026-05-10-53: also void any pending schedule rows so future
  // automation (charge cron, reminder dispatcher) doesn't pick up leftover
  // installments that belong to a cancelled plan. Wrap in adb.transaction
  // so a mid-cancel failure leaves the plan in its prior state instead of
  // a half-cancelled mix.
  //
  // BUGHUNT-2026-05-17: guarded UPDATE WHERE status NOT IN (completed,
  // cancelled) + expectChanges. The SELECT precheck above is TOCTOU —
  // an auto-charge cron could flip status to 'completed' between the
  // SELECT and the UPDATE, and the unguarded UPDATE would silently
  // overwrite the completed state back to 'cancelled' (losing the fact
  // that the customer already finished paying).
  let cancelResult: Awaited<ReturnType<typeof adb.transaction>>;
  try {
    cancelResult = await adb.transaction([
      {
        sql: `UPDATE installment_plans SET status = 'cancelled' WHERE id = ? AND status NOT IN ('completed', 'cancelled')`,
        params: [id],
        expectChanges: true,
        expectChangesError: 'INSTALLMENT_PLAN_NOT_CANCELLABLE',
      },
      {
        sql: `UPDATE installment_schedule SET status = 'cancelled' WHERE plan_id = ? AND status = 'pending'`,
        params: [id],
      },
    ]);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('INSTALLMENT_PLAN_NOT_CANCELLABLE')) {
      throw new AppError('Plan status changed concurrently; refresh and retry', 409);
    }
    throw err;
  }
  const schedRowsCancelled = Array.isArray(cancelResult) ? cancelResult[1]?.changes ?? 0 : 0;

  audit(db, 'installment_plan.cancel', req.user!.id, req.ip ?? '', {
    plan_id: id,
    pending_schedule_rows_cancelled: schedRowsCancelled,
  });

  res.json({
    success: true,
    data: { id, status: 'cancelled', pending_schedule_rows_cancelled: schedRowsCancelled },
  });
}));

export default router;
