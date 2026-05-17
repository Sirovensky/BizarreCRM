/**
 * Membership Routes — Tier management, subscription lifecycle, BlockChyp integration.
 * All routes are per-tenant (use req.db / req.asyncDb).
 */
import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { audit } from '../utils/audit.js';
import type { TxQuery } from '../db/async-db.js';
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
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid tier id', 400);
  const { name, monthly_price, discount_pct, discount_applies_to, benefits, color, sort_order, is_active } = req.body;

  const result = await adb.run(
    `UPDATE membership_tiers SET name = COALESCE(?, name), monthly_price = COALESCE(?, monthly_price),
     discount_pct = COALESCE(?, discount_pct), discount_applies_to = COALESCE(?, discount_applies_to),
     benefits = COALESCE(?, benefits), color = COALESCE(?, color), sort_order = COALESCE(?, sort_order),
     is_active = COALESCE(?, is_active), updated_at = ? WHERE id = ?`,
    name ?? null, monthly_price ?? null, discount_pct ?? null, discount_applies_to ?? null,
    benefits ? JSON.stringify(benefits) : null, color ?? null, sort_order ?? null,
    is_active ?? null, now(), id
  );
  if (!result.changes) throw new AppError('Tier not found', 404);

  const tier = await adb.get<AnyRow>('SELECT * FROM membership_tiers WHERE id = ?', id);
  res.json({ success: true, data: tier });
}));

router.delete('/tiers/:id', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid tier id', 400);

  // Soft delete — don't remove active subscriptions
  const result = await adb.run('UPDATE membership_tiers SET is_active = 0, updated_at = ? WHERE id = ?', now(), id);
  if (!result.changes) throw new AppError('Tier not found', 404);
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

// WEB-UIUX-1493: list every subscription a customer has ever had, including
// cancelled / paused rows. The active /customer/:id endpoint above filters
// to status IN ('active', 'past_due'); after an immediate cancel that
// returns null and the CustomerDetailPage membership card vanishes,
// losing tier/tenure/last-charge context. This endpoint lets the UI
// render a "past memberships" section with churn dates + cancellation
// reason (WEB-UIUX-1067 column) for retention review.
router.get('/customer/:customerId/history', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const customerId = parseInt(req.params.customerId as string, 10);
  if (!Number.isFinite(customerId)) throw new AppError('Invalid customer id', 400);
  const rows = await adb.all<AnyRow>(`
    SELECT cs.id, cs.tier_id, cs.status, cs.cancel_at_period_end,
           cs.cancellation_reason, cs.cancellation_note,
           cs.created_at, cs.updated_at, cs.current_period_start, cs.current_period_end,
           cs.last_charge_at, cs.last_charge_amount, cs.paused_at, cs.pause_reason,
           mt.name AS tier_name, mt.monthly_price, mt.color
      FROM customer_subscriptions cs
      JOIN membership_tiers mt ON mt.id = cs.tier_id
     WHERE cs.customer_id = ?
     ORDER BY cs.created_at DESC
  `, customerId);
  res.json({ success: true, data: rows });
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

  // Calculate period — handle month-end boundary so Jan 31 + 1 month doesn't
  // overflow to Mar 3. If the resulting day is less than the original day,
  // clamp to the last day of the previous (intended) month.
  const start = now();
  const endDate = new Date();
  const originalDay = endDate.getUTCDate();
  endDate.setUTCMonth(endDate.getUTCMonth() + 1);
  if (endDate.getUTCDate() !== originalDay) {
    endDate.setUTCDate(0);
  }
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
      // BUGHUNT-2026-05-17: atomically cancel the subscription + log the
      // failure. Previously these were two adb.run() calls in sequence; if
      // the second crashed, the subscription was 'cancelled' with no
      // matching subscription_payments row, so analytics / reconciliation
      // couldn't see WHY the customer was cancelled (lost MRR-churn reason).
      await adb.transaction([
        {
          sql: `UPDATE customer_subscriptions
                   SET status = 'cancelled',
                       updated_at = ?
                 WHERE id = ?`,
          params: [now(), subscriptionId],
        },
        {
          sql: 'INSERT INTO subscription_payments (subscription_id, amount, status, error_message, payment_provider) VALUES (?, ?, ?, ?, ?)',
          params: [subscriptionId, monthlyPrice, 'failed', chargeResult.error || 'Payment declined', 'blockchyp'],
        },
      ]);
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

// WEB-UIUX-1067: allow-listed cancellation reasons mirror the industry-standard
// MRR-churn taxonomy (Stripe/Recurly/ChartMogul). 'other' lets the operator
// store an unstructured note when none of the buckets fit; bucket choice still
// gives the analytics layer something to GROUP BY.
const CANCELLATION_REASONS = new Set([
  'too_expensive',
  'missing_features',
  'switched_service',
  'low_value',
  'customer_service',
  'business_closed',
  'no_longer_needed',
  'other',
]);

router.post('/:id/cancel', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  const { immediate, reason, note } = req.body as { immediate?: boolean; reason?: string; note?: string };

  // WEB-UIUX-1067: validate reason against the allow-list; ignore unknown
  // values so a stale client doesn't poison the analytics column with
  // free-form strings. Note caps at 500 chars to mirror the discount_reason
  // / refund_reason ceiling.
  const cleanReason = typeof reason === 'string' && CANCELLATION_REASONS.has(reason) ? reason : null;
  const cleanNote = typeof note === 'string' ? note.trim().slice(0, 500) || null : null;

  // WEB-UIUX-1499: when immediate cancel runs against a subscription that the
  // customer has already paid for the current period, post a prorated store
  // credit so they aren't left short. Computed as
  //   (remaining_seconds / period_seconds) * last_charge_amount
  // rounded to 2dp. Store credit (not cash refund) so the operator isn't
  // forced into a tender choice at cancel time; customer can spend the
  // credit on a future invoice or escalate to a manual refund manually.
  // Skipped when sub was never charged, period already ended, or
  // last_charge_amount is 0/null (free tier).
  let prorationAmount = 0;
  let prorationCreditId: number | null = null;

  if (immediate) {
    const subBeforeCancel = await adb.get<AnyRow>(
      `SELECT customer_id, current_period_start, current_period_end, last_charge_amount
         FROM customer_subscriptions WHERE id = ?`,
      id,
    );
    if (subBeforeCancel) {
      const lastCharge = Number((subBeforeCancel as AnyRow).last_charge_amount) || 0;
      const startStr = (subBeforeCancel as AnyRow).current_period_start as string | null;
      const endStr = (subBeforeCancel as AnyRow).current_period_end as string | null;
      // BUGHUNT-2026-05-16: SQLite stores period boundaries as
      // 'YYYY-MM-DD HH:MM:SS' (no 'Z' suffix). Node.js parses that as
      // `Invalid Date` (unlike browsers), so both startMs/endMs were NaN
      // and Number.isFinite always false — proration silently dead, and
      // cancelling customers never received the partial-period credit
      // note they were owed.
      const normalize = (v: string): string =>
        v.includes('T') || v.endsWith('Z') || v.includes('+') ? v : `${v.replace(' ', 'T')}Z`;
      const startMs = startStr ? new Date(normalize(startStr)).getTime() : NaN;
      const endMs = endStr ? new Date(normalize(endStr)).getTime() : NaN;
      const nowMs = Date.now();
      if (
        lastCharge > 0
        && Number.isFinite(startMs)
        && Number.isFinite(endMs)
        && endMs > nowMs
        && endMs > startMs
      ) {
        const remaining = endMs - nowMs;
        const period = endMs - startMs;
        prorationAmount = Math.round((remaining / period) * lastCharge * 100) / 100;
        if (prorationAmount > 0) {
          const customerId = Number((subBeforeCancel as AnyRow).customer_id);
          // BUGHUNT-2026-05-17: bundle the store_credits UPSERT + the
          // store_credit_transactions ledger row so the credit balance and
          // the audit trail land together. (Cancellation UPDATEs follow as
          // a second batch below; doing both as one would force us to merge
          // the optional-proration branch with the always-on UPDATEs and
          // make the query list awkward to read — accept the small window
          // between the credit and the status flip in exchange for clarity.)
          const credTxResults = await adb.transaction([
            {
              sql: `INSERT INTO store_credits (customer_id, amount, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(customer_id) DO UPDATE
                      SET amount = amount + excluded.amount,
                          updated_at = excluded.updated_at`,
              params: [customerId, prorationAmount, now(), now()],
            },
            {
              sql: `INSERT INTO store_credit_transactions
                      (customer_id, amount, type, reference_type, reference_id, notes, user_id, created_at)
                    VALUES (?, ?, 'credit', 'subscription_cancellation', ?, ?, ?, ?)`,
              params: [
                customerId,
                prorationAmount,
                id,
                `Prorated refund for unused days on subscription #${id}`,
                req.user!.id,
                now(),
              ],
            },
          ]);
          prorationCreditId = Number(credTxResults[1].lastInsertRowid);
          audit(req.db, 'subscription_proration_credited', req.user!.id, req.ip || 'unknown', {
            subscription_id: id,
            customer_id: customerId,
            amount: prorationAmount,
            credit_transaction_id: prorationCreditId,
            period_start: startStr,
            period_end: endStr,
            last_charge_amount: lastCharge,
          });
        }
      }
    }

    // BUGHUNT-2026-05-17: bundle the subscription cancel + the
    // customers.active_subscription_id clear so the customer never appears as
    // having an active subscription whose row is in 'cancelled' state (the
    // resubscribe code path keys off active_subscription_id and would refuse
    // a rejoin if this UPDATE crashed before the customers UPDATE).
    const customerIdFromSub = (subBeforeCancel as AnyRow | undefined)?.customer_id as number | undefined;
    const cancelTxQueries: TxQuery[] = [
      {
        sql: `UPDATE customer_subscriptions
                 SET status = 'cancelled',
                     auto_renew = 0,
                     next_billing_attempt_at = NULL,
                     cancellation_reason = ?,
                     cancellation_note = ?,
                     updated_at = ?
               WHERE id = ?`,
        params: [cleanReason, cleanNote, now(), id],
      },
    ];
    if (customerIdFromSub) {
      cancelTxQueries.push({
        sql: 'UPDATE customers SET active_subscription_id = NULL WHERE id = ?',
        params: [customerIdFromSub],
      });
    }
    await adb.transaction(cancelTxQueries);
  } else {
    await adb.run(
      `UPDATE customer_subscriptions
          SET cancel_at_period_end = 1,
              auto_renew = 0,
              next_billing_attempt_at = NULL,
              cancellation_reason = ?,
              cancellation_note = ?,
              updated_at = ?
        WHERE id = ?`,
      cleanReason,
      cleanNote,
      now(),
      id,
    );
  }

  audit(req.db, 'membership_cancelled', req.user!.id, req.ip || 'unknown', {
    subscription_id: id,
    immediate: !!immediate,
    reason: cleanReason,
    note: cleanNote,
  });
  res.json({
    success: true,
    data: {
      cancelled: true,
      immediate: !!immediate,
      reason: cleanReason,
      // WEB-UIUX-1499: surface the prorated credit so the cancel toast can
      // tell the operator exactly how much landed on the customer's store
      // credit. 0 = no proration (free tier, ended period, never charged).
      proration_credit: prorationAmount > 0
        ? { amount: prorationAmount, credit_transaction_id: prorationCreditId }
        : null,
    },
  });
}));

// WEB-UIUX-828: change-tier so operators don't have to cancel + re-subscribe
// (which loses tenure, triggers two audit rows, and refuses the customer
// any in-flight grandfathered pricing). Admin only. The new tier id must
// reference an active membership_tiers row. Status stays as-is (does not
// re-activate a cancelled sub — use /subscribe for that). next_billing_attempt_at
// untouched so the upcoming renewal fires at the new tier's monthly_price.
router.post('/:id/change-tier', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid subscription id', 400);

  const newTierIdRaw = req.body?.tier_id;
  const newTierId = Number(newTierIdRaw);
  if (!Number.isFinite(newTierId) || newTierId <= 0) {
    throw new AppError('tier_id required (positive integer)', 400);
  }
  const noteRaw = typeof req.body?.note === 'string' ? req.body.note.trim().slice(0, 500) : '';

  const sub = await adb.get<AnyRow>(
    'SELECT id, tier_id, status FROM customer_subscriptions WHERE id = ?',
    id,
  );
  if (!sub) throw new AppError('Subscription not found', 404);
  if (sub.status === 'cancelled') {
    throw new AppError('Cannot change tier on a cancelled subscription. Use /subscribe for re-enrolment.', 409);
  }
  if (Number(sub.tier_id) === newTierId) {
    throw new AppError('Subscription is already on this tier.', 409);
  }
  const newTier = await adb.get<AnyRow>(
    'SELECT id, name, is_active FROM membership_tiers WHERE id = ?',
    newTierId,
  );
  if (!newTier) throw new AppError('Target tier not found', 404);
  if (Number(newTier.is_active) !== 1) {
    throw new AppError('Target tier is not active', 400);
  }

  // BUGHUNT-2026-05-17: guard the UPDATE WHERE tier_id matches the
  // snapshot AND status != 'cancelled'. Without this, two concurrent
  // change-tier calls both pass the SELECT precheck and the second
  // writer silently overrides the first — the audit log records an
  // A->B transition that never persisted. Also blocks a tier change
  // racing with a /cancel from quietly mutating a cancelled sub's
  // tier_id without affecting status.
  const tierUpdate = await adb.run(
    "UPDATE customer_subscriptions SET tier_id = ?, updated_at = ? WHERE id = ? AND tier_id = ? AND status != 'cancelled'",
    newTierId, now(), id, sub.tier_id,
  );
  if (tierUpdate.changes === 0) {
    throw new AppError('Subscription state changed; refresh and retry', 409);
  }

  audit(req.db, 'membership_tier_changed', req.user!.id, req.ip || 'unknown', {
    subscription_id: id,
    prev_tier_id: Number(sub.tier_id),
    new_tier_id: newTierId,
    new_tier_name: newTier.name,
    note: noteRaw || null,
  });

  const updated = await adb.get<AnyRow>(
    `SELECT cs.*, mt.name AS tier_name, mt.monthly_price, mt.discount_pct,
            mt.discount_applies_to, mt.color
       FROM customer_subscriptions cs
       JOIN membership_tiers mt ON mt.id = cs.tier_id
      WHERE cs.id = ?`,
    id,
  );
  res.json({ success: true, data: updated });
}));

router.post('/:id/pause', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid subscription id', 400);
  // BUGHUNT-2026-05-17: guard the UPDATE WHERE status NOT IN
  // ('cancelled','paused'). Without this, /pause silently flips a
  // cancelled subscription back to 'paused', which the /resume guard
  // then happily revives to 'active' — bypassing the cancellation
  // invariant noted in /resume's comment (customers.active_subscription_id
  // was nulled by the immediate-cancel path, so an 'active' sub against
  // a null active_subscription_id is an unrecoverable inconsistency).
  const result = await adb.run("UPDATE customer_subscriptions SET status = 'paused', pause_reason = ?, auto_renew = 0, next_billing_attempt_at = NULL, updated_at = ? WHERE id = ? AND status NOT IN ('cancelled','paused')",
    req.body.reason || null, now(), id);
  if (!result.changes) {
    const existing = await adb.get<AnyRow>('SELECT status FROM customer_subscriptions WHERE id = ?', id);
    if (!existing) throw new AppError('Subscription not found', 404);
    throw new AppError(`Subscription is ${existing.status}; cannot pause`, 409);
  }
  res.json({ success: true, data: { paused: true } });
}));

router.post('/:id/resume', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  // WEB-UIUX-1491: cancelled subscriptions cannot be resumed — the immediate-cancel
  // path nulls customers.active_subscription_id, so silently flipping status back
  // to 'active' would leave cs.status='active' AND customers.active_subscription_id=NULL,
  // an unrecoverable inconsistency (POS won't apply membership discount, customer-detail
  // hides the card). UI already hides Resume for cancelled rows; this is the server-side
  // matching guard. Operator who wants the customer back must enroll a fresh subscription.
  const current = await adb.get<AnyRow>(
    'SELECT status FROM customer_subscriptions WHERE id = ?',
    id,
  );
  if (!current) {
    throw new AppError('Subscription not found', 404);
  }
  if (current.status === 'cancelled') {
    throw new AppError('Cancelled subscriptions cannot be resumed; enroll the customer in a new subscription instead.', 409);
  }
  // BUGHUNT-2026-05-17: guard the UPDATE WHERE status != 'cancelled'.
  // The SELECT precheck above is TOCTOU — a concurrent cancellation
  // could flip the sub to 'cancelled' between the read and the write,
  // and the unguarded UPDATE would silently revive it. Per the comment
  // above, cancelled→active leaves an unrecoverable inconsistency
  // (customers.active_subscription_id is already NULL by then).
  const result = await adb.run(
    `UPDATE customer_subscriptions
        SET status = 'active',
            pause_reason = NULL,
            auto_renew = 1,
            cancel_at_period_end = 0,
            billing_suspended_at = NULL,
            updated_at = ?
      WHERE id = ? AND status != 'cancelled'`,
    now(),
    id,
  );
  if (!result.changes) {
    throw new AppError('Subscription was cancelled concurrently; enroll the customer in a new subscription instead.', 409);
  }
  res.json({ success: true, data: { resumed: true } });
}));

// ── Payment History ──────────────────────────────────────────────────

router.get('/:id/payments', asyncHandler(async (req: Request, res: Response) => {
  // SEC: gate behind requireAdmin to match the rest of this billing-history
  // surface. Without this any authenticated user could enumerate every
  // subscription's payment ledger (amounts, methods, transaction ids).
  requireAdmin(req);
  const adb = req.asyncDb;
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid subscription id', 400);
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
  // WEB-UIUX-1500: optional ?include_cancelled=1 surfaces churn history so the
  // admin can answer "did Anya cancel last week or did her card decline?"
  // without reading audit_logs. Default behaviour (active/past_due/paused) is
  // unchanged so existing callers see no shift.
  const includeCancelled = String(req.query.include_cancelled ?? '').trim() === '1';
  const statuses = includeCancelled
    ? ['active', 'past_due', 'paused', 'cancelled']
    : ['active', 'past_due', 'paused'];
  const placeholders = statuses.map(() => '?').join(', ');
  const subs = await adb.all<AnyRow>(`
    SELECT cs.*, mt.name AS tier_name, mt.monthly_price, mt.color,
           c.first_name, c.last_name, c.phone, c.email
    FROM customer_subscriptions cs
    JOIN membership_tiers mt ON mt.id = cs.tier_id
    JOIN customers c ON c.id = cs.customer_id
    WHERE cs.status IN (${placeholders})
    ORDER BY cs.created_at DESC
  `, ...statuses);
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

// WEB-UIUX-1069: distinct "Retry payment" semantic for past-due subs.
// Functionally similar to /run-billing but gated on the subscription
// being in 'past_due' status so the UI can wire a Retry button that's
// safe to expose to operators outside the admin's bill-now-token path.
// `force=true` is implicit because past_due means the renewal already
// failed at least once.
router.post('/:id/retry-payment', asyncHandler(async (req: Request, res: Response) => {
  requireMembershipsFeature(req);
  requireAdmin(req);
  const db = req.db;
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid subscription id', 400);
  const sub = loadMembershipBillingSubscription(db, id);
  if (!sub) throw new AppError('Subscription not found', 404);
  if ((sub as any).status !== 'past_due') {
    throw new AppError(
      `Retry payment only applies to past-due subscriptions (current status: ${(sub as any).status}). Use /run-billing for a normal bill-now.`,
      409,
    );
  }
  const result = await billMembershipSubscription(db, sub, {
    userId: req.user!.id,
    ip: req.ip || 'unknown',
    force: true,
    source: 'retry_past_due',
  });
  if (result.status !== 'success') {
    throw new AppError(result.message, result.httpStatus ?? 400);
  }
  const updated = await req.asyncDb.get<AnyRow>('SELECT * FROM customer_subscriptions WHERE id = ?', id);
  audit(req.db, 'membership_retry_payment', req.user!.id, req.ip || 'unknown', {
    subscription_id: id,
    new_status: (updated as any)?.status ?? null,
  });
  res.json({ success: true, data: { subscription: updated, result } });
}));

export default router;
