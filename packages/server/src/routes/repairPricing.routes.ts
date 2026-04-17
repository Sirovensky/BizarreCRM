import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// Admin-only middleware for mutating global pricing adjustments
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  next();
}

// @audit-fixed: §37 — Manager OR admin can edit catalogue prices, but every
// other authenticated user is read-only. Previously the catalog endpoints had
// zero role gating, so any technician could rewrite labor_price.
function adminOrManager(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
    throw new AppError('Admin or manager access required', 403);
  }
  next();
}

// @audit-fixed: §37 — Bound prices so a fat-finger or hostile actor can't
// store negative or absurdly large numbers in repair_prices/grades.
const MAX_REPAIR_PRICE = 100_000;
function validatePriceField(field: string, value: unknown): number | null {
  if (value == null) return null;
  const n = Number(value);
  if (!Number.isFinite(n)) throw new AppError(`${field} must be a finite number`, 400);
  if (n < 0) throw new AppError(`${field} must be non-negative`, 400);
  if (n > MAX_REPAIR_PRICE) throw new AppError(`${field} must be ${MAX_REPAIR_PRICE} or less`, 400);
  return n;
}

// ==================== Helper: apply global adjustments ====================

async function getAdjustments(adb: AsyncDb): Promise<{ flat: number; pct: number }> {
  const [flatRow, pctRow] = await Promise.all([
    adb.get<any>("SELECT value FROM store_config WHERE key = 'repair_price_flat_adjustment'"),
    adb.get<any>("SELECT value FROM store_config WHERE key = 'repair_price_pct_adjustment'"),
  ]);
  // SEC-M37: guard against non-finite / oversized config values (e.g.
  // NaN, Infinity, 1e308). parseFloat returns Infinity for "1e308" and
  // the downstream `price * (1 + pct/100)` silently wraps to Infinity
  // which then rounds to MAX_VALUE — a DoS primitive for any path that
  // feeds this into invoice totals.
  const safeNum = (raw: unknown): number => {
    if (raw === null || raw === undefined) return 0;
    const n = typeof raw === 'number' ? raw : parseFloat(String(raw));
    return Number.isFinite(n) ? n : 0;
  };
  return {
    flat: flatRow ? safeNum(flatRow.value) : 0,
    pct: pctRow ? safeNum(pctRow.value) : 0,
  };
}

function applyAdjustment(basePrice: number, adj: { flat: number; pct: number }): number {
  let price = basePrice;
  if (adj.pct !== 0) price = price * (1 + adj.pct / 100);
  if (adj.flat !== 0) price = price + adj.flat;
  return Math.round(price * 100) / 100;
}

// ==================== Repair Services CRUD ====================

// @audit-fixed: §37 — wrap GET in asyncHandler so a thrown rejection becomes
// a clean 500 instead of an unhandled promise that hangs the request.
router.get('/services', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const { category } = _req.query;
  let sql = 'SELECT * FROM repair_services';
  const params: any[] = [];
  if (category) {
    sql += ' WHERE category = ?';
    params.push(category);
  }
  sql += ' ORDER BY category ASC, sort_order ASC';
  const services = await adb.all(sql, ...params);
  res.json({ success: true, data: services });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + audit
router.post('/services', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { name, slug, category, description, is_active = 1, sort_order = 0 } = req.body;
  if (!name || !slug) throw new AppError('Name and slug are required', 400);

  const existing = await adb.get('SELECT id FROM repair_services WHERE slug = ?', slug);
  if (existing) throw new AppError('A service with this slug already exists', 400);

  const result = await adb.run(`
    INSERT INTO repair_services (name, slug, category, description, is_active, sort_order)
    VALUES (?, ?, ?, ?, ?, ?)
  `, name, slug, category || null, description || null, is_active, sort_order);

  const service = await adb.get('SELECT * FROM repair_services WHERE id = ?', result.lastInsertRowid);
  audit(req.db, 'repair_service_created', req.user!.id, req.ip || 'unknown', { service_id: Number(result.lastInsertRowid), name, slug });
  res.status(201).json({ success: true, data: service });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + audit
router.put('/services/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { name, slug, category, description, is_active, sort_order } = req.body;
  const existing = await adb.get('SELECT id FROM repair_services WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Service not found', 404);

  if (slug) {
    const dup = await adb.get('SELECT id FROM repair_services WHERE slug = ? AND id != ?', slug, req.params.id);
    if (dup) throw new AppError('A service with this slug already exists', 400);
  }

  await adb.run(`
    UPDATE repair_services SET
      name = COALESCE(?, name), slug = COALESCE(?, slug), category = COALESCE(?, category),
      description = COALESCE(?, description), is_active = COALESCE(?, is_active),
      sort_order = COALESCE(?, sort_order), updated_at = datetime('now')
    WHERE id = ?
  `, name ?? null, slug ?? null, category ?? null, description ?? null,
    is_active ?? null, sort_order ?? null, req.params.id);

  const service = await adb.get('SELECT * FROM repair_services WHERE id = ?', req.params.id);
  audit(req.db, 'repair_service_updated', req.user!.id, req.ip || 'unknown', { service_id: Number(req.params.id) });
  res.json({ success: true, data: service });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + existence check + audit.
// Previous code returned 200 even when the service didn't exist; we now 404.
router.delete('/services/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM repair_services WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Service not found', 404);
  const inUse = await adb.get<any>('SELECT COUNT(*) as c FROM repair_prices WHERE repair_service_id = ?', req.params.id);
  if (inUse && inUse.c > 0) throw new AppError('Service is in use by repair prices', 400);
  await adb.run('DELETE FROM repair_services WHERE id = ?', req.params.id);
  audit(req.db, 'repair_service_deleted', req.user!.id, req.ip || 'unknown', { service_id: Number(req.params.id) });
  res.json({ success: true, data: { message: 'Service deleted' } });
}));

// ==================== Repair Prices CRUD ====================

router.get('/prices', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { device_model_id, repair_service_id, category } = req.query;
  let sql = `
    SELECT rp.*, dm.name as device_model_name, m.name as manufacturer_name,
           rs.name as repair_service_name, rs.slug as repair_service_slug, rs.category as service_category,
           (SELECT COUNT(*) FROM repair_price_grades WHERE repair_price_id = rp.id) as grade_count
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    JOIN manufacturers m ON m.id = dm.manufacturer_id
    JOIN repair_services rs ON rs.id = rp.repair_service_id
    WHERE 1=1
  `;
  const params: any[] = [];

  if (device_model_id) {
    sql += ' AND rp.device_model_id = ?';
    params.push(device_model_id);
  }
  if (repair_service_id) {
    sql += ' AND rp.repair_service_id = ?';
    params.push(repair_service_id);
  }
  if (category) {
    sql += ' AND rs.category = ?';
    params.push(category);
  }

  sql += ' ORDER BY m.name ASC, dm.name ASC, rs.sort_order ASC';
  const prices = await adb.all(sql, ...params);
  res.json({ success: true, data: prices });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + price validation +
// audit. Previously labor_price could be -50 or $1e9 and any technician could
// rewrite the catalogue.
router.post('/prices', adminOrManager, asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { device_model_id, repair_service_id, labor_price = 0, default_grade = 'aftermarket', is_active = 1, grades } = req.body;
  if (!device_model_id || !repair_service_id) throw new AppError('device_model_id and repair_service_id are required', 400);

  const validatedLabor = validatePriceField('labor_price', labor_price) ?? 0;

  const existing = await adb.get('SELECT id FROM repair_prices WHERE device_model_id = ? AND repair_service_id = ?',
    device_model_id, repair_service_id);
  if (existing) throw new AppError('A price already exists for this device model and service', 400);

  const priceResult = await adb.run(`
    INSERT INTO repair_prices (device_model_id, repair_service_id, labor_price, default_grade, is_active)
    VALUES (?, ?, ?, ?, ?)
  `, device_model_id, repair_service_id, validatedLabor, default_grade, is_active);

  const priceId = priceResult.lastInsertRowid;

  if (grades && Array.isArray(grades)) {
    for (const g of grades) {
      // @audit-fixed: §37 — bound part_price + labor_price_override per grade
      const validatedPartPrice = validatePriceField('part_price', g.part_price) ?? 0;
      const validatedOverride = validatePriceField('labor_price_override', g.labor_price_override);
      await adb.run(`
        INSERT INTO repair_price_grades (repair_price_id, grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price, labor_price_override, is_default, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `, priceId, g.grade, g.grade_label,
        g.part_inventory_item_id || null, g.part_catalog_item_id || null,
        validatedPartPrice, validatedOverride,
        g.is_default ? 1 : 0, g.sort_order || 0
      );
    }
  }

  const [price, priceGrades] = await Promise.all([
    adb.get(`
      SELECT rp.*, dm.name as device_model_name, m.name as manufacturer_name,
             rs.name as repair_service_name, rs.slug as repair_service_slug, rs.category as service_category
      FROM repair_prices rp
      JOIN device_models dm ON dm.id = rp.device_model_id
      JOIN manufacturers m ON m.id = dm.manufacturer_id
      JOIN repair_services rs ON rs.id = rp.repair_service_id
      WHERE rp.id = ?
    `, priceId),
    adb.all('SELECT * FROM repair_price_grades WHERE repair_price_id = ? ORDER BY sort_order ASC', priceId),
  ]);

  audit(db, 'repair_price_created', req.user!.id, req.ip || 'unknown', { price_id: Number(priceId), device_model_id, repair_service_id });
  res.status(201).json({ success: true, data: { ...price as any, grades: priceGrades } });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + price validation + audit
router.put('/prices/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM repair_prices WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Price not found', 404);

  const { labor_price, default_grade, is_active } = req.body;
  const validatedLabor = validatePriceField('labor_price', labor_price);
  await adb.run(`
    UPDATE repair_prices SET
      labor_price = COALESCE(?, labor_price), default_grade = COALESCE(?, default_grade),
      is_active = COALESCE(?, is_active), updated_at = datetime('now')
    WHERE id = ?
  `, validatedLabor, default_grade ?? null, is_active ?? null, req.params.id);

  const price = await adb.get('SELECT * FROM repair_prices WHERE id = ?', req.params.id);
  audit(req.db, 'repair_price_updated', req.user!.id, req.ip || 'unknown', { price_id: Number(req.params.id) });
  res.json({ success: true, data: price });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + existence check + audit.
// Previous code returned 200 even when the price didn't exist.
router.delete('/prices/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM repair_prices WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Price not found', 404);
  // CASCADE the grades to keep repair_price_grades consistent.
  await adb.run('DELETE FROM repair_price_grades WHERE repair_price_id = ?', req.params.id);
  await adb.run('DELETE FROM repair_prices WHERE id = ?', req.params.id);
  audit(req.db, 'repair_price_deleted', req.user!.id, req.ip || 'unknown', { price_id: Number(req.params.id) });
  res.json({ success: true, data: { message: 'Price deleted' } });
}));

// ==================== Lookup (for check-in wizard) ====================

// @audit-fixed: §37 — wrap in asyncHandler so a thrown rejection doesn't hang.
router.get('/lookup', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { device_model_id, repair_service_id } = req.query;
  if (!device_model_id || !repair_service_id) throw new AppError('device_model_id and repair_service_id are required', 400);

  const price = await adb.get<any>(`
    SELECT rp.*, dm.name as device_model_name, m.name as manufacturer_name,
           rs.name as repair_service_name, rs.slug as repair_service_slug
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    JOIN manufacturers m ON m.id = dm.manufacturer_id
    JOIN repair_services rs ON rs.id = rp.repair_service_id
    WHERE rp.device_model_id = ? AND rp.repair_service_id = ?
  `, device_model_id, repair_service_id);

  if (!price) {
    res.json({ success: true, data: null });
    return;
  }

  const [grades, adj] = await Promise.all([
    adb.all<any>(`
      SELECT rpg.*,
             ii.name as inventory_item_name, ii.in_stock as inventory_in_stock, ii.price as inventory_price,
             sc.name as catalog_item_name, sc.price as catalog_price, sc.url as catalog_url
      FROM repair_price_grades rpg
      LEFT JOIN inventory_items ii ON ii.id = rpg.part_inventory_item_id
      LEFT JOIN supplier_catalog sc ON sc.id = rpg.part_catalog_item_id
      WHERE rpg.repair_price_id = ?
      ORDER BY rpg.sort_order ASC
    `, price.id),
    getAdjustments(adb),
  ]);
  const adjustedLaborPrice = applyAdjustment(price.labor_price, adj);

  const adjustedGrades = (grades as any[]).map((g: any) => ({
    ...g,
    effective_labor_price: g.labor_price_override != null
      ? applyAdjustment(g.labor_price_override, adj)
      : adjustedLaborPrice,
  }));

  res.json({
    success: true,
    data: {
      ...price,
      base_labor_price: price.labor_price,
      labor_price: adjustedLaborPrice,
      adjustments: adj,
      grades: adjustedGrades,
    },
  });
}));

// ==================== Grade Management ====================

// @audit-fixed: §37 — wrap in asyncHandler
router.get('/prices/:id/grades', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const priceExists = await adb.get('SELECT id FROM repair_prices WHERE id = ?', req.params.id);
  if (!priceExists) throw new AppError('Price not found', 404);

  const grades = await adb.all(`
    SELECT rpg.*,
           ii.name as inventory_item_name, ii.in_stock as inventory_in_stock,
           sc.name as catalog_item_name, sc.url as catalog_url
    FROM repair_price_grades rpg
    LEFT JOIN inventory_items ii ON ii.id = rpg.part_inventory_item_id
    LEFT JOIN supplier_catalog sc ON sc.id = rpg.part_catalog_item_id
    WHERE rpg.repair_price_id = ?
    ORDER BY rpg.sort_order ASC
  `, req.params.id);

  res.json({ success: true, data: grades });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + price validation + audit
router.post('/prices/:id/grades', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const priceExists = await adb.get('SELECT id FROM repair_prices WHERE id = ?', req.params.id);
  if (!priceExists) throw new AppError('Price not found', 404);

  const { grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price = 0, labor_price_override, is_default = 0, sort_order = 0 } = req.body;
  if (!grade || !grade_label) throw new AppError('grade and grade_label are required', 400);

  const validatedPart = validatePriceField('part_price', part_price) ?? 0;
  const validatedOverride = validatePriceField('labor_price_override', labor_price_override);

  const result = await adb.run(`
    INSERT INTO repair_price_grades (repair_price_id, grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price, labor_price_override, is_default, sort_order)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, req.params.id, grade, grade_label, part_inventory_item_id || null, part_catalog_item_id || null,
    validatedPart, validatedOverride, is_default ? 1 : 0, sort_order);

  const gradeRow = await adb.get('SELECT * FROM repair_price_grades WHERE id = ?', result.lastInsertRowid);
  audit(req.db, 'repair_grade_created', req.user!.id, req.ip || 'unknown', { grade_id: Number(result.lastInsertRowid), price_id: Number(req.params.id) });
  res.status(201).json({ success: true, data: gradeRow });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + price validation + audit
router.put('/grades/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM repair_price_grades WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Grade not found', 404);

  const { grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price, labor_price_override, is_default, sort_order } = req.body;
  const validatedPart = validatePriceField('part_price', part_price);
  const validatedOverride = validatePriceField('labor_price_override', labor_price_override);
  await adb.run(`
    UPDATE repair_price_grades SET
      grade = COALESCE(?, grade), grade_label = COALESCE(?, grade_label),
      part_inventory_item_id = COALESCE(?, part_inventory_item_id),
      part_catalog_item_id = COALESCE(?, part_catalog_item_id),
      part_price = COALESCE(?, part_price), labor_price_override = ?,
      is_default = COALESCE(?, is_default), sort_order = COALESCE(?, sort_order)
    WHERE id = ?
  `, grade ?? null, grade_label ?? null, part_inventory_item_id ?? null,
    part_catalog_item_id ?? null, validatedPart,
    labor_price_override !== undefined ? validatedOverride : null,
    is_default ?? null, sort_order ?? null, req.params.id);

  const gradeRow = await adb.get('SELECT * FROM repair_price_grades WHERE id = ?', req.params.id);
  audit(req.db, 'repair_grade_updated', req.user!.id, req.ip || 'unknown', { grade_id: Number(req.params.id) });
  res.json({ success: true, data: gradeRow });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + existence check + audit
router.delete('/grades/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM repair_price_grades WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Grade not found', 404);
  await adb.run('DELETE FROM repair_price_grades WHERE id = ?', req.params.id);
  audit(req.db, 'repair_grade_deleted', req.user!.id, req.ip || 'unknown', { grade_id: Number(req.params.id) });
  res.json({ success: true, data: { message: 'Grade deleted' } });
}));

// ==================== Global Adjustments ====================

// @audit-fixed: §37 — wrap in asyncHandler
router.get('/adjustments', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const adj = await getAdjustments(adb);
  res.json({ success: true, data: adj });
}));

// @audit-fixed: §37 — wrap in asyncHandler + audit (already adminOnly).
// Validate flat/pct so an admin can't accidentally store NaN/Infinity in
// store_config and break every lookup downstream.
router.put('/adjustments', adminOnly, asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { flat, pct } = req.body;
  if (flat !== undefined) {
    const n = Number(flat);
    if (!Number.isFinite(n) || n < -10_000 || n > 10_000) {
      throw new AppError('flat must be a finite number between -10000 and 10000', 400);
    }
  }
  if (pct !== undefined) {
    const n = Number(pct);
    // SEC-H46: cap pct_adjustment at ±50% to prevent runaway markups.
    // 1000% was theoretically allowed before — an admin with a fat finger
    // or a compromised session could 11x every repair price in one PUT.
    // Adjustments >±20% require a paper-trail signal: we accept 20 < |n|
    // <= 50 only when `confirm_large_adjustment: true` is in the body,
    // forcing a UI confirmation step. Values outside ±50% reject outright.
    if (!Number.isFinite(n) || n < -50 || n > 50) {
      throw new AppError('pct must be a finite number between -50 and 50', 400);
    }
    if (Math.abs(n) > 20 && req.body?.confirm_large_adjustment !== true) {
      throw new AppError(
        `pct adjustment of ${n}% exceeds 20% safety threshold; resubmit with confirm_large_adjustment: true`,
        400,
      );
    }
  }
  const adjQueries: Array<{ sql: string; params: unknown[] }> = [];
  if (flat !== undefined) adjQueries.push({ sql: 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', params: ['repair_price_flat_adjustment', String(flat)] });
  if (pct !== undefined) adjQueries.push({ sql: 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', params: ['repair_price_pct_adjustment', String(pct)] });
  if (adjQueries.length > 0) await adb.transaction(adjQueries);
  const adj = await getAdjustments(adb);
  audit(db, 'repair_adjustments_updated', req.user!.id, req.ip || 'unknown', { flat: flat ?? undefined, pct: pct ?? undefined });
  res.json({ success: true, data: adj });
}));

export default router;
