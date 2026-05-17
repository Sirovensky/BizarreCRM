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
import {
  validateIntegerQuantity,
  validateTextLength,
  validateEnum,
} from '../utils/validate.js';
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
    const status = req.query.status
      ? validateEnum(
          req.query.status,
          ['open', 'committed', 'cancelled'] as const,
          'status',
          false,
        )
      : null;
    const where = status ? 'WHERE status = ?' : '';
    const params: unknown[] = status ? [status] : [];
    // WEB-UIUX-1362: hydrate each row with `items_counted` +
    // `items_with_variance` so the session list can surface progress on the
    // card itself. Without this the operator returning to 5 open sessions
    // has to drill into each one to remember how far they had gotten.
    // Subqueries scoped to the row keep the cost bounded — same pattern as
    // POST /stocktake/:id's variance aggregator.
    const rows = await adb.all<StocktakeRow & { items_counted?: number; items_with_variance?: number }>(
      `SELECT s.*,
              (SELECT COUNT(*) FROM stocktake_counts c
                WHERE c.stocktake_id = s.id) AS items_counted,
              (SELECT COUNT(*) FROM stocktake_counts c
                WHERE c.stocktake_id = s.id AND c.counted_qty <> c.expected_qty) AS items_with_variance
         FROM stocktakes s ${where} ORDER BY s.opened_at DESC LIMIT 200`,
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
    // SCAN-580: opening a session is a manager/admin action — it anchors the
    // entire count workflow; technicians and cashiers must not create sessions.
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager role required', 403);
    }
    const adb: AsyncDb = req.asyncDb;
    const name = validateTextLength(req.body?.name, 120, 'name');
    if (!name) throw new AppError('name is required', 400);
    const location = req.body?.location
      ? validateTextLength(req.body.location, 120, 'location')
      : null;
    const notes = req.body?.notes
      ? validateTextLength(req.body.notes, 1000, 'notes')
      : null;

    // WEB-UIUX-1371: refuse to open a second OPEN session with the same name
    // + location. Multi-day counts that "resume by name" would otherwise
    // create a fresh empty session and orphan day-1 counts in the prior row.
    // Cancelled / committed rows are fine to share a name — those are
    // historical and won't be confused with the new session.
    //
    // BUGHUNT-2026-05-17: stocktakes has no UNIQUE on (status, name, location)
    // (migration 091), so a pre-check SELECT then bare INSERT was a TOCTOU
    // window — two concurrent "open count for Back Stock" requests both
    // passed the SELECT and both INSERTed, splitting the day's counts
    // across two sessions and silently zeroing one of them on commit.
    // Fold the dup check into the INSERT via WHERE NOT EXISTS so SQLite's
    // writer lock serialises the race; the loser sees changes=0 -> 409.
    const result = await adb.run(
      `INSERT INTO stocktakes (name, location, opened_by_user_id, notes)
       SELECT ?, ?, ?, ?
        WHERE NOT EXISTS (
          SELECT 1 FROM stocktakes
           WHERE status = 'open'
             AND LOWER(name) = LOWER(?)
             AND COALESCE(LOWER(location), '') = COALESCE(LOWER(?), '')
        )`,
      name,
      location,
      req.user!.id,
      notes,
      name,
      location,
    );
    if (result.changes === 0) {
      const dup = await adb.get<{ id: number }>(
        `SELECT id FROM stocktakes
          WHERE status = 'open'
            AND LOWER(name) = LOWER(?)
            AND COALESCE(LOWER(location), '') = COALESCE(LOWER(?), '')
          LIMIT 1`,
        name,
        location,
      );
      throw new AppError(
        dup
          ? `An open stocktake named "${name}"${location ? ` at "${location}"` : ''} already exists (id=${dup.id}). Resume that session or close it before opening another.`
          : 'A concurrent request created a matching open stocktake. Refresh and try again.',
        409,
      );
    }

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
      `SELECT sc.*, i.name, i.sku, i.in_stock as current_in_stock, i.cost_price
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
// WEB-UIUX-1366: GET /stocktake/:id.csv — flat audit export
// Auditors require a CSV they can attach to year-end paperwork. Mirrors the
// detail JSON shape but as flat rows: sku, name, expected, counted, variance,
// current_in_stock, counted_at, notes. SCAN-1161 anti-formula prefix applied
// per cell so a SKU starting with `=`/`+`/`-`/`@` doesn't execute inside
// Excel/Calc.
// --------------------------------------------------------------------------
router.get(
  '/:id.csv',
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
        ORDER BY sc.counted_at ASC`,
      id,
    );

    const sanitize = (s: string | number | null | undefined): string => {
      const str = String(s ?? '').replace(/[",\n\r]/g, ' ').trim();
      return /^[=+\-@\t\r]/.test(str) ? `'${str}` : str;
    };

    const csvLines: string[] = [
      'sku,name,expected_qty,counted_qty,variance,current_in_stock,counted_at,notes',
    ];
    for (const c of counts) {
      const row = c as unknown as {
        sku?: string | null;
        name?: string | null;
        expected_qty: number;
        counted_qty: number;
        variance: number;
        current_in_stock?: number | null;
        counted_at?: string;
        notes?: string | null;
      };
      csvLines.push([
        `"${sanitize(row.sku)}"`,
        `"${sanitize(row.name)}"`,
        row.expected_qty,
        row.counted_qty,
        row.variance,
        row.current_in_stock ?? '',
        `"${sanitize(row.counted_at)}"`,
        `"${sanitize(row.notes)}"`,
      ].join(','));
    }

    const csv = csvLines.join('\n');
    const safeName = session.name.replace(/[^a-z0-9_\-]/gi, '_');
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="stocktake_${safeName}_${session.id}.csv"`);
    res.send(csv);
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
    // SCAN-581: cashiers must not submit scan counts — only admin, manager,
    // and technician roles are permitted to handle physical inventory scanning.
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager' && role !== 'technician') {
      throw new AppError('Admin, manager, or technician role required', 403);
    }
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

    // WEB-UIUX-1352: when the caller is scanning single units (each scan
    // represents +1 physical unit), pass `mode='increment'` so the server
    // ADDS counted_qty to any prior count instead of replacing it. The
    // default `mode='set'` preserves the existing "operator counts a bin
    // then types the total" semantics so existing integrations keep
    // working.
    const mode: 'set' | 'increment' = req.body?.mode === 'increment' ? 'increment' : 'set';

    // expected_qty is captured at the moment of scan — we don't re-read it
    // on commit because in_stock may have drifted from concurrent sales.
    const item = await adb.get<{ in_stock: number; name: string }>(
      'SELECT in_stock, name FROM inventory_items WHERE id = ? AND is_active = 1',
      inventoryItemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);

    const expectedQty = item.in_stock;

    if (mode === 'increment') {
      // Atomic add — combines INSERT-new-row with UPDATE-existing-row by
      // using COALESCE on stocktake_counts.counted_qty.
      await adb.run(
        `INSERT INTO stocktake_counts
           (stocktake_id, inventory_item_id, expected_qty, counted_qty, variance, notes)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(stocktake_id, inventory_item_id) DO UPDATE SET
           expected_qty = excluded.expected_qty,
           counted_qty  = stocktake_counts.counted_qty + excluded.counted_qty,
           variance     = (stocktake_counts.counted_qty + excluded.counted_qty) - excluded.expected_qty,
           notes        = COALESCE(excluded.notes, stocktake_counts.notes),
           counted_at   = datetime('now')`,
        id,
        inventoryItemId,
        expectedQty,
        countedQty,
        countedQty - expectedQty,
        notes,
      );
    } else {
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
    }
    // Re-fetch the row so the audit + response carry the authoritative
    // counted_qty after a possible increment (delta vs final total).
    const stored = await adb.get<{ counted_qty: number; variance: number }>(
      'SELECT counted_qty, variance FROM stocktake_counts WHERE stocktake_id = ? AND inventory_item_id = ?',
      id, inventoryItemId,
    );
    const finalCountedQty = stored?.counted_qty ?? countedQty;
    const variance = stored?.variance ?? (countedQty - expectedQty);

    // Per-scan audit so variance-inflating writes can be traced back to an
    // operator. Commit() audits the whole session, but that's too coarse for
    // spotting the individual scan that caused a fraudulent variance.
    audit(req.db, 'stocktake_count_upserted', req.user!.id, req.ip || 'unknown', {
      stocktake_id: id,
      inventory_item_id: inventoryItemId,
      expected_qty: expectedQty,
      counted_qty: finalCountedQty,
      delta: mode === 'increment' ? countedQty : null,
      variance,
      mode,
    });

    res.json({
      success: true,
      data: {
        stocktake_id: id,
        inventory_item_id: inventoryItemId,
        name: item.name,
        expected_qty: expectedQty,
        counted_qty: finalCountedQty,
        variance,
        mode,
      },
    });
  }),
);

// --------------------------------------------------------------------------
// POST /stocktake/:id/counts/bulk — WEB-UIUX-1368: bulk CSV-style upload
// for blind counts. Stores that count on paper or offline scanners can
// submit `{ rows: [{ sku|inventory_item_id, counted_qty, notes? }, ...] }`
// in a single request; the server upserts each row using the same
// expected_qty snapshot logic as the single-row endpoint.
// Mode defaults to 'set' (replace) to match CSV semantics; pass
// `mode: 'increment'` if the upload is intended as a delta.
// --------------------------------------------------------------------------
router.post(
  '/:id/counts/bulk',
  asyncHandler(async (req, res) => {
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager' && role !== 'technician') {
      throw new AppError('Admin, manager, or technician role required', 403);
    }
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

    const rowsRaw = (req.body?.rows ?? []) as Array<Record<string, unknown>>;
    if (!Array.isArray(rowsRaw) || rowsRaw.length === 0) {
      throw new AppError('rows array required (at least one row)', 400);
    }
    if (rowsRaw.length > 5000) {
      throw new AppError('rows capped at 5,000 per upload', 400);
    }
    const mode: 'set' | 'increment' = req.body?.mode === 'increment' ? 'increment' : 'set';

    const results: Array<{
      sku?: string | null;
      inventory_item_id?: number | null;
      status: 'ok' | 'not_found' | 'invalid_qty' | 'duplicate_sku';
      counted_qty?: number;
      variance?: number;
      message?: string;
    }> = [];
    let okCount = 0;

    for (const row of rowsRaw) {
      const skuRaw = typeof row.sku === 'string' ? row.sku.trim() : '';
      const itemIdRaw = row.inventory_item_id;
      let inventoryItemId: number | null = null;
      if (Number.isFinite(Number(itemIdRaw)) && Number(itemIdRaw) > 0) {
        inventoryItemId = Number(itemIdRaw);
      } else if (skuRaw) {
        const matches = await adb.all<{ id: number }>(
          'SELECT id FROM inventory_items WHERE LOWER(sku) = LOWER(?) AND is_active = 1',
          skuRaw,
        );
        if (matches.length === 0) {
          results.push({ sku: skuRaw, status: 'not_found', message: `SKU '${skuRaw}' not found` });
          continue;
        }
        if (matches.length > 1) {
          results.push({ sku: skuRaw, status: 'duplicate_sku', message: `Multiple active items share SKU '${skuRaw}' — resolve in Inventory` });
          continue;
        }
        inventoryItemId = matches[0].id;
      }
      if (!inventoryItemId) {
        results.push({ sku: skuRaw || null, status: 'not_found', message: 'inventory_item_id or sku required' });
        continue;
      }
      const countedQtyRaw = Number(row.counted_qty);
      if (!Number.isFinite(countedQtyRaw) || !Number.isInteger(countedQtyRaw) || countedQtyRaw < 0) {
        results.push({ sku: skuRaw || null, inventory_item_id: inventoryItemId, status: 'invalid_qty', message: 'counted_qty must be a non-negative integer' });
        continue;
      }
      const notes = typeof row.notes === 'string' ? row.notes.trim().slice(0, 500) || null : null;
      const item = await adb.get<{ in_stock: number; name: string }>(
        'SELECT in_stock, name FROM inventory_items WHERE id = ? AND is_active = 1',
        inventoryItemId,
      );
      if (!item) {
        results.push({ sku: skuRaw || null, inventory_item_id: inventoryItemId, status: 'not_found', message: 'Inventory item not active' });
        continue;
      }
      const expectedQty = item.in_stock;
      if (mode === 'increment') {
        await adb.run(
          `INSERT INTO stocktake_counts
             (stocktake_id, inventory_item_id, expected_qty, counted_qty, variance, notes)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(stocktake_id, inventory_item_id) DO UPDATE SET
             expected_qty = excluded.expected_qty,
             counted_qty  = stocktake_counts.counted_qty + excluded.counted_qty,
             variance     = (stocktake_counts.counted_qty + excluded.counted_qty) - excluded.expected_qty,
             notes        = COALESCE(excluded.notes, stocktake_counts.notes),
             counted_at   = datetime('now')`,
          id, inventoryItemId, expectedQty, countedQtyRaw, countedQtyRaw - expectedQty, notes,
        );
      } else {
        const variance = countedQtyRaw - expectedQty;
        await adb.run(
          `INSERT INTO stocktake_counts
             (stocktake_id, inventory_item_id, expected_qty, counted_qty, variance, notes)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(stocktake_id, inventory_item_id) DO UPDATE SET
             expected_qty = excluded.expected_qty,
             counted_qty  = excluded.counted_qty,
             variance     = excluded.variance,
             notes        = COALESCE(excluded.notes, stocktake_counts.notes),
             counted_at   = datetime('now')`,
          id, inventoryItemId, expectedQty, countedQtyRaw, variance, notes,
        );
      }
      const stored = await adb.get<{ counted_qty: number; variance: number }>(
        'SELECT counted_qty, variance FROM stocktake_counts WHERE stocktake_id = ? AND inventory_item_id = ?',
        id, inventoryItemId,
      );
      results.push({
        sku: skuRaw || null,
        inventory_item_id: inventoryItemId,
        status: 'ok',
        counted_qty: stored?.counted_qty ?? countedQtyRaw,
        variance: stored?.variance ?? (countedQtyRaw - expectedQty),
      });
      okCount++;
    }

    audit(req.db, 'stocktake_bulk_upload', req.user!.id, req.ip || 'unknown', {
      stocktake_id: id,
      row_count: rowsRaw.length,
      ok_count: okCount,
      reject_count: rowsRaw.length - okCount,
      mode,
    });

    res.json({
      success: true,
      data: {
        stocktake_id: id,
        mode,
        ok_count: okCount,
        reject_count: rowsRaw.length - okCount,
        results,
      },
    });
  }),
);

// --------------------------------------------------------------------------
// DELETE /stocktake/:id/counts/:itemId — remove a typo'd row (WEB-UIUX-1354)
// --------------------------------------------------------------------------
// Operator scanned the wrong SKU or fat-fingered a qty on a row mid-session.
// Without a per-row remove, the typo persists until commit and corrupts the
// variance report. Only allowed while the session is still in-progress —
// committed/cancelled stocktakes are immutable.
router.delete(
  '/:id/counts/:itemId',
  asyncHandler(async (req, res) => {
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager' && role !== 'technician') {
      throw new AppError('Admin, manager, or technician role required', 403);
    }
    const adb = req.asyncDb;
    const stocktakeId = parseInt(req.params.id as string, 10);
    const inventoryItemId = parseInt(req.params.itemId as string, 10);
    if (!Number.isInteger(stocktakeId) || stocktakeId <= 0) {
      res.status(400).json({ success: false, message: 'Invalid stocktake id.' });
      return;
    }
    if (!Number.isInteger(inventoryItemId) || inventoryItemId <= 0) {
      res.status(400).json({ success: false, message: 'Invalid inventory item id.' });
      return;
    }
    const session = await adb.get<{ status: string }>(
      'SELECT status FROM stocktakes WHERE id = ?',
      stocktakeId,
    );
    if (!session) {
      res.status(404).json({ success: false, message: 'Stocktake not found.' });
      return;
    }
    if (session.status !== 'open') {
      res.status(409).json({
        success: false,
        code: 'ERR_STOCKTAKE_LOCKED',
        message: `Stocktake is ${session.status}; rows can no longer be removed.`,
      });
      return;
    }
    const result = await adb.run(
      'DELETE FROM stocktake_counts WHERE stocktake_id = ? AND inventory_item_id = ?',
      stocktakeId, inventoryItemId,
    );
    if (result.changes === 0) {
      res.status(404).json({ success: false, message: 'Count row not found for this item.' });
      return;
    }
    audit(req.db, 'stocktake_count_removed', req.user!.id, req.ip || 'unknown', {
      stocktake_id: stocktakeId,
      inventory_item_id: inventoryItemId,
    });
    res.json({ success: true, data: { stocktake_id: stocktakeId, inventory_item_id: inventoryItemId } });
  }),
);

// --------------------------------------------------------------------------
// POST /stocktake/:id/commit — apply variance, close session (manager/admin)
// --------------------------------------------------------------------------
router.post(
  '/:id/commit',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): commit rewrites every `in_stock` row
    // in the session — should not be reachable from a technician or cashier
    // account. Cancel has the same restriction because either terminal
    // action closes a count started by a manager.
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager role required', 403);
    }
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

    // SEC-H63: atomic commit with status race guard INSIDE the transaction.
    // Previously the pre-txn read of `status === 'open'` could be overtaken
    // by a concurrent POST /commit — both callers could pass the check, then
    // both write stock adjustments + stock_movements rows, double-applying
    // every variance. The schema CHECK constraint forbids a 'committing'
    // intermediate status, so instead we make the status flip from 'open'
    // → 'committed' the FIRST mutation inside the txn and assert changes=1.
    // better-sqlite3 `db.transaction(fn)` runs fn inside `BEGIN...COMMIT`,
    // so any throw (including the race-lost throw) rolls every write back
    // — quantities, movements, and the status flip all revert as a unit.
    // A second concurrent commit that arrives between our SELECT and the
    // conditional UPDATE will find `status != 'open'` (because the winner
    // already committed, flipping it to 'committed', or threw mid-txn and
    // rolled back leaving it 'open' — in which case the retry is legal).
    let raceLost = false;
    const commitTx = db.transaction(() => {
      // Race guard: conditional UPDATE as the first statement. Only one
      // caller can transition 'open' → 'committed'; losers see changes=0
      // and throw, rolling back before any stock is written.
      const lockResult = db
        .prepare(
          `UPDATE stocktakes
           SET status = 'committed',
               committed_at = datetime('now'),
               committed_by_user_id = ?
           WHERE id = ? AND status = 'open'`,
        )
        .run(req.user!.id, id);
      if (lockResult.changes !== 1) {
        raceLost = true;
        throw new AppError(
          'Stocktake is already being committed or was just closed',
          409,
        );
      }

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
    });

    try {
      commitTx();
    } catch (err) {
      logger.error('Stocktake commit failed', {
        stocktake_id: id,
        race_lost: raceLost,
        error: err instanceof Error ? err.message : String(err),
      });
      // SEC-H63: audit the failed commit attempt so a race-loss or any
      // mid-txn rollback is visible in the audit log even though the DB
      // state is unchanged.
      audit(req.db, 'stocktake_commit_failed', req.user!.id, req.ip || 'unknown', {
        stocktake_id: id,
        race_lost: raceLost,
        reason: err instanceof Error ? err.message : String(err),
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
// POST /stocktake/:id/cancel — abandon without applying variance (manager/admin)
// --------------------------------------------------------------------------
router.post(
  '/:id/cancel',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): only a manager can close out a count.
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager role required', 403);
    }
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

    // BUGHUNT-2026-05-16: conditional update + changes-check mirrors the
    // commit handler. Previously a concurrent commit that won the race could
    // be silently overwritten back to 'cancelled' — stock variances stayed
    // applied but the session showed as cancelled with committed_at still set.
    const result = await adb.run(
      `UPDATE stocktakes SET status = 'cancelled' WHERE id = ? AND status = 'open'`,
      id,
    );
    if (!result.changes) {
      throw new AppError('Stocktake state changed; refresh and retry', 409);
    }

    audit(req.db, 'stocktake_cancelled', req.user!.id, req.ip || 'unknown', {
      stocktake_id: id,
    });

    res.json({ success: true, data: { stocktake_id: id, status: 'cancelled' } });
  }),
);

export default router;
