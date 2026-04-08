import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

type AnyRow = Record<string, any>;

// Rate limiter for public tracking (1 request per 5 seconds per IP)
const trackingLimiter = new Map<string, number>();
function checkTrackingRate(ip: string): boolean {
  const last = trackingLimiter.get(ip);
  if (last && Date.now() - last < 5000) return false;
  trackingLimiter.set(ip, Date.now());
  return true;
}
setInterval(() => { const now = Date.now(); for (const [k, v] of trackingLimiter) { if (now - v > 60000) trackingLimiter.delete(k); } }, 60000);

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
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkTrackingRate(ip)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }

  const orderId = normaliseOrderId(req.params.orderId);
  const token = req.query.token as string;

  // Token is REQUIRED to prevent brute-force enumeration of order IDs
  if (!token || token.length < 6) {
    res.status(400).json({ success: false, message: 'A valid tracking token is required. Use POST /lookup with phone number instead.' });
    return;
  }

  const ticket = db.prepare(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `).get(orderId, token) as AnyRow | undefined;

  if (!ticket) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const devices = db.prepare(
    'SELECT device_name, device_type FROM ticket_devices WHERE ticket_id = ?'
  ).all(ticket.id) as AnyRow[];

  res.json({ success: true, data: toPublicTicket(ticket, devices) });
}));

// ---------------------------------------------------------------------------
// POST /api/v1/track/lookup — look up tickets by phone (+ optional order_id)
// ---------------------------------------------------------------------------
router.post('/lookup', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkTrackingRate(ip)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }
  const { phone, order_id } = req.body as { phone?: string; order_id?: string };

  if (!phone || phone.trim().length < 4) {
    res.status(400).json({ success: false, message: 'Phone number (min 4 digits) is required' });
    return;
  }

  const digits = phone.replace(/\D/g, '');
  const last4 = digits.slice(-4);

  // Find customer IDs whose phone or mobile ends with those 4 digits
  const customers = db.prepare(`
    SELECT DISTINCT c.id
    FROM customers c
    LEFT JOIN customer_phones cp ON cp.customer_id = c.id
    WHERE c.is_deleted = 0
      AND (
        REPLACE(REPLACE(REPLACE(REPLACE(c.phone, '-', ''), ' ', ''), '(', ''), ')', '') LIKE ?
        OR REPLACE(REPLACE(REPLACE(REPLACE(c.mobile, '-', ''), ' ', ''), '(', ''), ')', '') LIKE ?
        OR REPLACE(REPLACE(REPLACE(REPLACE(cp.phone, '-', ''), ' ', ''), '(', ''), ')', '') LIKE ?
      )
  `).all(`%${last4}`, `%${last4}`, `%${last4}`) as AnyRow[];

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

  const tickets = db.prepare(query).all(...params) as AnyRow[];

  const results = tickets.map(t => {
    const devices = db.prepare(
      'SELECT device_name, device_type FROM ticket_devices WHERE ticket_id = ?'
    ).all(t.id) as AnyRow[];
    return toPublicTicket(t, devices);
  });

  res.json({ success: true, data: results });
}));

// ---------------------------------------------------------------------------
// GET /api/v1/track/token/:token — direct link via tracking token
// ---------------------------------------------------------------------------
router.get('/token/:token', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const { token } = req.params;

  if (!token || token.length < 6) {
    res.status(400).json({ success: false, message: 'Invalid tracking token' });
    return;
  }

  const ticket = db.prepare(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token,
           c.first_name AS c_first_name,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.tracking_token = ? AND t.is_deleted = 0
  `).get(token) as AnyRow | undefined;

  if (!ticket) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const devices = db.prepare(
    'SELECT device_name, device_type FROM ticket_devices WHERE ticket_id = ?'
  ).all(ticket.id) as AnyRow[];

  res.json({ success: true, data: toPublicTicket(ticket, devices) });
}));

// ---------------------------------------------------------------------------
// Portal endpoints — all require tracking_token for auth
// ---------------------------------------------------------------------------

/** Shared helper: validate token and return ticket row or null */
function getTicketByToken(db: any, token: string | undefined): AnyRow | undefined {
  if (!token || token.length < 6) return undefined;
  return db.prepare(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token, t.due_on,
           t.subtotal, t.discount, t.total_tax, t.total, t.invoice_id,
           c.first_name AS c_first_name, c.id AS c_id,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.tracking_token = ? AND t.is_deleted = 0
  `).get(token) as AnyRow | undefined;
}

// ---------------------------------------------------------------------------
// GET /api/v1/track/portal/:orderId — Full portal data (status, devices, estimate)
// ---------------------------------------------------------------------------
router.get('/portal/:orderId', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkTrackingRate(ip)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }

  const orderId = normaliseOrderId(req.params.orderId);
  const token = req.query.token as string;

  if (!token || token.length < 6) {
    res.status(400).json({ success: false, message: 'Valid tracking token required' });
    return;
  }

  const ticket = db.prepare(`
    SELECT t.id, t.order_id, t.created_at, t.updated_at, t.tracking_token, t.due_on,
           t.subtotal, t.discount, t.total_tax, t.total, t.invoice_id,
           c.first_name AS c_first_name, c.id AS c_id,
           ts.name AS status_name, ts.color AS status_color, ts.is_closed AS status_is_closed
    FROM tickets t
    LEFT JOIN customers c ON c.id = t.customer_id
    LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `).get(orderId, token) as AnyRow | undefined;

  if (!ticket) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const devices = db.prepare(`
    SELECT device_name, device_type, imei, serial_number, status, due_on,
           additional_notes
    FROM ticket_devices WHERE ticket_id = ?
  `).all(ticket.id) as AnyRow[];

  // Get status timeline
  const history = db.prepare(`
    SELECT action, description, old_value, new_value, created_at
    FROM ticket_history
    WHERE ticket_id = ?
    ORDER BY created_at ASC
  `).all(ticket.id) as AnyRow[];

  // Get customer messages (notes of type 'customer')
  const messages = db.prepare(`
    SELECT tn.id, tn.content, tn.type, tn.created_at,
           u.display_name AS author
    FROM ticket_notes tn
    LEFT JOIN users u ON u.id = tn.user_id
    WHERE tn.ticket_id = ? AND tn.type = 'customer'
    ORDER BY tn.created_at DESC
    LIMIT 50
  `).all(ticket.id) as AnyRow[];

  // Check for invoice
  let invoice: AnyRow | null = null;
  if (ticket.invoice_id) {
    invoice = db.prepare(`
      SELECT i.order_id, i.status, i.subtotal, i.discount, i.total_tax, i.total,
             i.amount_paid, i.amount_due, i.created_at
      FROM invoices i WHERE i.id = ?
    `).get(ticket.invoice_id) as AnyRow | null;
  }
  // Also check by ticket_id
  if (!invoice) {
    invoice = db.prepare(`
      SELECT i.order_id, i.status, i.subtotal, i.discount, i.total_tax, i.total,
             i.amount_paid, i.amount_due, i.created_at
      FROM invoices i WHERE i.ticket_id = ?
      LIMIT 1
    `).get(ticket.id) as AnyRow | null;
  }

  // Get store info for display
  const storeRows = db.prepare(`
    SELECT key, value FROM store_config
    WHERE key IN ('store_name', 'store_phone', 'store_email', 'store_address',
                  'store_city', 'store_state', 'store_zip', 'store_hours')
  `).all() as AnyRow[];
  const store: Record<string, string> = {};
  for (const r of storeRows) store[r.key] = r.value;

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
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkTrackingRate(ip)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }

  const orderId = normaliseOrderId(req.params.orderId);
  const token = req.query.token as string;
  if (!token || token.length < 6) {
    res.status(400).json({ success: false, message: 'Valid tracking token required' });
    return;
  }

  const ticket = db.prepare(`
    SELECT t.id FROM tickets t
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `).get(orderId, token) as AnyRow | undefined;

  if (!ticket) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  const history = db.prepare(`
    SELECT action, description, old_value, new_value, created_at
    FROM ticket_history
    WHERE ticket_id = ?
    ORDER BY created_at ASC
  `).all(ticket.id) as AnyRow[];

  res.json({ success: true, data: history });
}));

// ---------------------------------------------------------------------------
// GET /api/v1/track/portal/:orderId/invoice — Invoice summary
// ---------------------------------------------------------------------------
router.get('/portal/:orderId/invoice', asyncHandler(async (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkTrackingRate(ip)) {
    res.status(429).json({ success: false, message: 'Please wait before trying again' });
    return;
  }

  const orderId = normaliseOrderId(req.params.orderId);
  const token = req.query.token as string;
  if (!token || token.length < 6) {
    res.status(400).json({ success: false, message: 'Valid tracking token required' });
    return;
  }

  const ticket = db.prepare(`
    SELECT t.id, t.invoice_id FROM tickets t
    WHERE t.order_id = ? AND t.tracking_token = ? AND t.is_deleted = 0
  `).get(orderId, token) as AnyRow | undefined;

  if (!ticket) {
    res.status(404).json({ success: false, message: 'Ticket not found' });
    return;
  }

  // Find invoice by invoice_id or ticket_id
  let invoice = null as AnyRow | null;
  if (ticket.invoice_id) {
    invoice = db.prepare(`SELECT * FROM invoices WHERE id = ?`).get(ticket.invoice_id) as AnyRow | null;
  }
  if (!invoice) {
    invoice = db.prepare(`SELECT * FROM invoices WHERE ticket_id = ? LIMIT 1`).get(ticket.id) as AnyRow | null;
  }

  if (!invoice) {
    res.json({ success: true, data: null });
    return;
  }

  const lineItems = db.prepare(`
    SELECT description, quantity, unit_price, line_discount, tax_amount, total
    FROM invoice_line_items WHERE invoice_id = ?
  `).all(invoice.id) as AnyRow[];

  const payments = db.prepare(`
    SELECT amount, method, payment_date, notes FROM payments WHERE invoice_id = ?
  `).all(invoice.id) as AnyRow[];

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
