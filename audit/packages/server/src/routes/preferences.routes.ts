import { Router } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import type { AsyncDb } from '../db/async-db.js';

type AnyRow = Record<string, any>;
const router = Router();

// @audit-fixed: §37 — Bound preference key length AND value payload size so a
// hostile client can't pollute the user_preferences table with multi-MB JSON
// blobs or 100KB key names. The keys themselves are kept open (the UI uses a
// growing set of names that we don't want to centralise here yet) but length
// and shape are validated.
const MAX_PREF_KEY_LEN = 100;
const MAX_PREF_VALUE_BYTES = 32 * 1024; // ~32KB serialized JSON
const PREF_KEY_PATTERN = /^[a-zA-Z0-9_.\-]+$/;

function validatePrefKey(key: string): void {
  if (typeof key !== 'string' || key.length === 0 || key.length > MAX_PREF_KEY_LEN) {
    const err: any = new Error(`preference key must be 1-${MAX_PREF_KEY_LEN} characters`);
    err.status = 400;
    throw err;
  }
  if (!PREF_KEY_PATTERN.test(key)) {
    const err: any = new Error('preference key may only contain letters, digits, underscore, dot, or dash');
    err.status = 400;
    throw err;
  }
}

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
  // @audit-fixed: §37 — validate key shape on read too so callers fail fast.
  const key = String(req.params.key || '');
  validatePrefKey(key);
  const row = await adb.get<AnyRow>('SELECT value FROM user_preferences WHERE user_id = ? AND key = ?', userId, key);
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
  const key = String(req.params.key || '');
  // @audit-fixed: §37 — validate key + cap serialized value size to prevent
  // a logged-in user from filling user_preferences with multi-MB JSON.
  validatePrefKey(key);
  if (req.body.value === undefined) {
    res.status(400).json({ success: false, error: 'value is required' });
    return;
  }
  let value: string;
  try {
    value = JSON.stringify(req.body.value);
  } catch {
    res.status(400).json({ success: false, error: 'value must be JSON-serialisable' });
    return;
  }
  if (value.length > MAX_PREF_VALUE_BYTES) {
    res.status(400).json({ success: false, error: `value too large (max ${MAX_PREF_VALUE_BYTES} bytes)` });
    return;
  }
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
  const key = String(req.params.key || '');
  // @audit-fixed: §37 — validate key on delete for symmetry.
  validatePrefKey(key);
  await adb.run('DELETE FROM user_preferences WHERE user_id = ? AND key = ?', userId, key);
  res.json({ success: true, data: null });
}));

export default router;
