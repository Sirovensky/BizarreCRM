import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { config } from '../config.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';

const router = Router();

// SEC-H10: Rate limit constants for estimate approval (10 attempts per minute per IP)
const APPROVAL_RATE_LIMIT = 10;
const APPROVAL_RATE_WINDOW = 60_000; // 1 minute

// ---------------------------------------------------------------------------
// GET / – List estimates (paginated, filterable)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(250, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));
    const status = (req.query.status as string || '').trim();
    const keyword = (req.query.keyword as string || '').trim();

    const conditions: string[] = ['e.is_deleted = 0'];
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

    const whereClause = `WHERE ${conditions.join(' AND ')}`;

    const { total } = await adb.get<{ total: number }>(`
      SELECT COUNT(*) as total FROM estimates e
      LEFT JOIN customers c ON c.id = e.customer_id
      ${whereClause}
    `, ...params) as { total: number };

    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const estimates = await adb.all<any>(`
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
    `, ...params, pageSize, offset);

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
    const adb = req.asyncDb;
    const { customer_id, status, discount, notes, valid_until, line_items } = req.body;

    if (!customer_id) throw new AppError('customer_id is required');

    const customer = await adb.get<{ id: number }>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customer_id);
    if (!customer) throw new AppError('Customer not found', 404);

    const result = await adb.run(`
      INSERT INTO estimates (order_id, customer_id, status, discount, notes, valid_until, created_by)
      VALUES ('TEMP', ?, ?, ?, ?, ?, ?)
    `,
      customer_id,
      status ?? 'draft',
      discount ?? 0,
      notes ?? null,
      valid_until ?? null,
      req.user!.id,
    );

    const estimateId = result.lastInsertRowid;
    const orderId = generateOrderId('EST', estimateId);
    await adb.run('UPDATE estimates SET order_id = ? WHERE id = ?', orderId, estimateId);

    let subtotal = 0;
    let totalTax = 0;

    if (line_items?.length) {
      for (const item of line_items) {
        const qty = item.quantity ?? 1;
        const price = item.unit_price ?? 0;
        const tax = item.tax_amount ?? 0;
        const lineTotal = qty * price + tax;
        subtotal += qty * price;
        totalTax += tax;

        await adb.run(`
          INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `,
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
    await adb.run('UPDATE estimates SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?',
      subtotal, totalTax, total, estimateId);

    const [estimate, items] = await Promise.all([
      adb.get<any>('SELECT * FROM estimates WHERE id = ?', estimateId),
      adb.all<any>('SELECT * FROM estimate_line_items WHERE estimate_id = ?', estimateId),
    ]);

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

    const adb = req.asyncDb;
    const { estimate_ids } = req.body;
    if (!Array.isArray(estimate_ids) || estimate_ids.length === 0) {
      throw new AppError('estimate_ids array is required', 400);
    }
    if (estimate_ids.length > 50) {
      throw new AppError('Maximum 50 estimates per batch', 400);
    }

    // Tier: atomic monthly ticket limit check for the entire batch (reserve N at once)
    // Free plans cap maxTicketsMonth; Pro plans set it to null (unlimited).
    let tierReservationCommitted = false;
    const tierReservationTenantId = req.tenantId;
    if (config.multiTenant && tierReservationTenantId && req.tenantLimits?.maxTicketsMonth != null) {
      const { getMasterDb } = await import('../db/master-connection.js');
      const masterDb = getMasterDb();
      if (masterDb) {
        const month = new Date().toISOString().slice(0, 7); // YYYY-MM
        const limit = req.tenantLimits.maxTicketsMonth;
        const estimateCount = estimate_ids.length;

        const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
          const usage = masterDb.prepare(
            'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
          ).get(tierReservationTenantId, month) as { tickets_created: number } | undefined;
          const current = usage?.tickets_created ?? 0;
          if (current + estimateCount > limit) {
            return { allowed: false, current };
          }
          masterDb.prepare(`
            INSERT INTO tenant_usage (tenant_id, month, tickets_created)
            VALUES (?, ?, ?)
            ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + ?
          `).run(tierReservationTenantId, month, estimateCount, estimateCount);
          return { allowed: true, current: current + estimateCount };
        })();

        if (!reservation.allowed) {
          res.status(403).json({
            success: false,
            upgrade_required: true,
            feature: 'ticket_limit',
            message: `Monthly ticket limit would be exceeded by this batch (${reservation.current} used + ${estimateCount} requested > ${limit}). Upgrade to Pro for unlimited tickets.`,
            current: reservation.current,
            limit,
            requested: estimateCount,
          });
          return;
        }
        tierReservationCommitted = true;
      }
    }
    void tierReservationCommitted;

    const results: Array<{ estimate_id: number; ticket_id?: number; error?: string }> = [];

    for (const estId of estimate_ids) {
      try {
        const estimate = await adb.get<any>('SELECT * FROM estimates WHERE id = ?', estId);
        if (!estimate) {
          results.push({ estimate_id: estId, error: 'Estimate not found' });
          continue;
        }
        if (estimate.status === 'converted') {
          results.push({ estimate_id: estId, error: 'Already converted' });
          continue;
        }

        // Get default (open) status
        const defaultStatus = await adb.get<any>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
        const statusId = defaultStatus?.id ?? 1;

        // Create ticket
        const ticketResult = await adb.run(`
          INSERT INTO tickets (order_id, customer_id, status_id, estimate_id, subtotal, discount, total_tax, total,
            source, created_by)
          VALUES ('TEMP', ?, ?, ?, ?, ?, ?, ?, 'estimate', ?)
        `,
          estimate.customer_id, statusId, estId,
          estimate.subtotal, estimate.discount, estimate.total_tax, estimate.total,
          req.user!.id,
        );

        const ticketId = ticketResult.lastInsertRowid;
        const ticketOrderId = generateOrderId('T', ticketId);
        await adb.run('UPDATE tickets SET order_id = ? WHERE id = ?', ticketOrderId, ticketId);

        // Copy line items as ticket devices
        const lineItems = await adb.all<any>('SELECT * FROM estimate_line_items WHERE estimate_id = ?', estId);
        for (const item of lineItems) {
          await adb.run(`
            INSERT INTO ticket_devices (ticket_id, device_name, service_id, price, tax_amount, total, additional_notes)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          `,
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
        await adb.run("UPDATE estimates SET status = 'converted', converted_ticket_id = ?, updated_at = datetime('now') WHERE id = ?",
          ticketId, estId);

        results.push({ estimate_id: estId, ticket_id: ticketId });
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : 'Unknown error';
        results.push({ estimate_id: estId, error: msg });
      }
    }

    const successCount = results.filter(r => !r.error).length;
    const failCount = results.filter(r => r.error).length;

    audit(req.db, 'estimate_bulk_convert', req.user!.id, req.ip || 'unknown', {
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
    const adb = req.asyncDb;
    const id = Number(req.params.id);

    const estimate = await adb.get<any>(`
      SELECT e.*,
        c.first_name AS customer_first_name, c.last_name AS customer_last_name,
        c.email AS customer_email, c.phone AS customer_phone, c.mobile AS customer_mobile,
        c.address1, c.city, c.state, c.postcode,
        u.first_name AS created_by_first_name, u.last_name AS created_by_last_name
      FROM estimates e
      LEFT JOIN customers c ON c.id = e.customer_id
      LEFT JOIN users u ON u.id = e.created_by
      WHERE e.id = ? AND e.is_deleted = 0
    `, id);

    if (!estimate) throw new AppError('Estimate not found', 404);

    const lineItems = await adb.all<any>(`
      SELECT eli.*, ii.name AS item_name, ii.sku AS item_sku
      FROM estimate_line_items eli
      LEFT JOIN inventory_items ii ON ii.id = eli.inventory_item_id
      WHERE eli.estimate_id = ?
      ORDER BY eli.id
    `, id);

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
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<any>('SELECT * FROM estimates WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Estimate not found', 404);

    const { customer_id, status, discount, notes, valid_until, line_items } = req.body;

    // ENR-LE6: Snapshot current state before updating
    const currentLineItems = await adb.all<any>('SELECT * FROM estimate_line_items WHERE estimate_id = ?', id);
    const lastVersion = await adb.get<any>(
      'SELECT MAX(version_number) AS max_ver FROM estimate_versions WHERE estimate_id = ?', id,
    );
    const nextVersion = (lastVersion?.max_ver ?? 0) + 1;

    const snapshot = {
      ...existing,
      line_items: currentLineItems,
    };
    await adb.run(`
      INSERT INTO estimate_versions (estimate_id, version_number, data)
      VALUES (?, ?, ?)
    `, id, nextVersion, JSON.stringify(snapshot));

    // ENR-LE8: Track sent_at when status transitions to 'sent'
    const effectiveStatus = status !== undefined ? status : existing.status;
    const shouldSetSentAt = effectiveStatus === 'sent' && existing.status !== 'sent' && !existing.sent_at;

    await adb.run(`
      UPDATE estimates SET
        customer_id = ?, status = ?, discount = ?, notes = ?, valid_until = ?,
        sent_at = CASE WHEN ? THEN datetime('now') ELSE sent_at END,
        updated_at = datetime('now')
      WHERE id = ?
    `,
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
      await adb.run('DELETE FROM estimate_line_items WHERE estimate_id = ?', id);

      let subtotal = 0;
      let totalTax = 0;

      if (line_items?.length) {
        for (const item of line_items) {
          const qty = item.quantity ?? 1;
          const price = item.unit_price ?? 0;
          const tax = item.tax_amount ?? 0;
          const lineTotal = qty * price + tax;
          subtotal += qty * price;
          totalTax += tax;

          await adb.run(`
            INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          `, id, item.inventory_item_id ?? null, item.description ?? '', qty, price, tax, lineTotal);
        }
      }

      const disc = discount !== undefined ? discount : existing.discount;
      const total = subtotal - disc + totalTax;
      await adb.run('UPDATE estimates SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?',
        subtotal, totalTax, total, id);
    }

    const [estimate, items] = await Promise.all([
      adb.get<any>('SELECT * FROM estimates WHERE id = ?', id),
      adb.all<any>('SELECT * FROM estimate_line_items WHERE estimate_id = ?', id),
    ]);

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
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<{ id: number }>('SELECT id FROM estimates WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Estimate not found', 404);

    const versions = await adb.all<any>(
      'SELECT id, estimate_id, version_number, created_at FROM estimate_versions WHERE estimate_id = ? ORDER BY version_number DESC',
      id,
    );

    res.json({ success: true, data: versions });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id/versions/:versionId – Get a specific estimate version snapshot (ENR-LE6)
// ---------------------------------------------------------------------------
router.get(
  '/:id/versions/:versionId',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const versionId = Number(req.params.versionId);

    const version = await adb.get<any>(
      'SELECT * FROM estimate_versions WHERE id = ? AND estimate_id = ?',
      versionId, id,
    );
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
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const estimate = await adb.get<any>('SELECT * FROM estimates WHERE id = ? AND is_deleted = 0', id);
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'converted') throw new AppError('Estimate already converted', 400);

    // Tier: atomic monthly ticket limit check (check + pre-increment in one transaction)
    // Free plans cap maxTicketsMonth; Pro plans set it to null (unlimited).
    let tierReservationCommitted = false;
    const tierReservationTenantId = req.tenantId;
    if (config.multiTenant && tierReservationTenantId && req.tenantLimits?.maxTicketsMonth != null) {
      const { getMasterDb } = await import('../db/master-connection.js');
      const masterDb = getMasterDb();
      if (masterDb) {
        const month = new Date().toISOString().slice(0, 7); // YYYY-MM
        const limit = req.tenantLimits.maxTicketsMonth;

        const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
          const usage = masterDb.prepare(
            'SELECT tickets_created FROM tenant_usage WHERE tenant_id = ? AND month = ?'
          ).get(tierReservationTenantId, month) as { tickets_created: number } | undefined;
          const current = usage?.tickets_created ?? 0;
          if (current >= limit) {
            return { allowed: false, current };
          }
          masterDb.prepare(`
            INSERT INTO tenant_usage (tenant_id, month, tickets_created)
            VALUES (?, ?, 1)
            ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
          `).run(tierReservationTenantId, month);
          return { allowed: true, current: current + 1 };
        })();

        if (!reservation.allowed) {
          res.status(403).json({
            success: false,
            upgrade_required: true,
            feature: 'ticket_limit',
            message: `Monthly ticket limit reached (${reservation.current}/${limit}). Upgrade to Pro for unlimited tickets.`,
            current: reservation.current,
            limit,
          });
          return;
        }
        tierReservationCommitted = true;
      }
    }
    void tierReservationCommitted;

    // Get default (open) status
    const defaultStatus = await adb.get<any>('SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1');
    const statusId = defaultStatus?.id ?? 1;

    // Create ticket
    const ticketResult = await adb.run(`
      INSERT INTO tickets (order_id, customer_id, status_id, estimate_id, subtotal, discount, total_tax, total,
        source, created_by)
      VALUES ('TEMP', ?, ?, ?, ?, ?, ?, ?, 'estimate', ?)
    `,
      estimate.customer_id, statusId, id,
      estimate.subtotal, estimate.discount, estimate.total_tax, estimate.total,
      req.user!.id,
    );

    const ticketId = ticketResult.lastInsertRowid;
    const ticketOrderId = generateOrderId('T', ticketId);
    await adb.run('UPDATE tickets SET order_id = ? WHERE id = ?', ticketOrderId, ticketId);

    // Copy line items as ticket devices
    const lineItems = await adb.all<any>('SELECT * FROM estimate_line_items WHERE estimate_id = ?', id);
    for (const item of lineItems) {
      await adb.run(`
        INSERT INTO ticket_devices (ticket_id, device_name, service_id, price, tax_amount, total, additional_notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
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
    await adb.run("UPDATE estimates SET status = 'converted', converted_ticket_id = ?, updated_at = datetime('now') WHERE id = ?",
      ticketId, id);

    const ticket = await adb.get<any>('SELECT * FROM tickets WHERE id = ?', ticketId);

    res.status(201).json({
      success: true,
      data: { ticket, message: 'Estimate converted to ticket' },
    });
  }),
);

// DELETE /:id — Soft delete estimate
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<{ id: number; status: string }>('SELECT id, status FROM estimates WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Estimate not found', 404);
    if (existing.status === 'converted') throw new AppError('Cannot delete a converted estimate', 400);

    await adb.run("UPDATE estimates SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?", id);
    audit(req.db, 'estimate_deleted', req.user!.id, req.ip || 'unknown', { estimate_id: id });
    res.json({ success: true, data: { message: 'Estimate deleted' } });
  }),
);

// POST /:id/send — Send estimate to customer via SMS/email
router.post(
  '/:id/send',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const estimate = await adb.get<any>(`
      SELECT e.*, c.first_name, c.last_name, c.phone, c.mobile, c.email
      FROM estimates e LEFT JOIN customers c ON c.id = e.customer_id WHERE e.id = ? AND e.is_deleted = 0
    `, id);
    if (!estimate) throw new AppError('Estimate not found', 404);

    // Generate approval token if not exists
    let token = estimate.approval_token;
    if (!token) {
      const crypto = await import('crypto');
      token = crypto.randomBytes(16).toString('hex');
      const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
      // ENR-LE8: Also set sent_at for auto-follow-up tracking
      await adb.run('UPDATE estimates SET approval_token = ?, status = ?, sent_at = COALESCE(sent_at, ?), updated_at = ? WHERE id = ?',
        token, 'sent', now, now, id);
    }

    const { method = 'sms' } = req.body;
    const phone = estimate.phone || estimate.mobile;

    if (method === 'sms' && phone) {
      try {
        const { sendSms } = await import('../providers/sms/index.js');
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
    const db = req.db;
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    if (!checkWindowRate(db, 'estimate_approval', ip, APPROVAL_RATE_LIMIT, APPROVAL_RATE_WINDOW)) {
      throw new AppError('Too many approval attempts. Please try again later.', 429);
    }
    recordWindowFailure(db, 'estimate_approval', ip, APPROVAL_RATE_WINDOW);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const { token } = req.body;
    const estimate = await adb.get<any>('SELECT id, approval_token, status FROM estimates WHERE id = ? AND is_deleted = 0', id);
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'approved') throw new AppError('Already approved', 400);
    if (estimate.status === 'converted') throw new AppError('Already converted', 400);

    // Validate token if provided (for unauthenticated approval)
    if (token && estimate.approval_token !== token) throw new AppError('Invalid approval token', 403);
    if (!token && req.user?.role !== 'admin') throw new AppError('Approval token required', 400);

    const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
    await adb.run('UPDATE estimates SET status = ?, approved_at = ?, updated_at = ? WHERE id = ?',
      'approved', now, now, id);

    // SW-D7: Auto-change linked ticket status when estimate is approved
    const statusAfterEstimate = await adb.get<any>("SELECT value FROM store_config WHERE key = 'ticket_status_after_estimate'");
    if (statusAfterEstimate?.value) {
      const targetStatusId = parseInt(statusAfterEstimate.value);
      if (targetStatusId > 0) {
        // Find linked ticket: check converted_ticket_id on estimate, or estimate_id on tickets
        const est = await adb.get<any>('SELECT converted_ticket_id FROM estimates WHERE id = ?', id);
        const ticketId = est?.converted_ticket_id
          || (await adb.get<any>('SELECT id FROM tickets WHERE estimate_id = ? AND is_deleted = 0', id))?.id;
        if (ticketId) {
          const statusExists = await adb.get<any>('SELECT id FROM ticket_statuses WHERE id = ?', targetStatusId);
          if (statusExists) {
            await adb.run('UPDATE tickets SET status_id = ?, updated_at = ? WHERE id = ? AND is_deleted = 0',
              targetStatusId, now, ticketId);
          }
        }
      }
    }

    res.json({ success: true, data: { approved: true } });
  }),
);

export default router;
