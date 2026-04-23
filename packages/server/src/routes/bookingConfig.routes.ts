/**
 * Booking Configuration Routes — admin CRUD (SCAN-471, android §58.3)
 *
 * Mounted at /api/v1/booking-config with authMiddleware at parent mount.
 * DO NOT re-add authMiddleware here.
 *
 * Endpoints:
 *   GET    /services?active=1        — list services
 *   POST   /services                 — create service (admin)
 *   PATCH  /services/:id             — update service (admin)
 *   DELETE /services/:id             — soft-delete: sets is_active=0 (admin)
 *
 *   GET    /hours                    — list all 7 weekday rows
 *   PATCH  /hours/:dayOfWeek         — update weekday hours (admin)
 *
 *   GET    /exceptions?from=&to=     — list exceptions in range
 *   POST   /exceptions               — create exception (admin)
 *   PATCH  /exceptions/:id           — update exception (admin)
 *   DELETE /exceptions/:id           — hard-delete exception (admin)
 *
 * Security:
 *   - authMiddleware on parent mount — covers all routes here
 *   - writes gated by requireAdmin() role check
 *   - rate-limit writes 30/min/user
 *   - parameterized SQL throughout
 *   - integer guards + length caps (name 200, description 1000, notes 2000)
 *   - all mutations emit audit() rows
 */

import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateTextLength,
} from '../utils/validate.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';

const router = Router();
const log = createLogger('bookingConfig');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const WRITE_RL_CATEGORY = 'booking_config_write';
const WRITE_RL_MAX = 30;
const WRITE_RL_WINDOW_MS = 60_000;

const MAX_NAME_LEN = 200;
const MAX_DESC_LEN = 1000;
const MAX_REASON_LEN = 2000;

// HH:MM regex — 00:00 through 23:59
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
// YYYY-MM-DD
const DATE_RE = /^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAdmin(req: any): void {
  if (req?.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
  }
}

function checkWriteRateLimit(req: any): void {
  const userId = String(req.user?.id ?? 'unknown');
  const result = consumeWindowRate(
    req.db,
    WRITE_RL_CATEGORY,
    userId,
    WRITE_RL_MAX,
    WRITE_RL_WINDOW_MS,
  );
  if (!result.allowed) {
    throw new AppError(`Rate limit exceeded. Retry in ${result.retryAfterSeconds}s`, 429);
  }
}

function validateNonNegativeInt(value: unknown, fieldName: string): number {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isInteger(n) || n < 0) {
    throw new AppError(`${fieldName} must be a non-negative integer`, 400);
  }
  return n;
}

function validatePositiveInt(value: unknown, fieldName: string): number {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isInteger(n) || n <= 0) {
    throw new AppError(`${fieldName} must be a positive integer`, 400);
  }
  return n;
}

function validateTimeString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || !TIME_RE.test(value)) {
    throw new AppError(`${fieldName} must be HH:MM (24-hour)`, 400);
  }
  return value;
}

function validateDateString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || !DATE_RE.test(value)) {
    throw new AppError(`${fieldName} must be YYYY-MM-DD`, 400);
  }
  return value;
}

function validateDayOfWeek(raw: string): number {
  const n = parseInt(raw, 10);
  if (!Number.isInteger(n) || n < 0 || n > 6) {
    throw new AppError('dayOfWeek must be an integer 0–6', 400);
  }
  return n;
}

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

// GET /services?active=1
router.get('/services', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const onlyActive = req.query.active === '1';

  const sql = onlyActive
    ? 'SELECT * FROM booking_services WHERE is_active = 1 ORDER BY sort_order, name'
    : 'SELECT * FROM booking_services ORDER BY sort_order, name';

  const rows = await adb.all(sql);
  res.json({ success: true, data: rows });
}));

// POST /services (admin)
router.post('/services', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const {
    name,
    description,
    duration_minutes,
    buffer_before_minutes,
    buffer_after_minutes,
    deposit_required,
    deposit_amount_cents,
    visible_on_booking,
    sort_order,
  } = req.body as Record<string, unknown>;

  const validName = validateRequiredString(name, 'name', MAX_NAME_LEN);
  const validDesc = description != null
    ? validateTextLength(String(description), MAX_DESC_LEN, 'description')
    : null;
  const validDuration = validatePositiveInt(duration_minutes, 'duration_minutes');
  const validBufBefore = buffer_before_minutes != null
    ? validateNonNegativeInt(buffer_before_minutes, 'buffer_before_minutes')
    : 0;
  const validBufAfter = buffer_after_minutes != null
    ? validateNonNegativeInt(buffer_after_minutes, 'buffer_after_minutes')
    : 0;
  const validDepositRequired = deposit_required != null
    ? (deposit_required ? 1 : 0)
    : 0;
  const validDepositCents = deposit_amount_cents != null
    ? validateNonNegativeInt(deposit_amount_cents, 'deposit_amount_cents')
    : 0;
  const validVisible = visible_on_booking != null
    ? (visible_on_booking ? 1 : 0)
    : 1;
  const validSortOrder = sort_order != null
    ? validateNonNegativeInt(sort_order, 'sort_order')
    : 0;

  const adb = req.asyncDb;

  const existing = await adb.get<{ id: number }>(
    'SELECT id FROM booking_services WHERE name = ?',
    validName,
  );
  if (existing) {
    throw new AppError('A service with that name already exists', 409);
  }

  const result = await adb.run(
    `INSERT INTO booking_services
      (name, description, duration_minutes, buffer_before_minutes, buffer_after_minutes,
       deposit_required, deposit_amount_cents, visible_on_booking, sort_order,
       is_active, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))`,
    validName, validDesc, validDuration, validBufBefore, validBufAfter,
    validDepositRequired, validDepositCents, validVisible, validSortOrder,
  );

  const newRow = await adb.get('SELECT * FROM booking_services WHERE id = ?', result.lastInsertRowid);

  audit(req.db, 'booking_service.create', req.user!.id, Array.isArray(req.ip) ? req.ip[0] : (req.ip || 'unknown'), {
    serviceId: result.lastInsertRowid,
    name: validName,
  });

  log.info('booking service created', { id: result.lastInsertRowid, name: validName, userId: req.user!.id });
  res.status(201).json({ success: true, data: newRow });
}));

// PATCH /services/:id (admin)
router.patch('/services/:id', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError('Invalid service id', 400);
  }

  const adb = req.asyncDb;
  const existing = await adb.get<{ id: number; name: string }>(
    'SELECT id, name FROM booking_services WHERE id = ?',
    id,
  );
  if (!existing) {
    throw new AppError('Service not found', 404);
  }

  const {
    name,
    description,
    duration_minutes,
    buffer_before_minutes,
    buffer_after_minutes,
    deposit_required,
    deposit_amount_cents,
    visible_on_booking,
    sort_order,
    is_active,
  } = req.body as Record<string, unknown>;

  const fields: string[] = [];
  const params: unknown[] = [];

  if (name !== undefined) {
    const v = validateRequiredString(name, 'name', MAX_NAME_LEN);
    const dupe = await adb.get<{ id: number }>(
      'SELECT id FROM booking_services WHERE name = ? AND id != ?',
      v, id,
    );
    if (dupe) throw new AppError('A service with that name already exists', 409);
    fields.push('name = ?'); params.push(v);
  }
  if (description !== undefined) {
    const v = description === null ? null : validateTextLength(String(description), MAX_DESC_LEN, 'description');
    fields.push('description = ?'); params.push(v);
  }
  if (duration_minutes !== undefined) {
    fields.push('duration_minutes = ?'); params.push(validatePositiveInt(duration_minutes, 'duration_minutes'));
  }
  if (buffer_before_minutes !== undefined) {
    fields.push('buffer_before_minutes = ?'); params.push(validateNonNegativeInt(buffer_before_minutes, 'buffer_before_minutes'));
  }
  if (buffer_after_minutes !== undefined) {
    fields.push('buffer_after_minutes = ?'); params.push(validateNonNegativeInt(buffer_after_minutes, 'buffer_after_minutes'));
  }
  if (deposit_required !== undefined) {
    fields.push('deposit_required = ?'); params.push(deposit_required ? 1 : 0);
  }
  if (deposit_amount_cents !== undefined) {
    fields.push('deposit_amount_cents = ?'); params.push(validateNonNegativeInt(deposit_amount_cents, 'deposit_amount_cents'));
  }
  if (visible_on_booking !== undefined) {
    fields.push('visible_on_booking = ?'); params.push(visible_on_booking ? 1 : 0);
  }
  if (sort_order !== undefined) {
    fields.push('sort_order = ?'); params.push(validateNonNegativeInt(sort_order, 'sort_order'));
  }
  if (is_active !== undefined) {
    fields.push('is_active = ?'); params.push(is_active ? 1 : 0);
  }

  if (fields.length === 0) {
    throw new AppError('No fields to update', 400);
  }

  fields.push("updated_at = datetime('now')");
  params.push(id);

  await adb.run(
    `UPDATE booking_services SET ${fields.join(', ')} WHERE id = ?`,
    ...params,
  );

  const updated = await adb.get('SELECT * FROM booking_services WHERE id = ?', id);

  audit(req.db, 'booking_service.update', req.user!.id, req.ip || 'unknown', {
    serviceId: id,
    fields: fields.filter(f => !f.includes('updated_at')),
  });

  res.json({ success: true, data: updated });
}));

// DELETE /services/:id (admin) — soft delete: is_active = 0
router.delete('/services/:id', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError('Invalid service id', 400);
  }

  const adb = req.asyncDb;
  const existing = await adb.get<{ id: number; name: string }>(
    'SELECT id, name FROM booking_services WHERE id = ?',
    id,
  );
  if (!existing) {
    throw new AppError('Service not found', 404);
  }

  await adb.run(
    "UPDATE booking_services SET is_active = 0, updated_at = datetime('now') WHERE id = ?",
    id,
  );

  audit(req.db, 'booking_service.delete', req.user!.id, req.ip || 'unknown', {
    serviceId: id,
    name: existing.name,
  });

  res.json({ success: true, data: { id } });
}));

// ---------------------------------------------------------------------------
// Hours
// ---------------------------------------------------------------------------

// GET /hours — list all 7 rows
router.get('/hours', asyncHandler(async (req, res) => {
  const rows = await req.asyncDb.all(
    'SELECT * FROM booking_hours ORDER BY day_of_week',
  );
  res.json({ success: true, data: rows });
}));

// PATCH /hours/:dayOfWeek (admin)
router.patch('/hours/:dayOfWeek', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const dow = validateDayOfWeek(req.params.dayOfWeek as string);
  const { open_time, close_time, is_active } = req.body as Record<string, unknown>;

  const fields: string[] = [];
  const params: unknown[] = [];

  if (open_time !== undefined) {
    fields.push('open_time = ?'); params.push(validateTimeString(open_time, 'open_time'));
  }
  if (close_time !== undefined) {
    fields.push('close_time = ?'); params.push(validateTimeString(close_time, 'close_time'));
  }
  if (is_active !== undefined) {
    fields.push('is_active = ?'); params.push(is_active ? 1 : 0);
  }
  if (fields.length === 0) {
    throw new AppError('No fields to update', 400);
  }

  params.push(dow);

  await req.asyncDb.run(
    `UPDATE booking_hours SET ${fields.join(', ')} WHERE day_of_week = ?`,
    ...params,
  );

  const updated = await req.asyncDb.get(
    'SELECT * FROM booking_hours WHERE day_of_week = ?',
    dow,
  );

  audit(req.db, 'booking_hours.update', req.user!.id, req.ip || 'unknown', {
    dayOfWeek: dow,
    fields,
  });

  res.json({ success: true, data: updated });
}));

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

// GET /exceptions?from=YYYY-MM-DD&to=YYYY-MM-DD
router.get('/exceptions', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { from, to } = req.query as Record<string, string>;

  if (from && !DATE_RE.test(from)) throw new AppError('from must be YYYY-MM-DD', 400);
  if (to && !DATE_RE.test(to)) throw new AppError('to must be YYYY-MM-DD', 400);

  let sql = 'SELECT * FROM booking_exceptions';
  const params: unknown[] = [];

  if (from && to) {
    sql += ' WHERE date >= ? AND date <= ?';
    params.push(from, to);
  } else if (from) {
    sql += ' WHERE date >= ?';
    params.push(from);
  } else if (to) {
    sql += ' WHERE date <= ?';
    params.push(to);
  }

  sql += ' ORDER BY date';

  const rows = await adb.all(sql, ...params);
  res.json({ success: true, data: rows });
}));

// POST /exceptions (admin)
router.post('/exceptions', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const { date, is_closed, open_time, close_time, reason } = req.body as Record<string, unknown>;

  const validDate = validateDateString(date, 'date');
  const validIsClosed = is_closed !== undefined ? (is_closed ? 1 : 0) : 1;

  let validOpen: string | null = null;
  let validClose: string | null = null;
  if (!validIsClosed) {
    // Special hours: both open_time and close_time required
    if (!open_time || !close_time) {
      throw new AppError('open_time and close_time are required when is_closed=0', 400);
    }
    validOpen = validateTimeString(open_time, 'open_time');
    validClose = validateTimeString(close_time, 'close_time');
  } else if (open_time !== undefined) {
    validOpen = validateTimeString(open_time, 'open_time');
  } else if (close_time !== undefined) {
    validClose = validateTimeString(close_time, 'close_time');
  }

  const validReason = reason != null
    ? validateTextLength(String(reason), MAX_REASON_LEN, 'reason')
    : null;

  const adb = req.asyncDb;

  const dupe = await adb.get<{ id: number }>(
    'SELECT id FROM booking_exceptions WHERE date = ?',
    validDate,
  );
  if (dupe) {
    throw new AppError('An exception for that date already exists', 409);
  }

  const result = await adb.run(
    `INSERT INTO booking_exceptions (date, is_closed, open_time, close_time, reason)
     VALUES (?, ?, ?, ?, ?)`,
    validDate, validIsClosed, validOpen, validClose, validReason,
  );

  const newRow = await adb.get('SELECT * FROM booking_exceptions WHERE id = ?', result.lastInsertRowid);

  audit(req.db, 'booking_exception.create', req.user!.id, req.ip || 'unknown', {
    exceptionId: result.lastInsertRowid,
    date: validDate,
    is_closed: validIsClosed,
  });

  res.status(201).json({ success: true, data: newRow });
}));

// PATCH /exceptions/:id (admin)
router.patch('/exceptions/:id', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError('Invalid exception id', 400);
  }

  const adb = req.asyncDb;
  const existing = await adb.get<{ id: number; date: string }>(
    'SELECT id, date FROM booking_exceptions WHERE id = ?',
    id,
  );
  if (!existing) {
    throw new AppError('Exception not found', 404);
  }

  const { date, is_closed, open_time, close_time, reason } = req.body as Record<string, unknown>;

  const fields: string[] = [];
  const params: unknown[] = [];

  if (date !== undefined) {
    const v = validateDateString(date, 'date');
    const dupe = await adb.get<{ id: number }>(
      'SELECT id FROM booking_exceptions WHERE date = ? AND id != ?',
      v, id,
    );
    if (dupe) throw new AppError('An exception for that date already exists', 409);
    fields.push('date = ?'); params.push(v);
  }
  if (is_closed !== undefined) {
    fields.push('is_closed = ?'); params.push(is_closed ? 1 : 0);
  }
  if (open_time !== undefined) {
    const v = open_time === null ? null : validateTimeString(open_time, 'open_time');
    fields.push('open_time = ?'); params.push(v);
  }
  if (close_time !== undefined) {
    const v = close_time === null ? null : validateTimeString(close_time, 'close_time');
    fields.push('close_time = ?'); params.push(v);
  }
  if (reason !== undefined) {
    const v = reason === null ? null : validateTextLength(String(reason), MAX_REASON_LEN, 'reason');
    fields.push('reason = ?'); params.push(v);
  }

  if (fields.length === 0) {
    throw new AppError('No fields to update', 400);
  }

  params.push(id);

  await adb.run(
    `UPDATE booking_exceptions SET ${fields.join(', ')} WHERE id = ?`,
    ...params,
  );

  const updated = await adb.get('SELECT * FROM booking_exceptions WHERE id = ?', id);

  audit(req.db, 'booking_exception.update', req.user!.id, req.ip || 'unknown', {
    exceptionId: id,
    date: existing.date,
    fields,
  });

  res.json({ success: true, data: updated });
}));

// DELETE /exceptions/:id (admin) — hard delete
router.delete('/exceptions/:id', asyncHandler(async (req, res) => {
  requireAdmin(req);
  checkWriteRateLimit(req);

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) {
    throw new AppError('Invalid exception id', 400);
  }

  const adb = req.asyncDb;
  const existing = await adb.get<{ id: number; date: string }>(
    'SELECT id, date FROM booking_exceptions WHERE id = ?',
    id,
  );
  if (!existing) {
    throw new AppError('Exception not found', 404);
  }

  await adb.run('DELETE FROM booking_exceptions WHERE id = ?', id);

  audit(req.db, 'booking_exception.delete', req.user!.id, req.ip || 'unknown', {
    exceptionId: id,
    date: existing.date,
  });

  res.json({ success: true, data: { id } });
}));

export default router;
