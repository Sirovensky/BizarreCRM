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
  const customerExists = await adb.get<{ id: number }>('SELECT id FROM customers WHERE id = ?', customer_id);
  if (!customerExists) throw new AppError('Customer not found', 404);

  let invoiceIdClean: number | null = null;
  if (invoice_id !== null && invoice_id !== undefined) {
    invoiceIdClean = parseId(invoice_id, 'invoice_id');
    const invExists = await adb.get<{ id: number }>('SELECT id FROM invoices WHERE id = ?', invoiceIdClean);
    if (!invExists) throw new AppError('Invoice not found', 404);
  }

  // ── Insert plan ───────────────────────────────────────────────────────────
  const planResult = await adb.run(
    `INSERT INTO installment_plans
       (invoice_id, customer_id, total_cents, installment_count, frequency_days,
        acceptance_token, acceptance_signed_at, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'active')`,
    invoiceIdClean,
    customer_id,
    total_cents,
    installment_count,
    frequency_days,
    acceptance_token.trim(),
    acceptance_signed_at,
  );
  const planId = Number(planResult.lastInsertRowid);

  // ── Insert schedule rows ──────────────────────────────────────────────────
  for (const row of schedule) {
    const amountCents = Number(row.amount_cents);
    if (!Number.isInteger(amountCents) || amountCents < 1) {
      throw new AppError('Each schedule row must have a positive integer amount_cents', 400);
    }
    const dueDate = String(row.due_date ?? '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) {
      throw new AppError('Each schedule row must have a due_date in YYYY-MM-DD format', 400);
    }
    await adb.run(
      `INSERT INTO installment_schedule (plan_id, due_date, amount_cents, status)
       VALUES (?, ?, ?, 'pending')`,
      planId,
      dueDate,
      amountCents,
    );
  }

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
    conditions.push('ip.customer_id = ?');
    params.push(parseInt(customer_id, 10));
  }
  if (invoice_id) {
    conditions.push('ip.invoice_id = ?');
    params.push(parseInt(invoice_id, 10));
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

  await adb.run(
    `UPDATE installment_plans SET status = 'cancelled' WHERE id = ?`,
    id,
  );

  audit(db, 'installment_plan.cancel', req.user!.id, req.ip ?? '', { plan_id: id });

  res.json({ success: true, data: { id, status: 'cancelled' } });
}));

export default router;
