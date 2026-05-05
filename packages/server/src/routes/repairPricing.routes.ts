import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';
import { ERROR_CODES } from '../utils/errorCodes.js';
import {
  bulkApplyTier,
  getTierThresholds,
  parsePricingTier,
  pricingTierDescriptors,
  revertPriceToTier,
  setTierThresholds,
  tierForReleaseYear,
  tierLabel,
  type PricingTier,
} from '../services/repairPricing/tierResolver.js';
import { recomputeRepairPriceProfits } from '../services/repairPricing/profitRecompute.js';
import {
  getAutoMarginSettings,
  previewAutoMargin,
  runAutoMargin,
  setAutoMarginSettings,
} from '../services/repairPricing/autoMargin.js';
import { seedRepairPricingDefaults } from '../services/repairPricing/seedDefaults.js';
import {
  runNightlyRebase,
  getLastRebaseSummary,
  ackRebaseSummary,
} from '../services/repairPricing/nightlyRebase.js';
import {
  getActiveMarginAlerts,
  getMarginAlertSummary,
  ackMarginAlert,
} from '../services/repairPricing/marginAlerts.js';

const router = Router();

// Admin-only middleware for mutating global pricing adjustments
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
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

function parseBoolish(value: unknown, fallback = false): boolean {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
  return fallback;
}

function parsePositiveInt(value: unknown, field: string): number | null {
  if (value === undefined || value === null || value === '') return null;
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw new AppError(`${field} must be a positive integer`, 400);
  return n;
}

function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

function clampLimit(value: unknown, fallback = 250, max = 1000): number {
  if (value === undefined || value === null || value === '') return fallback;
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw new AppError('limit must be a positive integer', 400);
  return Math.min(n, max);
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

// ==================== Dynamic Repair-Pricing Matrix ====================

router.get('/tiers', asyncHandler(async (req, res) => {
  const thresholds = getTierThresholds(req.db);
  const devices = await req.asyncDb.all<{ release_year: number | null }>('SELECT release_year FROM device_models');
  const counts: Record<PricingTier, number> = { tier_a: 0, tier_b: 0, tier_c: 0, unknown: 0 };
  for (const device of devices) {
    counts[tierForReleaseYear(device.release_year, thresholds)] += 1;
  }

  res.json({
    success: true,
    data: {
      thresholds,
      tiers: pricingTierDescriptors(thresholds).map((tier) => ({
        ...tier,
        device_count: counts[tier.key],
      })),
    },
  });
}));

router.put('/tiers', adminOrManager, asyncHandler(async (req, res) => {
  const tierAYears = Number(req.body?.tier_a_years ?? req.body?.tierAYears);
  const tierBYears = Number(req.body?.tier_b_years ?? req.body?.tierBYears);
  if (!Number.isFinite(tierAYears) || !Number.isFinite(tierBYears)) {
    throw new AppError('tier_a_years and tier_b_years are required numbers', 400);
  }
  if (tierAYears < 0 || tierBYears < 0 || tierAYears > 50 || tierBYears > 50 || tierBYears < tierAYears) {
    throw new AppError('Tier windows must be 0-50 years and tier_b_years must be >= tier_a_years', 400);
  }

  const thresholds = setTierThresholds(req.db, {
    tierAYears: Math.trunc(tierAYears),
    tierBYears: Math.trunc(tierBYears),
  });
  audit(req.db, 'repair_pricing_tiers_updated', req.user!.id, req.ip || 'unknown', { ...thresholds });
  res.json({ success: true, data: { thresholds, tiers: pricingTierDescriptors(thresholds) } });
}));

router.get('/matrix', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const thresholds = getTierThresholds(req.db);
  const { category, q } = req.query as { category?: string; q?: string };
  const manufacturerId = parsePositiveInt(req.query.manufacturer_id, 'manufacturer_id');
  const repairServiceId = parsePositiveInt(req.query.repair_service_id, 'repair_service_id');
  const limit = clampLimit(req.query.limit);

  const serviceParams: unknown[] = [];
  let serviceSql = 'SELECT * FROM repair_services WHERE is_active = 1';
  if (category) {
    serviceSql += ' AND category = ?';
    serviceParams.push(category);
  }
  if (repairServiceId) {
    serviceSql += ' AND id = ?';
    serviceParams.push(repairServiceId);
  }
  serviceSql += ' ORDER BY category ASC, sort_order ASC, name ASC';

  const deviceWhere: string[] = [];
  const deviceParams: unknown[] = [];
  if (category) {
    deviceWhere.push('dm.category = ?');
    deviceParams.push(category);
  }
  if (manufacturerId) {
    deviceWhere.push('dm.manufacturer_id = ?');
    deviceParams.push(manufacturerId);
  }
  if (q && q.trim().length > 0) {
    deviceWhere.push("(LOWER(dm.name) LIKE ? ESCAPE '\\' OR LOWER(m.name) LIKE ? ESCAPE '\\')");
    const like = `%${escapeLike(q.trim().toLowerCase())}%`;
    deviceParams.push(like, like);
  }

  const [services, devices] = await Promise.all([
    adb.all<any>(serviceSql, ...serviceParams),
    adb.all<any>(`
      SELECT dm.id, dm.name, dm.slug, dm.category, dm.release_year, dm.is_popular,
             m.id AS manufacturer_id, m.name AS manufacturer_name
      FROM device_models dm
      JOIN manufacturers m ON m.id = dm.manufacturer_id
      ${deviceWhere.length ? `WHERE ${deviceWhere.join(' AND ')}` : ''}
      ORDER BY m.name ASC, dm.release_year DESC, dm.name ASC
      LIMIT ?
    `, ...deviceParams, limit),
  ]);

  if (devices.length === 0 || services.length === 0) {
    res.json({ success: true, data: { thresholds, services, devices: [] } });
    return;
  }

  const deviceIds = devices.map((device: any) => device.id);
  const serviceIds = services.map((service: any) => service.id);
  const priceRows = await adb.all<any>(`
    SELECT rp.*
    FROM repair_prices rp
    WHERE rp.device_model_id IN (${deviceIds.map(() => '?').join(',')})
      AND rp.repair_service_id IN (${serviceIds.map(() => '?').join(',')})
  `, ...deviceIds, ...serviceIds);

  const priceByPair = new Map<string, any>();
  for (const price of priceRows) {
    priceByPair.set(`${price.device_model_id}:${price.repair_service_id}`, price);
  }

  const matrixDevices = devices.map((device: any) => {
    const tier = tierForReleaseYear(device.release_year, thresholds);
    return {
      device_model_id: device.id,
      device_model_name: device.name,
      device_model_slug: device.slug,
      manufacturer_id: device.manufacturer_id,
      manufacturer_name: device.manufacturer_name,
      category: device.category,
      release_year: device.release_year,
      tier,
      tier_label: tierLabel(tier),
      is_popular: device.is_popular,
      prices: services.map((service: any) => {
        const price = priceByPair.get(`${device.id}:${service.id}`);
        return {
          repair_service_id: service.id,
          repair_service_name: service.name,
          repair_service_slug: service.slug,
          service_category: service.category,
          price_id: price?.id ?? null,
          labor_price: price?.labor_price ?? null,
          default_grade: price?.default_grade ?? null,
          is_active: price?.is_active ?? null,
          is_custom: price?.is_custom ?? 0,
          tier_label: price?.tier_label ?? tier,
          profit_estimate: price?.profit_estimate ?? null,
          profit_stale_at: price?.profit_stale_at ?? null,
          auto_margin_enabled: price?.auto_margin_enabled ?? 0,
          last_supplier_cost: price?.last_supplier_cost ?? null,
          last_supplier_seen_at: price?.last_supplier_seen_at ?? null,
          suggested_labor_price: price?.suggested_labor_price ?? null,
          updated_at: price?.updated_at ?? null,
        };
      }),
    };
  });

  res.json({
    success: true,
    data: {
      thresholds,
      services,
      devices: matrixDevices,
    },
  });
}));

router.post('/seed-defaults', adminOrManager, asyncHandler(async (req, res) => {
  const category = typeof req.body?.category === 'string' && req.body.category.trim()
    ? req.body.category.trim()
    : 'phone';

  try {
    const result = seedRepairPricingDefaults(req.db, {
      category,
      pricing: req.body?.pricing,
      overwriteCustom: parseBoolish(req.body?.overwrite_custom),
      changedByUserId: req.user!.id,
    });
    audit(req.db, 'repair_pricing_seed_defaults', req.user!.id, req.ip || 'unknown', {
      category: result.category,
      ...result.summary,
    });
    res.json({ success: true, data: result });
  } catch (err) {
    if (err instanceof Error && /labor price|Invalid/i.test(err.message)) {
      throw new AppError(err.message, 400);
    }
    throw err;
  }
}));

router.post('/tier-apply', adminOrManager, asyncHandler(async (req, res) => {
  const repairServiceId = parsePositiveInt(req.body?.repair_service_id, 'repair_service_id');
  const tier = parsePricingTier(req.body?.tier);
  const laborPrice = validatePriceField('labor_price', req.body?.labor_price);
  if (!repairServiceId || !tier || laborPrice == null) {
    throw new AppError('repair_service_id, tier, and labor_price are required', 400);
  }
  if (tier === 'unknown') throw new AppError('Cannot bulk-apply an unknown tier', 400);

  const service = req.db.prepare('SELECT id FROM repair_services WHERE id = ?').get(repairServiceId);
  if (!service) throw new AppError('Repair service not found', 404);

  const result = bulkApplyTier(req.db, {
    repairServiceId,
    tier,
    laborPrice,
    category: typeof req.body?.category === 'string' && req.body.category.trim() ? req.body.category.trim() : undefined,
    overwriteCustom: parseBoolish(req.body?.overwrite_custom),
    changedByUserId: req.user!.id,
  });
  audit(req.db, 'repair_pricing_tier_applied', req.user!.id, req.ip || 'unknown', { ...result });
  res.json({ success: true, data: result });
}));

router.get('/audit', asyncHandler(async (req, res) => {
  const where: string[] = [];
  const params: unknown[] = [];
  const priceId = parsePositiveInt(req.query.repair_price_id, 'repair_price_id');
  const deviceModelId = parsePositiveInt(req.query.device_model_id, 'device_model_id');
  const repairServiceId = parsePositiveInt(req.query.repair_service_id, 'repair_service_id');
  const limit = clampLimit(req.query.limit, 100, 500);

  if (priceId) { where.push('rpa.repair_price_id = ?'); params.push(priceId); }
  if (deviceModelId) { where.push('rpa.device_model_id = ?'); params.push(deviceModelId); }
  if (repairServiceId) { where.push('rpa.repair_service_id = ?'); params.push(repairServiceId); }
  if (typeof req.query.from === 'string' && req.query.from.trim()) { where.push('rpa.created_at >= ?'); params.push(req.query.from.trim()); }
  if (typeof req.query.to === 'string' && req.query.to.trim()) { where.push('rpa.created_at <= ?'); params.push(req.query.to.trim()); }

  const rows = await req.asyncDb.all<any>(`
    SELECT rpa.*,
           dm.name AS device_model_name,
           rs.name AS repair_service_name,
           u.username AS changed_by_username
    FROM repair_prices_audit rpa
    LEFT JOIN device_models dm ON dm.id = rpa.device_model_id
    LEFT JOIN repair_services rs ON rs.id = rpa.repair_service_id
    LEFT JOIN users u ON u.id = rpa.changed_by_user_id
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY rpa.created_at DESC, rpa.id DESC
    LIMIT ?
  `, ...params, limit);
  res.json({ success: true, data: rows });
}));

router.post('/revert/:id', adminOrManager, asyncHandler(async (req, res) => {
  const priceId = parsePositiveInt(req.params.id, 'id');
  try {
    const result = revertPriceToTier(req.db, priceId!, req.user!.id);
    audit(req.db, 'repair_pricing_price_reverted', req.user!.id, req.ip || 'unknown', {
      price_id: priceId,
      tier: result.tier,
      default_source: result.default_source,
    });
    res.json({ success: true, data: result });
  } catch (err) {
    if (err instanceof Error && err.message === 'Price not found') {
      throw new AppError('Price not found', 404);
    }
    throw err;
  }
}));

router.get('/auto-margin-settings', asyncHandler(async (req, res) => {
  res.json({ success: true, data: getAutoMarginSettings(req.db) });
}));

router.put('/auto-margin-settings', adminOrManager, asyncHandler(async (req, res) => {
  const settings = setAutoMarginSettings(req.db, {
    preset: req.body?.preset,
    target_type: req.body?.target_type,
    target_margin_pct: req.body?.target_margin_pct,
    target_profit_amount: req.body?.target_profit_amount,
    calculation_basis: req.body?.calculation_basis,
    rounding_mode: req.body?.rounding_mode,
    cap_pct: req.body?.cap_pct,
    rules: req.body?.rules,
  });
  audit(req.db, 'repair_pricing_auto_margin_settings_updated', req.user!.id, req.ip || 'unknown', { ...settings });
  res.json({ success: true, data: settings });
}));

router.post('/auto-margin-preview', adminOrManager, asyncHandler(async (req, res) => {
  const supplierCost = Number(req.body?.supplier_cost);
  if (!Number.isFinite(supplierCost) || supplierCost < 0) {
    throw new AppError('supplier_cost must be a non-negative number', 400);
  }
  const currentLaborPrice = req.body?.current_labor_price === undefined || req.body?.current_labor_price === null
    ? undefined
    : Number(req.body.current_labor_price);
  if (currentLaborPrice !== undefined && (!Number.isFinite(currentLaborPrice) || currentLaborPrice < 0)) {
    throw new AppError('current_labor_price must be a non-negative number', 400);
  }

  const preview = previewAutoMargin({
    supplier_cost: supplierCost,
    current_labor_price: currentLaborPrice,
    target_margin_pct: req.body?.target_margin_pct,
    target_type: req.body?.target_type,
    target_profit_amount: req.body?.target_profit_amount,
    calculation_basis: req.body?.calculation_basis,
    rounding_mode: req.body?.rounding_mode,
    cap_pct: req.body?.cap_pct,
    rule: req.body?.rule,
  }, getAutoMarginSettings(req.db));
  res.json({ success: true, data: preview });
}));

router.post('/recompute-profits', adminOrManager, asyncHandler(async (req, res) => {
  const rawIds = Array.isArray(req.body?.price_ids) ? req.body.price_ids : undefined;
  const priceIds = rawIds
    ?.map((id: unknown) => Number(id))
    .filter((id: number) => Number.isInteger(id) && id > 0)
    .slice(0, 1000);
  const recompute = recomputeRepairPriceProfits(req.db, { priceIds });
  const autoMargin = parseBoolish(req.body?.auto_margin) ? runAutoMargin(req.db) : null;
  audit(req.db, 'repair_pricing_profit_recomputed', req.user!.id, req.ip || 'unknown', {
    processed: recompute.processed,
    updated: recompute.updated,
    stale: recompute.stale,
    auto_margin_adjusted: autoMargin?.adjusted ?? 0,
  });
  res.json({ success: true, data: { recompute, auto_margin: autoMargin } });
}));

// ==================== Nightly Rebase ====================

router.get('/rebase-summary', asyncHandler(async (req, res) => {
  const summary = getLastRebaseSummary(req.db);
  res.json({ success: true, data: summary });
}));

router.post('/rebase-ack', adminOrManager, asyncHandler(async (req, res) => {
  ackRebaseSummary(req.db);
  audit(req.db, 'repair_pricing_rebase_acked', req.user!.id, req.ip || 'unknown', {});
  res.json({ success: true });
}));

router.post('/rebase-run', adminOnly, asyncHandler(async (req, res) => {
  const result = runNightlyRebase(req.db);
  audit(req.db, 'repair_pricing_rebase_manual', req.user!.id, req.ip || 'unknown', {
    evaluated: result.evaluated,
    rebased: result.rebased,
    crossing_count: result.crossing_count,
  });
  res.json({ success: true, data: result });
}));

// ==================== Margin Alerts ====================

router.get('/margin-alerts', asyncHandler(async (req, res) => {
  const limit = clampLimit(req.query.limit, 100, 500);
  const minDays = Number(req.query.min_days) || 0;
  const alerts = getActiveMarginAlerts(req.db, { limit, minDays });
  res.json({ success: true, data: alerts });
}));

router.get('/margin-alerts/summary', asyncHandler(async (req, res) => {
  const summary = getMarginAlertSummary(req.db);
  res.json({ success: true, data: summary });
}));

router.post('/margin-alerts/:id/ack', adminOrManager, asyncHandler(async (req, res) => {
  const alertId = parsePositiveInt(req.params.id, 'id');
  if (!alertId) throw new AppError('id is required', 400);
  const updated = ackMarginAlert(req.db, alertId);
  if (!updated) throw new AppError('Alert not found or already resolved', 404);
  audit(req.db, 'margin_alert_acked', req.user!.id, req.ip || 'unknown', { alert_id: alertId });
  res.json({ success: true });
}));

router.post('/unpause-auto-margin/:id', adminOrManager, asyncHandler(async (req, res) => {
  const priceId = parsePositiveInt(req.params.id, 'id');
  if (!priceId) throw new AppError('id is required', 400);
  const existing = req.db.prepare('SELECT id, auto_margin_paused_at FROM repair_prices WHERE id = ?').get(priceId) as { id: number; auto_margin_paused_at: string | null } | undefined;
  if (!existing) throw new AppError('Price not found', 404);
  if (!existing.auto_margin_paused_at) throw new AppError('Auto-margin is not paused for this price', 400);
  req.db.prepare('UPDATE repair_prices SET auto_margin_paused_at = NULL, updated_at = datetime(\'now\') WHERE id = ?').run(priceId);
  audit(req.db, 'repair_pricing_auto_margin_unpaused', req.user!.id, req.ip || 'unknown', { price_id: priceId });
  res.json({ success: true });
}));

// ==================== Repair Services CRUD ====================

// @audit-fixed: §37 — wrap GET in asyncHandler so a thrown rejection becomes
// a clean 500 instead of an unhandled promise that hangs the request.
router.get('/services', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const { category, q } = _req.query as { category?: string; q?: string };
  let sql = 'SELECT * FROM repair_services WHERE 1=1';
  const params: any[] = [];
  if (category) {
    sql += ' AND category = ?';
    params.push(category);
  }
  if (q && typeof q === 'string' && q.trim().length > 0) {
    sql += " AND (LOWER(name) LIKE ? OR LOWER(COALESCE(category,'')) LIKE ?)";
    const like = `%${q.trim().toLowerCase()}%`;
    params.push(like, like);
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
  const {
    device_model_id,
    repair_service_id,
    labor_price = req.body?.base_price ?? 0,
    default_grade = 'aftermarket',
    is_active = 1,
    is_custom = 1,
    auto_margin_enabled = 0,
    grades,
  } = req.body;
  if (!device_model_id || !repair_service_id) throw new AppError('device_model_id and repair_service_id are required', 400);

  const validatedLabor = validatePriceField('labor_price', labor_price) ?? 0;
  const device = await adb.get<{ release_year: number | null }>('SELECT release_year FROM device_models WHERE id = ?', device_model_id);
  if (!device) throw new AppError('Device model not found', 404);
  const service = await adb.get('SELECT id FROM repair_services WHERE id = ?', repair_service_id);
  if (!service) throw new AppError('Repair service not found', 404);
  const tier = tierForReleaseYear(device.release_year, getTierThresholds(db));

  const existing = await adb.get('SELECT id FROM repair_prices WHERE device_model_id = ? AND repair_service_id = ?',
    device_model_id, repair_service_id);
  if (existing) throw new AppError('A price already exists for this device model and service', 400);

  const priceResult = await adb.run(`
    INSERT INTO repair_prices (
      device_model_id, repair_service_id, labor_price, default_grade,
      is_active, is_custom, tier_label, auto_margin_enabled
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, device_model_id, repair_service_id, validatedLabor, default_grade, is_active, is_custom ? 1 : 0, tier, auto_margin_enabled ? 1 : 0);

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
  await adb.run(`
    INSERT INTO repair_prices_audit (
      repair_price_id, device_model_id, repair_service_id,
      old_labor_price, new_labor_price, old_is_custom, new_is_custom,
      old_tier_label, new_tier_label, source, changed_by_user_id, note
    )
    VALUES (?, ?, ?, NULL, ?, NULL, ?, NULL, ?, 'manual', ?, ?)
  `, priceId, device_model_id, repair_service_id, validatedLabor, is_custom ? 1 : 0, tier, req.user!.id, 'Manual repair price created');
  res.status(201).json({ success: true, data: { ...price as any, grades: priceGrades } });
}));

// @audit-fixed: §37 — adminOrManager + asyncHandler + price validation + audit
router.put('/prices/:id', adminOrManager, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<any>('SELECT * FROM repair_prices WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Price not found', 404);

  const {
    labor_price = req.body?.base_price,
    default_grade,
    is_active,
    is_custom,
    auto_margin_enabled,
  } = req.body;
  const validatedLabor = validatePriceField('labor_price', labor_price);
  const nextIsCustom = is_custom !== undefined
    ? (is_custom ? 1 : 0)
    : (validatedLabor !== null ? 1 : existing.is_custom ?? 0);
  const nextAutoMargin = auto_margin_enabled !== undefined
    ? (auto_margin_enabled ? 1 : 0)
    : null;
  await adb.run(`
    UPDATE repair_prices SET
      labor_price = COALESCE(?, labor_price), default_grade = COALESCE(?, default_grade),
      is_active = COALESCE(?, is_active), is_custom = COALESCE(?, is_custom),
      auto_margin_enabled = COALESCE(?, auto_margin_enabled), updated_at = datetime('now')
    WHERE id = ?
  `, validatedLabor, default_grade ?? null, is_active ?? null, nextIsCustom, nextAutoMargin, req.params.id);

  const price = await adb.get('SELECT * FROM repair_prices WHERE id = ?', req.params.id);
  audit(req.db, 'repair_price_updated', req.user!.id, req.ip || 'unknown', { price_id: Number(req.params.id) });
  if (validatedLabor !== null || nextIsCustom !== existing.is_custom) {
    await adb.run(`
      INSERT INTO repair_prices_audit (
        repair_price_id, device_model_id, repair_service_id,
        old_labor_price, new_labor_price, old_is_custom, new_is_custom,
        old_tier_label, new_tier_label, source, changed_by_user_id, note
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual', ?, ?)
    `, req.params.id, existing.device_model_id, existing.repair_service_id,
      existing.labor_price, validatedLabor ?? existing.labor_price,
      existing.is_custom ?? 0, nextIsCustom,
      existing.tier_label ?? null, existing.tier_label ?? null,
      req.user!.id, 'Manual repair price updated');
  }
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
