import { Router } from 'express';
import crypto from 'crypto';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { roundCurrency } from '../utils/currency.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function generateCode(): string {
  return crypto.randomBytes(8).toString('hex').toUpperCase(); // 16 chars
}

// GET / — List gift cards
router.get('/', asyncHandler(async (req, res) => {
  const keyword = (req.query.keyword as string || '').trim();
  const status = (req.query.status as string || '').trim();

  const conditions: string[] = [];
  const params: any[] = [];
  if (keyword) { conditions.push('(gc.code LIKE ? OR gc.recipient_name LIKE ?)'); params.push(`%${keyword}%`, `%${keyword}%`); }
  if (status) { conditions.push('gc.status = ?'); params.push(status); }

  const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';

  const cards = db.prepare(`
    SELECT gc.*, c.first_name, c.last_name
    FROM gift_cards gc
    LEFT JOIN customers c ON c.id = gc.customer_id
    ${whereClause}
    ORDER BY gc.created_at DESC
  `).all(...params);

  const summary = db.prepare(`
    SELECT COUNT(*) AS total_cards,
           COALESCE(SUM(current_balance), 0) AS total_outstanding,
           COUNT(CASE WHEN status = 'active' THEN 1 END) AS active_count
    FROM gift_cards
  `).get() as any;

  res.json({ success: true, data: { cards, summary } });
}));

// GET /lookup/:code — Lookup gift card by code (for POS)
router.get('/lookup/:code', asyncHandler(async (req, res) => {
  const card = db.prepare('SELECT * FROM gift_cards WHERE code = ?').get(req.params.code.toUpperCase()) as any;
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status !== 'active') throw new AppError(`Gift card is ${card.status}`, 400);
  if (card.expires_at && new Date(card.expires_at) < new Date()) throw new AppError('Gift card expired', 400);
  res.json({ success: true, data: card });
}));

// POST / — Issue new gift card
router.post('/', asyncHandler(async (req, res) => {
  const { amount, customer_id, recipient_name, recipient_email, expires_at, notes } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);

  const code = generateCode();
  const result = db.prepare(`
    INSERT INTO gift_cards (code, initial_balance, current_balance, status, customer_id, recipient_name, recipient_email, expires_at, notes, created_by, created_at, updated_at)
    VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(code, amount, amount, customer_id || null, recipient_name || null, recipient_email || null,
    expires_at || null, notes || null, req.user!.id, now(), now());

  // Record purchase transaction
  db.prepare('INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .run(Number(result.lastInsertRowid), 'purchase', amount, 'Initial load', req.user!.id, now());

  res.status(201).json({ success: true, data: { id: Number(result.lastInsertRowid), code } });
}));

// POST /:id/redeem — Redeem gift card (at POS)
router.post('/:id/redeem', asyncHandler(async (req, res) => {
  const { amount, invoice_id } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);

  const card = db.prepare('SELECT * FROM gift_cards WHERE id = ?').get(req.params.id) as any;
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status !== 'active') throw new AppError(`Gift card is ${card.status}`, 400);
  if (card.current_balance < amount) throw new AppError('Insufficient balance', 400);

  const newBalance = roundCurrency(card.current_balance - amount);
  const newStatus = newBalance <= 0 ? 'used' : 'active';

  db.prepare('UPDATE gift_cards SET current_balance = ?, status = ?, updated_at = ? WHERE id = ?')
    .run(newBalance, newStatus, now(), req.params.id);
  db.prepare('INSERT INTO gift_card_transactions (gift_card_id, type, amount, invoice_id, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .run(req.params.id, 'redemption', -amount, invoice_id || null, 'Redeemed at POS', req.user!.id, now());

  res.json({ success: true, data: { new_balance: newBalance, status: newStatus } });
}));

// POST /:id/reload — Add balance to gift card
router.post('/:id/reload', asyncHandler(async (req, res) => {
  const { amount } = req.body;
  if (!amount || amount <= 0) throw new AppError('Valid amount required', 400);

  const card = db.prepare('SELECT * FROM gift_cards WHERE id = ?').get(req.params.id) as any;
  if (!card) throw new AppError('Gift card not found', 404);

  db.prepare('UPDATE gift_cards SET current_balance = current_balance + ?, status = ?, updated_at = ? WHERE id = ?')
    .run(amount, 'active', now(), req.params.id);
  db.prepare('INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .run(req.params.id, 'adjustment', amount, 'Reloaded', req.user!.id, now());

  res.json({ success: true, data: { new_balance: roundCurrency(card.current_balance + amount) } });
}));

// GET /:id — Gift card details with transactions
router.get('/:id', asyncHandler(async (req, res) => {
  const card = db.prepare('SELECT * FROM gift_cards WHERE id = ?').get(req.params.id);
  if (!card) throw new AppError('Gift card not found', 404);
  const transactions = db.prepare('SELECT * FROM gift_card_transactions WHERE gift_card_id = ? ORDER BY created_at DESC').all(req.params.id);
  res.json({ success: true, data: { ...(card as any), transactions } });
}));

export default router;
