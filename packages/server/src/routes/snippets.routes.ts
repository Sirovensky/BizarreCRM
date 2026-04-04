import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List all snippets
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const category = (req.query.category as string || '').trim();

    let snippets;
    if (category) {
      snippets = db.prepare(
        'SELECT * FROM snippets WHERE category = ? ORDER BY shortcode'
      ).all(category);
    } else {
      snippets = db.prepare('SELECT * FROM snippets ORDER BY shortcode').all();
    }

    res.json({ success: true, data: snippets });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create snippet
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const { shortcode, title, content, category } = req.body;

    if (!shortcode) throw new AppError('shortcode is required');
    if (!title) throw new AppError('title is required');
    if (!content) throw new AppError('content is required');

    // Check uniqueness
    const existing = db.prepare('SELECT id FROM snippets WHERE shortcode = ?').get(shortcode);
    if (existing) throw new AppError('A snippet with this shortcode already exists', 409);

    const result = db.prepare(`
      INSERT INTO snippets (shortcode, title, content, category, created_by)
      VALUES (?, ?, ?, ?, ?)
    `).run(shortcode, title, content, category ?? null, req.user!.id);

    const snippet = db.prepare('SELECT * FROM snippets WHERE id = ?').get(result.lastInsertRowid);

    res.status(201).json({ success: true, data: snippet });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update snippet
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM snippets WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Snippet not found', 404);

    const { shortcode, title, content, category } = req.body;

    // Check shortcode uniqueness if changing
    if (shortcode && shortcode !== existing.shortcode) {
      const dup = db.prepare('SELECT id FROM snippets WHERE shortcode = ? AND id != ?').get(shortcode, id);
      if (dup) throw new AppError('A snippet with this shortcode already exists', 409);
    }

    db.prepare(`
      UPDATE snippets SET
        shortcode = ?, title = ?, content = ?, category = ?, updated_at = datetime('now')
      WHERE id = ?
    `).run(
      shortcode !== undefined ? shortcode : existing.shortcode,
      title !== undefined ? title : existing.title,
      content !== undefined ? content : existing.content,
      category !== undefined ? category : existing.category,
      id,
    );

    const updated = db.prepare('SELECT * FROM snippets WHERE id = ?').get(id);

    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id – Delete snippet
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id FROM snippets WHERE id = ?').get(id);
    if (!existing) throw new AppError('Snippet not found', 404);

    db.prepare('DELETE FROM snippets WHERE id = ?').run(id);

    res.json({ success: true, data: { message: 'Snippet deleted' } });
  }),
);

export default router;
