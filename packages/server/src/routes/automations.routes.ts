import { Router, type Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// SEC (PL5): Every write route here must verify the actor is an admin,
// regardless of whatever middleware the router is mounted under. Relying on
// the mount point means a future routing refactor can silently expose these
// endpoints to non-admins. Do the check inline at each handler entrypoint.
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403);
  }
}

// ---------------------------------------------------------------------------
// GET / – List all automation rules
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (_req, res) => {
    const adb = _req.asyncDb;
    const automations = await adb.all(`
      SELECT * FROM automations ORDER BY sort_order ASC, created_at DESC
    `);

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
    requireAdmin(req);
    const adb = req.asyncDb;
    const { name, trigger_type, trigger_config, action_type, action_config, sort_order } = req.body;

    if (!name) throw new AppError('name is required');
    if (!trigger_type) throw new AppError('trigger_type is required');
    if (!action_type) throw new AppError('action_type is required');

    const result = await adb.run(`
      INSERT INTO automations (name, trigger_type, trigger_config, action_type, action_config, sort_order)
      VALUES (?, ?, ?, ?, ?, ?)
    `,
      name,
      trigger_type,
      JSON.stringify(trigger_config ?? {}),
      action_type,
      JSON.stringify(action_config ?? {}),
      sort_order ?? 0,
    );

    const automation = await adb.get('SELECT * FROM automations WHERE id = ?', result.lastInsertRowid) as any;
    audit(req.db, 'automation_created', req.user!.id, req.ip || 'unknown', { automation_id: Number(result.lastInsertRowid), name, trigger_type, action_type });

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
    requireAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    if (!existing) throw new AppError('Automation not found', 404);

    const { name, trigger_type, trigger_config, action_type, action_config, sort_order } = req.body;

    await adb.run(`
      UPDATE automations SET
        name = ?, trigger_type = ?, trigger_config = ?, action_type = ?, action_config = ?,
        sort_order = ?, updated_at = datetime('now')
      WHERE id = ?
    `,
      name !== undefined ? name : existing.name,
      trigger_type !== undefined ? trigger_type : existing.trigger_type,
      trigger_config !== undefined ? JSON.stringify(trigger_config) : existing.trigger_config,
      action_type !== undefined ? action_type : existing.action_type,
      action_config !== undefined ? JSON.stringify(action_config) : existing.action_config,
      sort_order !== undefined ? sort_order : existing.sort_order,
      id,
    );

    const updated = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    audit(req.db, 'automation_updated', req.user!.id, req.ip || 'unknown', { automation_id: id });

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
    requireAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get('SELECT id FROM automations WHERE id = ?', id);
    if (!existing) throw new AppError('Automation not found', 404);

    await adb.run('DELETE FROM automations WHERE id = ?', id);
    audit(req.db, 'automation_deleted', req.user!.id, req.ip || 'unknown', { automation_id: id });
    res.json({ success: true, data: { message: 'Automation deleted' } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id/toggle – Toggle is_active
// ---------------------------------------------------------------------------
router.patch(
  '/:id/toggle',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;
    if (!existing) throw new AppError('Automation not found', 404);

    const newActive = existing.is_active ? 0 : 1;
    await adb.run("UPDATE automations SET is_active = ?, updated_at = datetime('now') WHERE id = ?",
      newActive, id);
    audit(req.db, 'automation_toggled', req.user!.id, req.ip || 'unknown', { automation_id: id, is_active: newActive });

    const updated = await adb.get('SELECT * FROM automations WHERE id = ?', id) as any;

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
