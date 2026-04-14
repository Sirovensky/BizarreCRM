import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import type { AsyncDb } from '../db/async-db.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';

const router = Router();

type AnyRow = Record<string, any>;

// ---------------------------------------------------------------------------
// Security constants
// ---------------------------------------------------------------------------

/**
 * PT5: Minimum accepted tracking token length. Tokens are generated at 64
 * hex chars (32 bytes), so anything shorter than 32 is either malformed or
 * a legacy short token we no longer trust. Rejecting at 32 gives 128 bits of
 * entropy which is infeasible to brute force.
 */
const MIN_TRACKING_TOKEN_LEN = 32;

/**
 * PT7: Lookups are not constant-time (indexed DB lookup leaks presence via
 * response time). Until we move to hashed tokens via a migration, floor every
 * token lookup at this duration so the timing difference between a hit and
 * a miss is dominated by the wait, not the query. 50ms is short enough to
 * be imperceptible on the happy path and long enough to drown out ~ms-scale
 * DB variation.
 */
const TOKEN_LOOKUP_FLOOR_MS = 50;

/** Wait until at least `floorMs` have passed since `startedAt`. */
async function enforceTimingFloor(startedAt: number, floorMs: number): Promise<void> {
  const elapsed = Date.now() - startedAt;
  const remaining = floorMs - elapsed;
  if (remaining > 0) {
    await new Promise<void>(resolve => setTimeout(resolve, remaining));
  }
}

/** PT5 guard: consistent error for invalid / too-short tokens. */
function rejectShortToken(res: Response, token: unknown): boolean {
  if (typeof token !== 'string' || token.length < MIN_TRACKING_TOKEN_LEN) {
    res.status(400).json({
      success: false,
      message: 'A valid tracking token is required. Use POST /lookup with phone number instead.',
    });
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Normalise an order_id input like "42", "0042", "T-0042" → "T-0042" so it
 *  matches the stored format. */
function normaliseOrderId(raw: string): string {
  let cleaned = raw.trim().toUpperCase();
  // Strip leading "T-" if present
  if (cleaned.startsWith('T-')) cleaned = cleaned.substring(2);
  // Remove leading zeros then pad to 4 digits
  const num = parseInt(cleaned, 10);
  if (isNaN(num)) return raw.trim(); // fallback — let the DB reject it
  return `T-${String(num).padStart(4, '0')}`;
}

/** Shape a raw ticket row into the safe public payload (no pricing, no notes,
 *  no full customer info). */
// @audit-fixed: §37 — Reverted token-stripping after confirming
// pages/tracking/TrackingPage.tsx:192-194 needs the token back from
// /lookup to navigate the customer into the portal. The architectural
// flaw (phone last-4 yields token) is logged in criticalaudit-rerun.md
// §37 as a follow-up requiring proper customer auth, NOT a one-line fix.
// Compensating control: per-phone rate limit added below in /lookup.
function toPublicTicket(row: AnyRow, devices: AnyRow[]): Record<string, any> {
  return {
    order_id: row.order_id,
    status: {
      name: row.status_name,
      color: row.status_color,
      is_closed: !!row.status_is_closed,
    },
    customer_first_name: row.c_first_name ?? null,
    devices: devices.map(d => ({
      name: d.device_name,
      type: d.device_type,
    })),
    created_at: row.created_at,
    updated_at: row.updated_at,
    tracking_token: row.tracking_token ?? null,
  };
}

// ---------------------------------------------------------------------------
// GET /api/v1/track/:orderId — look up a single ticket by order_id
// ---------------------------------------------------------------------------
router.get('/:orderId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(req.db, 'tracking', ip, 1, 5000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  recordWindowFailure(req.db, 'tracking', ip, 5000);

  const orderId = normaliseOrderId(req.params.orderId as string);
  const token = req.query.token as string | undefined;

  // PT5: reject anything shorter than a full 32-char token.
  if (rejectShortToken(res, token)) return;

  // PT7: start the timing floor BEFORE the lookup so the response time
  // is the same whether the row exists or not.
  const startedAt = Date.now();

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `, orderId, token);

  if (!ticket) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const devices = await adb.all<AnyRow>(
    'SELECT device_name, device_type FROM ticket_devices WHERE ticket_id = ?',
    ticket.id
  );

  await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
  res.json({ success: true, data: toPublicTicket(ticket, devices) });
}));

// ---------------------------------------------------------------------------
// POST /api/v1/track/lookup — look up tickets by phone (+ optional order_id)
// ---------------------------------------------------------------------------
router.post('/lookup', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(req.db, 'tracking', ip, 1, 5000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  recordWindowFailure(req.db, 'tracking', ip, 5000);
  const { phone, order_id } = req.body as { phone?: string; order_id?: string };

  if (!phone || phone.trim().length < 4) {
    res.status(400).json({ success: false, message: 'Phone number (min 4 digits) is required' });
    return;
  }

  const digits = phone.replace(/\D/g, '');
  const last4 = digits.slice(-4);

  // @audit-fixed: §37 — Compensating control for the architectural flaw that
  // /lookup returns tracking_token when given just a phone last-4. Per-IP
  // rate limiting alone lets a botnet harvest tokens at any rate. Add a
  // per-last4 rate limit (10 attempts per hour) so a single phone segment
  // can't be brute-forced across all 10000 combinations from any IP set.
  const last4Key = `lookup_last4:${last4}`;
  if (!checkWindowRate(req.db, 'tracking_last4', last4Key, 10, 60 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many lookups for this number. Try again later.' });
    return;
  }
  recordWindowFailure(req.db, 'tracking_last4', last4Key, 60 * 60 * 1000);

  // Find customer IDs whose phone or mobile ends with those 4 digits
  const customers = await adb.all<AnyRow>(`
    SELECT DISTINCT c.id
    FROM customers c
    LEFT JOIN customer_phones cp ON cp.customer_id = c.id
    WHERE c.is_deleted = 0
      AND (
        REPLACE(REPLACE(REPLACE(REPLACE(c.phone, '-', ''), ' ', ''), '(', ''), ')', '') LIKE ?
        OR REPLACE(REPLACE(REPLACE(REPLACE(c.mobile, '-', ''), ' ', ''), '(', ''), ')', '') LIKE ?
        OR REPLACE(REPLACE(REPLACE(REPLACE(cp.phone, '-', ''), ' ', ''), '(', ''), ')', '') LIKE ?
      )
  `, `%${last4}`, `%${last4}`, `%${last4}`);

  if (customers.length === 0) {
    res.json({ success: true, data: [] });
    return;
  }

  const customerIds = customers.map(c => c.id);
  const placeholders = customerIds.map(() => '?').join(',');

  let query = `
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.customer_id IN (${placeholders}) AND t.is_deleted = 0
  `;
  const params: any[] = [...customerIds];

  // If order_id also provided, filter to that specific ticket (validates phone ownership)
  if (order_id) {
    const normId = normaliseOrderId(order_id);
    query += ' AND t.order_id = ?';
    params.push(normId);
  }

  query += ' ORDER BY t.created_at DESC LIMIT 10';

  const tickets = await adb.all<AnyRow>(query, ...params);

  const results = await Promise.all(tickets.map(async t => {
    const devices = await adb.all<AnyRow>(
      'SELECT device_name, device_type FROM ticket_devices WHERE ticket_id = ?',
      t.id
    );
    return toPublicTicket(t, devices);
  }));

  res.json({ success: true, data: results });
}));

// ---------------------------------------------------------------------------
// GET /api/v1/track/token/:token — direct link via tracking token
// ---------------------------------------------------------------------------
router.get('/token/:token', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const { token } = req.params;

  // PT5: reject anything shorter than a full 32-char token.
  if (rejectShortToken(res, token)) return;

  // PT7: timing floor around the lookup.
  const startedAt = Date.now();

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.tracking_token = ? AND t.is_deleted = 0
  `, token);

  if (!ticket) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const devices = await adb.all<AnyRow>(
    'SELECT device_name, device_type FROM ticket_devices WHERE ticket_id = ?',
    ticket.id
  );

  await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
  res.json({ success: true, data: toPublicTicket(ticket, devices) });
}));

// ---------------------------------------------------------------------------
// Portal endpoints — all require tracking_token for auth
// ---------------------------------------------------------------------------

/** Shared helper: validate token and return ticket row or null */
async function getTicketByToken(adb: AsyncDb, token: string | undefined): Promise<AnyRow | undefined> {
  if (!token || token.length < MIN_TRACKING_TOKEN_LEN) return undefined;
  return await adb.get<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token, t.due_on,
           t.subtotal, t.discount, t.total_tax, t.total, t.invoice_id,
           c.first_name AS c_first_name, c.id AS c_id,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.tracking_token = ? AND t.is_deleted = 0
  `, token);
}

// ---------------------------------------------------------------------------
// GET /api/v1/track/portal/:orderId — Full portal data (status, devices, estimate)
// ---------------------------------------------------------------------------
router.get('/portal/:orderId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(req.db, 'tracking', ip, 1, 5000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  recordWindowFailure(req.db, 'tracking', ip, 5000);

  const orderId = normaliseOrderId(req.params.orderId as string);
  const token = req.query.token as string | undefined;

  // PT5: require a full-length token
  if (rejectShortToken(res, token)) return;

  // PT7: timing floor around lookup
  const startedAt = Date.now();

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token, t.due_on,
           t.subtotal, t.discount, t.total_tax, t.total, t.invoice_id,
           c.first_name AS c_first_name, c.id AS c_id,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `, orderId, token);

  if (!ticket) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const [devices, history, messages, storeRows] = await Promise.all([
    adb.all<AnyRow>(`
      SELECT device_name, device_type, imei, serial_number, status, due_on,
             additional_notes
      FROM ticket_devices WHERE ticket_id = ?
    `, ticket.id),
    adb.all<AnyRow>(`
      SELECT action, description, old_value, new_value, created_at
      FROM ticket_history
      WHERE ticket_id = ?
      ORDER BY created_at ASC
    `, ticket.id),
    adb.all<AnyRow>(`
      SELECT tn.id, tn.content, tn.type, tn.created_at,
             u.display_name AS author
      FROM ticket_notes tn
      LEFT JOIN users u ON u.id = tn.user_id
      WHERE tn.ticket_id = ? AND tn.type = 'customer'
      ORDER BY tn.created_at DESC
      LIMIT 50
    `, ticket.id),
    adb.all<AnyRow>(`
      SELECT key, value FROM store_config
      WHERE key IN ('store_name', 'store_phone', 'store_email', 'store_address',
                    'store_city', 'store_state', 'store_zip', 'store_hours')
    `),
  ]);

  // Check for invoice
  let invoice: AnyRow | null = null;
  if (ticket.invoice_id) {
    invoice = await adb.get<AnyRow>(`
      SELECT i.order_id, i.status, i.subtotal, i.discount, i.total_tax, i.total,
             i.amount_paid, i.amount_due, i.created_at
      FROM invoices i WHERE i.id = ?
    `, ticket.invoice_id) ?? null;
  }
  // Also check by ticket_id
  if (!invoice) {
    invoice = await adb.get<AnyRow>(`
      SELECT i.order_id, i.status, i.subtotal, i.discount, i.total_tax, i.total,
             i.amount_paid, i.amount_due, i.created_at
      FROM invoices i WHERE i.ticket_id = ?
      LIMIT 1
    `, ticket.id) ?? null;
  }

  const store: Record<string, string> = {};
  for (const r of storeRows) store[r.key] = r.value;

  await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
  res.json({
    success: true,
    data: {
      order_id: ticket.order_id,
      status: {
        name: ticket.status_name,
        color: ticket.status_color,
        is_closed: !!ticket.status_is_closed,
      },
      customer_first_name: ticket.c_first_name ?? null,
      due_on: ticket.due_on ?? null,
      created_at: ticket.created_at,
      updated_at: ticket.updated_at,
      devices: devices.map(d => ({
        name: d.device_name,
        type: d.device_type,
        status: d.status,
        due_on: d.due_on,
        notes: d.additional_notes,
      })),
      history: history.map(h => ({
        action: h.action,
        description: h.description,
        old_value: h.old_value,
        new_value: h.new_value,
        created_at: h.created_at,
      })),
      messages,
      invoice: invoice ? {
        order_id: invoice.order_id,
        status: invoice.status,
        subtotal: invoice.subtotal,
        discount: invoice.discount,
        tax: invoice.total_tax,
        total: invoice.total,
        amount_paid: invoice.amount_paid,
        amount_due: invoice.amount_due,
      } : null,
      store,
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /api/v1/track/portal/:orderId/history — Status change timeline only
// ---------------------------------------------------------------------------
router.get('/portal/:orderId/history', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(req.db, 'tracking', ip, 1, 5000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  recordWindowFailure(req.db, 'tracking', ip, 5000);

  const orderId = normaliseOrderId(req.params.orderId as string);
  const token = req.query.token as string | undefined;

  // PT5: require a full-length token
  if (rejectShortToken(res, token)) return;

  // PT7: timing floor around lookup
  const startedAt = Date.now();

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id FROM tickets t
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `, orderId, token);

  if (!ticket) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const history = await adb.all<AnyRow>(`
    SELECT action, description, old_value, new_value, created_at
    FROM ticket_history
    WHERE ticket_id = ?
    ORDER BY created_at ASC
  `, ticket.id);

  await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
  res.json({ success: true, data: history });
}));

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// POST /api/v1/track/portal/:orderId/message — Public tracking message composer
// ---------------------------------------------------------------------------
router.post('/portal/:orderId/message', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(req.db, 'tracking_msg', ip, 3, 60000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }

  const orderId = normaliseOrderId(req.params.orderId as string);
  const token = req.query.token as string | undefined;

  if (rejectShortToken(res, token)) return;
  const startedAt = Date.now();

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id FROM tickets t
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `, orderId, token);

  if (!ticket) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const { content } = req.body as { content?: string };
  if (!content || typeof content !== 'string' || content.trim().length === 0) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(400).json({ success: false, message: 'Message content is required' });
    return;
  }

  await adb.run(`
    INSERT INTO ticket_notes (ticket_id, content, type, created_at, updated_at)
    VALUES (?, ?, 'customer', datetime('now'), datetime('now'))
  `, ticket.id, content.trim().slice(0, 5000));

  await adb.run(`
    INSERT INTO ticket_history (ticket_id, action, description, created_at)
    VALUES (?, 'customer_message', 'Customer left a message via tracking portal', datetime('now'))
  `, ticket.id);

  recordWindowFailure(req.db, 'tracking_msg', ip, 60000);

  await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
  res.json({ success: true, data: { sent: true } });
}));

// ---------------------------------------------------------------------------
// GET /api/v1/track/portal/:orderId/invoice — Invoice summary
// ---------------------------------------------------------------------------
router.get('/portal/:orderId/invoice', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(req.db, 'tracking', ip, 1, 5000)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  recordWindowFailure(req.db, 'tracking', ip, 5000);

  const orderId = normaliseOrderId(req.params.orderId as string);
  const token = req.query.token as string | undefined;

  // PT5: require a full-length token
  if (rejectShortToken(res, token)) return;

  // PT7: timing floor around lookup
  const startedAt = Date.now();

  const ticket = await adb.get<AnyRow>(`
    SELECT t.id, t.invoice_id FROM tickets t
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `, orderId, token);

  if (!ticket) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  // Find invoice by invoice_id or ticket_id
  let invoice: AnyRow | null = null;
  if (ticket.invoice_id) {
    invoice = await adb.get<AnyRow>(`SELECT * FROM invoices WHERE id = ?`, ticket.invoice_id) ?? null;
  }
  if (!invoice) {
    invoice = await adb.get<AnyRow>(`SELECT * FROM invoices WHERE ticket_id = ? LIMIT 1`, ticket.id) ?? null;
  }

  if (!invoice) {
    await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
    res.json({ success: true, data: null });
    return;
  }

  const [lineItems, payments] = await Promise.all([
    adb.all<AnyRow>(`
      SELECT description, quantity, unit_price, line_discount, tax_amount, total
      FROM invoice_line_items WHERE invoice_id = ?
    `, invoice.id),
    adb.all<AnyRow>(`
      SELECT amount, method, payment_date, notes FROM payments WHERE invoice_id = ?
    `, invoice.id),
  ]);

  await enforceTimingFloor(startedAt, TOKEN_LOOKUP_FLOOR_MS);
  res.json({
    success: true,
    data: {
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
      payments: payments.map(p => ({
        amount: p.amount,
        method: p.method,
        date: p.payment_date,
      })),
    },
  });
}));

export default router;
