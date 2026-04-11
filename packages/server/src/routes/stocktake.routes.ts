/**
 * Stocktake routes — physical count workflow.
 *
 * Cross-ref: criticalaudit.md §48 idea #1.
 *
 * Lifecycle:
 *   POST /stocktake                    — open a new count session
 *   GET  /stocktake/:id                — fetch session + counts + variance
 *   POST /stocktake/:id/counts         — UPSERT a per-item scan
 *   POST /stocktake/:id/commit         — apply variance to inventory_items,
 *                                         write stock_movements, close session
 *   POST /stocktake/:id/cancel         — abandon the session (no stock change)
 *
 * Commit is a single transaction. If any item fails its guarded update the
 * whole commit rolls back. Stock movements are written with type='stocktake'
 * so the audit trail is visible in the item history view.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { qs } from '../utils/query.js';
import { validateIntegerQuantity, validateTextLength } from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('stocktake');
const router = Router();

interface StocktakeRow {
  id: number;
  name: string;
  location: string | null;
  status: 'open' | 'committed' | 'cancelled';
  opened_by_user_id: number | null;
  opened_at: string;
  committed_at: string | null;
  committed_by_user_id: number | null;
  notes: string | null;
}

interface StocktakeCountRow {
  id: number;
  stocktake_id: number;
  inventory_item_id: number;
  expected_qty: number;
  counted_qty: number;
  variance: number;
  notes: string | null;
  counted_at: string;
  name?: string;
  sku?: string;
}

// --------------------------------------------------------------------------
// GET /stocktake — list sessions (most recent first)
// --------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const status = (req.query.status as string | undefined)?.trim();
    const where = status ? 'WHERE status = ?' : '';
    const params = status ? [status] : [];
    const rows = await adb.all<StocktakeRow>(
      `SELECT * FROM stocktakes ${where} ORDER BY opened_at DESC LIMIT 200`,
      ...params,
    );
    res.json({ success: true, data: rows });
  }),
);

// --------------------------------------------------------------------------
// POST /stocktake — open a session
// --------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const name = validateTextLength(req.body?.name, 120, 'name');
    if (!name) throw new AppError('name is required', 400);
    const location = req.body?.location
      ? validateTextLength(req.body.location, 120, 'location')
      : null;
    const notes = req.body?.notes
      ? validateTextLength(req.body.notes, 1000, 'notes')
      : null;

    const result = await adb.run(
      `INSERT INTO stocktakes (name, location, opened_by_user_id, notes)
       VALUES (?, ?, ?, ?)`,
      name,
      location,
      req.user!.id,
      notes,
    );

    const id = Number(result.lastInsertRowid);
    audit(req.db, 'stocktake_opened', req.user!.id, req.ip || 'unknown', {
      stocktake_id: id,
      name,
    });
    logger.info('Stocktake opened', { stocktake_id: id, user_id: req.user!.id });

    const row = await adb.get<StocktakeRow>(
      'SELECT * FROM stocktakes WHERE id = ?',
      id,
    );
    res.json({ success: true, data: row });
  }),
);

// --------------------------------------------------------------------------
// GET /stocktake/:id — session + all counts + variance summary
// --------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid stocktake id', 400);

    const session = await adb.get<StocktakeRow>(
      'SELECT * FROM stocktakes WHERE id = ?',
      id,
    );
    if (!session) throw new AppError('Stocktake not found', 404);

    const counts = await adb.all<StocktakeCountRow>(
      `SELECT sc.*, i.name, i.sku, i.in_stock as current_in_stock
       FROM stocktake_counts sc
       LEFT JOIN inventory_items i ON i.id = sc.inventory_item_id
       WHERE sc.stocktake_id = ?
       ORDER BY sc.counted_at DESC`,
      id,
    );

    const summary = counts.reduce(
      (acc, c) => {
        acc.items_counted += 1;
        acc.total_variance += c.variance;
        if (c.variance !== 0) acc.items_with_variance += 1;
        if (c.variance > 0) acc.surplus += c.variance;
        if (c.variance < 0) acc.shortage += Math.abs(c.variance);
        return acc;
      },
      { items_counted: 0, items_with_variance: 0, total_variance: 0, surplus: 0, shortage: 0 },
    );

    res.json({ success: true, data: { session, counts, summary } });
  }),
);

// --------------------------------------------------------------------------
// POST /stocktake/:id/counts — UPSERT a single item count
// Body: { inventory_item_id, counted_qty, notes? }
// Re-scanning the same SKU replaces the prior row (not a duplicate insert).
// --------------------------------------------------------------------------
router.post(
  '/:id/counts',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid stocktake id', 400);

    const session = await adb.get<StocktakeRow>(
      'SELECT * FROM stocktakes WHERE id = ?',
      id,
    );
    if (!session) throw new AppError('Stocktake not found', 404);
    if (session.status !== 'open') {
      throw new AppError(`Cannot add counts to a ${session.status} stocktake`, 400);
    }

    const inventoryItemId = validateIntegerQuantity(
      req.body?.inventory_item_id,
      'inventory_item_id',
    );
    const countedQty = validateIntegerQuantity(req.body?.counted_qty, 'counted_qty');
    const notes = req.body?.notes
      ? validateTextLength(req.body.notes, 500, 'notes')
      : null;

    // expected_qty is captured at the moment of scan — we don't re-read it
    // on commit because in_stock may have drifted from concurrent sales.
    const item = await adb.get<{ in_stock: number; name: string }>(
      'SELECT in_stock, name FROM inventory_items WHERE id = ? AND is_active = 1',
      inventoryItemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);

    const expectedQty = item.in_stock;
    const variance = countedQty - expectedQty;

    await adb.run(
      `INSERT INTO stocktake_counts
         (stocktake_id, inventory_item_id, expected_qty, counted_qty, variance, notes)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(stocktake_id, inventory_item_id) DO UPDATE SET
         expected_qty = excluded.expected_qty,
         counted_qty  = excluded.counted_qty,
         variance     = excluded.variance,
         notes        = excluded.notes,
         counted_at   = datetime('now')`,
      id,
      inventoryItemId,
      expectedQty,
      countedQty,
      variance,
      notes,
    );

    res.json({
      success: true,
      data: {
        stocktake_id: id,
        inventory_item_id: inventoryItemId,
        name: item.name,
        expected_qty: expectedQty,
        counted_qty: countedQty,
        variance,
      },
    });
  }),
);

// --------------------------------------------------------------------------
// POST /stocktake/:id/commit — apply variance, close session
// --------------------------------------------------------------------------
router.post(
  '/:id/commit',
  asyncHandler(async (req, res) => {
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid stocktake id', 400);

    const db = req.db;
    const session = db
      .prepare('SELECT * FROM stocktakes WHERE id = ?')
      .get(id) as StocktakeRow | undefined;
    if (!session) throw new AppError('Stocktake not found', 404);
    if (session.status !== 'open') {
      throw new AppError(`Stocktake is already ${session.status}`, 400);
    }

    const counts = db
      .prepare('SELECT * FROM stocktake_counts WHERE stocktake_id = ?')
      .all(id) as StocktakeCountRow[];

    if (counts.length === 0) {
      throw new AppError('No counts recorded — cannot commit empty stocktake', 400);
    }

    // Commit in a single transaction: update stock, write movements, mark
    // session committed. If any update throws (e.g. item deleted mid-count),
    // the whole thing rolls back.
    const commitTx = db.transaction(() => {
      const updateStockStmt = db.prepare(
        `UPDATE inventory_items
         SET in_stock = ?, updated_at = datetime('now')
         WHERE id = ? AND is_active = 1`,
      );
      const insertMovementStmt = db.prepare(
        `INSERT INTO stock_movements
           (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id)
         VALUES (?, 'stocktake', ?, 'stocktake', ?, ?, ?)`,
      );

      for (const c of counts) {
        const upd = updateStockStmt.run(c.counted_qty, c.inventory_item_id);
        if (upd.changes === 0) {
          throw new AppError(
            `Inventory item ${c.inventory_item_id} not found or inactive`,
            404,
          );
        }
        insertMovementStmt.run(
          c.inventory_item_id,
          c.variance, // signed — negative = shrinkage surfaced by count
          id,
          `Stocktake #${id}: ${c.expected_qty} -> ${c.counted_qty}`,
          req.user!.id,
        );
      }

      db.prepare(
        `UPDATE stocktakes
         SET status = 'committed',
             committed_at = datetime('now'),
             committed_by_user_id = ?
         WHERE id = ?`,
      ).run(req.user!.id, id);
    });

    try {
      commitTx();
    } catch (err) {
      logger.error('Stocktake commit failed', {
        stocktake_id: id,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    }

    audit(req.db, 'stocktake_committed', req.user!.id, req.ip || 'unknown', {
      stocktake_id: id,
      items_adjusted: counts.length,
      total_variance: counts.reduce((s, c) => s + c.variance, 0),
    });

    res.json({
      success: true,
      data: {
        stocktake_id: id,
        items_adjusted: counts.length,
      },
    });
  }),
);

// --------------------------------------------------------------------------
// POST /stocktake/:id/cancel — abandon without applying variance
// --------------------------------------------------------------------------
router.post(
  '/:id/cancel',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid stocktake id', 400);

    const session = await adb.get<StocktakeRow>(
      'SELECT * FROM stocktakes WHERE id = ?',
      id,
    );
    if (!session) throw new AppError('Stocktake not found', 404);
    if (session.status !== 'open') {
      throw new AppError(`Stocktake is already ${session.status}`, 400);
    }

    await adb.run(
      `UPDATE stocktakes SET status = 'cancelled' WHERE id = ?`,
      id,
    );

    audit(req.db, 'stocktake_cancelled', req.user!.id, req.ip || 'unknown', {
      stocktake_id: id,
    });

    res.json({ success: true, data: { stocktake_id: id, status: 'cancelled' } });
  }),
);

export default router;
