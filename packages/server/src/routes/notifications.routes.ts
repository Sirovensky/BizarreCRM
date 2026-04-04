import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List notifications for current user (paginated, unread first)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const userId = req.user!.id;

    const { total } = db.prepare(
      'SELECT COUNT(*) as total FROM notifications WHERE user_id = ?'
    ).get(userId) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const notifications = db.prepare(`
      SELECT * FROM notifications
      WHERE user_id = ?
      ORDER BY is_read ASC, created_at DESC
      LIMIT ? OFFSET ?
    `).all(userId, pageSize, offset);

    res.json({
      success: true,
      data: {
        notifications,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /unread-count – Count of unread notifications for current user
// ---------------------------------------------------------------------------
router.get(
  '/unread-count',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;

    const { count } = db.prepare(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0'
    ).get(userId) as { count: number };

    res.json({ success: true, data: { count } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id/read – Mark single notification as read
// ---------------------------------------------------------------------------
router.patch(
  '/:id/read',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const userId = req.user!.id;

    const existing = db.prepare(
      'SELECT id FROM notifications WHERE id = ? AND user_id = ?'
    ).get(id, userId);
    if (!existing) throw new AppError('Notification not found', 404);

    db.prepare(
      "UPDATE notifications SET is_read = 1, updated_at = datetime('now') WHERE id = ?"
    ).run(id);

    const updated = db.prepare('SELECT * FROM notifications WHERE id = ?').get(id);

    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// POST /mark-all-read – Mark all as read for current user
// ---------------------------------------------------------------------------
router.post(
  '/mark-all-read',
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;

    const result = db.prepare(
      "UPDATE notifications SET is_read = 1, updated_at = datetime('now') WHERE user_id = ? AND is_read = 0"
    ).run(userId);

    res.json({
      success: true,
      data: { message: 'All notifications marked as read', updated: result.changes },
    });
  }),
);

export default router;
