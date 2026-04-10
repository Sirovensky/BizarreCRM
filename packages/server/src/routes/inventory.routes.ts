import { Router } from 'express';
import crypto from 'crypto';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { createCanvas } from 'canvas';
import JsBarcode from 'jsbarcode';
import { AppError } from '../middleware/errorHandler.js';
import { generateOrderId } from '../utils/format.js';
import { broadcast } from '../ws/server.js';
import { validatePrice } from '../utils/validate.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { config } from '../config.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();
const maxLen = (val: string | undefined, max: number) => val && val.length > max ? val.slice(0, max) : val;

// ENR-INV9: Multer setup for inventory image uploads
const ALLOWED_IMAGE_MIMES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const inventoryImageUpload = multer({
  storage: multer.diskStorage({
    destination: (req: any, _file: any, cb: any) => {
      const tenantSlug = req.tenantSlug;
      const dest = tenantSlug
        ? path.join(config.uploadsPath, tenantSlug, 'inventory')
        : path.join(config.uploadsPath, 'inventory');
      if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
      cb(null, dest);
    },
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
      const safe = ext && ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(ext) ? ext : '.jpg';
      cb(null, `inv-${Date.now()}-${crypto.randomBytes(6).toString('hex')}${safe}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_IMAGE_MIMES.includes(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPEG, PNG, WebP, GIF images allowed'));
  },
});

// GET /inventory - list items
router.get('/', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { page = '1', pagesize = '20', keyword, item_type, category, low_stock, reorderable_only, supplier_id, min_price, max_price, hide_out_of_stock, manufacturer, sort_by, sort_order } = req.query as Record<string, string>;
  const p = Math.max(1, parseInt(page, 10) || 1);
  const ps = Math.min(250, Math.max(1, parseInt(pagesize, 10) || 20));
  const offset = (p - 1) * ps;

  let where = 'WHERE i.is_active = 1';
  const params: any[] = [];

  if (item_type) { where += ' AND i.item_type = ?'; params.push(item_type); }
  if (category) { where += ' AND i.category = ?'; params.push(category); }
  if (low_stock === 'true') { where += " AND i.item_type != 'service' AND i.is_reorderable = 1 AND i.in_stock <= i.reorder_level AND i.low_stock_dismissed_at IS NULL"; }
  if (reorderable_only === 'true') { where += ' AND i.is_reorderable = 1'; }
  if (supplier_id) { where += ' AND i.supplier_id = ?'; params.push(parseInt(supplier_id, 10)); }
  if (manufacturer) { where += ' AND i.manufacturer LIKE ?'; params.push(`%${manufacturer}%`); }
  if (min_price) { where += ' AND i.retail_price >= ?'; params.push(parseFloat(min_price)); }
  if (max_price) { where += ' AND i.retail_price <= ?'; params.push(parseFloat(max_price)); }
  if (hide_out_of_stock === 'true') { where += ' AND (i.item_type = "service" OR i.in_stock > 0)'; }

  // Sorting
  const allowedSorts = ['name', 'sku', 'item_type', 'in_stock', 'cost_price', 'retail_price', 'created_at'];
  const safeSortBy = allowedSorts.includes(sort_by) ? `i.${sort_by}` : 'i.name';
  const safeSortOrder = sort_order?.toUpperCase() === 'DESC' ? 'DESC' : 'ASC';
  if (keyword) {
    where += ' AND (i.name LIKE ? OR i.sku LIKE ? OR i.upc LIKE ? OR i.manufacturer LIKE ?)';
    const k = `%${keyword}%`;
    params.push(k, k, k, k);
  }

  const [totalRow, items] = await Promise.all([
    adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM inventory_items i ${where}`, ...params),
    adb.all(`
      SELECT i.*, s.name as supplier_name,
        (SELECT sc.product_url FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(i.name)) AND sc.product_url IS NOT NULL LIMIT 1) AS supplier_url,
        (SELECT sc.source FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(i.name)) AND sc.product_url IS NOT NULL LIMIT 1) AS supplier_source
      FROM inventory_items i
      LEFT JOIN suppliers s ON s.id = i.supplier_id
      ${where}
      ORDER BY ${safeSortBy} ${safeSortOrder}
      LIMIT ? OFFSET ?
    `, ...params, ps, offset),
  ]);
  const total = totalRow!.c;

  res.json({
    success: true,
    data: {
      items,
      pagination: { page: p, per_page: ps, total, total_pages: Math.ceil(total / ps) },
    },
  });
});

// GET /inventory/manufacturers — distinct manufacturer values
router.get('/manufacturers', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const rows = await adb.all<{ manufacturer: string }>(`SELECT DISTINCT manufacturer FROM inventory_items WHERE manufacturer IS NOT NULL AND manufacturer != '' AND is_active = 1 ORDER BY manufacturer`);
  res.json({ success: true, data: { manufacturers: rows.map((r: any) => r.manufacturer) } });
});

// POST /inventory/import-csv — bulk create items from CSV data
// SEC-H8: Admin or manager role required for bulk import operations
router.post('/import-csv', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') throw new AppError('Admin or manager access required', 403);
  const db = req.db;
  const { items } = req.body;
  if (!Array.isArray(items) || items.length === 0) throw new AppError('items array is required', 400);
  if (items.length > 500) throw new AppError('Maximum 500 items per import', 400);

  const results: { created: number; errors: { row: number; error: string }[] } = { created: 0, errors: [] };

  const importItems = db.transaction(() => {
    for (let i = 0; i < items.length; i++) {
      const row = items[i];
      try {
        if (!row.name) { results.errors.push({ row: i + 1, error: 'Name is required' }); continue; }
        const itemType = ['product', 'part', 'service'].includes(row.item_type) ? row.item_type : 'product';

        let sku = row.sku || null;
        if (!sku) {
          const prefix = itemType === 'product' ? 'PRD' : itemType === 'part' ? 'PRT' : 'SVC';
          const lastRow = db.prepare("SELECT MAX(id) as maxId FROM inventory_items").get() as any;
          const nextNum = (lastRow?.maxId ?? 0) + 1 + results.created;
          sku = `${prefix}-${String(nextNum).padStart(5, '0')}`;
        }

        const costPrice = validatePrice(parseFloat(row.cost_price) || 0, `Row ${i + 1} cost_price`);
        const retailPrice = validatePrice(parseFloat(row.retail_price) || 0, `Row ${i + 1} retail_price`);
        const inStock = Math.max(0, parseInt(row.in_stock) || 0);
        const reorderLevel = Math.max(0, parseInt(row.reorder_level) || 0);

        db.prepare(`
          INSERT INTO inventory_items (name, description, item_type, category, manufacturer, sku, cost_price, retail_price, in_stock, reorder_level, supplier_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          row.name, row.description || null, itemType, row.category || null, row.manufacturer || null,
          sku, costPrice, retailPrice,
          inStock, reorderLevel, row.supplier_id ? parseInt(row.supplier_id) : null,
        );
        results.created++;
      } catch (err: any) {
        results.errors.push({ row: i + 1, error: err.message || 'Unknown error' });
      }
    }
  });

  importItems();
  audit(db, 'inventory_csv_imported', req.user!.id, req.ip || 'unknown', { created: results.created, errors: results.errors.length });
  res.json({ success: true, data: results });
});

// POST /inventory/bulk-action — bulk update/delete items
// SEC-H8: Admin or manager role required for bulk operations
router.post('/bulk-action', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') throw new AppError('Admin or manager access required', 403);
  const db = req.db;
  const { item_ids, action, value } = req.body;
  if (!Array.isArray(item_ids) || item_ids.length === 0) throw new AppError('item_ids array required', 400);
  if (!action) throw new AppError('action is required', 400);

  let affected = 0;
  const perform = db.transaction(() => {
    for (const id of item_ids) {
      const item = db.prepare('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1').get(id) as any;
      if (!item) continue;

      if (action === 'delete') {
        db.prepare("UPDATE inventory_items SET is_active = 0, updated_at = datetime('now') WHERE id = ?").run(id);
        affected++;
      } else if (action === 'update_category' && value) {
        db.prepare("UPDATE inventory_items SET category = ?, updated_at = datetime('now') WHERE id = ?").run(value, id);
        affected++;
      } else if (action === 'update_price' && value !== undefined) {
        const pct = parseFloat(value);
        if (isNaN(pct)) continue;
        const newPrice = Math.round(item.retail_price * (1 + pct / 100) * 100) / 100;
        if (newPrice < 0) continue;
        db.prepare("UPDATE inventory_items SET retail_price = ?, updated_at = datetime('now') WHERE id = ?").run(newPrice, id);
        affected++;
      } else if (action === 'update_item_type' && value) {
        if (!['product', 'part', 'service'].includes(value)) continue;
        db.prepare("UPDATE inventory_items SET item_type = ?, updated_at = datetime('now') WHERE id = ?").run(value, id);
        affected++;
      }
    }
  });

  perform();
  audit(db, 'inventory_bulk_action', req.user!.id, req.ip || 'unknown', { action, item_count: item_ids.length, affected });
  res.json({ success: true, data: { affected } });
});

// GET /inventory/low-stock
router.get('/low-stock', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const limit = Math.min(parseInt(req.query.limit as string) || 100, 500);
  const items = await adb.all(`
    SELECT * FROM inventory_items
    WHERE is_active = 1 AND item_type != 'service' AND is_reorderable = 1 AND in_stock <= reorder_level
    ORDER BY in_stock ASC
    LIMIT ?
  `, limit);
  res.json({ success: true, data: { items } });
});

// GET /inventory/summary — Stock value summary
router.get('/summary', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const summary = await adb.get(`
    SELECT
      COUNT(*) AS total_items,
      COUNT(CASE WHEN in_stock > 0 THEN 1 END) AS in_stock_items,
      COUNT(CASE WHEN in_stock <= COALESCE(reorder_level, 0) AND in_stock >= 0 AND item_type != 'service' AND is_reorderable = 1 THEN 1 END) AS low_stock_items,
      COALESCE(SUM(CASE WHEN item_type != 'service' THEN in_stock * retail_price ELSE 0 END), 0) AS total_retail_value,
      COALESCE(SUM(CASE WHEN item_type != 'service' THEN in_stock * cost_price ELSE 0 END), 0) AS total_cost_value,
      COALESCE(SUM(in_stock), 0) AS total_units
    FROM inventory_items WHERE is_active = 1
  `);
  res.json({ success: true, data: summary });
});

// GET /inventory/categories
router.get('/categories', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const rows = await adb.all<{ category: string }>(`SELECT DISTINCT category FROM inventory_items WHERE category IS NOT NULL AND is_active = 1 ORDER BY category`);
  res.json({ success: true, data: { categories: rows.map((r: any) => r.category) } });
});

// ==================== ENR-INV1: Auto-reorder / PO generation ====================

// POST /inventory/auto-reorder — Find low-stock reorderable items, group by supplier, create POs
router.post('/auto-reorder', async (req, res) => {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;

  // Find all items needing reorder: in_stock <= reorder_level, reorder_level > 0, is_reorderable = 1
  const lowStockItems = await adb.all<any>(`
    SELECT i.id, i.name, i.sku, i.in_stock, i.reorder_level, i.desired_stock_level,
           i.cost_price, i.supplier_id, s.name as supplier_name
    FROM inventory_items i
    LEFT JOIN suppliers s ON s.id = i.supplier_id
    WHERE i.is_active = 1
      AND i.in_stock <= i.reorder_level
      AND i.reorder_level > 0
      AND i.is_reorderable = 1
      AND i.supplier_id IS NOT NULL
    ORDER BY i.supplier_id, i.name
  `);

  if (lowStockItems.length === 0) {
    res.json({ success: true, data: { orders_created: 0, items_ordered: 0, orders: [] } });
    return;
  }

  // Group by supplier
  const bySupplier = new Map<number, any[]>();
  for (const item of lowStockItems) {
    const existing = bySupplier.get(item.supplier_id) || [];
    existing.push(item);
    bySupplier.set(item.supplier_id, existing);
  }

  const createdOrders: any[] = [];

  const createPOs = db.transaction(() => {
    for (const [supplierId, items] of bySupplier) {
      // Generate next PO order_id
      const seqRow = db.prepare(
        "SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 4) AS INTEGER)), 0) + 1 as next_num FROM purchase_orders"
      ).get() as any;
      const orderId = generateOrderId('PO', seqRow.next_num);

      let subtotal = 0;
      const poItems: { inventory_item_id: number; quantity_ordered: number; cost_price: number; name: string }[] = [];

      for (const item of items) {
        // desired_stock_level if set, otherwise reorder_level * 2
        const target = item.desired_stock_level > 0 ? item.desired_stock_level : item.reorder_level * 2;
        const qtyNeeded = Math.max(1, target - item.in_stock);
        const lineTotal = qtyNeeded * item.cost_price;
        subtotal += lineTotal;
        poItems.push({
          inventory_item_id: item.id,
          quantity_ordered: qtyNeeded,
          cost_price: item.cost_price,
          name: item.name,
        });
      }

      const result = db.prepare(`
        INSERT INTO purchase_orders (order_id, supplier_id, subtotal, total, notes, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(orderId, supplierId, subtotal, subtotal, 'Auto-generated reorder', req.user!.id);

      const poId = result.lastInsertRowid;
      for (const poItem of poItems) {
        db.prepare(`
          INSERT INTO purchase_order_items (purchase_order_id, inventory_item_id, quantity_ordered, cost_price)
          VALUES (?, ?, ?, ?)
        `).run(poId, poItem.inventory_item_id, poItem.quantity_ordered, poItem.cost_price);
      }

      createdOrders.push({
        id: poId,
        order_id: orderId,
        supplier_id: supplierId,
        supplier_name: items[0].supplier_name,
        subtotal,
        items: poItems.map(i => ({ name: i.name, quantity_ordered: i.quantity_ordered, cost_price: i.cost_price })),
      });
    }
  });

  createPOs();
  audit(db, 'inventory_auto_reorder', req.user!.id, req.ip || 'unknown', { orders_created: createdOrders.length, items_ordered: createdOrders.reduce((sum, o) => sum + o.items.length, 0) });

  const totalItems = createdOrders.reduce((sum, o) => sum + o.items.length, 0);
  res.json({
    success: true,
    data: {
      orders_created: createdOrders.length,
      items_ordered: totalItems,
      orders: createdOrders,
    },
  });
});

// ==================== ENR-INV2: Stock alert digest ====================

// GET /inventory/stock-alerts-summary — Summary of low/out-of-stock items
router.get('/stock-alerts-summary', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;

  const lowStockItems = await adb.all<any>(`
    SELECT i.id, i.name, i.sku, i.in_stock, i.reorder_level, i.supplier_id, s.name as supplier_name
    FROM inventory_items i
    LEFT JOIN suppliers s ON s.id = i.supplier_id
    WHERE i.is_active = 1
      AND i.item_type != 'service'
      AND i.is_reorderable = 1
      AND i.in_stock <= i.reorder_level
    ORDER BY i.in_stock ASC
    LIMIT 200
  `);

  const outOfStock = lowStockItems.filter(i => i.in_stock <= 0);
  const lowButInStock = lowStockItems.filter(i => i.in_stock > 0);

  res.json({
    success: true,
    data: {
      out_of_stock_count: outOfStock.length,
      low_stock_count: lowButInStock.length,
      total_needing_attention: lowStockItems.length,
      items: lowStockItems.map(i => ({
        id: i.id,
        name: i.name,
        sku: i.sku,
        in_stock: i.in_stock,
        reorder_level: i.reorder_level,
        supplier_name: i.supplier_name,
        status: i.in_stock <= 0 ? 'out_of_stock' : 'low_stock',
      })),
    },
  });
});

// ==================== ENR-INV3: Inventory variance analysis ====================

// GET /inventory/variance-report — Monthly stock movement variance analysis
router.get('/variance-report', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const months = parseInt(req.query.months as string) || 6;

  // Get monthly in/out totals per item over the last N months
  const rows = await adb.all<any>(`
    SELECT
      sm.inventory_item_id,
      i.name AS item_name,
      i.sku,
      strftime('%Y-%m', sm.created_at) AS month,
      SUM(CASE WHEN sm.quantity > 0 THEN sm.quantity ELSE 0 END) AS stock_in,
      SUM(CASE WHEN sm.quantity < 0 THEN ABS(sm.quantity) ELSE 0 END) AS stock_out
    FROM stock_movements sm
    JOIN inventory_items i ON i.id = sm.inventory_item_id
    WHERE i.is_active = 1
      AND sm.created_at >= datetime('now', '-' || ? || ' months')
    GROUP BY sm.inventory_item_id, month
    ORDER BY sm.inventory_item_id, month
  `, months);

  // Group by item
  const itemMap = new Map<number, {
    item_name: string; sku: string;
    monthly: { month: string; stock_in: number; stock_out: number; net: number }[];
  }>();

  for (const row of rows) {
    if (!itemMap.has(row.inventory_item_id)) {
      itemMap.set(row.inventory_item_id, {
        item_name: row.item_name,
        sku: row.sku,
        monthly: [],
      });
    }
    const net = row.stock_in - row.stock_out;
    itemMap.get(row.inventory_item_id)!.monthly.push({
      month: row.month,
      stock_in: row.stock_in,
      stock_out: row.stock_out,
      net,
    });
  }

  // Flag items with 3+ months of negative variance
  const flagged: {
    inventory_item_id: number; item_name: string; sku: string;
    negative_months: number; total_months: number;
    monthly_variances: { month: string; stock_in: number; stock_out: number; net: number }[];
    trend: string;
  }[] = [];

  for (const [itemId, data] of itemMap) {
    const negativeMonths = data.monthly.filter(m => m.net < 0).length;
    if (negativeMonths >= 3) {
      // Determine trend from last 3 months
      const recent = data.monthly.slice(-3);
      const recentNets = recent.map(m => m.net);
      let trend = 'declining';
      if (recentNets.length >= 2) {
        const improving = recentNets[recentNets.length - 1] > recentNets[0];
        trend = improving ? 'improving' : 'declining';
      }

      flagged.push({
        inventory_item_id: itemId,
        item_name: data.item_name,
        sku: data.sku,
        negative_months: negativeMonths,
        total_months: data.monthly.length,
        monthly_variances: data.monthly,
        trend,
      });
    }
  }

  // Sort by negative months descending
  flagged.sort((a, b) => b.negative_months - a.negative_months);

  res.json({
    success: true,
    data: {
      period_months: months,
      total_items_analyzed: itemMap.size,
      flagged_items: flagged.length,
      items: flagged,
    },
  });
});

// GET /inventory/barcode/:code
router.get('/barcode/:code', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const item = await adb.get(`SELECT * FROM inventory_items WHERE (sku = ? OR upc = ?) AND is_active = 1`, req.params.code, req.params.code);
  if (!item) throw new AppError('Item not found', 404);
  res.json({ success: true, data: { item } });
});

// ---------------------------------------------------------------------------
// ENR-INV11: Kit/bundle definitions
// ---------------------------------------------------------------------------

// GET /inventory/kits — list all kits
router.get('/kits', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const kits = await adb.all<Record<string, unknown>>(
    `SELECT k.*, COUNT(ki.id) AS item_count
     FROM inventory_kits k
     LEFT JOIN inventory_kit_items ki ON ki.kit_id = k.id
     GROUP BY k.id
     ORDER BY k.name`,
  );
  res.json({ success: true, data: kits });
});

// POST /inventory/kits — create kit with items
router.post('/kits', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager')
    throw new AppError('Admin or manager access required', 403);

  const db = req.db;
  const { name, description, items } = req.body;
  if (!name || typeof name !== 'string' || !name.trim())
    throw new AppError('Kit name is required', 400);
  if (!Array.isArray(items) || items.length === 0)
    throw new AppError('At least one item is required', 400);

  const createKit = db.transaction(() => {
    const result = db.prepare(
      `INSERT INTO inventory_kits (name, description) VALUES (?, ?)`,
    ).run(name.trim(), description || null);

    const kitId = Number(result.lastInsertRowid);

    for (const item of items) {
      const invId = parseInt(item.inventory_item_id, 10);
      const qty = Math.max(1, parseInt(item.quantity, 10) || 1);
      if (!invId) continue;

      // Verify item exists
      const exists = db.prepare(
        'SELECT id FROM inventory_items WHERE id = ? AND is_active = 1',
      ).get(invId);
      if (!exists) throw new AppError(`Inventory item ${invId} not found`, 404);

      db.prepare(
        `INSERT INTO inventory_kit_items (kit_id, inventory_item_id, quantity) VALUES (?, ?, ?)`,
      ).run(kitId, invId, qty);
    }

    return kitId;
  });

  const kitId = createKit();
  audit(db, 'inventory_kit_created', req.user!.id, req.ip || 'unknown', { kit_id: kitId, name: name.trim(), item_count: items.length });

  const kit = db.prepare('SELECT * FROM inventory_kits WHERE id = ?').get(kitId);
  const kitItems = db.prepare(
    `SELECT ki.*, i.name AS item_name, i.sku, i.retail_price, i.cost_price
     FROM inventory_kit_items ki
     JOIN inventory_items i ON i.id = ki.inventory_item_id
     WHERE ki.kit_id = ?`,
  ).all(kitId);

  res.status(201).json({ success: true, data: { ...kit as Record<string, unknown>, items: kitItems } });
});

// GET /inventory/kits/:id — get kit with items
router.get('/kits/:id', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const kitId = parseInt(req.params.id, 10);
  if (!kitId) throw new AppError('Invalid kit ID', 400);

  const kit = await adb.get<Record<string, unknown>>(
    'SELECT * FROM inventory_kits WHERE id = ?', kitId,
  );
  if (!kit) throw new AppError('Kit not found', 404);

  const items = await adb.all<Record<string, unknown>>(
    `SELECT ki.*, i.name AS item_name, i.sku, i.retail_price, i.cost_price, i.in_stock
     FROM inventory_kit_items ki
     JOIN inventory_items i ON i.id = ki.inventory_item_id
     WHERE ki.kit_id = ?`,
    kitId,
  );

  res.json({ success: true, data: { ...kit, items } });
});

// DELETE /inventory/kits/:id — delete kit
router.delete('/kits/:id', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager')
    throw new AppError('Admin or manager access required', 403);

  const db = req.db;
  const kitId = parseInt(req.params.id, 10);
  if (!kitId) throw new AppError('Invalid kit ID', 400);

  const kit = db.prepare('SELECT id FROM inventory_kits WHERE id = ?').get(kitId);
  if (!kit) throw new AppError('Kit not found', 404);

  const deleteKit = db.transaction(() => {
    db.prepare('DELETE FROM inventory_kit_items WHERE kit_id = ?').run(kitId);
    db.prepare('DELETE FROM inventory_kits WHERE id = ?').run(kitId);
  });

  deleteKit();
  audit(db, 'inventory_kit_deleted', req.user!.id, req.ip || 'unknown', { kit_id: kitId });

  res.json({ success: true, data: { message: 'Kit deleted' } });
});

// GET /inventory/:id (must be numeric — skip for named routes like /suppliers, /purchase-orders)
router.get('/:id', async (req, res, next) => {
  const adb: AsyncDb = req.asyncDb;
  if (!/^\d+$/.test(req.params.id)) return next();

  const [item, movements, groupPrices] = await Promise.all([
    adb.get(`
      SELECT i.*, s.name as supplier_name
      FROM inventory_items i
      LEFT JOIN suppliers s ON s.id = i.supplier_id
      WHERE i.id = ? AND i.is_active = 1
    `, req.params.id),
    adb.all(`
      SELECT sm.*, u.first_name || ' ' || u.last_name as user_name
      FROM stock_movements sm
      LEFT JOIN users u ON u.id = sm.user_id
      WHERE sm.inventory_item_id = ?
      ORDER BY sm.created_at DESC
      LIMIT 50
    `, req.params.id),
    adb.all(`
      SELECT gp.*, cg.name as group_name
      FROM inventory_group_prices gp
      JOIN customer_groups cg ON cg.id = gp.customer_group_id
      WHERE gp.inventory_item_id = ?
    `, req.params.id),
  ]);
  if (!item) throw new AppError('Item not found', 404);

  res.json({ success: true, data: { item, movements, group_prices: groupPrices } });
});

// ==================== ENR-INV8: Barcode generation ====================

// GET /inventory/:id/barcode — Generate barcode image (PNG) for item's SKU or UPC
router.get('/:id/barcode', async (req, res, next) => {
  if (!/^\d+$/.test(req.params.id)) return next();
  const adb: AsyncDb = req.asyncDb;
  const item = await adb.get<any>('SELECT id, sku, upc, name FROM inventory_items WHERE id = ? AND is_active = 1', req.params.id);
  if (!item) throw new AppError('Item not found', 404);

  const code = item.upc || item.sku;
  if (!code) throw new AppError('Item has no SKU or UPC for barcode generation', 400);

  const format = (req.query.format as string) || 'png';
  const width = Math.min(4, Math.max(1, parseInt(req.query.width as string) || 2));
  const height = Math.min(200, Math.max(30, parseInt(req.query.height as string) || 80));

  try {
    const canvas = createCanvas(code.length * width * 11 + 40, height + 30);
    JsBarcode(canvas, code, {
      format: 'CODE128',
      width,
      height,
      displayValue: true,
      fontSize: 14,
      margin: 10,
      text: `${code} - ${item.name}`.slice(0, 60),
    });

    if (format === 'svg') {
      // Return SVG-like data URL for embedding
      const pngBuf = canvas.toBuffer('image/png');
      const base64 = pngBuf.toString('base64');
      res.json({ success: true, data: { barcode_data_url: `data:image/png;base64,${base64}`, sku: item.sku, upc: item.upc } });
    } else {
      const pngBuf = canvas.toBuffer('image/png');
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Content-Disposition', `inline; filename="barcode-${code}.png"`);
      res.send(pngBuf);
    }
  } catch (err: any) {
    throw new AppError(`Barcode generation failed: ${err.message}`, 500);
  }
});

// ==================== ENR-INV9: Product image upload ====================
// POST /inventory/:id/image — upload an image for an inventory item
router.post('/:id/image', inventoryImageUpload.single('image'), async (req, res, next) => {
  if (!/^\d+$/.test(req.params.id as string)) return next();
  const adb: AsyncDb = req.asyncDb;
  const itemId = parseInt(req.params.id as string, 10);

  const item = await adb.get('SELECT id FROM inventory_items WHERE id = ? AND is_active = 1', itemId);
  if (!item) throw new AppError('Item not found', 404);

  const file = (req as any).file;
  if (!file) throw new AppError('No image file provided', 400);

  // Build the URL path (relative to uploads root)
  const tenantSlug = (req as any).tenantSlug;
  const relativePath = tenantSlug
    ? `/uploads/${tenantSlug}/inventory/${file.filename}`
    : `/uploads/inventory/${file.filename}`;

  await adb.run("UPDATE inventory_items SET image_url = ?, updated_at = datetime('now') WHERE id = ?",
    relativePath, itemId);
  audit(req.db, 'inventory_image_uploaded', req.user!.id, req.ip || 'unknown', { item_id: itemId, image_url: relativePath });

  res.json({
    success: true,
    data: { image_url: relativePath },
  });
});

// POST /inventory
router.post('/', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const {
    name, description, item_type = 'product', category, manufacturer, device_type,
    sku, upc, cost_price = 0, retail_price = 0, in_stock = 0,
    reorder_level = 0, stock_warning = 5, tax_class_id, tax_inclusive = 0,
    is_serialized = 0, supplier_id, image_url,
    location, shelf, bin,
  } = req.body;

  if (!name) throw new AppError('Name is required', 400);
  if (!['product', 'part', 'service'].includes(item_type)) throw new AppError('Invalid item_type', 400);

  // SEC-M10: Enforce max lengths on text inputs
  const safeName = maxLen(name, 200)!;
  const safeDescription = maxLen(description, 2000);
  const safeCategory = maxLen(category, 100);
  const safeManufacturer = maxLen(manufacturer, 200);
  const safeSku = maxLen(sku, 100);
  const safeUpc = maxLen(upc, 100);

  // CRM33: Auto-generate SKU if not provided
  let finalSku = safeSku || null;
  if (!finalSku) {
    const prefix = item_type === 'product' ? 'PRD' : item_type === 'part' ? 'PRT' : 'SVC';
    const lastRow = await adb.get<any>("SELECT MAX(id) as maxId FROM inventory_items");
    const nextNum = (lastRow?.maxId ?? 0) + 1;
    finalSku = `${prefix}-${String(nextNum).padStart(5, '0')}`;
  }

  const result = await adb.run(`
    INSERT INTO inventory_items (name, description, item_type, category, manufacturer, device_type,
      sku, upc, cost_price, retail_price, in_stock, reorder_level, stock_warning,
      tax_class_id, tax_inclusive, is_serialized, supplier_id, image_url,
      location, shelf, bin)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, safeName, safeDescription || null, item_type, safeCategory || null, safeManufacturer || null,
    device_type || null, finalSku, safeUpc || null, cost_price, retail_price, in_stock,
    reorder_level, stock_warning, tax_class_id || null, tax_inclusive, is_serialized,
    supplier_id || null, image_url || null,
    location || '', shelf || '', bin || '');

  // Record initial stock movement
  if (in_stock > 0 && item_type !== 'service') {
    await adb.run(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id)
      VALUES (?, 'purchase', ?, 'manual', 'Initial stock', ?)
    `, result.lastInsertRowid, in_stock, req.user!.id);
  }

  const item = await adb.get('SELECT * FROM inventory_items WHERE id = ?', result.lastInsertRowid);
  audit(req.db, 'inventory_item_created', req.user!.id, req.ip || 'unknown', { item_id: Number(result.lastInsertRowid), name: safeName, sku: finalSku, item_type });
  res.status(201).json({ success: true, data: { item } });
});

// PUT /inventory/:id
router.put('/:id', async (req, res, next) => {
  const adb: AsyncDb = req.asyncDb;
  if (!/^\d+$/.test(req.params.id)) return next();
  const existing = await adb.get('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1', req.params.id);
  if (!existing) throw new AppError('Item not found', 404);

  const {
    name, description, item_type, category, manufacturer, device_type,
    sku, upc, cost_price, retail_price, reorder_level, stock_warning,
    tax_class_id, tax_inclusive, is_serialized, supplier_id, image_url,
    location, shelf, bin,
  } = req.body;

  // ENR-INV10: Track cost_price changes before updating
  const incomingCost = cost_price ?? null;
  if (incomingCost !== null && Number(incomingCost) !== Number((existing as any).cost_price)) {
    await adb.run(
      `INSERT INTO cost_price_history (inventory_item_id, old_price, new_price, changed_by)
       VALUES (?, ?, ?, ?)`,
      req.params.id,
      (existing as any).cost_price ?? null,
      Number(incomingCost),
      req.user?.id ?? null,
    );
  }

  // NOTE: COALESCE(?, column) means sending null/undefined keeps the existing value.
  // This is intentional for partial updates (PATCH semantics) but means the client
  // CANNOT clear a field to NULL by omitting it. To clear a nullable field, the client
  // should send an empty string ("") which COALESCE will accept as a non-null value.
  // Example: { "description": "" } clears description; omitting "description" keeps it.
  await adb.run(`
    UPDATE inventory_items SET
      name = COALESCE(?, name),
      description = COALESCE(?, description),
      item_type = COALESCE(?, item_type),
      category = COALESCE(?, category),
      manufacturer = COALESCE(?, manufacturer),
      device_type = COALESCE(?, device_type),
      sku = COALESCE(?, sku),
      upc = COALESCE(?, upc),
      cost_price = COALESCE(?, cost_price),
      retail_price = COALESCE(?, retail_price),
      reorder_level = COALESCE(?, reorder_level),
      stock_warning = COALESCE(?, stock_warning),
      tax_class_id = COALESCE(?, tax_class_id),
      tax_inclusive = COALESCE(?, tax_inclusive),
      is_serialized = COALESCE(?, is_serialized),
      supplier_id = COALESCE(?, supplier_id),
      image_url = COALESCE(?, image_url),
      location = COALESCE(?, location),
      shelf = COALESCE(?, shelf),
      bin = COALESCE(?, bin),
      updated_at = datetime('now')
    WHERE id = ?
  `, name ?? null, description ?? null, item_type ?? null, category ?? null,
    manufacturer ?? null, device_type ?? null, sku ?? null, upc ?? null,
    cost_price ?? null, retail_price ?? null, reorder_level ?? null, stock_warning ?? null,
    tax_class_id ?? null, tax_inclusive ?? null, is_serialized ?? null,
    supplier_id ?? null, image_url ?? null,
    location ?? null, shelf ?? null, bin ?? null, req.params.id);

  const item = await adb.get('SELECT * FROM inventory_items WHERE id = ?', req.params.id);
  audit(req.db, 'inventory_item_updated', req.user!.id, req.ip || 'unknown', { item_id: Number(req.params.id) });
  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, item, req.tenantSlug || null);
  res.json({ success: true, data: { item } });
});

// POST /inventory/:id/adjust-stock
router.post('/:id/adjust-stock', async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const item = await adb.get<any>('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1', req.params.id);
  if (!item) throw new AppError('Item not found', 404);

  const { quantity, type = 'adjustment', notes } = req.body;
  if (quantity === undefined) throw new AppError('Quantity is required', 400);

  const parsedQty = parseInt(quantity, 10);
  if (isNaN(parsedQty)) throw new AppError('Quantity must be a valid integer', 400);

  const newStock = item.in_stock + parsedQty;
  if (newStock < 0) throw new AppError('Insufficient stock', 400);

  const adjustStock = db.transaction(() => {
    // Clear low_stock_dismissed when stock increases (so alerts re-trigger if it drops again later)
    if (parsedQty > 0 && item.low_stock_dismissed_at) {
      db.prepare("UPDATE inventory_items SET in_stock = ?, low_stock_dismissed_at = NULL, updated_at = datetime('now') WHERE id = ?").run(newStock, req.params.id);
    } else {
      db.prepare("UPDATE inventory_items SET in_stock = ?, updated_at = datetime('now') WHERE id = ?").run(newStock, req.params.id);
    }
    db.prepare(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id)
      VALUES (?, ?, ?, 'manual', ?, ?)
    `).run(req.params.id, type, parsedQty, notes || null, req.user!.id);
  });
  adjustStock();
  audit(db, 'inventory_stock_adjusted', req.user!.id, req.ip || 'unknown', { item_id: Number(req.params.id), quantity: parsedQty, type, new_stock: newStock });

  const updated = await adb.get<any>('SELECT * FROM inventory_items WHERE id = ?', req.params.id);

  // Check for low stock and broadcast appropriate event
  if (updated && updated.in_stock <= updated.reorder_level) {
    broadcast(WS_EVENTS.INVENTORY_LOW_STOCK, updated, req.tenantSlug || null);
  }
  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, updated, req.tenantSlug || null);
  res.json({ success: true, data: { item: updated } });
});

// DELETE /inventory/:id (soft deactivate)
router.delete('/:id', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const item = await adb.get('SELECT * FROM inventory_items WHERE id = ?', req.params.id);
  if (!item) throw new AppError('Item not found', 404);
  await adb.run("UPDATE inventory_items SET is_active = 0, updated_at = datetime('now') WHERE id = ?", req.params.id);
  audit(req.db, 'inventory_item_deleted', req.user!.id, req.ip || 'unknown', { item_id: Number(req.params.id) });
  res.json({ success: true, data: { message: 'Item deactivated' } });
});

// ==================== Suppliers ====================

// GET /suppliers/list — list all suppliers (optionally filter by is_active)
router.get('/suppliers/list', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { active_only } = req.query as Record<string, string>;
  // SEC-M11: Cap unbounded lookup query
  const where = active_only === 'true' ? 'WHERE is_active = 1' : '';
  const suppliers = await adb.all(`SELECT * FROM suppliers ${where} ORDER BY name ASC LIMIT 500`);
  res.json({ success: true, data: { suppliers } });
});

// POST /suppliers — create a new supplier
router.post('/suppliers', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { name, contact_name, email, phone, address, website, rating, notes } = req.body;
  if (!name) throw new AppError('Name is required', 400);
  if (rating != null && (rating < 1 || rating > 5 || !Number.isInteger(Number(rating)))) {
    throw new AppError('Rating must be an integer between 1 and 5', 400);
  }
  const result = await adb.run(`
    INSERT INTO suppliers (name, contact_name, email, phone, address, website, rating, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, name, contact_name || null, email || null, phone || null, address || null, website || null, rating != null ? Number(rating) : null, notes || null);
  const supplier = await adb.get('SELECT * FROM suppliers WHERE id = ?', result.lastInsertRowid);
  audit(req.db, 'supplier_created', req.user!.id, req.ip || 'unknown', { supplier_id: Number(result.lastInsertRowid), name });
  res.status(201).json({ success: true, data: { supplier } });
});

// PUT /suppliers/:id — update a supplier
router.put('/suppliers/:id', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { name, contact_name, email, phone, address, website, rating, notes } = req.body;
  if (rating != null && (rating < 1 || rating > 5 || !Number.isInteger(Number(rating)))) {
    throw new AppError('Rating must be an integer between 1 and 5', 400);
  }
  await adb.run(`
    UPDATE suppliers SET
      name = COALESCE(?, name), contact_name = COALESCE(?, contact_name),
      email = COALESCE(?, email), phone = COALESCE(?, phone),
      address = COALESCE(?, address), website = COALESCE(?, website),
      rating = COALESCE(?, rating), notes = COALESCE(?, notes),
      updated_at = datetime('now')
    WHERE id = ?
  `, name ?? null, contact_name ?? null, email ?? null, phone ?? null, address ?? null, website ?? null, rating != null ? Number(rating) : null, notes ?? null, req.params.id);
  const supplier = await adb.get('SELECT * FROM suppliers WHERE id = ?', req.params.id);
  if (!supplier) throw new AppError('Supplier not found', 404);
  audit(req.db, 'supplier_updated', req.user!.id, req.ip || 'unknown', { supplier_id: Number(req.params.id) });
  res.json({ success: true, data: { supplier } });
});

// DELETE /suppliers/:id — soft-delete a supplier
router.delete('/suppliers/:id', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const supplier = await adb.get('SELECT id FROM suppliers WHERE id = ?', req.params.id);
  if (!supplier) throw new AppError('Supplier not found', 404);
  await adb.run("UPDATE suppliers SET is_active = 0, updated_at = datetime('now') WHERE id = ?", req.params.id);
  audit(req.db, 'supplier_deleted', req.user!.id, req.ip || 'unknown', { supplier_id: Number(req.params.id) });
  res.json({ success: true, data: { message: 'Supplier deactivated' } });
});

// ==================== Purchase Orders ====================

router.get('/purchase-orders/list', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { page = '1', pagesize = '20', status } = req.query as Record<string, string>;
  const p = Math.max(1, parseInt(page, 10) || 1);
  const ps = Math.min(100, parseInt(pagesize, 10) || 20);
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: any[] = [];
  if (status) { where += ' AND po.status = ?'; params.push(status); }

  const [totalRow, orders] = await Promise.all([
    adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM purchase_orders po ${where}`, ...params),
    adb.all(`
      SELECT po.*, s.name as supplier_name, u.first_name || ' ' || u.last_name as created_by_name
      FROM purchase_orders po
      LEFT JOIN suppliers s ON s.id = po.supplier_id
      LEFT JOIN users u ON u.id = po.created_by
      ${where}
      ORDER BY po.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, ps, offset),
  ]);
  const total = totalRow!.c;

  res.json({ success: true, data: { orders, pagination: { page: p, per_page: ps, total, total_pages: Math.ceil(total / ps) } } });
});

router.post('/purchase-orders', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { supplier_id, notes, expected_date, items = [] } = req.body;
  if (!supplier_id) throw new AppError('Supplier is required', 400);

  // Get next order_id from existing order_ids (safe across deletions)
  const seqRow = await adb.get<any>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 4) AS INTEGER)), 0) + 1 as next_num FROM purchase_orders");
  const orderId = generateOrderId('PO', seqRow.next_num);

  let subtotal = 0;
  for (const item of items) { subtotal += (item.quantity_ordered || 0) * (item.cost_price || 0); }

  const result = await adb.run(`
    INSERT INTO purchase_orders (order_id, supplier_id, subtotal, total, notes, expected_date, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `, orderId, supplier_id, subtotal, subtotal, notes || null, expected_date || null, req.user!.id);

  for (const item of items) {
    await adb.run(`
      INSERT INTO purchase_order_items (purchase_order_id, inventory_item_id, quantity_ordered, cost_price)
      VALUES (?, ?, ?, ?)
    `, result.lastInsertRowid, item.inventory_item_id, item.quantity_ordered, item.cost_price || 0);
  }

  const po = await adb.get('SELECT * FROM purchase_orders WHERE id = ?', result.lastInsertRowid);
  audit(req.db, 'purchase_order_created', req.user!.id, req.ip || 'unknown', { po_id: Number(result.lastInsertRowid), order_id: orderId, supplier_id, total: subtotal });
  res.status(201).json({ success: true, data: { order: po } });
});

router.get('/purchase-orders/:id', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const [po, items] = await Promise.all([
    adb.get(`
      SELECT po.*, s.name as supplier_name
      FROM purchase_orders po LEFT JOIN suppliers s ON s.id = po.supplier_id
      WHERE po.id = ?
    `, req.params.id),
    adb.all(`
      SELECT poi.*, i.name as item_name, i.sku
      FROM purchase_order_items poi
      JOIN inventory_items i ON i.id = poi.inventory_item_id
      WHERE poi.purchase_order_id = ?
    `, req.params.id),
  ]);
  if (!po) throw new AppError('Purchase order not found', 404);

  res.json({ success: true, data: { order: po, items } });
});

router.post('/purchase-orders/:id/receive', async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const { items } = req.body; // [{purchase_order_item_id, quantity_received}]
  if (!items?.length) throw new AppError('Items required', 400);

  const receiveItems = db.transaction(() => {
    for (const item of items) {
      const poItem = db.prepare('SELECT * FROM purchase_order_items WHERE id = ?').get(item.purchase_order_item_id) as any;
      if (!poItem) continue;
      const received = Math.min(item.quantity_received, poItem.quantity_ordered - poItem.quantity_received);
      if (received <= 0) continue;

      db.prepare('UPDATE purchase_order_items SET quantity_received = quantity_received + ? WHERE id = ?').run(received, item.purchase_order_item_id);
      db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = datetime(\'now\') WHERE id = ?').run(received, poItem.inventory_item_id);
      db.prepare(`
        INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id)
        VALUES (?, 'purchase', ?, 'purchase_order', ?, 'Received from PO', ?)
      `).run(poItem.inventory_item_id, received, req.params.id, req.user!.id);
    }

    // Check if fully received
    const remaining = db.prepare(`
      SELECT SUM(quantity_ordered - quantity_received) as r FROM purchase_order_items WHERE purchase_order_id = ?
    `).get(req.params.id) as any;
    const newStatus = remaining.r <= 0 ? 'received' : 'partial';
    // ENR-INV7: Set actual_received_date when items are received
    db.prepare("UPDATE purchase_orders SET status = ?, received_date = datetime('now'), actual_received_date = datetime('now'), updated_at = datetime('now') WHERE id = ?").run(newStatus, req.params.id);
  });

  receiveItems();
  audit(db, 'purchase_order_received', req.user!.id, req.ip || 'unknown', { po_id: Number(req.params.id), items_received: items.length });
  const po = await adb.get('SELECT * FROM purchase_orders WHERE id = ?', req.params.id);
  res.json({ success: true, data: { order: po } });
});

// ==================== ENR-INV6: PO status workflow ====================

// Valid status transitions: draft → pending → ordered → partial → received
//                           Any non-received status → cancelled
//                           ordered → backordered → ordered (cycle back)
const PO_VALID_TRANSITIONS: Record<string, string[]> = {
  draft:       ['pending', 'cancelled'],
  pending:     ['ordered', 'cancelled'],
  ordered:     ['partial', 'received', 'cancelled', 'backordered'],
  partial:     ['received', 'cancelled', 'backordered'],
  backordered: ['ordered', 'cancelled'],
  // received and cancelled are terminal states
  received:    [],
  cancelled:   [],
};

// PUT /purchase-orders/:id — Update PO with status transitions
router.put('/purchase-orders/:id', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const po = await adb.get<any>('SELECT * FROM purchase_orders WHERE id = ?', req.params.id);
  if (!po) throw new AppError('Purchase order not found', 404);

  const { status, notes, expected_date, actual_received_date, paid_status } = req.body;

  if (status && status !== po.status) {
    const allowed = PO_VALID_TRANSITIONS[po.status];
    if (!allowed) {
      throw new AppError(`Cannot transition from terminal status '${po.status}'`, 400);
    }
    if (!allowed.includes(status)) {
      throw new AppError(`Invalid status transition: '${po.status}' → '${status}'. Allowed: ${allowed.join(', ')}`, 400);
    }
  }

  const updates: string[] = ["updated_at = datetime('now')"];
  const params: any[] = [];

  if (status !== undefined) {
    updates.push('status = ?');
    params.push(status);

    // Set date fields based on status
    if (status === 'ordered') {
      updates.push("ordered_date = datetime('now')");
    } else if (status === 'received') {
      updates.push("received_date = datetime('now')");
    } else if (status === 'cancelled') {
      updates.push("cancelled_date = datetime('now')");
      if (req.body.cancelled_reason) {
        updates.push('cancelled_reason = ?');
        params.push(req.body.cancelled_reason);
      }
    }
  }

  if (notes !== undefined) {
    updates.push('notes = ?');
    params.push(notes);
  }
  if (expected_date !== undefined) {
    updates.push('expected_date = ?');
    params.push(expected_date);
  }
  // ENR-INV7: Accept actual_received_date
  if (actual_received_date !== undefined) {
    updates.push('actual_received_date = ?');
    params.push(actual_received_date);
  }
  if (paid_status !== undefined) {
    if (!['unpaid', 'partial', 'paid'].includes(paid_status)) {
      throw new AppError('Invalid paid_status', 400);
    }
    updates.push('paid_status = ?');
    params.push(paid_status);
  }

  params.push(req.params.id);
  await adb.run(`UPDATE purchase_orders SET ${updates.join(', ')} WHERE id = ?`, ...params);

  const updated = await adb.get(`
    SELECT po.*, s.name as supplier_name
    FROM purchase_orders po
    LEFT JOIN suppliers s ON s.id = po.supplier_id
    WHERE po.id = ?
  `, req.params.id);
  audit(req.db, 'purchase_order_updated', req.user!.id, req.ip || 'unknown', { po_id: Number(req.params.id), status: status ?? po.status });
  res.json({ success: true, data: { order: updated } });
});

// POST /dismiss-low-stock — Dismiss all current low stock alerts
router.post('/dismiss-low-stock', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const result = await adb.run(`
    UPDATE inventory_items SET low_stock_dismissed_at = ?
    WHERE is_reorderable = 1 AND is_active = 1 AND item_type != 'service'
      AND in_stock <= reorder_level AND low_stock_dismissed_at IS NULL
  `, now);
  audit(req.db, 'low_stock_alerts_dismissed', req.user!.id, req.ip || 'unknown', { dismissed: result.changes });
  res.json({ success: true, data: { dismissed: result.changes } });
});

// POST /undismiss-low-stock — Clear all dismissals (re-show alerts)
router.post('/undismiss-low-stock', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const result = await adb.run(`
    UPDATE inventory_items SET low_stock_dismissed_at = NULL
    WHERE low_stock_dismissed_at IS NOT NULL
  `);
  audit(req.db, 'low_stock_alerts_undismissed', req.user!.id, req.ip || 'unknown', { undismissed: result.changes });
  res.json({ success: true, data: { undismissed: result.changes } });
});

// ==================== Stocktake / Inventory Count ====================

// POST /stocktake — Submit a stocktake (array of {item_id, counted_qty})
// SEC-H8: Admin or manager role required for stocktake operations
router.post('/stocktake', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') throw new AppError('Admin or manager access required', 403);
  const db = req.db;
  const { items, notes } = req.body;
  if (!Array.isArray(items) || items.length === 0) throw new AppError('items array required', 400);

  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const userId = req.user!.id;
  const adjustments: { id: number; name: string; expected: number; counted: number; diff: number }[] = [];

  const process = db.transaction(() => {
    for (const item of items) {
      const inv = db.prepare('SELECT id, name, in_stock FROM inventory_items WHERE id = ? AND is_active = 1').get(item.item_id) as any;
      if (!inv) continue;

      const counted = parseInt(item.counted_qty);
      if (isNaN(counted) || counted < 0) continue;

      const diff = counted - inv.in_stock;
      if (diff !== 0) {
        db.prepare('UPDATE inventory_items SET in_stock = ?, updated_at = ? WHERE id = ?').run(counted, now, inv.id);
        db.prepare(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id, created_at, updated_at)
          VALUES (?, 'stocktake', ?, 'stocktake', ?, ?, ?, ?)
        `).run(inv.id, diff, notes || `Stocktake adjustment: ${inv.in_stock} → ${counted}`, userId, now, now);
      }

      adjustments.push({ id: inv.id, name: inv.name, expected: inv.in_stock, counted, diff });
    }
  });
  process();
  audit(db, 'inventory_stocktake', req.user!.id, req.ip || 'unknown', { total_items: adjustments.length, adjusted: adjustments.filter(a => a.diff !== 0).length });

  res.json({
    success: true,
    data: {
      total_items: adjustments.length,
      adjusted: adjustments.filter(a => a.diff !== 0).length,
      adjustments,
    },
  });
});

// GET /stocktake/discrepancies — Items where stock may be inaccurate (negative or suspiciously high)
router.get('/stocktake/discrepancies', async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const items = await adb.all(`
    SELECT id, name, sku, in_stock, reorder_level, item_type
    FROM inventory_items
    WHERE is_active = 1 AND (in_stock < 0 OR in_stock > 1000)
    ORDER BY ABS(in_stock) DESC LIMIT 50
  `);
  res.json({ success: true, data: items });
});

// ─── Scan-to-Receive: bulk barcode receiving ───────────────────────────────────

// POST /inventory/receive-scan — look up barcodes and receive matched items
router.post('/receive-scan', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager')
    throw new AppError('Admin or manager access required', 403);

  const db = req.db;
  const { items, notes } = req.body;
  if (!Array.isArray(items) || items.length === 0) throw new AppError('items array is required', 400);
  if (items.length > 200) throw new AppError('Maximum 200 items per receive session', 400);

  const received: any[] = [];
  const unmatched: any[] = [];

  const findByBarcode = db.prepare(
    'SELECT * FROM inventory_items WHERE is_active = 1 AND (upc = ? OR sku = ?) LIMIT 1'
  );
  const findInCatalog = db.prepare(
    'SELECT id, source, sku, name, price, image_url FROM supplier_catalog WHERE sku = ? LIMIT 1'
  );
  const updateStock = db.prepare(
    "UPDATE inventory_items SET in_stock = in_stock + ?, low_stock_dismissed_at = NULL, updated_at = datetime('now') WHERE id = ?"
  );
  const insertMovement = db.prepare(
    "INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id) VALUES (?, 'received', ?, 'scan_receive', ?, ?)"
  );

  const doReceive = db.transaction(() => {
    for (const entry of items) {
      const barcode = String(entry.barcode || '').trim();
      const qty = Math.max(1, parseInt(entry.quantity, 10) || 1);
      if (!barcode) continue;

      const item = findByBarcode.get(barcode, barcode) as any;
      if (item) {
        updateStock.run(qty, item.id);
        insertMovement.run(item.id, qty, notes || `Scan receive: ${barcode}`, req.user!.id);
        received.push({ id: item.id, sku: item.sku, upc: item.upc, name: item.name, quantity: qty, new_stock: item.in_stock + qty });
      } else {
        const catalogMatch = findInCatalog.get(barcode) as any;
        unmatched.push({
          barcode,
          quantity: qty,
          catalog_match: catalogMatch ? {
            id: catalogMatch.id,
            source: catalogMatch.source,
            sku: catalogMatch.sku,
            name: catalogMatch.name,
            cost_price: catalogMatch.price,
            image_url: catalogMatch.image_url,
          } : null,
        });
      }
    }
  });
  doReceive();
  audit(db, 'inventory_scan_received', req.user!.id, req.ip || 'unknown', { received_count: received.length, unmatched_count: unmatched.length });

  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, { bulk: true, count: received.length }, req.tenantSlug || null);
  res.json({ success: true, data: { received, unmatched } });
});

// POST /inventory/receive-scan/create-from-catalog — create inventory item from catalog match + receive stock
router.post('/receive-scan/create-from-catalog', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager')
    throw new AppError('Admin or manager access required', 403);

  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const { catalog_id, quantity = 1, retail_price, markup_pct = 30 } = req.body;
  if (!catalog_id) throw new AppError('catalog_id is required', 400);

  const catalogItem = await adb.get<any>('SELECT * FROM supplier_catalog WHERE id = ?', catalog_id);
  if (!catalogItem) throw new AppError('Catalog item not found', 404);

  // Check for duplicate SKU
  if (catalogItem.sku) {
    const existing = await adb.get<any>('SELECT id FROM inventory_items WHERE sku = ?', catalogItem.sku);
    if (existing) throw new AppError('Item already in inventory (matching SKU)', 409);
  }

  const finalRetail = retail_price != null
    ? parseFloat(retail_price)
    : Math.round(catalogItem.price * (1 + markup_pct / 100) * 100) / 100;
  const qty = Math.max(1, parseInt(quantity, 10) || 1);

  const createAndReceive = db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO inventory_items (name, sku, item_type, is_reorderable, cost_price, retail_price, in_stock, image_url, description, created_at)
      VALUES (?, ?, 'part', 1, ?, ?, ?, ?, ?, datetime('now'))
    `).run(
      catalogItem.name, catalogItem.sku || null,
      catalogItem.price, finalRetail, qty,
      catalogItem.image_url || null,
      `Imported from ${catalogItem.source}. ${catalogItem.product_url || ''}`.trim(),
    );
    const itemId = Number(result.lastInsertRowid);

    // Copy device compatibility
    const compatRows = db.prepare(
      'SELECT device_model_id FROM catalog_device_compatibility WHERE supplier_catalog_id = ?'
    ).all(catalog_id) as { device_model_id: number }[];
    const insertCompat = db.prepare(
      'INSERT OR IGNORE INTO inventory_device_compatibility (inventory_item_id, device_model_id) VALUES (?, ?)'
    );
    for (const row of compatRows) insertCompat.run(itemId, row.device_model_id);

    // Log stock movement
    db.prepare(
      "INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id) VALUES (?, 'received', ?, 'scan_receive', ?, ?)"
    ).run(itemId, qty, `Created from ${catalogItem.source} catalog + received`, req.user!.id);

    return db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(itemId);
  });

  const item = createAndReceive();
  audit(db, 'inventory_created_from_catalog', req.user!.id, req.ip || 'unknown', { catalog_id, quantity: qty, name: catalogItem.name });
  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, item, req.tenantSlug || null);
  res.status(201).json({ success: true, data: { item } });
});

// POST /inventory/receive-scan/quick-add — create new item from manual input + receive stock
router.post('/receive-scan/quick-add', async (req, res) => {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager')
    throw new AppError('Admin or manager access required', 403);

  const db = req.db;
  const { barcode, name, cost_price, retail_price, category, quantity = 1 } = req.body;
  if (!name) throw new AppError('Name is required', 400);

  const qty = Math.max(1, parseInt(quantity, 10) || 1);
  const cost = parseFloat(cost_price) || 0;
  const retail = parseFloat(retail_price) || 0;

  const createItem = db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO inventory_items (name, upc, sku, item_type, category, cost_price, retail_price, in_stock, created_at)
      VALUES (?, ?, ?, 'part', ?, ?, ?, ?, datetime('now'))
    `).run(name, barcode || null, barcode || null, category || null, cost, retail, qty);

    const itemId = Number(result.lastInsertRowid);
    db.prepare(
      "INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id) VALUES (?, 'received', ?, 'scan_receive', ?, ?)"
    ).run(itemId, qty, `Quick-added during scan receive`, req.user!.id);

    return db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(itemId);
  });

  const item = createItem();
  audit(db, 'inventory_quick_added', req.user!.id, req.ip || 'unknown', { name, barcode, quantity: qty });
  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, item, req.tenantSlug || null);
  res.status(201).json({ success: true, data: { item } });
});

export default router;
