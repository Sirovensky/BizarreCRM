import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler.js';

const router = Router();

// Admin-only middleware for mutating global pricing adjustments
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  next();
}

// ==================== Helper: apply global adjustments ====================

function getAdjustments(db: any): { flat: number; pct: number } {
  const flatRow = db.prepare("SELECT value FROM store_config WHERE key = 'repair_price_flat_adjustment'").get() as any;
  const pctRow = db.prepare("SELECT value FROM store_config WHERE key = 'repair_price_pct_adjustment'").get() as any;
  return {
    flat: flatRow ? parseFloat(flatRow.value) || 0 : 0,
    pct: pctRow ? parseFloat(pctRow.value) || 0 : 0,
  };
}

function applyAdjustment(basePrice: number, adj: { flat: number; pct: number }): number {
  let price = basePrice;
  if (adj.pct !== 0) price = price * (1 + adj.pct / 100);
  if (adj.flat !== 0) price = price + adj.flat;
  return Math.round(price * 100) / 100;
}

// ==================== Repair Services CRUD ====================

router.get('/services', (_req, res) => {
  const db = _req.db;
  const { category } = _req.query;
  let sql = 'SELECT * FROM repair_services';
  const params: any[] = [];
  if (category) {
    sql += ' WHERE category = ?';
    params.push(category);
  }
  sql += ' ORDER BY category ASC, sort_order ASC';
  const services = db.prepare(sql).all(...params);
  res.json({ success: true, data: services });
});

router.post('/services', (req, res) => {
  const db = req.db;
  const { name, slug, category, description, is_active = 1, sort_order = 0 } = req.body;
  if (!name || !slug) throw new AppError('Name and slug are required', 400);

  const existing = db.prepare('SELECT id FROM repair_services WHERE slug = ?').get(slug);
  if (existing) throw new AppError('A service with this slug already exists', 400);

  const result = db.prepare(`
    INSERT INTO repair_services (name, slug, category, description, is_active, sort_order)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(name, slug, category || null, description || null, is_active, sort_order);

  const service = db.prepare('SELECT * FROM repair_services WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: service });
});

router.put('/services/:id', (req, res) => {
  const db = req.db;
  const { name, slug, category, description, is_active, sort_order } = req.body;
  const existing = db.prepare('SELECT id FROM repair_services WHERE id = ?').get(req.params.id);
  if (!existing) throw new AppError('Service not found', 404);

  if (slug) {
    const dup = db.prepare('SELECT id FROM repair_services WHERE slug = ? AND id != ?').get(slug, req.params.id);
    if (dup) throw new AppError('A service with this slug already exists', 400);
  }

  db.prepare(`
    UPDATE repair_services SET
      name = COALESCE(?, name), slug = COALESCE(?, slug), category = COALESCE(?, category),
      description = COALESCE(?, description), is_active = COALESCE(?, is_active),
      sort_order = COALESCE(?, sort_order), updated_at = datetime('now')
    WHERE id = ?
  `).run(name ?? null, slug ?? null, category ?? null, description ?? null,
    is_active ?? null, sort_order ?? null, req.params.id);

  const service = db.prepare('SELECT * FROM repair_services WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: service });
});

router.delete('/services/:id', (req, res) => {
  const db = req.db;
  const inUse = db.prepare('SELECT COUNT(*) as c FROM repair_prices WHERE repair_service_id = ?').get(req.params.id) as any;
  if (inUse.c > 0) throw new AppError('Service is in use by repair prices', 400);
  db.prepare('DELETE FROM repair_services WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Service deleted' } });
});

// ==================== Repair Prices CRUD ====================

router.get('/prices', (req, res) => {
  const db = req.db;
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
  const prices = db.prepare(sql).all(...params);
  res.json({ success: true, data: prices });
});

router.post('/prices', (req, res) => {
  const db = req.db;
  const { device_model_id, repair_service_id, labor_price = 0, default_grade = 'aftermarket', is_active = 1, grades } = req.body;
  if (!device_model_id || !repair_service_id) throw new AppError('device_model_id and repair_service_id are required', 400);

  const existing = db.prepare('SELECT id FROM repair_prices WHERE device_model_id = ? AND repair_service_id = ?')
    .get(device_model_id, repair_service_id);
  if (existing) throw new AppError('A price already exists for this device model and service', 400);

  const insertPrice = db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO repair_prices (device_model_id, repair_service_id, labor_price, default_grade, is_active)
      VALUES (?, ?, ?, ?, ?)
    `).run(device_model_id, repair_service_id, labor_price, default_grade, is_active);

    const priceId = result.lastInsertRowid;

    if (grades && Array.isArray(grades)) {
      const insertGrade = db.prepare(`
        INSERT INTO repair_price_grades (repair_price_id, grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price, labor_price_override, is_default, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      for (const g of grades) {
        insertGrade.run(
          priceId, g.grade, g.grade_label,
          g.part_inventory_item_id || null, g.part_catalog_item_id || null,
          g.part_price || 0, g.labor_price_override ?? null,
          g.is_default ? 1 : 0, g.sort_order || 0
        );
      }
    }

    return priceId;
  });

  const priceId = insertPrice();
  const price = db.prepare(`
    SELECT rp.*, dm.name as device_model_name, m.name as manufacturer_name,
           rs.name as repair_service_name, rs.slug as repair_service_slug, rs.category as service_category
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    JOIN manufacturers m ON m.id = dm.manufacturer_id
    JOIN repair_services rs ON rs.id = rp.repair_service_id
    WHERE rp.id = ?
  `).get(priceId);

  const priceGrades = db.prepare('SELECT * FROM repair_price_grades WHERE repair_price_id = ? ORDER BY sort_order ASC').all(priceId);

  res.status(201).json({ success: true, data: { ...price as any, grades: priceGrades } });
});

router.put('/prices/:id', (req, res) => {
  const db = req.db;
  const existing = db.prepare('SELECT id FROM repair_prices WHERE id = ?').get(req.params.id);
  if (!existing) throw new AppError('Price not found', 404);

  const { labor_price, default_grade, is_active } = req.body;
  db.prepare(`
    UPDATE repair_prices SET
      labor_price = COALESCE(?, labor_price), default_grade = COALESCE(?, default_grade),
      is_active = COALESCE(?, is_active), updated_at = datetime('now')
    WHERE id = ?
  `).run(labor_price ?? null, default_grade ?? null, is_active ?? null, req.params.id);

  const price = db.prepare('SELECT * FROM repair_prices WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: price });
});

router.delete('/prices/:id', (req, res) => {
  const db = req.db;
  db.prepare('DELETE FROM repair_prices WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Price deleted' } });
});

// ==================== Lookup (for check-in wizard) ====================

router.get('/lookup', (req, res) => {
  const db = req.db;
  const { device_model_id, repair_service_id } = req.query;
  if (!device_model_id || !repair_service_id) throw new AppError('device_model_id and repair_service_id are required', 400);

  const price = db.prepare(`
    SELECT rp.*, dm.name as device_model_name, m.name as manufacturer_name,
           rs.name as repair_service_name, rs.slug as repair_service_slug
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    JOIN manufacturers m ON m.id = dm.manufacturer_id
    JOIN repair_services rs ON rs.id = rp.repair_service_id
    WHERE rp.device_model_id = ? AND rp.repair_service_id = ?
  `).get(device_model_id, repair_service_id) as any;

  if (!price) {
    res.json({ success: true, data: null });
    return;
  }

  const grades = db.prepare(`
    SELECT rpg.*,
           ii.name as inventory_item_name, ii.in_stock as inventory_in_stock, ii.price as inventory_price,
           sc.name as catalog_item_name, sc.price as catalog_price, sc.url as catalog_url
    FROM repair_price_grades rpg
    LEFT JOIN inventory_items ii ON ii.id = rpg.part_inventory_item_id
    LEFT JOIN supplier_catalog sc ON sc.id = rpg.part_catalog_item_id
    WHERE rpg.repair_price_id = ?
    ORDER BY rpg.sort_order ASC
  `).all(price.id);

  const adj = getAdjustments(db);
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
});

// ==================== Grade Management ====================

router.get('/prices/:id/grades', (req, res) => {
  const db = req.db;
  const priceExists = db.prepare('SELECT id FROM repair_prices WHERE id = ?').get(req.params.id);
  if (!priceExists) throw new AppError('Price not found', 404);

  const grades = db.prepare(`
    SELECT rpg.*,
           ii.name as inventory_item_name, ii.in_stock as inventory_in_stock,
           sc.name as catalog_item_name, sc.url as catalog_url
    FROM repair_price_grades rpg
    LEFT JOIN inventory_items ii ON ii.id = rpg.part_inventory_item_id
    LEFT JOIN supplier_catalog sc ON sc.id = rpg.part_catalog_item_id
    WHERE rpg.repair_price_id = ?
    ORDER BY rpg.sort_order ASC
  `).all(req.params.id);

  res.json({ success: true, data: grades });
});

router.post('/prices/:id/grades', (req, res) => {
  const db = req.db;
  const priceExists = db.prepare('SELECT id FROM repair_prices WHERE id = ?').get(req.params.id);
  if (!priceExists) throw new AppError('Price not found', 404);

  const { grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price = 0, labor_price_override, is_default = 0, sort_order = 0 } = req.body;
  if (!grade || !grade_label) throw new AppError('grade and grade_label are required', 400);

  const result = db.prepare(`
    INSERT INTO repair_price_grades (repair_price_id, grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price, labor_price_override, is_default, sort_order)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(req.params.id, grade, grade_label, part_inventory_item_id || null, part_catalog_item_id || null,
    part_price, labor_price_override ?? null, is_default ? 1 : 0, sort_order);

  const gradeRow = db.prepare('SELECT * FROM repair_price_grades WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: gradeRow });
});

router.put('/grades/:id', (req, res) => {
  const db = req.db;
  const existing = db.prepare('SELECT id FROM repair_price_grades WHERE id = ?').get(req.params.id);
  if (!existing) throw new AppError('Grade not found', 404);

  const { grade, grade_label, part_inventory_item_id, part_catalog_item_id, part_price, labor_price_override, is_default, sort_order } = req.body;
  db.prepare(`
    UPDATE repair_price_grades SET
      grade = COALESCE(?, grade), grade_label = COALESCE(?, grade_label),
      part_inventory_item_id = COALESCE(?, part_inventory_item_id),
      part_catalog_item_id = COALESCE(?, part_catalog_item_id),
      part_price = COALESCE(?, part_price), labor_price_override = ?,
      is_default = COALESCE(?, is_default), sort_order = COALESCE(?, sort_order)
    WHERE id = ?
  `).run(grade ?? null, grade_label ?? null, part_inventory_item_id ?? null,
    part_catalog_item_id ?? null, part_price ?? null,
    labor_price_override !== undefined ? labor_price_override : null,
    is_default ?? null, sort_order ?? null, req.params.id);

  const gradeRow = db.prepare('SELECT * FROM repair_price_grades WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: gradeRow });
});

router.delete('/grades/:id', (req, res) => {
  const db = req.db;
  db.prepare('DELETE FROM repair_price_grades WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Grade deleted' } });
});

// ==================== Global Adjustments ====================

router.get('/adjustments', (_req, res) => {
  const db = _req.db;
  const adj = getAdjustments(db);
  res.json({ success: true, data: adj });
});

router.put('/adjustments', adminOnly, (req, res) => {
  const db = req.db;
  const { flat, pct } = req.body;
  const upsert = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const update = db.transaction(() => {
    if (flat !== undefined) upsert.run('repair_price_flat_adjustment', String(flat));
    if (pct !== undefined) upsert.run('repair_price_pct_adjustment', String(pct));
  });
  update();
  const adj = getAdjustments(db);
  res.json({ success: true, data: adj });
});

export default router;
