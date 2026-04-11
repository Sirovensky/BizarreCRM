import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// @audit-fixed: §37 — Custom field DEFINITIONS are global schema and should
// only be mutable by admins/managers, not by every authenticated user. Reads
// stay open so the rest of the UI can render the forms.
function adminOnly(req: Request, _res: Response, next: NextFunction) {
  if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
    throw new AppError('Admin or manager access required', 403);
  }
  next();
}

// @audit-fixed: §37 — Bound the JSON.stringify(options) and value payloads so
// a malicious client cannot store unbounded TEXT in custom_field_*.
const MAX_OPTIONS_BYTES = 8 * 1024;     // ~8KB
const MAX_VALUE_LEN = 16 * 1024;        // ~16KB per cell
const VALID_ENTITY_TYPES = new Set(['ticket', 'customer', 'inventory', 'invoice']);
const VALID_FIELD_TYPES = new Set(['text', 'number', 'boolean', 'date', 'select', 'multiselect', 'textarea']);

function serializeOptions(options: unknown): string | null {
  if (options == null) return null;
  let json: string;
  try {
    json = JSON.stringify(options);
  } catch {
    throw new AppError('options must be JSON-serialisable', 400);
  }
  if (json.length > MAX_OPTIONS_BYTES) {
    throw new AppError(`options too large (max ${MAX_OPTIONS_BYTES} bytes)`, 400);
  }
  return json;
}

// GET /definitions — List all field definitions
router.get('/definitions', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const entityType = (req.query.entity_type as string || '').trim();
  const conditions = entityType ? 'WHERE entity_type = ?' : '';
  const params = entityType ? [entityType] : [];
  const defs = await adb.all(`SELECT * FROM custom_field_definitions ${conditions} ORDER BY entity_type, sort_order`, ...params);
  res.json({ success: true, data: defs });
}));

// POST /definitions — Create field definition
// @audit-fixed: §37 — adminOnly added; previously any technician could mutate
// global schema.
router.post('/definitions', adminOnly, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { entity_type, field_name, field_type = 'text', options, is_required = 0, sort_order = 0 } = req.body;
  if (!entity_type || !field_name) throw new AppError('entity_type and field_name required', 400);
  // V1: Bound custom field name length
  if (typeof field_name !== 'string' || field_name.length > 100) throw new AppError('field_name must be 100 characters or fewer', 400);
  if (!VALID_ENTITY_TYPES.has(entity_type)) throw new AppError('Invalid entity_type', 400);
  if (!VALID_FIELD_TYPES.has(field_type)) throw new AppError('Invalid field_type', 400);

  // @audit-fixed: §37 — bound options JSON size
  const optionsJson = serializeOptions(options);

  const result = await adb.run(
    'INSERT INTO custom_field_definitions (entity_type, field_name, field_type, options, is_required, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    entity_type, field_name, field_type, optionsJson, is_required ? 1 : 0, sort_order, now(), now());
  audit(req.db, 'custom_field_created', req.user!.id, req.ip || 'unknown', { definition_id: Number(result.lastInsertRowid), entity_type, field_name, field_type });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /definitions/:id — Update field definition
// @audit-fixed: §37 — adminOnly + existence check + field_type whitelist on
// update path (previously you could change field_type to anything).
router.put('/definitions/:id', adminOnly, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM custom_field_definitions WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Custom field definition not found', 404);

  const { field_name, field_type, options, is_required, sort_order } = req.body;
  if (field_name !== undefined && (typeof field_name !== 'string' || field_name.length > 100)) {
    throw new AppError('field_name must be 100 characters or fewer', 400);
  }
  if (field_type !== undefined && !VALID_FIELD_TYPES.has(field_type)) {
    throw new AppError('Invalid field_type', 400);
  }
  // @audit-fixed: §37 — bound options JSON size on update too
  const optionsJson = options !== undefined ? serializeOptions(options) : null;

  await adb.run(`
    UPDATE custom_field_definitions SET
      field_name = COALESCE(?, field_name), field_type = COALESCE(?, field_type),
      options = COALESCE(?, options), is_required = COALESCE(?, is_required),
      sort_order = COALESCE(?, sort_order), updated_at = ?
    WHERE id = ?
  `, field_name ?? null, field_type ?? null, optionsJson,
    is_required !== undefined ? (is_required ? 1 : 0) : null, sort_order ?? null, now(), req.params.id);
  audit(req.db, 'custom_field_updated', req.user!.id, req.ip || 'unknown', { definition_id: Number(req.params.id) });
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

// DELETE /definitions/:id — Remove field definition + its values
// @audit-fixed: §37 — adminOnly + existence check (previously returned 200 even
// when nothing existed, masking caller bugs).
router.delete('/definitions/:id', adminOnly, asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get('SELECT id FROM custom_field_definitions WHERE id = ?', req.params.id);
  if (!existing) throw new AppError('Custom field definition not found', 404);
  await adb.run('DELETE FROM custom_field_values WHERE definition_id = ?', req.params.id);
  await adb.run('DELETE FROM custom_field_definitions WHERE id = ?', req.params.id);
  audit(req.db, 'custom_field_deleted', req.user!.id, req.ip || 'unknown', { definition_id: Number(req.params.id) });
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

// GET /values/:entityType/:entityId — Get custom field values for an entity
router.get('/values/:entityType/:entityId', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const values = await adb.all(`
    SELECT cfv.*, cfd.field_name, cfd.field_type, cfd.options
    FROM custom_field_values cfv
    JOIN custom_field_definitions cfd ON cfd.id = cfv.definition_id
    WHERE cfv.entity_type = ? AND cfv.entity_id = ?
    ORDER BY cfd.sort_order
  `, req.params.entityType, req.params.entityId);
  res.json({ success: true, data: values });
}));

// PUT /values/:entityType/:entityId — Set custom field values (upsert)
router.put('/values/:entityType/:entityId', asyncHandler(async (req, res) => {
  const db = req.db;
  const { fields } = req.body; // Array of { definition_id, value }
  if (!Array.isArray(fields)) throw new AppError('fields array required', 400);
  // @audit-fixed: §37 — validate entityType against the schema whitelist; an
  // arbitrary string would happily get stored and pollute the values table.
  const entityType = String(req.params.entityType || '');
  if (!VALID_ENTITY_TYPES.has(entityType)) {
    throw new AppError('Invalid entity_type', 400);
  }
  // @audit-fixed: §37 — bound fields array length and per-cell value size to
  // prevent unbounded TEXT writes.
  if (fields.length > 200) throw new AppError('Too many fields (max 200)', 400);

  const adb = req.asyncDb;
  const queries: Array<{ sql: string; params: unknown[] }> = [];
  for (const f of fields) {
    if (!f.definition_id) continue;
    const stringValue = String(f.value ?? '');
    if (stringValue.length > MAX_VALUE_LEN) {
      throw new AppError(`Custom field value too large (max ${MAX_VALUE_LEN} chars)`, 400);
    }
    queries.push({
      sql: 'INSERT INTO custom_field_values (definition_id, entity_type, entity_id, value) VALUES (?, ?, ?, ?) ON CONFLICT(definition_id, entity_type, entity_id) DO UPDATE SET value = excluded.value',
      params: [f.definition_id, req.params.entityType, req.params.entityId, stringValue],
    });
  }
  if (queries.length > 0) await adb.transaction(queries);
  audit(db, 'custom_field_values_saved', req.user!.id, req.ip || 'unknown', { entity_type: req.params.entityType, entity_id: Number(req.params.entityId), field_count: fields.length });

  res.json({ success: true, data: { saved: fields.length } });
}));

export default router;
