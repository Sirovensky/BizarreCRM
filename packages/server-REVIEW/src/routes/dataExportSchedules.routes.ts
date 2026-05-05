/**
 * dataExportSchedules.routes.ts — SCAN-498
 *
 * Admin-only CRUD for recurring data export schedules.
 * Mount at: /api/v1/data-export/schedules  (behind authMiddleware)
 *
 * All endpoints require admin role (requireAdmin guard).
 * Parameterized SQL throughout. Integer IDs validated before use.
 */

import { Router, Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES } from '../utils/errorCodes.js';

const router = Router();
const logger = createLogger('data-export-schedules');

// ---------------------------------------------------------------------------
// Constants / allowed values
// ---------------------------------------------------------------------------

const VALID_EXPORT_TYPES = ['full', 'customers', 'tickets', 'invoices', 'inventory', 'expenses'] as const;
const VALID_INTERVAL_KINDS = ['daily', 'weekly', 'monthly'] as const;
const VALID_STATUSES = ['active', 'paused', 'canceled'] as const;

type ExportType = typeof VALID_EXPORT_TYPES[number];
type IntervalKind = typeof VALID_INTERVAL_KINDS[number];
type ScheduleStatus = typeof VALID_STATUSES[number];

// ---------------------------------------------------------------------------
// Admin-only guard (same inline pattern as inbox.routes.ts, dunning.routes.ts)
// ---------------------------------------------------------------------------

function requireAdmin(req: Request): void {
  if (!req.user || req.user.role !== 'admin') {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function validatePositiveInt(raw: unknown, field: string): number {
  const n = Number(raw);
  if (!Number.isInteger(n) || n <= 0) {
    throw new AppError(`${field} must be a positive integer`, 400);
  }
  return n;
}

function sqlNow(): string {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

/**
 * Advance a date string by the schedule's interval.
 * Returns ISO "YYYY-MM-DD HH:MM:SS".
 */
function advanceScheduleNextRun(current: string, kind: IntervalKind, count: number): string {
  const d = new Date(current.includes('T') ? current : current.replace(' ', 'T') + 'Z');
  switch (kind) {
    case 'daily':   d.setUTCDate(d.getUTCDate() + count); break;
    case 'weekly':  d.setUTCDate(d.getUTCDate() + 7 * count); break;
    case 'monthly': d.setUTCMonth(d.getUTCMonth() + count); break;
  }
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

export { advanceScheduleNextRun };

// ---------------------------------------------------------------------------
// GET / — List all schedules
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const schedules = await adb.all<Record<string, unknown>>(
      `SELECT s.*, u.username AS created_by_username
         FROM data_export_schedules s
         LEFT JOIN users u ON u.id = s.created_by_user_id
        ORDER BY s.created_at DESC`,
    );

    res.json({ success: true, data: schedules });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id — Schedule detail + last 20 runs
// ---------------------------------------------------------------------------

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const id = validatePositiveInt(req.params.id as string, 'id');

    const schedule = await adb.get<Record<string, unknown>>(
      `SELECT s.*, u.username AS created_by_username
         FROM data_export_schedules s
         LEFT JOIN users u ON u.id = s.created_by_user_id
        WHERE s.id = ?`,
      id,
    );
    if (!schedule) throw new AppError('Schedule not found', 404);

    const runs = await adb.all<Record<string, unknown>>(
      `SELECT id, schedule_id, run_at, succeeded, export_file, error_message
         FROM data_export_schedule_runs
        WHERE schedule_id = ?
        ORDER BY run_at DESC
        LIMIT 20`,
      id,
    );

    res.json({ success: true, data: { ...schedule, recent_runs: runs } });
  }),
);

// ---------------------------------------------------------------------------
// POST / — Create schedule
// ---------------------------------------------------------------------------

router.post(
  '/',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const {
      name,
      export_type,
      interval_kind,
      interval_count,
      start_date,
      delivery_email,
    } = req.body;

    // Validate required string fields
    if (typeof name !== 'string' || !name.trim()) {
      throw new AppError('name is required', 400);
    }
    const safeName = name.trim().slice(0, 200);

    if (!VALID_EXPORT_TYPES.includes(export_type as ExportType)) {
      throw new AppError(`export_type must be one of: ${VALID_EXPORT_TYPES.join(', ')}`, 400);
    }

    if (!VALID_INTERVAL_KINDS.includes(interval_kind as IntervalKind)) {
      throw new AppError(`interval_kind must be one of: ${VALID_INTERVAL_KINDS.join(', ')}`, 400);
    }

    const safeCount = validatePositiveInt(interval_count, 'interval_count');

    // start_date must be a parseable date string
    if (typeof start_date !== 'string' || !start_date.trim()) {
      throw new AppError('start_date is required (ISO date string)', 400);
    }
    const parsedStart = Date.parse(start_date);
    if (!Number.isFinite(parsedStart)) {
      throw new AppError('start_date is not a valid date', 400);
    }
    const nextRunAt = new Date(parsedStart).toISOString().replace('T', ' ').slice(0, 19);

    const safeEmail = delivery_email
      ? String(delivery_email).trim().slice(0, 254)
      : null;
    if (safeEmail && (safeEmail.length < 3 || !safeEmail.includes('@'))) {
      throw new AppError('delivery_email appears invalid', 400);
    }

    const now = sqlNow();
    const result = await adb.run(
      `INSERT INTO data_export_schedules
         (name, export_type, interval_kind, interval_count, next_run_at, delivery_email,
          status, created_by_user_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?)`,
      safeName,
      export_type,
      interval_kind,
      safeCount,
      nextRunAt,
      safeEmail,
      req.user!.id,
      now,
      now,
    );

    const newId = result.lastInsertRowid as number;

    audit(req.db, 'data_export_schedule_created', req.user!.id, req.ip || 'unknown', {
      schedule_id: newId,
      name: safeName,
      export_type,
      interval_kind,
      interval_count: safeCount,
    });

    logger.info('data export schedule created', {
      schedule_id: newId,
      name: safeName,
      user_id: req.user!.id,
    });

    const created = await adb.get<Record<string, unknown>>(
      'SELECT * FROM data_export_schedules WHERE id = ?',
      newId,
    );

    res.status(201).json({ success: true, data: created });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id — Partial update
// ---------------------------------------------------------------------------

router.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const id = validatePositiveInt(req.params.id as string, 'id');

    const existing = await adb.get<{
      id: number;
      name: string;
      export_type: string;
      interval_kind: string;
      interval_count: number;
      next_run_at: string;
      delivery_email: string | null;
      status: string;
    }>('SELECT * FROM data_export_schedules WHERE id = ?', id);

    if (!existing) throw new AppError('Schedule not found', 404);
    if (existing.status === 'canceled') {
      throw new AppError('Cannot modify a canceled schedule', 409);
    }

    const fields: string[] = [];
    const params: unknown[] = [];

    if (req.body.name !== undefined) {
      const n = String(req.body.name).trim().slice(0, 200);
      if (!n) throw new AppError('name cannot be empty', 400);
      fields.push('name = ?');
      params.push(n);
    }

    if (req.body.export_type !== undefined) {
      if (!VALID_EXPORT_TYPES.includes(req.body.export_type as ExportType)) {
        throw new AppError(`export_type must be one of: ${VALID_EXPORT_TYPES.join(', ')}`, 400);
      }
      fields.push('export_type = ?');
      params.push(req.body.export_type);
    }

    if (req.body.interval_kind !== undefined) {
      if (!VALID_INTERVAL_KINDS.includes(req.body.interval_kind as IntervalKind)) {
        throw new AppError(`interval_kind must be one of: ${VALID_INTERVAL_KINDS.join(', ')}`, 400);
      }
      fields.push('interval_kind = ?');
      params.push(req.body.interval_kind);
    }

    if (req.body.interval_count !== undefined) {
      const c = validatePositiveInt(req.body.interval_count, 'interval_count');
      fields.push('interval_count = ?');
      params.push(c);
    }

    if (req.body.delivery_email !== undefined) {
      const e = req.body.delivery_email
        ? String(req.body.delivery_email).trim().slice(0, 254)
        : null;
      if (e && (e.length < 3 || !e.includes('@'))) {
        throw new AppError('delivery_email appears invalid', 400);
      }
      fields.push('delivery_email = ?');
      params.push(e);
    }

    if (fields.length === 0) {
      throw new AppError('No updatable fields provided', 400);
    }

    fields.push('updated_at = ?');
    params.push(sqlNow());
    params.push(id);

    await adb.run(
      `UPDATE data_export_schedules SET ${fields.join(', ')} WHERE id = ?`,
      ...params,
    );

    audit(req.db, 'data_export_schedule_updated', req.user!.id, req.ip || 'unknown', {
      schedule_id: id,
      fields: fields.filter(f => f !== 'updated_at = ?').map(f => f.split(' = ')[0]),
    });

    const updated = await adb.get<Record<string, unknown>>(
      'SELECT * FROM data_export_schedules WHERE id = ?',
      id,
    );

    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/pause
// ---------------------------------------------------------------------------

router.post(
  '/:id/pause',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const id = validatePositiveInt(req.params.id as string, 'id');

    const existing = await adb.get<{ id: number; status: ScheduleStatus }>(
      'SELECT id, status FROM data_export_schedules WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Schedule not found', 404);
    if (existing.status !== 'active') {
      throw new AppError(`Schedule is already ${existing.status}`, 409);
    }

    await adb.run(
      `UPDATE data_export_schedules SET status = 'paused', updated_at = ? WHERE id = ?`,
      sqlNow(),
      id,
    );

    audit(req.db, 'data_export_schedule_paused', req.user!.id, req.ip || 'unknown', { schedule_id: id });

    res.json({ success: true, data: { id, status: 'paused' } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/resume
// ---------------------------------------------------------------------------

router.post(
  '/:id/resume',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const id = validatePositiveInt(req.params.id as string, 'id');

    const existing = await adb.get<{ id: number; status: ScheduleStatus }>(
      'SELECT id, status FROM data_export_schedules WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Schedule not found', 404);
    if (existing.status !== 'paused') {
      throw new AppError(`Schedule is not paused (current status: ${existing.status})`, 409);
    }

    await adb.run(
      `UPDATE data_export_schedules SET status = 'active', updated_at = ? WHERE id = ?`,
      sqlNow(),
      id,
    );

    audit(req.db, 'data_export_schedule_resumed', req.user!.id, req.ip || 'unknown', { schedule_id: id });

    res.json({ success: true, data: { id, status: 'active' } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/cancel
// ---------------------------------------------------------------------------

router.post(
  '/:id/cancel',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;

    const id = validatePositiveInt(req.params.id as string, 'id');

    const existing = await adb.get<{ id: number; status: ScheduleStatus }>(
      'SELECT id, status FROM data_export_schedules WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Schedule not found', 404);
    if (existing.status === 'canceled') {
      throw new AppError('Schedule is already canceled', 409);
    }

    await adb.run(
      `UPDATE data_export_schedules SET status = 'canceled', updated_at = ? WHERE id = ?`,
      sqlNow(),
      id,
    );

    audit(req.db, 'data_export_schedule_canceled', req.user!.id, req.ip || 'unknown', { schedule_id: id });

    res.json({ success: true, data: { id, status: 'canceled' } });
  }),
);

export default router;
