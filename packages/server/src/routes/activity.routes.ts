/**
 * Activity Feed — /api/v1/activity
 *
 * SCAN-488
 * Auth:  authMiddleware applied at parent mount (index.ts) — not re-added here.
 * Authz: non-manager roles can only see their own events (actor_user_id forced to self).
 *        manager / admin / superadmin may filter by any actor_user_id.
 * Pagination: cursor-based (monotonic id, newest-first).
 */
import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('activity');

// Roles that may query other users' activity.
const MANAGER_ROLES = new Set(['admin', 'manager', 'superadmin']);

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

/** Parse a positive integer from a query param. Returns null on failure. */
function parsePositiveInt(raw: unknown): number | null {
  if (raw === undefined || raw === null || raw === '') return null;
  const n = Number(raw);
  return Number.isInteger(n) && n > 0 ? n : null;
}

// ---------------------------------------------------------------------------
// GET /me — shortcut: current user's own activity
// ---------------------------------------------------------------------------
router.get(
  '/me',
  asyncHandler(async (req, res) => {
    // Force actor_user_id to self without mutating req.query.
    return listActivity(req, res, req.user!.id);
  }),
);

// ---------------------------------------------------------------------------
// GET / — paginated activity feed
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => listActivity(req, res, null)),
);

/**
 * @param actorOverride - when non-null, bypasses query param parsing for
 *   actor_user_id (used by the /me shortcut to avoid req.query mutation).
 */
async function listActivity(req: Request, res: Response, actorOverride: number | null): Promise<void> {
  const adb = req.asyncDb;
  const user = req.user!;
  const isManager = MANAGER_ROLES.has(user.role);

  // Parse limit
  const rawLimit = req.query.limit;
  let limit = DEFAULT_LIMIT;
  if (rawLimit !== undefined && rawLimit !== '') {
    const parsed = parsePositiveInt(rawLimit);
    if (parsed === null) throw new AppError('limit must be a positive integer', 400);
    limit = Math.min(parsed, MAX_LIMIT);
  }

  // Parse cursor (last id from previous page)
  const rawCursor = req.query.cursor;
  let cursor: number | null = null;
  if (rawCursor !== undefined && rawCursor !== '') {
    cursor = parsePositiveInt(rawCursor);
    if (cursor === null) throw new AppError('cursor must be a positive integer', 400);
  }

  // Parse entity_kind filter (free text, parameterized)
  const entityKind = typeof req.query.entity_kind === 'string' && req.query.entity_kind.trim()
    ? req.query.entity_kind.trim()
    : null;

  // Parse actor_user_id filter (actorOverride takes precedence over query param)
  let actorUserId: number | null = actorOverride;
  if (actorOverride === null) {
    if (req.query.actor_user_id !== undefined && req.query.actor_user_id !== '') {
      const parsed = parsePositiveInt(req.query.actor_user_id);
      if (parsed === null) throw new AppError('actor_user_id must be a positive integer', 400);
      actorUserId = parsed;
    }
  }

  // AUTHZ: non-manager can only see own events
  if (!isManager) {
    if (actorUserId !== null && actorUserId !== user.id) {
      throw new AppError('Insufficient permissions to view other users\' activity', 403);
    }
    actorUserId = user.id;
  }

  // Build WHERE clauses
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (cursor !== null) {
    conditions.push('e.id < ?');
    params.push(cursor);
  }
  if (actorUserId !== null) {
    conditions.push('e.actor_user_id = ?');
    params.push(actorUserId);
  }
  if (entityKind !== null) {
    conditions.push('e.entity_kind = ?');
    params.push(entityKind);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const events = await adb.all<{
    id: number;
    actor_user_id: number | null;
    entity_kind: string;
    entity_id: number | null;
    action: string;
    metadata_json: string | null;
    created_at: string;
    actor_first_name: string | null;
    actor_last_name: string | null;
  }>(
    `SELECT e.id, e.actor_user_id, e.entity_kind, e.entity_id, e.action,
            e.metadata_json, e.created_at,
            u.first_name AS actor_first_name, u.last_name AS actor_last_name
     FROM activity_events e
     LEFT JOIN users u ON u.id = e.actor_user_id
     ${whereClause}
     ORDER BY e.id DESC
     LIMIT ?`,
    ...params,
    limit + 1, // fetch one extra to determine if there's a next page
  );

  // Determine next cursor
  const hasMore = events.length > limit;
  const pageEvents = hasMore ? events.slice(0, limit) : events;
  const nextCursor = hasMore ? String(pageEvents[pageEvents.length - 1].id) : null;

  // Parse metadata_json inline — surface as object, never throw
  const normalized = pageEvents.map((e) => {
    let metadata: Record<string, unknown> | null = null;
    if (e.metadata_json) {
      try {
        metadata = JSON.parse(e.metadata_json);
      } catch {
        logger.warn('activity: unparseable metadata_json', { id: e.id });
      }
    }
    const { metadata_json: _dropped, ...rest } = e;
    void _dropped;
    return { ...rest, metadata };
  });

  res.json({
    success: true,
    data: {
      events: normalized,
      next_cursor: nextCursor,
    },
  });
}

export default router;
