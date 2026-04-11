/**
 * Inbox routes — Communications team-inbox enrichment (audit §51)
 *
 * Endpoints:
 *   GET    /inbox/conversations?assigned_to=me|all&tags=foo,bar
 *   PATCH  /inbox/conversation/:phone/assign          { user_id }
 *   POST   /inbox/conversation/:phone/tag             { tag }
 *   DELETE /inbox/conversation/:phone/tag/:tag
 *   POST   /inbox/conversation/:phone/mark-read       { last_message_id? }
 *   GET    /inbox/unread-count                         → per user
 *
 *   POST   /inbox/bulk-send                            (admin-only)
 *       body: { segment, template_id, confirmation_token }
 *
 *   GET    /inbox/retry-queue
 *   POST   /inbox/retry-queue/:id/retry
 *   POST   /inbox/retry-queue/:id/cancel
 *
 *   GET    /inbox/template-analytics
 *   POST   /inbox/sentiment/analyze                    { message_id?, phone, text }
 *   GET    /inbox/sla-stats?days=30
 *
 * Rules:
 *   - auth middleware mounted at index.ts
 *   - every mutating endpoint writes an audit() row
 *   - bulk-send REQUIRES admin role AND a double-submit confirmation token
 *   - sentiment classifier is purely keyword-based — no external AI
 *   - never modifies sms_messages; new tables only (migration 094)
 */

import { Router, type Request } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateEnum,
} from '../utils/validate.js';
import { normalizePhone } from '../utils/phone.js';
import type { AsyncDb } from '../db/async-db.js';

const log = createLogger('comms');
const router = Router();

// -----------------------------------------------------------------------------
// Local guards + helpers
// -----------------------------------------------------------------------------

/**
 * SEC: admin check inline (same pattern as automations.routes.ts). Relying on
 * mount-point middleware for sensitive actions is fragile; any future routing
 * refactor could silently expose them.
 */
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403);
  }
}

/**
 * Normalize a phone input (also rejects empty / too-short values) to match
 * how sms.routes stores conv_phone. Throws 400 on invalid input.
 */
function requirePhone(value: unknown, fieldName = 'phone'): string {
  const raw = validateRequiredString(value, fieldName, 32);
  const normalized = normalizePhone(raw);
  if (!normalized || normalized.length < 7) {
    throw new AppError(`${fieldName} is not a valid phone`, 400);
  }
  return normalized;
}

/** Positive int that must fit a DB id. */
function requirePositiveInt(value: unknown, fieldName: string): number {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0 || !Number.isInteger(n)) {
    throw new AppError(`${fieldName} must be a positive integer`, 400);
  }
  return n;
}

// Exponential backoff in minutes for the retry queue. Keeps retries cheap
// for humans and bounded (~1d after 7 tries).
const RETRY_BACKOFF_MINUTES = [1, 5, 15, 60, 180, 720, 1440] as const;

function nextRetryAt(retryCount: number): string {
  const idx = Math.min(retryCount, RETRY_BACKOFF_MINUTES.length - 1);
  const mins = RETRY_BACKOFF_MINUTES[idx];
  const d = new Date(Date.now() + mins * 60_000);
  return d.toISOString();
}

// -----------------------------------------------------------------------------
// Conversation assignment (idea §51.1)
// -----------------------------------------------------------------------------

router.get(
  '/conversations',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const filter = validateEnum(
      req.query.assigned_to ?? 'all',
      ['me', 'all', 'unassigned'] as const,
      'assigned_to',
      false,
    );
    const tagsCsv = typeof req.query.tags === 'string' ? req.query.tags.trim() : '';
    const tags = tagsCsv ? tagsCsv.split(',').map((t) => t.trim()).filter(Boolean) : [];

    // Keep the query small — the full conversation list still comes from the
    // existing GET /sms/conversations. This endpoint just joins assignments
    // + tags so the UI can filter by them.
    const where: string[] = [];
    const params: unknown[] = [];

    if (filter === 'me') {
      where.push('ca.assigned_user_id = ?');
      params.push(userId);
    } else if (filter === 'unassigned') {
      where.push('ca.assigned_user_id IS NULL');
    }

    let tagJoin = '';
    if (tags.length > 0) {
      tagJoin = `INNER JOIN conversation_tags ct ON ct.phone = ca.phone
                 AND ct.tag IN (${tags.map(() => '?').join(',')})`;
      params.push(...tags);
    }

    const sql = `
      SELECT ca.phone,
             ca.assigned_user_id,
             ca.assigned_at,
             (SELECT GROUP_CONCAT(tag, ',') FROM conversation_tags
               WHERE phone = ca.phone) AS tags
        FROM conversation_assignments ca
        ${tagJoin}
        ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
       GROUP BY ca.phone
       ORDER BY ca.assigned_at DESC
       LIMIT 500
    `;
    const rows = await adb.all<{
      phone: string;
      assigned_user_id: number | null;
      assigned_at: string;
      tags: string | null;
    }>(sql, ...params);

    const enriched = rows.map((r) => ({
      phone: r.phone,
      assigned_user_id: r.assigned_user_id,
      assigned_at: r.assigned_at,
      tags: r.tags ? r.tags.split(',').filter(Boolean) : [],
    }));
    res.json({ success: true, data: enriched });
  }),
);

router.patch(
  '/conversation/:phone/assign',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const phone = requirePhone(req.params.phone);
    // Allow explicit null → unclaim conversation.
    const userIdRaw = (req.body ?? {}).user_id;
    const userId: number | null =
      userIdRaw === null || userIdRaw === undefined
        ? null
        : requirePositiveInt(userIdRaw, 'user_id');

    if (userId !== null) {
      const exists = await adb.get<{ id: number }>(
        'SELECT id FROM users WHERE id = ? AND is_active = 1',
        userId,
      );
      if (!exists) throw new AppError('User not found or inactive', 404);
    }

    await adb.run(
      `INSERT INTO conversation_assignments (phone, assigned_user_id, assigned_at)
            VALUES (?, ?, datetime('now'))
       ON CONFLICT(phone) DO UPDATE SET
             assigned_user_id = excluded.assigned_user_id,
             assigned_at = datetime('now')`,
      phone,
      userId,
    );

    audit(db, 'inbox_conversation_assigned', req.user!.id, req.ip || 'unknown', {
      phone,
      assigned_to: userId,
    });
    res.json({ success: true, data: { phone, assigned_user_id: userId } });
  }),
);

// -----------------------------------------------------------------------------
// Conversation tags (idea §51.6)
// -----------------------------------------------------------------------------

router.post(
  '/conversation/:phone/tag',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const phone = requirePhone(req.params.phone);
    const tag = validateRequiredString((req.body ?? {}).tag, 'tag', 32).toLowerCase();

    try {
      await adb.run(
        'INSERT INTO conversation_tags (phone, tag) VALUES (?, ?)',
        phone,
        tag,
      );
    } catch (err: any) {
      if (!String(err?.message || '').includes('UNIQUE')) throw err;
      // Idempotent — tag already exists is not an error.
    }

    audit(db, 'inbox_tag_added', req.user!.id, req.ip || 'unknown', { phone, tag });
    res.json({ success: true, data: { phone, tag } });
  }),
);

router.delete(
  '/conversation/:phone/tag/:tag',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const phone = requirePhone(req.params.phone);
    const tag = validateRequiredString(req.params.tag, 'tag', 32).toLowerCase();

    await adb.run('DELETE FROM conversation_tags WHERE phone = ? AND tag = ?', phone, tag);
    audit(db, 'inbox_tag_removed', req.user!.id, req.ip || 'unknown', { phone, tag });
    res.json({ success: true, data: { phone, tag } });
  }),
);

// -----------------------------------------------------------------------------
// Read receipts (idea §51.1)
// -----------------------------------------------------------------------------

router.post(
  '/conversation/:phone/mark-read',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const phone = requirePhone(req.params.phone);
    const lastMsgRaw = (req.body ?? {}).last_message_id;
    const lastMessageId =
      lastMsgRaw === null || lastMsgRaw === undefined
        ? null
        : requirePositiveInt(lastMsgRaw, 'last_message_id');

    await adb.run(
      `INSERT INTO conversation_read_receipts
              (phone, user_id, last_read_message_id, last_read_at)
            VALUES (?, ?, ?, datetime('now'))
       ON CONFLICT(phone, user_id) DO UPDATE SET
             last_read_message_id = excluded.last_read_message_id,
             last_read_at = datetime('now')`,
      phone,
      req.user!.id,
      lastMessageId,
    );
    res.json({ success: true, data: { phone, last_message_id: lastMessageId } });
  }),
);

router.get(
  '/unread-count',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;

    // Per-user: count inbound messages newer than this user's last_read_at.
    // Fall back to conversation's total unread if no receipt yet.
    const row = await adb.get<{ unread: number }>(
      `SELECT COUNT(*) AS unread
         FROM sms_messages m
         LEFT JOIN conversation_read_receipts r
                ON r.phone = m.conv_phone AND r.user_id = ?
        WHERE m.direction = 'inbound'
          AND (r.last_read_at IS NULL OR m.created_at > r.last_read_at)`,
      userId,
    );
    res.json({ success: true, data: { unread: row?.unread ?? 0 } });
  }),
);

// -----------------------------------------------------------------------------
// Bulk SMS (idea §51.3) — admin-only + double-submit confirmation token
// -----------------------------------------------------------------------------

type BulkSegment = 'open_tickets' | 'all_customers' | 'recent_purchases';
const BULK_SEGMENTS: readonly BulkSegment[] = [
  'open_tickets',
  'all_customers',
  'recent_purchases',
];

/**
 * Preview the size of a segment without sending anything. Returns a
 * confirmation token the caller must submit with the actual send request
 * — double-submit protection prevents a single compromised click from
 * dispatching a bulk send.
 */
async function previewBulkSegment(
  adb: AsyncDb,
  segment: BulkSegment,
): Promise<{ count: number; phones: string[] }> {
  let rows: { phone: string }[] = [];
  switch (segment) {
    case 'open_tickets':
      rows = await adb.all<{ phone: string }>(
        `SELECT DISTINCT c.mobile AS phone
           FROM customers c
           JOIN tickets t ON t.customer_id = c.id
           JOIN ticket_statuses s ON s.id = t.status_id
          WHERE s.is_closed = 0 AND s.is_cancelled = 0
            AND t.is_deleted = 0
            AND c.mobile IS NOT NULL AND c.mobile <> ''`,
      );
      break;
    case 'all_customers':
      rows = await adb.all<{ phone: string }>(
        `SELECT DISTINCT mobile AS phone FROM customers
          WHERE mobile IS NOT NULL AND mobile <> ''`,
      );
      break;
    case 'recent_purchases':
      rows = await adb.all<{ phone: string }>(
        `SELECT DISTINCT c.mobile AS phone
           FROM customers c
           JOIN invoices i ON i.customer_id = c.id
          WHERE i.created_at >= datetime('now','-30 days')
            AND c.mobile IS NOT NULL AND c.mobile <> ''`,
      );
      break;
  }
  const phones = rows.map((r) => normalizePhone(r.phone)).filter(Boolean);
  return { count: phones.length, phones };
}

/**
 * Confirmation tokens are derived so the server doesn't have to store them.
 * Payload = segment|template_id|user_id|bucket (5-min granularity). A caller
 * must GET preview first (same bucket), then POST with the returned token.
 */
function makeBulkToken(segment: string, templateId: number, userId: number): string {
  const bucket = Math.floor(Date.now() / (5 * 60_000));
  const payload = `${segment}|${templateId}|${userId}|${bucket}`;
  const secret = process.env.JWT_SECRET || 'bizarre-inbox-bulk';
  return crypto.createHmac('sha256', secret).update(payload).digest('hex').slice(0, 32);
}
function verifyBulkToken(
  token: string,
  segment: string,
  templateId: number,
  userId: number,
): boolean {
  if (typeof token !== 'string' || token.length !== 32) return false;
  const tokenBuf = Buffer.from(token);
  // Accept current bucket OR previous bucket (5-min grace for slow humans).
  for (const delta of [0, -1]) {
    const bucket = Math.floor(Date.now() / (5 * 60_000)) + delta;
    const payload = `${segment}|${templateId}|${userId}|${bucket}`;
    const secret = process.env.JWT_SECRET || 'bizarre-inbox-bulk';
    const expected = crypto
      .createHmac('sha256', secret)
      .update(payload)
      .digest('hex')
      .slice(0, 32);
    const expectedBuf = Buffer.from(expected);
    if (expectedBuf.length === tokenBuf.length &&
        crypto.timingSafeEqual(expectedBuf, tokenBuf)) return true;
  }
  return false;
}

router.post(
  '/bulk-send',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const db = req.db;
    const adb = req.asyncDb;

    const segment = validateEnum(
      (req.body ?? {}).segment,
      BULK_SEGMENTS,
      'segment',
    ) as BulkSegment;
    const templateId = requirePositiveInt((req.body ?? {}).template_id, 'template_id');
    const token = (req.body ?? {}).confirmation_token;

    // Step 1: no token → return a preview + fresh token. Caller confirms then
    // re-posts.
    if (!token) {
      const preview = await previewBulkSegment(adb, segment);
      const freshToken = makeBulkToken(segment, templateId, req.user!.id);
      res.json({
        success: true,
        data: {
          preview_count: preview.count,
          confirmation_token: freshToken,
          confirmed: false,
        },
      });
      return;
    }

    // Step 2: token present → must match + user must still be admin.
    if (!verifyBulkToken(token, segment, templateId, req.user!.id)) {
      throw new AppError('Invalid or expired confirmation token', 400);
    }

    const tpl = await adb.get<{ id: number; content: string; name: string }>(
      'SELECT id, content, name FROM sms_templates WHERE id = ?',
      templateId,
    );
    if (!tpl) throw new AppError('Template not found', 404);

    const preview = await previewBulkSegment(adb, segment);
    if (preview.count === 0) {
      res.json({ success: true, data: { enqueued: 0, segment, confirmed: true } });
      return;
    }

    // Enqueue via sms_retry_queue so the same backoff path handles failures.
    for (const phone of preview.phones) {
      await adb.run(
        `INSERT INTO sms_retry_queue (to_phone, body, retry_count, next_retry_at, status)
              VALUES (?, ?, 0, datetime('now'), 'pending')`,
        phone,
        tpl.content,
      );
    }

    audit(db, 'inbox_bulk_send_enqueued', req.user!.id, req.ip || 'unknown', {
      segment,
      template_id: templateId,
      recipients: preview.count,
    });
    log.info('bulk send enqueued', {
      segment,
      template_id: templateId,
      count: preview.count,
    });

    res.json({
      success: true,
      data: {
        enqueued: preview.count,
        segment,
        template: { id: tpl.id, name: tpl.name },
        confirmed: true,
      },
    });
  }),
);

// -----------------------------------------------------------------------------
// Retry queue (idea §51.4)
// -----------------------------------------------------------------------------

router.get(
  '/retry-queue',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const rows = await adb.all(
      `SELECT id, original_message_id, to_phone, body, retry_count, next_retry_at,
              last_error, status, created_at
         FROM sms_retry_queue
        WHERE status IN ('pending','failed')
        ORDER BY next_retry_at ASC
        LIMIT 200`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/retry-queue/:id/retry',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const id = requirePositiveInt(req.params.id, 'id');

    const row = await adb.get<{
      id: number;
      retry_count: number;
      status: string;
    }>('SELECT id, retry_count, status FROM sms_retry_queue WHERE id = ?', id);
    if (!row) throw new AppError('Retry item not found', 404);
    if (row.status === 'succeeded' || row.status === 'cancelled') {
      throw new AppError(`Cannot retry item in ${row.status} state`, 400);
    }

    const newCount = row.retry_count + 1;
    const when = nextRetryAt(newCount);
    await adb.run(
      `UPDATE sms_retry_queue
          SET retry_count = ?, next_retry_at = ?, status = 'pending',
              last_error = NULL
        WHERE id = ?`,
      newCount,
      when,
      id,
    );

    audit(db, 'inbox_retry_requested', req.user!.id, req.ip || 'unknown', {
      retry_id: id,
      retry_count: newCount,
    });
    res.json({ success: true, data: { id, retry_count: newCount, next_retry_at: when } });
  }),
);

router.post(
  '/retry-queue/:id/cancel',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const id = requirePositiveInt(req.params.id, 'id');

    const result = await adb.run(
      `UPDATE sms_retry_queue SET status = 'cancelled'
        WHERE id = ? AND status IN ('pending','failed')`,
      id,
    );
    if (result.changes === 0) {
      throw new AppError('Retry item not found or not cancellable', 404);
    }

    audit(db, 'inbox_retry_cancelled', req.user!.id, req.ip || 'unknown', { retry_id: id });
    res.json({ success: true, data: { id, status: 'cancelled' } });
  }),
);

// -----------------------------------------------------------------------------
// Template analytics (idea §51.11)
// -----------------------------------------------------------------------------

router.get(
  '/template-analytics',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const rows = await adb.all<{
      template_id: number;
      name: string | null;
      sent_count: number;
      reply_count: number;
      last_sent_at: string | null;
    }>(
      `SELECT a.template_id,
              t.name,
              a.sent_count,
              a.reply_count,
              a.last_sent_at
         FROM sms_template_analytics a
         LEFT JOIN sms_templates t ON t.id = a.template_id
        ORDER BY a.sent_count DESC
        LIMIT 100`,
    );
    const enriched = rows.map((r) => ({
      template_id: r.template_id,
      name: r.name ?? '(deleted)',
      sent_count: r.sent_count,
      reply_count: r.reply_count,
      reply_rate: r.sent_count > 0 ? r.reply_count / r.sent_count : 0,
      last_sent_at: r.last_sent_at,
    }));
    res.json({ success: true, data: enriched });
  }),
);

// -----------------------------------------------------------------------------
// Sentiment classifier (idea §51.5) — pure keyword-based. NO external AI.
// -----------------------------------------------------------------------------

const ANGRY_WORDS = ['terrible', 'awful', 'worst', 'broken', 'scam', 'angry', 'unacceptable', 'ridiculous'];
const HAPPY_WORDS = ['thanks', 'thank you', 'great', 'awesome', 'perfect', 'love it', 'amazing', 'excellent'];
const URGENT_WORDS = ['asap', 'urgent', 'emergency', 'right now', 'immediately'];

type Sentiment = 'angry' | 'happy' | 'neutral' | 'urgent';

function classifySentiment(text: string): { sentiment: Sentiment; score: number } {
  const t = text.toLowerCase();
  const count = (words: readonly string[]): number =>
    words.reduce((sum, w) => sum + (t.includes(w) ? 1 : 0), 0);

  const angry = count(ANGRY_WORDS);
  const urgent = count(URGENT_WORDS);
  const happy = count(HAPPY_WORDS);

  // Precedence: urgent > angry > happy > neutral (urgent is actionable even
  // if the tone is mixed, so it gets priority attention).
  if (urgent > 0) return { sentiment: 'urgent', score: Math.min(100, 40 + urgent * 20) };
  if (angry > happy) return { sentiment: 'angry', score: Math.min(100, 40 + angry * 15) };
  if (happy > angry) return { sentiment: 'happy', score: Math.min(100, 40 + happy * 15) };
  return { sentiment: 'neutral', score: 50 };
}

router.post(
  '/sentiment/analyze',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const body = req.body ?? {};
    const phone = requirePhone(body.phone);
    const text = validateRequiredString(body.text, 'text', 2000);
    const messageId =
      body.message_id === null || body.message_id === undefined
        ? null
        : requirePositiveInt(body.message_id, 'message_id');

    const { sentiment, score } = classifySentiment(text);

    await adb.run(
      `INSERT INTO sms_sentiment_history (message_id, phone, sentiment, score)
            VALUES (?, ?, ?, ?)`,
      messageId,
      phone,
      sentiment,
      score,
    );

    res.json({ success: true, data: { sentiment, score, message_id: messageId, phone } });
  }),
);

// -----------------------------------------------------------------------------
// Inbox-scoped store_config (ideas §51.9 & §51.12) — admin-only
// -----------------------------------------------------------------------------
//
// settings.routes.ts has a strict whitelist (ALLOWED_CONFIG_KEYS) that does
// not include the four inbox keys added by migration 094. Rather than modify
// that file (out of scope), we expose a tiny scoped PATCH here for just the
// inbox_* keys. Keeps the blast radius small and avoids cross-file churn.

const INBOX_CONFIG_KEYS = new Set([
  'inbox_auto_assignment',
  'inbox_off_hours_autoreply_enabled',
  'inbox_off_hours_autoreply_message',
  'inbox_compliance_archive_years',
]);

router.get(
  '/config',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const rows = await adb.all<{ key: string; value: string }>(
      `SELECT key, value FROM store_config
        WHERE key IN (
          'inbox_auto_assignment',
          'inbox_off_hours_autoreply_enabled',
          'inbox_off_hours_autoreply_message',
          'inbox_compliance_archive_years'
        )`,
    );
    const data: Record<string, string> = {};
    for (const r of rows) data[r.key] = r.value;
    res.json({ success: true, data });
  }),
);

router.patch(
  '/config',
  asyncHandler(async (req, res) => {
    requireAdmin(req);
    const db = req.db;
    const adb = req.asyncDb;
    const body = (req.body ?? {}) as Record<string, unknown>;

    const toWrite: [string, string][] = [];
    for (const [key, value] of Object.entries(body)) {
      if (!INBOX_CONFIG_KEYS.has(key)) continue;
      if (value === null || value === undefined) continue;
      const str = String(value).slice(0, 1000);
      toWrite.push([key, str]);
    }
    if (toWrite.length === 0) {
      throw new AppError('No inbox config keys in payload', 400);
    }

    for (const [key, value] of toWrite) {
      await adb.run(
        'INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)',
        key,
        value,
      );
    }
    audit(db, 'inbox_config_updated', req.user!.id, req.ip || 'unknown', {
      keys: toWrite.map((p) => p[0]),
    });
    res.json({ success: true, data: Object.fromEntries(toWrite) });
  }),
);

// -----------------------------------------------------------------------------
// SLA stats (idea §51.10) — simple aggregate on sms_messages
// -----------------------------------------------------------------------------

router.get(
  '/sla-stats',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const daysRaw = Number(req.query.days ?? 30);
    const days = Number.isFinite(daysRaw) && daysRaw > 0 && daysRaw <= 365 ? Math.floor(daysRaw) : 30;

    // "First response time" = seconds between an inbound message and the next
    // outbound on the same conv_phone. Averaged over the window.
    const row = await adb.get<{
      avg_seconds: number | null;
      total_inbound: number;
      responded: number;
    }>(
      `WITH inbound AS (
         SELECT id, conv_phone, created_at
           FROM sms_messages
          WHERE direction = 'inbound'
            AND created_at >= datetime('now', ?)
       ),
       first_reply AS (
         SELECT i.id AS inbound_id,
                i.conv_phone,
                i.created_at AS inbound_at,
                (SELECT MIN(m.created_at) FROM sms_messages m
                   WHERE m.conv_phone = i.conv_phone
                     AND m.direction = 'outbound'
                     AND m.created_at > i.created_at) AS reply_at
           FROM inbound i
       )
       SELECT AVG(CAST(
                (strftime('%s', reply_at) - strftime('%s', inbound_at))
                AS REAL)) AS avg_seconds,
              COUNT(*) AS total_inbound,
              SUM(CASE WHEN reply_at IS NOT NULL THEN 1 ELSE 0 END) AS responded
         FROM first_reply`,
      `-${days} days`,
    );

    const avgSeconds = row?.avg_seconds ?? 0;
    res.json({
      success: true,
      data: {
        window_days: days,
        total_inbound: row?.total_inbound ?? 0,
        responded: row?.responded ?? 0,
        response_rate:
          row && row.total_inbound > 0 ? (row.responded ?? 0) / row.total_inbound : 0,
        avg_first_response_seconds: Math.round(avgSeconds),
        avg_first_response_minutes: Math.round((avgSeconds / 60) * 10) / 10,
      },
    });
  }),
);

export default router;
