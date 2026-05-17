import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import multer from 'multer';
import { config } from '../config.js';
import { AppError } from '../middleware/errorHandler.js';
import { getProviderForDb, getSmsProvider, sendSmsTenant } from '../services/smsProvider.js';
import type { MmsMedia, InboundMessage } from '../services/smsProvider.js';
import { broadcast } from '../ws/server.js';
import { normalizePhone } from '../utils/phone.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowFailure, consumeWindowRate } from '../utils/rateLimiter.js';
import { reserveStorage } from '../services/usageTracker.js';
import { validateIsoDate } from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { fileUploadValidator } from '../middleware/fileUploadValidator.js';
import { enforceUploadQuota } from '../middleware/uploadQuota.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';
import { tryAutoRespond } from '../services/smsAutoResponderMatcher.js';
import {
  IMAGE_UPLOAD_FORMAT_ERROR,
  IMAGE_UPLOAD_MIME_TYPES,
  SMALL_IMAGE_UPLOAD_MAX_BYTES,
  imageExtensionForMime,
  isSupportedImageMime,
} from '../utils/imageUploadPolicy.js';

const logger = createLogger('sms.routes');

// SEC-H93: Allowlist of hosts that may supply MMS media URLs.
// The server GETs these URLs (no auth headers on MMS fetches, but SSRF is still
// a risk — a forged webhook could exfiltrate internal-network resources or hit
// cloud metadata endpoints). Reject-by-default; add only observed-in-the-wild
// provider hosts. IP-literal URLs are separately rejected below.
const ALLOWED_MMS_HOSTS = new Set([
  'api.twilio.com',          // Twilio MMS MediaUrl fields
  'messaging.bandwidth.com', // Bandwidth MMS media
  'api.telnyx.com',          // Telnyx message media
  'api.plivo.com',           // Plivo MMS MediaUrl fields
  'api.nexmo.com',           // Vonage (Nexmo) message media
]);

/**
 * SEC-H93: Validate that a media/recording URL is from an allowed provider host.
 * Returns the validated URL string on success, or throws with a descriptive reason.
 * Rejects: non-https, IP literals (numeric IPv4 or bracketed IPv6), and any host
 * not in the supplied allowlist.
 */
function validateProviderUrl(url: string, allowedHosts: Set<string>, context: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`${context}: URL parse failed — rejecting`);
  }

  if (parsed.protocol !== 'https:') {
    throw new Error(`${context}: only https: URLs allowed, got ${parsed.protocol}`);
  }

  const { hostname } = parsed;

  // Reject IP-literal addresses (IPv4 dotted-decimal or bracketed IPv6).
  // These are not in any provider's allowlist and are a direct SSRF path to
  // internal/metadata endpoints (e.g. 169.254.169.254).
  const isIpv4 = /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname);
  const isIpv6 = hostname.startsWith('[');
  if (isIpv4 || isIpv6) {
    throw new Error(`${context}: IP-literal URL rejected (${hostname})`);
  }

  if (!allowedHosts.has(hostname)) {
    throw new Error(`${context}: host not in allowlist (${hostname})`);
  }
}

// SEC-M56: Never log full phone numbers — they are customer PII and show up
// in log aggregators / ops dashboards where cross-tenant staff can see them.
// Preserve the last 4 digits so ops can still correlate support tickets but
// the national/carrier prefix is stripped. Examples:
//   "+15551234567" -> "XXX-XXX-4567"
//   "5551234567"   -> "XXX-XXX-4567"
//   "abc"          -> "XXX-XXX-XXXX"   (fully masked for garbage input)
function redactPhone(phone: unknown): string {
  if (typeof phone !== 'string') return 'XXX-XXX-XXXX';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 4) return 'XXX-XXX-XXXX';
  return `XXX-XXX-${digits.slice(-4)}`;
}

const router = Router();

function isManagerOrAdmin(req: Request): boolean {
  const role = (req as any).user?.role;
  return role === 'admin' || role === 'manager';
}

function requireReminderAccess(req: Request, reminder: { created_by: number }): void {
  if (isManagerOrAdmin(req)) return;
  if (reminder.created_by === (req as any).user?.id) return;
  throw new AppError('Reminder not found', 404);
}

function parseReminderDueAt(value: unknown): string {
  if (typeof value !== 'string') throw new AppError('due_at is required', 400);
  const normalized = validateIsoDate(value, 'due_at', false);
  if (!normalized || !/T\d{2}:\d{2}/.test(normalized)) {
    throw new AppError('due_at must include a date and time', 400);
  }
  const due = new Date(normalized);
  if (Number.isNaN(due.getTime())) throw new AppError('Invalid due_at datetime', 400);
  if (due.getTime() <= Date.now() - 60_000) throw new AppError('due_at must be in the future', 400);
  return due.toISOString().slice(0, 19).replace('T', ' ');
}

function normalizeReminderPhone(raw: unknown): { phone: string; convPhone: string } {
  if (typeof raw !== 'string' || !raw.trim()) throw new AppError('phone is required', 400);
  if (raw.length > 30) throw new AppError('Phone number too long', 400);
  const convPhone = normalizePhone(raw);
  if (convPhone.length < 8 || convPhone.length > 15) {
    throw new AppError('Phone number is not valid enough for a follow-up reminder', 400);
  }
  return { phone: raw.trim(), convPhone };
}

// --- MMS media upload config ---
const MMS_MAX_SIZE = SMALL_IMAGE_UPLOAD_MAX_BYTES;
const MMS_COMPRESS_THRESHOLD = 600 * 1024; // 600KB — compress images over this for MMS
const ALLOWED_MEDIA_TYPES = IMAGE_UPLOAD_MIME_TYPES;

const mmsDir = path.join(config.uploadsPath, 'mms');
if (!fs.existsSync(mmsDir)) fs.mkdirSync(mmsDir, { recursive: true });

const mmsUpload = multer({
  storage: multer.diskStorage({
    destination: (req: any, _file: any, cb: any) => {
      const slug = req.tenantSlug;
      const dir = slug ? path.join(config.uploadsPath, slug, 'mms') : mmsDir;
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (_req, file, cb) => {
      // SEC: Derive extension from validated MIME type, not user-supplied filename
      const ext = imageExtensionForMime(file.mimetype) || '.jpg';
      cb(null, `${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`);
    },
  }),
  limits: { fileSize: MMS_MAX_SIZE },
  fileFilter: (_req, file, cb) => {
    if (isSupportedImageMime(file.mimetype)) cb(null, true);
    else cb(new Error(IMAGE_UPLOAD_FORMAT_ERROR));
  },
});

/** Compress an image file if over threshold. Returns the (possibly new) file path. */
async function compressIfNeeded(filePath: string, mimeType: string): Promise<string> {
  const stat = fs.statSync(filePath);
  if (stat.size <= MMS_COMPRESS_THRESHOLD) return filePath;

  try {
    const sharp = (await import('sharp')).default;
    const ext = path.extname(filePath).toLowerCase();
    let outputPath = filePath;

    // PNG → convert to JPEG for compression
    if (ext === '.png' || mimeType === 'image/png') {
      outputPath = filePath.replace(/\.png$/i, '.jpg');
    }

    // D3-3: cap decompressed pixel count to 24MP (~matches phone camera max).
    // Prevents decompression-bomb uploads (tiny file → gigabytes of RAM after
    // decode). `failOn: 'error'` aborts on malformed headers instead of trying
    // to recover. 5MB upload cap is already enforced by multer above — this is
    // the second gate against pixel-bomb files that compress well but expand.
    let pipeline = sharp(filePath, { limitInputPixels: 24_000_000, failOn: 'error' })
      .resize(1600, 1600, { fit: 'inside', withoutEnlargement: true });

    // Progressive quality reduction until under threshold
    for (const quality of [80, 60, 40]) {
      const buffer = await pipeline.jpeg({ quality, progressive: true }).toBuffer();
      if (buffer.length <= MMS_COMPRESS_THRESHOLD || quality === 40) {
        fs.writeFileSync(outputPath, buffer);
        // Clean up original if different
        if (outputPath !== filePath && fs.existsSync(filePath)) fs.unlinkSync(filePath);
        return outputPath;
      }
    }

    return filePath; // Fallback: return original
  } catch (err) {
    // L8-SMS (rerun §24): Structured warning instead of console.warn so MMS
    // compression failures surface in the ops dashboard.
    logger.warn('mms image compression failed, using original', {
      filePath,
      mimeType,
      error: err instanceof Error ? err.message : String(err),
    });
    return filePath;
  }
}

// Substitute template variables
function substituteVars(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => vars[key] ?? '');
}

// ---------------------------------------------------------------------------
// GET /sms/unread-count — Lightweight total unread SMS count (no conversation data)
// ---------------------------------------------------------------------------
router.get('/unread-count', async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;

  // Sum unread messages across all conversations in a single query.
  // A message is "unread" if it's inbound and arrived after the latest outbound
  // message or manual read marker for that conversation.
  const row = await adb.get<{ total: number }>(`
    SELECT COALESCE(SUM(unread), 0) AS total FROM (
      SELECT
        conv_phone,
        (SELECT COUNT(*) FROM sms_messages m3
          WHERE m3.conv_phone = m1.conv_phone AND m3.direction = 'inbound'
          AND m3.created_at > COALESCE(
            (SELECT MAX(cutoff) FROM (
              SELECT MAX(m4.created_at) AS cutoff FROM sms_messages m4 WHERE m4.conv_phone = m1.conv_phone AND m4.direction = 'outbound'
              UNION ALL
              SELECT scr.read_at AS cutoff FROM sms_conversation_reads scr WHERE scr.conv_phone = m1.conv_phone AND scr.user_id = ?
            )),
            '1970-01-01'
          )
        ) AS unread
      FROM sms_messages m1
      GROUP BY conv_phone
    )
  `, userId);

  res.json({ success: true, data: { count: row!.total } });
});

// ---------------------------------------------------------------------------
// SMS follow-up reminders
// ---------------------------------------------------------------------------

router.get('/reminders', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  const status = typeof req.query.status === 'string' ? req.query.status : 'pending';
  const dueOnly = req.query.due === '1' || req.query.due === 'true';
  const phone = typeof req.query.phone === 'string' ? normalizePhone(req.query.phone) : '';
  const id = req.query.id ? Number(req.query.id) : null;

  const where: string[] = ['1=1'];
  const params: unknown[] = [];
  if (id && Number.isFinite(id)) {
    where.push('r.id = ?');
    params.push(id);
  }
  if (status && status !== 'all') {
    where.push('r.status = ?');
    params.push(status);
  }
  if (dueOnly) where.push("r.status = 'pending' AND r.due_at <= datetime('now')");
  if (phone) {
    where.push('r.conv_phone = ?');
    params.push(phone);
  }
  if (!isManagerOrAdmin(req)) {
    where.push('r.created_by = ?');
    params.push(userId);
  }

  const reminders = await adb.all<any>(`
    SELECT r.*,
           TRIM(COALESCE(c.first_name, '') || ' ' || COALESCE(c.last_name, '')) AS customer_name,
           TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) AS created_by_name
    FROM sms_followup_reminders r
    LEFT JOIN customers c ON c.id = r.customer_id
    LEFT JOIN users u ON u.id = r.created_by
    WHERE ${where.join(' AND ')}
    ORDER BY CASE WHEN r.status = 'pending' AND r.due_at <= datetime('now') THEN 0 ELSE 1 END,
             r.due_at ASC
    LIMIT 100
  `, ...params);

  res.json({ success: true, data: { reminders } });
}));

router.post('/reminders', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { phone, label, note } = req.body ?? {};
  const { convPhone } = normalizeReminderPhone(phone);
  const dueAt = parseReminderDueAt(req.body?.due_at);
  const safeLabel = typeof label === 'string' && label.trim() ? label.trim().slice(0, 80) : 'Follow up';
  const safeNote = typeof note === 'string' && note.trim() ? note.trim().slice(0, 1000) : null;

  const customer = await adb.get<any>(`
    SELECT id FROM customers
    WHERE is_deleted = 0 AND (phone = ? OR mobile = ?)
    UNION
    SELECT c.id FROM customers c
    JOIN customer_phones cp ON cp.customer_id = c.id
    WHERE c.is_deleted = 0 AND cp.phone = ?
    LIMIT 1
  `, convPhone, convPhone, convPhone);

  const result = await adb.run(`
    INSERT INTO sms_followup_reminders (conv_phone, phone, customer_id, label, note, due_at, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `, convPhone, String(phone).trim(), customer?.id ?? null, safeLabel, safeNote, dueAt, req.user!.id);

  const reminder = await adb.get<any>('SELECT * FROM sms_followup_reminders WHERE id = ?', result.lastInsertRowid);
  audit(req.db, 'sms_followup_reminder_created', req.user!.id, req.ip || 'unknown', {
    reminder_id: result.lastInsertRowid,
    conv_phone_last4: convPhone.slice(-4),
    due_at: dueAt,
  });
  res.status(201).json({ success: true, data: reminder });
}));

router.post('/reminders/:id/complete', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid reminder id', 400);
  const reminder = await adb.get<any>('SELECT id, created_by FROM sms_followup_reminders WHERE id = ?', id);
  if (!reminder) throw new AppError('Reminder not found', 404);
  requireReminderAccess(req, reminder);

  // BUGHUNT-2026-05-17: guard the UPDATE WHERE status='pending' so a
  // concurrent /cancel or /snooze doesn't get clobbered. CHECK constraint
  // on the column limits to pending/completed/cancelled, so the loser
  // either tried to complete a terminal state (already completed) or had
  // their snooze overridden by this complete.
  const result = await adb.run(`
    UPDATE sms_followup_reminders
    SET status = 'completed', completed_by = ?, completed_at = datetime('now'), updated_at = datetime('now')
    WHERE id = ? AND status = 'pending'
  `, req.user!.id, id);
  if (result.changes === 0) {
    throw new AppError('Reminder status changed; refresh and retry', 409);
  }
  const updated = await adb.get<any>('SELECT * FROM sms_followup_reminders WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

router.post('/reminders/:id/snooze', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid reminder id', 400);
  const reminder = await adb.get<any>('SELECT id, created_by FROM sms_followup_reminders WHERE id = ?', id);
  if (!reminder) throw new AppError('Reminder not found', 404);
  requireReminderAccess(req, reminder);

  const dueAt = parseReminderDueAt(req.body?.due_at);
  // BUGHUNT-2026-05-17: guard the UPDATE WHERE status='pending'. Without
  // this, snoozing a just-completed-or-cancelled reminder silently revives
  // it (status stays 'pending', new due_at lands) — the reminder fires
  // again later despite being terminal.
  const result = await adb.run(`
    UPDATE sms_followup_reminders
    SET status = 'pending', due_at = ?, notified_at = NULL, updated_at = datetime('now')
    WHERE id = ? AND status = 'pending'
  `, dueAt, id);
  if (result.changes === 0) {
    throw new AppError('Reminder status changed; refresh and retry', 409);
  }
  const updated = await adb.get<any>('SELECT * FROM sms_followup_reminders WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

router.delete('/reminders/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid reminder id', 400);
  const reminder = await adb.get<any>('SELECT id, created_by FROM sms_followup_reminders WHERE id = ?', id);
  if (!reminder) throw new AppError('Reminder not found', 404);
  requireReminderAccess(req, reminder);
  // BUGHUNT-2026-05-17: guard the UPDATE WHERE status='pending' so a
  // racing complete doesn't get clobbered by this cancel.
  const result = await adb.run("UPDATE sms_followup_reminders SET status = 'cancelled', updated_at = datetime('now') WHERE id = ? AND status = 'pending'", id);
  if (result.changes === 0) {
    throw new AppError('Reminder status changed; refresh and retry', 409);
  }
  res.json({ success: true, data: { id, status: 'cancelled' } });
}));

// ---------------------------------------------------------------------------
// GET /sms/conversations
// ---------------------------------------------------------------------------
router.get('/conversations', async (req, res) => {
  const adb = req.asyncDb;
  // WEB-S6-034: accept `q=` (debounced server-side search) or legacy `keyword=`.
  const keyword = ((req.query.q as string) || (req.query.keyword as string) || '').trim();
  const includeArchived = req.query.include_archived === '1' || req.query.include_archived === 'true';
  const assignedTo = typeof req.query.assigned_to === 'string' ? req.query.assigned_to : 'all';
  if (!['all', 'me', 'unassigned'].includes(assignedTo)) {
    throw new AppError('assigned_to must be all, me, or unassigned', 400);
  }
  const userId = req.user!.id;

  const where: string[] = [];
  const params: unknown[] = [userId];
  if (assignedTo === 'me') {
    where.push('ca.assigned_user_id = ?');
    params.push(userId);
  } else if (assignedTo === 'unassigned') {
    where.push('ca.assigned_user_id IS NULL');
  }

  const conversations = await adb.all<any>(`
    SELECT
      conv_phone,
      MAX(created_at) as last_message_at,
      (SELECT message FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_message,
      (SELECT direction FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_direction,
      (SELECT status FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_status,
      (SELECT message_type FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_message_type,
      COUNT(*) as message_count,
      (SELECT COUNT(*) FROM sms_messages m3
        WHERE m3.conv_phone = m1.conv_phone AND m3.direction = 'inbound'
        AND m3.created_at > COALESCE(
          (SELECT MAX(cutoff) FROM (
            SELECT MAX(m4.created_at) AS cutoff FROM sms_messages m4 WHERE m4.conv_phone = m1.conv_phone AND m4.direction = 'outbound'
            UNION ALL
            SELECT scr.read_at AS cutoff FROM sms_conversation_reads scr WHERE scr.conv_phone = m1.conv_phone AND scr.user_id = ?
          )),
          '1970-01-01'
        )
      ) as unread_count,
      ca.assigned_user_id,
      ca.assigned_at
    FROM sms_messages m1
    LEFT JOIN conversation_assignments ca ON ca.phone = m1.conv_phone
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    GROUP BY conv_phone
    ORDER BY last_message_at DESC
    LIMIT 200
  `, ...params);

  // --- Batch lookups to avoid N+1 queries ---
  const convPhones = conversations.map((c: any) => c.conv_phone);
  if (convPhones.length === 0) {
    res.json({ success: true, data: { conversations: [] } });
    return;
  }

  // 1) & 2) Batch-fetch flags and customer matches in parallel
  const flagPlaceholders = convPhones.map(() => '?').join(',');
  const [allFlags, customerRows] = await Promise.all([
    adb.all<any>(
      `SELECT conv_phone, is_flagged, is_pinned, is_archived FROM sms_conversation_flags WHERE conv_phone IN (${flagPlaceholders})`,
      ...convPhones
    ),
    adb.all<any>(`
      SELECT c.id, c.first_name, c.last_name, c.phone AS match_phone FROM customers c
      WHERE c.phone IN (${flagPlaceholders}) OR c.mobile IN (${flagPlaceholders})
      UNION
      SELECT c.id, c.first_name, c.last_name, cp.phone AS match_phone FROM customers c
      JOIN customer_phones cp ON cp.customer_id = c.id
      WHERE cp.phone IN (${flagPlaceholders})
    `, ...convPhones, ...convPhones, ...convPhones),
  ]);

  const flagMap = new Map<string, { is_flagged: number; is_pinned: number; is_archived: number }>();
  for (const f of allFlags) flagMap.set(f.conv_phone, f);

  // Build phone -> customer map (first match wins per phone)
  const customerByPhone = new Map<string, { id: number; first_name: string; last_name: string }>();
  for (const row of customerRows) {
    if (!customerByPhone.has(row.match_phone)) {
      customerByPhone.set(row.match_phone, { id: row.id, first_name: row.first_name, last_name: row.last_name });
    }
  }

  // 3) Batch-fetch recent open tickets for all matched customer IDs
  const matchedCustomerIds = [...new Set([...customerByPhone.values()].map(c => c.id))];
  const ticketMap = new Map<number, any>();
  if (matchedCustomerIds.length > 0) {
    const custPlaceholders = matchedCustomerIds.map(() => '?').join(',');
    const ticketRows = await adb.all<any>(`
      SELECT t.id, t.order_id, t.customer_id, ts.name AS status_name, ts.color AS status_color,
             ROW_NUMBER() OVER (PARTITION BY t.customer_id ORDER BY t.created_at DESC) AS rn
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.customer_id IN (${custPlaceholders}) AND (ts.is_closed = 0 OR ts.is_closed IS NULL) AND t.is_deleted = 0
    `, ...matchedCustomerIds);
    for (const t of ticketRows) {
      if (t.rn === 1) {
        ticketMap.set(t.customer_id, { id: t.id, order_id: t.order_id, status_name: t.status_name, status_color: t.status_color });
      }
    }
  }

  // 4) Assemble results using maps (zero per-row queries)
  const withCustomer = conversations.map((conv: any) => {
    const customer = customerByPhone.get(conv.conv_phone) || null;
    const flags = flagMap.get(conv.conv_phone);
    const recent_ticket = customer ? (ticketMap.get(customer.id) || null) : null;
    return {
      ...conv,
      customer,
      recent_ticket,
      is_flagged: !!(flags?.is_flagged),
      is_pinned: !!(flags?.is_pinned),
      is_archived: !!(flags?.is_archived),
    };
  })

  // ENR-SMS7: Filter out archived conversations unless explicitly requested
  const nonArchived = includeArchived
    ? withCustomer
    : withCustomer.filter((c: any) => !c.is_archived);

  const filtered = keyword
    ? nonArchived.filter((c: any) => {
        const q = keyword.toLowerCase();
        const name = c.customer ? `${c.customer.first_name} ${c.customer.last_name}`.toLowerCase() : '';
        return name.includes(q) || c.conv_phone.includes(q);
      })
    : nonArchived;

  const sorted = filtered.sort((a: any, b: any) => {
    if (a.is_pinned && !b.is_pinned) return -1;
    if (!a.is_pinned && b.is_pinned) return 1;
    return 0;
  });

  res.json({ success: true, data: { conversations: sorted } });
});

// ---------------------------------------------------------------------------
// Conversation flag/pin/read + message list (unchanged)
// ---------------------------------------------------------------------------
router.patch('/conversations/:phone/flag', async (req, res) => {
  const adb = req.asyncDb;
  const convPhone = req.params.phone;
  // BUGHUNT-2026-05-17: atomic toggle via CASE inside ON CONFLICT so two
  // concurrent flag clicks don't both read the same is_flagged value and
  // both write the opposite (which cancels out — net zero flips). The
  // VALUES branch inserts is_flagged=1 (default flip from no-row); the
  // CASE in DO UPDATE flips the persisted value. We re-SELECT after to
  // return the post-flip truth to the client even on contention.
  await adb.run(`
    INSERT INTO sms_conversation_flags (conv_phone, is_flagged, updated_at)
    VALUES (?, 1, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET
      is_flagged = CASE WHEN COALESCE(is_flagged, 0) = 1 THEN 0 ELSE 1 END,
      updated_at = datetime('now')
  `, convPhone);
  const fresh = await adb.get<{ is_flagged: number }>(
    'SELECT is_flagged FROM sms_conversation_flags WHERE conv_phone = ?', convPhone,
  );
  res.json({ success: true, data: { conv_phone: convPhone, is_flagged: !!(fresh?.is_flagged) } });
});

router.patch('/conversations/:phone/pin', async (req, res) => {
  const adb = req.asyncDb;
  const convPhone = req.params.phone;
  // BUGHUNT-2026-05-17: atomic CASE toggle (see /flag for shape + why).
  await adb.run(`
    INSERT INTO sms_conversation_flags (conv_phone, is_pinned, updated_at)
    VALUES (?, 1, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET
      is_pinned = CASE WHEN COALESCE(is_pinned, 0) = 1 THEN 0 ELSE 1 END,
      updated_at = datetime('now')
  `, convPhone);
  const fresh = await adb.get<{ is_pinned: number }>(
    'SELECT is_pinned FROM sms_conversation_flags WHERE conv_phone = ?', convPhone,
  );
  res.json({ success: true, data: { conv_phone: convPhone, is_pinned: !!(fresh?.is_pinned) } });
});

router.get('/conversations/:phone', async (req, res) => {
  const adb = req.asyncDb;
  const phone = req.params.phone;

  const [messages, customer] = await Promise.all([
    adb.all<any>(`
      SELECT sm.*, u.first_name || ' ' || u.last_name as sender_name
      FROM sms_messages sm
      LEFT JOIN users u ON u.id = sm.user_id
      WHERE sm.conv_phone = ?
      ORDER BY sm.created_at ASC
      LIMIT 200
    `, phone),
    adb.get<any>(`
      SELECT c.id, c.first_name, c.last_name, c.phone, c.mobile, c.email
      FROM customers c
      WHERE c.phone = ? OR c.mobile = ?
      UNION
      SELECT c.id, c.first_name, c.last_name, c.phone, c.mobile, c.email
      FROM customers c JOIN customer_phones cp ON cp.customer_id = c.id
      WHERE cp.phone = ?
      LIMIT 1
    `, phone, phone, phone),
  ]);

  let recent_tickets: any[] = [];
  if (customer) {
    recent_tickets = await adb.all<any>(`
      SELECT t.id, t.order_id, ts.name AS status_name, ts.color AS status_color,
             (SELECT td.device_name FROM ticket_devices td WHERE td.ticket_id = t.id ORDER BY td.id LIMIT 1) AS device_name,
             t.total, t.created_at
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.customer_id = ? AND t.is_deleted = 0 AND COALESCE(ts.is_closed, 0) = 0 AND COALESCE(ts.is_cancelled, 0) = 0
      ORDER BY t.created_at DESC LIMIT 3
    `, customer.id);
  }

  res.json({ success: true, data: { messages, customer, recent_tickets } });
});

// ENR-SMS7: Archive/unarchive a conversation
router.patch('/conversations/:phone/archive', async (req, res) => {
  const adb = req.asyncDb;
  const convPhone = req.params.phone;
  // BUGHUNT-2026-05-17: atomic CASE toggle (see /flag for shape + why).
  await adb.run(`
    INSERT INTO sms_conversation_flags (conv_phone, is_archived, updated_at)
    VALUES (?, 1, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET
      is_archived = CASE WHEN COALESCE(is_archived, 0) = 1 THEN 0 ELSE 1 END,
      updated_at = datetime('now')
  `, convPhone);
  const fresh = await adb.get<{ is_archived: number }>(
    'SELECT is_archived FROM sms_conversation_flags WHERE conv_phone = ?', convPhone,
  );
  res.json({ success: true, data: { conv_phone: convPhone, is_archived: !!(fresh?.is_archived) } });
});

router.patch('/conversations/:phone/read', async (req, res) => {
  const adb = req.asyncDb;
  const userId = req.user!.id;
  await adb.run(`
    INSERT INTO sms_conversation_reads (conv_phone, user_id, read_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone, user_id) DO UPDATE SET read_at = datetime('now')
  `, req.params.phone, userId);
  res.json({ success: true });
});

// ---------------------------------------------------------------------------
// POST /sms/upload-media — Upload image for MMS (auto-compresses if over 600KB)
// ---------------------------------------------------------------------------
router.post('/upload-media', enforceUploadQuota, mmsUpload.single('file'), fileUploadValidator({ allowedMimes: ALLOWED_MEDIA_TYPES, getTenantDir: (r) => {
  const slug = (r as any).tenantSlug;
  return slug ? path.join(config.uploadsPath, slug, 'mms') : mmsDir;
} }), async (req, res, next) => {
  try {
    if (!req.file) throw new AppError('No file uploaded', 400);
    // BUGHUNT-2026-05-17: rate-limit per user. Image compression is
    // CPU-heavy (Sharp) and a buggy or malicious client could submit
    // thousands of small images per minute to saturate the worker
    // pool; storage quota only catches bytes, not request rate.
    // 60/min is generous for legitimate MMS composition.
    const userId = req.user?.id;
    if (userId && !checkWindowRate(req.db, 'mms_upload', String(userId), 60, 60_000)) {
      try { fs.unlinkSync(req.file.path); } catch {}
      throw new AppError('Too many MMS uploads. Try again shortly.', 429);
    }

    // Auto-compress if needed
    const compressed = await compressIfNeeded(req.file.path, req.file.mimetype);
    const filename = path.basename(compressed);
    const stat = fs.statSync(compressed);

    // Multi-tenant storage quota enforcement — atomic check + reserve in one transaction
    // to prevent races between concurrent uploads.
    if (!reserveStorage(req.tenantId, stat.size, req.tenantLimits?.storageLimitMb ?? null)) {
      try { fs.unlinkSync(compressed); } catch {}
      res.status(403).json({
        success: false,
        upgrade_required: true,
        feature: 'storage_limit',
        message: `Storage limit (${req.tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for 30 GB storage.`,
      });
      return;
    }

    res.json({
      success: true,
      data: {
        url: (req as any).tenantSlug ? `/uploads/${(req as any).tenantSlug}/mms/${filename}` : `/uploads/mms/${filename}`,
        filename,
        contentType: compressed.endsWith('.jpg') ? 'image/jpeg' : req.file.mimetype,
        size: stat.size,
        compressed: compressed !== req.file.path,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// SMS send rate limiter (5 per minute per user) — SQLite-backed
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// POST /sms/send — Send SMS or MMS
// ---------------------------------------------------------------------------
// SEC-M55: Per-tenant daily SMS cap — carrier-fraud containment. A compromised
// user account can otherwise burn thousands of outbound SMS in a few hours
// against toll numbers or number-enumeration bots before the shop notices
// the BlockChyp / Twilio bill. The per-user 5/min limiter above bounds burst
// velocity but not daily volume — an attacker with a steady 5/min drip still
// sends 7200/day. We add a second hard ceiling keyed by the tenant DB so the
// cap is scoped to the shop, not a single user. Default 500/day covers the
// busiest legitimate shops (~10x observed p99); ops can raise via env.
const DAILY_TENANT_SMS_CAP = (() => {
  const n = parseInt(process.env.TENANT_SMS_DAILY_CAP || '500', 10);
  return Number.isFinite(n) && n >= 1 ? n : 500;
})();

function estimateSmsSegments(body: string, isMms: boolean): number {
  if (isMms) return 1;
  const text = body || '';
  if (!text) return 1;
  const gsm7 = /^[\u000A\u000D\u0020-\u007E£¥èéùìòÇØøÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ!"#¤%&'()*+,\-.\/0-9:;<=>?¡A-ZÄÖÑÜ§¿a-zäöñüà{}\\[~\]|^€]*$/.test(text);
  const single = gsm7 ? 160 : 70;
  const multipart = gsm7 ? 153 : 67;
  return text.length <= single ? 1 : Math.ceil(text.length / multipart);
}

async function resolveDailyTenantSmsCap(req: Request, adb: AsyncDb): Promise<number> {
  const row = await adb.get<{ provider?: string | null; tier?: string | null }>(
    `SELECT
       MAX(CASE WHEN key = 'sms_provider_type' THEN value END) AS provider,
       MAX(CASE WHEN key = 'tier' THEN value END) AS tier
     FROM store_config
     WHERE key IN ('sms_provider_type', 'tier')`,
  );
  if (row?.provider !== 'bizarresms') return DAILY_TENANT_SMS_CAP;

  const tier = req.tenantTrialActive
    ? 'trial'
    : String(row?.tier || req.tenantPlan || 'free').toLowerCase();
  if (tier === 'pro_plus' || tier === 'pro+') return 2000;
  if (tier === 'pro') return 500;
  return 50;
}

router.post('/send', async (req, res, next) => {
  try {
    const adb = req.asyncDb;
    const userId = req.user!.id;
    // SECURITY: Key includes tenantSlug to prevent cross-tenant rate limit collision
    const rateLimitKey = `${(req as any).tenantSlug || 'default'}:${userId}`;
    if (!checkWindowRate(req.db, 'sms_send', rateLimitKey, 5, 60000)) {
      throw new AppError('SMS rate limit: max 5 per minute', 429);
    }
    recordWindowFailure(req.db, 'sms_send', rateLimitKey, 60000);

    // SEC-M55: Tenant-wide daily cap (carrier-fraud). Count outbound messages
    // that actually consumed provider quota — exclude 'failed' (never hit
    // wire) and 'simulated' (dev/console provider). We deliberately count
    // 'sending' / 'scheduled' so in-flight messages still debit the ceiling
    // and a burst can't race past it before statuses settle.
    const sentTodayRow = await adb.get<{ n: number }>(
      `SELECT COUNT(*) AS n FROM sms_messages
        WHERE direction = 'outbound'
          AND status NOT IN ('failed','simulated')
          AND created_at > datetime('now', '-1 day')`,
    );
    const sentToday = sentTodayRow?.n ?? 0;
    const dailyTenantSmsCap = await resolveDailyTenantSmsCap(req, adb);
    if (sentToday >= dailyTenantSmsCap) {
      throw new AppError(
        `Daily SMS cap reached (${dailyTenantSmsCap}/day). Contact support to raise the limit.`,
        429,
      );
    }

    const {
      to, message, media, entity_type, entity_id, template_id, template_vars, send_at,
      // SEC-H115: TCPA discriminator — 'marketing' | 'transactional'.
      // Transactional allows admin override for opted-out customers.
      message_type: tcpaSendType,
    } = req.body;
    if (!to) throw new AppError('Recipient phone is required', 400);

    // SEC-H115: Validate TCPA send type if provided
    const TCPA_SEND_TYPES = ['marketing', 'transactional'] as const;
    type TcpaSendType = typeof TCPA_SEND_TYPES[number];
    const validatedSendType: TcpaSendType | undefined =
      tcpaSendType !== undefined
        ? TCPA_SEND_TYPES.includes(tcpaSendType as TcpaSendType)
          ? (tcpaSendType as TcpaSendType)
          : (() => { throw new AppError("message_type must be 'marketing' or 'transactional'", 400); })()
        : undefined;

    // SEC-M10: Input length validation
    if (typeof to === 'string' && to.length > 30) throw new AppError('Phone number too long', 400);
    if (typeof message === 'string' && message.length > 1600) throw new AppError('Message exceeds 1600 characters', 400);

    // SEC-L37: validate the destination is parseable as E.164 BEFORE we
    // insert an outbound row and hand it to the provider. Prior code let
    // garbage phone strings ("hello", "123", "" after trim, emoji) drop
    // straight through to the provider — each rejection was billable
    // provider reject + audit noise, and some providers silently swallow
    // malformed numbers into successful "delivered" callbacks that never
    // actually sent.
    // Accept: leading +, 8-15 digits total (ITU-T E.164 max is 15).
    // Normalised form is 8-15 digits after stripping non-numerics.
    if (typeof to === 'string') {
      const digits = to.replace(/\D/g, '');
      if (digits.length < 8 || digits.length > 15) {
        throw new AppError('Recipient phone is not a valid E.164 number (8-15 digits)', 400);
      }
    }

    // ENR-SMS1 / TZ5: Validate send_at if provided. `validateIsoDate` permits
    // both date-only and naked date-time values without an offset — we need
    // STRICTER rules for SMS scheduling because `new Date("2026-04-10T14:30")`
    // is parsed as the server's LOCAL time, which means a user who typed
    // "2:30 PM their time" can have their message fire at the wrong absolute
    // instant. Require an explicit `Z` or `+HH:MM` / `-HH:MM` offset so the
    // caller must commit to an unambiguous instant.
    let scheduledIso: string | null = null;
    if (send_at) {
      if (typeof send_at !== 'string') {
        throw new AppError('send_at must be an ISO 8601 string with an explicit timezone offset', 400);
      }
      const normalized = validateIsoDate(send_at, 'send_at', false);
      if (normalized) {
        // Reject date-only forms: need at least `T` + time.
        if (!/T\d{2}:\d{2}/.test(normalized)) {
          throw new AppError('send_at must include a time component (YYYY-MM-DDTHH:MM)', 400);
        }
        // Require explicit UTC marker `Z` or a numeric offset like +05:30 / -0800.
        if (!/(Z|[+-]\d{2}:?\d{2})$/.test(normalized)) {
          throw new AppError(
            'send_at must include an explicit timezone offset (e.g. "2026-04-10T14:30:00-05:00" or "2026-04-10T19:30:00Z")',
            400,
          );
        }
        const scheduledTime = new Date(normalized);
        if (isNaN(scheduledTime.getTime())) {
          throw new AppError('Invalid send_at datetime', 400);
        }
        if (scheduledTime.getTime() <= Date.now()) {
          throw new AppError('send_at must be in the future', 400);
        }
        scheduledIso = scheduledTime.toISOString();
      }
    }

    let body = message || '';

    if (template_id && !body) {
      const tpl = await adb.get<any>('SELECT * FROM sms_templates WHERE id = ? AND is_active = 1', template_id);
      if (!tpl) throw new AppError('Template not found', 404);
      body = substituteVars(tpl.content, template_vars || {});
    }

    if (!body.trim() && (!media || media.length === 0)) {
      throw new AppError('Message body or media is required', 400);
    }

    const convPhone = normalizePhone(to);
    const storePhoneRow = await adb.get<any>("SELECT value FROM store_config WHERE key = 'store_phone'");
    const storePhone = storePhoneRow?.value || '';

    // SEC-M56: Per-destination rate limit — max 3 messages per hour to the
    // same normalized phone number. Stops an automated loop / buggy
    // integration from hammering one customer with dozens of identical
    // SMS in a few minutes (happens in the wild when template-render
    // fails and an integration keeps retrying). Keyed on `conv_phone`
    // (the normalized form) so raw "+15551234567" vs "(555) 123-4567"
    // hit the same counter.
    const perDestRate = consumeWindowRate(req.db, 'sms_per_destination', convPhone, 3, 3600_000);
    if (!perDestRate.allowed) {
      throw new AppError(
        `Too many messages to this number. Try again in ${perDestRate.retryAfterSeconds}s.`,
        429,
      );
    }

    // Parse media array
    const mediaItems: MmsMedia[] = [];
    if (media && Array.isArray(media)) {
      for (const m of media) {
        if (m.url && m.contentType) {
          // Convert relative URLs to absolute for provider
          const absoluteUrl = m.url.startsWith('http') ? m.url : `${req.protocol}://${req.get('host')}${m.url}`;
          mediaItems.push({ url: absoluteUrl, contentType: m.contentType });
        }
      }
    }

    const messageType = mediaItems.length > 0 ? 'mms' : 'sms';

    // -------------------------------------------------------------------------
    // SEC-H115: TCPA opt-in gate — must run before provider call AND before
    // writing to sms_messages so an opted-out send never appears in the DB.
    // -------------------------------------------------------------------------
    {
      // Look up the target customer by normalized phone (primary, mobile, or
      // customer_phones table). A non-customer number is allowed through.
      const tcpaCustomer = await adb.get<{
        id: number;
        sms_opt_in: number | null;
        first_name: string;
        last_name: string;
      }>(`
        SELECT c.id, c.sms_opt_in, c.first_name, c.last_name
        FROM customers c
        WHERE (c.phone = ? OR c.mobile = ?) AND c.is_deleted = 0
        UNION
        SELECT c.id, c.sms_opt_in, c.first_name, c.last_name
        FROM customers c
        JOIN customer_phones cp ON cp.customer_id = c.id
        WHERE cp.phone = ? AND c.is_deleted = 0
        LIMIT 1
      `, convPhone, convPhone, convPhone);

      const toCustomerId = tcpaCustomer?.id ?? null;
      const optInState: number | null = tcpaCustomer ? (tcpaCustomer.sms_opt_in ?? null) : null;
      const isAdminUser = req.user!.role === 'admin';
      const isTransactional = validatedSendType === 'transactional';
      const adminOverride = isTransactional && isAdminUser;
      const phoneLast4 = redactPhone(to);

      if (!tcpaCustomer) {
        // Unknown number — allow send; audit so compliance can see the gap.
        audit(req.db, 'sms_sent', userId, req.ip ?? '', {
          to_customer_id: null,
          to_phone_last4: phoneLast4,
          message_type: validatedSendType ?? null,
          opt_in_state: null,
          admin_override: false,
          decision: 'unknown_number_allowed',
        });
      } else if (optInState === 0) {
        // Explicit opt-out: block UNLESS admin sends transactional.
        if (!adminOverride) {
          // Audit the rejected attempt before throwing.
          audit(req.db, 'tcpa_send_blocked', userId, req.ip ?? '', {
            to_customer_id: toCustomerId,
            to_phone_last4: phoneLast4,
            message_type: validatedSendType ?? null,
            opt_in_state: 0,
            admin_override: false,
            decision: 'opt_out_blocked',
          });
          throw new AppError('Customer has opted out of SMS', 403);
        }
        // Admin transactional override — allow but audit clearly.
        audit(req.db, 'sms_sent', userId, req.ip ?? '', {
          to_customer_id: toCustomerId,
          to_phone_last4: phoneLast4,
          message_type: validatedSendType,
          opt_in_state: 0,
          admin_override: true,
          decision: 'transactional_admin_override',
        });
      } else if (optInState === null) {
        // NULL opt-in (never asked) — allow but surface the consent gap.
        audit(req.db, 'tcpa_sms_no_consent', userId, req.ip ?? '', {
          to_customer_id: toCustomerId,
          to_phone_last4: phoneLast4,
          message_type: validatedSendType ?? null,
          opt_in_state: null,
          admin_override: false,
          decision: 'no_consent_allowed',
        });
      } else {
        // sms_opt_in = 1 — explicit consent; standard send audit row.
        audit(req.db, 'sms_sent', userId, req.ip ?? '', {
          to_customer_id: toCustomerId,
          to_phone_last4: phoneLast4,
          message_type: validatedSendType ?? null,
          opt_in_state: 1,
          admin_override: false,
          decision: 'opted_in',
        });
      }
    }
    // -------------------------------------------------------------------------

    // ENR-SMS1: Determine initial status based on scheduling
    const initialStatus = scheduledIso ? 'scheduled' : 'sending';

    // Store outbound message
    const result = await adb.run(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider,
                                entity_type, entity_id, user_id, message_type, media_urls, media_types, send_at)
      VALUES (?, ?, ?, ?, ?, 'outbound', ?, ?, ?, ?, ?, ?, ?, ?)
    `,
      storePhone, to, convPhone, body,
      initialStatus,
      getProviderForDb(req.db, req.tenantSlug).name,
      entity_type || null, entity_id || null, userId,
      messageType,
      mediaItems.length > 0 ? JSON.stringify(mediaItems.map(m => m.url)) : null,
      mediaItems.length > 0 ? JSON.stringify(mediaItems.map(m => m.contentType)) : null,
      scheduledIso,
    );

    const msgId = result.lastInsertRowid;

    // ENR-SMS1: If scheduled, don't send now — return the stored message
    if (scheduledIso) {
      const msg = await adb.get<any>('SELECT * FROM sms_messages WHERE id = ?', msgId);
      res.status(201).json({ success: true, data: msg });
      return;
    }

    // Send via provider (immediate).
    // AUDIT L3: We MUST check providerResult.success and providerResult.simulated
    // before marking the message as 'sent'. Previously we trusted any non-thrown
    // call, which meant ConsoleProvider dev sends looked like real deliveries
    // to the rest of the app (inflated usage counters, "sent" status in UI).
    const providerResult = await sendSmsTenant(req.db, req.tenantSlug, to, body, storePhone, mediaItems.length > 0 ? mediaItems : undefined);
    const providerOk = providerResult.success === true && providerResult.simulated !== true;

    if (providerOk) {
      await adb.run(`
        UPDATE sms_messages SET status = 'sent', provider = ?, provider_message_id = ?, updated_at = datetime('now')
        WHERE id = ?
      `, providerResult.providerName, providerResult.providerId || null, msgId);

      // Track usage for tier enforcement. Only count REAL sends — simulated /
      // failed sends do not consume a tenant's quota.
      // SEC-L36: fail-closed. Prior version was fire-and-forget: if the
      // dynamic import or incrementSmsCount threw, the error was logged
      // but the counter was silently left unincremented — an attacker
      // could exploit any route that reliably crashes the counter path
      // to exceed the tenant's plan quota without ever paying for the
      // overage. Now we await the path AND mark the message with a
      // `usage_tracked = 0` tombstone when counting fails, so ops can
      // reconcile and rate-limit the tenant if desync is material.
      try {
        const { incrementSmsCount } = await import('../services/usageTracker.js');
        await incrementSmsCount(req.tenantId, estimateSmsSegments(body, mediaItems.length > 0));
      } catch (e: unknown) {
        logger.error('sms analytics update failed (fail-closed)', {
          msgId,
          tenantId: req.tenantId ?? null,
          error: e instanceof Error ? e.message : String(e),
        });
        try {
          await adb.run(
            "UPDATE sms_messages SET error = COALESCE(error, '') || '; usage_untracked' WHERE id = ?",
            msgId,
          );
        } catch {
          // If we can't even tag the message, the log line above is the
          // only record — accept that rather than cascade failures.
        }
      }
    } else {
      // Distinguish dev-simulated vs real provider failure so operators can tell
      // them apart in the DB and in the UI.
      const dbStatus = providerResult.simulated ? 'simulated' : 'failed';
      const errText = providerResult.error
        || (providerResult.simulated ? 'Simulated send (console provider)' : 'Unknown error');
      await adb.run(`
        UPDATE sms_messages SET status = ?, provider = ?, error = ?, updated_at = datetime('now')
        WHERE id = ?
      `, dbStatus, providerResult.providerName, errText, msgId);

      logger.warn('outbound sms not delivered', {
        msgId,
        // SEC-M56: redact recipient to last-4 — full phone is customer PII.
        toRedacted: redactPhone(to),
        providerName: providerResult.providerName,
        simulated: providerResult.simulated === true,
        error: errText,
      });
    }

    const msg = await adb.get<any>('SELECT * FROM sms_messages WHERE id = ?', msgId);
    // Preserve the { success: true, data: X } envelope shape — the Express
    // request itself succeeded even if the provider didn't. The `status`
    // field inside `data` tells callers whether the SMS actually went out.
    res.status(201).json({
      success: true,
      data: msg,
      meta: {
        provider: providerResult.providerName,
        simulated: providerResult.simulated === true,
        delivered: providerOk,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// Templates CRUD
// ---------------------------------------------------------------------------

// SCAN-532: template mutations are manager/admin-only — ordinary staff must
// not be able to create, edit, or delete shared SMS templates.
function requireManagerOrAdmin(req: Request): void {
  const role = (req as any).user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Manager or admin role required', 403);
  }
}

// WEB-UIUX-690: known-token registry. Template content uses single-brace
// `{var}` substitution on the auto-feedback + automations paths; the bulk-
// SMS customers path uses `{{var}}`. Reject any token outside the known
// set so a `{first_nam}` typo doesn't silently send the literal text to a
// thousand recipients. Matches both single and double braces.
const KNOWN_SMS_TEMPLATE_VARS = new Set([
  'customer_name', 'first_name', 'last_name',
  'ticket_id', 'order_id',
  'device_name', 'store_name', 'store_phone',
  'amount', 'balance', 'invoice_id',
  'appointment_date', 'appointment_time',
  'estimate_id', 'estimate_total',
]);

function findUnknownTemplateTokens(content: string): string[] {
  const tokens = new Set<string>();
  // Match {key} and {{key}} forms; trim outer braces in the capture group.
  const re = /\{\{?([a-zA-Z0-9_]+)\}?\}/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(content)) !== null) {
    tokens.add(m[1]);
  }
  const unknown: string[] = [];
  for (const t of tokens) {
    if (!KNOWN_SMS_TEMPLATE_VARS.has(t)) unknown.push(t);
  }
  return unknown.sort();
}

router.get('/templates', async (req, res) => {
  const adb = req.asyncDb;
  const templates = await adb.all<any>('SELECT * FROM sms_templates WHERE is_active = 1 ORDER BY category, name');
  // ENR-SMS5: Include available template variables for documentation.
  // WEB-UIUX-690: this is now the authoritative known-token set; keep
  // KNOWN_SMS_TEMPLATE_VARS above in sync if you add anything.
  const available_variables = Array.from(KNOWN_SMS_TEMPLATE_VARS).sort();
  res.json({ success: true, data: { templates, available_variables } });
});

router.post('/templates', async (req, res) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const { name, content, category } = req.body;
  if (!name || !content) throw new AppError('Name and content required', 400);
  // WEB-UIUX-690: reject unknown tokens up-front so the operator catches
  // the typo at save time, not when 1000 SMS go out with literal
  // "{first_nam}" in the body.
  const unknown = findUnknownTemplateTokens(String(content));
  if (unknown.length > 0) {
    throw new AppError(
      `Unknown template token(s): ${unknown.map((t) => `{${t}}`).join(', ')}. Allowed: ${Array.from(KNOWN_SMS_TEMPLATE_VARS).sort().join(', ')}`,
      400,
    );
  }
  const result = await adb.run('INSERT INTO sms_templates (name, content, category) VALUES (?, ?, ?)', name, content, category || null);
  const tpl = await adb.get<any>('SELECT * FROM sms_templates WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: tpl });
});

router.put('/templates/:id', async (req, res) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const { name, content, category, is_active } = req.body;
  // WEB-UIUX-690: same guard on PUT — bad token shape never gets persisted.
  if (content !== undefined && content !== null) {
    const unknown = findUnknownTemplateTokens(String(content));
    if (unknown.length > 0) {
      throw new AppError(
        `Unknown template token(s): ${unknown.map((t) => `{${t}}`).join(', ')}. Allowed: ${Array.from(KNOWN_SMS_TEMPLATE_VARS).sort().join(', ')}`,
        400,
      );
    }
  }
  await adb.run(`
    UPDATE sms_templates SET
      name = COALESCE(?, name), content = COALESCE(?, content),
      category = COALESCE(?, category), is_active = COALESCE(?, is_active)
    WHERE id = ?
  `, name ?? null, content ?? null, category ?? null, is_active ?? null, req.params.id);
  const tpl = await adb.get<any>('SELECT * FROM sms_templates WHERE id = ?', req.params.id);
  res.json({ success: true, data: tpl });
});

router.delete('/templates/:id', async (req, res) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  await adb.run('UPDATE sms_templates SET is_active = 0 WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Template deleted' } });
});

router.post('/preview-template', async (req, res) => {
  const adb = req.asyncDb;
  const { template_id, vars } = req.body;
  // SCAN-535: sms_templates has no tenant_id column (see migration 001_initial.sql).
  // Tenant isolation is enforced at the DB-file level — each tenant has its own
  // SQLite file so `req.asyncDb` already scopes every query to the correct tenant.
  // Per-row tenant_id scoping is therefore not needed here.
  const tpl = await adb.get<any>('SELECT * FROM sms_templates WHERE id = ?', template_id);
  if (!tpl) throw new AppError('Template not found', 404);
  const preview = substituteVars(tpl.content, vars || {});
  res.json({ success: true, data: { preview, char_count: preview.length } });
});

export default router;

// ---------------------------------------------------------------------------
// Inbound SMS/MMS webhook handler (public, no auth)
// ---------------------------------------------------------------------------
export async function smsInboundWebhookHandler(req: Request, res: Response): Promise<void> {
  try {
    const db = req.db;
    const adb = req.asyncDb;
    const provider = getSmsProvider();

    if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
      logger.warn('sms inbound webhook signature verification failed', {
        ip: req.ip,
        provider: provider.name ?? 'unknown',
      });
      res.status(403).json({ success: false, message: 'Invalid signature' });
      return;
    }

    if (!provider.parseInboundWebhook) {
      res.status(200).json({ success: true });
      return;
    }

    const parsed: InboundMessage | null = provider.parseInboundWebhook(req);
    if (!parsed) {
      res.status(200).json({ success: true });
      return;
    }

    const { from, to, body: msgBody, providerId, media, messageType } = parsed;
    const convPhone = normalizePhone(from);

    // Download and store inbound MMS media locally
    let mediaLocalPaths: string[] = [];
    let mediaUrls: string[] = [];
    let mediaTypes: string[] = [];

    if (media && media.length > 0) {
      for (const m of media) {
        mediaUrls.push(m.url);
        mediaTypes.push(m.contentType);
        try {
          // SEC-H93: Validate MMS media URL against the provider allowlist before
          // fetching. A forged (or signature-bypassed) webhook can supply an
          // attacker-controlled URL; without this check the server would act as
          // an SSRF proxy and could reach internal network resources.
          validateProviderUrl(m.url, ALLOWED_MMS_HOSTS, 'mms media fetch');
          const MAX_MMS_SIZE = 10 * 1024 * 1024; // 10MB
          const ALLOWED_MMS_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/3gpp'];
          const controller = new AbortController();
          const timeout = setTimeout(() => controller.abort(), 10_000); // 10s timeout
          const resp = await fetch(m.url, { signal: controller.signal, redirect: 'error' });
          clearTimeout(timeout);
          if (resp.ok) {
            // Validate content-type from response headers before writing to disk
            const respContentType = (resp.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
            if (respContentType && !ALLOWED_MMS_CONTENT_TYPES.includes(respContentType)) {
              logger.warn('mms unexpected content-type from server, skipping', {
                url: m.url,
                respContentType,
              });
              continue;
            }
            const contentLength = parseInt(resp.headers.get('content-length') || '0', 10);
            if (contentLength > MAX_MMS_SIZE) {
              logger.warn('mms media too large (content-length), skipping', {
                url: m.url,
                contentLength,
                maxSize: MAX_MMS_SIZE,
              });
              continue;
            }
            const chunks: Buffer[] = [];
            let totalSize = 0;
            const reader = resp.body?.getReader();
            if (!reader) continue;
            let oversize = false;
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              totalSize += value.byteLength;
              if (totalSize > MAX_MMS_SIZE) {
                reader.cancel();
                logger.warn('mms media exceeded 10MB during download, skipping', {
                  url: m.url,
                  totalSize,
                  maxSize: MAX_MMS_SIZE,
                });
                oversize = true;
                break;
              }
              chunks.push(Buffer.from(value));
            }
            if (oversize) continue;
            const buffer = Buffer.concat(chunks);
            // Use the actual response content-type for extension if available, fall back to provider-reported type
            const effectiveType = respContentType || m.contentType;
            const ext = effectiveType.includes('png') ? '.png' :
                        effectiveType.includes('gif') ? '.gif' :
                        effectiveType.includes('webp') ? '.webp' :
                        effectiveType.includes('mp4') ? '.mp4' :
                        effectiveType.includes('3gpp') ? '.3gp' : '.jpg';
            const filename = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`;
            const filepath = path.join(mmsDir, filename);
            fs.writeFileSync(filepath, buffer);
            const slug = (req as any).tenantSlug;
            mediaLocalPaths.push(slug ? `/uploads/${slug}/mms/${filename}` : `/uploads/mms/${filename}`);
          }
        } catch (err) {
          // L8-SMS (rerun §24): structured warn so MMS download failures aren't lost.
          logger.warn('mms failed to download media', {
            url: m.url,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    }

    // Store inbound message
    const result = await adb.run(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider,
                                provider_message_id, message_type, media_urls, media_types, media_local_paths)
      VALUES (?, ?, ?, ?, 'delivered', 'inbound', ?, ?, ?, ?, ?, ?)
    `,
      from, to || '', convPhone, msgBody, provider.name, providerId || null,
      messageType || 'sms',
      mediaUrls.length > 0 ? JSON.stringify(mediaUrls) : null,
      mediaTypes.length > 0 ? JSON.stringify(mediaTypes) : null,
      mediaLocalPaths.length > 0 ? JSON.stringify(mediaLocalPaths) : null,
    );

    const msg = await adb.get<any>('SELECT * FROM sms_messages WHERE id = ?', result.lastInsertRowid);

    // ENR-SMS4: Check for opt-out keywords (STOP, UNSUBSCRIBE, CANCEL)
    const OPT_OUT_KEYWORDS = ['stop', 'unsubscribe', 'cancel'];
    const bodyTrimmed = (msgBody || '').trim().toLowerCase();
    if (OPT_OUT_KEYWORDS.includes(bodyTrimmed)) {
      // Set sms_opt_in = 0 for any customer matching this phone
      const [optOutCustomers, cpCustomers] = await Promise.all([
        adb.all<{ id: number }>(
          'SELECT id FROM customers WHERE phone = ? OR mobile = ?',
          convPhone, convPhone
        ),
        adb.all<{ id: number }>(
          'SELECT DISTINCT customer_id AS id FROM customer_phones WHERE phone = ?',
          convPhone
        ),
      ]);
      const allIds = [...new Set([...optOutCustomers.map(c => c.id), ...cpCustomers.map(c => c.id)])];

      for (const custId of allIds) {
        await adb.run('UPDATE customers SET sms_opt_in = 0, updated_at = datetime(\'now\') WHERE id = ?', custId);
        audit(db, 'sms_opt_out', null, 'webhook', { customer_id: custId, phone: convPhone, keyword: bodyTrimmed });
      }
      if (allIds.length > 0) {
        // Structured info log so opt-out events land in the ops dashboard.
        logger.info('sms opt-out keyword received', {
          convPhone,
          keyword: bodyTrimmed,
          optedOutCount: allIds.length,
        });
      }
    }

    // Auto-responder: attempt rule match on non-opt-out inbound messages.
    // Wrapped in try/catch so any matcher failure never breaks the 2xx webhook response.
    // Skip entirely if the inbound body was an opt-out keyword (STOP/UNSUBSCRIBE/CANCEL)
    // so we don't auto-reply after the customer has already opted out.
    if (!OPT_OUT_KEYWORDS.includes(bodyTrimmed)) {
      // SCAN-530: check sms_opt_in before firing auto-responder — a customer
      // who has set opt_in=0 must not receive any automated outbound message.
      const arOptInRow = await adb.get<{ sms_opt_in: number | null }>(
        'SELECT sms_opt_in FROM customers WHERE phone = ? OR mobile = ? LIMIT 1',
        convPhone, convPhone,
      );
      const arOptedOut = arOptInRow && arOptInRow.sms_opt_in === 0;

      if (arOptedOut) {
        logger.info('sms auto-responder skipped — customer opted out', {
          fromRedacted: redactPhone(from),
        });
      } else {
      try {
        const match = await tryAutoRespond(adb, {
          from: convPhone,
          body: msgBody,
          tenant_slug: (req as any).tenantSlug ?? undefined,
        });
        if (match.matched && match.response) {
          const { sendSmsTenant } = await import('../services/smsProvider.js');
          await sendSmsTenant(db, (req as any).tenantSlug ?? null, convPhone, match.response);

          // Record the auto-responder outbound message
          await adb.run(`
            INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto-responder', datetime('now'), datetime('now'))
          `, to || '', convPhone, convPhone, match.response);

          audit(db, 'sms_auto_responder_matched', null, 'webhook', {
            responder_id: match.responder_id,
            inbound_from: redactPhone(from),
          });
          logger.info('sms auto-responder fired', {
            responder_id: match.responder_id,
            fromRedacted: redactPhone(from),
          });
        }
      } catch (autoResponderErr) {
        logger.error('sms auto-responder block failed', {
          error: autoResponderErr instanceof Error ? autoResponderErr.message : String(autoResponderErr),
        });
      }
      } // end: !arOptedOut
    }

    // Match phone to customer — include sms_opt_in so SCAN-531 can reuse this row.
    const customer = await adb.get<any>(
      'SELECT id, first_name, last_name, sms_opt_in FROM customers WHERE phone = ? OR mobile = ? LIMIT 1',
      convPhone, convPhone
    );

    // F6: Auto-update ticket status on customer reply
    // Only move status forward if ticket is currently in a "waiting" category to avoid regressing active tickets
    if (customer) {
      try {
        const autoFlag = await adb.get<any>("SELECT value FROM store_config WHERE key = 'ticket_auto_status_on_reply'");
        if (autoFlag?.value === '1' || autoFlag?.value === 'true') {
          const openTicket = await adb.get<any>(`
            SELECT t.id, ts.name AS status_name FROM tickets t
            LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
            WHERE t.customer_id = ? AND t.is_deleted = 0 AND COALESCE(ts.is_closed, 0) = 0 AND COALESCE(ts.is_cancelled, 0) = 0
            ORDER BY t.created_at DESC LIMIT 1
          `, customer.id);
          if (openTicket) {
            // Only auto-change if current status is a "waiting" category
            const statusLower = (openTicket.status_name || '').toLowerCase();
            const isWaiting = statusLower.includes('waiting') || statusLower.includes('hold')
              || statusLower.includes('pending') || statusLower.includes('transit');
            if (isWaiting) {
              const openStatus = await adb.get<any>("SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 ORDER BY sort_order LIMIT 1");
              if (openStatus) {
                await adb.run('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?',
                  openStatus.id, new Date().toISOString().replace('T', ' ').substring(0, 19), openTicket.id);
              }
            }
          }
        }
      } catch (e) {
        // L8-SMS (rerun §24): auto-status-on-reply should never silently die.
        // Log with the ticket context so operators can find and fix broken rules.
        logger.error('sms auto-status-on-reply failed', {
          convPhone,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }

    // WEB-UIUX-954: estimate auto-approve on "YES" reply. The outbound
    // estimate-send SMS body literally says "Reply YES to approve" — but
    // before this handler there was no inbound parser for it, so the
    // promise was hollow. Match a customer who has a `status='sent'`
    // estimate within the last 30 days and flip it to approved. We do
    // this AFTER the auto-responder so an operator-configured custom
    // responder still gets a chance to handle exact-match keywords.
    if (customer && bodyTrimmed === 'yes') {
      try {
        const recentEstimate = await adb.get<{ id: number; order_id: string }>(
          `SELECT id, order_id FROM estimates
            WHERE customer_id = ?
              AND status = 'sent'
              AND created_at > datetime('now', '-30 days')
            ORDER BY id DESC LIMIT 1`,
          customer.id,
        );
        if (recentEstimate) {
          // BUGHUNT-2026-05-17: guard the UPDATE WHERE status='sent'. The
          // SELECT precheck is TOCTOU racy — a portal approve, portal
          // reject, or shop-side estimates.routes.ts reject landing between
          // the SELECT and this UPDATE would otherwise be silently
          // overwritten to 'approved' by this SMS path. If we lost the race,
          // skip the signature INSERT + audit, but let the rest of the
          // inbound-SMS handler (broadcast, auto-reply) continue.
          const smsApproveResult = await adb.run(
            `UPDATE estimates
               SET status = 'approved',
                   approved_at = datetime('now'),
                   updated_at = datetime('now')
             WHERE id = ? AND status = 'sent'`,
            recentEstimate.id,
          );
          if (smsApproveResult.changes === 0) {
            logger.info('sms_yes_estimate_skipped_status_changed', {
              estimate_id: recentEstimate.id,
              reason: 'concurrent portal/staff action moved status off sent',
            });
          } else {
          // Mirror portal flow — write an estimate_signatures audit row
          // anchored to the SMS reply so the shop has compliance evidence.
          try {
            const customerName = [customer.first_name, customer.last_name]
              .filter(Boolean)
              .join(' ')
              .trim() || 'SMS reply';
            await adb.run(
              `INSERT INTO estimate_signatures
                 (estimate_id, signer_name, signer_email, signer_ip,
                  signature_data_url, signed_at, user_agent)
               VALUES (?, ?, NULL, ?, NULL, datetime('now'), ?)`,
              recentEstimate.id,
              `${customerName} (SMS YES reply)`,
              `sms:${convPhone}`,
              `inbound-sms:${(req as any).tenantSlug ?? ''}`,
            );
          } catch (sigErr) {
            logger.warn('sms_yes_estimate_signature_write_failed', {
              estimate_id: recentEstimate.id,
              error: sigErr instanceof Error ? sigErr.message : String(sigErr),
            });
          }
          audit(db, 'estimate_approved_via_sms', null, 'webhook', {
            estimate_id: recentEstimate.id,
            order_id: recentEstimate.order_id,
            customer_id: customer.id,
            from: redactPhone(from),
          });
          logger.info('estimate approved via SMS YES reply', {
            estimate_id: recentEstimate.id,
            customer_id: customer.id,
          });
          } // end else (smsApproveResult had changes)
        }
      } catch (yesErr) {
        logger.error('sms_yes_estimate_approve_failed', {
          customer_id: customer.id,
          error: yesErr instanceof Error ? yesErr.message : String(yesErr),
        });
      }
    }

    broadcast(WS_EVENTS.SMS_RECEIVED, { message: msg, customer: customer || null }, req.tenantSlug || null);

    // ENR-SMS6: Auto-reply when outside business hours
    try {
      const autoReplyEnabled = await adb.get<any>("SELECT value FROM store_config WHERE key = 'auto_reply_enabled'");
      if (autoReplyEnabled?.value === '1' || autoReplyEnabled?.value === 'true') {
        const [hoursRow, replyMsgRow, tzRow] = await Promise.all([
          adb.get<any>("SELECT value FROM store_config WHERE key = 'business_hours'"),
          adb.get<any>("SELECT value FROM store_config WHERE key = 'auto_reply_message'"),
          adb.get<any>("SELECT value FROM store_config WHERE key = 'store_timezone'"),
        ]);

        if (hoursRow?.value && replyMsgRow?.value) {
          // AUDIT TZ1: Day-of-week and local time must be computed IN the tenant's
          // timezone. The old code called `new Date().getDay()` (UTC) and tried to
          // patch it with a broken string parse; on Sunday 11pm MDT this returned
          // Monday's hours. Use Intl.DateTimeFormat parts which always respect the
          // timeZone option and are available in the Node runtime.
          const tz = tzRow?.value || 'America/Denver';
          const dayNames = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

          let todayKey = 'sun';
          let currentMinutes = 0;
          try {
            const parts = new Intl.DateTimeFormat('en-US', {
              timeZone: tz,
              weekday: 'short',
              hour: '2-digit',
              minute: '2-digit',
              hour12: false,
            }).formatToParts(new Date());
            const weekdayPart = parts.find(p => p.type === 'weekday')?.value || '';
            const hourPart = parts.find(p => p.type === 'hour')?.value || '0';
            const minutePart = parts.find(p => p.type === 'minute')?.value || '0';

            const weekdayToKey: Record<string, string> = {
              Sun: 'sun', Mon: 'mon', Tue: 'tue', Wed: 'wed',
              Thu: 'thu', Fri: 'fri', Sat: 'sat',
            };
            todayKey = weekdayToKey[weekdayPart] || dayNames[new Date().getUTCDay()];

            // `hour: '2-digit', hour12: false` returns '24' at midnight in some
            // Node/ICU combinations — normalize to 0.
            const h = parseInt(hourPart, 10);
            const m = parseInt(minutePart, 10);
            currentMinutes = ((h === 24 ? 0 : h) * 60) + (isNaN(m) ? 0 : m);
          } catch (tzErr) {
            logger.warn('auto-reply tz parse failed, defaulting to UTC', {
              tz,
              error: (tzErr as Error).message,
            });
            const fallback = new Date();
            todayKey = dayNames[fallback.getUTCDay()];
            currentMinutes = fallback.getUTCHours() * 60 + fallback.getUTCMinutes();
          }

          let isOutsideHours = true;
          try {
            const hours = JSON.parse(hoursRow.value);
            const todayHours = hours[todayKey];
            if (todayHours?.open && todayHours?.close) {
              const [openH, openM] = todayHours.open.split(':').map(Number);
              const [closeH, closeM] = todayHours.close.split(':').map(Number);
              const openMinutes = openH * 60 + openM;
              const closeMinutes = closeH * 60 + closeM;
              if (currentMinutes >= openMinutes && currentMinutes < closeMinutes) {
                isOutsideHours = false;
              }
            }
            // If no hours defined for today (e.g., Sunday), it stays outside hours
          } catch {
            isOutsideHours = false; // If we can't parse hours, don't auto-reply
          }

          if (isOutsideHours) {
            // SCAN-531: skip auto-reply if customer has opted out of SMS.
            // `customer` already includes sms_opt_in (fetched above).
            if (customer && customer.sms_opt_in === 0) {
              logger.info('sms auto-reply skipped — customer opted out', {
                fromRedacted: redactPhone(from),
              });
            } else if (
              // WEB-UIUX-691: loop-detection / per-sender 24h rate-limit.
              // Without this an auto-reply whose body fragments accidentally
              // match an automation trigger (or another customer-side
              // auto-responder) re-fires every inbound message, draining
              // Twilio credit. Skip when we've already sent an auto-reply
              // outbound to this conv_phone within the configurable
              // cooldown window.
              // WEB-UIUX-945: read auto_reply_cooldown_hours from
              // store_config so the previously hardcoded 24h is tunable
              // per tenant (low-volume shops 48h, high-volume 4h, etc.).
              // Bounded [1, 168] (1h - 1 week) to prevent operator typos
              // from disabling the suppression entirely.
              await (async () => {
                const cooldownRow = await adb.get<{ value?: string }>(
                  `SELECT value FROM store_config WHERE key = 'auto_reply_cooldown_hours'`,
                );
                let cooldownHours = parseInt(cooldownRow?.value ?? '24', 10);
                if (!Number.isFinite(cooldownHours) || cooldownHours <= 0) cooldownHours = 24;
                cooldownHours = Math.min(168, Math.max(1, cooldownHours));
                const row = await adb.get<{ c: number }>(
                  `SELECT COUNT(*) AS c
                     FROM sms_messages
                    WHERE conv_phone = ?
                      AND direction = 'outbound'
                      AND provider IN ('auto-reply', 'auto-responder')
                      AND created_at > datetime('now', ?)`,
                  convPhone,
                  `-${cooldownHours} hours`,
                );
                return (row?.c ?? 0) > 0;
              })()
            ) {
              logger.info('sms auto-reply suppressed — already replied to this sender within the configured cooldown window', {
                fromRedacted: redactPhone(from),
              });
            } else {
            const [storeNameRow, storePhoneRow] = await Promise.all([
              adb.get<any>("SELECT value FROM store_config WHERE key = 'store_name'"),
              adb.get<any>("SELECT value FROM store_config WHERE key = 'store_phone'"),
            ]);
            const customerObj = customer as any;
            const replyBody = replyMsgRow.value
              .replace(/\{customer_name\}/g, customerObj?.first_name || 'there')
              .replace(/\{store_name\}/g, storeNameRow?.value || 'our store')
              .replace(/\{store_phone\}/g, storePhoneRow?.value || '');

            const { sendSmsTenant } = await import('../services/smsProvider.js');
            await sendSmsTenant(db, (req as any).tenantSlug ?? null, from, replyBody);

            // Record the auto-reply
            await adb.run(`
              INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, created_at, updated_at)
              VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto-reply', datetime('now'), datetime('now'))
            `, to || '', from, convPhone, replyBody);
            // SEC-M56: redact sender — full inbound phone is customer PII.
            logger.info('sms auto-reply sent off-hours', { fromRedacted: redactPhone(from) });
            } // end: !arOptedOut (SCAN-531)
          }
        }
      }
    } catch (autoReplyErr) {
      logger.error('sms auto-reply failed', {
        error: autoReplyErr instanceof Error ? autoReplyErr.message : String(autoReplyErr),
      });
    }

    res.status(200).json({ success: true });
  } catch (err: any) {
    // L8-SMS (rerun §24): surface inbound-webhook pipeline failures in structured logs.
    logger.error('sms inbound webhook pipeline crashed', {
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });
    res.status(200).json({ success: false, error: 'Internal processing error' });
  }
}

// ---------------------------------------------------------------------------
// Delivery status webhook handler (public, no auth)
// ---------------------------------------------------------------------------
export async function smsStatusWebhookHandler(req: Request, res: Response): Promise<void> {
  try {
    const adb = req.asyncDb;
    const provider = getSmsProvider();

    // Verify webhook signature (same pattern as inbound webhook)
    if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
      logger.warn('sms status webhook signature verification failed', {
        ip: req.ip,
        provider: provider.name ?? 'unknown',
      });
      res.status(403).json({ success: false, message: 'Invalid signature' });
      return;
    }

    if (!provider.parseStatusWebhook) {
      res.status(200).json({ success: true });
      return;
    }

    const status = provider.parseStatusWebhook(req);
    if (!status) {
      res.status(200).json({ success: true });
      return;
    }

    const updates: string[] = ['status = ?', "updated_at = datetime('now')"];
    const params: any[] = [status.status];

    if (status.status === 'delivered') {
      updates.push("delivered_at = datetime('now')");
    }
    if (status.errorCode) {
      updates.push('error = ?');
      params.push(`${status.errorCode}: ${status.errorMessage || ''}`);
    }

    params.push(status.providerId);
    await adb.run(`UPDATE sms_messages SET ${updates.join(', ')} WHERE provider_message_id = ?`, ...params);

    // Broadcast status update
    broadcast(WS_EVENTS.SMS_STATUS_UPDATED, { providerId: status.providerId, status: status.status }, req.tenantSlug || null);

    res.status(200).json({ success: true });
  } catch (err: any) {
    // L8-SMS (rerun §24): never silently swallow status webhook failures.
    logger.error('sms status webhook pipeline crashed', {
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });
    res.status(200).json({ success: false });
  }
}
