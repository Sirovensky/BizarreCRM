import { Router, Request, Response } from 'express';
import { db } from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// GET / — List expenses (paginated, filterable)
router.get('/', asyncHandler(async (req: Request, res: Response) => {
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

  const total = (db.prepare(`SELECT COUNT(*) AS c FROM expenses e ${whereClause}`).get(...params) as AnyRow).c;
  const offset = (page - 1) * pageSize;

  const expenses = db.prepare(`
    SELECT e.*, u.first_name, u.last_name
    FROM expenses e
    LEFT JOIN users u ON u.id = e.user_id
    ${whereClause}
    ORDER BY e.date DESC, e.id DESC
    LIMIT ? OFFSET ?
  `).all(...params, pageSize, offset) as AnyRow[];

  // Summary totals
  const summary = db.prepare(`
    SELECT COALESCE(SUM(amount), 0) AS total_amount, COUNT(*) AS total_count
    FROM expenses e ${whereClause}
  `).get(...params) as AnyRow;

  // Category breakdown
  const categories = db.prepare(`
    SELECT category, COUNT(*) AS count, COALESCE(SUM(amount), 0) AS total
    FROM expenses e ${whereClause}
    GROUP BY category ORDER BY total DESC
  `).all(...params) as AnyRow[];

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
  const id = parseInt(req.params.id);
  const expense = db.prepare('SELECT e.*, u.first_name, u.last_name FROM expenses e LEFT JOIN users u ON u.id = e.user_id WHERE e.id = ?').get(id);
  if (!expense) throw new AppError('Expense not found', 404);
  res.json({ success: true, data: expense });
}));

// POST / — Create expense
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  const { category, amount, description, date, receipt_path } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);
  if (!category) throw new AppError('Category required', 400);

  const result = db.prepare(`
    INSERT INTO expenses (category, amount, description, date, receipt_path, user_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(category, amount, description || null, date || now().substring(0, 10), receipt_path || null, req.user!.id, now(), now());

  res.status(201).json({ success: true, data: { id: Number(result.lastInsertRowid) } });
}));

// PUT /:id — Update expense
router.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const id = parseInt(req.params.id);
  const existing = db.prepare('SELECT id FROM expenses WHERE id = ?').get(id);
  if (!existing) throw new AppError('Expense not found', 404);

  const { category, amount, description, date, receipt_path } = req.body;
  db.prepare(`
    UPDATE expenses SET category = COALESCE(?, category), amount = COALESCE(?, amount),
      description = COALESCE(?, description), date = COALESCE(?, date),
      receipt_path = COALESCE(?, receipt_path), updated_at = ?
    WHERE id = ?
  `).run(category ?? null, amount ?? null, description ?? null, date ?? null, receipt_path ?? null, now(), id);

  res.json({ success: true, data: { id } });
}));

// DELETE /:id — Delete expense
router.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  const id = parseInt(req.params.id);
  const existing = db.prepare('SELECT id FROM expenses WHERE id = ?').get(id);
  if (!existing) throw new AppError('Expense not found', 404);

  db.prepare('DELETE FROM expenses WHERE id = ?').run(id);
  res.json({ success: true, data: { id } });
}));

export default router;
