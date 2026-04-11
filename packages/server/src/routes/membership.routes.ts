/**
 * Membership Routes — Tier management, subscription lifecycle, BlockChyp integration.
 * All routes are per-tenant (use req.db / req.asyncDb).
 */
import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { audit } from '../utils/audit.js';
import { enrollCard, createPaymentLink } from '../services/blockchyp.js';
import type { AsyncDb } from '../db/async-db.js';

const router = Router();
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// SEC (PL6): Every write/billing route here must verify the actor is an admin,
// regardless of whatever middleware the router is mounted under. Relying on
// the mount point means a future routing refactor can silently expose tier
// creation / subscription lifecycle / payment-link generation to clerks.
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403);
  }
}

// ── Tiers CRUD ───────────────────────────────────────────────────────

router.get('/tiers', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const tiers = await adb.all<AnyRow>(
    'SELECT * FROM membership_tiers WHERE is_active = 1 ORDER BY sort_order ASC'
  );
  // Parse benefits JSON
  const shaped = tiers.map(t => ({
    ...t,
    benefits: t.benefits ? JSON.parse(t.benefits) : [],
  }));
  res.json({ success: true, data: shaped });
}));

router.post('/tiers', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const { name, monthly_price, discount_pct, discount_applies_to, benefits, color, sort_order } = req.body;

  if (!name || !monthly_price) {
    res.status(400).json({ success: false, message: 'Name and monthly price required' });
    return;
  }

  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const result = await adb.run(
    `INSERT INTO membership_tiers (name, slug, monthly_price, discount_pct, discount_applies_to, benefits, color, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    name, slug, monthly_price, discount_pct || 0, discount_applies_to || 'labor',
    JSON.stringify(benefits || []), color || '#3b82f6', sort_order || 0
  );

  audit(req.db, 'membership_tier_created', req.user!.id, req.ip || 'unknown', { tier_id: result.lastInsertRowid, name });
  const tier = await adb.get<AnyRow>('SELECT * FROM membership_tiers WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: tier });
}));

router.put('/tiers/:id', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  const { name, monthly_price, discount_pct, discount_applies_to, benefits, color, sort_order, is_active } = req.body;

  await adb.run(
    `UPDATE membership_tiers SET name = COALESCE(?, name), monthly_price = COALESCE(?, monthly_price),
     discount_pct = COALESCE(?, discount_pct), discount_applies_to = COALESCE(?, discount_applies_to),
     benefits = COALESCE(?, benefits), color = COALESCE(?, color), sort_order = COALESCE(?, sort_order),
     is_active = COALESCE(?, is_active), updated_at = ? WHERE id = ?`,
    name ?? null, monthly_price ?? null, discount_pct ?? null, discount_applies_to ?? null,
    benefits ? JSON.stringify(benefits) : null, color ?? null, sort_order ?? null,
    is_active ?? null, now(), id
  );

  const tier = await adb.get<AnyRow>('SELECT * FROM membership_tiers WHERE id = ?', id);
  res.json({ success: true, data: tier });
}));

router.delete('/tiers/:id', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);

  // Soft delete — don't remove active subscriptions
  await adb.run('UPDATE membership_tiers SET is_active = 0, updated_at = ? WHERE id = ?', now(), id);
  res.json({ success: true, data: { deleted: true } });
}));

// ── Customer Membership ──────────────────────────────────────────────

router.get('/customer/:customerId', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const customerId = parseInt(req.params.customerId as string, 10);

  const subscription = await adb.get<AnyRow>(`
    SELECT cs.*, mt.name AS tier_name, mt.monthly_price, mt.discount_pct,
           mt.discount_applies_to, mt.benefits, mt.color
    FROM customer_subscriptions cs
    JOIN membership_tiers mt ON mt.id = cs.tier_id
    WHERE cs.customer_id = ? AND cs.status IN ('active', 'past_due')
    ORDER BY cs.created_at DESC LIMIT 1
  `, customerId);

  if (subscription?.benefits) {
    subscription.benefits = JSON.parse(subscription.benefits);
  }

  res.json({ success: true, data: subscription || null });
}));

// ── Subscribe ────────────────────────────────────────────────────────

router.post('/subscribe', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;
  const { customer_id, tier_id, blockchyp_token, signature_file } = req.body;

  if (!customer_id || !tier_id) {
    res.status(400).json({ success: false, message: 'customer_id and tier_id required' });
    return;
  }

  const customer = await adb.get<AnyRow>('SELECT id, first_name, last_name FROM customers WHERE id = ? AND is_deleted = 0', customer_id);
  if (!customer) {
    res.status(404).json({ success: false, message: 'Customer not found' });
    return;
  }

  const tier = await adb.get<AnyRow>('SELECT * FROM membership_tiers WHERE id = ? AND is_active = 1', tier_id);
  if (!tier) {
    res.status(404).json({ success: false, message: 'Membership tier not found' });
    return;
  }

  // Check for existing active subscription
  const existing = await adb.get<AnyRow>(
    "SELECT id FROM customer_subscriptions WHERE customer_id = ? AND status IN ('active', 'past_due')",
    customer_id
  );
  if (existing) {
    res.status(409).json({ success: false, message: 'Customer already has an active membership' });
    return;
  }

  // Calculate period
  const start = now();
  const endDate = new Date();
  endDate.setMonth(endDate.getMonth() + 1);
  const end = endDate.toISOString().replace('T', ' ').substring(0, 19);

  const result = await adb.run(
    `INSERT INTO customer_subscriptions (customer_id, tier_id, blockchyp_token, status,
     current_period_start, current_period_end, signature_file, last_charge_at, last_charge_amount)
     VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?)`,
    customer_id, tier_id, blockchyp_token || null, start, end,
    signature_file || null, start, tier.monthly_price
  );

  // Update customer quick-lookup
  await adb.run('UPDATE customers SET active_subscription_id = ? WHERE id = ?', result.lastInsertRowid, customer_id);

  // Record first payment
  await adb.run(
    'INSERT INTO subscription_payments (subscription_id, amount, status) VALUES (?, ?, ?)',
    result.lastInsertRowid, tier.monthly_price, 'success'
  );

  audit(db, 'membership_subscribed', req.user!.id, req.ip || 'unknown', {
    customer_id, tier_id, tier_name: tier.name, amount: tier.monthly_price,
  });

  const subscription = await adb.get<AnyRow>('SELECT * FROM customer_subscriptions WHERE id = ?', result.lastInsertRowid);
  res.status(201).json({ success: true, data: subscription });
}));

// ── Cancel / Pause / Resume ──────────────────────────────────────────

router.post('/:id/cancel', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  const { immediate } = req.body;

  if (immediate) {
    await adb.run("UPDATE customer_subscriptions SET status = 'cancelled', updated_at = ? WHERE id = ?", now(), id);
    const sub = await adb.get<AnyRow>('SELECT customer_id FROM customer_subscriptions WHERE id = ?', id);
    if (sub) await adb.run('UPDATE customers SET active_subscription_id = NULL WHERE id = ?', sub.customer_id);
  } else {
    await adb.run('UPDATE customer_subscriptions SET cancel_at_period_end = 1, updated_at = ? WHERE id = ?', now(), id);
  }

  audit(req.db, 'membership_cancelled', req.user!.id, req.ip || 'unknown', { subscription_id: id, immediate: !!immediate });
  res.json({ success: true, data: { cancelled: true, immediate: !!immediate } });
}));

router.post('/:id/pause', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  await adb.run("UPDATE customer_subscriptions SET status = 'paused', pause_reason = ?, updated_at = ? WHERE id = ?",
    req.body.reason || null, now(), id);
  res.json({ success: true, data: { paused: true } });
}));

router.post('/:id/resume', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  await adb.run("UPDATE customer_subscriptions SET status = 'active', pause_reason = NULL, updated_at = ? WHERE id = ?", now(), id);
  res.json({ success: true, data: { resumed: true } });
}));

// ── Payment History ──────────────────────────────────────────────────

router.get('/:id/payments', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  const payments = await adb.all<AnyRow>(
    'SELECT * FROM subscription_payments WHERE subscription_id = ? ORDER BY created_at DESC',
    id
  );
  res.json({ success: true, data: payments });
}));

// ── All Active Subscriptions (for admin) ─────────────────────────────

router.get('/subscriptions', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const subs = await adb.all<AnyRow>(`
    SELECT cs.*, mt.name AS tier_name, mt.monthly_price, mt.color,
           c.first_name, c.last_name, c.phone, c.email
    FROM customer_subscriptions cs
    JOIN membership_tiers mt ON mt.id = cs.tier_id
    JOIN customers c ON c.id = cs.customer_id
    WHERE cs.status IN ('active', 'past_due', 'paused')
    ORDER BY cs.created_at DESC
  `);
  res.json({ success: true, data: subs });
}));

// ── BlockChyp: Enroll card on terminal ───────────────────────────────

router.post('/enroll', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const db = req.db;
  const result = await enrollCard(db);

  if (!result.success) {
    res.status(400).json({ success: false, message: result.error || 'Card enrollment failed' });
    return;
  }

  res.json({
    success: true,
    data: {
      token: result.token,
      maskedPan: result.maskedPan,
      cardType: result.cardType,
    },
  });
}));

// ── BlockChyp: Generate payment link (for remote signup) ─────────────

router.post('/payment-link', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const db = req.db;
  const adb = req.asyncDb;
  const { tier_id, customer_id } = req.body;

  if (!tier_id) {
    res.status(400).json({ success: false, message: 'tier_id required' });
    return;
  }

  const tier = await adb.get<AnyRow>('SELECT * FROM membership_tiers WHERE id = ? AND is_active = 1', tier_id);
  if (!tier) {
    res.status(404).json({ success: false, message: 'Tier not found' });
    return;
  }

  const description = `${tier.name} Membership - $${tier.monthly_price}/mo`;
  const result = await createPaymentLink(db, tier.monthly_price.toFixed(2), description);

  if (!result.success) {
    res.status(400).json({ success: false, message: result.error || 'Failed to create payment link' });
    return;
  }

  res.json({
    success: true,
    data: {
      linkUrl: result.linkUrl,
      linkCode: result.linkCode,
      tier_name: tier.name,
      amount: tier.monthly_price,
    },
  });
}));

export default router;
