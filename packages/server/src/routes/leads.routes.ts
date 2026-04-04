import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List leads (paginated, searchable)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
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

    const { total } = db.prepare(`SELECT COUNT(*) as total FROM leads l ${whereClause}`).get(...params) as { total: number };
    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const leads = db.prepare(`
      SELECT l.*,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM leads l
      LEFT JOIN users u ON u.id = l.assigned_to
      LEFT JOIN customers c ON c.id = l.customer_id
      ${whereClause}
      ORDER BY l.${safeSortBy} ${sortOrder}
      LIMIT ? OFFSET ?
    `).all(...params, pageSize, offset);

    res.json({
      success: true,
      data: {
        leads,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create lead
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const {
      customer_id, first_name, last_name, email, phone,
      zip_code, address, status, referred_by, assigned_to,
      source, notes, devices,
    } = req.body;

    if (!first_name) throw new AppError('first_name is required');

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
        assigned_to ?? null,
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
    const lead = db.prepare('SELECT * FROM leads WHERE id = ?').get(leadId);
    const leadDevices = db.prepare('SELECT * FROM lead_devices WHERE lead_id = ?').all(leadId);

    const leadData = { ...(lead as any), devices: leadDevices };
    broadcast(WS_EVENTS.LEAD_CREATED, leadData);
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

    const appointments = db.prepare(`
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
    `).all(...params);

    res.json({ success: true, data: appointments });
  }),
);

// ---------------------------------------------------------------------------
// POST /appointments – Create appointment
// ---------------------------------------------------------------------------
router.post(
  '/appointments',
  asyncHandler(async (req, res) => {
    const { lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes } = req.body;

    if (!start_time) throw new AppError('start_time is required');

    const result = db.prepare(`
      INSERT INTO appointments (lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      lead_id ?? null,
      customer_id ?? null,
      title ?? '',
      start_time,
      end_time ?? null,
      assigned_to ?? null,
      status ?? 'scheduled',
      notes ?? null,
    );

    const appointment = db.prepare('SELECT * FROM appointments WHERE id = ?').get(result.lastInsertRowid);
    res.status(201).json({ success: true, data: appointment });
  }),
);

// ---------------------------------------------------------------------------
// PUT /appointments/:id – Update appointment
// ---------------------------------------------------------------------------
router.put(
  '/appointments/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM appointments WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Appointment not found', 404);

    const { lead_id, customer_id, title, start_time, end_time, assigned_to, status, notes } = req.body;

    db.prepare(`
      UPDATE appointments SET
        lead_id = ?, customer_id = ?, title = ?, start_time = ?, end_time = ?,
        assigned_to = ?, status = ?, notes = ?, updated_at = datetime('now')
      WHERE id = ?
    `).run(
      lead_id !== undefined ? lead_id : existing.lead_id,
      customer_id !== undefined ? customer_id : existing.customer_id,
      title !== undefined ? title : existing.title,
      start_time !== undefined ? start_time : existing.start_time,
      end_time !== undefined ? end_time : existing.end_time,
      assigned_to !== undefined ? assigned_to : existing.assigned_to,
      status !== undefined ? status : existing.status,
      notes !== undefined ? notes : existing.notes,
      id,
    );

    const updated = db.prepare('SELECT * FROM appointments WHERE id = ?').get(id);
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /appointments/:id – Delete appointment
// ---------------------------------------------------------------------------
router.delete(
  '/appointments/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id FROM appointments WHERE id = ?').get(id);
    if (!existing) throw new AppError('Appointment not found', 404);

    db.prepare('DELETE FROM appointments WHERE id = ?').run(id);
    res.json({ success: true, data: { message: 'Appointment deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Lead detail
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);

    const lead = db.prepare(`
      SELECT l.*,
        u.first_name AS assigned_first_name, u.last_name AS assigned_last_name,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name
      FROM leads l
      LEFT JOIN users u ON u.id = l.assigned_to
      LEFT JOIN customers c ON c.id = l.customer_id
      WHERE l.id = ?
    `).get(id);

    if (!lead) throw new AppError('Lead not found', 404);

    const devices = db.prepare('SELECT * FROM lead_devices WHERE lead_id = ?').all(id);
    const appointments = db.prepare('SELECT * FROM appointments WHERE lead_id = ? ORDER BY start_time ASC').all(id);

    res.json({
      success: true,
      data: { ...(lead as any), devices, appointments },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update lead
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM leads WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Lead not found', 404);

    const {
      customer_id, first_name, last_name, email, phone,
      zip_code, address, status, referred_by, assigned_to,
      source, notes, devices,
    } = req.body;

    const updateLead = db.transaction(() => {
      db.prepare(`
        UPDATE leads SET
          customer_id = ?, first_name = ?, last_name = ?, email = ?, phone = ?,
          zip_code = ?, address = ?, status = ?, referred_by = ?, assigned_to = ?,
          source = ?, notes = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(
        customer_id !== undefined ? customer_id : existing.customer_id,
        first_name !== undefined ? first_name : existing.first_name,
        last_name !== undefined ? last_name : existing.last_name,
        email !== undefined ? email : existing.email,
        phone !== undefined ? phone : existing.phone,
        zip_code !== undefined ? zip_code : existing.zip_code,
        address !== undefined ? address : existing.address,
        status !== undefined ? status : existing.status,
        referred_by !== undefined ? referred_by : existing.referred_by,
        assigned_to !== undefined ? assigned_to : existing.assigned_to,
        source !== undefined ? source : existing.source,
        notes !== undefined ? notes : existing.notes,
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

    const lead = db.prepare('SELECT * FROM leads WHERE id = ?').get(id);
    const leadDevices = db.prepare('SELECT * FROM lead_devices WHERE lead_id = ?').all(id);

    res.json({
      success: true,
      data: { ...(lead as any), devices: leadDevices },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/convert – Convert lead to ticket
// ---------------------------------------------------------------------------
router.post(
  '/:id/convert',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const lead = db.prepare('SELECT * FROM leads WHERE id = ?').get(id) as any;
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
        `).run(ticketId, d.device_name, d.service_id, d.price, d.tax, d.price + d.tax, d.problem);
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
    const ticket = db.prepare('SELECT * FROM tickets WHERE id = ?').get(ticketId);

    audit('lead_converted', req.user!.id, req.ip || 'unknown', { lead_id: id, ticket_id: ticketId });

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
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id FROM leads WHERE id = ?').get(id) as any;
    if (!existing) return res.status(404).json({ success: false, message: 'Lead not found' });

    db.prepare('DELETE FROM lead_devices WHERE lead_id = ?').run(id);
    db.prepare('DELETE FROM leads WHERE id = ?').run(id);

    audit('lead_deleted', req.user!.id, req.ip || 'unknown', { lead_id: id });

    res.json({ success: true, data: { message: 'Lead deleted' } });
  }),
);

export default router;
