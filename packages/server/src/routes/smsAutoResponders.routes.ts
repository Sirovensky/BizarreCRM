/**
 * SMS Auto-Responders routes
 * Mounted at: /api/v1/sms/auto-responders
 * Auth: authMiddleware applied at parent mount — NOT repeated here.
 *
 * Role gates:
 *   GET /        — any authenticated user
 *   GET /:id     — any authenticated user
 *   POST /       — manager or admin
 *   PATCH /:id   — manager or admin
 *   DELETE /:id  — manager or admin (soft delete: is_active=0)
 *   POST /:id/toggle — manager or admin
 *
 * Rate limits:
 *   Creates: 20 per hour per user (consumeWindowRate category 'sms_ar_create')
 *
 * rule_json shape: { type: 'keyword' | 'regex', match: string, case_sensitive?: boolean }
 * response_body: ≤ 1600 chars
 * rule_json: ≤ 8 KB serialized
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
} from '../utils/validate.js';

const router = Router();
const logger = createLogger('sms-auto-responders');

// ---------------------------------------------------------------------------
// Rate limit constants
// ---------------------------------------------------------------------------
const RL_CREATE_MAX = 20;
const RL_CREATE_WINDOW_MS = 3_600_000; // 1 hour

// ---------------------------------------------------------------------------
// Role guard helpers
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

// ---------------------------------------------------------------------------
// Validate rule_json shape and serialize
// ---------------------------------------------------------------------------

const RULE_TYPES = ['keyword', 'regex'] as const;
type RuleType = (typeof RULE_TYPES)[number];

interface AutoResponderRule {
  type: RuleType;
  match: string;
  case_sensitive?: boolean;
}

function validateAndSerializeRuleJson(raw: unknown): string {
  // Accept either a JSON string or a plain object from the request body
  let parsed: unknown;
  if (typeof raw === 'string') {
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new AppError('rule_json must be valid JSON', 400);
    }
  } else {
    parsed = raw;
  }

  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new AppError('rule_json must be an object', 400);
  }

  const obj = parsed as Record<string, unknown>;

  if (!RULE_TYPES.includes(obj.type as RuleType)) {
    throw new AppError(`rule_json.type must be one of: ${RULE_TYPES.join(', ')}`, 400);
  }
  if (typeof obj.match !== 'string' || !obj.match.trim()) {
    throw new AppError('rule_json.match must be a non-empty string', 400);
  }
  if (obj.match.length > 500) {
    throw new AppError('rule_json.match exceeds 500 characters', 400);
  }
  if (obj.type === 'regex') {
    try {
      new RegExp(obj.match);
    } catch {
      throw new AppError('rule_json.match is not a valid regular expression', 400);
    }
  }
  if (obj.case_sensitive !== undefined && typeof obj.case_sensitive !== 'boolean') {
    throw new AppError('rule_json.case_sensitive must be a boolean', 400);
  }

  const normalized: AutoResponderRule = {
    type: obj.type as RuleType,
    match: obj.match.trim(),
    ...(obj.case_sensitive !== undefined ? { case_sensitive: obj.case_sensitive as boolean } : {}),
  };

  return validateJsonPayload(normalized, 'rule_json', 8_192);
}

// ---------------------------------------------------------------------------
// GET / — list active auto-responders
// ---------------------------------------------------------------------------

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const rows = await adb.all<Record<string, unknown>>(
      `SELECT id, name, trigger_keyword, rule_json, response_body,
              is_active, match_count, last_matched_at,
              created_by_user_id, created_at, updated_at
         FROM sms_auto_responders
        WHERE is_active = 1
        ORDER BY name ASC`,
    );
    res.json({ success: true, data: rows });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id — detail + last 20 match timestamps (from audit log)
// ---------------------------------------------------------------------------

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id);

    const row = await adb.get<Record<string, unknown>>(
      `SELECT id, name, trigger_keyword, rule_json, response_body,
              is_active, match_count, last_matched_at,
              created_by_user_id, created_at, updated_at
         FROM sms_auto_responders
        WHERE id = ?`,
      id,
    );
    if (!row) throw new AppError('Auto-responder not found', 404);

    // Pull last 20 match events from audit_log — graceful if table is sparse
    const recentMatches = await adb.all<{ created_at: string; details: string }>(
      `SELECT created_at, details
         FROM audit_log
        WHERE action = 'sms_auto_responder_matched'
          AND JSON_EXTRACT(details, '$.responder_id') = ?
        ORDER BY created_at DESC
        LIMIT 20`,
      id,
    ).catch(() => [] as { created_at: string; details: string }[]);

    res.json({ success: true, data: { ...row, recent_matches: recentMatches } });
  }),
);

// ---------------------------------------------------------------------------
// POST / — create auto-responder (manager+)
// ---------------------------------------------------------------------------

router.post(
  '/',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);

    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;

    // Rate-limit creates: 20/hr per user
    const rlKey = `${(req as any).tenantSlug || 'default'}:${userId}`;
    const rl = consumeWindowRate(db, 'sms_ar_create', rlKey, RL_CREATE_MAX, RL_CREATE_WINDOW_MS);
    if (!rl.allowed) {
      throw new AppError(
        `Too many auto-responders created. Try again in ${rl.retryAfterSeconds}s.`,
        429,
      );
    }

    const body = (req.body ?? {}) as Record<string, unknown>;

    const name = validateRequiredString(body.name, 'name', 100);
    const trigger_keyword = validateTextLength(
      typeof body.trigger_keyword === 'string' ? body.trigger_keyword : undefined,
      100,
      'trigger_keyword',
    ) || null;
    const rule_json = validateAndSerializeRuleJson(body.rule_json);
    const response_body = validateRequiredString(body.response_body, 'response_body', 1600);

    const result = await adb.run(
      `INSERT INTO sms_auto_responders
         (name, trigger_keyword, rule_json, response_body, is_active, created_by_user_id,
          created_at, updated_at)
       VALUES (?, ?, ?, ?, 1, ?, datetime('now'), datetime('now'))`,
      name,
      trigger_keyword,
      rule_json,
      response_body,
      userId,
    );

    const newId = result.lastInsertRowid;

    audit(db, 'sms_auto_responder_created', userId, req.ip || 'unknown', {
      responder_id: newId,
      name,
    });

    logger.info('sms auto-responder created', { responder_id: newId, name, userId });

    const created = await adb.get<Record<string, unknown>>(
      'SELECT * FROM sms_auto_responders WHERE id = ?',
      newId,
    );
    res.status(201).json({ success: true, data: created });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id — partial update (manager+)
// ---------------------------------------------------------------------------

router.patch(
  '/:id',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);

    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const id = validateId(req.params.id);

    const existing = await adb.get<{ id: number }>(
      'SELECT id FROM sms_auto_responders WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Auto-responder not found', 404);

    const body = (req.body ?? {}) as Record<string, unknown>;
    const fields: string[] = [];
    const params: unknown[] = [];

    if (body.name !== undefined) {
      fields.push('name = ?');
      params.push(validateRequiredString(body.name, 'name', 100));
    }
    if (body.trigger_keyword !== undefined) {
      fields.push('trigger_keyword = ?');
      params.push(
        body.trigger_keyword === null
          ? null
          : validateTextLength(String(body.trigger_keyword), 100, 'trigger_keyword') || null,
      );
    }
    if (body.rule_json !== undefined) {
      fields.push('rule_json = ?');
      params.push(validateAndSerializeRuleJson(body.rule_json));
    }
    if (body.response_body !== undefined) {
      fields.push('response_body = ?');
      params.push(validateRequiredString(body.response_body, 'response_body', 1600));
    }
    if (body.is_active !== undefined) {
      const v = Number(body.is_active);
      if (v !== 0 && v !== 1) throw new AppError('is_active must be 0 or 1', 400);
      fields.push('is_active = ?');
      params.push(v);
    }

    if (fields.length === 0) throw new AppError('No fields to update', 400);

    fields.push("updated_at = datetime('now')");
    params.push(id);

    await adb.run(
      `UPDATE sms_auto_responders SET ${fields.join(', ')} WHERE id = ?`,
      ...params,
    );

    audit(db, 'sms_auto_responder_updated', userId, req.ip || 'unknown', {
      responder_id: id,
      fields: Object.keys(body),
    });

    const updated = await adb.get<Record<string, unknown>>(
      'SELECT * FROM sms_auto_responders WHERE id = ?',
      id,
    );
    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id — soft delete (is_active=0) (manager+)
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
      'SELECT id, name FROM sms_auto_responders WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Auto-responder not found', 404);

    await adb.run(
      `UPDATE sms_auto_responders SET is_active = 0, updated_at = datetime('now') WHERE id = ?`,
      id,
    );

    audit(db, 'sms_auto_responder_deleted', userId, req.ip || 'unknown', {
      responder_id: id,
      name: existing.name,
    });

    logger.info('sms auto-responder soft-deleted', { responder_id: id, userId });

    res.json({ success: true, data: { id, is_active: 0 } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/toggle — flip is_active (manager+)
// ---------------------------------------------------------------------------

router.post(
  '/:id/toggle',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);

    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const id = validateId(req.params.id);

    const existing = await adb.get<{ id: number; name: string; is_active: number }>(
      'SELECT id, name, is_active FROM sms_auto_responders WHERE id = ?',
      id,
    );
    if (!existing) throw new AppError('Auto-responder not found', 404);

    const newActive = existing.is_active ? 0 : 1;

    await adb.run(
      `UPDATE sms_auto_responders SET is_active = ?, updated_at = datetime('now') WHERE id = ?`,
      newActive,
      id,
    );

    audit(db, newActive ? 'sms_auto_responder_enabled' : 'sms_auto_responder_disabled', userId, req.ip || 'unknown', {
      responder_id: id,
      name: existing.name,
    });

    res.json({ success: true, data: { id, is_active: newActive } });
  }),
);

export default router;
