import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { sendEmail, isEmailConfigured } from '../services/email.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List notifications for current user (paginated, unread first)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const userId = req.user!.id;

    const { total } = db.prepare(
      'SELECT COUNT(*) as total FROM notifications WHERE user_id = ?'
    ).get(userId) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const notifications = db.prepare(`
      SELECT * FROM notifications
      WHERE user_id = ?
      ORDER BY is_read ASC, created_at DESC
      LIMIT ? OFFSET ?
    `).all(userId, pageSize, offset);

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
    const db = req.db;
    const userId = req.user!.id;

    const { count } = db.prepare(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0'
    ).get(userId) as { count: number };

    res.json({ success: true, data: { count } });
  }),
);

// ---------------------------------------------------------------------------
// PATCH /:id/read – Mark single notification as read
// ---------------------------------------------------------------------------
router.patch(
  '/:id/read',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const userId = req.user!.id;

    const existing = db.prepare(
      'SELECT id FROM notifications WHERE id = ? AND user_id = ?'
    ).get(id, userId);
    if (!existing) throw new AppError('Notification not found', 404);

    db.prepare(
      "UPDATE notifications SET is_read = 1, updated_at = datetime('now') WHERE id = ?"
    ).run(id);

    const updated = db.prepare('SELECT * FROM notifications WHERE id = ?').get(id);

    res.json({ success: true, data: updated });
  }),
);

// ---------------------------------------------------------------------------
// POST /mark-all-read – Mark all as read for current user
// ---------------------------------------------------------------------------
router.post(
  '/mark-all-read',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const userId = req.user!.id;

    const result = db.prepare(
      "UPDATE notifications SET is_read = 1, updated_at = datetime('now') WHERE user_id = ? AND is_read = 0"
    ).run(userId);

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
    const { invoice_id, email } = req.body;

    if (!invoice_id) throw new AppError('invoice_id is required', 400);

    // Look up invoice with customer info
    const invoice = db.prepare(`
      SELECT inv.*, c.first_name, c.last_name, c.email as customer_email,
        c.phone as customer_phone, c.organization
      FROM invoices inv
      LEFT JOIN customers c ON c.id = inv.customer_id
      WHERE inv.id = ?
    `).get(invoice_id) as any;
    if (!invoice) throw new AppError('Invoice not found', 404);

    const recipientEmail = email || invoice.customer_email;
    if (!recipientEmail) throw new AppError('No email address available. Provide an email in the request.', 400);

    if (!isEmailConfigured(db)) {
      throw new AppError('SMTP is not configured. Set up email in Settings.', 400);
    }

    // Fetch line items
    const lineItems = db.prepare(`
      SELECT description, quantity, unit_price, tax_amount, total
      FROM invoice_line_items WHERE invoice_id = ?
      ORDER BY id ASC
    `).all(invoice_id) as any[];

    // Get store name
    const storeNameRow = db.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as any;
    const storeName = storeNameRow?.value || 'Bizarre Electronics';

    // Build receipt HTML
    const lineItemsHtml = lineItems.map((li: any) =>
      `<tr>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;">${li.description}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:center;">${li.quantity}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:right;">$${Number(li.unit_price).toFixed(2)}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #eee;text-align:right;">$${Number(li.total).toFixed(2)}</td>
      </tr>`
    ).join('');

    const html = `
      <div style="max-width:600px;margin:0 auto;font-family:Arial,sans-serif;color:#333;">
        <h2 style="color:#0d9488;">${storeName}</h2>
        <p>Receipt for Invoice <strong>${invoice.order_id}</strong></p>
        <p>Customer: ${invoice.first_name || ''} ${invoice.last_name || ''}</p>
        <p>Date: ${new Date(invoice.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</p>
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

    const sent = await sendEmail(db, {
      to: recipientEmail,
      subject: `Receipt for Invoice ${invoice.order_id} — ${storeName}`,
      html,
    });

    if (!sent) throw new AppError('Failed to send email', 500);

    res.json({ success: true, data: { message: `Receipt sent to ${recipientEmail}` } });
  }),
);

export default router;
