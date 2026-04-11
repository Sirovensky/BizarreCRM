/**
 * Dunning routes — audit §52 ideas 3 & 4.
 *
 * Mounted at /api/v1/dunning with authMiddleware.
 * Response shape: `{ success: true, data: X }`.
 *
 * Endpoints:
 *   GET    /sequences               — list dunning sequences
 *   POST   /sequences               — create new sequence
 *   PUT    /sequences/:id           — update sequence
 *   DELETE /sequences/:id           — soft-disable sequence
 *   GET    /invoices/aging          — aging report (0-30/31-60/61-90/90+)
 *   POST   /run-now                 — manual trigger (admin)
 */
import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import { audit } from '../utils/audit.js';
import { validateRequiredString, validateJsonPayload } from '../utils/validate.js';
import { runDunningOnce, type DunningStep } from '../services/dunningScheduler.js';

const logger = createLogger('billing-enrich');
const router = Router();

type Row = Record<string, any>;

// ---------------------------------------------------------------------------
// Sequences CRUD
// ---------------------------------------------------------------------------

router.get('/sequences', asyncHandler(async (req: Request, res: Response) => {
  const rows = await req.asyncDb.all<Row>(
    `SELECT id, name, is_active, steps_json, created_at
       FROM dunning_sequences
       ORDER BY id DESC`,
  );

  const parsed = rows.map((r) => ({
    ...r,
    steps: safeParseSteps(r.steps_json),
  }));

  res.json({ success: true, data: parsed });
}));

router.post('/sequences', asyncHandler(async (req: Request, res: Response) => {
  const name = validateRequiredString(req.body?.name, 'name', 120);
  const steps = req.body?.steps;
  if (!Array.isArray(steps) || steps.length === 0) {
    throw new AppError('steps must be a non-empty array', 400);
  }
  for (const [i, s] of steps.entries()) {
    if (typeof s !== 'object' || s === null) throw new AppError(`steps[${i}] invalid`, 400);
    if (typeof s.days_offset !== 'number') throw new AppError(`steps[${i}].days_offset must be a number`, 400);
    if (typeof s.action !== 'string') throw new AppError(`steps[${i}].action must be a string`, 400);
  }
  const stepsJson = validateJsonPayload(steps, 'steps', 16_384);

  const result = await req.asyncDb.run(
    `INSERT INTO dunning_sequences (name, is_active, steps_json) VALUES (?, 1, ?)`,
    name,
    stepsJson,
  );

  audit(req.db, 'dunning.sequence.create', req.user?.id ?? null, req.ip ?? '', {
    id: result.lastInsertRowid,
    name,
  });

  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

router.put('/sequences/:id', asyncHandler(async (req: Request, res: Response) => {
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const existing = await req.asyncDb.get<Row>('SELECT id FROM dunning_sequences WHERE id = ?', id);
  if (!existing) throw new AppError('Sequence not found', 404);

  const updates: string[] = [];
  const params: any[] = [];

  if (req.body?.name !== undefined) {
    updates.push('name = ?');
    params.push(validateRequiredString(req.body.name, 'name', 120));
  }
  if (req.body?.is_active !== undefined) {
    updates.push('is_active = ?');
    params.push(req.body.is_active ? 1 : 0);
  }
  if (req.body?.steps !== undefined) {
    if (!Array.isArray(req.body.steps)) throw new AppError('steps must be an array', 400);
    updates.push('steps_json = ?');
    params.push(validateJsonPayload(req.body.steps, 'steps', 16_384));
  }

  if (updates.length === 0) throw new AppError('No updates supplied', 400);
  params.push(id);

  await req.asyncDb.run(
    `UPDATE dunning_sequences SET ${updates.join(', ')} WHERE id = ?`,
    ...params,
  );

  audit(req.db, 'dunning.sequence.update', req.user?.id ?? null, req.ip ?? '', { id });

  res.json({ success: true, data: { id } });
}));

router.delete('/sequences/:id', asyncHandler(async (req: Request, res: Response) => {
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  await req.asyncDb.run(`UPDATE dunning_sequences SET is_active = 0 WHERE id = ?`, id);

  audit(req.db, 'dunning.sequence.disable', req.user?.id ?? null, req.ip ?? '', { id });

  res.json({ success: true, data: { id, is_active: 0 } });
}));

// ---------------------------------------------------------------------------
// Aging report — idea 4
// ---------------------------------------------------------------------------

/**
 * GET /invoices/aging — buckets by days-overdue.
 * Response data: {
 *   buckets: { '0-30': { count, total_cents }, '31-60': ..., '61-90': ..., '90+': ... },
 *   invoices: [ { id, order_id, customer_id, customer_name, amount_due_cents, days_overdue, bucket } ]
 * }
 */
router.get('/invoices/aging', asyncHandler(async (req: Request, res: Response) => {
  const rows = await req.asyncDb.all<Row>(
    `SELECT i.id, i.order_id, i.customer_id, i.amount_due, i.total, i.due_date, i.status,
            c.first_name, c.last_name
       FROM invoices i
       LEFT JOIN customers c ON c.id = i.customer_id
      WHERE i.status IN ('unpaid','overdue','partial','draft')
        AND i.amount_due > 0
      ORDER BY i.due_date ASC`,
  );

  const now = Date.now();
  const buckets: Record<string, { count: number; total_cents: number }> = {
    '0-30':  { count: 0, total_cents: 0 },
    '31-60': { count: 0, total_cents: 0 },
    '61-90': { count: 0, total_cents: 0 },
    '90+':   { count: 0, total_cents: 0 },
  };

  const invoices = rows.map((r) => {
    const dueTs = r.due_date ? new Date(r.due_date).getTime() : now;
    const daysOverdue = Math.max(0, Math.floor((now - dueTs) / (1000 * 60 * 60 * 24)));
    const bucketKey =
      daysOverdue <= 30 ? '0-30' :
      daysOverdue <= 60 ? '31-60' :
      daysOverdue <= 90 ? '61-90' : '90+';

    const amountDueCents = Math.round((Number(r.amount_due) || 0) * 100);
    buckets[bucketKey].count += 1;
    buckets[bucketKey].total_cents += amountDueCents;

    return {
      id: r.id,
      order_id: r.order_id,
      customer_id: r.customer_id,
      customer_name: [r.first_name, r.last_name].filter(Boolean).join(' ') || null,
      amount_due_cents: amountDueCents,
      days_overdue: daysOverdue,
      bucket: bucketKey,
      due_date: r.due_date,
      status: r.status,
    };
  });

  res.json({ success: true, data: { buckets, invoices } });
}));

// ---------------------------------------------------------------------------
// Manual runner — idea 3
// ---------------------------------------------------------------------------

/**
 * POST /run-now — admin-only manual trigger for the dunning scheduler.
 * The cron itself is NOT wired from index.ts yet — see dunningScheduler.ts
 * for the TODO.
 */
router.post('/run-now', asyncHandler(async (req: Request, res: Response) => {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin only', 403);
  }

  const db = req.db;
  const summary = runDunningOnce(db);
  const summaryRecord: Record<string, unknown> = { ...summary };

  audit(req.db, 'dunning.run.manual', req.user?.id ?? null, req.ip ?? '', summaryRecord);
  logger.info('dunning manual run complete', summaryRecord);

  res.json({ success: true, data: summary });
}));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function safeParseSteps(json: unknown): DunningStep[] {
  if (typeof json !== 'string') return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export default router;
