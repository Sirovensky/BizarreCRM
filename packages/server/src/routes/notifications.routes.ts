import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { sendEmail, isEmailConfigured } from '../services/email.js';
import type { AsyncDb } from '../db/async-db.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';

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
    const id = Number(req.params.id);
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
// POST /send-receipt – Email a receipt for an invoice
// ---------------------------------------------------------------------------
router.post(
  '/send-receipt',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const { invoice_id, email } = req.body;

    if (!invoice_id) throw new AppError('invoice_id is required', 400);

    // Look up invoice with customer info
    const invoice = await adb.get<any>(`
      SELECT inv.*, c.first_name, c.last_name, c.email as customer_email,
        c.phone as customer_phone, c.organization
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `, invoice_id);
    if (!invoice) throw new AppError('Invoice not found', 404);

    const recipientEmail = email || invoice.customer_email;
    if (!recipientEmail) throw new AppError('No email address available. Provide an email in the request.', 400);

    if (!isEmailConfigured(db)) {
      throw new AppError('SMTP is not configured. Set up email in Settings.', 400);
    }

    // Fetch line items + store name in parallel
    const [lineItems, storeNameRow] = await Promise.all([
      adb.all<any>(`
        SELECT description, quantity, unit_price, tax_amount, total
        FROM invoice_line_items WHERE invoice_id = ?
        ORDER BY id ASC
      `, invoice_id),
      adb.get<any>("SELECT value FROM store_config WHERE key = 'store_name'"),
    ]);
    const storeName = storeNameRow?.value || 'Bizarre Electronics';

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
        <p style="font-size:12px;color:#999;">Thank you for your business!</p>
      </div>
    `;

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
