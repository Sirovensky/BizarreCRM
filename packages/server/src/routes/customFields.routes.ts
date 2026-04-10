import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
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
router.post('/definitions', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { entity_type, field_name, field_type = 'text', options, is_required = 0, sort_order = 0 } = req.body;
  if (!entity_type || !field_name) throw new AppError('entity_type and field_name required', 400);
  // V1: Bound custom field name length
  if (typeof field_name !== 'string' || field_name.length > 100) throw new AppError('field_name must be 100 characters or fewer', 400);
  if (!['ticket', 'customer', 'inventory', 'invoice'].includes(entity_type)) throw new AppError('Invalid entity_type', 400);
  if (!['text', 'number', 'boolean', 'date', 'select', 'multiselect', 'textarea'].includes(field_type)) throw new AppError('Invalid field_type', 400);

  const result = await adb.run(
    'INSERT INTO custom_field_definitions (entity_type, field_name, field_type, options, is_required, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    entity_type, field_name, field_type, options ? JSON.stringify(options) : null, is_required ? 1 : 0, sort_order, now(), now());
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /definitions/:id — Update field definition
router.put('/definitions/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { field_name, field_type, options, is_required, sort_order } = req.body;
  await adb.run(`
    UPDATE custom_field_definitions SET
      field_name = COALESCE(?, field_name), field_type = COALESCE(?, field_type),
      options = COALESCE(?, options), is_required = COALESCE(?, is_required),
      sort_order = COALESCE(?, sort_order), updated_at = ?
    WHERE id = ?
  `, field_name ?? null, field_type ?? null, options ? JSON.stringify(options) : null,
    is_required !== undefined ? (is_required ? 1 : 0) : null, sort_order ?? null, now(), req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

// DELETE /definitions/:id — Remove field definition + its values
router.delete('/definitions/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  await adb.run('DELETE FROM custom_field_values WHERE definition_id = ?', req.params.id);
  await adb.run('DELETE FROM custom_field_definitions WHERE id = ?', req.params.id);
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

  const upsert = db.prepare(`
    INSERT INTO custom_field_values (definition_id, entity_type, entity_id, value)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(definition_id, entity_type, entity_id) DO UPDATE SET value = excluded.value
  `);

  const save = db.transaction(() => {
    for (const f of fields) {
      if (!f.definition_id) continue;
      upsert.run(f.definition_id, req.params.entityType, req.params.entityId, String(f.value ?? ''));
    }
  });
  save();

  res.json({ success: true, data: { saved: fields.length } });
}));

export default router;
