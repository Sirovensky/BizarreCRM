/**
 * Internal team chat routes — criticalaudit.md §53.
 *
 * Mounted at /api/v1/team-chat. Simple polling-based MVP:
 *   - Channels: 'general' (one row, seeded by 096), 'ticket' (one per ticket,
 *     created on demand), 'direct' (one-on-one DM, two participants in name).
 *   - Messages: append-only, ordered by created_at.
 *   - @mentions: parsed from message body and inserted into team_mentions.
 *
 * No WebSocket fan-out yet — clients poll `GET /channels/:id/messages?after=`
 * with the last message id. Real-time push is a TODO; the existing WS infra
 * (`packages/server/src/websocket/`) can be wired in a follow-up without
 * touching this route.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateTextLength,
  validateEnum,
} from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';
import { parsePageSize } from '../utils/pagination.js';

const router = Router();
const logger = createLogger('team-chat');

interface ChannelRow {
  id: number;
  name: string;
  kind: 'general' | 'ticket' | 'direct';
  ticket_id: number | null;
  created_at: string;
}

function requireUserId(req: any): number {
  const id = req?.user?.id;
  if (!id) throw new AppError('Authentication required', 401);
  return Number(id);
}

/**
 * SCAN-1109 [HIGH]: direct-message channels are named as two usernames
 * joined by `--` (convention set by the POST /channels handler for
 * `kind='direct'`). Enforce that the caller's username is one of them
 * before allowing read or write. `general` and `ticket` kinds remain open
 * to any authenticated user (team-wide and ticket-working respectively —
 * that matches the UI's shared surfaces).
 *
 * The check is case-insensitive and matches on a word-boundary so
 * "alice" doesn't match a channel named "alice2--bob". The channel name
 * is split on `--` (the single documented separator) and each token is
 * compared exactly to the caller's username.
 */
function assertChannelAccess(ch: ChannelRow, req: any): void {
  if (ch.kind === 'general' || ch.kind === 'ticket') return;
  if (ch.kind !== 'direct') return; // future kinds: explicit allow only
  const callerUsername = String(req?.user?.username ?? '').toLowerCase();
  if (!callerUsername) throw new AppError('Not a member of this channel', 403);
  const participants = ch.name.split('--').map((s) => s.trim().toLowerCase());
  if (!participants.includes(callerUsername)) {
    throw new AppError('Not a member of this channel', 403);
  }
}

function parseId(value: unknown, label = 'id'): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = parseInt(String(raw ?? ''), 10);
  if (!n || isNaN(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

// Extract @username tokens from a message body. Lower-cased, no @ prefix,
// deduplicated. Bounds: 32 chars per name, 10 mentions per message max.
export function parseMentionUsernames(body: string): string[] {
  const out = new Set<string>();
  // D3-5: cap input length BEFORE regex to prevent pathological inputs from
  // eating CPU. 4000 chars is more than enough for a chat message. The regex
  // itself uses fixed-bound quantifiers so catastrophic backtracking is not
  // possible, but the length cap is belt-and-suspenders.
  const capped = typeof body === 'string' ? body.slice(0, 4000) : '';
  if (!capped) return [];
  const re = /@([a-zA-Z0-9_.\-]{2,32})/g;
  let m: RegExpExecArray | null;
  // Also cap exec iterations in case a highly repetitive string triggers a
  // hot loop — break after 200 regex matches regardless of dedupe bucket.
  let iterations = 0;
  while ((m = re.exec(capped)) !== null) {
    out.add(m[1].toLowerCase());
    if (out.size >= 10) break;
    if (++iterations > 200) break;
  }
  return Array.from(out);
}

// ── CHANNELS ────────────────────────────────────────────────────────────────

router.get(
  '/channels',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const kind = req.query.kind
      ? validateEnum(
          req.query.kind,
          ['general', 'ticket', 'direct'] as const,
          'kind',
          false,
        )
      : null;
    const sql = kind
      ? `SELECT * FROM team_chat_channels WHERE kind = ? ORDER BY created_at DESC LIMIT 200`
      : `SELECT * FROM team_chat_channels ORDER BY created_at DESC LIMIT 200`;
    const rows = (kind ? await adb.all<ChannelRow>(sql, kind) : await adb.all<ChannelRow>(sql));
    // SCAN-1109 [HIGH]: filter direct channels client-side by the caller's
    // membership so the list doesn't enumerate other users' DMs. Non-direct
    // kinds (`general`, `ticket`) remain visible team-wide.
    const callerUsername = String(req?.user?.username ?? '').toLowerCase();
    const visible = rows.filter((r) => {
      if (r.kind !== 'direct') return true;
      if (!callerUsername) return false;
      return r.name.split('--').map((s) => s.trim().toLowerCase()).includes(callerUsername);
    });
    res.json({ success: true, data: visible });
  }),
);

router.post(
  '/channels',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): only admins create 'general'/'direct'
    // channels. 'ticket' channels are created on-demand by any tech working
    // the ticket — so we allow that kind without the admin gate.
    const kind = validateEnum(
      req.body?.kind,
      ['general', 'ticket', 'direct'] as const,
      'kind',
      true,
    )!;
    if (kind !== 'ticket' && req?.user?.role !== 'admin') {
      throw new AppError('Admin role required', 403);
    }
    const adb: AsyncDb = req.asyncDb;
    const name = validateRequiredString(req.body?.name, 'name', 80);
    let ticketId: number | null = null;
    if (kind === 'ticket') {
      ticketId = parseId(String(req.body?.ticket_id ?? ''), 'ticket_id');
      // FK: ticket must exist before we bind a channel to it.
      const ticketExists = await adb.get(
        'SELECT id FROM tickets WHERE id = ? AND is_deleted = 0',
        ticketId,
      );
      if (!ticketExists) throw new AppError('Ticket not found', 404);
      // Reuse existing channel if it exists (UNIQUE partial index in 096).
      const existing = await adb.get<ChannelRow>(
        `SELECT * FROM team_chat_channels WHERE ticket_id = ?`, ticketId,
      );
      if (existing) {
        res.json({ success: true, data: existing });
        return;
      }
    }
    const result = await adb.run(
      `INSERT INTO team_chat_channels (name, kind, ticket_id) VALUES (?, ?, ?)`,
      name, kind, ticketId,
    );
    const row = await adb.get<ChannelRow>(
      'SELECT * FROM team_chat_channels WHERE id = ?', result.lastInsertRowid,
    );
    audit(req.db, 'chat_channel_created', requireUserId(req), req.ip || 'unknown', {
      channel_id: Number(result.lastInsertRowid), kind,
    });
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/channels/:id',
  asyncHandler(async (req, res) => {
    if (req?.user?.role !== 'admin') throw new AppError('Admin role required', 403);
    const adb: AsyncDb = req.asyncDb;
    const db = req.db;
    const id = parseId(req.params.id, 'channel id');
    // Refuse to nuke the seeded general channel.
    const ch = await adb.get<ChannelRow>('SELECT * FROM team_chat_channels WHERE id = ?', id);
    if (!ch) throw new AppError('Channel not found', 404);
    if (ch.kind === 'general' && ch.name === 'general') {
      throw new AppError('Cannot delete the default general channel', 400);
    }
    // SCAN-1116: refuse to delete the `ticket` channel while the owning
    // ticket is still open — deleting the channel orphans the ticket's
    // discussion history, which is useful to techs mid-repair and to
    // after-the-fact audit. Admins can force-delete by closing the ticket
    // first.
    if (ch.kind === 'ticket' && ch.ticket_id !== null) {
      const t = await adb.get<{ id: number; is_closed: number; is_deleted: number }>(
        `SELECT t.id, ts.is_closed AS is_closed, t.is_deleted
         FROM tickets t
         LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
         WHERE t.id = ?`,
        ch.ticket_id,
      );
      if (t && !t.is_deleted && !t.is_closed) {
        throw new AppError('Close the ticket before deleting its chat channel', 400);
      }
    }
    // SCAN-1116: previously the two DELETEs were separate awaited calls; a
    // failure on the channel DELETE after the messages DELETE committed
    // left a channel row with no messages. Wrap in a sync transaction so
    // either both succeed or both roll back.
    db.transaction(() => {
      db.prepare('DELETE FROM team_chat_messages WHERE channel_id = ?').run(id);
      db.prepare('DELETE FROM team_chat_channels WHERE id = ?').run(id);
    })();
    audit(req.db, 'chat_channel_deleted', requireUserId(req), req.ip || 'unknown', { channel_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// ── MESSAGES ────────────────────────────────────────────────────────────────

router.get(
  '/channels/:id/messages',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const channelId = parseId(req.params.id, 'channel id');
    const after = req.query.after ? parseInt(String(req.query.after), 10) : 0;
    const limit = parsePageSize(req.query.limit, 50);

    const ch = await adb.get<ChannelRow>(
      'SELECT * FROM team_chat_channels WHERE id = ?', channelId,
    );
    if (!ch) throw new AppError('Channel not found', 404);
    // SCAN-1109: block non-participants from reading direct-message history.
    assertChannelAccess(ch, req);

    const rows = await adb.all(
      `SELECT m.*, u.first_name, u.last_name, u.username
       FROM team_chat_messages m
       LEFT JOIN users u ON u.id = m.user_id
       WHERE m.channel_id = ? AND m.id > ?
       ORDER BY m.id ASC LIMIT ?`,
      channelId, after, limit,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/channels/:id/messages',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const channelId = parseId(req.params.id, 'channel id');
    const body = validateRequiredString(req.body?.body, 'body', 2000);
    const userId = requireUserId(req);

    const ch = await adb.get<ChannelRow>('SELECT * FROM team_chat_channels WHERE id = ?', channelId);
    if (!ch) throw new AppError('Channel not found', 404);
    // SCAN-1109: block non-participants from posting to direct-message channels.
    assertChannelAccess(ch, req);

    const result = await adb.run(
      `INSERT INTO team_chat_messages (channel_id, user_id, body) VALUES (?, ?, ?)`,
      channelId, userId, body,
    );
    const messageId = Number(result.lastInsertRowid);

    // Chat messages are high volume but per-handler audit rule requires this.
    // Admins can filter by event type if log bloat becomes an issue.
    audit(req.db, 'chat_message_posted', userId, req.ip || 'unknown', {
      channel_id: channelId,
      message_id: messageId,
    });

    // Parse @mentions and write notification rows. Best-effort — failures
    // don't block message delivery, just log a warning.
    try {
      const usernames = parseMentionUsernames(body);
      if (usernames.length) {
        const placeholders = usernames.map(() => '?').join(',');
        const users = await adb.all<{ id: number; username: string }>(
          `SELECT id, username FROM users
           WHERE LOWER(username) IN (${placeholders}) AND is_active = 1`,
          ...usernames,
        );
        for (const u of users) {
          if (u.id === userId) continue;
          await adb.run(
            `INSERT INTO team_mentions
               (mentioned_user_id, mentioned_by_user_id, context_type, context_id, message_snippet)
             VALUES (?, ?, 'chat', ?, ?)`,
            u.id, userId, messageId, body.slice(0, 280),
          );
        }
      }
    } catch (err) {
      logger.warn('chat mention parse failed', {
        message_id: messageId,
        error: err instanceof Error ? err.message : 'unknown',
      });
    }

    const row = await adb.get(
      `SELECT m.*, u.first_name, u.last_name, u.username
       FROM team_chat_messages m
       LEFT JOIN users u ON u.id = m.user_id
       WHERE m.id = ?`,
      messageId,
    );
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/channels/:channelId/messages/:messageId',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const channelId = parseId(req.params.channelId, 'channel id');
    const messageId = parseId(req.params.messageId, 'message id');
    const userId = requireUserId(req);
    const isAdmin = req?.user?.role === 'admin';

    const msg = await adb.get<{ id: number; user_id: number }>(
      'SELECT id, user_id FROM team_chat_messages WHERE id = ? AND channel_id = ?',
      messageId, channelId,
    );
    if (!msg) throw new AppError('Message not found', 404);
    if (msg.user_id !== userId && !isAdmin) {
      throw new AppError('Not allowed to delete this message', 403);
    }
    await adb.run('DELETE FROM team_chat_messages WHERE id = ?', messageId);
    audit(req.db, 'chat_message_deleted', userId, req.ip || 'unknown', {
      channel_id: channelId, message_id: messageId,
    });
    res.json({ success: true, data: { id: messageId } });
  }),
);

export default router;
