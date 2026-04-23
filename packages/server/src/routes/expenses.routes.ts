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

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
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

  const conditions: string[] = [];
  const params: any[] = [];

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

  const [totalRow, expenses, summary, categories] = await Promise.all([
    adb.get<AnyRow>(`SELECT COUNT(*) AS c FROM expenses e ${whereClause}`, ...params),
    adb.all<AnyRow>(`
      SELECT e.*, u.first_name, u.last_name
      FROM expenses e
      LEFT JOIN users u ON u.id = e.user_id
      ${whereClause}
      ORDER BY e.date DESC, e.id DESC
      LIMIT ? OFFSET ?
    `, ...params, pageSize, offset),
    adb.get<AnyRow>(`
      SELECT COALESCE(SUM(amount), 0) AS total_amount, COUNT(*) AS total_count
      FROM expenses e ${whereClause}
    `, ...params),
    adb.all<AnyRow>(`
      SELECT category, COUNT(*) AS count, COALESCE(SUM(amount), 0) AS total
      FROM expenses e ${whereClause}
      GROUP BY category ORDER BY total DESC
    `, ...params),
  ]);

  const total = totalRow!.c;

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
  const expense = await adb.get('SELECT e.*, u.first_name, u.last_name FROM expenses e LEFT JOIN users u ON u.id = e.user_id WHERE e.id = ?', id);
  if (!expense) throw new AppError('Expense not found', 404);
  res.json({ success: true, data: expense });
}));

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

  const result = await adb.run(`
    INSERT INTO expenses (category, amount, description, date, receipt_path, user_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, category, amt, description || null, date || now().substring(0, 10), receipt_path || null, req.user!.id, now(), now());

  // @audit-fixed: audit() coverage on expense create — financial mutation, was untracked
  audit(db, 'expense_created', req.user!.id, req.ip || 'unknown', { expense_id: Number(result.lastInsertRowid), amount: amt, category });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /:id — Update expense
router.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // @audit-fixed: validate id is positive integer
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid expense ID', 400);
  const existing = await adb.get('SELECT id FROM expenses WHERE id = ?', id);
  if (!existing) throw new AppError('Expense not found', 404);

  const { category, amount, description, date, receipt_path } = req.body;
  // @audit-fixed: V3 expense amount bounds check on update too — previously
  // PUT silently accepted NaN/Infinity/negatives via the COALESCE pattern.
  if (amount !== undefined && amount !== null) {
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0 || amt > 100_000) {
      throw new AppError('Expense amount must be a positive number <= $100,000', 400);
    }
  }
  await adb.run(`
    UPDATE expenses SET category = COALESCE(?, category), amount = COALESCE(?, amount),
      description = COALESCE(?, description), date = COALESCE(?, date),
      receipt_path = COALESCE(?, receipt_path), updated_at = ?
    WHERE id = ?
  `, category ?? null, amount ?? null, description ?? null, date ?? null, receipt_path ?? null, now(), id);

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

  const result = await adb.run(`
    INSERT INTO expenses
      (category, amount, description, date, vendor, user_id,
       expense_subtype, mileage_miles, mileage_rate_cents,
       status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'mileage', ?, ?, 'pending', ?, ?)
  `,
    category, amount, description, incurred_at, vendor, req.user!.id,
    miles, rate_cents,
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

  const result = await adb.run(`
    INSERT INTO expenses
      (category, amount, description, date, user_id,
       expense_subtype, perdiem_days, perdiem_rate_cents,
       status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, 'perdiem', ?, ?, 'pending', ?, ?)
  `,
    category, amount, description, incurred_at, req.user!.id,
    days, rate_cents,
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
  await adb.run(`
    UPDATE expenses
    SET status = 'approved', approved_by_user_id = ?, approved_at = ?, updated_at = ?
    WHERE id = ?
  `, req.user!.id, approvedAt, approvedAt, id);

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

  await adb.run(`
    UPDATE expenses
    SET status = 'denied', denial_reason = ?, updated_at = ?
    WHERE id = ?
  `, reason, now(), id);

  audit(db, 'expense.denied', req.user!.id, req.ip || 'unknown', {
    expense_id: id, previous_status: existing.status, reason,
  });
  res.json({ success: true, data: { id, status: 'denied', denial_reason: reason } });
}));

export default router;
