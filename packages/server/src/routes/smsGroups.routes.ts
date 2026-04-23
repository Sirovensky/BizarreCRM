/**
 * SMS Customer Groups routes
 * Mounted at: /api/v1/sms/groups
 * Auth: authMiddleware applied at parent mount — NOT repeated here.
 *
 * Role gates:
 *   GET /                 — any authenticated user
 *   GET /:id              — any authenticated user
 *   POST /                — any authenticated user (rate-limited)
 *   PATCH /:id            — any authenticated user
 *   DELETE /:id           — manager or admin
 *   POST /:id/members     — any authenticated user (static groups only)
 *   DELETE /:id/members/:customerId — any authenticated user (static groups only)
 *   POST /:id/send        — any authenticated user (subject to per-tenant SMS quota)
 *   GET /:id/sends        — any authenticated user
 *
 * Rate limits:
 *   Group creates: 20/hr per user  (category 'sms_group_create')
 *   Group sends: 5/day per group   (category 'sms_group_send')
 *
 * Length caps:
 *   group name ≤ 100, description ≤ 500, send body ≤ 1600
 *   filter_json ≤ 8 KB
 */
import { Router, Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateTextLength,
  validateJsonPayload,
  validateIntegerQuantity,
} from '../utils/validate.js';

const router = Router();
const logger = createLogger('sms-groups');

// ---------------------------------------------------------------------------
// Rate limit constants
// ---------------------------------------------------------------------------
const RL_CREATE_MAX = 20;
const RL_CREATE_WINDOW_MS = 3_600_000;     // 1 hour
const RL_SEND_MAX = 5;
const RL_SEND_WINDOW_MS = 86_400_000;      // 24 hours

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireManagerOrAdmin(req: Request): void {
  if (!req.user) throw new AppError('Not authenticated', 401);
  if (req.user.role !== 'admin' && req.user.role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

function validateId(raw: unknown, field = 'id'): number {
  const s = typeof raw === 'string' ? raw : String(raw ?? '');
  const n = parseInt(s, 10);
  if (!Number.isInteger(n) || n < 1) throw new AppError(`${field} must be a positive integer`, 400);
  return n;
}

function serializeFilterJson(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  let parsed: unknown;
  if (typeof raw === 'string') {
    try { parsed = JSON.parse(raw); } catch {
      throw new AppError('filter_json must be valid JSON', 400);
    }
  } else {
    parsed = raw;
  }
  return validateJsonPayload(parsed, 'filter_json', 8_192);
}

// ---------------------------------------------------------------------------
// GET / — list groups with member_count_cache
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const rows = await adb.all<Record<string, unknown>>(
      `SELECT id, name, description, is_dynamic, member_count_cache,
              created_by_user_id, created_at, updated_at
         FROM sms_customer_groups
        ORDER BY name ASC`,
    );
    res.json({ success: true, data: rows });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id — detail + paginated members
// ---------------------------------------------------------------------------

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id);
    const page = Math.max(1, parseInt((req.query.page as string) || '1', 10));
    const limit = Math.min(200, Math.max(1, parseInt((req.query.limit as string) || '50', 10)));
    const offset = (page - 1) * limit;

    const group = await adb.get<Record<string, unknown>>(
      `SELECT id, name, description, filter_json, is_dynamic, member_count_cache,
              created_by_user_id, created_at, updated_at
         FROM sms_customer_groups
        WHERE id = ?`,
      id,
    );
    if (!group) throw new AppError('Group not found', 404);

    const [members, countRow] = await Promise.all([
      adb.all<Record<string, unknown>>(
        `SELECT m.id AS member_id, m.customer_id, m.added_at,
                c.first_name, c.last_name, c.phone, c.mobile, c.email
           FROM sms_customer_group_members m
           JOIN customers c ON c.id = m.customer_id
          WHERE m.group_id = ?
          ORDER BY m.added_at DESC
          LIMIT ? OFFSET ?`,
        id, limit, offset,
      ),
      adb.get<{ total: number }>(
        'SELECT COUNT(*) AS total FROM sms_customer_group_members WHERE group_id = ?',
        id,
      ),
    ]);

    res.json({
      success: true,
      data: {
        group,
        members,
        pagination: {
          page,
          limit,
          total: countRow?.total ?? 0,
          pages: Math.ceil((countRow?.total ?? 0) / limit),
        },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST / — create group (any authed user, rate-limited)
// ---------------------------------------------------------------------------

router.post(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;

    const rlKey = `${(req as any).tenantSlug || 'default'}:${userId}`;
    const rl = consumeWindowRate(db, 'sms_group_create', rlKey, RL_CREATE_MAX, RL_CREATE_WINDOW_MS);
    if (!rl.allowed) {
      throw new AppError(`Too many groups created. Try again in ${rl.retryAfterSeconds}s.`, 429);
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const name = validateRequiredString(body.name, 'name', 100);
    const description = validateTextLength(
      typeof body.description === 'string' ? body.description : undefined,
      500,
      'description',
    ) || null;
    const filter_json = serializeFilterJson(body.filter_json);
    const is_dynamic = body.is_dynamic ? 1 : 0;

    const result = await adb.run(
      `INSERT INTO sms_customer_groups
         (name, description, filter_json, is_dynamic, member_count_cache,
          created_by_user_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, 0, ?, datetime('now'), datetime('now'))`,
      name, description, filter_json, is_dynamic, userId,
    );

    const newId = result.lastInsertRowid;
    logger.info('sms group created', { group_id: newId, name, userId });

    const created = await adb.get<Record<string, unknown>>(
      'SELECT * FROM sms_customer_groups WHERE id = ?',
      newId,
    );
    res.status(201).json({ success: true, data: created });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id — partial update (any authed user)
// ---------------------------------------------------------------------------

router.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id);

    const existing = await adb.get<{ id: number }>(
      'SELECT id FROM sms_customer_groups WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Group not found', 404);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const fields: string[] = [];
    const params: unknown[] = [];

    if (body.name !== undefined) {
      fields.push('name = ?');
      params.push(validateRequiredString(body.name, 'name', 100));
    }
    if (body.description !== undefined) {
      fields.push('description = ?');
      params.push(
        body.description === null
          ? null
          : validateTextLength(String(body.description), 500, 'description') || null,
      );
    }
    if (body.filter_json !== undefined) {
      fields.push('filter_json = ?');
      params.push(serializeFilterJson(body.filter_json));
    }
    if (body.is_dynamic !== undefined) {
      fields.push('is_dynamic = ?');
      params.push(body.is_dynamic ? 1 : 0);
    }

    if (fields.length === 0) throw new AppError('No fields to update', 400);

    fields.push("updated_at = datetime('now')");
    params.push(id);

    await adb.run(
      `UPDATE sms_customer_groups SET ${fields.join(', ')} WHERE id = ?`,
      ...params,
    );

    const updated = await adb.get<Record<string, unknown>>(
      'SELECT * FROM sms_customer_groups WHERE id = ?',
      id,
    );
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id — hard delete (cascades members) (manager+)
// ---------------------------------------------------------------------------

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);

    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const id = validateId(req.params.id);

    const existing = await adb.get<{ id: number; name: string }>(
      'SELECT id, name FROM sms_customer_groups WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Group not found', 404);

    await adb.run('DELETE FROM sms_customer_groups WHERE id = ?', id);

    audit(db, 'sms_group_deleted', userId, req.ip || 'unknown', {
      group_id: id,
      name: existing.name,
    });

    res.json({ success: true, data: { id } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/members — batch add members (static groups only)
// ---------------------------------------------------------------------------

router.post(
  '/:id/members',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id);

    const group = await adb.get<{ id: number; is_dynamic: number }>(
      'SELECT id, is_dynamic FROM sms_customer_groups WHERE id = ?',
      id,
    );
    if (!group) throw new AppError('Group not found', 404);
    if (group.is_dynamic) throw new AppError('Cannot manually add members to a dynamic group', 400);

    const body = (req.body ?? {}) as Record<string, unknown>;
    if (!Array.isArray(body.customer_ids) || body.customer_ids.length === 0) {
      throw new AppError('customer_ids must be a non-empty array', 400);
    }
    if (body.customer_ids.length > 500) {
      throw new AppError('Cannot add more than 500 members in a single request', 400);
    }

    // Validate each id is a positive integer
    const customerIds: number[] = body.customer_ids.map((v: unknown, i: number) => {
      const n = typeof v === 'number' ? v : parseInt(String(v), 10);
      if (!Number.isInteger(n) || n < 1) {
        throw new AppError(`customer_ids[${i}] must be a positive integer`, 400);
      }
      return n;
    });

    // Verify customers exist (batch check)
    const placeholders = customerIds.map(() => '?').join(',');
    const existingCustomers = await adb.all<{ id: number }>(
      `SELECT id FROM customers WHERE id IN (${placeholders}) AND is_deleted = 0`,
      ...customerIds,
    );
    const validIds = new Set(existingCustomers.map((c) => c.id));

    let added = 0;
    let skipped = 0;

    for (const custId of customerIds) {
      if (!validIds.has(custId)) {
        skipped++;
        continue;
      }
      try {
        await adb.run(
          `INSERT OR IGNORE INTO sms_customer_group_members
             (group_id, customer_id, added_at)
           VALUES (?, ?, datetime('now'))`,
          id, custId,
        );
        added++;
      } catch {
        skipped++;
      }
    }

    // Refresh member_count_cache
    const countRow = await adb.get<{ total: number }>(
      'SELECT COUNT(*) AS total FROM sms_customer_group_members WHERE group_id = ?',
      id,
    );
    await adb.run(
      `UPDATE sms_customer_groups SET member_count_cache = ?, updated_at = datetime('now') WHERE id = ?`,
      countRow?.total ?? 0, id,
    );

    res.json({ success: true, data: { group_id: id, added, skipped } });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id/members/:customerId — remove one member (static groups only)
// ---------------------------------------------------------------------------

router.delete(
  '/:id/members/:customerId',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id);
    const customerId = validateId(req.params.customerId, 'customerId');

    const group = await adb.get<{ id: number; is_dynamic: number }>(
      'SELECT id, is_dynamic FROM sms_customer_groups WHERE id = ?',
      id,
    );
    if (!group) throw new AppError('Group not found', 404);
    if (group.is_dynamic) throw new AppError('Cannot remove members from a dynamic group', 400);

    await adb.run(
      'DELETE FROM sms_customer_group_members WHERE group_id = ? AND customer_id = ?',
      id, customerId,
    );

    // Refresh member_count_cache
    const countRow = await adb.get<{ total: number }>(
      'SELECT COUNT(*) AS total FROM sms_customer_group_members WHERE group_id = ?',
      id,
    );
    await adb.run(
      `UPDATE sms_customer_groups SET member_count_cache = ?, updated_at = datetime('now') WHERE id = ?`,
      countRow?.total ?? 0, id,
    );

    res.json({ success: true, data: { group_id: id, customer_id: customerId, removed: true } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/send — dispatch to all current group members
// ---------------------------------------------------------------------------

router.post(
  '/:id/send',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const id = validateId(req.params.id);

    const group = await adb.get<{ id: number; name: string; is_dynamic: number; filter_json: string | null }>(
      'SELECT id, name, is_dynamic, filter_json FROM sms_customer_groups WHERE id = ?',
      id,
    );
    if (!group) throw new AppError('Group not found', 404);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const msgBody = validateRequiredString(body.body, 'body', 1600);

    // Per-group daily send limit: 5/day
    const rlResult = consumeWindowRate(db, 'sms_group_send', String(id), RL_SEND_MAX, RL_SEND_WINDOW_MS);
    if (!rlResult.allowed) {
      throw new AppError(
        `Group send limit reached (${RL_SEND_MAX}/day). Try again in ${rlResult.retryAfterSeconds}s.`,
        429,
      );
    }

    // Count recipients
    const countRow = await adb.get<{ total: number }>(
      `SELECT COUNT(*) AS total
         FROM sms_customer_group_members m
         JOIN customers c ON c.id = m.customer_id
        WHERE m.group_id = ? AND c.is_deleted = 0
          AND COALESCE(c.sms_opt_in, 1) = 1`,
      id,
    );
    const recipientCount = countRow?.total ?? 0;

    // Create sms_group_sends row with status='queued'
    // Actual dispatch is wired in next wave via the queue processor.
    const insertResult = await adb.run(
      `INSERT INTO sms_group_sends
         (group_id, body, sender_user_id, recipient_count, sent_count, failed_count,
          started_at, status)
       VALUES (?, ?, ?, ?, 0, 0, datetime('now'), 'queued')`,
      id, msgBody, userId, recipientCount,
    );

    const sendId = insertResult.lastInsertRowid;

    audit(db, 'sms_group_send_dispatched', userId, req.ip || 'unknown', {
      send_id: sendId,
      group_id: id,
      group_name: group.name,
      recipient_count: recipientCount,
      body_length: msgBody.length,
    });

    logger.info('sms group send queued', {
      send_id: sendId,
      group_id: id,
      recipient_count: recipientCount,
      userId,
    });

    const send = await adb.get<Record<string, unknown>>(
      'SELECT * FROM sms_group_sends WHERE id = ?',
      sendId,
    );
    res.status(202).json({ success: true, data: send });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/sends — list past group sends + status
// ---------------------------------------------------------------------------

router.get(
  '/:id/sends',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id);
    const limit = Math.min(100, Math.max(1, parseInt((req.query.limit as string) || '20', 10)));

    const group = await adb.get<{ id: number }>(
      'SELECT id FROM sms_customer_groups WHERE id = ?',
      id,
    );
    if (!group) throw new AppError('Group not found', 404);

    const sends = await adb.all<Record<string, unknown>>(
      `SELECT gs.id, gs.group_id, gs.body, gs.sender_user_id,
              u.first_name || ' ' || u.last_name AS sender_name,
              gs.recipient_count, gs.sent_count, gs.failed_count,
              gs.started_at, gs.completed_at, gs.status
         FROM sms_group_sends gs
         LEFT JOIN users u ON u.id = gs.sender_user_id
        WHERE gs.group_id = ?
        ORDER BY gs.started_at DESC
        LIMIT ?`,
      id, limit,
    );

    res.json({ success: true, data: sends });
  }),
);

export default router;
