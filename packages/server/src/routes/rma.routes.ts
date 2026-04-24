import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requirePermission } from '../middleware/auth.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { validateEnum, validateTextLength, validatePaginationOffset, validateId } from '../utils/validate.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import type { AsyncDb, TxQuery } from '../db/async-db.js';

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

// SEC-M18: RMA rows leak supplier relationship + tracking numbers —
// e.g. a cashier who opens the list sees "Supplier: Mobilesentrix,
// tracking #CJ12345" which lets them place outside-the-system orders,
// intercept shipments, or build a supplier graph for social-engineering.
// Gate list + detail on inventory.adjust (same grant that owns the
// create/patch path in SEC-H31 via inventory.edit — readers get a
// looser gate). Non-admin readers additionally get supplier_name,
// supplier_id, tracking_number, and notes redacted from the payload;
// admin sees everything.
const SENSITIVE_RMA_FIELDS = ['supplier_id', 'supplier_name', 'tracking_number', 'notes'] as const;

function redactRmaForRole(row: any, role: string | undefined): any {
  if (role === 'admin') return row;
  const out = { ...row };
  for (const k of SENSITIVE_RMA_FIELDS) {
    if (k in out) out[k] = null;
  }
  return out;
}

// GET / — List RMA requests
router.get('/', requirePermission('inventory.adjust'), asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const page = parsePage(_req.query.page);
  const perPage = parsePageSize(_req.query.per_page, 50);
  const offset = validatePaginationOffset((page - 1) * perPage, 'offset');

  const [totalRow, rmas] = await Promise.all([
    adb.get<{ c: number }>('SELECT COUNT(*) as c FROM rma_requests WHERE is_deleted = 0'),
    adb.all<any>(`
      SELECT r.*, u.first_name, u.last_name,
             (SELECT COUNT(*) FROM rma_items ri WHERE ri.rma_id = r.id) AS item_count
      FROM rma_requests r
      LEFT JOIN users u ON u.id = r.created_by
      WHERE r.is_deleted = 0
      ORDER BY r.created_at DESC
      LIMIT ? OFFSET ?
    `, perPage, offset),
  ]);

  const total = totalRow!.c;
  const redacted = rmas.map((r) => redactRmaForRole(r, _req.user?.role));
  res.json({ success: true, data: redacted, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /:id — Single RMA with items
router.get('/:id', requirePermission('inventory.adjust'), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const rmaId = validateId(req.params.id, 'id');
  const [rma, items] = await Promise.all([
    adb.get<any>('SELECT * FROM rma_requests WHERE id = ? AND is_deleted = 0', rmaId),
    adb.all(`
      SELECT ri.*, ii.name AS item_name, ii.sku
      FROM rma_items ri
      LEFT JOIN inventory_items ii ON ii.id = ri.inventory_item_id
      WHERE ri.rma_id = ?
    `, rmaId),
  ]);
  if (!rma) throw new AppError('RMA not found', 404);
  const safe = redactRmaForRole(rma, req.user?.role);
  res.json({ success: true, data: { ...safe, items } });
}));

// POST / — Create RMA
// SEC-H31: Creating an RMA drives inventory/supplier state — gate to users
// with `inventory.edit`. The previous auth-only check let any logged-in user
// (including cashier-tier) queue a return and send it to a supplier.
router.post('/', requirePermission('inventory.edit'), asyncHandler(async (req, res) => {
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
// SEC-H31: gate transitions behind `inventory.edit` so a cashier-tier user
// cannot mark an RMA as `received`/`resolved` and short-circuit the return path.
router.patch('/:id/status', requirePermission('inventory.edit'), asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const rmaId = validateId(req.params.id, 'id');

  const rawStatus = req.body?.status;
  if (!rawStatus || typeof rawStatus !== 'string') {
    throw new AppError('status required', 400);
  }
  const nextStatus = normaliseStatus(rawStatus);
  // validateEnum throws 400 with the whitelist in the message if unknown.
  validateEnum(nextStatus, RMA_STATUSES, 'status');

  const rma = await adb.get<{ id: number; status: string }>(
    'SELECT id, status FROM rma_requests WHERE id = ? AND is_deleted = 0',
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

  // S20-R1: Enforce the from-state in the WHERE clause so two parallel
  // status patches can't both succeed. Without this guard, a racing pair of
  // pending -> approved transitions would both observe `fromStatus = pending`
  // in the SELECT, then both blindly UPDATE. With it, only the first wins
  // (`changes === 1`); the second sees a 409 conflict.
  //
  // The `fromStatus === nextStatus` branch above is allowed to be a noop
  // tracking/notes patch, so in that case we keep the WHERE relaxed. Only
  // strict transitions get the status guard.
  let result;
  if (fromStatus === nextStatus) {
    result = await adb.run(
      `UPDATE rma_requests
          SET tracking_number = COALESCE(?, tracking_number),
              notes = COALESCE(?, notes),
              updated_at = ?
        WHERE id = ?`,
      trackingNumber, notes, now(), rmaId,
    );
  } else {
    // We use both the canonical spelling and any accepted legacy value of
    // fromStatus in the guard so a row stored under an alias (e.g. 'rejected'
    // vs 'declined') still matches.
    const fromAliases: string[] = [fromStatus];
    if (fromStatus === 'declined') fromAliases.push('rejected');
    const placeholders = fromAliases.map(() => '?').join(',');

    // SCAN-637 / S-RMA-1: The 'received' transition must restore stock atomically
    // with the status change. Fetch items first (read-only), then commit the
    // status UPDATE + all stock increments in a single transaction so a crash
    // mid-flight cannot leave the RMA 'received' with stock still missing.
    if (nextStatus === 'received') {
      const rmaItems = await adb.all<{ inventory_item_id: number | null; quantity: number }>(
        'SELECT inventory_item_id, quantity FROM rma_items WHERE rma_id = ? AND inventory_item_id IS NOT NULL',
        rmaId,
      );

      const statusUpdate: TxQuery = {
        sql: `UPDATE rma_requests
                 SET status = ?,
                     tracking_number = COALESCE(?, tracking_number),
                     notes = COALESCE(?, notes),
                     updated_at = ?
               WHERE id = ?
                 AND status IN (${placeholders})`,
        params: [nextStatus, trackingNumber, notes, now(), rmaId, ...fromAliases],
        expectChanges: true,
        expectChangesError: 'RMA status changed concurrently. Refresh and retry.',
      };

      const stockUpdates: TxQuery[] = rmaItems
        .filter(item => item.inventory_item_id !== null)
        .map(item => ({
          sql: "UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime('now') WHERE id = ?",
          params: [item.quantity, item.inventory_item_id as number],
        }));

      await adb.transaction([statusUpdate, ...stockUpdates]);
      // Mark as handled — skip the redundant adb.run below.
      result = { changes: 1, lastInsertRowid: 0 };
    } else {
      result = await adb.run(
        `UPDATE rma_requests
            SET status = ?,
                tracking_number = COALESCE(?, tracking_number),
                notes = COALESCE(?, notes),
                updated_at = ?
          WHERE id = ?
            AND status IN (${placeholders})`,
        nextStatus, trackingNumber, notes, now(), rmaId, ...fromAliases,
      );
    }
  }
  if (result.changes === 0) {
    throw new AppError('RMA status changed concurrently. Refresh and retry.', 409);
  }

  audit(req.db, 'rma_status_updated', req.user!.id, req.ip || 'unknown', {
    rma_id: rmaId,
    from_status: fromStatus,
    to_status: nextStatus,
  });
  res.json({ success: true, data: { id: rmaId, status: nextStatus } });
}));

export default router;
