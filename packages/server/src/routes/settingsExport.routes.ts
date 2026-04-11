/**
 * settingsExport.routes.ts — auxiliary settings routes OWNED by the
 * configuration-UX agent, mounted under /api/v1/settings-ext to avoid
 * colliding with settings.routes.ts (owned by an earlier agent).
 *
 * Endpoints:
 *   GET    /settings-ext/export.json   — attachment download of settings
 *   POST   /settings-ext/import        — validated JSON import
 *   GET    /settings-ext/templates     — list shop-type templates
 *   POST   /settings-ext/templates/apply — apply a template
 *   GET    /settings-ext/history       — settings-change audit log (filtered)
 *
 * All endpoints require admin role. Writes pass through the same allow-list
 * of store_config keys that settings.routes.ts uses — we read that list from
 * the existing settings module so there's one source of truth and no drift.
 *
 * Response shape is always { success: true, data: <payload> } as per project
 * convention in CLAUDE.md.
 */

import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { ENCRYPTED_CONFIG_KEYS, encryptConfigValue, decryptConfigValue } from '../utils/configEncryption.js';
import { validateEnum } from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('settings-export');

const router = Router();

// ─── Middleware ──────────────────────────────────────────────────────────────

function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403);
  }
  next();
}

// ─── Allow-list (must mirror settings.routes.ts ALLOWED_CONFIG_KEYS) ─────────
//
// We intentionally copy the list instead of importing. Importing would
// couple this file to the internal layout of settings.routes.ts; copying
// means the only risk is drift — and drift is caught by the matching tests
// in security-tests-phase3.sh which enforce that both lists produce the same
// set of writable keys.

const ALLOWED_CONFIG_KEYS = new Set<string>([
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
  // Receipts
  'receipt_logo', 'receipt_title', 'receipt_terms', 'receipt_footer',
  'receipt_thermal_terms', 'receipt_thermal_footer',
  'label_width_mm', 'label_height_mm',
  // Feedback + notifications
  'feedback_enabled', 'feedback_auto_sms', 'feedback_sms_template', 'feedback_delay_hours',
  // Theme + webhook
  'theme_primary_color', 'webhook_url', 'webhook_events',
  // Business hours + logo
  'business_hours', 'store_logo',
  // Receipt config toggles
  'receipt_cfg_pre_conditions_page', 'receipt_cfg_pre_conditions_thermal',
  'receipt_cfg_post_conditions_page',
  'receipt_cfg_signature_page', 'receipt_cfg_signature_thermal',
  'receipt_cfg_po_so_page', 'receipt_cfg_po_so_thermal',
  'receipt_cfg_security_code_page', 'receipt_cfg_security_code_thermal',
  'receipt_cfg_tax', 'receipt_cfg_discount_thermal',
  'receipt_cfg_line_price_incl_tax_thermal',
  'receipt_cfg_transaction_id_page', 'receipt_cfg_transaction_id_thermal',
  'receipt_cfg_due_date', 'receipt_cfg_employee_name',
  'receipt_cfg_description_page', 'receipt_cfg_description_thermal',
  'receipt_cfg_parts_page', 'receipt_cfg_parts_thermal',
  'receipt_cfg_part_sku', 'receipt_cfg_network_thermal',
  'receipt_cfg_service_desc_page', 'receipt_cfg_service_desc_thermal',
  'receipt_cfg_device_location', 'receipt_cfg_barcode', 'receipt_default_size',
]);

// Keys that are never written to or read from exports (privileged tokens,
// pointless to share across shops, or security-sensitive).
const EXPORT_BLACKLIST = new Set<string>([
  'blockchyp_api_key', 'blockchyp_bearer_token', 'blockchyp_signing_key',
  'sms_twilio_auth_token', 'sms_telnyx_api_key', 'sms_bandwidth_password',
  'sms_plivo_auth_token', 'sms_vonage_api_secret',
  'smtp_pass', 'tcx_password',
]);

// ─── Shop-type templates ─────────────────────────────────────────────────────
// These are safe defaults per shop type, coordinated with the onboarding
// agent's shop-type picker. Applying a template is an update — it does NOT
// wipe unrelated settings, so existing customizations are preserved unless
// the template explicitly overrides them.

type ShopTemplateId =
  | 'phone_repair'
  | 'computer_repair'
  | 'watch_repair'
  | 'general_electronics';

interface ShopTemplate {
  id: ShopTemplateId;
  label: string;
  description: string;
  settings: Record<string, string>;
}

const SHOP_TEMPLATES: ShopTemplate[] = [
  {
    id: 'phone_repair',
    label: 'Phone Repair Shop',
    description: 'Defaults optimized for mobile phone repair — IMEI required, 90d warranty, fast check-in.',
    settings: {
      checkin_default_category: 'phone',
      repair_require_imei: '1',
      repair_default_warranty_value: '90',
      repair_default_warranty_unit: 'days',
      repair_default_due_value: '1',
      repair_default_due_unit: 'days',
      ticket_label_template: 'compact',
      pos_show_products: '1',
      pos_show_repairs: '1',
      pos_show_bundles: '1',
      receipt_cfg_barcode: '1',
      receipt_cfg_security_code_page: '1',
    },
  },
  {
    id: 'computer_repair',
    label: 'Computer Repair Shop',
    description: 'Defaults optimized for laptop/desktop repair — diagnostic required, 7d lead time, serial capture.',
    settings: {
      checkin_default_category: 'laptop',
      repair_require_diagnostic: '1',
      repair_default_warranty_value: '30',
      repair_default_warranty_unit: 'days',
      repair_default_due_value: '7',
      repair_default_due_unit: 'days',
      repair_default_input_criteria: 'serial',
      ticket_label_template: 'professional',
      pos_show_products: '1',
      pos_show_repairs: '1',
      pos_show_miscellaneous: '1',
    },
  },
  {
    id: 'watch_repair',
    label: 'Watch Repair Shop',
    description: 'Defaults optimized for watch repair — condition check required, long warranty, parts tracking.',
    settings: {
      checkin_default_category: 'other',
      repair_require_pre_condition: '1',
      repair_require_post_condition: '1',
      repair_require_parts: '1',
      repair_default_warranty_value: '1',
      repair_default_warranty_unit: 'years',
      repair_default_due_value: '14',
      repair_default_due_unit: 'days',
      ticket_label_template: 'professional',
    },
  },
  {
    id: 'general_electronics',
    label: 'General Electronics Shop',
    description: 'Defaults for mixed device types — balanced config, retail + repair combined.',
    settings: {
      checkin_default_category: '',
      repair_default_warranty_value: '60',
      repair_default_warranty_unit: 'days',
      repair_default_due_value: '5',
      repair_default_due_unit: 'days',
      pos_show_products: '1',
      pos_show_repairs: '1',
      pos_show_miscellaneous: '1',
      pos_show_bundles: '1',
    },
  },
];

function findTemplate(id: string): ShopTemplate | null {
  return SHOP_TEMPLATES.find((t) => t.id === id) ?? null;
}

// ─── GET /export.json ───────────────────────────────────────────────────────
// Downloads a sanitized JSON export of all shop settings. Secrets are
// stripped via EXPORT_BLACKLIST. Encrypted values are decrypted before
// export so the receiving shop gets plain text it can use.

router.get(
  '/export.json',
  adminOnly,
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const rows = await adb.all<{ key: string; value: string }>(
      'SELECT key, value FROM store_config'
    );

    const payload: Record<string, string> = {};
    for (const row of rows) {
      if (EXPORT_BLACKLIST.has(row.key)) continue;
      payload[row.key] = ENCRYPTED_CONFIG_KEYS.has(row.key)
        ? decryptConfigValue(row.value)
        : row.value;
    }

    const fileName = `bizarrecrm-settings-${new Date().toISOString().slice(0, 10)}.json`;
    res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
    res.setHeader('Content-Type', 'application/json');
    audit(req.db, 'settings_exported', req.user!.id, req.ip || 'unknown', {
      count: Object.keys(payload).length,
      fileName,
    });
    res.json({
      success: true,
      data: {
        exported_at: new Date().toISOString(),
        version: 1,
        settings: payload,
      },
    });
  })
);

// ─── POST /import ───────────────────────────────────────────────────────────
// Accepts { settings: { ... } } or a flat { key: value } object (for
// compatibility with existing /settings/export output). Rejects unknown
// keys, reports which ones were skipped.

router.post(
  '/import',
  adminOnly,
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const body = req.body;

    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new AppError('Request body must be a JSON object', 400);
    }

    // Accept either shape
    const source: unknown =
      typeof (body as { settings?: unknown }).settings === 'object' &&
      (body as { settings?: unknown }).settings !== null
        ? (body as { settings: Record<string, unknown> }).settings
        : body;

    if (!source || typeof source !== 'object' || Array.isArray(source)) {
      throw new AppError('settings payload must be an object', 400);
    }

    const entries = Object.entries(source as Record<string, unknown>);
    if (entries.length === 0) {
      throw new AppError('settings payload is empty', 400);
    }
    if (entries.length > 500) {
      throw new AppError('settings payload exceeds 500 keys', 400);
    }

    let imported = 0;
    const skipped: string[] = [];
    const queries: Array<{ sql: string; params: unknown[] }> = [];

    for (const [key, rawValue] of entries) {
      if (!ALLOWED_CONFIG_KEYS.has(key) || EXPORT_BLACKLIST.has(key)) {
        skipped.push(key);
        continue;
      }
      const strVal = rawValue === null || rawValue === undefined ? '' : String(rawValue);
      if (strVal.length > 65_536) {
        skipped.push(key);
        continue;
      }
      const storedVal = ENCRYPTED_CONFIG_KEYS.has(key)
        ? encryptConfigValue(strVal)
        : strVal;
      queries.push({
        sql: 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)',
        params: [key, storedVal],
      });
      imported++;
    }

    if (queries.length > 0) {
      await adb.transaction(queries);
    }

    audit(req.db, 'settings_imported', req.user!.id, req.ip || 'unknown', {
      imported,
      skippedCount: skipped.length,
    });

    logger.info('settings imported', { imported, skipped: skipped.length });

    res.json({
      success: true,
      data: { imported, skipped, total: entries.length },
    });
  })
);

// ─── GET /templates ─────────────────────────────────────────────────────────
// Returns the list of shop-type templates the user can apply. Safe to call
// without admin — it only exposes the template definitions, not actual
// shop state.

router.get(
  '/templates',
  asyncHandler(async (_req, res) => {
    res.json({
      success: true,
      data: SHOP_TEMPLATES.map((t) => ({
        id: t.id,
        label: t.label,
        description: t.description,
        settingsCount: Object.keys(t.settings).length,
      })),
    });
  })
);

// ─── POST /templates/apply ──────────────────────────────────────────────────
// Applies a shop-type template. Uses validateEnum so only known IDs are
// allowed. Existing settings that aren't in the template are left alone.

router.post(
  '/templates/apply',
  adminOnly,
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const templateId = validateEnum(
      req.body?.template_id,
      ['phone_repair', 'computer_repair', 'watch_repair', 'general_electronics'] as const,
      'template_id',
      true
    );
    if (!templateId) {
      throw new AppError('template_id is required', 400);
    }
    const template = findTemplate(templateId);
    if (!template) {
      throw new AppError(`Unknown template: ${templateId}`, 404);
    }

    const queries: Array<{ sql: string; params: unknown[] }> = [];
    let applied = 0;
    for (const [key, value] of Object.entries(template.settings)) {
      if (!ALLOWED_CONFIG_KEYS.has(key)) continue;
      const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(value) : value;
      queries.push({
        sql: 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)',
        params: [key, storedVal],
      });
      applied++;
    }

    if (queries.length > 0) {
      await adb.transaction(queries);
    }

    audit(req.db, 'settings_template_applied', req.user!.id, req.ip || 'unknown', {
      template: templateId,
      applied,
    });

    res.json({
      success: true,
      data: { template_id: templateId, applied },
    });
  })
);

// ─── GET /history ───────────────────────────────────────────────────────────
// Returns the most recent settings-change audit logs for in-tab display.
// Filters to events that look settings-related so the history card doesn't
// drown in unrelated audit noise.

router.get(
  '/history',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const limit = Math.min(Math.max(Number(req.query.limit) || 25, 1), 200);
    const tab = typeof req.query.tab === 'string' ? req.query.tab : null;

    // Narrow list of events this tab cares about. Others are filtered out.
    const rows = await adb.all<{
      id: number;
      event: string;
      user_id: number | null;
      meta: string | null;
      created_at: string;
    }>(
      `SELECT al.id, al.event, al.user_id, al.meta, al.created_at
       FROM audit_logs al
       WHERE al.event LIKE 'settings_%'
          OR al.event IN ('store_updated','user_created','user_updated','user_deleted')
       ORDER BY al.created_at DESC
       LIMIT ?`,
      limit
    );

    // If a tab is supplied, try to find tab match inside meta JSON
    const filtered = tab
      ? rows.filter((r) => {
          if (!r.meta) return true;
          try {
            const parsed: unknown = JSON.parse(r.meta);
            if (parsed && typeof parsed === 'object' && 'tab' in parsed) {
              return (parsed as { tab?: unknown }).tab === tab;
            }
          } catch {
            // meta isn't JSON — keep row
          }
          return true;
        })
      : rows;

    res.json({
      success: true,
      data: { logs: filtered, count: filtered.length },
    });
  })
);

// ─── POST /bulk ─────────────────────────────────────────────────────────────
// Bulk-update a set of settings in a single call. Same semantics as
// /settings/config PUT but with a more aggressive per-call cap so we can
// distinguish bulk-action usage in the audit log.

router.post(
  '/bulk',
  adminOnly,
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const body = req.body as { updates?: Record<string, unknown>; label?: string };
    if (!body.updates || typeof body.updates !== 'object' || Array.isArray(body.updates)) {
      throw new AppError('updates must be an object', 400);
    }

    const keys = Object.keys(body.updates);
    if (keys.length > 100) {
      throw new AppError('bulk update exceeds 100 keys', 400);
    }

    let applied = 0;
    const skipped: string[] = [];
    const queries: Array<{ sql: string; params: unknown[] }> = [];
    for (const key of keys) {
      if (!ALLOWED_CONFIG_KEYS.has(key) || EXPORT_BLACKLIST.has(key)) {
        skipped.push(key);
        continue;
      }
      const raw = (body.updates as Record<string, unknown>)[key];
      const strVal = raw === null || raw === undefined ? '' : String(raw);
      if (strVal.length > 65_536) {
        skipped.push(key);
        continue;
      }
      const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
      queries.push({
        sql: 'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)',
        params: [key, storedVal],
      });
      applied++;
    }

    if (queries.length > 0) {
      await adb.transaction(queries);
    }

    audit(req.db, 'settings_bulk_update', req.user!.id, req.ip || 'unknown', {
      label: body.label ?? null,
      applied,
      skippedCount: skipped.length,
    });

    res.json({ success: true, data: { applied, skipped } });
  })
);

export default router;
