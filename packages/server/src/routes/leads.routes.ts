import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

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
    const created = new Date(lead.created_at).getTime();
    const updated = new Date(lead.updated_at).getTime();
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
      ORDER BY l.updated_at DESC
    `);

    const pipeline: Record<string, any[]> = {};
    for (const lead of leads) {
      const status = lead.status || 'new';
      if (!pipeline[status]) {
        pipeline[status] = [];
      }
      pipeline[status].push(lead);
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
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const keyword = (req.query.keyword as string || '').trim();
    const status = (req.query.status as string || '').trim();
    const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string, 10) : null;
    const sortBy = (req.query.sort_by as string) || 'created_at';
    const sortOrder = (req.query.sort_order as string || 'DESC').toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

    const allowedSorts = ['created_at', 'updated_at', 'first_name', 'last_name', 'status'];
    const safeSortBy = allowedSorts.includes(sortBy) ? sortBy : 'created_at';

    const conditions: string[] = [];
    const params: unknown[] = [];

    if (keyword) {
      conditions.push('(l.first_name LIKE ? OR l.last_name LIKE ? OR l.email LIKE ? OR l.phone LIKE ? OR l.order_id LIKE ?)');
      const like = `%${keyword}%`;
      params.push(like, like, like, like, like);
    }

    if (status) {
      conditions.push('l.status = ?');
      params.push(status);
    }

    if (assignedTo) {
      conditions.push('l.assigned_to = ?');
      params.push(assignedTo);
    }

    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

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
function autoAssignLead(db: any): number | null {
  const setting = db.prepare("SELECT value FROM store_config WHERE key = 'lead_auto_assign'").get() as any;
  if (!setting?.value || setting.value === 'off') return null;

  const technicians = db.prepare(
    "SELECT id FROM users WHERE role IN ('admin', 'technician', 'manager') AND is_active = 1 ORDER BY id"
  ).all() as any[];
  if (technicians.length === 0) return null;

  if (setting.value === 'least_loaded') {
    // Assign to technician with fewest open leads
    const result = db.prepare(`
      SELECT u.id, COUNT(l.id) AS open_count
      FROM users u
      LEFT JOIN leads l ON l.assigned_to = u.id AND l.status NOT IN ('converted', 'lost')
      WHERE u.role IN ('admin', 'technician', 'manager') AND u.is_active = 1
      GROUP BY u.id
      ORDER BY open_count ASC, u.id ASC
      LIMIT 1
    `).get() as any;
    return result?.id ?? technicians[0].id;
  }

  // round_robin: pick the next technician after the most recently assigned
  const lastAssigned = db.prepare(`
    SELECT assigned_to FROM leads WHERE assigned_to IS NOT NULL ORDER BY id DESC LIMIT 1
  `).get() as any;

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
    const db = req.db;
    const adb = req.asyncDb;
    const {
      customer_id, first_name, last_name, email, phone,
      zip_code, address, status, referred_by, assigned_to,
      source, notes, devices,
    } = req.body;

    if (!first_name) throw new AppError('first_name is required');

    // ENR-LE4: Auto-assign if no explicit assigned_to and setting enabled
    const effectiveAssignedTo = assigned_to ?? autoAssignLead(db);

    const createLead = db.transaction(() => {
      const result = db.prepare(`
        INSERT INTO leads (order_id, customer_id, first_name, last_name, email, phone,
          zip_code, address, status, referred_by, assigned_to, source, notes, created_by)
        VALUES ('TEMP', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        customer_id ?? null,
        first_name,
        last_name ?? '',
        email ?? null,
        phone ?? null,
        zip_code ?? null,
        address ?? null,
        status ?? 'new',
        referred_by ?? null,
        effectiveAssignedTo,
        source ?? null,
        notes ?? null,
        req.user!.id,
      );

      const leadId = result.lastInsertRowid as number;
      const orderId = generateOrderId('L', leadId);
      db.prepare('UPDATE leads SET order_id = ? WHERE id = ?').run(orderId, leadId);

      // Insert devices
      if (devices?.length) {
        const insertDevice = db.prepare(`
          INSERT INTO lead_devices (lead_id, device_name, repair_type, service_type, service_id,
            price, tax, problem, customer_notes, security_code, start_time, end_time)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `);
        for (const d of devices) {
          insertDevice.run(
            leadId,
            d.device_name ?? '',
            d.repair_type ?? null,
            d.service_type ?? null,
            d.service_id ?? null,
            d.price ?? 0,
            d.tax ?? 0,
            d.problem ?? null,
            d.customer_notes ?? null,
            d.security_code ?? null,
            d.start_time ?? null,
            d.end_time ?? null,
          );
        }
      }

      return leadId;
    });

    const leadId = createLead();
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
// GET /appointments – List appointments
// ---------------------------------------------------------------------------
router.get(
  '/appointments',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();
    const assignedTo = req.query.assigned_to ? parseInt(req.query.assigned_to as string, 10) : null;
    const status = (req.query.status as string || '').trim();

    const conditions: string[] = [];
    const params: unknown[] = [];

    if (fromDate) {
      conditions.push('a.start_time >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      conditions.push('a.start_time <= ?');
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

    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

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
// POST /appointments – Create appointment
// ---------------------------------------------------------------------------
router.post(
  '/appointments',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const { lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, recurrence } = req.body;

    if (!start_time) throw new AppError('start_time is required');

    // V7: Validate end_time is after start_time
    if (end_time && new Date(end_time) <= new Date(start_time)) {
      throw new AppError('end_time must be after start_time', 400);
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

    const result = await adb.run(`
      INSERT INTO appointments (lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, recurrence)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
      lead_id ?? null,
      customer_id ?? null,
      title ?? '',
      start_time,
      end_time ?? null,
      assigned_to ?? null,
      status ?? 'scheduled',
      notes ?? null,
      recurrence || null,
    );

    const parentId = result.lastInsertRowid;

    // ENR-LE12: Auto-create recurring occurrences (next 4 by default)
    const recurringIds: number[] = [];
    if (recurrence && ['weekly', 'biweekly', 'monthly'].includes(recurrence)) {
      const OCCURRENCE_COUNT = 4;
      const baseStart = new Date(start_time);
      const baseEnd = end_time ? new Date(end_time) : null;

      for (let i = 1; i <= OCCURRENCE_COUNT; i++) {
        const nextStart = new Date(baseStart);
        const nextEnd = baseEnd ? new Date(baseEnd) : null;

        if (recurrence === 'weekly') {
          nextStart.setDate(nextStart.getDate() + 7 * i);
          if (nextEnd) nextEnd.setDate(nextEnd.getDate() + 7 * i);
        } else if (recurrence === 'biweekly') {
          nextStart.setDate(nextStart.getDate() + 14 * i);
          if (nextEnd) nextEnd.setDate(nextEnd.getDate() + 14 * i);
        } else {
          nextStart.setMonth(nextStart.getMonth() + i);
          if (nextEnd) nextEnd.setMonth(nextEnd.getMonth() + i);
        }

        const fmtDate = (d: Date) => d.toISOString().replace('T', ' ').substring(0, 19);
        const childResult = await adb.run(`
          INSERT INTO appointments (lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes, recurrence, recurrence_parent_id)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
          lead_id ?? null,
          customer_id ?? null,
          title ?? '',
          fmtDate(nextStart),
          nextEnd ? fmtDate(nextEnd) : null,
          assigned_to ?? null,
          'scheduled',
          notes ?? null,
          recurrence,
          parentId,
        );
        recurringIds.push(childResult.lastInsertRowid);
      }
    }

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
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT * FROM appointments WHERE id = ?', id);
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
// DELETE /appointments/:id – Delete appointment
// ---------------------------------------------------------------------------
router.delete(
  '/appointments/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT id FROM appointments WHERE id = ?', id);
    if (!existing) throw new AppError('Appointment not found', 404);

    await adb.run('DELETE FROM appointments WHERE id = ?', id);
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
    const id = Number(req.params.id);

    const lead = await adb.get<any>(`
      SELECT l.*,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM leads l
      LEFT JOIN users u ON u.id = l.assigned_to
      LEFT JOIN customers c ON c.id = l.customer_id
      WHERE l.id = ?
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
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT * FROM leads WHERE id = ?', id);
    if (!existing) throw new AppError('Lead not found', 404);

    const {
      customer_id, first_name, last_name, email, phone,
      zip_code, address, status, referred_by, assigned_to,
      source, notes, devices, lost_reason,
    } = req.body;

    // ENR-LE5: Require lost_reason when status changes to 'lost'
    const effectiveStatus = status !== undefined ? status : existing.status;
    if (effectiveStatus === 'lost' && existing.status !== 'lost' && !lost_reason) {
      throw new AppError('lost_reason is required when marking a lead as lost', 400);
    }

    const VALID_LOST_REASONS = ['price', 'competitor', 'no_response', 'changed_mind', 'other'];
    if (lost_reason && !VALID_LOST_REASONS.includes(lost_reason)) {
      throw new AppError(`lost_reason must be one of: ${VALID_LOST_REASONS.join(', ')}`, 400);
    }

    const updateLead = db.transaction(() => {
      db.prepare(`
        UPDATE leads SET
          customer_id = ?, first_name = ?, last_name = ?, email = ?, phone = ?,
          zip_code = ?, address = ?, status = ?, referred_by = ?, assigned_to = ?,
          source = ?, notes = ?, lost_reason = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(
        customer_id !== undefined ? customer_id : existing.customer_id,
        first_name !== undefined ? first_name : existing.first_name,
        last_name !== undefined ? last_name : existing.last_name,
        email !== undefined ? email : existing.email,
        phone !== undefined ? phone : existing.phone,
        zip_code !== undefined ? zip_code : existing.zip_code,
        address !== undefined ? address : existing.address,
        effectiveStatus,
        referred_by !== undefined ? referred_by : existing.referred_by,
        assigned_to !== undefined ? assigned_to : existing.assigned_to,
        source !== undefined ? source : existing.source,
        notes !== undefined ? notes : existing.notes,
        effectiveStatus === 'lost' ? (lost_reason ?? existing.lost_reason) : null,
        id,
      );

      // Replace devices if provided
      if (devices !== undefined) {
        db.prepare('DELETE FROM lead_devices WHERE lead_id = ?').run(id);
        if (devices?.length) {
          const insertDevice = db.prepare(`
            INSERT INTO lead_devices (lead_id, device_name, repair_type, service_type, service_id,
              price, tax, problem, customer_notes, security_code, start_time, end_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `);
          for (const d of devices) {
            insertDevice.run(
              id,
              d.device_name ?? '',
              d.repair_type ?? null,
              d.service_type ?? null,
              d.service_id ?? null,
              d.price ?? 0,
              d.tax ?? 0,
              d.problem ?? null,
              d.customer_notes ?? null,
              d.security_code ?? null,
              d.start_time ?? null,
              d.end_time ?? null,
            );
          }
        }
      }
    });

    updateLead();

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
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT id FROM leads WHERE id = ?', id);
    if (!existing) throw new AppError('Lead not found', 404);

    const { remind_at, note } = req.body;
    if (!remind_at) throw new AppError('remind_at is required');

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
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT id FROM leads WHERE id = ?', id);
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
    const id = Number(req.params.id);
    const lead = await adb.get<any>('SELECT * FROM leads WHERE id = ?', id);
    if (!lead) throw new AppError('Lead not found', 404);
    if (lead.status === 'converted') throw new AppError('Lead already converted', 400);

    const convertLead = db.transaction(() => {
      // Find or create customer
      let customerId = lead.customer_id;
      if (!customerId && (lead.first_name || lead.last_name)) {
        const custResult = db.prepare(`
          INSERT INTO customers (first_name, last_name, email, phone, source)
          VALUES (?, ?, ?, ?, 'lead')
        `).run(lead.first_name, lead.last_name, lead.email, lead.phone);
        customerId = custResult.lastInsertRowid as number;
        const code = generateOrderId('C', customerId);
        db.prepare('UPDATE customers SET code = ? WHERE id = ?').run(code, customerId);
      }

      if (!customerId) throw new AppError('Cannot convert lead without customer information', 400);

      // Get default (open) status
      const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get() as any;
      const statusId = defaultStatus?.id ?? 1;

      // Create ticket
      const ticketResult = db.prepare(`
        INSERT INTO tickets (order_id, customer_id, status_id, assigned_to, source, referral_source, created_by)
        VALUES ('TEMP', ?, ?, ?, 'lead', ?, ?)
      `).run(customerId, statusId, lead.assigned_to, lead.referred_by, req.user!.id);

      const ticketId = ticketResult.lastInsertRowid as number;
      const ticketOrderId = generateOrderId('T', ticketId);
      db.prepare('UPDATE tickets SET order_id = ? WHERE id = ?').run(ticketOrderId, ticketId);

      // Copy devices
      const leadDevices = db.prepare('SELECT * FROM lead_devices WHERE lead_id = ?').all(id) as any[];
      for (const d of leadDevices) {
        db.prepare(`
          INSERT INTO ticket_devices (ticket_id, device_name, service_id, price, tax_amount, total, additional_notes)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(ticketId, d.device_name, d.service_id, d.price || 0, d.tax || 0, (d.price || 0) + (d.tax || 0), d.problem);
      }

      // Recalc ticket totals
      const totals = db.prepare(`
        SELECT COALESCE(SUM(price), 0) as subtotal, COALESCE(SUM(tax_amount), 0) as total_tax, COALESCE(SUM(total), 0) as total
        FROM ticket_devices WHERE ticket_id = ?
      `).get(ticketId) as any;

      db.prepare('UPDATE tickets SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?')
        .run(totals.subtotal, totals.total_tax, totals.total, ticketId);

      // Update lead status
      db.prepare("UPDATE leads SET status = 'converted', updated_at = datetime('now') WHERE id = ?").run(id);

      return ticketId;
    });

    const ticketId = convertLead();
    const ticket = await adb.get<any>('SELECT * FROM tickets WHERE id = ?', ticketId);

    audit(db, 'lead_converted', req.user!.id, req.ip || 'unknown', { lead_id: id, ticket_id: ticketId });

    res.status(201).json({
      success: true,
      data: { ticket, message: 'Lead converted to ticket' },
    });
  }),
);

// ─── DELETE /leads/:id ─────────────────────────────────────────
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT id FROM leads WHERE id = ?', id);
    if (!existing) return res.status(404).json({ success: false, message: 'Lead not found' });

    await adb.run('DELETE FROM lead_devices WHERE lead_id = ?', id);
    await adb.run('DELETE FROM leads WHERE id = ?', id);

    audit(db, 'lead_deleted', req.user!.id, req.ip || 'unknown', { lead_id: id });

    res.json({ success: true, data: { message: 'Lead deleted' } });
  }),
);

export default router;
