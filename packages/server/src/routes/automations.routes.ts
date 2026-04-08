import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List all automation rules
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (_req, res) => {
    const db = _req.db;
    const automations = db.prepare(`
      SELECT * FROM automations ORDER BY sort_order ASC, created_at DESC
    `).all();

    // Parse JSON config fields
    const parsed = automations.map((a: any) => ({
      ...a,
      trigger_config: safeParseJson(a.trigger_config, {}),
      action_config: safeParseJson(a.action_config, {}),
    }));

    res.json({ success: true, data: parsed });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create automation rule
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const { name, trigger_type, trigger_config, action_type, action_config, sort_order } = req.body;

    if (!name) throw new AppError('name is required');
    if (!trigger_type) throw new AppError('trigger_type is required');
    if (!action_type) throw new AppError('action_type is required');

    const result = db.prepare(`
      INSERT INTO automations (name, trigger_type, trigger_config, action_type, action_config, sort_order)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(
      name,
      trigger_type,
      JSON.stringify(trigger_config ?? {}),
      action_type,
      JSON.stringify(action_config ?? {}),
      sort_order ?? 0,
    );

    const automation = db.prepare('SELECT * FROM automations WHERE id = ?').get(result.lastInsertRowid) as any;

    res.status(201).json({
      success: true,
      data: {
        ...automation,
        trigger_config: safeParseJson(automation.trigger_config, {}),
        action_config: safeParseJson(automation.action_config, {}),
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update automation rule
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM automations WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Automation not found', 404);

    const { name, trigger_type, trigger_config, action_type, action_config, sort_order } = req.body;

    db.prepare(`
      UPDATE automations SET
        name = ?, trigger_type = ?, trigger_config = ?, action_type = ?, action_config = ?,
        sort_order = ?, updated_at = datetime('now')
      WHERE id = ?
    `).run(
      name !== undefined ? name : existing.name,
      trigger_type !== undefined ? trigger_type : existing.trigger_type,
      trigger_config !== undefined ? JSON.stringify(trigger_config) : existing.trigger_config,
      action_type !== undefined ? action_type : existing.action_type,
      action_config !== undefined ? JSON.stringify(action_config) : existing.action_config,
      sort_order !== undefined ? sort_order : existing.sort_order,
      id,
    );

    const updated = db.prepare('SELECT * FROM automations WHERE id = ?').get(id) as any;

    res.json({
      success: true,
      data: {
        ...updated,
        trigger_config: safeParseJson(updated.trigger_config, {}),
        action_config: safeParseJson(updated.action_config, {}),
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id – Delete automation rule
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id FROM automations WHERE id = ?').get(id);
    if (!existing) throw new AppError('Automation not found', 404);

    db.prepare('DELETE FROM automations WHERE id = ?').run(id);
    res.json({ success: true, data: { message: 'Automation deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id/toggle – Toggle is_active
// ---------------------------------------------------------------------------
router.patch(
  '/:id/toggle',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM automations WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Automation not found', 404);

    const newActive = existing.is_active ? 0 : 1;
    db.prepare("UPDATE automations SET is_active = ?, updated_at = datetime('now') WHERE id = ?")
      .run(newActive, id);

    const updated = db.prepare('SELECT * FROM automations WHERE id = ?').get(id) as any;

    res.json({
      success: true,
      data: {
        ...updated,
        trigger_config: safeParseJson(updated.trigger_config, {}),
        action_config: safeParseJson(updated.action_config, {}),
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function safeParseJson(val: any, fallback: any = {}): any {
  if (!val) return fallback;
  try { return JSON.parse(val); } catch { return fallback; }
}

export default router;
