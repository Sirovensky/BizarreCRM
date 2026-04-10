import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
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
  if (offered_price != null && (typeof offered_price !== 'number' || !isFinite(offered_price) || offered_price < 0)) {
    throw new AppError('offered_price must be a non-negative number', 400);
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
router.patch('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { status, offered_price, accepted_price, notes, condition } = req.body;
  const existing = await adb.get('SELECT id FROM trade_ins WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Trade-in not found', 404);
  if (offered_price != null && (typeof offered_price !== 'number' || !isFinite(offered_price) || offered_price < 0)) {
    throw new AppError('offered_price must be a non-negative number', 400);
  }
  if (accepted_price != null && (typeof accepted_price !== 'number' || !isFinite(accepted_price) || accepted_price < 0)) {
    throw new AppError('accepted_price must be a non-negative number', 400);
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
