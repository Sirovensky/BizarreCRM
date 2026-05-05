/**
 * Time-off request routes — SCAN-484.
 *
 * Mounted at /api/v1/time-off. Covers:
 *  - Self-service submission
 *  - Manager/admin approve / deny flow
 *
 * Security contract:
 *  - authMiddleware applied at mount point — NOT re-added here.
 *  - POST / is self-service; user_id is always set to req.user.id.
 *  - GET / returns self by default; manager/admin can pass user_id filter.
 *  - Approve/deny require manager or admin.
 *  - Rate limits on write paths via checkWindowRate / recordWindowAttempt.
 *  - Parameterized SQL, ISO-date validation, 1000-char cap on reason/denial_reason.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';
import {
  validateIsoDate,
  validateTextLength,
  validateEnum,
} from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// ── helpers ──────────────────────────────────────────────────────────────────

function requireUserId(req: any): number {
  const id = req?.user?.id;
  if (!id) throw new AppError('Authentication required', 401);
  return Number(id);
}

function requireManagerOrAdmin(req: any): void {
  const role = req?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function isManagerOrAdmin(req: any): boolean {
  const role = req?.user?.role;
  return role === 'admin' || role === 'manager';
}

function parseId(value: unknown, label = 'id'): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = parseInt(String(raw ?? ''), 10);
  if (!n || isNaN(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

const TIME_OFF_KINDS = ['pto', 'sick', 'unpaid'] as const;

const RL_WINDOW_MS   = 60_000;
const RL_SUBMIT_MAX  = 20;   // 20 submissions/min per user
const RL_APPROVE_MAX = 30;   // 30 approval actions/min per manager

// ============================================================================
// POST / — submit a time-off request (self-service)
// ============================================================================

router.post('/', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'timeoff_submit', String(callerId), RL_SUBMIT_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'timeoff_submit', String(callerId), RL_WINDOW_MS);

  const startDate = validateIsoDate(req.body?.start_date, 'start_date', true)!;
  const endDate   = validateIsoDate(req.body?.end_date, 'end_date', true)!;

  if (new Date(endDate).getTime() < new Date(startDate).getTime()) {
    throw new AppError('end_date must be on or after start_date', 400);
  }

  const kind   = validateEnum(req.body?.kind, TIME_OFF_KINDS, 'kind', true)!;
  const reason = req.body?.reason
    ? validateTextLength(req.body.reason, 1000, 'reason')
    : null;

  const result = await adb.run(
    `INSERT INTO time_off_requests
       (user_id, start_date, end_date, kind, reason)
     VALUES (?, ?, ?, ?, ?)`,
    callerId, startDate, endDate, kind, reason,
  );

  audit(db, 'time_off_requested', callerId, req.ip || 'unknown', {
    id: Number(result.lastInsertRowid),
    kind,
    start_date: startDate,
    end_date: endDate,
  });

  const row = await adb.get(
    'SELECT * FROM time_off_requests WHERE id = ?', result.lastInsertRowid,
  );
  res.status(201).json({ success: true, data: row });
}));

// ============================================================================
// GET / — list time-off requests
// ============================================================================

router.get('/', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const callerId = requireUserId(req);
  const callerIsManager = isManagerOrAdmin(req);

  let userIdFilter: number | null = null;
  if (req.query.user_id) {
    userIdFilter = parseId(String(req.query.user_id), 'user_id');
    if (!callerIsManager && userIdFilter !== callerId) {
      userIdFilter = callerId;
    }
  } else if (!callerIsManager) {
    userIdFilter = callerId;
  }

  const where: string[] = [];
  const params: unknown[] = [];

  if (userIdFilter !== null) {
    where.push('t.user_id = ?');
    params.push(userIdFilter);
  }

  const status = req.query.status
    ? validateEnum(req.query.status, ['pending', 'approved', 'denied', 'cancelled'] as const, 'status', false)
    : null;
  if (status) {
    where.push('t.status = ?');
    params.push(status);
  }

  const whereClause = where.length ? 'WHERE ' + where.join(' AND ') : '';
  const rows = await adb.all(
    `SELECT t.*, u.first_name, u.last_name
     FROM time_off_requests t
     LEFT JOIN users u ON u.id = t.user_id
     ${whereClause}
     ORDER BY t.requested_at DESC
     LIMIT 500`,
    ...params,
  );
  res.json({ success: true, data: rows });
}));

// ============================================================================
// POST /:id/approve — manager/admin approves
// ============================================================================

router.post('/:id/approve', asyncHandler(async (req: any, res: any) => {
  requireManagerOrAdmin(req);
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'timeoff_approve', String(callerId), RL_APPROVE_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'timeoff_approve', String(callerId), RL_WINDOW_MS);

  const id = parseId(req.params.id, 'id');
  const existing = await adb.get<{ id: number; status: string; user_id: number }>(
    'SELECT id, status, user_id FROM time_off_requests WHERE id = ?', id,
  );
  if (!existing) throw new AppError('Time-off request not found', 404);
  if (existing.status !== 'pending') {
    throw new AppError(`Cannot approve a request with status '${existing.status}'`, 409);
  }

  const decidedAt = new Date().toISOString();
  await adb.run(
    `UPDATE time_off_requests
     SET status = 'approved', approver_user_id = ?, decided_at = ?,
         approved_by_user_id = ?, approved_at = ?
     WHERE id = ?`,
    callerId, decidedAt, callerId, decidedAt, id,
  );

  audit(db, 'time_off_approved', callerId, req.ip || 'unknown', {
    id, user_id: existing.user_id,
  });

  const row = await adb.get('SELECT * FROM time_off_requests WHERE id = ?', id);
  res.json({ success: true, data: row });
}));

// ============================================================================
// POST /:id/deny — manager/admin denies with optional reason
// ============================================================================

router.post('/:id/deny', asyncHandler(async (req: any, res: any) => {
  requireManagerOrAdmin(req);
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'timeoff_approve', String(callerId), RL_APPROVE_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'timeoff_approve', String(callerId), RL_WINDOW_MS);

  const id = parseId(req.params.id, 'id');
  const existing = await adb.get<{ id: number; status: string; user_id: number }>(
    'SELECT id, status, user_id FROM time_off_requests WHERE id = ?', id,
  );
  if (!existing) throw new AppError('Time-off request not found', 404);
  if (existing.status !== 'pending') {
    throw new AppError(`Cannot deny a request with status '${existing.status}'`, 409);
  }

  const denialReason = req.body?.reason
    ? validateTextLength(req.body.reason, 1000, 'reason')
    : null;
  const decidedAt = new Date().toISOString();

  await adb.run(
    `UPDATE time_off_requests
     SET status = 'denied', approver_user_id = ?, decided_at = ?,
         denial_reason = ?, approved_by_user_id = ?, approved_at = ?
     WHERE id = ?`,
    callerId, decidedAt, denialReason, callerId, decidedAt, id,
  );

  audit(db, 'time_off_denied', callerId, req.ip || 'unknown', {
    id, user_id: existing.user_id,
  });

  const row = await adb.get('SELECT * FROM time_off_requests WHERE id = ?', id);
  res.json({ success: true, data: row });
}));

export default router;
