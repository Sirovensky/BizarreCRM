import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { generateOrderId } from '../utils/format.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { config } from '../config.js';
import { validatePrice, validateQuantity } from '../utils/validate.js';
import { runAutomations } from '../services/automations.js';
import { idempotent } from '../middleware/idempotency.js';
import { calculateActiveRepairTime } from '../utils/repair-time.js';
import { roundCurrency } from '../utils/currency.js';
import { audit } from '../utils/audit.js';
import { fireWebhook } from '../services/webhooks.js';
import type { AsyncDb } from '../db/async-db.js';

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

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function parseJsonCol(val: any, fallback: any = []): any {
  if (!val) return fallback;
  try { return JSON.parse(val); } catch { return fallback; }
}

function calcTax(db: any, price: number, taxClassId: number | null, taxInclusive: boolean): number {
  if (!taxClassId) return 0;
  const tc = db.prepare('SELECT rate FROM tax_classes WHERE id = ?').get(taxClassId) as AnyRow | undefined;
  if (!tc) return 0;
  const rate = tc.rate / 100;
  if (taxInclusive) return roundCurrency(price - price / (1 + rate));
  return roundCurrency(price * rate);
}

/** Look up the default tax class ID from store_config based on item type.
 *  Repairs/services → tax_default_services, parts → tax_default_parts,
 *  accessories/products → tax_default_accessories.
 *  Returns null if no default is configured. */
function getDefaultTaxClassId(db: any, itemType?: string): number | null {
  const key = itemType === 'part' ? 'tax_default_parts'
    : itemType === 'accessory' || itemType === 'product' ? 'tax_default_accessories'
    : 'tax_default_services';  // repairs / services / default
  const row = db.prepare("SELECT value FROM store_config WHERE key = ?").get(key) as AnyRow | undefined;
  if (!row?.value) return null;
  const id = parseInt(row.value);
  return isNaN(id) || id <= 0 ? null : id;
}

function insertHistory(db: any, ticketId: number, userId: number | null, action: string, description: string, oldValue?: string | null, newValue?: string | null): void {
  db.prepare(
    `INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(ticketId, userId, action, description, oldValue ?? null, newValue ?? null);
}

function getFullTicket(db: any, ticketId: number): AnyRow | null {
  const ticket = db.prepare(`
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
  `).get(ticketId) as AnyRow | undefined;

  if (!ticket) return null;

  // Shape the joined data
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

  // Devices
  const devices = db.prepare(`
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
  `).all(ticketId) as AnyRow[];

  result.devices = devices.map((d) => {
    const parts = db.prepare(`
      SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
      FROM ticket_device_parts tdp
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      WHERE tdp.ticket_device_id = ?
    `).all(d.id) as AnyRow[];

    const photos = db.prepare('SELECT * FROM ticket_photos WHERE ticket_device_id = ? ORDER BY created_at ASC').all(d.id) as AnyRow[];

    const checklist = db.prepare('SELECT * FROM ticket_checklists WHERE ticket_device_id = ?').get(d.id) as AnyRow | undefined;

    return {
      id: d.id,
      ticket_id: d.ticket_id,
      device_name: d.device_name,
      device_type: d.device_type,
      imei: d.imei,
      serial: d.serial,
      security_code: d.security_code,
      color: d.color,
      network: d.network,
      status_id: d.status_id,
      assigned_to: d.assigned_to,
      service_id: d.service_id,
      price: d.price,
      line_discount: d.line_discount,
      tax_amount: d.tax_amount,
      tax_class_id: d.tax_class_id,
      tax_inclusive: d.tax_inclusive,
      total: d.total,
      warranty: d.warranty,
      warranty_days: d.warranty_days,
      due_on: d.due_on,
      collected_date: d.collected_date,
      device_location: d.device_location,
      additional_notes: d.additional_notes,
      pre_conditions: parseJsonCol(d.pre_conditions, []),
      post_conditions: parseJsonCol(d.post_conditions, []),
      loaner_device_id: d.loaner_device_id,
      created_at: d.created_at,
      updated_at: d.updated_at,
      status: d.status_id ? { id: d.status_id, name: d.status_name, color: d.status_color } : null,
      assigned_user: d.assigned_to ? { id: d.assigned_to, first_name: d.assigned_first, last_name: d.assigned_last } : null,
      service: d.service_id ? { id: d.service_id, name: d.service_name } : null,
      parts,
      photos,
      checklist: checklist ? { ...checklist, items: parseJsonCol(checklist.items, []) } : null,
    };
  });

  // Notes
  result.notes = (db.prepare(`
    SELECT tn.*, u3.first_name, u3.last_name, u3.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u3 ON u3.id = tn.user_id
    WHERE tn.ticket_id = ?
    ORDER BY tn.created_at DESC
  `).all(ticketId) as AnyRow[]).map((n) => ({
    ...n,
    is_flagged: !!n.is_flagged,
    user: { id: n.user_id, first_name: n.first_name, last_name: n.last_name, avatar_url: n.avatar_url },
  }));

  // History
  result.history = (db.prepare(`
    SELECT th.*, u4.first_name, u4.last_name
    FROM ticket_history th
    LEFT JOIN users u4 ON u4.id = th.user_id
    WHERE th.ticket_id = ?
    ORDER BY th.created_at DESC
  `).all(ticketId) as AnyRow[]).map((h) => ({
    ...h,
    user: h.user_id ? { id: h.user_id, first_name: h.first_name, last_name: h.last_name } : null,
  }));

  // Payments (via linked invoice)
  if (result.invoice_id) {
    result.payments = db.prepare(`
      SELECT p.id, p.amount, p.method, p.method_detail, p.transaction_id, p.notes, p.created_at
      FROM payments p WHERE p.invoice_id = ?
      ORDER BY p.created_at ASC
    `).all(result.invoice_id) as AnyRow[];
  } else {
    result.payments = [];
  }

  return result;
}

function recalcTicketTotals(db: any, ticketId: number): void {
  const devices = db.prepare('SELECT price, line_discount, tax_amount, total FROM ticket_devices WHERE ticket_id = ?').all(ticketId) as AnyRow[];
  const parts = db.prepare(`
    SELECT tdp.quantity, tdp.price
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    WHERE td.ticket_id = ?
  `).all(ticketId) as AnyRow[];

  let subtotal = 0;
  let totalTax = 0;
  for (const d of devices) {
    subtotal += (d.price - d.line_discount);
    totalTax += d.tax_amount;
  }
  // Parts are added to subtotal but NOT separately taxed.
  // Tax is calculated at the device level (ticket_devices.tax_amount) which covers
  // the flat-rate repair price (labor + parts combined). Individual parts costs
  // are tracked for internal margin/COGS purposes only — the customer-facing tax
  // is on the device-level price. This is intentional: the repair is a single
  // taxable service, not a parts-and-labor itemized bill.
  for (const p of parts) {
    subtotal += p.quantity * p.price;
  }

  const ticketRow = db.prepare('SELECT discount FROM tickets WHERE id = ?').get(ticketId) as AnyRow;
  const discount = ticketRow?.discount ?? 0;
  const total = roundCurrency(subtotal - discount + totalTax);

  db.prepare('UPDATE tickets SET subtotal = ?, total_tax = ?, total = ?, updated_at = ? WHERE id = ?')
    .run(roundCurrency(subtotal), roundCurrency(totalTax), total, now(), ticketId);
}

// ---------------------------------------------------------------------------
// Async helper variants — worker-thread versions for use outside transactions
// ---------------------------------------------------------------------------

async function calcTaxAsync(adb: AsyncDb, price: number, taxClassId: number | null, taxInclusive: boolean): Promise<number> {
  if (!taxClassId) return 0;
  const tc = await adb.get<AnyRow>('SELECT rate FROM tax_classes WHERE id = ?', taxClassId);
  if (!tc) return 0;
  const rate = tc.rate / 100;
  if (taxInclusive) return roundCurrency(price - price / (1 + rate));
  return roundCurrency(price * rate);
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
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string) || 20));
  const keyword = (req.query.keyword as string || '').trim();
  const statusParam = (req.query.status_id as string || '').trim();
  const statusId = /^\d+$/.test(statusParam) ? parseInt(statusParam) : null;
  const statusGroup = ['open', 'closed', 'cancelled', 'onhold', 'active', 'on_hold'].includes(statusParam) ? statusParam : null;
  const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string) : null;
  const fromDate = req.query.from_date as string || null;
  const toDate = req.query.to_date as string || null;
  const dateFilter = req.query.date_filter as string || 'all';
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
    } else if (statusGroup === 'onhold' || statusGroup === 'on_hold') {
      conditions.push("t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 AND (LOWER(name) LIKE '%hold%' OR LOWER(name) LIKE '%waiting%' OR LOWER(name) LIKE '%pending%' OR LOWER(name) LIKE '%transit%'))");
    }
  }
  if (assignedTo) {
    conditions.push('t.assigned_to = ?');
    params.push(assignedTo);
  }

  // SW-D4: When ticket_all_employees_view_all is '0', non-admin users only see their own tickets
  if (!assignedTo && req.user?.role !== 'admin') {
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

  // Keyword search: order_id, customer name, device names, notes content, history description
  let keywordJoin = '';
  if (keyword) {
    keywordJoin = 'LEFT JOIN ticket_devices td_kw ON td_kw.ticket_id = t.id';
    conditions.push(`(
      t.order_id LIKE ? OR
      c.first_name LIKE ? OR c.last_name LIKE ? OR
      (c.first_name || ' ' || c.last_name) LIKE ? OR
      td_kw.device_name LIKE ? OR
      t.id IN (SELECT ticket_id FROM ticket_notes WHERE content LIKE ?) OR
      t.id IN (SELECT ticket_id FROM ticket_history WHERE description LIKE ?)
    )`);
    const like = `%${keyword}%`;
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
  const countRow = await adb.get<AnyRow>(countSql, ...params);
  const totalCount = countRow?.total ?? 0;

  // Main query
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
  const rows = await adb.all<AnyRow>(dataSql, ...dataParams);

  // Batch-fetch device info for all ticket IDs (eliminates N+1)
  const ticketIds = rows.map(r => r.id);
  const deviceMap = new Map<number, AnyRow>();
  const countMap = new Map<number, number>();
  const partsCountMap = new Map<number, number>();
  const partsListMap = new Map<number, string[]>();
  const latestSmsMap = new Map<number, { message: string; direction: string; date_time: string }>();

  if (ticketIds.length > 0) {
    const placeholders = ticketIds.map(() => '?').join(',');
    const devices = await adb.all<AnyRow>(`
      SELECT td.ticket_id, td.device_name, td.additional_notes, td.device_type,
             td.imei, td.serial, td.security_code, td.service_id,
             COALESCE(td.service_name, ii.name) AS service_name,
             ROW_NUMBER() OVER (PARTITION BY td.ticket_id ORDER BY td.id ASC) AS rn
      FROM ticket_devices td
      LEFT JOIN inventory_items ii ON ii.id = td.service_id
      WHERE td.ticket_id IN (${placeholders})
    `, ...ticketIds);
    for (const d of devices) {
      if (d.rn === 1) deviceMap.set(d.ticket_id, d);
      countMap.set(d.ticket_id, (countMap.get(d.ticket_id) || 0) + 1);
    }

    // SW-D2: Skip parts data when ticket_show_parts_column is disabled
    const showPartsCfg = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_show_parts_column'");
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
      console.error('SMS lookup for ticket list failed:', (e as Error).message);
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

  // Status counts for overview bar
  const statusCounts = await adb.all<AnyRow>(`
    SELECT ts.id, ts.name, ts.color, ts.sort_order, COUNT(t.id) AS count
    FROM ticket_statuses ts
    LEFT JOIN tickets t ON t.status_id = ts.id AND t.is_deleted = 0
    GROUP BY ts.id
    ORDER BY ts.sort_order ASC
  `);

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
router.post('/', idempotent, asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const userId = req.user!.id;
  const body = req.body;

  // F18: Require customer if setting enabled (default: required)
  const requireCustomer = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_customer'").get() as AnyRow | undefined;
  const customerRequired = !requireCustomer || requireCustomer.value !== '0';
  if (!body.customer_id && customerRequired) {
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

  // Verify customer exists (if provided)
  if (body.customer_id) {
    const customer = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(body.customer_id) as AnyRow | undefined;
    if (!customer) throw new AppError('Customer not found', 404);
  }

  // F9: Require pre-conditions if setting enabled
  const requirePreCond = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_pre_condition'").get() as AnyRow | undefined;
  if (requirePreCond?.value === '1' || requirePreCond?.value === 'true') {
    for (const dev of body.devices) {
      if (!dev.pre_conditions || dev.pre_conditions.length === 0) {
        throw new AppError(`Pre-conditions required for device: ${dev.device_name || 'Unknown'}`, 400);
      }
    }
  }

  // F14: Require IMEI if setting enabled
  const requireImei = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_imei'").get() as AnyRow | undefined;
  if (requireImei?.value === '1' || requireImei?.value === 'true') {
    for (const dev of body.devices) {
      if (!dev.imei && !dev.serial) {
        throw new AppError(`IMEI or serial number required for device: ${dev.device_name || 'Unknown'}`, 400);
      }
    }
  }

  // Get default status if not provided
  let statusId = body.status_id;
  if (!statusId) {
    const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get() as AnyRow | undefined;
    statusId = defaultStatus?.id ?? 1;
  }

  // F16: Auto-calculate due date if not provided
  let dueOn = body.due_on ?? null;
  if (!dueOn) {
    const dueCfg = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_due_value'").get() as AnyRow | undefined;
    const dueUnit = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_due_unit'").get() as AnyRow | undefined;
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
    const defaultAssignment = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_default_assignment'").get() as AnyRow | undefined;
    if (defaultAssignment?.value === 'default') {
      assignedTo = userId; // Assign to creator
    }
    // 'unassigned' and 'pin_based' leave it null
  }

  const createTicket = db.transaction(() => {
    // Get next order_id from existing order_ids (safe across deletions)
    const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 3) AS INTEGER)), 0) + 1 as next_num FROM tickets").get() as AnyRow;
    const orderId = generateOrderId('T', seqRow.next_num);

    // Generate tracking token for public ticket lookup
    const trackingToken = crypto.randomBytes(16).toString('hex'); // 32-char hex (128-bit)

    // Insert ticket (ENR-POS1: includes is_layaway + layaway_expires)
    const ticketResult = db.prepare(`
      INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                           source, referral_source, labels, due_on, created_by, tracking_token,
                           is_layaway, layaway_expires, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      orderId,
      body.customer_id,
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
      now(),
      now(),
    );

    const ticketId = Number(ticketResult.lastInsertRowid);

    // Insert devices
    for (const dev of body.devices) {
      const devicePrice = validatePrice(dev.price ?? 0, 'device price');
      const lineDiscount = dev.line_discount ?? 0;
      if (typeof lineDiscount !== 'number' || lineDiscount < 0 || lineDiscount > devicePrice) {
        throw new AppError('line_discount must be >= 0 and <= price', 400);
      }
      const resolvedTaxClassId = dev.tax_class_id ?? getDefaultTaxClassId(db, dev.item_type);
      const taxAmount = calcTax(db, devicePrice - lineDiscount, resolvedTaxClassId, dev.tax_inclusive ?? false);
      const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

      const devResult = db.prepare(`
        INSERT INTO ticket_devices (ticket_id, device_name, device_type, device_model_id, service_name,
                                    imei, serial, security_code,
                                    color, network, status_id, assigned_to, service_id, price, line_discount,
                                    tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                    due_on, device_location, additional_notes, customer_comments, staff_comments,
                                    pre_conditions, post_conditions,
                                    created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
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
        dev.warranty_days ?? (() => {
          // F15: Auto-fill default warranty from settings
          // SW-D11: Respect repair_default_warranty_unit (days or months)
          const wVal = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_warranty_value'").get() as AnyRow | undefined;
          const wUnit = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_warranty_unit'").get() as AnyRow | undefined;
          const rawVal = wVal?.value ? parseInt(wVal.value) : 0;
          // Convert months to days (approximate: 30 days per month)
          return wUnit?.value === 'months' ? rawVal * 30 : rawVal;
        })(),
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

          // Check stock availability before decrementing
          const invItem = db.prepare('SELECT in_stock FROM inventory_items WHERE id = ?').get(part.inventory_item_id) as AnyRow | undefined;
          if (invItem && invItem.in_stock < partQty) {
            throw new AppError(`Insufficient stock for ${part.name || 'item'}: ${invItem.in_stock} available, ${partQty} needed`, 400);
          }

          db.prepare(`
            INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          `).run(deviceId, part.inventory_item_id, partQty, partPrice, part.warranty ? 1 : 0, part.serial ?? null, now(), now());

          // Decrease inventory stock
          db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?')
            .run(partQty, now(), part.inventory_item_id);

          // Stock movement
          db.prepare(`
            INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
            VALUES (?, 'ticket_usage', ?, 'ticket', ?, ?, ?, ?, ?)
          `).run(part.inventory_item_id, -partQty, ticketId, `Used in ticket ${orderId}`, userId, now(), now());
        }
      }
    }

    // Recalculate totals
    recalcTicketTotals(db, ticketId);

    // History
    insertHistory(db, ticketId, userId, 'created', 'Ticket created');

    // Check if status should notify customer
    const status = db.prepare('SELECT notify_customer, name FROM ticket_statuses WHERE id = ?').get(statusId) as AnyRow | undefined;
    if (status?.notify_customer) {
      import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
        sendTicketStatusNotification(db, { ticketId, statusName: status.name, tenantSlug: req.tenantSlug || null });
      }).catch(() => {});
    }

    return ticketId;
  });

  const ticketId = createTicket();
  const ticket = getFullTicket(db, ticketId);

  broadcast(WS_EVENTS.TICKET_CREATED, ticket, req.tenantSlug || null);

  // ENR-A6: Fire webhook
  fireWebhook(db, 'ticket_created', { ticket_id: ticketId, order_id: (ticket as any)?.order_id });

  // Fire automations (async, non-blocking)
  const cust = db.prepare('SELECT * FROM customers WHERE id = ?').get(body.customer_id) as AnyRow | undefined;
  runAutomations(db, 'ticket_created', { ticket, customer: cust ?? {} });

  res.status(201).json({ success: true, data: ticket });
}));

// ===================================================================
// GET /kanban - Tickets grouped by status for kanban view
// ===================================================================
router.get('/kanban', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const statuses = await adb.all<AnyRow>('SELECT * FROM ticket_statuses ORDER BY sort_order ASC');

  // Fetch all status columns in parallel via worker threads
  const columns = await Promise.all(statuses.map(async (status) => {
    const tickets = await adb.all<AnyRow>(`
      SELECT t.id, t.order_id, t.customer_id, t.status_id, t.assigned_to,
             t.total, t.due_on, t.labels, t.created_at, t.updated_at,
             c.first_name AS c_first_name, c.last_name AS c_last_name,
             u.first_name AS assigned_first, u.last_name AS assigned_last
      FROM tickets t
      LEFT JOIN customers c ON c.id = t.customer_id
      LEFT JOIN users u ON u.id = t.assigned_to
      WHERE t.status_id = ? AND t.is_deleted = 0
      ORDER BY t.updated_at DESC
      LIMIT 100
    `, status.id);

    return {
      status: {
        id: status.id,
        name: status.name,
        color: status.color,
        sort_order: status.sort_order,
        is_closed: !!status.is_closed,
        is_cancelled: !!status.is_cancelled,
      },
      tickets: tickets.map((t) => ({
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
    };
  }));

  res.json({ success: true, data: { columns } });
}));

// ===================================================================
// GET /stalled - Stalled tickets
// ===================================================================
router.get('/stalled', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  let days = parseInt(req.query.days as string) || 0;
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
  const tickets = await adb.all<AnyRow>(`
    SELECT t.id, t.order_id, t.status_id,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color,
           u.first_name AS tech_first, u.last_name AS tech_last
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
    ORDER BY t.updated_at DESC
    LIMIT 50
  `);

  // Fetch all device names in parallel
  const result = await Promise.all(tickets.map(async (t) => {
    const devices = await adb.all<AnyRow>('SELECT device_name FROM ticket_devices WHERE ticket_id = ?', t.id);
    return {
      id: t.id,
      order_id: t.order_id,
      customer_first_name: t.c_first_name,
      device_names: devices.map((d) => d.device_name),
      status: { name: t.status_name, color: t.status_color },
      assigned_tech: t.tech_first ? `${t.tech_first} ${t.tech_last}` : null,
    };
  }));

  res.json({ success: true, data: result });
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
router.get('/export', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const keyword = (req.query.keyword as string || '').trim();
  const statusParam = (req.query.status_id as string || '').trim();
  const statusId = /^\d+$/.test(statusParam) ? parseInt(statusParam) : null;
  const statusGroup = ['open', 'closed', 'cancelled', 'onhold', 'active', 'on_hold'].includes(statusParam) ? statusParam : null;
  const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string) : null;
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
    } else if (statusGroup === 'onhold' || statusGroup === 'on_hold') {
      conditions.push("t.status_id IN (SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 AND (LOWER(name) LIKE '%hold%' OR LOWER(name) LIKE '%waiting%' OR LOWER(name) LIKE '%pending%' OR LOWER(name) LIKE '%transit%'))");
    }
  }
  if (assignedTo) {
    conditions.push('t.assigned_to = ?');
    params.push(assignedTo);
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
      t.order_id LIKE ? OR
      c.first_name LIKE ? OR c.last_name LIKE ? OR
      (c.first_name || ' ' || c.last_name) LIKE ? OR
      td_kw.device_name LIKE ? OR
      t.id IN (SELECT ticket_id FROM ticket_notes WHERE content LIKE ?) OR
      t.id IN (SELECT ticket_id FROM ticket_history WHERE description LIKE ?)
    )`);
    const like = `%${keyword}%`;
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
  const csvHeader = 'Order ID,Customer,Device,Status,Created,Total';
  const csvRows = rows.map((r) => {
    const escapeCsv = (val: string) => {
      if (!val) return '';
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
  const filterId = parseInt(req.params.id);
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
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
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
router.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for automations
  const ticketId = parseInt(req.params.id);
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

  // Validate customer_id if provided
  if (req.body.customer_id !== undefined) {
    const cust = await adb.get<AnyRow>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', req.body.customer_id);
    if (!cust) throw new AppError('Customer not found', 404);
  }

  const allowedFields = [
    'customer_id', 'assigned_to', 'discount', 'discount_reason',
    'source', 'referral_source', 'labels', 'due_on', 'signature',
    'is_layaway', 'layaway_expires', // ENR-POS1
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

  await insertHistoryAsync(adb, ticketId, userId, 'updated', 'Ticket updated');
  const ticket = await getFullTicketAsync(adb, ticketId);
  broadcast(WS_EVENTS.TICKET_UPDATED, ticket, req.tenantSlug || null);

  // Fire automations for assignment changes
  if (req.body.assigned_to !== undefined && req.body.assigned_to !== existing.assigned_to) {
    const cust = await adb.get<AnyRow>('SELECT * FROM customers WHERE id = ?', ticket.customer_id);
    runAutomations(db, 'ticket_assigned', { ticket, customer: cust ?? {} });
  }

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// DELETE /:id - Soft delete
// ===================================================================
router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for transaction
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = await adb.get<AnyRow>('SELECT id, invoice_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  // SW-D3: Block deletion when ticket has an invoice and setting is disabled
  if (existing.invoice_id) {
    const allowDeleteAfterInvoice = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_allow_delete_after_invoice'");
    if (allowDeleteAfterInvoice?.value === '0') {
      throw new AppError('Cannot delete a ticket with an associated invoice', 403);
    }
  }

  const softDelete = db.transaction(() => {
    // Restore inventory stock for all parts on all devices in this ticket
    const devices = db.prepare('SELECT id FROM ticket_devices WHERE ticket_id = ?').all(ticketId) as AnyRow[];
    for (const device of devices) {
      const parts = db.prepare('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?').all(device.id) as AnyRow[];
      for (const part of parts) {
        if (part.inventory_item_id) {
          db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?')
            .run(part.quantity, now(), part.inventory_item_id);

          db.prepare(`
            INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
            VALUES (?, 'ticket_return', ?, 'ticket', ?, 'Stock restored — ticket deleted', ?, ?, ?)
          `).run(part.inventory_item_id, part.quantity, ticketId, userId, now(), now());
        }
      }
    }

    // Void any linked non-void invoice (same pattern as cancellation)
    const linkedInvoice = db.prepare("SELECT id, status FROM invoices WHERE ticket_id = ? AND status != 'void'").get(ticketId) as AnyRow | undefined;
    if (linkedInvoice) {
      db.prepare("UPDATE invoices SET status = 'void', amount_due = 0, updated_at = ? WHERE id = ?").run(now(), linkedInvoice.id);
      insertHistory(db, ticketId, userId, 'invoice_voided', 'Invoice auto-voided on ticket deletion');
    }

    db.prepare('UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ?').run(now(), ticketId);
    insertHistory(db, ticketId, userId, 'deleted', 'Ticket deleted');
  });

  softDelete();
  broadcast(WS_EVENTS.TICKET_DELETED, { id: ticketId }, req.tenantSlug || null);

  res.json({ success: true, data: { id: ticketId } });
}));

// ===================================================================
// PATCH /:id/status - Change ticket status
// ===================================================================
router.patch('/:id/status', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db; // needed for services (notifications, automations, webhooks, sms) and calculateActiveRepairTime
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  const { status_id } = req.body;

  if (!ticketId) throw new AppError('Invalid ticket ID');
  if (!status_id) throw new AppError('status_id is required');

  // Validation reads — async (off main thread)
  const existing = await adb.get<AnyRow>('SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  const [oldStatus, newStatus] = await Promise.all([
    adb.get<AnyRow>('SELECT id, name FROM ticket_statuses WHERE id = ?', existing.status_id),
    adb.get<AnyRow>('SELECT id, name, notify_customer, is_closed, is_cancelled FROM ticket_statuses WHERE id = ?', status_id),
  ]);
  if (!newStatus) throw new AppError('Status not found', 404);

  // F10: Require post-conditions before closing
  if (newStatus.is_closed) {
    const requirePostCond = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_require_post_condition'");
    if (requirePostCond?.value === '1' || requirePostCond?.value === 'true') {
      const devices = await adb.all<AnyRow>('SELECT id, device_name, post_conditions FROM ticket_devices WHERE ticket_id = ?', ticketId);
      for (const d of devices) {
        const postConds = d.post_conditions ? JSON.parse(d.post_conditions) : [];
        if (postConds.length === 0) throw new AppError(`Post-conditions required for ${d.device_name} before closing`, 400);
      }
    }

    // F11: Require parts before closing
    const requireParts = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_require_parts'");
    if (requireParts?.value === '1' || requireParts?.value === 'true') {
      const partsCount = await adb.get<AnyRow>('SELECT COUNT(*) as c FROM ticket_device_parts tdp JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?', ticketId);
      if (partsCount!.c === 0) throw new AppError('At least one part must be added before closing the ticket', 400);
    }

    // SW-D5: Require repair timer / stopwatch usage before closing
    const requireStopwatch = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_require_stopwatch'");
    if (requireStopwatch?.value === '1') {
      const activeTime = calculateActiveRepairTime(db, ticketId);
      if (activeTime === null || activeTime <= 0) {
        throw new AppError('Repair timer must be started before closing the ticket', 400);
      }
    }
  }

  // F13: Require diagnostic note before any status change
  const requireDiag = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'repair_require_diagnostic'");
  if (requireDiag?.value === '1' || requireDiag?.value === 'true') {
    const diagNote = await adb.get<AnyRow>("SELECT id FROM ticket_notes WHERE ticket_id = ? AND type = 'diagnostic' LIMIT 1", ticketId);
    if (!diagNote) throw new AppError('A diagnostic note is required before changing status', 400);
  }

  // --- Writes (async standalone) ---
  await adb.run('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?', status_id, now(), ticketId);

  // SW-D9: Auto-start / auto-stop repair timer based on status change
  const [timerAutoStart, timerAutoStop] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_timer_auto_start_status'"),
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_timer_auto_stop_status'"),
  ]);

  if (timerAutoStart?.value && String(status_id) === String(timerAutoStart.value)) {
    await adb.run(
      "UPDATE tickets SET repair_timer_running = 1, repair_timer_started_at = COALESCE(repair_timer_started_at, ?) WHERE id = ? AND repair_timer_running = 0",
      now(), ticketId
    );
    await insertHistoryAsync(adb, ticketId, userId, 'timer_started', 'Repair timer auto-started on status change');
  }

  if (timerAutoStop?.value && String(status_id) === String(timerAutoStop.value)) {
    const running = await adb.get<AnyRow>('SELECT repair_timer_running FROM tickets WHERE id = ?', ticketId);
    if (running?.repair_timer_running) {
      await adb.run("UPDATE tickets SET repair_timer_running = 0, updated_at = ? WHERE id = ?", now(), ticketId);
      await insertHistoryAsync(adb, ticketId, userId, 'timer_stopped', 'Repair timer auto-stopped on status change');
    }
  }

  // If cancelled, void any linked unpaid invoice
  if (newStatus.is_cancelled) {
    const linkedInvoice = await adb.get<AnyRow>("SELECT id, status FROM invoices WHERE ticket_id = ? AND status != 'void'", ticketId);
    if (linkedInvoice) {
      await adb.run("UPDATE invoices SET status = 'void', amount_due = 0, updated_at = ? WHERE id = ?", now(), linkedInvoice.id);
      await insertHistoryAsync(adb, ticketId, userId, 'invoice_voided', `Invoice auto-voided on ticket cancellation`);
    }
  }

  // Sync device-level statuses to match ticket status
  await adb.run('UPDATE ticket_devices SET status_id = ?, updated_at = ? WHERE ticket_id = ?', status_id, now(), ticketId);

  await insertHistoryAsync(adb, ticketId, userId, 'status_changed',
    `Status changed from "${oldStatus!.name}" to "${newStatus.name}"`,
    oldStatus!.name, newStatus.name);

  if (newStatus.notify_customer) {
    import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
      sendTicketStatusNotification(db, { ticketId, statusName: newStatus.name, tenantSlug: req.tenantSlug || null });
    }).catch(err => console.error('[Notification] Import error:', err));
  }

  const ticket = await getFullTicketAsync(adb, ticketId);
  broadcast(WS_EVENTS.TICKET_STATUS_CHANGED, ticket, req.tenantSlug || null);

  // SW-D14: Schedule feedback SMS after ticket close
  if (newStatus.is_closed) {
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
            db.prepare(`
              INSERT INTO customer_feedback (ticket_id, customer_id, source, requested_at)
              VALUES (?, ?, 'sms', datetime('now'))
            `).run(ticketId, ticket!.customer_id);
            db.prepare(`
              INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
              VALUES ('', ?, ?, ?, 'sent', 'outbound', 'auto-feedback', 'ticket', ?, datetime('now'), datetime('now'))
            `).run(feedbackPhone, feedbackPhone.replace(/\D/g, '').replace(/^1/, ''), smsBody, ticketId);
            console.log(`[Feedback] Sent feedback SMS to ${feedbackPhone} for ticket ${ticket!.order_id}`);
          } catch (err) {
            console.error('[Feedback] Failed to send feedback SMS:', err);
          }
        }, delayMs);
      }
    }
  }

  // ENR-A6: Fire webhook for status change
  fireWebhook(db, 'ticket_status_changed', {
    ticket_id: ticketId,
    order_id: (ticket as any)?.order_id,
    from_status_id: oldStatus!.id,
    to_status_id: status_id,
  });

  // Fire automations (async, non-blocking)
  const cust = await adb.get<AnyRow>('SELECT * FROM customers WHERE id = ?', ticket!.customer_id);
  runAutomations(db, 'ticket_status_changed', {
    ticket,
    customer: cust ?? {},
    from_status_id: oldStatus!.id,
    to_status_id: status_id,
  });

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// PATCH /:id/pin - Toggle ticket pinned state
// ===================================================================
router.patch('/:id/pin', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);

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
router.post('/:id/notes', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
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
    console.log(`[Email] Would send email note for ticket ${existing.order_id}`);
  }

  const note = await adb.get<AnyRow>(`
    SELECT tn.*, u.first_name, u.last_name, u.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.id = ?
  `, noteId);

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
router.put('/notes/:noteId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const noteId = parseInt(req.params.noteId);
  if (!noteId) throw new AppError('Invalid note ID');

  const existing = await adb.get<AnyRow>('SELECT * FROM ticket_notes WHERE id = ?', noteId);
  if (!existing) throw new AppError('Note not found', 404);

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

  const note = await adb.get<AnyRow>(`
    SELECT tn.*, u.first_name, u.last_name, u.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.id = ?
  `, noteId);

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
router.delete('/notes/:noteId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const noteId = parseInt(req.params.noteId);
  if (!noteId) throw new AppError('Invalid note ID');

  const existing = await adb.get<AnyRow>('SELECT id, ticket_id, user_id FROM ticket_notes WHERE id = ?', noteId);
  if (!existing) throw new AppError('Note not found', 404);

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
// POST /:id/photos - Upload photos
// ===================================================================
router.post('/:id/photos', upload.array('photos', 20), asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = await adb.get<AnyRow>('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!existing) throw new AppError('Ticket not found', 404);

  const files = req.files as Express.Multer.File[];
  if (!files || files.length === 0) throw new AppError('No photos uploaded');

  const { type, ticket_device_id, caption } = req.body;
  if (!ticket_device_id) throw new AppError('ticket_device_id is required');

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

  await Promise.all([
    insertHistoryAsync(adb, ticketId, req.user!.id, 'photo_added', `${files.length} photo(s) uploaded`),
    adb.run('UPDATE tickets SET updated_at = ? WHERE id = ?', now(), ticketId),
  ]);

  res.status(201).json({ success: true, data: photos });
}));

// ===================================================================
// DELETE /photos/:photoId - Delete photo
// ===================================================================
router.delete('/photos/:photoId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const photoId = parseInt(req.params.photoId);
  if (!photoId) throw new AppError('Invalid photo ID');

  const photo = await adb.get<AnyRow>(`
    SELECT tp.*, td.ticket_id
    FROM ticket_photos tp
    JOIN ticket_devices td ON td.id = tp.ticket_device_id
    WHERE tp.id = ?
  `, photoId);
  if (!photo) throw new AppError('Photo not found', 404);

  // Try to delete the file — account for tenant slug in multi-tenant setups
  const tenantSlug = (req as any).tenantSlug || '';
  const filePath = path.join(config.uploadsPath, tenantSlug, photo.file_path);
  try { fs.unlinkSync(filePath); } catch { /* file may not exist */ }

  await Promise.all([
    adb.run('DELETE FROM ticket_photos WHERE id = ?', photoId),
    insertHistoryAsync(adb, photo.ticket_id, req.user!.id, 'photo_deleted', 'Photo deleted'),
  ]);

  res.json({ success: true, data: { id: photoId } });
}));

// ===================================================================
// POST /:id/convert-to-invoice - Generate invoice from ticket
// ===================================================================
router.post('/:id/convert-to-invoice', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = db.prepare('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

  // Block conversion for cancelled tickets
  const ticketStatus = db.prepare('SELECT is_cancelled FROM ticket_statuses WHERE id = ?').get(ticket.status_id) as AnyRow | undefined;
  if (ticketStatus?.is_cancelled) {
    throw new AppError('Cannot convert a cancelled ticket to an invoice', 400);
  }

  // Check if invoice already exists (via ticket.invoice_id or direct lookup)
  const existingInvoice = ticket.invoice_id
    ? db.prepare('SELECT id FROM invoices WHERE id = ?').get(ticket.invoice_id)
    : db.prepare('SELECT id FROM invoices WHERE ticket_id = ?').get(ticketId);
  if (existingInvoice) throw new AppError('Ticket already has an invoice');

  const devices = db.prepare('SELECT * FROM ticket_devices WHERE ticket_id = ?').all(ticketId) as AnyRow[];

  const convert = db.transaction(() => {
    // Generate invoice order_id (safe: extract sequence from existing order_ids)
    const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 as next_num FROM invoices").get() as AnyRow;
    const invoiceOrderId = generateOrderId('INV', seqRow.next_num);

    const invResult = db.prepare(`
      INSERT INTO invoices (order_id, ticket_id, customer_id, status, subtotal, discount, discount_reason,
                            total_tax, total, amount_paid, amount_due, notes, created_by, created_at, updated_at)
      VALUES (?, ?, ?, 'unpaid', ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?)
    `).run(
      invoiceOrderId, ticketId, ticket.customer_id,
      ticket.subtotal, ticket.discount, ticket.discount_reason,
      ticket.total_tax, ticket.total, ticket.total,
      `Generated from ticket ${ticket.order_id}`,
      userId, now(), now(),
    );

    const invoiceId = Number(invResult.lastInsertRowid);

    // SW-D10: Read repair pricing settings
    const itemizeSetting = db.prepare("SELECT value FROM store_config WHERE key = 'repair_itemize_line_items'").get() as AnyRow | undefined;
    const priceIncludesPartsSetting = db.prepare("SELECT value FROM store_config WHERE key = 'repair_price_includes_parts'").get() as AnyRow | undefined;
    const itemizeLineItems = itemizeSetting?.value === '1' || itemizeSetting?.value === 'true';
    const priceIncludesParts = priceIncludesPartsSetting?.value === '1' || priceIncludesPartsSetting?.value === 'true';

    // Create line items from devices
    for (const dev of devices) {
      if (itemizeLineItems) {
        // Itemized: each device service as separate line item
        db.prepare(`
          INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                          line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
          VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          invoiceId, dev.service_id, `${dev.device_name} - Service`, dev.price,
          dev.line_discount, dev.tax_amount, dev.tax_class_id, dev.total, now(), now(),
        );
      } else {
        // Non-itemized: single combined "Repair" line per device
        db.prepare(`
          INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                          line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
          VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          invoiceId, dev.service_id, `Repair: ${dev.device_name}`, dev.price,
          dev.line_discount, dev.tax_amount, dev.tax_class_id, dev.total, now(), now(),
        );
      }

      // Add parts as line items only if price does NOT already include parts
      if (!priceIncludesParts) {
        const parts = db.prepare(`
          SELECT tdp.*, ii.name AS item_name
          FROM ticket_device_parts tdp
          LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
          WHERE tdp.ticket_device_id = ?
        `).all(dev.id) as AnyRow[];

        if (itemizeLineItems) {
          // Itemized: each part as a separate line item
          for (const part of parts) {
            const lineTotal = roundCurrency(part.quantity * part.price);
            db.prepare(`
              INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                              line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, 0, 0, NULL, ?, ?, ?)
            `).run(invoiceId, part.inventory_item_id, `Part: ${part.item_name || 'Unknown'}`, part.quantity, part.price, lineTotal, now(), now());
          }
        }
        // When not itemized: parts omitted from line items (single "Repair" line covers service,
        // parts totals are already in the ticket total)
      }
    }

    // Link invoice to ticket
    db.prepare('UPDATE tickets SET invoice_id = ?, updated_at = ? WHERE id = ?').run(invoiceId, now(), ticketId);

    // F4: Auto-close ticket on invoice creation if setting enabled
    const autoClose = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_auto_close_on_invoice'").get() as AnyRow | undefined;
    if (autoClose?.value === '1' || autoClose?.value === 'true') {
      const closedStatus = db.prepare("SELECT id FROM ticket_statuses WHERE is_closed = 1 ORDER BY sort_order LIMIT 1").get() as AnyRow | undefined;
      if (closedStatus) {
        db.prepare('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?').run(closedStatus.id, now(), ticketId);
        insertHistory(db, ticketId, userId, 'status_changed', `Auto-closed on invoice creation`);
      }
    }

    // F5: Auto-remove passcode on close
    const autoRemovePasscode = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_auto_remove_passcode'").get() as AnyRow | undefined;
    if (autoRemovePasscode?.value === '1' || autoRemovePasscode?.value === 'true') {
      db.prepare('UPDATE ticket_devices SET security_code = NULL WHERE ticket_id = ?').run(ticketId);
    }

    insertHistory(db, ticketId, userId, 'invoice_created', `Invoice ${invoiceOrderId} created from ticket`);

    return invoiceId;
  });

  const invoiceId = convert();

  const invoice = db.prepare(`
    SELECT i.*, c.first_name, c.last_name, c.email, c.phone
    FROM invoices i
    LEFT JOIN customers c ON c.id = i.customer_id
    WHERE i.id = ?
  `).get(invoiceId) as AnyRow;

  const lineItems = db.prepare('SELECT * FROM invoice_line_items WHERE invoice_id = ?').all(invoiceId) as AnyRow[];

  res.status(201).json({
    success: true,
    data: {
      ...invoice,
      customer: { id: invoice.customer_id, first_name: invoice.first_name, last_name: invoice.last_name, email: invoice.email, phone: invoice.phone },
      line_items: lineItems,
    },
  });
}));

// ===================================================================
// GET /:id/history - Ticket activity history
// ===================================================================
router.get('/:id/history', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
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
  const ticketId = parseInt(req.params.id);
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
router.post('/:id/devices', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = db.prepare('SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

  const dev = req.body;
  const devicePrice = validatePrice(dev.price ?? 0, 'device price');
  const lineDiscount = dev.line_discount ?? 0;
  if (typeof lineDiscount !== 'number' || lineDiscount < 0 || lineDiscount > devicePrice) {
    throw new AppError('line_discount must be >= 0 and <= price', 400);
  }
  const resolvedTaxClassId = dev.tax_class_id ?? getDefaultTaxClassId(db, dev.item_type);
  const taxAmount = calcTax(db, devicePrice - lineDiscount, resolvedTaxClassId, dev.tax_inclusive ?? false);
  const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

  const addDevice = db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO ticket_devices (ticket_id, device_name, device_type, imei, serial, security_code,
                                  color, network, status_id, assigned_to, service_id, price, line_discount,
                                  tax_amount, tax_class_id, tax_inclusive, total, warranty, warranty_days,
                                  due_on, device_location, additional_notes, pre_conditions, post_conditions,
                                  created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
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

    // Insert parts if provided
    if (dev.parts && Array.isArray(dev.parts)) {
      for (const part of dev.parts) {
        // Check stock availability before decrementing
        const invItem = db.prepare('SELECT in_stock FROM inventory_items WHERE id = ?').get(part.inventory_item_id) as AnyRow | undefined;
        if (invItem && invItem.in_stock < part.quantity) {
          throw new AppError(`Insufficient stock for ${part.name || 'item'}: ${invItem.in_stock} available, ${part.quantity} needed`, 400);
        }

        db.prepare(`
          INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(deviceId, part.inventory_item_id, part.quantity, part.price, part.warranty ? 1 : 0, part.serial ?? null, now(), now());

        db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?')
          .run(part.quantity, now(), part.inventory_item_id);

        db.prepare(`
          INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
          VALUES (?, 'ticket_usage', ?, 'ticket_device', ?, 'Part added to ticket device', ?, ?, ?)
        `).run(part.inventory_item_id, -part.quantity, deviceId, userId, now(), now());
      }
    }

    recalcTicketTotals(db, ticketId);
    insertHistory(db, ticketId, userId, 'device_added', `Device added: ${dev.device_name || 'Unknown'}`);

    return deviceId;
  });

  const deviceId = addDevice();
  const device = db.prepare('SELECT * FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: ticketId }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: { ...device, pre_conditions: parseJsonCol(device.pre_conditions, []), post_conditions: parseJsonCol(device.post_conditions, []) } });
}));

// ===================================================================
// PUT /devices/:deviceId - Update device
// ===================================================================
router.put('/devices/:deviceId', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const existing = db.prepare('SELECT * FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!existing) throw new AppError('Device not found', 404);

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
  const taxAmount = calcTax(db, price - lineDiscount, taxClassId, taxInclusive);
  const total = roundCurrency(price - lineDiscount + taxAmount);

  updates.push('tax_amount = ?', 'total = ?', 'updated_at = ?');
  params.push(taxAmount, total, now());
  params.push(deviceId);

  db.prepare(`UPDATE ticket_devices SET ${updates.join(', ')} WHERE id = ?`).run(...params);

  recalcTicketTotals(db, existing.ticket_id);
  insertHistory(db, existing.ticket_id, userId, 'device_updated', `Device updated: ${req.body.device_name || existing.device_name}`);

  const device = db.prepare('SELECT * FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow;
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: existing.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: { ...device, pre_conditions: parseJsonCol(device.pre_conditions, []), post_conditions: parseJsonCol(device.post_conditions, []) } });
}));

// ===================================================================
// DELETE /devices/:deviceId - Remove device
// ===================================================================
router.delete('/devices/:deviceId', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const existing = db.prepare('SELECT id, ticket_id, device_name FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!existing) throw new AppError('Device not found', 404);

  const remove = db.transaction(() => {
    // Restore inventory for parts
    const parts = db.prepare('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?').all(deviceId) as AnyRow[];
    for (const part of parts) {
      db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?')
        .run(part.quantity, now(), part.inventory_item_id);

      db.prepare(`
        INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
        VALUES (?, 'ticket_return', ?, 'ticket_device', ?, 'Device removed from ticket', ?, ?, ?)
      `).run(part.inventory_item_id, part.quantity, deviceId, userId, now(), now());
    }

    // Delete photos from disk (tenant-scoped path)
    const tenantSlug = (req as any).tenantSlug || '';
    const uploadsBase = tenantSlug ? path.join(config.uploadsPath, tenantSlug) : config.uploadsPath;
    const photos = db.prepare('SELECT file_path FROM ticket_photos WHERE ticket_device_id = ?').all(deviceId) as AnyRow[];
    for (const photo of photos) {
      try { fs.unlinkSync(path.join(uploadsBase, photo.file_path)); } catch { /* ignore */ }
    }

    // CASCADE will handle ticket_device_parts, ticket_photos, ticket_checklists
    db.prepare('DELETE FROM ticket_devices WHERE id = ?').run(deviceId);

    recalcTicketTotals(db, existing.ticket_id);
    insertHistory(db, existing.ticket_id, userId, 'device_removed', `Device removed: ${existing.device_name}`);
  });

  remove();
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: existing.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: { id: deviceId } });
}));

// ===================================================================
// POST /devices/:deviceId/parts - Add parts to device
// ===================================================================
router.post('/devices/:deviceId/parts', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = db.prepare('SELECT id, ticket_id FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!device) throw new AppError('Device not found', 404);

  // SW-D1: Block adding inventory parts when ticket_show_inventory is disabled
  const showInventoryCfg = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_show_inventory'").get() as AnyRow | undefined;
  if (showInventoryCfg?.value === '0') {
    throw new AppError('Inventory part selection is disabled', 403);
  }

  const { inventory_item_id, quantity, price, warranty, serial } = req.body;
  if (!inventory_item_id) throw new AppError('inventory_item_id is required');
  if (!quantity || quantity < 1) throw new AppError('quantity must be at least 1');

  const item = db.prepare('SELECT id, name, in_stock, is_serialized FROM inventory_items WHERE id = ?').get(inventory_item_id) as AnyRow | undefined;
  if (!item) throw new AppError('Inventory item not found', 404);
  if (item.in_stock < quantity) {
    throw new AppError(`Insufficient stock for ${item.name}: ${item.in_stock} available, ${quantity} needed`, 400);
  }

  // ENR-INV4: Serial number enforcement for serialized items
  if (item.is_serialized === 1 && !serial) {
    throw new AppError('Serial number required for serialized items', 400);
  }

  const addPart = db.transaction(() => {
    const result = db.prepare(`
      INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(deviceId, inventory_item_id, quantity, price ?? 0, warranty ? 1 : 0, serial ?? null, now(), now());

    // Decrease stock
    db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?')
      .run(quantity, now(), inventory_item_id);

    // Stock movement
    const ticket = db.prepare('SELECT order_id FROM tickets WHERE id = ?').get(device.ticket_id) as AnyRow;
    db.prepare(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
      VALUES (?, 'ticket_usage', ?, 'ticket_device', ?, ?, ?, ?, ?)
    `).run(inventory_item_id, -quantity, deviceId, `Part added to ticket ${ticket.order_id}`, userId, now(), now());

    recalcTicketTotals(db, device.ticket_id);
    insertHistory(db, device.ticket_id, userId, 'part_added', `Part added: ${item.name} x${quantity}`);

    return Number(result.lastInsertRowid);
  });

  const partId = addPart();
  const part = db.prepare(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: device.ticket_id }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: part });
}));

// ===================================================================
// POST /devices/:deviceId/quick-add-part - Create inventory item + add to device in one step
// ===================================================================
router.post('/devices/:deviceId/quick-add-part', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = db.prepare('SELECT id, ticket_id FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!device) throw new AppError('Device not found', 404);

  const { name, price, quantity: rawQty } = req.body;
  if (!name || !name.trim()) throw new AppError('Name is required');
  if (price == null || Number(price) < 0) throw new AppError('Valid price is required');
  const quantity = Math.max(1, parseInt(rawQty) || 1);
  const itemPrice = Number(price);

  const sku = `QA-${Date.now()}`;

  const run = db.transaction(() => {
    // 1. Create inventory item
    const itemResult = db.prepare(`
      INSERT INTO inventory_items (name, sku, item_type, cost_price, retail_price, in_stock, created_at, updated_at)
      VALUES (?, ?, 'part', ?, ?, ?, ?, ?)
    `).run(name.trim(), sku, itemPrice, itemPrice, quantity, now(), now());
    const inventoryItemId = Number(itemResult.lastInsertRowid);

    // 2. Add part to device
    const partResult = db.prepare(`
      INSERT INTO ticket_device_parts (ticket_device_id, inventory_item_id, quantity, price, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'available', ?, ?)
    `).run(deviceId, inventoryItemId, quantity, itemPrice, now(), now());

    // 3. Deduct stock
    db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?')
      .run(quantity, now(), inventoryItemId);

    // 4. Stock movement
    const ticket = db.prepare('SELECT order_id FROM tickets WHERE id = ?').get(device.ticket_id) as AnyRow;
    db.prepare(`
      INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
      VALUES (?, 'ticket_usage', ?, 'ticket_device', ?, ?, ?, ?, ?)
    `).run(inventoryItemId, -quantity, deviceId, `Quick-add part for ticket ${ticket.order_id}`, userId, now(), now());

    recalcTicketTotals(db, device.ticket_id);
    insertHistory(db, device.ticket_id, userId, 'part_added', `Quick-added part: ${name.trim()} x${quantity} @ $${itemPrice.toFixed(2)}`);

    return Number(partResult.lastInsertRowid);
  });

  const partId = run();
  const part = db.prepare(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: device.ticket_id }, req.tenantSlug || null);

  res.status(201).json({ success: true, data: part });
}));

// ===================================================================
// DELETE /devices/parts/:partId - Remove part from device
// ===================================================================
router.delete('/devices/parts/:partId', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const partId = parseInt(req.params.partId);
  const userId = req.user!.id;
  if (!partId) throw new AppError('Invalid part ID');

  const part = db.prepare(`
    SELECT tdp.*, td.ticket_id, ii.name AS item_name
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow | undefined;
  if (!part) throw new AppError('Part not found', 404);

  const removePart = db.transaction(() => {
    // Return stock if it was deducted
    if (part.inventory_item_id) {
      db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?')
        .run(part.quantity, now(), part.inventory_item_id);

      db.prepare(`
        INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
        VALUES (?, 'ticket_return', ?, 'ticket_device', ?, 'Part removed from ticket', ?, ?, ?)
      `).run(part.inventory_item_id, part.quantity, part.ticket_device_id, userId, now(), now());
    }

    db.prepare('DELETE FROM ticket_device_parts WHERE id = ?').run(partId);
    recalcTicketTotals(db, part.ticket_id);
    insertHistory(db, part.ticket_id, userId, 'part_removed', `Part removed: ${part.item_name || 'Unknown'} x${part.quantity}`);
  });

  removePart();
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: part.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: { id: partId } });
}));

// ===================================================================
// PATCH /devices/parts/:partId - Update part supplier linking
// ===================================================================
router.patch('/devices/parts/:partId', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const partId = parseInt(req.params.partId);
  const userId = req.user!.id;
  if (!partId) throw new AppError('Invalid part ID');

  const part = db.prepare(`
    SELECT tdp.*, td.ticket_id
    FROM ticket_device_parts tdp
    JOIN ticket_devices td ON td.id = tdp.ticket_device_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow | undefined;
  if (!part) throw new AppError('Part not found', 404);

  const { catalog_item_id, supplier_url } = req.body;

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

  if (updates.length === 0) throw new AppError('No fields to update');

  updates.push('updated_at = ?');
  values.push(now());
  values.push(partId);

  db.prepare(`UPDATE ticket_device_parts SET ${updates.join(', ')} WHERE id = ?`).run(...values);
  insertHistory(db, part.ticket_id, userId, 'part_updated', 'Part supplier info updated');
  db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), part.ticket_id);

  const updated = db.prepare(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: part.ticket_id }, req.tenantSlug || null);

  res.json({ success: true, data: updated });
}));

// ===================================================================
// PUT /devices/:deviceId/checklist - Update checklist items
// ===================================================================
router.put('/devices/:deviceId/checklist', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const deviceId = parseInt(req.params.deviceId);
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = await adb.get<AnyRow>('SELECT id, ticket_id FROM ticket_devices WHERE id = ?', deviceId);
  if (!device) throw new AppError('Device not found', 404);

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

  const checklist = await adb.get<AnyRow>('SELECT * FROM ticket_checklists WHERE ticket_device_id = ?', deviceId);

  res.json({ success: true, data: { ...checklist, items: parseJsonCol(checklist.items, []) } });
}));

// ===================================================================
// POST /devices/:deviceId/loaner - Assign loaner device
// ===================================================================
router.post('/devices/:deviceId/loaner', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = db.prepare('SELECT td.id, td.ticket_id, t.customer_id FROM ticket_devices td JOIN tickets t ON t.id = td.ticket_id WHERE td.id = ?').get(deviceId) as AnyRow | undefined;
  if (!device) throw new AppError('Device not found', 404);

  const { loaner_device_id } = req.body;
  if (!loaner_device_id) throw new AppError('loaner_device_id is required');

  const loaner = db.prepare("SELECT * FROM loaner_devices WHERE id = ? AND status = 'available'").get(loaner_device_id) as AnyRow | undefined;
  if (!loaner) throw new AppError('Loaner device not available', 400);

  const assign = db.transaction(() => {
    // Mark loaner as loaned
    db.prepare("UPDATE loaner_devices SET status = 'loaned', updated_at = ? WHERE id = ?").run(now(), loaner_device_id);

    // Insert loaner history
    db.prepare(`
      INSERT INTO loaner_history (loaner_device_id, ticket_device_id, customer_id, loaned_at, condition_out)
      VALUES (?, ?, ?, ?, ?)
    `).run(loaner_device_id, deviceId, device.customer_id, now(), loaner.condition);

    // Link to ticket device
    db.prepare('UPDATE ticket_devices SET loaner_device_id = ?, updated_at = ? WHERE id = ?').run(loaner_device_id, now(), deviceId);

    insertHistory(db, device.ticket_id, userId, 'loaner_assigned', `Loaner device assigned: ${loaner.name}`);
    db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), device.ticket_id);
  });

  assign();

  res.status(201).json({ success: true, data: { loaner_device_id, device_id: deviceId, loaner_name: loaner.name } });
}));

// ===================================================================
// DELETE /devices/:deviceId/loaner - Return loaner device
// ===================================================================
router.delete('/devices/:deviceId/loaner', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = db.prepare('SELECT id, ticket_id, loaner_device_id FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!device) throw new AppError('Device not found', 404);
  if (!device.loaner_device_id) throw new AppError('No loaner device assigned', 400);

  const returnLoaner = db.transaction(() => {
    // Mark loaner as available
    db.prepare("UPDATE loaner_devices SET status = 'available', updated_at = ? WHERE id = ?").run(now(), device.loaner_device_id);

    // Update loaner history
    db.prepare(`
      UPDATE loaner_history SET returned_at = ?, condition_in = ?
      WHERE loaner_device_id = ? AND ticket_device_id = ? AND returned_at IS NULL
    `).run(now(), req.body.condition_in ?? null, device.loaner_device_id, deviceId);

    // Unlink from ticket device
    db.prepare('UPDATE ticket_devices SET loaner_device_id = NULL, updated_at = ? WHERE id = ?').run(now(), deviceId);

    insertHistory(db, device.ticket_id, userId, 'loaner_returned', 'Loaner device returned');
    db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), device.ticket_id);
  });

  returnLoaner();

  res.json({ success: true, data: { device_id: deviceId } });
}));

// ---------------------------------------------------------------------------
// OTP verify rate limiter (5 attempts per 15 minutes per IP+ticket)
// ---------------------------------------------------------------------------
const otpVerifyLimiter = new Map<string, number[]>();

function checkOtpRate(key: string): boolean {
  const rateNow = Date.now();
  const windowMs = 15 * 60 * 1000;
  const maxAttempts = 5;
  const timestamps = otpVerifyLimiter.get(key) || [];
  const filtered = timestamps.filter(t => rateNow - t < windowMs);
  if (filtered.length >= maxAttempts) return false;
  filtered.push(rateNow);
  otpVerifyLimiter.set(key, filtered);
  return true;
}

// Clean up OTP rate limiter every 5 minutes
setInterval(() => {
  const cleanNow = Date.now();
  for (const [k, v] of otpVerifyLimiter) {
    const filtered = v.filter(t => cleanNow - t < 15 * 60 * 1000);
    if (filtered.length === 0) otpVerifyLimiter.delete(k); else otpVerifyLimiter.set(k, filtered);
  }
}, 5 * 60 * 1000);

// ===================================================================
// POST /:id/otp - Generate OTP
// ===================================================================
router.post('/:id/otp', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
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
    console.error(`[OTP] Failed to send SMS to ${phone}:`, err);
  }

  // Never return the OTP code in the response — it should only be sent via SMS
  res.status(201).json({ success: true, data: { expires_at: expiresAt, phone, message: 'OTP sent via SMS' } });
}));

// ===================================================================
// POST /:id/verify-otp - Verify OTP
// ===================================================================
router.post('/:id/verify-otp', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  // Rate limit: 5 attempts per 15 minutes per IP+ticket
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const rateLimitKey = `${ip}:${ticketId}`;
  if (!checkOtpRate(rateLimitKey)) {
    throw new AppError('Too many OTP verification attempts. Try again later.', 429);
  }

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
router.post('/bulk-action', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
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

  const doBulk = db.transaction(() => {
    const affected: number[] = [];

    for (const id of ticket_ids) {
      const ticket = db.prepare('SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0').get(id) as AnyRow | undefined;
      if (!ticket) continue;

      switch (action) {
        case 'change_status': {
          if (!value) throw new AppError('value (status_id) is required for change_status');
          const oldStatus = db.prepare('SELECT name FROM ticket_statuses WHERE id = ?').get(ticket.status_id) as AnyRow;
          const newStatus = db.prepare('SELECT name, notify_customer, is_closed FROM ticket_statuses WHERE id = ?').get(value) as AnyRow | undefined;
          if (!newStatus) throw new AppError(`Status ${value} not found`, 404);

          // AUD-M1: Pre-close validation (same checks as single status change)
          if (newStatus.is_closed) {
            const requirePostCond = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_post_condition'").get() as AnyRow | undefined;
            if (requirePostCond?.value === '1' || requirePostCond?.value === 'true') {
              const devices = db.prepare('SELECT id, device_name, post_conditions FROM ticket_devices WHERE ticket_id = ?').all(id) as AnyRow[];
              for (const d of devices) {
                const postConds = d.post_conditions ? JSON.parse(d.post_conditions) : [];
                if (postConds.length === 0) throw new AppError(`Post-conditions required for ${d.device_name} on ticket ${id} before closing`, 400);
              }
            }

            const requireParts = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_parts'").get() as AnyRow | undefined;
            if (requireParts?.value === '1' || requireParts?.value === 'true') {
              const partsCount = db.prepare('SELECT COUNT(*) as c FROM ticket_device_parts tdp JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?').get(id) as AnyRow;
              if (partsCount.c === 0) throw new AppError(`At least one part must be added to ticket ${id} before closing`, 400);
            }

            // SW-D5: Require repair timer / stopwatch usage before closing (bulk)
            const requireStopwatch = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_require_stopwatch'").get() as AnyRow | undefined;
            if (requireStopwatch?.value === '1') {
              const activeTime = calculateActiveRepairTime(db, id);
              if (activeTime === null || activeTime <= 0) {
                throw new AppError(`Repair timer must be started for ticket ${id} before closing`, 400);
              }
            }
          }

          // Require diagnostic note before any status change (same as single)
          const requireDiag = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_diagnostic'").get() as AnyRow | undefined;
          if (requireDiag?.value === '1' || requireDiag?.value === 'true') {
            const diagNote = db.prepare("SELECT id FROM ticket_notes WHERE ticket_id = ? AND type = 'diagnostic' LIMIT 1").get(id) as AnyRow | undefined;
            if (!diagNote) throw new AppError(`A diagnostic note is required for ticket ${id} before changing status`, 400);
          }

          db.prepare('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?').run(value, now(), id);

          // AUD-M2: Sync device-level statuses to match ticket status
          db.prepare('UPDATE ticket_devices SET status_id = ?, updated_at = ? WHERE ticket_id = ?').run(value, now(), id);

          insertHistory(db, id, userId, 'status_changed', `Bulk status change: "${oldStatus.name}" to "${newStatus.name}"`, oldStatus.name, newStatus.name);
          if (newStatus.notify_customer) {
            import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
              sendTicketStatusNotification(db, { ticketId: id, statusName: newStatus.name, tenantSlug: req.tenantSlug || null });
            }).catch(() => {});
          }
          affected.push(id);
          break;
        }
        case 'assign': {
          db.prepare('UPDATE tickets SET assigned_to = ?, updated_at = ? WHERE id = ?').run(value ?? null, now(), id);
          insertHistory(db, id, userId, 'assigned', value ? `Bulk assigned to user ${value}` : 'Bulk unassigned');
          affected.push(id);
          break;
        }
        case 'delete': {
          if (req.user?.role !== 'admin') throw new AppError('Only admins can bulk delete', 403);

          // Restore inventory stock for all parts on all devices in this ticket
          const devices = db.prepare('SELECT id FROM ticket_devices WHERE ticket_id = ?').all(id) as AnyRow[];
          for (const dev of devices) {
            const parts = db.prepare('SELECT * FROM ticket_device_parts WHERE ticket_device_id = ?').all(dev.id) as AnyRow[];
            for (const part of parts) {
              if (part.inventory_item_id) {
                db.prepare('UPDATE inventory_items SET in_stock = in_stock + ?, updated_at = ? WHERE id = ?')
                  .run(part.quantity, now(), part.inventory_item_id);

                db.prepare(`
                  INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
                  VALUES (?, 'ticket_return', ?, 'ticket', ?, 'Stock restored — ticket bulk deleted', ?, ?, ?)
                `).run(part.inventory_item_id, part.quantity, id, userId, now(), now());
              }
            }
          }

          db.prepare('UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ?').run(now(), id);
          insertHistory(db, id, userId, 'deleted', 'Bulk deleted');
          affected.push(id);
          break;
        }
      }
    }

    return affected;
  });

  const affected = doBulk();

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
  const ticketId = parseInt(req.params.id);
  const feedback = await adb.all<AnyRow>('SELECT * FROM customer_feedback WHERE ticket_id = ? ORDER BY created_at DESC', ticketId);
  res.json({ success: true, data: feedback });
}));

// ===================================================================
// POST /:id/feedback - Submit feedback for a ticket
// ===================================================================
router.post('/:id/feedback', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
  const { rating, comment, source = 'web' } = req.body;

  const [feedbackCfg, ticket] = await Promise.all([
    adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'feedback_enabled'"),
    adb.get<AnyRow>('SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId),
  ]);

  if (feedbackCfg?.value === '0' || feedbackCfg?.value === 'false') {
    throw new AppError('Feedback is disabled', 400);
  }
  if (!rating || rating < 1 || rating > 5) throw new AppError('Rating must be 1-5', 400);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const result = await adb.run(`
    INSERT INTO customer_feedback (ticket_id, customer_id, rating, comment, source, responded_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, ticketId, ticket.customer_id, rating, comment || null, source, now(), now(), now());

  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// ===================================================================
// POST /:id/appointment - Create appointment linked to this ticket
// ===================================================================
router.post('/:id/appointment', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id);
  const { start_time, end_time, note } = req.body;

  if (!start_time) throw new AppError('start_time is required', 400);

  const ticket = await adb.get<AnyRow>('SELECT id, customer_id, order_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);

  const title = `Ticket #${ticket.order_id} appointment`;

  const result = await adb.run(`
    INSERT INTO appointments (ticket_id, customer_id, title, start_time, end_time, assigned_to, status, notes)
    VALUES (?, ?, ?, ?, ?, ?, 'scheduled', ?)
  `,
    ticketId,
    ticket.customer_id,
    title,
    start_time,
    end_time || null,
    req.user!.id,
    note || null,
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
  const ticketId = parseInt(req.params.id);

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
router.post('/merge', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const userId = req.user!.id;

  if (req.user!.role !== 'admin') {
    throw new AppError('Only admins can merge tickets', 403);
  }

  const { keep_id, merge_id } = req.body;
  if (!keep_id || !merge_id) throw new AppError('keep_id and merge_id are required', 400);
  if (keep_id === merge_id) throw new AppError('Cannot merge a ticket with itself', 400);

  const keepTicket = db.prepare('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0').get(keep_id) as AnyRow | undefined;
  if (!keepTicket) throw new AppError('Keep ticket not found', 404);

  const mergeTicket = db.prepare('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0').get(merge_id) as AnyRow | undefined;
  if (!mergeTicket) throw new AppError('Merge ticket not found', 404);

  const doMerge = db.transaction(() => {
    // Move all devices from merge_id to keep_id
    db.prepare('UPDATE ticket_devices SET ticket_id = ?, updated_at = ? WHERE ticket_id = ?')
      .run(keep_id, now(), merge_id);

    // Move all notes
    db.prepare('UPDATE ticket_notes SET ticket_id = ? WHERE ticket_id = ?')
      .run(keep_id, merge_id);

    // Move all history entries
    db.prepare('UPDATE ticket_history SET ticket_id = ? WHERE ticket_id = ?')
      .run(keep_id, merge_id);

    // Move all photos (ticket-level, not device-level -- device photos moved with devices)
    db.prepare('UPDATE ticket_photos SET ticket_id = ? WHERE ticket_id = ? AND ticket_device_id IS NULL')
      .run(keep_id, merge_id);

    // Move any ticket_links referencing merge_id
    db.prepare('UPDATE ticket_links SET ticket_id_a = ? WHERE ticket_id_a = ?')
      .run(keep_id, merge_id);
    db.prepare('UPDATE ticket_links SET ticket_id_b = ? WHERE ticket_id_b = ?')
      .run(keep_id, merge_id);
    // Remove self-links that may have resulted
    db.prepare('DELETE FROM ticket_links WHERE ticket_id_a = ticket_id_b').run();

    // Recalculate totals on keep ticket
    recalcTicketTotals(db, keep_id);

    // Soft-delete the merged ticket
    db.prepare('UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ?')
      .run(now(), merge_id);

    // History on keep ticket
    insertHistory(db, keep_id, userId, 'merged',
      `Merged ticket #${mergeTicket.order_id} (ID ${merge_id}) into this ticket`);

    // History on merged ticket
    insertHistory(db, merge_id, userId, 'merged',
      `Merged into ticket #${keepTicket.order_id} (ID ${keep_id})`);

    // Audit log
    audit(db, 'ticket_merged', userId, (req as any).ip || 'unknown', {
      keep_id, merge_id,
      keep_order_id: keepTicket.order_id,
      merge_order_id: mergeTicket.order_id,
    });
  });

  doMerge();

  const ticket = await getFullTicketAsync(req.asyncDb, keep_id);
  broadcast(WS_EVENTS.TICKET_UPDATED, ticket, req.tenantSlug || null);
  broadcast(WS_EVENTS.TICKET_DELETED, { id: merge_id }, req.tenantSlug || null);

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// POST /:id/link - Link two tickets
// ===================================================================
router.post('/:id/link', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const ticketId = parseInt(req.params.id);

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
  const ticketId = parseInt(req.params.id);

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
router.delete('/links/:linkId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const linkId = parseInt(req.params.linkId);

  const link = await adb.get<AnyRow>('SELECT * FROM ticket_links WHERE id = ?', linkId);
  if (!link) throw new AppError('Link not found', 404);

  await adb.run('DELETE FROM ticket_links WHERE id = ?', linkId);

  res.json({ success: true, data: { message: 'Link removed' } });
}));

// ===================================================================
// POST /:id/clone-warranty - Clone ticket as warranty case
// ===================================================================
router.post('/:id/clone-warranty', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const userId = req.user!.id;
  const sourceId = parseInt(req.params.id);

  const source = db.prepare('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0').get(sourceId) as AnyRow | undefined;
  if (!source) throw new AppError('Source ticket not found', 404);

  const cloneTicket = db.transaction(() => {
    // Get default status
    const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get() as AnyRow | undefined;
    const statusId = defaultStatus?.id ?? 1;

    // Generate new order_id
    const seqRow = db.prepare("SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 3) AS INTEGER)), 0) + 1 as next_num FROM tickets").get() as AnyRow;
    const orderId = generateOrderId('T', seqRow.next_num);

    // Generate tracking token
    const trackingToken = crypto.randomBytes(16).toString('hex');

    // Insert new ticket as warranty case
    const result = db.prepare(`
      INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                           source, referral_source, labels, due_on, is_warranty, created_by,
                           tracking_token, created_at, updated_at)
      VALUES (?, ?, ?, ?, 0, NULL, ?, NULL, '[]', NULL, 1, ?, ?, ?, ?)
    `).run(
      orderId,
      source.customer_id,
      statusId,
      source.assigned_to,
      'warranty',
      userId,
      trackingToken,
      now(),
      now(),
    );

    const newTicketId = Number(result.lastInsertRowid);

    // Copy devices (without parts -- warranty gets fresh assessment)
    const devices = db.prepare('SELECT * FROM ticket_devices WHERE ticket_id = ?').all(sourceId) as AnyRow[];
    for (const dev of devices) {
      db.prepare(`
        INSERT INTO ticket_devices (ticket_id, device_name, device_type, device_model_id, service_name,
                                    imei, serial, security_code, color, network, status_id, assigned_to,
                                    service_id, price, line_discount, tax_amount, tax_class_id, tax_inclusive,
                                    total, warranty, warranty_days, due_on, device_location,
                                    additional_notes, pre_conditions, post_conditions,
                                    created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?, 0, 0, 1, ?, NULL, ?, ?, '[]', '[]', ?, ?)
      `).run(
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
    recalcTicketTotals(db, newTicketId);

    // Link to original ticket
    const idA = Math.min(sourceId, newTicketId);
    const idB = Math.max(sourceId, newTicketId);
    db.prepare(
      'INSERT INTO ticket_links (ticket_id_a, ticket_id_b, link_type, created_by) VALUES (?, ?, ?, ?)'
    ).run(idA, idB, 'warranty_followup', userId);

    // History on new ticket
    insertHistory(db, newTicketId, userId, 'created', `Warranty case cloned from ticket #${source.order_id} (ID ${sourceId})`);

    // History on source ticket
    insertHistory(db, sourceId, userId, 'linked', `Warranty case #${orderId} created from this ticket`);

    return newTicketId;
  });

  const newTicketId = cloneTicket();
  const ticket = getFullTicket(db, newTicketId);

  broadcast(WS_EVENTS.TICKET_CREATED, ticket, req.tenantSlug || null);

  res.status(201).json({ success: true, data: ticket });
}));

export default router;
