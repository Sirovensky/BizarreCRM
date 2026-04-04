import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET /definitions — List all field definitions
router.get('/definitions', (req, res) => {
  const entityType = (req.query.entity_type as string || '').trim();
  const conditions = entityType ? 'WHERE entity_type = ?' : '';
  const params = entityType ? [entityType] : [];
  const defs = db.prepare(`SELECT * FROM custom_field_definitions ${conditions} ORDER BY entity_type, sort_order`).all(...params);
  res.json({ success: true, data: defs });
});

// POST /definitions — Create field definition
router.post('/definitions', (req, res) => {
  const { entity_type, field_name, field_type = 'text', options, is_required = 0, sort_order = 0 } = req.body;
  if (!entity_type || !field_name) throw new AppError('entity_type and field_name required', 400);
  if (!['ticket', 'customer', 'inventory', 'invoice'].includes(entity_type)) throw new AppError('Invalid entity_type', 400);
  if (!['text', 'number', 'boolean', 'date', 'select', 'multiselect', 'textarea'].includes(field_type)) throw new AppError('Invalid field_type', 400);

  const result = db.prepare(
    'INSERT INTO custom_field_definitions (entity_type, field_name, field_type, options, is_required, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
  ).run(entity_type, field_name, field_type, options ? JSON.stringify(options) : null, is_required ? 1 : 0, sort_order, now(), now());
  res.status(201).json({ success: true, data: { id: Number(result.lastInsertRowid) } });
});

// PUT /definitions/:id — Update field definition
router.put('/definitions/:id', (req, res) => {
  const { field_name, field_type, options, is_required, sort_order } = req.body;
  db.prepare(`
    UPDATE custom_field_definitions SET
      field_name = COALESCE(?, field_name), field_type = COALESCE(?, field_type),
      options = COALESCE(?, options), is_required = COALESCE(?, is_required),
      sort_order = COALESCE(?, sort_order), updated_at = ?
    WHERE id = ?
  `).run(field_name ?? null, field_type ?? null, options ? JSON.stringify(options) : null,
    is_required !== undefined ? (is_required ? 1 : 0) : null, sort_order ?? null, now(), req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
});

// DELETE /definitions/:id — Remove field definition + its values
router.delete('/definitions/:id', (req, res) => {
  db.prepare('DELETE FROM custom_field_values WHERE definition_id = ?').run(req.params.id);
  db.prepare('DELETE FROM custom_field_definitions WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { id: Number(req.params.id) } });
});

// GET /values/:entityType/:entityId — Get custom field values for an entity
router.get('/values/:entityType/:entityId', (req, res) => {
  const values = db.prepare(`
    SELECT cfv.*, cfd.field_name, cfd.field_type, cfd.options
    FROM custom_field_values cfv
    JOIN custom_field_definitions cfd ON cfd.id = cfv.definition_id
    WHERE cfv.entity_type = ? AND cfv.entity_id = ?
    ORDER BY cfd.sort_order
  `).all(req.params.entityType, req.params.entityId);
  res.json({ success: true, data: values });
});

// PUT /values/:entityType/:entityId — Set custom field values (upsert)
router.put('/values/:entityType/:entityId', (req, res) => {
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
});

export default router;
