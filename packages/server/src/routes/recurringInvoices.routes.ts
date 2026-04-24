/**
 * Recurring Invoices routes
 * Mounted at: /api/v1/recurring-invoices
 * Auth: authMiddleware applied at parent mount — NOT repeated here.
 *
 * Role gates:
 *   POST /        — requireAdmin (create template)
 *   POST /:id/cancel — requireAdmin (cancel template)
 *   PATCH /:id    — requireAdmin (structural edits)
 *   GET, pause, resume — any authenticated user
 */
import { Router, Request } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';

const router = Router();

// ---------------------------------------------------------------------------
// Rate limit constants
// ---------------------------------------------------------------------------
const RL_CREATE_MAX = 20;
const RL_CREATE_WINDOW_MS = 60_000; // 20 creates per minute per user

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAdmin(req: Request): void {
  if (!req.user) throw new AppError('Not authenticated', 401);
  if (req.user.role !== 'admin') throw new AppError('Admin role required', 403);
}

function validateId(raw: string, field = 'id'): number {
  const n = parseInt(raw, 10);
  if (!Number.isInteger(n) || n < 1) throw new AppError(`${field} must be a positive integer`, 400);
  return n;
}

function validateIntervalKind(v: unknown): string {
  const allowed = ['daily', 'weekly', 'monthly', 'yearly'] as const;
  if (typeof v !== 'string' || !allowed.includes(v as (typeof allowed)[number])) {
    throw new AppError(`interval_kind must be one of: ${allowed.join(', ')}`, 400);
  }
  return v;
}

function validateIntervalCount(v: unknown): number {
  const n = typeof v === 'number' ? v : parseInt(v as string, 10);
  if (!Number.isInteger(n) || n < 1) throw new AppError('interval_count must be a positive integer', 400);
  if (n > 365) throw new AppError('interval_count exceeds maximum (365)', 400);
  return n;
}

function validateIsoDate(v: unknown, field: string): string {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) {
    throw new AppError(`${field} must be a date in YYYY-MM-DD format`, 400);
  }
  const d = new Date(v);
  if (isNaN(d.getTime())) throw new AppError(`${field} is not a valid date`, 400);
  return v;
}

function validateLineItems(items: unknown): object[] {
  if (!Array.isArray(items) || items.length === 0) {
    throw new AppError('line_items must be a non-empty array', 400);
  }
  if (items.length > 200) throw new AppError('line_items exceeds maximum of 200', 400);
  return items.map((item, i) => {
    if (!item || typeof item !== 'object') throw new AppError(`line_items[${i}] is invalid`, 400);
    const it = item as Record<string, unknown>;
    const description = it.description ?? '';
    if (typeof description === 'string' && description.length > 500) {
      throw new AppError(`line_items[${i}].description exceeds 500 characters`, 400);
    }
    const qty = typeof it.quantity === 'number' ? it.quantity : parseInt(String(it.quantity ?? 1), 10);
    if (!Number.isInteger(qty) || qty < 1) throw new AppError(`line_items[${i}].quantity must be >= 1`, 400);
    const unitPriceCents = typeof it.unit_price_cents === 'number' ? it.unit_price_cents : parseInt(String(it.unit_price_cents ?? 0), 10);
    if (!Number.isInteger(unitPriceCents) || unitPriceCents < 0) {
      throw new AppError(`line_items[${i}].unit_price_cents must be a non-negative integer`, 400);
    }
    return {
      description: String(description),
      quantity: qty,
      unit_price_cents: unitPriceCents,
      tax_class_id: it.tax_class_id != null ? parseInt(String(it.tax_class_id), 10) : null,
    };
  });
}

/**
 * Advance a date-string by (intervalKind × intervalCount).
 * Returns an ISO datetime string.
 */
function advanceNextRunAt(current: string, kind: string, count: number): string {
  const d = new Date(current);
  // SCAN-1114: mirror the clamp applied in services/recurringInvoicesCron.ts.
  // `setUTCMonth(m + count)` rolls Jan-31 → Mar-03 (overflowing Feb); same
  // issue for yearly Feb-29 under non-leap years. Clamp to the last valid
  // day of the target month when the original day was dropped.
  const originalDay = d.getUTCDate();
  switch (kind) {
    case 'daily':   d.setUTCDate(d.getUTCDate() + count); break;
    case 'weekly':  d.setUTCDate(d.getUTCDate() + 7 * count); break;
    case 'monthly':
      d.setUTCMonth(d.getUTCMonth() + count);
      if (d.getUTCDate() !== originalDay) d.setUTCDate(0);
      break;
    case 'yearly':
      d.setUTCFullYear(d.getUTCFullYear() + count);
      if (d.getUTCDate() !== originalDay) d.setUTCDate(0);
      break;
  }
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

function nowIso(): string {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

// ---------------------------------------------------------------------------
// GET /
// ---------------------------------------------------------------------------
router.get('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { page = '1', pagesize = '20', status } = req.query as Record<string, string>;
  const p  = Math.max(1, parseInt(page, 10));
  const ps = Math.min(100, Math.max(1, parseInt(pagesize, 10)));
  const offset = (p - 1) * ps;

  let where = 'WHERE 1=1';
  const params: unknown[] = [];

  if (status) {
    const allowed = ['active', 'paused', 'canceled'];
    if (!allowed.includes(status)) throw new AppError(`status must be one of: ${allowed.join(', ')}`, 400);
    where += ' AND t.status = ?';
    params.push(status);
  }

  const [totalRow, templates] = await Promise.all([
    adb.get<{ c: number }>(`
      SELECT COUNT(*) AS c
      FROM invoice_templates t
      ${where}
    `, ...params),
    adb.all<Record<string, unknown>>(`
      SELECT t.*,
        c.first_name || ' ' || c.last_name AS customer_name,
        u.first_name || ' ' || u.last_name AS created_by_name
      FROM invoice_templates t
      LEFT JOIN customers c ON c.id = t.customer_id
      LEFT JOIN users u ON u.id = t.created_by_user_id
      ${where}
      ORDER BY t.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, ps, offset),
  ]);

  res.json({
    success: true,
    data: {
      templates,
      pagination: {
        page: p,
        per_page: ps,
        total: totalRow?.c ?? 0,
        total_pages: Math.ceil((totalRow?.c ?? 0) / ps),
      },
    },
  });
}));

// ---------------------------------------------------------------------------
// GET /:id
// ---------------------------------------------------------------------------
router.get('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = validateId(String(req.params.id));

  const [template, runs] = await Promise.all([
    adb.get<Record<string, unknown>>(`
      SELECT t.*,
        c.first_name || ' ' || c.last_name AS customer_name,
        u.first_name || ' ' || u.last_name AS created_by_name
      FROM invoice_templates t
      LEFT JOIN customers c ON c.id = t.customer_id
      LEFT JOIN users u ON u.id = t.created_by_user_id
      WHERE t.id = ?
    `, id),
    adb.all<Record<string, unknown>>(`
      SELECT r.*, inv.order_id AS invoice_order_id
      FROM invoice_template_runs r
      LEFT JOIN invoices inv ON inv.id = r.invoice_id
      WHERE r.template_id = ?
      ORDER BY r.run_at DESC
      LIMIT 20
    `, id),
  ]);

  if (!template) throw new AppError('Template not found', 404);

  res.json({ success: true, data: { ...template, recent_runs: runs } });
}));

// ---------------------------------------------------------------------------
// POST /  — create template
// ---------------------------------------------------------------------------
router.post('/', asyncHandler(async (req, res) => {
  requireAdmin(req);

  // Rate limit create by user id
  const rlKey = String(req.user!.id);
  const rl = consumeWindowRate(req.db, 'recurring_invoice_create', rlKey, RL_CREATE_MAX, RL_CREATE_WINDOW_MS);
  if (!rl.allowed) {
    res.setHeader('Retry-After', String(rl.retryAfterSeconds));
    throw new AppError('Too many template creates — please slow down', 429);
  }

  const adb = req.asyncDb;
  const {
    name,
    customer_id,
    interval_kind,
    interval_count,
    start_date,
    line_items,
    notes_template,
    tax_class_id,
  } = req.body as Record<string, unknown>;

  // Validate
  if (typeof name !== 'string' || name.trim().length === 0) throw new AppError('name is required', 400);
  if (name.length > 200) throw new AppError('name exceeds 200 characters', 400);
  const safeCustomerId = typeof customer_id === 'number' ? customer_id : parseInt(String(customer_id), 10);
  if (!Number.isInteger(safeCustomerId) || safeCustomerId < 1) throw new AppError('customer_id must be a positive integer', 400);
  const safeKind = validateIntervalKind(interval_kind);
  const safeCount = validateIntervalCount(interval_count);
  const safeStartDate = validateIsoDate(start_date, 'start_date');
  const safeLineItems = validateLineItems(line_items);
  if (notes_template != null && typeof notes_template === 'string' && notes_template.length > 2000) {
    throw new AppError('notes_template exceeds 2000 characters', 400);
  }
  if (tax_class_id != null) {
    const tcId = parseInt(String(tax_class_id), 10);
    if (!Number.isInteger(tcId) || tcId < 1) throw new AppError('tax_class_id must be a positive integer', 400);
  }

  // Verify customer exists
  const cust = await adb.get<{ id: number }>('SELECT id FROM customers WHERE id = ?', safeCustomerId);
  if (!cust) throw new AppError('Customer not found', 404);

  // First next_run_at = start_date (beginning of day UTC)
  const nextRunAt = `${safeStartDate} 00:00:00`;

  const result = await adb.run(`
    INSERT INTO invoice_templates
      (name, customer_id, interval_kind, interval_count, start_date,
       next_run_at, status, line_items_json, notes_template, tax_class_id,
       created_by_user_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, datetime('now'), datetime('now'))
  `,
    name.trim(),
    safeCustomerId,
    safeKind,
    safeCount,
    safeStartDate,
    nextRunAt,
    JSON.stringify(safeLineItems),
    (typeof notes_template === 'string' ? notes_template : null),
    (tax_class_id != null ? parseInt(String(tax_class_id), 10) : null),
    req.user!.id,
  );

  const newId = result.lastInsertRowid as number;

  audit(req.db, 'invoice_template.created', req.user!.id, req.ip ?? '', {
    template_id: newId,
    name: name.trim(),
    customer_id: safeCustomerId,
    interval_kind: safeKind,
    interval_count: safeCount,
  });

  const template = await adb.get<Record<string, unknown>>('SELECT * FROM invoice_templates WHERE id = ?', newId);
  res.status(201).json({ success: true, data: template });
}));

// ---------------------------------------------------------------------------
// PATCH /:id — partial update (status, next_run_at, notes_template, line_items)
// ---------------------------------------------------------------------------
router.patch('/:id', asyncHandler(async (req, res) => {
  requireAdmin(req);

  const rlKey = String(req.user!.id);
  const rl = consumeWindowRate(req.db, 'recurring_invoice_update', rlKey, RL_CREATE_MAX, RL_CREATE_WINDOW_MS);
  if (!rl.allowed) {
    res.setHeader('Retry-After', String(rl.retryAfterSeconds));
    throw new AppError('Too many template updates — please slow down', 429);
  }

  const adb = req.asyncDb;
  const id = validateId(String(req.params.id));

  const existing = await adb.get<Record<string, unknown>>('SELECT * FROM invoice_templates WHERE id = ?', id);
  if (!existing) throw new AppError('Template not found', 404);
  if (existing.status === 'canceled') throw new AppError('Cannot modify a canceled template', 400);

  const { status, next_run_at, notes_template, line_items } = req.body as Record<string, unknown>;

  const updates: string[] = [];
  const vals: unknown[] = [];

  if (status !== undefined) {
    const allowed = ['active', 'paused', 'canceled'];
    if (!allowed.includes(status as string)) throw new AppError(`status must be one of: ${allowed.join(', ')}`, 400);
    updates.push('status = ?');
    vals.push(status);
  }

  if (next_run_at !== undefined) {
    if (typeof next_run_at !== 'string') throw new AppError('next_run_at must be a string', 400);
    if (Number.isNaN(Date.parse(next_run_at))) throw new AppError('next_run_at must be a valid ISO date', 400);
    updates.push('next_run_at = ?');
    vals.push(next_run_at);
  }

  if (notes_template !== undefined) {
    if (notes_template !== null && typeof notes_template === 'string' && notes_template.length > 2000) {
      throw new AppError('notes_template exceeds 2000 characters', 400);
    }
    updates.push('notes_template = ?');
    vals.push(notes_template);
  }

  if (line_items !== undefined) {
    const safeItems = validateLineItems(line_items);
    updates.push('line_items_json = ?');
    vals.push(JSON.stringify(safeItems));
  }

  if (updates.length === 0) throw new AppError('No updatable fields provided', 400);

  updates.push("updated_at = datetime('now')");
  vals.push(id);

  await adb.run(
    `UPDATE invoice_templates SET ${updates.join(', ')} WHERE id = ?`,
    ...vals,
  );

  audit(req.db, 'invoice_template.updated', req.user!.id, req.ip ?? '', {
    template_id: id,
    fields_changed: updates.filter(u => !u.startsWith('updated_at')).map(u => u.split(' ')[0]),
  });

  const updated = await adb.get<Record<string, unknown>>('SELECT * FROM invoice_templates WHERE id = ?', id);
  res.json({ success: true, data: updated });
}));

// ---------------------------------------------------------------------------
// POST /:id/pause
// ---------------------------------------------------------------------------
router.post('/:id/pause', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = validateId(String(req.params.id));

  const existing = await adb.get<{ id: number; status: string }>('SELECT id, status FROM invoice_templates WHERE id = ?', id);
  if (!existing) throw new AppError('Template not found', 404);
  if (existing.status === 'canceled') throw new AppError('Cannot pause a canceled template', 400);
  if (existing.status === 'paused') throw new AppError('Template is already paused', 400);

  await adb.run("UPDATE invoice_templates SET status = 'paused', updated_at = datetime('now') WHERE id = ?", id);

  audit(req.db, 'invoice_template.paused', req.user!.id, req.ip ?? '', { template_id: id });

  res.json({ success: true, data: { id, status: 'paused' } });
}));

// ---------------------------------------------------------------------------
// POST /:id/resume
// ---------------------------------------------------------------------------
router.post('/:id/resume', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = validateId(String(req.params.id));

  const existing = await adb.get<{ id: number; status: string; next_run_at: string }>('SELECT id, status, next_run_at FROM invoice_templates WHERE id = ?', id);
  if (!existing) throw new AppError('Template not found', 404);
  if (existing.status === 'canceled') throw new AppError('Cannot resume a canceled template', 400);
  if (existing.status === 'active') throw new AppError('Template is already active', 400);

  // Recompute next_run_at = max(now, existing next_run_at)
  const now = nowIso();
  const nextRun = existing.next_run_at < now ? now : existing.next_run_at;

  await adb.run(
    "UPDATE invoice_templates SET status = 'active', next_run_at = ?, updated_at = datetime('now') WHERE id = ?",
    nextRun,
    id,
  );

  audit(req.db, 'invoice_template.resumed', req.user!.id, req.ip ?? '', { template_id: id, next_run_at: nextRun });

  res.json({ success: true, data: { id, status: 'active', next_run_at: nextRun } });
}));

// ---------------------------------------------------------------------------
// POST /:id/cancel  — soft cancel (history preserved)
// ---------------------------------------------------------------------------
router.post('/:id/cancel', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = validateId(String(req.params.id));

  const existing = await adb.get<{ id: number; status: string }>('SELECT id, status FROM invoice_templates WHERE id = ?', id);
  if (!existing) throw new AppError('Template not found', 404);
  if (existing.status === 'canceled') throw new AppError('Template is already canceled', 400);

  await adb.run("UPDATE invoice_templates SET status = 'canceled', updated_at = datetime('now') WHERE id = ?", id);

  audit(req.db, 'invoice_template.canceled', req.user!.id, req.ip ?? '', { template_id: id });

  res.json({ success: true, data: { id, status: 'canceled' } });
}));

export default router;
