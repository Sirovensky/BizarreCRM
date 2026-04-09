import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List RMA requests
router.get('/', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const page = Math.max(1, parseInt(_req.query.page as string) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(_req.query.per_page as string) || 50));
  const offset = (page - 1) * perPage;

  const [totalRow, rmas] = await Promise.all([
    adb.get<{ c: number }>('SELECT COUNT(*) as c FROM rma_requests'),
    adb.all(`
      SELECT r.*, u.first_name, u.last_name,
             (SELECT COUNT(*) FROM rma_items ri WHERE ri.rma_id = r.id) AS item_count
      FROM rma_requests r
      LEFT JOIN users u ON u.id = r.created_by
      ORDER BY r.created_at DESC
      LIMIT ? OFFSET ?
    `, perPage, offset),
  ]);

  const total = totalRow!.c;
  res.json({ success: true, data: rmas, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /:id — Single RMA with items
router.get('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const [rma, items] = await Promise.all([
    adb.get<any>('SELECT * FROM rma_requests WHERE id = ?', req.params.id),
    adb.all(`
      SELECT ri.*, ii.name AS item_name, ii.sku
      FROM rma_items ri
      LEFT JOIN inventory_items ii ON ii.id = ri.inventory_item_id
      WHERE ri.rma_id = ?
    `, req.params.id),
  ]);
  if (!rma) throw new AppError('RMA not found', 404);
  res.json({ success: true, data: { ...rma, items } });
}));

// POST / — Create RMA
router.post('/', asyncHandler(async (req, res) => {
  const db = req.db;
  const { supplier_id, supplier_name, reason, notes, items } = req.body;
  if (!items?.length) throw new AppError('At least one item required', 400);

  // V4: Validate each RMA item has required fields
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (!item.inventory_item_id && !item.name) {
      throw new AppError(`Item ${i + 1}: inventory_item_id or name is required`, 400);
    }
    if (item.quantity !== undefined && (!Number.isInteger(item.quantity) || item.quantity < 1)) {
      throw new AppError(`Item ${i + 1}: quantity must be a positive integer`, 400);
    }
    if (!item.reason) {
      throw new AppError(`Item ${i + 1}: reason is required`, 400);
    }
  }

  const create = db.transaction(() => {
    // Insert with placeholder order_id, then update using lastInsertRowid to avoid MAX(id)+1 race
    const result = db.prepare(`
      INSERT INTO rma_requests (order_id, supplier_id, supplier_name, status, reason, notes, created_by, created_at, updated_at)
      VALUES ('__pending__', ?, ?, 'pending', ?, ?, ?, ?, ?)
    `).run(supplier_id || null, supplier_name || null, reason || null, notes || null, req.user!.id, now(), now());

    const rmaId = Number(result.lastInsertRowid);
    const orderId = generateOrderId('RMA', rmaId);
    db.prepare('UPDATE rma_requests SET order_id = ? WHERE id = ?').run(orderId, rmaId);

    for (const item of items) {
      db.prepare(`
        INSERT INTO rma_items (rma_id, inventory_item_id, ticket_device_part_id, name, quantity, reason, resolution)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(rmaId, item.inventory_item_id || null, item.ticket_device_part_id || null,
        item.name, item.quantity || 1, item.reason || null, item.resolution || null);
    }
    return { id: rmaId, order_id: orderId };
  });

  const rma = create();
  res.status(201).json({ success: true, data: rma });
}));

// PATCH /:id/status — Update RMA status
router.patch('/:id/status', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { status, tracking_number, notes } = req.body;
  if (!status) throw new AppError('status required', 400);
  await adb.run(`
    UPDATE rma_requests SET status = ?, tracking_number = COALESCE(?, tracking_number), notes = COALESCE(?, notes), updated_at = ?
    WHERE id = ?
  `, status, tracking_number ?? null, notes ?? null, now(), req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

export default router;
