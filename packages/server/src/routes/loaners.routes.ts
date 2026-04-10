import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List all loaner devices
router.get('/', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const page = Math.max(1, parseInt(_req.query.page as string) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(_req.query.per_page as string) || 50));
  const offset = (page - 1) * perPage;
  const total = ((await adb.get<{ c: number }>('SELECT COUNT(*) as c FROM loaner_devices'))!).c;
  const devices = await adb.all(`
    SELECT ld.*,
      (SELECT COUNT(*) FROM loaner_history lh WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL) AS is_loaned_out,
      (SELECT c.first_name || ' ' || c.last_name FROM loaner_history lh
       LEFT JOIN customers c ON c.id = lh.customer_id
       WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL LIMIT 1) AS loaned_to
    FROM loaner_devices ld ORDER BY ld.name LIMIT ? OFFSET ?
  `, perPage, offset);
  res.json({ success: true, data: devices, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /:id — Single loaner device with history
router.get('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const device = await adb.get('SELECT * FROM loaner_devices WHERE id = ?', req.params.id);
  if (!device) throw new AppError('Loaner device not found', 404);
  const history = await adb.all(`
    SELECT lh.*, c.first_name, c.last_name, t.order_id AS ticket_order_id
    FROM loaner_history lh
    LEFT JOIN customers c ON c.id = lh.customer_id
    LEFT JOIN ticket_devices td ON td.id = lh.ticket_device_id
    LEFT JOIN tickets t ON t.id = td.ticket_id
    WHERE lh.loaner_device_id = ? ORDER BY lh.loaned_at DESC
  `, req.params.id);
  res.json({ success: true, data: { ...device as any, history } });
}));

// POST / — Create loaner device
router.post('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { name, serial, imei, condition = 'good', notes } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run(
    'INSERT INTO loaner_devices (name, serial, imei, condition, status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    name, serial || null, imei || null, condition, 'available', notes || null, now(), now()
  );
  audit(req.db, 'loaner_device_created', req.user!.id, req.ip || 'unknown', { loaner_id: Number(result.lastInsertRowid), name });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /:id — Update loaner device details (API-3)
router.put('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM loaner_devices WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Loaner device not found', 404);

  const { name, serial, imei, condition, notes } = req.body;
  if (name !== undefined && !name) throw new AppError('Name cannot be empty', 400);

  await adb.run(`
    UPDATE loaner_devices SET
      name = COALESCE(?, name),
      serial = COALESCE(?, serial),
      imei = COALESCE(?, imei),
      condition = COALESCE(?, condition),
      notes = COALESCE(?, notes),
      updated_at = ?
    WHERE id = ?
  `, name ?? null, serial ?? null, imei ?? null, condition ?? null, notes ?? null, now(), req.params.id);
  audit(req.db, 'loaner_device_updated', req.user!.id, req.ip || 'unknown', { loaner_id: Number(req.params.id) });

  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

// POST /:id/loan — Loan out to customer
router.post('/:id/loan', asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { customer_id, ticket_device_id, notes } = req.body;
  if (!customer_id) throw new AppError('customer_id required', 400);

  // V6: Verify FK existence before INSERT
  const [customer, device] = await Promise.all([
    adb.get('SELECT id FROM customers WHERE id = ?', customer_id),
    adb.get('SELECT * FROM loaner_devices WHERE id = ?', req.params.id),
  ]);
  if (!customer) throw new AppError('Customer not found', 404);
  if (ticket_device_id) {
    const ticketDevice = await adb.get('SELECT id FROM ticket_devices WHERE id = ?', ticket_device_id);
    if (!ticketDevice) throw new AppError('Ticket device not found', 404);
  }

  if (!device) throw new AppError('Loaner device not found', 404);
  if ((device as any).status !== 'available') throw new AppError('Device is not available', 400);

  const loanOut = db.transaction(() => {
    db.prepare('UPDATE loaner_devices SET status = ?, updated_at = ? WHERE id = ?').run('loaned', now(), req.params.id);
    const result = db.prepare(
      'INSERT INTO loaner_history (loaner_device_id, ticket_device_id, customer_id, loaned_at, condition_out, notes) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(req.params.id, ticket_device_id || null, customer_id, now(), (device as any).condition, notes || null);
    return Number(result.lastInsertRowid);
  });

  const historyId = loanOut();
  audit(db, 'loaner_device_loaned', req.user!.id, req.ip || 'unknown', { loaner_id: Number(req.params.id), customer_id, history_id: historyId });
  res.json({ success: true, data: { history_id: historyId } });
}));

// POST /:id/return — Return loaner
router.post('/:id/return', asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { condition_in, notes } = req.body;
  const active = await adb.get<{ id: number }>(
    'SELECT id FROM loaner_history WHERE loaner_device_id = ? AND returned_at IS NULL ORDER BY loaned_at DESC LIMIT 1',
    req.params.id
  );
  if (!active) throw new AppError('Device is not currently loaned out', 400);

  const returnLoaner = db.transaction(() => {
    db.prepare('UPDATE loaner_history SET returned_at = ?, condition_in = ?, notes = COALESCE(?, notes) WHERE id = ?')
      .run(now(), condition_in || 'good', notes || null, active.id);
    db.prepare('UPDATE loaner_devices SET status = ?, condition = COALESCE(?, condition), updated_at = ? WHERE id = ?')
      .run('available', condition_in || null, now(), req.params.id);
  });

  returnLoaner();
  audit(db, 'loaner_device_returned', req.user!.id, req.ip || 'unknown', { loaner_id: Number(req.params.id), history_id: active.id, condition_in: condition_in || 'good' });
  res.json({ success: true, data: { returned: true } });
}));

// DELETE /:id — Remove loaner device
router.delete('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const device = await adb.get('SELECT * FROM loaner_devices WHERE id = ?', req.params.id) as any;
  if (!device) throw new AppError('Loaner device not found', 404);
  if (device.status === 'loaned') throw new AppError('Cannot delete a device that is currently loaned out. Return it first.', 400);

  await adb.run('DELETE FROM loaner_history WHERE loaner_device_id = ?', req.params.id);
  await adb.run('DELETE FROM loaner_devices WHERE id = ?', req.params.id);
  audit(req.db, 'loaner_device_deleted', req.user!.id, req.ip || 'unknown', { loaner_id: Number(req.params.id), name: device.name });
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

export default router;
