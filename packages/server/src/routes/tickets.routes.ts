import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { generateOrderId } from '../utils/format.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { requirePermission, JWT_SIGN_OPTIONS } from '../middleware/auth.js';
import { config } from '../config.js';
import { validatePrice, validateQuantity, roundCents, toCents, validateId } from '../utils/validate.js';
import { writeCommission } from '../utils/commissions.js';
import { runAutomations } from '../services/automations.js';
import { applyTicketStatusChange } from '../services/ticketStatus.js';
import { idempotent } from '../middleware/idempotency.js';
import { calculateActiveRepairTime } from '../utils/repair-time.js';
import { roundCurrency } from '../utils/currency.js';
import { audit } from '../utils/audit.js';
import { fireWebhook } from '../services/webhooks.js';
import { checkWindowRate, recordWindowFailure, consumeWindowRate } from '../utils/rateLimiter.js';
import { reserveStorage, decrementStorageBytes } from '../services/usageTracker.js';
import { allocateCounter, formatTicketOrderId, formatInvoiceOrderId } from '../utils/counters.js';
import { createLogger } from '../utils/logger.js';
import { fileUploadValidator, releaseFileCount } from '../middleware/fileUploadValidator.js';
import { computeSlaForTicket } from '../services/slaAssignment.js';
import { enforceUploadQuota } from '../middleware/uploadQuota.js';
import type { AsyncDb, TxQuery } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import { logActivity } from '../utils/activityLog.js';

const logger = createLogger('tickets.routes');

// Preserve last-4 digits for correlation; strips carrier prefix (customer PII).
// "+15551234567" -> "XXX-XXX-4567" | "abc" -> "XXX-XXX-XXXX"
function redactPhone(phone: unknown): string {
  if (typeof phone !== 'string') return 'XXX-XXX-XXXX';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 4) return 'XXX-XXX-XXXX';
  return `XXX-XXX-${digits.slice(-4)}`;
}

const router = Router();

// ---------------------------------------------------------------------------
// Multer setup for photo uploads
// ---------------------------------------------------------------------------
if (!fs.existsSync(config.uploadsPath)) {
  fs.mkdirSync(config.uploadsPath, { recursive: true });
}

const ALLOWED_MIMES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

const upload = multer({
  storage: multer.diskStorage({
    destination: (req, _file, cb) => {
      // In multi-tenant mode, store uploads under uploads/{slug}/
      const tenantSlug = (req as any).tenantSlug;
      const dest = tenantSlug
        ? path.join(config.uploadsPath, tenantSlug)
        : config.uploadsPath;
      if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
      cb(null, dest);
    },
    filename: (_req, file, cb) => {
      // Randomize filename to prevent path traversal and name collisions
      const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
      const safe = ext && ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(ext) ? ext : '.jpg';
      cb(null, `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${safe}`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_MIMES.includes(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPEG, PNG, WebP, GIF images allowed'));
  },
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
type AnyRow = Record<string, any>;
const maxLen = (val: string | undefined, max: number) => val && val.length > max ? val.slice(0, max) : val;

function parseAssignedToFilter(value: unknown, currentUserId?: number): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (trimmed.toLowerCase() === 'me') return currentUserId ?? null;
  return /^\d+$/.test(trimmed) ? parseInt(trimmed, 10) : null;
}

function parseStatusGroup(value: unknown): 'open' | 'closed' | 'cancelled' | 'on_hold' | 'active' | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (typeof raw !== 'string') return null;
  const normalized = raw.trim().toLowerCase().replace('-', '_');
  if (normalized === 'onhold') return 'on_hold';
  if (['open', 'closed', 'cancelled', 'on_hold', 'active'].includes(normalized)) {
    return normalized as 'open' | 'closed' | 'cancelled' | 'on_hold' | 'active';
  }
  return null;
}

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function parseJsonCol(val: any, fallback: any = []): any {
  if (!val) return fallback;
  try { return JSON.parse(val); } catch { return fallback; }
}

/**
 * SEC-H16: Reject nested-resource mutations (notes, photos, devices, parts,
 * checklist) when the parent ticket is closed OR has an attached invoice.
 * Admins bypass via the store_config toggles that already exist for the
 * top-level PUT /:id handler (ticket_allow_edit_closed / ticket_allow_edit_after_invoice).
 *
 * Keeps behaviour consistent with the existing F1/F2 guard in PUT /:id so that
 * staff cannot side-step it by touching the nested path instead of the parent.
 */
async function assertTicketMutable(adb: AsyncDb, ticketId: number, userRole: string | undefined): Promise<void> {
  const row = await adb.get<AnyRow>(`
    SELECT t.id, t.invoice_id, ts.is_closed
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
     WHERE t.id = ? AND t.is_deleted = 0
  `, ticketId);
  if (!row) throw new AppError('Ticket not found', 404);

  // Admin bypass — matches the hard admin bypass in requirePermission().
  if (userRole === 'admin') return;

  if (row.is_closed) {
    const toggle = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_allow_edit_closed'");
    if (toggle?.value === '0' || toggle?.value === 'false') {
      throw new AppError('Cannot modify a closed ticket', 403);
    }
  }
  if (row.invoice_id) {
    const toggle = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_allow_edit_after_invoice'");
    if (toggle?.value === '0' || toggle?.value === 'false') {
      throw new AppError('Cannot modify a ticket with an invoice', 403);
    }
  }
}

/**
 * M10 fix: compute tax for a given line and surface a warning when the referenced
 * tax_class_id points to a deleted / missing row. Previously this silently defaulted
 * to 0 and under-remitted tax with no indication to the caller or support.
 *
 * Returns the computed tax amount plus an optional warning string. The tax amount
 * itself stays zero when the class is missing (we cannot guess a rate) but the
 * warning lets the handler attach it to the response and log an error server-side.
 */
interface TaxResult {
  amount: number;
  warning: string | null;
}

async function calcTaxWithWarningAsync(
  adb: AsyncDb,
  price: number,
  taxClassId: number | null,
  taxInclusive: boolean,
): Promise<TaxResult> {
  if (!taxClassId) return { amount: 0, warning: null };
  const tc = await adb.get<AnyRow>('SELECT rate FROM tax_classes WHERE id = ?', taxClassId);
  if (!tc) {
    const warning = `tax class ${taxClassId} deleted, defaulted to 0`;
    logger.warn('tax class lookup missed — defaulting tax to 0', {
      tax_class_id: taxClassId,
      price,
      tax_inclusive: taxInclusive,
    });
    return { amount: 0, warning };
  }
  const rate = tc.rate / 100;
  const amount = taxInclusive
    ? roundCurrency(price - price / (1 + rate))
    : roundCurrency(price * rate);
  return { amount, warning: null };
}

/**
 * Thin async facade kept for callers that only need the numeric tax value.
 * New code that wants to expose the warning should call calcTaxWithWarningAsync directly.
 */
async function calcTaxAsync(
  adb: AsyncDb,
  price: number,
  taxClassId: number | null,
  taxInclusive: boolean,
): Promise<number> {
  const result = await calcTaxWithWarningAsync(adb, price, taxClassId, taxInclusive);
  return result.amount;
}

async function getDefaultTaxClassIdAsync(adb: AsyncDb, itemType?: string): Promise<number | null> {
  const key = itemType === 'part' ? 'tax_default_parts'
    : itemType === 'accessory' || itemType === 'product' ? 'tax_default_accessories'
    : 'tax_default_services';
  const row = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = ?", key);
  if (!row?.value) return null;
  const id = parseInt(row.value);
  return isNaN(id) || id <= 0 ? null : id;
}

async function insertHistoryAsync(adb: AsyncDb, ticketId: number, userId: number | null, action: string, description: string, oldValue?: string | null, newValue?: string | null): Promise<void> {
  await adb.run(
    `INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
     VALUES (?, ?, ?, ?, ?, ?)`,
    ticketId, userId, action, description, oldValue ?? null, newValue ?? null
  );
}

/**
 * P2 / T10 fix: when the async notification hook throws catastrophically (dynamic
 * import failure, DB lookup error, unexpected exception inside sendTicketStatusNotification),
 * queue the notification so the retry cron will pick it up on the next sweep.
 *
 * The retry queue is keyed by recipient phone + message; here we look up the
 * customer phone and fall back to a generic status-change message when no template
 * can be rendered synchronously. If the notification_retry_queue table does not
 * exist (very old tenant DB) we still log the error and move on — we never let a
 * hook failure crash the route.
 */
function enqueueTicketNotificationRetry(
  db: any,
  ticketId: number,
  statusName: string,
  tenantSlug: string | null,
  originalError: unknown,
): void {
  try {
    const tableExists = db
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'notification_retry_queue'")
      .get() as { name: string } | undefined;
    if (!tableExists) return;

    const ticket = db.prepare(`
      SELECT t.order_id, c.mobile AS customer_phone, c.phone AS customer_phone2, c.first_name AS customer_name
      FROM tickets t
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.id = ?
    `).get(ticketId) as AnyRow | undefined;

    const phone = ticket?.customer_phone || ticket?.customer_phone2;
    if (!phone) return;

    const message = `Your ticket ${ticket?.order_id || `T-${ticketId}`} status has changed to ${statusName}.`;
    const errorMsg = originalError instanceof Error ? originalError.message : String(originalError);

    db.prepare(`
      INSERT INTO notification_retry_queue (recipient_phone, message, entity_type, entity_id, tenant_slug, retry_count, max_retries, next_retry_at, last_error)
      VALUES (?, ?, 'ticket', ?, ?, 0, 3, datetime('now', '+5 minutes'), ?)
    `).run(phone, message, ticketId, tenantSlug, `route-hook failure: ${errorMsg}`);
  } catch (enqueueErr: unknown) {
    logger.error('failed to enqueue ticket notification retry', {
      ticket_id: ticketId,
      error: enqueueErr instanceof Error ? enqueueErr.message : String(enqueueErr),
    });
  }
}

async function getFullTicketAsync(adb: AsyncDb, ticketId: number): Promise<AnyRow | null> {
  // Round 1: fetch ticket + devices in parallel
  const [ticket, devices] = await Promise.all([
    adb.get<AnyRow>(`
      SELECT t.*,
             c.first_name AS c_first_name, c.last_name AS c_last_name,
             c.phone AS c_phone, c.mobile AS c_mobile, c.email AS c_email, c.organization AS c_organization,
             ts.name AS status_name, ts.color AS status_color, ts.sort_order AS status_sort_order,
             ts.is_default AS status_is_default, ts.is_closed AS status_is_closed,
             ts.is_cancelled AS status_is_cancelled, ts.notify_customer AS status_notify_customer,
             ts.notification_template AS status_notification_template,
             u.first_name AS assigned_first, u.last_name AS assigned_last,
             cb.first_name AS created_first, cb.last_name AS created_last
      FROM tickets t
      LEFT JOIN customers c ON c.id = t.customer_id
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      LEFT JOIN users u ON u.id = t.assigned_to
      LEFT JOIN users cb ON cb.id = t.created_by
      WHERE t.id = ? AND t.is_deleted = 0
    `, ticketId),
    adb.all<AnyRow>(`
      SELECT td.*,
             ts2.name AS status_name, ts2.color AS status_color,
             u2.first_name AS assigned_first, u2.last_name AS assigned_last,
             COALESCE(td.service_name, ii.name) AS service_name
      FROM ticket_devices td
      LEFT JOIN ticket_statuses ts2 ON ts2.id = td.status_id
      LEFT JOIN users u2 ON u2.id = td.assigned_to
      LEFT JOIN inventory_items ii ON ii.id = td.service_id
      WHERE td.ticket_id = ?
      ORDER BY td.id ASC
    `, ticketId),
  ]);

  if (!ticket) return null;

  const result: AnyRow = {
    id: ticket.id,
    order_id: ticket.order_id,
    customer_id: ticket.customer_id,
    status_id: ticket.status_id,
    assigned_to: ticket.assigned_to,
    subtotal: ticket.subtotal,
    discount: ticket.discount,
    discount_reason: ticket.discount_reason,
    total_tax: ticket.total_tax,
    total: ticket.total,
    source: ticket.source,
    referral_source: ticket.referral_source,
    signature: ticket.signature,
    labels: parseJsonCol(ticket.labels, []),
    due_on: ticket.due_on,
    invoice_id: ticket.invoice_id,
    estimate_id: ticket.estimate_id,
    is_deleted: ticket.is_deleted,
    created_by: ticket.created_by,
    created_at: ticket.created_at,
    updated_at: ticket.updated_at,
    customer: {
      id: ticket.customer_id,
      first_name: ticket.c_first_name,
      last_name: ticket.c_last_name,
      phone: ticket.c_phone,
      mobile: ticket.c_mobile,
      email: ticket.c_email,
      organization: ticket.c_organization,
    },
    status: {
      id: ticket.status_id,
      name: ticket.status_name,
      color: ticket.status_color,
      sort_order: ticket.status_sort_order,
      is_default: ticket.status_is_default,
      is_closed: ticket.status_is_closed,
      is_cancelled: ticket.status_is_cancelled,
      notify_customer: ticket.status_notify_customer,
      notification_template: ticket.status_notification_template,
    },
    assigned_user: ticket.assigned_to ? { id: ticket.assigned_to, first_name: ticket.assigned_first, last_name: ticket.assigned_last } : null,
    created_by_user: { id: ticket.created_by, first_name: ticket.created_first, last_name: ticket.created_last },
  };

  // Round 2: per-device details + notes/history/payments in parallel
  const notesFetch = adb.all<AnyRow>(`
    SELECT tn.*, u3.first_name, u3.last_name, u3.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u3 ON u3.id = tn.user_id
    WHERE tn.ticket_id = ?
    ORDER BY tn.created_at DESC
  `, ticketId);
  const historyFetch = adb.all<AnyRow>(`
    SELECT th.*, u4.first_name, u4.last_name
    FROM ticket_history th
    LEFT JOIN users u4 ON u4.id = th.user_id
    WHERE th.ticket_id = ?
    ORDER BY th.created_at DESC
  `, ticketId);
  const paymentsFetch = ticket.invoice_id
    ? adb.all<AnyRow>(`
        SELECT p.id, p.amount, p.method, p.method_detail, p.transaction_id, p.notes, p.created_at
        FROM payments p WHERE p.invoice_id = ?
        ORDER BY p.created_at ASC
      `, ticket.invoice_id)
    : Promise.resolve([]);

  const deviceDetailFetches = devices.map(async (d) => {
    const [parts, photos, checklist] = await Promise.all([
      adb.all<AnyRow>(`
        SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
        FROM ticket_device_parts tdp
        LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
        WHERE tdp.ticket_device_id = ?
      `, d.id),
      adb.all<AnyRow>('SELECT * FROM ticket_photos WHERE ticket_device_id = ? ORDER BY created_at ASC', d.id),
      adb.get<AnyRow>('SELECT * FROM ticket_checklists WHERE ticket_device_id = ?', d.id),
    ]);
    return {
      id: d.id, ticket_id: d.ticket_id, device_name: d.device_name, device_type: d.device_type,
      imei: d.imei, serial: d.serial, security_code: d.security_code, color: d.color, network: d.network,
      status_id: d.status_id, assigned_to: d.assigned_to, service_id: d.service_id, price: d.price,
      line_discount: d.line_discount, tax_amount: d.tax_amount, tax_class_id: d.tax_class_id,
      tax_inclusive: d.tax_inclusive, total: d.total, warranty: d.warranty, warranty_days: d.warranty_days,
      due_on: d.due_on, collected_date: d.collected_date, device_location: d.device_location,
      additional_notes: d.additional_notes, pre_conditions: parseJsonCol(d.pre_conditions, []),
      post_conditions: parseJsonCol(d.post_conditions, []), loaner_device_id: d.loaner_device_id,
      created_at: d.created_at, updated_at: d.updated_at,
      status: d.status_id ? { id: d.status_id, name: d.status_name, color: d.status_color } : null,
      assigned_user: d.assigned_to ? { id: d.assigned_to, first_name: d.assigned_first, last_name: d.assigned_last } : null,
      service: d.service_id ? { id: d.service_id, name: d.service_name } : null,
      parts, photos,
      checklist: checklist ? { ...checklist, items: parseJsonCol(checklist.items, []) } : null,
    };
  });

  const [devicesWithDetails, notes, history, payments] = await Promise.all([
    Promise.all(deviceDetailFetches),
    notesFetch,
    historyFetch,
    paymentsFetch,
  ]);

  result.devices = devicesWithDetails;
  result.notes = notes.map((n) => ({
    ...n, is_flagged: !!n.is_flagged,
    user: { id: n.user_id, first_name: n.first_name, last_name: n.last_name, avatar_url: n.avatar_url },
  }));
  result.history = history.map((h) => ({
    ...h, user: h.user_id ? { id: h.user_id, first_name: h.first_name, last_name: h.last_name } : null,
  }));
  result.payments = payments;

  return result;
}

async function recalcTicketTotalsAsync(adb: AsyncDb, ticketId: number): Promise<void> {
  const [devices, parts, ticketRow] = await Promise.all([
    adb.all<AnyRow>('SELECT price, line_discount, tax_amount, total FROM ticket_devices WHERE ticket_id = ?', ticketId),
    adb.all<AnyRow>(`
      SELECT tdp.quantity, tdp.price
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      WHERE td.ticket_id = ?
    `, ticketId),
    adb.get<AnyRow>('SELECT discount FROM tickets WHERE id = ?', ticketId),
  ]);

  let subtotal = 0;
  let totalTax = 0;
  for (const d of devices) {
    subtotal += (d.price - d.line_discount);
    totalTax += d.tax_amount;
  }
  for (const p of parts) {
    subtotal += p.quantity * p.price;
  }

  const discount = ticketRow?.discount ?? 0;
  const total = roundCurrency(subtotal - discount + totalTax);

  await adb.run(
    'UPDATE tickets SET subtotal = ?, total_tax = ?, total = ?, updated_at = ? WHERE id = ?',
    roundCurrency(subtotal), roundCurrency(totalTax), total, now(), ticketId
  );
}

// ---------------------------------------------------------------------------
// (asyncHandler imported from ../middleware/asyncHandler.js)

// ===================================================================
// GET /my-queue - Lightweight ticket counts for current user
// ===================================================================
router.get('/my-queue', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = (req as any).user?.id;
  if (!userId) {
    res.json({ success: true, data: { total: 0, open: 0, waiting_parts: 0, in_progress: 0 } });
    return;
  }

  const row = await adb.get<any>(`
    SELECT
      COUNT(*) AS total,
      SUM(CASE WHEN ts.name = 'Open' THEN 1 ELSE 0 END) AS open,
      SUM(CASE WHEN ts.name IN ('Waiting for Parts', 'Special Part Order (Pending Parts)') THEN 1 ELSE 0 END) AS waiting_parts,
      SUM(CASE WHEN ts.name = 'In Progress' THEN 1 ELSE 0 END) AS in_progress
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      AND t.assigned_to = ?
  `, userId);

  res.json({
    success: true,
    data: {
      total: row?.total ?? 0,
      open: row?.open ?? 0,
      waiting_parts: row?.waiting_parts ?? 0,
      in_progress: row?.in_progress ?? 0,
    },
  });
}));

// ===================================================================
// GET / - List tickets (paginated, filterable, sortable)
// ===================================================================
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 20);
  const keyword = (req.query.keyword as string || '').trim();
  const statusParam = (req.query.status_id as string || '').trim();
  const statusId = /^\d+$/.test(statusParam) ? parseInt(statusParam) : null;
  const statusGroup = parseStatusGroup(req.query.status_group) || parseStatusGroup(statusParam);
  const assignedTo = parseAssignedToFilter(req.query.assigned_to, req.user?.id);
  const fromDate = req.query.from_date as string || null;
  const toDate = req.query.to_date as string || null;
  const dateFilter = req.query.date_filter as string || 'all';
  // SCAN-462 / migration 136: optional location filter (backwards-compat — omitting it returns all)
  const locationIdParam = req.query.location_id as string || '';
  const locationIdFilter = /^\d+$/.test(locationIdParam) ? parseInt(locationIdParam, 10) : null;
  const sortBy = (req.query.sort_by as string) || 'created_at';
  const sortOrder = (req.query.sort_order as string || 'DESC').toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

  const allowedSorts = ['created_at', 'updated_at', 'order_id', 'total', 'due_on', 'status_id', 'urgency'];
  let safeSortBy: string;
  if (sortBy === 'urgency') {
    safeSortBy = `CASE WHEN ts.is_closed = 1 OR ts.is_cancelled = 1 THEN 1 ELSE 0 END ASC,
      CASE WHEN t.due_on IS NOT NULL AND t.due_on < datetime('now') THEN 0 ELSE 1 END ASC,
      t.created_at`;
  } else {
    safeSortBy = allowedSorts.includes(sortBy) ? `t.${sortBy}` : 't.created_at';
  }

  const conditions: string[] = ['t.is_deleted = 0'];
  const params: any[] = [];

  if (statusId) {
    conditions.push('t.status_id = ?');
    params.push(statusId);
  } else if (statusGroup) {
    // Filter by status group using is_closed / is_cancelled flags
    if (statusGroup === 'active') {
      // All non-closed, non-cancelled — for POS and dashboards
      conditions.push('t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0)');
    } else if (statusGroup === 'open') {
      // Open = non-closed, non-cancelled, AND not on-hold/waiting
      conditions.push("t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 AND LOWER(name) NOT LIKE '%hold%' AND LOWER(name) NOT LIKE '%waiting%' AND LOWER(name) NOT LIKE '%pending%' AND LOWER(name) NOT LIKE '%transit%')");
    } else if (statusGroup === 'closed') {
      conditions.push('t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 1)');
    } else if (statusGroup === 'cancelled') {
      conditions.push('t.status_id IN (SELECT id FROM ticket_statuses WHERE is_cancelled = 1)');
    } else if (statusGroup === 'on_hold') {
      conditions.push("t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 AND (LOWER(name) LIKE '%hold%' OR LOWER(name) LIKE '%waiting%' OR LOWER(name) LIKE '%pending%' OR LOWER(name) LIKE '%transit%'))");
    }
  }
  if (assignedTo) {
    conditions.push('t.assigned_to = ?');
    params.push(assignedTo);
  }

  // CROSS1 / SW-D4: When ticket_all_employees_view_all is '0', non-admin/non-manager
  // users (i.e. techs) only see their own tickets. Admins + managers always see all.
  // Matches search.routes.ts visibility pattern.
  const role = req.user?.role;
  const isAdminOrManager = role === 'admin' || role === 'manager';
  if (!assignedTo && !isAdminOrManager) {
    const allViewCfg = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_all_employees_view_all'");
    if (allViewCfg?.value === '0') {
      conditions.push('t.assigned_to = ?');
      params.push(req.user!.id);
    }
  }

  // Date filtering
  if (dateFilter !== 'all') {
    let daysBack = 0;
    switch (dateFilter) {
      case 'today': daysBack = 0; break;
      case 'yesterday': daysBack = 1; break;
      case '7days': daysBack = 7; break;
      case '14days': daysBack = 14; break;
      case '30days': daysBack = 30; break;
    }
    if (dateFilter === 'today') {
      conditions.push("date(t.created_at) = date('now')");
    } else if (dateFilter === 'yesterday') {
      conditions.push("date(t.created_at) = date('now', '-1 day')");
    } else {
      conditions.push(`t.created_at >= datetime('now', '-${daysBack} days')`);
    }
  }

  if (fromDate) {
    conditions.push('t.created_at >= ?');
    params.push(fromDate);
  }
  if (toDate) {
    conditions.push('t.created_at <= ?');
    params.push(toDate + ' 23:59:59');
  }

  // SCAN-462 / migration 136: location filter — no forced scoping, purely additive
  if (locationIdFilter !== null) {
    conditions.push('t.location_id = ?');
    params.push(locationIdFilter);
  }

  // Keyword search: order_id, customer name, device names, notes content, history description
  let keywordJoin = '';
  if (keyword) {
    keywordJoin = 'LEFT JOIN ticket_devices td_kw ON td_kw.ticket_id = t.id';
    // ESCAPE '\' + escapeLike() prevents users from supplying raw %/_
    // wildcards that would widen the match (enumeration / DoS).
    conditions.push(`(
      t.order_id LIKE ? ESCAPE '\\' OR
      c.first_name LIKE ? ESCAPE '\\' OR c.last_name LIKE ? ESCAPE '\\' OR
      (c.first_name || ' ' || c.last_name) LIKE ? ESCAPE '\\' OR
      td_kw.device_name LIKE ? ESCAPE '\\' OR
      t.id IN (SELECT ticket_id FROM ticket_notes WHERE content LIKE ? ESCAPE '\\') OR
      t.id IN (SELECT ticket_id FROM ticket_history WHERE description LIKE ? ESCAPE '\\')
    )`);
    const like = `%${escapeLike(keyword)}%`;
    params.push(like, like, like, like, like, like, like);
  }

  const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';

  // Count query (use DISTINCT because keyword join can multiply rows)
  const countSql = `
    SELECT COUNT(DISTINCT t.id) AS total
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    ${keywordJoin}
    ${whereClause}
  `;
  // Run count + status counts in parallel with main data query
  const offset = (page - 1) * pageSize;
  const dataSql = `
    SELECT DISTINCT t.id, t.order_id, t.customer_id, t.status_id, t.assigned_to,
           t.subtotal, t.discount, t.total_tax, t.total,
           t.source, t.labels, t.due_on, t.invoice_id, t.estimate_id,
           t.created_by, t.created_at, t.updated_at, t.is_pinned,
           c.first_name AS c_first_name, c.last_name AS c_last_name,
           c.phone AS c_phone, c.mobile AS c_mobile, c.email AS c_email, c.organization AS c_organization,
           ts.name AS status_name, ts.color AS status_color,
           ts.is_closed AS status_is_closed, ts.is_cancelled AS status_is_cancelled,
           ts.sort_order AS status_sort_order,
           u.first_name AS assigned_first, u.last_name AS assigned_last,
           ln_int.content AS latest_internal_note,
           ln_diag.content AS latest_diagnostic_note
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    LEFT JOIN (
      SELECT ticket_id, content, ROW_NUMBER() OVER (PARTITION BY ticket_id ORDER BY created_at DESC) AS rn
      FROM ticket_notes WHERE type = 'internal'
    ) ln_int ON ln_int.ticket_id = t.id AND ln_int.rn = 1
    LEFT JOIN (
      SELECT ticket_id, content, ROW_NUMBER() OVER (PARTITION BY ticket_id ORDER BY created_at DESC) AS rn
      FROM ticket_notes WHERE type = 'diagnostic'
    ) ln_diag ON ln_diag.ticket_id = t.id AND ln_diag.rn = 1
    ${keywordJoin}
    ${whereClause}
    ORDER BY t.is_pinned DESC, ${safeSortBy} ${sortOrder}
    LIMIT ? OFFSET ?
  `;
  const dataParams = [...params, pageSize, offset];

  // Parallel round 1: count + data + status counts all at once
  const [countRow, rows, statusCounts] = await Promise.all([
    adb.get<AnyRow>(countSql, ...params),
    adb.all<AnyRow>(dataSql, ...dataParams),
    adb.all<AnyRow>(`
      SELECT ts.id, ts.name, ts.color, ts.sort_order, COUNT(t.id) AS count
      FROM ticket_statuses ts
      LEFT JOIN tickets t ON t.status_id = ts.id AND t.is_deleted = 0
      GROUP BY ts.id
      ORDER BY ts.sort_order ASC
    `),
  ]);
  const totalCount = countRow?.total ?? 0;

  // Batch-fetch device info for all ticket IDs (eliminates N+1)
  const ticketIds = rows.map(r => r.id);
  const deviceMap = new Map<number, AnyRow>();
  const countMap = new Map<number, number>();
  const partsCountMap = new Map<number, number>();
  const partsListMap = new Map<number, string[]>();
  const latestSmsMap = new Map<number, { message: string; direction: string; date_time: string }>();

  if (ticketIds.length > 0) {
    const placeholders = ticketIds.map(() => '?').join(',');

    // Parallel round 2: devices + parts config + parts data all at once
    const [devices, showPartsCfg] = await Promise.all([
      adb.all<AnyRow>(`
        SELECT td.ticket_id, td.device_name, td.additional_notes, td.device_type,
               td.imei, td.serial, td.security_code, td.service_id,
               COALESCE(td.service_name, ii.name) AS service_name,
               ROW_NUMBER() OVER (PARTITION BY td.ticket_id ORDER BY td.id ASC) AS rn
        FROM ticket_devices td
        LEFT JOIN inventory_items ii ON ii.id = td.service_id
        WHERE td.ticket_id IN (${placeholders})
      `, ...ticketIds),
      adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_show_parts_column'"),
    ]);
    for (const d of devices) {
      if (d.rn === 1) deviceMap.set(d.ticket_id, d);
      countMap.set(d.ticket_id, (countMap.get(d.ticket_id) || 0) + 1);
    }

    const showParts = !showPartsCfg || showPartsCfg.value !== '0';

    // Parts counts + names per ticket
    if (showParts) {
      const parts = await adb.all<AnyRow>(`
        SELECT td.ticket_id, tdp.inventory_item_id, ii.name AS item_name
        FROM ticket_device_parts tdp
        JOIN ticket_devices td ON td.id = tdp.ticket_device_id
        LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
        WHERE td.ticket_id IN (${placeholders})
      `, ...ticketIds);
      for (const p of parts) {
        partsCountMap.set(p.ticket_id, (partsCountMap.get(p.ticket_id) || 0) + 1);
        const list = partsListMap.get(p.ticket_id) || [];
        list.push(p.item_name || 'Unknown part');
        partsListMap.set(p.ticket_id, list);
      }
    }

    // Latest SMS per customer (best-effort — don't crash ticket list if SMS query fails)
    try {
      const custPhones = new Map<number, string>();
      for (const r of rows) {
        if (r.customer_id && (r.c_phone || r.c_mobile)) {
          custPhones.set(r.customer_id, r.c_phone || r.c_mobile);
        }
      }
      const phoneList = [...new Set(custPhones.values())];
      if (phoneList.length > 0) {
        const phonePlaceholders = phoneList.map(() => '?').join(',');
        const smsRows = await adb.all<AnyRow>(`
          SELECT s.id, s.message, s.direction, s.created_at, s.from_number, s.to_number
          FROM sms_messages s
          INNER JOIN (
            SELECT MAX(id) as max_id FROM sms_messages
            WHERE (from_number IN (${phonePlaceholders}) OR to_number IN (${phonePlaceholders}))
            GROUP BY CASE WHEN direction = 'inbound' THEN from_number ELSE to_number END
          ) latest ON s.id = latest.max_id
        `, ...phoneList, ...phoneList);

        const phoneSmsMap = new Map<string, AnyRow>();
        for (const sms of smsRows) {
          const phone = sms.direction === 'inbound' ? sms.from_number : sms.to_number;
          if (!phoneSmsMap.has(phone)) phoneSmsMap.set(phone, sms);
        }
        for (const r of rows) {
          const phone = custPhones.get(r.customer_id);
          if (phone && phoneSmsMap.has(phone)) {
            const sms = phoneSmsMap.get(phone)!;
            latestSmsMap.set(r.id, { message: sms.message, direction: sms.direction, date_time: sms.created_at });
          }
        }
      }
    } catch (e) {
      // SMS lookup is non-critical — silently skip if table/schema issue
      logger.error('tickets_sms_lookup_failed', { error: e instanceof Error ? e.message : String(e) });
    }
  }

  const tickets = rows.map((r) => {
    const firstDevice = deviceMap.get(r.id);
    const deviceCount = countMap.get(r.id) || 0;
    return {
      id: r.id,
      order_id: r.order_id,
      customer_id: r.customer_id,
      status_id: r.status_id,
      assigned_to: r.assigned_to,
      subtotal: r.subtotal,
      discount: r.discount,
      total_tax: r.total_tax,
      total: r.total,
      source: r.source,
      labels: parseJsonCol(r.labels, []),
      due_on: r.due_on,
      invoice_id: r.invoice_id,
      estimate_id: r.estimate_id,
      created_by: r.created_by,
      created_at: r.created_at,
      updated_at: r.updated_at,
      customer: {
        id: r.customer_id,
        first_name: r.c_first_name,
        last_name: r.c_last_name,
        phone: r.c_phone || r.c_mobile,
        mobile: r.c_mobile,
        email: r.c_email,
        organization: r.c_organization,
      },
      status: {
        id: r.status_id,
        name: r.status_name,
        color: r.status_color,
        is_closed: r.status_is_closed,
        is_cancelled: r.status_is_cancelled,
        sort_order: r.status_sort_order,
      },
      assigned_user: r.assigned_to ? { id: r.assigned_to, first_name: r.assigned_first, last_name: r.assigned_last } : null,
      first_device: firstDevice ? {
        device_name: firstDevice.device_name,
        additional_notes: firstDevice.additional_notes,
        device_type: firstDevice.device_type,
        imei: firstDevice.imei || null,
        serial: firstDevice.serial || null,
        service_name: firstDevice.service_name || null,
      } : null,
      device_count: deviceCount,
      parts_count: partsCountMap.get(r.id) || 0,
      parts_names: partsListMap.get(r.id) || [],
      is_pinned: !!r.is_pinned,
      latest_internal_note: r.latest_internal_note || null,
      latest_diagnostic_note: r.latest_diagnostic_note || null,
      latest_sms: latestSmsMap.get(r.id) || null,
      // ENR-T6: SLA tracking — computed from due_on
      sla_status: (() => {
        if (!r.due_on) return null;
        const dueMs = new Date(r.due_on.endsWith('Z') || r.due_on.includes('+') ? r.due_on : r.due_on + 'Z').getTime();
        const nowMs = Date.now();
        if (dueMs < nowMs) return 'overdue';
        if (dueMs - nowMs <= 24 * 60 * 60 * 1000) return 'at_risk';
        return 'on_track';
      })(),
      // ENR-T9: Priority / urgency — computed from due date and status
      urgency: (() => {
        const isClosed = !!r.status_is_closed || !!r.status_is_cancelled;
        if (isClosed) return 'low';
        if (!r.due_on) return 'normal';
        const dueMs = new Date(r.due_on.endsWith('Z') || r.due_on.includes('+') ? r.due_on : r.due_on + 'Z').getTime();
        const nowMs = Date.now();
        if (dueMs < nowMs) return 'critical';
        if (dueMs - nowMs <= 24 * 60 * 60 * 1000) return 'high';
        if (dueMs - nowMs <= 3 * 24 * 60 * 60 * 1000) return 'medium';
        return 'normal';
      })(),
    };
  });

  // statusCounts already fetched in parallel round 1 above

  res.json({
    success: true,
    data: {
      tickets,
      status_counts: statusCounts,
      pagination: {
        page,
        per_page: pageSize,
        total: totalCount,
        total_pages: Math.ceil(totalCount / pageSize),
      },
    },
  });
}));

// ===================================================================
// POST / - Create ticket
// ===================================================================
// SEC-H25: gate ticket creation behind tickets.create permission.
router.post('/', idempotent, requirePermission('tickets.create'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for notifications, automations, webhooks
  const userId = req.user!.id;
  const body = req.body;

  // F18: Require customer if setting enabled (default: required).
  // CROSS12-fix: walk-in tickets (is_walk_in=true) are exempt -- the server
  // resolves or creates a customer row below, so no customer_id is needed
  // from the client.
  const requireCustomer = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_require_customer'");
  const customerRequired = !requireCustomer || requireCustomer.value !== '0';
  const isWalkIn = body.is_walk_in === true;
  if (!body.customer_id && customerRequired && !isWalkIn) {
    throw new AppError('customer_id is required', 400);
  }
  if (!body.devices || !Array.isArray(body.devices) || body.devices.length === 0) {
    throw new AppError('At least one device is required');
  }

  // SEC-M10: Enforce max lengths on text inputs
  body.notes = maxLen(body.notes, 5000);
  body.internal_notes = maxLen(body.internal_notes, 5000);
  body.customer_notes = maxLen(body.customer_notes, 2000);
  for (const dev of body.devices) {
    dev.device_name = maxLen(dev.device_name, 200);
    dev.imei = maxLen(dev.imei, 50);
    dev.serial = maxLen(dev.serial, 100);
    dev.additional_notes = maxLen(dev.additional_notes, 2000);
  }

  // CROSS12-fix: resolve the effective customer_id.
  //   - Normal ticket:  use body.customer_id as-is (verified below).
  //   - Walk-in with identity (name/phone provided): create a unique customer
  //     row so this ticket has an editable, per-ticket customer record.
  //   - Truly anonymous walk-in (no identity fields): fall back to the shared
  //     WALK-IN sentinel -- that row must NOT be renamed (CROSS12 guard on
  //     CustomerDetailScreen keeps the Edit button hidden for it).
  let resolvedCustomerId: number | null = body.customer_id ?? null;

  if (isWalkIn) {
    const walkInFirst = ((body.walk_in_first_name as string | undefined) ?? '').trim();
    const walkInLast  = ((body.walk_in_last_name  as string | undefined) ?? '').trim();
    const walkInPhone = ((body.walk_in_phone       as string | undefined) ?? '').trim();
    const walkInEmail = ((body.walk_in_email       as string | undefined) ?? '').trim();

    if (walkInFirst || walkInLast || walkInPhone) {
      // Create a unique, fully-editable customer row for this walk-in.
      const insertResult = await adb.run(
        `INSERT INTO customers
           (first_name, last_name, mobile, email, type, source, is_deleted, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'individual', 'Walk-in', 0, datetime('now'), datetime('now'))`,
        walkInFirst || 'Walk-in',
        walkInLast  || '',
        walkInPhone || null,
        walkInEmail || null,
      );
      resolvedCustomerId = Number(insertResult.lastInsertRowid);
    } else {
      // Truly anonymous walk-in -- use the shared sentinel.
      const sentinel = await adb.get<{ id: number }>(
        "SELECT id FROM customers WHERE code = 'WALK-IN' LIMIT 1",
      );
      resolvedCustomerId = sentinel?.id ?? null;
    }
  } else if (body.customer_id) {
    // Verify non-walk-in customer exists.
    const customer = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', body.customer_id);
    if (!customer) throw new AppError('Customer not found', 404);
  }

  // F9: Require pre-conditions if setting enabled
  const requirePreCond = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_require_pre_condition'");
  if (requirePreCond?.value === '1' || requirePreCond?.value === 'true') {
    for (const dev of body.devices) {
      if (!dev.pre_conditions || dev.pre_conditions.length === 0) {
        throw new AppError(`Pre-conditions required for device: ${dev.device_name || 'Unknown'}`, 400);
      }
    }
  }

  // F14: Require IMEI if setting enabled
  const requireImei = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_require_imei'");
  if (requireImei?.value === '1' || requireImei?.value === 'true') {
    for (const dev of body.devices) {
      if (!dev.imei && !dev.serial) {
        throw new AppError(`IMEI or serial number required for device: ${dev.device_name || 'Unknown'}`, 400);
      }
    }
  }

  // Tier: check monthly ticket limit (atomic — check + pre-increment in same transaction)
  // Free plans have a maxTicketsMonth cap; Pro plans set it to null (unlimited).
  let tierReservationCommitted = false;
  const tierReservationTenantId = req.tenantId;
  if (config.multiTenant && tierReservationTenantId && req.tenantLimits?.maxTicketsMonth != null) {
    const { getMasterDb } = await import('../db/master-connection.js');
    const masterDb = getMasterDb();
    if (masterDb) {
      const month = new Date().toISOString().slice(0, 7); // YYYY-MM
      const limit = req.tenantLimits.maxTicketsMonth;

      // Atomic reservation: read + insert/increment inside a transaction to prevent TOCTOU
      // races where two concurrent requests both pass a stale pre-limit check.
      const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
        const usage = masterDb.prepare(
          'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
        ).get(tierReservationTenantId, month) as { tickets_created: number } | undefined;
        const current = usage?.tickets_created ?? 0;
        if (current >= limit) {
          return { allowed: false, current };
        }
        masterDb.prepare(`
          INSERT INTO tenant_usage (tenant_id, month, tickets_created)
          VALUES (?, ?, 1)
          ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
        `).run(tierReservationTenantId, month);
        return { allowed: true, current: current + 1 };
      })();

      if (!reservation.allowed) {
        res.status(403).json({
          success: false,
          upgrade_required: true,
          feature: 'ticket_limit',
          message: `Monthly ticket limit reached (${reservation.current}/${limit}). Upgrade to Pro for unlimited tickets.`,
          current: reservation.current,
          limit,
        });
        return;
      }
      tierReservationCommitted = true;
    }
  }

  // Get default status if not provided
  let statusId = body.status_id;
  if (!statusId) {
    const defaultStatus = await adb.get<AnyRow>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
    statusId = defaultStatus?.id ?? 1;
  }

  // F16: Auto-calculate due date if not provided
  let dueOn = body.due_on ?? null;
  if (!dueOn) {
    const [dueCfg, dueUnit] = await Promise.all([
      adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_due_value'"),
      adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_due_unit'"),
    ]);
    if (dueCfg?.value && parseInt(dueCfg.value) > 0) {
      const val = parseInt(dueCfg.value);
      const unit = dueUnit?.value || 'days';
      const d = new Date();
      if (unit === 'hours') d.setHours(d.getHours() + val);
      else d.setDate(d.getDate() + val);
      dueOn = d.toISOString().replace('T', ' ').substring(0, 19);
    }
  }

  // F7: Default assignment if not provided
  let assignedTo = body.assigned_to ?? null;
  if (!assignedTo) {
    const defaultAssignment = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_default_assignment'");
    if (defaultAssignment?.value === 'default') {
      assignedTo = userId; // Assign to creator
    }
    // 'unassigned' and 'pin_based' leave it null
  }

  // I4 fix: atomic, race-free, poison-resistant counter allocation via migration 072.
  // Replaces the old SELECT MAX(...) + 1 pattern that was vulnerable to:
  //   - Android-poisoned negative order_ids permanently corrupting the counter
  //   - Two concurrent inserts reading the same MAX and colliding
  const ticketSeq = allocateCounter(db, 'ticket_order_id');
  const orderId = formatTicketOrderId(ticketSeq);

  // Generate tracking token for public ticket lookup
  const trackingToken = crypto.randomBytes(16).toString('hex'); // 32-char hex (128-bit)

  // Validate priority enum (migration 135)
  const PRIORITY_VALUES = ['low', 'normal', 'high', 'critical'] as const;
  const priority: string = PRIORITY_VALUES.includes(body.priority as typeof PRIORITY_VALUES[number])
    ? (body.priority as string)
    : 'normal';

  // SCAN-462 / migration 136: resolve location_id — default to 1 (Main Store) when not provided.
  // Validate that the supplied id references an existing, active location.
  let ticketLocationId: number = 1;
  if (body.location_id !== undefined && body.location_id !== null) {
    if (!Number.isInteger(body.location_id) || (body.location_id as number) <= 0) {
      throw new AppError('location_id must be a positive integer', 400);
    }
    const loc = await adb.get<AnyRow>(
      'SELECT id FROM locations WHERE id = ? AND is_active = 1',
      body.location_id,
    );
    if (!loc) throw new AppError('location_id references an unknown or inactive location', 400);
    ticketLocationId = body.location_id as number;
  }

  // Insert ticket (ENR-POS1: includes is_layaway + layaway_expires; migration 136: location_id)
  // CROSS12-fix: use resolvedCustomerId so walk-in tickets point to their
  // unique customer row (or the sentinel for truly anonymous walk-ins).
  const ticketResult = await adb.run(`
    INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                         source, referral_source, labels, due_on, created_by, tracking_token,
                         is_layaway, layaway_expires, priority, location_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
    orderId,
    resolvedCustomerId,
    statusId,
    assignedTo,
    body.discount ?? 0,
    body.discount_reason ?? null,
    body.source ?? null,
    body.referral_source ?? null,
    JSON.stringify(body.labels ?? []),
    dueOn,
    userId,
    trackingToken,
    body.is_layaway ? 1 : 0,
    body.layaway_expires ?? null,
    priority,
    ticketLocationId,
    now(),
    now(),
  );

  const ticketId = Number(ticketResult.lastInsertRowid);
  const ticketCreatedAt = now();

  // SCAN-464: Assign SLA policy based on priority level (migration 135: priority column).
  // Fail-open: SLA assignment failure must never abort ticket creation.
  try {
    await computeSlaForTicket(adb, {
      ticket_id: ticketId,
      priority_level: priority,
      created_at: ticketCreatedAt,
    });
  } catch (slaErr) {
    logger.warn('sla assignment failed on ticket create (non-fatal)', {
      ticket_id: ticketId,
      error: slaErr instanceof Error ? slaErr.message : String(slaErr),
    });
  }

  // F15: Pre-fetch default warranty settings once (used per device if warranty_days not provided)
  const [wVal, wUnit] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_warranty_value'"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_default_warranty_unit'"),
  ]);
  const defaultWarrantyDays = (() => {
    const rawVal = wVal?.value ? parseInt(wVal.value) : 0;
    return wUnit?.value === 'months' ? rawVal * 30 : rawVal;
  })();

  // M10 fix: collect per-device tax warnings so the create response can surface them.
  const taxWarnings: string[] = [];

  // Insert devices
  for (const dev of body.devices) {
    const devicePrice = validatePrice(dev.price ?? 0, 'device price');
    const lineDiscount = dev.line_discount ?? 0;
    if (typeof lineDiscount !== 'number' || lineDiscount < 0 || lineDiscount > devicePrice) {
      throw new AppError('line_discount must be >= 0 and <= price', 400);
    }
    const resolvedTaxClassId = dev.tax_class_id ?? await getDefaultTaxClassIdAsync(adb, dev.item_type);
    const taxResult = await calcTaxWithWarningAsync(adb, devicePrice - lineDiscount, resolvedTaxClassId, dev.tax_inclusive ?? false);
    const taxAmount = taxResult.amount;
    if (taxResult.warning) taxWarnings.push(taxResult.warning);
    const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

    const devResult = await adb.run(`
      INSERT INTO ticket_devices (ticket_id, device_name, device_type, device_model_id, service_name,
                                  imei, serial, security_code,
                                  color, network, status_id, assigned_to, service_id, price, line_discount,
                                  tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                  due_on, device_location, additional_notes, customer_comments, staff_comments,
                                  pre_conditions, post_conditions,
                                  created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
      ticketId,
      dev.device_name ?? '',
      dev.device_type ?? null,
      dev.device_model_id ?? null,
      dev.service_name ?? null,
      dev.imei ?? null,
      dev.serial ?? null,
      dev.security_code ?? null,
      dev.color ?? null,
      dev.network ?? null,
      dev.status_id ?? statusId,
      dev.assigned_to ?? body.assigned_to ?? null,
      dev.service_id ?? null,
      devicePrice,
      lineDiscount,
      taxAmount,
      resolvedTaxClassId,
      dev.tax_inclusive ? 1 : 0,
      deviceTotal,
      dev.warranty ? 1 : 0,
      dev.warranty_days ?? defaultWarrantyDays,
      dev.due_on ?? null,
      dev.device_location ?? null,
      dev.additional_notes ?? null,
      dev.customer_comments ?? null,
      dev.staff_comments ?? null,
      JSON.stringify(dev.pre_conditions ?? []),
      JSON.stringify(dev.post_conditions ?? []),
      now(),
      now(),
    );

    const deviceId = Number(devResult.lastInsertRowid);

    // Insert parts and update inventory
    if (dev.parts && Array.isArray(dev.parts)) {
      for (const part of dev.parts) {
        const partQty = validateQuantity(part.quantity ?? 1, 'part quantity');
        const partPrice = validatePrice(part.price ?? 0, 'part price');

        await adb.run(`
          INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `, deviceId, part.inventory_item_id, partQty, partPrice, part.warranty ? 1 : 0, part.serial ?? null, now(), now());

        // Atomic stock deduction with availability guard — prevents negative stock
        const stockResult = await adb.run(
          'UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ? AND in_stock >= ?',
          partQty, now(), part.inventory_item_id, partQty
        );

        if (stockResult.changes === 0) {
          const invItem = await adb.get<AnyRow>('SELECT in_stock FROM inventory_items WHERE id = ?', part.inventory_item_id);
          throw new AppError(`Insufficient stock for ${part.name || 'item'}: ${invItem?.in_stock ?? 0} available, ${partQty} needed`, 400);
        }

        // Stock movement
        await adb.run(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
          VALUES (?, 'ticket_usage', ?, 'ticket', ?, ?, ?, ?, ?)
        `, part.inventory_item_id, -partQty, ticketId, `Used in ticket ${orderId}`, userId, now(), now());
      }
    }
  }

  // Recalculate totals
  await recalcTicketTotalsAsync(adb, ticketId);

  // History
  await insertHistoryAsync(adb, ticketId, userId, 'created', 'Ticket created');

  // Track usage for tier enforcement — only if we didn't already pre-increment during the
  // atomic tier reservation above. Skipping this prevents double-counting.
  // T10 fix: surface errors from the usage-tracker hook instead of swallowing them.
  if (!tierReservationCommitted) {
    import('../services/usageTracker.js').then(({ incrementTicketCount }) => {
      incrementTicketCount(req.tenantId);
    }).catch((e: unknown) => {
      logger.error('ticket-created usage tracker hook failed', {
        ticket_id: ticketId,
        error: e instanceof Error ? e.message : String(e),
      });
    });
  }

  // Check if status should notify customer
  const status = await adb.get<AnyRow>('SELECT notify_customer, name FROM ticket_statuses WHERE id = ?', statusId);
  if (status?.notify_customer) {
    // P2 / T10 fix: log failures and queue a retry via the notification_retry_queue
    // table (migration 070) so a transient notification failure does not silently
    // drop the customer's SMS.
    import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
      return sendTicketStatusNotification(db, { ticketId, statusName: status.name, tenantSlug: req.tenantSlug || null });
    }).catch((e: unknown) => {
      logger.error('ticket-created notification failed', {
        ticket_id: ticketId,
        status_id: statusId,
        status_name: status.name,
        error: e instanceof Error ? e.message : String(e),
      });
      enqueueTicketNotificationRetry(db, ticketId, status.name, req.tenantSlug || null, e);
    });
  }

  const ticket = await getFullTicketAsync(adb, ticketId);

  broadcast(WS_EVENTS.TICKET_CREATED, ticket, req.tenantSlug || null);

  // ENR-A6: Fire webhook
  // SA10-1: reuse the already-computed local `orderId` instead of reading it
  // back off the `ticket` detail shape (which was typed loosely and required
  // an `as any` cast at the broadcast boundary). Same value, no cast.
  fireWebhook(db, 'ticket_created', { ticket_id: ticketId, order_id: orderId });

  // Fire automations (async, non-blocking)
  // CROSS12-fix: use resolvedCustomerId (handles walk-in rows correctly).
  const cust = await adb.get<AnyRow>('SELECT * FROM customers WHERE id = ?', resolvedCustomerId);
  runAutomations(db, 'ticket_created', { ticket, customer: cust ?? {} });

  // M10 fix: attach a tax_warning field when any device referenced a deleted/missing tax class
  // so the UI can surface the issue to staff instead of silently under-charging.
  const createPayload: AnyRow = { ...(ticket as AnyRow) };
  if (taxWarnings.length > 0) {
    createPayload.tax_warning = taxWarnings.length === 1
      ? taxWarnings[0]
      : `${taxWarnings.length} tax class lookups defaulted to 0 (${taxWarnings.join('; ')})`;
  }

  // SCAN-522: fire-and-forget activity log
  logActivity(adb, {
    actor_user_id: userId,
    entity_kind: 'ticket',
    entity_id: ticketId,
    action: 'created',
  }).catch((err: unknown) => {
    logger.warn('tickets: activity-log dispatch failed', {
      err: err instanceof Error ? err.message : String(err),
      ticket_id: ticketId,
    });
  });

  res.status(201).json({ success: true, data: createPayload });
}));

// ===================================================================
// GET /kanban - Tickets grouped by status for kanban view
// ===================================================================
router.get('/kanban', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const statuses = await adb.all<AnyRow>('SELECT * FROM ticket_statuses ORDER BY sort_order ASC');

  // Single query: ROW_NUMBER() OVER (PARTITION BY status_id ORDER BY updated_at DESC)
  // caps each column at 500 rows without N separate round-trips.
  // ENR-UX16: cap raised from 100 to 500 to support shops with large backlogs.
  const KANBAN_PER_COLUMN = 500;
  const statusIds = statuses.map((s) => s.id as number);

  const allTickets = statusIds.length === 0 ? [] : await adb.all<AnyRow>(
    `SELECT id, order_id, customer_id, status_id, assigned_to,
            total, due_on, labels, created_at, updated_at,
            c_first_name, c_last_name, assigned_first, assigned_last
     FROM (
       SELECT t.id, t.order_id, t.customer_id, t.status_id, t.assigned_to,
              t.total, t.due_on, t.labels, t.created_at, t.updated_at,
              c.first_name AS c_first_name, c.last_name AS c_last_name,
              u.first_name AS assigned_first, u.last_name AS assigned_last,
              ROW_NUMBER() OVER (PARTITION BY t.status_id ORDER BY t.updated_at DESC) AS rn
       FROM tickets t
       LEFT JOIN customers c ON c.id = t.customer_id
       LEFT JOIN users u ON u.id = t.assigned_to
       WHERE t.status_id IN (${statusIds.map(() => '?').join(',')})
         AND t.is_deleted = 0
     ) sub
     WHERE sub.rn <= ${KANBAN_PER_COLUMN}
     ORDER BY sub.status_id, sub.updated_at DESC`,
    ...statusIds,
  );

  // Group rows by status_id in JS and merge with ordered status metadata.
  const ticketsByStatus = new Map<number, AnyRow[]>();
  for (const t of allTickets) {
    const sid = t.status_id as number;
    let bucket = ticketsByStatus.get(sid);
    if (!bucket) { bucket = []; ticketsByStatus.set(sid, bucket); }
    bucket.push(t);
  }

  const columns = statuses.map((status) => ({
    status: {
      id: status.id,
      name: status.name,
      color: status.color,
      sort_order: status.sort_order,
      is_closed: !!status.is_closed,
      is_cancelled: !!status.is_cancelled,
    },
    tickets: (ticketsByStatus.get(status.id as number) ?? []).map((t) => ({
      id: t.id,
      order_id: t.order_id,
      customer_id: t.customer_id,
      status_id: t.status_id,
      assigned_to: t.assigned_to,
      total: t.total,
      due_on: t.due_on,
      labels: parseJsonCol(t.labels, []),
      created_at: t.created_at,
      updated_at: t.updated_at,
      customer: { id: t.customer_id, first_name: t.c_first_name, last_name: t.c_last_name },
      assigned_user: t.assigned_to ? { id: t.assigned_to, first_name: t.assigned_first, last_name: t.assigned_last } : null,
    })),
  }));

  res.json({ success: true, data: { columns } });
}));

// ===================================================================
// GET /stalled - Stalled tickets
// ===================================================================
router.get('/stalled', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const daysRaw = req.query.days;
  let days = 0;
  if (daysRaw !== undefined && daysRaw !== '') {
    const n = Number(daysRaw);
    if (Number.isFinite(n) && n >= 1 && n <= 365) {
      days = Math.floor(n);
    }
  }
  if (!days) {
    const cfg = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'stall_alert_days'");
    days = cfg ? parseInt(cfg.value) || 3 : 3;
  }

  const tickets = await adb.all<AnyRow>(`
    SELECT t.id, t.order_id, t.customer_id, t.status_id, t.assigned_to,
           t.total, t.created_at, t.updated_at,
           c.first_name AS c_first_name, c.last_name AS c_last_name,
           ts.name AS status_name, ts.color AS status_color,
           u.first_name AS assigned_first, u.last_name AS assigned_last
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    WHERE t.is_deleted = 0
      AND ts.is_closed = 0
      AND ts.is_cancelled = 0
      AND t.updated_at <= datetime('now', ? || ' days')
    ORDER BY t.updated_at ASC
  `, `-${days}`);

  res.json({
    success: true,
    data: tickets.map((t) => ({
      id: t.id,
      order_id: t.order_id,
      customer_id: t.customer_id,
      status_id: t.status_id,
      assigned_to: t.assigned_to,
      total: t.total,
      created_at: t.created_at,
      updated_at: t.updated_at,
      customer: { id: t.customer_id, first_name: t.c_first_name, last_name: t.c_last_name },
      status: { id: t.status_id, name: t.status_name, color: t.status_color },
      assigned_user: t.assigned_to ? { id: t.assigned_to, first_name: t.assigned_first, last_name: t.assigned_last } : null,
    })),
  });
}));

// ===================================================================
// GET /device-history - Search tickets by IMEI or serial number
// ===================================================================
router.get('/device-history', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const imei = (req.query.imei as string || '').trim();
  const serial = (req.query.serial as string || '').trim();
  if (!imei && !serial) throw new AppError('imei or serial required', 400);

  const conditions: string[] = ['t.is_deleted = 0'];
  const params: any[] = [];
  if (imei) { conditions.push('td.imei = ?'); params.push(imei); }
  if (serial) { conditions.push('td.serial = ?'); params.push(serial); }

  const rows = await adb.all<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at,
           td.device_name, td.imei, td.serial, td.device_type,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed,
           c.first_name AS customer_first, c.last_name AS customer_last
    FROM ticket_devices td
    JOIN tickets t ON t.id = td.ticket_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE ${conditions.join(' AND ')}
    ORDER BY t.created_at DESC
    LIMIT 50
  `, ...params);

  res.json({ success: true, data: rows });
}));

// ===================================================================
// GET /warranty-lookup - Check if a device is under warranty
// ===================================================================
router.get('/warranty-lookup', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const imei = (req.query.imei as string || '').trim();
  const serial = (req.query.serial as string || '').trim();
  const phone = (req.query.phone as string || '').trim();
  if (!imei && !serial && !phone) throw new AppError('imei, serial, or phone required', 400);

  const conditions: string[] = ['t.is_deleted = 0', 'td.warranty = 1', 'td.warranty_days > 0'];
  const params: any[] = [];
  if (imei) { conditions.push('td.imei = ?'); params.push(imei); }
  if (serial) { conditions.push('td.serial = ?'); params.push(serial); }
  if (phone) { conditions.push('(c.mobile = ? OR c.phone = ?)'); params.push(phone, phone); }

  const [rows, copyNotesCfg] = await Promise.all([
    adb.all<AnyRow>(`
      SELECT t.id AS ticket_id, t.order_id, t.created_at AS ticket_created, t.updated_at,
             td.device_name, td.imei, td.serial, td.warranty_days, td.collected_date,
             ts.name AS status_name, ts.is_closed,
             c.first_name AS customer_first, c.last_name AS customer_last,
             CASE
               WHEN td.collected_date IS NOT NULL
                 THEN date(td.collected_date, '+' || td.warranty_days || ' days')
               WHEN ts.is_closed = 1
                 THEN date(t.updated_at, '+' || td.warranty_days || ' days')
               ELSE date(t.created_at, '+' || td.warranty_days || ' days')
             END AS warranty_expires
      FROM ticket_devices td
      JOIN tickets t ON t.id = td.ticket_id
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY warranty_expires DESC
      LIMIT 20
    `, ...params),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_copy_warranty_notes'"),
  ]);

  const today = new Date().toISOString().slice(0, 10);
  const copyNotes = copyNotesCfg?.value === '1';

  const results = await Promise.all(rows.map(async (r) => {
    const result: AnyRow = { ...r, warranty_active: r.warranty_expires >= today };
    if (copyNotes) {
      result.diagnostic_notes = await adb.all<AnyRow>(
        "SELECT content, created_at FROM ticket_notes WHERE ticket_id = ? AND type = 'diagnostic' ORDER BY created_at DESC",
        r.ticket_id
      );
    }
    return result;
  }));

  res.json({ success: true, data: results });
}));

// ===================================================================
// GET /missing-parts - All parts across open tickets with in_stock = 0
// ===================================================================
router.get('/missing-parts', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const rows = await adb.all<AnyRow>(`
    SELECT
      tdp.id AS part_id,
      tdp.ticket_device_id,
      tdp.inventory_item_id,
      tdp.quantity,
      tdp.price,
      tdp.status AS part_status,
      tdp.catalog_item_id,
      tdp.supplier_url,
      ii.name AS part_name,
      ii.sku AS part_sku,
      ii.in_stock,
      ii.image_url,
      sc.product_url AS catalog_url,
      sc.source AS catalog_source,
      sc.price AS catalog_price,
      sc.external_id AS catalog_external_id,
      td.device_name,
      t.id AS ticket_id,
      t.order_id,
      c.first_name || ' ' || c.last_name AS customer_name,
      ts.name AS ticket_status,
      ts.color AS ticket_status_color
    FROM ticket_device_parts tdp
    JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    JOIN tickets t ON t.id = td.ticket_id
    JOIN customers c ON c.id = t.customer_id
    JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN supplier_catalog sc ON sc.id = tdp.catalog_item_id
    WHERE t.is_deleted = 0
      AND ts.is_closed = 0
      AND ts.is_cancelled = 0
      AND ii.in_stock <= ii.reorder_level
    ORDER BY t.created_at DESC
    LIMIT 500
  `);

  res.json({ success: true, data: rows });
}));

// ===================================================================
// GET /tv-display - Simplified view for shop TV
// ===================================================================
router.get('/tv-display', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // Single query joining ticket_devices via GROUP_CONCAT — eliminates the
  // previous Promise.all N-per-ticket round-trips for device names.
  const result = await adb.all<AnyRow>(`
    SELECT t.id, t.order_id, t.status_id,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color,
           u.first_name AS tech_first, u.last_name AS tech_last,
           GROUP_CONCAT(td.device_name, '||') AS device_names_raw
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    LEFT JOIN ticket_devices td ON td.ticket_id = t.id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
    GROUP BY t.id
    ORDER BY t.updated_at DESC
    LIMIT 50
  `);

  res.json({
    success: true,
    data: result.map((t) => ({
      id: t.id,
      order_id: t.order_id,
      customer_first_name: t.c_first_name,
      device_names: t.device_names_raw ? (t.device_names_raw as string).split('||') : [],
      status: { name: t.status_name, color: t.status_color },
      assigned_tech: t.tech_first ? `${t.tech_first} ${t.tech_last}` : null,
    })),
  });
}));

// ===================================================================
// GET /feedback-summary - Overall feedback stats
// (Must be before /:id to avoid route conflict)
// ===================================================================
router.get('/feedback-summary', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const [stats, recent] = await Promise.all([
    adb.get<AnyRow>(`
      SELECT COUNT(*) AS total_reviews,
             COALESCE(AVG(rating), 0) AS avg_rating,
             COUNT(CASE WHEN rating >= 4 THEN 1 END) AS positive_count,
             COUNT(CASE WHEN rating <= 2 THEN 1 END) AS negative_count
      FROM customer_feedback
    `),
    adb.all<AnyRow>(`
      SELECT cf.*, c.first_name, c.last_name, t.order_id
      FROM customer_feedback cf
      LEFT JOIN customers c ON c.id = cf.customer_id
      LEFT JOIN tickets t ON t.id = cf.ticket_id
      ORDER BY cf.created_at DESC LIMIT 10
    `),
  ]);

  res.json({ success: true, data: { ...stats, recent } });
}));

// ===================================================================
// GET /export - Export tickets as CSV (no pagination, max 10,000 rows)
// ===================================================================
// SCAN-1073: unguarded CSV export was an exfiltration + DoS vector.
//  - Gate on tickets.view so revoked roles cannot dump all tickets.
//  - Per-user throttle: 5 exports / 60s. A CSV export materialises every row
//    in the filtered set and serialises them — a tight loop otherwise ties up
//    the async-db worker. 60s / 5 is conservative; admins doing legit bulk
//    work can still paginate via the regular list handler.
router.get('/export', requirePermission('tickets.view'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;

  const userId = req.user?.id;
  if (userId) {
    const rate = consumeWindowRate(req.db, 'ticket_export', `u:${userId}`, 5, 60_000);
    if (!rate.allowed) {
      res.setHeader('Retry-After', String(rate.retryAfterSeconds));
      throw new AppError(`Too many exports; retry in ${rate.retryAfterSeconds}s`, 429);
    }
  }
  const keyword = (req.query.keyword as string || '').trim();
  const statusParam = (req.query.status_id as string || '').trim();
  const statusId = /^\d+$/.test(statusParam) ? parseInt(statusParam) : null;
  const statusGroup = parseStatusGroup(req.query.status_group) || parseStatusGroup(statusParam);
  const assignedTo = parseAssignedToFilter(req.query.assigned_to, req.user?.id);
  const fromDate = req.query.from_date as string || null;
  const toDate = req.query.to_date as string || null;
  const dateFilter = req.query.date_filter as string || 'all';
  const sortBy = (req.query.sort_by as string) || 'created_at';
  const sortOrder = (req.query.sort_order as string || 'DESC').toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

  const allowedSorts = ['created_at', 'updated_at', 'order_id', 'total', 'due_on', 'status_id'];
  const safeSortBy = allowedSorts.includes(sortBy) ? `t.${sortBy}` : 't.created_at';

  const conditions: string[] = ['t.is_deleted = 0'];
  const params: any[] = [];

  if (statusId) {
    conditions.push('t.status_id = ?');
    params.push(statusId);
  } else if (statusGroup) {
    if (statusGroup === 'active') {
      conditions.push('t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0)');
    } else if (statusGroup === 'open') {
      conditions.push("t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 AND LOWER(name) NOT LIKE '%hold%' AND LOWER(name) NOT LIKE '%waiting%' AND LOWER(name) NOT LIKE '%pending%' AND LOWER(name) NOT LIKE '%transit%')");
    } else if (statusGroup === 'closed') {
      conditions.push('t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 1)');
    } else if (statusGroup === 'cancelled') {
      conditions.push('t.status_id IN (SELECT id FROM ticket_statuses WHERE is_cancelled = 1)');
    } else if (statusGroup === 'on_hold') {
      conditions.push("t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 AND (LOWER(name) LIKE '%hold%' OR LOWER(name) LIKE '%waiting%' OR LOWER(name) LIKE '%pending%' OR LOWER(name) LIKE '%transit%'))");
    }
  }
  if (assignedTo) {
    conditions.push('t.assigned_to = ?');
    params.push(assignedTo);
  }

  // SCAN-526: mirror the ticket_all_employees_view_all guard from the list handler.
  // Technicians (non-admin/non-manager) may only export their own tickets when the
  // setting is disabled, preventing enumeration of other techs' work via CSV export.
  const exportRole = req.user?.role;
  const exportIsAdminOrManager = exportRole === 'admin' || exportRole === 'manager';
  if (!assignedTo && !exportIsAdminOrManager) {
    const allViewCfg = await req.asyncDb.get<{ value: string }>(
      "SELECT value FROM store_config WHERE key = 'ticket_all_employees_view_all'"
    );
    if (allViewCfg?.value === '0') {
      conditions.push('t.assigned_to = ?');
      params.push(req.user!.id);
    }
  }

  // Date filtering
  if (dateFilter !== 'all') {
    let daysBack = 0;
    switch (dateFilter) {
      case 'today': daysBack = 0; break;
      case 'yesterday': daysBack = 1; break;
      case '7days': daysBack = 7; break;
      case '14days': daysBack = 14; break;
      case '30days': daysBack = 30; break;
    }
    if (dateFilter === 'today') {
      conditions.push("date(t.created_at) = date('now')");
    } else if (dateFilter === 'yesterday') {
      conditions.push("date(t.created_at) = date('now', '-1 day')");
    } else {
      conditions.push(`t.created_at >= datetime('now', '-${daysBack} days')`);
    }
  }

  if (fromDate) {
    conditions.push('t.created_at >= ?');
    params.push(fromDate);
  }
  if (toDate) {
    conditions.push('t.created_at <= ?');
    params.push(toDate + ' 23:59:59');
  }

  // Keyword search (same as list endpoint)
  let keywordJoin = '';
  if (keyword) {
    keywordJoin = 'LEFT JOIN ticket_devices td_kw ON td_kw.ticket_id = t.id';
    conditions.push(`(
      t.order_id LIKE ? ESCAPE '\\' OR
      c.first_name LIKE ? ESCAPE '\\' OR c.last_name LIKE ? ESCAPE '\\' OR
      (c.first_name || ' ' || c.last_name) LIKE ? ESCAPE '\\' OR
      td_kw.device_name LIKE ? ESCAPE '\\' OR
      t.id IN (SELECT ticket_id FROM ticket_notes WHERE content LIKE ? ESCAPE '\\') OR
      t.id IN (SELECT ticket_id FROM ticket_history WHERE description LIKE ? ESCAPE '\\')
    )`);
    const like = `%${escapeLike(keyword)}%`;
    params.push(like, like, like, like, like, like, like);
  }

  const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';
  const MAX_EXPORT = 10000;

  const sql = `
    SELECT DISTINCT t.order_id,
           COALESCE(c.first_name || ' ' || c.last_name, '') AS customer_name,
           (SELECT GROUP_CONCAT(td_exp.device_name, '; ') FROM ticket_devices td_exp WHERE td_exp.ticket_id = t.id) AS device_names,
           ts.name AS status_name,
           t.created_at,
           t.total
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    ${keywordJoin}
    ${whereClause}
    ORDER BY ${safeSortBy} ${sortOrder}
    LIMIT ${MAX_EXPORT}
  `;
  const rows = await adb.all<AnyRow>(sql, ...params);

  // Build CSV
  // SCAN-1161: prefix any leading `=`, `+`, `-`, `@`, TAB, CR with a single
  // quote so Excel/Calc/Sheets don't evaluate cell content as a formula —
  // mirrors the server-side toCsv guard in reports.routes.ts (SCAN-1130).
  const csvHeader = 'Order ID,Customer,Device,Status,Created,Total';
  const CSV_FORMULA_TRIGGERS = /^[=+\-@\t\r]/;
  const csvRows = rows.map((r) => {
    const escapeCsv = (raw: unknown): string => {
      if (!raw) return '';
      const val = CSV_FORMULA_TRIGGERS.test(String(raw)) ? `'${String(raw)}` : String(raw);
      if (val.includes(',') || val.includes('"') || val.includes('\n')) {
        return `"${val.replace(/"/g, '""')}"`;
      }
      return val;
    };
    return [
      escapeCsv(r.order_id || ''),
      escapeCsv(r.customer_name || ''),
      escapeCsv(r.device_names || ''),
      escapeCsv(r.status_name || ''),
      escapeCsv(r.created_at || ''),
      r.total != null ? r.total.toFixed(2) : '0.00',
    ].join(',');
  });

  const csv = [csvHeader, ...csvRows].join('\n');

  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', 'attachment; filename="tickets-export.csv"');
  res.send(csv);
}));

// ===================================================================
// GET /saved-filters - List user's saved ticket filter presets
// ===================================================================
router.get('/saved-filters', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const filters = await adb.all<AnyRow>(
    'SELECT id, name, filters, created_at FROM ticket_saved_filters WHERE user_id = ? ORDER BY created_at DESC',
    userId
  );

  res.json({
    success: true,
    data: filters.map((f) => ({
      ...f,
      filters: parseJsonCol(f.filters, {}),
    })),
  });
}));

// ===================================================================
// POST /saved-filters - Save a ticket filter preset
// ===================================================================
router.post('/saved-filters', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const { name, filters } = req.body;

  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    throw new AppError('Filter name is required', 400);
  }
  if (!filters || typeof filters !== 'object') {
    throw new AppError('Filters object is required', 400);
  }

  const safeName = name.trim().slice(0, 100);
  const filtersJson = JSON.stringify(filters);

  const result = await adb.run(
    'INSERT INTO ticket_saved_filters (user_id, name, filters) VALUES (?, ?, ?)',
    userId, safeName, filtersJson
  );

  res.json({
    success: true,
    data: {
      id: result.lastInsertRowid,
      name: safeName,
      filters,
    },
  });
}));

// ===================================================================
// DELETE /saved-filters/:id - Delete a saved filter preset
// ===================================================================
router.delete('/saved-filters/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const filterId = validateId(req.params.id, 'filter id');
  if (!filterId) throw new AppError('Invalid filter ID', 400);

  const existing = await adb.get<AnyRow>(
    'SELECT id FROM ticket_saved_filters WHERE id = ? AND user_id = ?',
    filterId, userId
  );
  if (!existing) throw new AppError('Saved filter not found', 404);

  await adb.run('DELETE FROM ticket_saved_filters WHERE id = ? AND user_id = ?', filterId, userId);

  res.json({ success: true, data: { deleted: true } });
}));

// ===================================================================
// GET /:id - Full ticket detail
// ===================================================================
// SCAN-1074: sibling PUT/PATCH/DELETE gate on tickets.edit/delete/change_status,
// but detail-read was ungated, so a custom role with tickets.view revoked could
// still fetch any ticket by iterating ids.
router.get('/:id', requirePermission('tickets.view'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = await getFullTicketAsync(adb, ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);
  if (ticket.is_deleted) throw new AppError('Ticket has been deleted', 404);

  // SW-D8: Include label template setting for print/label rendering
  const labelTemplateCfg = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_label_template'");
  if (labelTemplateCfg?.value) {
    ticket.label_template = labelTemplateCfg.value;
  }

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// PUT /:id - Update ticket summary fields
// ===================================================================
// SEC-H25: gate ticket updates behind tickets.edit permission.
router.put('/:id', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for automations
  const ticketId = validateId(req.params.id, 'ticket id');
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = await adb.get<AnyRow>('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  // F1: Check if editing closed tickets is allowed
  const existingStatus = await adb.get<AnyRow>('SELECT is_closed FROM ticket_statuses WHERE id = ?', existing.status_id);
  if (existingStatus?.is_closed) {
    const allowEditClosed = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_allow_edit_closed'");
    if (allowEditClosed?.value === '0' || allowEditClosed?.value === 'false') {
      throw new AppError('Cannot edit a closed ticket', 403);
    }
  }

  // F2/F3: Check if editing/deleting after invoice is allowed
  if (existing.invoice_id) {
    const allowEditAfterInvoice = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_allow_edit_after_invoice'");
    if (allowEditAfterInvoice?.value === '0' || allowEditAfterInvoice?.value === 'false') {
      throw new AppError('Cannot edit a ticket with an invoice', 403);
    }
  }

  // Validate customer_id if provided.
  // SA2-1: coerce + primitive-type check so a malicious body like
  // `{customer_id: {id: 1}}` or `{customer_id: [1]}` doesn't crash
  // better-sqlite3's bind step with "SQLite3 can only bind numbers,
  // strings, bigints, buffers, and null". Express/body-parser happily
  // accepts JSON objects/arrays here; we reject upfront with a clean
  // 400 instead of a 500.
  if (req.body.customer_id !== undefined && req.body.customer_id !== null) {
    const raw = req.body.customer_id;
    const t = typeof raw;
    if (t !== 'number' && t !== 'string') {
      throw new AppError('customer_id must be a number or string', 400);
    }
    const customerId = typeof raw === 'string' ? parseInt(raw, 10) : raw;
    if (!Number.isInteger(customerId) || customerId <= 0) {
      throw new AppError('customer_id must be a positive integer', 400);
    }
    const cust = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customerId);
    if (!cust) throw new AppError('Customer not found', 404);
    // Normalise back into req.body so the downstream UPDATE binds an int.
    (req.body as Record<string, unknown>).customer_id = customerId;
  }

  const PATCH_PRIORITY_VALUES = ['low', 'normal', 'high', 'critical'] as const;
  if (req.body.priority !== undefined &&
      !PATCH_PRIORITY_VALUES.includes(req.body.priority as typeof PATCH_PRIORITY_VALUES[number])) {
    throw new AppError('priority must be one of: low, normal, high, critical', 400);
  }

  // SCAN-462 / migration 136: validate location_id before entering the update loop
  if (req.body.location_id !== undefined && req.body.location_id !== null) {
    if (!Number.isInteger(req.body.location_id) || (req.body.location_id as number) <= 0) {
      throw new AppError('location_id must be a positive integer', 400);
    }
    const patchLoc = await adb.get<AnyRow>(
      'SELECT id FROM locations WHERE id = ? AND is_active = 1',
      req.body.location_id,
    );
    if (!patchLoc) throw new AppError('location_id references an unknown or inactive location', 400);
  }

  const allowedFields = [
    'customer_id', 'assigned_to', 'discount', 'discount_reason',
    'source', 'referral_source', 'labels', 'due_on', 'signature',
    'is_layaway', 'layaway_expires', // ENR-POS1
    'priority', // migration 135
    'location_id', // migration 136 (SCAN-462)
  ];
  const updates: string[] = [];
  const params: any[] = [];

  for (const field of allowedFields) {
    if (req.body[field] !== undefined) {
      const val = field === 'labels' ? JSON.stringify(req.body[field]) : req.body[field];
      updates.push(`${field} = ?`);
      params.push(val);
    }
  }

  if (updates.length === 0) throw new AppError('No valid fields to update');

  // Optimistic locking: if client sends updated_at, verify no concurrent edit
  const clientUpdatedAt = req.body._updated_at;
  if (clientUpdatedAt && clientUpdatedAt !== existing.updated_at) {
    throw new AppError('Ticket was modified by another user. Please refresh and try again.', 409);
  }

  updates.push('updated_at = ?');
  params.push(now());
  params.push(ticketId);

  await adb.run(`UPDATE tickets SET ${updates.join(', ')} WHERE id = ?`, ...params);

  // Recalculate if discount changed
  if (req.body.discount !== undefined) {
    await recalcTicketTotalsAsync(adb, ticketId);
  }

  // SCAN-464 (migration 135): Re-assign SLA when priority changes.
  // priority is now persisted in the DB; read it back from body or fall back to existing row.
  if (req.body.priority !== undefined) {
    const effectivePriority: string = (req.body.priority as string) || (existing.priority as string) || 'normal';
    try {
      await computeSlaForTicket(adb, {
        ticket_id: ticketId,
        priority_level: effectivePriority,
        created_at: existing.created_at as string,
      });
    } catch (slaErr) {
      logger.warn('sla assignment failed on ticket update (non-fatal)', {
        ticket_id: ticketId,
        error: slaErr instanceof Error ? slaErr.message : String(slaErr),
      });
    }
  }

  await insertHistoryAsync(adb, ticketId, userId, 'updated', 'Ticket updated');
  const ticket = await getFullTicketAsync(adb, ticketId);
  broadcast(WS_EVENTS.TICKET_UPDATED, ticket, req.tenantSlug || null);

  // Fire automations for assignment changes
  if (req.body.assigned_to !== undefined && req.body.assigned_to !== existing.assigned_to) {
    const cust = await adb.get<AnyRow>('SELECT * FROM customers WHERE id = ?', ticket!.customer_id);
    runAutomations(db, 'ticket_assigned', { ticket, customer: cust ?? {} });
  }

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// DELETE /:id - Soft delete
// ===================================================================
// SEC-M62: Ticket delete is destructive — it soft-deletes the ticket,
// cascades stock restores, and voids any associated invoice. Before
// this fix the route was gated only by authMiddleware, so any logged-in
// user could nuke any ticket including paid-through ones, and refund
// flows could be used to launder stock back into inventory.
router.delete('/:id', requirePermission('tickets.delete'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = await adb.get<AnyRow>('SELECT id, invoice_id, estimate_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  // SW-D3 + SEC-M62: Block deletion when ticket has an invoice and the
  // allow-delete-after-invoice toggle is disabled. Additionally hard-block
  // deletion of tickets whose invoice has any payment recorded — a paid
  // invoice is evidence of revenue and cannot be retroactively unpaid via
  // a cascade. This is tighter than the existing toggle (which permits
  // delete-through for admin) because a paid-invoice delete cascades into
  // stock restoration + invoice void, both of which confuse revenue
  // reporting even when done by an admin.
  if (existing.invoice_id) {
    const allowDeleteAfterInvoice = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_allow_delete_after_invoice'");
    if (allowDeleteAfterInvoice?.value === '0') {
      throw new AppError('Cannot delete a ticket with an associated invoice', 403);
    }
    const inv = await adb.get<AnyRow>('SELECT id, amount_paid, total, status FROM invoices WHERE id = ?', existing.invoice_id);
    if (inv && (inv.amount_paid ?? 0) > 0) {
      throw new AppError('Cannot delete a ticket whose invoice has been paid. Issue a refund first.', 403);
    }
  }

  // Atomically claim the soft-delete before touching stock or invoices.
  // Two concurrent DELETE requests both pass the `is_deleted = 0` precheck
  // above; whichever writes first gets changes=1 and owns the stock-credit
  // path. The loser gets changes=0 and 409s — preventing double-credit of
  // inventory (double-credit race guard, SEC-H62).
  const claimedDelete = await adb.run(
    'UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ? AND is_deleted = 0',
    now(), ticketId,
  );
  if (claimedDelete.changes === 0) {
    throw new AppError('Ticket already deleted (concurrent request)', 409);
  }

  // Restore inventory stock for all parts on all devices in this ticket.
  // SEC-H49: ONLY credit stock for parts in 'available' / 'received' status.
  // 'missing' parts never existed in inventory (stock was never decremented),
  // 'ordered' parts are en-route from the supplier and haven't been added to
  // inventory yet. Crediting stock for either state MINTS inventory out of
  // thin air — a theft primitive: a cashier who can soft-delete a ticket
  // with `status='missing'` lines inflates stock count without taking
  // physical goods. Matches the corresponding invariant on ticket cancel
  // (see F5 cancel path in the same file).
  const devices = await adb.all<AnyRow>('SELECT id FROM ticket_devices WHERE ticket_id = ?', ticketId);
  for (const device of devices) {
    const parts = await adb.all<AnyRow>('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?', device.id);
    for (const part of parts) {
      if (part.inventory_item_id && (part.status === 'available' || part.status === 'received' || part.status == null)) {
        await adb.run('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?',
          part.quantity, now(), part.inventory_item_id);

        await adb.run(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
          VALUES (?, 'ticket_return', ?, 'ticket', ?, 'Stock restored — ticket deleted', ?, ?, ?)
        `, part.inventory_item_id, part.quantity, ticketId, userId, now(), now());
      }
    }
  }

  // Void any linked non-void invoice (same pattern as cancellation)
  const linkedInvoice = await adb.get<AnyRow>("SELECT id, status FROM invoices WHERE ticket_id = ? AND status != 'void'", ticketId);
  if (linkedInvoice) {
    await adb.run("UPDATE invoices SET status = 'void', amount_due = 0, updated_at = ? WHERE id = ?", now(), linkedInvoice.id);
    await insertHistoryAsync(adb, ticketId, userId, 'invoice_voided', 'Invoice auto-voided on ticket deletion');
  }

  // D6 fix: detach linked estimates so they are not left with a dangling
  // converted_ticket_id pointer to a deleted ticket. We null the back-reference
  // and flip the estimate status back to 'draft' so staff can re-convert it.
  // Covers both directions: tickets created FROM an estimate AND estimates that
  // were manually marked as converted without going through the automated path.
  const detachEstimatesResult = await adb.run(
    "UPDATE estimates SET converted_ticket_id = NULL, status = CASE WHEN status = 'converted' THEN 'draft' ELSE status END, updated_at = ? WHERE converted_ticket_id = ?",
    now(), ticketId,
  );
  if (detachEstimatesResult.changes > 0) {
    logger.info('detached estimates from deleted ticket', {
      ticket_id: ticketId,
      estimates_detached: detachEstimatesResult.changes,
    });
  }

  await insertHistoryAsync(adb, ticketId, userId, 'deleted', 'Ticket deleted');

  broadcast(WS_EVENTS.TICKET_DELETED, { id: ticketId }, req.tenantSlug || null);

  res.json({ success: true, data: { id: ticketId } });
}));

// ===================================================================
// PATCH /:id/status - Change ticket status
// ===================================================================
// SEC-H25: gate status changes behind tickets.change_status permission.
router.patch('/:id/status', requirePermission('tickets.change_status'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ticketId = validateId(req.params.id, 'ticket id');
  const userId = req.user!.id;
  const { status_id } = req.body;

  if (!ticketId) throw new AppError('Invalid ticket ID');
  if (!status_id) throw new AppError('status_id is required');
  const statusIdInt = typeof status_id === 'string' ? parseInt(status_id, 10) : Number(status_id);
  if (!Number.isInteger(statusIdInt) || statusIdInt <= 0) {
    throw new AppError('status_id must be a positive integer', 400);
  }

  // SEC-H122: all guards + UPDATE + audit + broadcast + webhook + automations
  // are handled by the shared helper so the automation path runs the same logic.
  const { ticket, oldStatusId, newStatusId: resolvedNewStatusId } = await applyTicketStatusChange(
    db,
    ticketId,
    statusIdInt,
    userId,
    req.tenantSlug || null,
  );

  // SCAN-522: fire-and-forget activity log for status change
  logActivity(adb, {
    actor_user_id: userId,
    entity_kind: 'ticket',
    entity_id: ticketId,
    action: 'status_changed',
    metadata: { from: oldStatusId, to: resolvedNewStatusId },
  }).catch((err: unknown) => {
    logger.warn('tickets: status-change activity-log dispatch failed', {
      err: err instanceof Error ? err.message : String(err),
      ticket_id: ticketId,
    });
  });

  // Notification (HTTP-only: needs tenantSlug from req, and retry-queue fallback
  // that uses the sync db handle directly).
  // Fetch newStatus for notify_customer flag — the helper already validated it.
  const newStatus = await adb.get<AnyRow>(
    'SELECT name, notify_customer, is_closed FROM ticket_statuses WHERE id = ?',
    statusIdInt,
  );
  if (newStatus?.notify_customer) {
    import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
      sendTicketStatusNotification(db, { ticketId, statusName: newStatus.name, tenantSlug: req.tenantSlug || null });
    }).catch(err => logger.error('notification_import_failed', { err: err instanceof Error ? err.message : String(err) }));
  }

  // SW-D14: Schedule feedback SMS after ticket close (HTTP-only side-effect)
  if (newStatus?.is_closed) {
    const [feedbackAutoSms, feedbackTemplate, feedbackDelay] = await Promise.all([
      adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'feedback_auto_sms'"),
      adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'feedback_sms_template'"),
      adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'feedback_delay_hours'"),
    ]);
    if (feedbackAutoSms?.value === '1' || feedbackAutoSms?.value === 'true') {
      const delayHours = feedbackDelay?.value ? parseFloat(feedbackDelay.value) : 24;
      const delayMs = Math.max(0, delayHours * 60 * 60 * 1000);
      const templateBody = feedbackTemplate?.value || 'Hi {customer_name}, how was your experience with your recent repair? Reply with a rating 1-5. Thank you!';

      const [feedbackCust, storeNameRow] = await Promise.all([
        adb.get<AnyRow>('SELECT first_name, mobile, phone FROM customers WHERE id = ?', ticket!.customer_id),
        adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'store_name'"),
      ]);
      const feedbackPhone = feedbackCust?.mobile || feedbackCust?.phone;
      if (feedbackPhone) {
        const smsBody = templateBody
          .replace(/{customer_name}/g, feedbackCust?.first_name || 'Customer')
          .replace(/{ticket_id}/g, ticket!.order_id || '')
          .replace(/{store_name}/g, storeNameRow?.value || 'our store');

        const tenantSlug = req.tenantSlug || null;
        setTimeout(async () => {
          try {
            const { sendSmsTenant } = await import('../services/smsProvider.js');
            await sendSmsTenant(db, tenantSlug, feedbackPhone, smsBody);
            await adb.run(`
              INSERT INTO customer_feedback (ticket_id, customer_id, source, requested_at)
              VALUES (?, ?, 'sms', datetime('now'))
            `, ticketId, ticket!.customer_id);
            await adb.run(`
              INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
              VALUES ('', ?, ?, ?, 'sent', 'outbound', 'auto-feedback', 'ticket', ?, datetime('now'), datetime('now'))
            `, feedbackPhone, feedbackPhone.replace(/\D/g, '').replace(/^1/, ''), smsBody, ticketId);
            logger.info('feedback sms sent', { toRedacted: redactPhone(feedbackPhone), orderId: ticket!.order_id });
          } catch (err) {
            logger.error('feedback_sms_failed', { err: err instanceof Error ? err.message : String(err) });
          }
        }, delayMs);
      }
    }
  }

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// PATCH /:id/pin - Toggle ticket pinned state
// ===================================================================
// SEC-H25: pinning a ticket modifies state — gate behind tickets.edit.
router.patch('/:id/pin', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');

  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = await adb.get<AnyRow>('SELECT id, is_pinned FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  const newPinned = existing.is_pinned ? 0 : 1;
  await adb.run('UPDATE tickets SET is_pinned = ?, updated_at = ? WHERE id = ?', newPinned, now(), ticketId);

  res.json({ success: true, data: { id: ticketId, is_pinned: !!newPinned } });
}));

// ===================================================================
// POST /:id/notes - Add note
// ===================================================================
// SEC-H25: adding a note modifies the ticket — gate behind tickets.edit.
router.post('/:id/notes', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  const userId = req.user!.id;

  if (!ticketId) throw new AppError('Invalid ticket ID');
  const existing = await adb.get<AnyRow>('SELECT id, order_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  const { type, content, is_flagged, ticket_device_id, parent_id } = req.body;
  if (!content) throw new AppError('content is required');
  if (content.length > 10000) throw new AppError('Note content too long (max 10,000 characters)', 400);

  const result = await adb.run(`
    INSERT INTO ticket_notes (ticket_id, ticket_device_id, user_id, type, content, is_flagged, parent_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, ticketId, ticket_device_id ?? null, userId, type || 'internal', content, is_flagged ? 1 : 0, parent_id ?? null, now(), now());

  const noteId = result.lastInsertRowid;

  // History + timestamp update in parallel
  await Promise.all([
    insertHistoryAsync(adb, ticketId, userId, 'note_added', `Note added (${type || 'internal'})`),
    adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), ticketId),
  ]);

  if (type === 'email') {
    // TODO(MEDIUM, §26): wire outbound email send for type='email' notes.
    // Previously this was a silent `console.log` that pretended the email
    // went out; flipped to a LOUD stub warn so operators can see in logs
    // that the note was stored but no email was actually dispatched.
    logger.warn('[stub] type=email note stored but no email dispatched (not yet wired)', {
      ticketId,
      ticketOrderId: existing.order_id,
    });
  }

  const note = (await adb.get<AnyRow>(`
    SELECT tn.*, u.first_name, u.last_name, u.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.id = ?
  `, noteId))!;

  const shaped = {
    ...note,
    is_flagged: !!note.is_flagged,
    user: { id: note.user_id, first_name: note.first_name, last_name: note.last_name, avatar_url: note.avatar_url },
  };

  broadcast(WS_EVENTS.TICKET_NOTE_ADDED, { ticket_id: ticketId, note: shaped }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: shaped });
}));

// ===================================================================
// PUT /notes/:noteId - Edit note
// ===================================================================
router.put('/notes/:noteId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const noteId = validateId(req.params.noteId, 'note id');
  if (!noteId) throw new AppError('Invalid note ID');

  const existing = await adb.get<AnyRow>('SELECT * FROM ticket_notes WHERE id = ?', noteId);
  if (!existing) throw new AppError('Note not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, existing.ticket_id, req.user?.role);

  // Ownership check: only note author or admin can edit
  if (existing.user_id !== req.user!.id && req.user!.role !== 'admin') {
    throw new AppError('You can only edit your own notes', 403);
  }

  const { content, is_flagged, type } = req.body;
  const updates: string[] = ['updated_at = ?'];
  const params: any[] = [now()];

  if (content !== undefined) { updates.push('content = ?'); params.push(content); }
  if (is_flagged !== undefined) { updates.push('is_flagged = ?'); params.push(is_flagged ? 1 : 0); }
  if (type !== undefined) { updates.push('type = ?'); params.push(type); }

  params.push(noteId);
  await adb.run(`UPDATE ticket_notes SET ${updates.join(', ')} WHERE id = ?`, ...params);

  const note = (await adb.get<AnyRow>(`
    SELECT tn.*, u.first_name, u.last_name, u.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.id = ?
  `, noteId))!;

  res.json({
    success: true,
    data: {
      ...note,
      is_flagged: !!note.is_flagged,
      user: { id: note.user_id, first_name: note.first_name, last_name: note.last_name, avatar_url: note.avatar_url },
    },
  });
}));

// ===================================================================
// DELETE /notes/:noteId - Delete note
// ===================================================================
router.delete('/notes/:noteId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const noteId = validateId(req.params.noteId, 'note id');
  if (!noteId) throw new AppError('Invalid note ID');

  const existing = await adb.get<AnyRow>('SELECT id, ticket_id, user_id FROM ticket_notes WHERE id = ?', noteId);
  if (!existing) throw new AppError('Note not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, existing.ticket_id, req.user?.role);

  // Ownership check: only note author or admin can delete
  if (existing.user_id !== req.user!.id && req.user!.role !== 'admin') {
    throw new AppError('You can only delete your own notes', 403);
  }

  await Promise.all([
    adb.run('DELETE FROM ticket_notes WHERE id = ?', noteId),
    insertHistoryAsync(adb, existing.ticket_id, req.user!.id, 'note_deleted', 'Note deleted'),
  ]);

  res.json({ success: true, data: { id: noteId } });
}));

// ===================================================================
// POST /:id/devices/:deviceId/photo-upload-token  — mint scoped token
// ===================================================================
// AUDIT-WEB-002: Returns a short-lived JWT scoped to one ticket+device so
// customers can use the QR photo-upload link without holding a full staff
// bearer token. Token expires in 30 minutes and carries aud='photo-upload'
// to prevent cross-endpoint reuse.
router.post(
  '/:id/devices/:deviceId/photo-upload-token',
  requirePermission('tickets.edit'),
  asyncHandler(async (req: Request, res: Response) => {
    const adb = req.asyncDb;
    const ticketId = validateId(req.params.id, 'ticket id');
    if (!ticketId) throw new AppError('Invalid ticket ID');
    const deviceId = validateId(req.params.deviceId, 'device id');
    if (!deviceId) throw new AppError('Invalid device ID');

    const ticket = await adb.get<AnyRow>(
      'SELECT id FROM tickets WHERE id = ? AND is_deleted = 0',
      ticketId,
    );
    if (!ticket) throw new AppError('Ticket not found', 404);

    const device = await adb.get<AnyRow>(
      'SELECT id FROM ticket_devices WHERE id = ? AND ticket_id = ?',
      deviceId,
      ticketId,
    );
    if (!device) throw new AppError('Device does not belong to this ticket', 400);

    const token = jwt.sign(
      {
        sub: 'photo-upload',
        ticket_id: ticketId,
        ticket_device_id: deviceId,
      },
      config.accessJwtSecret,
      {
        ...JWT_SIGN_OPTIONS,
        audience: 'photo-upload',
        expiresIn: '30m',
      },
    );

    res.json({ success: true, data: { token } });
  }),
);

// ===================================================================
// POST /:id/photos - Upload photos
// ===================================================================
// SEC-H25: uploading photos modifies the ticket — gate behind tickets.edit.
// AUDIT-WEB-002: also accepts a scoped photo-upload token (aud='photo-upload',
// sub='photo-upload') passed as Bearer. The scoped token must match the
// ticket_id and ticket_device_id in the request body/params.
router.post(
  '/:id/photos',
  // Middleware: allow EITHER a normal staff JWT OR a scoped photo-upload token.
  (req: Request, res: Response, next: NextFunction) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      res.status(401).json({ success: false, message: 'No token provided' });
      return;
    }
    const raw = authHeader.slice(7);

    // Attempt to verify as a scoped photo-upload token first.
    let scopedPayload: { sub?: string; ticket_id?: number; ticket_device_id?: number } | null = null;
    try {
      scopedPayload = jwt.verify(raw, config.accessJwtSecret, {
        algorithms: ['HS256'],
        issuer: JWT_SIGN_OPTIONS.issuer,
        audience: 'photo-upload',
      }) as { sub?: string; ticket_id?: number; ticket_device_id?: number };
    } catch {
      // Not a scoped token — fall through to normal auth middleware below.
    }

    if (scopedPayload) {
      if (scopedPayload.sub !== 'photo-upload') {
        res.status(403).json({ success: false, message: 'Invalid scoped token' });
        return;
      }
      // Attach scoped context for the handler to validate IDs.
      (req as any).photoUploadScoped = scopedPayload;
      // Skip requirePermission — scoped tokens carry their own authorization.
      next();
      return;
    }

    // Fall through to normal staff-auth flow.
    next();
  },
  // Normal staff auth (no-op when scoped token already attached).
  (req: Request, res: Response, next: NextFunction) => {
    if ((req as any).photoUploadScoped) { next(); return; }
    requirePermission('tickets.edit')(req, res, next);
  },
  enforceUploadQuota,
  upload.array('photos', 20),
  fileUploadValidator({ allowedMimes: ALLOWED_MIMES }),
  asyncHandler(async (req: Request, res: Response) => {
    const adb = req.asyncDb;
    const ticketId = validateId(req.params.id, 'ticket id');
    if (!ticketId) throw new AppError('Invalid ticket ID');

    const existing = await adb.get<AnyRow>('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
    if (!existing) throw new AppError('Ticket not found', 404);

    const files = req.files as Express.Multer.File[];
    if (!files || files.length === 0) throw new AppError('No photos uploaded');

    // Multi-tenant storage quota enforcement — atomic check + reserve
    const totalSize = files.reduce((sum, f) => sum + (f.size ?? 0), 0);
    if (!reserveStorage(req.tenantId, totalSize, req.tenantLimits?.storageLimitMb ?? null)) {
      for (const f of files) {
        if (f?.path) { try { fs.unlinkSync(f.path); } catch {} }
      }
      res.status(403).json({
        success: false,
        upgrade_required: true,
        feature: 'storage_limit',
        message: `Storage limit (${req.tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for 30 GB storage.`,
      });
      return;
    }

    const { type, ticket_device_id, caption } = req.body;
    if (!ticket_device_id) throw new AppError('ticket_device_id is required');

    // AUDIT-WEB-002: if a scoped photo-upload token was used, verify the
    // ticket_device_id in the body matches what the token was minted for.
    const scoped = (req as any).photoUploadScoped as { ticket_id?: number; ticket_device_id?: number } | undefined;
    if (scoped) {
      const bodyDeviceId = parseInt(ticket_device_id, 10);
      if (scoped.ticket_id !== ticketId || scoped.ticket_device_id !== bodyDeviceId) {
        res.status(403).json({ success: false, message: 'Scoped token does not match this ticket/device' });
        return;
      }
    }

    const deviceRow = await adb.get<AnyRow>('SELECT id FROM ticket_devices WHERE id = ? AND ticket_id = ?', ticket_device_id, ticketId);
    if (!deviceRow) throw new AppError('Device does not belong to this ticket', 400);

    const photos: AnyRow[] = [];
    for (const file of files) {
      const result = await adb.run(`
        INSERT INTO ticket_photos (ticket_device_id, type, file_path, caption, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `, ticket_device_id, type || 'pre', file.filename, caption ?? null, now(), now());

      photos.push({
        id: result.lastInsertRowid,
        ticket_device_id: parseInt(ticket_device_id),
        type: type || 'pre',
        file_path: file.filename,
        caption: caption ?? null,
        created_at: now(),
      });
    }

    // AUDIT-WEB-002: scoped photo-upload tokens have no req.user — use a
    // sentinel user id of 0 for the history row so it's distinguishable.
    const actorId = req.user?.id ?? 0;
    await Promise.all([
      insertHistoryAsync(adb, ticketId, actorId, 'photo_added', `${files.length} photo(s) uploaded`),
      adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), ticketId),
    ]);

    res.status(201).json({ success: true, data: photos });
  }),
);

// ===================================================================
// DELETE /photos/:photoId - Delete photo
// ===================================================================
router.delete('/photos/:photoId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const photoId = validateId(req.params.photoId, 'photo id');
  if (!photoId) throw new AppError('Invalid photo ID');

  const photo = await adb.get<AnyRow>(`
    SELECT tp.*, td.ticket_id
    FROM ticket_photos tp
    JOIN ticket_devices td ON td.id = tp.ticket_device_id
    WHERE tp.id = ?
  `, photoId);
  if (!photo) throw new AppError('Photo not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, photo.ticket_id, req.user?.role);

  // Try to delete the file — account for tenant slug in multi-tenant setups.
  // Capture file size BEFORE delete so we can refund storage quota.
  const tenantSlug = (req as any).tenantSlug || '';
  const tenantUploadsRoot = path.resolve(config.uploadsPath, tenantSlug);
  const filePath = path.resolve(tenantUploadsRoot, photo.file_path);
  if (!filePath.startsWith(tenantUploadsRoot + path.sep) && filePath !== tenantUploadsRoot) {
    logger.error('ticket photo path traversal attempt', {
      ticket_id: photo.ticket_id, file_path: photo.file_path, resolved: filePath,
    });
    throw new AppError('invalid photo path', 400);
  }
  let deletedBytes = 0;
  try {
    const stat = fs.statSync(filePath);
    deletedBytes = stat.size;
  } catch { /* file may not exist on disk */ }
  try { fs.unlinkSync(filePath); } catch { /* file may not exist */ }

  // Refund storage quota for the deleted file
  if (deletedBytes > 0) {
    decrementStorageBytes(req.tenantId, deletedBytes);
  }
  // Decrement the per-tenant file-count sentinel so the F4 quota stays accurate.
  releaseFileCount(req, 1);

  await Promise.all([
    adb.run('DELETE FROM ticket_photos WHERE id = ?', photoId),
    insertHistoryAsync(adb, photo.ticket_id, req.user!.id, 'photo_deleted', 'Photo deleted'),
  ]);

  res.json({ success: true, data: { id: photoId } });
}));

// ===================================================================
// POST /:id/convert-to-invoice - Generate invoice from ticket
// ===================================================================
// SEC-H25: creating an invoice from a ticket requires both tickets.edit and
// invoices.create permissions. Use tickets.edit as the gating permission since
// the caller must have edit access on the source ticket.
router.post('/:id/convert-to-invoice', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for allocateCounter (sync better-sqlite3 handle)
  const ticketId = validateId(req.params.id, 'ticket id');
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = await adb.get<AnyRow>('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  // Block conversion for cancelled tickets
  const ticketStatus = await adb.get<AnyRow>('SELECT is_cancelled FROM ticket_statuses WHERE id = ?', ticket.status_id);
  if (ticketStatus?.is_cancelled) {
    throw new AppError('Cannot convert a cancelled ticket to an invoice', 400);
  }

  // Check if invoice already exists (via ticket.invoice_id or direct lookup)
  const existingInvoice = ticket.invoice_id
    ? await adb.get<AnyRow>('SELECT id FROM invoices WHERE id = ?', ticket.invoice_id)
    : await adb.get<AnyRow>('SELECT id FROM invoices WHERE ticket_id = ?', ticketId);
  if (existingInvoice) throw new AppError('Ticket already has an invoice');

  const devices = await adb.all<AnyRow>('SELECT * FROM ticket_devices WHERE ticket_id = ?', ticketId);

  // I5: Atomic counter allocation — single source of truth, no MAX() race.
  // Falls back to the legacy MAX query if the counters table isn't present
  // (older tenant DBs that haven't run migration 072 yet).
  let invoiceOrderId: string;
  try {
    const nextSeq = allocateCounter(db, 'invoice_order_id');
    invoiceOrderId = formatInvoiceOrderId(nextSeq);
  } catch {
    const seqRow = await adb.get<AnyRow>("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices");
    invoiceOrderId = generateOrderId('INV', seqRow!.next_num);
  }

  const invResult = await adb.run(`
    INSERT INTO invoices (order_id, ticket_id, customer_id, status, subtotal, discount, discount_reason,
                          total_tax, total, amount_paid, amount_due, notes, created_by, created_at, updated_at)
    VALUES (?, ?, ?, 'unpaid', ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?)
  `,
    invoiceOrderId, ticketId, ticket.customer_id,
    ticket.subtotal, ticket.discount, ticket.discount_reason,
    ticket.total_tax, ticket.total, ticket.total,
    `Generated from ticket ${ticket.order_id}`,
    userId, now(), now(),
  );

  const invoiceId = Number(invResult.lastInsertRowid);

  // SW-D10: Read repair pricing settings
  const [itemizeSetting, priceIncludesPartsSetting] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_itemize_line_items'"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_price_includes_parts'"),
  ]);
  const itemizeLineItems = itemizeSetting?.value === '1' || itemizeSetting?.value === 'true';
  const priceIncludesParts = priceIncludesPartsSetting?.value === '1' || priceIncludesPartsSetting?.value === 'true';

  // Create line items from devices
  for (const dev of devices) {
    if (itemizeLineItems) {
      // Itemized: each device service as separate line item
      await adb.run(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                        line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
        VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
      `,
        invoiceId, dev.service_id, `${dev.device_name} - Service`, dev.price,
        dev.line_discount, dev.tax_amount, dev.tax_class_id, dev.total, now(), now(),
      );
    } else {
      // Non-itemized: single combined "Repair" line per device
      await adb.run(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                        line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
        VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
      `,
        invoiceId, dev.service_id, `Repair: ${dev.device_name}`, dev.price,
        dev.line_discount, dev.tax_amount, dev.tax_class_id, dev.total, now(), now(),
      );
    }

    // Add parts as line items only if price does NOT already include parts
    if (!priceIncludesParts) {
      const parts = await adb.all<AnyRow>(`
        SELECT tdp.*, ii.name AS item_name
        FROM ticket_device_parts tdp
        LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
        WHERE tdp.ticket_device_id = ?
      `, dev.id);

      if (itemizeLineItems) {
        // Itemized: each part as a separate line item
        for (const part of parts) {
          const lineTotal = roundCurrency(part.quantity * part.price);
          await adb.run(`
            INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                            line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 0, 0, NULL, ?, ?, ?)
          `, invoiceId, part.inventory_item_id, `Part: ${part.item_name || 'Unknown'}`, part.quantity, part.price, lineTotal, now(), now());
        }
      }
      // When not itemized: parts omitted from line items (single "Repair" line covers service,
      // parts totals are already in the ticket total)
    }
  }

  // Link invoice to ticket
  await adb.run('UPDATE tickets SET invoice_id = ?, updated_at = ? WHERE id = ?', invoiceId, now(), ticketId);

  // F4: Auto-close ticket on invoice creation if setting enabled
  const autoClose = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_auto_close_on_invoice'");
  if (autoClose?.value === '1' || autoClose?.value === 'true') {
    const closedStatus = await adb.get<AnyRow>("SELECT id FROM ticket_statuses WHERE is_closed = 1 ORDER BY sort_order LIMIT 1");
    if (closedStatus) {
      await adb.run('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?', closedStatus.id, now(), ticketId);
      await insertHistoryAsync(adb, ticketId, userId, 'status_changed', `Auto-closed on invoice creation`);
    }
  }

  // F5: Auto-remove passcode on close
  const autoRemovePasscode = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_auto_remove_passcode'");
  if (autoRemovePasscode?.value === '1' || autoRemovePasscode?.value === 'true') {
    await adb.run('UPDATE ticket_devices SET security_code = NULL WHERE ticket_id = ?', ticketId);
  }

  await insertHistoryAsync(adb, ticketId, userId, 'invoice_created', `Invoice ${invoiceOrderId} created from ticket`);

  const [invoice, lineItems] = await Promise.all([
    adb.get<AnyRow>(`
      SELECT i.*, c.first_name, c.last_name, c.email, c.phone
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customer_id
      WHERE i.id = ?
    `, invoiceId),
    adb.all<AnyRow>('SELECT * FROM invoice_line_items WHERE invoice_id = ?', invoiceId),
  ]);

  res.status(201).json({
    success: true,
    data: {
      ...invoice,
      customer: { id: invoice!.customer_id, first_name: invoice!.first_name, last_name: invoice!.last_name, email: invoice!.email, phone: invoice!.phone },
      line_items: lineItems,
    },
  });
}));

// ===================================================================
// GET /:id/history - Ticket activity history
// ===================================================================
router.get('/:id/history', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = await adb.get<AnyRow>('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  const historyRows = await adb.all<AnyRow>(`
    SELECT th.*, u.first_name, u.last_name
    FROM ticket_history th
    LEFT JOIN users u ON u.id = th.user_id
    WHERE th.ticket_id = ?
    ORDER BY th.created_at DESC
  `, ticketId);

  const history = historyRows.map((h) => ({
    ...h,
    user: h.user_id ? { id: h.user_id, first_name: h.first_name, last_name: h.last_name } : null,
  }));

  res.json({ success: true, data: history });
}));

// ===================================================================
// GET /:id/repair-time - Active repair time for a ticket
// ===================================================================
router.get('/:id/repair-time', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // calculateActiveRepairTime still uses sync db
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, ts.name AS status_name, ts.is_closed
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.id = ? AND t.is_deleted = 0
  `, ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const activeHours = calculateActiveRepairTime(db, ticketId);
  const totalHours = ticket.is_closed
    ? null
    : (Date.now() - new Date(ticket.created_at as string).getTime()) / (1000 * 60 * 60);

  const closeEvent = await adb.get<AnyRow>(`
    SELECT th.created_at FROM ticket_history th
    JOIN ticket_statuses ts ON ts.name = th.new_value
    WHERE th.ticket_id = ? AND th.action IN ('status_changed', 'status_change') AND ts.is_closed = 1
    ORDER BY th.created_at DESC LIMIT 1
  `, ticketId);

  const endTime = closeEvent
    ? new Date(closeEvent.created_at as string).getTime()
    : Date.now();
  const totalElapsedHours = (endTime - new Date(ticket.created_at as string).getTime()) / (1000 * 60 * 60);

  res.json({
    success: true,
    data: {
      ticket_id: ticketId,
      order_id: ticket.order_id,
      active_hours: activeHours ? Math.round(activeHours * 10) / 10 : null,
      total_elapsed_hours: Math.round(totalElapsedHours * 10) / 10,
      inactive_hours: activeHours != null
        ? Math.round((totalElapsedHours - activeHours) * 10) / 10
        : null,
      is_closed: !!ticket.is_closed,
    },
  });
}));

// ===================================================================
// POST /:id/devices - Add device to ticket
// ===================================================================
// SEC-H25: adding a device modifies the ticket — gate behind tickets.edit.
router.post('/:id/devices', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  // S5 fix: join ticket_statuses so we can block stock mutations on a ticket that
  // is already closed / delivered / cancelled. Without this guard a user can reopen
  // a closed ticket, add parts, and silently decrement inventory a second time.
  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.status_id, ts.name AS status_name, ts.is_closed, ts.is_cancelled
    FROM tickets t
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.id = ? AND t.is_deleted = 0
  `, ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const dev = req.body;
  const devicePrice = validatePrice(dev.price ?? 0, 'device price');
  const lineDiscount = dev.line_discount ?? 0;
  if (typeof lineDiscount !== 'number' || lineDiscount < 0 || lineDiscount > devicePrice) {
    throw new AppError('line_discount must be >= 0 and <= price', 400);
  }
  const resolvedTaxClassId = dev.tax_class_id ?? await getDefaultTaxClassIdAsync(adb, dev.item_type);
  // M10 fix: capture the tax-class warning so we can surface it on the response.
  const taxResult = await calcTaxWithWarningAsync(adb, devicePrice - lineDiscount, resolvedTaxClassId, dev.tax_inclusive ?? false);
  const taxAmount = taxResult.amount;
  const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

  // S5 fix: if the request tries to mutate stock on a closed/cancelled ticket, reject
  // BEFORE any writes. A device with no parts is still allowed to attach (informational).
  const hasParts = Array.isArray(dev.parts) && dev.parts.length > 0;
  if (hasParts && (ticket.is_closed || ticket.is_cancelled)) {
    throw new AppError(
      `Cannot add parts to a ticket in status "${ticket.status_name}" — reopen the ticket first`,
      409,
    );
  }

  const result = await adb.run(`
    INSERT INTO ticket_devices (ticket_id, device_name, device_type, imei, serial, security_code,
                                color, network, status_id, assigned_to, service_id, price, line_discount,
                                tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                due_on, device_location, additional_notes, pre_conditions, post_conditions,
                                created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
    ticketId,
    dev.device_name ?? '',
    dev.device_type ?? null,
    dev.imei ?? null,
    dev.serial ?? null,
    dev.security_code ?? null,
    dev.color ?? null,
    dev.network ?? null,
    dev.status_id ?? ticket.status_id,
    dev.assigned_to ?? null,
    dev.service_id ?? null,
    devicePrice,
    lineDiscount,
    taxAmount,
    resolvedTaxClassId,
    dev.tax_inclusive ? 1 : 0,
    deviceTotal,
    dev.warranty ? 1 : 0,
    dev.warranty_days ?? 0,
    dev.due_on ?? null,
    dev.device_location ?? null,
    dev.additional_notes ?? null,
    JSON.stringify(dev.pre_conditions ?? []),
    JSON.stringify(dev.post_conditions ?? []),
    now(),
    now(),
  );

  const deviceId = Number(result.lastInsertRowid);

  // Insert parts if provided. S2 fix: every part insert + stock decrement + movement
  // is now batched into a single atomic transaction. The UPDATE uses a guarded
  // `WHERE id = ? AND in_stock >= ?` clause; if the guard fails the worker throws
  // and the whole batch rolls back, so a double-click / retry can never double-deduct.
  if (hasParts) {
    const ts = now();
    const partsTx: TxQuery[] = [];
    for (const part of dev.parts) {
      const partQty = validateQuantity(part.quantity ?? 1, 'part quantity');
      const partPrice = validatePrice(part.price ?? 0, 'part price');

      partsTx.push({
        sql: `INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        params: [deviceId, part.inventory_item_id, partQty, partPrice, part.warranty ? 1 : 0, part.serial ?? null, ts, ts],
      });

      // S2 fix: guarded atomic decrement. expectChanges forces the whole tx to roll
      // back if another concurrent writer already claimed the stock.
      partsTx.push({
        sql: 'UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ? AND in_stock >= ?',
        params: [partQty, ts, part.inventory_item_id, partQty],
        expectChanges: true,
        expectChangesError: `Insufficient stock for ${part.name || `item ${part.inventory_item_id}`}: requested ${partQty}`,
      });

      partsTx.push({
        sql: `INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
              VALUES (?, 'ticket_usage', ?, 'ticket_device', ?, 'Part added to ticket device', ?, ?, ?)`,
        params: [part.inventory_item_id, -partQty, deviceId, userId, ts, ts],
      });
    }
    try {
      await adb.transaction(partsTx);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      // Remove the device we just inserted so the ticket is not left with a dangling device.
      try {
        await adb.run('DELETE FROM ticket_devices WHERE id = ?', deviceId);
      } catch (cleanupErr: unknown) {
        logger.error('failed to clean up ticket_device after stock transaction failure', {
          device_id: deviceId,
          ticket_id: ticketId,
          error: cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr),
        });
      }
      // Surface a 409 for stock conflicts (race or insufficient), 500 for anything else.
      if (msg.toLowerCase().includes('insufficient stock')) {
        throw new AppError(msg, 409);
      }
      throw err;
    }
  }

  await recalcTicketTotalsAsync(adb, ticketId);
  await insertHistoryAsync(adb, ticketId, userId, 'device_added', `Device added: ${dev.device_name || 'Unknown'}`);

  const device = await adb.get<AnyRow>('SELECT * FROM ticket_devices WHERE id = ?', deviceId);

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: ticketId }, req.tenantSlug || null);

  // M10 fix: if tax class was deleted/missing, flag it on the response so the
  // frontend can surface the warning to staff and a support engineer can investigate.
  const responsePayload: AnyRow = {
    ...device,
    pre_conditions: parseJsonCol(device!.pre_conditions, []),
    post_conditions: parseJsonCol(device!.post_conditions, []),
  };
  if (taxResult.warning) {
    responsePayload.tax_warning = taxResult.warning;
  }

  res.status(201).json({ success: true, data: responsePayload });
}));

// ===================================================================
// PUT /devices/:deviceId - Update device
// ===================================================================
router.put('/devices/:deviceId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const existing = await adb.get<AnyRow>('SELECT * FROM ticket_devices WHERE id = ?', deviceId);
  if (!existing) throw new AppError('Device not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, existing.ticket_id, req.user?.role);

  const allowedFields = [
    'device_name', 'device_type', 'imei', 'serial', 'security_code', 'color', 'network',
    'status_id', 'assigned_to', 'service_id', 'price', 'line_discount',
    'tax_class_id', 'tax_inclusive', 'warranty', 'warranty_days',
    'due_on', 'collected_date', 'device_location', 'additional_notes',
    'pre_conditions', 'post_conditions',
  ];

  const updates: string[] = [];
  const params: any[] = [];

  for (const field of allowedFields) {
    if (req.body[field] !== undefined) {
      let val = req.body[field];
      if (field === 'pre_conditions' || field === 'post_conditions') val = JSON.stringify(val);
      if (field === 'tax_inclusive' || field === 'warranty') val = val ? 1 : 0;
      updates.push(`${field} = ?`);
      params.push(val);
    }
  }

  if (updates.length === 0) throw new AppError('No valid fields to update');

  // Recalculate tax and total
  const price = req.body.price !== undefined ? validatePrice(req.body.price, 'device price') : existing.price;
  const lineDiscount = req.body.line_discount ?? existing.line_discount;
  if (typeof lineDiscount !== 'number' || lineDiscount < 0 || lineDiscount > price) {
    throw new AppError('line_discount must be >= 0 and <= price', 400);
  }
  const taxClassId = req.body.tax_class_id !== undefined ? req.body.tax_class_id : existing.tax_class_id;
  const taxInclusive = req.body.tax_inclusive !== undefined ? req.body.tax_inclusive : !!existing.tax_inclusive;
  const taxAmount = await calcTaxAsync(adb, price - lineDiscount, taxClassId, taxInclusive);
  const total = roundCurrency(price - lineDiscount + taxAmount);

  updates.push('tax_amount = ?', 'total = ?', 'updated_at = ?');
  params.push(taxAmount, total, now());
  params.push(deviceId);

  await adb.run(`UPDATE ticket_devices SET ${updates.join(', ')} WHERE id = ?`, ...params);

  await recalcTicketTotalsAsync(adb, existing.ticket_id);
  await insertHistoryAsync(adb, existing.ticket_id, userId, 'device_updated', `Device updated: ${req.body.device_name || existing.device_name}`);

  const device = await adb.get<AnyRow>('SELECT * FROM ticket_devices WHERE id = ?', deviceId);
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: existing.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: { ...device, pre_conditions: parseJsonCol(device!.pre_conditions, []), post_conditions: parseJsonCol(device!.post_conditions, []) } });
}));

// ===================================================================
// DELETE /devices/:deviceId - Remove device
// ===================================================================
router.delete('/devices/:deviceId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const existing = await adb.get<AnyRow>('SELECT id, ticket_id, device_name FROM ticket_devices WHERE id = ?', deviceId);
  if (!existing) throw new AppError('Device not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, existing.ticket_id, req.user?.role);

  // Snapshot the parts list before deletion so we can credit stock after.
  const parts = await adb.all<AnyRow>('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?', deviceId);

  // Delete photos from disk (tenant-scoped path)
  const tenantSlug = (req as any).tenantSlug || '';
  const uploadsBase = path.resolve(tenantSlug ? path.join(config.uploadsPath, tenantSlug) : config.uploadsPath);
  const photos = await adb.all<AnyRow>('SELECT file_path FROM ticket_photos WHERE ticket_device_id = ?', deviceId);
  for (const photo of photos) {
    const photoPath = path.resolve(uploadsBase, photo.file_path);
    if (!photoPath.startsWith(uploadsBase + path.sep) && photoPath !== uploadsBase) {
      logger.error('ticket device photo path traversal attempt', {
        device_id: deviceId, file_path: photo.file_path, resolved: photoPath,
      });
      continue;
    }
    try { fs.unlinkSync(photoPath); } catch { /* ignore */ }
  }

  // Delete the device first (CASCADE removes ticket_device_parts, ticket_photos,
  // ticket_checklists). Doing this atomically before stock credit means a second
  // concurrent delete of the same device gets 0 rows here and cannot double-credit
  // stock (double-credit race guard).
  const devDeleted = await adb.run('DELETE FROM ticket_devices WHERE id = ?', deviceId);
  if (devDeleted.changes === 0) {
    throw new AppError('Device not found (concurrent delete)', 409);
  }

  // Restore inventory for parts — runs after the device row is gone so no
  // second concurrent request can replay this credit path.
  for (const part of parts) {
    if (!part.inventory_item_id) continue;
    await adb.run('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?',
      part.quantity, now(), part.inventory_item_id);

    await adb.run(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
      VALUES (?, 'ticket_return', ?, 'ticket_device', ?, 'Device removed from ticket', ?, ?, ?)
    `, part.inventory_item_id, part.quantity, deviceId, userId, now(), now());
  }

  await recalcTicketTotalsAsync(adb, existing.ticket_id);
  await insertHistoryAsync(adb, existing.ticket_id, userId, 'device_removed', `Device removed: ${existing.device_name}`);

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: existing.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: { id: deviceId } });
}));

// ===================================================================
// POST /devices/:deviceId/parts - Add parts to device
// ===================================================================
// SEC-H25: adding parts modifies a ticket device — gate behind tickets.edit.
router.post('/devices/:deviceId/parts', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = await adb.get<AnyRow>('SELECT id, ticket_id FROM ticket_devices WHERE id = ?', deviceId);
  if (!device) throw new AppError('Device not found', 404);

  // SW-D1: Block adding inventory parts when ticket_show_inventory is disabled
  const showInventoryCfg = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_show_inventory'");
  if (showInventoryCfg?.value === '0') {
    throw new AppError('Inventory part selection is disabled', 403);
  }

  const { inventory_item_id, quantity, price, warranty, serial } = req.body;
  if (!inventory_item_id) throw new AppError('inventory_item_id is required');
  // @audit-fixed: validate quantity is a positive integer (validateQuantity rejects
  // NaN/floats/Infinity). Previously `quantity = "abc"` slipped past the falsy check.
  const safeQty = validateQuantity(quantity ?? 1, 'quantity');
  // @audit-fixed: validate price too — was being inserted with `price ?? 0` no checks.
  const safePrice = price !== undefined && price !== null ? validatePrice(price, 'price') : 0;

  const item = await adb.get<AnyRow>('SELECT id, name, in_stock, is_serialized FROM inventory_items WHERE id = ?', inventory_item_id);
  if (!item) throw new AppError('Inventory item not found', 404);
  if (item.in_stock < safeQty) {
    throw new AppError(`Insufficient stock for ${item.name}: ${item.in_stock} available, ${safeQty} needed`, 400);
  }

  // ENR-INV4: Serial number enforcement for serialized items
  if (item.is_serialized === 1 && !serial) {
    throw new AppError('Serial number required for serialized items', 400);
  }

  const result = await adb.run(`
    INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, deviceId, inventory_item_id, safeQty, safePrice, warranty ? 1 : 0, serial ?? null, now(), now());

  // @audit-fixed: guarded atomic decrement (S1 / S2 pattern). Without the guard
  // a concurrent sale could race the precheck and oversell to negative stock.
  const dec = await adb.run(
    'UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ? AND in_stock >= ?',
    safeQty, now(), inventory_item_id, safeQty,
  );
  if (dec.changes === 0) {
    // Revert the part insert so the device isn't left with a phantom row.
    await adb.run('DELETE FROM ticket_device_parts WHERE id = ?', result.lastInsertRowid);
    throw new AppError(`Insufficient stock for ${item.name} (concurrent update)`, 409);
  }

  // Stock movement
  const ticketRow = await adb.get<AnyRow>('SELECT order_id FROM tickets WHERE id = ?', device.ticket_id);
  await adb.run(`
    INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
    VALUES (?, 'ticket_usage', ?, 'ticket_device', ?, ?, ?, ?, ?)
  `, inventory_item_id, -safeQty, deviceId, `Part added to ticket ${ticketRow!.order_id}`, userId, now(), now());

  await recalcTicketTotalsAsync(adb, device.ticket_id);
  await insertHistoryAsync(adb, device.ticket_id, userId, 'part_added', `Part added: ${item.name} x${safeQty}`);

  const partId = Number(result.lastInsertRowid);
  const part = await adb.get<AnyRow>(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `, partId);

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: device.ticket_id }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: part });
}));

// ===================================================================
// POST /devices/:deviceId/quick-add-part - Create inventory item + add to device in one step
// ===================================================================
// SEC-H25: quick-add-part creates an inventory item + links it — gate behind
// tickets.edit (also requires inventory.create but we use tickets.edit as the
// primary gate since the caller must have ticket edit access).
router.post('/devices/:deviceId/quick-add-part', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = await adb.get<AnyRow>('SELECT id, ticket_id FROM ticket_devices WHERE id = ?', deviceId);
  if (!device) throw new AppError('Device not found', 404);

  const { name, price, quantity: rawQty } = req.body;
  if (!name || !name.trim()) throw new AppError('Name is required');
  // @audit-fixed: validatePrice rejects NaN/Infinity/negative; the previous
  // `Number(price) < 0` check accepted Infinity and NaN (NaN < 0 = false).
  const itemPrice = validatePrice(price ?? 0, 'price');
  const quantity = Math.max(1, parseInt(rawQty, 10) || 1);
  // @audit-fixed: cap quantity so a single quick-add can't allocate millions of units.
  if (quantity > 10_000) throw new AppError('quantity must be <= 10,000', 400);

  const sku = `QA-${Date.now()}`;

  // 1. Create inventory item
  const itemResult = await adb.run(`
    INSERT INTO inventory_items (name, sku, item_type, cost_price, retail_price, in_stock, created_at, updated_at)
    VALUES (?, ?, 'part', ?, ?, ?, ?, ?)
  `, name.trim(), sku, itemPrice, itemPrice, quantity, now(), now());
  const inventoryItemId = Number(itemResult.lastInsertRowid);

  // 2. Add part to device
  const partResult = await adb.run(`
    INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'available', ?, ?)
  `, deviceId, inventoryItemId, quantity, itemPrice, now(), now());

  // 3. Deduct stock — differential guard prevents double-spend if a
  // concurrent request somehow references this newly-created item before
  // this request completes (e.g. scanner racing a quick-add).
  const quickAddDec = await adb.run(
    'UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ? AND in_stock >= ?',
    quantity, now(), inventoryItemId, quantity,
  );
  if (quickAddDec.changes === 0) {
    // Revert the part insert so the device isn't left with a phantom row.
    await adb.run('DELETE FROM ticket_device_parts WHERE ticket_device_id = ? AND inventory_item_id = ?', deviceId, inventoryItemId);
    throw new AppError(`Insufficient stock for ${name.trim()} (concurrent update)`, 409);
  }

  // 4. Stock movement
  const ticketRow = await adb.get<AnyRow>('SELECT order_id FROM tickets WHERE id = ?', device.ticket_id);
  await adb.run(`
    INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
    VALUES (?, 'ticket_usage', ?, 'ticket_device', ?, ?, ?, ?, ?)
  `, inventoryItemId, -quantity, deviceId, `Quick-add part for ticket ${ticketRow!.order_id}`, userId, now(), now());

  await recalcTicketTotalsAsync(adb, device.ticket_id);
  await insertHistoryAsync(adb, device.ticket_id, userId, 'part_added', `Quick-added part: ${name.trim()} x${quantity} @ $${itemPrice.toFixed(2)}`);

  const partId = Number(partResult.lastInsertRowid);
  const part = await adb.get<AnyRow>(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `, partId);

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: device.ticket_id }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: part });
}));

// ===================================================================
// DELETE /devices/parts/:partId - Remove part from device
// ===================================================================
router.delete('/devices/parts/:partId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const partId = validateId(req.params.partId, 'part id');
  const userId = req.user!.id;
  if (!partId) throw new AppError('Invalid part ID');

  const part = await adb.get<AnyRow>(`
    SELECT tdp.*, td.ticket_id, ii.name AS item_name
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `, partId);
  if (!part) throw new AppError('Part not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, part.ticket_id, req.user?.role);

  // Return stock if it was deducted. DELETE the row first inside an
  // implicit SQLite serialised write so that a second concurrent DELETE
  // of the same partId finds 0 rows and short-circuits before crediting
  // stock a second time (double-credit race).
  const partDeleted = await adb.run('DELETE FROM ticket_device_parts WHERE id = ?', partId);
  if (partDeleted.changes === 0) {
    // Already deleted by a concurrent request — nothing to credit.
    throw new AppError('Part not found (concurrent delete)', 409);
  }

  if (part.inventory_item_id) {
    await adb.run('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?',
      part.quantity, now(), part.inventory_item_id);

    await adb.run(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
      VALUES (?, 'ticket_return', ?, 'ticket_device', ?, 'Part removed from ticket', ?, ?, ?)
    `, part.inventory_item_id, part.quantity, part.ticket_device_id, userId, now(), now());
  }
  await recalcTicketTotalsAsync(adb, part.ticket_id);
  await insertHistoryAsync(adb, part.ticket_id, userId, 'part_removed', `Part removed: ${part.item_name || 'Unknown'} x${part.quantity}`);

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: part.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: { id: partId } });
}));

// ===================================================================
// PATCH /devices/parts/:partId - Update part supplier linking
// ===================================================================
router.patch('/devices/parts/:partId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const partId = validateId(req.params.partId, 'part id');
  const userId = req.user!.id;
  if (!partId) throw new AppError('Invalid part ID');

  const part = await adb.get<AnyRow>(`
    SELECT tdp.*, td.ticket_id
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    WHERE tdp.id = ?
  `, partId);
  if (!part) throw new AppError('Part not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, part.ticket_id, req.user?.role);

  const { catalog_item_id, supplier_url, status } = req.body;

  const updates: string[] = [];
  const values: any[] = [];

  if (catalog_item_id !== undefined) {
    updates.push('catalog_item_id = ?');
    values.push(catalog_item_id);
  }
  if (supplier_url !== undefined) {
    updates.push('supplier_url = ?');
    values.push(supplier_url);
  }
  const validPartStatuses = ['available', 'missing', 'ordered', 'received'];
  if (status !== undefined) {
    if (!validPartStatuses.includes(status)) {
      throw new AppError(`Invalid status. Must be one of: ${validPartStatuses.join(', ')}`, 400);
    }
    updates.push('status = ?');
    values.push(status);
  }

  if (updates.length === 0) throw new AppError('No fields to update');

  updates.push('updated_at = ?');
  values.push(now());
  values.push(partId);

  await adb.run(`UPDATE ticket_device_parts SET ${updates.join(', ')} WHERE id = ?`, ...values);
  const historyMsg = status ? `Part status changed to ${status}` : 'Part supplier info updated';
  await insertHistoryAsync(adb, part.ticket_id, userId, 'part_updated', historyMsg);
  await adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), part.ticket_id);

  const updated = await adb.get<AnyRow>(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `, partId);

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: part.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: updated });
}));

// ===================================================================
// PUT /devices/:deviceId/checklist - Update checklist items
// ===================================================================
router.put('/devices/:deviceId/checklist', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = await adb.get<AnyRow>('SELECT id, ticket_id FROM ticket_devices WHERE id = ?', deviceId);
  if (!device) throw new AppError('Device not found', 404);

  // SEC-H16: reject mutation when parent ticket is closed/invoiced (admin bypass).
  await assertTicketMutable(adb, device.ticket_id, req.user?.role);

  const { items } = req.body;
  if (!items || !Array.isArray(items)) throw new AppError('items array is required');

  const existing = await adb.get<AnyRow>('SELECT id FROM ticket_checklists WHERE ticket_device_id = ?', deviceId);

  if (existing) {
    await adb.run('UPDATE ticket_checklists SET items = ?, updated_at = ? WHERE id = ?',
      JSON.stringify(items), now(), existing.id);
  } else {
    const template = await adb.get<AnyRow>('SELECT id FROM checklist_templates LIMIT 1');
    const templateId = template?.id ?? 1;
    await adb.run(`
      INSERT INTO ticket_checklists (ticket_device_id, checklist_template_id, items, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `, deviceId, templateId, JSON.stringify(items), now(), now());
  }

  await Promise.all([
    insertHistoryAsync(adb, device.ticket_id, req.user!.id, 'checklist_updated', 'Checklist updated'),
    adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), device.ticket_id),
  ]);

  const checklist = (await adb.get<AnyRow>('SELECT * FROM ticket_checklists WHERE ticket_device_id = ?', deviceId))!;

  res.json({ success: true, data: { ...checklist, items: parseJsonCol(checklist.items, []) } });
}));

// ===================================================================
// POST /devices/:deviceId/loaner - Assign loaner device
// ===================================================================
// SEC-H25: assigning/returning a loaner modifies inventory state — gate behind
// tickets.edit as the caller must have ticket edit access.
router.post('/devices/:deviceId/loaner', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = await adb.get<AnyRow>('SELECT td.id, td.ticket_id, t.customer_id FROM ticket_devices td JOIN tickets t ON t.id = td.ticket_id WHERE td.id = ?', deviceId);
  if (!device) throw new AppError('Device not found', 404);

  const { loaner_device_id } = req.body;
  if (!loaner_device_id) throw new AppError('loaner_device_id is required');

  const loaner = await adb.get<AnyRow>("SELECT * FROM loaner_devices WHERE id = ? AND status = 'available'", loaner_device_id);
  if (!loaner) throw new AppError('Loaner device not available', 400);

  // Mark loaner as loaned
  await adb.run("UPDATE loaner_devices SET status = 'loaned', updated_at = ? WHERE id = ?", now(), loaner_device_id);

  // Insert loaner history
  await adb.run(`
    INSERT INTO loaner_history (loaner_device_id, ticket_device_id, customer_id, loaned_at, condition_out)
    VALUES (?, ?, ?, ?, ?)
  `, loaner_device_id, deviceId, device.customer_id, now(), loaner.condition);

  // Link to ticket device
  await adb.run('UPDATE ticket_devices SET loaner_device_id = ?, updated_at = ? WHERE id = ?', loaner_device_id, now(), deviceId);

  await insertHistoryAsync(adb, device.ticket_id, userId, 'loaner_assigned', `Loaner device assigned: ${loaner.name}`);
  await adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), device.ticket_id);

  res.status(201).json({ success: true, data: { loaner_device_id, device_id: deviceId, loaner_name: loaner.name } });
}));

// ===================================================================
// DELETE /devices/:deviceId/loaner - Return loaner device
// ===================================================================
// SEC-H25: returning a loaner modifies inventory state — gate behind tickets.edit.
router.delete('/devices/:deviceId/loaner', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = validateId(req.params.deviceId, 'device id');
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = await adb.get<AnyRow>('SELECT id, ticket_id, loaner_device_id FROM ticket_devices WHERE id = ?', deviceId);
  if (!device) throw new AppError('Device not found', 404);
  if (!device.loaner_device_id) throw new AppError('No loaner device assigned', 400);

  // Mark loaner as available
  await adb.run("UPDATE loaner_devices SET status = 'available', updated_at = ? WHERE id = ?", now(), device.loaner_device_id);

  // Update loaner history
  await adb.run(`
    UPDATE loaner_history SET returned_at = ?, condition_in = ?
    WHERE loaner_device_id = ? AND ticket_device_id = ? AND returned_at IS NULL
  `, now(), req.body.condition_in ?? null, device.loaner_device_id, deviceId);

  // Unlink from ticket device
  await adb.run('UPDATE ticket_devices SET loaner_device_id = NULL, updated_at = ? WHERE id = ?', now(), deviceId);

  await insertHistoryAsync(adb, device.ticket_id, userId, 'loaner_returned', 'Loaner device returned');
  await adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), device.ticket_id);

  res.json({ success: true, data: { device_id: deviceId } });
}));

// ---------------------------------------------------------------------------
// OTP verify rate limit constants (5 attempts per 15 minutes per IP+ticket)
// ---------------------------------------------------------------------------
const OTP_RATE_LIMIT = 5;
const OTP_RATE_WINDOW = 15 * 60 * 1000; // 15 minutes

// ===================================================================
// POST /:id/otp - Generate OTP
// ===================================================================
// SEC-H25: generating an OTP for a customer is a ticket write operation.
router.post('/:id/otp', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, c.phone, c.mobile
    FROM tickets t
    JOIN customers c ON c.id = t.customer_id
    WHERE t.id = ? AND t.is_deleted = 0
  `, ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const { ticket_device_id } = req.body;
  if (!ticket_device_id) throw new AppError('ticket_device_id is required');

  const code = String(crypto.randomInt(100000, 999999));
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString().replace('T', ' ').substring(0, 19);
  const phone = ticket.mobile || ticket.phone;

  await adb.run(`
    INSERT INTO device_otps (ticket_id, ticket_device_id, code, phone, expires_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `, ticketId, ticket_device_id, code, phone, expiresAt, now(), now());

  // Send OTP via SMS
  try {
    const { sendSms } = await import('../services/smsProvider.js');
    await sendSms(phone, `Your verification code for ticket T-${ticketId} is: ${code}. It expires in 15 minutes.`);
  } catch (err) {
    // Log failure but do not expose to client — OTP is stored, staff can resend
    logger.error('[OTP] Failed to send SMS', { toRedacted: redactPhone(phone), error: (err as Error).message });
  }

  // Never return the OTP code in the response — it should only be sent via SMS
  res.status(201).json({ success: true, data: { expires_at: expiresAt, phone, message: 'OTP sent via SMS' } });
}));

// ===================================================================
// POST /:id/verify-otp - Verify OTP
// ===================================================================
router.post('/:id/verify-otp', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!ticketId) throw new AppError('Invalid ticket ID');

  // Rate limit: 5 attempts per 15 minutes per IP+ticket
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const rateLimitKey = `${ip}:${ticketId}`;
  if (!checkWindowRate(req.db, 'otp_verify', rateLimitKey, OTP_RATE_LIMIT, OTP_RATE_WINDOW)) {
    throw new AppError('Too many OTP verification attempts. Try again later.', 429);
  }
  recordWindowFailure(req.db, 'otp_verify', rateLimitKey, OTP_RATE_WINDOW);

  const { code } = req.body;
  if (!code) throw new AppError('code is required');

  const otp = await adb.get<AnyRow>(`
    SELECT * FROM device_otps
    WHERE ticket_id = ? AND code = ? AND is_verified = 0 AND expires_at > datetime('now')
    ORDER BY created_at DESC
    LIMIT 1
  `, ticketId, code);

  if (!otp) throw new AppError('Invalid or expired OTP', 400);

  await Promise.all([
    adb.run('UPDATE device_otps SET is_verified = 1, updated_at = ? WHERE id = ?', now(), otp.id),
    insertHistoryAsync(adb, ticketId, req.user?.id ?? null, 'otp_verified', 'OTP verified successfully'),
  ]);

  res.json({ success: true, data: { verified: true, ticket_device_id: otp.ticket_device_id } });
}));

// ===================================================================
// POST /bulk-action - Bulk actions on tickets
// ===================================================================
// SEC-H25: bulk actions (change_status, assign, delete) require elevated access.
router.post('/bulk-action', requirePermission('tickets.bulk_update'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for calculateActiveRepairTime, notifications
  const userId = req.user!.id;
  const { ticket_ids, action, value } = req.body;

  if (!ticket_ids || !Array.isArray(ticket_ids) || ticket_ids.length === 0) {
    throw new AppError('ticket_ids array is required');
  }
  if (ticket_ids.length > 100) {
    throw new AppError('ticket_ids must be an array of at most 100 IDs', 400);
  }
  if (!action) throw new AppError('action is required');

  const validActions = ['change_status', 'assign', 'delete'];
  if (!validActions.includes(action)) throw new AppError(`Invalid action. Must be one of: ${validActions.join(', ')}`);

  const affected: number[] = [];

  // Pre-fetch status metadata once — only notify_customer + name are still
  // needed (for the customer-notification SMS fire after the bulk helper call).
  // The post-condition / parts / stopwatch / diagnostic guards are re-fetched
  // per ticket inside applyTicketStatusChange(), so this is the only surviving
  // pre-fetch since the SEC-H68/H122 refactor.
  let newStatusRow: AnyRow | undefined;

  if (action === 'change_status') {
    if (!value) throw new AppError('value (status_id) is required for change_status');
    const newSt = await adb.get<AnyRow>(
      'SELECT name, notify_customer, is_closed, is_cancelled FROM ticket_statuses WHERE id = ?',
      value,
    );
    if (!newSt) throw new AppError(`Status ${value} not found`, 404);
    newStatusRow = newSt;
  }

  for (const id of ticket_ids) {
    const ticket = await adb.get<AnyRow>('SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0', id);
    if (!ticket) continue;

    switch (action) {
      case 'change_status': {
        // SEC-H68 / SEC-H122: bulk status change delegates to the shared
        // applyTicketStatusChange() helper so every guard (post-conditions,
        // required parts, stopwatch, diagnostic note, state machine), the
        // atomic UPDATE, device-status sync, commission accrual (UNIQUE-index
        // protected), history row, WebSocket broadcast, webhook fire, and
        // automation re-trigger all run identically to the single-ticket path
        // and the automation engine. AppError guard rejections are re-wrapped
        // with per-ticket context so the bulk caller sees which ticket failed.
        try {
          await applyTicketStatusChange(db, id, value, userId, req.tenantSlug || null);
        } catch (err) {
          if (err instanceof AppError) {
            throw new AppError(`Ticket ${id}: ${err.message}`, err.statusCode ?? 400);
          }
          throw err;
        }

        // Customer notification SMS stays in the route: needs req.tenantSlug
        // and the notification retry queue (same pattern as PATCH /:id/status).
        if (newStatusRow!.notify_customer) {
          const bulkTicketId = id;
          const bulkStatusName = newStatusRow!.name;
          import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
            return sendTicketStatusNotification(db, { ticketId: bulkTicketId, statusName: bulkStatusName, tenantSlug: req.tenantSlug || null });
          }).catch((e: unknown) => {
            logger.error('bulk-status notification hook failed', {
              ticket_id: bulkTicketId,
              status_name: bulkStatusName,
              error: e instanceof Error ? e.message : String(e),
            });
            enqueueTicketNotificationRetry(db, bulkTicketId, bulkStatusName, req.tenantSlug || null, e);
          });
        }
        affected.push(id);
        break;
      }
      case 'assign': {
        await adb.run('UPDATE tickets SET assigned_to = ?, updated_at = ? WHERE id = ?', value ?? null, now(), id);
        await insertHistoryAsync(adb, id, userId, 'assigned', value ? `Bulk assigned to user ${value}` : 'Bulk unassigned');
        affected.push(id);
        break;
      }
      case 'delete': {
        if (req.user?.role !== 'admin') throw new AppError('Only admins can bulk delete', 403);

        // Atomically claim the soft-delete before crediting stock — same
        // double-credit race guard as the single-delete path (SEC-H62).
        // If two concurrent bulk-delete requests include the same ticket id,
        // only the one that wins the CAS here will restore stock.
        const bulkClaimed = await adb.run(
          'UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ? AND is_deleted = 0',
          now(), id,
        );
        if (bulkClaimed.changes === 0) {
          // Already deleted — skip stock credit for this ticket.
          break;
        }

        // Restore inventory stock for all parts on all devices in this ticket
        const devices = await adb.all<AnyRow>('SELECT id FROM ticket_devices WHERE ticket_id = ?', id);
        for (const dev of devices) {
          const parts = await adb.all<AnyRow>('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?', dev.id);
          for (const part of parts) {
            if (part.inventory_item_id) {
              await adb.run('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?',
                part.quantity, now(), part.inventory_item_id);

              await adb.run(`
                INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
                VALUES (?, 'ticket_return', ?, 'ticket', ?, 'Stock restored — ticket bulk deleted', ?, ?, ?)
              `, part.inventory_item_id, part.quantity, id, userId, now(), now());
            }
          }
        }

        await insertHistoryAsync(adb, id, userId, 'deleted', 'Bulk deleted');
        affected.push(id);
        break;
      }
    }
  }

  if (action === 'delete') {
    for (const id of affected) broadcast(WS_EVENTS.TICKET_DELETED, { id }, req.tenantSlug || null);
  } else {
    for (const id of affected) broadcast(WS_EVENTS.TICKET_UPDATED, { id }, req.tenantSlug || null);
  }

  res.json({ success: true, data: { affected: affected.length, ticket_ids: affected } });
}));

// ===================================================================
// GET /:id/feedback - Get feedback for a ticket
// ===================================================================
router.get('/:id/feedback', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // @audit-fixed: validate id (NaN was silently flowing into SQL)
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!Number.isInteger(ticketId) || ticketId <= 0) throw new AppError('Invalid ticket ID', 400);
  const feedback = await adb.all<AnyRow>('SELECT * FROM customer_feedback WHERE ticket_id = ? ORDER BY created_at DESC', ticketId);
  res.json({ success: true, data: feedback });
}));

// ===================================================================
// POST /:id/feedback - Submit feedback for a ticket
// ===================================================================
router.post('/:id/feedback', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // @audit-fixed: validate id
  const ticketId = validateId(req.params.id, 'ticket id');
  if (!Number.isInteger(ticketId) || ticketId <= 0) throw new AppError('Invalid ticket ID', 400);
  const { rating, comment, source = 'web' } = req.body;

  const [feedbackCfg, ticket] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'feedback_enabled'"),
    adb.get<AnyRow>('SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId),
  ]);

  if (feedbackCfg?.value === '0' || feedbackCfg?.value === 'false') {
    throw new AppError('Feedback is disabled', 400);
  }
  // @audit-fixed: enforce integer rating in [1,5]. Previously NaN > 5 = false slipped past
  // the bounds check, and the value got bound to SQLite as TEXT which broke AVG() reports.
  const ratingNum = Number(rating);
  if (!Number.isInteger(ratingNum) || ratingNum < 1 || ratingNum > 5) {
    throw new AppError('Rating must be an integer 1-5', 400);
  }
  if (!ticket) throw new AppError('Ticket not found', 404);

  const result = await adb.run(`
    INSERT INTO customer_feedback (ticket_id, customer_id, rating, comment, source, responded_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, ticketId, ticket.customer_id, ratingNum, comment || null, source, now(), now(), now());

  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// ===================================================================
// POST /:id/appointment - Create appointment linked to this ticket
// ===================================================================
// SEC-H25: creating an appointment modifies the ticket — gate behind tickets.edit.
router.post('/:id/appointment', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');
  const { start_time, end_time, note, location_id: rawLocationId } = req.body;

  if (!start_time) throw new AppError('start_time is required', 400);

  // Validate and resolve location_id; default to 1.
  let resolvedLocationId = 1;
  if (rawLocationId !== undefined && rawLocationId !== null) {
    const parsed = Number(rawLocationId);
    if (!Number.isInteger(parsed) || parsed < 1) {
      throw new AppError('location_id must be a positive integer', 400);
    }
    resolvedLocationId = parsed;
  }

  const ticket = await adb.get<AnyRow>('SELECT id, customer_id, order_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const title = `Ticket #${ticket.order_id} appointment`;

  const result = await adb.run(`
    INSERT INTO appointments (ticket_id, customer_id, title, start_time, end_time, assigned_to, status, notes, location_id)
    VALUES (?, ?, ?, ?, ?, ?, 'scheduled', ?, ?)
  `,
    ticketId,
    ticket.customer_id,
    title,
    start_time,
    end_time || null,
    req.user!.id,
    note || null,
    resolvedLocationId,
  );

  const [appointment] = await Promise.all([
    adb.get<AnyRow>('SELECT * FROM appointments WHERE id = ?', result.lastInsertRowid),
    insertHistoryAsync(adb, ticketId, req.user!.id, 'appointment_created', `Appointment scheduled for ${start_time}`),
  ]);

  res.status(201).json({ success: true, data: appointment });
}));

// ===================================================================
// GET /:id/appointments - List appointments for this ticket
// ===================================================================
router.get('/:id/appointments', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');

  const ticket = await adb.get<AnyRow>('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const appointments = await adb.all<AnyRow>(`
    SELECT a.*, u.first_name AS assigned_first, u.last_name AS assigned_last
    FROM appointments a
    LEFT JOIN users u ON u.id = a.assigned_to
    WHERE a.ticket_id = ?
    ORDER BY a.start_time ASC
  `, ticketId);

  res.json({ success: true, data: appointments });
}));

// ===================================================================
// POST /merge - Merge two tickets (admin-only)
// ===================================================================
// SEC-H25: ticket merge is a destructive bulk operation — gate behind
// tickets.bulk_update permission. The inline role check below is kept as
// defence-in-depth for deployments whose custom-role matrix doesn't restrict
// this permission (admin always passes requirePermission due to SEC-H18 bypass).
router.post('/merge', requirePermission('tickets.bulk_update'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for audit helper
  const userId = req.user!.id;

  // Admin bypass — matches the hard admin bypass in requirePermission().
  if (req.user!.role !== 'admin') {
    throw new AppError('Only admins can merge tickets', 403);
  }

  const { keep_id, merge_id } = req.body;
  if (!keep_id || !merge_id) throw new AppError('keep_id and merge_id are required', 400);
  if (keep_id === merge_id) throw new AppError('Cannot merge a ticket with itself', 400);

  const [keepTicket, mergeTicket] = await Promise.all([
    adb.get<AnyRow>('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0', keep_id),
    adb.get<AnyRow>('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0', merge_id),
  ]);
  if (!keepTicket) throw new AppError('Keep ticket not found', 404);
  if (!mergeTicket) throw new AppError('Merge ticket not found', 404);

  // Move all devices from merge_id to keep_id
  await adb.run('UPDATE ticket_devices SET ticket_id = ?, updated_at = ? WHERE ticket_id = ?',
    keep_id, now(), merge_id);

  // Move all notes
  await adb.run('UPDATE ticket_notes SET ticket_id = ? WHERE ticket_id = ?',
    keep_id, merge_id);

  // Move all history entries
  await adb.run('UPDATE ticket_history SET ticket_id = ? WHERE ticket_id = ?',
    keep_id, merge_id);

  // Move all photos (ticket-level, not device-level -- device photos moved with devices)
  await adb.run('UPDATE ticket_photos SET ticket_id = ? WHERE ticket_id = ? AND ticket_device_id IS NULL',
    keep_id, merge_id);

  // Move any ticket_links referencing merge_id
  await adb.run('UPDATE ticket_links SET ticket_id_a = ? WHERE ticket_id_a = ?',
    keep_id, merge_id);
  await adb.run('UPDATE ticket_links SET ticket_id_b = ? WHERE ticket_id_b = ?',
    keep_id, merge_id);
  // Remove self-links that may have resulted
  await adb.run('DELETE FROM ticket_links WHERE ticket_id_a = ticket_id_b');

  // Recalculate totals on keep ticket
  await recalcTicketTotalsAsync(adb, keep_id);

  // Soft-delete the merged ticket
  await adb.run('UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ?',
    now(), merge_id);

  // History on keep ticket
  await insertHistoryAsync(adb, keep_id, userId, 'merged',
    `Merged ticket #${mergeTicket.order_id} (ID ${merge_id}) into this ticket`);

  // History on merged ticket
  await insertHistoryAsync(adb, merge_id, userId, 'merged',
    `Merged into ticket #${keepTicket.order_id} (ID ${keep_id})`);

  // Audit log
  audit(db, 'ticket_merged', userId, (req as any).ip || 'unknown', {
    keep_id, merge_id,
    keep_order_id: keepTicket.order_id,
    merge_order_id: mergeTicket.order_id,
  });

  const ticket = await getFullTicketAsync(adb, keep_id);
  broadcast(WS_EVENTS.TICKET_UPDATED, ticket, req.tenantSlug || null);
  broadcast(WS_EVENTS.TICKET_DELETED, { id: merge_id }, req.tenantSlug || null);

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// POST /:id/link - Link two tickets
// ===================================================================
// SEC-H25: linking tickets modifies both tickets — gate behind tickets.edit.
router.post('/:id/link', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const ticketId = validateId(req.params.id, 'ticket id');

  const { linked_ticket_id, link_type = 'related' } = req.body;
  if (!linked_ticket_id) throw new AppError('linked_ticket_id is required', 400);
  if (ticketId === linked_ticket_id) throw new AppError('Cannot link a ticket to itself', 400);

  const validLinkTypes = ['related', 'duplicate', 'warranty_followup'];
  if (!validLinkTypes.includes(link_type)) {
    throw new AppError(`Invalid link_type. Must be one of: ${validLinkTypes.join(', ')}`, 400);
  }

  const [ticket, linkedTicket, existing] = await Promise.all([
    adb.get<AnyRow>('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId),
    adb.get<AnyRow>('SELECT id, order_id FROM tickets WHERE id = ? AND is_deleted = 0', linked_ticket_id),
    adb.get<AnyRow>(
      'SELECT id FROM ticket_links WHERE (ticket_id_a = ? AND ticket_id_b = ?) OR (ticket_id_a = ? AND ticket_id_b = ?)',
      ticketId, linked_ticket_id, linked_ticket_id, ticketId
    ),
  ]);
  if (!ticket) throw new AppError('Ticket not found', 404);
  if (!linkedTicket) throw new AppError('Linked ticket not found', 404);
  if (existing) throw new AppError('These tickets are already linked', 409);

  const idA = Math.min(ticketId, linked_ticket_id);
  const idB = Math.max(ticketId, linked_ticket_id);

  const result = await adb.run(
    'INSERT INTO ticket_links (ticket_id_a, ticket_id_b, link_type, created_by) VALUES (?, ?, ?, ?)',
    idA, idB, link_type, userId
  );

  const [link] = await Promise.all([
    adb.get<AnyRow>('SELECT * FROM ticket_links WHERE id = ?', result.lastInsertRowid),
    insertHistoryAsync(adb, ticketId, userId, 'linked', `Linked to ticket #${linkedTicket.order_id} (${link_type})`),
  ]);

  res.status(201).json({ success: true, data: link });
}));

// ===================================================================
// GET /:id/links - Get linked tickets
// ===================================================================
router.get('/:id/links', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = validateId(req.params.id, 'ticket id');

  const ticket = await adb.get<AnyRow>('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const links = await adb.all<AnyRow>(`
    SELECT tl.*,
           CASE WHEN tl.ticket_id_a = ? THEN tl.ticket_id_b ELSE tl.ticket_id_a END AS linked_ticket_id,
           t.order_id AS linked_order_id,
           t.status_id AS linked_status_id,
           ts.name AS linked_status_name,
           ts.color AS linked_status_color,
           c.first_name AS linked_customer_first,
           c.last_name AS linked_customer_last,
           t.created_at AS linked_created_at,
           u.first_name AS created_by_first,
           u.last_name AS created_by_last
    FROM ticket_links tl
    JOIN tickets t ON t.id = CASE WHEN tl.ticket_id_a = ? THEN tl.ticket_id_b ELSE tl.ticket_id_a END
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN users u ON u.id = tl.created_by
    WHERE (tl.ticket_id_a = ? OR tl.ticket_id_b = ?) AND t.is_deleted = 0
    ORDER BY tl.created_at DESC
  `, ticketId, ticketId, ticketId, ticketId);

  const shaped = links.map((l) => ({
    id: l.id,
    link_type: l.link_type,
    linked_ticket_id: l.linked_ticket_id,
    linked_order_id: l.linked_order_id,
    linked_status: { id: l.linked_status_id, name: l.linked_status_name, color: l.linked_status_color },
    linked_customer: { first_name: l.linked_customer_first, last_name: l.linked_customer_last },
    linked_created_at: l.linked_created_at,
    created_by: l.created_by ? { first_name: l.created_by_first, last_name: l.created_by_last } : null,
    created_at: l.created_at,
  }));

  res.json({ success: true, data: shaped });
}));

// ===================================================================
// DELETE /links/:linkId - Remove a ticket link
// ===================================================================
// SEC-H25: removing a ticket link modifies both tickets — gate behind tickets.edit.
router.delete('/links/:linkId', requirePermission('tickets.edit'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const linkId = validateId(req.params.linkId, 'linkId');

  const link = await adb.get<AnyRow>('SELECT * FROM ticket_links WHERE id = ?', linkId);
  if (!link) throw new AppError('Link not found', 404);

  await adb.run('DELETE FROM ticket_links WHERE id = ?', linkId);

  res.json({ success: true, data: { message: 'Link removed' } });
}));

// ===================================================================
// POST /:id/clone-warranty - Clone ticket as warranty case
// ===================================================================
// SEC-H25: cloning a ticket creates a new ticket — gate behind tickets.create.
router.post('/:id/clone-warranty', requirePermission('tickets.create'), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for allocateCounter and dynamic-import hooks below
  const userId = req.user!.id;
  const sourceId = validateId(req.params.id, 'id');

  const source = await adb.get<AnyRow>('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0', sourceId);
  if (!source) throw new AppError('Source ticket not found', 404);

  // Tier: atomic ticket limit check (warranty clones count against the monthly cap)
  let warrantyReservationCommitted = false;
  const warrantyTenantId = req.tenantId;
  if (config.multiTenant && warrantyTenantId && req.tenantLimits?.maxTicketsMonth != null) {
    const { getMasterDb } = await import('../db/master-connection.js');
    const masterDb = getMasterDb();
    if (masterDb) {
      const month = new Date().toISOString().slice(0, 7);
      const limit = req.tenantLimits.maxTicketsMonth;
      const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
        const usage = masterDb.prepare(
          'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
        ).get(warrantyTenantId, month) as { tickets_created: number } | undefined;
        const current = usage?.tickets_created ?? 0;
        if (current >= limit) {
          return { allowed: false, current };
        }
        masterDb.prepare(`
          INSERT INTO tenant_usage (tenant_id, month, tickets_created)
          VALUES (?, ?, 1)
          ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
        `).run(warrantyTenantId, month);
        return { allowed: true, current: current + 1 };
      })();

      if (!reservation.allowed) {
        res.status(403).json({
          success: false,
          upgrade_required: true,
          feature: 'ticket_limit',
          message: `Monthly ticket limit reached (${reservation.current}/${limit}). Upgrade to Pro for unlimited tickets.`,
          current: reservation.current,
          limit,
        });
        return;
      }
      warrantyReservationCommitted = true;
    }
  }

  // Get default status
  const defaultStatus = await adb.get<AnyRow>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
  const statusId = defaultStatus?.id ?? 1;

  // I4 fix: allocate ticket order_id via the shared atomic counter.
  const warrantySeq = allocateCounter(db, 'ticket_order_id');
  const orderId = formatTicketOrderId(warrantySeq);

  // Generate tracking token
  const trackingToken = crypto.randomBytes(16).toString('hex');

  // Insert new ticket as warranty case
  // SCAN-529: include location_id so the warranty clone is associated with the same
  // location as the source ticket (fallback 1 = Main Store for legacy rows with no location).
  const result = await adb.run(`
    INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                         source, referral_source, labels, due_on, is_warranty, created_by,
                         tracking_token, location_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, 0, NULL, ?, NULL, '[]', NULL, 1, ?, ?, ?, ?, ?)
  `,
    orderId,
    source.customer_id,
    statusId,
    source.assigned_to,
    'warranty',
    userId,
    trackingToken,
    source.location_id ?? 1,
    now(),
    now(),
  );

  const newTicketId = Number(result.lastInsertRowid);

  // Copy devices (without parts -- warranty gets fresh assessment)
  const devices = await adb.all<AnyRow>('SELECT * FROM ticket_devices WHERE ticket_id = ?', sourceId);
  for (const dev of devices) {
    await adb.run(`
      INSERT INTO ticket_devices (ticket_id, device_name, device_type, device_model_id, service_name,
                                  imei, serial, security_code, color, network, status_id, assigned_to,
                                  service_id, price, line_discount, tax_amount, tax_class_id, tax_inclusive,
                                  total, warranty, warranty_days, due_on, device_location,
                                  additional_notes, pre_conditions, post_conditions,
                                  created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?, 0, 0, 1, ?, NULL, ?, ?, '[]', '[]', ?, ?)
    `,
      newTicketId,
      dev.device_name,
      dev.device_type,
      dev.device_model_id,
      dev.service_name,
      dev.imei,
      dev.serial,
      dev.security_code,
      dev.color,
      dev.network,
      statusId,
      dev.assigned_to,
      dev.service_id,
      dev.tax_class_id,
      dev.warranty_days,
      dev.device_location,
      dev.additional_notes,
      now(),
      now(),
    );
  }

  // Recalculate totals (will be 0 since prices are reset)
  await recalcTicketTotalsAsync(adb, newTicketId);

  // Link to original ticket
  const idA = Math.min(sourceId, newTicketId);
  const idB = Math.max(sourceId, newTicketId);
  await adb.run(
    'INSERT INTO ticket_links (ticket_id_a, ticket_id_b, link_type, created_by) VALUES (?, ?, ?, ?)',
    idA, idB, 'warranty_followup', userId
  );

  // History on new ticket
  await insertHistoryAsync(adb, newTicketId, userId, 'created', `Warranty case cloned from ticket #${source.order_id} (ID ${sourceId})`);

  // History on source ticket
  await insertHistoryAsync(adb, sourceId, userId, 'linked', `Warranty case #${orderId} created from this ticket`);

  // Track usage for tier enforcement — skip if we already pre-incremented in the reservation
  // T10 fix: surface errors from the usage-tracker hook so we can investigate drift.
  if (!warrantyReservationCommitted) {
    import('../services/usageTracker.js').then(({ incrementTicketCount }) => {
      incrementTicketCount(req.tenantId);
    }).catch((e: unknown) => {
      logger.error('warranty-clone usage tracker hook failed', {
        ticket_id: newTicketId,
        source_ticket_id: sourceId,
        error: e instanceof Error ? e.message : String(e),
      });
    });
  }

  const ticket = await getFullTicketAsync(adb, newTicketId);

  broadcast(WS_EVENTS.TICKET_CREATED, ticket, req.tenantSlug || null);

  res.status(201).json({ success: true, data: ticket });
}));

export default router;
