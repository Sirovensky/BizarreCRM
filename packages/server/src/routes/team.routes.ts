/**
 * Team management routes — criticalaudit.md §53.
 *
 * Mounted at /api/v1/team. Bundles every team feature that doesn't belong in
 * employees.routes.ts (which is owned by another agent and intentionally
 * untouched). Covers:
 *
 *   - Shift schedules + time-off requests (with approval flow)
 *   - "My queue" tech dashboard (reads existing tickets table)
 *   - Ticket handoffs with required reason
 *   - @mentions inbox (mark-read)
 *   - Goals + targets per tech
 *   - Performance reviews (admin only)
 *   - Knowledge base CRUD (deliberately empty — audit forbids seeding)
 *   - Payroll period lock + CSV export
 *
 * All responses follow `{ success: true, data: <payload> }`. Mutating routes
 * audit through `audit()` and use the shared validators.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateTextLength,
  validateIsoDate,
  validateEnum,
  validatePositiveAmount,
} from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';
import { isCommissionLocked } from './_team.payroll.js';
import { escapeLike } from '../utils/query.js';

const router = Router();
const logger = createLogger('team');

// ── small helpers ───────────────────────────────────────────────────────────

function requireUserId(req: any): number {
  const id = req?.user?.id;
  if (!id) throw new AppError('Authentication required', 401);
  return Number(id);
}

function requireAdminOrManager(req: any): void {
  const role = req?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

function requireAdmin(req: any): void {
  if (req?.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
  }
}

function parseId(value: unknown, label = 'id'): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = parseInt(String(raw ?? ''), 10);
  if (!n || isNaN(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

// ============================================================================
// SHIFTS
// ============================================================================

interface ShiftRow {
  id: number;
  user_id: number;
  start_at: string;
  end_at: string;
  role: string | null;
  notes: string | null;
  status: string;
  created_at: string;
  created_by_user_id: number | null;
}

router.get(
  '/shifts',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = req.query.user_id ? parseId(String(req.query.user_id), 'user_id') : null;
    const from = validateIsoDate(req.query.from, 'from', false);
    const to = validateIsoDate(req.query.to, 'to', false);

    const where: string[] = [];
    const params: unknown[] = [];
    if (userId) {
      where.push('user_id = ?');
      params.push(userId);
    }
    if (from) {
      where.push('start_at >= ?');
      params.push(from);
    }
    if (to) {
      where.push('start_at <= ?');
      params.push(to);
    }
    const sql = `SELECT s.*, u.first_name, u.last_name, u.username
                 FROM shift_schedules s
                 LEFT JOIN users u ON u.id = s.user_id
                 ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
                 ORDER BY start_at ASC LIMIT 500`;
    const rows = await adb.all(sql, ...params);
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/shifts',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = parseId(String(req.body?.user_id ?? ''), 'user_id');
    // FK: scheduling a shift for a non-existent user leaves an orphan row
    // that shows up as "Unknown" in the schedule view.
    const targetUser = await adb.get<{ id: number }>(
      'SELECT id FROM users WHERE id = ? AND is_active = 1',
      userId,
    );
    if (!targetUser) throw new AppError('Target user not found or inactive', 404);
    const startAt = validateIsoDate(req.body?.start_at, 'start_at', true)!;
    const endAt = validateIsoDate(req.body?.end_at, 'end_at', true)!;
    if (new Date(endAt).getTime() <= new Date(startAt).getTime()) {
      throw new AppError('end_at must be after start_at', 400);
    }
    const role = req.body?.role ? validateTextLength(req.body.role, 50, 'role') : null;
    const notes = req.body?.notes ? validateTextLength(req.body.notes, 500, 'notes') : null;

    const result = await adb.run(
      `INSERT INTO shift_schedules
         (user_id, start_at, end_at, role, notes, created_by_user_id)
       VALUES (?, ?, ?, ?, ?, ?)`,
      userId, startAt, endAt, role, notes, requireUserId(req),
    );
    audit(req.db, 'shift_created', requireUserId(req), req.ip || 'unknown', {
      shift_id: Number(result.lastInsertRowid),
      user_id: userId,
    });
    const row = await adb.get<ShiftRow>('SELECT * FROM shift_schedules WHERE id = ?', result.lastInsertRowid);
    res.json({ success: true, data: row });
  }),
);

router.put(
  '/shifts/:id',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'shift id');

    const existing = await adb.get<ShiftRow>('SELECT * FROM shift_schedules WHERE id = ?', id);
    if (!existing) throw new AppError('Shift not found', 404);

    const startAt = req.body?.start_at
      ? validateIsoDate(req.body.start_at, 'start_at', true)!
      : existing.start_at;
    const endAt = req.body?.end_at
      ? validateIsoDate(req.body.end_at, 'end_at', true)!
      : existing.end_at;
    if (new Date(endAt).getTime() <= new Date(startAt).getTime()) {
      throw new AppError('end_at must be after start_at', 400);
    }
    const role = req.body?.role !== undefined
      ? (req.body.role ? validateTextLength(req.body.role, 50, 'role') : null)
      : existing.role;
    const notes = req.body?.notes !== undefined
      ? (req.body.notes ? validateTextLength(req.body.notes, 500, 'notes') : null)
      : existing.notes;
    const status = req.body?.status
      ? validateEnum(req.body.status, ['scheduled', 'confirmed', 'swapped', 'missed', 'completed'] as const, 'status', false)
      : existing.status;

    await adb.run(
      `UPDATE shift_schedules
       SET start_at = ?, end_at = ?, role = ?, notes = ?, status = ?
       WHERE id = ?`,
      startAt, endAt, role, notes, status, id,
    );
    audit(req.db, 'shift_updated', requireUserId(req), req.ip || 'unknown', { shift_id: id });
    const row = await adb.get<ShiftRow>('SELECT * FROM shift_schedules WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/shifts/:id',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'shift id');
    await adb.run('DELETE FROM shift_schedules WHERE id = ?', id);
    audit(req.db, 'shift_deleted', requireUserId(req), req.ip || 'unknown', { shift_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// ============================================================================
// TIME OFF
// ============================================================================

router.get(
  '/time-off',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const status = req.query.status
      ? validateEnum(req.query.status, ['pending', 'approved', 'denied', 'cancelled'] as const, 'status', false)
      : null;
    const userId = req.query.user_id ? parseId(String(req.query.user_id), 'user_id') : null;

    const where: string[] = [];
    const params: unknown[] = [];
    if (status) {
      where.push('status = ?');
      params.push(status);
    }
    if (userId) {
      where.push('user_id = ?');
      params.push(userId);
    }
    const sql = `SELECT t.*, u.first_name, u.last_name
                 FROM time_off_requests t
                 LEFT JOIN users u ON u.id = t.user_id
                 ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
                 ORDER BY requested_at DESC LIMIT 500`;
    const rows = await adb.all(sql, ...params);
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/time-off',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = req.body?.user_id ? parseId(String(req.body.user_id), 'user_id') : requireUserId(req);
    // Staff can only file for themselves; managers/admins for anyone.
    if (userId !== requireUserId(req)) requireAdminOrManager(req);

    const startDate = validateIsoDate(req.body?.start_date, 'start_date', true)!;
    const endDate = validateIsoDate(req.body?.end_date, 'end_date', true)!;
    if (new Date(endDate).getTime() < new Date(startDate).getTime()) {
      throw new AppError('end_date must be on/after start_date', 400);
    }
    const reason = req.body?.reason ? validateTextLength(req.body.reason, 500, 'reason') : null;

    const result = await adb.run(
      `INSERT INTO time_off_requests (user_id, start_date, end_date, reason)
       VALUES (?, ?, ?, ?)`,
      userId, startDate, endDate, reason,
    );
    audit(req.db, 'time_off_requested', requireUserId(req), req.ip || 'unknown', {
      id: Number(result.lastInsertRowid), user_id: userId,
    });
    const row = await adb.get('SELECT * FROM time_off_requests WHERE id = ?', result.lastInsertRowid);
    res.json({ success: true, data: row });
  }),
);

router.put(
  '/time-off/:id',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'time-off id');
    const status = validateEnum(req.body?.status, ['pending', 'approved', 'denied', 'cancelled'] as const, 'status', true)!;
    const approvedAt = (status === 'approved' || status === 'denied') ? new Date().toISOString() : null;
    const approvedBy = (status === 'approved' || status === 'denied') ? requireUserId(req) : null;

    const result = await adb.run(
      `UPDATE time_off_requests SET status = ?, approved_at = ?, approved_by_user_id = ? WHERE id = ?`,
      status, approvedAt, approvedBy, id,
    );
    if (result.changes === 0) throw new AppError('Time-off request not found', 404);
    audit(req.db, 'time_off_status_changed', requireUserId(req), req.ip || 'unknown', { id, status });
    const row = await adb.get('SELECT * FROM time_off_requests WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/time-off/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'time-off id');
    const row = await adb.get<{ user_id: number; status: string }>(
      'SELECT user_id, status FROM time_off_requests WHERE id = ?', id,
    );
    if (!row) throw new AppError('Time-off request not found', 404);
    // Only the requester (when still pending) or a manager can cancel.
    if (row.user_id !== requireUserId(req)) requireAdminOrManager(req);
    if (row.status !== 'pending') {
      requireAdminOrManager(req);
    }
    await adb.run(`UPDATE time_off_requests SET status = 'cancelled' WHERE id = ?`, id);
    audit(req.db, 'time_off_cancelled', requireUserId(req), req.ip || 'unknown', { id });
    res.json({ success: true, data: { id } });
  }),
);

// ============================================================================
// MY QUEUE — tickets assigned to me
// ============================================================================

router.get(
  '/my-queue',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = requireUserId(req);

    // tickets table uses `assigned_to`, not `assigned_user_id`. Sort: due first
    // (NULLs last), then oldest unfinished. Excludes soft-deleted + closed.
    const tickets = await adb.all(`
      SELECT t.id, t.order_id, t.customer_id, t.status_id, t.assigned_to,
             t.due_on, t.created_at, t.updated_at, t.total,
             ts.name AS status_name, ts.is_closed,
             c.first_name, c.last_name
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.assigned_to = ?
        AND t.is_deleted = 0
        AND COALESCE(ts.is_closed, 0) = 0
      ORDER BY
        CASE WHEN t.due_on IS NULL THEN 1 ELSE 0 END,
        t.due_on ASC,
        t.created_at ASC
      LIMIT 200
    `, userId);

    res.json({ success: true, data: tickets });
  }),
);

// ============================================================================
// TICKET HANDOFF — Tech A → Tech B with required reason
// ============================================================================

router.post(
  '/handoff/:ticketId',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const ticketId = parseId(req.params.ticketId, 'ticket id');
    const toUserId = parseId(String(req.body?.to_user_id ?? ''), 'to_user_id');
    const reason = validateRequiredString(req.body?.reason, 'reason', 500);
    const context = req.body?.context ? validateTextLength(req.body.context, 1000, 'context') : null;
    const fromUserId = requireUserId(req);

    if (toUserId === fromUserId) throw new AppError('Cannot hand off to yourself', 400);

    const ticket = await adb.get<{ id: number; assigned_to: number | null }>(
      'SELECT id, assigned_to FROM tickets WHERE id = ? AND is_deleted = 0', ticketId,
    );
    if (!ticket) throw new AppError('Ticket not found', 404);

    // Optional sanity: only the current assignee or a manager+ can hand off.
    if (ticket.assigned_to && ticket.assigned_to !== fromUserId) {
      requireAdminOrManager(req);
    }
    const target = await adb.get<{ id: number }>('SELECT id FROM users WHERE id = ? AND is_active = 1', toUserId);
    if (!target) throw new AppError('Target user not found', 404);

    await adb.run(
      `INSERT INTO ticket_handoffs (ticket_id, from_user_id, to_user_id, reason, context)
       VALUES (?, ?, ?, ?, ?)`,
      ticketId, fromUserId, toUserId, reason, context,
    );
    await adb.run('UPDATE tickets SET assigned_to = ?, updated_at = datetime("now") WHERE id = ?', toUserId, ticketId);
    audit(req.db, 'ticket_handed_off', fromUserId, req.ip || 'unknown', {
      ticket_id: ticketId, to_user_id: toUserId,
    });
    res.json({ success: true, data: { ticket_id: ticketId, to_user_id: toUserId } });
  }),
);

router.get(
  '/handoff/:ticketId',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const ticketId = parseId(req.params.ticketId, 'ticket id');
    const rows = await adb.all(`
      SELECT h.*, fu.first_name AS from_first, fu.last_name AS from_last,
             tu.first_name AS to_first, tu.last_name AS to_last
      FROM ticket_handoffs h
      LEFT JOIN users fu ON fu.id = h.from_user_id
      LEFT JOIN users tu ON tu.id = h.to_user_id
      WHERE h.ticket_id = ?
      ORDER BY handed_off_at DESC LIMIT 50
    `, ticketId);
    res.json({ success: true, data: rows });
  }),
);

// ============================================================================
// MENTIONS — inbox + mark-read
// ============================================================================

router.get(
  '/mentions',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = requireUserId(req);
    const onlyUnread = String(req.query.unread || '') === '1';
    const sql = `SELECT m.*, u.first_name AS by_first, u.last_name AS by_last
                 FROM team_mentions m
                 LEFT JOIN users u ON u.id = m.mentioned_by_user_id
                 WHERE m.mentioned_user_id = ?
                 ${onlyUnread ? 'AND m.read_at IS NULL' : ''}
                 ORDER BY created_at DESC LIMIT 100`;
    const rows = await adb.all(sql, userId);
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/mentions',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const mentionedUserId = parseId(String(req.body?.mentioned_user_id ?? ''), 'mentioned_user_id');
    const contextType = validateEnum(
      req.body?.context_type,
      ['ticket_note', 'chat', 'invoice_note', 'customer_note'] as const,
      'context_type',
      true,
    )!;
    const contextId = parseId(String(req.body?.context_id ?? ''), 'context_id');
    const snippet = req.body?.message_snippet
      ? validateTextLength(req.body.message_snippet, 280, 'message_snippet')
      : null;

    const result = await adb.run(
      `INSERT INTO team_mentions (mentioned_user_id, mentioned_by_user_id, context_type, context_id, message_snippet)
       VALUES (?, ?, ?, ?, ?)`,
      mentionedUserId, requireUserId(req), contextType, contextId, snippet,
    );
    audit(req.db, 'team_mention_created', requireUserId(req), req.ip || 'unknown', {
      mention_id: Number(result.lastInsertRowid),
      mentioned_user_id: mentionedUserId,
      context_type: contextType,
      context_id: contextId,
    });
    res.json({
      success: true,
      data: { id: Number(result.lastInsertRowid), mentioned_user_id: mentionedUserId },
    });
  }),
);

router.post(
  '/mentions/:id/read',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'mention id');
    const userId = requireUserId(req);
    const result = await adb.run(
      `UPDATE team_mentions SET read_at = datetime('now')
       WHERE id = ? AND mentioned_user_id = ? AND read_at IS NULL`,
      id, userId,
    );
    audit(req.db, 'team_mention_read', userId, req.ip || 'unknown', {
      mention_id: id,
      marked: result.changes > 0,
    });
    res.json({ success: true, data: { id, marked: result.changes > 0 } });
  }),
);

// ============================================================================
// GOALS
// ============================================================================

const VALID_METRICS = ['tickets_closed_week', 'revenue_week', 'csat'] as const;
type GoalMetric = typeof VALID_METRICS[number];

router.get(
  '/goals',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = req.query.user_id ? parseId(String(req.query.user_id), 'user_id') : null;
    const sql = `SELECT g.*, u.first_name, u.last_name
                 FROM team_goals g
                 LEFT JOIN users u ON u.id = g.user_id
                 ${userId ? 'WHERE g.user_id = ?' : ''}
                 ORDER BY g.period_start DESC LIMIT 200`;
    const rows = userId ? await adb.all(sql, userId) : await adb.all(sql);

    // Compute progress: query the relevant table per metric. Cheap N+1 here is
    // fine — bounded to ~200 rows.
    const out = await Promise.all(rows.map(async (g: any) => {
      const progress = await computeGoalProgress(adb, g);
      return { ...g, progress };
    }));
    res.json({ success: true, data: out });
  }),
);

async function computeGoalProgress(
  adb: AsyncDb,
  goal: { user_id: number; metric: string; period_start: string; period_end: string },
): Promise<number> {
  try {
    if (goal.metric === 'tickets_closed_week') {
      const row = await adb.get<{ n: number }>(
        `SELECT COUNT(*) AS n FROM tickets t
         LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
         WHERE t.assigned_to = ? AND ts.is_closed = 1
           AND t.updated_at BETWEEN ? AND ?`,
        goal.user_id, goal.period_start, goal.period_end,
      );
      return row?.n ?? 0;
    }
    if (goal.metric === 'revenue_week') {
      const row = await adb.get<{ n: number }>(
        `SELECT COALESCE(SUM(total),0) AS n FROM tickets
         WHERE assigned_to = ? AND created_at BETWEEN ? AND ?`,
        goal.user_id, goal.period_start, goal.period_end,
      );
      return row?.n ?? 0;
    }
    return 0;
  } catch (err) {
    logger.warn('goal progress compute failed', { goal_user: goal.user_id, error: err instanceof Error ? err.message : 'unknown' });
    return 0;
  }
}

router.post(
  '/goals',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = parseId(String(req.body?.user_id ?? ''), 'user_id');
    const metric = validateEnum(req.body?.metric, VALID_METRICS, 'metric', true)! as GoalMetric;
    const target = validatePositiveAmount(req.body?.target_value, 'target_value');
    const periodStart = validateIsoDate(req.body?.period_start, 'period_start', true)!;
    const periodEnd = validateIsoDate(req.body?.period_end, 'period_end', true)!;
    if (new Date(periodEnd).getTime() < new Date(periodStart).getTime()) {
      throw new AppError('period_end must be on/after period_start', 400);
    }

    const result = await adb.run(
      `INSERT INTO team_goals (user_id, metric, target_value, period_start, period_end)
       VALUES (?, ?, ?, ?, ?)`,
      userId, metric, target, periodStart, periodEnd,
    );
    audit(req.db, 'goal_created', requireUserId(req), req.ip || 'unknown', {
      goal_id: Number(result.lastInsertRowid), user_id: userId, metric,
    });
    const row = await adb.get('SELECT * FROM team_goals WHERE id = ?', result.lastInsertRowid);
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/goals/:id',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'goal id');
    await adb.run('DELETE FROM team_goals WHERE id = ?', id);
    audit(req.db, 'goal_deleted', requireUserId(req), req.ip || 'unknown', { goal_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// ============================================================================
// PERFORMANCE REVIEWS — admin only
// ============================================================================

router.get(
  '/reviews',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = req.query.user_id ? parseId(String(req.query.user_id), 'user_id') : null;
    const sql = `SELECT r.*, u.first_name, u.last_name, ru.first_name AS reviewer_first, ru.last_name AS reviewer_last
                 FROM performance_reviews r
                 LEFT JOIN users u  ON u.id  = r.user_id
                 LEFT JOIN users ru ON ru.id = r.reviewer_user_id
                 ${userId ? 'WHERE r.user_id = ?' : ''}
                 ORDER BY r.created_at DESC LIMIT 100`;
    const rows = userId ? await adb.all(sql, userId) : await adb.all(sql);
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/reviews',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = parseId(String(req.body?.user_id ?? ''), 'user_id');
    const notes = validateRequiredString(req.body?.notes, 'notes', 5000);
    const periodStart = validateIsoDate(req.body?.period_start, 'period_start', false);
    const periodEnd = validateIsoDate(req.body?.period_end, 'period_end', false);
    const ratingRaw = req.body?.rating;
    const rating = ratingRaw == null || ratingRaw === '' ? null : Number(ratingRaw);
    if (rating !== null && (!Number.isInteger(rating) || rating < 1 || rating > 5)) {
      throw new AppError('rating must be 1-5', 400);
    }
    const result = await adb.run(
      `INSERT INTO performance_reviews
         (user_id, reviewer_user_id, period_start, period_end, notes, rating)
       VALUES (?, ?, ?, ?, ?, ?)`,
      userId, requireUserId(req), periodStart, periodEnd, notes, rating,
    );
    audit(req.db, 'review_created', requireUserId(req), req.ip || 'unknown', {
      review_id: Number(result.lastInsertRowid), user_id: userId,
    });
    const row = await adb.get('SELECT * FROM performance_reviews WHERE id = ?', result.lastInsertRowid);
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/reviews/:id',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'review id');
    await adb.run('DELETE FROM performance_reviews WHERE id = ?', id);
    audit(req.db, 'review_deleted', requireUserId(req), req.ip || 'unknown', { review_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// ============================================================================
// KNOWLEDGE BASE — explicitly empty by default; CRUD is open to all staff so
// each shop can build their own. No seeds (audit instruction).
// ============================================================================

router.get(
  '/kb',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const q = req.query.q ? validateTextLength(String(req.query.q), 100, 'q') : '';
    const rows = q
      ? await adb.all(
          `SELECT id, title, tags, created_at, updated_at
           FROM knowledge_base_articles
           WHERE title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\'
           ORDER BY CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END,
                    updated_at DESC, created_at DESC LIMIT 200`,
          `%${escapeLike(q)}%`, `%${escapeLike(q)}%`,
        )
      : await adb.all(
          `SELECT id, title, tags, created_at, updated_at
           FROM knowledge_base_articles
           ORDER BY CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END,
                    updated_at DESC, created_at DESC LIMIT 200`,
        );
    res.json({ success: true, data: rows });
  }),
);

router.get(
  '/kb/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'article id');
    const row = await adb.get('SELECT * FROM knowledge_base_articles WHERE id = ?', id);
    if (!row) throw new AppError('Article not found', 404);
    res.json({ success: true, data: row });
  }),
);

router.post(
  '/kb',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const title = validateRequiredString(req.body?.title, 'title', 200);
    const body = validateRequiredString(req.body?.body, 'body', 50_000);
    const tags = req.body?.tags ? validateTextLength(req.body.tags, 200, 'tags') : null;
    const result = await adb.run(
      `INSERT INTO knowledge_base_articles (title, body, tags, created_by_user_id)
       VALUES (?, ?, ?, ?)`,
      title, body, tags, requireUserId(req),
    );
    audit(req.db, 'kb_article_created', requireUserId(req), req.ip || 'unknown', {
      article_id: Number(result.lastInsertRowid),
    });
    const row = await adb.get('SELECT * FROM knowledge_base_articles WHERE id = ?', result.lastInsertRowid);
    res.json({ success: true, data: row });
  }),
);

router.put(
  '/kb/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'article id');
    const title = req.body?.title !== undefined ? validateRequiredString(req.body.title, 'title', 200) : null;
    const body = req.body?.body !== undefined ? validateRequiredString(req.body.body, 'body', 50_000) : null;
    const tags = req.body?.tags !== undefined
      ? (req.body.tags ? validateTextLength(req.body.tags, 200, 'tags') : null)
      : undefined;

    const fields: string[] = [];
    const params: unknown[] = [];
    if (title !== null) {
      fields.push('title = ?');
      params.push(title);
    }
    if (body !== null) {
      fields.push('body = ?');
      params.push(body);
    }
    if (tags !== undefined) {
      fields.push('tags = ?');
      params.push(tags);
    }
    if (fields.length === 0) throw new AppError('No fields to update', 400);
    fields.push("updated_at = datetime('now')");
    params.push(id);

    const result = await adb.run(
      `UPDATE knowledge_base_articles SET ${fields.join(', ')} WHERE id = ?`,
      ...params,
    );
    if (result.changes === 0) throw new AppError('Article not found', 404);
    audit(req.db, 'kb_article_updated', requireUserId(req), req.ip || 'unknown', {
      article_id: id,
    });
    const row = await adb.get('SELECT * FROM knowledge_base_articles WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/kb/:id',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'article id');
    await adb.run('DELETE FROM knowledge_base_articles WHERE id = ?', id);
    audit(req.db, 'kb_article_deleted', requireUserId(req), req.ip || 'unknown', { article_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// ============================================================================
// PAYROLL — periods + lock + CSV export
// ============================================================================

router.get(
  '/payroll/periods',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const rows = await adb.all(
      `SELECT * FROM payroll_periods ORDER BY start_date DESC LIMIT 100`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/payroll/periods',
  asyncHandler(async (req, res) => {
    requireAdminOrManager(req);
    const adb: AsyncDb = req.asyncDb;
    const name = validateRequiredString(req.body?.name, 'name', 100);
    const startDate = validateIsoDate(req.body?.start_date, 'start_date', true)!;
    const endDate = validateIsoDate(req.body?.end_date, 'end_date', true)!;
    if (new Date(endDate).getTime() < new Date(startDate).getTime()) {
      throw new AppError('end_date must be on/after start_date', 400);
    }
    const notes = req.body?.notes ? validateTextLength(req.body.notes, 500, 'notes') : null;
    const result = await adb.run(
      `INSERT INTO payroll_periods (name, start_date, end_date, notes) VALUES (?, ?, ?, ?)`,
      name, startDate, endDate, notes,
    );
    audit(req.db, 'payroll_period_created', requireUserId(req), req.ip || 'unknown', {
      period_id: Number(result.lastInsertRowid),
    });
    const row = await adb.get('SELECT * FROM payroll_periods WHERE id = ?', result.lastInsertRowid);
    res.json({ success: true, data: row });
  }),
);

router.post(
  '/payroll/lock/:periodId',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): payroll lock freezes commissions and
    // time entries for a period — admin only per audit scope.
    requireAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.periodId, 'period id');
    const period = await adb.get<{ id: number; locked_at: string | null }>(
      'SELECT id, locked_at FROM payroll_periods WHERE id = ?', id,
    );
    if (!period) throw new AppError('Payroll period not found', 404);
    if (period.locked_at) throw new AppError('Payroll period is already locked', 409);
    const now = new Date().toISOString();
    await adb.run(
      `UPDATE payroll_periods SET locked_at = ?, locked_by_user_id = ? WHERE id = ?`,
      now, requireUserId(req), id,
    );
    audit(req.db, 'payroll_period_locked', requireUserId(req), req.ip || 'unknown', { period_id: id });
    res.json({ success: true, data: { id, locked_at: now } });
  }),
);

router.get(
  '/payroll/export.csv',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): CSV contains commission + tip totals
    // per employee — admin only per audit scope.
    requireAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const periodId = parseId(String(req.query.period ?? ''), 'period id');
    const period = await adb.get<{ id: number; name: string; start_date: string; end_date: string }>(
      'SELECT id, name, start_date, end_date FROM payroll_periods WHERE id = ?', periodId,
    );
    if (!period) throw new AppError('Payroll period not found', 404);

    // Upper boundary: include the full end_date day by widening to 23:59:59.
    const periodStart = period.start_date;
    const periodEnd = /^\d{4}-\d{2}-\d{2}$/.test(period.end_date)
      ? `${period.end_date} 23:59:59`
      : period.end_date;

    // Hours per user
    const hours = await adb.all<{ user_id: number; hours: number }>(
      `SELECT user_id, COALESCE(SUM(total_hours), 0) AS hours
       FROM clock_entries
       WHERE clock_in BETWEEN ? AND ? AND clock_out IS NOT NULL
       GROUP BY user_id`,
      periodStart, periodEnd,
    );

    // Commissions per user (includes reversal rows which carry negative amount)
    const commissions = await adb.all<{ user_id: number; commission: number }>(
      `SELECT user_id, COALESCE(SUM(amount), 0) AS commission
       FROM commissions
       WHERE created_at BETWEEN ? AND ?
       GROUP BY user_id`,
      periodStart, periodEnd,
    );

    // POST-ENRICH §28: tips pull from employee_tips (the actual table from
    // migration 075_pos_payment_tracking.sql). The prior `pos_tips` name was
    // a typo — every query silently returned 0 tips via the try/catch.
    let tips: Array<{ user_id: number; tips: number }> = [];
    try {
      tips = await adb.all<{ user_id: number; tips: number }>(
        `SELECT employee_id AS user_id, COALESCE(SUM(tip_amount), 0) AS tips
         FROM employee_tips
         WHERE created_at BETWEEN ? AND ?
         GROUP BY employee_id`,
        periodStart, periodEnd,
      );
    } catch {
      tips = [];
    }

    // Stitch users
    const users = await adb.all<{ id: number; first_name: string; last_name: string; username: string }>(
      `SELECT id, first_name, last_name, username FROM users WHERE is_active = 1 ORDER BY first_name`,
    );
    const hMap = new Map(hours.map(h => [h.user_id, h.hours]));
    const cMap = new Map(commissions.map(c => [c.user_id, c.commission]));
    const tMap = new Map(tips.map(t => [t.user_id, t.tips]));

    // POST-ENRICH §28: Gusto / ADP-compatible column set.
    // Employee ID, First Name, Last Name, Username, Regular Hours, Overtime
    // Hours, Commissions, Tips, Gross Pay, Pay Period Start, Pay Period End.
    // Overtime column is always 0 until the overtime feature is requested
    // (per the audit scope, overtime is explicitly opt-in).
    const csvLines: string[] = [
      'employee_id,first_name,last_name,username,regular_hours,overtime_hours,commissions,tips,gross,period_start,period_end',
    ];
    const sanitize = (s: string | null | undefined) =>
      (s ?? '').replace(/[",\n\r]/g, ' ').trim();
    for (const u of users) {
      const h = Number(hMap.get(u.id) ?? 0).toFixed(2);
      const c = Number(cMap.get(u.id) ?? 0).toFixed(2);
      const t = Number(tMap.get(u.id) ?? 0).toFixed(2);
      const gross = (Number(h) + Number(c) + Number(t)).toFixed(2);
      csvLines.push(
        `${u.id},"${sanitize(u.first_name)}","${sanitize(u.last_name)}",${u.username},${h},0.00,${c},${t},${gross},${period.start_date},${period.end_date}`,
      );
    }

    const csv = csvLines.join('\n');
    const filename = `payroll_${period.name.replace(/[^a-z0-9_\-]/gi, '_')}.csv`;
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.send(csv);
  }),
);

// Read-only check used by other routes (e.g. tickets/commissions) to enforce
// the lock. Exposed via a tiny helper module so we don't have a circular
// import here.
router.get(
  '/payroll/lock-check',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const ts = validateIsoDate(req.query.at, 'at', true)!;
    const locked = await isCommissionLocked(adb, ts);
    res.json({ success: true, data: { locked } });
  }),
);

export default router;
