import { Router } from 'express';

type AnyRow = Record<string, any>;
const router = Router();

// GET / — all preferences for current user
router.get('/', (req, res) => {
  const db = req.db;
  const userId = req.user!.id;
  const rows = db.prepare('SELECT key, value FROM user_preferences WHERE user_id = ?').all(userId) as AnyRow[];
  const prefs: Record<string, any> = {};
  for (const row of rows) {
    try { prefs[row.key] = JSON.parse(row.value); } catch { prefs[row.key] = row.value; }
  }
  res.json({ success: true, data: prefs });
});

// GET /:key — single preference
router.get('/:key', (req, res) => {
  const db = req.db;
  const userId = req.user!.id;
  const row = db.prepare('SELECT value FROM user_preferences WHERE user_id = ? AND key = ?').get(userId, req.params.key) as AnyRow | undefined;
  let value = null;
  if (row) {
    try { value = JSON.parse(row.value); } catch { value = row.value; }
  }
  res.json({ success: true, data: value });
});

// PUT /:key — upsert a preference
router.put('/:key', (req, res) => {
  const db = req.db;
  const userId = req.user!.id;
  const key = req.params.key;
  if (req.body.value === undefined) {
    res.status(400).json({ success: false, error: 'value is required' });
    return;
  }
  const value = JSON.stringify(req.body.value);
  db.prepare(`
    INSERT INTO user_preferences (user_id, key, value) VALUES (?, ?, ?)
    ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value
  `).run(userId, key, value);
  res.json({ success: true, data: { key, value: req.body.value } });
});

// DELETE /:key — delete a preference
router.delete('/:key', (req, res) => {
  const db = req.db;
  const userId = req.user!.id;
  db.prepare('DELETE FROM user_preferences WHERE user_id = ? AND key = ?').run(userId, req.params.key);
  res.json({ success: true, data: null });
});

export default router;
