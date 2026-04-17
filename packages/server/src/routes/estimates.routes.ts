import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { generateOrderId } from '../utils/format.js';
import { audit } from '../utils/audit.js';
import { config } from '../config.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import {
  validatePrice,
  validateArrayBounds,
  validateJsonPayload,
  validateIntegerQuantity,
} from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import { escapeLike } from '../utils/query.js';

/**
 * S20-E1: Constant-time comparison for approval tokens. Previously we used
 * plain `===`, which short-circuits on the first mismatched byte and leaks
 * the prefix length of valid tokens. Use crypto.timingSafeEqual so any two
 * equal-length strings take the same amount of time to compare regardless
 * of where they differ.
 *
 * Returns false on any length mismatch (without calling timingSafeEqual,
 * which would throw) so the caller sees a single boolean result.
 */
function constantTimeEquals(a: string, b: string): boolean {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

const router = Router();
const logger = createLogger('estimates');

// SEC-H10: Rate limit constants for estimate approval (10 attempts per minute per IP)
const APPROVAL_RATE_LIMIT = 10;
const APPROVAL_RATE_WINDOW = 60_000; // 1 minute

// SC4: Approval token lifetime (24 hours from send)
const APPROVAL_TOKEN_TTL_MS = 24 * 60 * 60 * 1000;

// V12: Max line items per estimate (prevents 100k-item DoS payload)
const MAX_ESTIMATE_LINE_ITEMS = 500;

// Helpers to format timestamps for SQLite TEXT columns ("YYYY-MM-DD HH:MM:SS")
function sqlNow(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}
function sqlTimestamp(date: Date): string {
  return date.toISOString().replace('T', ' ').substring(0, 19);
}

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
      conditions.push("(e.order_id LIKE ? ESCAPE '\\' OR c.first_name LIKE ? ESCAPE '\\' OR c.last_name LIKE ? ESCAPE '\\')");
      const like = `%${escapeLike(keyword)}%`;
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
    const { customer_id, status, discount, notes, valid_until, line_items, reserve_parts } = req.body;

    if (!customer_id) throw new AppError('customer_id is required');

    const customer = await adb.get<{ id: number }>('SELECT id FROM customers WHERE id = ? AND is_deleted = 0', customer_id);
    if (!customer) throw new AppError('Customer not found', 404);

    // V11: discount has explicit bounds (validatePrice caps at 999999.99, rejects negatives/NaN/Infinity).
    const validatedDiscount = discount !== undefined && discount !== null
      ? validatePrice(discount, 'discount')
      : 0;

    // V12: line_items array must be bounded (reject 100k-item DoS payloads).
    const validatedLineItems = line_items !== undefined && line_items !== null
      ? validateArrayBounds<any>(line_items, 'line_items', MAX_ESTIMATE_LINE_ITEMS)
      : [];

    // Pre-compute subtotal so we can enforce discount <= subtotal before any writes.
    const normalizedItems = validatedLineItems.map((item) => {
      const qty = validateIntegerQuantity(item.quantity ?? 1, 'line_items.quantity');
      const price = validatePrice(item.unit_price ?? 0, 'line_items.unit_price');
      const tax = validatePrice(item.tax_amount ?? 0, 'line_items.tax_amount');
      return {
        inventory_item_id: item.inventory_item_id ?? null,
        description: item.description ?? '',
        quantity: qty,
        unit_price: price,
        tax_amount: tax,
        line_subtotal: qty * price,
        line_total: qty * price + tax,
      };
    });

    const subtotal = normalizedItems.reduce((s, i) => s + i.line_subtotal, 0);
    const totalTax = normalizedItems.reduce((s, i) => s + i.tax_amount, 0);

    // V11: discount cannot exceed subtotal — prevents negative totals via runaway discount.
    if (validatedDiscount > subtotal) {
      throw new AppError('discount cannot exceed subtotal', 400);
    }

    // SC7: Optional inventory reservation check (availability only, no decrement).
    // Caller must pass `reserve_parts: true` explicitly — we never auto-reserve.
    let reservationStatus:
      | {
          requested: true;
          all_available: boolean;
          items: Array<{
            inventory_item_id: number;
            name: string | null;
            requested: number;
            in_stock: number;
            available: boolean;
          }>;
        }
      | null = null;

    if (reserve_parts === true) {
      const partChecks: Array<{
        inventory_item_id: number;
        name: string | null;
        requested: number;
        in_stock: number;
        available: boolean;
      }> = [];

      // Aggregate requested quantity per inventory_item_id (same part may appear in multiple rows).
      const requested = new Map<number, number>();
      for (const item of normalizedItems) {
        if (item.inventory_item_id != null) {
          requested.set(
            item.inventory_item_id,
            (requested.get(item.inventory_item_id) ?? 0) + item.quantity,
          );
        }
      }

      for (const [invId, qty] of requested.entries()) {
        const row = await adb.get<{ id: number; name: string; in_stock: number; item_type: string }>(
          'SELECT id, name, in_stock, item_type FROM inventory_items WHERE id = ?',
          invId,
        );
        if (!row) {
          partChecks.push({
            inventory_item_id: invId,
            name: null,
            requested: qty,
            in_stock: 0,
            available: false,
          });
          continue;
        }
        // Services have no inventory — always "available".
        const available = row.item_type === 'service' || row.in_stock >= qty;
        partChecks.push({
          inventory_item_id: row.id,
          name: row.name,
          requested: qty,
          in_stock: row.in_stock,
          available,
        });
      }

      reservationStatus = {
        requested: true,
        all_available: partChecks.every((p) => p.available),
        items: partChecks,
      };
    }

    const result = await adb.run(`
      INSERT INTO estimates (order_id, customer_id, status, discount, notes, valid_until, created_by)
      VALUES ('TEMP', ?, ?, ?, ?, ?, ?)
    `,
      customer_id,
      status ?? 'draft',
      validatedDiscount,
      notes ?? null,
      valid_until ?? null,
      req.user!.id,
    );

    const estimateId = result.lastInsertRowid;
    const orderId = generateOrderId('EST', estimateId);
    await adb.run('UPDATE estimates SET order_id = ? WHERE id = ?', orderId, estimateId);

    for (const item of normalizedItems) {
      await adb.run(`
        INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
        estimateId,
        item.inventory_item_id,
        item.description,
        item.quantity,
        item.unit_price,
        item.tax_amount,
        item.line_total,
      );
    }

    const total = subtotal - validatedDiscount + totalTax;
    await adb.run('UPDATE estimates SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?',
      subtotal, totalTax, total, estimateId);

    const [estimate, items] = await Promise.all([
      adb.get<any>('SELECT * FROM estimates WHERE id = ?', estimateId),
      adb.all<any>('SELECT * FROM estimate_line_items WHERE estimate_id = ?', estimateId),
    ]);

    const payload: Record<string, unknown> = { ...(estimate as any), line_items: items };
    if (reservationStatus) {
      payload.reservation = reservationStatus;
    }

    res.status(201).json({
      success: true,
      data: payload,
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

    // SEC-M54: we reserved `estimateCount` slots against tenant_usage
    // up-front (atomic transaction above). If any estimate failed
    // mid-loop we'd over-charge the monthly ticket quota by failCount.
    // Refund the unused portion to tenant_usage here. Only runs when
    // the reservation actually committed.
    if (tierReservationCommitted && failCount > 0 && config.multiTenant && tierReservationTenantId) {
      try {
        const { getMasterDb } = await import('../db/master-connection.js');
        const masterDb = getMasterDb();
        if (masterDb) {
          const month = new Date().toISOString().slice(0, 7);
          masterDb.prepare(`
            UPDATE tenant_usage
               SET tickets_created = MAX(0, tickets_created - ?)
             WHERE tenant_id = ? AND month = ?
          `).run(failCount, tierReservationTenantId, month);
        }
      } catch (err) {
        // Refund is best-effort: if master DB is down we'd rather
        // over-charge the quota by failCount than throw a 500 at the
        // user who already has a mixed-result response ready. Logged
        // so ops can reconcile.
        console.error('[estimate.bulk-convert] SEC-M54 quota refund failed', err);
      }
    }

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

    // V11: validate discount bounds if supplied (non-negative, <= 999999.99).
    const validatedDiscount = discount !== undefined && discount !== null
      ? validatePrice(discount, 'discount')
      : undefined;

    // V12: bound line_items length if supplied.
    const validatedLineItems = line_items !== undefined && line_items !== null
      ? validateArrayBounds<any>(line_items, 'line_items', MAX_ESTIMATE_LINE_ITEMS)
      : undefined;

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
    // V13: circular-ref + size guarded JSON serialization (replaces raw JSON.stringify).
    const snapshotJson = validateJsonPayload(snapshot, 'snapshot', 262_144); // 256 KB cap
    await adb.run(`
      INSERT INTO estimate_versions (estimate_id, version_number, data)
      VALUES (?, ?, ?)
    `, id, nextVersion, snapshotJson);

    // ENR-LE8: Track sent_at when status transitions to 'sent'
    const effectiveStatus = status !== undefined ? status : existing.status;
    const shouldSetSentAt = effectiveStatus === 'sent' && existing.status !== 'sent' && !existing.sent_at;

    const effectiveDiscount = validatedDiscount !== undefined ? validatedDiscount : existing.discount;

    await adb.run(`
      UPDATE estimates SET
        customer_id = ?, status = ?, discount = ?, notes = ?, valid_until = ?,
        sent_at = CASE WHEN ? THEN datetime('now') ELSE sent_at END,
        updated_at = datetime('now')
      WHERE id = ?
    `,
      customer_id !== undefined ? customer_id : existing.customer_id,
      effectiveStatus,
      effectiveDiscount,
      notes !== undefined ? notes : existing.notes,
      valid_until !== undefined ? valid_until : existing.valid_until,
      shouldSetSentAt ? 1 : 0,
      id,
    );

    // Replace line items if provided
    if (validatedLineItems !== undefined) {
      const normalizedItems = validatedLineItems.map((item) => {
        const qty = validateIntegerQuantity(item.quantity ?? 1, 'line_items.quantity');
        const price = validatePrice(item.unit_price ?? 0, 'line_items.unit_price');
        const tax = validatePrice(item.tax_amount ?? 0, 'line_items.tax_amount');
        return {
          inventory_item_id: item.inventory_item_id ?? null,
          description: item.description ?? '',
          quantity: qty,
          unit_price: price,
          tax_amount: tax,
          line_subtotal: qty * price,
          line_total: qty * price + tax,
        };
      });

      const subtotal = normalizedItems.reduce((s, i) => s + i.line_subtotal, 0);
      const totalTax = normalizedItems.reduce((s, i) => s + i.tax_amount, 0);

      // V11: discount must not exceed subtotal.
      if (effectiveDiscount > subtotal) {
        throw new AppError('discount cannot exceed subtotal', 400);
      }

      await adb.run('DELETE FROM estimate_line_items WHERE estimate_id = ?', id);
      for (const item of normalizedItems) {
        await adb.run(`
          INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, total)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `, id, item.inventory_item_id, item.description, item.quantity, item.unit_price, item.tax_amount, item.line_total);
      }

      const total = subtotal - effectiveDiscount + totalTax;
      await adb.run('UPDATE estimates SET subtotal = ?, total_tax = ?, total = ? WHERE id = ?',
        subtotal, totalTax, total, id);
    } else if (validatedDiscount !== undefined) {
      // If only discount changed without replacing line items, sanity-check against current subtotal.
      const cur = await adb.get<{ subtotal: number; total_tax: number }>(
        'SELECT subtotal, total_tax FROM estimates WHERE id = ?', id,
      );
      if (cur && validatedDiscount > cur.subtotal) {
        throw new AppError('discount cannot exceed subtotal', 400);
      }
      if (cur) {
        const total = cur.subtotal - validatedDiscount + cur.total_tax;
        await adb.run('UPDATE estimates SET total = ? WHERE id = ?', total, id);
      }
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
// D7: Clean up foreign references before soft-delete so tickets never point at a
// ghost estimate. We null both sides of the link:
//   - tickets.estimate_id (tickets created from this estimate pre-conversion)
//   - estimates.converted_ticket_id (no-op for delete but documented here)
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    const existing = await adb.get<{ id: number; status: string }>('SELECT id, status FROM estimates WHERE id = ? AND is_deleted = 0', id);
    if (!existing) throw new AppError('Estimate not found', 404);
    if (existing.status === 'converted') throw new AppError('Cannot delete a converted estimate', 400);

    // Atomic: null ticket references + soft-delete the estimate together.
    await adb.transaction([
      {
        sql: 'UPDATE tickets SET estimate_id = NULL WHERE estimate_id = ?',
        params: [id],
      },
      {
        sql: "UPDATE estimates SET is_deleted = 1, updated_at = datetime('now') WHERE id = ?",
        params: [id],
      },
    ]);

    audit(req.db, 'estimate_deleted', req.user!.id, req.ip || 'unknown', { estimate_id: id });
    res.json({ success: true, data: { message: 'Estimate deleted' } });
  }),
);

// POST /:id/send — Send estimate to customer via SMS/email
// SC4: Always regenerate approval_token + expires_at on send so tokens have a
// bounded lifetime. SC6: surface SMS failures in the response + warn log.
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

    // SC4: Issue a fresh, time-limited token on each send. Clear any prior
    // used_at marker since this is a re-send and the new token is unused.
    const token = crypto.randomBytes(16).toString('hex');
    const now = sqlNow();
    const expiresAt = sqlTimestamp(new Date(Date.now() + APPROVAL_TOKEN_TTL_MS));

    // ENR-LE8: Also set sent_at for auto-follow-up tracking
    await adb.run(
      `UPDATE estimates SET
        approval_token = ?,
        approval_token_expires_at = ?,
        approval_token_used_at = NULL,
        status = ?,
        sent_at = COALESCE(sent_at, ?),
        updated_at = ?
       WHERE id = ?`,
      token, expiresAt, 'sent', now, now, id,
    );

    const { method = 'sms' } = req.body;
    const phone = estimate.phone || estimate.mobile;

    // SC6: Track delivery outcome so we can surface failures rather than
    // swallowing them silently.
    let smsAttempted = false;
    let smsSent = false;
    let smsError: string | null = null;

    if (method === 'sms' && phone) {
      smsAttempted = true;
      try {
        const { sendSms } = await import('../providers/sms/index.js');
        const msg = `Hi ${estimate.first_name}, your estimate ${estimate.order_id} for $${Number(estimate.total).toFixed(2)} is ready. Reply YES to approve or view details at your repair shop.`;
        await sendSms(phone, msg);
        smsSent = true;
      } catch (err: unknown) {
        smsError = err instanceof Error ? err.message : String(err);
        logger.warn('estimate_send_sms_failed', {
          estimate_id: id,
          order_id: estimate.order_id,
          phone_masked: phone ? `***${String(phone).slice(-4)}` : null,
          error: smsError,
        });
      }
    }

    const responseData: Record<string, unknown> = {
      sent: smsAttempted ? smsSent : true, // If no SMS requested, the token generation itself is the "send".
      method,
      approval_token: token,
      token_expires_at: expiresAt,
    };

    if (smsAttempted && !smsSent) {
      responseData.sent = false;
      responseData.warning = 'SMS delivery failed — token was issued but customer was not notified.';
      responseData.sms_error = smsError;
    } else if (method === 'sms' && !phone) {
      responseData.sent = false;
      responseData.warning = 'Customer has no phone number on file.';
    }

    res.json({ success: true, data: responseData });
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
    const estimate = await adb.get<any>(
      'SELECT id, approval_token, approval_token_expires_at, approval_token_used_at, status FROM estimates WHERE id = ? AND is_deleted = 0',
      id,
    );
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'approved') throw new AppError('Already approved', 400);
    if (estimate.status === 'converted') throw new AppError('Already converted', 400);

    // Validate token if provided (for unauthenticated approval)
    // S20-E1: Use constant-time comparison so mismatches don't leak timing info.
    if (token) {
      if (
        !estimate.approval_token ||
        typeof token !== 'string' ||
        !constantTimeEquals(estimate.approval_token, token)
      ) {
        throw new AppError('Invalid approval token', 403);
      }
      // SC4: single-use enforcement — reject if already consumed.
      if (estimate.approval_token_used_at) {
        throw new AppError('Approval token has already been used', 403);
      }
      // SC4: expiry enforcement. NULL expires_at = legacy token, treated as non-expiring
      // to avoid breaking estimates sent before this migration. New tokens always set it.
      if (estimate.approval_token_expires_at) {
        const exp = new Date(estimate.approval_token_expires_at.replace(' ', 'T') + 'Z').getTime();
        if (!isNaN(exp) && Date.now() > exp) {
          throw new AppError('Approval token has expired', 403);
        }
      }
    }
    if (!token && req.user?.role !== 'admin') throw new AppError('Approval token required', 400);

    const now = sqlNow();
    // SC4 / S20-E2: mark the token as consumed atomically. The WHERE clause
    // enforces status='sent' AND approval_token_used_at IS NULL so two parallel
    // valid approvals can no longer both succeed — only the first wins; the
    // second sees `changes === 0` and is rejected below. Admin bypass (no
    // token) still works because the token-id match is replaced with a
    // status-not-already-approved guard.
    let updateResult;
    if (token) {
      updateResult = await adb.run(
        `UPDATE estimates SET
          status = 'approved',
          approved_at = ?,
          approval_token_used_at = ?,
          updated_at = ?
         WHERE id = ?
           AND approval_token = ?
           AND approval_token_used_at IS NULL
           AND status NOT IN ('approved','converted')`,
        now, now, now, id, token,
      );
    } else {
      updateResult = await adb.run(
        `UPDATE estimates SET
          status = 'approved',
          approved_at = ?,
          updated_at = ?
         WHERE id = ?
           AND status NOT IN ('approved','converted')`,
        now, now, id,
      );
    }
    if (updateResult.changes === 0) {
      // Lost the race — another request already consumed the token / approved.
      throw new AppError('Estimate approval conflict. Refresh and try again.', 409);
    }

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
