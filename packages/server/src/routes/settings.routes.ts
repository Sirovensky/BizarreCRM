import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { verifySync } from 'otplib';
import { AppError } from '../middleware/errorHandler.js';
import { config } from '../config.js';
import { requireFeature } from '../middleware/tierGate.js';
import { reloadSmsProvider, createTestProvider, getProviderRegistry } from '../services/smsProvider.js';
import type { ProviderType } from '../services/smsProvider.js';
import { ENCRYPTED_CONFIG_KEYS, encryptConfigValue, decryptConfigValue } from '../utils/configEncryption.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { clearEmailCache, sendEmail, isEmailConfigured } from '../services/email.js';
import { refreshClient as refreshBlockChypClient } from '../services/blockchyp.js';
import { requireStepUpTotp } from '../middleware/stepUpTotp.js';
import { reserveStorage, decrementStorageBytes } from '../services/usageTracker.js';
import { normalizePhone } from '../utils/phone.js';
import {
  validateEmail,
  validatePhoneDigits,
  validateHexColor,
  validateRequiredString,
  roundCents,
} from '../utils/validate.js';
import { logger } from '../utils/logger.js';
import { fileUploadValidator } from '../middleware/fileUploadValidator.js';
import { enforceUploadQuota } from '../middleware/uploadQuota.js';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { parsePageSize, parsePage, MAX_PAGE_SIZE } from '../utils/pagination.js';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { ROLE_PERMISSIONS } from '@bizarre-crm/shared';

const LOGO_ALLOWED_MIMES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

// SEC: Allowlist of valid user roles derived from the shared ROLE_PERMISSIONS
// map. Any role string from req.body not in this set is rejected immediately
// so callers cannot craft an arbitrary role string (e.g. "superadmin") that
// bypasses authMiddleware / requirePermission checks downstream.
const VALID_ROLES = new Set(Object.keys(ROLE_PERMISSIONS));

// ─── TOTP secret decryption (P2FA4) ─────────────────────────────────────────
// AES-256-GCM decryption for TOTP secrets. Keys are derived from JWT_SECRET
// (+ superAdminSecret for v2) exactly like auth.routes.ts. This is inlined
// rather than imported because auth.routes.ts is not in scope for this file.
const TOTP_DECRYPT_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':totp:v1').digest(),
  2: crypto.createHash('sha256').update(config.jwtSecret + ':totp-encryption:v2:' + config.superAdminSecret).digest(),
};

function decryptTotpSecret(ciphertext: string): string {
  if (!ciphertext.includes(':')) return ciphertext;
  if (!ciphertext.startsWith('v')) {
    const key = crypto.createHash('sha256').update(config.jwtSecret).digest();
    const [ivHex, tagHex, encHex] = ciphertext.split(':');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
    return decipher.update(Buffer.from(encHex, 'hex')) + decipher.final('utf8');
  }
  const [vStr, ivHex, tagHex, encHex] = ciphertext.split(':');
  const version = parseInt(vStr.slice(1), 10);
  const key = TOTP_DECRYPT_KEYS[version];
  if (!key) throw new Error(`Unknown encryption key version: ${version}`);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  return decipher.update(Buffer.from(encHex, 'hex')) + decipher.final('utf8');
}

// SCAN-648: Guard that all values in a request body map are strings.
// Rejects non-string values at the boundary instead of silently coercing them.
function isStringMap(obj: unknown): obj is Record<string, string> {
  return (
    typeof obj === 'object' &&
    obj !== null &&
    !Array.isArray(obj) &&
    Object.values(obj as Record<string, unknown>).every(v => typeof v === 'string')
  );
}

const router = Router();

// Multer for logo upload
const logoUpload = multer({
  storage: multer.diskStorage({
    destination: (req: any, _file: any, cb: any) => {
      const slug = req.tenantSlug;
      const dest = slug ? path.join(config.uploadsPath, slug) : config.uploadsPath;
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

// Roles treated as admin for settings mutations.
// Mirrors the pattern in onboarding.routes.ts (ONBOARDING_ADMIN_ROLES) which
// admits 'owner' for tenants with legacy role strings, and normalises to
// lowercase so 'Admin' / 'ADMIN' are also accepted.
const SETTINGS_ADMIN_ROLES = new Set(['admin', 'owner']);

// Admin-only middleware for mutating settings
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (!req.user?.role || !SETTINGS_ADMIN_ROLES.has(req.user.role.toLowerCase())) {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
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
  // PROD105: per-tenant sender ID override (alphanumeric or E.164 phone).
  // Validated by SMS_SENDER_ID_RE / E164_RE at PUT /config time.
  'sms_sender_id',
  // Voice settings
  'voice_auto_record', 'voice_auto_transcribe', 'voice_announce_recording',
  'voice_inbound_action', 'voice_forward_number',
  // NOTE: RepairDesk / RepairShopr / MyRepairApp import API keys are deliberately
  // NOT whitelisted here. They are never persisted to store_config — the import
  // endpoints require the key in the request body and only hold it in memory for
  // the duration of the import run.
  // SMTP (per-tenant email credentials)
  'smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from',
  // PROD105: per-tenant outbound email "From" identity (may differ from smtp_user/smtp_from
  // when sending through a relay that allows any verified sender).  Falls back to
  // smtp_from → smtp_user at send-time when empty.  Validated as an email address.
  'from_email',
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
  // First-run setup wizard (SSW)
  // wizard_completed: 'true' | 'skipped' | 'grandfathered' — controls whether the
  // wizard gate in App.tsx redirects new tenants to /setup on first login
  // theme: 'light' | 'dark' | 'system' — user preference; also mirrored in localStorage
  // for offline access and cross-device sync (localStorage wins for the current session)
  'wizard_completed',
  'theme',
  // SCAN-469: Shared-device mode (PIN-based session swap + auto-logoff policy)
  'shared_device_mode_enabled',
  'shared_device_auto_logoff_minutes',
  'shared_device_require_pin_on_switch',
]);

// ==================== Generic Config (key-value) ====================

// Sensitive config keys only visible to admins (hidden from non-admin users on GET /config)
const SENSITIVE_CONFIG_KEYS = new Set([
  'tcx_password',
  'smtp_pass',
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
]);

// GET /setup-status — check if initial store setup has been completed
// Also returns wizard_completed for the first-run setup wizard gate (SSW1).
//   setup_completed: boolean — admin account exists and basic setup is done
//   wizard_completed: 'true' | 'skipped' | 'grandfathered' | null — wizard gate state.
//     null means "brand new tenant, show the wizard" (only possible post-feature deploy)
router.get('/setup-status', async (req, res) => {
  const adb = req.asyncDb;
  const [row, nameRow, wizardRow] = await Promise.all([
    adb.get<any>("SELECT value FROM store_config WHERE key = 'setup_completed'"),
    adb.get<any>("SELECT value FROM store_config WHERE key = 'store_name'"),
    adb.get<any>("SELECT value FROM store_config WHERE key = 'wizard_completed'"),
  ]);
  const completed = row?.value === 'true';
  res.json({
    success: true,
    data: {
      setup_completed: completed,
      store_name: nameRow?.value || null,
      wizard_completed: wizardRow?.value || null,
    },
  });
});

// POST /complete-setup — save initial store info and mark setup as done
// V21: validate email / phone formats before persisting, not just trim.
router.post('/complete-setup', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { store_name, address, phone, email, timezone, currency } = req.body;

  // V21: require a real store name, reject whitespace-only values.
  const nameTrimmed = validateRequiredString(store_name, 'store_name', 255);

  // V21: email must match a valid format (or be empty/undefined).
  const emailValidated = validateEmail(email, 'store_email', false);

  // V21: phone is normalized to digits-only first, then length-checked.
  // Empty phone is allowed.
  let phoneValidated: string | null = null;
  if (phone !== undefined && phone !== null && String(phone).trim() !== '') {
    const digits = normalizePhone(String(phone));
    phoneValidated = validatePhoneDigits(digits, 'store_phone', false);
  }

  const addressTrimmed = typeof address === 'string' ? address.trim() : '';
  const timezoneTrimmed = typeof timezone === 'string' ? timezone.trim() : '';
  const currencyTrimmed = typeof currency === 'string' ? currency.trim() : '';

  const queries: Array<{ sql: string; params: unknown[] }> = [];
  const upsertSql = 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)';
  queries.push({ sql: upsertSql, params: ['store_name', nameTrimmed] });
  if (addressTrimmed) queries.push({ sql: upsertSql, params: ['store_address', addressTrimmed] });
  if (phoneValidated) queries.push({ sql: upsertSql, params: ['store_phone', phoneValidated] });
  if (emailValidated) queries.push({ sql: upsertSql, params: ['store_email', emailValidated] });
  if (timezoneTrimmed) queries.push({ sql: upsertSql, params: ['timezone', timezoneTrimmed] });
  if (currencyTrimmed) queries.push({ sql: upsertSql, params: ['currency', currencyTrimmed] });
  if (phoneValidated) queries.push({ sql: upsertSql, params: ['phone', phoneValidated] });
  if (addressTrimmed) queries.push({ sql: upsertSql, params: ['address', addressTrimmed] });
  if (emailValidated) queries.push({ sql: upsertSql, params: ['email', emailValidated] });
  queries.push({ sql: upsertSql, params: ['setup_completed', 'true'] });
  await adb.transaction(queries);

  res.json({ success: true, data: { message: 'Store setup completed' } });
});

router.get('/config', async (req, res) => {
  const adb = req.asyncDb;
  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const isAdmin = req.user?.role != null && SETTINGS_ADMIN_ROLES.has(req.user.role.toLowerCase());
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

// PROD105: SMS sender ID validation.
// Alphanumeric sender IDs: 1-11 chars, letters and digits only (GSMA spec).
// E.164 phone numbers: leading +, 1-3 digit country code, 7-11 digit subscriber.
// Header injection guard: both patterns exclude whitespace, \r, \n, and other
// control characters by construction (character class [A-Za-z0-9] / [\d]).
const SMS_ALPHA_SENDER_RE = /^[A-Za-z0-9]{1,11}$/;
const E164_RE = /^\+[1-9]\d{7,14}$/;

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
  // PROD105: per-tenant outbound From identity — same format rules as smtp_from.
  'from_email',
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
  // PROD105: SMS sender ID — must be alphanumeric (≤11 chars) OR E.164 phone.
  // We validate both forms here; the send path prefers alphanumeric when both
  // could technically match (a 11-char string starting with + is E.164, not alpha).
  if (key === 'sms_sender_id' && value) {
    if (!SMS_ALPHA_SENDER_RE.test(value) && !E164_RE.test(value)) {
      return (
        `sms_sender_id must be an alphanumeric sender ID (1-11 chars, letters and digits only) ` +
        `or an E.164 phone number (e.g. +13035551234), got: "${value}"`
      );
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

  // SCAN-648: Reject if any value is not a string — indicates a client bug.
  if (!isStringMap(req.body)) {
    return res.status(400).json({ success: false, message: 'All config values must be strings' });
  }

  // ENR-S2: Read old values for audit trail before updating
  const oldRows = await adb.all<any>('SELECT key, value FROM store_config');
  const oldConfig: Record<string, string> = {};
  for (const row of oldRows) {
    oldConfig[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key) ? decryptConfigValue(row.value) : row.value;
  }

  for (const [key, value] of Object.entries(req.body)) {
    if (!ALLOWED_CONFIG_KEYS.has(key)) continue;
    if (config.multiTenant && BLOCKED_IN_MULTITENANT.has(key)) continue;
    const strVal = value;
    const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
    await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', key, storedVal);

    const oldValue = oldConfig[key] ?? null;
    if (oldValue !== strVal) {
      const safeOld = SENSITIVE_CONFIG_KEYS.has(key) ? '***' : (oldValue ?? '(unset)');
      const safeNew = SENSITIVE_CONFIG_KEYS.has(key) ? '***' : strVal;
      audit(db, 'setting_changed', req.user!.id, req.ip || 'unknown', { key, old_value: safeOld, new_value: safeNew });
    }
  }

  // MW5: Clear cached email transporter when SMTP settings change.
  // PROD105: also clear on from_email change (per-tenant sender identity).
  const smtpKeys = ['smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'from_email'];
  if (smtpKeys.some(k => k in req.body)) {
    clearEmailCache();
  }

  // BL-CRED: Evict the BlockChyp client cache when credentials change so the
  // next terminal call uses the new keys immediately rather than after the
  // 5-minute TTL. Mirrors the clearEmailCache() pattern for SMTP.
  const blockchypCredKeys = ['blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key', 'blockchyp_test_mode'];
  if (blockchypCredKeys.some(k => k in req.body)) {
    refreshBlockChypClient();
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
  const isAdmin = req.user?.role != null && SETTINGS_ADMIN_ROLES.has(req.user.role.toLowerCase());
  const cfg: Record<string, string> = {};
  for (const row of rows) {
    if (!isAdmin && SENSITIVE_CONFIG_KEYS.has(row.key)) continue;
    cfg[row.key] = (isAdmin && ENCRYPTED_CONFIG_KEYS.has(row.key))
      ? decryptConfigValue(row.value)
      : row.value;
  }
  res.json({ success: true, data: cfg });
});

router.put('/store', adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  // SCAN-648: Reject if any value is not a string.
  if (!isStringMap(req.body)) {
    logger.warn('PUT /store: non-string value in request body — potential client bug');
    return res.status(400).json({ success: false, message: 'All store values must be strings' });
  }
  const allowed = ['store_name','address','phone','email','timezone','currency','tax_rate','receipt_header','receipt_footer','logo_url','sms_provider','tcx_host','tcx_extension','tcx_password','smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
  for (const [key, value] of Object.entries(req.body)) {
    if (!allowed.includes(key)) continue;
    const strVal = value;
    const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
    await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', key, storedVal);
  }

  // MW5: Clear cached email transporter when any SMTP credential changes.
  // Previously smtp_pass was missing, so a password rotation wouldn't take
  // effect until the next server restart.
  const smtpStoreKeys = ['smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from'];
  if (smtpStoreKeys.some(k => k in req.body)) {
    clearEmailCache();
  }

  const rows = await adb.all<any>('SELECT key, value FROM store_config');
  const cfg: Record<string, string> = {};
  for (const row of rows) cfg[row.key] = row.value;
  res.json({ success: true, data: cfg });
});

// ==================== Ticket Statuses ====================

router.get('/statuses', async (req, res) => {
  const adb = req.asyncDb;
  const statuses = await adb.all<any>('SELECT * FROM ticket_statuses ORDER BY sort_order ASC LIMIT 200');
  res.json({ success: true, data: statuses });
});

// V23: integer clamp helper for sort_order (0-9999).
function clampSortOrder(value: unknown, fieldName = 'sort_order'): number {
  if (value === undefined || value === null || value === '') return 0;
  const num = typeof value === 'number' ? value : parseFloat(String(value));
  if (!Number.isFinite(num)) throw new AppError(`${fieldName} must be a number`, 400);
  const int = Math.trunc(num);
  if (int < 0) return 0;
  if (int > 9999) return 9999;
  return int;
}

// V23: tax rate 0-100 with max 3 decimal precision.
function validateTaxRate(value: unknown, fieldName = 'rate'): number {
  if (value === undefined || value === null || value === '') {
    throw new AppError(`${fieldName} is required`, 400);
  }
  const num = typeof value === 'number' ? value : parseFloat(String(value));
  if (!Number.isFinite(num)) throw new AppError(`${fieldName} must be a number`, 400);
  if (num < 0 || num > 100) throw new AppError(`${fieldName} must be between 0 and 100`, 400);
  // Round to 3 decimals — kills `33.33333333333333` absurd precision.
  return Math.round(num * 1000) / 1000;
}

router.post('/statuses', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, color = '#6b7280', sort_order = 0, is_default = 0, is_closed = 0, is_cancelled = 0, notify_customer = 0, notification_template } = req.body;
  // V22: name must be a real non-empty string; color must be hex.
  const nameClean = validateRequiredString(name, 'name', 100);
  const colorClean = validateHexColor(color, 'color', true) ?? '#6b7280';
  // V23: sort_order clamped to 0-9999 integer.
  const sortOrderInt = clampSortOrder(sort_order, 'sort_order');

  const result = await adb.run(`
    INSERT INTO ticket_statuses (name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, nameClean, colorClean, sortOrderInt, is_default, is_closed, is_cancelled, notify_customer, notification_template || null);
  const status = await adb.get<any>('SELECT * FROM ticket_statuses WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: status });
});

router.put('/statuses/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer, notification_template } = req.body;

  // V22: validate color if present (must be hex).
  const colorClean = color !== undefined && color !== null && color !== ''
    ? validateHexColor(color, 'color', true)
    : null;
  // V22: if name was supplied, it must be a real string.
  const nameClean = name !== undefined && name !== null
    ? validateRequiredString(name, 'name', 100)
    : null;
  // V23: clamp sort_order if supplied.
  const sortOrderInt = sort_order !== undefined && sort_order !== null && sort_order !== ''
    ? clampSortOrder(sort_order, 'sort_order')
    : null;

  await adb.run(`
    UPDATE ticket_statuses SET
      name = COALESCE(?, name), color = COALESCE(?, color), sort_order = COALESCE(?, sort_order),
      is_default = COALESCE(?, is_default), is_closed = COALESCE(?, is_closed),
      is_cancelled = COALESCE(?, is_cancelled), notify_customer = COALESCE(?, notify_customer),
      notification_template = COALESCE(?, notification_template)
    WHERE id = ?
  `, nameClean, colorClean, sortOrderInt, is_default ?? null, is_closed ?? null,
    is_cancelled ?? null, notify_customer ?? null, notification_template ?? null, req.params.id);
  const status = await adb.get<any>('SELECT * FROM ticket_statuses WHERE id = ?', req.params.id);
  res.json({ success: true, data: status });
});

// D2: Deleting a status must also account for soft-deleted tickets.
// Previously only active (is_deleted = 0) tickets were checked, so deleting a
// status could orphan is_deleted=1 rows whose status_id now points nowhere.
// Fix: any ticket referencing the status (regardless of is_deleted) is migrated
// to the system default status before the delete proceeds. If no default exists
// and there are referencing tickets, we block the delete outright.
router.delete('/statuses/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const statusId = req.params.id;

  const refCount = await adb.get<any>(
    'SELECT COUNT(*) as c FROM tickets WHERE status_id = ?',
    statusId,
  );
  const referenced = (refCount?.c || 0) > 0;

  if (referenced) {
    // Find the system default (is_default = 1) that is NOT the status being deleted.
    const defaultStatus = await adb.get<any>(
      'SELECT id, name FROM ticket_statuses WHERE is_default = 1 AND id != ? LIMIT 1',
      statusId,
    );
    if (!defaultStatus) {
      throw new AppError(
        'Status is in use by tickets (including deleted). Set another status as default before deleting.',
        400,
      );
    }
    // Migrate every ticket (active + soft-deleted) to the default.
    await adb.run(
      'UPDATE tickets SET status_id = ?, updated_at = datetime(\'now\') WHERE status_id = ?',
      defaultStatus.id,
      statusId,
    );
    audit(db, 'status_delete_migrated_tickets', req.user!.id, req.ip || 'unknown', {
      from_status_id: Number(statusId),
      to_status_id: defaultStatus.id,
      migrated_ticket_count: refCount.c,
    });
  }

  await adb.run('DELETE FROM ticket_statuses WHERE id = ?', statusId);
  audit(db, 'status_deleted', req.user!.id, req.ip || 'unknown', { status_id: Number(statusId) });
  res.json({ success: true, data: { message: 'Status deleted' } });
});

// ==================== Tax Classes ====================

router.get('/tax-classes', async (req, res) => {
  const adb = req.asyncDb;
  const taxClasses = await adb.all<any>('SELECT * FROM tax_classes ORDER BY name ASC LIMIT 200');
  res.json({ success: true, data: taxClasses });
});

router.post('/tax-classes', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const { name, rate, is_default = 0 } = req.body;
  // V23: name is required, rate clamped to 3 decimals.
  const nameClean = validateRequiredString(name, 'name', 100);
  const rateClean = validateTaxRate(rate, 'rate');

  if (is_default) await adb.run('UPDATE tax_classes SET is_default = 0');
  const result = await adb.run(
    'INSERT INTO tax_classes (name, rate, is_default) VALUES (?, ?, ?)',
    nameClean,
    rateClean,
    is_default ? 1 : 0,
  );
  const tc = await adb.get<any>('SELECT * FROM tax_classes WHERE id = ?', result.lastInsertRowid);
  // AL3: auditing tax class creation because tax rate changes are financial.
  audit(db, 'tax_class_created', req.user!.id, req.ip || 'unknown', {
    tax_class_id: result.lastInsertRowid,
    name: nameClean,
    rate: rateClean,
    is_default: is_default ? 1 : 0,
  });
  res.status(201).json({ success: true, data: tc });
});

router.put('/tax-classes/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const { name, rate, is_default } = req.body;

  // AL3: read old values for a before-and-after audit record.
  const before = await adb.get<any>('SELECT * FROM tax_classes WHERE id = ?', req.params.id);
  if (!before) throw new AppError('Tax class not found', 404);

  // V23: clamp + validate if a new rate was supplied.
  const rateClean = rate !== undefined && rate !== null && rate !== ''
    ? validateTaxRate(rate, 'rate')
    : null;
  // V22/V23: validate name if supplied.
  const nameClean = name !== undefined && name !== null
    ? validateRequiredString(name, 'name', 100)
    : null;

  if (is_default) await adb.run('UPDATE tax_classes SET is_default = 0');
  await adb.run(
    'UPDATE tax_classes SET name = COALESCE(?, name), rate = COALESCE(?, rate), is_default = COALESCE(?, is_default) WHERE id = ?',
    nameClean,
    rateClean,
    is_default ?? null,
    req.params.id,
  );
  const tc = await adb.get<any>('SELECT * FROM tax_classes WHERE id = ?', req.params.id);
  // AL3: audit the financial mutation with a before/after snapshot.
  audit(db, 'tax_class_updated', req.user!.id, req.ip || 'unknown', {
    tax_class_id: Number(req.params.id),
    before: { name: before.name, rate: before.rate, is_default: before.is_default },
    after: { name: tc?.name, rate: tc?.rate, is_default: tc?.is_default },
  });
  res.json({ success: true, data: tc });
});

// D4: also refuse when a ticket_devices row references this tax class.
// The original check missed ticket_devices.tax_class_id, which meant deleting a
// tax class could leave unquoted device line items pointing nowhere.
// AL3: audit the delete because it is a financial mutation.
router.delete('/tax-classes/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const taxClassId = req.params.id;

  // Guard: block deleting the last remaining tax class.  pos.routes.ts relies on
  // `SELECT id, rate FROM tax_classes WHERE is_default = 1` returning a row for
  // every POS transaction. Deleting the only (default) class leaves the system
  // with no fallback tax rate, silently breaking checkout.
  const totalCount = await adb.get<{ c: number }>('SELECT COUNT(*) as c FROM tax_classes');
  if ((totalCount?.c ?? 0) <= 1) {
    throw new AppError('Cannot delete the last tax class — at least one must always exist', 400);
  }

  const [invCount, lineCount, deviceCount] = await Promise.all([
    adb.get<any>('SELECT COUNT(*) as c FROM inventory_items WHERE tax_class_id = ?', taxClassId),
    adb.get<any>('SELECT COUNT(*) as c FROM invoice_line_items WHERE tax_class_id = ?', taxClassId),
    adb.get<any>('SELECT COUNT(*) as c FROM ticket_devices WHERE tax_class_id = ?', taxClassId),
  ]);
  if ((invCount?.c || 0) > 0 || (lineCount?.c || 0) > 0 || (deviceCount?.c || 0) > 0) {
    throw new AppError(
      'Tax class is in use by inventory items, invoice line items, or ticket devices and cannot be deleted',
      400,
    );
  }

  const before = await adb.get<any>('SELECT * FROM tax_classes WHERE id = ?', taxClassId);
  await adb.run('DELETE FROM tax_classes WHERE id = ?', taxClassId);
  audit(db, 'tax_class_deleted', req.user!.id, req.ip || 'unknown', {
    tax_class_id: Number(taxClassId),
    name: before?.name,
    rate: before?.rate,
    is_default: before?.is_default,
  });
  res.json({ success: true, data: { message: 'Deleted' } });
});

// ==================== Payment Methods ====================

router.get('/payment-methods', async (req, res) => {
  const adb = req.asyncDb;
  const methods = await adb.all<any>('SELECT * FROM payment_methods WHERE is_active = 1 ORDER BY sort_order ASC LIMIT 200');
  res.json({ success: true, data: methods });
});

router.post('/payment-methods', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, sort_order = 0 } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run('INSERT INTO payment_methods (name, sort_order) VALUES (?, ?)', name, sort_order);
  const method = await adb.get<any>('SELECT * FROM payment_methods WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: method });
});

// ==================== Referral Sources ====================

router.get('/referral-sources', async (req, res) => {
  const adb = req.asyncDb;
  const sources = await adb.all<any>('SELECT * FROM referral_sources ORDER BY sort_order ASC LIMIT 200');
  res.json({ success: true, data: sources });
});

router.post('/referral-sources', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { name, sort_order = 0 } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run('INSERT INTO referral_sources (name, sort_order) VALUES (?, ?)', name, sort_order);
  const source = await adb.get<any>('SELECT * FROM referral_sources WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: source });
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

// SCAN-1098 [HIGH]: staff email dump was ungated. Any authenticated user
// (including revoked/low-privilege roles) could enumerate all staff emails
// + usernames + role assignments — a ready-made phishing + social-engineering
// target list including admin accounts. Gate behind adminOnly to match the
// POST/PUT/DELETE sibling handlers below.
router.get('/users', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const users = await adb.all<any>('SELECT id, username, email, first_name, last_name, role, is_active, created_at FROM users ORDER BY first_name ASC LIMIT 500');
  res.json({ success: true, data: users });
});

router.post('/users', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  // bcrypt imported at top level
  const { username, email, password, first_name, last_name, role = 'technician', pin } = req.body;
  if (!username || !first_name || !last_name) throw new AppError('Username, first name and last name required', 400);
  if (password && password.length < 8) throw new AppError('Password must be at least 8 characters', 400);
  // SCAN-1108: cap password/pin length BEFORE bcrypt.hashSync. bcryptjs is a
  // pure-JS implementation — a 10MB password string would block the single
  // Node event loop for minutes while the prep runs, stalling every other
  // request. bcrypt truncates inputs at 72 bytes anyway so the cap is a
  // no-op for legitimate callers.
  if (password && password.length > 72) throw new AppError('Password must be 72 characters or fewer', 400);
  if (pin != null && typeof pin === 'string' && pin.length > 32) throw new AppError('PIN must be 32 characters or fewer', 400);
  // SEC: Reject any role value that is not in the shared allowlist.
  if (!VALID_ROLES.has(role)) throw new AppError(`Invalid role "${role}". Must be one of: ${[...VALID_ROLES].join(', ')}`, 400);

  // Tier: enforce user limit (Free = 1 user, Pro = unlimited).
  // Only counts active users — deactivating a user frees up a seat.
  if (config.multiTenant && req.tenantLimits?.maxUsers != null) {
    const userCount = await adb.get<{ c: number }>(
      'SELECT COUNT(*) as c FROM users WHERE is_active = 1'
    );
    const current = userCount?.c ?? 0;
    if (current >= req.tenantLimits.maxUsers) {
      res.status(403).json({
        success: false,
        upgrade_required: true,
        feature: 'user_limit',
        message: `User limit reached (${current}/${req.tenantLimits.maxUsers}). Upgrade to Pro for unlimited users.`,
        current,
        limit: req.tenantLimits.maxUsers,
      });
      return;
    }
  }

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

  // AL1: audit user creation — especially important when the new user is an
  // admin/manager, because the old code left no paper trail for privilege grants.
  audit(db, 'user_created', req.user!.id, req.ip || 'unknown', {
    created_user_id: result.lastInsertRowid,
    username,
    role,
    has_password: !!password,
    has_pin: !!pin,
  });
  res.status(201).json({ success: true, data: user });
});

router.put('/users/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const db = req.db;
  const targetUserId = Number(req.params.id);
  // bcrypt imported at top level
  const { email, first_name, last_name, role, pin, password, is_active, home_location_id, admin_confirm_password, admin_totp_code } = req.body;
  if (password && password.length < 8) throw new AppError('Password must be at least 8 characters', 400);
  // SCAN-1108: mirror the POST cap — bcrypt DoS applies on PUT too.
  if (password && password.length > 72) throw new AppError('Password must be 72 characters or fewer', 400);
  if (pin != null && typeof pin === 'string' && pin.length > 32) throw new AppError('PIN must be 32 characters or fewer', 400);
  // SEC: Reject any role value that is not in the shared allowlist.
  if (role !== undefined && role !== null && !VALID_ROLES.has(role)) {
    throw new AppError(`Invalid role "${role}". Must be one of: ${[...VALID_ROLES].join(', ')}`, 400);
  }
  // Validate home_location_id: must be a positive integer pointing at an active location.
  let validatedHomeLocationId: number | null | undefined;
  if (home_location_id !== undefined) {
    if (home_location_id === null) {
      validatedHomeLocationId = null;
    } else {
      const hlid = parseInt(String(home_location_id), 10);
      if (!Number.isInteger(hlid) || hlid <= 0) {
        throw new AppError('home_location_id must be a positive integer', 400);
      }
      const locRow = await adb.get<{ id: number }>(
        'SELECT id FROM locations WHERE id = ? AND is_active = 1',
        hlid,
      );
      if (!locRow) throw new AppError('home_location_id references an unknown or inactive location', 400);
      validatedHomeLocationId = hlid;
    }
  }

  // Fetch the target user's current state — needed for A3 admin guard and
  // AL4 role-change audit.
  const targetBefore = await adb.get<any>(
    'SELECT id, username, role, is_active, password_hash FROM users WHERE id = ?',
    targetUserId,
  );
  if (!targetBefore) throw new AppError('User not found', 404);

  // SEC-L14: Prevent admin from demoting themselves
  if (role && req.user!.id === targetUserId && req.user!.role === 'admin' && role !== 'admin') {
    throw new AppError('Cannot demote your own admin account', 400);
  }

  // A3: Prevent one admin from demoting another admin without proper
  // safeguards. If the target is currently an admin and the change would
  // remove the admin role (or deactivate them), require either:
  //   (a) the caller is the same user (already blocked by SEC-L14 for demote),
  //   (b) at least 2 active admins would remain after the change.
  const isTargetAdmin = targetBefore.role === 'admin';
  const isRoleChange = role !== undefined && role !== null && role !== targetBefore.role;
  const isDemotingAdmin = isTargetAdmin && isRoleChange && role !== 'admin';
  const isDeactivatingAdmin = isTargetAdmin && (is_active === 0 || is_active === false);
  if ((isDemotingAdmin || isDeactivatingAdmin) && req.user!.id !== targetUserId) {
    const adminCountRow = await adb.get<{ c: number }>(
      "SELECT COUNT(*) as c FROM users WHERE role = 'admin' AND is_active = 1",
    );
    const activeAdmins = adminCountRow?.c ?? 0;
    // After this change, the target would no longer count as an active admin.
    const remaining = activeAdmins - 1;
    if (remaining < 2) {
      throw new AppError(
        'Cannot demote or deactivate another admin — at least 2 active admins must remain.',
        400,
      );
    }
  }

  // SEC-H17: 24 h cooldown on role mutations AFTER a backup-code recovery.
  // Prevents an attacker who ran /auth/recover-with-backup-code with a
  // stolen backup code + leaked email from immediately elevating role.
  // Cooldown applies to the TARGET user — an attacker who recovered the
  // target's session can still act within the target's existing role,
  // but cannot change it for 24 h, during which the legitimate user
  // should notice the password-reset notification and intervene.
  if (isRoleChange) {
    const lastRecoveryRow = await adb.get<{ last_backup_recovery_at: string | null }>(
      'SELECT last_backup_recovery_at FROM users WHERE id = ?',
      targetUserId,
    );
    const lastRecovery = lastRecoveryRow?.last_backup_recovery_at;
    if (lastRecovery) {
      const ageMs = Date.now() - Date.parse(String(lastRecovery) + 'Z');
      const COOLDOWN_MS = 24 * 60 * 60 * 1000;
      if (Number.isFinite(ageMs) && ageMs < COOLDOWN_MS) {
        const remainingHrs = Math.ceil((COOLDOWN_MS - ageMs) / (60 * 60 * 1000));
        throw new AppError(
          `Role cannot be changed for ${remainingHrs}h after a backup-code recovery. Try again later.`,
          403,
        );
      }
    }
  }

  // P2FA4: any of password / pin / role change is a sensitive mutation and
  // must be re-authenticated with the CALLER's current password (and TOTP if
  // they have 2FA enabled). This guards against a hijacked admin session
  // silently elevating or rotating another user's credentials.
  const sensitiveChange = !!password || !!pin || isRoleChange;
  if (sensitiveChange) {
    if (typeof admin_confirm_password !== 'string' || !admin_confirm_password) {
      throw new AppError('admin_confirm_password is required for password, PIN, or role changes', 401);
    }
    // SCAN-1181: sibling gap of SCAN-1178/1155. An attacker with a hijacked
    // admin session could otherwise brute the admin's own password here to
    // step-up to password/pin/role changes on any user. 5 attempts per hour
    // per (admin,ip) matches the cap used on /change-password + /change-pin.
    const reauthRateKey = `${req.user!.id}:${req.ip || 'unknown'}`;
    if (!checkWindowRate(db, 'settings_user_reauth', reauthRateKey, 5, 3600_000)) {
      throw new AppError('Too many re-auth attempts. Try again in an hour.', 429);
    }
    const caller = await adb.get<any>(
      'SELECT id, password_hash, totp_secret, totp_enabled FROM users WHERE id = ? AND is_active = 1',
      req.user!.id,
    );
    if (!caller || !caller.password_hash) {
      recordWindowFailure(db, 'settings_user_reauth', reauthRateKey, 3600_000);
      throw new AppError('Re-authentication failed', 401);
    }
    const callerPwMatch = bcrypt.compareSync(admin_confirm_password, caller.password_hash);
    if (!callerPwMatch) {
      recordWindowFailure(db, 'settings_user_reauth', reauthRateKey, 3600_000);
      audit(db, 'admin_reauth_failed', req.user!.id, req.ip || 'unknown', {
        target_user_id: targetUserId,
        reason: 'bad_password',
      });
      throw new AppError('admin_confirm_password is incorrect', 401);
    }
    if (caller.totp_enabled && caller.totp_secret) {
      if (typeof admin_totp_code !== 'string' || !/^\d{6}$/.test(admin_totp_code)) {
        throw new AppError('admin_totp_code (6 digits) is required for this change', 401);
      }
      let totpValid = false;
      try {
        const secret = decryptTotpSecret(caller.totp_secret);
        totpValid = Boolean(verifySync({ token: admin_totp_code, secret }));
      } catch (err) {
        logger.error('TOTP verification failed during sensitive user update', { err, targetUserId });
        totpValid = false;
      }
      if (!totpValid) {
        // SCAN-1181: bad TOTP also counts toward the cap.
        recordWindowFailure(db, 'settings_user_reauth', reauthRateKey, 3600_000);
        audit(db, 'admin_reauth_failed', req.user!.id, req.ip || 'unknown', {
          target_user_id: targetUserId,
          reason: 'bad_totp',
        });
        throw new AppError('admin_totp_code is invalid', 401);
      }
    }
  }

  // Tier: if reactivating a user (is_active 0 -> 1), enforce the seat limit.
  // Only check when transitioning from inactive to active to avoid blocking no-op updates.
  const isReactivating = is_active === 1 || is_active === true;
  if (config.multiTenant && isReactivating && req.tenantLimits?.maxUsers != null) {
    const currentRow = await adb.get<{ is_active: number }>(
      'SELECT is_active FROM users WHERE id = ?',
      targetUserId
    );
    const wasInactive = currentRow && currentRow.is_active === 0;
    if (wasInactive) {
      const userCount = await adb.get<{ c: number }>(
        'SELECT COUNT(*) as c FROM users WHERE is_active = 1 AND id != ?',
        targetUserId
      );
      const otherActive = userCount?.c ?? 0;
      if (otherActive >= req.tenantLimits.maxUsers) {
        res.status(403).json({
          success: false,
          upgrade_required: true,
          feature: 'user_limit',
          message: `User limit reached (${otherActive}/${req.tenantLimits.maxUsers}). Upgrade to Pro for unlimited users.`,
          current: otherActive,
          limit: req.tenantLimits.maxUsers,
        });
        return;
      }
    }
  }

  const hash = password ? bcrypt.hashSync(password, 12) : null;
  const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
  // home_location_id: use explicit sentinel to distinguish "not supplied"
  // (undefined → skip via COALESCE) from "explicitly cleared" (null → write NULL).
  const homeLocSql = validatedHomeLocationId !== undefined
    ? ', home_location_id = ?'
    : '';
  const homeLocParam = validatedHomeLocationId !== undefined ? [validatedHomeLocationId] : [];
  await adb.run(`
    UPDATE users SET
      email = COALESCE(?, email), first_name = COALESCE(?, first_name),
      last_name = COALESCE(?, last_name), role = COALESCE(?, role),
      pin = COALESCE(?, pin), is_active = COALESCE(?, is_active),
      password_hash = COALESCE(?, password_hash)${homeLocSql},
      updated_at = datetime('now')
    WHERE id = ?
  `, email ?? null, first_name ?? null, last_name ?? null, role ?? null, pinHash, is_active ?? null, hash, ...homeLocParam, req.params.id);

  // SEC-L13: If password was changed, invalidate all sessions except the current admin's
  if (password) {
    await adb.run('DELETE FROM sessions WHERE user_id = ? AND id != ?', targetUserId, req.user!.sessionId);
    audit(db, 'password_changed_by_admin', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId });
  }

  // AL4: audit role changes. Previously only password changes were logged,
  // so a silent privilege grant (technician -> admin) left no paper trail.
  if (isRoleChange) {
    audit(db, 'user_role_changed', req.user!.id, req.ip || 'unknown', {
      target_user_id: targetUserId,
      old_role: targetBefore.role,
      new_role: role,
    });
    // If the role change also deactivates admin privileges for the target,
    // revoke their sessions so they can't continue acting as admin.
    if (targetBefore.role === 'admin' && role !== 'admin') {
      await adb.run('DELETE FROM sessions WHERE user_id = ?', targetUserId);
    }
  }

  if (pin) {
    audit(db, 'pin_changed_by_admin', req.user!.id, req.ip || 'unknown', { target_user_id: targetUserId });
  }

  // If user was deactivated, invalidate all their sessions
  if (is_active === 0 || is_active === false) {
    await adb.run('DELETE FROM sessions WHERE user_id = ?', req.params.id);
  }

  const user = await adb.get<any>(
    'SELECT id, username, email, first_name, last_name, role, is_active, home_location_id FROM users WHERE id = ?',
    req.params.id,
  );
  res.json({ success: true, data: user });
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
          WHERE price > 0 AND LOWER(name) LIKE ? ESCAPE '\\' AND LOWER(name) LIKE ? ESCAPE '\\'
          LIMIT 50
        `, `%${escapeLike(device.toLowerCase())}%`, `%${escapeLike(partType.toLowerCase())}%`);

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
          WHERE price > 0 AND LOWER(name) LIKE ? ESCAPE '\\'
          GROUP BY name LIMIT 20
        `, `%${escapeLike(searchTerm.toLowerCase())}%`);

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
  const queries = order.map((id: number, idx: number) => ({
    sql: 'UPDATE condition_checks SET sort_order = ? WHERE id = ? AND template_id = ?',
    params: [idx, id, req.params.templateId],
  }));
  await adb.transaction(queries);
  const checks = await adb.all<any>('SELECT * FROM condition_checks WHERE template_id = ? ORDER BY sort_order ASC', req.params.templateId);
  res.json({ success: true, data: checks });
});

// ==================== Notification Templates ====================

router.get('/notification-templates', async (req, res) => {
  const adb = req.asyncDb;
  const templates = await adb.all<any>('SELECT * FROM notification_templates ORDER BY id ASC');
  res.json({ success: true, data: templates });
});

router.put('/notification-templates/:id', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const { subject, email_body, sms_body, send_email_auto, send_sms_auto, is_active, show_in_canned } = req.body;
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
      show_in_canned = COALESCE(?, show_in_canned),
      updated_at = datetime('now')
    WHERE id = ?
  `,
    subject ?? null,
    email_body ?? null,
    sms_body ?? null,
    send_email_auto ?? null,
    send_sms_auto ?? null,
    is_active ?? null,
    show_in_canned ?? null,
    req.params.id
  );
  const template = await adb.get<any>('SELECT * FROM notification_templates WHERE id = ?', req.params.id);
  res.json({ success: true, data: template });
});

// ==================== Checklist Templates ====================

router.get('/checklist-templates', async (req, res) => {
  const adb = req.asyncDb;
  const templates = await adb.all<any>('SELECT * FROM checklist_templates ORDER BY device_type, name');
  res.json({ success: true, data: templates });
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

router.post('/logo', adminOnly, enforceUploadQuota, logoUpload.single('logo'), fileUploadValidator({ allowedMimes: LOGO_ALLOWED_MIMES }), async (req, res) => {
  const adb = req.asyncDb;
  if (!req.file) throw new AppError('No file uploaded', 400);

  // Atomic storage reservation
  const fileSize = req.file.size ?? 0;
  if (!reserveStorage(req.tenantId, fileSize, req.tenantLimits?.storageLimitMb ?? null)) {
    if (req.file.path) { try { fs.unlinkSync(req.file.path); } catch {} }
    res.status(403).json({
      success: false,
      upgrade_required: true,
      feature: 'storage_limit',
      message: `Storage limit (${req.tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for 30 GB storage.`,
    });
    return;
  }

  // Refund the previous logo's bytes if one exists (replacing logo shouldn't grow quota)
  try {
    const prevRow = await adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'store_logo'");
    if (prevRow?.value && prevRow.value.startsWith('/uploads/')) {
      const prevAbs = path.join(config.uploadsPath, prevRow.value.replace(/^\/uploads\//, ''));
      const stat = fs.statSync(prevAbs);
      decrementStorageBytes(req.tenantId, stat.size);
      try { fs.unlinkSync(prevAbs); } catch {}
    }
  } catch { /* previous logo missing or unreadable */ }

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
// L6: Every provider now runs a real authenticated API call against the
// vendor's account-info endpoint so bad credentials surface here instead of
// silently failing at first send. The previous implementation only tested
// Twilio + Telnyx; Bandwidth / Plivo / Vonage short-circuited to a "success"
// response regardless of the credentials they were handed.
router.post('/sms/test-connection', adminOnly, async (req, res, next) => {
  try {
    const { provider_type, credentials } = req.body as { provider_type: ProviderType; credentials: Record<string, string> };
    if (!provider_type) throw new AppError('Provider type is required', 400);
    if (!credentials || typeof credentials !== 'object') {
      throw new AppError('Credentials are required', 400);
    }

    const testProvider = createTestProvider(provider_type, credentials);
    if (testProvider.name === 'console' && provider_type !== 'console') {
      throw new AppError('Credentials incomplete — provider fell back to console', 400);
    }

    // 10s hard timeout on every outbound probe — matches other provider calls.
    const FETCH_TIMEOUT_MS = 10_000;
    const timeoutSignal = () => AbortSignal.timeout(FETCH_TIMEOUT_MS);

    if (provider_type === 'twilio') {
      if (!credentials.account_sid || !credentials.auth_token) {
        throw new AppError('Twilio requires account_sid and auth_token', 400);
      }
      const resp = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(credentials.account_sid)}.json`,
        {
          headers: {
            Authorization: 'Basic ' + Buffer.from(`${credentials.account_sid}:${credentials.auth_token}`).toString('base64'),
          },
          signal: timeoutSignal(),
        },
      );
      if (!resp.ok) throw new AppError('Twilio authentication failed. Check Account SID and Auth Token.', 401);
      res.json({ success: true, data: { message: 'Twilio credentials verified', provider: 'twilio' } });
      return;
    }

    if (provider_type === 'telnyx') {
      if (!credentials.api_key) throw new AppError('Telnyx requires api_key', 400);
      const resp = await fetch('https://api.telnyx.com/v2/phone_numbers?page[size]=1', {
        headers: { Authorization: `Bearer ${credentials.api_key}` },
        signal: timeoutSignal(),
      });
      if (!resp.ok) throw new AppError('Telnyx authentication failed. Check your API Key.', 401);
      res.json({ success: true, data: { message: 'Telnyx credentials verified', provider: 'telnyx' } });
      return;
    }

    if (provider_type === 'bandwidth') {
      if (!credentials.account_id || !credentials.username || !credentials.password) {
        throw new AppError('Bandwidth requires account_id, username, and password', 400);
      }
      const auth = 'Basic ' + Buffer.from(`${credentials.username}:${credentials.password}`).toString('base64');
      // Account-level GET — 200 means credentials work, 401/403 means not.
      const resp = await fetch(
        `https://messaging.bandwidth.com/api/v2/users/${encodeURIComponent(credentials.account_id)}/messages?limit=1`,
        {
          headers: { Authorization: auth },
          signal: timeoutSignal(),
        },
      );
      if (resp.status === 401 || resp.status === 403) {
        throw new AppError('Bandwidth authentication failed. Check account_id, username, and password.', 401);
      }
      if (!resp.ok && resp.status !== 400) {
        // 400 can happen on a query-validation error even with valid creds,
        // so treat 200/400 as "credentials accepted" and anything else as error.
        throw new AppError(`Bandwidth test failed (HTTP ${resp.status})`, 502);
      }
      res.json({ success: true, data: { message: 'Bandwidth credentials verified', provider: 'bandwidth' } });
      return;
    }

    if (provider_type === 'plivo') {
      if (!credentials.auth_id || !credentials.auth_token) {
        throw new AppError('Plivo requires auth_id and auth_token', 400);
      }
      const auth = 'Basic ' + Buffer.from(`${credentials.auth_id}:${credentials.auth_token}`).toString('base64');
      const resp = await fetch(
        `https://api.plivo.com/v1/Account/${encodeURIComponent(credentials.auth_id)}/`,
        {
          headers: { Authorization: auth },
          signal: timeoutSignal(),
        },
      );
      if (!resp.ok) {
        throw new AppError('Plivo authentication failed. Check Auth ID and Auth Token.', 401);
      }
      res.json({ success: true, data: { message: 'Plivo credentials verified', provider: 'plivo' } });
      return;
    }

    if (provider_type === 'vonage') {
      if (!credentials.api_key || !credentials.api_secret) {
        throw new AppError('Vonage requires api_key and api_secret', 400);
      }
      const params = new URLSearchParams({
        api_key: credentials.api_key,
        api_secret: credentials.api_secret,
      });
      const resp = await fetch(`https://rest.nexmo.com/account/get-balance?${params.toString()}`, {
        signal: timeoutSignal(),
      });
      if (!resp.ok) {
        throw new AppError(`Vonage test failed (HTTP ${resp.status})`, 502);
      }
      const data = (await resp.json().catch(() => null)) as any;
      // Vonage returns 200 on auth failure too, with { "error-code": "401" }
      if (data && (data['error-code'] || data.error_code) && String(data['error-code'] ?? data.error_code) !== '200') {
        throw new AppError('Vonage authentication failed. Check API Key and Secret.', 401);
      }
      res.json({ success: true, data: { message: 'Vonage credentials verified', provider: 'vonage' } });
      return;
    }

    if (provider_type === 'console') {
      res.json({ success: true, data: { message: 'Console provider ready (debug only)', provider: 'console' } });
      return;
    }

    // Unknown provider type — reject rather than returning a fake success.
    throw new AppError(`Unknown SMS provider type: ${provider_type}`, 400);
  } catch (err) {
    if (err instanceof Error && err.name === 'TimeoutError') {
      return next(new AppError('Provider API timeout — check network connectivity', 504));
    }
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

// WEB-W1-034: POST /settings/test-smtp — send a test email to verify SMTP config
// SEC: admin-only; uses the stored smtp credentials via sendEmail service.
router.post('/test-smtp', adminOnly, async (req, res) => {
  const db = req.db;
  if (!isEmailConfigured(db)) {
    return res.status(400).json({
      success: false,
      message: 'SMTP is not configured. Fill in smtp_host, smtp_user, and smtp_pass first.',
    });
  }
  const recipient = (req.body?.to as string | undefined)?.trim() || req.user?.email;
  if (!recipient) {
    return res.status(400).json({ success: false, message: 'No recipient email address. Provide ?to= or log in.' });
  }
  const ok = await sendEmail(db, {
    to: recipient,
    subject: 'SMTP Test — Bizarre CRM',
    html: '<p>This is a test email from your Bizarre CRM setup. If you received this, your SMTP configuration is working correctly.</p>',
    text: 'This is a test email from your Bizarre CRM setup. If you received this, your SMTP configuration is working correctly.',
  });
  if (ok) {
    return res.json({ success: true, data: { message: `Test email sent to ${recipient}` } });
  }
  return res.status(500).json({ success: false, message: 'Failed to send test email. Check server logs for SMTP errors.' });
});

// ---------------------------------------------------------------------------
// ENR-S8: GET /settings/audit-logs — Paginated audit log viewer
// ---------------------------------------------------------------------------
// SEC-H120: enforce MAX_PAGE_SIZE=100 via pagination utility. Accept either
// page/pagesize OR limit/offset query parameters. Max offset capped at
// 1_000_000 to stop DoS via skip-ahead pagination.
router.get('/audit-logs', adminOnly, async (req, res) => {
  const adb = req.asyncDb;
  const MAX_OFFSET = 1_000_000;

  // Accept both `limit` + `offset` and `page` + `pagesize` so existing UI code
  // keeps working while new clients can use the simpler limit/offset form.
  const rawOffset = parseInt(req.query.offset as string);

  let pageSize: number;
  let offset: number;
  let page: number;

  if (req.query.limit !== undefined) {
    pageSize = parsePageSize(req.query.limit, 50);
    offset = Number.isFinite(rawOffset) && rawOffset >= 0
      ? Math.min(MAX_OFFSET, rawOffset)
      : 0;
    page = Math.floor(offset / pageSize) + 1;
  } else {
    page = parsePage(req.query.page);
    pageSize = parsePageSize(req.query.pagesize, 50);
    offset = Math.min(MAX_OFFSET, (page - 1) * pageSize);
  }

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
    adb.all<{ event: string }>('SELECT DISTINCT event FROM audit_logs ORDER BY event LIMIT 500'),
  ]);

  const total = totalRow.c;

  res.json({
    success: true,
    data: {
      logs,
      event_types: eventTypes.map(e => e.event),
      pagination: {
        page,
        per_page: pageSize,
        limit: pageSize,
        offset,
        total,
        total_pages: Math.ceil(total / pageSize),
        max_limit: MAX_PAGE_SIZE,
      },
    },
  });
});

// ---------------------------------------------------------------------------
// ENR-S1: Settings import/export
// ---------------------------------------------------------------------------

// GET /settings/export — Download all store_config as JSON
// SEC-H56: Step-up TOTP required before any PII export.
router.get('/export', adminOnly, requireStepUpTotp('GET /settings-ext/export.json'), async (req, res) => {
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
  const adb = req.asyncDb;

  if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) {
    throw new AppError('Request body must be a JSON object', 400);
  }
  // SCAN-648: Reject non-string values — settings are all string-valued.
  if (!isStringMap(req.body)) {
    logger.warn('POST /import: non-string value in settings import payload — potential client bug');
    return res.status(400).json({ success: false, message: 'All settings values must be strings' });
  }
  const data = req.body;

  let imported = 0;
  let skipped = 0;
  const queries: Array<{ sql: string; params: unknown[] }> = [];

  for (const [key, value] of Object.entries(data)) {
    if (!ALLOWED_CONFIG_KEYS.has(key)) {
      skipped++;
      continue;
    }
    const strVal = value;
    const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
    queries.push({ sql: 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', params: [key, storedVal] });
    imported++;
  }
  if (queries.length > 0) await adb.transaction(queries);

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

  const prefQueries: Array<{ sql: string; params: unknown[] }> = [];
  for (const [key, value] of Object.entries(data)) {
    if (!ALLOWED_PREF_KEYS.has(key)) continue;
    prefQueries.push({
      sql: 'INSERT INTO user_preferences (user_id, key, value) VALUES (?, ?, ?) ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value',
      params: [userId, key, JSON.stringify(value)],
    });
  }
  if (prefQueries.length > 0) await adb.transaction(prefQueries);

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
router.get('/api-keys', requireFeature('apiKeys'), adminOnly, async (req, res) => {
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
router.post('/api-keys', requireFeature('apiKeys'), adminOnly, async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const { label } = req.body;

  // Generate a random API key: bcrm_<32 hex chars>
  const rawKey = 'bcrm_' + crypto.randomBytes(24).toString('hex');
  const keyPrefix = rawKey.substring(0, 12); // First 12 chars for identification
  // SEC-L32: bump bcrypt cost from 10 → 12 for API key hashes. Cost 10
  // runs ~0.1s single-core; cost 12 runs ~0.4s and lifts the offline
  // brute-force ceiling by 4× per GPU-hour. API keys are high-value
  // (full tenant scope, no 2FA, no rate-limit friction on the receiving
  // side) — the same reasoning that justifies cost 12 on password
  // hashes applies here, and this is called at most once per key
  // creation so the UX cost is negligible.
  const keyHash = bcrypt.hashSync(rawKey, 12);

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
router.delete('/api-keys/:id', requireFeature('apiKeys'), adminOnly, async (req, res) => {
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

// ─── ENR-A6: Tenant-admin webhook dead-letter endpoints ──────────────────────
// Super-admin already has read + retry via super-admin.routes.ts. These routes
// give the tenant admin the same visibility into their own dead-letter queue
// without needing to contact support, and add a test-delivery action missing
// entirely (BUG: no test-delivery existed for any role before this).

// GET /webhook-failures — list this tenant's dead-lettered deliveries
router.get('/webhook-failures', adminOnly, async (req: Request, res: Response) => {
  const db = req.db;
  const tableExists = db
    .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='webhook_delivery_failures'")
    .get();
  if (!tableExists) {
    res.json({ success: true, data: { failures: [], total: 0 } });
    return;
  }
  const limit = Math.min(parseInt(req.query.limit as string || '50', 10), 200);
  const rows = db
    .prepare(
      'SELECT id, endpoint, event, attempts, last_error, last_status, created_at FROM webhook_delivery_failures ORDER BY created_at DESC LIMIT ?'
    )
    .all(limit) as Array<{
      id: number; endpoint: string; event: string;
      attempts: number; last_error: string | null; last_status: number | null; created_at: string;
    }>;
  const totalRow = db
    .prepare('SELECT COUNT(*) as c FROM webhook_delivery_failures')
    .get() as { c: number };
  res.json({ success: true, data: { failures: rows, total: totalRow.c } });
});

// POST /webhook-failures/:id/retry — operator retry of a single dead-lettered delivery
router.post('/webhook-failures/:id/retry', adminOnly, async (req: Request, res: Response) => {
  const failureId = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(failureId)) {
    throw new AppError('Invalid failure id', 400);
  }
  const { retryDeliveryFailure } = await import('../services/webhooks.js');
  const result = await retryDeliveryFailure(req.db, failureId);
  audit(req.db, 'webhook_retry', req.user!.id, req.ip || 'unknown', { failure_id: failureId, ok: result.ok });
  res.json({ success: true, data: result });
});

// ---------------------------------------------------------------------------
// GET /receipt-templates — list all receipt templates
// GET /receipt-templates/for-type/:type — return the best template for a
//   given transaction type ('default' | 'warranty' | 'trade_in'), with
//   fallback: exact type → default+is_default → first row.
// PUT /receipt-templates/:id — update a template's header/footer text
// ---------------------------------------------------------------------------

interface ReceiptTemplateRow {
  id: number;
  name: string;
  type: string;
  header_text: string | null;
  footer_text: string | null;
  show_warranty_info: number;
  show_trade_in_info: number;
  is_default: number;
  created_at: string;
}

router.get('/receipt-templates', async (req: Request, res: Response) => {
  const rows = await req.asyncDb.all<ReceiptTemplateRow>(
    'SELECT * FROM receipt_templates ORDER BY is_default DESC, id ASC'
  );
  res.json({ success: true, data: rows });
});

router.get('/receipt-templates/for-type/:type', async (req: Request, res: Response) => {
  const type = req.params.type as string;
  const validTypes = new Set(['default', 'warranty', 'trade_in', 'credit_note']);
  const safeType = validTypes.has(type) ? type : 'default';

  // 1. Exact type match
  let tpl = await req.asyncDb.get<ReceiptTemplateRow>(
    'SELECT * FROM receipt_templates WHERE type = ? LIMIT 1', safeType
  );
  // 2. Fallback: default row with is_default=1
  if (!tpl) {
    tpl = await req.asyncDb.get<ReceiptTemplateRow>(
      "SELECT * FROM receipt_templates WHERE type = 'default' AND is_default = 1 LIMIT 1"
    );
  }
  // 3. Fallback: any row
  if (!tpl) {
    tpl = await req.asyncDb.get<ReceiptTemplateRow>(
      'SELECT * FROM receipt_templates ORDER BY is_default DESC, id ASC LIMIT 1'
    );
  }

  if (!tpl) throw new AppError('No receipt templates found', 404);
  res.json({ success: true, data: tpl });
});

router.put('/receipt-templates/:id', adminOnly, async (req: Request, res: Response) => {
  const id = parseInt(String(req.params.id), 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const { header_text, footer_text, name } = req.body as {
    header_text?: string;
    footer_text?: string;
    name?: string;
  };

  const existing = await req.asyncDb.get<ReceiptTemplateRow>(
    'SELECT * FROM receipt_templates WHERE id = ?', id
  );
  if (!existing) throw new AppError('Template not found', 404);

  await req.asyncDb.run(
    `UPDATE receipt_templates
       SET header_text = COALESCE(?, header_text),
           footer_text = COALESCE(?, footer_text),
           name        = COALESCE(?, name)
     WHERE id = ?`,
    header_text ?? null,
    footer_text ?? null,
    name ?? null,
    id
  );

  const updated = await req.asyncDb.get<ReceiptTemplateRow>(
    'SELECT * FROM receipt_templates WHERE id = ?', id
  );
  res.json({ success: true, data: updated });
});

// POST /webhook-test — fire a synthetic test delivery to the configured URL
router.post('/webhook-test', adminOnly, async (req: Request, res: Response) => {
  const db = req.db;
  const urlRow = db
    .prepare("SELECT value FROM store_config WHERE key = 'webhook_url'")
    .get() as { value?: string } | undefined;
  if (!urlRow?.value) {
    throw new AppError('No webhook URL configured', 400);
  }
  const { fireWebhook } = await import('../services/webhooks.js');
  fireWebhook(db, 'ticket_created', {
    test: true,
    initiated_by: req.user!.id,
    message: 'This is a test delivery from BizarreCRM webhook settings.',
  });
  audit(db, 'webhook_test', req.user!.id, req.ip || 'unknown', { url: urlRow.value });
  res.json({ success: true, data: { message: 'Test delivery queued — check dead-letter queue if it does not arrive.' } });
});

export default router;
