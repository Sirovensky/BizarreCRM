import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET / – List estimates (paginated, filterable)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const status = (req.query.status as string || '').trim();
    const keyword = (req.query.keyword as string || '').trim();

    const conditions: string[] = [];
    const params: unknown[] = [];

    if (status) {
      conditions.push('e.status = ?');
      params.push(status);
    }
    if (keyword) {
      conditions.push('(e.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ?)');
      const like = `%${keyword}%`;
      params.push(like, like, like);
    }

    const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const { total } = db.prepare(`
      SELECT COUNT(*) as total FROM estimates e
      LEFT JOIN customers c ON c.id = e.customer_id
      ${whereClause}
    `).get(...params) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const estimates = db.prepare(`
      SELECT e.*,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name,
        c.email AS customer_email, c.phone AS customer_phone,
        u.first_name AS created_by_first_name, u.last_name AS created_by_last_name
      FROM estimates e
      LEFT JOIN customers c ON c.id = e.customer_id
      LEFT JOIN users u ON u.id = e.created_by
      ${whereClause}
      ORDER BY e.created_at DESC
      LIMIT ? OFFSET ?
    `).all(...params, pageSize, offset);

    res.json({
      success: true,
      data: {
        estimates,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST / – Create estimate with line items
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const { customer_id, status, discount, notes, valid_until, line_items } = req.body;

    if (!customer_id) throw new AppError('customer_id is required');

    const customer = db.prepare('SELECT id FROM customers WHERE id = ? AND is_deleted = 0').get(customer_id);
    if (!customer) throw new AppError('Customer not found', 404);

    const createEstimate = db.transaction(() => {
      const result = db.prepare(`
        INSERT INTO estimates (order_id, customer_id, status, discount, notes, valid_until, created_by)
        VALUES ('TEMP', ?, ?, ?, ?, ?, ?)
      `).run(
        customer_id,
        status ?? 'draft',
        discount ?? 0,
        notes ?? null,
        valid_until ?? null,
        req.user!.id,
      );

      const estimateId = result.lastInsertRowid as number;
      const orderId = generateOrderId('EST', estimateId);
      db.prepare('UPDATE estimates SET order_id = ? WHERE id = ?').run(orderId, estimateId);

      let subtotal = 0;
      let totalTax = 0;

      if (line_items?.length) {
        const insertItem = db.prepare(`
          INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `);
        for (const item of line_items) {
          const qty = item.quantity ?? 1;
          const price = item.unit_price ?? 0;
          const tax = item.tax_amount ?? 0;
          const lineTotal = qty * price + tax;
          subtotal += qty * price;
          totalTax += tax;

          insertItem.run(
            estimateId,
            item.inventory_item_id ?? null,
            item.description ?? '',
            qty,
            price,
            tax,
            lineTotal,
          );
        }
      }

      const total = subtotal - (discount ?? 0) + totalTax;
      db.prepare('UPDATE estimates SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?')
        .run(subtotal, totalTax, total, estimateId);

      return estimateId;
    });

    const estimateId = createEstimate();
    const estimate = db.prepare('SELECT * FROM estimates WHERE id = ?').get(estimateId);
    const items = db.prepare('SELECT * FROM estimate_line_items WHERE estimate_id = ?').all(estimateId);

    res.status(201).json({
      success: true,
      data: { ...(estimate as any), line_items: items },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Estimate detail with line items
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);

    const estimate = db.prepare(`
      SELECT e.*,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name,
        c.email AS customer_email, c.phone AS customer_phone, c.mobile AS customer_mobile,
        c.address1, c.city, c.state, c.postcode,
        u.first_name AS created_by_first_name, u.last_name AS created_by_last_name
      FROM estimates e
      LEFT JOIN customers c ON c.id = e.customer_id
      LEFT JOIN users u ON u.id = e.created_by
      WHERE e.id = ?
    `).get(id);

    if (!estimate) throw new AppError('Estimate not found', 404);

    const lineItems = db.prepare(`
      SELECT eli.*, ii.name AS item_name, ii.sku AS item_sku
      FROM estimate_line_items eli
      LEFT JOIN inventory_items ii ON ii.id = eli.inventory_item_id
      WHERE eli.estimate_id = ?
      ORDER BY eli.id
    `).all(id);

    res.json({
      success: true,
      data: { ...(estimate as any), line_items: lineItems },
    });
  }),
);

// ---------------------------------------------------------------------------
// PUT /:id – Update estimate
// ---------------------------------------------------------------------------
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM estimates WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Estimate not found', 404);

    const { customer_id, status, discount, notes, valid_until, line_items } = req.body;

    const updateEstimate = db.transaction(() => {
      db.prepare(`
        UPDATE estimates SET
          customer_id = ?, status = ?, discount = ?, notes = ?, valid_until = ?,
          updated_at = datetime('now')
        WHERE id = ?
      `).run(
        customer_id !== undefined ? customer_id : existing.customer_id,
        status !== undefined ? status : existing.status,
        discount !== undefined ? discount : existing.discount,
        notes !== undefined ? notes : existing.notes,
        valid_until !== undefined ? valid_until : existing.valid_until,
        id,
      );

      // Replace line items if provided
      if (line_items !== undefined) {
        db.prepare('DELETE FROM estimate_line_items WHERE estimate_id = ?').run(id);

        let subtotal = 0;
        let totalTax = 0;

        if (line_items?.length) {
          const insertItem = db.prepare(`
            INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          `);
          for (const item of line_items) {
            const qty = item.quantity ?? 1;
            const price = item.unit_price ?? 0;
            const tax = item.tax_amount ?? 0;
            const lineTotal = qty * price + tax;
            subtotal += qty * price;
            totalTax += tax;

            insertItem.run(id, item.inventory_item_id ?? null, item.description ?? '', qty, price, tax, lineTotal);
          }
        }

        const disc = discount !== undefined ? discount : existing.discount;
        const total = subtotal - disc + totalTax;
        db.prepare('UPDATE estimates SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?')
          .run(subtotal, totalTax, total, id);
      }
    });

    updateEstimate();

    const estimate = db.prepare('SELECT * FROM estimates WHERE id = ?').get(id);
    const items = db.prepare('SELECT * FROM estimate_line_items WHERE estimate_id = ?').all(id);

    res.json({
      success: true,
      data: { ...(estimate as any), line_items: items },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/convert – Convert estimate to ticket
// ---------------------------------------------------------------------------
router.post(
  '/:id/convert',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const estimate = db.prepare('SELECT * FROM estimates WHERE id = ?').get(id) as any;
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'converted') throw new AppError('Estimate already converted', 400);

    const convertEstimate = db.transaction(() => {
      // Get default (open) status
      const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get() as any;
      const statusId = defaultStatus?.id ?? 1;

      // Create ticket
      const ticketResult = db.prepare(`
        INSERT INTO tickets (order_id, customer_id, status_id, estimate_id, subtotal, discount, total_tax, total,
          source, created_by)
        VALUES ('TEMP', ?, ?, ?, ?, ?, ?, ?, 'estimate', ?)
      `).run(
        estimate.customer_id, statusId, id,
        estimate.subtotal, estimate.discount, estimate.total_tax, estimate.total,
        req.user!.id,
      );

      const ticketId = ticketResult.lastInsertRowid as number;
      const ticketOrderId = generateOrderId('T', ticketId);
      db.prepare('UPDATE tickets SET order_id = ? WHERE id = ?').run(ticketOrderId, ticketId);

      // Copy line items as ticket devices
      const lineItems = db.prepare('SELECT * FROM estimate_line_items WHERE estimate_id = ?').all(id) as any[];
      for (const item of lineItems) {
        db.prepare(`
          INSERT INTO ticket_devices (ticket_id, device_name, service_id, price, tax_amount, total, additional_notes)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(
          ticketId,
          item.description || 'From Estimate',
          item.inventory_item_id,
          item.unit_price * item.quantity,
          item.tax_amount,
          item.total,
          null,
        );
      }

      // Update estimate status
      db.prepare("UPDATE estimates SET status = 'converted', converted_ticket_id = ?, updated_at = datetime('now') WHERE id = ?")
        .run(ticketId, id);

      return ticketId;
    });

    const ticketId = convertEstimate();
    const ticket = db.prepare('SELECT * FROM tickets WHERE id = ?').get(ticketId);

    res.status(201).json({
      success: true,
      data: { ticket, message: 'Estimate converted to ticket' },
    });
  }),
);

// DELETE /:id — Delete estimate
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id, status FROM estimates WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Estimate not found', 404);
    if (existing.status === 'converted') throw new AppError('Cannot delete a converted estimate', 400);

    db.prepare('DELETE FROM estimate_line_items WHERE estimate_id = ?').run(id);
    db.prepare('DELETE FROM estimates WHERE id = ?').run(id);
    res.json({ success: true, data: { message: 'Estimate deleted' } });
  }),
);

// POST /:id/send — Send estimate to customer via SMS/email
router.post(
  '/:id/send',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const estimate = db.prepare(`
      SELECT e.*, c.first_name, c.last_name, c.phone, c.mobile, c.email
      FROM estimates e LEFT JOIN customers c ON c.id = e.customer_id WHERE e.id = ?
    `).get(id) as any;
    if (!estimate) throw new AppError('Estimate not found', 404);

    // Generate approval token if not exists
    let token = estimate.approval_token;
    if (!token) {
      const crypto = await import('crypto');
      token = crypto.randomBytes(16).toString('hex');
      db.prepare('UPDATE estimates SET approval_token = ?, status = ?, updated_at = ? WHERE id = ?')
        .run(token, 'sent', new Date().toISOString().replace('T', ' ').substring(0, 19), id);
    }

    const { method = 'sms' } = req.body;
    const phone = estimate.phone || estimate.mobile;

    if (method === 'sms' && phone) {
      try {
        const { sendSms } = await import('../services/sms.js');
        const msg = `Hi ${estimate.first_name}, your estimate ${estimate.order_id} for $${Number(estimate.total).toFixed(2)} is ready. Reply YES to approve or view details at your repair shop.`;
        await sendSms(phone, msg);
      } catch { /* SMS provider may not be configured */ }
    }

    res.json({ success: true, data: { sent: true, approval_token: token } });
  }),
);

// POST /:id/approve — Customer approves estimate (can be called with token)
router.post(
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const { token } = req.body;
    const estimate = db.prepare('SELECT id, approval_token, status FROM estimates WHERE id = ?').get(id) as any;
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'approved') throw new AppError('Already approved', 400);
    if (estimate.status === 'converted') throw new AppError('Already converted', 400);

    // Validate token if provided (for unauthenticated approval)
    if (token && estimate.approval_token !== token) throw new AppError('Invalid approval token', 403);

    const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
    db.prepare('UPDATE estimates SET status = ?, approved_at = ?, updated_at = ? WHERE id = ?')
      .run('approved', now, now, id);

    res.json({ success: true, data: { approved: true } });
  }),
);

export default router;
