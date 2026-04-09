import { Router, Request, Response } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List expenses (paginated, filterable)
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const pageSize = Math.min(100, parseInt(req.query.pagesize as string) || 25);
  const category = (req.query.category as string || '').trim();
  const fromDate = (req.query.from_date as string || '').trim();
  const toDate = (req.query.to_date as string || '').trim();
  const keyword = (req.query.keyword as string || '').trim();

  const conditions: string[] = [];
  const params: any[] = [];

  if (category) { conditions.push('e.category = ?'); params.push(category); }
  if (fromDate) { conditions.push('e.date >= ?'); params.push(fromDate); }
  if (toDate) { conditions.push('e.date <= ?'); params.push(toDate); }
  if (keyword) { conditions.push('(e.description LIKE ? OR e.category LIKE ?)'); params.push(`%${keyword}%`, `%${keyword}%`); }

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
  const id = parseInt(req.params.id as string);
  const expense = await adb.get('SELECT e.*, u.first_name, u.last_name FROM expenses e LEFT JOIN users u ON u.id = e.user_id WHERE e.id = ?', id);
  if (!expense) throw new AppError('Expense not found', 404);
  res.json({ success: true, data: expense });
}));

// POST / — Create expense
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const { category, amount, description, date, receipt_path } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);
  // V3: Expense amount bounds check
  if (amount > 1_000_000) throw new AppError('Expense amount cannot exceed $1,000,000', 400);
  if (!category) throw new AppError('Category required', 400);

  const result = await adb.run(`
    INSERT INTO expenses (category, amount, description, date, receipt_path, user_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `, category, amount, description || null, date || now().substring(0, 10), receipt_path || null, req.user!.id, now(), now());

  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /:id — Update expense
router.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string);
  const existing = await adb.get('SELECT id FROM expenses WHERE id = ?', id);
  if (!existing) throw new AppError('Expense not found', 404);

  const { category, amount, description, date, receipt_path } = req.body;
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
  const id = parseInt(req.params.id as string);
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

export default router;
