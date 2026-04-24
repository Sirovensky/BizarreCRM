import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { sendEmail, isEmailConfigured } from '../services/email.js';
import type { AsyncDb } from '../db/async-db.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import { validateId } from '../utils/validate.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('notifications');

function requireManagerOrAdmin(req: any): void {
  const role = req?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

const router = Router();

// @audit-fixed: §37 — Receipt HTML used to interpolate customer + line-item
// strings directly into the template, so an attacker who could write a
// description (e.g. via the POS or invoice editor) could land stored XSS in
// any receipt email. Escape every user-derived string before it lands in the
// HTML body.
function escapeHtml(value: unknown): string {
  if (value == null) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ---------------------------------------------------------------------------
// GET / – List notifications for current user (paginated, unread first)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = parsePage(req.query.page);
    const pageSize = parsePageSize(req.query.pagesize, 20);
    const userId = req.user!.id;
    const offset = (page - 1) * pageSize;

    const [countRow, notifications] = await Promise.all([
      adb.get<{ total: number }>(
        'SELECT COUNT(*) as total FROM notifications WHERE user_id = ?', userId
      ),
      adb.all(`
        SELECT * FROM notifications
        WHERE user_id = ?
        ORDER BY is_read ASC, created_at DESC
        LIMIT ? OFFSET ?
      `, userId, pageSize, offset),
    ]);

    const total = countRow?.total ?? 0;
    const totalPages = Math.ceil(total / pageSize);

    res.json({
      success: true,
      data: {
        notifications,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /unread-count – Count of unread notifications for current user
// ---------------------------------------------------------------------------
router.get(
  '/unread-count',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;

    const row = await adb.get<{ count: number }>(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0', userId
    );
    const count = row?.count ?? 0;

    res.json({ success: true, data: { count } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id/read – Mark single notification as read
// ---------------------------------------------------------------------------
router.patch(
  '/:id/read',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = validateId(req.params.id, 'id');
    const userId = req.user!.id;

    const existing = await adb.get(
      'SELECT id FROM notifications WHERE id = ? AND user_id = ?', id, userId
    );
    if (!existing) throw new AppError('Notification not found', 404);

    await adb.run(
      "UPDATE notifications SET is_read = 1, updated_at = datetime('now') WHERE id = ?", id
    );

    const updated = await adb.get('SELECT * FROM notifications WHERE id = ?', id);

    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// POST /mark-all-read – Mark all as read for current user
// ---------------------------------------------------------------------------
router.post(
  '/mark-all-read',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;

    const result = await adb.run(
      "UPDATE notifications SET is_read = 1, updated_at = datetime('now') WHERE user_id = ? AND is_read = 0", userId
    );

    res.json({
      success: true,
      data: { message: 'All notifications marked as read', updated: result.changes },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /focus-policies – Fetch stored focus-filter descriptor for current user
// PUT /focus-policies – Persist focus-filter descriptor for current user
// Called by iOS FocusFilterEndpoints. Stored as a single JSON blob per user
// in user_preferences table (key = 'focus_policies').
// ---------------------------------------------------------------------------
router.get(
  '/focus-policies',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user!.id;

    const row = await adb.get<{ value: string }>(
      "SELECT value FROM user_preferences WHERE user_id = ? AND key = 'focus_policies'",
      userId,
    );

    // Return empty policies object when none stored — client builds its own defaults
    let policies: unknown = { policies: [] };
    if (row?.value) {
      try {
        policies = JSON.parse(row.value);
      } catch {
        logger.warn('[notifications] focus_policies JSON.parse failed for user', { userId });
      }
    }
    res.json({ success: true, data: policies });
  }),
);

router.put(
  '/focus-policies',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const userId = req.user!.id;
    const body = req.body;

    if (!body || typeof body !== 'object') {
      throw new AppError('Request body is required', 400);
    }

    const json = JSON.stringify(body);

    await adb.run(
      `INSERT INTO user_preferences (user_id, key, value)
       VALUES (?, 'focus_policies', ?)
       ON CONFLICT(user_id, key) DO UPDATE SET value = excluded.value`,
      userId,
      json,
    );

    audit(db, 'focus_policies_updated', userId, req.ip ?? '', { policies: body });

    res.json({ success: true, data: null });
  }),
);

// ---------------------------------------------------------------------------
// POST /send-receipt – Email a receipt for an invoice
// ---------------------------------------------------------------------------
router.post(
  '/send-receipt',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);

    const db = req.db;
    const adb = req.asyncDb;
    const { invoice_id, recipient_email } = req.body as { invoice_id: unknown; recipient_email: unknown };

    const invoiceId = validateId(invoice_id, 'invoice_id');

    if (typeof recipient_email !== 'string' || !recipient_email.includes('@')) {
      throw new AppError('recipient_email required', 400);
    }

    // Look up invoice with customer info
    const invoice = await adb.get<any>(`
      SELECT inv.*, c.first_name, c.last_name, c.email as customer_email,
        c.phone as customer_phone, c.organization
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `, invoiceId);
    if (!invoice) throw new AppError('Invoice not found', 404);

    // SCAN-811: Verify recipient matches the invoice's customer (defense in depth)
    if (invoice.customer_email !== recipient_email) {
      throw new AppError('recipient_email must match the invoice customer', 403);
    }

    const recipientEmail = recipient_email;

    if (!isEmailConfigured(db)) {
      throw new AppError('SMTP is not configured. Set up email in Settings.', 400);
    }

    // Fetch line items + receipt config rows in parallel
    const [lineItems, configRows] = await Promise.all([
      adb.all<{ description: string; quantity: number; unit_price: number; tax_amount: number; total: number }>(`
        SELECT description, quantity, unit_price, tax_amount, total
        FROM invoice_line_items WHERE invoice_id = ?
        ORDER BY id ASC
      `, invoiceId),
      adb.all<{ key: string; value: string }>(
        `SELECT key, value FROM store_config WHERE key IN ('store_name','receipt_header','receipt_footer','receipt_thermal_footer')`
      ),
    ]);
    const cfgMap = Object.fromEntries(configRows.map((r) => [r.key, r.value]));
    const storeName = cfgMap['store_name'] || 'Your Shop';
    const receiptHeader = cfgMap['receipt_header'] || '';
    // Prefer thermal footer; fall back to page footer; then a generic default.
    const receiptFooter = cfgMap['receipt_thermal_footer'] || cfgMap['receipt_footer'] || 'Thank you for your business!';

    // Build receipt HTML
    // @audit-fixed: §37 — escape every user-controlled field. li.description,
    // first_name, last_name, store_name, and invoice.order_id all flow from
    // user input and previously enabled stored XSS in the receipt email.
    const lineItemsHtml = lineItems.map((li: any) =>
      `<tr>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;">${escapeHtml(li.description)}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:center;">${escapeHtml(li.quantity)}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:right;">$${Number(li.unit_price).toFixed(2)}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:right;">$${Number(li.total).toFixed(2)}</td>
      </tr>`
    ).join('');

    const html = `
      <div style="max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#333;">
        <h2 style="color:#0d9488;">${escapeHtml(storeName)}</h2>
        ${receiptHeader ? `<p style="font-size:13px;color:#555;margin-bottom:12px;">${escapeHtml(receiptHeader)}</p>` : ''}
        <p>Receipt for Invoice <strong>${escapeHtml(invoice.order_id)}</strong></p>
        <p>Customer: ${escapeHtml(invoice.first_name || '')} ${escapeHtml(invoice.last_name || '')}</p>
        <p>Date: ${escapeHtml(new Date(invoice.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }))}</p>
        <table style="width:100%;border-collapse:collapse;margin:16px 0;">
          <thead>
            <tr style="background:#f5f5f5;">
              <th style="padding:8px;text-align:left;">Description</th>
              <th style="padding:8px;text-align:center;">Qty</th>
              <th style="padding:8px;text-align:right;">Price</th>
              <th style="padding:8px;text-align:right;">Total</th>
            </tr>
          </thead>
          <tbody>${lineItemsHtml}</tbody>
        </table>
        <div style="text-align:right;margin-top:12px;">
          <p>Subtotal: <strong>$${Number(invoice.subtotal).toFixed(2)}</strong></p>
          ${invoice.discount > 0 ? `<p>Discount: <strong>-$${Number(invoice.discount).toFixed(2)}</strong></p>` : ''}
          <p>Tax: <strong>$${Number(invoice.total_tax).toFixed(2)}</strong></p>
          <p style="font-size:18px;">Total: <strong>$${Number(invoice.total).toFixed(2)}</strong></p>
          <p>Paid: <strong>$${Number(invoice.amount_paid).toFixed(2)}</strong></p>
          ${invoice.amount_due > 0 ? `<p style="color:#dc2626;">Balance Due: <strong>$${Number(invoice.amount_due).toFixed(2)}</strong></p>` : ''}
        </div>
        <hr style="margin:24px 0;border:none;border-top:1px solid #ddd;" />
        <p style="font-size:12px;color:#999;">${escapeHtml(receiptFooter)}</p>
      </div>
    `;

    // SCAN-810: Audit before dispatch so the record exists even if email fails
    audit(db, 'receipt_emailed', req.user!.id, req.ip ?? '', { invoice_id: invoiceId, recipient_email: recipientEmail });

    // @audit-fixed: §37 — strip CR/LF from email subject so a malicious
    // order_id can't inject extra headers (header injection).
    const safeSubjectOrderId = String(invoice.order_id).replace(/[\r\n]+/g, ' ');
    const safeSubjectStoreName = String(storeName).replace(/[\r\n]+/g, ' ');
    const sent = await sendEmail(db, {
      to: recipientEmail,
      subject: `Receipt for Invoice ${safeSubjectOrderId} — ${safeSubjectStoreName}`,
      html,
    });

    if (!sent) throw new AppError('Failed to send email', 500);

    res.json({ success: true, data: { message: `Receipt sent to ${recipientEmail}` } });
  }),
);

export default router;
