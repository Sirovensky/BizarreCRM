import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS, LEGAL_LEAD_TRANSITIONS } from '@bizarre-crm/shared';
import { config } from '../config.js';
import { lastInsertRowidFrom } from '../db/async-db.js';
import type { AsyncDb, TxQuery } from '../db/async-db.js';
import { normalizePhone } from '../utils/phone.js';
import { createLogger } from '../utils/logger.js';
const logger = createLogger('leads');
import { escapeLike } from '../utils/query.js';
import {
  validateEmail,
  validatePhoneDigits,
  validatePrice,
  validateEnum,
  validateArrayBounds,
  validateQuantity,
} from '../utils/validate.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';

const router = Router();

/**
 * Transition map keyed by the SOURCE lead status.
 * Now lives in `@bizarre-crm/shared/constants/statuses` (WEB-UIUX-1343) so
 * the client status-pill picker can hide dead-end transitions instead of
 * surfacing them and silently rolling back on a server reject. Only
 * standard status names appear as keys; unrecognised sources (custom
 * tenant states) bypass the guard entirely (permissive fall-through).
 */

/**
 * Assert that transitioning a lead from `from` to `to` is legal.
 * If `from` is not a known standard status the guard is a no-op (permissive
 * fall-through for custom tenant statuses).
 */
function assertLeadTransition(from: string, to: string): void {
  const allowed = LEGAL_LEAD_TRANSITIONS[from];
  if (allowed === undefined) return; // unknown source — permissive fall-through
  if (!allowed.includes(to)) {
    throw new AppError(`Cannot transition lead from '${from}' to '${to}'`, 400);
  }
}

// V17: cap lead device array length to prevent 100k-item DoS payloads.
const MAX_LEAD_DEVICES = 500;

// V16: whitelist for lead loss reasons — trimmed-and-matched via validateEnum.
const VALID_LOST_REASONS = ['price', 'competitor', 'no_response', 'changed_mind', 'other'] as const;

/**
 * Normalize + validate a phone number from user input. Returns null for
 * empty input. Throws AppError on malformed input (V14).
 */
function normalizeAndValidatePhone(raw: unknown, fieldName = 'phone'): string | null {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const digits = normalizePhone(raw);
  if (!digits) throw new AppError(`${fieldName} is not a valid phone number`, 400);
  return validatePhoneDigits(digits, fieldName, false);
}

// ---------------------------------------------------------------------------
// ENR-LE3: Lead scoring helper (0-100)
// ---------------------------------------------------------------------------
function computeLeadScore(lead: any, appointments: any[] | null): number {
  let score = 0;
  if (lead.email) score += 20;
  if (lead.phone) score += 20;

  // Check total value from devices
  const totalValue = (lead.devices ?? []).reduce((sum: number, d: any) => sum + (Number(d.price) || 0), 0);
  // Fallback: if no devices array, check lead-level estimated_value if present
  if (totalValue > 100 || (lead.estimated_value && Number(lead.estimated_value) > 100)) score += 15;

  if (lead.source === 'referral' || lead.source === 'website') score += 15;

  // Responded within 24 hours of creation
  if (lead.updated_at && lead.created_at) {
    // BUGHUNT-2026-05-16: SQLite ts is 'YYYY-MM-DD HH:MM:SS' UTC without 'Z'.
    // V8 parses that as local time, so a UTC+N server would shift both
    // timestamps by N hours equally — the *difference* survives, but in
    // case the columns ever carry mixed forms (e.g. an ISO from a future
    // backfill), normalize to be safe.
    const normalize = (v: string): string =>
      v.includes('T') || v.endsWith('Z') || v.includes('+') ? v : `${v.replace(' ', 'T')}Z`;
    const created = new Date(normalize(lead.created_at)).getTime();
    const updated = new Date(normalize(lead.updated_at)).getTime();
    if (updated - created <= 24 * 60 * 60 * 1000 && updated !== created) score += 10;
  }

  // Has appointment scheduled
  const appts = appointments ?? lead.appointments ?? [];
  if (appts.length > 0) score += 10;

  if (lead.status === 'qualified' || lead.status === 'proposal') score += 10;

  return Math.min(score, 100);
}

// ---------------------------------------------------------------------------
// GET /pipeline – Leads grouped by status for kanban visualization (ENR-LE1)
// ---------------------------------------------------------------------------
router.get(
  '/pipeline',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;

    const leads = await adb.all<any>(`
      SELECT l.*,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM leads l
      LEFT JOIN users u ON u.id = l.assigned_to
      LEFT JOIN customers c ON c.id = l.customer_id
      WHERE l.is_deleted = 0
      ORDER BY l.updated_at DESC
    `);

    // ENR-LE3: compute lead_score for pipeline cards (same as list endpoint)
    const leadIds = leads.map((l: any) => l.id);
    const devicesByLead = new Map<number, any[]>();
    const apptsByLead = new Map<number, any[]>();
    if (leadIds.length > 0) {
      const ph = leadIds.map(() => '?').join(',');
      const [devices, appts] = await Promise.all([
        adb.all<any>(`SELECT * FROM lead_devices WHERE lead_id IN (${ph})`, ...leadIds),
        adb.all<any>(`SELECT * FROM appointments WHERE lead_id IN (${ph})`, ...leadIds),
      ]);
      for (const d of devices) {
        if (!devicesByLead.has(d.lead_id)) devicesByLead.set(d.lead_id, []);
        devicesByLead.get(d.lead_id)!.push(d);
      }
      for (const a of appts) {
        if (!apptsByLead.has(a.lead_id)) apptsByLead.set(a.lead_id, []);
        apptsByLead.get(a.lead_id)!.push(a);
      }
    }

    const pipeline: Record<string, any[]> = {};
    for (const lead of leads) {
      const status = lead.status || 'new';
      if (!pipeline[status]) {
        pipeline[status] = [];
      }
      const scored = {
        ...lead,
        lead_score: computeLeadScore(
          { ...lead, devices: devicesByLead.get(lead.id) || [] },
          apptsByLead.get(lead.id) || [],
        ),
      };
      pipeline[status].push(scored);
    }

    res.json({ success: true, data: pipeline });
  }),
);

// ---------------------------------------------------------------------------
// GET / – List leads (paginated, searchable)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);
    const keyword = (req.query.keyword as string || '').trim();
    const status = (req.query.status as string || '').trim();
    const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string, 10) : null;
    const sortBy = (req.query.sort_by as string) || 'created_at';
    const sortOrder = (req.query.sort_order as string || 'DESC').toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

    const allowedSorts = ['created_at', 'updated_at', 'first_name', 'last_name', 'status'];
    const safeSortBy = allowedSorts.includes(sortBy) ? sortBy : 'created_at';

    const conditions: string[] = ['l.is_deleted = 0'];
    const params: unknown[] = [];

    if (keyword) {
      const like = `%${escapeLike(keyword)}%`;
      // WEB-UIUX-662: digit-normalized phone match. "(555) 123-4567"
      // now hits stored "5551234567" without forcing the operator to
      // strip punctuation by hand.
      const digitsOnly = keyword.replace(/\D+/g, '');
      const digitMatch = digitsOnly.length >= 3 ? `%${escapeLike(digitsOnly)}%` : null;
      if (digitMatch) {
        conditions.push("(l.first_name LIKE ? ESCAPE '\\' OR l.last_name LIKE ? ESCAPE '\\' OR l.email LIKE ? ESCAPE '\\' OR l.phone LIKE ? ESCAPE '\\' OR l.order_id LIKE ? ESCAPE '\\' OR l.phone LIKE ? ESCAPE '\\')");
        params.push(like, like, like, like, like, digitMatch);
      } else {
        conditions.push("(l.first_name LIKE ? ESCAPE '\\' OR l.last_name LIKE ? ESCAPE '\\' OR l.email LIKE ? ESCAPE '\\' OR l.phone LIKE ? ESCAPE '\\' OR l.order_id LIKE ? ESCAPE '\\')");
        params.push(like, like, like, like, like);
      }
    }

    if (status) {
      conditions.push('l.status = ?');
      params.push(status);
    }

    if (assignedTo) {
      conditions.push('l.assigned_to = ?');
      params.push(assignedTo);
    }

    const whereClause = `WHERE ${conditions.join(' AND ')}`;

    const { total } = await adb.get<{ total: number }>(`SELECT COUNT(*) as total FROM leads l ${whereClause}`, ...params) as { total: number };
    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const leads = await adb.all<any>(`
      SELECT l.*,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM leads l
      LEFT JOIN users u ON u.id = l.assigned_to
      LEFT JOIN customers c ON c.id = l.customer_id
      ${whereClause}
      ORDER BY l.${safeSortBy} ${sortOrder}
      LIMIT ? OFFSET ?
    `, ...params, pageSize, offset);

    // ENR-LE3: Compute lead_score for each lead in the list
    const leadIds = leads.map(l => l.id);
    const devicesByLead = new Map<number, any[]>();
    const apptsByLead = new Map<number, any[]>();
    if (leadIds.length > 0) {
      const ph = leadIds.map(() => '?').join(',');
      const [devices, appts] = await Promise.all([
        adb.all<any>(`SELECT * FROM lead_devices WHERE lead_id IN (${ph})`, ...leadIds),
        adb.all<any>(`SELECT * FROM appointments WHERE lead_id IN (${ph})`, ...leadIds),
      ]);
      for (const d of devices) {
        if (!devicesByLead.has(d.lead_id)) devicesByLead.set(d.lead_id, []);
        devicesByLead.get(d.lead_id)!.push(d);
      }
      for (const a of appts) {
        if (!apptsByLead.has(a.lead_id)) apptsByLead.set(a.lead_id, []);
        apptsByLead.get(a.lead_id)!.push(a);
      }
    }
    const scoredLeads = leads.map(l => ({
      ...l,
      lead_score: computeLeadScore(
        { ...l, devices: devicesByLead.get(l.id) || [] },
        apptsByLead.get(l.id) || [],
      ),
    }));

    res.json({
      success: true,
      data: {
        leads: scoredLeads,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// ENR-LE4: Auto-assign helper (round_robin or least_loaded)
// ---------------------------------------------------------------------------
async function autoAssignLead(adb: AsyncDb): Promise<number | null> {
  const setting = await adb.get<any>("SELECT value FROM store_config WHERE key = 'lead_auto_assign'");
  if (!setting?.value || setting.value === 'off') return null;

  const technicians = await adb.all<any>(
    "SELECT id FROM users WHERE role IN ('admin', 'technician', 'manager') AND is_active = 1 ORDER BY id"
  );
  if (technicians.length === 0) return null;

  if (setting.value === 'least_loaded') {
    // Assign to technician with fewest open leads
    const result = await adb.get<any>(`
      SELECT u.id, COUNT(l.id) AS open_count
      FROM users u
      LEFT JOIN leads l ON l.assigned_to = u.id AND l.status NOT IN ('converted', 'lost')
      WHERE u.role IN ('admin', 'technician', 'manager') AND u.is_active = 1
      GROUP BY u.id
      ORDER BY open_count ASC, u.id ASC
      LIMIT 1
    `);
    return result?.id ?? technicians[0].id;
  }

  // round_robin: pick the next technician after the most recently assigned
  const lastAssigned = await adb.get<any>(`
    SELECT assigned_to FROM leads WHERE assigned_to IS NOT NULL ORDER BY id DESC LIMIT 1
  `);

  if (!lastAssigned?.assigned_to) return technicians[0].id;

  const lastIdx = technicians.findIndex((t: any) => t.id === lastAssigned.assigned_to);
  const nextIdx = (lastIdx + 1) % technicians.length;
  return technicians[nextIdx].id;
}

// ---------------------------------------------------------------------------
// POST / – Create lead
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const {
      customer_id, first_name, last_name, email, phone,
      zip_code, address, status, referred_by, assigned_to,
      source, notes, devices,
    } = req.body;

    if (!first_name) throw new AppError('first_name is required');

    // V14: normalize + validate phone (reject "+++++invalid")
    const validatedPhone = normalizeAndValidatePhone(phone, 'phone');
    // V5 (partial — enforce on create too): email validation at boundary.
    const validatedEmail = validateEmail(email, 'email', false);

    // V17: bound device array length before any per-item validation.
    const deviceList = devices !== undefined && devices !== null
      ? validateArrayBounds<any>(devices, 'devices', MAX_LEAD_DEVICES)
      : [];

    // V15: validate price/tax per device (non-negative, <= 999999.99).
    // Pre-validate BEFORE any writes so a bad row rejects the whole request atomically.
    const validatedDevices = deviceList.map((d, i) => ({
      device_name: d.device_name ?? '',
      repair_type: d.repair_type ?? null,
      service_type: d.service_type ?? null,
      service_id: d.service_id ?? null,
      price: validatePrice(d.price ?? 0, `devices[${i}].price`),
      tax: validatePrice(d.tax ?? 0, `devices[${i}].tax`),
      problem: d.problem ?? null,
      customer_notes: d.customer_notes ?? null,
      security_code: d.security_code ?? null,
      start_time: d.start_time ?? null,
      end_time: d.end_time ?? null,
      // V17: if callers pass `quantity_needed`, cap it. We don't store it on
      // lead_devices today (no column), but validate it so an attacker can't
      // smuggle a huge int that later flows into downstream conversion math.
      quantity_needed: d.quantity_needed !== undefined && d.quantity_needed !== null
        ? validateQuantity(d.quantity_needed, `devices[${i}].quantity_needed`)
        : undefined,
    }));

    // ENR-LE4: Auto-assign if no explicit assigned_to and setting enabled
    const effectiveAssignedTo = assigned_to ?? await autoAssignLead(adb);

    // BUGHUNT-2026-05-17: bundle the lead INSERT, order_id rename, and all
    // device INSERTs into a single adb.transaction so a crash mid-loop
    // can't leave a lead with order_id='TEMP' or a partial device list
    // that misleads the technician about scope of work. order_id is set
    // via a SQL printf expression keyed off the just-inserted rowid so we
    // don't need a round-trip back to JS to compute it.
    const leadTxQueries: TxQuery[] = [
      {
        sql: `INSERT INTO leads (order_id, customer_id, first_name, last_name, email, phone,
                zip_code, address, status, referred_by, assigned_to, source, notes, created_by)
              VALUES ('TEMP', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        params: [
          customer_id ?? null,
          first_name,
          last_name ?? '',
          validatedEmail,
          validatedPhone,
          zip_code ?? null,
          address ?? null,
          status ?? 'new',
          referred_by ?? null,
          effectiveAssignedTo,
          source ?? null,
          notes ?? null,
          req.user!.id,
        ],
      },
      {
        sql: `UPDATE leads SET order_id = 'L-' || printf('%04d', id) WHERE id = ?`,
        params: [lastInsertRowidFrom(0)],
      },
    ];
    for (const d of validatedDevices) {
      leadTxQueries.push({
        sql: `INSERT INTO lead_devices (lead_id, device_name, repair_type, service_type, service_id,
                price, tax, problem, customer_notes, security_code, start_time, end_time)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        params: [
          lastInsertRowidFrom(0),
          d.device_name,
          d.repair_type,
          d.service_type,
          d.service_id,
          d.price,
          d.tax,
          d.problem,
          d.customer_notes,
          d.security_code,
          d.start_time,
          d.end_time,
        ],
      });
    }
    const txResults = await adb.transaction(leadTxQueries);
    const leadId = Number(txResults[0]!.lastInsertRowid);

    const [lead, leadDevices] = await Promise.all([
      adb.get<any>('SELECT * FROM leads WHERE id = ?', leadId),
      adb.all<any>('SELECT * FROM lead_devices WHERE lead_id = ?', leadId),
    ]);

    const leadData = { ...(lead as any), devices: leadDevices };
    broadcast(WS_EVENTS.LEAD_CREATED, leadData, req.tenantSlug || null);
    res.status(201).json({
      success: true,
      data: leadData,
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /bulk-action – Bulk delete or status-change leads (WEB-W2-035)
// Must be before /:id routes to avoid Express capturing "bulk-action" as an id.
// ---------------------------------------------------------------------------
router.post(
  '/bulk-action',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const { lead_ids, action, value } = req.body;

    if (!Array.isArray(lead_ids) || lead_ids.length === 0) {
      throw new AppError('lead_ids must be a non-empty array', 400);
    }
    // Cap at 500 to prevent accidental mass-destruction and DoS
    if (lead_ids.length > 500) {
      throw new AppError('Cannot bulk-action more than 500 leads at once', 400);
    }
    const ids = lead_ids.map((id: unknown) => {
      const n = Number(id);
      if (!Number.isInteger(n) || n < 1) throw new AppError('Invalid lead id in lead_ids', 400);
      return n;
    });

    const ph = ids.map(() => '?').join(',');

    if (action === 'delete') {
      // BUGHUNT-2026-05-17: report `affected: result.changes` instead of
      // `ids.length`. The UPDATE's WHERE is_deleted = 0 silently skips
      // already-deleted rows; reporting the requested count overstates
      // the result and leaves the operator believing more was changed
      // than the row count would show.
      const delRes = await adb.run(
        `UPDATE leads SET is_deleted = 1, updated_at = datetime('now') WHERE id IN (${ph}) AND is_deleted = 0`,
        ...ids,
      );
      audit(db, 'leads_bulk_deleted', req.user!.id, req.ip || 'unknown', {
        lead_ids: ids, affected: delRes.changes,
      });
      res.json({ success: true, data: { affected: delRes.changes } });
      return;
    }

    if (action === 'status') {
      if (!value || typeof value !== 'string') {
        throw new AppError('value (status) is required for status action', 400);
      }
      const validStatuses = ['new', 'contacted', 'scheduled', 'qualified', 'proposal', 'converted', 'lost'];
      if (!validStatuses.includes(value)) {
        throw new AppError(`Invalid status value '${value}'`, 400);
      }
      // Bulk status change skips per-row state-machine enforcement intentionally —
      // this is an admin-level batch op. Single-row state machine still applies
      // when updating individual leads via PUT /:id.
      const statusRes = await adb.run(
        `UPDATE leads SET status = ?, updated_at = datetime('now') WHERE id IN (${ph}) AND is_deleted = 0`,
        value, ...ids,
      );
      audit(db, 'leads_bulk_status_changed', req.user!.id, req.ip || 'unknown', {
        lead_ids: ids, status: value, affected: statusRes.changes,
      });
      res.json({ success: true, data: { affected: statusRes.changes } });
      return;
    }

    throw new AppError(`Unknown action '${action}'. Supported: delete, status`, 400);
  }),
);

// ---------------------------------------------------------------------------
// GET /appointments – List appointments
// ---------------------------------------------------------------------------
router.get(
  '/appointments',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();
    const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string, 10) : null;
    const status = (req.query.status as string || '').trim();

    const conditions: string[] = ['a.is_deleted = 0'];
    const params: unknown[] = [];

    if (fromDate) {
      conditions.push('a.start_time >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      // BUGHUNT-2026-05-18: bare `a.start_time <= ?` does lexical string
      // comparison. With `toDate='2026-05-31'` (date-only) and start_time
      // stored as `'2026-05-31T08:00:00.000Z'`, T > "" so the full timestamp
      // is lexically GREATER than the bare date — the appointment is excluded.
      // iOS month-view / FieldService "today" tile lose the last day of the
      // window. Mirror the fix in timesheet.routes.ts:99: when toDate is a
      // bare YYYY-MM-DD, compare against datetime(?, '+1 day') so the entire
      // toDate calendar day is included. Full timestamps fall through to the
      // plain `<= ?` so callers that already pick a specific instant aren't
      // shifted.
      if (/^\d{4}-\d{2}-\d{2}$/.test(toDate)) {
        conditions.push("a.start_time < datetime(?, '+1 day')");
      } else {
        conditions.push('a.start_time <= ?');
      }
      params.push(toDate);
    }
    if (assignedTo) {
      conditions.push('a.assigned_to = ?');
      params.push(assignedTo);
    }
    if (status) {
      conditions.push('a.status = ?');
      params.push(status);
    }

    const whereClause = `WHERE ${conditions.join(' AND ')}`;

    const { total } = await adb.get<{ total: number }>(`SELECT COUNT(*) as total FROM appointments a ${whereClause}`, ...params) as { total: number };
    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const appointments = await adb.all<any>(`
      SELECT a.*,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        l.order_id AS lead_order_id
      FROM appointments a
      LEFT JOIN customers c ON c.id = a.customer_id
      LEFT JOIN users u ON u.id = a.assigned_to
      LEFT JOIN leads l ON l.id = a.lead_id
      ${whereClause}
      ORDER BY a.start_time ASC
      LIMIT ? OFFSET ?
    `, ...params, pageSize, offset);

    res.json({
      success: true,
      data: {
        appointments,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /appointments/overlaps – Cross-window conflict scan (WEB-UIUX-1324)
//
// CalendarPage's pre-flight overlap check uses `existingAppointments`, which
// is just the current month/week/day viewport. A booking on the last day of
// the viewed month against an appt on the first day of the next month gets a
// false-clear. This endpoint runs the same SQL the POST /appointments path
// uses (line ~575) but with no viewport limit, so the client can ask "does
// this assignee already have an appt that overlaps [start_time, end_time]?"
// regardless of what month is rendered.
//
// Required: assigned_to, start_time. end_time falls back to start_time
// (point-in-time check). Returns up to 5 conflicting rows.
// ---------------------------------------------------------------------------
router.get(
  '/appointments/overlaps',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string, 10) : NaN;
    const startTime = (req.query.start_time as string || '').trim();
    const endTime = (req.query.end_time as string || '').trim() || startTime;
    const excludeId = req.query.exclude_id ? parseInt(req.query.exclude_id as string, 10) : null;

    if (!Number.isInteger(assignedTo) || assignedTo < 1) {
      throw new AppError('assigned_to is required', 400);
    }
    if (!startTime) {
      throw new AppError('start_time is required', 400);
    }
    if (new Date(endTime).getTime() < new Date(startTime).getTime()) {
      throw new AppError('end_time must be >= start_time', 400);
    }

    const params: unknown[] = [assignedTo, endTime, startTime];
    let excludeClause = '';
    if (excludeId && Number.isInteger(excludeId)) {
      excludeClause = ' AND a.id != ?';
      params.push(excludeId);
    }

    const overlaps = await adb.all<any>(`
      SELECT a.id, a.title, a.start_time, a.end_time, a.status,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM appointments a
      LEFT JOIN customers c ON c.id = a.customer_id
      WHERE a.assigned_to = ?
        AND a.is_deleted = 0
        AND a.status != 'cancelled'
        AND a.start_time < ?
        AND COALESCE(a.end_time, a.start_time) > ?
        ${excludeClause}
      ORDER BY a.start_time ASC
      LIMIT 5
    `, ...params);

    res.json({
      success: true,
      data: { overlaps, count: overlaps.length },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /appointments – Create appointment
// ---------------------------------------------------------------------------
router.post(
  '/appointments',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const { lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, recurrence, location_id: rawLocationId } = req.body;

    // Validate and resolve location_id; default to 1.
    let resolvedLocationId = 1;
    if (rawLocationId !== undefined && rawLocationId !== null) {
      const parsed = Number(rawLocationId);
      if (!Number.isInteger(parsed) || parsed < 1) {
        throw new AppError('location_id must be a positive integer', 400);
      }
      resolvedLocationId = parsed;
    }

    if (!start_time) throw new AppError('start_time is required');

    // @audit-fixed: validate that start_time / end_time parse to real timestamps.
    // Previously "2025-02-30" silently rolled to March 2 inside the new Date() compare,
    // and a totally invalid string returned NaN ms which made every comparison `false`.
    const startMs = new Date(start_time).getTime();
    if (!Number.isFinite(startMs)) throw new AppError('start_time must be a valid ISO timestamp', 400);
    if (end_time !== undefined && end_time !== null && end_time !== '') {
      const endMs = new Date(end_time).getTime();
      if (!Number.isFinite(endMs)) throw new AppError('end_time must be a valid ISO timestamp', 400);
      // V7: Validate end_time is after start_time
      if (endMs <= startMs) {
        throw new AppError('end_time must be after start_time', 400);
      }
    }

    // ENR-LE12: Validate recurrence value
    const validRecurrences = [null, undefined, '', 'weekly', 'biweekly', 'monthly'];
    if (recurrence && !validRecurrences.includes(recurrence)) {
      throw new AppError('recurrence must be one of: weekly, biweekly, monthly', 400);
    }

    // ENR-LE13: Calendar conflict detection
    let warning: string | undefined;
    if (assigned_to) {
      const effectiveEnd = end_time || start_time; // If no end_time, treat as point-in-time
      const conflict = await adb.get<any>(`
        SELECT id, title, start_time, end_time FROM appointments
        WHERE assigned_to = ?
          AND status != 'cancelled'
          AND start_time < ?
          AND COALESCE(end_time, start_time) > ?
        LIMIT 1
      `, assigned_to, effectiveEnd, start_time);

      if (conflict) {
        warning = 'Technician already has an appointment at this time';
      }
    }

    // BUGHUNT-2026-05-17: previously the parent appointment INSERT + 4 child
    // INSERTs ran sequentially. A crash mid-loop left the user with a parent
    // appointment + some (but not all) of its recurring occurrences. Worse, a
    // partial weekly recurrence (parent + 2 of 4 weeks) silently looked
    // "scheduled" in the calendar but missed weeks 3-4, so customers in those
    // slots would never be reminded and a tech would skip those visits.
    // Pre-compute every occurrence's timing in JS, then batch parent + children
    // into one atomic adb.transaction(). lastInsertRowidFrom(0) so each child's
    // recurrence_parent_id resolves to the parent INSERT's rowid (each child
    // INSERT bumps last_insert_rowid()).
    const apptTxQueries: TxQuery[] = [
      {
        sql: `INSERT INTO appointments (lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, recurrence, location_id)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        params: [
          lead_id ?? null,
          customer_id ?? null,
          title ?? '',
          start_time,
          end_time ?? null,
          assigned_to ?? null,
          status ?? 'scheduled',
          notes ?? null,
          recurrence || null,
          resolvedLocationId,
        ],
      },
    ];

    if (recurrence && ['weekly', 'biweekly', 'monthly'].includes(recurrence)) {
      const OCCURRENCE_COUNT = 4;
      const baseStart = new Date(start_time);
      const baseEnd = end_time ? new Date(end_time) : null;

      // SEC-L39: recurring occurrences previously used native `setMonth(
      // getMonth() + i)` which silently rolls Jan 31 → Mar 3 on non-leap
      // years because Feb only has 28/29 days. addMonthsClamped() clamps
      // the day to the last valid day of the target month so the 31st
      // of one month lands on the 28/29/30/31 of the next, matching how
      // humans read "monthly on the 31st".
      const addMonthsClamped = (source: Date, months: number): Date => {
        const d = new Date(source);
        const originalDay = d.getDate();
        d.setDate(1);
        d.setMonth(d.getMonth() + months);
        const lastDayOfTarget = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
        d.setDate(Math.min(originalDay, lastDayOfTarget));
        return d;
      };
      const fmtDate = (d: Date) => d.toISOString().replace('T', ' ').substring(0, 19);

      for (let i = 1; i <= OCCURRENCE_COUNT; i++) {
        let nextStart: Date;
        let nextEnd: Date | null;

        if (recurrence === 'weekly') {
          nextStart = new Date(baseStart);
          nextStart.setDate(nextStart.getDate() + 7 * i);
          nextEnd = baseEnd ? new Date(baseEnd) : null;
          if (nextEnd) nextEnd.setDate(nextEnd.getDate() + 7 * i);
        } else if (recurrence === 'biweekly') {
          nextStart = new Date(baseStart);
          nextStart.setDate(nextStart.getDate() + 14 * i);
          nextEnd = baseEnd ? new Date(baseEnd) : null;
          if (nextEnd) nextEnd.setDate(nextEnd.getDate() + 14 * i);
        } else {
          nextStart = addMonthsClamped(baseStart, i);
          nextEnd = baseEnd ? addMonthsClamped(baseEnd, i) : null;
        }

        apptTxQueries.push({
          sql: `INSERT INTO appointments (lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, recurrence, recurrence_parent_id, location_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          params: [
            lead_id ?? null,
            customer_id ?? null,
            title ?? '',
            fmtDate(nextStart),
            nextEnd ? fmtDate(nextEnd) : null,
            assigned_to ?? null,
            'scheduled',
            notes ?? null,
            recurrence,
            lastInsertRowidFrom(0),
            resolvedLocationId,
          ],
        });
      }
    }

    const apptTxResults = await adb.transaction(apptTxQueries);
    const parentId = Number(apptTxResults[0].lastInsertRowid);
    const recurringIds: number[] = apptTxResults
      .slice(1)
      .map((r) => Number(r.lastInsertRowid));

    const appointment = await adb.get<any>('SELECT * FROM appointments WHERE id = ?', parentId);

    const response: any = { success: true, data: appointment };
    if (warning) {
      response.warning = warning;
    }
    if (recurringIds.length > 0) {
      response.recurring_ids = recurringIds;
    }
    res.status(201).json(response);
  }),
);

// ---------------------------------------------------------------------------
// PUT /appointments/:id – Update appointment
// ---------------------------------------------------------------------------
router.put(
  '/appointments/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    // @audit-fixed: validate id — Number("abc") = NaN was silently flowing into SQL
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid appointment ID', 400);
    const existing = await adb.get<any>('SELECT * FROM appointments WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Appointment not found', 404);

    const { lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, no_show } = req.body;

    // ENR-LE11: Accept no_show boolean field
    const effectiveNoShow = no_show !== undefined ? (no_show ? 1 : 0) : existing.no_show;

    await adb.run(`
      UPDATE appointments SET
        lead_id = ?, customer_id = ?, title = ?, start_time = ?, end_time = ?,
        assigned_to = ?, status = ?, notes = ?, no_show = ?, updated_at = datetime('now')
      WHERE id = ?
    `,
      lead_id !== undefined ? lead_id : existing.lead_id,
      customer_id !== undefined ? customer_id : existing.customer_id,
      title !== undefined ? title : existing.title,
      start_time !== undefined ? start_time : existing.start_time,
      end_time !== undefined ? end_time : existing.end_time,
      assigned_to !== undefined ? assigned_to : existing.assigned_to,
      status !== undefined ? status : existing.status,
      notes !== undefined ? notes : existing.notes,
      effectiveNoShow,
      id,
    );

    // ENR-LE11: Log no-show to audit when marked
    if (no_show && !existing.no_show) {
      audit(db, 'appointment_no_show', req.user!.id, req.ip || 'unknown', {
        appointment_id: id,
        customer_id: existing.customer_id,
        lead_id: existing.lead_id,
      });
    }

    const updated = await adb.get<any>('SELECT * FROM appointments WHERE id = ?', id);
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /appointments/:id – Soft delete appointment
// ---------------------------------------------------------------------------
router.delete(
  '/appointments/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    // @audit-fixed: validate id — Number("abc") = NaN was silently flowing into SQL
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid appointment ID', 400);
    const existing = await adb.get<{ id: number; assigned_to: number | null }>(
      'SELECT id, assigned_to FROM appointments WHERE id = ? AND is_deleted = 0',
      id,
    );
    if (!existing) throw new AppError('Appointment not found', 404);

    // D3-4: only admin OR the owner (assigned_to) may delete. Previously any
    // authenticated tech could enumerate IDs and soft-delete the entire
    // company's calendar.
    const user = req.user!;
    const isAdmin = user.role === 'admin';
    const isOwner = existing.assigned_to != null && existing.assigned_to === user.id;
    if (!isAdmin && !isOwner) {
      throw new AppError('You do not have permission to delete this appointment', 403);
    }

    // BUGHUNT-2026-05-17: AND is_deleted = 0 + use result.changes so
    // two concurrent deletes don't both write an audit-row equivalent.
    const apptDelRes = await adb.run(
      "UPDATE appointments SET is_deleted = 1, updated_at = datetime('now') WHERE id = ? AND is_deleted = 0",
      id,
    );
    if (apptDelRes.changes === 0) {
      throw new AppError('Appointment was just deleted; refresh and retry', 409);
    }
    res.json({ success: true, data: { message: 'Appointment deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Lead detail
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    // @audit-fixed: validate id — Number("abc") = NaN was silently flowing into SQL
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid lead ID', 400);

    const lead = await adb.get<any>(`
      SELECT l.*,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM leads l
      LEFT JOIN users u ON u.id = l.assigned_to
      LEFT JOIN customers c ON c.id = l.customer_id
      WHERE l.id = ? AND l.is_deleted = 0
    `, id);

    if (!lead) throw new AppError('Lead not found', 404);

    const [devices, appointments] = await Promise.all([
      adb.all<any>('SELECT * FROM lead_devices WHERE lead_id = ?', id),
      adb.all<any>('SELECT * FROM appointments WHERE lead_id = ? ORDER BY start_time ASC', id),
    ]);

    // ENR-LE3: Compute lead_score
    const lead_score = computeLeadScore({ ...(lead as any), devices }, appointments);

    res.json({
      success: true,
      data: { ...(lead as any), devices, appointments, lead_score },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update lead
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    // @audit-fixed: validate id
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid lead ID', 400);
    const existing = await adb.get<any>('SELECT * FROM leads WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Lead not found', 404);

    const {
      customer_id, first_name, last_name, email, phone,
      zip_code, address, status, referred_by, assigned_to,
      source, notes, devices, lost_reason,
    } = req.body;

    // V14: normalize + validate phone if supplied (reject "+++++invalid" et al.)
    const validatedPhone = phone !== undefined
      ? normalizeAndValidatePhone(phone, 'phone')
      : undefined;
    // V5: email validation at edit boundary.
    const validatedEmail = email !== undefined
      ? validateEmail(email, 'email', false)
      : undefined;

    // ENR-LE5: Require lost_reason when status changes to 'lost'
    const effectiveStatus = status !== undefined ? status : existing.status;
    if (effectiveStatus === 'lost' && existing.status !== 'lost' && !lost_reason) {
      throw new AppError('lost_reason is required when marking a lead as lost', 400);
    }

    // SEC-H113: enforce state-machine transition before writing
    if (status !== undefined && status !== existing.status) {
      assertLeadTransition(existing.status, status);
      // WEB-UIUX-1337: refuse 'converted' on the generic PUT path. The
      // /convert endpoint is the canonical entry — it creates the ticket,
      // dedupes/creates the customer, writes the lead_converted audit, and
      // broadcasts. PUT-to-converted silently sets the badge with none of
      // those side effects, leaving the operator believing a ticket exists
      // when nothing downstream has fired.
      if (status === 'converted') {
        throw new AppError(
          "Use POST /leads/:id/convert to mark a lead converted (it creates the ticket + customer). PUT cannot set status='converted' directly.",
          400,
        );
      }
    }

    // V16: trim + enum check — rejects " price " and similar whitespace bypass attempts.
    const validatedLostReason = lost_reason !== undefined && lost_reason !== null && lost_reason !== ''
      ? validateEnum(lost_reason, VALID_LOST_REASONS, 'lost_reason', false)
      : null;

    // V17: bound device array BEFORE validating each item.
    const deviceList = devices !== undefined && devices !== null
      ? validateArrayBounds<any>(devices, 'devices', MAX_LEAD_DEVICES)
      : undefined;

    // V15: validate prices + taxes up front.
    const validatedDevices = deviceList?.map((d, i) => ({
      device_name: d.device_name ?? '',
      repair_type: d.repair_type ?? null,
      service_type: d.service_type ?? null,
      service_id: d.service_id ?? null,
      price: validatePrice(d.price ?? 0, `devices[${i}].price`),
      tax: validatePrice(d.tax ?? 0, `devices[${i}].tax`),
      problem: d.problem ?? null,
      customer_notes: d.customer_notes ?? null,
      security_code: d.security_code ?? null,
      start_time: d.start_time ?? null,
      end_time: d.end_time ?? null,
      quantity_needed: d.quantity_needed !== undefined && d.quantity_needed !== null
        ? validateQuantity(d.quantity_needed, `devices[${i}].quantity_needed`)
        : undefined,
    }));

    // BUGHUNT-2026-05-17: CAS on status — the state-machine transition was
    // validated against existing.status above, but the unguarded UPDATE
    // would let a concurrent /convert (or another PUT) silently slip its
    // status change past us, bypassing assertLeadTransition. With `AND
    // status = ?` the writer that arrives second sees changes=0 → 409.
    const leadUpdRes = await adb.run(`
      UPDATE leads SET
        customer_id = ?, first_name = ?, last_name = ?, email = ?, phone = ?,
        zip_code = ?, address = ?, status = ?, referred_by = ?, assigned_to = ?,
        source = ?, notes = ?, lost_reason = ?, updated_at = datetime('now')
      WHERE id = ? AND status = ?
    `,
      customer_id !== undefined ? customer_id : existing.customer_id,
      first_name !== undefined ? first_name : existing.first_name,
      last_name !== undefined ? last_name : existing.last_name,
      validatedEmail !== undefined ? validatedEmail : existing.email,
      validatedPhone !== undefined ? validatedPhone : existing.phone,
      zip_code !== undefined ? zip_code : existing.zip_code,
      address !== undefined ? address : existing.address,
      effectiveStatus,
      referred_by !== undefined ? referred_by : existing.referred_by,
      assigned_to !== undefined ? assigned_to : existing.assigned_to,
      source !== undefined ? source : existing.source,
      notes !== undefined ? notes : existing.notes,
      effectiveStatus === 'lost' ? (validatedLostReason ?? existing.lost_reason) : null,
      id,
      existing.status,
    );
    if (leadUpdRes.changes === 0) {
      throw new AppError('Lead status changed concurrently; refresh and retry', 409);
    }

    // Replace devices if provided
    // BUGHUNT-2026-05-17: bundle the DELETE + each INSERT into a single
    // adb.transaction so a mid-loop failure (constraint, disk full, FK
    // miss on a poorly-shaped catalog service_id) doesn't leave the lead
    // with partial devices — previously DELETE would commit and then
    // the loop crash would leave the lead with zero devices despite the
    // PUT containing many.
    if (validatedDevices !== undefined) {
      const deviceTxQueries: import('../db/async-db.js').TxQuery[] = [
        { sql: 'DELETE FROM lead_devices WHERE lead_id = ?', params: [id] },
      ];
      for (const d of validatedDevices) {
        deviceTxQueries.push({
          sql: `INSERT INTO lead_devices (lead_id, device_name, repair_type, service_type, service_id,
                  price, tax, problem, customer_notes, security_code, start_time, end_time)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          params: [
            id,
            d.device_name,
            d.repair_type,
            d.service_type,
            d.service_id,
            d.price,
            d.tax,
            d.problem,
            d.customer_notes,
            d.security_code,
            d.start_time,
            d.end_time,
          ],
        });
      }
      await adb.transaction(deviceTxQueries);
    }

    const [lead, leadDevices] = await Promise.all([
      adb.get<any>('SELECT * FROM leads WHERE id = ?', id),
      adb.all<any>('SELECT * FROM lead_devices WHERE lead_id = ?', id),
    ]);

    res.json({
      success: true,
      data: { ...(lead as any), devices: leadDevices },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/reminder – Create a follow-up reminder for a lead (ENR-LE2)
// ---------------------------------------------------------------------------
router.post(
  '/:id/reminder',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    // @audit-fixed: validate id
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid lead ID', 400);
    const existing = await adb.get<any>('SELECT id FROM leads WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Lead not found', 404);

    const { remind_at, note } = req.body;
    if (!remind_at) throw new AppError('remind_at is required');
    // @audit-fixed: V8 ISO date validation — bad timestamps were inserted verbatim
    if (typeof remind_at !== 'string' || isNaN(new Date(remind_at).getTime())) {
      throw new AppError('remind_at must be a valid ISO timestamp', 400);
    }

    const result = await adb.run(`
      INSERT INTO lead_reminders (lead_id, remind_at, note, created_by)
      VALUES (?, ?, ?, ?)
    `, id, remind_at, note ?? null, req.user!.id);

    const reminder = await adb.get<any>('SELECT * FROM lead_reminders WHERE id = ?', result.lastInsertRowid);

    audit(db, 'lead_reminder_created', req.user!.id, req.ip || 'unknown', { lead_id: id, reminder_id: result.lastInsertRowid });
    res.status(201).json({ success: true, data: reminder });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/reminders – List reminders for a lead (ENR-LE2)
// ---------------------------------------------------------------------------
router.get(
  '/:id/reminders',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    // @audit-fixed: validate id
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid lead ID', 400);
    const existing = await adb.get<any>('SELECT id FROM leads WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Lead not found', 404);

    const reminders = await adb.all<any>(`
      SELECT r.*, u.first_name AS created_by_first_name, u.last_name AS created_by_last_name
      FROM lead_reminders r
      LEFT JOIN users u ON u.id = r.created_by
      WHERE r.lead_id = ?
      ORDER BY r.remind_at ASC
    `, id);

    res.json({ success: true, data: reminders });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/convert – Convert lead to ticket
// ---------------------------------------------------------------------------
router.post(
  '/:id/convert',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    // @audit-fixed: validate id
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid lead ID', 400);
    const lead = await adb.get<any>('SELECT * FROM leads WHERE id = ? AND is_deleted = 0', id);
    if (!lead) throw new AppError('Lead not found', 404);
    if (lead.status === 'converted') throw new AppError('Lead already converted', 400);
    // SEC-H113: enforce state-machine transition before writing
    assertLeadTransition(lead.status, 'converted');

    // BUGHUNT-2026-05-17: claim the conversion atomically up-front so two
    // concurrent /convert calls on the same lead can't both pass the
    // SELECT-status precheck above, both reserve tier slots, and both
    // create separate tickets. The UPDATE WHERE status != 'converted'
    // serialises via SQLite's writer lock — only one caller flips the
    // status; the loser sees changes=0 and gets 409. If downstream work
    // fails after the claim, the operator can manually transition the
    // lead back via PUT /:id (the converted→new transition is legal).
    const claimResult = await adb.run(
      "UPDATE leads SET status = 'converted', updated_at = datetime('now') WHERE id = ? AND status != 'converted' AND is_deleted = 0",
      id,
    );
    if (claimResult.changes === 0) {
      throw new AppError('Lead already converted (race with another request)', 409);
    }

    // Tier: atomic monthly ticket limit check (check + pre-increment in one transaction)
    // Free plans cap maxTicketsMonth; Pro plans set it to null (unlimited).
    let tierReservationCommitted = false;
    const tierReservationTenantId = req.tenantId;
    if (config.multiTenant && tierReservationTenantId && req.tenantLimits?.maxTicketsMonth != null) {
      const { getMasterDb } = await import('../db/master-connection.js');
      const masterDb = getMasterDb();
      if (masterDb) {
        const month = new Date().toISOString().slice(0, 7); // YYYY-MM
        const limit = req.tenantLimits.maxTicketsMonth;

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
    void tierReservationCommitted;

    // Find or create customer. Persist the customer_id back to the lead row immediately
    // so that if ticket creation fails downstream, a retry will reuse the same customer
    // instead of creating duplicates (and the orphan is at least linked to its lead).
    let customerId = lead.customer_id;
    if (!customerId && (lead.first_name || lead.last_name)) {
      // V5: re-validate email + phone on conversion. Historical leads (imports, old rows
      // predating validators) may hold junk that would poison the customer table otherwise.
      // Allow nulls (the field was simply not collected) but reject malformed values.
      const convertedEmail = lead.email ? validateEmail(lead.email, 'email', false) : null;
      const convertedPhone = lead.phone ? normalizeAndValidatePhone(lead.phone, 'phone') : null;

      // WEB-UIUX-1339: dedupe against existing customer rows before INSERT.
      // Match on email (case-insensitive) OR normalized phone. CustomerCreate
      // already does this check; convert flow used to silently INSERT a
      // duplicate, polluting loyalty + dedup + support history. Link the lead
      // to the existing customer instead of creating a second row.
      let existingCustomer: { id: number; is_deleted: number } | undefined;
      if (convertedEmail) {
        existingCustomer = await adb.get<{ id: number; is_deleted: number }>(
          'SELECT id, is_deleted FROM customers WHERE LOWER(email) = LOWER(?) ORDER BY is_deleted ASC, id ASC LIMIT 1',
          convertedEmail,
        );
      }
      if (!existingCustomer && convertedPhone) {
        existingCustomer = await adb.get<{ id: number; is_deleted: number }>(
          'SELECT id, is_deleted FROM customers WHERE phone = ? ORDER BY is_deleted ASC, id ASC LIMIT 1',
          convertedPhone,
        );
      }
      if (existingCustomer && existingCustomer.is_deleted === 0) {
        customerId = existingCustomer.id;
        await adb.run('UPDATE leads SET customer_id = ? WHERE id = ?', customerId, id);
      } else {
        const custResult = await adb.run(`
          INSERT INTO customers (first_name, last_name, email, phone, source)
          VALUES (?, ?, ?, ?, 'lead')
        `, lead.first_name, lead.last_name, convertedEmail, convertedPhone);
        customerId = custResult.lastInsertRowid as number;
        const code = generateOrderId('C', customerId);
        await adb.run('UPDATE customers SET code = ? WHERE id = ?', code, customerId);
        // Link the new customer to the lead so retries are idempotent
        await adb.run('UPDATE leads SET customer_id = ? WHERE id = ?', customerId, id);
      }
    }

    if (!customerId) throw new AppError('Cannot convert lead without customer information', 400);

    // Get default (open) status
    const defaultStatus = await adb.get<any>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
    const statusId = defaultStatus?.id ?? 1;

    // Create ticket
    const ticketResult = await adb.run(`
      INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, source, referral_source, created_by)
      VALUES ('TEMP', ?, ?, ?, 'lead', ?, ?)
    `, customerId, statusId, lead.assigned_to, lead.referred_by, req.user!.id);

    const ticketId = ticketResult.lastInsertRowid as number;
    const ticketOrderId = generateOrderId('T', ticketId);
    await adb.run('UPDATE tickets SET order_id = ? WHERE id = ?', ticketOrderId, ticketId);

    // Copy devices
    const leadDevices = await adb.all<any>('SELECT * FROM lead_devices WHERE lead_id = ?', id);
    for (const d of leadDevices) {
      // @audit-fixed: validate price/tax + use rounded math instead of `||0` float add.
      // Lead-side validators only ran when the lead was created/updated; legacy rows
      // imported from RD could carry NaN/string values that broke ticket totals on conversion.
      const dp = Number(d.price);
      const dt = Number(d.tax);
      const safePrice = Number.isFinite(dp) && dp >= 0 ? dp : 0;
      const safeTax = Number.isFinite(dt) && dt >= 0 ? dt : 0;
      const lineTotal = Math.round((safePrice + safeTax) * 100) / 100;
      await adb.run(`
        INSERT INTO ticket_devices (ticket_id, device_name, service_id, price, tax_amount, total, additional_notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `, ticketId, d.device_name, d.service_id, safePrice, safeTax, lineTotal, d.problem);
    }

    // Recalc ticket totals
    const totals = await adb.get<any>(`
      SELECT COALESCE(SUM(price), 0) as subtotal, COALESCE(SUM(tax_amount), 0) as total_tax, COALESCE(SUM(total), 0) as total
      FROM ticket_devices WHERE ticket_id = ?
    `, ticketId);

    await adb.run('UPDATE tickets SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?',
      totals.subtotal, totals.total_tax, totals.total, ticketId);

    // WEB-UIUX-1340: carry open lead reminders forward as a ticket note so
    // the future-Monday follow-up doesn't silently vanish when the lead
    // closes. No new ticket_reminders table — the reminder text just becomes
    // a visible ticket-note line so the operator sees it on the ticket
    // detail's note history. Each reminder gets the remind_at date prefix.
    try {
      const openReminders = await adb.all<any>(
        `SELECT remind_at, note FROM lead_reminders
          WHERE lead_id = ? AND COALESCE(completed, 0) = 0
       ORDER BY remind_at ASC`,
        id,
      );
      if (openReminders.length > 0) {
        const lines = openReminders.map((r) => {
          const due = r.remind_at ? String(r.remind_at) : 'no date';
          const text = r.note ? String(r.note).trim() : '(no note)';
          return `• ${due} — ${text}`;
        });
        const noteBody =
          `[Carried from Lead ${lead.order_id ?? `#${id}`}] ${openReminders.length} open reminder${openReminders.length === 1 ? '' : 's'}:\n`
          + lines.join('\n');
        await adb.run(
          `INSERT INTO ticket_notes (ticket_id, user_id, content, created_at, updated_at)
           VALUES (?, ?, ?, datetime('now'), datetime('now'))`,
          ticketId, req.user!.id, noteBody.slice(0, 4000),
        );
      }
    } catch (remErr) {
      logger.warn('lead_convert_reminder_carryover_failed', {
        error: remErr instanceof Error ? remErr.message : String(remErr),
        lead_id: id,
        ticket_id: ticketId,
      });
    }

    // Lead status was already flipped to 'converted' atomically at the top of
    // this handler (BUGHUNT-2026-05-17). Nothing more to do here.

    const ticket = await adb.get<any>('SELECT * FROM tickets WHERE id = ?', ticketId);
    // WEB-UIUX-1350: include the lead's order_id alongside the ticket so the
    // client can render "Lead #L042 → Ticket #T117" with both stable IDs and
    // unify success copy between the list and detail surfaces.
    const leadStub = await adb.get<{ id: number; order_id: string | null }>(
      'SELECT id, order_id FROM leads WHERE id = ?', id,
    );

    audit(db, 'lead_converted', req.user!.id, req.ip || 'unknown', { lead_id: id, ticket_id: ticketId });

    res.status(201).json({
      success: true,
      data: { ticket, lead: leadStub ?? { id, order_id: null }, message: 'Lead converted to ticket' },
    });
  }),
);

// ─── DELETE /leads/:id (soft delete) ──────────────────────────
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    // @audit-fixed: validate id
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid lead ID', 400);
    const existing = await adb.get<{ id: number; assigned_to: number | null }>(
      'SELECT id, assigned_to FROM leads WHERE id = ? AND is_deleted = 0',
      id,
    );
    if (!existing) throw new AppError('Lead not found', 404);

    // Only admin/manager OR the assignee may delete. Without this any
    // technician/cashier could enumerate IDs and soft-delete the entire
    // lead pipeline (mirrors the DELETE /appointments/:id gate above).
    const user = req.user!;
    const isAdminOrManager = user.role === 'admin' || user.role === 'manager';
    const isOwner = existing.assigned_to != null && existing.assigned_to === user.id;
    if (!isAdminOrManager && !isOwner) {
      throw new AppError('You do not have permission to delete this lead', 403);
    }

    await adb.run("UPDATE leads SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?", id);

    audit(db, 'lead_deleted', req.user!.id, req.ip || 'unknown', { lead_id: id });

    res.json({ success: true, data: { message: 'Lead deleted' } });
  }),
);

export default router;
