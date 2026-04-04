import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import multer from 'multer';
import path from 'path';
import crypto from 'crypto';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { config } from '../config.js';

const router = Router();

// Multer for logo upload
const logoUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, config.uploadsPath),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
      const safe = ext && ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(ext) ? ext : '.jpg';
      cb(null, `logo-${Date.now()}-${crypto.randomBytes(4).toString('hex')}${safe}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPEG, PNG, WebP, GIF images allowed'));
  },
});

// Admin-only middleware for mutating settings
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
  next();
}

// Allowed config keys (T1.2: prevent arbitrary key injection)
const ALLOWED_CONFIG_KEYS = new Set([
  // Store info
  'store_name', 'store_address', 'store_phone', 'store_email', 'store_timezone', 'store_currency',
  'receipt_header', 'receipt_footer', 'logo_url',
  // Ticket settings
  'ticket_show_inventory', 'ticket_show_closed', 'ticket_show_empty', 'ticket_show_parts_column',
  'ticket_allow_edit_closed', 'ticket_allow_delete_after_invoice', 'ticket_allow_edit_after_invoice',
  'ticket_auto_close_on_invoice', 'ticket_all_employees_view_all', 'ticket_require_stopwatch',
  'ticket_auto_status_on_reply', 'ticket_auto_remove_passcode', 'ticket_copy_warranty_notes',
  'ticket_default_assignment', 'ticket_default_view', 'ticket_default_filter',
  'ticket_default_date_sort', 'ticket_default_pagination', 'ticket_default_sort_order',
  'ticket_status_after_estimate', 'ticket_label_template',
  'ticket_timer_auto_start_status', 'ticket_timer_auto_stop_status',
  // Repair settings
  'repair_require_pre_condition', 'repair_require_post_condition', 'repair_require_parts',
  'repair_require_customer', 'repair_require_diagnostic', 'repair_require_imei',
  'repair_itemize_line_items', 'repair_price_includes_parts',
  'repair_default_warranty_value', 'repair_default_warranty_unit',
  'repair_default_input_criteria', 'repair_default_due_value', 'repair_default_due_unit',
  // POS settings
  'pos_show_products', 'pos_show_repairs', 'pos_show_miscellaneous', 'pos_show_bundles',
  'pos_show_out_of_stock', 'pos_show_invoice_notes', 'pos_show_outstanding_alert',
  'pos_show_images', 'pos_show_discount_reason', 'pos_show_cost_price',
  'pos_require_pin_sale', 'pos_require_pin_ticket', 'pos_require_referral',
  'checkin_default_category', 'checkin_auto_print_label',
  // Invoice/receipt settings
  'invoice_logo', 'invoice_title', 'invoice_payment_terms', 'invoice_slogan', 'invoice_footer',
  'invoice_terms', 'invoice_signature_terms', 'invoice_refund_terms', 'invoice_review_url',
  'receipt_logo', 'receipt_title', 'receipt_terms', 'receipt_footer',
  'receipt_thermal_terms', 'receipt_thermal_footer',
  'label_width_mm', 'label_height_mm',
  // Tax defaults
  'tax_default_parts', 'tax_default_services', 'tax_default_accessories',
  // Backup
  'backup_path', 'backup_schedule', 'backup_retention', 'backup_last_run', 'backup_last_status',
  // Repair pricing
  'repair_price_flat_adjustment', 'repair_price_pct_adjustment',
  // SMS
  'sms_provider', 'stall_alert_days', 'review_request_delay_hours',
  // Customer feedback
  'feedback_enabled', 'feedback_auto_sms', 'feedback_sms_template', 'feedback_delay_hours',
  // Business hours + logo
  'business_hours', 'store_logo',
  // Receipt configuration toggles
  'receipt_cfg_pre_conditions_page', 'receipt_cfg_pre_conditions_thermal',
  'receipt_cfg_post_conditions_page',
  'receipt_cfg_signature_page', 'receipt_cfg_signature_thermal',
  'receipt_cfg_po_so_page', 'receipt_cfg_po_so_thermal',
  'receipt_cfg_security_code_page', 'receipt_cfg_security_code_thermal',
  'receipt_cfg_tax', 'receipt_cfg_discount_thermal',
  'receipt_cfg_line_price_incl_tax_thermal',
  'receipt_cfg_transaction_id_page', 'receipt_cfg_transaction_id_thermal',
  'receipt_cfg_due_date',
  'receipt_cfg_employee_name',
  'receipt_cfg_description_page', 'receipt_cfg_description_thermal',
  'receipt_cfg_parts_page', 'receipt_cfg_parts_thermal',
  'receipt_cfg_part_sku',
  'receipt_cfg_network_thermal',
  'receipt_cfg_service_desc_page', 'receipt_cfg_service_desc_thermal',
  'receipt_cfg_device_location',
  'receipt_cfg_barcode',
  'receipt_default_size',
  // BlockChyp payment terminal
  'blockchyp_enabled', 'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'blockchyp_terminal_name', 'blockchyp_test_mode',
  'blockchyp_tc_enabled', 'blockchyp_tc_content', 'blockchyp_tc_name',
  'blockchyp_prompt_for_tip', 'blockchyp_sig_required_payment',
  'blockchyp_sig_format', 'blockchyp_sig_width', 'blockchyp_auto_close_ticket',
]);

// ==================== Generic Config (key-value) ====================

// Sensitive config keys only visible to admins
const SENSITIVE_CONFIG_KEYS = new Set([
  'tcx_password', 'smtp_user', 'smtp_from', 'smtp_host', 'smtp_port',
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
]);

router.get('/config', (req, res) => {
  const rows = db.prepare('SELECT key, value FROM store_config').all() as any[];
  const isAdmin = req.user?.role === 'admin';
  const config: Record<string, string> = {};
  for (const row of rows) {
    if (!isAdmin && SENSITIVE_CONFIG_KEYS.has(row.key)) continue;
    config[row.key] = row.value;
  }
  res.json({ success: true, data: config });
});

router.put('/config', adminOnly, (req, res) => {
  const update = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const updateMany = db.transaction((data: Record<string, string>) => {
    for (const [key, value] of Object.entries(data)) {
      if (!ALLOWED_CONFIG_KEYS.has(key)) continue; // T1.2: skip unknown keys
      update.run(key, String(value));
    }
  });
  updateMany(req.body);
  // Return all config
  const rows = db.prepare('SELECT key, value FROM store_config').all() as any[];
  const config: Record<string, string> = {};
  for (const row of rows) config[row.key] = row.value;
  res.json({ success: true, data: config });
});

// ==================== Store Settings ====================

router.get('/store', (_req, res) => {
  const rows = db.prepare('SELECT key, value FROM store_config').all() as any[];
  const config: Record<string, string> = {};
  for (const row of rows) config[row.key] = row.value;
  res.json({ success: true, data: { store: config } });
});

router.put('/store', adminOnly, (req, res) => {
  const allowed = ['store_name','address','phone','email','timezone','currency','tax_rate','receipt_header','receipt_footer','logo_url','sms_provider','tcx_host','tcx_extension','tcx_password','smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
  const update = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const updateMany = db.transaction((data: Record<string, string>) => {
    for (const [key, value] of Object.entries(data)) {
      if (allowed.includes(key)) update.run(key, String(value));
    }
  });
  updateMany(req.body);
  const rows = db.prepare('SELECT key, value FROM store_config').all() as any[];
  const config: Record<string, string> = {};
  for (const row of rows) config[row.key] = row.value;
  res.json({ success: true, data: { store: config } });
});

// ==================== Ticket Statuses ====================

router.get('/statuses', (_req, res) => {
  const statuses = db.prepare('SELECT * FROM ticket_statuses ORDER BY sort_order ASC').all();
  res.json({ success: true, data: { statuses } });
});

router.post('/statuses', adminOnly, (req, res) => {
  const { name, color = '#6b7280', sort_order = 0, is_default = 0, is_closed = 0, is_cancelled = 0, notify_customer = 0, notification_template } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = db.prepare(`
    INSERT INTO ticket_statuses (name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template || null);
  const status = db.prepare('SELECT * FROM ticket_statuses WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { status } });
});

router.put('/statuses/:id', adminOnly, (req, res) => {
  const { name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template } = req.body;
  db.prepare(`
    UPDATE ticket_statuses SET
      name = COALESCE(?, name), color = COALESCE(?, color), sort_order = COALESCE(?, sort_order),
      is_default = COALESCE(?, is_default), is_closed = COALESCE(?, is_closed),
      is_cancelled = COALESCE(?, is_cancelled), notify_customer = COALESCE(?, notify_customer),
      notification_template = COALESCE(?, notification_template)
    WHERE id = ?
  `).run(name ?? null, color ?? null, sort_order ?? null, is_default ?? null, is_closed ?? null,
    is_cancelled ?? null, notify_customer ?? null, notification_template ?? null, req.params.id);
  const status = db.prepare('SELECT * FROM ticket_statuses WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: { status } });
});

router.delete('/statuses/:id', adminOnly, (req, res) => {
  const inUse = db.prepare('SELECT COUNT(*) as c FROM tickets WHERE status_id = ?').get(req.params.id) as any;
  if (inUse.c > 0) throw new AppError('Status is in use by tickets', 400);
  db.prepare('DELETE FROM ticket_statuses WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Status deleted' } });
});

// ==================== Tax Classes ====================

router.get('/tax-classes', (_req, res) => {
  const taxClasses = db.prepare('SELECT * FROM tax_classes ORDER BY name ASC').all();
  res.json({ success: true, data: { tax_classes: taxClasses } });
});

router.post('/tax-classes', adminOnly, (req, res) => {
  const { name, rate, is_default = 0 } = req.body;
  if (!name || rate === undefined) throw new AppError('Name and rate required', 400);
  if (is_default) db.prepare('UPDATE tax_classes SET is_default = 0').run();
  const result = db.prepare('INSERT INTO tax_classes (name, rate, is_default) VALUES (?, ?, ?)').run(name, rate, is_default);
  const tc = db.prepare('SELECT * FROM tax_classes WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { tax_class: tc } });
});

router.put('/tax-classes/:id', adminOnly, (req, res) => {
  const { name, rate, is_default } = req.body;
  if (is_default) db.prepare('UPDATE tax_classes SET is_default = 0').run();
  db.prepare('UPDATE tax_classes SET name = COALESCE(?, name), rate = COALESCE(?, rate), is_default = COALESCE(?, is_default) WHERE id = ?')
    .run(name ?? null, rate ?? null, is_default ?? null, req.params.id);
  const tc = db.prepare('SELECT * FROM tax_classes WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: { tax_class: tc } });
});

router.delete('/tax-classes/:id', adminOnly, (req, res) => {
  db.prepare('DELETE FROM tax_classes WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Deleted' } });
});

// ==================== Payment Methods ====================

router.get('/payment-methods', (_req, res) => {
  const methods = db.prepare('SELECT * FROM payment_methods WHERE is_active = 1 ORDER BY sort_order ASC').all();
  res.json({ success: true, data: { payment_methods: methods } });
});

router.post('/payment-methods', adminOnly, (req, res) => {
  const { name, sort_order = 0 } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = db.prepare('INSERT INTO payment_methods (name, sort_order) VALUES (?, ?)').run(name, sort_order);
  const method = db.prepare('SELECT * FROM payment_methods WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { payment_method: method } });
});

// ==================== Referral Sources ====================

router.get('/referral-sources', (_req, res) => {
  const sources = db.prepare('SELECT * FROM referral_sources ORDER BY sort_order ASC').all();
  res.json({ success: true, data: { referral_sources: sources } });
});

router.post('/referral-sources', adminOnly, (req, res) => {
  const { name, sort_order = 0 } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = db.prepare('INSERT INTO referral_sources (name, sort_order) VALUES (?, ?)').run(name, sort_order);
  const source = db.prepare('SELECT * FROM referral_sources WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { referral_source: source } });
});

// ==================== Customer Groups ====================

router.get('/customer-groups', (_req, res) => {
  const groups = db.prepare('SELECT * FROM customer_groups ORDER BY name ASC').all();
  res.json({ success: true, data: groups });
});

router.post('/customer-groups', adminOnly, (req, res) => {
  const { name, discount_pct = 0, discount_type = 'percentage', auto_apply = 1, description } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = db.prepare(
    'INSERT INTO customer_groups (name, discount_pct, discount_type, auto_apply, description) VALUES (?, ?, ?, ?, ?)'
  ).run(name, discount_pct, discount_type, auto_apply ? 1 : 0, description || null);
  const group = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: group });
});

router.put('/customer-groups/:id', adminOnly, (req, res) => {
  const { name, discount_pct, discount_type, auto_apply, description } = req.body;
  const existing = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(req.params.id) as any;
  if (!existing) throw new AppError('Customer group not found', 404);

  db.prepare(`
    UPDATE customer_groups SET
      name = COALESCE(?, name),
      discount_pct = COALESCE(?, discount_pct),
      discount_type = COALESCE(?, discount_type),
      auto_apply = COALESCE(?, auto_apply),
      description = COALESCE(?, description),
      updated_at = datetime('now')
    WHERE id = ?
  `).run(
    name ?? null,
    discount_pct ?? null,
    discount_type ?? null,
    auto_apply !== undefined ? (auto_apply ? 1 : 0) : null,
    description !== undefined ? description : null,
    req.params.id
  );
  const group = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: group });
});

router.delete('/customer-groups/:id', adminOnly, (req, res) => {
  const existing = db.prepare('SELECT * FROM customer_groups WHERE id = ?').get(req.params.id) as any;
  if (!existing) throw new AppError('Customer group not found', 404);
  // Unlink customers first
  db.prepare('UPDATE customers SET customer_group_id = NULL WHERE customer_group_id = ?').run(req.params.id);
  db.prepare('DELETE FROM customer_groups WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Customer group deleted' } });
});

// ==================== Users ====================

router.get('/users', (_req, res) => {
  const users = db.prepare('SELECT id, username, email, first_name, last_name, role, is_active, created_at FROM users ORDER BY first_name ASC').all();
  res.json({ success: true, data: { users } });
});

router.post('/users', adminOnly, (req, res) => {
  // bcrypt imported at top level
  const { username, email, password, first_name, last_name, role = 'technician', pin } = req.body;
  if (!username || !first_name || !last_name) throw new AppError('Username, first name and last name required', 400);

  // Check for duplicate username
  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username) as any;
  if (existing) throw new AppError(`Username "${username}" already exists`, 409);

  const hash = password ? bcrypt.hashSync(password, 12) : null;
  const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
  const passwordSet = password ? 1 : 0;
  const result = db.prepare(`
    INSERT INTO users (username, email, password_hash, first_name, last_name, role, pin, password_set)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(username, email || null, hash, first_name, last_name, role, pinHash, passwordSet);
  const user = db.prepare('SELECT id, username, email, first_name, last_name, role, is_active FROM users WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { user } });
});

router.put('/users/:id', adminOnly, (req, res) => {
  // bcrypt imported at top level
  const { email, first_name, last_name, role, pin, password, is_active } = req.body;
  const hash = password ? bcrypt.hashSync(password, 12) : null;
  const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
  db.prepare(`
    UPDATE users SET
      email = COALESCE(?, email), first_name = COALESCE(?, first_name),
      last_name = COALESCE(?, last_name), role = COALESCE(?, role),
      pin = COALESCE(?, pin), is_active = COALESCE(?, is_active),
      password_hash = COALESCE(?, password_hash),
      updated_at = datetime('now')
    WHERE id = ?
  `).run(email ?? null, first_name ?? null, last_name ?? null, role ?? null, pinHash, is_active ?? null, hash, req.params.id);

  // If user was deactivated, invalidate all their sessions
  if (is_active === 0 || is_active === false) {
    db.prepare('DELETE FROM sessions WHERE user_id = ?').run(req.params.id);
  }

  const user = db.prepare('SELECT id, username, email, first_name, last_name, role, is_active FROM users WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: { user } });
});

// (Old COGS reconciliation removed — moved to catalog.routes.ts syncCostPricesFromCatalog)

// ==================== Condition Templates ====================
// PLACEHOLDER_REMOVE_OLD_CODE
const DEVICE_PATTERNS = [
  // Apple
  /iPhone\s*\d+\s*(Pro\s*Max|Pro|Plus|Mini)?/i,
  /iPad\s*(Pro|Air|Mini)?\s*\d*\.?\d*(\s*(st|nd|rd|th)\s*Gen)?/i,
  /MacBook\s*(Pro|Air)?\s*\d*[""]?\s*\d*\.?\d*[""]?/i,
  /Apple\s*Watch\s*(Ultra|SE|Series)?\s*\d*/i,
  /AirPods?\s*(Pro|Max)?\s*\d*/i,
  /iMac\s*\d*[""]?/i,
  // Samsung
  /Galaxy\s*(S|A|Z|Note|Tab)\s*\d+\s*(Ultra|Plus|\+|FE|Lite|e)?/i,
  // Google
  /Pixel\s*\d+\s*(Pro|a|XL)?/i,
  // Others
  /Moto\s*(G|E|Edge|Razr)\s*\d*\s*(Power|Play|Stylus|5G)?/i,
  /OnePlus\s*\d+\s*(Pro|T|R)?/i,
  // Laptop codes
  /A\d{4}/i,  // Apple model codes like A1990, A2338
];

const PART_TYPES = [
  'oled assembly', 'lcd assembly', 'screen assembly', 'screen', 'lcd', 'oled', 'display',
  'battery', 'charging port', 'charge port', 'dock connector',
  'back camera', 'front camera', 'rear camera', 'camera lens', 'camera',
  'back cover', 'back glass', 'back housing', 'housing frame', 'housing',
  'speaker', 'earpiece', 'ear speaker', 'loud speaker',
  'flex cable', 'power flex', 'volume flex',
  'digitizer', 'touch screen',
  'home button', 'power button', 'volume button',
  'sim tray', 'sim card',
  'antenna', 'wifi antenna',
  'motherboard', 'logic board',
  'palmrest', 'keyboard', 'trackpad', 'touchpad',
  'hinge', 'bezel', 'frame',
  'tempered glass', 'screen protector',
];

const QUALITY_TIERS = ['premium', 'oem', 'original', 'aftermarket', 'refurbished', 'incell', 'soft oled', 'hard oled', 'service pack'];

function extractDeviceModel(name: string): string | null {
  for (const pattern of DEVICE_PATTERNS) {
    const match = name.match(pattern);
    if (match) return match[0].trim();
  }
  return null;
}

function extractPartType(name: string): string | null {
  const lower = name.toLowerCase();
  // Try longest matches first
  const sorted = [...PART_TYPES].sort((a, b) => b.length - a.length);
  for (const pt of sorted) {
    if (lower.includes(pt)) return pt;
  }
  return null;
}

function extractQuality(name: string): string | null {
  const lower = name.toLowerCase();
  for (const q of QUALITY_TIERS) {
    if (lower.includes(q)) return q;
  }
  return null;
}

// Score how well two names match by significant token overlap
function tokenMatchScore(invName: string, catName: string): number {
  const normalize = (s: string) => s.toLowerCase().replace(/[^a-z0-9\s]/g, '').split(/\s+/).filter(t => t.length > 2);
  const invTokens = normalize(invName);
  const catTokens = new Set(normalize(catName));
  if (invTokens.length === 0) return 0;
  const matches = invTokens.filter(t => catTokens.has(t)).length;
  return matches / invTokens.length;
}

router.post('/reconcile-cogs', adminOnly, (_req, res) => {
  type AnyRow = Record<string, any>;

  // Get ALL inventory items — we check cost_price AND whether they need updating
  // Items need reconciliation if: cost_price is 0 OR they've been used in tickets with no cost
  const allItems = db.prepare(`
    SELECT id, name, sku, cost_price, retail_price FROM inventory_items
    WHERE is_active = 1 AND (cost_price IS NULL OR cost_price = 0)
  `).all() as AnyRow[];

  let matched = 0;
  let updated = 0;
  let skipped = 0;
  const unmatched: string[] = [];
  const matches: { item: string; catalog: string; price: number; method: string }[] = [];

  const updateStmt = db.prepare("UPDATE inventory_items SET cost_price = ?, is_reorderable = 1, updated_at = datetime('now') WHERE id = ?");
  const updateRetailStmt = db.prepare("UPDATE inventory_items SET retail_price = ?, updated_at = datetime('now') WHERE id = ? AND (retail_price IS NULL OR retail_price = 0)");

  for (const item of allItems) {
    let bestMatch: { price: number; name: string; method: string } | null = null;
    const itemName = (item.name || '').trim();
    if (!itemName) { skipped++; continue; }

    // Pass 1: SKU match
    if (item.sku) {
      const skuMatch = db.prepare('SELECT name, MIN(price) as price FROM supplier_catalog WHERE sku = ? AND price > 0').get(item.sku) as AnyRow | undefined;
      if (skuMatch && skuMatch.price > 0) {
        bestMatch = { price: skuMatch.price, name: skuMatch.name, method: 'sku' };
      }
    }

    // Pass 2: Exact name match (case-insensitive, trimmed)
    if (!bestMatch) {
      const nameMatch = db.prepare('SELECT name, MIN(price) as price FROM supplier_catalog WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) AND price > 0').get(itemName) as AnyRow | undefined;
      if (nameMatch && nameMatch.price > 0) {
        bestMatch = { price: nameMatch.price, name: nameMatch.name, method: 'exact_name' };
      }
    }

    // Pass 2b: Substring match — catalog name CONTAINS inventory name (handles truncation)
    if (!bestMatch && itemName.length >= 15) {
      const subMatch = db.prepare(`
        SELECT name, MIN(price) as price FROM supplier_catalog
        WHERE price > 0 AND LOWER(name) LIKE '%' || LOWER(?) || '%'
        LIMIT 1
      `).get(itemName) as AnyRow | undefined;
      if (subMatch && subMatch.price > 0) {
        bestMatch = { price: subMatch.price, name: subMatch.name, method: 'substring' };
      }
    }

    // Pass 2c: Inventory name CONTAINS catalog name (reverse — catalog name is shorter)
    if (!bestMatch && itemName.length >= 15) {
      const revMatch = db.prepare(`
        SELECT name, MIN(price) as price FROM supplier_catalog
        WHERE price > 0 AND LOWER(?) LIKE '%' || LOWER(TRIM(name)) || '%' AND LENGTH(name) >= 15
        LIMIT 1
      `).get(itemName) as AnyRow | undefined;
      if (revMatch && revMatch.price > 0) {
        bestMatch = { price: revMatch.price, name: revMatch.name, method: 'reverse_substring' };
      }
    }

    // Pass 3: Fuzzy token match (device + part type extraction)
    if (!bestMatch) {
      const device = extractDeviceModel(itemName);
      const partType = extractPartType(itemName);
      const quality = extractQuality(itemName);

      if (device && partType) {
        const candidates = db.prepare(`
          SELECT id, name, price FROM supplier_catalog
          WHERE price > 0 AND LOWER(name) LIKE ? AND LOWER(name) LIKE ?
          LIMIT 50
        `).all(`%${device.toLowerCase()}%`, `%${partType.toLowerCase()}%`) as AnyRow[];

        if (candidates.length > 0) {
          let best: AnyRow | null = null;
          let bestScore = 0;

          for (const cand of candidates) {
            let score = tokenMatchScore(itemName, cand.name);
            if (quality) {
              const candQuality = extractQuality(cand.name);
              if (candQuality === quality) score += 0.2;
            }
            if (score > bestScore) {
              bestScore = score;
              best = cand;
            }
          }

          if (best && bestScore >= 0.35) {
            bestMatch = { price: best.price, name: best.name, method: `fuzzy (${Math.round(bestScore * 100)}%)` };
          }
        }
      } else if (device || partType) {
        // Has device OR part type but not both — try looser match
        const searchTerm = device || partType || '';
        const candidates = db.prepare(`
          SELECT name, MIN(price) as price FROM supplier_catalog
          WHERE price > 0 AND LOWER(name) LIKE ?
          GROUP BY name LIMIT 20
        `).all(`%${searchTerm.toLowerCase()}%`) as AnyRow[];

        for (const cand of candidates) {
          const score = tokenMatchScore(itemName, cand.name);
          if (score >= 0.5 && cand.price > 0) {
            bestMatch = { price: cand.price, name: cand.name, method: `partial (${Math.round(score * 100)}%)` };
            break;
          }
        }
      } else {
        skipped++;
        continue;
      }
    }

    if (bestMatch) {
      updateStmt.run(bestMatch.price, item.id);
      updateRetailStmt.run(Math.round(bestMatch.price * 1.4 * 100) / 100, item.id);
      matched++;
      updated++;
      matches.push({ item: item.name, catalog: bestMatch.name, price: bestMatch.price, method: bestMatch.method });
    } else {
      unmatched.push(item.name);
    }
  }

  res.json({
    success: true,
    data: {
      total_checked: allItems.length,
      matched,
      updated,
      skipped,
      unmatched_count: unmatched.length,
      unmatched: unmatched.slice(0, 50), // limit response size
      matches: matches.slice(0, 50),
    },
  });
});

// ==================== Condition Templates ====================

router.get('/condition-templates', (req, res) => {
  const { category } = req.query;
  let templates: any[];
  if (category) {
    templates = db.prepare('SELECT * FROM condition_templates WHERE category = ? ORDER BY is_default DESC, name ASC').all(category);
  } else {
    templates = db.prepare('SELECT * FROM condition_templates ORDER BY category, is_default DESC, name ASC').all();
  }
  // Attach checks to each template
  const getChecks = db.prepare('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC');
  for (const t of templates) {
    (t as any).checks = getChecks.all(t.id);
  }
  res.json({ success: true, data: templates });
});

router.post('/condition-templates', (req, res) => {
  const { category, name } = req.body;
  if (!category || !name) throw new AppError('Category and name required', 400);
  const result = db.prepare('INSERT INTO condition_templates (category, name) VALUES (?, ?)').run(category, name);
  const template = db.prepare('SELECT * FROM condition_templates WHERE id = ?').get(result.lastInsertRowid) as any;
  template.checks = [];
  res.status(201).json({ success: true, data: template });
});

router.put('/condition-templates/:id', (req, res) => {
  const { name, is_default } = req.body;
  db.prepare(`
    UPDATE condition_templates SET
      name = COALESCE(?, name),
      is_default = COALESCE(?, is_default)
    WHERE id = ?
  `).run(name ?? null, is_default ?? null, req.params.id);
  const template = db.prepare('SELECT * FROM condition_templates WHERE id = ?').get(req.params.id) as any;
  if (!template) throw new AppError('Template not found', 404);
  template.checks = db.prepare('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC').all(template.id);
  res.json({ success: true, data: template });
});

router.delete('/condition-templates/:id', (req, res) => {
  const template = db.prepare('SELECT * FROM condition_templates WHERE id = ?').get(req.params.id) as any;
  if (!template) throw new AppError('Template not found', 404);
  if (template.is_default) throw new AppError('Cannot delete default template', 400);
  db.prepare('DELETE FROM condition_templates WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Template deleted' } });
});

// ==================== Condition Checks ====================

router.get('/condition-checks/:category', (req, res) => {
  const template = db.prepare(
    'SELECT * FROM condition_templates WHERE category = ? AND is_default = 1'
  ).get(req.params.category) as any;
  if (!template) {
    res.json({ success: true, data: [] });
    return;
  }
  const checks = db.prepare(
    'SELECT * FROM condition_checks WHERE template_id = ? AND is_active = 1 ORDER BY sort_order ASC'
  ).all(template.id);
  res.json({ success: true, data: checks });
});

router.post('/condition-checks', (req, res) => {
  const { template_id, label } = req.body;
  if (!template_id || !label) throw new AppError('template_id and label required', 400);
  // Get max sort_order for this template
  const max = db.prepare('SELECT MAX(sort_order) as m FROM condition_checks WHERE template_id = ?').get(template_id) as any;
  const sort_order = (max?.m ?? -1) + 1;
  const result = db.prepare('INSERT INTO condition_checks (template_id, label, sort_order) VALUES (?, ?, ?)').run(template_id, label, sort_order);
  const check = db.prepare('SELECT * FROM condition_checks WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: check });
});

router.put('/condition-checks/:id', (req, res) => {
  const { label, sort_order, is_active } = req.body;
  db.prepare(`
    UPDATE condition_checks SET
      label = COALESCE(?, label),
      sort_order = COALESCE(?, sort_order),
      is_active = COALESCE(?, is_active)
    WHERE id = ?
  `).run(label ?? null, sort_order ?? null, is_active ?? null, req.params.id);
  const check = db.prepare('SELECT * FROM condition_checks WHERE id = ?').get(req.params.id);
  if (!check) throw new AppError('Check not found', 404);
  res.json({ success: true, data: check });
});

router.delete('/condition-checks/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM condition_checks WHERE id = ?').get(req.params.id);
  if (!existing) throw new AppError('Check not found', 404);
  db.prepare('DELETE FROM condition_checks WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Check deleted' } });
});

// Bulk reorder checks for a template
router.put('/condition-checks-reorder/:templateId', (req, res) => {
  const { order } = req.body; // array of check IDs in desired order
  if (!Array.isArray(order)) throw new AppError('order array required', 400);
  const update = db.prepare('UPDATE condition_checks SET sort_order = ? WHERE id = ? AND template_id = ?');
  const reorder = db.transaction((ids: number[]) => {
    ids.forEach((id, idx) => update.run(idx, id, req.params.templateId));
  });
  reorder(order);
  const checks = db.prepare('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC').all(req.params.templateId);
  res.json({ success: true, data: checks });
});

// ==================== Notification Templates ====================

router.get('/notification-templates', (_req, res) => {
  const templates = db.prepare('SELECT * FROM notification_templates ORDER BY id ASC').all();
  res.json({ success: true, data: { templates } });
});

router.put('/notification-templates/:id', (req, res) => {
  const { subject, email_body, sms_body, send_email_auto, send_sms_auto, is_active } = req.body;
  const existing = db.prepare('SELECT * FROM notification_templates WHERE id = ?').get(req.params.id) as any;
  if (!existing) throw new AppError('Notification template not found', 404);

  db.prepare(`
    UPDATE notification_templates SET
      subject = COALESCE(?, subject),
      email_body = COALESCE(?, email_body),
      sms_body = COALESCE(?, sms_body),
      send_email_auto = COALESCE(?, send_email_auto),
      send_sms_auto = COALESCE(?, send_sms_auto),
      is_active = COALESCE(?, is_active),
      updated_at = datetime('now')
    WHERE id = ?
  `).run(
    subject ?? null,
    email_body ?? null,
    sms_body ?? null,
    send_email_auto ?? null,
    send_sms_auto ?? null,
    is_active ?? null,
    req.params.id
  );
  const template = db.prepare('SELECT * FROM notification_templates WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: template });
});

// ==================== Checklist Templates ====================

router.get('/checklist-templates', (_req, res) => {
  const templates = db.prepare('SELECT * FROM checklist_templates ORDER BY device_type, name').all();
  res.json({ success: true, data: { templates } });
});

router.post('/checklist-templates', adminOnly, (req, res) => {
  const { name, device_type, items } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const result = db.prepare(
    'INSERT INTO checklist_templates (name, device_type, items, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'
  ).run(name, device_type || null, JSON.stringify(items || []), now, now);
  const template = db.prepare('SELECT * FROM checklist_templates WHERE id = ?').get(Number(result.lastInsertRowid));
  res.status(201).json({ success: true, data: template });
});

router.put('/checklist-templates/:id', adminOnly, (req, res) => {
  const { name, device_type, items } = req.body;
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  db.prepare(
    'UPDATE checklist_templates SET name = COALESCE(?, name), device_type = COALESCE(?, device_type), items = COALESCE(?, items), updated_at = ? WHERE id = ?'
  ).run(name ?? null, device_type ?? null, items ? JSON.stringify(items) : null, now, req.params.id);
  const template = db.prepare('SELECT * FROM checklist_templates WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: template });
});

router.delete('/checklist-templates/:id', adminOnly, (req, res) => {
  db.prepare('DELETE FROM checklist_templates WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
});

// ==================== Logo Upload ====================

router.post('/logo', adminOnly, logoUpload.single('logo'), (req, res) => {
  if (!req.file) throw new AppError('No file uploaded', 400);
  const logoPath = `/uploads/${req.file.filename}`;
  db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)').run('store_logo', logoPath);
  res.json({ success: true, data: { store_logo: logoPath } });
});

export default router;
