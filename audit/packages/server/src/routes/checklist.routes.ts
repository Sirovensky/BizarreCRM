/**
 * Checklist routes — mount at /api/v1/checklists
 *
 * authMiddleware is applied at the parent mount point in index.ts.
 * Manager/admin gates are enforced inline where required.
 *
 * SCAN-468: Daily operational checklist (open-shop / close-shop / midday / custom)
 *
 * Registration snippet (add to index.ts beside other route mounts):
 * ```ts
 * import checklistRoutes from './routes/checklist.routes.js';
 * app.use('/api/v1/checklists', authMiddleware, checklistRoutes);
 * ```
 */

import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';
import { parsePage, parsePageSize } from '../utils/pagination.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('checklist.routes');

type AnyRow = Record<string, unknown>;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_KINDS = ['open', 'close', 'midday', 'custom'] as const;
type ChecklistKind = typeof VALID_KINDS[number];

const VALID_STATUSES = ['in_progress', 'completed', 'abandoned'] as const;
type InstanceStatus = typeof VALID_STATUSES[number];

const MAX_NAME_LEN = 200;
const MAX_NOTES_LEN = 2000;
const MAX_ITEMS = 100;
const MAX_ITEM_LABEL_LEN = 500;

// Rate-limit: 20 template writes per user per minute
const TEMPLATE_WRITE_CATEGORY = 'checklist_template_write';
const TEMPLATE_WRITE_MAX = 20;
const TEMPLATE_WRITE_WINDOW_MS = 60_000;

// Rate-limit: 60 instance writes per user per minute
const INSTANCE_WRITE_CATEGORY = 'checklist_instance_write';
const INSTANCE_WRITE_MAX = 60;
const INSTANCE_WRITE_WINDOW_MS = 60_000;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function parseId(raw: unknown, label = 'ID'): number {
  const id = parseInt(String(raw), 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError(`Invalid ${label}`, 400);
  return id;
}

function validateString(value: unknown, field: string, maxLen: number): string {
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

interface ChecklistItem {
  id: string;
  label: string;
  required: boolean;
}

function validateItemsJson(raw: unknown): string {
  if (!Array.isArray(raw)) throw new AppError('items_json must be an array', 400);
  if (raw.length > MAX_ITEMS) {
    throw new AppError(`items_json cannot exceed ${MAX_ITEMS} items`, 400);
  }
  const items: ChecklistItem[] = raw.map((item: unknown, idx: number) => {
    if (typeof item !== 'object' || item === null) {
      throw new AppError(`items_json[${idx}] must be an object`, 400);
    }
    const obj = item as Record<string, unknown>;
    const id = String(obj.id ?? '').trim().slice(0, 64);
    if (!id) throw new AppError(`items_json[${idx}].id is required`, 400);
    const label = validateString(obj.label, `items_json[${idx}].label`, MAX_ITEM_LABEL_LEN);
    const required = Boolean(obj.required);
    return { id, label, required };
  });
  return JSON.stringify(items);
}

function validateCompletedItemsJson(raw: unknown): string {
  if (!Array.isArray(raw)) throw new AppError('completed_items_json must be an array', 400);
  if (raw.length > MAX_ITEMS) {
    throw new AppError(`completed_items_json cannot exceed ${MAX_ITEMS} entries`, 400);
  }
  // Accept array of item-id strings or objects with { id, checked }
  const normalized = raw.map((entry: unknown, idx: number) => {
    if (typeof entry === 'string') return { id: entry.slice(0, 64), checked: true };
    if (typeof entry === 'object' && entry !== null) {
      const obj = entry as Record<string, unknown>;
      return {
        id: String(obj.id ?? '').trim().slice(0, 64),
        checked: Boolean(obj.checked ?? true),
      };
    }
    throw new AppError(`completed_items_json[${idx}] must be a string or object`, 400);
  });
  return JSON.stringify(normalized);
}

function checkTemplateWriteRate(req: Request): void {
  const db = req.db;
  const key = String(req.user!.id);
  if (!checkWindowRate(db, TEMPLATE_WRITE_CATEGORY, key, TEMPLATE_WRITE_MAX, TEMPLATE_WRITE_WINDOW_MS)) {
    throw new AppError('Too many checklist template writes. Please slow down.', 429);
  }
  recordWindowAttempt(db, TEMPLATE_WRITE_CATEGORY, key, TEMPLATE_WRITE_WINDOW_MS);
}

function checkInstanceWriteRate(req: Request): void {
  const db = req.db;
  const key = String(req.user!.id);
  if (!checkWindowRate(db, INSTANCE_WRITE_CATEGORY, key, INSTANCE_WRITE_MAX, INSTANCE_WRITE_WINDOW_MS)) {
    throw new AppError('Too many checklist instance writes. Please slow down.', 429);
  }
  recordWindowAttempt(db, INSTANCE_WRITE_CATEGORY, key, INSTANCE_WRITE_WINDOW_MS);
}

// ---------------------------------------------------------------------------
// Template routes
// ---------------------------------------------------------------------------

// GET /templates — list all active (or all) templates
router.get('/templates', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset = (page - 1) * pageSize;

  const activeOnly = req.query.active !== '0';
  const kindFilter = (req.query.kind as string || '').trim();

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (activeOnly) { conditions.push('is_active = 1'); }
  if (kindFilter) {
    if (!(VALID_KINDS as readonly string[]).includes(kindFilter)) {
      throw new AppError('kind must be one of: open, close, midday, custom', 400);
    }
    conditions.push('kind = ?');
    params.push(kindFilter);
  }

  const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

  const [totalRow, templates] = await Promise.all([
    adb.get<AnyRow>(`SELECT COUNT(*) AS c FROM ops_checklist_templates ${where}`, ...params),
    adb.all<AnyRow>(
      `SELECT t.*, u.first_name, u.last_name
       FROM ops_checklist_templates t
       LEFT JOIN users u ON u.id = t.created_by_user_id
       ${where}
       ORDER BY t.kind, t.name
       LIMIT ? OFFSET ?`,
      ...params, pageSize, offset,
    ),
  ]);

  const total = (totalRow as AnyRow).c as number;
  res.json({
    success: true,
    data: {
      templates,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// POST /templates — create template (manager+)
router.post('/templates', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  checkTemplateWriteRate(req);

  const adb = req.asyncDb;
  const db = req.db;

  const name = validateString(req.body.name, 'name', MAX_NAME_LEN);
  const kind = req.body.kind as ChecklistKind;
  if (!(VALID_KINDS as readonly string[]).includes(kind)) {
    throw new AppError('kind must be one of: open, close, midday, custom', 400);
  }
  const itemsJson = validateItemsJson(req.body.items_json ?? []);

  const result = await adb.run(
    `INSERT INTO ops_checklist_templates
       (name, kind, items_json, is_active, created_by_user_id, created_at, updated_at)
     VALUES (?, ?, ?, 1, ?, ?, ?)`,
    name, kind, itemsJson, req.user!.id, now(), now(),
  );

  audit(db, 'checklist_template.created', req.user!.id, req.ip || 'unknown', {
    template_id: Number(result.lastInsertRowid),
    name,
    kind,
  });

  const created = await adb.get<AnyRow>('SELECT * FROM ops_checklist_templates WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: created });
}));

// PATCH /templates/:id — update template (manager+)
router.patch('/templates/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  checkTemplateWriteRate(req);

  const adb = req.asyncDb;
  const db = req.db;
  const id = parseId(req.params.id, 'template ID');

  const existing = await adb.get<AnyRow>('SELECT id, name, kind FROM ops_checklist_templates WHERE id = ?', id);
  if (!existing) throw new AppError('Checklist template not found', 404);

  const name = req.body.name !== undefined
    ? validateString(req.body.name, 'name', MAX_NAME_LEN)
    : null;

  let kind: ChecklistKind | null = null;
  if (req.body.kind !== undefined) {
    if (!(VALID_KINDS as readonly string[]).includes(req.body.kind)) {
      throw new AppError('kind must be one of: open, close, midday, custom', 400);
    }
    kind = req.body.kind as ChecklistKind;
  }

  let itemsJson: string | null = null;
  if (req.body.items_json !== undefined) {
    itemsJson = validateItemsJson(req.body.items_json);
  }

  let isActive: number | null = null;
  if (req.body.is_active !== undefined) {
    isActive = req.body.is_active ? 1 : 0;
  }

  await adb.run(
    `UPDATE ops_checklist_templates
     SET name       = COALESCE(?, name),
         kind       = COALESCE(?, kind),
         items_json = COALESCE(?, items_json),
         is_active  = COALESCE(?, is_active),
         updated_at = ?
     WHERE id = ?`,
    name, kind, itemsJson, isActive, now(), id,
  );

  audit(db, 'checklist_template.updated', req.user!.id, req.ip || 'unknown', {
    template_id: id,
    changes: { name, kind, has_items: itemsJson !== null, is_active: isActive },
  });

  const updated = await adb.get<AnyRow>('SELECT * FROM ops_checklist_templates WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

// DELETE /templates/:id — soft delete (manager+)
router.delete('/templates/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);

  const adb = req.asyncDb;
  const db = req.db;
  const id = parseId(req.params.id, 'template ID');

  const existing = await adb.get<AnyRow>('SELECT id FROM ops_checklist_templates WHERE id = ? AND is_active = 1', id);
  if (!existing) throw new AppError('Active checklist template not found', 404);

  await adb.run('UPDATE ops_checklist_templates SET is_active = 0, updated_at = ? WHERE id = ?', now(), id);

  audit(db, 'checklist_template.deleted', req.user!.id, req.ip || 'unknown', { template_id: id });
  res.json({ success: true, data: { id } });
}));

// ---------------------------------------------------------------------------
// Instance routes
// ---------------------------------------------------------------------------

// GET /instances — list instances with optional filters
router.get('/instances', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const offset = (page - 1) * pageSize;

  // Non-managers can only see their own instances
  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  const callerUserId = req.user!.id;

  const conditions: string[] = [];
  const params: unknown[] = [];

  if (!isManager) {
    conditions.push('i.completed_by_user_id = ?');
    params.push(callerUserId);
  } else if (req.query.user_id) {
    const uid = parseId(req.query.user_id, 'user_id');
    conditions.push('i.completed_by_user_id = ?');
    params.push(uid);
  }

  if (req.query.template_id) {
    const tid = parseId(req.query.template_id, 'template_id');
    conditions.push('i.template_id = ?');
    params.push(tid);
  }
  if (req.query.from_date) {
    conditions.push('i.started_at >= ?');
    params.push(String(req.query.from_date).slice(0, 30));
  }
  if (req.query.to_date) {
    conditions.push('i.started_at <= ?');
    params.push(String(req.query.to_date).slice(0, 30));
  }

  const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

  const [totalRow, instances] = await Promise.all([
    adb.get<AnyRow>(`SELECT COUNT(*) AS c FROM ops_checklist_instances i ${where}`, ...params),
    adb.all<AnyRow>(
      `SELECT i.*, t.name AS template_name, t.kind AS template_kind,
              u.first_name, u.last_name
       FROM ops_checklist_instances i
       JOIN ops_checklist_templates t ON t.id = i.template_id
       LEFT JOIN users u ON u.id = i.completed_by_user_id
       ${where}
       ORDER BY i.started_at DESC
       LIMIT ? OFFSET ?`,
      ...params, pageSize, offset,
    ),
  ]);

  const total = (totalRow as AnyRow).c as number;
  res.json({
    success: true,
    data: {
      instances,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// POST /instances — start a new checklist instance
router.post('/instances', asyncHandler(async (req: Request, res: Response) => {
  checkInstanceWriteRate(req);

  const adb = req.asyncDb;
  const templateId = parseId(req.body.template_id, 'template_id');

  const template = await adb.get<AnyRow>(
    'SELECT id FROM ops_checklist_templates WHERE id = ? AND is_active = 1',
    templateId,
  );
  if (!template) throw new AppError('Active checklist template not found', 404);

  const startedAt = now();
  const result = await adb.run(
    `INSERT INTO ops_checklist_instances
       (template_id, completed_by_user_id, completed_items_json, notes, status, started_at)
     VALUES (?, ?, '[]', NULL, 'in_progress', ?)`,
    templateId, req.user!.id, startedAt,
  );

  const created = await adb.get<AnyRow>(
    `SELECT i.*, t.name AS template_name, t.kind AS template_kind, t.items_json
     FROM ops_checklist_instances i
     JOIN ops_checklist_templates t ON t.id = i.template_id
     WHERE i.id = ?`,
    result.lastInsertRowid,
  );

  logger.info('checklist instance started', {
    instance_id: Number(result.lastInsertRowid),
    template_id: templateId,
    user_id: req.user!.id,
  });

  res.status(201).json({ success: true, data: created });
}));

// PATCH /instances/:id — update progress (owner or manager+)
router.patch('/instances/:id', asyncHandler(async (req: Request, res: Response) => {
  checkInstanceWriteRate(req);

  const adb = req.asyncDb;
  const id = parseId(req.params.id, 'instance ID');

  const existing = await adb.get<AnyRow>(
    'SELECT id, completed_by_user_id, status FROM ops_checklist_instances WHERE id = ?',
    id,
  );
  if (!existing) throw new AppError('Checklist instance not found', 404);

  // Only owner or manager+ may update
  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager && existing.completed_by_user_id !== req.user!.id) {
    throw new AppError('Not authorized to update this checklist instance', 403);
  }

  if (existing.status === 'completed' || existing.status === 'abandoned') {
    throw new AppError(`Cannot update a ${existing.status} instance`, 409);
  }

  let completedItemsJson: string | null = null;
  if (req.body.completed_items_json !== undefined) {
    completedItemsJson = validateCompletedItemsJson(req.body.completed_items_json);
  }

  const notes = req.body.notes !== undefined
    ? validateOptionalString(req.body.notes, 'notes', MAX_NOTES_LEN)
    : null;

  let status: InstanceStatus | null = null;
  if (req.body.status !== undefined) {
    if (!(VALID_STATUSES as readonly string[]).includes(req.body.status)) {
      throw new AppError('status must be one of: in_progress, completed, abandoned', 400);
    }
    status = req.body.status as InstanceStatus;
  }

  // Compute completed_at when transitioning to a terminal state
  const completedAt = (status === 'completed' || status === 'abandoned') ? now() : null;

  await adb.run(
    `UPDATE ops_checklist_instances
     SET completed_items_json = COALESCE(?, completed_items_json),
         notes                = COALESCE(?, notes),
         status               = COALESCE(?, status),
         completed_at         = CASE
                                  WHEN ? IS NOT NULL THEN ?
                                  ELSE completed_at
                                END
     WHERE id = ?`,
    completedItemsJson, notes, status, completedAt, completedAt, id,
  );

  const updated = await adb.get<AnyRow>('SELECT * FROM ops_checklist_instances WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

// POST /instances/:id/complete — mark completed
router.post('/instances/:id/complete', asyncHandler(async (req: Request, res: Response) => {
  checkInstanceWriteRate(req);

  const adb = req.asyncDb;
  const id = parseId(req.params.id, 'instance ID');

  const existing = await adb.get<AnyRow>(
    'SELECT id, completed_by_user_id, status FROM ops_checklist_instances WHERE id = ?',
    id,
  );
  if (!existing) throw new AppError('Checklist instance not found', 404);

  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager && existing.completed_by_user_id !== req.user!.id) {
    throw new AppError('Not authorized to complete this checklist instance', 403);
  }
  if (existing.status === 'completed') throw new AppError('Instance already completed', 409);
  if (existing.status === 'abandoned') throw new AppError('Cannot complete an abandoned instance', 409);

  const completedAt = now();
  await adb.run(
    `UPDATE ops_checklist_instances
     SET status = 'completed', completed_at = ?
     WHERE id = ?`,
    completedAt, id,
  );

  logger.info('checklist instance completed', { instance_id: id, user_id: req.user!.id });
  res.json({ success: true, data: { id, status: 'completed', completed_at: completedAt } });
}));

// POST /instances/:id/abandon — mark abandoned
router.post('/instances/:id/abandon', asyncHandler(async (req: Request, res: Response) => {
  checkInstanceWriteRate(req);

  const adb = req.asyncDb;
  const id = parseId(req.params.id, 'instance ID');

  const existing = await adb.get<AnyRow>(
    'SELECT id, completed_by_user_id, status FROM ops_checklist_instances WHERE id = ?',
    id,
  );
  if (!existing) throw new AppError('Checklist instance not found', 404);

  const isManager = req.user!.role === 'admin' || req.user!.role === 'manager';
  if (!isManager && existing.completed_by_user_id !== req.user!.id) {
    throw new AppError('Not authorized to abandon this checklist instance', 403);
  }
  if (existing.status === 'abandoned') throw new AppError('Instance already abandoned', 409);
  if (existing.status === 'completed') throw new AppError('Cannot abandon a completed instance', 409);

  const abandonedAt = now();
  await adb.run(
    `UPDATE ops_checklist_instances
     SET status = 'abandoned', completed_at = ?
     WHERE id = ?`,
    abandonedAt, id,
  );

  res.json({ success: true, data: { id, status: 'abandoned', completed_at: abandonedAt } });
}));

export default router;
