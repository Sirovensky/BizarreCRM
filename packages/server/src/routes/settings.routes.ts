import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import multer from 'multer';
import path from 'path';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { config } from '../config.js';
import { reloadSmsProvider, createTestProvider, getProviderRegistry } from '../services/smsProvider.js';
import type { ProviderType } from '../services/smsProvider.js';
import { ENCRYPTED_CONFIG_KEYS, encryptConfigValue, decryptConfigValue } from '../utils/configEncryption.js';
import { audit } from '../utils/audit.js';
import { clearEmailCache } from '../services/email.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// Multer for logo upload
const logoUpload = multer({
  storage: multer.diskStorage({
    destination: (req: any, _file: any, cb: any) => {
      const slug = req.tenantSlug;
      const dest = slug ? path.join(config.uploadsPath, slug) : config.uploadsPath;
      const fs = require('fs');
      if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
      cb(null, dest);
    },
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
  'business_hours', 'business_hours_start', 'business_hours_end', 'store_logo',
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
  // SMS/MMS provider
  'sms_provider_type',
  'sms_twilio_account_sid', 'sms_twilio_auth_token', 'sms_twilio_from_number',
  'sms_telnyx_api_key', 'sms_telnyx_from_number', 'sms_telnyx_public_key', 'sms_telnyx_connection_id',
  'sms_bandwidth_account_id', 'sms_bandwidth_username', 'sms_bandwidth_password', 'sms_bandwidth_application_id', 'sms_bandwidth_from_number',
  'sms_plivo_auth_id', 'sms_plivo_auth_token', 'sms_plivo_from_number',
  'sms_vonage_api_key', 'sms_vonage_api_secret', 'sms_vonage_from_number', 'sms_vonage_application_id',
  'sms_10dlc_status',
  // Voice settings
  'voice_auto_record', 'voice_auto_transcribe', 'voice_announce_recording',
  'voice_inbound_action', 'voice_forward_number',
  // RepairDesk import
  'rd_api_key', 'rd_api_url',
  // SMTP (per-tenant email credentials)
  'smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from',
  // 3CX (per-tenant telephony)
  // SW-D15: Reserved for future 3CX integration — stored in UI but not enforced server-side.
  // These settings will be used when server-side 3CX call routing/logging is implemented.
  'tcx_host', 'tcx_username', 'tcx_password', 'tcx_extension', 'tcx_store_number',
  // Role-based module visibility (ENR-S7)
  'role_module_visibility',
  // ENR-SMS6: Auto-reply off-hours
  'auto_reply_enabled', 'auto_reply_message',
  // ENR-LE8: Estimate auto-follow-up days
  'estimate_followup_days',
  // ENR-A3: Notification digest mode
  'notification_digest_mode', 'notification_digest_hour',
  // ENR-S5: Theme customization
  'theme_primary_color', 'theme_logo_url',
  // ENR-S9/A6: Webhook configuration
  'webhook_url', 'webhook_events',
  // ENR-LE4: Lead auto-assignment
  'lead_auto_assign',
]);

// ==================== Generic Config (key-value) ====================

// Sensitive config keys only visible to admins (hidden from non-admin users on GET /config)
const SENSITIVE_CONFIG_KEYS = new Set([
  'rd_api_key',
  'tcx_password',
  'smtp_pass',
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
]);

// GET /setup-status — check if initial store setup has been completed
router.get('/setup-status', async (req, res) => {
  const adb = req.asyncDb;
  const [row, nameRow] = await Promise.all([
    adb.get<any>("SELECT value FROM store_config WHERE key = 'setup_completed'"),
    adb.get<any>("SELECT value FROM store_config WHERE key = 'store_name'"),
  ]);
  const completed = row?.value === 'true';
  res.json({
    success: true,
    data: {
      setup_completed: completed,
      store_name: nameRow?.value || null,
    },
  });
});

// POST /complete-setup — save initial store info and mark setup as done
router.post('/complete-setup', adminOnly, async (req, res) => {
  const db = req.db;
  const { store_name, address, phone, email, timezone, currency } = req.body;

  if (!store_name?.trim()) {
    return res.status(400).json({ success: false, message: 'Store name is required' });
  }

  const upsert = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const run = db.transaction(() => {
    if (store_name) upsert.run('store_name', store_name.trim());
    if (address) upsert.run('store_address', address.trim());
    if (phone) upsert.run('store_phone', phone.trim());
    if (email) upsert.run('store_email', email.trim());
    if (timezone) upsert.run('timezone', timezone.trim());
    if (currency) upsert.run('currency', currency.trim());
    // Also set legacy keys for backwards compat
    if (phone) upsert.run('phone', phone.trim());
    if (address) upsert.run('address', address.trim());
    if (email) upsert.run('email', email.trim());
    upsert.run('setup_completed', 'true');
  });
  run();

  res.json({ success: true, data: { message: 'Store setup completed' } });
});

router.get('/config', async (req, res) => {
  const adb = req.asyncDb;
  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const isAdmin = req.user?.role === 'admin';
  const cfg: Record<string, string> = {};
  for (const row of rows) {
    if (!isAdmin && SENSITIVE_CONFIG_KEYS.has(row.key)) continue;
    // Decrypt sensitive values for admin display
    cfg[row.key] = (isAdmin && ENCRYPTED_CONFIG_KEYS.has(row.key))
      ? decryptConfigValue(row.value)
      : row.value;
  }
  // Include server environment mode so frontend can show dev warning banner
  cfg._node_env = process.env.NODE_ENV || 'development';
  res.json({ success: true, data: cfg });
});

// ─── Settings validation rules (ENR-S3) ─────────────────────────────────────
const ISO_CURRENCY_RE = /^[A-Z]{3}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Build a set of known IANA timezones for validation
const KNOWN_TIMEZONES: Set<string> = (() => {
  try {
    return new Set(Intl.supportedValuesOf('timeZone'));
  } catch {
    // Fallback: accept any non-empty string if runtime doesn't support this API
    return new Set<string>();
  }
})();

const NUMERIC_SETTINGS = new Set([
  'stall_alert_days', 'review_request_delay_hours', 'feedback_delay_hours',
  'repair_default_warranty_value', 'repair_default_due_value',
  'label_width_mm', 'label_height_mm',
  'repair_price_flat_adjustment', 'repair_price_pct_adjustment',
  'backup_retention', 'smtp_port',
  'estimate_followup_days', 'notification_digest_hour',
]);

const EMAIL_SETTINGS = new Set([
  'store_email', 'smtp_from', 'smtp_user',
]);

/** Validate a config key/value pair. Returns an error string or null if valid. */
function validateConfigValue(key: string, value: string): string | null {
  if (key === 'store_timezone' && value) {
    if (KNOWN_TIMEZONES.size > 0 && !KNOWN_TIMEZONES.has(value)) {
      return `Invalid timezone: "${value}"`;
    }
  }
  if (key === 'store_currency' && value) {
    if (!ISO_CURRENCY_RE.test(value)) {
      return `Invalid currency code: "${value}" (must be 3-letter ISO code like USD, CAD, EUR)`;
    }
  }
  if (EMAIL_SETTINGS.has(key) && value) {
    if (!EMAIL_RE.test(value)) {
      return `Invalid email format for ${key}: "${value}"`;
    }
  }
  if (NUMERIC_SETTINGS.has(key) && value !== '' && value != null) {
    const num = Number(value);
    if (!Number.isFinite(num) || num < 0 || num !== Math.floor(num)) {
      return `${key} must be a non-negative integer, got: "${value}"`;
    }
  }
  return null;
}

router.put('/config', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;

  // SECURITY: In multi-tenant mode, block backup/server-level config keys
  // These are managed by the platform super-admin, not tenant admins
  const BLOCKED_IN_MULTITENANT = new Set([
    'backup_path', 'backup_schedule', 'backup_retention',
  ]);

  // Validate all incoming values before persisting (ENR-S3)
  const validationErrors: string[] = [];
  for (const [key, value] of Object.entries(req.body)) {
    if (!ALLOWED_CONFIG_KEYS.has(key)) continue;
    const error = validateConfigValue(key, String(value));
    if (error) validationErrors.push(error);
  }
  if (validationErrors.length > 0) {
    return res.status(400).json({ success: false, message: 'Validation failed', errors: validationErrors });
  }

  // ENR-S2: Read old values for audit trail before updating
  const oldRows = await adb.all<any>('SELECT key, value FROM store_config');
  const oldConfig: Record<string, string> = {};
  for (const row of oldRows) {
    oldConfig[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key) ? decryptConfigValue(row.value) : row.value;
  }

  const update = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const updateMany = db.transaction((data: Record<string, string>) => {
    for (const [key, value] of Object.entries(data)) {
      if (!ALLOWED_CONFIG_KEYS.has(key)) continue; // T1.2: skip unknown keys
      if (config.multiTenant && BLOCKED_IN_MULTITENANT.has(key)) continue; // Block server-level keys
      const strVal = String(value);
      // Encrypt sensitive credentials at rest
      const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
      update.run(key, storedVal);

      // ENR-S2: Log setting change to audit trail
      const oldValue = oldConfig[key] ?? null;
      if (oldValue !== strVal) {
        // Mask sensitive values in audit log
        const safeOld = SENSITIVE_CONFIG_KEYS.has(key) ? '***' : (oldValue ?? '(unset)');
        const safeNew = SENSITIVE_CONFIG_KEYS.has(key) ? '***' : strVal;
        audit(db, 'setting_changed', req.user!.id, req.ip || 'unknown', { key, old_value: safeOld, new_value: safeNew });
      }
    }
  });
  updateMany(req.body);

  // MW5: Clear cached email transporter when SMTP settings change
  const smtpKeys = ['smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from'];
  if (smtpKeys.some(k => k in req.body)) {
    clearEmailCache();
  }

  // Return all config (decrypt sensitive values for admin response)
  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const result: Record<string, string> = {};
  for (const row of rows) {
    result[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key) ? decryptConfigValue(row.value) : row.value;
  }
  res.json({ success: true, data: result });
});

// ==================== Store Settings ====================

router.get('/store', async (req, res) => {
  const adb = req.asyncDb;
  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const isAdmin = req.user?.role === 'admin';
  const cfg: Record<string, string> = {};
  for (const row of rows) {
    if (!isAdmin && SENSITIVE_CONFIG_KEYS.has(row.key)) continue;
    cfg[row.key] = (isAdmin && ENCRYPTED_CONFIG_KEYS.has(row.key))
      ? decryptConfigValue(row.value)
      : row.value;
  }
  res.json({ success: true, data: { store: cfg } });
});

router.put('/store', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const allowed = ['store_name','address','phone','email','timezone','currency','tax_rate','receipt_header','receipt_footer','logo_url','sms_provider','tcx_host','tcx_extension','tcx_password','smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
  const update = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const updateMany = db.transaction((data: Record<string, string>) => {
    for (const [key, value] of Object.entries(data)) {
      if (!allowed.includes(key)) continue;
      const strVal = String(value);
      const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
      update.run(key, storedVal);
    }
  });
  updateMany(req.body);

  // MW5: Clear cached email transporter when SMTP settings change
  const smtpStoreKeys = ['smtp_host', 'smtp_port', 'smtp_user', 'smtp_from'];
  if (smtpStoreKeys.some(k => k in req.body)) {
    clearEmailCache();
  }

  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const cfg: Record<string, string> = {};
  for (const row of rows) cfg[row.key] = row.value;
  res.json({ success: true, data: { store: cfg } });
});

// ==================== Ticket Statuses ====================

router.get('/statuses', async (req, res) => {
  const adb = req.asyncDb;
  const statuses = await adb.all<any>('SELECT * FROM ticket_statuses ORDER BY sort_order ASC LIMIT 200');
  res.json({ success: true, data: { statuses } });
});

router.post('/statuses', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, color = '#6b7280', sort_order = 0, is_default = 0, is_closed = 0, is_cancelled = 0, notify_customer = 0, notification_template } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run(`
    INSERT INTO ticket_statuses (name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template || null);
  const status = await adb.get<any>('SELECT * FROM ticket_statuses WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { status } });
});

router.put('/statuses/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template } = req.body;
  await adb.run(`
    UPDATE ticket_statuses SET
      name = COALESCE(?, name), color = COALESCE(?, color), sort_order = COALESCE(?, sort_order),
      is_default = COALESCE(?, is_default), is_closed = COALESCE(?, is_closed),
      is_cancelled = COALESCE(?, is_cancelled), notify_customer = COALESCE(?, notify_customer),
      notification_template = COALESCE(?, notification_template)
    WHERE id = ?
  `, name ?? null, color ?? null, sort_order ?? null, is_default ?? null, is_closed ?? null,
    is_cancelled ?? null, notify_customer ?? null, notification_template ?? null, req.params.id);
  const status = await adb.get<any>('SELECT * FROM ticket_statuses WHERE id = ?', req.params.id);
  res.json({ success: true, data: { status } });
});

router.delete('/statuses/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const inUse = await adb.get<any>('SELECT COUNT(*) as c FROM tickets WHERE status_id = ?', req.params.id);
  if (inUse.c > 0) throw new AppError('Status is in use by tickets', 400);
  await adb.run('DELETE FROM ticket_statuses WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Status deleted' } });
});

// ==================== Tax Classes ====================

router.get('/tax-classes', async (req, res) => {
  const adb = req.asyncDb;
  const taxClasses = await adb.all<any>('SELECT * FROM tax_classes ORDER BY name ASC LIMIT 200');
  res.json({ success: true, data: { tax_classes: taxClasses } });
});

router.post('/tax-classes', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, rate, is_default = 0 } = req.body;
  if (!name || rate === undefined) throw new AppError('Name and rate required', 400);
  const numRate = Number(rate);
  if (!Number.isFinite(numRate) || numRate < 0 || numRate > 100) throw new AppError('Rate must be a number between 0 and 100', 400);
  if (is_default) await adb.run('UPDATE tax_classes SET is_default = 0');
  const result = await adb.run('INSERT INTO tax_classes (name, rate, is_default) VALUES (?, ?, ?)', name, rate, is_default);
  const tc = await adb.get<any>('SELECT * FROM tax_classes WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { tax_class: tc } });
});

router.put('/tax-classes/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, rate, is_default } = req.body;
  if (rate !== undefined && rate !== null) {
    const numRate = Number(rate);
    if (!Number.isFinite(numRate) || numRate < 0 || numRate > 100) throw new AppError('Rate must be a number between 0 and 100', 400);
  }
  if (is_default) await adb.run('UPDATE tax_classes SET is_default = 0');
  await adb.run('UPDATE tax_classes SET name = COALESCE(?, name), rate = COALESCE(?, rate), is_default = COALESCE(?, is_default) WHERE id = ?',
    name ?? null, rate ?? null, is_default ?? null, req.params.id);
  const tc = await adb.get<any>('SELECT * FROM tax_classes WHERE id = ?', req.params.id);
  res.json({ success: true, data: { tax_class: tc } });
});

router.delete('/tax-classes/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const [invCount, lineCount] = await Promise.all([
    adb.get<any>('SELECT COUNT(*) as c FROM inventory_items WHERE tax_class_id = ?', req.params.id),
    adb.get<any>('SELECT COUNT(*) as c FROM invoice_line_items WHERE tax_class_id = ?', req.params.id),
  ]);
  if ((invCount?.c || 0) > 0 || (lineCount?.c || 0) > 0) {
    throw new AppError('Tax class is in use by inventory items or invoice line items and cannot be deleted', 400);
  }
  await adb.run('DELETE FROM tax_classes WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Deleted' } });
});

// ==================== Payment Methods ====================

router.get('/payment-methods', async (req, res) => {
  const adb = req.asyncDb;
  const methods = await adb.all<any>('SELECT * FROM payment_methods WHERE is_active = 1 ORDER BY sort_order ASC LIMIT 200');
  res.json({ success: true, data: { payment_methods: methods } });
});

router.post('/payment-methods', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, sort_order = 0 } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run('INSERT INTO payment_methods (name, sort_order) VALUES (?, ?)', name, sort_order);
  const method = await adb.get<any>('SELECT * FROM payment_methods WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { payment_method: method } });
});

// ==================== Referral Sources ====================

router.get('/referral-sources', async (req, res) => {
  const adb = req.asyncDb;
  const sources = await adb.all<any>('SELECT * FROM referral_sources ORDER BY sort_order ASC LIMIT 200');
  res.json({ success: true, data: { referral_sources: sources } });
});

router.post('/referral-sources', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, sort_order = 0 } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run('INSERT INTO referral_sources (name, sort_order) VALUES (?, ?)', name, sort_order);
  const source = await adb.get<any>('SELECT * FROM referral_sources WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { referral_source: source } });
});

// ==================== Customer Groups ====================

router.get('/customer-groups', async (req, res) => {
  const adb = req.asyncDb;
  const groups = await adb.all<any>('SELECT * FROM customer_groups ORDER BY name ASC LIMIT 200');
  res.json({ success: true, data: groups });
});

router.post('/customer-groups', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, discount_pct = 0, discount_type = 'percentage', auto_apply = 1, description } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run(
    'INSERT INTO customer_groups (name, discount_pct, discount_type, auto_apply, description) VALUES (?, ?, ?, ?, ?)',
    name, discount_pct, discount_type, auto_apply ? 1 : 0, description || null);
  const group = await adb.get<any>('SELECT * FROM customer_groups WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: group });
});

router.put('/customer-groups/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, discount_pct, discount_type, auto_apply, description } = req.body;
  const existing = await adb.get<any>('SELECT * FROM customer_groups WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Customer group not found', 404);

  await adb.run(`
    UPDATE customer_groups SET
      name = COALESCE(?, name),
      discount_pct = COALESCE(?, discount_pct),
      discount_type = COALESCE(?, discount_type),
      auto_apply = COALESCE(?, auto_apply),
      description = COALESCE(?, description),
      updated_at = datetime('now')
    WHERE id = ?
  `,
    name ?? null,
    discount_pct ?? null,
    discount_type ?? null,
    auto_apply !== undefined ? (auto_apply ? 1 : 0) : null,
    description !== undefined ? description : null,
    req.params.id
  );
  const group = await adb.get<any>('SELECT * FROM customer_groups WHERE id = ?', req.params.id);
  res.json({ success: true, data: group });
});

router.delete('/customer-groups/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<any>('SELECT * FROM customer_groups WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Customer group not found', 404);
  // Unlink customers first
  await adb.run('UPDATE customers SET customer_group_id = NULL WHERE customer_group_id = ?', req.params.id);
  await adb.run('DELETE FROM customer_groups WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Customer group deleted' } });
});

// ==================== Users ====================

router.get('/users', async (req, res) => {
  const adb = req.asyncDb;
  const users = await adb.all<any>('SELECT id, username, email, first_name, last_name, role, is_active, created_at FROM users ORDER BY first_name ASC LIMIT 500');
  res.json({ success: true, data: { users } });
});

router.post('/users', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  // bcrypt imported at top level
  const { username, email, password, first_name, last_name, role = 'technician', pin } = req.body;
  if (!username || !first_name || !last_name) throw new AppError('Username, first name and last name required', 400);
  if (password && password.length < 8) throw new AppError('Password must be at least 8 characters', 400);

  // Check for duplicate username
  const existing = await adb.get<any>('SELECT id FROM users WHERE username = ?', username);
  if (existing) throw new AppError(`Username "${username}" already exists`, 409);

  const hash = password ? bcrypt.hashSync(password, 12) : null;
  const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
  const passwordSet = password ? 1 : 0;
  const result = await adb.run(`
    INSERT INTO users (username, email, password_hash, first_name, last_name, role, pin, password_set)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, username, email || null, hash, first_name, last_name, role, pinHash, passwordSet);
  const user = await adb.get<any>('SELECT id, username, email, first_name, last_name, role, is_active FROM users WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: { user } });
});

router.put('/users/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const targetUserId = Number(req.params.id);
  // bcrypt imported at top level
  const { email, first_name, last_name, role, pin, password, is_active } = req.body;
  if (password && password.length < 8) throw new AppError('Password must be at least 8 characters', 400);

  // SEC-L14: Prevent admin from demoting themselves
  if (role && req.user!.id === targetUserId && req.user!.role === 'admin' && role !== 'admin') {
    throw new AppError('Cannot demote your own admin account', 400);
  }

  const hash = password ? bcrypt.hashSync(password, 12) : null;
  const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
  await adb.run(`
    UPDATE users SET
      email = COALESCE(?, email), first_name = COALESCE(?, first_name),
      last_name = COALESCE(?, last_name), role = COALESCE(?, role),
      pin = COALESCE(?, pin), is_active = COALESCE(?, is_active),
      password_hash = COALESCE(?, password_hash),
      updated_at = datetime('now')
    WHERE id = ?
  `, email ?? null, first_name ?? null, last_name ?? null, role ?? null, pinHash, is_active ?? null, hash, req.params.id);

  // SEC-L13: If password was changed, invalidate all sessions except the current admin's
  if (password) {
    await adb.run('DELETE FROM sessions WHERE user_id = ? AND id != ?', targetUserId, req.user!.sessionId);
    audit(db, 'password_changed_by_admin', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId });
  }

  // If user was deactivated, invalidate all their sessions
  if (is_active === 0 || is_active === false) {
    await adb.run('DELETE FROM sessions WHERE user_id = ?', req.params.id);
  }

  const user = await adb.get<any>('SELECT id, username, email, first_name, last_name, role, is_active FROM users WHERE id = ?', req.params.id);
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

router.post('/reconcile-cogs', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  type AnyRow = Record<string, any>;

  // Get ALL inventory items — we check cost_price AND whether they need updating
  // Items need reconciliation if: cost_price is 0 OR they've been used in tickets with no cost
  const allItems = await adb.all<AnyRow>(`
    SELECT id, name, sku, cost_price, retail_price FROM inventory_items
    WHERE is_active = 1 AND (cost_price IS NULL OR cost_price = 0)
  `);

  let matched = 0;
  let updated = 0;
  let skipped = 0;
  const unmatched: string[] = [];
  const matches: { item: string; catalog: string; price: number; method: string }[] = [];

  for (const item of allItems) {
    let bestMatch: { price: number; name: string; method: string } | null = null;
    const itemName = (item.name || '').trim();
    if (!itemName) { skipped++; continue; }

    // Pass 1: SKU match
    if (item.sku) {
      const skuMatch = await adb.get<AnyRow>('SELECT name, MIN(price) as price FROM supplier_catalog WHERE sku = ? AND price > 0', item.sku);
      if (skuMatch && skuMatch.price > 0) {
        bestMatch = { price: skuMatch.price, name: skuMatch.name, method: 'sku' };
      }
    }

    // Pass 2: Exact name match (case-insensitive, trimmed)
    if (!bestMatch) {
      const nameMatch = await adb.get<AnyRow>('SELECT name, MIN(price) as price FROM supplier_catalog WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) AND price > 0', itemName);
      if (nameMatch && nameMatch.price > 0) {
        bestMatch = { price: nameMatch.price, name: nameMatch.name, method: 'exact_name' };
      }
    }

    // Pass 2b: Substring match — catalog name CONTAINS inventory name (handles truncation)
    if (!bestMatch && itemName.length >= 15) {
      const subMatch = await adb.get<AnyRow>(`
        SELECT name, MIN(price) as price FROM supplier_catalog
        WHERE price > 0 AND LOWER(name) LIKE '%' || LOWER(?) || '%'
        LIMIT 1
      `, itemName);
      if (subMatch && subMatch.price > 0) {
        bestMatch = { price: subMatch.price, name: subMatch.name, method: 'substring' };
      }
    }

    // Pass 2c: Inventory name CONTAINS catalog name (reverse — catalog name is shorter)
    if (!bestMatch && itemName.length >= 15) {
      const revMatch = await adb.get<AnyRow>(`
        SELECT name, MIN(price) as price FROM supplier_catalog
        WHERE price > 0 AND LOWER(?) LIKE '%' || LOWER(TRIM(name)) || '%' AND LENGTH(name) >= 15
        LIMIT 1
      `, itemName);
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
        const candidates = await adb.all<AnyRow>(`
          SELECT id, name, price FROM supplier_catalog
          WHERE price > 0 AND LOWER(name) LIKE ? AND LOWER(name) LIKE ?
          LIMIT 50
        `, `%${device.toLowerCase()}%`, `%${partType.toLowerCase()}%`);

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
        const candidates = await adb.all<AnyRow>(`
          SELECT name, MIN(price) as price FROM supplier_catalog
          WHERE price > 0 AND LOWER(name) LIKE ?
          GROUP BY name LIMIT 20
        `, `%${searchTerm.toLowerCase()}%`);

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
      await adb.run("UPDATE inventory_items SET cost_price = ?, is_reorderable = 1, updated_at = datetime('now') WHERE id = ?", bestMatch.price, item.id);
      await adb.run("UPDATE inventory_items SET retail_price = ?, updated_at = datetime('now') WHERE id = ? AND (retail_price IS NULL OR retail_price = 0)", Math.round(bestMatch.price * 1.4 * 100) / 100, item.id);
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

router.get('/condition-templates', async (req, res) => {
  const adb = req.asyncDb;
  const { category } = req.query;
  let templates: any[];
  if (category) {
    templates = await adb.all<any>('SELECT * FROM condition_templates WHERE category = ? ORDER BY is_default DESC, name ASC', category);
  } else {
    templates = await adb.all<any>('SELECT * FROM condition_templates ORDER BY category, is_default DESC, name ASC');
  }
  // Attach checks to each template
  await Promise.all(templates.map(async (t: any) => {
    t.checks = await adb.all<any>('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC', t.id);
  }));
  res.json({ success: true, data: templates });
});

router.post('/condition-templates', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { category, name } = req.body;
  if (!category || !name) throw new AppError('Category and name required', 400);
  const result = await adb.run('INSERT INTO condition_templates (category, name) VALUES (?, ?)', category, name);
  const template = await adb.get<any>('SELECT * FROM condition_templates WHERE id = ?', result.lastInsertRowid);
  (template as any).checks = [];
  res.status(201).json({ success: true, data: template });
});

router.put('/condition-templates/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, is_default } = req.body;
  await adb.run(`
    UPDATE condition_templates SET
      name = COALESCE(?, name),
      is_default = COALESCE(?, is_default)
    WHERE id = ?
  `, name ?? null, is_default ?? null, req.params.id);
  const template = await adb.get<any>('SELECT * FROM condition_templates WHERE id = ?', req.params.id);
  if (!template) throw new AppError('Template not found', 404);
  (template as any).checks = await adb.all<any>('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC', template.id);
  res.json({ success: true, data: template });
});

router.delete('/condition-templates/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const template = await adb.get<any>('SELECT * FROM condition_templates WHERE id = ?', req.params.id);
  if (!template) throw new AppError('Template not found', 404);
  if (template.is_default) throw new AppError('Cannot delete default template', 400);
  await adb.run('DELETE FROM condition_templates WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Template deleted' } });
});

// ==================== Condition Checks ====================

router.get('/condition-checks/:category', async (req, res) => {
  const adb = req.asyncDb;
  const template = await adb.get<any>(
    'SELECT * FROM condition_templates WHERE category = ? AND is_default = 1',
    req.params.category);
  if (!template) {
    res.json({ success: true, data: [] });
    return;
  }
  const checks = await adb.all<any>(
    'SELECT * FROM condition_checks WHERE template_id = ? AND is_active = 1 ORDER BY sort_order ASC',
    template.id);
  res.json({ success: true, data: checks });
});

router.post('/condition-checks', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { template_id, label } = req.body;
  if (!template_id || !label) throw new AppError('template_id and label required', 400);
  // Get max sort_order for this template
  const max = await adb.get<any>('SELECT MAX(sort_order) as m FROM condition_checks WHERE template_id = ?', template_id);
  const sort_order = (max?.m ?? -1) + 1;
  const result = await adb.run('INSERT INTO condition_checks (template_id, label, sort_order) VALUES (?, ?, ?)', template_id, label, sort_order);
  const check = await adb.get<any>('SELECT * FROM condition_checks WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: check });
});

router.put('/condition-checks/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { label, sort_order, is_active } = req.body;
  await adb.run(`
    UPDATE condition_checks SET
      label = COALESCE(?, label),
      sort_order = COALESCE(?, sort_order),
      is_active = COALESCE(?, is_active)
    WHERE id = ?
  `, label ?? null, sort_order ?? null, is_active ?? null, req.params.id);
  const check = await adb.get<any>('SELECT * FROM condition_checks WHERE id = ?', req.params.id);
  if (!check) throw new AppError('Check not found', 404);
  res.json({ success: true, data: check });
});

router.delete('/condition-checks/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<any>('SELECT * FROM condition_checks WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Check not found', 404);
  await adb.run('DELETE FROM condition_checks WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Check deleted' } });
});

// Bulk reorder checks for a template
router.put('/condition-checks-reorder/:templateId', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { order } = req.body; // array of check IDs in desired order
  if (!Array.isArray(order)) throw new AppError('order array required', 400);
  const update = db.prepare('UPDATE condition_checks SET sort_order = ? WHERE id = ? AND template_id = ?');
  const reorder = db.transaction((ids: number[]) => {
    ids.forEach((id, idx) => update.run(idx, id, req.params.templateId));
  });
  reorder(order);
  const checks = await adb.all<any>('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC', req.params.templateId);
  res.json({ success: true, data: checks });
});

// ==================== Notification Templates ====================

router.get('/notification-templates', async (req, res) => {
  const adb = req.asyncDb;
  const templates = await adb.all<any>('SELECT * FROM notification_templates ORDER BY id ASC');
  res.json({ success: true, data: { templates } });
});

router.put('/notification-templates/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { subject, email_body, sms_body, send_email_auto, send_sms_auto, is_active } = req.body;
  const existing = await adb.get<any>('SELECT * FROM notification_templates WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Notification template not found', 404);

  await adb.run(`
    UPDATE notification_templates SET
      subject = COALESCE(?, subject),
      email_body = COALESCE(?, email_body),
      sms_body = COALESCE(?, sms_body),
      send_email_auto = COALESCE(?, send_email_auto),
      send_sms_auto = COALESCE(?, send_sms_auto),
      is_active = COALESCE(?, is_active),
      updated_at = datetime('now')
    WHERE id = ?
  `,
    subject ?? null,
    email_body ?? null,
    sms_body ?? null,
    send_email_auto ?? null,
    send_sms_auto ?? null,
    is_active ?? null,
    req.params.id
  );
  const template = await adb.get<any>('SELECT * FROM notification_templates WHERE id = ?', req.params.id);
  res.json({ success: true, data: template });
});

// ==================== Checklist Templates ====================

router.get('/checklist-templates', async (req, res) => {
  const adb = req.asyncDb;
  const templates = await adb.all<any>('SELECT * FROM checklist_templates ORDER BY device_type, name');
  res.json({ success: true, data: { templates } });
});

router.post('/checklist-templates', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, device_type, items } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const result = await adb.run(
    'INSERT INTO checklist_templates (name, device_type, items, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    name, device_type || null, JSON.stringify(items || []), now, now);
  const template = await adb.get<any>('SELECT * FROM checklist_templates WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: template });
});

router.put('/checklist-templates/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, device_type, items } = req.body;
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  await adb.run(
    'UPDATE checklist_templates SET name = COALESCE(?, name), device_type = COALESCE(?, device_type), items = COALESCE(?, items), updated_at = ? WHERE id = ?',
    name ?? null, device_type ?? null, items ? JSON.stringify(items) : null, now, req.params.id);
  const template = await adb.get<any>('SELECT * FROM checklist_templates WHERE id = ?', req.params.id);
  res.json({ success: true, data: template });
});

router.delete('/checklist-templates/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  await adb.run('DELETE FROM checklist_templates WHERE id = ?', req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
});

// ==================== Logo Upload ====================

router.post('/logo', adminOnly, logoUpload.single('logo'), async (req, res) => {
  const adb = req.asyncDb;
  if (!req.file) throw new AppError('No file uploaded', 400);
  const logoPath = (req as any).tenantSlug
    ? `/uploads/${(req as any).tenantSlug}/${req.file.filename}`
    : `/uploads/${req.file.filename}`;
  await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', 'store_logo', logoPath);
  res.json({ success: true, data: { store_logo: logoPath } });
});

// ==================== SMS/Voice Provider Settings ====================

// GET /settings/sms/providers — Provider registry (for UI dropdown)
router.get('/sms/providers', (_req, res) => {
  res.json({ success: true, data: getProviderRegistry() });
});

// POST /settings/sms/test-connection — Test provider credentials without saving
router.post('/sms/test-connection', adminOnly, async (req, res, next) => {
  try {
    const { provider_type, credentials } = req.body as { provider_type: ProviderType; credentials: Record<string, string> };
    if (!provider_type) throw new AppError('Provider type is required', 400);

    const testProvider = createTestProvider(provider_type, credentials);
    if (testProvider.name === 'console' && provider_type !== 'console') {
      throw new AppError('Credentials incomplete — provider fell back to console', 400);
    }

    // Try sending a test (dry run — send to null which most providers will reject gracefully)
    // For Twilio: fetch account info instead
    if (provider_type === 'twilio' && credentials.account_sid) {
      const resp = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${credentials.account_sid}.json`, {
        headers: { 'Authorization': 'Basic ' + Buffer.from(`${credentials.account_sid}:${credentials.auth_token}`).toString('base64') },
      });
      if (!resp.ok) throw new AppError('Twilio authentication failed. Check Account SID and Auth Token.', 401);
      res.json({ success: true, data: { message: 'Twilio credentials verified', provider: 'twilio' } });
      return;
    }

    if (provider_type === 'telnyx' && credentials.api_key) {
      const resp = await fetch('https://api.telnyx.com/v2/phone_numbers?page[size]=1', {
        headers: { 'Authorization': `Bearer ${credentials.api_key}` },
      });
      if (!resp.ok) throw new AppError('Telnyx authentication failed. Check your API Key.', 401);
      res.json({ success: true, data: { message: 'Telnyx credentials verified', provider: 'telnyx' } });
      return;
    }

    // For other providers, just confirm the provider was created successfully
    res.json({ success: true, data: { message: `${provider_type} provider configured successfully`, provider: provider_type } });
  } catch (err) {
    next(err);
  }
});

// POST /settings/sms/reload — Hot-reload SMS provider from store_config
// Note: reloadSmsProvider uses sync db internally, keep req.db
router.post('/sms/reload', adminOnly, async (req, res) => {
  const db = req.db;
  const providerName = reloadSmsProvider(db);
  res.json({ success: true, data: { provider: providerName } });
});

// ---------------------------------------------------------------------------
// ENR-S8: GET /settings/audit-logs — Paginated audit log viewer
// ---------------------------------------------------------------------------
router.get('/audit-logs', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const pageSize = Math.min(100, parseInt(req.query.pagesize as string) || 50);
  const offset = (page - 1) * pageSize;
  const { event, user_id, from_date, to_date } = req.query as Record<string, string>;

  let where = 'WHERE 1=1';
  const params: any[] = [];

  if (event) {
    where += ' AND a.event = ?';
    params.push(event);
  }
  if (user_id) {
    where += ' AND a.user_id = ?';
    params.push(parseInt(user_id));
  }
  if (from_date) {
    where += ' AND a.created_at >= ?';
    params.push(from_date);
  }
  if (to_date) {
    where += ' AND a.created_at <= ?';
    params.push(to_date + ' 23:59:59');
  }

  const [totalRow, logs, eventTypes] = await Promise.all([
    adb.get<any>(`SELECT COUNT(*) as c FROM audit_logs a ${where}`, ...params),
    adb.all<any>(`
      SELECT a.*, u.first_name || ' ' || u.last_name as user_name, u.username
      FROM audit_logs a
      LEFT JOIN users u ON u.id = a.user_id
      ${where}
      ORDER BY a.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, pageSize, offset),
    adb.all<{ event: string }>('SELECT DISTINCT event FROM audit_logs ORDER BY event'),
  ]);

  const total = totalRow.c;

  res.json({
    success: true,
    data: {
      logs,
      event_types: eventTypes.map(e => e.event),
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
});

// ---------------------------------------------------------------------------
// ENR-S1: Settings import/export
// ---------------------------------------------------------------------------

// GET /settings/export — Download all store_config as JSON
router.get('/export', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const rows = await adb.all<{ key: string; value: string }>('SELECT key, value FROM store_config');
  const configData: Record<string, string> = {};
  for (const row of rows) {
    // Decrypt encrypted values for export
    configData[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key)
      ? decryptConfigValue(row.value)
      : row.value;
  }
  res.setHeader('Content-Disposition', 'attachment; filename="bizarrecrm-settings.json"');
  res.setHeader('Content-Type', 'application/json');
  res.json({ success: true, data: configData });
});

// POST /settings/import — Import settings from JSON, validate keys
router.post('/import', adminOnly, async (req, res) => {
  const db = req.db;
  const data = req.body as Record<string, string>;

  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new AppError('Request body must be a JSON object', 400);
  }

  const upsert = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  let imported = 0;
  let skipped = 0;

  const importMany = db.transaction(() => {
    for (const [key, value] of Object.entries(data)) {
      if (!ALLOWED_CONFIG_KEYS.has(key)) {
        skipped++;
        continue;
      }
      const strVal = String(value);
      const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
      upsert.run(key, storedVal);
      imported++;
    }
  });
  importMany();

  res.json({ success: true, data: { imported, skipped, total: Object.keys(data).length } });
});

// ---------------------------------------------------------------------------
// ENR-S6: Per-user preferences (convenience aliases under /settings)
// These complement the existing /preferences routes with bulk GET/PUT.
// ---------------------------------------------------------------------------

// GET /settings/preferences — returns all preferences for the current user
router.get('/preferences', async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const rows = await adb.all<any>('SELECT key, value FROM user_preferences WHERE user_id = ?', userId);
  const prefs: Record<string, unknown> = {};
  for (const row of rows) {
    try { prefs[row.key] = JSON.parse(row.value); } catch { prefs[row.key] = row.value; }
  }
  res.json({ success: true, data: prefs });
});

// PUT /settings/preferences — bulk upsert preferences for the current user
// Body: { theme: "dark", default_view: "list", timezone: "America/Toronto", ... }
router.put('/preferences', async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const data = req.body;

  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return res.status(400).json({ success: false, message: 'Body must be a JSON object of key-value pairs' });
  }

  const ALLOWED_PREF_KEYS = new Set([
    'theme', 'default_view', 'timezone', 'language', 'sidebar_collapsed',
    'ticket_default_sort', 'ticket_default_filter', 'ticket_page_size',
    'notification_sound', 'notification_desktop', 'dashboard_widgets',
    'pos_default_view', 'compact_mode',
  ]);

  const upsert = db.prepare(`
    INSERT INTO user_preferences (user_id, key, value) VALUES (?, ?, ?)
    ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value
  `);

  const saveAll = db.transaction(() => {
    for (const [key, value] of Object.entries(data)) {
      if (!ALLOWED_PREF_KEYS.has(key)) continue;
      upsert.run(userId, key, JSON.stringify(value));
    }
  });
  saveAll();

  // Return all prefs
  const rows = await adb.all<any>('SELECT key, value FROM user_preferences WHERE user_id = ?', userId);
  const prefs: Record<string, unknown> = {};
  for (const row of rows) {
    try { prefs[row.key] = JSON.parse(row.value); } catch { prefs[row.key] = row.value; }
  }
  res.json({ success: true, data: prefs });
});

// ---------------------------------------------------------------------------
// ENR-S7: Role-based module visibility
// Stored as JSON in store_config under key 'role_module_visibility'.
// Default: all roles see all modules. No server enforcement — UI only.
// ---------------------------------------------------------------------------

const DEFAULT_MODULE_VISIBILITY: Record<string, string[]> = {};

// GET /settings/module-visibility — returns the role->modules config
router.get('/module-visibility', async (req, res) => {
  const adb = req.asyncDb;
  const row = await adb.get<any>("SELECT value FROM store_config WHERE key = 'role_module_visibility'");
  let visibility = DEFAULT_MODULE_VISIBILITY;
  if (row?.value) {
    try { visibility = JSON.parse(row.value); } catch { /* use default */ }
  }
  res.json({ success: true, data: visibility });
});

// PUT /settings/module-visibility — save the role->modules config (admin only)
// Body: { "technician": ["tickets", "customers", "pos"], "cashier": ["pos", "invoices", "customers"] }
router.put('/module-visibility', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const data = req.body;

  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return res.status(400).json({ success: false, message: 'Body must be a JSON object mapping roles to module arrays' });
  }

  // Validate structure: each value must be an array of strings
  for (const [role, modules] of Object.entries(data)) {
    if (!Array.isArray(modules) || !modules.every((m): m is string => typeof m === 'string')) {
      return res.status(400).json({
        success: false,
        message: `Value for role "${role}" must be an array of module name strings`,
      });
    }
  }

  await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)',
    'role_module_visibility',
    JSON.stringify(data),
  );

  res.json({ success: true, data });
});

// ==================== ENR-S10: API Key Self-Service ====================

// GET /api-keys — list API keys (masked)
router.get('/api-keys', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const rows = await adb.all<any>(
    "SELECT id, key_prefix, key_hash, label, created_at, last_used_at FROM api_keys WHERE revoked_at IS NULL ORDER BY created_at DESC"
  );

  // Return masked keys: show prefix + ****
  const keys = rows.map((r: any) => ({
    id: r.id,
    key_masked: r.key_prefix + '****',
    label: r.label,
    created_at: r.created_at,
    last_used_at: r.last_used_at,
  }));

  res.json({ success: true, data: keys });
});

// POST /api-keys — generate a new API key
router.post('/api-keys', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { label } = req.body;

  // Generate a random API key: bcrm_<32 hex chars>
  const rawKey = 'bcrm_' + crypto.randomBytes(24).toString('hex');
  const keyPrefix = rawKey.substring(0, 12); // First 12 chars for identification
  const keyHash = bcrypt.hashSync(rawKey, 10);

  // Ensure api_keys table exists (create if not — graceful for first use)
  await adb.run(`
    CREATE TABLE IF NOT EXISTS api_keys (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key_prefix TEXT NOT NULL,
      key_hash TEXT NOT NULL,
      label TEXT,
      created_by INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_used_at TEXT,
      revoked_at TEXT
    )
  `);

  const result = await adb.run(`
    INSERT INTO api_keys (key_prefix, key_hash, label, created_by)
    VALUES (?, ?, ?, ?)
  `, keyPrefix, keyHash, label || null, req.user!.id);

  audit(db, 'api_key_created', req.user!.id, req.ip || 'unknown', {
    api_key_id: result.lastInsertRowid,
    label: label || null,
  });

  // Return the full key ONLY on creation — it cannot be retrieved later
  res.status(201).json({
    success: true,
    data: {
      id: result.lastInsertRowid,
      key: rawKey,
      key_masked: keyPrefix + '****',
      label: label || null,
      message: 'Save this key now — it will not be shown again.',
    },
  });
});

// DELETE /api-keys/:id — revoke an API key
router.delete('/api-keys/:id', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);

  const existing = await adb.get<any>('SELECT id FROM api_keys WHERE id = ? AND revoked_at IS NULL', id);
  if (!existing) {
    throw new AppError('API key not found or already revoked', 404);
  }

  await adb.run("UPDATE api_keys SET revoked_at = datetime('now') WHERE id = ?", id);

  audit(db, 'api_key_revoked', req.user!.id, req.ip || 'unknown', { api_key_id: id });

  res.json({ success: true, data: { message: 'API key revoked' } });
});

export default router;
