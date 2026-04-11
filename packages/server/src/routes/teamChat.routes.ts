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
  const re = /@([a-zA-Z0-9_.\-]{2,32})/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) {
    out.add(m[1].toLowerCase());
    if (out.size >= 10) break;
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
    const rows = kind ? await adb.all(sql, kind) : await adb.all(sql);
    res.json({ success: true, data: rows });
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
    const id = parseId(req.params.id, 'channel id');
    // Refuse to nuke the seeded general channel.
    const ch = await adb.get<ChannelRow>('SELECT * FROM team_chat_channels WHERE id = ?', id);
    if (!ch) throw new AppError('Channel not found', 404);
    if (ch.kind === 'general' && ch.name === 'general') {
      throw new AppError('Cannot delete the default general channel', 400);
    }
    await adb.run('DELETE FROM team_chat_messages WHERE channel_id = ?', id);
    await adb.run('DELETE FROM team_chat_channels WHERE id = ?', id);
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
    const limit = Math.min(200, Math.max(1, parseInt(String(req.query.limit || '50'), 10) || 50));

    const ch = await adb.get<ChannelRow>(
      'SELECT id FROM team_chat_channels WHERE id = ?', channelId,
    );
    if (!ch) throw new AppError('Channel not found', 404);

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

    const ch = await adb.get<ChannelRow>('SELECT id FROM team_chat_channels WHERE id = ?', channelId);
    if (!ch) throw new AppError('Channel not found', 404);

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
