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
router.get('/', (req, res) => {
  const db = req.db;
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

  const total = (db.prepare(`SELECT COUNT(*) as c FROM inventory_items i ${where}`).get(...params) as any).c;
  const items = db.prepare(`
    SELECT i.*, s.name as supplier_name,
      (SELECT sc.product_url FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(i.name)) AND sc.product_url IS NOT NULL LIMIT 1) AS supplier_url,
      (SELECT sc.source FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(i.name)) AND sc.product_url IS NOT NULL LIMIT 1) AS supplier_source
    FROM inventory_items i
    LEFT JOIN suppliers s ON s.id = i.supplier_id
    ${where}
    ORDER BY ${safeSortBy} ${safeSortOrder}
    LIMIT ? OFFSET ?
  `).all(...params, ps, offset);

  res.json({
    success: true,
    data: {
      items,
      pagination: { page: p, per_page: ps, total, total_pages: Math.ceil(total / ps) },
    },
  });
});

// GET /inventory/manufacturers — distinct manufacturer values
router.get('/manufacturers', (req, res) => {
  const db = req.db;
  const rows = db.prepare(`SELECT DISTINCT manufacturer FROM inventory_items WHERE manufacturer IS NOT NULL AND manufacturer != '' AND is_active = 1 ORDER BY manufacturer`).all();
  res.json({ success: true, data: { manufacturers: rows.map((r: any) => r.manufacturer) } });
});

// POST /inventory/import-csv — bulk create items from CSV data
// SEC-H8: Admin or manager role required for bulk import operations
router.post('/import-csv', (req, res) => {
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
  res.json({ success: true, data: results });
});

// POST /inventory/bulk-action — bulk update/delete items
// SEC-H8: Admin or manager role required for bulk operations
router.post('/bulk-action', (req, res) => {
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
  res.json({ success: true, data: { affected } });
});

// GET /inventory/low-stock
router.get('/low-stock', (req, res) => {
  const db = req.db;
  const items = db.prepare(`
    SELECT * FROM inventory_items
    WHERE is_active = 1 AND item_type != 'service' AND is_reorderable = 1 AND in_stock <= reorder_level
    ORDER BY in_stock ASC
  `).all();
  res.json({ success: true, data: { items } });
});

// GET /inventory/summary — Stock value summary
router.get('/summary', (req, res) => {
  const db = req.db;
  const summary = db.prepare(`
    SELECT
      COUNT(*) AS total_items,
      COUNT(CASE WHEN in_stock > 0 THEN 1 END) AS in_stock_items,
      COUNT(CASE WHEN in_stock <= COALESCE(reorder_level, 0) AND in_stock >= 0 AND item_type != 'service' AND is_reorderable = 1 THEN 1 END) AS low_stock_items,
      COALESCE(SUM(CASE WHEN item_type != 'service' THEN in_stock * retail_price ELSE 0 END), 0) AS total_retail_value,
      COALESCE(SUM(CASE WHEN item_type != 'service' THEN in_stock * cost_price ELSE 0 END), 0) AS total_cost_value,
      COALESCE(SUM(in_stock), 0) AS total_units
    FROM inventory_items WHERE is_active = 1
  `).get();
  res.json({ success: true, data: summary });
});

// GET /inventory/categories
router.get('/categories', (req, res) => {
  const db = req.db;
  const rows = db.prepare(`SELECT DISTINCT category FROM inventory_items WHERE category IS NOT NULL AND is_active = 1 ORDER BY category`).all();
  res.json({ success: true, data: { categories: rows.map((r: any) => r.category) } });
});

// ==================== ENR-INV1: Auto-reorder / PO generation ====================

// POST /inventory/auto-reorder — Find low-stock reorderable items, group by supplier, create POs
router.post('/auto-reorder', (req, res) => {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  const db = req.db;

  // Find all items needing reorder: in_stock <= reorder_level, reorder_level > 0, is_reorderable = 1
  const lowStockItems = db.prepare(`
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
  `).all() as any[];

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
router.get('/stock-alerts-summary', (req, res) => {
  const db = req.db;

  const lowStockItems = db.prepare(`
    SELECT i.id, i.name, i.sku, i.in_stock, i.reorder_level, i.supplier_id, s.name as supplier_name
    FROM inventory_items i
    LEFT JOIN suppliers s ON s.id = i.supplier_id
    WHERE i.is_active = 1
      AND i.item_type != 'service'
      AND i.is_reorderable = 1
      AND i.in_stock <= i.reorder_level
    ORDER BY i.in_stock ASC
  `).all() as any[];

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
router.get('/variance-report', (req, res) => {
  const db = req.db;
  const months = parseInt(req.query.months as string) || 6;

  // Get monthly in/out totals per item over the last N months
  const rows = db.prepare(`
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
  `).all(months) as any[];

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
router.get('/barcode/:code', (req, res) => {
  const db = req.db;
  const item = db.prepare(`SELECT * FROM inventory_items WHERE (sku = ? OR upc = ?) AND is_active = 1`).get(req.params.code, req.params.code);
  if (!item) throw new AppError('Item not found', 404);
  res.json({ success: true, data: { item } });
});

// GET /inventory/:id (must be numeric — skip for named routes like /suppliers, /purchase-orders)
router.get('/:id', (req, res, next) => {
  const db = req.db;
  if (!/^\d+$/.test(req.params.id)) return next();
  const item = db.prepare(`
    SELECT i.*, s.name as supplier_name
    FROM inventory_items i
    LEFT JOIN suppliers s ON s.id = i.supplier_id
    WHERE i.id = ? AND i.is_active = 1
  `).get(req.params.id);
  if (!item) throw new AppError('Item not found', 404);

  const movements = db.prepare(`
    SELECT sm.*, u.first_name || ' ' || u.last_name as user_name
    FROM stock_movements sm
    LEFT JOIN users u ON u.id = sm.user_id
    WHERE sm.inventory_item_id = ?
    ORDER BY sm.created_at DESC
    LIMIT 50
  `).all(req.params.id);

  const groupPrices = db.prepare(`
    SELECT gp.*, cg.name as group_name
    FROM inventory_group_prices gp
    JOIN customer_groups cg ON cg.id = gp.customer_group_id
    WHERE gp.inventory_item_id = ?
  `).all(req.params.id);

  res.json({ success: true, data: { item, movements, group_prices: groupPrices } });
});

// ==================== ENR-INV8: Barcode generation ====================

// GET /inventory/:id/barcode — Generate barcode image (PNG) for item's SKU or UPC
router.get('/:id/barcode', (req, res, next) => {
  if (!/^\d+$/.test(req.params.id)) return next();
  const db = req.db;
  const item = db.prepare('SELECT id, sku, upc, name FROM inventory_items WHERE id = ? AND is_active = 1').get(req.params.id) as any;
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
router.post('/:id/image', inventoryImageUpload.single('image'), (req, res, next) => {
  if (!/^\d+$/.test(req.params.id)) return next();
  const db = req.db;
  const itemId = parseInt(req.params.id, 10);

  const item = db.prepare('SELECT id FROM inventory_items WHERE id = ? AND is_active = 1').get(itemId);
  if (!item) throw new AppError('Item not found', 404);

  const file = (req as any).file;
  if (!file) throw new AppError('No image file provided', 400);

  // Build the URL path (relative to uploads root)
  const tenantSlug = (req as any).tenantSlug;
  const relativePath = tenantSlug
    ? `/uploads/${tenantSlug}/inventory/${file.filename}`
    : `/uploads/inventory/${file.filename}`;

  db.prepare("UPDATE inventory_items SET image_url = ?, updated_at = datetime('now') WHERE id = ?")
    .run(relativePath, itemId);

  res.json({
    success: true,
    data: { image_url: relativePath },
  });
});

// POST /inventory
router.post('/', (req, res) => {
  const db = req.db;
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
    const lastRow = db.prepare("SELECT MAX(id) as maxId FROM inventory_items").get() as any;
    const nextNum = (lastRow?.maxId ?? 0) + 1;
    finalSku = `${prefix}-${String(nextNum).padStart(5, '0')}`;
  }

  const result = db.prepare(`
    INSERT INTO inventory_items (name, description, item_type, category, manufacturer, device_type,
      sku, upc, cost_price, retail_price, in_stock, reorder_level, stock_warning,
      tax_class_id, tax_inclusive, is_serialized, supplier_id, image_url,
      location, shelf, bin)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(safeName, safeDescription || null, item_type, safeCategory || null, safeManufacturer || null,
    device_type || null, finalSku, safeUpc || null, cost_price, retail_price, in_stock,
    reorder_level, stock_warning, tax_class_id || null, tax_inclusive, is_serialized,
    supplier_id || null, image_url || null,
    location || '', shelf || '', bin || '');

  // Record initial stock movement
  if (in_stock > 0 && item_type !== 'service') {
    db.prepare(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, notes, user_id)
      VALUES (?, 'purchase', ?, 'manual', 'Initial stock', ?)
    `).run(result.lastInsertRowid, in_stock, req.user!.id);
  }

  const item = db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { item } });
});

// PUT /inventory/:id
router.put('/:id', (req, res, next) => {
  const db = req.db;
  if (!/^\d+$/.test(req.params.id)) return next();
  const existing = db.prepare('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1').get(req.params.id) as any;
  if (!existing) throw new AppError('Item not found', 404);

  const {
    name, description, item_type, category, manufacturer, device_type,
    sku, upc, cost_price, retail_price, reorder_level, stock_warning,
    tax_class_id, tax_inclusive, is_serialized, supplier_id, image_url,
    location, shelf, bin,
  } = req.body;

  // NOTE: COALESCE(?, column) means sending null/undefined keeps the existing value.
  // This is intentional for partial updates (PATCH semantics) but means the client
  // CANNOT clear a field to NULL by omitting it. To clear a nullable field, the client
  // should send an empty string ("") which COALESCE will accept as a non-null value.
  // Example: { "description": "" } clears description; omitting "description" keeps it.
  db.prepare(`
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
  `).run(name ?? null, description ?? null, item_type ?? null, category ?? null,
    manufacturer ?? null, device_type ?? null, sku ?? null, upc ?? null,
    cost_price ?? null, retail_price ?? null, reorder_level ?? null, stock_warning ?? null,
    tax_class_id ?? null, tax_inclusive ?? null, is_serialized ?? null,
    supplier_id ?? null, image_url ?? null,
    location ?? null, shelf ?? null, bin ?? null, req.params.id);

  const item = db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(req.params.id);
  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, item, req.tenantSlug || null);
  res.json({ success: true, data: { item } });
});

// POST /inventory/:id/adjust-stock
router.post('/:id/adjust-stock', (req, res) => {
  const db = req.db;
  const item = db.prepare('SELECT * FROM inventory_items WHERE id = ? AND is_active = 1').get(req.params.id) as any;
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

  const updated = db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(req.params.id) as any;

  // Check for low stock and broadcast appropriate event
  if (updated && updated.in_stock <= updated.reorder_level) {
    broadcast(WS_EVENTS.INVENTORY_LOW_STOCK, updated, req.tenantSlug || null);
  }
  broadcast(WS_EVENTS.INVENTORY_STOCK_CHANGED, updated, req.tenantSlug || null);
  res.json({ success: true, data: { item: updated } });
});

// DELETE /inventory/:id (soft deactivate)
router.delete('/:id', (req, res) => {
  const db = req.db;
  const item = db.prepare('SELECT * FROM inventory_items WHERE id = ?').get(req.params.id);
  if (!item) throw new AppError('Item not found', 404);
  db.prepare('UPDATE inventory_items SET is_active = 0, updated_at = datetime(\'now\') WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Item deactivated' } });
});

// ==================== Suppliers ====================

router.get('/suppliers/list', (req, res) => {
  const db = req.db;
  const suppliers = db.prepare('SELECT * FROM suppliers ORDER BY name ASC').all();
  res.json({ success: true, data: { suppliers } });
});

router.post('/suppliers', (req, res) => {
  const db = req.db;
  const { name, contact_name, email, phone, address, notes } = req.body;
  if (!name) throw new AppError('Name is required', 400);
  const result = db.prepare(`
    INSERT INTO suppliers (name, contact_name, email, phone, address, notes)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(name, contact_name || null, email || null, phone || null, address || null, notes || null);
  const supplier = db.prepare('SELECT * FROM suppliers WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { supplier } });
});

router.put('/suppliers/:id', (req, res) => {
  const db = req.db;
  const { name, contact_name, email, phone, address, notes } = req.body;
  db.prepare(`
    UPDATE suppliers SET
      name = COALESCE(?, name), contact_name = COALESCE(?, contact_name),
      email = COALESCE(?, email), phone = COALESCE(?, phone),
      address = COALESCE(?, address), notes = COALESCE(?, notes)
    WHERE id = ?
  `).run(name ?? null, contact_name ?? null, email ?? null, phone ?? null, address ?? null, notes ?? null, req.params.id);
  const supplier = db.prepare('SELECT * FROM suppliers WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: { supplier } });
});

// ==================== Purchase Orders ====================

router.get('/purchase-orders/list', (req, res) => {
  const db = req.db;
  const { page = '1', pagesize = '20', status } = req.query as Record<string, string>;
  const p = Math.max(1, parseInt(page, 10) || 1);
  const ps = Math.min(100, parseInt(pagesize, 10) || 20);
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: any[] = [];
  if (status) { where += ' AND po.status = ?'; params.push(status); }

  const total = (db.prepare(`SELECT COUNT(*) as c FROM purchase_orders po ${where}`).get(...params) as any).c;
  const orders = db.prepare(`
    SELECT po.*, s.name as supplier_name, u.first_name || ' ' || u.last_name as created_by_name
    FROM purchase_orders po
    LEFT JOIN suppliers s ON s.id = po.supplier_id
    LEFT JOIN users u ON u.id = po.created_by
    ${where}
    ORDER BY po.created_at DESC
    LIMIT ? OFFSET ?
  `).all(...params, ps, offset);

  res.json({ success: true, data: { orders, pagination: { page: p, per_page: ps, total, total_pages: Math.ceil(total / ps) } } });
});

router.post('/purchase-orders', (req, res) => {
  const db = req.db;
  const { supplier_id, notes, expected_date, items = [] } = req.body;
  if (!supplier_id) throw new AppError('Supplier is required', 400);

  // Get next order_id from existing order_ids (safe across deletions)
  const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 4) AS INTEGER)), 0) + 1 as next_num FROM purchase_orders").get() as any;
  const orderId = generateOrderId('PO', seqRow.next_num);

  let subtotal = 0;
  for (const item of items) { subtotal += (item.quantity_ordered || 0) * (item.cost_price || 0); }

  const result = db.prepare(`
    INSERT INTO purchase_orders (order_id, supplier_id, subtotal, total, notes, expected_date, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(orderId, supplier_id, subtotal, subtotal, notes || null, expected_date || null, req.user!.id);

  for (const item of items) {
    db.prepare(`
      INSERT INTO purchase_order_items (purchase_order_id, inventory_item_id, quantity_ordered, cost_price)
      VALUES (?, ?, ?, ?)
    `).run(result.lastInsertRowid, item.inventory_item_id, item.quantity_ordered, item.cost_price || 0);
  }

  const po = db.prepare('SELECT * FROM purchase_orders WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { order: po } });
});

router.get('/purchase-orders/:id', (req, res) => {
  const db = req.db;
  const po = db.prepare(`
    SELECT po.*, s.name as supplier_name
    FROM purchase_orders po LEFT JOIN suppliers s ON s.id = po.supplier_id
    WHERE po.id = ?
  `).get(req.params.id);
  if (!po) throw new AppError('Purchase order not found', 404);

  const items = db.prepare(`
    SELECT poi.*, i.name as item_name, i.sku
    FROM purchase_order_items poi
    JOIN inventory_items i ON i.id = poi.inventory_item_id
    WHERE poi.purchase_order_id = ?
  `).all(req.params.id);

  res.json({ success: true, data: { order: po, items } });
});

router.post('/purchase-orders/:id/receive', (req, res) => {
  const db = req.db;
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
  const po = db.prepare('SELECT * FROM purchase_orders WHERE id = ?').get(req.params.id);
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
router.put('/purchase-orders/:id', (req, res) => {
  const db = req.db;
  const po = db.prepare('SELECT * FROM purchase_orders WHERE id = ?').get(req.params.id) as any;
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
  db.prepare(`UPDATE purchase_orders SET ${updates.join(', ')} WHERE id = ?`).run(...params);

  const updated = db.prepare(`
    SELECT po.*, s.name as supplier_name
    FROM purchase_orders po
    LEFT JOIN suppliers s ON s.id = po.supplier_id
    WHERE po.id = ?
  `).get(req.params.id);
  res.json({ success: true, data: { order: updated } });
});

// POST /dismiss-low-stock — Dismiss all current low stock alerts
router.post('/dismiss-low-stock', (req, res) => {
  const db = req.db;
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const result = (db as any).prepare(`
    UPDATE inventory_items SET low_stock_dismissed_at = ?
    WHERE is_reorderable = 1 AND is_active = 1 AND item_type != 'service'
      AND in_stock <= reorder_level AND low_stock_dismissed_at IS NULL
  `).run(now);
  res.json({ success: true, data: { dismissed: result.changes } });
});

// POST /undismiss-low-stock — Clear all dismissals (re-show alerts)
router.post('/undismiss-low-stock', (req, res) => {
  const db = req.db;
  const result = (db as any).prepare(`
    UPDATE inventory_items SET low_stock_dismissed_at = NULL
    WHERE low_stock_dismissed_at IS NOT NULL
  `).run();
  res.json({ success: true, data: { undismissed: result.changes } });
});

// ==================== Stocktake / Inventory Count ====================

// POST /stocktake — Submit a stocktake (array of {item_id, counted_qty})
// SEC-H8: Admin or manager role required for stocktake operations
router.post('/stocktake', (req, res) => {
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
router.get('/stocktake/discrepancies', (req, res) => {
  const db = req.db;
  const items = db.prepare(`
    SELECT id, name, sku, in_stock, reorder_level, item_type
    FROM inventory_items
    WHERE is_active = 1 AND (in_stock < 0 OR in_stock > 1000)
    ORDER BY ABS(in_stock) DESC LIMIT 50
  `).all();
  res.json({ success: true, data: items });
});

export default router;
