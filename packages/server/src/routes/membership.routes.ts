/**
 * Membership Routes — Tier management, subscription lifecycle, BlockChyp integration.
 * All routes are per-tenant (use req.db / req.asyncDb).
 */
import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { audit } from '../utils/audit.js';
import { enrollCard, createPaymentLink, chargeToken, isBlockChypEnabled, verifyCustomerToken } from '../services/blockchyp.js';
import { config } from '../config.js';
import { isFeatureAllowed } from '@bizarre-crm/shared';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { formatCurrency, getStoreLocale } from '../utils/format.js';
import {
  billMembershipSubscription,
  loadMembershipBillingSubscription,
  runMembershipBillingOnce,
} from '../services/membershipBilling.js';

const router = Router();
type AnyRow = Record<string, any>;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function safeJsonParseArray(s: string | null | undefined): unknown[] {
  if (!s) return [];
  try {
    const v = JSON.parse(s);
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

function normalizeBlockChypToken(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const token = value.trim();
  if (!token) return null;
  if (token.length > 512 || /[\x00-\x1F\x7F]/.test(token)) {
    throw new AppError('Invalid BlockChyp payment token', 400);
  }
  return token;
}

// SEC (PL6): Every write/billing route here must verify the actor is an admin,
// regardless of whatever middleware the router is mounted under. Relying on
// the mount point means a future routing refactor can silently expose tier
// creation / subscription lifecycle / payment-link generation to clerks.
function requireAdmin(req: Request): void {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
}

// POST-ENRICH AUDIT §23.3 (PL6 defense-in-depth): the router is mounted
// behind `requireFeature('memberships')` in index.ts. The prior audit called
// router-level gating brittle because a middleware reorder can silently open
// this file to Free-tier tenants. Mirror the feature gate inside each write
// handler so a routing refactor cannot bypass it. We leave reads open so a
// Free-tier admin can still load tier definitions and see what Pro unlocks.
function requireMembershipsFeature(req: Request): void {
  if (!config.multiTenant) return;
  const plan = req.tenantPlan;
  if (!plan || !isFeatureAllowed(plan, 'memberships')) {
    throw new AppError('memberships require Pro', 402);
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
    benefits: safeJsonParseArray(t.benefits),
  }));
  res.json({ success: true, data: shaped });
}));

router.post('/tiers', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
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
  requireMembershipsFeature(req);
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
  requireMembershipsFeature(req);
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

  if (subscription) {
    subscription.benefits = safeJsonParseArray(subscription.benefits);
  }

  res.json({ success: true, data: subscription || null });
}));

// ── Subscribe ────────────────────────────────────────────────────────

router.post('/subscribe', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const db = req.db;
  const { customer_id, tier_id, blockchyp_token, signature_file } = req.body;
  const normalizedToken = normalizeBlockChypToken(blockchyp_token);

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
  const monthlyPrice = Number(tier.monthly_price);
  if (!Number.isFinite(monthlyPrice) || monthlyPrice < 0) {
    throw new AppError('Invalid membership tier price', 400);
  }

  const isPaidTier = monthlyPrice > 0;
  if (isPaidTier && !normalizedToken) {
    throw new AppError('Paid memberships require a reusable BlockChyp payment token', 400);
  }
  if (isPaidTier && !isBlockChypEnabled(db)) {
    throw new AppError('BlockChyp is not configured for this tenant', 503);
  }

  const existingLiveSubscription = await adb.get<AnyRow>(
    `SELECT id
       FROM customer_subscriptions
      WHERE customer_id = ?
        AND status IN ('active', 'past_due')
      LIMIT 1`,
    customer_id,
  );
  if (existingLiveSubscription) {
    res.status(409).json({ success: false, message: 'Customer already has an active subscription' });
    return;
  }

  if (isPaidTier) {
    const verification = await verifyCustomerToken(db, normalizedToken!);
    if (!verification.success) {
      audit(db, 'membership_blockchyp_token_verification_failed', req.user!.id, req.ip || 'unknown', {
        customer_id,
        tier_id,
        error: verification.error,
        response_description: verification.responseDescription,
      });
      throw new AppError(verification.error || 'BlockChyp payment token could not be verified', 400);
    }

    audit(db, 'membership_blockchyp_token_verification_success', req.user!.id, req.ip || 'unknown', {
      customer_id,
      tier_id,
      card_type: verification.cardType,
      masked_pan: verification.maskedPan,
      response_description: verification.responseDescription,
    });
  }

  // Calculate period
  const start = now();
  const endDate = new Date();
  endDate.setMonth(endDate.getMonth() + 1);
  const end = endDate.toISOString().replace('T', ' ').substring(0, 19);

  // WEB-UIUX-1071: prefer reactivating an existing cancelled row over
  // creating a new one. Stripe pattern: a customer who churns and returns
  // gets one row in the subscriptions table with full payment_history, not
  // two rows that LTV/dunning reports must `GROUP BY customer_id` to merge.
  // We pick the most recently cancelled row for this customer; if found we
  // UPDATE it in place (preserving id + history), otherwise INSERT new.
  const reactivatable = await adb.get<AnyRow>(
    `SELECT id FROM customer_subscriptions
      WHERE customer_id = ?
        AND status = 'cancelled'
      ORDER BY id DESC LIMIT 1`,
    customer_id,
  );

  // The UNIQUE partial index idx_customer_subscriptions_active_unique on
  // customer_subscriptions(customer_id) WHERE status IN ('active','past_due')
  // (migration 110) is the authoritative guard against concurrent duplicates.
  // A racing second INSERT hits the index and raises SQLITE_CONSTRAINT_UNIQUE,
  // which we catch here and surface as 409 Conflict.
  let result: Awaited<ReturnType<typeof adb.run>>;
  let subscriptionId: number;
  let reactivated = false;
  if (reactivatable) {
    try {
      await adb.run(
        `UPDATE customer_subscriptions
            SET tier_id = ?, blockchyp_token = ?, status = 'active',
                current_period_start = ?, current_period_end = ?,
                signature_file = COALESCE(?, signature_file),
                last_charge_at = ?, last_charge_amount = ?, payment_provider = ?,
                cancelled_at = NULL, paused_at = NULL, pause_reason = NULL,
                updated_at = ?
          WHERE id = ?`,
        tier_id,
        normalizedToken,
        start,
        end,
        signature_file || null,
        isPaidTier ? null : start,
        isPaidTier ? null : monthlyPrice,
        isPaidTier ? 'blockchyp' : 'none',
        now(),
        reactivatable.id,
      );
    } catch (err: unknown) {
      if (err instanceof Error && /UNIQUE constraint/i.test(err.message)) {
        res.status(409).json({ success: false, message: 'Customer already has an active subscription' });
        return;
      }
      throw err;
    }
    subscriptionId = Number(reactivatable.id);
    reactivated = true;
    result = { lastInsertRowid: subscriptionId } as any;
  } else {
    try {
      result = await adb.run(
        `INSERT INTO customer_subscriptions (customer_id, tier_id, blockchyp_token, status,
         current_period_start, current_period_end, signature_file, last_charge_at, last_charge_amount, payment_provider)
         VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?)`,
        customer_id, tier_id, normalizedToken, start, end,
        signature_file || null, isPaidTier ? null : start, isPaidTier ? null : monthlyPrice,
        isPaidTier ? 'blockchyp' : 'none',
      );
    } catch (err: unknown) {
      if (err instanceof Error && /UNIQUE constraint/i.test(err.message)) {
        res.status(409).json({ success: false, message: 'Customer already has an active subscription' });
        return;
      }
      throw err;
    }
    subscriptionId = Number(result.lastInsertRowid);
  }
  audit(db, reactivated ? 'membership_reactivated' : 'membership_subscribed', req.user!.id, req.ip || 'unknown', {
    customer_id,
    tier_id,
    subscription_id: subscriptionId,
    reactivated,
  });
  let initialTransactionId: string | null = null;

  if (isPaidTier) {
    const chargeResult = await chargeToken(
      db,
      normalizedToken!,
      monthlyPrice.toFixed(2),
      `${tier.name} Membership activation`,
    );

    if (!chargeResult.success) {
      await adb.run(
        `UPDATE customer_subscriptions
            SET status = 'cancelled',
                updated_at = ?
          WHERE id = ?`,
        now(),
        subscriptionId,
      );
      await adb.run(
        'INSERT INTO subscription_payments (subscription_id, amount, status, error_message, payment_provider) VALUES (?, ?, ?, ?, ?)',
        subscriptionId,
        monthlyPrice,
        'failed',
        chargeResult.error || 'Payment declined',
        'blockchyp',
      );
      audit(db, 'membership_initial_charge_failed', req.user!.id, req.ip || 'unknown', {
        subscription_id: subscriptionId,
        customer_id,
        tier_id,
        amount: monthlyPrice,
        error: chargeResult.error,
      });
      throw new AppError(chargeResult.error || 'Payment declined', 402);
    }

    initialTransactionId = chargeResult.transactionId ?? null;
  }

  const activationStamp = now();
  await adb.transaction([
    {
      sql: `UPDATE customer_subscriptions
               SET last_charge_at = ?,
                   last_charge_amount = ?,
                   updated_at = ?
             WHERE id = ?`,
      params: [activationStamp, monthlyPrice, activationStamp, subscriptionId],
    },
    {
      sql: 'UPDATE customers SET active_subscription_id = ? WHERE id = ?',
      params: [subscriptionId, customer_id],
    },
    {
      sql: 'INSERT INTO subscription_payments (subscription_id, amount, status, blockchyp_transaction_id, payment_provider, processor_transaction_id) VALUES (?, ?, ?, ?, ?, ?)',
      params: [
        subscriptionId,
        monthlyPrice,
        'success',
        isPaidTier ? initialTransactionId : null,
        isPaidTier ? 'blockchyp' : 'none',
        initialTransactionId,
      ],
    },
  ]);

  if (isPaidTier) {
    audit(db, 'membership_initial_charge_success', req.user!.id, req.ip || 'unknown', {
      subscription_id: subscriptionId,
      customer_id,
      tier_id,
      amount: monthlyPrice,
      transaction_id: initialTransactionId,
    });
  }

  audit(db, 'membership_subscribed', req.user!.id, req.ip || 'unknown', {
    customer_id, tier_id, tier_name: tier.name, amount: monthlyPrice,
    has_blockchyp_token: !!normalizedToken,
    transaction_id: initialTransactionId,
  });

  const subscription = await adb.get<AnyRow>('SELECT * FROM customer_subscriptions WHERE id = ?', subscriptionId);
  res.status(201).json({ success: true, data: subscription });
}));

// ── Cancel / Pause / Resume ──────────────────────────────────────────

router.post('/:id/cancel', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  const { immediate } = req.body;

  if (immediate) {
    await adb.run(
      `UPDATE customer_subscriptions
          SET status = 'cancelled',
              auto_renew = 0,
              next_billing_attempt_at = NULL,
              updated_at = ?
        WHERE id = ?`,
      now(),
      id,
    );
    const sub = await adb.get<AnyRow>('SELECT customer_id FROM customer_subscriptions WHERE id = ?', id);
    if (sub) await adb.run('UPDATE customers SET active_subscription_id = NULL WHERE id = ?', sub.customer_id);
  } else {
    await adb.run(
      `UPDATE customer_subscriptions
          SET cancel_at_period_end = 1,
              auto_renew = 0,
              next_billing_attempt_at = NULL,
              updated_at = ?
        WHERE id = ?`,
      now(),
      id,
    );
  }

  audit(req.db, 'membership_cancelled', req.user!.id, req.ip || 'unknown', { subscription_id: id, immediate: !!immediate });
  res.json({ success: true, data: { cancelled: true, immediate: !!immediate } });
}));

router.post('/:id/pause', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  await adb.run("UPDATE customer_subscriptions SET status = 'paused', pause_reason = ?, auto_renew = 0, next_billing_attempt_at = NULL, updated_at = ? WHERE id = ?",
    req.body.reason || null, now(), id);
  res.json({ success: true, data: { paused: true } });
}));

router.post('/:id/resume', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  await adb.run(
    `UPDATE customer_subscriptions
        SET status = 'active',
            pause_reason = NULL,
            auto_renew = 1,
            cancel_at_period_end = 0,
            billing_suspended_at = NULL,
            updated_at = ?
      WHERE id = ?`,
    now(),
    id,
  );
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
  requireAdmin(req);
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
  requireMembershipsFeature(req);
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

// ── Billing Run Controls ─────────────────────────────────────────────

router.post('/run-billing', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const user = req.user!;
  const limitRaw = Number(req.body?.limit ?? 100);
  const limit = Number.isInteger(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 500) : 100;
  const result = await runMembershipBillingOnce(req.db, {
    mode: 'manual',
    source: 'manual_global',
    startedBy: user.id,
    ip: req.ip || 'unknown',
    limit,
  });

  if (result.skipped) {
    res.status(409).json({
      success: false,
      message: result.message || 'Membership billing run skipped',
      data: { run: result.run },
    });
    return;
  }

  res.json({ success: true, data: { run: result.run, results: result.results } });
}));

router.get('/billing-runs/latest', asyncHandler(async (req: Request, res: Response) => {
  requireAdmin(req);
  const run = await req.asyncDb.get<AnyRow>(
    'SELECT * FROM membership_billing_runs ORDER BY started_at DESC, id DESC LIMIT 1',
  );
  res.json({ success: true, data: run || null });
}));

// ── BlockChyp: Generate payment link (for remote signup) ─────────────

router.post('/payment-link', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
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

  const { currency } = getStoreLocale(db);
  const description = `${tier.name} Membership - ${formatCurrency(Number(tier.monthly_price), currency)}/mo`;
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

// ─── WEB-W3-020 / WEB-UNWIRED-035: per-row immediate billing ─────────
router.post('/:id/run-billing', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const db = req.db;
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid subscription id', 400);
  const force = req.query.force === '1' || req.body?.force === true;
  const sub = loadMembershipBillingSubscription(db, id);
  if (!sub) throw new AppError('Subscription not found', 404);

  const result = await billMembershipSubscription(db, sub, {
    userId: req.user!.id,
    ip: req.ip || 'unknown',
    force,
    source: 'manual_single',
  });

  if (result.status !== 'success') {
    throw new AppError(result.message, result.httpStatus ?? 400);
  }

  const updated = await req.asyncDb.get<AnyRow>('SELECT * FROM customer_subscriptions WHERE id = ?', id);
  res.json({ success: true, data: { subscription: updated, result } });
}));

export default router;
