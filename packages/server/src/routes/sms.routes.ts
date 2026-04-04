import { Router, Request, Response } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { sendSms, getSmsProvider } from '../services/smsProvider.js';
import { broadcast } from '../ws/server.js';
import { WS_EVENTS } from '@bizarre-crm/shared';

const router = Router();

// Substitute template variables
function substituteVars(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => vars[key] ?? `{{${key}}}`);
}

// GET /sms/conversations
router.get('/conversations', (req, res) => {
  const keyword = (req.query.keyword as string || '').trim();
  const userId = req.user!.id;

  const conversations = db.prepare(`
    SELECT
      conv_phone,
      MAX(created_at) as last_message_at,
      (SELECT message FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_message,
      (SELECT direction FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_direction,
      (SELECT status FROM sms_messages m2 WHERE m2.conv_phone = m1.conv_phone ORDER BY m2.created_at DESC LIMIT 1) as last_status,
      COUNT(*) as message_count,
      -- unread = inbound messages after the later of (last outbound, last read)
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
  `).all(userId);

  // Attach customer info + flags
  const flagStmt = db.prepare('SELECT is_flagged, is_pinned FROM sms_conversation_flags WHERE conv_phone = ?');
  const withCustomer = conversations.map((conv: any) => {
    const customer = db.prepare(`
      SELECT c.id, c.first_name, c.last_name FROM customers c
      WHERE c.phone = ? OR c.mobile = ?
      UNION
      SELECT c.id, c.first_name, c.last_name FROM customers c
      JOIN customer_phones cp ON cp.customer_id = c.id
      WHERE cp.phone = ?
      LIMIT 1
    `).get(conv.conv_phone, conv.conv_phone, conv.conv_phone);
    const flags = flagStmt.get(conv.conv_phone) as any;
    // Find most recent open ticket for this customer
    let recent_ticket: any = null;
    if (customer) {
      recent_ticket = db.prepare(`
        SELECT t.id, t.order_id, ts.name AS status_name, ts.color AS status_color
        FROM tickets t
        LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
        WHERE t.customer_id = ? AND (ts.is_closed = 0 OR ts.is_closed IS NULL)
        ORDER BY t.created_at DESC LIMIT 1
      `).get((customer as any).id) || null;
    }
    return {
      ...conv,
      customer,
      recent_ticket,
      is_flagged: !!(flags?.is_flagged),
      is_pinned: !!(flags?.is_pinned),
    };
  });

  // Filter by keyword (customer name or phone) if provided
  const filtered = keyword
    ? withCustomer.filter((c: any) => {
        const q = keyword.toLowerCase();
        const name = c.customer ? `${c.customer.first_name} ${c.customer.last_name}`.toLowerCase() : '';
        return name.includes(q) || c.conv_phone.includes(q);
      })
    : withCustomer;

  // Sort: pinned first, then by last message time
  const sorted = filtered.sort((a: any, b: any) => {
    if (a.is_pinned && !b.is_pinned) return -1;
    if (!a.is_pinned && b.is_pinned) return 1;
    return 0; // Keep original time-based ordering within groups
  });

  res.json({ success: true, data: { conversations: sorted } });
});

// PATCH /sms/conversations/:phone/flag - Toggle flagged state
router.patch('/conversations/:phone/flag', (req, res) => {
  const convPhone = req.params.phone;
  const existing = db.prepare('SELECT is_flagged FROM sms_conversation_flags WHERE conv_phone = ?').get(convPhone) as any;
  const newVal = existing ? (existing.is_flagged ? 0 : 1) : 1;

  db.prepare(`
    INSERT INTO sms_conversation_flags (conv_phone, is_flagged, updated_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET is_flagged = ?, updated_at = datetime('now')
  `).run(convPhone, newVal, newVal);

  res.json({ success: true, data: { conv_phone: convPhone, is_flagged: !!newVal } });
});

// PATCH /sms/conversations/:phone/pin - Toggle pinned state
router.patch('/conversations/:phone/pin', (req, res) => {
  const convPhone = req.params.phone;
  const existing = db.prepare('SELECT is_pinned FROM sms_conversation_flags WHERE conv_phone = ?').get(convPhone) as any;
  const newVal = existing ? (existing.is_pinned ? 0 : 1) : 1;

  db.prepare(`
    INSERT INTO sms_conversation_flags (conv_phone, is_pinned, updated_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone) DO UPDATE SET is_pinned = ?, updated_at = datetime('now')
  `).run(convPhone, newVal, newVal);

  res.json({ success: true, data: { conv_phone: convPhone, is_pinned: !!newVal } });
});

// GET /sms/conversations/:phone
router.get('/conversations/:phone', (req, res) => {
  const messages = db.prepare(`
    SELECT sm.*, u.first_name || ' ' || u.last_name as sender_name
    FROM sms_messages sm
    LEFT JOIN users u ON u.id = sm.user_id
    WHERE sm.conv_phone = ?
    ORDER BY sm.created_at ASC
    LIMIT 200
  `).all(req.params.phone);

  const customer = db.prepare(`
    SELECT c.id, c.first_name, c.last_name, c.phone, c.mobile, c.email
    FROM customers c
    WHERE c.phone = ? OR c.mobile = ?
    UNION
    SELECT c.id, c.first_name, c.last_name, c.phone, c.mobile, c.email
    FROM customers c
    JOIN customer_phones cp ON cp.customer_id = c.id
    WHERE cp.phone = ?
    LIMIT 1
  `).get(req.params.phone, req.params.phone, req.params.phone);

  // Find most recent open tickets for this customer
  let recent_tickets: any[] = [];
  if (customer) {
    recent_tickets = db.prepare(`
      SELECT t.id, t.order_id, ts.name AS status_name, ts.color AS status_color,
             (SELECT td.device_name FROM ticket_devices td WHERE td.ticket_id = t.id ORDER BY td.id LIMIT 1) AS device_name,
             t.total, t.created_at
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.customer_id = ? AND t.is_deleted = 0 AND COALESCE(ts.is_closed, 0) = 0 AND COALESCE(ts.is_cancelled, 0) = 0
      ORDER BY t.created_at DESC
      LIMIT 3
    `).all((customer as any).id);
  }

  res.json({ success: true, data: { messages, customer, recent_tickets } });
});

// PATCH /sms/conversations/:phone/read
router.patch('/conversations/:phone/read', (req, res) => {
  const userId = req.user!.id;
  const convPhone = req.params.phone;

  db.prepare(`
    INSERT INTO sms_conversation_reads (conv_phone, user_id, read_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(conv_phone, user_id) DO UPDATE SET read_at = datetime('now')
  `).run(convPhone, userId);

  res.json({ success: true });
});

// SMS send rate limiter (5 per minute per user)
const smsSendLimiter = new Map<number, { count: number; resetAt: number }>();

// POST /sms/send
router.post('/send', async (req, res, next) => {
  try {
    const userId = req.user!.id;
    const now = Date.now();
    const entry = smsSendLimiter.get(userId);
    if (entry && now < entry.resetAt && entry.count >= 5) {
      throw new AppError('SMS rate limit: max 5 per minute', 429);
    }
    if (!entry || now >= entry.resetAt) {
      smsSendLimiter.set(userId, { count: 1, resetAt: now + 60000 });
    } else {
      entry.count++;
    }

    const { to, message, entity_type, entity_id, template_id, template_vars } = req.body;
    if (!to) throw new AppError('Recipient phone is required', 400);

    let body = message || '';

    // If template_id provided, substitute vars
    if (template_id && !body) {
      const tpl = db.prepare('SELECT * FROM sms_templates WHERE id = ? AND is_active = 1').get(template_id) as any;
      if (!tpl) throw new AppError('Template not found', 404);
      body = substituteVars(tpl.content, template_vars || {});
    }

    if (!body.trim()) throw new AppError('Message body is required', 400);

    // Normalize phone for conv_phone
    const convPhone = to.replace(/\D/g, '').replace(/^1/, '');

    const storePhone = (db.prepare("SELECT value FROM store_config WHERE key = 'store_phone'").get() as any)?.value || '';

    // Store outbound message with 'sending' status
    const result = db.prepare(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, user_id)
      VALUES (?, ?, ?, ?, 'sending', 'outbound', ?, ?, ?, ?)
    `).run(
      storePhone,
      to, convPhone, body,
      getSmsProvider().name,
      entity_type || null, entity_id || null, req.user!.id
    );

    const msgId = result.lastInsertRowid;

    // Actually send via the active provider
    const providerResult = await sendSms(to, body, storePhone);

    if (providerResult.success) {
      db.prepare(`
        UPDATE sms_messages SET status = 'sent', provider = ?, provider_message_id = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(providerResult.providerName, providerResult.providerId || null, msgId);
    } else {
      db.prepare(`
        UPDATE sms_messages SET status = 'failed', provider = ?, error = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(providerResult.providerName, providerResult.error || 'Unknown error', msgId);
    }

    const msg = db.prepare('SELECT * FROM sms_messages WHERE id = ?').get(msgId);
    res.status(201).json({ success: true, data: msg });
  } catch (err) {
    next(err);
  }
});

// GET /sms/templates
router.get('/templates', (_req, res) => {
  const templates = db.prepare('SELECT * FROM sms_templates WHERE is_active = 1 ORDER BY category, name').all();
  res.json({ success: true, data: { templates } });
});

// POST /sms/templates
router.post('/templates', (req, res) => {
  const { name, content, category } = req.body;
  if (!name || !content) throw new AppError('Name and content required', 400);
  const result = db.prepare('INSERT INTO sms_templates (name, content, category) VALUES (?, ?, ?)').run(name, content, category || null);
  const tpl = db.prepare('SELECT * FROM sms_templates WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: { template: tpl } });
});

// PUT /sms/templates/:id
router.put('/templates/:id', (req, res) => {
  const { name, content, category, is_active } = req.body;
  db.prepare(`
    UPDATE sms_templates SET
      name = COALESCE(?, name), content = COALESCE(?, content),
      category = COALESCE(?, category), is_active = COALESCE(?, is_active)
    WHERE id = ?
  `).run(name ?? null, content ?? null, category ?? null, is_active ?? null, req.params.id);
  const tpl = db.prepare('SELECT * FROM sms_templates WHERE id = ?').get(req.params.id);
  res.json({ success: true, data: { template: tpl } });
});

// DELETE /sms/templates/:id
router.delete('/templates/:id', (req, res) => {
  db.prepare('UPDATE sms_templates SET is_active = 0 WHERE id = ?').run(req.params.id);
  res.json({ success: true, data: { message: 'Template deleted' } });
});

// POST /sms/preview-template - preview a template with variables
router.post('/preview-template', (req, res) => {
  const { template_id, vars } = req.body;
  const tpl = db.prepare('SELECT * FROM sms_templates WHERE id = ?').get(template_id) as any;
  if (!tpl) throw new AppError('Template not found', 404);
  const preview = substituteVars(tpl.content, vars || {});
  res.json({ success: true, data: { preview, char_count: preview.length } });
});

export default router;

// --- Inbound webhook handler (public, no auth) ---
// Exported separately so index.ts can mount it without authMiddleware
export function smsInboundWebhookHandler(req: Request, res: Response): void {
  try {
    const provider = getSmsProvider();

    // Verify webhook signature if provider supports it
    if (provider.verifyWebhookSignature && !provider.verifyWebhookSignature(req)) {
      console.warn('[SMS Webhook] Signature verification failed');
      res.status(403).json({ success: false, message: 'Invalid signature' });
      return;
    }

    if (!provider.parseInboundWebhook) {
      // Provider doesn't support inbound parsing — just acknowledge
      res.status(200).json({ success: true, data: { message: 'No inbound parser for current provider' } });
      return;
    }

    const parsed = provider.parseInboundWebhook(req);
    if (!parsed) {
      res.status(200).json({ success: true, data: { message: 'Could not parse inbound message' } });
      return;
    }

    const { from, to, body: msgBody, providerId } = parsed;

    // Normalize phone for conv_phone
    const convPhone = from.replace(/\D/g, '').replace(/^1/, '');

    // Store inbound message
    const result = db.prepare(`
      INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, provider_message_id)
      VALUES (?, ?, ?, ?, 'delivered', 'inbound', ?, ?)
    `).run(from, to || '', convPhone, msgBody, provider.name, providerId || null);

    const msg = db.prepare('SELECT * FROM sms_messages WHERE id = ?').get(result.lastInsertRowid) as any;

    // Try to match phone to a customer
    const customer = db.prepare(`
      SELECT id, first_name, last_name FROM customers
      WHERE phone = ? OR mobile = ? LIMIT 1
    `).get(convPhone, convPhone) as any;

    // F6: Auto-update ticket status when customer replies via SMS
    if (customer) {
      try {
        const autoStatusOnReply = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_auto_status_on_reply'").get() as any;
        if (autoStatusOnReply?.value === '1' || autoStatusOnReply?.value === 'true') {
          // Find customer's most recent open ticket
          const openTicket = db.prepare(`
            SELECT t.id FROM tickets t
            LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
            WHERE t.customer_id = ? AND t.is_deleted = 0 AND COALESCE(ts.is_closed, 0) = 0 AND COALESCE(ts.is_cancelled, 0) = 0
            ORDER BY t.created_at DESC LIMIT 1
          `).get(customer.id) as any;
          if (openTicket) {
            // Change to "Waiting on customer" → customer replied → change to "Open" or first non-closed status
            const openStatus = db.prepare("SELECT id FROM ticket_statuses WHERE is_closed = 0 AND is_cancelled = 0 ORDER BY sort_order LIMIT 1").get() as any;
            if (openStatus) {
              db.prepare('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ?')
                .run(openStatus.id, new Date().toISOString().replace('T', ' ').substring(0, 19), openTicket.id);
            }
          }
        }
      } catch (e) {
        // Non-critical — don't fail SMS processing
        console.error('[SMS] Auto-status-on-reply error:', (e as Error).message);
      }
    }

    // Broadcast to all connected clients
    broadcast(WS_EVENTS.SMS_RECEIVED, { message: msg, customer: customer || null });

    // Providers expect 200 OK
    res.status(200).json({ success: true });
  } catch (err: any) {
    console.error('[SMS Webhook] Error processing inbound:', err.message);
    // Still return 200 so the provider doesn't retry endlessly
    res.status(200).json({ success: false, error: 'Internal processing error' });
  }
}
