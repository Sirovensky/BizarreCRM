import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List all loaner devices
router.get('/', (_req, res) => {
  const devices = db.prepare(`
    SELECT ld.*,
      (SELECT COUNT(*) FROM loaner_history lh WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL) AS is_loaned_out,
      (SELECT c.first_name || ' ' || c.last_name FROM loaner_history lh
       LEFT JOIN customers c ON c.id = lh.customer_id
       WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL LIMIT 1) AS loaned_to
    FROM loaner_devices ld ORDER BY ld.name
  `).all();
  res.json({ success: true, data: devices });
});

// GET /:id — Single loaner device with history
router.get('/:id', (req, res) => {
  const device = db.prepare('SELECT * FROM loaner_devices WHERE id = ?').get(req.params.id);
  if (!device) throw new AppError('Loaner device not found', 404);
  const history = db.prepare(`
    SELECT lh.*, c.first_name, c.last_name, t.order_id AS ticket_order_id
    FROM loaner_history lh
    LEFT JOIN customers c ON c.id = lh.customer_id
    LEFT JOIN ticket_devices td ON td.id = lh.ticket_device_id
    LEFT JOIN tickets t ON t.id = td.ticket_id
    WHERE lh.loaner_device_id = ? ORDER BY lh.loaned_at DESC
  `).all(req.params.id);
  res.json({ success: true, data: { ...device as any, history } });
});

// POST / — Create loaner device
router.post('/', (req, res) => {
  const { name, serial, imei, condition = 'good', notes } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = db.prepare(
    'INSERT INTO loaner_devices (name, serial, imei, condition, status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
  ).run(name, serial || null, imei || null, condition, 'available', notes || null, now(), now());
  res.status(201).json({ success: true, data: { id: Number(result.lastInsertRowid) } });
});

// POST /:id/loan — Loan out to customer
router.post('/:id/loan', (req, res) => {
  const { customer_id, ticket_device_id, notes } = req.body;
  if (!customer_id) throw new AppError('customer_id required', 400);
  const device = db.prepare('SELECT * FROM loaner_devices WHERE id = ?').get(req.params.id) as any;
  if (!device) throw new AppError('Loaner device not found', 404);
  if (device.status !== 'available') throw new AppError('Device is not available', 400);

  db.prepare('UPDATE loaner_devices SET status = ?, updated_at = ? WHERE id = ?').run('loaned', now(), req.params.id);
  const result = db.prepare(
    'INSERT INTO loaner_history (loaner_device_id, ticket_device_id, customer_id, loaned_at, condition_out, notes) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(req.params.id, ticket_device_id || null, customer_id, now(), device.condition, notes || null);
  res.json({ success: true, data: { history_id: Number(result.lastInsertRowid) } });
});

// POST /:id/return — Return loaner
router.post('/:id/return', (req, res) => {
  const { condition_in, notes } = req.body;
  const active = db.prepare(
    'SELECT id FROM loaner_history WHERE loaner_device_id = ? AND returned_at IS NULL ORDER BY loaned_at DESC LIMIT 1'
  ).get(req.params.id) as any;
  if (!active) throw new AppError('Device is not currently loaned out', 400);

  db.prepare('UPDATE loaner_history SET returned_at = ?, condition_in = ?, notes = COALESCE(?, notes) WHERE id = ?')
    .run(now(), condition_in || 'good', notes || null, active.id);
  db.prepare('UPDATE loaner_devices SET status = ?, condition = COALESCE(?, condition), updated_at = ? WHERE id = ?')
    .run('available', condition_in || null, now(), req.params.id);
  res.json({ success: true, data: { returned: true } });
});

// DELETE /:id — Remove loaner device
router.delete('/:id', (req, res) => {
  db.prepare('DELETE FROM loaner_history WHERE loaner_device_id = ?').run(req.params.id);
  db.prepare('DELETE FROM loaner_devices WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
});

export default router;
