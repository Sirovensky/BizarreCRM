import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { normalizePhone } from '../utils/phone.js';
import { sendSms } from '../services/smsProvider.js';
import { audit } from '../utils/audit.js';

const router = Router();

type AnyRow = Record<string, any>;

// ---------------------------------------------------------------------------
// Rate limiters
// ---------------------------------------------------------------------------

const rateLimiters = {
  quickTrack: new Map<string, number[]>(),   // IP -> timestamps (5/min)
  login: new Map<string, number[]>(),         // IP -> timestamps (5/15min)
  sendCode: new Map<string, number[]>(),      // phone -> timestamps (3/hour)
  sendCodeIp: new Map<string, number>(),      // IP -> last timestamp (1/5s)
};

function checkRate(map: Map<string, number[]>, key: string, maxRequests: number, windowMs: number): boolean {
  const now = Date.now();
  const timestamps = map.get(key) || [];
  const filtered = timestamps.filter(t => now - t < windowMs);
  if (filtered.length >= maxRequests) return false;
  filtered.push(now);
  map.set(key, filtered);
  return true;
}

// Clean up rate limiter maps every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const map of [rateLimiters.quickTrack, rateLimiters.login]) {
    for (const [k, v] of map) {
      const filtered = v.filter(t => now - t < 15 * 60 * 1000);
      if (filtered.length === 0) map.delete(k); else map.set(k, filtered);
    }
  }
  for (const [k, v] of rateLimiters.sendCode) {
    const filtered = v.filter(t => now - t < 60 * 60 * 1000);
    if (filtered.length === 0) rateLimiters.sendCode.delete(k); else rateLimiters.sendCode.set(k, filtered);
  }
  for (const [k, v] of rateLimiters.sendCodeIp) {
    if (now - v > 60000) rateLimiters.sendCodeIp.delete(k);
  }
}, 5 * 60 * 1000);

// ---------------------------------------------------------------------------
// Portal auth middleware
// ---------------------------------------------------------------------------

interface PortalRequest extends Request {
  portalCustomerId?: number;
  portalScope?: 'ticket' | 'full';
  portalTicketId?: number | null;
  portalSessionToken?: string;
}

function portalAuth(req: PortalRequest, res: Response, next: NextFunction): void {
  const db = req.db;
  const authHeader = req.headers.authorization;
  const queryToken = req.query.token as string | undefined;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : queryToken;

  if (!token) {
    res.status(401).json({ success: false, message: 'Authentication required' });
    return;
  }

  const session = db.prepare(`
    SELECT customer_id, scope, ticket_id, token
    FROM portal_sessions
    WHERE token = ? AND expires_at > datetime('now')
  `).get(token) as AnyRow | undefined;

  if (!session) {
    res.status(401).json({ success: false, message: 'Session expired or invalid' });
    return;
  }

  // Update last_used_at
  db.prepare("UPDATE portal_sessions SET last_used_at = datetime('now') WHERE token = ?").run(token);

  req.portalCustomerId = session.customer_id;
  req.portalScope = session.scope as 'ticket' | 'full';
  req.portalTicketId = session.ticket_id;
  req.portalSessionToken = session.token;
  next();
}

/** Require full scope (account login) */
function requireFullScope(req: PortalRequest, res: Response, next: NextFunction): void {
  if (req.portalScope !== 'full') {
    res.status(403).json({ success: false, message: 'Full account access required. Create a free account for full access.' });
    return;
  }
  next();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function normaliseOrderId(raw: string): string {
  let cleaned = raw.trim().toUpperCase();
  if (cleaned.startsWith('T-')) cleaned = cleaned.substring(2);
  const num = parseInt(cleaned, 10);
  if (isNaN(num)) return raw.trim();
  return `T-${String(num).padStart(4, '0')}`;
}

function generateToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

function getStoreConfig(db: any): Record<string, string> {
  const rows = db.prepare(`
    SELECT key, value FROM store_config
    WHERE key IN ('store_name', 'store_phone', 'store_email', 'store_address',
                  'store_city', 'store_state', 'store_zip', 'store_hours',
                  'store_logo', 'store_website')
  `).all() as AnyRow[];
  const config: Record<string, string> = {};
  for (const r of rows) config[r.key] = r.value;
  return config;
}

function getTicketDetail(db: any, ticketId: number): Record<string, any> | null {
  const ticket = db.prepare(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.due_on,
           t.subtotal, t.discount, t.total_tax, t.total, t.invoice_id,
           c.first_name AS c_first_name, c.last_name AS c_last_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.id = ? AND t.is_deleted = 0
  `).get(ticketId) as AnyRow | undefined;

  if (!ticket) return null;

  const devices = db.prepare(`
    SELECT td.id, td.device_name, td.device_type, td.imei, td.serial,
           ts.name AS status_name, td.due_on, td.additional_notes,
           td.price, td.total, td.service_name
    FROM ticket_devices td
    LEFT JOIN ticket_statuses ts ON ts.id = td.status_id
    WHERE td.ticket_id = ?
  `).all(ticket.id) as AnyRow[];

  // Build combined timeline: history + SMS + customer notes (no internal notes)
  const history = db.prepare(`
    SELECT action, description, old_value, new_value, created_at
    FROM ticket_history WHERE ticket_id = ?
    ORDER BY created_at ASC
  `).all(ticket.id) as AnyRow[];

  // Get SMS messages linked to this ticket
  const smsMessages = db.prepare(`
    SELECT sm.message, sm.direction, sm.created_at
    FROM sms_messages sm
    WHERE sm.entity_type = 'ticket' AND sm.entity_id = ?
    ORDER BY sm.created_at ASC
    LIMIT 50
  `).all(ticket.id) as AnyRow[];

  // Get customer-visible notes (diagnostic + customer, NOT internal)
  const messages = db.prepare(`
    SELECT tn.id, tn.content, tn.type, tn.created_at,
           COALESCE(u.first_name || ' ' || u.last_name, u.username) AS author
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.ticket_id = ? AND tn.type IN ('customer', 'diagnostic')
    ORDER BY tn.created_at DESC
    LIMIT 50
  `).all(ticket.id) as AnyRow[];

  // Combine into a single timeline
  const timeline: { type: string; description: string; detail?: string; created_at: string }[] = [];

  for (const h of history) {
    if (h.action === 'customer_message') continue; // shown in messages section
    timeline.push({
      type: 'status',
      description: h.description || `Status changed to ${h.new_value || 'unknown'}`,
      created_at: h.created_at,
    });
  }

  for (const sm of smsMessages) {
    timeline.push({
      type: sm.direction === 'inbound' ? 'sms_in' : 'sms_out',
      description: sm.direction === 'inbound' ? 'You sent a message' : 'We sent you a message',
      detail: sm.message,
      created_at: sm.created_at,
    });
  }

  for (const m of messages) {
    timeline.push({
      type: m.type === 'customer' ? 'customer_msg' : 'diagnostic',
      description: m.type === 'customer' ? 'You sent a message via portal' : 'Diagnostic update',
      detail: m.content,
      created_at: m.created_at,
    });
  }

  // Sort timeline chronologically
  timeline.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

  // Find invoice
  let invoice: AnyRow | null = null;
  if (ticket.invoice_id) {
    invoice = db.prepare('SELECT * FROM invoices WHERE id = ?').get(ticket.invoice_id) as AnyRow | null;
  }
  if (!invoice) {
    invoice = db.prepare('SELECT * FROM invoices WHERE ticket_id = ? LIMIT 1').get(ticket.id) as AnyRow | null;
  }

  let invoiceData = null;
  if (invoice) {
    const lineItems = db.prepare(
      'SELECT description, quantity, unit_price, line_discount, tax_amount, total FROM invoice_line_items WHERE invoice_id = ?'
    ).all(invoice.id) as AnyRow[];
    const payments = db.prepare(
      'SELECT amount, method, created_at, notes FROM payments WHERE invoice_id = ?'
    ).all(invoice.id) as AnyRow[];
    invoiceData = {
      order_id: invoice.order_id,
      status: invoice.status,
      subtotal: invoice.subtotal,
      discount: invoice.discount,
      tax: invoice.total_tax,
      total: invoice.total,
      amount_paid: invoice.amount_paid,
      amount_due: invoice.amount_due,
      line_items: lineItems,
      payments: payments.map(p => ({ amount: p.amount, method: p.method, date: p.created_at })),
    };
  }

  // Check for existing feedback
  const feedback = db.prepare(
    'SELECT rating, comment, responded_at FROM customer_feedback WHERE ticket_id = ? LIMIT 1'
  ).get(ticket.id) as AnyRow | undefined;

  // Get check-in notes (first diagnostic note, which is typically the intake description)
  const checkinNotes = db.prepare(`
    SELECT content FROM ticket_notes
    WHERE ticket_id = ? AND type = 'diagnostic'
    ORDER BY created_at ASC LIMIT 1
  `).get(ticket.id) as AnyRow | undefined;

  return {
    id: ticket.id,
    order_id: ticket.order_id,
    status: { name: ticket.status_name, color: ticket.status_color, is_closed: !!ticket.status_is_closed },
    customer_first_name: ticket.c_first_name ?? null,
    due_on: ticket.due_on ?? null,
    created_at: ticket.created_at,
    updated_at: ticket.updated_at,
    checkin_notes: checkinNotes?.content ?? null,
    devices: devices.map(d => ({
      id: d.id,
      name: d.device_name,
      type: d.device_type,
      service: d.service_name,
      imei: d.imei,
      serial: d.serial,
      status: d.status_name,
      price: d.price,
      total: d.total,
      due_on: d.due_on,
      notes: d.additional_notes,
    })),
    timeline,
    messages,
    invoice: invoiceData,
    feedback: feedback ? { rating: feedback.rating, comment: feedback.comment, responded_at: feedback.responded_at } : null,
    store: getStoreConfig(db),
  };
}

// ---------------------------------------------------------------------------
// POST /quick-track — Ticket ID + last 4 phone digits
// ---------------------------------------------------------------------------
router.post('/quick-track', asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkRate(rateLimiters.quickTrack, ip, 3, 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Please wait 60 seconds before trying again.' });
    return;
  }

  const { order_id, phone_last4 } = req.body as { order_id?: string; phone_last4?: string };

  if (!order_id || !phone_last4) {
    res.status(400).json({ success: false, message: 'Ticket ID and last 4 digits of phone are required' });
    return;
  }

  const digits = phone_last4.replace(/\D/g, '');
  if (digits.length !== 4) {
    res.status(400).json({ success: false, message: 'Please enter exactly 4 digits' });
    return;
  }

  const normId = normaliseOrderId(order_id);

  // Find ticket and verify customer phone matches
  const ticket = db.prepare(`
    SELECT t.id, t.customer_id, t.order_id,
           c.phone AS c_phone, c.mobile AS c_mobile
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE t.order_id = ? AND t.is_deleted = 0
  `).get(normId) as AnyRow | undefined;

  if (!ticket || !ticket.customer_id) {
    // Don't reveal whether ticket exists or not
    audit(db, 'quick_track_failed', null, ip, { order_id: normId, reason: 'ticket_not_found' });
    res.status(404).json({ success: false, message: 'No matching repair found. Please check your ticket ID and phone number.' });
    return;
  }

  // Check phone match against customer's phones (main + additional)
  const customerPhones = [
    normalizePhone(ticket.c_phone),
    normalizePhone(ticket.c_mobile),
  ];

  const additionalPhones = db.prepare(
    'SELECT phone FROM customer_phones WHERE customer_id = ?'
  ).all(ticket.customer_id) as AnyRow[];
  for (const p of additionalPhones) {
    customerPhones.push(normalizePhone(p.phone));
  }

  const phoneMatch = customerPhones.some(p => p.length >= 4 && p.slice(-4) === digits);

  if (!phoneMatch) {
    audit(db, 'quick_track_failed', null, ip, { order_id: normId, reason: 'phone_mismatch' });
    res.status(404).json({ success: false, message: 'No matching repair found. Please check your ticket ID and phone number.' });
    return;
  }

  // Create ticket-scoped session
  const token = generateToken();
  const sessionId = crypto.randomUUID();
  db.prepare(`
    INSERT INTO portal_sessions (id, customer_id, token, scope, ticket_id, expires_at)
    VALUES (?, ?, ?, 'ticket', ?, datetime('now', '+24 hours'))
  `).run(sessionId, ticket.customer_id, token, ticket.id);

  // Return token + ticket summary
  const detail = getTicketDetail(db, ticket.id);

  res.json({ success: true, data: { token, ticket: detail } });
}));

// ---------------------------------------------------------------------------
// POST /login — Phone + PIN (full account)
// ---------------------------------------------------------------------------
router.post('/login', asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkRate(rateLimiters.login, ip, 5, 15 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many login attempts. Please try again later.' });
    return;
  }

  const { phone, pin } = req.body as { phone?: string; pin?: string };

  if (!phone || !pin) {
    res.status(400).json({ success: false, message: 'Phone number and PIN are required' });
    return;
  }

  const normalized = normalizePhone(phone);
  if (normalized.length < 10) {
    res.status(400).json({ success: false, message: 'Please enter a valid phone number' });
    return;
  }

  // Find customer by phone (exact match on normalized digits)
  const customer = db.prepare(`
    SELECT c.id, c.first_name, c.portal_pin, c.portal_verified
    FROM customers c
    WHERE c.is_deleted = 0
      AND c.portal_verified = 1
      AND (
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.phone, '-', ''), ' ', ''), '(', ''), ')', ''), '+', '') LIKE ?
        OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.mobile, '-', ''), ' ', ''), '(', ''), ')', ''), '+', '') LIKE ?
      )
    LIMIT 1
  `).get(`%${normalized}`, `%${normalized}`) as AnyRow | undefined;

  // Also check customer_phones table
  let foundCustomer = customer;
  if (!foundCustomer) {
    const cp = db.prepare(`
      SELECT cp.customer_id FROM customer_phones cp
      JOIN customers c ON c.id = cp.customer_id
      WHERE c.is_deleted = 0 AND c.portal_verified = 1
        AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(cp.phone, '-', ''), ' ', ''), '(', ''), ')', ''), '+', '') LIKE ?
      LIMIT 1
    `).get(`%${normalized}`) as AnyRow | undefined;
    if (cp) {
      foundCustomer = db.prepare(
        'SELECT id, first_name, portal_pin, portal_verified FROM customers WHERE id = ?'
      ).get(cp.customer_id) as AnyRow | undefined;
    }
  }

  if (!foundCustomer || !foundCustomer.portal_pin) {
    // Generic error — don't reveal whether account exists
    res.status(401).json({ success: false, message: 'Invalid phone number or PIN' });
    return;
  }

  const pinValid = await bcrypt.compare(pin, foundCustomer.portal_pin);
  if (!pinValid) {
    res.status(401).json({ success: false, message: 'Invalid phone number or PIN' });
    return;
  }

  // Create full-scope session
  const token = generateToken();
  const sessionId = crypto.randomUUID();
  db.prepare(`
    INSERT INTO portal_sessions (id, customer_id, token, scope, expires_at)
    VALUES (?, ?, ?, 'full', datetime('now', '+24 hours'))
  `).run(sessionId, foundCustomer.id, token);

  res.json({
    success: true,
    data: {
      token,
      customer: { first_name: foundCustomer.first_name },
      scope: 'full',
    },
  });
}));

// ---------------------------------------------------------------------------
// POST /register/send-code — Send SMS verification code
// ---------------------------------------------------------------------------
router.post('/register/send-code', asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  // IP rate: 1 per 5 seconds
  const lastIp = rateLimiters.sendCodeIp.get(ip);
  if (lastIp && Date.now() - lastIp < 5000) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  rateLimiters.sendCodeIp.set(ip, Date.now());

  const { phone } = req.body as { phone?: string };
  if (!phone) {
    res.status(400).json({ success: false, message: 'Phone number is required' });
    return;
  }

  const normalized = normalizePhone(phone);
  if (normalized.length < 10) {
    res.status(400).json({ success: false, message: 'Please enter a valid phone number' });
    return;
  }

  // Phone rate: 3 per hour
  if (!checkRate(rateLimiters.sendCode, normalized, 3, 60 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many verification attempts. Please try again later.' });
    return;
  }

  // Find customer by phone
  const customer = db.prepare(`
    SELECT c.id, c.portal_verified
    FROM customers c
    WHERE c.is_deleted = 0
      AND (
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.phone, '-', ''), ' ', ''), '(', ''), ')', ''), '+', '') LIKE ?
        OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.mobile, '-', ''), ' ', ''), '(', ''), ')', ''), '+', '') LIKE ?
      )
    LIMIT 1
  `).get(`%${normalized}`, `%${normalized}`) as AnyRow | undefined;

  // Also check customer_phones
  let foundCustomer = customer;
  if (!foundCustomer) {
    const cp = db.prepare(`
      SELECT cp.customer_id FROM customer_phones cp
      JOIN customers c ON c.id = cp.customer_id
      WHERE c.is_deleted = 0
        AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(cp.phone, '-', ''), ' ', ''), '(', ''), ')', ''), '+', '') LIKE ?
      LIMIT 1
    `).get(`%${normalized}`) as AnyRow | undefined;
    if (cp) {
      foundCustomer = db.prepare('SELECT id, portal_verified FROM customers WHERE id = ?').get(cp.customer_id) as AnyRow | undefined;
    }
  }

  // Always return same generic success to prevent phone/account enumeration (AUD-M9)
  if (!foundCustomer || foundCustomer.portal_verified) {
    res.json({ success: true, data: { sent: true } });
    return;
  }

  // Generate 6-digit code
  const code = String(crypto.randomInt(100000, 999999));

  // Expire old unused codes for this customer
  db.prepare(
    "UPDATE portal_verification_codes SET used = 1 WHERE customer_id = ? AND used = 0"
  ).run(foundCustomer.id);

  // Insert new code (expires in 10 minutes)
  db.prepare(`
    INSERT INTO portal_verification_codes (customer_id, phone, code, expires_at)
    VALUES (?, ?, ?, datetime('now', '+10 minutes'))
  `).run(foundCustomer.id, normalized, code);

  // Send SMS
  const storeName = db.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as AnyRow | undefined;
  const name = storeName?.value || 'our shop';
  await sendSms(phone, `Your ${name} portal verification code is: ${code}. It expires in 10 minutes.`);

  res.json({ success: true, data: { sent: true } });
}));

// ---------------------------------------------------------------------------
// POST /register/verify — Verify code + set PIN
// ---------------------------------------------------------------------------
router.post('/register/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkRate(rateLimiters.login, ip, 5, 15 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Please try again later.' });
    return;
  }

  const { phone, code, pin } = req.body as { phone?: string; code?: string; pin?: string };

  if (!phone || !code || !pin) {
    res.status(400).json({ success: false, message: 'Phone, verification code, and PIN are required' });
    return;
  }

  if (!/^\d{4}$/.test(pin)) {
    res.status(400).json({ success: false, message: 'PIN must be exactly 4 digits' });
    return;
  }

  if (!/^\d{6}$/.test(code)) {
    res.status(400).json({ success: false, message: 'Verification code must be 6 digits' });
    return;
  }

  const normalized = normalizePhone(phone);

  // Find the verification code
  const verification = db.prepare(`
    SELECT id, customer_id, attempts
    FROM portal_verification_codes
    WHERE phone = ? AND code = ? AND used = 0 AND expires_at > datetime('now')
    ORDER BY created_at DESC LIMIT 1
  `).get(normalized, code) as AnyRow | undefined;

  if (!verification) {
    // Check if there's an unused code to increment attempts
    const anyCode = db.prepare(`
      SELECT id, attempts FROM portal_verification_codes
      WHERE phone = ? AND used = 0 AND expires_at > datetime('now')
      ORDER BY created_at DESC LIMIT 1
    `).get(normalized) as AnyRow | undefined;

    if (anyCode) {
      const newAttempts = anyCode.attempts + 1;
      if (newAttempts >= 5) {
        db.prepare('UPDATE portal_verification_codes SET used = 1 WHERE id = ?').run(anyCode.id);
      } else {
        db.prepare('UPDATE portal_verification_codes SET attempts = ? WHERE id = ?').run(newAttempts, anyCode.id);
      }
    }

    res.status(400).json({ success: false, message: 'Invalid or expired verification code' });
    return;
  }

  // Mark code as used
  db.prepare('UPDATE portal_verification_codes SET used = 1 WHERE id = ?').run(verification.id);

  // Hash PIN and update customer
  const hashedPin = await bcrypt.hash(pin, 12);
  db.prepare(`
    UPDATE customers
    SET portal_pin = ?, portal_verified = 1, portal_created_at = datetime('now'), updated_at = datetime('now')
    WHERE id = ?
  `).run(hashedPin, verification.customer_id);

  // Create full-scope session immediately
  const token = generateToken();
  const sessionId = crypto.randomUUID();
  db.prepare(`
    INSERT INTO portal_sessions (id, customer_id, token, scope, expires_at)
    VALUES (?, ?, ?, 'full', datetime('now', '+24 hours'))
  `).run(sessionId, verification.customer_id, token);

  const customer = db.prepare('SELECT first_name FROM customers WHERE id = ?').get(verification.customer_id) as AnyRow;

  res.json({
    success: true,
    data: {
      token,
      customer: { first_name: customer?.first_name },
      scope: 'full',
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /verify — Check if session token is valid
// ---------------------------------------------------------------------------
router.get('/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  // Accept token from Authorization header (preferred) or query param (legacy)
  const authHeader = req.headers.authorization;
  const token = (authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null)
    || req.query.token as string;
  if (!token) {
    res.status(400).json({ success: false, message: 'Token is required' });
    return;
  }

  const session = db.prepare(`
    SELECT ps.customer_id, ps.scope, ps.ticket_id,
           c.first_name, c.portal_verified
    FROM portal_sessions ps
    JOIN customers c ON c.id = ps.customer_id
    WHERE ps.token = ? AND ps.expires_at > datetime('now')
  `).get(token) as AnyRow | undefined;

  if (!session) {
    res.json({ success: true, data: { valid: false } });
    return;
  }

  db.prepare("UPDATE portal_sessions SET last_used_at = datetime('now') WHERE token = ?").run(token);

  res.json({
    success: true,
    data: {
      valid: true,
      customer_first_name: session.first_name,
      scope: session.scope,
      ticket_id: session.ticket_id,
      has_account: !!session.portal_verified,
    },
  });
}));

// ---------------------------------------------------------------------------
// POST /logout
// ---------------------------------------------------------------------------
router.post('/logout', portalAuth, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  db.prepare('DELETE FROM portal_sessions WHERE token = ?').run(req.portalSessionToken);
  res.json({ success: true, data: { logged_out: true } });
}));

// ---------------------------------------------------------------------------
// GET /dashboard — Summary for full account
// ---------------------------------------------------------------------------
router.get('/dashboard', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const cid = req.portalCustomerId!;

  const ticketCount = db.prepare(
    'SELECT COUNT(*) AS cnt FROM tickets WHERE customer_id = ? AND is_deleted = 0'
  ).get(cid) as AnyRow;

  const openTickets = db.prepare(`
    SELECT COUNT(*) AS cnt FROM tickets t
    JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.customer_id = ? AND t.is_deleted = 0 AND ts.is_closed = 0
  `).get(cid) as AnyRow;

  const pendingEstimates = db.prepare(
    "SELECT COUNT(*) AS cnt FROM estimates WHERE customer_id = ? AND status = 'sent'"
  ).get(cid) as AnyRow;

  // AUD-M11: Subquery to deduplicate invoices that match on both FK directions
  const outstandingInvoices = db.prepare(`
    SELECT COUNT(*) AS cnt, COALESCE(SUM(amount_due), 0) AS total_due
    FROM invoices
    WHERE id IN (
      SELECT DISTINCT i.id
      FROM invoices i
      JOIN tickets t ON (i.ticket_id = t.id OR i.id = t.invoice_id)
      WHERE t.customer_id = ? AND t.is_deleted = 0
    ) AND amount_due > 0
  `).get(cid) as AnyRow;

  const customer = db.prepare('SELECT first_name, last_name FROM customers WHERE id = ?').get(cid) as AnyRow;

  res.json({
    success: true,
    data: {
      customer: { first_name: customer?.first_name, last_name: customer?.last_name },
      total_tickets: ticketCount.cnt,
      open_tickets: openTickets.cnt,
      pending_estimates: pendingEstimates.cnt,
      outstanding_invoices: outstandingInvoices.cnt,
      outstanding_balance: outstandingInvoices.total_due,
      store: getStoreConfig(db),
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /tickets — All tickets for customer (full scope)
// ---------------------------------------------------------------------------
router.get('/tickets', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const cid = req.portalCustomerId!;

  const tickets = db.prepare(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.due_on,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.customer_id = ? AND t.is_deleted = 0
    ORDER BY t.created_at DESC
    LIMIT 50
  `).all(cid) as AnyRow[];

  // Batch fetch devices
  const ticketIds = tickets.map(t => t.id);
  let devicesMap: Record<number, AnyRow[]> = {};
  if (ticketIds.length > 0) {
    const placeholders = ticketIds.map(() => '?').join(',');
    const devices = db.prepare(`
      SELECT ticket_id, device_name, device_type
      FROM ticket_devices WHERE ticket_id IN (${placeholders})
    `).all(...ticketIds) as AnyRow[];
    for (const d of devices) {
      if (!devicesMap[d.ticket_id]) devicesMap[d.ticket_id] = [];
      devicesMap[d.ticket_id].push(d);
    }
  }

  const result = tickets.map(t => ({
    id: t.id,
    order_id: t.order_id,
    status: { name: t.status_name, color: t.status_color, is_closed: !!t.status_is_closed },
    devices: (devicesMap[t.id] || []).map(d => ({ name: d.device_name, type: d.device_type })),
    due_on: t.due_on,
    created_at: t.created_at,
    updated_at: t.updated_at,
  }));

  res.json({ success: true, data: result });
}));

// ---------------------------------------------------------------------------
// GET /tickets/:id — Single ticket detail (scope-aware)
// ---------------------------------------------------------------------------
router.get('/tickets/:id', portalAuth, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const ticketId = parseInt(req.params.id, 10);
  if (isNaN(ticketId)) {
    res.status(400).json({ success: false, message: 'Invalid ticket ID' });
    return;
  }

  // Verify ticket belongs to customer
  const ticket = db.prepare(
    'SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0'
  ).get(ticketId) as AnyRow | undefined;

  if (!ticket || ticket.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  // If ticket-scoped, must match session ticket
  if (req.portalScope === 'ticket' && req.portalTicketId !== ticketId) {
    res.status(403).json({ success: false, message: 'Access restricted to your tracked ticket' });
    return;
  }

  const detail = getTicketDetail(db, ticketId);
  res.json({ success: true, data: detail });
}));

// ---------------------------------------------------------------------------
// POST /tickets/:id/feedback — Leave rating
// ---------------------------------------------------------------------------
router.post('/tickets/:id/feedback', portalAuth, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const ticketId = parseInt(req.params.id, 10);
  if (isNaN(ticketId)) {
    res.status(400).json({ success: false, message: 'Invalid ticket ID' });
    return;
  }

  const { rating, comment } = req.body as { rating?: number; comment?: string };
  if (!rating || rating < 1 || rating > 5 || !Number.isInteger(rating)) {
    res.status(400).json({ success: false, message: 'Rating must be an integer from 1 to 5' });
    return;
  }

  const ticket = db.prepare(
    'SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0'
  ).get(ticketId) as AnyRow | undefined;

  if (!ticket || ticket.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  // Check for existing feedback
  const existing = db.prepare(
    'SELECT id FROM customer_feedback WHERE ticket_id = ? AND customer_id = ?'
  ).get(ticketId, req.portalCustomerId!) as AnyRow | undefined;

  if (existing) {
    res.status(409).json({ success: false, message: 'You have already left feedback for this repair' });
    return;
  }

  db.prepare(`
    INSERT INTO customer_feedback (ticket_id, customer_id, rating, comment, source, responded_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'portal', datetime('now'), datetime('now'), datetime('now'))
  `).run(ticketId, req.portalCustomerId!, rating, comment?.trim() || null);

  res.json({ success: true, data: { submitted: true } });
}));

// ---------------------------------------------------------------------------
// GET /estimates — Customer's estimates (full scope)
// ---------------------------------------------------------------------------
router.get('/estimates', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const cid = req.portalCustomerId!;

  const estimates = db.prepare(`
    SELECT e.id, e.order_id, e.status, e.subtotal, e.discount, e.total_tax, e.total,
           e.valid_until, e.notes, e.created_at, e.approved_at, e.viewed_at
    FROM estimates e
    WHERE e.customer_id = ? AND e.status IN ('draft', 'sent', 'approved', 'converted')
    ORDER BY e.created_at DESC
    LIMIT 50
  `).all(cid) as AnyRow[];

  // ENR-LE7: Mark unviewed estimates as viewed when customer opens the list
  const unviewedIds = estimates.filter(e => !e.viewed_at).map(e => e.id);
  if (unviewedIds.length > 0) {
    const ph = unviewedIds.map(() => '?').join(',');
    db.prepare(`UPDATE estimates SET viewed_at = datetime('now') WHERE id IN (${ph}) AND viewed_at IS NULL`).run(...unviewedIds);
  }

  // Batch fetch line items
  const estIds = estimates.map(e => e.id);
  let itemsMap: Record<number, AnyRow[]> = {};
  if (estIds.length > 0) {
    const placeholders = estIds.map(() => '?').join(',');
    const items = db.prepare(`
      SELECT estimate_id, description, quantity, unit_price, tax_amount, total
      FROM estimate_line_items WHERE estimate_id IN (${placeholders})
    `).all(...estIds) as AnyRow[];
    for (const item of items) {
      if (!itemsMap[item.estimate_id]) itemsMap[item.estimate_id] = [];
      itemsMap[item.estimate_id].push(item);
    }
  }

  const result = estimates.map(e => ({
    id: e.id,
    order_id: e.order_id,
    status: e.status,
    subtotal: e.subtotal,
    discount: e.discount,
    tax: e.total_tax,
    total: e.total,
    valid_until: e.valid_until,
    notes: e.notes,
    created_at: e.created_at,
    approved_at: e.approved_at,
    line_items: (itemsMap[e.id] || []).map(i => ({
      description: i.description,
      quantity: i.quantity,
      unit_price: i.unit_price,
      discount: 0,
      tax: i.tax_amount,
      total: i.total,
    })),
  }));

  res.json({ success: true, data: result });
}));

// ---------------------------------------------------------------------------
// POST /estimates/:id/approve — Approve an estimate
// ---------------------------------------------------------------------------
router.post('/estimates/:id/approve', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const estimateId = parseInt(req.params.id, 10);
  if (isNaN(estimateId)) {
    res.status(400).json({ success: false, message: 'Invalid estimate ID' });
    return;
  }

  const estimate = db.prepare(
    "SELECT id, customer_id, status FROM estimates WHERE id = ? AND status = 'sent'"
  ).get(estimateId) as AnyRow | undefined;

  if (!estimate || estimate.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Estimate not found or already processed' });
    return;
  }

  db.prepare(`
    UPDATE estimates SET status = 'approved', approved_at = datetime('now'), updated_at = datetime('now')
    WHERE id = ?
  `).run(estimateId);

  // SW-D7: Auto-change linked ticket status when estimate is approved
  const statusAfterEstimate = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_status_after_estimate'").get() as AnyRow | undefined;
  if (statusAfterEstimate?.value) {
    const targetStatusId = parseInt(statusAfterEstimate.value);
    if (targetStatusId > 0) {
      const est = db.prepare('SELECT converted_ticket_id FROM estimates WHERE id = ?').get(estimateId) as AnyRow | undefined;
      const ticketId = est?.converted_ticket_id
        || (db.prepare('SELECT id FROM tickets WHERE estimate_id = ? AND is_deleted = 0').get(estimateId) as AnyRow | undefined)?.id;
      if (ticketId) {
        const statusExists = db.prepare('SELECT id FROM ticket_statuses WHERE id = ?').get(targetStatusId);
        if (statusExists) {
          db.prepare('UPDATE tickets SET status_id = ?, updated_at = datetime(\'now\') WHERE id = ? AND is_deleted = 0')
            .run(targetStatusId, ticketId);
        }
      }
    }
  }

  res.json({ success: true, data: { approved: true } });
}));

// ---------------------------------------------------------------------------
// GET /invoices — Customer's invoices (full scope)
// ---------------------------------------------------------------------------
router.get('/invoices', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const cid = req.portalCustomerId!;

  const invoices = db.prepare(`
    SELECT DISTINCT i.id, i.order_id, i.status, i.subtotal, i.discount, i.total_tax, i.total,
           i.amount_paid, i.amount_due, i.created_at, t.order_id AS ticket_order_id
    FROM invoices i
    LEFT JOIN tickets t ON (i.ticket_id = t.id OR i.id = t.invoice_id)
    WHERE (t.customer_id = ? OR i.customer_id = ?) AND (t.is_deleted = 0 OR t.id IS NULL)
    ORDER BY i.created_at DESC
    LIMIT 50
  `).all(cid, cid) as AnyRow[];

  res.json({
    success: true,
    data: invoices.map(i => ({
      id: i.id,
      order_id: i.order_id,
      status: i.status,
      subtotal: i.subtotal,
      discount: i.discount,
      tax: i.total_tax,
      total: i.total,
      amount_paid: i.amount_paid,
      amount_due: i.amount_due,
      created_at: i.created_at,
      ticket_order_id: i.ticket_order_id,
    })),
  });
}));

// ---------------------------------------------------------------------------
// GET /invoices/:id — Invoice detail (full scope)
// ---------------------------------------------------------------------------
router.get('/invoices/:id', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const db = req.db;
  const invoiceId = parseInt(req.params.id, 10);
  if (isNaN(invoiceId)) {
    res.status(400).json({ success: false, message: 'Invalid invoice ID' });
    return;
  }

  const cid = req.portalCustomerId!;

  // Verify invoice belongs to customer (via ticket or direct customer_id)
  const invoice = db.prepare(`
    SELECT i.* FROM invoices i
    LEFT JOIN tickets t ON (i.ticket_id = t.id OR i.id = t.invoice_id)
    WHERE i.id = ? AND (t.customer_id = ? OR i.customer_id = ?)
    LIMIT 1
  `).get(invoiceId, cid, cid) as AnyRow | undefined;

  if (!invoice) {
    res.status(404).json({ success: false, message: 'Invoice not found' });
    return;
  }

  const lineItems = db.prepare(
    'SELECT description, quantity, unit_price, line_discount, tax_amount, total FROM invoice_line_items WHERE invoice_id = ?'
  ).all(invoice.id) as AnyRow[];

  const payments = db.prepare(
    'SELECT amount, method, created_at, notes FROM payments WHERE invoice_id = ?'
  ).all(invoice.id) as AnyRow[];

  res.json({
    success: true,
    data: {
      id: invoice.id,
      order_id: invoice.order_id,
      status: invoice.status,
      subtotal: invoice.subtotal,
      discount: invoice.discount,
      tax: invoice.total_tax,
      total: invoice.total,
      amount_paid: invoice.amount_paid,
      amount_due: invoice.amount_due,
      created_at: invoice.created_at,
      line_items: lineItems,
      payments: payments.map(p => ({ amount: p.amount, method: p.method, date: p.created_at })),
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /embed/config — Public store branding for widget
// ---------------------------------------------------------------------------
router.get('/embed/config', asyncHandler(async (_req: Request, res: Response) => {
  const db = _req.db;
  const store = getStoreConfig(db);
  res.json({
    success: true,
    data: {
      name: store.store_name || 'Repair Shop',
      phone: store.store_phone || '',
      address: [store.store_address, store.store_city, store.store_state, store.store_zip].filter(Boolean).join(', '),
      logo: store.store_logo || null,
      hours: store.store_hours || '',
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /widget.js — Embeddable widget JavaScript
// ---------------------------------------------------------------------------
router.get('/widget.js', (_req: Request, res: Response) => {
  res.setHeader('Content-Type', 'application/javascript');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  res.send(getWidgetScript());
});

function getWidgetScript(): string {
  return `(function() {
  var script = document.currentScript;
  var server = script.getAttribute('data-server') || '';
  var position = script.getAttribute('data-position') || 'inline';
  var rawColor = script.getAttribute('data-color') || '#2563eb';
  var color = /^#[0-9a-fA-F]{3,8}$/.test(rawColor) ? rawColor : '#2563eb';

  if (!server) { console.error('[BizarrePortal] data-server attribute is required'); return; }
  server = server.replace(/\\/$/, '');

  function createWidget() {
    if (position === 'floating') {
      // Floating button + expandable iframe
      var btn = document.createElement('div');
      btn.id = 'bizarre-portal-btn';
      btn.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1"/><path d="M9 14l2 2 4-4"/></svg>';
      btn.style.cssText = 'position:fixed;bottom:20px;right:20px;width:56px;height:56px;border-radius:50%;background:' + color + ';display:flex;align-items:center;justify-content:center;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.2);z-index:99999;transition:transform 0.2s';
      btn.onmouseenter = function() { btn.style.transform = 'scale(1.1)'; };
      btn.onmouseleave = function() { btn.style.transform = 'scale(1)'; };
      document.body.appendChild(btn);

      var container = document.createElement('div');
      container.id = 'bizarre-portal-container';
      container.style.cssText = 'position:fixed;bottom:86px;right:20px;width:380px;height:520px;border-radius:12px;overflow:hidden;box-shadow:0 8px 30px rgba(0,0,0,0.2);z-index:99999;display:none;background:white';
      document.body.appendChild(container);

      var iframe = document.createElement('iframe');
      iframe.src = server + '/customer-portal?mode=widget';
      iframe.style.cssText = 'width:100%;height:100%;border:none';
      iframe.title = 'Repair Status Tracker';
      iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-forms allow-popups');
      container.appendChild(iframe);

      var open = false;
      btn.onclick = function() {
        open = !open;
        container.style.display = open ? 'block' : 'none';
        btn.innerHTML = open
          ? '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>'
          : '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1"/><path d="M9 14l2 2 4-4"/></svg>';
      };
    } else {
      // Inline embed
      var container = document.createElement('div');
      container.id = 'bizarre-portal-container';
      container.style.cssText = 'width:100%;max-width:480px;margin:0 auto;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.1);background:white';

      var iframe = document.createElement('iframe');
      iframe.src = server + '/customer-portal?mode=widget';
      iframe.style.cssText = 'width:100%;min-height:400px;border:none';
      iframe.title = 'Repair Status Tracker';
      iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-forms allow-popups');
      container.appendChild(iframe);

      script.parentNode.insertBefore(container, script.nextSibling);

      // Auto-resize iframe based on content height
      window.addEventListener('message', function(e) {
        if (e.origin !== server) return;
        if (e.data && e.data.type === 'bizarre-portal-resize') {
          iframe.style.height = e.data.height + 'px';
        }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', createWidget);
  } else {
    createWidget();
  }
})();`;
}

export default router;
