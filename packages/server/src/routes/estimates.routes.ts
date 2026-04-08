import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';

const router = Router();

// SEC-H10: Rate limiter for estimate approval (10 attempts per minute per IP)
// Prevents brute-force guessing of approval tokens on the public-facing endpoint.
const approvalRateMap = new Map<string, { count: number; resetAt: number }>();
const APPROVAL_RATE_LIMIT = 10;
const APPROVAL_RATE_WINDOW = 60_000; // 1 minute
function checkApprovalRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = approvalRateMap.get(ip);
  if (entry && now < entry.resetAt) {
    if (entry.count >= APPROVAL_RATE_LIMIT) return false;
    entry.count++;
    return true;
  }
  approvalRateMap.set(ip, { count: 1, resetAt: now + APPROVAL_RATE_WINDOW });
  return true;
}
// Clean stale entries every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of approvalRateMap) { if (now >= entry.resetAt) approvalRateMap.delete(ip); }
}, 5 * 60_000).unref();

// ---------------------------------------------------------------------------
// GET / – List estimates (paginated, filterable)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const db = req.db;
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
    `).all(...params, pageSize, offset) as any[];

    // ENR-LE9: Compute is_expiring and days_until_expiry for each estimate
    const now = new Date();
    const enrichedEstimates = estimates.map(est => {
      let days_until_expiry: number | null = null;
      let is_expiring = false;
      if (est.valid_until) {
        const expiryDate = new Date(est.valid_until);
        const diffMs = expiryDate.getTime() - now.getTime();
        days_until_expiry = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
        is_expiring = days_until_expiry >= 0 && days_until_expiry <= 3;
      }
      return { ...est, is_expiring, days_until_expiry };
    });

    res.json({
      success: true,
      data: {
        estimates: enrichedEstimates,
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
    const db = req.db;
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
// POST /bulk-convert – Bulk convert estimates to tickets (ENR-LE10, admin-only)
// ---------------------------------------------------------------------------
router.post(
  '/bulk-convert',
  asyncHandler(async (req, res) => {
    if (req.user!.role !== 'admin') throw new AppError('Admin access required', 403);

    const db = req.db;
    const { estimate_ids } = req.body;
    if (!Array.isArray(estimate_ids) || estimate_ids.length === 0) {
      throw new AppError('estimate_ids array is required', 400);
    }
    if (estimate_ids.length > 50) {
      throw new AppError('Maximum 50 estimates per batch', 400);
    }

    const results: Array<{ estimate_id: number; ticket_id?: number; error?: string }> = [];

    const bulkConvert = db.transaction(() => {
      for (const estId of estimate_ids) {
        try {
          const estimate = db.prepare('SELECT * FROM estimates WHERE id = ?').get(estId) as any;
          if (!estimate) {
            results.push({ estimate_id: estId, error: 'Estimate not found' });
            continue;
          }
          if (estimate.status === 'converted') {
            results.push({ estimate_id: estId, error: 'Already converted' });
            continue;
          }

          // Get default (open) status
          const defaultStatus = db.prepare('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1').get() as any;
          const statusId = defaultStatus?.id ?? 1;

          // Create ticket
          const ticketResult = db.prepare(`
            INSERT INTO tickets (order_id, customer_id, status_id, estimate_id, subtotal, discount, total_tax, total,
              source, created_by)
            VALUES ('TEMP', ?, ?, ?, ?, ?, ?, ?, 'estimate', ?)
          `).run(
            estimate.customer_id, statusId, estId,
            estimate.subtotal, estimate.discount, estimate.total_tax, estimate.total,
            req.user!.id,
          );

          const ticketId = ticketResult.lastInsertRowid as number;
          const ticketOrderId = generateOrderId('T', ticketId);
          db.prepare('UPDATE tickets SET order_id = ? WHERE id = ?').run(ticketOrderId, ticketId);

          // Copy line items as ticket devices
          const lineItems = db.prepare('SELECT * FROM estimate_line_items WHERE estimate_id = ?').all(estId) as any[];
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
            .run(ticketId, estId);

          results.push({ estimate_id: estId, ticket_id: ticketId });
        } catch (err: unknown) {
          const msg = err instanceof Error ? err.message : 'Unknown error';
          results.push({ estimate_id: estId, error: msg });
        }
      }
    });

    bulkConvert();

    const successCount = results.filter(r => !r.error).length;
    const failCount = results.filter(r => r.error).length;

    audit(db, 'estimate_bulk_convert', req.user!.id, req.ip || 'unknown', {
      estimate_ids,
      success_count: successCount,
      fail_count: failCount,
    });

    res.json({
      success: true,
      data: { results, success_count: successCount, fail_count: failCount },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id – Estimate detail with line items
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const db = req.db;
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
    const db = req.db;
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT * FROM estimates WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Estimate not found', 404);

    const { customer_id, status, discount, notes, valid_until, line_items } = req.body;

    const updateEstimate = db.transaction(() => {
      // ENR-LE6: Snapshot current state before updating
      const currentLineItems = db.prepare('SELECT * FROM estimate_line_items WHERE estimate_id = ?').all(id);
      const lastVersion = db.prepare(
        'SELECT MAX(version_number) AS max_ver FROM estimate_versions WHERE estimate_id = ?'
      ).get(id) as any;
      const nextVersion = (lastVersion?.max_ver ?? 0) + 1;

      const snapshot = {
        ...existing,
        line_items: currentLineItems,
      };
      db.prepare(`
        INSERT INTO estimate_versions (estimate_id, version_number, data)
        VALUES (?, ?, ?)
      `).run(id, nextVersion, JSON.stringify(snapshot));

      // ENR-LE8: Track sent_at when status transitions to 'sent'
      const effectiveStatus = status !== undefined ? status : existing.status;
      const shouldSetSentAt = effectiveStatus === 'sent' && existing.status !== 'sent' && !existing.sent_at;

      db.prepare(`
        UPDATE estimates SET
          customer_id = ?, status = ?, discount = ?, notes = ?, valid_until = ?,
          sent_at = CASE WHEN ? THEN datetime('now') ELSE sent_at END,
          updated_at = datetime('now')
        WHERE id = ?
      `).run(
        customer_id !== undefined ? customer_id : existing.customer_id,
        effectiveStatus,
        discount !== undefined ? discount : existing.discount,
        notes !== undefined ? notes : existing.notes,
        valid_until !== undefined ? valid_until : existing.valid_until,
        shouldSetSentAt ? 1 : 0,
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
// GET /:id/versions – List estimate version history (ENR-LE6)
// ---------------------------------------------------------------------------
router.get(
  '/:id/versions',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id FROM estimates WHERE id = ?').get(id);
    if (!existing) throw new AppError('Estimate not found', 404);

    const versions = db.prepare(
      'SELECT id, estimate_id, version_number, created_at FROM estimate_versions WHERE estimate_id = ? ORDER BY version_number DESC'
    ).all(id);

    res.json({ success: true, data: versions });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/versions/:versionId – Get a specific estimate version snapshot (ENR-LE6)
// ---------------------------------------------------------------------------
router.get(
  '/:id/versions/:versionId',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const id = Number(req.params.id);
    const versionId = Number(req.params.versionId);

    const version = db.prepare(
      'SELECT * FROM estimate_versions WHERE id = ? AND estimate_id = ?'
    ).get(versionId, id) as any;
    if (!version) throw new AppError('Version not found', 404);

    const data = JSON.parse(version.data);
    res.json({ success: true, data: { ...version, data } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/convert – Convert estimate to ticket
// ---------------------------------------------------------------------------
router.post(
  '/:id/convert',
  asyncHandler(async (req, res) => {
    const db = req.db;
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
    const db = req.db;
    const id = Number(req.params.id);
    const existing = db.prepare('SELECT id, status FROM estimates WHERE id = ?').get(id) as any;
    if (!existing) throw new AppError('Estimate not found', 404);
    if (existing.status === 'converted') throw new AppError('Cannot delete a converted estimate', 400);

    db.prepare('DELETE FROM estimate_line_items WHERE estimate_id = ?').run(id);
    db.prepare('DELETE FROM estimates WHERE id = ?').run(id);
    audit(db, 'estimate_deleted', req.user!.id, req.ip || 'unknown', { estimate_id: id });
    res.json({ success: true, data: { message: 'Estimate deleted' } });
  }),
);

// POST /:id/send — Send estimate to customer via SMS/email
router.post(
  '/:id/send',
  asyncHandler(async (req, res) => {
    const db = req.db;
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
      const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
      // ENR-LE8: Also set sent_at for auto-follow-up tracking
      db.prepare('UPDATE estimates SET approval_token = ?, status = ?, sent_at = COALESCE(sent_at, ?), updated_at = ? WHERE id = ?')
        .run(token, 'sent', now, now, id);
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
// SEC-H10: Rate limited to prevent brute-force token guessing
router.post(
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    if (!checkApprovalRateLimit(ip)) {
      throw new AppError('Too many approval attempts. Please try again later.', 429);
    }
    const db = req.db;
    const id = Number(req.params.id);
    const { token } = req.body;
    const estimate = db.prepare('SELECT id, approval_token, status FROM estimates WHERE id = ?').get(id) as any;
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'approved') throw new AppError('Already approved', 400);
    if (estimate.status === 'converted') throw new AppError('Already converted', 400);

    // Validate token if provided (for unauthenticated approval)
    if (token && estimate.approval_token !== token) throw new AppError('Invalid approval token', 403);
    if (!token && req.user?.role !== 'admin') throw new AppError('Approval token required', 400);

    const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
    db.prepare('UPDATE estimates SET status = ?, approved_at = ?, updated_at = ? WHERE id = ?')
      .run('approved', now, now, id);

    // SW-D7: Auto-change linked ticket status when estimate is approved
    const statusAfterEstimate = db.prepare("SELECT value FROM store_config WHERE key = 'ticket_status_after_estimate'").get() as any;
    if (statusAfterEstimate?.value) {
      const targetStatusId = parseInt(statusAfterEstimate.value);
      if (targetStatusId > 0) {
        // Find linked ticket: check converted_ticket_id on estimate, or estimate_id on tickets
        const est = db.prepare('SELECT converted_ticket_id FROM estimates WHERE id = ?').get(id) as any;
        const ticketId = est?.converted_ticket_id
          || (db.prepare('SELECT id FROM tickets WHERE estimate_id = ? AND is_deleted = 0').get(id) as any)?.id;
        if (ticketId) {
          const statusExists = db.prepare('SELECT id FROM ticket_statuses WHERE id = ?').get(targetStatusId);
          if (statusExists) {
            db.prepare('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ? AND is_deleted = 0')
              .run(targetStatusId, now, ticketId);
          }
        }
      }
    }

    res.json({ success: true, data: { approved: true } });
  }),
);

export default router;
