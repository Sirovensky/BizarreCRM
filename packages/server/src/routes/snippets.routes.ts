import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List all snippets
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const category = (req.query.category as string || '').trim();

    let snippets;
    if (category) {
      snippets = await adb.all(
        'SELECT * FROM snippets WHERE category = ? ORDER BY shortcode', category
      );
    } else {
      snippets = await adb.all('SELECT * FROM snippets ORDER BY shortcode');
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
    const adb = req.asyncDb;
    const { shortcode, title, content, category } = req.body;

    // @audit-fixed: §37 — first three throws were missing the explicit 400
    // status, so they fell through to the generic 500 default. Add 400 + bound
    // shortcode shape so it can't contain whitespace or shell tokens.
    if (!shortcode) throw new AppError('shortcode is required', 400);
    if (!title) throw new AppError('title is required', 400);
    if (!content) throw new AppError('content is required', 400);
    if (typeof shortcode !== 'string' || shortcode.length > 50) throw new AppError('shortcode must be 50 characters or less', 400);
    if (!/^[a-zA-Z0-9_\-]+$/.test(shortcode)) throw new AppError('shortcode may only contain letters, digits, underscore, or dash', 400);
    if (typeof title !== 'string' || title.length > 200) throw new AppError('title must be 200 characters or less', 400);
    if (typeof content !== 'string' || content.length > 10000) throw new AppError('content must be 10000 characters or less', 400);

    // Check uniqueness
    const existing = await adb.get('SELECT id FROM snippets WHERE shortcode = ?', shortcode);
    if (existing) throw new AppError('A snippet with this shortcode already exists', 409);

    const result = await adb.run(`
      INSERT INTO snippets (shortcode, title, content, category, created_by)
      VALUES (?, ?, ?, ?, ?)
    `, shortcode, title, content, category ?? null, req.user!.id);

    const snippet = await adb.get('SELECT * FROM snippets WHERE id = ?', result.lastInsertRowid);
    audit(req.db, 'snippet_created', req.user!.id, req.ip || 'unknown', { snippet_id: Number(result.lastInsertRowid), shortcode, title });

    res.status(201).json({ success: true, data: snippet });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update snippet
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT * FROM snippets WHERE id = ?', id);
    if (!existing) throw new AppError('Snippet not found', 404);

    const { shortcode, title, content, category } = req.body;

    // Length validation
    if (shortcode !== undefined && shortcode.length > 50) throw new AppError('shortcode must be 50 characters or less', 400);
    if (title !== undefined && title.length > 200) throw new AppError('title must be 200 characters or less', 400);
    if (content !== undefined && content.length > 10000) throw new AppError('content must be 10000 characters or less', 400);

    // Check shortcode uniqueness if changing
    if (shortcode && shortcode !== existing.shortcode) {
      const dup = await adb.get('SELECT id FROM snippets WHERE shortcode = ? AND id != ?', shortcode, id);
      if (dup) throw new AppError('A snippet with this shortcode already exists', 409);
    }

    await adb.run(`
      UPDATE snippets SET
        shortcode = ?, title = ?, content = ?, category = ?, updated_at = datetime('now')
      WHERE id = ?
    `,
      shortcode !== undefined ? shortcode : existing.shortcode,
      title !== undefined ? title : existing.title,
      content !== undefined ? content : existing.content,
      category !== undefined ? category : existing.category,
      id,
    );

    const updated = await adb.get('SELECT * FROM snippets WHERE id = ?', id);
    audit(req.db, 'snippet_updated', req.user!.id, req.ip || 'unknown', { snippet_id: id });

    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id – Delete snippet
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get('SELECT id FROM snippets WHERE id = ?', id);
    if (!existing) throw new AppError('Snippet not found', 404);

    await adb.run('DELETE FROM snippets WHERE id = ?', id);
    audit(req.db, 'snippet_deleted', req.user!.id, req.ip || 'unknown', { snippet_id: id });

    res.json({ success: true, data: { message: 'Snippet deleted' } });
  }),
);

export default router;
