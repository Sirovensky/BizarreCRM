import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { db } from '../db/connection.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import { generateOrderId } from '../utils/format.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { config } from '../config.js';
import { validatePrice } from '../utils/validate.js';
import { runAutomations } from '../services/automations.js';
import { idempotent } from '../middleware/idempotency.js';
import { calculateActiveRepairTime } from '../utils/repair-time.js';
import { roundCurrency } from '../utils/currency.js';

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
    destination: (_req, _file, cb) => cb(null, config.uploadsPath),
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

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function parseJsonCol(val: any, fallback: any = []): any {
  if (!val) return fallback;
  try { return JSON.parse(val); } catch { return fallback; }
}

function calcTax(price: number, taxClassId: number | null, taxInclusive: boolean): number {
  if (!taxClassId) return 0;
  const tc = db.prepare('SELECT rate FROM tax_classes WHERE id = ?').get(taxClassId) as AnyRow | undefined;
  if (!tc) return 0;
  const rate = tc.rate / 100;
  if (taxInclusive) return roundCurrency(price - price / (1 + rate));
  return roundCurrency(price * rate);
}

function insertHistory(ticketId: number, userId: number | null, action: string, description: string, oldValue?: string | null, newValue?: string | null): void {
  db.prepare(
    `INSERT INTO ticket_history (ticket_id, user_id, action, description, old_value, new_value)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(ticketId, userId, action, description, oldValue ?? null, newValue ?? null);
}

function getFullTicket(ticketId: number): AnyRow | null {
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

function recalcTicketTotals(ticketId: number): void {
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
// (asyncHandler imported from ../middleware/asyncHandler.js)

// ===================================================================
// GET /my-queue - Lightweight ticket counts for current user
// ===================================================================
router.get('/my-queue', asyncHandler(async (req: Request, res: Response) => {
  const userId = (req as any).user?.id;
  if (!userId) {
    res.json({ success: true, data: { total: 0, open: 0, waiting_parts: 0, in_progress: 0 } });
    return;
  }

  const row = db.prepare(`
    SELECT
      COUNT(*) AS total,
      SUM(CASE WHEN ts.name = 'Open' THEN 1 ELSE 0 END) AS open,
      SUM(CASE WHEN ts.name IN ('Waiting for Parts', 'Special Part Order (Pending Parts)') THEN 1 ELSE 0 END) AS waiting_parts,
      SUM(CASE WHEN ts.name = 'In Progress' THEN 1 ELSE 0 END) AS in_progress
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.is_deleted = 0 AND ts.is_closed = 0 AND ts.is_cancelled = 0
      AND t.assigned_to = ?
  `).get(userId) as any;

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

  // Keyword search: order_id, customer name, device names
  let keywordJoin = '';
  if (keyword) {
    keywordJoin = 'LEFT JOIN ticket_devices td_kw ON td_kw.ticket_id = t.id';
    conditions.push(`(
      t.order_id LIKE ? OR
      c.first_name LIKE ? OR c.last_name LIKE ? OR
      (c.first_name || ' ' || c.last_name) LIKE ? OR
      td_kw.device_name LIKE ?
    )`);
    const like = `%${keyword}%`;
    params.push(like, like, like, like, like);
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
  const countRow = db.prepare(countSql).get(...params) as AnyRow;
  const totalCount = countRow.total;

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
           (SELECT content FROM ticket_notes WHERE ticket_id = t.id AND type = 'internal' ORDER BY created_at DESC LIMIT 1) AS latest_internal_note,
           (SELECT content FROM ticket_notes WHERE ticket_id = t.id AND type = 'diagnostic' ORDER BY created_at DESC LIMIT 1) AS latest_diagnostic_note
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    LEFT JOIN users u ON u.id = t.assigned_to
    ${keywordJoin}
    ${whereClause}
    ORDER BY t.is_pinned DESC, ${safeSortBy} ${sortOrder}
    LIMIT ? OFFSET ?
  `;
  const dataParams = [...params, pageSize, offset];
  const rows = db.prepare(dataSql).all(...dataParams) as AnyRow[];

  // Batch-fetch device info for all ticket IDs (eliminates N+1)
  const ticketIds = rows.map(r => r.id);
  const deviceMap = new Map<number, AnyRow>();
  const countMap = new Map<number, number>();
  const partsCountMap = new Map<number, number>();
  const partsListMap = new Map<number, string[]>();
  const latestSmsMap = new Map<number, { message: string; direction: string; date_time: string }>();

  if (ticketIds.length > 0) {
    const placeholders = ticketIds.map(() => '?').join(',');
    const devices = db.prepare(`
      SELECT td.ticket_id, td.device_name, td.additional_notes, td.device_type,
             td.imei, td.serial, td.security_code, td.service_id,
             COALESCE(td.service_name, ii.name) AS service_name,
             ROW_NUMBER() OVER (PARTITION BY td.ticket_id ORDER BY td.id ASC) AS rn
      FROM ticket_devices td
      LEFT JOIN inventory_items ii ON ii.id = td.service_id
      WHERE td.ticket_id IN (${placeholders})
    `).all(...ticketIds) as AnyRow[];
    for (const d of devices) {
      if (d.rn === 1) deviceMap.set(d.ticket_id, d);
      countMap.set(d.ticket_id, (countMap.get(d.ticket_id) || 0) + 1);
    }

    // Parts counts + names per ticket
    const parts = db.prepare(`
      SELECT td.ticket_id, tdp.inventory_item_id, ii.name AS item_name
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      WHERE td.ticket_id IN (${placeholders})
    `).all(...ticketIds) as AnyRow[];
    for (const p of parts) {
      partsCountMap.set(p.ticket_id, (partsCountMap.get(p.ticket_id) || 0) + 1);
      const list = partsListMap.get(p.ticket_id) || [];
      list.push(p.item_name || 'Unknown part');
      partsListMap.set(p.ticket_id, list);
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
        const smsRows = db.prepare(`
          SELECT s.id, s.message, s.direction, s.created_at, s.from_number, s.to_number
          FROM sms_messages s
          INNER JOIN (
            SELECT MAX(id) as max_id FROM sms_messages
            WHERE (from_number IN (${phonePlaceholders}) OR to_number IN (${phonePlaceholders}))
            GROUP BY CASE WHEN direction = 'inbound' THEN from_number ELSE to_number END
          ) latest ON s.id = latest.max_id
        `).all(...phoneList, ...phoneList) as AnyRow[];

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
    };
  });

  // Status counts for overview bar
  const statusCounts = db.prepare(`
    SELECT ts.id, ts.name, ts.color, ts.sort_order, COUNT(t.id) AS count
    FROM ticket_statuses ts
    LEFT JOIN tickets t ON t.status_id = ts.id AND t.is_deleted = 0
    GROUP BY ts.id
    ORDER BY ts.sort_order ASC
  `).all() as AnyRow[];

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
  const userId = req.user!.id;
  const body = req.body;

  if (!body.customer_id) throw new AppError('customer_id is required');
  if (!body.devices || !Array.isArray(body.devices) || body.devices.length === 0) {
    throw new AppError('At least one device is required');
  }

  // Verify customer exists
  const customer = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(body.customer_id) as AnyRow | undefined;
  if (!customer) throw new AppError('Customer not found', 404);

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
    const trackingToken = crypto.randomUUID().split('-')[0]; // 8-char hex

    // Insert ticket
    const ticketResult = db.prepare(`
      INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, discount, discount_reason,
                           source, referral_source, labels, due_on, created_by, tracking_token, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      now(),
      now(),
    );

    const ticketId = Number(ticketResult.lastInsertRowid);

    // Insert devices
    for (const dev of body.devices) {
      const devicePrice = validatePrice(dev.price ?? 0, 'device price');
      const lineDiscount = dev.line_discount ?? 0;
      const taxAmount = calcTax(devicePrice - lineDiscount, dev.tax_class_id ?? null, dev.tax_inclusive ?? false);
      const deviceTotal = roundCurrency(devicePrice - lineDiscount + taxAmount);

      const devResult = db.prepare(`
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
        dev.status_id ?? statusId,
        dev.assigned_to ?? body.assigned_to ?? null,
        dev.service_id ?? null,
        devicePrice,
        lineDiscount,
        taxAmount,
        dev.tax_class_id ?? null,
        dev.tax_inclusive ? 1 : 0,
        deviceTotal,
        dev.warranty ? 1 : 0,
        dev.warranty_days ?? (() => {
          // F15: Auto-fill default warranty from settings
          const wVal = db.prepare("SELECT value FROM store_config WHERE key = 'repair_default_warranty_value'").get() as AnyRow | undefined;
          return wVal?.value ? parseInt(wVal.value) : 0;
        })(),
        dev.due_on ?? null,
        dev.device_location ?? null,
        dev.additional_notes ?? null,
        JSON.stringify(dev.pre_conditions ?? []),
        JSON.stringify(dev.post_conditions ?? []),
        now(),
        now(),
      );

      const deviceId = Number(devResult.lastInsertRowid);

      // Insert parts and update inventory
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

          // Decrease inventory stock
          db.prepare('UPDATE inventory_items SET in_stock = in_stock - ?, updated_at = ? WHERE id = ?')
            .run(part.quantity, now(), part.inventory_item_id);

          // Stock movement
          db.prepare(`
            INSERT INTO stock_movements (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id, created_at, updated_at)
            VALUES (?, 'ticket_usage', ?, 'ticket', ?, ?, ?, ?, ?)
          `).run(part.inventory_item_id, -part.quantity, ticketId, `Used in ticket ${orderId}`, userId, now(), now());
        }
      }
    }

    // Recalculate totals
    recalcTicketTotals(ticketId);

    // History
    insertHistory(ticketId, userId, 'created', 'Ticket created');

    // Check if status should notify customer
    const status = db.prepare('SELECT notify_customer, name FROM ticket_statuses WHERE id = ?').get(statusId) as AnyRow | undefined;
    if (status?.notify_customer) {
      import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
        sendTicketStatusNotification({ ticketId, statusName: status.name });
      }).catch(() => {});
    }

    return ticketId;
  });

  const ticketId = createTicket();
  const ticket = getFullTicket(ticketId);

  broadcast(WS_EVENTS.TICKET_CREATED, ticket);

  // Fire automations (async, non-blocking)
  const cust = db.prepare('SELECT * FROM customers WHERE id = ?').get(body.customer_id) as AnyRow | undefined;
  runAutomations('ticket_created', { ticket, customer: cust ?? {} });

  res.status(201).json({ success: true, data: ticket });
}));

// ===================================================================
// GET /kanban - Tickets grouped by status for kanban view
// ===================================================================
router.get('/kanban', asyncHandler(async (req: Request, res: Response) => {
  const statuses = db.prepare('SELECT * FROM ticket_statuses ORDER BY sort_order ASC').all() as AnyRow[];

  const columns = statuses.map((status) => {
    const tickets = db.prepare(`
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
    `).all(status.id) as AnyRow[];

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
  });

  res.json({ success: true, data: { columns } });
}));

// ===================================================================
// GET /stalled - Stalled tickets
// ===================================================================
router.get('/stalled', asyncHandler(async (req: Request, res: Response) => {
  let days = parseInt(req.query.days as string) || 0;
  if (!days) {
    const cfg = db.prepare("SELECT value FROM store_config WHERE key = 'stall_alert_days'").get() as AnyRow | undefined;
    days = cfg ? parseInt(cfg.value) || 3 : 3;
  }

  const tickets = db.prepare(`
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
  `).all(`-${days}`) as AnyRow[];

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
  const imei = (req.query.imei as string || '').trim();
  const serial = (req.query.serial as string || '').trim();
  if (!imei && !serial) throw new AppError('imei or serial required', 400);

  const conditions: string[] = ['t.is_deleted = 0'];
  const params: any[] = [];
  if (imei) { conditions.push('td.imei = ?'); params.push(imei); }
  if (serial) { conditions.push('td.serial = ?'); params.push(serial); }

  const rows = db.prepare(`
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
  `).all(...params) as AnyRow[];

  res.json({ success: true, data: rows });
}));

// ===================================================================
// GET /warranty-lookup - Check if a device is under warranty
// ===================================================================
router.get('/warranty-lookup', asyncHandler(async (req: Request, res: Response) => {
  const imei = (req.query.imei as string || '').trim();
  const serial = (req.query.serial as string || '').trim();
  const phone = (req.query.phone as string || '').trim();
  if (!imei && !serial && !phone) throw new AppError('imei, serial, or phone required', 400);

  const conditions: string[] = ['t.is_deleted = 0', 'td.warranty = 1', 'td.warranty_days > 0'];
  const params: any[] = [];
  if (imei) { conditions.push('td.imei = ?'); params.push(imei); }
  if (serial) { conditions.push('td.serial = ?'); params.push(serial); }
  if (phone) { conditions.push('(c.mobile = ? OR c.phone = ?)'); params.push(phone, phone); }

  const rows = db.prepare(`
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
  `).all(...params) as AnyRow[];

  // Add active/expired flag
  const today = new Date().toISOString().slice(0, 10);
  const results = rows.map(r => ({
    ...r,
    warranty_active: r.warranty_expires >= today,
  }));

  res.json({ success: true, data: results });
}));

// ===================================================================
// GET /missing-parts - All parts across open tickets with in_stock = 0
// ===================================================================
router.get('/missing-parts', asyncHandler(async (_req: Request, res: Response) => {
  // ticket_device_parts rows where the linked inventory item has no stock
  // OR where the part has status = 'missing'
  const rows = db.prepare(`
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
      AND (ii.in_stock < tdp.quantity OR tdp.status = 'missing')
    ORDER BY t.created_at DESC
    LIMIT 500
  `).all() as AnyRow[];

  res.json({ success: true, data: rows });
}));

// ===================================================================
// GET /tv-display - Simplified view for shop TV
// ===================================================================
router.get('/tv-display', asyncHandler(async (_req: Request, res: Response) => {
  const tickets = db.prepare(`
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
  `).all() as AnyRow[];

  const result = tickets.map((t) => {
    const devices = db.prepare('SELECT device_name FROM ticket_devices WHERE ticket_id = ?').all(t.id) as AnyRow[];
    return {
      id: t.id,
      order_id: t.order_id,
      customer_first_name: t.c_first_name,
      device_names: devices.map((d) => d.device_name),
      status: { name: t.status_name, color: t.status_color },
      assigned_tech: t.tech_first ? `${t.tech_first} ${t.tech_last}` : null,
    };
  });

  res.json({ success: true, data: result });
}));

// ===================================================================
// GET /:id - Full ticket detail
// ===================================================================
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = getFullTicket(ticketId);
  if (!ticket) throw new AppError('Ticket not found', 404);
  if (ticket.is_deleted) throw new AppError('Ticket has been deleted', 404);

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// PUT /:id - Update ticket summary fields
// ===================================================================
router.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = db.prepare('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  // F1: Check if editing closed tickets is allowed
  const existingStatus = db.prepare('SELECT is_closed FROM ticket_statuses WHERE id = ?').get(existing.status_id) as AnyRow | undefined;
  if (existingStatus?.is_closed) {
    const allowEditClosed = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_allow_edit_closed'").get() as AnyRow | undefined;
    if (allowEditClosed?.value === '0' || allowEditClosed?.value === 'false') {
      throw new AppError('Cannot edit a closed ticket', 403);
    }
  }

  // F2/F3: Check if editing/deleting after invoice is allowed
  if (existing.invoice_id) {
    const allowEditAfterInvoice = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_allow_edit_after_invoice'").get() as AnyRow | undefined;
    if (allowEditAfterInvoice?.value === '0' || allowEditAfterInvoice?.value === 'false') {
      throw new AppError('Cannot edit a ticket with an invoice', 403);
    }
  }

  // Validate customer_id if provided
  if (req.body.customer_id !== undefined) {
    const cust = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(req.body.customer_id) as AnyRow | undefined;
    if (!cust) throw new AppError('Customer not found', 404);
  }

  const allowedFields = [
    'customer_id', 'assigned_to', 'discount', 'discount_reason',
    'source', 'referral_source', 'labels', 'due_on', 'signature',
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

  db.prepare(`UPDATE tickets SET ${updates.join(', ')} WHERE id = ?`).run(...params);

  // Recalculate if discount changed
  if (req.body.discount !== undefined) {
    recalcTicketTotals(ticketId);
  }

  insertHistory(ticketId, userId, 'updated', 'Ticket updated');
  const ticket = getFullTicket(ticketId);
  broadcast(WS_EVENTS.TICKET_UPDATED, ticket);

  // Fire automations for assignment changes
  if (req.body.assigned_to !== undefined && req.body.assigned_to !== existing.assigned_to) {
    const cust = db.prepare('SELECT * FROM customers WHERE id = ?').get(ticket.customer_id) as AnyRow | undefined;
    runAutomations('ticket_assigned', { ticket, customer: cust ?? {} });
  }

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// DELETE /:id - Soft delete
// ===================================================================
router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = db.prepare('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  db.prepare('UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ?').run(now(), ticketId);
  insertHistory(ticketId, userId, 'deleted', 'Ticket deleted');
  broadcast(WS_EVENTS.TICKET_DELETED, { id: ticketId });

  res.json({ success: true, data: { id: ticketId } });
}));

// ===================================================================
// PATCH /:id/status - Change ticket status
// ===================================================================
router.patch('/:id/status', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  const { status_id } = req.body;

  if (!ticketId) throw new AppError('Invalid ticket ID');
  if (!status_id) throw new AppError('status_id is required');

  const existing = db.prepare('SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  const oldStatus = db.prepare('SELECT id, name FROM ticket_statuses WHERE id = ?').get(existing.status_id) as AnyRow;
  const newStatus = db.prepare('SELECT id, name, notify_customer, is_closed FROM ticket_statuses WHERE id = ?').get(status_id) as AnyRow | undefined;
  if (!newStatus) throw new AppError('Status not found', 404);

  // F10: Require post-conditions before closing
  if (newStatus.is_closed) {
    const requirePostCond = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_post_condition'").get() as AnyRow | undefined;
    if (requirePostCond?.value === '1' || requirePostCond?.value === 'true') {
      const devices = db.prepare('SELECT id, device_name, post_conditions FROM ticket_devices WHERE ticket_id = ?').all(ticketId) as AnyRow[];
      for (const d of devices) {
        const postConds = d.post_conditions ? JSON.parse(d.post_conditions) : [];
        if (postConds.length === 0) throw new AppError(`Post-conditions required for ${d.device_name} before closing`, 400);
      }
    }

    // F11: Require parts before closing
    const requireParts = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_parts'").get() as AnyRow | undefined;
    if (requireParts?.value === '1' || requireParts?.value === 'true') {
      const partsCount = db.prepare('SELECT COUNT(*) as c FROM ticket_device_parts tdp JOIN ticket_devices td ON td.id = tdp.ticket_device_id WHERE td.ticket_id = ?').get(ticketId) as AnyRow;
      if (partsCount.c === 0) throw new AppError('At least one part must be added before closing the ticket', 400);
    }
  }

  // F13: Require diagnostic note before any status change
  const requireDiag = db.prepare("SELECT value FROM store_config WHERE key = 'repair_require_diagnostic'").get() as AnyRow | undefined;
  if (requireDiag?.value === '1' || requireDiag?.value === 'true') {
    const diagNote = db.prepare("SELECT id FROM ticket_notes WHERE ticket_id = ? AND type = 'diagnostic' LIMIT 1").get(ticketId) as AnyRow | undefined;
    if (!diagNote) throw new AppError('A diagnostic note is required before changing status', 400);
  }

  db.prepare('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?').run(status_id, now(), ticketId);

  // If cancelled, void any linked unpaid invoice
  if (newStatus.is_cancelled) {
    const linkedInvoice = db.prepare("SELECT id, status FROM invoices WHERE ticket_id = ? AND status != 'void'").get(ticketId) as AnyRow | undefined;
    if (linkedInvoice) {
      db.prepare("UPDATE invoices SET status = 'void', amount_due = 0, updated_at = ? WHERE id = ?").run(now(), linkedInvoice.id);
      insertHistory(ticketId, userId, 'invoice_voided', `Invoice auto-voided on ticket cancellation`);
    }
  }

  // Sync device-level statuses to match ticket status
  db.prepare('UPDATE ticket_devices SET status_id = ?, updated_at = ? WHERE ticket_id = ?')
    .run(status_id, now(), ticketId);

  insertHistory(ticketId, userId, 'status_changed',
    `Status changed from "${oldStatus.name}" to "${newStatus.name}"`,
    oldStatus.name, newStatus.name);

  if (newStatus.notify_customer) {
    // Fire async notification (don't block the response)
    import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
      sendTicketStatusNotification({ ticketId, statusName: newStatus.name });
    }).catch(err => console.error('[Notification] Import error:', err));
  }

  const ticket = getFullTicket(ticketId);
  broadcast(WS_EVENTS.TICKET_STATUS_CHANGED, ticket);

  // Fire automations (async, non-blocking)
  const cust = db.prepare('SELECT * FROM customers WHERE id = ?').get(ticket.customer_id) as AnyRow | undefined;
  runAutomations('ticket_status_changed', {
    ticket,
    customer: cust ?? {},
    from_status_id: oldStatus.id,
    to_status_id: status_id,
  });

  res.json({ success: true, data: ticket });
}));

// ===================================================================
// PATCH /:id/pin - Toggle ticket pinned state
// ===================================================================
router.patch('/:id/pin', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);

  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = db.prepare('SELECT id, is_pinned FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  const newPinned = existing.is_pinned ? 0 : 1;
  db.prepare('UPDATE tickets SET is_pinned = ?, updated_at = ? WHERE id = ?').run(newPinned, now(), ticketId);

  res.json({ success: true, data: { id: ticketId, is_pinned: !!newPinned } });
}));

// ===================================================================
// POST /:id/notes - Add note
// ===================================================================
router.post('/:id/notes', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;

  if (!ticketId) throw new AppError('Invalid ticket ID');
  const existing = db.prepare('SELECT id, order_id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  const { type, content, is_flagged, ticket_device_id, parent_id } = req.body;
  if (!content) throw new AppError('content is required');
  if (content.length > 10000) throw new AppError('Note content too long (max 10,000 characters)', 400);

  const result = db.prepare(`
    INSERT INTO ticket_notes (ticket_id, ticket_device_id, user_id, type, content, is_flagged, parent_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(ticketId, ticket_device_id ?? null, userId, type || 'internal', content, is_flagged ? 1 : 0, parent_id ?? null, now(), now());

  const noteId = Number(result.lastInsertRowid);

  insertHistory(ticketId, userId, 'note_added', `Note added (${type || 'internal'})`);

  // Update ticket timestamp
  db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), ticketId);

  if (type === 'email') {
    console.log(`[Email] Would send email note for ticket ${existing.order_id}`);
  }

  const note = db.prepare(`
    SELECT tn.*, u.first_name, u.last_name, u.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.id = ?
  `).get(noteId) as AnyRow;

  const shaped = {
    ...note,
    is_flagged: !!note.is_flagged,
    user: { id: note.user_id, first_name: note.first_name, last_name: note.last_name, avatar_url: note.avatar_url },
  };

  broadcast(WS_EVENTS.TICKET_NOTE_ADDED, { ticket_id: ticketId, note: shaped });

  res.status(201).json({ success: true, data: shaped });
}));

// ===================================================================
// PUT /notes/:noteId - Edit note
// ===================================================================
router.put('/notes/:noteId', asyncHandler(async (req: Request, res: Response) => {
  const noteId = parseInt(req.params.noteId);
  if (!noteId) throw new AppError('Invalid note ID');

  const existing = db.prepare('SELECT * FROM ticket_notes WHERE id = ?').get(noteId) as AnyRow | undefined;
  if (!existing) throw new AppError('Note not found', 404);

  const { content, is_flagged, type } = req.body;
  const updates: string[] = ['updated_at = ?'];
  const params: any[] = [now()];

  if (content !== undefined) { updates.push('content = ?'); params.push(content); }
  if (is_flagged !== undefined) { updates.push('is_flagged = ?'); params.push(is_flagged ? 1 : 0); }
  if (type !== undefined) { updates.push('type = ?'); params.push(type); }

  params.push(noteId);
  db.prepare(`UPDATE ticket_notes SET ${updates.join(', ')} WHERE id = ?`).run(...params);

  const note = db.prepare(`
    SELECT tn.*, u.first_name, u.last_name, u.avatar_url
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.id = ?
  `).get(noteId) as AnyRow;

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
  const noteId = parseInt(req.params.noteId);
  if (!noteId) throw new AppError('Invalid note ID');

  const existing = db.prepare('SELECT id, ticket_id FROM ticket_notes WHERE id = ?').get(noteId) as AnyRow | undefined;
  if (!existing) throw new AppError('Note not found', 404);

  db.prepare('DELETE FROM ticket_notes WHERE id = ?').run(noteId);
  insertHistory(existing.ticket_id, req.user!.id, 'note_deleted', 'Note deleted');

  res.json({ success: true, data: { id: noteId } });
}));

// ===================================================================
// POST /:id/photos - Upload photos
// ===================================================================
router.post('/:id/photos', upload.array('photos', 20), asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = db.prepare('SELECT id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  const files = req.files as Express.Multer.File[];
  if (!files || files.length === 0) throw new AppError('No photos uploaded');

  const { type, ticket_device_id, caption } = req.body;
  if (!ticket_device_id) throw new AppError('ticket_device_id is required');

  const photos: AnyRow[] = [];
  for (const file of files) {
    const result = db.prepare(`
      INSERT INTO ticket_photos (ticket_device_id, type, file_path, caption, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(ticket_device_id, type || 'pre', file.filename, caption ?? null, now(), now());

    photos.push({
      id: Number(result.lastInsertRowid),
      ticket_device_id: parseInt(ticket_device_id),
      type: type || 'pre',
      file_path: file.filename,
      caption: caption ?? null,
      created_at: now(),
    });
  }

  insertHistory(ticketId, req.user!.id, 'photo_added', `${files.length} photo(s) uploaded`);
  db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), ticketId);

  res.status(201).json({ success: true, data: photos });
}));

// ===================================================================
// DELETE /photos/:photoId - Delete photo
// ===================================================================
router.delete('/photos/:photoId', asyncHandler(async (req: Request, res: Response) => {
  const photoId = parseInt(req.params.photoId);
  if (!photoId) throw new AppError('Invalid photo ID');

  const photo = db.prepare(`
    SELECT tp.*, td.ticket_id
    FROM ticket_photos tp
    JOIN ticket_devices td ON td.id = tp.ticket_device_id
    WHERE tp.id = ?
  `).get(photoId) as AnyRow | undefined;
  if (!photo) throw new AppError('Photo not found', 404);

  // Try to delete the file
  const filePath = path.join(config.uploadsPath, photo.file_path);
  try { fs.unlinkSync(filePath); } catch { /* file may not exist */ }

  db.prepare('DELETE FROM ticket_photos WHERE id = ?').run(photoId);
  insertHistory(photo.ticket_id, req.user!.id, 'photo_deleted', 'Photo deleted');

  res.json({ success: true, data: { id: photoId } });
}));

// ===================================================================
// POST /:id/convert-to-invoice - Generate invoice from ticket
// ===================================================================
router.post('/:id/convert-to-invoice', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = db.prepare('SELECT * FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

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

    // Create line items from devices
    for (const dev of devices) {
      db.prepare(`
        INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                        line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
        VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        invoiceId, dev.service_id, `${dev.device_name} - Service`, dev.price,
        dev.line_discount, dev.tax_amount, dev.tax_class_id, dev.total, now(), now(),
      );

      // Add parts as line items
      const parts = db.prepare(`
        SELECT tdp.*, ii.name AS item_name
        FROM ticket_device_parts tdp
        LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
        WHERE tdp.ticket_device_id = ?
      `).all(dev.id) as AnyRow[];

      for (const part of parts) {
        const lineTotal = roundCurrency(part.quantity * part.price);
        db.prepare(`
          INSERT INTO invoice_line_items (invoice_id, inventory_item_id, description, quantity, unit_price,
                                          line_discount, tax_amount, tax_class_id, total, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, 0, 0, NULL, ?, ?, ?)
        `).run(invoiceId, part.inventory_item_id, `Part: ${part.item_name || 'Unknown'}`, part.quantity, part.price, lineTotal, now(), now());
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
        insertHistory(ticketId, userId, 'status_changed', `Auto-closed on invoice creation`);
      }
    }

    // F5: Auto-remove passcode on close
    const autoRemovePasscode = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_auto_remove_passcode'").get() as AnyRow | undefined;
    if (autoRemovePasscode?.value === '1' || autoRemovePasscode?.value === 'true') {
      db.prepare('UPDATE ticket_devices SET security_code = NULL WHERE ticket_id = ?').run(ticketId);
    }

    insertHistory(ticketId, userId, 'invoice_created', `Invoice ${invoiceOrderId} created from ticket`);

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
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const existing = db.prepare('SELECT id FROM tickets WHERE id = ?').get(ticketId) as AnyRow | undefined;
  if (!existing) throw new AppError('Ticket not found', 404);

  const history = (db.prepare(`
    SELECT th.*, u.first_name, u.last_name
    FROM ticket_history th
    LEFT JOIN users u ON u.id = th.user_id
    WHERE th.ticket_id = ?
    ORDER BY th.created_at DESC
  `).all(ticketId) as AnyRow[]).map((h) => ({
    ...h,
    user: h.user_id ? { id: h.user_id, first_name: h.first_name, last_name: h.last_name } : null,
  }));

  res.json({ success: true, data: history });
}));

// ===================================================================
// GET /:id/repair-time - Active repair time for a ticket
// ===================================================================
router.get('/:id/repair-time', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = db.prepare(`
    SELECT t.id, t.order_id, t.created_at, ts.name AS status_name, ts.is_closed
    FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.id = ? AND t.is_deleted = 0
  `).get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

  const activeHours = calculateActiveRepairTime(ticketId);
  const totalHours = ticket.is_closed
    ? null // would need close timestamp; use history
    : (Date.now() - new Date(ticket.created_at as string).getTime()) / (1000 * 60 * 60);

  // Calculate total elapsed from creation to last close (or now)
  const closeEvent = db.prepare(`
    SELECT th.created_at FROM ticket_history th
    JOIN ticket_statuses ts ON ts.name = th.new_value
    WHERE th.ticket_id = ? AND th.action IN ('status_changed', 'status_change') AND ts.is_closed = 1
    ORDER BY th.created_at DESC LIMIT 1
  `).get(ticketId) as AnyRow | undefined;

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
  const ticketId = parseInt(req.params.id);
  const userId = req.user!.id;
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = db.prepare('SELECT id, status_id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

  const dev = req.body;
  const devicePrice = dev.price ?? 0;
  const lineDiscount = dev.line_discount ?? 0;
  const taxAmount = calcTax(devicePrice - lineDiscount, dev.tax_class_id ?? null, dev.tax_inclusive ?? false);
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
      dev.tax_class_id ?? null,
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

    recalcTicketTotals(ticketId);
    insertHistory(ticketId, userId, 'device_added', `Device added: ${dev.device_name || 'Unknown'}`);

    return deviceId;
  });

  const deviceId = addDevice();
  const device = db.prepare('SELECT * FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: ticketId });

  res.status(201).json({ success: true, data: { ...device, pre_conditions: parseJsonCol(device.pre_conditions, []), post_conditions: parseJsonCol(device.post_conditions, []) } });
}));

// ===================================================================
// PUT /devices/:deviceId - Update device
// ===================================================================
router.put('/devices/:deviceId', asyncHandler(async (req: Request, res: Response) => {
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
  const price = req.body.price ?? existing.price;
  const lineDiscount = req.body.line_discount ?? existing.line_discount;
  const taxClassId = req.body.tax_class_id !== undefined ? req.body.tax_class_id : existing.tax_class_id;
  const taxInclusive = req.body.tax_inclusive !== undefined ? req.body.tax_inclusive : !!existing.tax_inclusive;
  const taxAmount = calcTax(price - lineDiscount, taxClassId, taxInclusive);
  const total = roundCurrency(price - lineDiscount + taxAmount);

  updates.push('tax_amount = ?', 'total = ?', 'updated_at = ?');
  params.push(taxAmount, total, now());
  params.push(deviceId);

  db.prepare(`UPDATE ticket_devices SET ${updates.join(', ')} WHERE id = ?`).run(...params);

  recalcTicketTotals(existing.ticket_id);
  insertHistory(existing.ticket_id, userId, 'device_updated', `Device updated: ${req.body.device_name || existing.device_name}`);

  const device = db.prepare('SELECT * FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow;
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: existing.ticket_id });

  res.json({ success: true, data: { ...device, pre_conditions: parseJsonCol(device.pre_conditions, []), post_conditions: parseJsonCol(device.post_conditions, []) } });
}));

// ===================================================================
// DELETE /devices/:deviceId - Remove device
// ===================================================================
router.delete('/devices/:deviceId', asyncHandler(async (req: Request, res: Response) => {
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

    // Delete photos from disk
    const photos = db.prepare('SELECT file_path FROM ticket_photos WHERE ticket_device_id = ?').all(deviceId) as AnyRow[];
    for (const photo of photos) {
      try { fs.unlinkSync(path.join(config.uploadsPath, photo.file_path)); } catch { /* ignore */ }
    }

    // CASCADE will handle ticket_device_parts, ticket_photos, ticket_checklists
    db.prepare('DELETE FROM ticket_devices WHERE id = ?').run(deviceId);

    recalcTicketTotals(existing.ticket_id);
    insertHistory(existing.ticket_id, userId, 'device_removed', `Device removed: ${existing.device_name}`);
  });

  remove();
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: existing.ticket_id });

  res.json({ success: true, data: { id: deviceId } });
}));

// ===================================================================
// POST /devices/:deviceId/parts - Add parts to device
// ===================================================================
router.post('/devices/:deviceId/parts', asyncHandler(async (req: Request, res: Response) => {
  const deviceId = parseInt(req.params.deviceId);
  const userId = req.user!.id;
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = db.prepare('SELECT id, ticket_id FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!device) throw new AppError('Device not found', 404);

  const { inventory_item_id, quantity, price, warranty, serial } = req.body;
  if (!inventory_item_id) throw new AppError('inventory_item_id is required');
  if (!quantity || quantity < 1) throw new AppError('quantity must be at least 1');

  const item = db.prepare('SELECT id, name, in_stock FROM inventory_items WHERE id = ?').get(inventory_item_id) as AnyRow | undefined;
  if (!item) throw new AppError('Inventory item not found', 404);
  if (item.in_stock < quantity) {
    throw new AppError(`Insufficient stock for ${item.name}: ${item.in_stock} available, ${quantity} needed`, 400);
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

    recalcTicketTotals(device.ticket_id);
    insertHistory(device.ticket_id, userId, 'part_added', `Part added: ${item.name} x${quantity}`);

    return Number(result.lastInsertRowid);
  });

  const partId = addPart();
  const part = db.prepare(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: device.ticket_id });

  res.status(201).json({ success: true, data: part });
}));

// ===================================================================
// DELETE /devices/parts/:partId - Remove part from device
// ===================================================================
router.delete('/devices/parts/:partId', asyncHandler(async (req: Request, res: Response) => {
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
    recalcTicketTotals(part.ticket_id);
    insertHistory(part.ticket_id, userId, 'part_removed', `Part removed: ${part.item_name || 'Unknown'} x${part.quantity}`);
  });

  removePart();
  broadcast(WS_EVENTS.TICKET_UPDATED, { id: part.ticket_id });

  res.json({ success: true, data: { id: partId } });
}));

// ===================================================================
// PATCH /devices/parts/:partId - Update part status (missing/ordered/received/available)
// ===================================================================
router.patch('/devices/parts/:partId', asyncHandler(async (req: Request, res: Response) => {
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

  const { status, catalog_item_id, supplier_url } = req.body;

  const updates: string[] = [];
  const values: any[] = [];

  if (status) {
    const allowed = ['available', 'missing', 'ordered', 'received'];
    if (!allowed.includes(status)) throw new AppError(`Invalid status. Allowed: ${allowed.join(', ')}`);
    updates.push('status = ?');
    values.push(status);
  }
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
  insertHistory(part.ticket_id, userId, 'part_status_changed', `Part status changed to ${status || 'updated'}`);
  db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), part.ticket_id);

  const updated = db.prepare(`
    SELECT tdp.*, ii.name AS item_name, ii.sku AS item_sku
    FROM ticket_device_parts tdp
    LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
    WHERE tdp.id = ?
  `).get(partId) as AnyRow;

  broadcast(WS_EVENTS.TICKET_UPDATED, { id: part.ticket_id });

  res.json({ success: true, data: updated });
}));

// ===================================================================
// PUT /devices/:deviceId/checklist - Update checklist items
// ===================================================================
router.put('/devices/:deviceId/checklist', asyncHandler(async (req: Request, res: Response) => {
  const deviceId = parseInt(req.params.deviceId);
  if (!deviceId) throw new AppError('Invalid device ID');

  const device = db.prepare('SELECT id, ticket_id FROM ticket_devices WHERE id = ?').get(deviceId) as AnyRow | undefined;
  if (!device) throw new AppError('Device not found', 404);

  const { items } = req.body;
  if (!items || !Array.isArray(items)) throw new AppError('items array is required');

  const existing = db.prepare('SELECT id FROM ticket_checklists WHERE ticket_device_id = ?').get(deviceId) as AnyRow | undefined;

  if (existing) {
    db.prepare('UPDATE ticket_checklists SET items = ?, updated_at = ? WHERE id = ?')
      .run(JSON.stringify(items), now(), existing.id);
  } else {
    // Need a template ID - use first available or create inline
    const template = db.prepare('SELECT id FROM checklist_templates LIMIT 1').get() as AnyRow | undefined;
    const templateId = template?.id ?? 1;
    db.prepare(`
      INSERT INTO ticket_checklists (ticket_device_id, checklist_template_id, items, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(deviceId, templateId, JSON.stringify(items), now(), now());
  }

  insertHistory(device.ticket_id, req.user!.id, 'checklist_updated', 'Checklist updated');
  db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), device.ticket_id);

  const checklist = db.prepare('SELECT * FROM ticket_checklists WHERE ticket_device_id = ?').get(deviceId) as AnyRow;

  res.json({ success: true, data: { ...checklist, items: parseJsonCol(checklist.items, []) } });
}));

// ===================================================================
// POST /devices/:deviceId/loaner - Assign loaner device
// ===================================================================
router.post('/devices/:deviceId/loaner', asyncHandler(async (req: Request, res: Response) => {
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

    insertHistory(device.ticket_id, userId, 'loaner_assigned', `Loaner device assigned: ${loaner.name}`);
    db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), device.ticket_id);
  });

  assign();

  res.status(201).json({ success: true, data: { loaner_device_id, device_id: deviceId, loaner_name: loaner.name } });
}));

// ===================================================================
// DELETE /devices/:deviceId/loaner - Return loaner device
// ===================================================================
router.delete('/devices/:deviceId/loaner', asyncHandler(async (req: Request, res: Response) => {
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

    insertHistory(device.ticket_id, userId, 'loaner_returned', 'Loaner device returned');
    db.prepare('UPDATE tickets SET updated_at = ? WHERE id = ?').run(now(), device.ticket_id);
  });

  returnLoaner();

  res.json({ success: true, data: { device_id: deviceId } });
}));

// ===================================================================
// POST /:id/otp - Generate OTP
// ===================================================================
router.post('/:id/otp', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const ticket = db.prepare(`
    SELECT t.id, c.phone, c.mobile
    FROM tickets t
    JOIN customers c ON c.id = t.customer_id
    WHERE t.id = ? AND t.is_deleted = 0
  `).get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

  const { ticket_device_id } = req.body;
  if (!ticket_device_id) throw new AppError('ticket_device_id is required');

  // Generate 6-digit code
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString().replace('T', ' ').substring(0, 19);
  const phone = ticket.mobile || ticket.phone;

  db.prepare(`
    INSERT INTO device_otps (ticket_id, ticket_device_id, code, phone, expires_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(ticketId, ticket_device_id, code, phone, expiresAt, now(), now());

  console.log(`[SMS] Would send OTP ${code} to ${phone} for ticket ${ticketId}`);

  // Never return the OTP code in the response — it should only be sent via SMS
  res.status(201).json({ success: true, data: { expires_at: expiresAt, phone, message: 'OTP sent via SMS' } });
}));

// ===================================================================
// POST /:id/verify-otp - Verify OTP
// ===================================================================
router.post('/:id/verify-otp', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  if (!ticketId) throw new AppError('Invalid ticket ID');

  const { code } = req.body;
  if (!code) throw new AppError('code is required');

  const otp = db.prepare(`
    SELECT * FROM device_otps
    WHERE ticket_id = ? AND code = ? AND is_verified = 0 AND expires_at > datetime('now')
    ORDER BY created_at DESC
    LIMIT 1
  `).get(ticketId, code) as AnyRow | undefined;

  if (!otp) throw new AppError('Invalid or expired OTP', 400);

  db.prepare('UPDATE device_otps SET is_verified = 1, updated_at = ? WHERE id = ?').run(now(), otp.id);

  insertHistory(ticketId, req.user?.id ?? null, 'otp_verified', 'OTP verified successfully');

  res.json({ success: true, data: { verified: true, ticket_device_id: otp.ticket_device_id } });
}));

// ===================================================================
// POST /bulk-action - Bulk actions on tickets
// ===================================================================
router.post('/bulk-action', asyncHandler(async (req: Request, res: Response) => {
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
          const newStatus = db.prepare('SELECT name, notify_customer FROM ticket_statuses WHERE id = ?').get(value) as AnyRow | undefined;
          if (!newStatus) throw new AppError(`Status ${value} not found`, 404);

          db.prepare('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?').run(value, now(), id);
          insertHistory(id, userId, 'status_changed', `Bulk status change: "${oldStatus.name}" to "${newStatus.name}"`, oldStatus.name, newStatus.name);
          if (newStatus.notify_customer) {
            import('../services/notifications.js').then(({ sendTicketStatusNotification }) => {
              sendTicketStatusNotification({ ticketId: id, statusName: newStatus.name });
            }).catch(() => {});
          }
          affected.push(id);
          break;
        }
        case 'assign': {
          db.prepare('UPDATE tickets SET assigned_to = ?, updated_at = ? WHERE id = ?').run(value ?? null, now(), id);
          insertHistory(id, userId, 'assigned', value ? `Bulk assigned to user ${value}` : 'Bulk unassigned');
          affected.push(id);
          break;
        }
        case 'delete': {
          if (req.user?.role !== 'admin') throw new AppError('Only admins can bulk delete', 403);
          db.prepare('UPDATE tickets SET is_deleted = 1, updated_at = ? WHERE id = ?').run(now(), id);
          insertHistory(id, userId, 'deleted', 'Bulk deleted');
          affected.push(id);
          break;
        }
      }
    }

    return affected;
  });

  const affected = doBulk();

  if (action === 'delete') {
    for (const id of affected) broadcast(WS_EVENTS.TICKET_DELETED, { id });
  } else {
    for (const id of affected) broadcast(WS_EVENTS.TICKET_UPDATED, { id });
  }

  res.json({ success: true, data: { affected: affected.length, ticket_ids: affected } });
}));

// ===================================================================
// GET /feedback-summary - Overall feedback stats
// Path uses hyphen to avoid matching /:id (which would catch "feedback")
// ===================================================================
router.get('/feedback-summary', asyncHandler(async (_req: Request, res: Response) => {
  const stats = db.prepare(`
    SELECT COUNT(*) AS total_reviews,
           COALESCE(AVG(rating), 0) AS avg_rating,
           COUNT(CASE WHEN rating >= 4 THEN 1 END) AS positive_count,
           COUNT(CASE WHEN rating <= 2 THEN 1 END) AS negative_count
    FROM customer_feedback
  `).get() as AnyRow;

  const recent = db.prepare(`
    SELECT cf.*, c.first_name, c.last_name, t.order_id
    FROM customer_feedback cf
    LEFT JOIN customers c ON c.id = cf.customer_id
    LEFT JOIN tickets t ON t.id = cf.ticket_id
    ORDER BY cf.created_at DESC LIMIT 10
  `).all();

  res.json({ success: true, data: { ...stats, recent } });
}));

// ===================================================================
// GET /:id/feedback - Get feedback for a ticket
// ===================================================================
router.get('/:id/feedback', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const feedback = db.prepare('SELECT * FROM customer_feedback WHERE ticket_id = ? ORDER BY created_at DESC').all(ticketId);
  res.json({ success: true, data: feedback });
}));

// ===================================================================
// POST /:id/feedback - Submit feedback for a ticket
// ===================================================================
router.post('/:id/feedback', asyncHandler(async (req: Request, res: Response) => {
  const ticketId = parseInt(req.params.id);
  const { rating, comment, source = 'web' } = req.body;

  if (!rating || rating < 1 || rating > 5) throw new AppError('Rating must be 1-5', 400);

  const ticket = db.prepare('SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0').get(ticketId) as AnyRow | undefined;
  if (!ticket) throw new AppError('Ticket not found', 404);

  const result = db.prepare(`
    INSERT INTO customer_feedback (ticket_id, customer_id, rating, comment, source, responded_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(ticketId, ticket.customer_id, rating, comment || null, source, now(), now(), now());

  res.status(201).json({ success: true, data: { id: Number(result.lastInsertRowid) } });
}));

export default router;
