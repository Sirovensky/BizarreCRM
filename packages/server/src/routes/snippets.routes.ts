import { Router, type Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';
import { validateId } from '../utils/validate.js';

const router = Router();

// BUGHUNT-2026-05-16: snippets are shared CRM-wide canned responses. Reads
// stay open for any staff member, but creates / edits / deletes need a role
// gate so a tech or cashier can't overwrite the manager's templates.
function requireAdminOrManager(req: Request): void {
  const role = (req as any).user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

// ---------------------------------------------------------------------------
// GET / – List all snippets
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const category = (req.query.category as string || '').trim();

    // BUGHUNT-2026-05-17: cap at 1000 — snippets are typically dozens
    // to low-hundreds per shop, but a malicious or buggy import could
    // create millions; the response was loaded entirely into memory
    // and shipped to every snippet-autocomplete dropdown.
    let snippets;
    if (category) {
      snippets = await adb.all(
        'SELECT * FROM snippets WHERE category = ? ORDER BY shortcode LIMIT 1000', category
      );
    } else {
      snippets = await adb.all('SELECT * FROM snippets ORDER BY shortcode LIMIT 1000');
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
    requireAdminOrManager(req);
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
    // SCAN-1095: `category` had no shape/length guard — a hostile caller could
    // store a 1MB string per snippet row. Cap at 64 chars (category is a UI
    // dropdown label in practice), reject non-string types.
    if (category != null && (typeof category !== 'string' || category.length > 64)) {
      throw new AppError('category must be a string of 64 characters or less', 400);
    }

    // BUGHUNT-2026-05-17: atomic insert-if-no-shortcode-conflict. Two
    // concurrent POSTs with the same shortcode previously both passed
    // the SELECT precheck and both INSERTed — the in-message snippet
    // expander then non-deterministically picked one of the duplicates
    // and the other operator's edit silently disappeared from rotation.
    const result = await adb.run(`
      INSERT INTO snippets (shortcode, title, content, category, created_by)
        SELECT ?, ?, ?, ?, ?
         WHERE NOT EXISTS (SELECT 1 FROM snippets WHERE shortcode = ?)
    `, shortcode, title, content, category ?? null, req.user!.id, shortcode);
    if (result.changes === 0) {
      throw new AppError('A snippet with this shortcode already exists', 409);
    }

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
    requireAdminOrManager(req);
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const existing = await adb.get<any>('SELECT * FROM snippets WHERE id = ?', id);
    if (!existing) throw new AppError('Snippet not found', 404);

    const { shortcode, title, content, category } = req.body;

    // Length and format validation
    if (shortcode !== undefined) {
      if (typeof shortcode !== 'string' || !/^[a-zA-Z0-9_\-]+$/.test(shortcode)) {
        throw new AppError('shortcode must match [a-zA-Z0-9_-]+', 400);
      }
      if (shortcode.length > 50) throw new AppError('shortcode must be 50 characters or less', 400);
    }
    if (title !== undefined && title.length > 200) throw new AppError('title must be 200 characters or less', 400);
    if (content !== undefined && content.length > 10000) throw new AppError('content must be 10000 characters or less', 400);
    // SCAN-1095: mirror the POST guard on PUT.
    if (category !== undefined && category != null && (typeof category !== 'string' || category.length > 64)) {
      throw new AppError('category must be a string of 64 characters or less', 400);
    }

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
    requireAdminOrManager(req);
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const existing = await adb.get('SELECT id FROM snippets WHERE id = ?', id);
    if (!existing) throw new AppError('Snippet not found', 404);

    await adb.run('DELETE FROM snippets WHERE id = ?', id);
    audit(req.db, 'snippet_deleted', req.user!.id, req.ip || 'unknown', { snippet_id: id });

    res.json({ success: true, data: { message: 'Snippet deleted' } });
  }),
);

export default router;
