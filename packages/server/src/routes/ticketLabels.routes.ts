import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';

// ---------------------------------------------------------------------------
// SCAN-470 — Ticket Labels CRUD + assignment endpoints
// authMiddleware is applied at mount point (index.ts); do NOT re-add here.
// ---------------------------------------------------------------------------

const router = Router();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_NAME_LEN = 100;
const MAX_COLOR_LEN = 7;   // '#RRGGBB'
const MAX_DESC_LEN  = 500;

const LABEL_WRITE_CATEGORY  = 'ticket_label_write';
const LABEL_WRITE_MAX       = 60;
const LABEL_WRITE_WINDOW_MS = 60_000; // 60 writes per user per minute

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function validateIntId(raw: unknown, label: string): number {
  const s = typeof raw === 'string' ? raw : String(raw ?? '');
  const id = parseInt(s, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError(`Invalid ${label}`, 400);
  return id;
}

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

const COLOR_HEX_RE = /^#[0-9A-Fa-f]{6}$/;

function validateColorHex(value: unknown, field: string): string {
  const s = validateRequiredString(value, field, MAX_COLOR_LEN);
  if (!COLOR_HEX_RE.test(s)) throw new AppError(`${field} must be a 6-digit hex color (e.g. #FF5733)`, 400);
  return s;
}

// ---------------------------------------------------------------------------
// Role guards (defence-in-depth — authMiddleware already checked at mount)
// ---------------------------------------------------------------------------

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function rateLimitWrite(req: Request): void {
  const db = req.db;
  const key = String(req.user!.id);
  if (!checkWindowRate(db, LABEL_WRITE_CATEGORY, key, LABEL_WRITE_MAX, LABEL_WRITE_WINDOW_MS)) {
    throw new AppError('Too many label write requests. Please wait before trying again.', 429);
  }
  recordWindowAttempt(db, LABEL_WRITE_CATEGORY, key, LABEL_WRITE_WINDOW_MS);
}

// ---------------------------------------------------------------------------
// GET / — list all active labels (any authed user)
// ---------------------------------------------------------------------------

router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const showAll = req.query.show_inactive === 'true' && (req.user?.role === 'admin' || req.user?.role === 'manager');
  const whereClause = showAll ? '' : 'WHERE is_active = 1';
  const labels = await adb.all<Record<string, unknown>>(
    `SELECT id, name, color_hex, description, is_active, sort_order, created_at, updated_at
     FROM ticket_labels ${whereClause}
     ORDER BY sort_order ASC, name ASC`
  );
  res.json({ success: true, data: labels });
}));

// ---------------------------------------------------------------------------
// POST / — create label (manager+)
// ---------------------------------------------------------------------------

router.post('/', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  rateLimitWrite(req);

  const adb = req.asyncDb;
  const db  = req.db;

  const name        = validateRequiredString(req.body.name, 'name', MAX_NAME_LEN);
  const color_hex   = req.body.color_hex !== undefined
    ? validateColorHex(req.body.color_hex, 'color_hex')
    : '#888888';
  const description = validateOptionalString(req.body.description, 'description', MAX_DESC_LEN);
  const sort_order  = req.body.sort_order !== undefined ? Number(req.body.sort_order) : 0;
  if (!Number.isInteger(sort_order)) throw new AppError('sort_order must be an integer', 400);

  // Unique-name collision → 409
  const existing = await adb.get<{ id: number }>(
    'SELECT id FROM ticket_labels WHERE name = ?', name
  );
  if (existing) throw new AppError(`Label name '${name}' already exists`, 409);

  const ts = now();
  const result = await adb.run(
    `INSERT INTO ticket_labels (name, color_hex, description, sort_order, is_active, created_at, updated_at)
     VALUES (?, ?, ?, ?, 1, ?, ?)`,
    name, color_hex, description, sort_order, ts, ts
  );

  const created = await adb.get('SELECT * FROM ticket_labels WHERE id = ?', result.lastInsertRowid);
  audit(db, 'ticket_label.created', req.user!.id, req.ip || 'unknown', {
    label_id: Number(result.lastInsertRowid), name, color_hex,
  });
  res.status(201).json({ success: true, data: created });
}));

// ---------------------------------------------------------------------------
// PATCH /:id — partial update (manager+)
// ---------------------------------------------------------------------------

router.patch('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  rateLimitWrite(req);

  const adb = req.asyncDb;
  const db  = req.db;
  const id  = validateIntId(req.params.id, 'label ID');

  const label = await adb.get<Record<string, unknown>>(
    'SELECT * FROM ticket_labels WHERE id = ?', id
  );
  if (!label) throw new AppError('Label not found', 404);

  // Only validate / overwrite fields that were sent
  const name = req.body.name !== undefined
    ? validateRequiredString(req.body.name, 'name', MAX_NAME_LEN)
    : null;
  const color_hex = req.body.color_hex !== undefined
    ? validateColorHex(req.body.color_hex, 'color_hex')
    : null;
  const description = req.body.description !== undefined
    ? validateOptionalString(req.body.description, 'description', MAX_DESC_LEN)
    : undefined; // undefined = don't touch
  const sort_order = req.body.sort_order !== undefined ? Number(req.body.sort_order) : null;
  if (sort_order !== null && !Number.isInteger(sort_order)) {
    throw new AppError('sort_order must be an integer', 400);
  }
  const is_active = req.body.is_active !== undefined
    ? (req.body.is_active ? 1 : 0)
    : null;

  // Name uniqueness check (only if changing the name)
  if (name !== null && name !== (label.name as string)) {
    const collision = await adb.get<{ id: number }>(
      'SELECT id FROM ticket_labels WHERE name = ? AND id != ?', name, id
    );
    if (collision) throw new AppError(`Label name '${name}' already exists`, 409);
  }

  await adb.run(
    `UPDATE ticket_labels SET
       name        = COALESCE(?, name),
       color_hex   = COALESCE(?, color_hex),
       description = CASE WHEN ? IS NOT NULL THEN ? ELSE description END,
       sort_order  = COALESCE(?, sort_order),
       is_active   = COALESCE(?, is_active),
       updated_at  = ?
     WHERE id = ?`,
    name, color_hex,
    description !== undefined ? description : null,
    description !== undefined ? description : null,
    sort_order, is_active,
    now(), id
  );

  const updated = await adb.get('SELECT * FROM ticket_labels WHERE id = ?', id);
  audit(db, 'ticket_label.updated', req.user!.id, req.ip || 'unknown', {
    label_id: id, changes: req.body,
  });
  res.json({ success: true, data: updated });
}));

// ---------------------------------------------------------------------------
// DELETE /:id — soft-delete (is_active=0, manager+)
// ---------------------------------------------------------------------------

router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  rateLimitWrite(req);

  const adb = req.asyncDb;
  const db  = req.db;
  const id  = validateIntId(req.params.id, 'label ID');

  const label = await adb.get<{ id: number; is_active: number }>(
    'SELECT id, is_active FROM ticket_labels WHERE id = ?', id
  );
  if (!label) throw new AppError('Label not found', 404);
  if (label.is_active === 0) throw new AppError('Label is already deactivated', 409);

  await adb.run(
    'UPDATE ticket_labels SET is_active = 0, updated_at = ? WHERE id = ?',
    now(), id
  );

  audit(db, 'ticket_label.deactivated', req.user!.id, req.ip || 'unknown', { label_id: id });
  res.json({ success: true, data: { id } });
}));

// ---------------------------------------------------------------------------
// POST /tickets/:ticketId/assign — assign label to ticket (manager+)
// ---------------------------------------------------------------------------

router.post('/tickets/:ticketId/assign', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  rateLimitWrite(req);

  const adb      = req.asyncDb;
  const db       = req.db;
  const ticketId = validateIntId(req.params.ticketId, 'ticket ID');
  const labelId  = req.body.label_id !== undefined
    ? validateIntId(String(req.body.label_id), 'label_id')
    : (() => { throw new AppError('label_id is required', 400); })();

  // Verify ticket exists
  const ticket = await adb.get<{ id: number }>(
    'SELECT id FROM tickets WHERE id = ?', ticketId
  );
  if (!ticket) throw new AppError('Ticket not found', 404);

  // Verify label exists and is active
  const label = await adb.get<{ id: number; is_active: number }>(
    'SELECT id, is_active FROM ticket_labels WHERE id = ?', labelId
  );
  if (!label) throw new AppError('Label not found', 404);
  if (label.is_active === 0) throw new AppError('Cannot assign a deactivated label', 422);

  // Existing assignment → 409
  const already = await adb.get<{ id: number }>(
    'SELECT id FROM ticket_label_assignments WHERE ticket_id = ? AND label_id = ?',
    ticketId, labelId
  );
  if (already) throw new AppError('Label is already assigned to this ticket', 409);

  const ts = now();
  const result = await adb.run(
    'INSERT INTO ticket_label_assignments (ticket_id, label_id, created_at) VALUES (?, ?, ?)',
    ticketId, labelId, ts
  );

  audit(db, 'ticket_label.assigned', req.user!.id, req.ip || 'unknown', {
    assignment_id: Number(result.lastInsertRowid), ticket_id: ticketId, label_id: labelId,
  });
  res.status(201).json({
    success: true,
    data: { id: Number(result.lastInsertRowid), ticket_id: ticketId, label_id: labelId, created_at: ts },
  });
}));

// ---------------------------------------------------------------------------
// DELETE /tickets/:ticketId/labels/:labelId — remove assignment (manager+)
// ---------------------------------------------------------------------------

router.delete('/tickets/:ticketId/labels/:labelId', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  rateLimitWrite(req);

  const adb      = req.asyncDb;
  const db       = req.db;
  const ticketId = validateIntId(req.params.ticketId, 'ticket ID');
  const labelId  = validateIntId(req.params.labelId,  'label ID');

  const assignment = await adb.get<{ id: number }>(
    'SELECT id FROM ticket_label_assignments WHERE ticket_id = ? AND label_id = ?',
    ticketId, labelId
  );
  if (!assignment) throw new AppError('Assignment not found', 404);

  await adb.run(
    'DELETE FROM ticket_label_assignments WHERE ticket_id = ? AND label_id = ?',
    ticketId, labelId
  );

  audit(db, 'ticket_label.unassigned', req.user!.id, req.ip || 'unknown', {
    ticket_id: ticketId, label_id: labelId,
  });
  res.json({ success: true, data: { ticket_id: ticketId, label_id: labelId } });
}));

// ---------------------------------------------------------------------------
// GET /tickets/:ticketId — list all labels assigned to a ticket (any authed user)
// ---------------------------------------------------------------------------

router.get('/tickets/:ticketId', asyncHandler(async (req: Request, res: Response) => {
  const adb      = req.asyncDb;
  const ticketId = validateIntId(req.params.ticketId, 'ticket ID');

  const ticket = await adb.get<{ id: number }>(
    'SELECT id FROM tickets WHERE id = ?', ticketId
  );
  if (!ticket) throw new AppError('Ticket not found', 404);

  const labels = await adb.all<Record<string, unknown>>(
    `SELECT tl.id, tl.name, tl.color_hex, tl.description, tl.sort_order,
            tla.created_at AS assigned_at
     FROM ticket_label_assignments tla
     JOIN ticket_labels tl ON tl.id = tla.label_id
     WHERE tla.ticket_id = ?
     ORDER BY tl.sort_order ASC, tl.name ASC`,
    ticketId
  );

  res.json({ success: true, data: labels });
}));

export default router;
