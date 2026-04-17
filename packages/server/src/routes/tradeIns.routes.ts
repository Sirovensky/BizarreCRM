import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// @audit-fixed: §37 — Centralised price/condition/status validators so the
// schema CHECK constraints can never throw raw 500s and an attacker can't
// store $1e12 in offered_price.
const MAX_TRADE_IN_PRICE = 100_000;
const VALID_CONDITIONS = new Set(['excellent', 'good', 'fair', 'poor', 'broken']);
const VALID_STATUSES = new Set(['pending', 'evaluated', 'accepted', 'declined', 'completed', 'scrapped']);

function validatePrice(field: string, value: unknown): void {
  if (value == null) return;
  if (typeof value !== 'number' || !isFinite(value) || value < 0) {
    throw new AppError(`${field} must be a non-negative number`, 400);
  }
  if (value > MAX_TRADE_IN_PRICE) {
    throw new AppError(`${field} must be ${MAX_TRADE_IN_PRICE} or less`, 400);
  }
}

// GET / — List trade-ins
router.get('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const status = (req.query.status as string || '').trim();
  const conditions = status ? 'WHERE ti.status = ?' : '';
  const params: any[] = status ? [status] : [];
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(req.query.per_page as string) || 50));
  const offset = (page - 1) * perPage;

  const [totalRow, tradeIns] = await Promise.all([
    adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM trade_ins ti ${conditions}`, ...params),
    adb.all(`
      SELECT ti.*, c.first_name, c.last_name, u.first_name AS eval_first, u.last_name AS eval_last
      FROM trade_ins ti
      LEFT JOIN customers c ON c.id = ti.customer_id
      LEFT JOIN users u ON u.id = ti.evaluated_by
      ${conditions}
      ORDER BY ti.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, perPage, offset),
  ]);

  const total = totalRow!.c;
  res.json({ success: true, data: tradeIns, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /:id — Single trade-in
router.get('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const ti = await adb.get(`
    SELECT ti.*, c.first_name, c.last_name, c.phone, c.email
    FROM trade_ins ti
    LEFT JOIN customers c ON c.id = ti.customer_id
    WHERE ti.id = ?
  `, req.params.id);
  if (!ti) throw new AppError('Trade-in not found', 404);
  res.json({ success: true, data: ti });
}));

// POST / — Create trade-in
router.post('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { customer_id, device_name, device_type, imei, serial, color, condition = 'good', offered_price, notes, pre_conditions } = req.body;
  if (!device_name) throw new AppError('device_name required', 400);
  // @audit-fixed: §37 — bound device_name + condition + offered_price so the
  // schema CHECKs never produce raw 500s and storage stays sane.
  if (typeof device_name !== 'string' || device_name.length > 200) {
    throw new AppError('device_name must be 200 characters or fewer', 400);
  }
  if (!VALID_CONDITIONS.has(condition)) {
    throw new AppError('condition must be one of excellent/good/fair/poor/broken', 400);
  }
  validatePrice('offered_price', offered_price);

  // @audit-fixed: §37 — verify customer FK exists when supplied; FKs are ON
  // (db/connection.ts:15) so a missing customer_id otherwise raises a generic
  // 500 instead of a 404.
  if (customer_id != null) {
    const cust = await adb.get('SELECT id FROM customers WHERE id = ?', customer_id);
    if (!cust) throw new AppError('Customer not found', 404);
  }

  const result = await adb.run(`
    INSERT INTO trade_ins (customer_id, device_name, device_type, imei, serial, color, condition, status, offered_price, notes, pre_conditions, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?)
  `, customer_id || null, device_name, device_type || null, imei || null, serial || null, color || null, condition,
    offered_price || 0, notes || null, pre_conditions ? JSON.stringify(pre_conditions) : null, req.user!.id, now(), now());

  audit(req.db, 'trade_in_created', req.user!.id, req.ip || 'unknown', { trade_in_id: Number(result.lastInsertRowid), device_name, customer_id: customer_id || null, offered_price: offered_price || 0 });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PATCH /:id — Update trade-in (evaluate, accept, decline)
// SEC-H30: Accepting a trade-in commits the shop to paying out `accepted_price`
// so the `status = 'accepted'` transition is gated to admin/manager. We also
// hard-cap accepted_price to (0, 100_000] so a typo can't issue a $1M payout
// and a sign-flip can't mint negative inventory value.
router.patch('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { status, offered_price, accepted_price, notes, condition } = req.body;
  const existing = await adb.get('SELECT id FROM trade_ins WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Trade-in not found', 404);
  // @audit-fixed: §37 — validate status + condition + price fields against
  // the same whitelists used by the schema CHECK constraints, otherwise an
  // invalid string drops through to a 500.
  if (status != null && !VALID_STATUSES.has(status)) {
    throw new AppError('Invalid status', 400);
  }
  if (condition != null && !VALID_CONDITIONS.has(condition)) {
    throw new AppError('Invalid condition', 400);
  }
  validatePrice('offered_price', offered_price);
  validatePrice('accepted_price', accepted_price);

  // SEC-H30: accepting a trade-in requires admin/manager.
  if (status === 'accepted') {
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager role required to accept a trade-in', 403);
    }
  }

  // SEC-H30: accepted_price sanity — reject <= 0 or > $100,000 when supplied.
  // Runs whenever accepted_price is in the body (not just on status=accepted)
  // so a manager cannot pre-set an absurd price and have a cashier flip status
  // later via a narrower endpoint. Uses Number() + Number.isFinite() because
  // validatePrice above only enforces >= 0 with no upper cap.
  if (accepted_price != null) {
    const ap = Number(accepted_price);
    if (!Number.isFinite(ap) || ap <= 0 || ap > 100_000) {
      throw new AppError('accepted_price must be > 0 and <= 100000', 400);
    }
  }

  await adb.run(`
    UPDATE trade_ins SET
      status = COALESCE(?, status), offered_price = COALESCE(?, offered_price),
      accepted_price = COALESCE(?, accepted_price), notes = COALESCE(?, notes),
      condition = COALESCE(?, condition), evaluated_by = ?, updated_at = ?
    WHERE id = ?
  `, status ?? null, offered_price ?? null, accepted_price ?? null, notes ?? null,
    condition ?? null, req.user!.id, now(), req.params.id);
  audit(req.db, 'trade_in_updated', req.user!.id, req.ip || 'unknown', { trade_in_id: Number(req.params.id), status: status ?? undefined, offered_price: offered_price ?? undefined, accepted_price: accepted_price ?? undefined });

  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

// DELETE /:id — Delete trade-in (API-4: only if pending/declined, not accepted)
router.delete('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<{ id: number; status: string }>('SELECT id, status FROM trade_ins WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Trade-in not found', 404);
  if (existing.status === 'accepted') {
    throw new AppError('Cannot delete an accepted trade-in. Decline it first.', 400);
  }

  await adb.run('DELETE FROM trade_ins WHERE id = ?', req.params.id);
  audit(req.db, 'trade_in_deleted', req.user!.id, req.ip || 'unknown', { trade_in_id: Number(req.params.id), status: existing.status });
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

export default router;
