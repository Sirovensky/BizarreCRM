/**
 * locations.routes.ts
 * SCAN-462: Multi-location management — core backend.
 * Mount point: /api/v1/locations (authMiddleware applied at mount in index.ts)
 *
 * SCOPE LIMITATION: This file covers ONLY the location registry and
 * user-location assignments. It does NOT scope tickets, invoices, or inventory
 * by location_id — that is a separate follow-up epic. See migration 132 for
 * the full scope notice.
 *
 * Role gates:
 *   CRUD (create/update/delete/set-default) : requireAdmin
 *   List / detail                           : any authenticated user
 *   User-location assignment                : requireManagerOrAdmin
 *   /me/* convenience                       : self (any authenticated user)
 */

import { Router, type Request, type Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { ERROR_CODES } from '../utils/errorCodes.js';

const router = Router();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_NAME_LEN    = 200;
const MAX_ADDR_LEN    = 500;
const MAX_PHONE_LEN   = 30;
const MAX_EMAIL_LEN   = 200;
const MAX_NOTES_LEN   = 2000;
const MAX_TZ_LEN      = 60;
const MAX_SHORT_LEN   = 100;   // city / state / postcode / country / role_at_location

const LOC_WRITE_CATEGORY   = 'location_write';
const LOC_WRITE_MAX        = 60;
const LOC_WRITE_WINDOW_MS  = 60_000;

// ---------------------------------------------------------------------------
// Role guards
// ---------------------------------------------------------------------------

function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
}

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
}

// ---------------------------------------------------------------------------
// Rate-limit guard (write paths)
// ---------------------------------------------------------------------------

function checkWriteRate(req: Request): void {
  const result = consumeWindowRate(
    req.db,
    LOC_WRITE_CATEGORY,
    String(req.user!.id),
    LOC_WRITE_MAX,
    LOC_WRITE_WINDOW_MS,
  );
  if (!result.allowed) {
    throw new AppError(
      `Too many location writes. Retry in ${result.retryAfterSeconds}s.`,
      429,
    );
  }
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

function validateRequiredString(value: unknown, field: string, maxLen: number): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new AppError(`${field} is required`, 400);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${field} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed;
}

function validateOptionalString(value: unknown, field: string, maxLen: number): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw new AppError(`${field} must be a string`, 400);
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${field} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed || null;
}

function validateOptionalFloat(value: unknown, field: string, min: number, max: number): number | null {
  if (value === undefined || value === null || value === '') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) throw new AppError(`${field} must be a number`, 400);
  if (n < min || n > max) throw new AppError(`${field} must be between ${min} and ${max}`, 400);
  return n;
}

function validatePositiveInt(value: unknown, field: string): number {
  const n = parseInt(String(value), 10);
  if (!Number.isInteger(n) || n <= 0) throw new AppError(`Invalid ${field}`, 400);
  return n;
}

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface LocationRow {
  id: number;
  name: string;
  address_line: string | null;
  city: string | null;
  state: string | null;
  postcode: string | null;
  country: string;
  phone: string | null;
  email: string | null;
  lat: number | null;
  lng: number | null;
  timezone: string;
  is_active: number;
  is_default: number;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

// ---------------------------------------------------------------------------
// GET / — list locations
// Query: ?active=1|0   (default: all)
// Any authenticated user.
// ---------------------------------------------------------------------------
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const activeFilter = req.query.active;

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (activeFilter !== undefined) {
    const activeVal = activeFilter === '1' || activeFilter === 'true' ? 1 : 0;
    conditions.push('is_active = ?');
    params.push(activeVal);
  }

  const where = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';
  const locations = await adb.all<LocationRow>(
    `SELECT * FROM locations ${where} ORDER BY is_default DESC, name ASC`,
    ...params,
  );

  res.json({ success: true, data: locations });
}));

// ---------------------------------------------------------------------------
// GET /me/locations — current user's assigned locations
// Any authenticated user (self only).
// ---------------------------------------------------------------------------
router.get('/me/locations', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;

  const rows = await adb.all<LocationRow & { is_primary: number; role_at_location: string | null; assigned_at: string }>(
    `SELECT l.*, ul.is_primary, ul.role_at_location, ul.assigned_at
     FROM user_locations ul
     JOIN locations l ON l.id = ul.location_id
     WHERE ul.user_id = ?
     ORDER BY ul.is_primary DESC, l.name ASC`,
    userId,
  );

  res.json({ success: true, data: rows });
}));

// ---------------------------------------------------------------------------
// GET /me/default-location — resolve the user's active work location for UI
// defaulting.  Priority order (Phase 4 — migration 141):
//   1. users.home_location_id   (explicit preference, if set and location is active)
//   2. user_locations.is_primary=1  (junction-table primary assignment)
//   3. locations.is_default=1   (global store default)
// Any authenticated user.
// ---------------------------------------------------------------------------
router.get('/me/default-location', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;

  // Step 1: check users.home_location_id (added in migration 141)
  const userRow = await adb.get<{ home_location_id: number | null }>(
    'SELECT home_location_id FROM users WHERE id = ?',
    userId,
  );
  if (userRow?.home_location_id != null) {
    const homeLocation = await adb.get<LocationRow>(
      'SELECT * FROM locations WHERE id = ? AND is_active = 1',
      userRow.home_location_id,
    );
    if (homeLocation) {
      res.json({ success: true, data: homeLocation });
      return;
    }
    // home_location_id set but location is now inactive — fall through
  }

  // Step 2: try is_primary=1 assignment in junction table
  const primary = await adb.get<LocationRow>(
    `SELECT l.* FROM user_locations ul
     JOIN locations l ON l.id = ul.location_id
     WHERE ul.user_id = ? AND ul.is_primary = 1 AND l.is_active = 1
     LIMIT 1`,
    userId,
  );

  if (primary) {
    res.json({ success: true, data: primary });
    return;
  }

  // Step 3: fall back to the global default location
  const globalDefault = await adb.get<LocationRow>(
    'SELECT * FROM locations WHERE is_default = 1 AND is_active = 1 LIMIT 1',
  );

  res.json({ success: true, data: globalDefault ?? null });
}));

// ---------------------------------------------------------------------------
// GET /users/:userId/locations — list a user's location assignments
// Self or manager+.
// ---------------------------------------------------------------------------
router.get('/users/:userId/locations', asyncHandler(async (req: Request, res: Response) => {
  const userId = validatePositiveInt(req.params.userId, 'userId');

  // Allow self-lookup; manager+ can view anyone's assignments
  if (req.user!.id !== userId) {
    requireManagerOrAdmin(req);
  }

  const rows = await req.asyncDb.all<LocationRow & { is_primary: number; role_at_location: string | null; assigned_at: string }>(
    `SELECT l.*, ul.is_primary, ul.role_at_location, ul.assigned_at
     FROM user_locations ul
     JOIN locations l ON l.id = ul.location_id
     WHERE ul.user_id = ?
     ORDER BY ul.is_primary DESC, l.name ASC`,
    userId,
  );

  res.json({ success: true, data: rows });
}));

// ---------------------------------------------------------------------------
// GET /:id — single location + user count
// Any authenticated user.
// ---------------------------------------------------------------------------
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const id = validatePositiveInt(req.params.id, 'location id');
  const adb = req.asyncDb;

  const [location, countRow] = await Promise.all([
    adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', id),
    adb.get<{ user_count: number }>(
      'SELECT COUNT(*) AS user_count FROM user_locations WHERE location_id = ?',
      id,
    ),
  ]);

  if (!location) throw new AppError('Location not found', 404);

  res.json({
    success: true,
    data: { ...location, user_count: countRow?.user_count ?? 0 },
  });
}));

// ---------------------------------------------------------------------------
// POST / — create location (admin only)
// ---------------------------------------------------------------------------
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  checkWriteRate(req);

  const adb = req.asyncDb;
  const db  = req.db;

  const name         = validateRequiredString(req.body.name, 'name', MAX_NAME_LEN);
  const address_line = validateOptionalString(req.body.address_line, 'address_line', MAX_ADDR_LEN);
  const city         = validateOptionalString(req.body.city, 'city', MAX_SHORT_LEN);
  const state        = validateOptionalString(req.body.state, 'state', MAX_SHORT_LEN);
  const postcode     = validateOptionalString(req.body.postcode, 'postcode', MAX_SHORT_LEN);
  const country      = validateOptionalString(req.body.country, 'country', MAX_SHORT_LEN) ?? 'US';
  const phone        = validateOptionalString(req.body.phone, 'phone', MAX_PHONE_LEN);
  const email        = validateOptionalString(req.body.email, 'email', MAX_EMAIL_LEN);
  const timezone     = validateOptionalString(req.body.timezone, 'timezone', MAX_TZ_LEN) ?? 'America/New_York';
  const notes        = validateOptionalString(req.body.notes, 'notes', MAX_NOTES_LEN);
  const lat          = validateOptionalFloat(req.body.lat, 'lat', -90, 90);
  const lng          = validateOptionalFloat(req.body.lng, 'lng', -180, 180);

  const result = await adb.run(
    `INSERT INTO locations
       (name, address_line, city, state, postcode, country, phone, email,
        lat, lng, timezone, is_active, is_default, notes, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?)`,
    name, address_line, city, state, postcode, country, phone, email,
    lat, lng, timezone, notes, now(), now(),
  );

  const newId = Number(result.lastInsertRowid);
  const created = await adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', newId);

  audit(db, 'location.created', req.user!.id, req.ip || 'unknown', {
    location_id: newId,
    name,
  });

  res.status(201).json({ success: true, data: created });
}));

// ---------------------------------------------------------------------------
// PATCH /:id — partial update (admin only)
// ---------------------------------------------------------------------------
router.patch('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  checkWriteRate(req);

  const id  = validatePositiveInt(req.params.id, 'location id');
  const adb = req.asyncDb;
  const db  = req.db;

  const existing = await adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', id);
  if (!existing) throw new AppError('Location not found', 404);

  // Validate only the fields that were supplied
  const name = req.body.name !== undefined
    ? validateRequiredString(req.body.name, 'name', MAX_NAME_LEN)
    : undefined;
  const address_line = req.body.address_line !== undefined
    ? validateOptionalString(req.body.address_line, 'address_line', MAX_ADDR_LEN)
    : undefined;
  const city = req.body.city !== undefined
    ? validateOptionalString(req.body.city, 'city', MAX_SHORT_LEN)
    : undefined;
  const state = req.body.state !== undefined
    ? validateOptionalString(req.body.state, 'state', MAX_SHORT_LEN)
    : undefined;
  const postcode = req.body.postcode !== undefined
    ? validateOptionalString(req.body.postcode, 'postcode', MAX_SHORT_LEN)
    : undefined;
  const country = req.body.country !== undefined
    ? validateOptionalString(req.body.country, 'country', MAX_SHORT_LEN) ?? 'US'
    : undefined;
  const phone = req.body.phone !== undefined
    ? validateOptionalString(req.body.phone, 'phone', MAX_PHONE_LEN)
    : undefined;
  const email = req.body.email !== undefined
    ? validateOptionalString(req.body.email, 'email', MAX_EMAIL_LEN)
    : undefined;
  const timezone = req.body.timezone !== undefined
    ? validateOptionalString(req.body.timezone, 'timezone', MAX_TZ_LEN) ?? 'America/New_York'
    : undefined;
  const notes = req.body.notes !== undefined
    ? validateOptionalString(req.body.notes, 'notes', MAX_NOTES_LEN)
    : undefined;
  const lat = req.body.lat !== undefined
    ? validateOptionalFloat(req.body.lat, 'lat', -90, 90)
    : undefined;
  const lng = req.body.lng !== undefined
    ? validateOptionalFloat(req.body.lng, 'lng', -180, 180)
    : undefined;

  await adb.run(
    `UPDATE locations SET
       name         = COALESCE(?, name),
       address_line = COALESCE(?, address_line),
       city         = COALESCE(?, city),
       state        = COALESCE(?, state),
       postcode     = COALESCE(?, postcode),
       country      = COALESCE(?, country),
       phone        = COALESCE(?, phone),
       email        = COALESCE(?, email),
       lat          = COALESCE(?, lat),
       lng          = COALESCE(?, lng),
       timezone     = COALESCE(?, timezone),
       notes        = COALESCE(?, notes),
       updated_at   = ?
     WHERE id = ?`,
    name        ?? null,
    address_line !== undefined ? address_line : null,
    city         !== undefined ? city         : null,
    state        !== undefined ? state        : null,
    postcode     !== undefined ? postcode     : null,
    country     ?? null,
    phone        !== undefined ? phone        : null,
    email        !== undefined ? email        : null,
    lat          !== undefined ? lat          : null,
    lng          !== undefined ? lng          : null,
    timezone    ?? null,
    notes        !== undefined ? notes        : null,
    now(),
    id,
  );

  const updated = await adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', id);

  audit(db, 'location.updated', req.user!.id, req.ip || 'unknown', {
    location_id: id,
    changed_fields: Object.keys(req.body),
  });

  res.json({ success: true, data: updated });
}));

// ---------------------------------------------------------------------------
// DELETE /:id — soft delete (admin only)
// Blocked if: only one active location, OR is_default=1
// ---------------------------------------------------------------------------
router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  checkWriteRate(req);

  const id  = validatePositiveInt(req.params.id, 'location id');
  const adb = req.asyncDb;
  const db  = req.db;

  const existing = await adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', id);
  if (!existing) throw new AppError('Location not found', 404);
  if (!existing.is_active) throw new AppError('Location is already inactive', 409);
  if (existing.is_default) {
    throw new AppError('Cannot deactivate the default location. Set another location as default first.', 409);
  }

  const activeCount = await adb.get<{ c: number }>(
    'SELECT COUNT(*) AS c FROM locations WHERE is_active = 1',
  );
  if ((activeCount?.c ?? 0) <= 1) {
    throw new AppError('Cannot deactivate the only active location', 409);
  }

  await adb.run(
    'UPDATE locations SET is_active = 0, updated_at = ? WHERE id = ?',
    now(), id,
  );

  audit(db, 'location.deactivated', req.user!.id, req.ip || 'unknown', {
    location_id: id,
    name: existing.name,
  });

  res.json({ success: true, data: { id, is_active: 0 } });
}));

// ---------------------------------------------------------------------------
// POST /:id/set-default — flip is_default (admin only)
// Trigger cascades: all other rows get is_default=0 atomically.
// ---------------------------------------------------------------------------
router.post('/:id/set-default', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  checkWriteRate(req);

  const id  = validatePositiveInt(req.params.id, 'location id');
  const adb = req.asyncDb;
  const db  = req.db;

  const existing = await adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', id);
  if (!existing) throw new AppError('Location not found', 404);
  if (!existing.is_active) throw new AppError('Cannot set an inactive location as default', 409);
  if (existing.is_default) {
    // Idempotent — already default, return current state
    res.json({ success: true, data: existing });
    return;
  }

  // Setting is_default=1 fires the trg_locations_single_default_update trigger
  // which clears all other rows before this row is written.
  await adb.run(
    'UPDATE locations SET is_default = 1, updated_at = ? WHERE id = ?',
    now(), id,
  );

  const updated = await adb.get<LocationRow>('SELECT * FROM locations WHERE id = ?', id);

  audit(db, 'location.set_default', req.user!.id, req.ip || 'unknown', {
    location_id: id,
    name: existing.name,
  });

  res.json({ success: true, data: updated });
}));

// ---------------------------------------------------------------------------
// POST /users/:userId/locations/:locationId — upsert assignment (manager+)
// Body: { is_primary?: boolean, role_at_location?: string }
// ---------------------------------------------------------------------------
router.post('/users/:userId/locations/:locationId', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  checkWriteRate(req);

  const userId     = validatePositiveInt(req.params.userId, 'userId');
  const locationId = validatePositiveInt(req.params.locationId, 'locationId');
  const adb        = req.asyncDb;
  const db         = req.db;

  // Validate both entities exist
  const [user, location] = await Promise.all([
    adb.get<{ id: number }>('SELECT id FROM users WHERE id = ? AND is_active = 1', userId),
    adb.get<{ id: number; is_active: number }>('SELECT id, is_active FROM locations WHERE id = ?', locationId),
  ]);
  if (!user)     throw new AppError('User not found', 404);
  if (!location) throw new AppError('Location not found', 404);
  if (!location.is_active) throw new AppError('Cannot assign user to an inactive location', 409);

  const isPrimary = req.body.is_primary === true || req.body.is_primary === 1 ? 1 : 0;
  const roleAtLocation = validateOptionalString(req.body.role_at_location, 'role_at_location', MAX_SHORT_LEN);

  // If setting is_primary=1, clear existing primary for this user first
  if (isPrimary) {
    await adb.run(
      'UPDATE user_locations SET is_primary = 0 WHERE user_id = ? AND is_primary = 1',
      userId,
    );
  }

  // Upsert the assignment
  await adb.run(
    `INSERT INTO user_locations (user_id, location_id, is_primary, role_at_location, assigned_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id, location_id) DO UPDATE SET
       is_primary       = excluded.is_primary,
       role_at_location = excluded.role_at_location,
       assigned_at      = excluded.assigned_at`,
    userId, locationId, isPrimary, roleAtLocation, now(),
  );

  const row = await adb.get<{ user_id: number; location_id: number; is_primary: number; role_at_location: string | null; assigned_at: string }>(
    'SELECT * FROM user_locations WHERE user_id = ? AND location_id = ?',
    userId, locationId,
  );

  audit(db, 'location.user_assigned', req.user!.id, req.ip || 'unknown', {
    actor_id:    req.user!.id,
    target_user_id: userId,
    location_id: locationId,
    is_primary:  isPrimary,
  });

  res.status(201).json({ success: true, data: row });
}));

// ---------------------------------------------------------------------------
// DELETE /users/:userId/locations/:locationId — remove assignment (manager+)
// Blocked if it would leave the user with zero location assignments.
// (Intentional: unassigned users are valid for single-location tenants, but
//  once a second location exists the admin must explicitly choose.)
// ---------------------------------------------------------------------------
router.delete('/users/:userId/locations/:locationId', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  checkWriteRate(req);

  const userId     = validatePositiveInt(req.params.userId, 'userId');
  const locationId = validatePositiveInt(req.params.locationId, 'locationId');
  const adb        = req.asyncDb;
  const db         = req.db;

  const existing = await adb.get<{ user_id: number }>(
    'SELECT user_id FROM user_locations WHERE user_id = ? AND location_id = ?',
    userId, locationId,
  );
  if (!existing) throw new AppError('Assignment not found', 404);

  // Count how many locations remain after removal
  const countRow = await adb.get<{ c: number }>(
    'SELECT COUNT(*) AS c FROM user_locations WHERE user_id = ?',
    userId,
  );
  if ((countRow?.c ?? 0) <= 1) {
    throw new AppError(
      'Cannot remove the last location assignment. Assign another location first.',
      409,
    );
  }

  await adb.run(
    'DELETE FROM user_locations WHERE user_id = ? AND location_id = ?',
    userId, locationId,
  );

  audit(db, 'location.user_unassigned', req.user!.id, req.ip || 'unknown', {
    actor_id:    req.user!.id,
    target_user_id: userId,
    location_id: locationId,
  });

  res.json({ success: true, data: { user_id: userId, location_id: locationId } });
}));

export default router;
