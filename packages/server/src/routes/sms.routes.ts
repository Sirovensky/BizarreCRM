import { Router, Request, Response } from 'express';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import multer from 'multer';
import { config } from '../config.js';
import { AppError } from '../middleware/errorHandler.js';
import { sendSms, getSmsProvider } from '../services/smsProvider.js';
import type { MmsMedia, InboundMessage } from '../services/smsProvider.js';
import { broadcast } from '../ws/server.js';
import { normalizePhone } from '../utils/phone.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { reserveStorage } from '../services/usageTracker.js';
import { WS_EVENTS } from '@bizarre-crm/shared';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();

// --- MMS media upload config ---
const MMS_MAX_SIZE = 5 * 1024 * 1024; // 5MB upload limit
const MMS_COMPRESS_THRESHOLD = 600 * 1024; // 600KB — compress images over this for MMS
const ALLOWED_MEDIA_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

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
      const MIME_TO_EXT: Record<string, string> = {
        'image/jpeg': '.jpg', 'image/png': '.png',
        'image/gif': '.gif', 'image/webp': '.webp',
      };
      const ext = MIME_TO_EXT[file.mimetype] || '.jpg';
      cb(null, `${Date.now()}-${crypto.randomBytes(4).toString('hex')}${ext}`);
    },
  }),
  limits: { fileSize: MMS_MAX_SIZE },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_MEDIA_TYPES.includes(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPEG, PNG, GIF, WebP images are allowed'));
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

    let pipeline = sharp(filePath).resize(1600, 1600, { fit: 'inside', withoutEnlargement: true });

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
    console.warn('[MMS] Image compression failed, using original:', (err as Error).message);
    return filePath;
  }
}

// Substitute template variables
function substituteVars(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => vars[key] ?? `{{${key}}}`);
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
// GET /sms/conversations
// ---------------------------------------------------------------------------
router.get('/conversations', async (req, res) => {
  const adb = req.asyncDb;
  const keyword = (req.query.keyword as string || '').trim();
  const includeArchived = req.query.include_archived === '1' || req.query.include_archived === 'true';
  const userId = req.user!.id;

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
      ) as unread_count
    FROM sms_messages m1
    GROUP BY conv_phone
    ORDER BY last_message_at DESC
    LIMIT 200
  `, userId);

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
  const existing = await adb.get<any>('SELECT is_flagged FROM sms_conversation_flags WHERE conv_phone = ?', convPhone);
  const newVal = existing ? (existing.is_flagged ? 0 : 1) : 1;
  await adb.run(`
    INSERT INTO sms_conversation_flags (conv_phone, is_flagged, updated_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET is_flagged = ?, updated_at = datetime('now')
  `, convPhone, newVal, newVal);
  res.json({ success: true, data: { conv_phone: convPhone, is_flagged: !!newVal } });
});

router.patch('/conversations/:phone/pin', async (req, res) => {
  const adb = req.asyncDb;
  const convPhone = req.params.phone;
  const existing = await adb.get<any>('SELECT is_pinned FROM sms_conversation_flags WHERE conv_phone = ?', convPhone);
  const newVal = existing ? (existing.is_pinned ? 0 : 1) : 1;
  await adb.run(`
    INSERT INTO sms_conversation_flags (conv_phone, is_pinned, updated_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET is_pinned = ?, updated_at = datetime('now')
  `, convPhone, newVal, newVal);
  res.json({ success: true, data: { conv_phone: convPhone, is_pinned: !!newVal } });
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
  const existing = await adb.get<any>('SELECT is_archived FROM sms_conversation_flags WHERE conv_phone = ?', convPhone);
  const newVal = existing ? (existing.is_archived ? 0 : 1) : 1;
  await adb.run(`
    INSERT INTO sms_conversation_flags (conv_phone, is_archived, updated_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET is_archived = ?, updated_at = datetime('now')
  `, convPhone, newVal, newVal);
  res.json({ success: true, data: { conv_phone: convPhone, is_archived: !!newVal } });
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
router.post('/upload-media', mmsUpload.single('file'), async (req, res, next) => {
  try {
    if (!req.file) throw new AppError('No file uploaded', 400);

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

    const { to, message, media, entity_type, entity_id, template_id, template_vars, send_at } = req.body;
    if (!to) throw new AppError('Recipient phone is required', 400);

    // SEC-M10: Input length validation
    if (typeof to === 'string' && to.length > 30) throw new AppError('Phone number too long', 400);
    if (typeof message === 'string' && message.length > 1600) throw new AppError('Message exceeds 1600 characters', 400);

    // ENR-SMS1: Validate send_at if provided
    if (send_at) {
      const scheduledTime = new Date(send_at);
      if (isNaN(scheduledTime.getTime())) throw new AppError('Invalid send_at datetime', 400);
      if (scheduledTime.getTime() <= Date.now()) throw new AppError('send_at must be in the future', 400);
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

    // ENR-SMS1: Determine initial status based on scheduling
    const initialStatus = send_at ? 'scheduled' : 'sending';

    // Store outbound message
    const result = await adb.run(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider,
                                entity_type, entity_id, user_id, message_type, media_urls, media_types, send_at)
      VALUES (?, ?, ?, ?, ?, 'outbound', ?, ?, ?, ?, ?, ?, ?, ?)
    `,
      storePhone, to, convPhone, body,
      initialStatus,
      getSmsProvider().name,
      entity_type || null, entity_id || null, userId,
      messageType,
      mediaItems.length > 0 ? JSON.stringify(mediaItems.map(m => m.url)) : null,
      mediaItems.length > 0 ? JSON.stringify(mediaItems.map(m => m.contentType)) : null,
      send_at ? new Date(send_at).toISOString() : null,
    );

    const msgId = result.lastInsertRowid;

    // ENR-SMS1: If scheduled, don't send now — return the stored message
    if (send_at) {
      const msg = await adb.get<any>('SELECT * FROM sms_messages WHERE id = ?', msgId);
      res.status(201).json({ success: true, data: msg });
      return;
    }

    // Send via provider (immediate)
    const providerResult = await sendSms(to, body, storePhone, mediaItems.length > 0 ? mediaItems : undefined);

    if (providerResult.success) {
      await adb.run(`
        UPDATE sms_messages SET status = 'sent', provider = ?, provider_message_id = ?, updated_at = datetime('now')
        WHERE id = ?
      `, providerResult.providerName, providerResult.providerId || null, msgId);

      // Track usage for tier enforcement
      import('../services/usageTracker.js').then(({ incrementSmsCount }) => {
        incrementSmsCount(req.tenantId);
      }).catch(() => {});
    } else {
      await adb.run(`
        UPDATE sms_messages SET status = 'failed', provider = ?, error = ?, updated_at = datetime('now')
        WHERE id = ?
      `, providerResult.providerName, providerResult.error || 'Unknown error', msgId);
    }

    const msg = await adb.get<any>('SELECT * FROM sms_messages WHERE id = ?', msgId);
    res.status(201).json({ success: true, data: msg });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// Templates CRUD
// ---------------------------------------------------------------------------
router.get('/templates', async (req, res) => {
  const adb = req.asyncDb;
  const templates = await adb.all<any>('SELECT * FROM sms_templates WHERE is_active = 1 ORDER BY category, name');
  // ENR-SMS5: Include available template variables for documentation
  const available_variables = [
    'customer_name', 'first_name', 'last_name', 'ticket_id',
    'device_name', 'store_name', 'store_phone', 'order_id',
  ];
  res.json({ success: true, data: { templates, available_variables } });
});

router.post('/templates', async (req, res) => {
  const adb = req.asyncDb;
  const { name, content, category } = req.body;
  if (!name || !content) throw new AppError('Name and content required', 400);
  const result = await adb.run('INSERT INTO sms_templates (name, content, category) VALUES (?, ?, ?)', name, content, category || null);
  const tpl = await adb.get<any>('SELECT * FROM sms_templates WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: tpl });
});

router.put('/templates/:id', async (req, res) => {
  const adb = req.asyncDb;
  const { name, content, category, is_active } = req.body;
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
  const adb = req.asyncDb;
  await adb.run('UPDATE sms_templates SET is_active = 0 WHERE id = ?', req.params.id);
  res.json({ success: true, data: { message: 'Template deleted' } });
});

router.post('/preview-template', async (req, res) => {
  const adb = req.asyncDb;
  const { template_id, vars } = req.body;
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
      console.warn('[SMS Webhook] Signature verification failed');
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
          const MAX_MMS_SIZE = 10 * 1024 * 1024; // 10MB
          const ALLOWED_MMS_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/3gpp'];
          const controller = new AbortController();
          const timeout = setTimeout(() => controller.abort(), 10_000); // 10s timeout
          const resp = await fetch(m.url, { signal: controller.signal });
          clearTimeout(timeout);
          if (resp.ok) {
            // Validate content-type from response headers before writing to disk
            const respContentType = (resp.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
            if (respContentType && !ALLOWED_MMS_CONTENT_TYPES.includes(respContentType)) {
              console.warn('[MMS] Unexpected content-type from server, skipping:', m.url, respContentType);
              continue;
            }
            const contentLength = parseInt(resp.headers.get('content-length') || '0', 10);
            if (contentLength > MAX_MMS_SIZE) {
              console.warn('[MMS] Media too large (content-length), skipping:', m.url, contentLength);
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
                console.warn('[MMS] Media exceeded 10MB during download, skipping:', m.url);
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
          console.warn('[MMS] Failed to download media:', m.url, (err as Error).message);
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
        console.log(`[SMS Opt-Out] ${convPhone} sent "${bodyTrimmed}" — opted out ${allIds.length} customer(s)`);
      }
    }

    // Match phone to customer
    const customer = await adb.get<any>(
      'SELECT id, first_name, last_name FROM customers WHERE phone = ? OR mobile = ? LIMIT 1',
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
        console.error('[SMS] Auto-status-on-reply error:', (e as Error).message);
      }
    }

    broadcast(WS_EVENTS.SMS_RECEIVED, { message: msg, customer: customer || null }, req.tenantSlug || null);

    // ENR-SMS6: Auto-reply when outside business hours
    try {
      const autoReplyEnabled = await adb.get<any>("SELECT value FROM store_config WHERE key = 'auto_reply_enabled'");
      if (autoReplyEnabled?.value === '1') {
        const [hoursRow, replyMsgRow, tzRow] = await Promise.all([
          adb.get<any>("SELECT value FROM store_config WHERE key = 'business_hours'"),
          adb.get<any>("SELECT value FROM store_config WHERE key = 'auto_reply_message'"),
          adb.get<any>("SELECT value FROM store_config WHERE key = 'store_timezone'"),
        ]);

        if (hoursRow?.value && replyMsgRow?.value) {
          const tz = tzRow?.value || 'America/Denver';
          const nowLocal = new Date();
          const dayNames = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
          const localDay = dayNames[parseInt(nowLocal.toLocaleString('en-US', { weekday: 'narrow', timeZone: tz }).length > 0
            ? String(new Date().toLocaleString('en-US', { timeZone: tz }).split(',')[0] ? nowLocal.getDay() : 0)
            : '0')];
          // More reliable: get day of week in timezone
          const dayOfWeek = new Date(nowLocal.toLocaleString('en-US', { timeZone: tz })).getDay();
          const todayKey = dayNames[dayOfWeek];

          let isOutsideHours = true;
          try {
            const hours = JSON.parse(hoursRow.value);
            const todayHours = hours[todayKey];
            if (todayHours?.open && todayHours?.close) {
              const localTimeStr = nowLocal.toLocaleString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz });
              const [hourStr, minStr] = localTimeStr.split(':');
              const currentMinutes = parseInt(hourStr) * 60 + parseInt(minStr);
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
            console.log(`[SMS AutoReply] Sent off-hours reply to ${from}`);
          }
        }
      }
    } catch (autoReplyErr) {
      console.error('[SMS AutoReply] Error:', (autoReplyErr as Error).message);
    }

    res.status(200).json({ success: true });
  } catch (err: any) {
    console.error('[SMS Webhook] Error:', err.message);
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
      console.warn('[SMS Status Webhook] Signature verification failed');
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
    broadcast('sms:status_updated', { providerId: status.providerId, status: status.status }, req.tenantSlug || null);

    res.status(200).json({ success: true });
  } catch (err: any) {
    console.error('[SMS Status Webhook] Error:', err.message);
    res.status(200).json({ success: false });
  }
}
