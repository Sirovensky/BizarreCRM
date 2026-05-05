/**
 * Inventory Variants + Bundles routes
 * SCAN-486, SCAN-487
 *
 * Variants mount: /api/v1/inventory-variants
 * Bundles  mount: /api/v1/inventory-bundles
 *
 * authMiddleware is applied at the parent router level — NOT re-added here.
 * Role gate: requirePermission('inventory.adjust') on all mutating endpoints.
 * Money: INTEGER cents only (SEC-H34).
 * Rate-limit writes via checkWindowRate / recordWindowAttempt.
 * Audit: variant create, variant stock-adjust, bundle create.
 */
import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requirePermission } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import type { AsyncDb } from '../db/async-db.js';

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------
const VARIANT_WRITE_CATEGORY = 'inventory_variant_write';
const BUNDLE_WRITE_CATEGORY  = 'inventory_bundle_write';
/** 30 mutations per user per 10 minutes */
const WRITE_MAX    = 30;
const WRITE_WIN_MS = 10 * 60 * 1000;

const NAME_MAX    = 200;
const SKU_MAX     = 100;
const VAL_MAX     = 100; // variant_value

type AnyRow = Record<string, unknown>;

function nowIso(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

/** Parse and validate a positive integer path parameter. */
function parseId(raw: string, label: string): number {
  const n = parseInt(raw, 10);
  if (!Number.isInteger(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

/** Validate a non-negative integer cent value. */
function parseCents(raw: unknown, label: string): number {
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 0) throw new AppError(`${label} must be a non-negative integer (cents)`, 400);
  return n;
}

// ===========================================================================
// Variants router  —  mounted at /api/v1/inventory-variants
// ===========================================================================
export const variantsRouter = Router();

// ---------------------------------------------------------------------------
// GET /items/:itemId/variants — list variants for a parent item
// ---------------------------------------------------------------------------
variantsRouter.get('/items/:itemId/variants', asyncHandler(async (req: Request, res: Response) => {
  const adb: AsyncDb = req.asyncDb;
  const itemId = parseId(req.params.itemId as string, 'itemId');
  const { active_only = 'true' } = req.query as Record<string, string>;

  const where = active_only !== 'false'
    ? 'WHERE v.parent_item_id = ? AND v.is_active = 1'
    : 'WHERE v.parent_item_id = ?';

  const variants = await adb.all<AnyRow>(
    `SELECT v.* FROM inventory_variants v ${where} ORDER BY v.variant_type, v.variant_value`,
    itemId,
  );

  res.json({ success: true, data: variants });
}));

// ---------------------------------------------------------------------------
// POST /items/:itemId/variants — create a variant
// ---------------------------------------------------------------------------
variantsRouter.post(
  '/items/:itemId/variants',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    // Rate limit
    if (!checkWindowRate(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many variant writes — please slow down', 429);
    }
    recordWindowAttempt(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const itemId = parseId(req.params.itemId as string, 'itemId');
    const { sku, variant_type, variant_value, retail_price_cents, cost_price_cents = 0, in_stock = 0 } = req.body as Record<string, unknown>;

    // Validate required fields
    if (typeof sku !== 'string' || !sku.trim()) throw new AppError('sku is required', 400);
    if (typeof variant_type !== 'string' || !variant_type.trim()) throw new AppError('variant_type is required', 400);
    if (typeof variant_value !== 'string' || !variant_value.trim()) throw new AppError('variant_value is required', 400);

    const safeSku          = sku.trim().slice(0, SKU_MAX);
    const safeVariantType  = variant_type.trim().slice(0, VAL_MAX);
    const safeVariantValue = variant_value.trim().slice(0, VAL_MAX);
    const retailCents      = parseCents(retail_price_cents, 'retail_price_cents');
    const costCents        = parseCents(cost_price_cents,   'cost_price_cents');
    const stockQty         = parseCents(in_stock,           'in_stock');

    // Verify parent item exists
    const parent = await adb.get<AnyRow>('SELECT id FROM inventory_items WHERE id = ? AND is_active = 1', itemId);
    if (!parent) throw new AppError('Parent inventory item not found', 404);

    const ts = nowIso();
    const result = await adb.run(
      `INSERT INTO inventory_variants
         (parent_item_id, sku, variant_type, variant_value, retail_price_cents, cost_price_cents, in_stock, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      itemId, safeSku, safeVariantType, safeVariantValue, retailCents, costCents, stockQty, ts, ts,
    );

    const newId = Number(result.lastInsertRowid);
    audit(db, 'inventory_variant_created', userId, ip, {
      variant_id: newId, parent_item_id: itemId, sku: safeSku,
      variant_type: safeVariantType, variant_value: safeVariantValue,
    });

    const created = await adb.get<AnyRow>('SELECT * FROM inventory_variants WHERE id = ?', newId);
    res.status(201).json({ success: true, data: created });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /variants/:id — partial update (non-stock fields)
// ---------------------------------------------------------------------------
variantsRouter.patch(
  '/variants/:id',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many variant writes — please slow down', 429);
    }
    recordWindowAttempt(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const id = parseId(req.params.id as string, 'variant id');
    const existing = await adb.get<AnyRow>('SELECT * FROM inventory_variants WHERE id = ?', id);
    if (!existing) throw new AppError('Variant not found', 404);

    const body = req.body as Record<string, unknown>;
    const sets: string[] = [];
    const vals: unknown[] = [];

    if (body.sku !== undefined) {
      if (typeof body.sku !== 'string' || !body.sku.trim()) throw new AppError('sku must be a non-empty string', 400);
      sets.push('sku = ?'); vals.push(body.sku.trim().slice(0, SKU_MAX));
    }
    if (body.variant_type !== undefined) {
      if (typeof body.variant_type !== 'string' || !body.variant_type.trim()) throw new AppError('variant_type must be a non-empty string', 400);
      sets.push('variant_type = ?'); vals.push(body.variant_type.trim().slice(0, VAL_MAX));
    }
    if (body.variant_value !== undefined) {
      if (typeof body.variant_value !== 'string' || !body.variant_value.trim()) throw new AppError('variant_value must be a non-empty string', 400);
      sets.push('variant_value = ?'); vals.push(body.variant_value.trim().slice(0, VAL_MAX));
    }
    if (body.retail_price_cents !== undefined) {
      sets.push('retail_price_cents = ?'); vals.push(parseCents(body.retail_price_cents, 'retail_price_cents'));
    }
    if (body.cost_price_cents !== undefined) {
      sets.push('cost_price_cents = ?'); vals.push(parseCents(body.cost_price_cents, 'cost_price_cents'));
    }
    if (body.is_active !== undefined) {
      const flag = body.is_active ? 1 : 0;
      sets.push('is_active = ?'); vals.push(flag);
    }

    if (sets.length === 0) throw new AppError('No updatable fields provided', 400);

    sets.push('updated_at = ?'); vals.push(nowIso());
    vals.push(id);

    await adb.run(`UPDATE inventory_variants SET ${sets.join(', ')} WHERE id = ?`, ...vals);

    const updated = await adb.get<AnyRow>('SELECT * FROM inventory_variants WHERE id = ?', id);
    audit(db, 'inventory_variant_updated', userId, ip, { variant_id: id, fields: sets.filter(s => !s.startsWith('updated_at')) });
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /variants/:id — soft-delete (is_active = 0)
// ---------------------------------------------------------------------------
variantsRouter.delete(
  '/variants/:id',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many variant writes — please slow down', 429);
    }
    recordWindowAttempt(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const id = parseId(req.params.id as string, 'variant id');
    const existing = await adb.get<AnyRow>('SELECT id FROM inventory_variants WHERE id = ?', id);
    if (!existing) throw new AppError('Variant not found', 404);

    await adb.run(
      'UPDATE inventory_variants SET is_active = 0, updated_at = ? WHERE id = ?',
      nowIso(), id,
    );
    audit(db, 'inventory_variant_deactivated', userId, ip, { variant_id: id });
    res.json({ success: true, data: { id, is_active: 0 } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /variants/:id/stock — atomic stock adjustment
// ---------------------------------------------------------------------------
variantsRouter.patch(
  '/variants/:id/stock',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many variant writes — please slow down', 429);
    }
    recordWindowAttempt(db, VARIANT_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const id = parseId(req.params.id as string, 'variant id');
    const { delta, reason } = req.body as { delta: unknown; reason: unknown };

    const deltaNum = Number(delta);
    if (!Number.isInteger(deltaNum)) throw new AppError('delta must be an integer', 400);
    if (typeof reason !== 'string' || !reason.trim()) throw new AppError('reason is required', 400);

    // Atomic transaction — read, check, write
    const tx = db.transaction(() => {
      const row = db.prepare('SELECT in_stock FROM inventory_variants WHERE id = ?').get(id) as AnyRow | undefined;
      if (!row) throw new AppError('Variant not found', 404);
      const currentStock = row.in_stock as number;
      const newStock = currentStock + deltaNum;
      if (newStock < 0) throw new AppError(`Adjustment would result in negative stock (current: ${currentStock}, delta: ${deltaNum})`, 409);
      db.prepare('UPDATE inventory_variants SET in_stock = ?, updated_at = ? WHERE id = ?').run(newStock, nowIso(), id);
      return { previous: currentStock, new_stock: newStock };
    });

    const result = tx() as { previous: number; new_stock: number };
    audit(db, 'inventory_variant_stock_adjusted', userId, ip, {
      variant_id: id, delta: deltaNum, reason: reason.trim().slice(0, 200),
      previous_stock: result.previous, new_stock: result.new_stock,
    });
    res.json({ success: true, data: { id, in_stock: result.new_stock } });
  }),
);

// ===========================================================================
// Bundles router  —  mounted at /api/v1/inventory-bundles
// ===========================================================================
export const bundlesRouter = Router();

// ---------------------------------------------------------------------------
// GET / — paginated list of bundles
// ---------------------------------------------------------------------------
bundlesRouter.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb: AsyncDb = req.asyncDb;
  const { is_active, keyword } = req.query as Record<string, string>;

  const page     = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset   = (page - 1) * pageSize;

  let where = 'WHERE 1=1';
  const params: unknown[] = [];

  const activeFilter = is_active === 'false' ? 0 : 1; // default active only
  where += ' AND b.is_active = ?';
  params.push(activeFilter);

  if (keyword) {
    where += ' AND (b.name LIKE ? OR b.sku LIKE ?)';
    const k = `%${keyword.replace(/[%_\\]/g, '\\$&')}%`;
    params.push(k, k);
  }

  const [totalRow, bundles] = await Promise.all([
    adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM inventory_bundles b ${where}`, ...params),
    adb.all<AnyRow>(
      `SELECT b.* FROM inventory_bundles b ${where} ORDER BY b.name ASC LIMIT ? OFFSET ?`,
      ...params, pageSize, offset,
    ),
  ]);

  const total = totalRow!.c;
  res.json({
    success: true,
    data: {
      bundles,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /:id — bundle detail + items
// ---------------------------------------------------------------------------
bundlesRouter.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb: AsyncDb = req.asyncDb;
  const id = parseId(req.params.id as string, 'bundle id');

  const bundle = await adb.get<AnyRow>('SELECT * FROM inventory_bundles WHERE id = ?', id);
  if (!bundle) throw new AppError('Bundle not found', 404);

  const items = await adb.all<AnyRow>(
    `SELECT bi.id, bi.bundle_id, bi.item_id, bi.variant_id, bi.qty,
            i.name  AS item_name,  i.sku  AS item_sku,
            v.sku   AS variant_sku, v.variant_type, v.variant_value
     FROM inventory_bundle_items bi
     JOIN inventory_items i ON i.id = bi.item_id
     LEFT JOIN inventory_variants v ON v.id = bi.variant_id
     WHERE bi.bundle_id = ?
     ORDER BY bi.id ASC`,
    id,
  );

  res.json({ success: true, data: { ...bundle, items } });
}));

// ---------------------------------------------------------------------------
// POST / — create bundle (with items) in a transaction
// ---------------------------------------------------------------------------
bundlesRouter.post(
  '/',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many bundle writes — please slow down', 429);
    }
    recordWindowAttempt(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const body = req.body as {
      name?: unknown;
      sku?: unknown;
      retail_price_cents?: unknown;
      description?: unknown;
      items?: unknown;
    };

    if (typeof body.name !== 'string' || !body.name.trim()) throw new AppError('name is required', 400);
    if (typeof body.sku !== 'string' || !body.sku.trim()) throw new AppError('sku is required', 400);
    if (!Array.isArray(body.items) || body.items.length === 0) throw new AppError('items array is required and must not be empty', 400);

    const safeName = body.name.trim().slice(0, NAME_MAX);
    const safeSku  = body.sku.trim().slice(0, SKU_MAX);
    const retailCents = parseCents(body.retail_price_cents, 'retail_price_cents');
    const description = typeof body.description === 'string' ? body.description.trim() || null : null;

    // Validate items before the transaction
    interface BundleItemInput { item_id: number; variant_id: number | null; qty: number }
    const bundleItems: BundleItemInput[] = body.items.map((it: Record<string, unknown>, idx: number) => {
      const itemId    = Number(it.item_id);
      const variantId = it.variant_id != null ? Number(it.variant_id) : null;
      const qty       = Number(it.qty);
      if (!Number.isInteger(itemId) || itemId <= 0) throw new AppError(`items[${idx}].item_id must be a positive integer`, 400);
      if (variantId !== null && (!Number.isInteger(variantId) || variantId <= 0)) throw new AppError(`items[${idx}].variant_id must be a positive integer`, 400);
      if (!Number.isInteger(qty) || qty <= 0) throw new AppError(`items[${idx}].qty must be a positive integer`, 400);
      return { item_id: itemId, variant_id: variantId, qty };
    });

    const ts = nowIso();
    const tx = db.transaction(() => {
      const bundleResult = db.prepare(
        `INSERT INTO inventory_bundles (name, sku, retail_price_cents, description, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).run(safeName, safeSku, retailCents, description, ts, ts);

      const bundleId = Number(bundleResult.lastInsertRowid);

      for (const it of bundleItems) {
        // Verify item exists
        const itemExists = db.prepare('SELECT id FROM inventory_items WHERE id = ?').get(it.item_id);
        if (!itemExists) throw new AppError(`Inventory item ${it.item_id} not found`, 404);
        if (it.variant_id !== null) {
          const varExists = db.prepare('SELECT id FROM inventory_variants WHERE id = ? AND parent_item_id = ?').get(it.variant_id, it.item_id);
          if (!varExists) throw new AppError(`Variant ${it.variant_id} not found under item ${it.item_id}`, 404);
        }
        db.prepare(
          `INSERT INTO inventory_bundle_items (bundle_id, item_id, variant_id, qty, created_at)
           VALUES (?, ?, ?, ?, ?)`,
        ).run(bundleId, it.item_id, it.variant_id, it.qty, ts);
      }

      return bundleId;
    });

    const newBundleId = tx() as number;
    audit(db, 'inventory_bundle_created', userId, ip, {
      bundle_id: newBundleId, sku: safeSku, name: safeName, item_count: bundleItems.length,
    });

    // Return full detail
    const bundle = await adb.get<AnyRow>('SELECT * FROM inventory_bundles WHERE id = ?', newBundleId);
    const items  = await adb.all<AnyRow>(
      `SELECT bi.id, bi.item_id, bi.variant_id, bi.qty,
              i.name AS item_name, i.sku AS item_sku,
              v.sku AS variant_sku, v.variant_type, v.variant_value
       FROM inventory_bundle_items bi
       JOIN inventory_items i ON i.id = bi.item_id
       LEFT JOIN inventory_variants v ON v.id = bi.variant_id
       WHERE bi.bundle_id = ?`,
      newBundleId,
    );

    res.status(201).json({ success: true, data: { ...bundle, items } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id — partial update of bundle header
// ---------------------------------------------------------------------------
bundlesRouter.patch(
  '/:id',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many bundle writes — please slow down', 429);
    }
    recordWindowAttempt(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const id = parseId(req.params.id as string, 'bundle id');
    const existing = await adb.get<AnyRow>('SELECT id FROM inventory_bundles WHERE id = ?', id);
    if (!existing) throw new AppError('Bundle not found', 404);

    const body = req.body as Record<string, unknown>;
    const sets: string[] = [];
    const vals: unknown[] = [];

    if (body.name !== undefined) {
      if (typeof body.name !== 'string' || !body.name.trim()) throw new AppError('name must be a non-empty string', 400);
      sets.push('name = ?'); vals.push(body.name.trim().slice(0, NAME_MAX));
    }
    if (body.sku !== undefined) {
      if (typeof body.sku !== 'string' || !body.sku.trim()) throw new AppError('sku must be a non-empty string', 400);
      sets.push('sku = ?'); vals.push(body.sku.trim().slice(0, SKU_MAX));
    }
    if (body.retail_price_cents !== undefined) {
      sets.push('retail_price_cents = ?'); vals.push(parseCents(body.retail_price_cents, 'retail_price_cents'));
    }
    if (body.description !== undefined) {
      sets.push('description = ?'); vals.push(body.description === null ? null : String(body.description).trim() || null);
    }
    if (body.is_active !== undefined) {
      sets.push('is_active = ?'); vals.push(body.is_active ? 1 : 0);
    }

    if (sets.length === 0) throw new AppError('No updatable fields provided', 400);

    sets.push('updated_at = ?'); vals.push(nowIso());
    vals.push(id);

    await adb.run(`UPDATE inventory_bundles SET ${sets.join(', ')} WHERE id = ?`, ...vals);

    const updated = await adb.get<AnyRow>('SELECT * FROM inventory_bundles WHERE id = ?', id);
    audit(db, 'inventory_bundle_updated', userId, ip, { bundle_id: id, fields: sets.filter(s => !s.startsWith('updated_at')) });
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id — soft-delete bundle
// ---------------------------------------------------------------------------
bundlesRouter.delete(
  '/:id',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many bundle writes — please slow down', 429);
    }
    recordWindowAttempt(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const id = parseId(req.params.id as string, 'bundle id');
    const existing = await adb.get<AnyRow>('SELECT id FROM inventory_bundles WHERE id = ?', id);
    if (!existing) throw new AppError('Bundle not found', 404);

    await adb.run('UPDATE inventory_bundles SET is_active = 0, updated_at = ? WHERE id = ?', nowIso(), id);
    audit(db, 'inventory_bundle_deactivated', userId, ip, { bundle_id: id });
    res.json({ success: true, data: { id, is_active: 0 } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/items — add a line item to an existing bundle
// ---------------------------------------------------------------------------
bundlesRouter.post(
  '/:id/items',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many bundle writes — please slow down', 429);
    }
    recordWindowAttempt(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const bundleId = parseId(req.params.id as string, 'bundle id');
    const bundle   = await adb.get<AnyRow>('SELECT id FROM inventory_bundles WHERE id = ?', bundleId);
    if (!bundle) throw new AppError('Bundle not found', 404);

    const body      = req.body as Record<string, unknown>;
    const itemId    = Number(body.item_id);
    const variantId = body.variant_id != null ? Number(body.variant_id) : null;
    const qty       = Number(body.qty);

    if (!Number.isInteger(itemId) || itemId <= 0) throw new AppError('item_id must be a positive integer', 400);
    if (variantId !== null && (!Number.isInteger(variantId) || variantId <= 0)) throw new AppError('variant_id must be a positive integer', 400);
    if (!Number.isInteger(qty) || qty <= 0) throw new AppError('qty must be a positive integer', 400);

    const itemExists = await adb.get<AnyRow>('SELECT id FROM inventory_items WHERE id = ?', itemId);
    if (!itemExists) throw new AppError(`Inventory item ${itemId} not found`, 404);
    if (variantId !== null) {
      const varExists = await adb.get<AnyRow>('SELECT id FROM inventory_variants WHERE id = ? AND parent_item_id = ?', variantId, itemId);
      if (!varExists) throw new AppError(`Variant ${variantId} not found under item ${itemId}`, 404);
    }

    const ts = nowIso();
    const result = await adb.run(
      'INSERT INTO inventory_bundle_items (bundle_id, item_id, variant_id, qty, created_at) VALUES (?, ?, ?, ?, ?)',
      bundleId, itemId, variantId, qty, ts,
    );

    const newId = Number(result.lastInsertRowid);
    audit(db, 'inventory_bundle_item_added', userId, ip, { bundle_id: bundleId, item_id: itemId, variant_id: variantId, qty });
    res.status(201).json({ success: true, data: { id: newId, bundle_id: bundleId, item_id: itemId, variant_id: variantId, qty } });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id/items/:bundleItemId — remove a line item from a bundle
// ---------------------------------------------------------------------------
bundlesRouter.delete(
  '/:id/items/:bundleItemId',
  requirePermission('inventory.adjust'),
  asyncHandler(async (req: Request, res: Response) => {
    const db  = req.db;
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;
    const ip     = req.ip || 'unknown';

    if (!checkWindowRate(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_MAX, WRITE_WIN_MS)) {
      throw new AppError('Too many bundle writes — please slow down', 429);
    }
    recordWindowAttempt(db, BUNDLE_WRITE_CATEGORY, String(userId), WRITE_WIN_MS);

    const bundleId     = parseId(req.params.id as string, 'bundle id');
    const bundleItemId = parseId(req.params.bundleItemId as string, 'bundleItemId');

    const row = await adb.get<AnyRow>(
      'SELECT id FROM inventory_bundle_items WHERE id = ? AND bundle_id = ?',
      bundleItemId, bundleId,
    );
    if (!row) throw new AppError('Bundle item not found', 404);

    await adb.run('DELETE FROM inventory_bundle_items WHERE id = ?', bundleItemId);
    audit(db, 'inventory_bundle_item_removed', userId, ip, { bundle_id: bundleId, bundle_item_id: bundleItemId });
    res.json({ success: true, data: { id: bundleItemId, deleted: true } });
  }),
);
