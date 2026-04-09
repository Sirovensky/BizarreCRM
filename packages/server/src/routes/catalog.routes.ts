/**
 * Catalog routes — supplier catalog (Mobilesentrix / PhoneLcdParts)
 * and device models / manufacturers.
 */
import { Router, Request, Response, NextFunction } from 'express';
import type Database from 'better-sqlite3';
import type { AsyncDb } from '../db/async-db.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import {
  scrapeCatalog,
  searchCatalog,
  liveSearchSupplier,
  searchPartsUnified,
  type CatalogSource,
} from '../services/catalogScraper.js';

const router = Router();

// Admin-only middleware for mutating catalog operations
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  next();
}

// ─── Manufacturers ───────────────────────────────────────────────────────────

router.get('/manufacturers', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const rows = await adb.all(`
    SELECT m.*, COUNT(dm.id) AS model_count
    FROM manufacturers m
    LEFT JOIN device_models dm ON dm.manufacturer_id = m.id
    GROUP BY m.id
    ORDER BY m.name
  `);
  res.json({ success: true, data: rows });
}));

// ─── Device models ───────────────────────────────────────────────────────────

router.get('/devices', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const manufacturerId = req.query.manufacturer_id ? Number(req.query.manufacturer_id) : null;
  const category = (req.query.category as string) || null;
  const popular = req.query.popular === '1';
  const q = (req.query.q as string || '').trim();
  const limit = Math.min(200, parseInt(req.query.limit as string, 10) || 100);

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (manufacturerId) { conditions.push('dm.manufacturer_id = ?'); params.push(manufacturerId); }
  if (category) { conditions.push('dm.category = ?'); params.push(category); }
  if (popular) {
    // Show models that are either statically popular OR frequently repaired
    conditions.push('(dm.is_popular = 1 OR repair_count > 0)');
  }
  if (q) {
    conditions.push(`(dm.name LIKE ? OR m.name LIKE ?)`);
    params.push(`%${q}%`, `%${q}%`);
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  // Count how often each model appears in ticket_devices (fuzzy match by device_name)
  // This boosts frequently-repaired models to the top of the popular list
  const rows = await adb.all(`
    SELECT dm.*, m.name AS manufacturer_name, m.slug AS manufacturer_slug,
      COALESCE(rc.cnt, 0) AS repair_count
    FROM device_models dm
    JOIN manufacturers m ON m.id = dm.manufacturer_id
    LEFT JOIN (
      SELECT td.device_name, COUNT(*) AS cnt
      FROM ticket_devices td
      GROUP BY LOWER(td.device_name)
    ) rc ON LOWER(rc.device_name) = LOWER(dm.name)
    ${where}
    ORDER BY repair_count DESC, dm.is_popular DESC, m.name ASC, dm.release_year DESC, dm.name ASC
    LIMIT ?
  `, ...params, limit);

  res.json({ success: true, data: rows });
}));

// Single device model detail + compatible catalog items
router.get('/devices/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  const dm = await adb.get(`
    SELECT dm.*, m.name AS manufacturer_name
    FROM device_models dm
    JOIN manufacturers m ON m.id = dm.manufacturer_id
    WHERE dm.id = ?
  `, id);
  if (!dm) throw new AppError('Device model not found', 404);

  const [catalogItems, inventoryItems] = await Promise.all([
    adb.all(`
      SELECT sc.* FROM supplier_catalog sc
      JOIN catalog_device_compatibility cdc ON cdc.supplier_catalog_id = sc.id
      WHERE cdc.device_model_id = ?
      ORDER BY sc.price ASC
      LIMIT 100
    `, id),
    adb.all(`
      SELECT ii.id, ii.name, ii.sku, ii.in_stock, ii.retail_price, ii.item_type
      FROM inventory_items ii
      JOIN inventory_device_compatibility idc ON idc.inventory_item_id = ii.id
      WHERE idc.device_model_id = ?
      ORDER BY ii.name
    `, id),
  ]);

  res.json({ success: true, data: { ...(dm as any), catalog_items: catalogItems, inventory_items: inventoryItems } });
}));

// ─── Supplier catalog search ──────────────────────────────────────────────────

router.get('/search', asyncHandler(async (req, res) => {
  const q = (req.query.q as string) || '';
  const source = (req.query.source as string) || undefined;
  const deviceModelId = req.query.device_model_id ? Number(req.query.device_model_id) : undefined;
  const category = (req.query.category as string) || undefined;
  const limit = Math.min(100, parseInt(req.query.limit as string, 10) || 50);
  const offset = parseInt(req.query.offset as string, 10) || 0;

  const db = req.db;
  const result = searchCatalog(db, { q, source, deviceModelId, category, limit, offset });
  res.json({ success: true, data: { items: result.items, total: result.total, limit, offset } });
}));

// ─── Import catalog item to local inventory ───────────────────────────────────

router.post('/import/:catalogId', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const catalogId = Number(req.params.catalogId);
  const catalogItem = await adb.get<any>('SELECT * FROM supplier_catalog WHERE id = ?', catalogId);
  if (!catalogItem) throw new AppError('Catalog item not found', 404);

  const { markup_pct = 30, in_stock_qty = 0 } = req.body;
  const retailPrice = Math.round(catalogItem.price * (1 + markup_pct / 100) * 100) / 100;

  // Check if already in inventory by SKU
  if (catalogItem.sku) {
    const existing = await adb.get('SELECT id FROM inventory_items WHERE sku = ?', catalogItem.sku);
    if (existing) throw new AppError('Item already in inventory (matching SKU)', 409);
  }

  const result = await adb.run(`
    INSERT INTO inventory_items
      (name, sku, item_type, is_reorderable, cost_price, retail_price, in_stock,
       image_url, description, created_at)
    VALUES (?, ?, 'part', 1, ?, ?, ?, ?, ?, datetime('now'))
  `,
    catalogItem.name,
    catalogItem.sku || null,
    catalogItem.price,
    retailPrice,
    Number(in_stock_qty),
    catalogItem.image_url || null,
    `Imported from ${catalogItem.source}. ${catalogItem.product_url || ''}`.trim(),
  );

  const itemId = result.lastInsertRowid;

  // Copy device model compatibility
  const compatRows = await adb.all<{ device_model_id: number }>(
    'SELECT device_model_id FROM catalog_device_compatibility WHERE supplier_catalog_id = ?',
    catalogId,
  );

  for (const row of compatRows) {
    await adb.run(
      'INSERT OR IGNORE INTO inventory_device_compatibility (inventory_item_id, device_model_id) VALUES (?, ?)',
      itemId, row.device_model_id,
    );
  }

  const item = await adb.get('SELECT * FROM inventory_items WHERE id = ?', itemId);
  res.status(201).json({ success: true, data: item });
}));

// ─── Scrape / sync jobs ───────────────────────────────────────────────────────

const VALID_SOURCES: CatalogSource[] = ['mobilesentrix', 'phonelcdparts'];

router.post('/sync', adminOnly, asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const source = req.body.source as CatalogSource;
  if (!VALID_SOURCES.includes(source)) {
    throw new AppError(`source must be one of: ${VALID_SOURCES.join(', ')}`);
  }

  // Prevent concurrent sync jobs for the same source
  const activeJob = await adb.get<{ id: number }>(
    `SELECT id FROM scrape_jobs WHERE source = ? AND status IN ('pending', 'running') LIMIT 1`,
    source,
  );
  if (activeJob) {
    throw new AppError(`A sync job for ${source} is already in progress (job #${activeJob.id})`, 409);
  }

  // Start scrape in background — don't await
  const jobRow = await adb.run(
    `INSERT INTO scrape_jobs (source, status) VALUES (?, 'pending')`,
    source,
  );
  const jobId = jobRow.lastInsertRowid;

  // Fire and forget — scrapeCatalog expects sync db
  scrapeCatalog(db, source, jobId as number).catch((err) => {
    console.error(`[catalog:${source}] sync failed:`, err);
  });

  res.json({ success: true, data: { job_id: jobId, source, message: 'Sync started in background' } });
}));

router.get('/jobs', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const jobs = await adb.all(`
    SELECT * FROM scrape_jobs ORDER BY created_at DESC LIMIT 20
  `);
  res.json({ success: true, data: jobs });
}));

router.get('/jobs/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const job = await adb.get('SELECT * FROM scrape_jobs WHERE id = ?', Number(req.params.id));
  if (!job) throw new AppError('Job not found', 404);
  res.json({ success: true, data: job });
}));

// ─── Bulk import from CSV rows ────────────────────────────────────────────────
// Body: { source: string, items: [{sku, name, price, category, image_url, product_url, compatible_devices}] }
router.post('/bulk-import', adminOnly, asyncHandler(async (req, res) => {
  const db = req.db;
  const { source, items } = req.body as {
    source: string;
    items: Array<{
      sku?: string;
      name: string;
      price: number;
      category?: string;
      image_url?: string;
      product_url?: string;
      compatible_devices?: string[]; // array of device name strings
    }>;
  };

  if (!source) throw new AppError('source is required');
  if (!Array.isArray(items) || items.length === 0) throw new AppError('items array is required');

  let upserted = 0;

  const run = db.transaction(() => {
    for (const item of items) {
      if (!item.name || item.price == null) continue;

      const compatDevices = item.compatible_devices || [];
      const externalId = item.sku || item.name.toLowerCase().replace(/\s+/g, '-').substring(0, 60);

      const existing = db.prepare(
        'SELECT id FROM supplier_catalog WHERE source = ? AND external_id = ?'
      ).get(source, externalId) as { id: number } | undefined;

      let catalogId: number;
      if (existing) {
        db.prepare(`
          UPDATE supplier_catalog SET name=?,sku=?,category=?,price=?,image_url=?,product_url=?,
          compatible_devices=?,last_synced=datetime('now') WHERE id=?
        `).run(item.name, item.sku||null, item.category||null, item.price, item.image_url||null, item.product_url||null, JSON.stringify(compatDevices), existing.id);
        catalogId = existing.id;
      } else {
        const r = db.prepare(`
          INSERT INTO supplier_catalog (source,external_id,name,sku,category,price,image_url,product_url,compatible_devices)
          VALUES (?,?,?,?,?,?,?,?,?)
        `).run(source, externalId, item.name, item.sku||null, item.category||null, item.price, item.image_url||null, item.product_url||null, JSON.stringify(compatDevices));
        catalogId = r.lastInsertRowid as number;
      }

      // Match device models
      if (compatDevices.length > 0) {
        db.prepare('DELETE FROM catalog_device_compatibility WHERE supplier_catalog_id=?').run(catalogId);
        const ins = db.prepare('INSERT OR IGNORE INTO catalog_device_compatibility (supplier_catalog_id,device_model_id) VALUES (?,?)');
        for (const dn of compatDevices) {
          const dm = db.prepare(`
            SELECT id FROM device_models WHERE LOWER(name)=LOWER(?)
            UNION SELECT id FROM device_models WHERE LOWER(?) LIKE '%'||LOWER(name)||'%' LIMIT 1
          `).get(dn, dn) as {id:number}|undefined;
          if (dm) ins.run(catalogId, dm.id);
        }
      }
      upserted++;
    }
  });

  run();
  res.json({ success: true, data: { upserted, source } });
}));

// ─── Unified parts search (inventory first, then supplier catalog) ────────────
// ─── Auto-sync cost prices from supplier catalog ───────────────────────────
// Matches inventory items to supplier catalog by exact name or SKU, updates cost_price

// Device patterns for fuzzy matching
const DEVICE_RX: [RegExp, (m: RegExpMatchArray) => string][] = [
  [/(?:samsung\s+)?(?:galaxy\s+)?(s\d+)\s*(ultra|plus|\+|fe|lite)?/i, (m) => 'galaxy ' + m[1].toLowerCase() + (m[2] ? ' ' + m[2].toLowerCase() : '')],
  [/(?:samsung\s+)?(?:galaxy\s+)?(a\d+)/i, (m) => 'galaxy ' + m[1].toLowerCase()],
  [/(?:samsung\s+)?(?:galaxy\s+)?(z\s*(?:fold|flip)\s*\d*)/i, (m) => 'galaxy ' + m[1].toLowerCase()],
  [/(?:samsung\s+)?(?:galaxy\s+)?(note\s*\d+)/i, (m) => 'galaxy ' + m[1].toLowerCase()],
  [/(?:samsung\s+)?(?:galaxy\s+)?(tab\s+\w+)\s*([\d.]+)?/i, (m) => 'galaxy ' + m[1].toLowerCase() + (m[2] ? ' ' + m[2] : '')],
  [/iphone\s*(\d+)\s*(pro\s*max|pro|plus|mini)?/i, (m) => 'iphone ' + m[1] + (m[2] ? ' ' + m[2].toLowerCase() : '')],
  [/ipad\s*(pro|air|mini)?\s*([\d."]+)?/i, (m) => 'ipad' + (m[1] ? ' ' + m[1].toLowerCase() : '') + (m[2] ? ' ' + m[2] : '')],
  [/ipod\s*(classic|touch|nano|shuffle)\s*(\d+)?/i, (m) => 'ipod ' + m[1].toLowerCase()],
  [/pixel\s*(\d+)\s*(pro|a|xl)?/i, (m) => 'pixel ' + m[1] + (m[2] ? ' ' + m[2].toLowerCase() : '')],
];

function extractDevice(name: string): string | null {
  for (const [rx, fmt] of DEVICE_RX) {
    const m = name.match(rx);
    if (m) return fmt(m);
  }
  return null;
}

type SyncMatch = { item_id: number; item_name: string; catalog_name: string; price: number; method: string };

export function syncCostPricesFromCatalog(db: Database.Database): { updated: number; matched: number; details: SyncMatch[] } {
  type AnyRow = Record<string, any>;
  const details: SyncMatch[] = [];
  let updated = 0;

  // 1. Exact SKU match (bulk SQL)
  const skuResult = (db as any).prepare(`
    UPDATE inventory_items SET cost_price = (
      SELECT MIN(sc.price) FROM supplier_catalog sc
      WHERE sc.sku IS NOT NULL AND sc.sku != '' AND sc.sku = inventory_items.sku AND sc.price > 0
    )
    WHERE (cost_price IS NULL OR cost_price = 0) AND is_active = 1
      AND sku IS NOT NULL AND sku != ''
      AND EXISTS (SELECT 1 FROM supplier_catalog sc WHERE sc.sku = inventory_items.sku AND sc.price > 0)
  `).run();
  updated += skuResult.changes;

  // 2. Exact name match (bulk SQL)
  const nameResult = (db as any).prepare(`
    UPDATE inventory_items SET cost_price = (
      SELECT MIN(sc.price) FROM supplier_catalog sc
      WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(inventory_items.name)) AND sc.price > 0
    )
    WHERE (cost_price IS NULL OR cost_price = 0) AND is_active = 1
      AND EXISTS (SELECT 1 FROM supplier_catalog sc WHERE LOWER(TRIM(sc.name)) = LOWER(TRIM(inventory_items.name)) AND sc.price > 0)
  `).run();
  updated += nameResult.changes;

  // 3. Fuzzy device+part matching (row by row for remaining $0 items)
  const remaining = (db as any).prepare(`
    SELECT id, name FROM inventory_items
    WHERE is_active = 1 AND (cost_price IS NULL OR cost_price = 0)
  `).all() as AnyRow[];

  const updateStmt = (db as any).prepare("UPDATE inventory_items SET cost_price = ?, is_reorderable = 1, item_type = 'part', updated_at = datetime('now') WHERE id = ?");

  for (const item of remaining) {
    const lower = (item.name || '').toLowerCase();
    const device = extractDevice(item.name || '');
    if (!device) continue; // Only phone/tablet parts

    // Determine part type search terms + exclusions
    let partTerms: string[] = [];
    let excludes: string[] = [];

    if (/screen|lcd|oled|display|assembly/i.test(lower)) {
      partTerms = ['assembly'];
      excludes = ['protector', 'mold', 'polishing', 'cable', 'tester', 'adhesive', 'tape', 'stencil'];
    } else if (/battery/i.test(lower)) {
      partTerms = ['battery'];
      excludes = ['cable', 'connector', 'adhesive', 'sticker'];
    } else if (/back camera|rear camera/i.test(lower)) {
      partTerms = ['back camera'];
    } else if (/front camera/i.test(lower)) {
      partTerms = ['front camera'];
    } else if (/camera/i.test(lower)) {
      partTerms = ['camera'];
      excludes = ['lens', 'glass', 'sticker', 'bracket'];
    } else if (/charging|charge port|dock/i.test(lower)) {
      partTerms = ['charging port'];
    } else if (/back cover|back glass|housing/i.test(lower)) {
      partTerms = ['back cover'];
    } else if (/speaker/i.test(lower)) {
      partTerms = ['speaker'];
    } else if (/glass/i.test(lower)) {
      partTerms = ['glass'];
    } else {
      continue; // Unknown part type
    }

    // Build SQL
    let sql = 'SELECT name, MIN(price) as price FROM supplier_catalog WHERE price > 0';
    const params: string[] = [];

    // Device terms (split multi-word device into separate LIKE clauses)
    for (const word of device.split(/\s+/)) {
      sql += ' AND LOWER(name) LIKE ?';
      params.push(`%${word}%`);
    }

    // Part terms
    for (const pt of partTerms) {
      sql += ' AND LOWER(name) LIKE ?';
      params.push(`%${pt}%`);
    }

    // Exclusions
    for (const ex of excludes) {
      sql += ' AND LOWER(name) NOT LIKE ?';
      params.push(`%${ex}%`);
    }

    // Quality preference
    const quality = /oem|original|service pack/i.test(lower) ? 'oem' :
                    /premium/i.test(lower) ? 'premium' : null;

    let finalSql = sql;
    let finalParams = [...params];
    if (quality) {
      finalSql += ' AND LOWER(name) LIKE ?';
      finalParams.push(`%${quality}%`);
    }

    let match = (db as any).prepare(finalSql).get(...finalParams) as AnyRow | undefined;
    if (!match || !match.price) {
      // Retry without quality filter
      match = (db as any).prepare(sql).get(...params) as AnyRow | undefined;
    }

    if (match && match.price > 0) {
      updateStmt.run(match.price, item.id);
      updated++;
      details.push({ item_id: item.id, item_name: item.name, catalog_name: match.name, price: match.price, method: 'fuzzy' });
    }
  }

  // 4. Update retail_price if $0 (cost * 1.4 markup)
  (db as any).prepare(`
    UPDATE inventory_items SET retail_price = ROUND(cost_price * 1.4, 2)
    WHERE cost_price > 0 AND (retail_price IS NULL OR retail_price = 0) AND is_active = 1
  `).run();

  const matched = updated;
  console.log(`[CatalogSync] Updated ${updated} inventory cost prices from supplier catalog`);
  return { updated, matched, details };
}

router.post('/sync-cost-prices', adminOnly, asyncHandler(async (req, res) => {
  const db = req.db;
  const result = syncCostPricesFromCatalog(db);
  res.json({ success: true, data: result });
}));

// Used when adding parts to a ticket device.
// ?q=    search query (required, min 2 chars)
// ?device_model_id=   filter results to a device model
// ?source=            only search one supplier (mobilesentrix|phonelcdparts)
// ?live=0             skip live scrape fallback (default: 1 = allow live)
router.get('/parts-search', asyncHandler(async (req, res) => {
  const q = (req.query.q as string || '').trim();
  if (q.length < 2) {
    res.json({ success: true, data: { inventoryItems: [], supplierItems: [] } });
    return;
  }
  const deviceModelId = req.query.device_model_id ? Number(req.query.device_model_id) : undefined;
  const source = (req.query.source as string) || undefined;
  const liveFallback = req.query.live !== '0';

  const db = req.db;
  const result = await searchPartsUnified(db, { q, deviceModelId, source, liveFallback });
  res.json({ success: true, data: result });
}));

// ─── Live search on supplier website ──────────────────────────────────────────
// Immediately scrapes first-page results from the supplier for a query.
// Results are cached in supplier_catalog for future searches.
// POST body: { source: 'mobilesentrix'|'phonelcdparts', q: string }
router.post('/live-search', asyncHandler(async (req, res) => {
  const { source, q } = req.body as { source: CatalogSource; q: string };
  if (!VALID_SOURCES.includes(source)) throw new AppError(`source must be one of: ${VALID_SOURCES.join(', ')}`);
  if (!q || q.trim().length < 2) throw new AppError('q must be at least 2 characters');

  const db = req.db;
  try {
    const products = await liveSearchSupplier(db, source, q.trim());
    res.json({ success: true, data: { products, count: products.length, source, query: q.trim() } });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Search failed';
    res.status(502).json({ success: false, message: `Supplier search failed: ${message}` });
  }
}));

// ─── Parts order queue ────────────────────────────────────────────────────────

// GET /catalog/order-queue — list all pending/ordered parts
router.get('/order-queue', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const status = (req.query.status as string) || 'pending';
  const rows = await adb.all(`
    SELECT poq.*,
      (SELECT json_group_array(json_object(
        'ticket_id', poqt.ticket_id,
        'order_id', t.order_id,
        'customer', c.first_name || ' ' || c.last_name
      ))
      FROM parts_order_queue_tickets poqt
      JOIN tickets t ON t.id = poqt.ticket_id
      JOIN customers c ON c.id = t.customer_id
      WHERE poqt.parts_order_queue_id = poq.id
      ) AS tickets_json
    FROM parts_order_queue poq
    WHERE poq.status = ?
    ORDER BY poq.created_at DESC
  `, status);

  const items = rows.map((r: any) => ({
    ...r,
    tickets: (() => {
      try { return JSON.parse(r.tickets_json || '[]'); } catch { return []; }
    })(),
  }));

  res.json({ success: true, data: items });
}));

// POST /catalog/order-queue/add — add a part to the order queue
router.post('/order-queue/add', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const {
    source, catalog_item_id, inventory_item_id, name, sku, supplier_url,
    image_url, unit_price, quantity_needed = 1, ticket_device_part_id, ticket_id, notes,
  } = req.body;

  if (!name) throw new AppError('name is required');

  // Upsert — if same catalog_item_id already pending, increment quantity
  let queueId: number | bigint;
  if (catalog_item_id) {
    const existing = await adb.get<{ id: number }>(
      `SELECT id FROM parts_order_queue WHERE catalog_item_id = ? AND status = 'pending'`,
      catalog_item_id,
    );

    if (existing) {
      await adb.run(
        `UPDATE parts_order_queue SET quantity_needed = quantity_needed + ?, updated_at = datetime('now') WHERE id = ?`,
        quantity_needed, existing.id,
      );
      queueId = existing.id;
    } else {
      const r = await adb.run(`
        INSERT INTO parts_order_queue (source,catalog_item_id,inventory_item_id,name,sku,supplier_url,image_url,unit_price,quantity_needed,notes)
        VALUES (?,?,?,?,?,?,?,?,?,?)
      `,
        source || 'manual', catalog_item_id || null, inventory_item_id || null,
        name, sku || null, supplier_url || null, image_url || null,
        unit_price || 0, quantity_needed, notes || null,
      );
      queueId = r.lastInsertRowid;
    }
  } else {
    const r = await adb.run(`
      INSERT INTO parts_order_queue (source,catalog_item_id,inventory_item_id,name,sku,supplier_url,image_url,unit_price,quantity_needed,notes)
      VALUES (?,?,?,?,?,?,?,?,?,?)
    `,
      source || 'manual', null, inventory_item_id || null,
      name, sku || null, supplier_url || null, image_url || null,
      unit_price || 0, quantity_needed, notes || null,
    );
    queueId = r.lastInsertRowid;
  }

  // Link to ticket
  if (ticket_device_part_id && ticket_id) {
    await adb.run(`
      INSERT OR IGNORE INTO parts_order_queue_tickets (parts_order_queue_id, ticket_device_part_id, ticket_id, quantity)
      VALUES (?,?,?,?)
    `, queueId, ticket_device_part_id, ticket_id, quantity_needed);

    // Mark the ticket_device_part as 'ordered'
    await adb.run(`UPDATE ticket_device_parts SET status = 'ordered' WHERE id = ?`, ticket_device_part_id);
  }

  const item = await adb.get('SELECT * FROM parts_order_queue WHERE id = ?', queueId);
  res.json({ success: true, data: item });
}));

// GET /catalog/order-queue/summary — dashboard badge: count of pending items
// (Must be before /order-queue/:id to avoid route conflict)
router.get('/order-queue/summary', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const row = await adb.get(`
    SELECT
      COUNT(*) AS total_items,
      SUM(quantity_needed) AS total_qty,
      SUM(unit_price * quantity_needed) AS estimated_cost
    FROM parts_order_queue
    WHERE status = 'pending'
  `);
  res.json({ success: true, data: row });
}));

// PATCH /catalog/order-queue/:id — update status (mark ordered, received, cancelled)
router.patch('/order-queue/:id', asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  const { status, notes } = req.body;
  const allowed = ['pending', 'ordered', 'received', 'cancelled'];
  if (status && !allowed.includes(status)) throw new AppError(`status must be one of: ${allowed.join(', ')}`);

  const sets: string[] = ['updated_at = datetime(\'now\')'];
  const params: unknown[] = [];
  if (status) { sets.push('status = ?'); params.push(status); }
  if (notes !== undefined) { sets.push('notes = ?'); params.push(notes); }

  const updateQueue = db.transaction(() => {
    db.prepare(`UPDATE parts_order_queue SET ${sets.join(', ')} WHERE id = ?`).run(...params, id);

    // If received, bump inventory stock and record stock movement
    if (status === 'received') {
      const item = db.prepare('SELECT * FROM parts_order_queue WHERE id = ?').get(id) as any;
      if (item?.inventory_item_id) {
        db.prepare(`UPDATE inventory_items SET in_stock = in_stock + ? WHERE id = ?`)
          .run(item.quantity_needed, item.inventory_item_id);
        db.prepare(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
          VALUES (?, 'received', ?, 'order_queue', ?, ?, ?, datetime('now'), datetime('now'))
        `).run(item.inventory_item_id, item.quantity_needed, id, `Parts order received: ${item.name || ''}`.trim(), req.user!.id);
      }
    }
  });
  updateQueue();

  const updated = await adb.get('SELECT * FROM parts_order_queue WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

// ─── Template catalog pre-population ─────────────────────────────────────────

// POST /catalog/load-from-template — Copy catalog from template DB to tenant
router.post('/load-from-template', adminOnly, asyncHandler(async (req, res) => {
  const { copyTemplateCatalogToTenant } = await import('../services/catalogSync.js');
  const result = copyTemplateCatalogToTenant(req.db);
  res.json({ success: true, data: { copied: result.copied } });
}));

// GET /catalog/template-count — How many items in the shared template catalog
router.get('/template-count', asyncHandler(async (req, res) => {
  const { getTemplateCatalogCount } = await import('../services/catalogSync.js');
  res.json({ success: true, data: { count: getTemplateCatalogCount() } });
}));

// ─── Stats ───────────────────────────────────────────────────────────────────

router.get('/stats', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const stats = await adb.get(`
    SELECT
      (SELECT COUNT(*) FROM supplier_catalog WHERE source = 'mobilesentrix') AS mobilesentrix_count,
      (SELECT COUNT(*) FROM supplier_catalog WHERE source = 'phonelcdparts') AS phonelcdparts_count,
      (SELECT COUNT(*) FROM supplier_catalog) AS total_catalog,
      (SELECT MAX(last_synced) FROM supplier_catalog WHERE source = 'mobilesentrix') AS mobilesentrix_last_sync,
      (SELECT MAX(last_synced) FROM supplier_catalog WHERE source = 'phonelcdparts') AS phonelcdparts_last_sync,
      (SELECT COUNT(*) FROM manufacturers) AS manufacturer_count,
      (SELECT COUNT(*) FROM device_models) AS device_model_count
  `);
  res.json({ success: true, data: stats });
}));

export default router;
