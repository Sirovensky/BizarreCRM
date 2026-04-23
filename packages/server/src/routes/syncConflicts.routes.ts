/**
 * Sync Conflict Resolution routes — mount at /api/v1/sync/conflicts
 *
 * SCAN-473: Mobile sync conflict queue (android §20.3).
 *
 * authMiddleware is applied at the parent mount point in index.ts — do NOT
 * re-add it here.
 *
 * IMPORTANT — DECLARATIVE RESOLUTION ONLY:
 * These endpoints record resolution decisions for audit purposes. They do NOT
 * write the chosen version back to the entity table (ticket, customer, etc.).
 * The client is responsible for replaying the chosen version via the regular
 * entity endpoints (e.g. PUT /api/v1/tickets/:id) after calling resolve.
 *
 * Registration snippet (add to index.ts beside other route mounts):
 * ```ts
 * import syncConflictsRoutes from './routes/syncConflicts.routes.js';
 * app.use('/api/v1/sync/conflicts', authMiddleware, syncConflictsRoutes);
 * ```
 *
 * Role matrix:
 *   POST /              — any authenticated user (mobile client reports a conflict)
 *   GET /               — manager or admin
 *   GET /:id            — manager or admin
 *   POST /:id/resolve   — manager or admin
 *   POST /:id/reject    — manager or admin
 *   POST /:id/defer     — manager or admin
 *   POST /bulk-resolve  — manager or admin
 */

import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { parsePage, parsePageSize } from '../utils/pagination.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('syncConflicts.routes');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Maximum total size of a single conflict_json field (client or server side). */
const MAX_VERSION_JSON_BYTES = 32 * 1024; // 32 KB each

/** Maximum total size of the combined conflict JSON payload (both sides). */
const MAX_CONFLICT_PAYLOAD_BYTES = 64 * 1024; // 64 KB

/** Max length for free-text notes fields. */
const MAX_NOTES_LEN = 2000;

/** Allowed values for conflict_type column. */
const CONFLICT_TYPES = [
  'concurrent_update',
  'stale_write',
  'duplicate_create',
  'deleted_remote',
] as const;
type ConflictType = typeof CONFLICT_TYPES[number];

/** Allowed values for status column. */
const CONFLICT_STATUSES = ['pending', 'resolved', 'rejected', 'deferred'] as const;
type ConflictStatus = typeof CONFLICT_STATUSES[number];

/** Allowed values for resolution column. */
const RESOLUTIONS = ['keep_client', 'keep_server', 'merge', 'manual', 'rejected'] as const;
type Resolution = typeof RESOLUTIONS[number];

/** Allowed values for reporter_platform. */
const PLATFORMS = ['android', 'ios', 'web'] as const;

/** Rate-limit category for conflict reports (60/min/user). */
const REPORT_RATE_CATEGORY = 'sync_conflict_report';
const REPORT_RATE_MAX = 60;
const REPORT_RATE_WINDOW_MS = 60_000;

/** Max ids in a single bulk-resolve call. */
const BULK_RESOLVE_MAX_IDS = 100;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

/** Throw 403 unless the request user is manager or admin. */
function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

/** Parse and validate a positive integer route/query parameter. */
function parseId(raw: unknown, label = 'id'): number {
  const id = parseInt(String(raw), 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError(`Invalid ${label}`, 400);
  return id;
}

/** Validate a string is non-empty and within the given length. */
function validateString(value: unknown, field: string, maxLen: number): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new AppError(`${field} is required`, 400);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${field} must be at most ${maxLen} characters`, 400);
  }
  return trimmed;
}

/** Validate a string enum value. */
function validateEnum<T extends string>(
  value: unknown,
  field: string,
  allowed: readonly T[],
): T {
  if (!allowed.includes(value as T)) {
    throw new AppError(
      `${field} must be one of: ${allowed.join(', ')}`,
      400,
    );
  }
  return value as T;
}

/**
 * Validate a version JSON blob:
 * - Must be a non-empty string
 * - Must be valid JSON
 * - Must not exceed MAX_VERSION_JSON_BYTES
 */
function validateVersionJson(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new AppError(`${field} is required`, 400);
  }
  const trimmed = value.trim();
  if (Buffer.byteLength(trimmed, 'utf8') > MAX_VERSION_JSON_BYTES) {
    throw new AppError(
      `${field} must not exceed ${MAX_VERSION_JSON_BYTES / 1024} KB`,
      400,
    );
  }
  try {
    JSON.parse(trimmed);
  } catch {
    throw new AppError(`${field} must be valid JSON`, 400);
  }
  return trimmed;
}

// ---------------------------------------------------------------------------
// POST / — Report a conflict (any authed user, rate-limited 60/min/user)
// ---------------------------------------------------------------------------

router.post(
  '/',
  asyncHandler(async (req: Request, res: Response) => {
    const userId = req.user!.id;
    const adb = req.asyncDb;
    const ip = req.socket.remoteAddress ?? 'unknown';

    // Rate-limit: 60 reports per user per minute to prevent log flooding
    const rateResult = consumeWindowRate(
      req.db,
      REPORT_RATE_CATEGORY,
      String(userId),
      REPORT_RATE_MAX,
      REPORT_RATE_WINDOW_MS,
    );
    if (!rateResult.allowed) {
      res.setHeader('Retry-After', String(rateResult.retryAfterSeconds));
      throw new AppError(
        `Too many conflict reports. Retry after ${rateResult.retryAfterSeconds}s`,
        429,
      );
    }

    const {
      entity_kind,
      entity_id,
      conflict_type,
      client_version_json,
      server_version_json,
      device_id,
      platform,
    } = req.body as Record<string, unknown>;

    // Validate inputs
    const safeEntityKind = validateString(entity_kind, 'entity_kind', 100);
    const safeEntityId = parseId(entity_id, 'entity_id');
    const safeConflictType = validateEnum(conflict_type, 'conflict_type', CONFLICT_TYPES);
    const safeClientJson = validateVersionJson(client_version_json, 'client_version_json');
    const safeServerJson = validateVersionJson(server_version_json, 'server_version_json');

    // Combined payload size guard
    const combinedBytes = Buffer.byteLength(safeClientJson, 'utf8')
      + Buffer.byteLength(safeServerJson, 'utf8');
    if (combinedBytes > MAX_CONFLICT_PAYLOAD_BYTES) {
      throw new AppError(
        `Combined conflict JSON must not exceed ${MAX_CONFLICT_PAYLOAD_BYTES / 1024} KB`,
        400,
      );
    }

    // Optional fields
    const safeDeviceId =
      typeof device_id === 'string' && device_id.trim().length > 0
        ? device_id.trim().slice(0, 200)
        : null;

    const safePlatform =
      typeof platform === 'string' && (PLATFORMS as readonly string[]).includes(platform)
        ? platform as typeof PLATFORMS[number]
        : null;

    const result = await adb.run(
      `INSERT INTO sync_conflicts
         (entity_kind, entity_id, conflict_type,
          client_version_json, server_version_json,
          reporter_user_id, reporter_device_id, reporter_platform,
          reported_at, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
      safeEntityKind,
      safeEntityId,
      safeConflictType,
      safeClientJson,
      safeServerJson,
      userId,
      safeDeviceId,
      safePlatform,
      now(),
    );

    const id = result.lastInsertRowid;

    logger.info('Sync conflict reported', {
      id,
      entity_kind: safeEntityKind,
      entity_id: safeEntityId,
      conflict_type: safeConflictType,
      reporter_user_id: userId,
    });

    audit(req.db, 'sync_conflict.reported', userId, ip, {
      id,
      entity_kind: safeEntityKind,
      entity_id: safeEntityId,
      conflict_type: safeConflictType,
    });

    res.status(202).json({ success: true, data: { id, status: 'pending' } });
  }),
);

// ---------------------------------------------------------------------------
// GET / — List conflicts (manager+, paginated)
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req: Request, res: Response) => {
    requireManagerOrAdmin(req);

    const adb = req.asyncDb;
    const page = parsePage(req.query.page);
    const perPage = parsePageSize(req.query.pagesize, 25);
    const offset = (page - 1) * perPage;

    // Optional filters
    const statusFilter =
      typeof req.query.status === 'string' &&
      (CONFLICT_STATUSES as readonly string[]).includes(req.query.status)
        ? req.query.status
        : null;
    const entityKindFilter =
      typeof req.query.entity_kind === 'string' && req.query.entity_kind.trim().length > 0
        ? req.query.entity_kind.trim().slice(0, 100)
        : null;

    // Build WHERE clauses without string interpolation of user input
    const conditions: string[] = [];
    const params: unknown[] = [];

    if (statusFilter) {
      conditions.push('sc.status = ?');
      params.push(statusFilter);
    }
    if (entityKindFilter) {
      conditions.push('sc.entity_kind = ?');
      params.push(entityKindFilter);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const [totalRow, rows] = await Promise.all([
      adb.get<{ c: number }>(
        `SELECT COUNT(*) AS c FROM sync_conflicts sc ${whereClause}`,
        ...params,
      ),
      adb.all<Record<string, unknown>>(
        `SELECT sc.*,
                r.first_name AS reporter_first_name,
                r.last_name  AS reporter_last_name,
                rv.first_name AS resolver_first_name,
                rv.last_name  AS resolver_last_name
           FROM sync_conflicts sc
           LEFT JOIN users r  ON r.id = sc.reporter_user_id
           LEFT JOIN users rv ON rv.id = sc.resolved_by_user_id
         ${whereClause}
          ORDER BY sc.reported_at DESC
          LIMIT ? OFFSET ?`,
        ...params,
        perPage,
        offset,
      ),
    ]);

    const total = totalRow?.c ?? 0;

    res.json({
      success: true,
      data: rows,
      meta: { total, page, pageSize: perPage, pages: Math.ceil(total / perPage) },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id — Get single conflict detail (manager+)
// ---------------------------------------------------------------------------

router.get(
  '/:id',
  asyncHandler(async (req: Request, res: Response) => {
    requireManagerOrAdmin(req);

    const id = parseId(req.params.id, 'conflict id');
    const adb = req.asyncDb;

    const row = await adb.get<Record<string, unknown>>(
      `SELECT sc.*,
              r.first_name  AS reporter_first_name,
              r.last_name   AS reporter_last_name,
              rv.first_name AS resolver_first_name,
              rv.last_name  AS resolver_last_name
         FROM sync_conflicts sc
         LEFT JOIN users r  ON r.id = sc.reporter_user_id
         LEFT JOIN users rv ON rv.id = sc.resolved_by_user_id
        WHERE sc.id = ?`,
      id,
    );

    if (!row) throw new AppError('Conflict not found', 404);

    res.json({ success: true, data: row });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/resolve — Resolve a conflict (manager+)
// ---------------------------------------------------------------------------

router.post(
  '/:id/resolve',
  asyncHandler(async (req: Request, res: Response) => {
    requireManagerOrAdmin(req);

    const id = parseId(req.params.id, 'conflict id');
    const userId = req.user!.id;
    const adb = req.asyncDb;
    const ip = (req.headers['x-forwarded-for'] as string | undefined)?.split(',')[0]?.trim()
      ?? req.socket.remoteAddress
      ?? 'unknown';

    const { resolution, resolution_notes } = req.body as Record<string, unknown>;

    const safeResolution = validateEnum(resolution, 'resolution', RESOLUTIONS);
    const safeNotes =
      typeof resolution_notes === 'string' && resolution_notes.trim().length > 0
        ? resolution_notes.trim().slice(0, MAX_NOTES_LEN)
        : null;

    // Verify conflict exists and is actionable
    const existing = await adb.get<{ id: number; status: ConflictStatus; entity_kind: string; entity_id: number }>(
      'SELECT id, status, entity_kind, entity_id FROM sync_conflicts WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Conflict not found', 404);
    if (existing.status === 'resolved') throw new AppError('Conflict is already resolved', 409);

    const resolvedAt = now();
    await adb.run(
      `UPDATE sync_conflicts
          SET status = 'resolved',
              resolution = ?,
              resolution_notes = ?,
              resolved_by_user_id = ?,
              resolved_at = ?
        WHERE id = ?`,
      safeResolution,
      safeNotes,
      userId,
      resolvedAt,
      id,
    );

    audit(req.db, 'sync_conflict.resolved', userId, ip, {
      conflict_id: id,
      entity_kind: existing.entity_kind,
      entity_id: existing.entity_id,
      resolution: safeResolution,
      notes: safeNotes,
    });

    logger.info('Sync conflict resolved', {
      conflict_id: id,
      resolution: safeResolution,
      resolved_by: userId,
    });

    res.json({
      success: true,
      data: {
        id,
        status: 'resolved',
        resolution: safeResolution,
        resolved_by_user_id: userId,
        resolved_at: resolvedAt,
        // IMPORTANT: resolution is declarative only — the client must replay
        // the chosen version via the regular entity endpoints.
        _note: 'Resolution persists the decision for audit; the client is responsible for replaying the chosen version via the regular entity endpoints.',
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/reject — Reject a conflict (manager+)
// ---------------------------------------------------------------------------

router.post(
  '/:id/reject',
  asyncHandler(async (req: Request, res: Response) => {
    requireManagerOrAdmin(req);

    const id = parseId(req.params.id, 'conflict id');
    const userId = req.user!.id;
    const adb = req.asyncDb;
    const ip = (req.headers['x-forwarded-for'] as string | undefined)?.split(',')[0]?.trim()
      ?? req.socket.remoteAddress
      ?? 'unknown';

    const { notes } = req.body as Record<string, unknown>;

    const safeNotes =
      typeof notes === 'string' && notes.trim().length > 0
        ? notes.trim().slice(0, MAX_NOTES_LEN)
        : null;

    const existing = await adb.get<{ id: number; status: ConflictStatus; entity_kind: string; entity_id: number }>(
      'SELECT id, status, entity_kind, entity_id FROM sync_conflicts WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Conflict not found', 404);
    if (existing.status === 'resolved' || existing.status === 'rejected') {
      throw new AppError(`Conflict is already ${existing.status}`, 409);
    }

    const rejectedAt = now();
    await adb.run(
      `UPDATE sync_conflicts
          SET status = 'rejected',
              resolution = 'rejected',
              resolution_notes = ?,
              resolved_by_user_id = ?,
              resolved_at = ?
        WHERE id = ?`,
      safeNotes,
      userId,
      rejectedAt,
      id,
    );

    audit(req.db, 'sync_conflict.rejected', userId, ip, {
      conflict_id: id,
      entity_kind: existing.entity_kind,
      entity_id: existing.entity_id,
      notes: safeNotes,
    });

    res.json({
      success: true,
      data: { id, status: 'rejected', resolved_by_user_id: userId, resolved_at: rejectedAt },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/defer — Defer a conflict back to pending review (manager+)
// ---------------------------------------------------------------------------

router.post(
  '/:id/defer',
  asyncHandler(async (req: Request, res: Response) => {
    requireManagerOrAdmin(req);

    const id = parseId(req.params.id, 'conflict id');
    const userId = req.user!.id;
    const adb = req.asyncDb;
    const ip = (req.headers['x-forwarded-for'] as string | undefined)?.split(',')[0]?.trim()
      ?? req.socket.remoteAddress
      ?? 'unknown';

    const existing = await adb.get<{ id: number; status: ConflictStatus; entity_kind: string; entity_id: number }>(
      'SELECT id, status, entity_kind, entity_id FROM sync_conflicts WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Conflict not found', 404);
    if (existing.status === 'resolved' || existing.status === 'rejected') {
      throw new AppError(`Cannot defer a ${existing.status} conflict`, 409);
    }

    await adb.run(
      `UPDATE sync_conflicts
          SET status = 'deferred',
              resolution = NULL,
              resolution_notes = NULL,
              resolved_by_user_id = NULL,
              resolved_at = NULL
        WHERE id = ?`,
      id,
    );

    audit(req.db, 'sync_conflict.deferred', userId, ip, {
      conflict_id: id,
      entity_kind: existing.entity_kind,
      entity_id: existing.entity_id,
    });

    res.json({ success: true, data: { id, status: 'deferred' } });
  }),
);

// ---------------------------------------------------------------------------
// POST /bulk-resolve — Resolve up to 100 conflicts in one call (manager+)
// ---------------------------------------------------------------------------

router.post(
  '/bulk-resolve',
  asyncHandler(async (req: Request, res: Response) => {
    requireManagerOrAdmin(req);

    const userId = req.user!.id;
    const adb = req.asyncDb;
    const ip = (req.headers['x-forwarded-for'] as string | undefined)?.split(',')[0]?.trim()
      ?? req.socket.remoteAddress
      ?? 'unknown';

    const { conflict_ids, resolution } = req.body as Record<string, unknown>;

    if (!Array.isArray(conflict_ids) || conflict_ids.length === 0) {
      throw new AppError('conflict_ids must be a non-empty array', 400);
    }
    if (conflict_ids.length > BULK_RESOLVE_MAX_IDS) {
      throw new AppError(`conflict_ids must not exceed ${BULK_RESOLVE_MAX_IDS} items`, 400);
    }

    // Validate each id is a positive integer
    const safeIds: number[] = conflict_ids.map((raw, idx) => {
      const id = parseInt(String(raw), 10);
      if (!Number.isInteger(id) || id <= 0) {
        throw new AppError(`conflict_ids[${idx}] is not a valid id`, 400);
      }
      return id;
    });

    const safeResolution = validateEnum(resolution, 'resolution', RESOLUTIONS);

    const resolvedAt = now();

    // Only resolve conflicts that are in a non-terminal state (not already resolved/rejected)
    // Use parameterised IN clause — build placeholders safely from validated integer array
    const placeholders = safeIds.map(() => '?').join(', ');
    const result = await adb.run(
      `UPDATE sync_conflicts
          SET status = 'resolved',
              resolution = ?,
              resolved_by_user_id = ?,
              resolved_at = ?
        WHERE id IN (${placeholders})
          AND status NOT IN ('resolved', 'rejected')`,
      safeResolution,
      userId,
      resolvedAt,
      ...safeIds,
    );

    audit(req.db, 'sync_conflict.bulk_resolved', userId, ip, {
      conflict_ids: safeIds,
      resolution: safeResolution,
      updated: result.changes,
    });

    logger.info('Bulk sync conflict resolution', {
      requested: safeIds.length,
      updated: result.changes,
      resolution: safeResolution,
      resolved_by: userId,
    });

    res.json({
      success: true,
      data: {
        requested: safeIds.length,
        updated: result.changes,
        skipped: safeIds.length - result.changes,
        resolution: safeResolution,
        resolved_at: resolvedAt,
        // IMPORTANT: resolution is declarative only — the client must replay
        // the chosen version via the regular entity endpoints.
        _note: 'Resolution persists the decision for audit; the client is responsible for replaying the chosen version via the regular entity endpoints.',
      },
    });
  }),
);

export default router;
