import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List RMA requests
router.get('/', asyncHandler(async (_req, res) => {
  const rmas = db.prepare(`
    SELECT r.*, u.first_name, u.last_name,
           (SELECT COUNT(*) FROM rma_items ri WHERE ri.rma_id = r.id) AS item_count
    FROM rma_requests r
    LEFT JOIN users u ON u.id = r.created_by
    ORDER BY r.created_at DESC
  `).all();
  res.json({ success: true, data: rmas });
}));

// GET /:id — Single RMA with items
router.get('/:id', asyncHandler(async (req, res) => {
  const rma = db.prepare('SELECT * FROM rma_requests WHERE id = ?').get(req.params.id) as any;
  if (!rma) throw new AppError('RMA not found', 404);
  const items = db.prepare(`
    SELECT ri.*, ii.name AS item_name, ii.sku
    FROM rma_items ri
    LEFT JOIN inventory_items ii ON ii.id = ri.inventory_item_id
    WHERE ri.rma_id = ?
  `).all(req.params.id);
  res.json({ success: true, data: { ...rma, items } });
}));

// POST / — Create RMA
router.post('/', asyncHandler(async (req, res) => {
  const { supplier_id, supplier_name, reason, notes, items } = req.body;
  if (!items?.length) throw new AppError('At least one item required', 400);

  const seqRow = db.prepare("SELECT COALESCE(MAX(id), 0) + 1 as next_num FROM rma_requests").get() as any;
  const orderId = generateOrderId('RMA', seqRow.next_num);

  const create = db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO rma_requests (order_id, supplier_id, supplier_name, status, reason, notes, created_by, created_at, updated_at)
      VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?)
    `).run(orderId, supplier_id || null, supplier_name || null, reason || null, notes || null, req.user!.id, now(), now());

    const rmaId = Number(result.lastInsertRowid);
    for (const item of items) {
      db.prepare(`
        INSERT INTO rma_items (rma_id, inventory_item_id, ticket_device_part_id, name, quantity, reason, resolution)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(rmaId, item.inventory_item_id || null, item.ticket_device_part_id || null,
        item.name, item.quantity || 1, item.reason || null, item.resolution || null);
    }
    return rmaId;
  });

  const rmaId = create();
  res.status(201).json({ success: true, data: { id: rmaId, order_id: orderId } });
}));

// PATCH /:id/status — Update RMA status
router.patch('/:id/status', asyncHandler(async (req, res) => {
  const { status, tracking_number, notes } = req.body;
  if (!status) throw new AppError('status required', 400);
  db.prepare(`
    UPDATE rma_requests SET status = ?, tracking_number = COALESCE(?, tracking_number), notes = COALESCE(?, notes), updated_at = ?
    WHERE id = ?
  `).run(status, tracking_number ?? null, notes ?? null, now(), req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

export default router;
