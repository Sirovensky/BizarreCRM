import { Router } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import type { AsyncDb } from '../db/async-db.js';

type AnyRow = Record<string, any>;
const router = Router();

// GET / — all preferences for current user
router.get('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const rows = await adb.all<AnyRow>('SELECT key, value FROM user_preferences WHERE user_id = ?', userId);
  const prefs: Record<string, any> = {};
  for (const row of rows) {
    try { prefs[row.key] = JSON.parse(row.value); } catch { prefs[row.key] = row.value; }
  }
  res.json({ success: true, data: prefs });
}));

// GET /:key — single preference
router.get('/:key', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const row = await adb.get<AnyRow>('SELECT value FROM user_preferences WHERE user_id = ? AND key = ?', userId, req.params.key);
  let value = null;
  if (row) {
    try { value = JSON.parse(row.value); } catch { value = row.value; }
  }
  res.json({ success: true, data: value });
}));

// PUT /:key — upsert a preference
router.put('/:key', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const key = req.params.key;
  if (req.body.value === undefined) {
    res.status(400).json({ success: false, error: 'value is required' });
    return;
  }
  const value = JSON.stringify(req.body.value);
  await adb.run(`
    INSERT INTO user_preferences (user_id, key, value) VALUES (?, ?, ?)
    ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value
  `, userId, key, value);
  res.json({ success: true, data: { key, value: req.body.value } });
}));

// DELETE /:key — delete a preference
router.delete('/:key', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  await adb.run('DELETE FROM user_preferences WHERE user_id = ? AND key = ?', userId, req.params.key);
  res.json({ success: true, data: null });
}));

export default router;
