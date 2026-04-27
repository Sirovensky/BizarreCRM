/**
 * Email thread routes — WEB-S6-017.
 *
 * Mounted at /api/v1/email.
 *
 * This is a STUB implementation. Full SMTP receiving infrastructure (Postfix
 * inbound relay, MX records, webhook parse) does not exist yet. The routes
 * return real data from an `email_threads` table if it exists, and an empty
 * list otherwise — so the CommunicationPage email tab shows an appropriate
 * empty state without crashing. When the email infra is wired the same
 * endpoints become real with no UI changes needed.
 *
 * Feature-flag: if `store_config.email_inbox_enabled` is not '1', the list
 * endpoint returns `{ threads: [], enabled: false }` so the frontend can gate
 * the tab behind a visible "not configured" notice rather than showing
 * a plain empty list.
 */
import { Router } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();
const logger = createLogger('email.routes');

type AnyRow = Record<string, any>;

// ---------------------------------------------------------------------------
// GET /email/threads — List email threads (newest first)
// ---------------------------------------------------------------------------
router.get(
  '/threads',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;

    // Feature flag: check if email inbox is enabled.
    let enabled = false;
    try {
      const flagRow = await adb.get<{ value: string }>(
        "SELECT value FROM store_config WHERE key = 'email_inbox_enabled'",
      );
      enabled = flagRow?.value === '1' || flagRow?.value === 'true';
    } catch {
      // store_config missing in test envs — treat as disabled.
    }

    if (!enabled) {
      res.json({ success: true, data: { threads: [], enabled: false } });
      return;
    }

    // Check if email_threads table exists (graceful degradation while infra is
    // being built — don't hard-fail if the migration hasn't landed yet).
    let tableExists = false;
    try {
      await adb.get("SELECT 1 FROM email_threads LIMIT 1");
      tableExists = true;
    } catch {
      tableExists = false;
    }

    if (!tableExists) {
      res.json({ success: true, data: { threads: [], enabled: true } });
      return;
    }

    const page = Math.max(1, parseInt(String(req.query.page ?? '1'), 10));
    const pageSize = Math.min(50, Math.max(1, parseInt(String(req.query.pagesize ?? '25'), 10)));
    const offset = (page - 1) * pageSize;

    const threads = await adb.all<AnyRow>(
      `SELECT t.*,
              c.first_name, c.last_name
       FROM email_threads t
       LEFT JOIN customers c ON c.id = t.customer_id
       ORDER BY t.last_message_at DESC
       LIMIT ? OFFSET ?`,
      pageSize, offset,
    );

    const countRow = await adb.get<{ total: number }>(
      'SELECT COUNT(*) AS total FROM email_threads',
    );
    const total = countRow?.total ?? 0;

    res.json({
      success: true,
      data: {
        threads,
        enabled: true,
        pagination: {
          page,
          per_page: pageSize,
          total,
          total_pages: Math.ceil(total / pageSize),
        },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /email/threads/:id/messages — Messages in a thread
// ---------------------------------------------------------------------------
router.get(
  '/threads/:id/messages',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const threadId = parseInt(req.params.id, 10);
    if (!threadId || isNaN(threadId)) {
      res.status(400).json({ success: false, error: 'Invalid thread id' });
      return;
    }

    let messages: AnyRow[] = [];
    try {
      messages = await adb.all<AnyRow>(
        'SELECT * FROM email_messages WHERE thread_id = ? ORDER BY sent_at ASC',
        threadId,
      );
    } catch {
      // Table doesn't exist yet — return empty array.
    }

    res.json({ success: true, data: messages });
  }),
);

export default router;
