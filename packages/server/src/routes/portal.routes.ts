import { Router, Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { normalizePhone } from '../utils/phone.js';
import { sendSms, sendSmsTenant } from '../services/smsProvider.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { checkWindowRate, recordWindowFailure, consumeWindowRate } from '../utils/rateLimiter.js';
import {
  generateCsrfToken,
  issueCsrfCookie,
  requireCsrfToken,
  CSRF_COOKIE_NAME,
} from '../utils/csrf.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();
const logger = createLogger('portal');

type AnyRow = Record<string, any>;

// ---------------------------------------------------------------------------
// Rate limit categories (persisted in rate_limits table — migration 069)
// ---------------------------------------------------------------------------

const RL = {
  QUICK_TRACK: 'portal_quick_track',     // IP -> 3 attempts / 60s
  LOGIN: 'portal_login',                 // IP -> 5 attempts / 15min
  SEND_CODE_PHONE: 'portal_send_code',   // phone -> 3 / hour
  SEND_CODE_IP: 'portal_send_code_ip',   // IP -> 1 / 5s
  SEND_CODE_CUSTOMER: 'portal_send_code_customer', // customer_id -> 3 / hour
  PIN_VERIFY: 'portal_pin_verify',               // customer_id -> 5 / 10min
  // SEC-M19: cap unauth config/embed scrapes to stop attackers from
  // enumerating the store branding (name/phone/address/logo) at high rate.
  EMBED_CONFIG: 'portal_embed_config',   // IP -> 60 / 5min
} as const;

// Session + CSRF cookie lifetimes (kept in sync with portal_sessions.expires_at).
const SESSION_LIFETIME_MS = 24 * 60 * 60 * 1000;

/**
 * SEC-L2: SQL expression that returns the 10-digit normalized form of a
 * phone-number column, mirroring JS `normalizePhone`. The previous portal
 * lookups used `LIKE '%<normalized>'` which let any stored number whose
 * suffix happened to match authenticate the wrong customer (e.g. the
 * "9995551234567" → "5551234567" collision class). Using '=' on the
 * canonical form closes the suffix-match hole.
 *
 * Steps:
 *   1. REPLACE out every non-digit separator we've ever seen in stored data:
 *      `-`, ` `, `(`, `)`, `+`, `.`, `/`. normalizePhone() strips all non-
 *      digits in JS via `/\D/g`; SQLite has no regex_replace in core, so we
 *      enumerate.
 *   2. If the cleaned value is 11 digits starting with '1' (US country code),
 *      drop the leading character so we land on the bare 10-digit line.
 *   3. Anything else passes through — if the stored value is garbage we'll
 *      simply fail to match the normalized input, which is the desired
 *      fail-closed behaviour.
 */
function NORMALIZED_DIGITS_EXPR(column: string): string {
  const stripped =
    `REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(` +
    `${column}, '-', ''), ' ', ''), '(', ''), ')', ''), '+', ''), '.', ''), '/', '')`;
  return `CASE WHEN LENGTH(${stripped}) = 11 AND SUBSTR(${stripped}, 1, 1) = '1' ` +
         `THEN SUBSTR(${stripped}, 2) ELSE ${stripped} END`;
}

/**
 * Wrap checkWindowRate + recordWindowFailure into a single call that both
 * gates the attempt AND records it on success. Returns true if the attempt
 * is allowed (in which case the caller should proceed), false if not.
 */
function consumeRate(
  req: Request,
  category: string,
  key: string,
  maxAttempts: number,
  windowMs: number,
): boolean {
  if (!checkWindowRate(req.db, category, key, maxAttempts, windowMs)) {
    return false;
  }
  recordWindowFailure(req.db, category, key, windowMs);
  return true;
}

// ---------------------------------------------------------------------------
// Portal auth middleware
// ---------------------------------------------------------------------------

interface PortalRequest extends Request {
  portalCustomerId?: number;
  portalScope?: 'ticket' | 'full';
  portalTicketId?: number | null;
  portalSessionToken?: string;
}

async function portalAuth(req: PortalRequest, res: Response, next: NextFunction): Promise<void> {
  const adb = req.asyncDb;
  const authHeader = req.headers.authorization;
  const cookieToken = req.cookies?.portalToken as string | undefined;
  // SEC: Prefer Authorization header, fall back to httpOnly cookie. Never accept from query string.
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : cookieToken;

  if (!token) {
    res.status(401).json({ success: false, message: 'Authentication required' });
    return;
  }

  // SEC-M45: pull last_used_at so we can also enforce idle timeout
  // (4 h default) on top of the absolute 24 h expires_at. A customer
  // who logs in from a shared workstation and walks away should be
  // kicked well before their 24 h session actually expires.
  const session = await adb.get<AnyRow>(`
    SELECT customer_id, scope, ticket_id, token, last_used_at
    FROM portal_sessions
    WHERE token = ? AND expires_at > datetime('now')
  `, token);

  if (!session) {
    res.status(401).json({ success: false, message: 'Session expired or invalid' });
    return;
  }

  // SEC-M45: reject idle sessions. IDLE_LIMIT_MS = 4 h. last_used_at
  // is updated on every request below, so active users are never
  // kicked. Null last_used_at (shouldn't happen — column is set on
  // insert) is treated as 'never used' and passes through.
  const IDLE_LIMIT_MS = 4 * 60 * 60 * 1000;
  if (session.last_used_at) {
    const lastUsedMs = Date.parse(String(session.last_used_at) + 'Z');
    if (Number.isFinite(lastUsedMs) && Date.now() - lastUsedMs > IDLE_LIMIT_MS) {
      // Evict the stale session so reuse of the token still fails on
      // the next request even if the expiry hasn't hit.
      await adb.run('DELETE FROM portal_sessions WHERE token = ?', token);
      res.status(401).json({ success: false, message: 'Session idle timeout. Please log in again.' });
      return;
    }
  }

  // Update last_used_at
  await adb.run("UPDATE portal_sessions SET last_used_at = datetime('now') WHERE token = ?", token);

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

/**
 * PT4: For detail endpoints that receive a ticket id in the URL (e.g.
 * `/tickets/:id/...`), if the session is ticket-scoped it MUST match the
 * URL ticket exactly. Rejects cross-ticket access attempts with a
 * ticket-scoped session. Full-scope sessions are allowed through.
 *
 * Reads the ticket id from `req.params.id` (the convention used by detail
 * routes in this file) and compares it to `req.portalTicketId`.
 */
function requireTicketScopeMatches(
  req: PortalRequest,
  res: Response,
  next: NextFunction,
): void {
  if (req.portalScope === 'ticket') {
    const ticketId = parseInt(req.params.id as string, 10);
    if (isNaN(ticketId)) {
      res.status(400).json({ success: false, message: 'Invalid ticket ID' });
      return;
    }
    if (req.portalTicketId !== ticketId) {
      logger.warn('ticket-scoped session attempted cross-ticket access', {
        session_ticket_id: req.portalTicketId,
        requested_ticket_id: ticketId,
      });
      res.status(403).json({
        success: false,
        message: 'Access restricted to your tracked ticket',
      });
      return;
    }
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

async function getStoreConfig(adb: AsyncDb): Promise<Record<string, string>> {
  const rows = await adb.all<AnyRow>(`
    SELECT key, value FROM store_config
    WHERE key IN ('store_name', 'store_phone', 'store_email', 'store_address',
                  'store_city', 'store_state', 'store_zip', 'store_hours',
                  'store_logo', 'store_website')
  `);
  const config: Record<string, string> = {};
  for (const r of rows) config[r.key] = r.value;
  return config;
}

async function getTicketDetail(adb: AsyncDb, ticketId: number): Promise<Record<string, any> | null> {
  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.due_on,
           t.subtotal, t.discount, t.total_tax, t.total, t.invoice_id,
           c.first_name AS c_first_name, c.last_name AS c_last_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.id = ? AND t.is_deleted = 0
  `, ticketId);

  if (!ticket) return null;

  // 6 independent queries — fire in parallel
  const [devices, history, smsMessages, messages, feedback, checkinNotes] = await Promise.all([
    adb.all<AnyRow>(`
      SELECT td.id, td.device_name, td.device_type, td.imei, td.serial,
             ts.name AS status_name, td.due_on, td.additional_notes,
             td.price, td.total, td.service_name
      FROM ticket_devices td
      LEFT JOIN ticket_statuses ts ON ts.id = td.status_id
      WHERE td.ticket_id = ?
    `, ticket.id),

    // Build combined timeline: history + SMS + customer notes (no internal notes)
    adb.all<AnyRow>(`
      SELECT action, description, old_value, new_value, created_at
      FROM ticket_history WHERE ticket_id = ?
      ORDER BY created_at ASC
    `, ticket.id),

    // Get SMS messages linked to this ticket
    adb.all<AnyRow>(`
      SELECT sm.message, sm.direction, sm.created_at
      FROM sms_messages sm
      WHERE sm.entity_type = 'ticket' AND sm.entity_id = ?
      ORDER BY sm.created_at ASC
      LIMIT 50
    `, ticket.id),

    // Get customer-visible notes (diagnostic + customer, NOT internal)
    adb.all<AnyRow>(`
      SELECT tn.id, tn.content, tn.type, tn.created_at,
             COALESCE(u.first_name || ' ' || u.last_name, u.username) AS author
      FROM ticket_notes tn
      LEFT JOIN users u ON u.id = tn.user_id
      WHERE tn.ticket_id = ? AND tn.type IN ('customer', 'diagnostic')
      ORDER BY tn.created_at DESC
      LIMIT 50
    `, ticket.id),

    // Check for existing feedback
    adb.get<AnyRow>(
      'SELECT rating, comment, responded_at FROM customer_feedback WHERE ticket_id = ? LIMIT 1',
      ticket.id),

    // Get check-in notes (first diagnostic note, which is typically the intake description)
    adb.get<AnyRow>(`
      SELECT content FROM ticket_notes
      WHERE ticket_id = ? AND type = 'diagnostic'
      ORDER BY created_at ASC LIMIT 1
    `, ticket.id),
  ]);

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
  let invoice: AnyRow | undefined;
  if (ticket.invoice_id) {
    invoice = await adb.get<AnyRow>('SELECT * FROM invoices WHERE id = ?', ticket.invoice_id);
  }
  if (!invoice) {
    invoice = await adb.get<AnyRow>('SELECT * FROM invoices WHERE ticket_id = ? LIMIT 1', ticket.id);
  }

  let invoiceData = null;
  if (invoice) {
    const [lineItems, payments] = await Promise.all([
      adb.all<AnyRow>(
        'SELECT description, quantity, unit_price, line_discount, tax_amount, total FROM invoice_line_items WHERE invoice_id = ?',
        invoice.id),
      adb.all<AnyRow>(
        'SELECT amount, method, created_at, notes FROM payments WHERE invoice_id = ?',
        invoice.id),
    ]);
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
    store: await getStoreConfig(adb),
  };
}

// ---------------------------------------------------------------------------
// POST /quick-track — Ticket ID + last 4 phone digits
// ---------------------------------------------------------------------------
router.post('/quick-track', asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  // R2: persistent IP rate limit (3 / 60s) — survives server restarts
  if (!consumeRate(req, RL.QUICK_TRACK, ip, 3, 60 * 1000)) {
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
  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.customer_id, t.order_id,
           c.phone AS c_phone, c.mobile AS c_mobile
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    WHERE t.order_id = ? AND t.is_deleted = 0
  `, normId);

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

  const additionalPhones = await adb.all<AnyRow>(
    'SELECT phone FROM customer_phones WHERE customer_id = ?',
    ticket.customer_id);
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
  await adb.run(`
    INSERT INTO portal_sessions (id, customer_id, token, scope, ticket_id, expires_at)
    VALUES (?, ?, ?, 'ticket', ?, datetime('now', '+24 hours'))
  `, sessionId, ticket.customer_id, token, ticket.id);

  // PT2: Issue CSRF token cookie alongside the session so POSTs can echo it.
  const csrfToken = generateCsrfToken();
  issueCsrfCookie(res, csrfToken, SESSION_LIFETIME_MS);

  // Return token + ticket summary
  const detail = await getTicketDetail(adb, ticket.id);

  res.json({ success: true, data: { token, csrf_token: csrfToken, ticket: detail } });
}));

// ---------------------------------------------------------------------------
// POST /login — Phone + PIN (full account)
// ---------------------------------------------------------------------------
router.post('/login', asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  // R2: persistent IP rate limit (5 / 15min)
  if (!consumeRate(req, RL.LOGIN, ip, 5, 15 * 60 * 1000)) {
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

  // SEC-L2: exact equality on fully-normalized digits (no LIKE suffix match).
  // Suffix matching lets "9995551234567" collide with "5551234567" — any stored
  // number whose last 10 digits happen to match the input would authenticate
  // a different customer's login. Strip the same punctuation set in SQL that
  // normalizePhone() strips in JS, then drop the leading country "1" to land
  // on the canonical 10-digit form, and compare with '='.
  const customer = await adb.get<AnyRow>(`
    SELECT c.id, c.first_name, c.portal_pin, c.portal_verified
    FROM customers c
    WHERE c.is_deleted = 0
      AND c.portal_verified = 1
      AND (
        ${NORMALIZED_DIGITS_EXPR('c.phone')} = ?
        OR ${NORMALIZED_DIGITS_EXPR('c.mobile')} = ?
      )
    LIMIT 1
  `, normalized, normalized);

  // Also check customer_phones table
  let foundCustomer = customer;
  if (!foundCustomer) {
    const cp = await adb.get<AnyRow>(`
      SELECT cp.customer_id FROM customer_phones cp
      JOIN customers c ON c.id = cp.customer_id
      WHERE c.is_deleted = 0 AND c.portal_verified = 1
        AND ${NORMALIZED_DIGITS_EXPR('cp.phone')} = ?
      LIMIT 1
    `, normalized);
    if (cp) {
      foundCustomer = await adb.get<AnyRow>(
        'SELECT id, first_name, portal_pin, portal_verified FROM customers WHERE id = ?',
        cp.customer_id);
    }
  }

  if (!foundCustomer || !foundCustomer.portal_pin) {
    // Generic error — don't reveal whether account exists
    res.status(401).json({ success: false, message: 'Invalid phone number or PIN' });
    return;
  }

  // SEC-H87: per-customer_id rate limit (5 / 10min). Must run after customer
  // lookup so we have the stable customer_id (not just IP). Uses consumeWindowRate
  // for atomic check-and-record. On the Nth attempt that hits the cap we also
  // send a lockout SMS to the customer's primary phone so they know to wait.
  const PIN_VERIFY_MAX = 5;
  const PIN_VERIFY_WINDOW_MS = 10 * 60 * 1000;
  const pinRlResult = consumeWindowRate(
    req.db,
    RL.PIN_VERIFY,
    `${foundCustomer.id}`,
    PIN_VERIFY_MAX,
    PIN_VERIFY_WINDOW_MS,
  );
  if (!pinRlResult.allowed) {
    // SEC-H87: Fire lockout SMS exactly once per lockout window. Use a
    // one-shot "notified" marker (category=portal_pin_notify, max=1 per
    // same window) so repeated 429s within the same 10-min window don't
    // spam the customer's phone. consumeWindowRate atomically marks it.
    const notifyResult = consumeWindowRate(
      req.db,
      'portal_pin_notify',
      `${foundCustomer.id}`,
      1,
      PIN_VERIFY_WINDOW_MS,
    );
    if (notifyResult.allowed) {
      // First time hitting lockout in this window — send the SMS.
      try {
        const custRow = await adb.get<AnyRow>(
          'SELECT phone, mobile FROM customers WHERE id = ?',
          foundCustomer.id,
        );
        const lockoutPhone = normalizePhone(custRow?.phone || '') ||
                             normalizePhone(custRow?.mobile || '');
        if (lockoutPhone.length >= 10) {
          await sendSmsTenant(
            req.db,
            null,
            lockoutPhone,
            'BizarreCRM: your portal PIN was entered incorrectly too many times. Wait 10 minutes and try again.',
          );
        }
      } catch (smsErr) {
        logger.warn('portal PIN lockout SMS failed', { customer_id: foundCustomer.id, error: smsErr });
      }
    }
    res.setHeader('Retry-After', String(pinRlResult.retryAfterSeconds));
    res.status(429).json({ success: false, message: 'Too many PIN attempts for this customer' });
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
  await adb.run(`
    INSERT INTO portal_sessions (id, customer_id, token, scope, expires_at)
    VALUES (?, ?, ?, 'full', datetime('now', '+24 hours'))
  `, sessionId, foundCustomer.id, token);

  // PT2: Issue CSRF token cookie
  const csrfToken = generateCsrfToken();
  issueCsrfCookie(res, csrfToken, SESSION_LIFETIME_MS);

  res.json({
    success: true,
    data: {
      token,
      csrf_token: csrfToken,
      customer: { first_name: foundCustomer.first_name },
      scope: 'full',
    },
  });
}));

// ---------------------------------------------------------------------------
// POST /register/send-code — Send SMS verification code
// ---------------------------------------------------------------------------
router.post('/register/send-code', asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  // R2: IP rate 1 / 5s — persistent
  if (!consumeRate(req, RL.SEND_CODE_IP, ip, 1, 5000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }

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

  // R2: Phone rate 3 / hour — persistent
  if (!consumeRate(req, RL.SEND_CODE_PHONE, normalized, 3, 60 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many verification attempts. Please try again later.' });
    return;
  }

  // SEC-M21: 24-hour hard cap at 10 per phone on top of the hourly rolling
  // limit above. Prevents a slow-drip spammer from sending 72 codes/day by
  // pacing one every 20 minutes under the hourly gate. Separate rate_limits
  // category so the window counts are independent. CAPTCHA-on-first-new-IP
  // (the original spec's second half) is tracked as SEC-M21-captcha — requires
  // a CAPTCHA provider integration (hCaptcha / reCAPTCHA / Turnstile) which
  // is out of scope for a self-contained fix.
  if (!consumeRate(req, 'portal_send_code_day', normalized, 10, 24 * 60 * 60 * 1000)) {
    res.status(429).json({
      success: false,
      message: 'Daily verification cap reached for this number. Please try again tomorrow or contact the shop directly.',
    });
    return;
  }

  // SEC-L2: exact equality on fully-normalized digits — see notes in /login.
  const customer = await adb.get<AnyRow>(`
    SELECT c.id, c.portal_verified, c.sms_consent_transactional, c.sms_opt_in
    FROM customers c
    WHERE c.is_deleted = 0
      AND (
        ${NORMALIZED_DIGITS_EXPR('c.phone')} = ?
        OR ${NORMALIZED_DIGITS_EXPR('c.mobile')} = ?
      )
    LIMIT 1
  `, normalized, normalized);

  // Also check customer_phones
  let foundCustomer = customer;
  if (!foundCustomer) {
    const cp = await adb.get<AnyRow>(`
      SELECT cp.customer_id FROM customer_phones cp
      JOIN customers c ON c.id = cp.customer_id
      WHERE c.is_deleted = 0
        AND ${NORMALIZED_DIGITS_EXPR('cp.phone')} = ?
      LIMIT 1
    `, normalized);
    if (cp) {
      foundCustomer = await adb.get<AnyRow>(
        'SELECT id, portal_verified, sms_consent_transactional, sms_opt_in FROM customers WHERE id = ?',
        cp.customer_id);
    }
  }

  // Always return same generic success to prevent phone/account enumeration (AUD-M9)
  if (!foundCustomer || foundCustomer.portal_verified) {
    res.json({ success: true, data: { sent: true } });
    return;
  }

  // R4: per-customer rate limit (3 / hour) in addition to per-phone / per-IP.
  // Stops a single customer from being hammered even if the attacker rotates phones.
  if (!consumeRate(req, RL.SEND_CODE_CUSTOMER, String(foundCustomer.id), 3, 60 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many verification attempts. Please try again later.' });
    return;
  }

  // PT1: SMS may only be sent if the customer has opted in to transactional SMS.
  // Both legacy `sms_opt_in` (001) and `sms_consent_transactional` (063) must be
  // set. If either is off, we return success with a `sent: false` warning rather
  // than silently queuing an SMS that will never be delivered (and would violate
  // TCPA).
  const optedIn = !!foundCustomer.sms_opt_in && !!foundCustomer.sms_consent_transactional;
  if (!optedIn) {
    logger.warn('portal send-code skipped — customer not opted in', {
      customer_id: foundCustomer.id,
    });
    res.json({
      success: true,
      data: {
        sent: false,
        reason: 'not opted in',
      },
    });
    return;
  }

  // Generate 6-digit code
  const code = String(crypto.randomInt(100000, 999999));

  // Expire old unused codes for this customer
  await adb.run(
    "UPDATE portal_verification_codes SET used = 1 WHERE customer_id = ? AND used = 0",
    foundCustomer.id);

  // Insert new code (expires in 10 minutes)
  await adb.run(`
    INSERT INTO portal_verification_codes (customer_id, phone, code, expires_at)
    VALUES (?, ?, ?, datetime('now', '+10 minutes'))
  `, foundCustomer.id, normalized, code);

  // Send SMS (L4: check the provider result rather than blindly reporting success)
  const storeName = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'store_name'");
  const name = storeName?.value || 'our shop';
  const smsResult = await sendSms(
    phone,
    `Your ${name} portal verification code is: ${code}. It expires in 10 minutes.`,
  );

  if (!smsResult.success) {
    logger.error('portal send-code SMS delivery failed', {
      customer_id: foundCustomer.id,
      provider: smsResult.providerName,
      error: smsResult.error,
    });
    // Burn the just-inserted code so a would-be attacker can't reuse it.
    await adb.run(
      "UPDATE portal_verification_codes SET used = 1 WHERE customer_id = ? AND used = 0",
      foundCustomer.id);
    res.status(502).json({
      success: false,
      error: 'SMS delivery failed',
    });
    return;
  }

  res.json({ success: true, data: { sent: true } });
}));

// ---------------------------------------------------------------------------
// POST /register/verify — Verify code + set PIN
// ---------------------------------------------------------------------------
router.post('/register/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  // R2: share the persistent login rate bucket (5 / 15 min)
  if (!consumeRate(req, RL.LOGIN, ip, 5, 15 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Please try again later.' });
    return;
  }

  const { phone, code, pin } = req.body as { phone?: string; code?: string; pin?: string };

  if (!phone || !code || !pin) {
    res.status(400).json({ success: false, message: 'Phone, verification code, and PIN are required' });
    return;
  }

  if (!/^\d{6}$/.test(pin)) {
    res.status(400).json({ success: false, message: 'PIN must be exactly 6 digits' });
    return;
  }

  if (!/^\d{6}$/.test(code)) {
    res.status(400).json({ success: false, message: 'Verification code must be 6 digits' });
    return;
  }

  const normalized = normalizePhone(phone);

  // Find the verification code
  const verification = await adb.get<AnyRow>(`
    SELECT id, customer_id, attempts
    FROM portal_verification_codes
    WHERE phone = ? AND code = ? AND used = 0 AND expires_at > datetime('now')
    ORDER BY created_at DESC LIMIT 1
  `, normalized, code);

  if (!verification) {
    // Check if there's an unused code to increment attempts
    const anyCode = await adb.get<AnyRow>(`
      SELECT id, attempts FROM portal_verification_codes
      WHERE phone = ? AND used = 0 AND expires_at > datetime('now')
      ORDER BY created_at DESC LIMIT 1
    `, normalized);

    if (anyCode) {
      const newAttempts = anyCode.attempts + 1;
      if (newAttempts >= 5) {
        await adb.run('UPDATE portal_verification_codes SET used = 1 WHERE id = ?', anyCode.id);
      } else {
        await adb.run('UPDATE portal_verification_codes SET attempts = ? WHERE id = ?', newAttempts, anyCode.id);
      }
    }

    res.status(400).json({ success: false, message: 'Invalid or expired verification code' });
    return;
  }

  // Mark code as used
  await adb.run('UPDATE portal_verification_codes SET used = 1 WHERE id = ?', verification.id);

  // Hash PIN and update customer
  const hashedPin = await bcrypt.hash(pin, 12);
  await adb.run(`
    UPDATE customers
    SET portal_pin = ?, portal_verified = 1, portal_created_at = datetime('now'), updated_at = datetime('now')
    WHERE id = ?
  `, hashedPin, verification.customer_id);

  // Create full-scope session immediately
  const token = generateToken();
  const sessionId = crypto.randomUUID();
  await adb.run(`
    INSERT INTO portal_sessions (id, customer_id, token, scope, expires_at)
    VALUES (?, ?, ?, 'full', datetime('now', '+24 hours'))
  `, sessionId, verification.customer_id, token);

  // PT2: Issue CSRF token cookie alongside the new full-scope session.
  const csrfToken = generateCsrfToken();
  issueCsrfCookie(res, csrfToken, SESSION_LIFETIME_MS);

  const customer = await adb.get<AnyRow>('SELECT first_name FROM customers WHERE id = ?', verification.customer_id);

  res.json({
    success: true,
    data: {
      token,
      csrf_token: csrfToken,
      customer: { first_name: customer?.first_name },
      scope: 'full',
    },
  });
}));

// ---------------------------------------------------------------------------
// Verify session token — shared handler used by both POST (preferred, PT3)
// and the deprecated GET (backwards compat for one more release).
// ---------------------------------------------------------------------------
async function verifySessionHandler(req: PortalRequest, res: Response, token: string): Promise<void> {
  const adb = req.asyncDb;
  const session = await adb.get<AnyRow>(`
    SELECT ps.customer_id, ps.scope, ps.ticket_id,
           c.first_name, c.portal_verified
    FROM portal_sessions ps
    JOIN customers c ON c.id = ps.customer_id
    WHERE ps.token = ? AND ps.expires_at > datetime('now')
  `, token);

  if (!session) {
    res.json({ success: true, data: { valid: false } });
    return;
  }

  await adb.run("UPDATE portal_sessions SET last_used_at = datetime('now') WHERE token = ?", token);

  const csrfToken = generateCsrfToken();
  issueCsrfCookie(res, csrfToken, SESSION_LIFETIME_MS);

  res.json({
    success: true,
    data: {
      valid: true,
      customer_first_name: session.first_name,
      scope: session.scope,
      ticket_id: session.ticket_id,
      has_account: !!session.portal_verified,
      csrf_token: csrfToken,
    },
  });
}

// ---------------------------------------------------------------------------
// POST /verify — Check if session token is valid (PREFERRED)
// PT3: Accept token from Authorization header or POST body to keep it out of
// request logs / referer headers / browser history.
// ---------------------------------------------------------------------------
router.post('/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const authHeader = req.headers.authorization;
  const bodyToken = (req.body as { token?: string } | undefined)?.token;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : bodyToken;

  if (!token || typeof token !== 'string') {
    res.status(400).json({ success: false, message: 'Token is required' });
    return;
  }

  await verifySessionHandler(req, res, token);
}));

// ---------------------------------------------------------------------------
// GET /verify — DEPRECATED. Use POST /verify instead.
// Kept for one more release so existing portal frontends keep working; logs a
// deprecation warning so we can measure when it's safe to remove.
// ---------------------------------------------------------------------------
router.get('/verify', asyncHandler(async (req: PortalRequest, res: Response) => {
  const authHeader = req.headers.authorization;
  const queryToken = req.query.token as string | undefined;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : queryToken;

  if (!token) {
    res.status(400).json({ success: false, message: 'Token is required' });
    return;
  }

  // PT3: Warn when the query-string path is actually used so we can retire it.
  if (queryToken && !authHeader) {
    logger.warn('DEPRECATED GET /portal/verify used with token in query string', {
      ip: req.ip || req.socket.remoteAddress,
      user_agent: req.headers['user-agent'],
    });
  }

  await verifySessionHandler(req, res, token);
}));

// ---------------------------------------------------------------------------
// POST /logout
// ---------------------------------------------------------------------------
router.post('/logout', portalAuth, requireCsrfToken, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  await adb.run('DELETE FROM portal_sessions WHERE token = ?', req.portalSessionToken);
  // Clear the CSRF cookie on logout so a stolen cookie can't be reused.
  res.clearCookie(CSRF_COOKIE_NAME, { path: '/' });
  res.json({ success: true, data: { logged_out: true } });
}));

// ---------------------------------------------------------------------------
// GET /dashboard — Summary for full account
// ---------------------------------------------------------------------------
router.get('/dashboard', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const cid = req.portalCustomerId!;

  const [ticketCount, openTickets, pendingEstimates, outstandingInvoices, customer, store] = await Promise.all([
    adb.get<AnyRow>(
      'SELECT COUNT(*) AS cnt FROM tickets WHERE customer_id = ? AND is_deleted = 0',
      cid),

    adb.get<AnyRow>(`
      SELECT COUNT(*) AS cnt FROM tickets t
      JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.customer_id = ? AND t.is_deleted = 0 AND ts.is_closed = 0
    `, cid),

    adb.get<AnyRow>(
      "SELECT COUNT(*) AS cnt FROM estimates WHERE customer_id = ? AND status = 'sent'",
      cid),

    // AUD-M11: Subquery to deduplicate invoices that match on both FK directions
    adb.get<AnyRow>(`
      SELECT COUNT(*) AS cnt, COALESCE(SUM(amount_due), 0) AS total_due
      FROM invoices
      WHERE id IN (
        SELECT DISTINCT i.id
        FROM invoices i
        JOIN tickets t ON (i.ticket_id = t.id OR i.id = t.invoice_id)
        WHERE t.customer_id = ? AND t.is_deleted = 0
      ) AND amount_due > 0
    `, cid),

    adb.get<AnyRow>('SELECT first_name, last_name FROM customers WHERE id = ?', cid),

    getStoreConfig(adb),
  ]);

  res.json({
    success: true,
    data: {
      customer: { first_name: customer?.first_name, last_name: customer?.last_name },
      total_tickets: ticketCount!.cnt,
      open_tickets: openTickets!.cnt,
      pending_estimates: pendingEstimates!.cnt,
      outstanding_invoices: outstandingInvoices!.cnt,
      outstanding_balance: outstandingInvoices!.total_due,
      store,
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /tickets — All tickets for customer (full scope)
// ---------------------------------------------------------------------------
router.get('/tickets', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const cid = req.portalCustomerId!;

  const tickets = await adb.all<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.due_on,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.customer_id = ? AND t.is_deleted = 0
    ORDER BY t.created_at DESC
    LIMIT 50
  `, cid);

  // Batch fetch devices
  const ticketIds = tickets.map(t => t.id);
  let devicesMap: Record<number, AnyRow[]> = {};
  if (ticketIds.length > 0) {
    const placeholders = ticketIds.map(() => '?').join(',');
    const devices = await adb.all<AnyRow>(`
      SELECT ticket_id, device_name, device_type
      FROM ticket_devices WHERE ticket_id IN (${placeholders})
    `, ...ticketIds);
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
// PT4: requireTicketScopeMatches runs BEFORE the DB lookup so a
// ticket-scoped session can never probe other tickets.
// ---------------------------------------------------------------------------
router.get('/tickets/:id', portalAuth, requireTicketScopeMatches, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id as string, 10);
  if (isNaN(ticketId)) {
    res.status(400).json({ success: false, message: 'Invalid ticket ID' });
    return;
  }

  // Verify ticket belongs to customer
  const ticket = await adb.get<AnyRow>(
    'SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0',
    ticketId);

  if (!ticket || ticket.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const detail = await getTicketDetail(adb, ticketId);
  res.json({ success: true, data: detail });
}));

// ---------------------------------------------------------------------------
// POST /tickets/:id/pay-link — Generate payment link for ticket's invoice
// ---------------------------------------------------------------------------
router.post('/tickets/:id/pay-link', portalAuth, requireCsrfToken, requireTicketScopeMatches, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id as string, 10);
  if (isNaN(ticketId)) {
    res.status(400).json({ success: false, message: 'Invalid ticket ID' });
    return;
  }

  const ticket = await adb.get<AnyRow>('SELECT id, customer_id, invoice_id FROM tickets WHERE id = ? AND is_deleted = 0', ticketId);
  if (!ticket || ticket.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  let invoice: AnyRow | null = null;
  if (ticket.invoice_id) {
    invoice = await adb.get<AnyRow>('SELECT id, amount_due FROM invoices WHERE id = ?', ticket.invoice_id) ?? null;
  }
  if (!invoice) {
    invoice = await adb.get<AnyRow>('SELECT id, amount_due FROM invoices WHERE ticket_id = ? LIMIT 1', ticket.id) ?? null;
  }

  if (!invoice) {
    res.status(404).json({ success: false, message: 'No invoice found to pay' });
    return;
  }
  if (invoice.amount_due <= 0) {
    res.status(409).json({ success: false, message: 'Invoice is already paid' });
    return;
  }

  const existing = await adb.get<AnyRow>(
    "SELECT token, expires_at FROM payment_links WHERE invoice_id = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1",
    invoice.id
  );
  if (existing && existing.expires_at && new Date(existing.expires_at).getTime() > Date.now()) {
    res.json({ success: true, data: { url: `/pay/${existing.token}` } });
    return;
  }

  const storeProvider = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'payment_provider'");
  let provider = 'stripe';
  if (storeProvider && storeProvider.value === 'blockchyp') {
    provider = 'blockchyp';
  }

  const token = crypto.randomBytes(24).toString('base64url');
  const amountCents = Math.round(invoice.amount_due * 100);
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

  await adb.run(
    `INSERT INTO payment_links (token, invoice_id, customer_id, amount_cents, description, provider, status, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, 'active', ?)`,
    token, invoice.id, ticket.customer_id, amountCents, `Payment for invoice for Ticket #${ticket.id}`, provider, expiresAt
  );

  res.json({ success: true, data: { url: `/pay/${token}` } });
}));

// ---------------------------------------------------------------------------
// POST /tickets/:id/feedback — Leave rating
// ---------------------------------------------------------------------------
router.post('/tickets/:id/feedback', portalAuth, requireCsrfToken, requireTicketScopeMatches, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const ticketId = parseInt(req.params.id as string, 10);
  if (isNaN(ticketId)) {
    res.status(400).json({ success: false, message: 'Invalid ticket ID' });
    return;
  }

  const { rating, comment } = req.body as { rating?: number; comment?: string };
  if (!rating || rating < 1 || rating > 5 || !Number.isInteger(rating)) {
    res.status(400).json({ success: false, message: 'Rating must be an integer from 1 to 5' });
    return;
  }

  // Ticket ownership + existing feedback check — independent, run in parallel
  const [ticket, existing] = await Promise.all([
    adb.get<AnyRow>(
      'SELECT id, customer_id FROM tickets WHERE id = ? AND is_deleted = 0',
      ticketId),
    adb.get<AnyRow>(
      'SELECT id FROM customer_feedback WHERE ticket_id = ? AND customer_id = ?',
      ticketId, req.portalCustomerId!),
  ]);

  if (!ticket || ticket.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  if (existing) {
    res.status(409).json({ success: false, message: 'You have already left feedback for this repair' });
    return;
  }

  await adb.run(`
    INSERT INTO customer_feedback (ticket_id, customer_id, rating, comment, source, responded_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'portal', datetime('now'), datetime('now'), datetime('now'))
  `, ticketId, req.portalCustomerId!, rating, comment?.trim() || null);

  res.json({ success: true, data: { submitted: true } });
}));

// ---------------------------------------------------------------------------
// GET /estimates — Customer's estimates (full scope)
// ---------------------------------------------------------------------------
router.get('/estimates', portalAuth, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const cid = req.portalCustomerId!;

  const estimates = await adb.all<AnyRow>(`
    SELECT e.id, e.order_id, e.status, e.subtotal, e.discount, e.total_tax, e.total,
           e.valid_until, e.notes, e.created_at, e.approved_at, e.viewed_at
    FROM estimates e
    WHERE e.customer_id = ? AND e.status IN ('draft', 'sent', 'approved', 'converted')
    ORDER BY e.created_at DESC
    LIMIT 50
  `, cid);

  // ENR-LE7: Mark unviewed estimates as viewed when customer opens the list
  const unviewedIds = estimates.filter(e => !e.viewed_at).map(e => e.id);
  if (unviewedIds.length > 0) {
    const ph = unviewedIds.map(() => '?').join(',');
    await adb.run(`UPDATE estimates SET viewed_at = datetime('now') WHERE id IN (${ph}) AND viewed_at IS NULL`, ...unviewedIds);
  }

  // Batch fetch line items
  const estIds = estimates.map(e => e.id);
  let itemsMap: Record<number, AnyRow[]> = {};
  if (estIds.length > 0) {
    const placeholders = estIds.map(() => '?').join(',');
    const items = await adb.all<AnyRow>(`
      SELECT estimate_id, description, quantity, unit_price, tax_amount, total
      FROM estimate_line_items WHERE estimate_id IN (${placeholders})
    `, ...estIds);
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
router.post('/estimates/:id/approve', portalAuth, requireCsrfToken, requireFullScope, asyncHandler(async (req: PortalRequest, res: Response) => {
  const adb = req.asyncDb;
  const estimateId = parseInt(req.params.id as string, 10);
  if (isNaN(estimateId)) {
    res.status(400).json({ success: false, message: 'Invalid estimate ID' });
    return;
  }

  const estimate = await adb.get<AnyRow>(
    "SELECT id, customer_id, status FROM estimates WHERE id = ? AND status = 'sent'",
    estimateId);

  if (!estimate || estimate.customer_id !== req.portalCustomerId) {
    res.status(404).json({ success: false, message: 'Estimate not found or already processed' });
    return;
  }

  await adb.run(`
    UPDATE estimates SET status = 'approved', approved_at = datetime('now'), updated_at = datetime('now')
    WHERE id = ?
  `, estimateId);

  // SW-D7: Auto-change linked ticket status when estimate is approved
  const statusAfterEstimate = await adb.get<AnyRow>("SELECT value FROM store_config WHERE key = 'ticket_status_after_estimate'");
  if (statusAfterEstimate?.value) {
    const targetStatusId = parseInt(statusAfterEstimate.value);
    if (targetStatusId > 0) {
      const est = await adb.get<AnyRow>('SELECT converted_ticket_id FROM estimates WHERE id = ?', estimateId);
      const ticketId = est?.converted_ticket_id
        || (await adb.get<AnyRow>('SELECT id FROM tickets WHERE estimate_id = ? AND is_deleted = 0', estimateId))?.id;
      if (ticketId) {
        const statusExists = await adb.get<AnyRow>('SELECT id FROM ticket_statuses WHERE id = ?', targetStatusId);
        if (statusExists) {
          await adb.run('UPDATE tickets SET status_id = ?, updated_at = datetime(\'now\') WHERE id = ? AND is_deleted = 0',
            targetStatusId, ticketId);
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
  const adb = req.asyncDb;
  const cid = req.portalCustomerId!;

  const invoices = await adb.all<AnyRow>(`
    SELECT DISTINCT i.id, i.order_id, i.status, i.subtotal, i.discount, i.total_tax, i.total,
           i.amount_paid, i.amount_due, i.created_at, t.order_id AS ticket_order_id
    FROM invoices i
    LEFT JOIN tickets t ON (i.ticket_id = t.id OR i.id = t.invoice_id)
    WHERE (t.customer_id = ? OR i.customer_id = ?) AND (t.is_deleted = 0 OR t.id IS NULL)
    ORDER BY i.created_at DESC
    LIMIT 50
  `, cid, cid);

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
  const adb = req.asyncDb;
  const invoiceId = parseInt(req.params.id as string, 10);
  if (isNaN(invoiceId)) {
    res.status(400).json({ success: false, message: 'Invalid invoice ID' });
    return;
  }

  const cid = req.portalCustomerId!;

  // Verify invoice belongs to customer (via ticket or direct customer_id)
  const invoice = await adb.get<AnyRow>(`
    SELECT i.* FROM invoices i
    LEFT JOIN tickets t ON (i.ticket_id = t.id OR i.id = t.invoice_id)
    WHERE i.id = ? AND (t.customer_id = ? OR i.customer_id = ?)
    LIMIT 1
  `, invoiceId, cid, cid);

  if (!invoice) {
    res.status(404).json({ success: false, message: 'Invoice not found' });
    return;
  }

  const [lineItems, payments] = await Promise.all([
    adb.all<AnyRow>(
      'SELECT description, quantity, unit_price, line_discount, tax_amount, total FROM invoice_line_items WHERE invoice_id = ?',
      invoice.id),
    adb.all<AnyRow>(
      'SELECT amount, method, created_at, notes FROM payments WHERE invoice_id = ?',
      invoice.id),
  ]);

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
// SEC-M19: IP-rate-limited (60 requests / 5 min) + gated on the tenant's
// `portal_embed_enabled` store_config flag (default OFF). Previously the
// endpoint was completely open — any unauth client could scrape every
// tenant's store name, phone, address, and logo by hitting it repeatedly
// across tenant subdomains. Now: disabled tenants return 404, and even
// enabled tenants get throttled per-IP so an attacker can't enumerate the
// fleet by rotating Host headers.
router.get('/embed/config', asyncHandler(async (_req: Request, res: Response) => {
  const db = _req.db;
  const adb = _req.asyncDb;
  const ip = _req.ip || _req.socket?.remoteAddress || 'unknown';

  const { consumeWindowRate } = await import('../utils/rateLimiter.js');
  const result = consumeWindowRate(db, RL.EMBED_CONFIG, ip, 60, 5 * 60 * 1000);
  if (!result.allowed) {
    res.setHeader('Retry-After', String(result.retryAfterSeconds));
    res.status(429).json({ success: false, message: 'Too many requests' });
    return;
  }

  const store = await getStoreConfig(adb);
  if (store.portal_embed_enabled !== '1') {
    res.status(404).json({ success: false, message: 'Not found' });
    return;
  }

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

  // SEC-L27: validate the data-server attribute against a canonical CNAME
  // pattern (\`https://<sub>.<domain>.<tld>[/path]\` OR \`http://localhost...\`
  // during dev). Prior code accepted ANY string, so a malicious embedder
  // could point the widget at an attacker-controlled origin and phish
  // customer credentials by rendering a lookalike portal. The widget is
  // served from OUR origin (same-site) — data-server should resolve to a
  // tenant subdomain we operate, not a random URL.
  var cnamePattern = /^https:\\/\\/[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]+)?(\\/.*)?$/i;
  var isDev = /^https?:\\/\\/(localhost|127\\.0\\.0\\.1)(:[0-9]+)?/i.test(server);
  if (!cnamePattern.test(server) && !isDev) {
    console.error('[BizarrePortal] data-server must be an https URL (hostname.domain.tld), got:', server);
    return;
  }

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
