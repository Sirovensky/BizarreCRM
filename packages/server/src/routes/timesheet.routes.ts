/**
 * Timesheet / clock-entry routes — SCAN-485.
 *
 * Mounted at /api/v1/timesheet. Covers:
 *  - Read clock entries (manager/admin sees all; employee sees own)
 *  - Manager/admin edit of clock entries with mandatory reason,
 *    before/after JSON written to clock_entry_edits, and audit trail.
 *
 * Security contract:
 *  - authMiddleware applied at mount point — NOT re-added here.
 *  - GET enforces self-service: non-manager callers get only their own entries.
 *  - PATCH is manager/admin only; requires non-empty `reason`; writes audit row.
 *  - Rate limits via checkWindowRate / recordWindowAttempt.
 *  - Parameterized SQL; ISO-date and integer validation throughout.
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

const RL_WINDOW_MS = 60_000;
const RL_EDIT_MAX  = 20;   // 20 edits/min per manager user

// ============================================================================
// GET /clock-entries — list entries
// ============================================================================

router.get('/clock-entries', asyncHandler(async (req: any, res: any) => {
  const adb: AsyncDb = req.asyncDb;
  const callerId = requireUserId(req);
  const callerIsManager = isManagerOrAdmin(req);

  let userIdFilter: number | null = null;
  if (req.query.user_id) {
    userIdFilter = parseId(String(req.query.user_id), 'user_id');
    if (!callerIsManager && userIdFilter !== callerId) {
      // Non-managers may only view their own entries.
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
    where.push('ce.user_id = ?');
    params.push(userIdFilter);
  }
  if (fromDate) {
    where.push('ce.clock_in >= ?');
    params.push(fromDate);
  }
  if (toDate) {
    // Include the full to_date day.
    where.push("ce.clock_in <= datetime(?, '+1 day')");
    params.push(toDate);
  }

  const whereClause = where.length ? 'WHERE ' + where.join(' AND ') : '';
  const rows = await adb.all(
    `SELECT ce.*, u.first_name, u.last_name, u.username
     FROM clock_entries ce
     LEFT JOIN users u ON u.id = ce.user_id
     ${whereClause}
     ORDER BY ce.clock_in DESC
     LIMIT 1000`,
    ...params,
  );
  res.json({ success: true, data: rows });
}));

// ============================================================================
// PATCH /clock-entries/:id — manager/admin edit with mandatory reason
// ============================================================================

interface ClockEntry {
  id: number;
  user_id: number;
  clock_in: string;
  clock_out: string | null;
  total_hours: number | null;
  notes: string | null;
}

router.patch('/clock-entries/:id', asyncHandler(async (req: any, res: any) => {
  requireManagerOrAdmin(req);
  const adb: AsyncDb = req.asyncDb;
  const db  = req.db;
  const callerId = requireUserId(req);

  if (!checkWindowRate(db, 'timesheet_edit', String(callerId), RL_EDIT_MAX, RL_WINDOW_MS)) {
    throw new AppError('Too many requests — please slow down', 429);
  }
  recordWindowAttempt(db, 'timesheet_edit', String(callerId), RL_WINDOW_MS);

  const id = parseId(req.params.id, 'clock entry id');

  const existing = await adb.get<ClockEntry>(
    'SELECT * FROM clock_entries WHERE id = ?', id,
  );
  if (!existing) throw new AppError('Clock entry not found', 404);

  // reason is mandatory for every manager edit (audit requirement).
  const reason = req.body?.reason;
  if (!reason || typeof reason !== 'string' || reason.trim().length === 0) {
    throw new AppError('reason is required for timesheet edits', 400);
  }
  const reasonTrimmed = validateTextLength(reason.trim(), 1000, 'reason');

  // Validate incoming fields.
  const newClockIn  = req.body?.clock_in  != null
    ? validateIsoDate(req.body.clock_in, 'clock_in', true)!
    : existing.clock_in;

  const newClockOut = req.body?.clock_out != null
    ? validateIsoDate(req.body.clock_out, 'clock_out', true)!
    : existing.clock_out;

  const newNotes = req.body?.notes !== undefined
    ? (req.body.notes ? validateTextLength(req.body.notes, 1000, 'notes') : null)
    : existing.notes;

  // Time range check when both ends are present.
  if (newClockOut !== null) {
    if (new Date(newClockOut).getTime() <= new Date(newClockIn).getTime()) {
      throw new AppError('clock_out must be after clock_in', 400);
    }
  }

  // Recompute total_hours if both bounds are present.
  let newTotalHours: number | null = existing.total_hours;
  if (newClockOut !== null) {
    const diffMs  = new Date(newClockOut).getTime() - new Date(newClockIn).getTime();
    newTotalHours = Math.round((diffMs / 3_600_000) * 100) / 100;
  } else if (req.body?.clock_out === null) {
    // Explicitly nulling clock_out clears total_hours.
    newTotalHours = null;
  }

  // Capture before/after snapshots for the audit table.
  const beforeJson = JSON.stringify({
    clock_in: existing.clock_in,
    clock_out: existing.clock_out,
    total_hours: existing.total_hours,
    notes: existing.notes,
  });
  const afterJson = JSON.stringify({
    clock_in: newClockIn,
    clock_out: newClockOut,
    total_hours: newTotalHours,
    notes: newNotes,
  });

  await adb.run(
    `UPDATE clock_entries
     SET clock_in = ?, clock_out = ?, total_hours = ?, notes = ?
     WHERE id = ?`,
    newClockIn, newClockOut, newTotalHours, newNotes, id,
  );

  // Write to clock_entry_edits.
  await adb.run(
    `INSERT INTO clock_entry_edits
       (clock_entry_id, editor_user_id, before_json, after_json, reason)
     VALUES (?, ?, ?, ?, ?)`,
    id, callerId, beforeJson, afterJson, reasonTrimmed,
  );

  audit(db, 'clock_entry_edited', callerId, req.ip || 'unknown', {
    clock_entry_id: id,
    user_id: existing.user_id,
    reason: reasonTrimmed,
  });

  const row = await adb.get<ClockEntry>('SELECT * FROM clock_entries WHERE id = ?', id);
  res.json({ success: true, data: row });
}));

export default router;
