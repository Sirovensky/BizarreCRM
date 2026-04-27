import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { isCommissionLocked } from './_team.payroll.js';
import type { AsyncDb } from '../db/async-db.js';
import { trackInterval } from '../utils/trackInterval.js';
import { validateId } from '../utils/validate.js';

const router = Router();
const logger = createLogger('employees');

// ---------------------------------------------------------------------------
// EM5 — Auto-lunch-break deduction helper
// Policy: if a shift exceeds the configured threshold (default 6 hours), a
// paid or unpaid lunch break of configured minutes (default 30) is deducted
// from total hours. Configurable via store_config keys:
//   auto_lunch_enabled          -> '1' | '0' (default '0' — disabled)
//   auto_lunch_threshold_hours  -> positive number (default 6)
//   auto_lunch_deduct_minutes   -> positive integer (default 30)
// Returns the adjusted hours (rounded to 2dp). Pure function; no side effects.
// ---------------------------------------------------------------------------
interface LunchConfig {
  enabled: boolean;
  thresholdHours: number;
  deductMinutes: number;
}

function parseLunchConfig(rawEnabled: unknown, rawThreshold: unknown, rawDeduct: unknown): LunchConfig {
  const enabled = String(rawEnabled ?? '0') === '1';
  const thresholdHours = (() => {
    const n = Number(rawThreshold);
    return Number.isFinite(n) && n > 0 ? n : 6;
  })();
  const deductMinutes = (() => {
    const n = Number(rawDeduct);
    return Number.isFinite(n) && n >= 0 ? Math.round(n) : 30;
  })();
  return { enabled, thresholdHours, deductMinutes };
}

async function getLunchConfig(adb: AsyncDb): Promise<LunchConfig> {
  try {
    const rows = await adb.all<{ key: string; value: string }>(
      "SELECT key, value FROM store_config WHERE key IN ('auto_lunch_enabled', 'auto_lunch_threshold_hours', 'auto_lunch_deduct_minutes')"
    );
    const map = new Map(rows.map(r => [r.key, r.value]));
    return parseLunchConfig(
      map.get('auto_lunch_enabled'),
      map.get('auto_lunch_threshold_hours'),
      map.get('auto_lunch_deduct_minutes'),
    );
  } catch {
    // If store_config lookup fails, return disabled default (safest)
    return { enabled: false, thresholdHours: 6, deductMinutes: 30 };
  }
}

export function applyLunchDeduction(totalHours: number, cfg: LunchConfig): number {
  if (!cfg.enabled || totalHours <= cfg.thresholdHours) return totalHours;
  const deductionHours = cfg.deductMinutes / 60;
  const adjusted = totalHours - deductionHours;
  // Never let the deduction push hours below zero (defensive — shouldn't happen
  // given threshold > deduction in practice, but float math + user config).
  return Math.max(0, +adjusted.toFixed(2));
}

// ---------------------------------------------------------------------------
// EM3 — Payroll immutability guard
// Commissions and clock_entries are payroll records. Once a pay period has
// closed they MUST be immutable — late edits destroy the audit trail and
// create payroll-legal liability. This file intentionally does NOT expose
// UPDATE or DELETE routes for commissions/clock_entries. If any future route
// adds mutation, it MUST first call assertWithinCurrentPayPeriod() below to
// reject edits on closed periods.
//
// Pay period model: week starts Monday 00:00:00 local / UTC (use UTC here to
// avoid timezone drift). "Current pay period" = the week that contains now().
// Any timestamp from a prior week is considered closed.
// ---------------------------------------------------------------------------
export function isWithinCurrentPayPeriod(timestamp: string | Date, now: Date = new Date()): boolean {
  const ts = typeof timestamp === 'string' ? new Date(timestamp) : timestamp;
  if (!Number.isFinite(ts.getTime())) return false;

  // Start of current week (Monday 00:00 UTC)
  const startOfWeek = new Date(now);
  const dayOfWeek = startOfWeek.getUTCDay(); // 0=Sun, 1=Mon, ..., 6=Sat
  const daysBackToMonday = (dayOfWeek + 6) % 7;
  startOfWeek.setUTCHours(0, 0, 0, 0);
  startOfWeek.setUTCDate(startOfWeek.getUTCDate() - daysBackToMonday);

  return ts.getTime() >= startOfWeek.getTime();
}

export function assertWithinCurrentPayPeriod(timestamp: string | Date, fieldName = 'period_end'): void {
  if (!isWithinCurrentPayPeriod(timestamp)) {
    throw new AppError(
      `Payroll records are immutable once the pay period closes (${fieldName} is in a past pay period)`,
      403,
    );
  }
}

// ---------------------------------------------------------------------------
// EM4 — Auto-clock-out stale sessions
// Closes any clock_entries row that's been open longer than the staleness
// threshold (default 16 hours). Intended to be wired into the main cron in
// index.ts by the infra agent. Exported so the cron can invoke it; also safe
// to call manually. Returns the number of rows closed. Never throws — logs
// internal errors and returns 0 on failure.
// ---------------------------------------------------------------------------
const STALE_CLOCK_IN_HOURS = 16;

export async function autoClockOutStaleSessions(adb: AsyncDb, db: any): Promise<number> {
  try {
    const cutoff = new Date(Date.now() - STALE_CLOCK_IN_HOURS * 3600 * 1000).toISOString();
    const stale = await adb.all<{ id: number; user_id: number; clock_in: string }>(
      'SELECT id, user_id, clock_in FROM clock_entries WHERE clock_out IS NULL AND clock_in < ?',
      cutoff,
    );

    if (stale.length === 0) return 0;

    const cfg = await getLunchConfig(adb);
    const now = new Date();
    let closed = 0;

    for (const entry of stale) {
      const clockIn = new Date(entry.clock_in);
      const rawHours = +(((now.getTime() - clockIn.getTime()) / 3600000).toFixed(2));
      const adjustedHours = applyLunchDeduction(rawHours, cfg);
      try {
        // clock_entries has no dedicated 'status' column — tag the notes field
        // with an auto-close marker so a reviewer can filter later.
        await adb.run(
          "UPDATE clock_entries SET clock_out = ?, total_hours = ?, notes = COALESCE(notes, '') || ' [auto-closed]' WHERE id = ? AND clock_out IS NULL",
          now.toISOString(), adjustedHours, entry.id,
        );
        audit(db, 'employee_auto_clocked_out', null, 'system', {
          employee_id: entry.user_id,
          entry_id: entry.id,
          clock_in: entry.clock_in,
          total_hours: adjustedHours,
          raw_hours: rawHours,
          stale_after_hours: STALE_CLOCK_IN_HOURS,
        });
        closed++;
      } catch (err) {
        logger.error('Failed to auto-close clock entry', {
          entry_id: entry.id,
          error: err instanceof Error ? err.message : 'unknown',
        });
      }
    }

    if (closed > 0) {
      logger.info('Auto-closed stale clock entries', { count: closed, cutoff });
    }
    return closed;
  } catch (err) {
    logger.error('autoClockOutStaleSessions failed', {
      error: err instanceof Error ? err.message : 'unknown',
    });
    return 0;
  }
}

// ---------------------------------------------------------------------------
// GET / – List employees (active users, no password_hash)
// WEB-S6-033: include is_clocked_in + weekly_hours in the list response so
// EmployeeListPage doesn't fire a separate detail fetch per row (N+1).
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;

    // Week start (Monday 00:00 UTC) for weekly_hours calculation
    const now = new Date();
    const dayOfWeek = now.getUTCDay();
    const daysBackToMonday = (dayOfWeek + 6) % 7;
    const weekStart = new Date(now);
    weekStart.setUTCHours(0, 0, 0, 0);
    weekStart.setUTCDate(weekStart.getUTCDate() - daysBackToMonday);
    const weekStartIso = weekStart.toISOString();

    const employees = await adb.all(`
      SELECT u.id, u.username, u.email, u.first_name, u.last_name, u.role, u.avatar_url,
             u.is_active, u.pin IS NOT NULL AS has_pin, u.permissions, u.home_location_id,
             u.created_at, u.updated_at,
             CASE WHEN open.id IS NOT NULL THEN 1 ELSE 0 END AS is_clocked_in,
             COALESCE(wk.weekly_hours, 0) AS weekly_hours
      FROM users u
      LEFT JOIN (
        SELECT user_id, id FROM clock_entries
        WHERE clock_out IS NULL
        GROUP BY user_id HAVING MIN(id)
      ) open ON open.user_id = u.id
      LEFT JOIN (
        SELECT user_id, ROUND(SUM(total_hours), 2) AS weekly_hours
        FROM clock_entries
        WHERE clock_in >= ? AND clock_out IS NOT NULL
        GROUP BY user_id
      ) wk ON wk.user_id = u.id
      WHERE u.is_active = 1
      ORDER BY u.first_name, u.last_name
    `, weekStartIso);

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
    const adb = req.asyncDb;
    const employees = await adb.all(`
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
    `);

    res.json({ success: true, data: employees });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Employee detail with recent clock entries and commissions
// POST-ENRICH §28 FIX: previously returned clock_entries + commissions for
// ANY authenticated user. Self-service visibility rule — only admin or self
// may view private payroll data. Non-self callers get the public profile
// without the private arrays.
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');

    const employee = await adb.get<any>(`
      SELECT id, username, email, first_name, last_name, role, avatar_url,
             is_active, pin IS NOT NULL AS has_pin, permissions, home_location_id,
             pay_rate, created_at, updated_at
      FROM users WHERE id = ?
    `, id);

    if (!employee) throw new AppError('Employee not found', 404);

    const isPrivileged = req.user?.role === 'admin' || req.user?.id === id;

    // Non-privileged callers get the public employee profile only. Private
    // payroll arrays (clock entries + commissions) are withheld.
    if (!isPrivileged) {
      res.json({ success: true, data: employee });
      return;
    }

    // Recent clock entries (last 30), commissions (last 30), current clock status — independent
    const [clockEntries, commissions, openEntry] = await Promise.all([
      adb.all(`
        SELECT * FROM clock_entries WHERE user_id = ? ORDER BY clock_in DESC LIMIT 30
      `, id),
      adb.all(`
        SELECT c.*, t.order_id AS ticket_order_id
        FROM commissions c
        LEFT JOIN tickets t ON t.id = c.ticket_id
        WHERE c.user_id = ?
        ORDER BY c.created_at DESC LIMIT 30
      `, id),
      adb.get(`
        SELECT * FROM clock_entries WHERE user_id = ? AND clock_out IS NULL ORDER BY clock_in DESC LIMIT 1
      `, id),
    ]);

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
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const { pin, location_id: rawLocationId } = req.body;

    // Only allow clocking in yourself unless admin
    if (req.user?.role !== 'admin' && req.user?.id !== id) {
      throw new AppError('Can only clock yourself in', 403);
    }

    const user = await adb.get<any>('SELECT id, pin, home_location_id FROM users WHERE id = ? AND is_active = 1', id);
    if (!user) throw new AppError('Employee not found', 404);

    // Verify PIN if set — ALWAYS use bcrypt, reject unhashed PINs
    // SCAN-1182: sibling gap of `/auth/verify-pin` which IS rate-limited.
    // Without a cap an admin (or hijacked admin session) could brute-force
    // any employee's 4-digit PIN here — 10k-space is small. 5 attempts per
    // 15 min per (targetUserId, ip) matches the /verify-pin cap.
    if (user.pin) {
      if (!user.pin.startsWith('$2')) {
        throw new AppError('PIN is not properly hashed — contact admin', 500);
      }
      const clockRateKey = `${id}:${req.ip || 'unknown'}`;
      if (!checkWindowRate(req.db, 'clock_pin', clockRateKey, 5, 900_000)) {
        throw new AppError('Too many PIN attempts for this employee. Try again in 15 min.', 429);
      }
      if (!bcrypt.compareSync(pin || '', user.pin)) {
        recordWindowFailure(req.db, 'clock_pin', clockRateKey, 900_000);
        throw new AppError('Invalid PIN', 401);
      }
    }

    // Check not already clocked in.
    // POST-ENRICH §28 EM4: before blocking, auto-close any stale session for
    // THIS user that's already older than the staleness threshold. This fixes
    // the common "can't clock in because a forgotten shift from yesterday is
    // still open" failure mode without waiting for the background cron.
    const staleCutoff = new Date(Date.now() - STALE_CLOCK_IN_HOURS * 3600 * 1000).toISOString();
    const staleForUser = await adb.get<{ id: number; clock_in: string }>(
      'SELECT id, clock_in FROM clock_entries WHERE user_id = ? AND clock_out IS NULL AND clock_in < ? ORDER BY clock_in DESC LIMIT 1',
      id, staleCutoff,
    );
    if (staleForUser) {
      const clockInDate = new Date(staleForUser.clock_in);
      const rawHours = +(((Date.now() - clockInDate.getTime()) / 3600000).toFixed(2));
      const cfg = await getLunchConfig(adb);
      const adjustedHours = applyLunchDeduction(rawHours, cfg);
      const autoCloseTs = new Date().toISOString();
      await adb.run(
        "UPDATE clock_entries SET clock_out = ?, total_hours = ?, notes = COALESCE(notes, '') || ' [auto-closed on clock-in]' WHERE id = ? AND clock_out IS NULL",
        autoCloseTs, adjustedHours, staleForUser.id,
      );
      audit(req.db, 'employee_auto_clocked_out', req.user!.id, req.ip || 'unknown', {
        employee_id: id,
        entry_id: staleForUser.id,
        total_hours: adjustedHours,
        raw_hours: rawHours,
        trigger: 'clock_in',
      });
    }

    const openEntry = await adb.get(
      'SELECT id FROM clock_entries WHERE user_id = ? AND clock_out IS NULL', id
    );
    if (openEntry) throw new AppError('Already clocked in', 400);

    const now = new Date().toISOString();

    // Payroll period lock — refuse to create a clock entry whose timestamp
    // falls inside a locked period (criticalaudit.md §53).
    if (await isCommissionLocked(adb, now)) {
      throw new AppError('Payroll period is locked', 403);
    }

    // Resolve location_id: validate if provided, else fall back to user's home_location_id, then 1.
    let resolvedLocationId: number = user.home_location_id ?? 1;
    if (rawLocationId !== undefined && rawLocationId !== null) {
      const parsed = Number(rawLocationId);
      if (!Number.isInteger(parsed) || parsed < 1) {
        throw new AppError('location_id must be a positive integer', 400);
      }
      const loc = await adb.get<{ id: number }>('SELECT id FROM locations WHERE id = ? AND is_active = 1', parsed);
      if (!loc) throw new AppError('Location not found or inactive', 400);
      resolvedLocationId = parsed;
    }

    const result = await adb.run(
      'INSERT INTO clock_entries (user_id, clock_in, location_id) VALUES (?, ?, ?)', id, now, resolvedLocationId
    );

    const entry = await adb.get('SELECT * FROM clock_entries WHERE id = ?', result.lastInsertRowid);
    audit(req.db, 'employee_clocked_in', req.user!.id, req.ip || 'unknown', { employee_id: id, entry_id: Number(result.lastInsertRowid) });

    res.status(201).json({ success: true, data: entry });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/clock-out – Clock out (verify PIN, calculate hours)
// ---------------------------------------------------------------------------
router.post(
  '/:id/clock-out',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const { pin, notes } = req.body;

    if (req.user?.role !== 'admin' && req.user?.id !== id) {
      throw new AppError('Can only clock yourself out', 403);
    }

    const user = await adb.get<any>('SELECT id, pin FROM users WHERE id = ? AND is_active = 1', id);
    if (!user) throw new AppError('Employee not found', 404);

    // Verify PIN if set — ALWAYS use bcrypt, reject unhashed PINs
    // SCAN-1182: same cap as clock-in.
    if (user.pin) {
      if (!user.pin.startsWith('$2')) {
        throw new AppError('PIN is not properly hashed — contact admin', 500);
      }
      const clockRateKey = `${id}:${req.ip || 'unknown'}`;
      if (!checkWindowRate(req.db, 'clock_pin', clockRateKey, 5, 900_000)) {
        throw new AppError('Too many PIN attempts for this employee. Try again in 15 min.', 429);
      }
      if (!bcrypt.compareSync(pin || '', user.pin)) {
        recordWindowFailure(req.db, 'clock_pin', clockRateKey, 900_000);
        throw new AppError('Invalid PIN', 401);
      }
    }

    const openEntry = await adb.get<any>(
      'SELECT * FROM clock_entries WHERE user_id = ? AND clock_out IS NULL ORDER BY clock_in DESC LIMIT 1', id
    );
    if (!openEntry) throw new AppError('Not clocked in', 400);

    const now = new Date();
    const clockIn = new Date(openEntry.clock_in);
    const nowIso = now.toISOString();

    // Payroll period lock — refuse to close a clock entry whose clock_in or
    // clock_out timestamp falls inside a locked period (criticalaudit.md §53).
    if (
      (await isCommissionLocked(adb, openEntry.clock_in)) ||
      (await isCommissionLocked(adb, nowIso))
    ) {
      throw new AppError('Payroll period is locked', 403);
    }

    // EM5: Raw hours from UTC math (timezone-agnostic — a duration has no tz).
    const rawHours = +(((now.getTime() - clockIn.getTime()) / 3600000).toFixed(2));
    // EM5: Apply auto-lunch-break deduction if configured for this store.
    const lunchCfg = await getLunchConfig(adb);
    const totalHours = applyLunchDeduction(rawHours, lunchCfg);

    await adb.run(
      'UPDATE clock_entries SET clock_out = ?, total_hours = ?, notes = ? WHERE id = ?',
      nowIso, totalHours, notes ?? openEntry.notes, openEntry.id
    );

    const entry = await adb.get('SELECT * FROM clock_entries WHERE id = ?', openEntry.id);
    audit(req.db, 'employee_clocked_out', req.user!.id, req.ip || 'unknown', {
      employee_id: id,
      entry_id: openEntry.id,
      total_hours: totalHours,
      raw_hours: rawHours,
      lunch_deducted: lunchCfg.enabled && rawHours > lunchCfg.thresholdHours,
    });

    res.json({ success: true, data: entry });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/hours – Hours log with date range filter
// AUTH: admin-only, or self (employee reading their own hours)
// Fix A2: previously any authenticated user could read anyone's hours.
// ---------------------------------------------------------------------------
router.get(
  '/:id/hours',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();

    if (req.user?.role !== 'admin' && req.user?.id !== id) {
      throw new AppError('Forbidden — can only view your own hours', 403);
    }

    const user = await adb.get('SELECT id FROM users WHERE id = ?', id);
    if (!user) throw new AppError('Employee not found', 404);

    const conditions: string[] = ['user_id = ?'];
    const params: unknown[] = [id];

    if (fromDate) {
      conditions.push('clock_in >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      // POST-ENRICH §28: date-only inputs (e.g. 2026-04-11) previously excluded
      // the entire day because clock_in stores full timestamps. Pad the upper
      // bound to 23:59:59 when the input looks like a bare date.
      conditions.push('clock_in <= ?');
      params.push(/^\d{4}-\d{2}-\d{2}$/.test(toDate) ? `${toDate} 23:59:59` : toDate);
    }

    const [entries, { total_hours }] = await Promise.all([
      adb.all(`
        SELECT * FROM clock_entries
        WHERE ${conditions.join(' AND ')}
        ORDER BY clock_in DESC
      `, ...params),
      adb.get<{ total_hours: number }>(`
        SELECT COALESCE(SUM(total_hours), 0) as total_hours FROM clock_entries
        WHERE ${conditions.join(' AND ')}
      `, ...params) as Promise<{ total_hours: number }>,
    ]);

    res.json({
      success: true,
      data: { entries, total_hours },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/commissions – Commissions with date range filter
// AUTH: admin-only, or self. Fix A2: commissions are private payroll data.
// ---------------------------------------------------------------------------
router.get(
  '/:id/commissions',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();

    if (req.user?.role !== 'admin' && req.user?.id !== id) {
      throw new AppError('Forbidden — can only view your own commissions', 403);
    }

    const user = await adb.get('SELECT id FROM users WHERE id = ?', id);
    if (!user) throw new AppError('Employee not found', 404);

    const conditions: string[] = ['c.user_id = ?'];
    const params: unknown[] = [id];

    if (fromDate) {
      conditions.push('c.created_at >= ?');
      params.push(fromDate);
    }
    if (toDate) {
      // POST-ENRICH §28: same date-only boundary bug as the hours endpoint.
      conditions.push('c.created_at <= ?');
      params.push(/^\d{4}-\d{2}-\d{2}$/.test(toDate) ? `${toDate} 23:59:59` : toDate);
    }

    const [commissions, { total_amount }] = await Promise.all([
      adb.all(`
        SELECT c.*, t.order_id AS ticket_order_id, i.order_id AS invoice_order_id
        FROM commissions c
        LEFT JOIN tickets t ON t.id = c.ticket_id
        LEFT JOIN invoices i ON i.id = c.invoice_id
        WHERE ${conditions.join(' AND ')}
        ORDER BY c.created_at DESC
      `, ...params),
      adb.get<{ total_amount: number }>(`
        SELECT COALESCE(SUM(amount), 0) as total_amount FROM commissions c
        WHERE ${conditions.join(' AND ')}
      `, ...params) as Promise<{ total_amount: number }>,
    ]);

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
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const fromDate = (req.query.from_date as string || '').trim();
    const toDate = (req.query.to_date as string || '').trim();

    const user = await adb.get<any>('SELECT id, first_name, last_name FROM users WHERE id = ?', id);
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

    // Tickets, avg repair time, device stats — all independent
    const [ticketStats, avgRepairTime, deviceStats] = await Promise.all([
      adb.get<any>(`
        SELECT
          COUNT(*) AS total_tickets,
          COUNT(CASE WHEN ts.is_closed = 1 THEN 1 END) AS closed_tickets,
          COALESCE(SUM(t.total), 0) AS total_revenue,
          COALESCE(AVG(t.total), 0) AS avg_ticket_value
        FROM tickets t
        LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.assigned_to = ? AND t.is_deleted = 0 ${dateCondition}
      `, id, ...dateParams),
      adb.get<any>(`
        SELECT AVG(
          (julianday(t.updated_at) - julianday(t.created_at)) * 24
        ) AS avg_hours
        FROM tickets t
        LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.assigned_to = ? AND t.is_deleted = 0 AND ts.is_closed = 1 ${dateCondition}
      `, id, ...dateParams),
      adb.get<any>(`
        SELECT COUNT(*) AS total_devices
        FROM ticket_devices td
        JOIN tickets t ON t.id = td.ticket_id
        WHERE td.assigned_to = ? AND t.is_deleted = 0 ${dateCondition}
      `, id, ...dateParams),
    ]);

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

// ---------------------------------------------------------------------------
// PATCH /:id – Update employee pay_rate (admin-only)
// WEB-S6-014: Admin can set/clear an employee's hourly pay rate without
// going through settings/users. Intentionally scoped to pay_rate only so
// this route never overlaps with the settings.routes.ts user-edit handler.
// ---------------------------------------------------------------------------
router.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');

    if (req.user?.role !== 'admin') {
      throw new AppError('Admin only', 403);
    }

    const { pay_rate } = req.body;

    // Allow explicit null to clear the rate; reject any non-numeric non-null value.
    let resolvedRate: number | null = null;
    if (pay_rate !== undefined && pay_rate !== null && pay_rate !== '') {
      const n = Number(pay_rate);
      if (!Number.isFinite(n) || n < 0 || n > 9999.99) {
        throw new AppError('pay_rate must be a non-negative number ≤ 9999.99', 400);
      }
      resolvedRate = +n.toFixed(2);
    }

    const employee = await adb.get<any>('SELECT id FROM users WHERE id = ? AND is_active = 1', id);
    if (!employee) throw new AppError('Employee not found', 404);

    await adb.run(
      "UPDATE users SET pay_rate = ?, updated_at = datetime('now') WHERE id = ?",
      resolvedRate,
      id,
    );

    audit(req.db, 'employee_pay_rate_updated', req.user!.id, req.ip || 'unknown', {
      employee_id: id,
      pay_rate: resolvedRate,
    });

    const updated = await adb.get<any>(
      'SELECT id, username, email, first_name, last_name, role, is_active, pay_rate FROM users WHERE id = ?',
      id,
    );
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// POST-ENRICH §28 EM4 — Self-installing hourly sweep for stale clock entries
//
// In single-tenant installs this lazily enumerates the default DB once per
// hour and closes any clock entry older than STALE_CLOCK_IN_HOURS. Multi-
// tenant installs should still wire autoClockOutStaleSessions() into
// index.ts (via forEachDbAsync) for per-tenant coverage — this module-local
// interval is a safety net, not a replacement.
//
// The interval is registered on import and cleared automatically via the
// process exit hook so it never outlives the server process. Failures are
// logged and swallowed — this must never crash the HTTP layer.
// ---------------------------------------------------------------------------
const AUTO_CLOCKOUT_SWEEP_INTERVAL_MS = 60 * 60 * 1000; // 1 hour

let autoClockoutSweepTimer: ReturnType<typeof setInterval> | null = null;

function startAutoClockoutSweep(): void {
  if (autoClockoutSweepTimer) return;
  // Defer first tick — don't try to read config.dbPath at module-load time
  // because the config module may not be fully initialized yet when route
  // files are first imported. A 5-minute delay is plenty.
  const firstTickDelay = 5 * 60 * 1000;
  setTimeout(() => {
    autoClockoutSweepTimer = trackInterval(async () => {
      // SEC-H19: prior version only read config.dbPath which in
      // multi-tenant mode points at the master DB, not any tenant.
      // Every tenant's employee_clock_entries therefore stayed open
      // forever (the sweep ran against a table that doesn't have
      // the row in the right file). forEachDbAsync walks the pool
      // correctly and creates an AsyncDb wrapper per tenant.
      try {
        const { config } = await import('../config.js');
        const { createAsyncDb } = await import('../db/async-db.js');
        if (config.multiTenant) {
          const { getMasterDb } = await import('../db/master-connection.js');
          const { getTenantDb, releaseTenantDb } = await import('../db/tenant-pool.js');
          const masterDb = getMasterDb();
          if (!masterDb) return;
          const tenants = masterDb
            .prepare("SELECT slug FROM tenants WHERE status = 'active'")
            .all() as { slug: string }[];
          for (const t of tenants) {
            let pooled: import('better-sqlite3').Database | undefined;
            try {
              pooled = await getTenantDb(t.slug);
              const tenantAdb = createAsyncDb(pooled.name);
              const closed = await autoClockOutStaleSessions(tenantAdb, pooled);
              if (closed > 0) {
                logger.info('Auto-clockout sweep closed stale entries', { tenant: t.slug, count: closed });
              }
            } catch (err) {
              logger.error('Auto-clockout sweep per-tenant error', {
                tenant: t.slug,
                error: err instanceof Error ? err.message : 'unknown',
              });
            } finally {
              if (pooled !== undefined) releaseTenantDb(t.slug);
            }
          }
        } else {
          const { db: sweepDb } = await import('../db/connection.js');
          const sweepAdb = createAsyncDb(config.dbPath);
          const closed = await autoClockOutStaleSessions(sweepAdb, sweepDb);
          if (closed > 0) {
            logger.info('Auto-clockout sweep closed stale entries', { count: closed });
          }
        }
      } catch (err) {
        logger.error('Auto-clockout sweep tick failed', {
          error: err instanceof Error ? err.message : 'unknown',
        });
      }
    }, AUTO_CLOCKOUT_SWEEP_INTERVAL_MS);
  }, firstTickDelay);
}

// Gate the sweep behind an env var so unit tests don't start background work.
if (process.env.NODE_ENV !== 'test') {
  startAutoClockoutSweep();
}

export default router;
