import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { validateEnum, validateTextLength } from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// SC8: Enforce a state machine on RMA status transitions.
// Happy path:    pending -> approved -> shipped -> received -> resolved
// Reject path:   pending -> rejected (aka "declined" in the schema)
//
// Additional allowances:
//   - Any non-terminal status may move back to `pending` (undo) by an admin.
//   - `rejected`/`resolved` are terminal — no further transitions.
//
// Note: the DB schema uses `declined` for the rejected state; we accept both
// spellings on input and canonicalise to `declined` for storage, so the
// audit requirement of "pending -> rejected" is satisfied against legacy data.
const RMA_STATUSES = ['pending', 'approved', 'shipped', 'received', 'resolved', 'declined'] as const;
type RmaStatus = typeof RMA_STATUSES[number];

const ALLOWED_TRANSITIONS: Record<RmaStatus, readonly RmaStatus[]> = {
  pending: ['approved', 'declined'],
  approved: ['shipped', 'declined', 'pending'],
  shipped: ['received', 'pending'],
  received: ['resolved', 'pending'],
  resolved: [],
  declined: [],
};

function normaliseStatus(input: string): RmaStatus {
  const v = input.trim().toLowerCase();
  if (v === 'rejected') return 'declined';
  return v as RmaStatus;
}

function isValidTransition(from: RmaStatus, to: RmaStatus): boolean {
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}

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
  const adb = req.asyncDb;
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

  // Insert with placeholder order_id, then update using lastInsertRowid to avoid MAX(id)+1 race
  const result = await adb.run(`
    INSERT INTO rma_requests (order_id, supplier_id, supplier_name, status, reason, notes, created_by, created_at, updated_at)
    VALUES ('__pending__', ?, ?, 'pending', ?, ?, ?, ?, ?)
  `, supplier_id || null, supplier_name || null, reason || null, notes || null, req.user!.id, now(), now());

  const rmaId = Number(result.lastInsertRowid);
  const orderId = generateOrderId('RMA', rmaId);
  await adb.run('UPDATE rma_requests SET order_id = ? WHERE id = ?', orderId, rmaId);

  for (const item of items) {
    await adb.run(`
      INSERT INTO rma_items (rma_id, inventory_item_id, ticket_device_part_id, name, quantity, reason, resolution)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `, rmaId, item.inventory_item_id || null, item.ticket_device_part_id || null,
      item.name, item.quantity || 1, item.reason || null, item.resolution || null);
  }

  audit(db, 'rma_created', req.user!.id, req.ip || 'unknown', { rma_id: rmaId, order_id: orderId, supplier_name: supplier_name || null, item_count: items.length });
  res.status(201).json({ success: true, data: { id: rmaId, order_id: orderId } });
}));

// PATCH /:id/status — Update RMA status
// SC8: Enforce state-machine transitions. Invalid jumps (e.g. pending -> resolved)
//      now return HTTP 400 with the allowed next states for the caller.
router.patch('/:id/status', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const rmaId = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(rmaId) || rmaId <= 0) throw new AppError('Invalid RMA id', 400);

  const rawStatus = req.body?.status;
  if (!rawStatus || typeof rawStatus !== 'string') {
    throw new AppError('status required', 400);
  }
  const nextStatus = normaliseStatus(rawStatus);
  // validateEnum throws 400 with the whitelist in the message if unknown.
  validateEnum(nextStatus, RMA_STATUSES, 'status');

  const rma = await adb.get<{ id: number; status: string }>(
    'SELECT id, status FROM rma_requests WHERE id = ?',
    rmaId,
  );
  if (!rma) throw new AppError('RMA not found', 404);

  const currentStatus = normaliseStatus(rma.status || 'pending');
  // Treat unknown legacy statuses as `pending` for transition purposes.
  const fromStatus: RmaStatus = (RMA_STATUSES as readonly string[]).includes(currentStatus)
    ? currentStatus
    : 'pending';

  if (fromStatus === nextStatus) {
    // No-op update — allow tracking_number / notes to still be patched without
    // a transition (harmless idempotent call).
  } else if (!isValidTransition(fromStatus, nextStatus)) {
    const allowed = ALLOWED_TRANSITIONS[fromStatus];
    throw new AppError(
      `Invalid RMA status transition: ${fromStatus} -> ${nextStatus}. Allowed next: ${
        allowed.length ? allowed.join(', ') : '(terminal state)'
      }`,
      400,
    );
  }

  const trackingNumber = req.body?.tracking_number != null
    ? validateTextLength(String(req.body.tracking_number), 128, 'tracking_number')
    : null;
  const notes = req.body?.notes != null
    ? validateTextLength(String(req.body.notes), 5000, 'notes')
    : null;

  await adb.run(`
    UPDATE rma_requests
       SET status = ?,
           tracking_number = COALESCE(?, tracking_number),
           notes = COALESCE(?, notes),
           updated_at = ?
     WHERE id = ?
  `, nextStatus, trackingNumber, notes, now(), rmaId);

  audit(req.db, 'rma_status_updated', req.user!.id, req.ip || 'unknown', {
    rma_id: rmaId,
    from_status: fromStatus,
    to_status: nextStatus,
  });
  res.json({ success: true, data: { id: rmaId, status: nextStatus } });
}));

export default router;
