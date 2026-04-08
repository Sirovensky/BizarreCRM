import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List employees (active users, no password_hash)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const employees = db.prepare(`
      SELECT id, username, email, first_name, last_name, role, avatar_url,
             is_active, pin IS NOT NULL AS has_pin, permissions, created_at, updated_at
      FROM users
      WHERE is_active = 1
      ORDER BY first_name, last_name
    `).all();

    res.json({ success: true, data: employees });
  }),
);

// ---------------------------------------------------------------------------
// GET /performance/all – All employees performance summary
// (Must be before /:id to avoid route conflict)
// ---------------------------------------------------------------------------
router.get(
  '/performance/all',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const employees = db.prepare(`
      SELECT u.id, u.first_name, u.last_name, u.role,
             COUNT(DISTINCT t.id) AS total_tickets,
             COUNT(DISTINCT CASE WHEN ts.is_closed = 1 THEN t.id END) AS closed_tickets,
             COALESCE(SUM(t.total), 0) AS total_revenue,
             COALESCE(AVG(t.total), 0) AS avg_ticket_value,
             AVG(CASE WHEN ts.is_closed = 1 THEN (julianday(t.updated_at) - julianday(t.created_at)) * 24 END) AS avg_repair_hours
      FROM users u
      LEFT JOIN tickets t ON t.assigned_to = u.id AND t.is_deleted = 0
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE u.is_active = 1
      GROUP BY u.id
      ORDER BY total_tickets DESC
    `).all();

    res.json({ success: true, data: employees });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Employee detail with recent clock entries and commissions
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);

    const employee = db.prepare(`
      SELECT id, username, email, first_name, last_name, role, avatar_url,
             is_active, pin IS NOT NULL AS has_pin, permissions, created_at, updated_at
      FROM users WHERE id = ?
    `).get(id) as any;

    if (!employee) throw new AppError('Employee not found', 404);

    // Recent clock entries (last 30)
    const clockEntries = db.prepare(`
      SELECT * FROM clock_entries WHERE user_id = ? ORDER BY clock_in DESC LIMIT 30
    `).all(id);

    // Recent commissions (last 30)
    const commissions = db.prepare(`
      SELECT c.*, t.order_id AS ticket_order_id
      FROM commissions c
      LEFT JOIN tickets t ON t.id = c.ticket_id
      WHERE c.user_id = ?
      ORDER BY c.created_at DESC LIMIT 30
    `).all(id);

    // Current clock status
    const openEntry = db.prepare(`
      SELECT * FROM clock_entries WHERE user_id = ? AND clock_out IS NULL ORDER BY clock_in DESC LIMIT 1
    `).get(id);

    res.json({
      success: true,
      data: {
        ...employee,
        clock_entries: clockEntries,
        commissions,
        is_clocked_in: !!openEntry,
        current_clock_entry: openEntry ?? null,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/clock-in – Clock in (verify PIN)
// ---------------------------------------------------------------------------
router.post(
  '/:id/clock-in',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const { pin } = req.body;

    // Only allow clocking in yourself unless admin
    if (req.user?.role !== 'admin' && req.user?.id !== id) {
      throw new AppError('Can only clock yourself in', 403);
    }

    const user = db.prepare('SELECT id, pin FROM users WHERE id = ? AND is_active = 1').get(id) as any;
    if (!user) throw new AppError('Employee not found', 404);

    // Verify PIN if set — ALWAYS use bcrypt, reject unhashed PINs
    if (user.pin) {
      if (!user.pin.startsWith('$2')) {
        throw new AppError('PIN is not properly hashed — contact admin', 500);
      }
      if (!bcrypt.compareSync(pin || '', user.pin)) {
        throw new AppError('Invalid PIN', 401);
      }
    }

    // Check not already clocked in
    const openEntry = db.prepare(
      'SELECT id FROM clock_entries WHERE user_id = ? AND clock_out IS NULL'
    ).get(id);
    if (openEntry) throw new AppError('Already clocked in', 400);

    const now = new Date().toISOString();
    const result = db.prepare(
      'INSERT INTO clock_entries (user_id, clock_in) VALUES (?, ?)'
    ).run(id, now);

    const entry = db.prepare('SELECT * FROM clock_entries WHERE id = ?').get(result.lastInsertRowid);

    res.status(201).json({ success: true, data: entry });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/clock-out – Clock out (verify PIN, calculate hours)
// ---------------------------------------------------------------------------
router.post(
  '/:id/clock-out',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const { pin, notes } = req.body;

    if (req.user?.role !== 'admin' && req.user?.id !== id) {
      throw new AppError('Can only clock yourself out', 403);
    }

    const user = db.prepare('SELECT id, pin FROM users WHERE id = ? AND is_active = 1').get(id) as any;
    if (!user) throw new AppError('Employee not found', 404);

    // Verify PIN if set — ALWAYS use bcrypt, reject unhashed PINs
    if (user.pin) {
      if (!user.pin.startsWith('$2')) {
        throw new AppError('PIN is not properly hashed — contact admin', 500);
      }
      if (!bcrypt.compareSync(pin || '', user.pin)) {
        throw new AppError('Invalid PIN', 401);
      }
    }

    const openEntry = db.prepare(
      'SELECT * FROM clock_entries WHERE user_id = ? AND clock_out IS NULL ORDER BY clock_in DESC LIMIT 1'
    ).get(id) as any;
    if (!openEntry) throw new AppError('Not clocked in', 400);

    const now = new Date();
    const clockIn = new Date(openEntry.clock_in);
    const totalHours = +(((now.getTime() - clockIn.getTime()) / 3600000).toFixed(2));

    db.prepare(
      'UPDATE clock_entries SET clock_out = ?, total_hours = ?, notes = ? WHERE id = ?'
    ).run(now.toISOString(), totalHours, notes ?? openEntry.notes, openEntry.id);

    const entry = db.prepare('SELECT * FROM clock_entries WHERE id = ?').get(openEntry.id);

    res.json({ success: true, data: entry });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/hours – Hours log with date range filter
// ---------------------------------------------------------------------------
router.get(
  '/:id/hours',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();

    const user = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
    if (!user) throw new AppError('Employee not found', 404);

    const conditions: string[] = ['user_id = ?'];
    const params: unknown[] = [id];

    if (fromDate) {
      conditions.push('clock_in >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      conditions.push('clock_in <= ?');
      params.push(toDate);
    }

    const entries = db.prepare(`
      SELECT * FROM clock_entries
      WHERE ${conditions.join(' AND ')}
      ORDER BY clock_in DESC
    `).all(...params);

    const { total_hours } = db.prepare(`
      SELECT COALESCE(SUM(total_hours), 0) as total_hours FROM clock_entries
      WHERE ${conditions.join(' AND ')}
    `).get(...params) as { total_hours: number };

    res.json({
      success: true,
      data: { entries, total_hours },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/commissions – Commissions with date range filter
// ---------------------------------------------------------------------------
router.get(
  '/:id/commissions',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();

    const user = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
    if (!user) throw new AppError('Employee not found', 404);

    const conditions: string[] = ['c.user_id = ?'];
    const params: unknown[] = [id];

    if (fromDate) {
      conditions.push('c.created_at >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      conditions.push('c.created_at <= ?');
      params.push(toDate);
    }

    const commissions = db.prepare(`
      SELECT c.*, t.order_id AS ticket_order_id, i.order_id AS invoice_order_id
      FROM commissions c
      LEFT JOIN tickets t ON t.id = c.ticket_id
      LEFT JOIN invoices i ON i.id = c.invoice_id
      WHERE ${conditions.join(' AND ')}
      ORDER BY c.created_at DESC
    `).all(...params);

    const { total_amount } = db.prepare(`
      SELECT COALESCE(SUM(amount), 0) as total_amount FROM commissions c
      WHERE ${conditions.join(' AND ')}
    `).get(...params) as { total_amount: number };

    res.json({
      success: true,
      data: { commissions, total_amount },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/performance – Performance metrics (avg repair time, ticket count, revenue)
// ---------------------------------------------------------------------------
router.get(
  '/:id/performance',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();

    const user = db.prepare('SELECT id, first_name, last_name FROM users WHERE id = ?').get(id) as any;
    if (!user) throw new AppError('Employee not found', 404);

    // SECURITY: Use parameterized queries — NEVER interpolate user input into SQL
    const dateCondition = fromDate && toDate
      ? 'AND t.created_at BETWEEN ? AND ?'
      : fromDate ? 'AND t.created_at >= ?'
      : toDate ? 'AND t.created_at <= ?'
      : '';
    const dateParams: string[] = fromDate && toDate
      ? [fromDate, `${toDate} 23:59:59`]
      : fromDate ? [fromDate]
      : toDate ? [`${toDate} 23:59:59`]
      : [];

    // Tickets assigned to this tech
    const ticketStats = db.prepare(`
      SELECT
        COUNT(*) AS total_tickets,
        COUNT(CASE WHEN ts.is_closed = 1 THEN 1 END) AS closed_tickets,
        COALESCE(SUM(t.total), 0) AS total_revenue,
        COALESCE(AVG(t.total), 0) AS avg_ticket_value
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.assigned_to = ? AND t.is_deleted = 0 ${dateCondition}
    `).get(id, ...dateParams) as any;

    // Average repair time (creation to close, in hours) for closed tickets
    const avgRepairTime = db.prepare(`
      SELECT AVG(
        (julianday(t.updated_at) - julianday(t.created_at)) * 24
      ) AS avg_hours
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.assigned_to = ? AND t.is_deleted = 0 AND ts.is_closed = 1 ${dateCondition}
    `).get(id, ...dateParams) as any;

    // Device-level stats (from ticket_devices)
    const deviceStats = db.prepare(`
      SELECT COUNT(*) AS total_devices
      FROM ticket_devices td
      JOIN tickets t ON t.id = td.ticket_id
      WHERE td.assigned_to = ? AND t.is_deleted = 0 ${dateCondition}
    `).get(id, ...dateParams) as any;

    res.json({
      success: true,
      data: {
        employee: { id: user.id, first_name: user.first_name, last_name: user.last_name },
        total_tickets: ticketStats.total_tickets,
        closed_tickets: ticketStats.closed_tickets,
        total_revenue: +Number(ticketStats.total_revenue).toFixed(2),
        avg_ticket_value: +Number(ticketStats.avg_ticket_value).toFixed(2),
        avg_repair_hours: avgRepairTime.avg_hours ? +Number(avgRepairTime.avg_hours).toFixed(1) : null,
        total_devices_repaired: deviceStats.total_devices,
      },
    });
  }),
);

export default router;
