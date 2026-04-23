/**
 * Shift schedule routes — SCAN-475.
 *
 * Mounted at /api/v1/schedule. Covers:
 *  - CRUD for shift_schedules (manager/admin only for writes; self-service read)
 *  - Shift swap request workflow (request / accept / decline / cancel)
 *
 * Security contract:
 *  - authMiddleware is applied at the parent mount point — NOT re-added here.
 *  - requireManagerOrAdmin gates all write-to-schedule operations.
 *  - Swap-request creation checks shift.user_id === req.user.id.
 *  - Accept/decline checks target_user_id === req.user.id.
 *  - Cancel checks requester_user_id === req.user.id.
 *  - Rate limits via checkWindowRate / recordWindowAttempt on write paths.
 *  - All SQL uses parameterized queries; integer/date inputs validated.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';
import {
  validateIsoDate,
  validateTextLength,
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

function parseId(value: unknown, label = 'id'): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = parseInt(String(raw ?? ''), 10);
  if (!n || isNaN(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

function isManagerOrAdmin(req: any): boolean {
  const role = req?.user?.role;
  return role === 'admin' || role === 'manager';
}

// ── rate limit constants ────────────────────────────────────────────────────

const RL_WINDOW_MS = 60_000;     // 1 minute
const RL_WRITE_MAX = 30;         // 30 writes/min per user
const RL_SWAP_MAX  = 10;         // 10 swap actions/min per user

// ============================================================================
// SHIFTS — CRUD
// ============================================================================

interface ShiftRow {
  id: number;
  user_id: number;
  start_at: string;
  end_at: string;
  role: string | null;
  role_tag: string | null;
  location_id: number | null;
  notes: string | null;
  status: string;
  created_by_user_id: number | null;
  created_at: string;
}

// GET /shifts — list shifts; non-manager can only view own.
router.get('/shifts', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const callerIsManager = isManagerOrAdmin(req);
  const callerId = requireUserId(req);

  // If non-manager requests a different user_id, silently clamp to their own.
  let userIdFilter: number | null = null;
  if (req.query.user_id) {
    userIdFilter = parseId(String(req.query.user_id), 'user_id');
    if (!callerIsManager && userIdFilter !== callerId) {
      userIdFilter = callerId;
    }
  } else if (!callerIsManager) {
    userIdFilter = callerId;
  }

  const fromDate = req.query.from_date
    ? validateIsoDate(req.query.from_date, 'from_date', false)
    : null;
  const toDate = req.query.to_date
    ? validateIsoDate(req.query.to_date, 'to_date', false)
    : null;

  const where: string[] = [];
  const params: unknown[] = [];

  if (userIdFilter !== null) {
    where.push('s.user_id = ?');
    params.push(userIdFilter);
  }
  if (fromDate) {
    where.push('s.start_at >= ?');
    params.push(fromDate);
  }
  if (toDate) {
    where.push('s.start_at <= ?');
    params.push(toDate);
  }

  const whereClause = where.length ? 'WHERE ' + where.join(' AND ') : '';
  const rows = await adb.all(
    `SELECT s.*, u.first_name, u.last_name, u.username
     FROM shift_schedules s
     LEFT JOIN users u ON u.id = s.user_id
     ${whereClause}
     ORDER BY s.start_at ASC
     LIMIT 500`,
    ...params,
  );
  res.json({ success: true, data: rows });
}));

// POST /shifts — create shift (manager/admin only).
router.post('/shifts', asyncHandler(async (req: any, res: any) => {
  requireManagerOrAdmin(req);
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'schedule_write', String(callerId), RL_WRITE_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'schedule_write', String(callerId), RL_WINDOW_MS);

  const userId   = parseId(String(req.body?.user_id ?? ''), 'user_id');
  const startAt  = validateIsoDate(req.body?.start_at, 'start_at', true)!;
  const endAt    = validateIsoDate(req.body?.end_at, 'end_at', true)!;

  if (new Date(endAt).getTime() <= new Date(startAt).getTime()) {
    throw new AppError('end_at must be after start_at', 400);
  }

  const roleTag    = req.body?.role_tag   ? validateTextLength(req.body.role_tag, 50, 'role_tag') : null;
  const locationId = req.body?.location_id != null ? parseId(String(req.body.location_id), 'location_id') : null;
  const notes      = req.body?.notes      ? validateTextLength(req.body.notes, 1000, 'notes') : null;

  // Verify the target user exists and is active.
  const target = await adb.get<{ id: number }>(
    'SELECT id FROM users WHERE id = ? AND is_active = 1', userId,
  );
  if (!target) throw new AppError('Target user not found or inactive', 404);

  const result = await adb.run(
    `INSERT INTO shift_schedules
       (user_id, start_at, end_at, role_tag, location_id, notes, created_by_user_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    userId, startAt, endAt, roleTag, locationId, notes, callerId,
  );

  audit(db, 'shift_created', callerId, req.ip || 'unknown', {
    shift_id: Number(result.lastInsertRowid), user_id: userId,
  });

  const row = await adb.get<ShiftRow>(
    'SELECT * FROM shift_schedules WHERE id = ?', result.lastInsertRowid,
  );
  res.status(201).json({ success: true, data: row });
}));

// PATCH /shifts/:id — partial update (manager/admin only).
router.patch('/shifts/:id', asyncHandler(async (req: any, res: any) => {
  requireManagerOrAdmin(req);
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'schedule_write', String(callerId), RL_WRITE_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'schedule_write', String(callerId), RL_WINDOW_MS);

  const id = parseId(req.params.id, 'shift id');
  const existing = await adb.get<ShiftRow>(
    'SELECT * FROM shift_schedules WHERE id = ?', id,
  );
  if (!existing) throw new AppError('Shift not found', 404);

  const startAt = req.body?.start_at != null
    ? validateIsoDate(req.body.start_at, 'start_at', true)!
    : existing.start_at;
  const endAt = req.body?.end_at != null
    ? validateIsoDate(req.body.end_at, 'end_at', true)!
    : existing.end_at;

  if (new Date(endAt).getTime() <= new Date(startAt).getTime()) {
    throw new AppError('end_at must be after start_at', 400);
  }

  const roleTag = req.body?.role_tag !== undefined
    ? (req.body.role_tag ? validateTextLength(req.body.role_tag, 50, 'role_tag') : null)
    : existing.role_tag;
  const locationId = req.body?.location_id !== undefined
    ? (req.body.location_id != null ? parseId(String(req.body.location_id), 'location_id') : null)
    : existing.location_id;
  const notes = req.body?.notes !== undefined
    ? (req.body.notes ? validateTextLength(req.body.notes, 1000, 'notes') : null)
    : existing.notes;

  await adb.run(
    `UPDATE shift_schedules
     SET start_at = ?, end_at = ?, role_tag = ?, location_id = ?, notes = ?,
         updated_at = datetime('now')
     WHERE id = ?`,
    startAt, endAt, roleTag, locationId, notes, id,
  );

  audit(db, 'shift_updated', callerId, req.ip || 'unknown', { shift_id: id });

  const row = await adb.get<ShiftRow>('SELECT * FROM shift_schedules WHERE id = ?', id);
  res.json({ success: true, data: row });
}));

// DELETE /shifts/:id — delete (manager/admin only).
router.delete('/shifts/:id', asyncHandler(async (req: any, res: any) => {
  requireManagerOrAdmin(req);
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'schedule_write', String(callerId), RL_WRITE_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'schedule_write', String(callerId), RL_WINDOW_MS);

  const id = parseId(req.params.id, 'shift id');
  const existing = await adb.get<{ id: number }>(
    'SELECT id FROM shift_schedules WHERE id = ?', id,
  );
  if (!existing) throw new AppError('Shift not found', 404);

  await adb.run('DELETE FROM shift_schedules WHERE id = ?', id);
  audit(db, 'shift_deleted', callerId, req.ip || 'unknown', { shift_id: id });
  res.json({ success: true, data: { id } });
}));

// ============================================================================
// SHIFT SWAP REQUESTS
// ============================================================================

interface SwapRow {
  id: number;
  requester_user_id: number;
  target_user_id: number;
  shift_id: number;
  status: string;
  created_at: string;
  decided_at: string | null;
}

// POST /shifts/:id/swap-request — only the shift owner can create.
router.post('/shifts/:id/swap-request', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'swap_write', String(callerId), RL_SWAP_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'swap_write', String(callerId), RL_WINDOW_MS);

  const shiftId      = parseId(req.params.id, 'shift id');
  const targetUserId = parseId(String(req.body?.target_user_id ?? ''), 'target_user_id');

  const shift = await adb.get<{ id: number; user_id: number }>(
    'SELECT id, user_id FROM shift_schedules WHERE id = ?', shiftId,
  );
  if (!shift) throw new AppError('Shift not found', 404);
  if (shift.user_id !== callerId) {
    throw new AppError('Only the shift owner can request a swap', 403);
  }
  if (targetUserId === callerId) {
    throw new AppError('Cannot swap with yourself', 400);
  }

  // Confirm target user is active.
  const target = await adb.get<{ id: number }>(
    'SELECT id FROM users WHERE id = ? AND is_active = 1', targetUserId,
  );
  if (!target) throw new AppError('Target user not found or inactive', 404);

  // Prevent duplicate pending requests for the same shift.
  const dup = await adb.get<{ id: number }>(
    `SELECT id FROM shift_swap_requests
     WHERE shift_id = ? AND status = 'pending' AND requester_user_id = ?`,
    shiftId, callerId,
  );
  if (dup) throw new AppError('A pending swap request already exists for this shift', 409);

  const result = await adb.run(
    `INSERT INTO shift_swap_requests (requester_user_id, target_user_id, shift_id)
     VALUES (?, ?, ?)`,
    callerId, targetUserId, shiftId,
  );

  audit(db, 'shift_swap_requested', callerId, req.ip || 'unknown', {
    swap_id: Number(result.lastInsertRowid), shift_id: shiftId, target_user_id: targetUserId,
  });

  const row = await adb.get<SwapRow>(
    'SELECT * FROM shift_swap_requests WHERE id = ?', result.lastInsertRowid,
  );
  res.status(201).json({ success: true, data: row });
}));

// POST /swap/:requestId/accept — only target_user_id can accept; swaps owner.
router.post('/swap/:requestId/accept', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'swap_write', String(callerId), RL_SWAP_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'swap_write', String(callerId), RL_WINDOW_MS);

  const reqId = parseId(req.params.requestId, 'requestId');
  const swap  = await adb.get<SwapRow>(
    'SELECT * FROM shift_swap_requests WHERE id = ?', reqId,
  );
  if (!swap) throw new AppError('Swap request not found', 404);
  if (swap.target_user_id !== callerId) {
    throw new AppError('Only the target user can accept a swap request', 403);
  }
  if (swap.status !== 'pending') {
    throw new AppError(`Swap request is already ${swap.status}`, 409);
  }

  // Transfer shift ownership atomically — both updates must succeed together.
  await adb.transaction([
    {
      sql: `UPDATE shift_schedules SET user_id = ?, updated_at = datetime('now') WHERE id = ?`,
      params: [callerId, swap.shift_id],
      expectChanges: true,
      expectChangesError: 'Shift no longer exists',
    },
    {
      sql: `UPDATE shift_swap_requests SET status = 'accepted', decided_at = datetime('now') WHERE id = ?`,
      params: [reqId],
      expectChanges: true,
      expectChangesError: 'Swap request no longer exists',
    },
  ]);

  audit(db, 'shift_swap_accepted', callerId, req.ip || 'unknown', {
    swap_id: reqId, shift_id: swap.shift_id, from_user_id: swap.requester_user_id,
  });

  const row = await adb.get<SwapRow>('SELECT * FROM shift_swap_requests WHERE id = ?', reqId);
  res.json({ success: true, data: row });
}));

// POST /swap/:requestId/decline — target user declines.
router.post('/swap/:requestId/decline', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'swap_write', String(callerId), RL_SWAP_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'swap_write', String(callerId), RL_WINDOW_MS);

  const reqId = parseId(req.params.requestId, 'requestId');
  const swap  = await adb.get<SwapRow>(
    'SELECT * FROM shift_swap_requests WHERE id = ?', reqId,
  );
  if (!swap) throw new AppError('Swap request not found', 404);
  if (swap.target_user_id !== callerId) {
    throw new AppError('Only the target user can decline a swap request', 403);
  }
  if (swap.status !== 'pending') {
    throw new AppError(`Swap request is already ${swap.status}`, 409);
  }

  await adb.run(
    `UPDATE shift_swap_requests
     SET status = 'declined', decided_at = datetime('now')
     WHERE id = ?`,
    reqId,
  );

  audit(db, 'shift_swap_declined', callerId, req.ip || 'unknown', {
    swap_id: reqId, shift_id: swap.shift_id,
  });

  const row = await adb.get<SwapRow>('SELECT * FROM shift_swap_requests WHERE id = ?', reqId);
  res.json({ success: true, data: row });
}));

// POST /swap/:requestId/cancel — requester cancels their own pending request.
router.post('/swap/:requestId/cancel', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'swap_write', String(callerId), RL_SWAP_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'swap_write', String(callerId), RL_WINDOW_MS);

  const reqId = parseId(req.params.requestId, 'requestId');
  const swap  = await adb.get<SwapRow>(
    'SELECT * FROM shift_swap_requests WHERE id = ?', reqId,
  );
  if (!swap) throw new AppError('Swap request not found', 404);
  if (swap.requester_user_id !== callerId) {
    throw new AppError('Only the requester can cancel a swap request', 403);
  }
  if (swap.status !== 'pending') {
    throw new AppError(`Swap request is already ${swap.status}`, 409);
  }

  await adb.run(
    `UPDATE shift_swap_requests
     SET status = 'canceled', decided_at = datetime('now')
     WHERE id = ?`,
    reqId,
  );

  audit(db, 'shift_swap_canceled', callerId, req.ip || 'unknown', {
    swap_id: reqId, shift_id: swap.shift_id,
  });

  const row = await adb.get<SwapRow>('SELECT * FROM shift_swap_requests WHERE id = ?', reqId);
  res.json({ success: true, data: row });
}));

export default router;
