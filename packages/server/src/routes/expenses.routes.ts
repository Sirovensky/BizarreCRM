import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';

const router = Router();
type AnyRow = Record<string, any>;
const CALCULATED_COGS_CATEGORY = 'Parts COGS (calculated)';

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function sortExpenseRows(a: AnyRow, b: AnyRow): number {
  const dateA = String(a.date || a.created_at || '');
  const dateB = String(b.date || b.created_at || '');
  const dateCmp = dateB.localeCompare(dateA);
  if (dateCmp !== 0) return dateCmp;
  return Number(b.id || 0) - Number(a.id || 0);
}

function shouldIncludeCalculatedCogs(category: string, statusFilter: string, subtypeFilter: string, includeRaw: string): boolean {
  if (includeRaw === 'false' || includeRaw === '0') return false;
  if (category && category !== CALCULATED_COGS_CATEGORY) return false;
  if (statusFilter && statusFilter !== 'approved') return false;
  if (subtypeFilter && subtypeFilter !== 'general') return false;
  return true;
}

function buildCalculatedDateFilters(dateExpr: string, fromDate: string, toDate: string, params: any[]): string[] {
  const conditions: string[] = [];
  if (fromDate) {
    conditions.push(`${dateExpr} >= ?`);
    params.push(fromDate);
  }
  if (toDate) {
    conditions.push(`${dateExpr} <= ?`);
    params.push(toDate);
  }
  return conditions;
}

async function getCalculatedCogsExpenses(
  adb: AsyncDb,
  filters: { fromDate: string; toDate: string; keyword: string },
): Promise<AnyRow[]> {
  const keywordLike = filters.keyword ? `%${escapeLike(filters.keyword)}%` : '';

  const partDateExpr = 'DATE(COALESCE(tdp.created_at, td.created_at, t.created_at))';
  const partParams: any[] = [];
  const partConditions = [
    't.is_deleted = 0',
    "COALESCE(tdp.status, 'available') != 'cancelled'",
    "COALESCE(NULLIF(ii.cost_price, 0), NULLIF(sc_direct.price, 0), sku_cost.min_price, part_name_cost.min_price, 0) > 0",
    ...buildCalculatedDateFilters(partDateExpr, filters.fromDate, filters.toDate, partParams),
  ];
  if (keywordLike) {
    partConditions.push(`(
      COALESCE(ii.name, sc_direct.name, '') LIKE ? ESCAPE '\\'
      OR COALESCE(ii.sku, sc_direct.sku, '') LIKE ? ESCAPE '\\'
      OR t.order_id LIKE ? ESCAPE '\\'
      OR ? LIKE ? ESCAPE '\\'
    )`);
    partParams.push(keywordLike, keywordLike, keywordLike, CALCULATED_COGS_CATEGORY, keywordLike);
  }

  const invoiceDateExpr = 'DATE(COALESCE(i.created_at, ili.created_at))';
  const invoiceParams: any[] = [];
  const invoiceConditions = [
    "COALESCE(i.status, '') != 'void'",
    'COALESCE(ili.quantity, 0) > 0',
    "COALESCE(ii.item_type, 'part') != 'service'",
    "COALESCE(NULLIF(ii.cost_price, 0), sku_cost.min_price, line_name_cost.min_price, inv_name_cost.min_price, 0) > 0",
    `NOT EXISTS (
      SELECT 1
      FROM ticket_device_parts existing_tdp
      JOIN ticket_devices existing_td ON existing_td.id = existing_tdp.ticket_device_id
      WHERE i.ticket_id IS NOT NULL
        AND existing_td.ticket_id = i.ticket_id
        AND (
          (ili.inventory_item_id IS NOT NULL AND existing_tdp.inventory_item_id = ili.inventory_item_id)
          OR LOWER(TRIM(COALESCE(ii.name, ili.description, ''))) = LOWER(TRIM(COALESCE((
            SELECT existing_ii.name FROM inventory_items existing_ii WHERE existing_ii.id = existing_tdp.inventory_item_id
          ), '')))
        )
    )`,
    ...buildCalculatedDateFilters(invoiceDateExpr, filters.fromDate, filters.toDate, invoiceParams),
  ];
  if (keywordLike) {
    invoiceConditions.push(`(
      ili.description LIKE ? ESCAPE '\\'
      OR COALESCE(ii.name, '') LIKE ? ESCAPE '\\'
      OR COALESCE(ii.sku, '') LIKE ? ESCAPE '\\'
      OR i.order_id LIKE ? ESCAPE '\\'
      OR ? LIKE ? ESCAPE '\\'
    )`);
    invoiceParams.push(keywordLike, keywordLike, keywordLike, keywordLike, CALCULATED_COGS_CATEGORY, keywordLike);
  }

  const [ticketPartRows, invoiceLineRows] = await Promise.all([
    adb.all<AnyRow>(`
      WITH
      sku_cost AS (
        SELECT LOWER(TRIM(sku)) AS norm_sku, MIN(price) AS min_price
        FROM supplier_catalog
        WHERE price > 0 AND sku IS NOT NULL AND TRIM(sku) != ''
        GROUP BY LOWER(TRIM(sku))
      ),
      part_name_cost AS (
        SELECT LOWER(TRIM(name)) AS norm_name, MIN(price) AS min_price
        FROM supplier_catalog
        WHERE price > 0
        GROUP BY LOWER(TRIM(name))
      )
      SELECT
        (-1000000000 - tdp.id) AS id,
        ? AS category,
        ROUND(
          COALESCE(tdp.quantity, 1) *
          COALESCE(NULLIF(ii.cost_price, 0), NULLIF(sc_direct.price, 0), sku_cost.min_price, part_name_cost.min_price, 0),
          2
        ) AS amount,
        'Calculated parts cost: ' || COALESCE(ii.name, sc_direct.name, 'Unknown part') ||
          ' for ' || COALESCE(t.order_id, 'ticket #' || t.id) AS description,
        ${partDateExpr} AS date,
        NULL AS receipt_path,
        NULL AS receipt_image_path,
        1 AS user_id,
        COALESCE(tdp.created_at, td.created_at, t.created_at) AS created_at,
        COALESCE(tdp.updated_at, td.updated_at, t.updated_at) AS updated_at,
        'approved' AS status,
        'general' AS expense_subtype,
        1 AS is_calculated,
        0 AS can_edit,
        'ticket_parts_cogs' AS expense_source,
        CASE
          WHEN NULLIF(ii.cost_price, 0) IS NOT NULL THEN 'inventory'
          WHEN NULLIF(sc_direct.price, 0) IS NOT NULL THEN COALESCE(sc_direct.source, 'supplier_catalog')
          WHEN sku_cost.min_price IS NOT NULL THEN 'supplier_catalog_sku'
          WHEN part_name_cost.min_price IS NOT NULL THEN 'supplier_catalog_name'
          ELSE 'unknown'
        END AS cost_source,
        'System' AS first_name,
        'Calculated' AS last_name
      FROM ticket_device_parts tdp
      JOIN ticket_devices td ON td.id = tdp.ticket_device_id
      JOIN tickets t ON t.id = td.ticket_id
      LEFT JOIN inventory_items ii ON ii.id = tdp.inventory_item_id
      LEFT JOIN supplier_catalog sc_direct ON sc_direct.id = tdp.catalog_item_id
      LEFT JOIN sku_cost ON sku_cost.norm_sku = LOWER(TRIM(COALESCE(ii.sku, sc_direct.sku, '')))
      LEFT JOIN part_name_cost ON part_name_cost.norm_name = LOWER(TRIM(COALESCE(ii.name, sc_direct.name, '')))
      WHERE ${partConditions.join(' AND ')}
    `, CALCULATED_COGS_CATEGORY, ...partParams),
    adb.all<AnyRow>(`
      WITH
      sku_cost AS (
        SELECT LOWER(TRIM(sku)) AS norm_sku, MIN(price) AS min_price
        FROM supplier_catalog
        WHERE price > 0 AND sku IS NOT NULL AND TRIM(sku) != ''
        GROUP BY LOWER(TRIM(sku))
      ),
      line_name_cost AS (
        SELECT LOWER(TRIM(name)) AS norm_name, MIN(price) AS min_price
        FROM supplier_catalog
        WHERE price > 0
        GROUP BY LOWER(TRIM(name))
      ),
      inv_name_cost AS (
        SELECT LOWER(TRIM(name)) AS norm_name, MIN(price) AS min_price
        FROM supplier_catalog
        WHERE price > 0
        GROUP BY LOWER(TRIM(name))
      )
      SELECT
        (-2000000000 - ili.id) AS id,
        ? AS category,
        ROUND(
          COALESCE(ili.quantity, 1) *
          COALESCE(NULLIF(ii.cost_price, 0), sku_cost.min_price, line_name_cost.min_price, inv_name_cost.min_price, 0),
          2
        ) AS amount,
        'Calculated item cost: ' || COALESCE(NULLIF(ili.description, ''), ii.name, 'Unknown item') ||
          ' for invoice ' || COALESCE(i.order_id, '#' || i.id) AS description,
        ${invoiceDateExpr} AS date,
        NULL AS receipt_path,
        NULL AS receipt_image_path,
        1 AS user_id,
        COALESCE(i.created_at, ili.created_at) AS created_at,
        COALESCE(ili.updated_at, i.updated_at) AS updated_at,
        'approved' AS status,
        'general' AS expense_subtype,
        1 AS is_calculated,
        0 AS can_edit,
        'invoice_line_cogs' AS expense_source,
        CASE
          WHEN NULLIF(ii.cost_price, 0) IS NOT NULL THEN 'inventory'
          WHEN sku_cost.min_price IS NOT NULL THEN 'supplier_catalog_sku'
          WHEN line_name_cost.min_price IS NOT NULL THEN 'supplier_catalog_name'
          WHEN inv_name_cost.min_price IS NOT NULL THEN 'supplier_catalog_name'
          ELSE 'unknown'
        END AS cost_source,
        'System' AS first_name,
        'Calculated' AS last_name
      FROM invoice_line_items ili
      JOIN invoices i ON i.id = ili.invoice_id
      LEFT JOIN inventory_items ii ON ii.id = ili.inventory_item_id
      LEFT JOIN sku_cost ON sku_cost.norm_sku = LOWER(TRIM(COALESCE(ii.sku, '')))
      LEFT JOIN line_name_cost ON line_name_cost.norm_name = LOWER(TRIM(ili.description))
      LEFT JOIN inv_name_cost ON inv_name_cost.norm_name = LOWER(TRIM(COALESCE(ii.name, '')))
      WHERE ${invoiceConditions.join(' AND ')}
    `, CALCULATED_COGS_CATEGORY, ...invoiceParams),
  ]);

  return [...ticketPartRows, ...invoiceLineRows];
}

// GET / — List expenses (paginated, filterable)
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const pageSize = parsePageSize(req.query.pagesize, 25);
  const category = (req.query.category as string || '').trim();
  const fromDate = (req.query.from_date as string || '').trim();
  const toDate = (req.query.to_date as string || '').trim();
  const keyword = (req.query.keyword as string || '').trim();
  const statusFilter = (req.query.status as string || '').trim();
  const subtypeFilter = (req.query.expense_subtype as string || '').trim();
  const includeCalculatedRaw = (req.query.include_calculated as string || '').trim().toLowerCase();

  const conditions: string[] = [];
  const params: any[] = [];

  // BUGHUNT-2026-05-17: non-admin/manager users only see their OWN
  // expenses. Previously this endpoint returned every employee's
  // expense rows (amount, description, receipt path) to any
  // authenticated user — an obvious within-tenant PII leak. The PUT
  // and DELETE handlers below already enforce owner-or-admin; the
  // list/detail GETs missed the matching guard.
  const isPrivileged = req.user?.role === 'admin' || req.user?.role === 'manager';
  if (!isPrivileged) {
    conditions.push('e.user_id = ?');
    params.push(req.user!.id);
  }

  if (category) { conditions.push('e.category = ?'); params.push(category); }
  if (fromDate) { conditions.push('e.date >= ?'); params.push(fromDate); }
  if (toDate) { conditions.push('e.date <= ?'); params.push(toDate); }
  if (statusFilter) {
    if (!['pending', 'approved', 'denied'].includes(statusFilter)) {
      throw new AppError('status must be pending, approved, or denied', 400);
    }
    conditions.push('e.status = ?');
    params.push(statusFilter);
  }
  if (subtypeFilter) {
    if (!['general', 'mileage', 'perdiem'].includes(subtypeFilter)) {
      throw new AppError('expense_subtype must be general, mileage, or perdiem', 400);
    }
    conditions.push('e.expense_subtype = ?');
    params.push(subtypeFilter);
  }
  if (keyword) {
    conditions.push("(e.description LIKE ? ESCAPE '\\' OR e.category LIKE ? ESCAPE '\\')");
    const k = `%${escapeLike(keyword)}%`;
    params.push(k, k);
  }

  const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';
  const offset = (page - 1) * pageSize;
  const includeCalculated = shouldIncludeCalculatedCogs(category, statusFilter, subtypeFilter, includeCalculatedRaw);

  const [manualExpenses, calculatedExpenses] = await Promise.all([
    adb.all<AnyRow>(`
      SELECT e.*, u.first_name, u.last_name, 0 AS is_calculated, 1 AS can_edit, 'manual' AS expense_source
      FROM expenses e
      LEFT JOIN users u ON u.id = e.user_id
      ${whereClause}
      ORDER BY e.date DESC, e.id DESC
    `, ...params),
    includeCalculated ? getCalculatedCogsExpenses(adb, { fromDate, toDate, keyword }) : Promise.resolve([]),
  ]);

  const combinedExpenses = [...manualExpenses, ...calculatedExpenses].sort(sortExpenseRows);
  const total = combinedExpenses.length;
  const expenses = combinedExpenses.slice(offset, offset + pageSize);

  const summary = {
    total_amount: combinedExpenses.reduce((sum, exp) => sum + (Number(exp.amount) || 0), 0),
    total_count: total,
  };
  const categoryMap = new Map<string, { category: string; count: number; total: number }>();
  for (const exp of combinedExpenses) {
    const key = String(exp.category || 'Other');
    const existing = categoryMap.get(key) || { category: key, count: 0, total: 0 };
    existing.count += 1;
    existing.total += Number(exp.amount) || 0;
    categoryMap.set(key, existing);
  }
  const categories = Array.from(categoryMap.values()).sort((a, b) => b.total - a.total);

  res.json({
    success: true,
    data: {
      expenses,
      summary,
      categories,
      pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) },
    },
  });
}));

// GET /:id — Single expense
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // @audit-fixed: validate id is positive integer (NaN previously slipped to SQL as `WHERE id = NaN`)
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);
  const expense = await adb.get<Record<string, any>>('SELECT e.*, u.first_name, u.last_name FROM expenses e LEFT JOIN users u ON u.id = e.user_id WHERE e.id = ?', id);
  if (!expense) throw new AppError('Expense not found', 404);
  // BUGHUNT-2026-05-17: non-admin/manager only see their own expense.
  // Previously an employee could enumerate sequential IDs and read
  // every coworker's expense detail (amount, receipt path, description).
  const isPrivileged = req.user?.role === 'admin' || req.user?.role === 'manager';
  if (!isPrivileged && expense.user_id !== req.user!.id) {
    throw new AppError('Expense not found', 404);
  }
  res.json({ success: true, data: expense });
}));

// ---------------------------------------------------------------------------
// Location validation helper
// ---------------------------------------------------------------------------

async function resolveLocationId(adb: AsyncDb, rawValue: unknown): Promise<number> {
  if (rawValue === undefined || rawValue === null || rawValue === '') {
    return 1; // default to Main Store
  }
  const locId = Number(rawValue);
  if (!Number.isInteger(locId) || locId <= 0) {
    throw new AppError('location_id must be a positive integer', 400);
  }
  const loc = await adb.get<{ id: number }>('SELECT id FROM locations WHERE id = ? AND is_active = 1', locId);
  if (!loc) throw new AppError('location_id does not reference an active location', 400);
  return locId;
}

// POST / — Create expense
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const { category, amount, description, date, receipt_path } = req.body;
  // @audit-fixed: reject NaN/Infinity/strings on amount instead of accepting via `!amount`.
  // Previously `amount = "5"` (string) silently passed `!amount` and `<= 0`, then
  // got bound to SQLite as TEXT — corrupting reports that SUM(amount).
  const amt = Number(amount);
  if (!Number.isFinite(amt) || amt <= 0) throw new AppError('Valid amount required', 400);
  // V3: Expense amount bounds check
  if (amt > 100_000) throw new AppError('Expense amount cannot exceed $100,000', 400);
  if (!category) throw new AppError('Category required', 400);

  const locationId = await resolveLocationId(adb, req.body.location_id);

  const result = await adb.run(`
    INSERT INTO expenses (category, amount, description, date, receipt_path, user_id, location_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `, category, amt, description || null, date || now().substring(0, 10), receipt_path || null, req.user!.id, locationId, now(), now());

  // @audit-fixed: audit() coverage on expense create — financial mutation, was untracked
  audit(db, 'expense_created', req.user!.id, req.ip || 'unknown', { expense_id: Number(result.lastInsertRowid), amount: amt, category, location_id: locationId });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /:id — Update expense
router.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // @audit-fixed: validate id is positive integer
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);
  const existing = await adb.get<Record<string, any>>('SELECT id, user_id FROM expenses WHERE id = ?', id);
  if (!existing) throw new AppError('Expense not found', 404);

  // Only admins or the user who created the expense can edit it
  // (mirror of the DELETE handler below). Without this any authenticated
  // user could overwrite another employee's expense amount/category.
  if (req.user!.role !== 'admin' && existing.user_id !== req.user!.id) {
    throw new AppError('Not authorized to edit this expense', 403);
  }

  const { category, amount, description, date, receipt_path } = req.body;
  // @audit-fixed: V3 expense amount bounds check on update too — previously
  // PUT silently accepted NaN/Infinity/negatives via the COALESCE pattern.
  if (amount !== undefined && amount !== null) {
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0 || amt > 100_000) {
      throw new AppError('Expense amount must be a positive number <= $100,000', 400);
    }
  }

  // Validate location_id only when caller supplies it
  let locationIdForUpdate: number | null = null;
  if (req.body.location_id !== undefined && req.body.location_id !== null) {
    locationIdForUpdate = await resolveLocationId(adb, req.body.location_id);
  }

  await adb.run(`
    UPDATE expenses SET category = COALESCE(?, category), amount = COALESCE(?, amount),
      description = COALESCE(?, description), date = COALESCE(?, date),
      receipt_path = COALESCE(?, receipt_path),
      location_id = COALESCE(?, location_id), updated_at = ?
    WHERE id = ?
  `, category ?? null, amount ?? null, description ?? null, date ?? null, receipt_path ?? null,
     locationIdForUpdate, now(), id);

  res.json({ success: true, data: { id } });
}));

// DELETE /:id — Delete expense
router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  // @audit-fixed: validate id is positive integer
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);
  const existing = await adb.get<Record<string, any>>('SELECT id, user_id FROM expenses WHERE id = ?', id);
  if (!existing) throw new AppError('Expense not found', 404);

  // Only admins or the user who created the expense can delete it
  if (req.user!.role !== 'admin' && existing.user_id !== req.user!.id) {
    throw new AppError('Not authorized to delete this expense', 403);
  }

  await adb.run('DELETE FROM expenses WHERE id = ?', id);
  audit(db, 'expense_deleted', req.user!.id, req.ip || 'unknown', { expense_id: id });
  res.json({ success: true, data: { id } });
}));

// ---------------------------------------------------------------------------
// Role guards (defence-in-depth — authMiddleware already applied at mount)
// ---------------------------------------------------------------------------

function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

// ---------------------------------------------------------------------------
// Rate-limit constants for write paths
// ---------------------------------------------------------------------------

const EXPENSE_WRITE_CATEGORY = 'expense_write';
const EXPENSE_WRITE_MAX = 30;
const EXPENSE_WRITE_WINDOW_MS = 60_000; // 30 writes per user per minute

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

const MAX_VENDOR_LEN = 200;
const MAX_DESC_LEN = 1000;
const MAX_CATEGORY_LEN = 100;
const MAX_REASON_LEN = 500;
const MAX_MILES = 1000;
const MAX_DAYS = 90;
const MAX_RATE_CENTS = 50_000;

function validateStringField(value: unknown, fieldName: string, maxLen: number): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new AppError(`${fieldName} is required`, 400);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${fieldName} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed;
}

function validateOptionalString(value: unknown, fieldName: string, maxLen: number): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const trimmed = value.trim();
  if (trimmed.length > maxLen) {
    throw new AppError(`${fieldName} must be ${maxLen} characters or fewer`, 400);
  }
  return trimmed || null;
}

// ---------------------------------------------------------------------------
// POST /mileage — create a mileage expense
// ---------------------------------------------------------------------------

router.post('/mileage', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;

  // Rate-limit per user
  if (!checkWindowRate(db, EXPENSE_WRITE_CATEGORY, String(req.user!.id), EXPENSE_WRITE_MAX, EXPENSE_WRITE_WINDOW_MS)) {
    throw new AppError('Too many expense submissions. Please wait before trying again.', 429);
  }
  recordWindowAttempt(db, EXPENSE_WRITE_CATEGORY, String(req.user!.id), EXPENSE_WRITE_WINDOW_MS);

  const vendor = validateStringField(req.body.vendor, 'vendor', MAX_VENDOR_LEN);
  const description = validateStringField(req.body.description, 'description', MAX_DESC_LEN);
  const incurred_at = validateStringField(req.body.incurred_at, 'incurred_at', 30);
  const category = validateStringField(req.body.category, 'category', MAX_CATEGORY_LEN);
  const customer_id = validateOptionalString(req.body.customer_id, 'customer_id', 20);

  const miles = Number(req.body.miles);
  if (!Number.isFinite(miles) || miles <= 0 || miles > MAX_MILES) {
    throw new AppError(`miles must be a positive number and cannot exceed ${MAX_MILES}`, 400);
  }
  const rate_cents = Number(req.body.rate_cents);
  if (!Number.isInteger(rate_cents) || rate_cents <= 0 || rate_cents > MAX_RATE_CENTS) {
    throw new AppError(`rate_cents must be a positive integer and cannot exceed ${MAX_RATE_CENTS}`, 400);
  }

  const amount_cents = Math.round(miles * rate_cents);
  // Store as dollar-equivalent amount for consistency with existing schema
  const amount = amount_cents / 100;

  const customerIdInt = customer_id !== null ? parseInt(customer_id, 10) : null;
  if (customer_id !== null && (!Number.isInteger(customerIdInt) || (customerIdInt as number) <= 0)) {
    throw new AppError('Invalid customer_id', 400);
  }

  const locationId = await resolveLocationId(adb, req.body.location_id);

  const result = await adb.run(`
    INSERT INTO expenses
      (category, amount, description, date, vendor, user_id,
       expense_subtype, mileage_miles, mileage_rate_cents,
       location_id, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'mileage', ?, ?, ?, 'pending', ?, ?)
  `,
    category, amount, description, incurred_at, vendor, req.user!.id,
    miles, rate_cents, locationId,
    now(), now()
  );

  const created = await adb.get('SELECT * FROM expenses WHERE id = ?', result.lastInsertRowid);
  audit(db, 'expense.mileage_created', req.user!.id, req.ip || 'unknown', {
    expense_id: Number(result.lastInsertRowid), miles, rate_cents, amount_cents,
  });
  res.status(201).json({ success: true, data: created });
}));

// ---------------------------------------------------------------------------
// POST /perdiem — create a per-diem expense
// ---------------------------------------------------------------------------

router.post('/perdiem', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;

  // Rate-limit per user
  if (!checkWindowRate(db, EXPENSE_WRITE_CATEGORY, String(req.user!.id), EXPENSE_WRITE_MAX, EXPENSE_WRITE_WINDOW_MS)) {
    throw new AppError('Too many expense submissions. Please wait before trying again.', 429);
  }
  recordWindowAttempt(db, EXPENSE_WRITE_CATEGORY, String(req.user!.id), EXPENSE_WRITE_WINDOW_MS);

  const description = validateStringField(req.body.description, 'description', MAX_DESC_LEN);
  const incurred_at = validateStringField(req.body.incurred_at, 'incurred_at', 30);
  const category = validateStringField(req.body.category, 'category', MAX_CATEGORY_LEN);
  const customer_id = validateOptionalString(req.body.customer_id, 'customer_id', 20);

  const days = Number(req.body.days);
  if (!Number.isInteger(days) || days <= 0 || days > MAX_DAYS) {
    throw new AppError(`days must be a positive integer and cannot exceed ${MAX_DAYS}`, 400);
  }
  const rate_cents = Number(req.body.rate_cents);
  if (!Number.isInteger(rate_cents) || rate_cents <= 0 || rate_cents > MAX_RATE_CENTS) {
    throw new AppError(`rate_cents must be a positive integer and cannot exceed ${MAX_RATE_CENTS}`, 400);
  }

  const amount_cents = days * rate_cents;
  const amount = amount_cents / 100;

  const customerIdInt = customer_id !== null ? parseInt(customer_id, 10) : null;
  if (customer_id !== null && (!Number.isInteger(customerIdInt) || (customerIdInt as number) <= 0)) {
    throw new AppError('Invalid customer_id', 400);
  }

  const locationId = await resolveLocationId(adb, req.body.location_id);

  const result = await adb.run(`
    INSERT INTO expenses
      (category, amount, description, date, user_id,
       expense_subtype, perdiem_days, perdiem_rate_cents,
       location_id, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, 'perdiem', ?, ?, ?, 'pending', ?, ?)
  `,
    category, amount, description, incurred_at, req.user!.id,
    days, rate_cents, locationId,
    now(), now()
  );

  const created = await adb.get('SELECT * FROM expenses WHERE id = ?', result.lastInsertRowid);
  audit(db, 'expense.perdiem_created', req.user!.id, req.ip || 'unknown', {
    expense_id: Number(result.lastInsertRowid), days, rate_cents, amount_cents,
  });
  res.status(201).json({ success: true, data: created });
}));

// ---------------------------------------------------------------------------
// POST /:id/approve — approve an expense (manager/admin only)
// ---------------------------------------------------------------------------

router.post('/:id/approve', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);

  const existing = await adb.get<AnyRow>('SELECT id, status FROM expenses WHERE id = ?', id);
  if (!existing) throw new AppError('Expense not found', 404);
  if (existing.status === 'approved') throw new AppError('Expense is already approved', 409);

  const approvedAt = now();
  // BUGHUNT-2026-05-17: guard WHERE status != 'approved' so two concurrent
  // approve calls don't both pass the precheck and both overwrite
  // approved_by_user_id + approved_at. changes === 0 → another manager
  // approved between the SELECT and the UPDATE; surface 409.
  const apprRes = await adb.run(`
    UPDATE expenses
    SET status = 'approved', approved_by_user_id = ?, approved_at = ?, updated_at = ?
    WHERE id = ? AND status != 'approved'
  `, req.user!.id, approvedAt, approvedAt, id);
  if (apprRes.changes === 0) {
    throw new AppError('Expense was approved by another user; refresh and retry', 409);
  }

  audit(db, 'expense.approved', req.user!.id, req.ip || 'unknown', {
    expense_id: id, previous_status: existing.status,
  });
  res.json({ success: true, data: { id, status: 'approved', approved_at: approvedAt } });
}));

// ---------------------------------------------------------------------------
// POST /:id/deny — deny an expense (manager/admin only)
// ---------------------------------------------------------------------------

router.post('/:id/deny', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;

  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);

  const existing = await adb.get<AnyRow>('SELECT id, status FROM expenses WHERE id = ?', id);
  if (!existing) throw new AppError('Expense not found', 404);
  if (existing.status === 'denied') throw new AppError('Expense is already denied', 409);

  const reason = validateStringField(req.body.reason, 'reason', MAX_REASON_LEN);

  // BUGHUNT-2026-05-17: guard WHERE status != 'denied' so two concurrent
  // deny calls don't both pass the precheck and both overwrite
  // denial_reason. Also blocks a stale /deny from clobbering a just-
  // approved expense back into the denied state.
  const denyRes = await adb.run(`
    UPDATE expenses
    SET status = 'denied', denial_reason = ?, updated_at = ?
    WHERE id = ? AND status != 'denied'
  `, reason, now(), id);
  if (denyRes.changes === 0) {
    throw new AppError('Expense was denied by another user; refresh and retry', 409);
  }

  audit(db, 'expense.denied', req.user!.id, req.ip || 'unknown', {
    expense_id: id, previous_status: existing.status, reason,
  });
  res.json({ success: true, data: { id, status: 'denied', denial_reason: reason } });
}));

export default router;
