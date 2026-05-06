import type Database from 'better-sqlite3';
import { chargeToken as blockChypChargeToken, isBlockChypEnabled } from './blockchyp.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('membership-billing');

const RETRY_DELAY_DAYS = [1, 3, 7] as const;
const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 500;

export type MembershipBillingMode = 'manual' | 'cron';
export type MembershipBillingSource = 'manual_single' | 'manual_global' | 'cron';

export interface MembershipBillingSubscription {
  id: number;
  customer_id: number;
  tier_id: number;
  blockchyp_token: string | null;
  status: string;
  current_period_start: string | null;
  current_period_end: string | null;
  cancel_at_period_end: number;
  auto_renew: number;
  failed_charge_count: number;
  next_billing_attempt_at: string | null;
  billing_retry_stage: number;
  billing_suspended_at: string | null;
  payment_provider: string | null;
  monthly_price: number;
  tier_name: string;
  first_name?: string | null;
  last_name?: string | null;
  email?: string | null;
  email_opt_in?: number | null;
}

export interface MembershipChargeResult {
  success: boolean;
  transactionId?: string | null;
  authCode?: string | null;
  amount?: string | null;
  error?: string | null;
}

export interface MembershipBillingGateway {
  key: string;
  canCharge(subscription: MembershipBillingSubscription): boolean;
  unavailableReason?(db: Database.Database, subscription: MembershipBillingSubscription): string | null;
  charge(
    db: Database.Database,
    subscription: MembershipBillingSubscription,
    amount: number,
    description: string,
  ): Promise<MembershipChargeResult>;
}

export interface BillingItemResult {
  status: 'success' | 'failed' | 'skipped';
  subscription_id: number;
  customer_id: number;
  tier_id: number;
  amount: number;
  message: string;
  payment_provider?: string | null;
  transaction_id?: string | null;
  previous_period_end?: string | null;
  new_period_end?: string | null;
  next_attempt_at?: string | null;
  attempt_number?: number;
  final_failure?: boolean;
  dunning_queued?: boolean;
  httpStatus?: number;
}

export interface MembershipBillingRunRow {
  id: number;
  status: string;
  mode: string;
  started_at: string;
  finished_at: string | null;
  started_by: number | null;
  total_due: number;
  charged_count: number;
  failed_count: number;
  skipped_count: number;
  result_json: string | null;
  error_message: string | null;
  created_at: string;
  updated_at: string;
}

export interface MembershipBillingRunResult {
  run: MembershipBillingRunRow | null;
  results: BillingItemResult[];
  skipped: boolean;
  message?: string;
}

export interface BillMembershipOptions {
  force?: boolean;
  source: MembershipBillingSource;
  userId?: number | null;
  ip?: string;
  runId?: number | null;
  now?: Date;
  gateways?: MembershipBillingGateway[];
}

export interface RunMembershipBillingOptions {
  mode: MembershipBillingMode;
  source: MembershipBillingSource;
  startedBy?: number | null;
  ip?: string;
  limit?: number;
  now?: Date;
  staleAfterHours?: number;
  tenantSlug?: string | null;
  gateways?: MembershipBillingGateway[];
}

function sqliteTimestamp(date = new Date()): string {
  return date.toISOString().replace('T', ' ').slice(0, 19);
}

function parseDbTimestamp(value: string | null | undefined): Date | null {
  if (!value) return null;
  const normalized = value.includes('T') ? value : `${value.replace(' ', 'T')}Z`;
  const date = new Date(normalized);
  return Number.isFinite(date.getTime()) ? date : null;
}

function addMonthsClamped(value: string | null | undefined, count: number, fallback: Date): string {
  const base = parseDbTimestamp(value) ?? new Date(fallback.getTime());
  const originalDay = base.getUTCDate();
  base.setUTCMonth(base.getUTCMonth() + count);
  if (base.getUTCDate() !== originalDay) {
    base.setUTCDate(0);
  }
  return sqliteTimestamp(base);
}

function addDays(value: Date, days: number): string {
  const next = new Date(value.getTime());
  next.setUTCDate(next.getUTCDate() + days);
  return sqliteTimestamp(next);
}

function isDue(subscription: MembershipBillingSubscription, now: Date): boolean {
  const periodEnd = parseDbTimestamp(subscription.current_period_end);
  if (!periodEnd || periodEnd.getTime() > now.getTime()) return false;
  const nextAttempt = parseDbTimestamp(subscription.next_billing_attempt_at);
  return !nextAttempt || nextAttempt.getTime() <= now.getTime();
}

function capError(value: string | null | undefined): string {
  const clean = (value || 'Payment declined').replace(/[\x00-\x1F\x7F]/g, ' ').trim();
  return clean.slice(0, 1000) || 'Payment declined';
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function tableExists(db: Database.Database, table: string): boolean {
  const row = db
    .prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
    .get(table);
  return !!row;
}

function readConfig(db: Database.Database, key: string): string | null {
  try {
    const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
    return row?.value ?? null;
  } catch {
    return null;
  }
}

function enqueueDunningEmail(input: {
  db: Database.Database;
  subscription: MembershipBillingSubscription;
  error: string;
  failedCount: number;
  finalFailure: boolean;
  nextAttemptAt: string | null;
  scheduledAt: string;
}): boolean {
  const { db, subscription, error, failedCount, finalFailure, nextAttemptAt, scheduledAt } = input;
  if (!tableExists(db, 'notification_queue')) return false;
  if (!subscription.email || subscription.email_opt_in === 0) return false;

  const storeName = readConfig(db, 'store_name') || 'our shop';
  const customerName = [subscription.first_name, subscription.last_name].filter(Boolean).join(' ') || 'there';
  const tierName = subscription.tier_name || 'membership';
  const subject = finalFailure
    ? `Membership billing suspended for ${tierName}`
    : `Membership payment failed for ${tierName}`;
  const nextLine = nextAttemptAt
    ? `<p>We will retry this payment on ${htmlEscape(nextAttemptAt)}.</p>`
    : '<p>Automatic retries have stopped. Please contact us to update your payment method.</p>';
  const body = [
    '<div style="font-family:system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;line-height:1.5;color:#0f172a">',
    `<p>Hi ${htmlEscape(customerName)},</p>`,
    `<p>We could not process your ${htmlEscape(tierName)} membership payment at ${htmlEscape(storeName)}.</p>`,
    `<p><strong>Reason:</strong> ${htmlEscape(error)}</p>`,
    `<p><strong>Attempt:</strong> ${failedCount}</p>`,
    nextLine,
    finalFailure
      ? '<p>Your membership benefits are past due until payment is resolved.</p>'
      : '<p>Your membership is marked past due until the renewal succeeds.</p>',
    '</div>',
  ].join('');

  try {
    db.prepare(`
      INSERT INTO notification_queue (type, recipient, subject, body, status, scheduled_at, max_retries)
      VALUES ('email', ?, ?, ?, 'pending', ?, 3)
    `).run(subscription.email, subject, body, scheduledAt);
    return true;
  } catch (err) {
    logger.warn('membership dunning email queue failed', {
      subscriptionId: subscription.id,
      error: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

const blockChypGateway: MembershipBillingGateway = {
  key: 'blockchyp',
  canCharge(subscription) {
    return !!subscription.blockchyp_token;
  },
  unavailableReason(db, subscription) {
    if (!subscription.blockchyp_token) return 'No card on file for this subscription';
    if (!isBlockChypEnabled(db)) return 'BlockChyp is not configured for this tenant';
    return null;
  },
  async charge(db, subscription, amount, description) {
    if (!subscription.blockchyp_token) {
      return { success: false, error: 'No card on file for this subscription' };
    }
    return blockChypChargeToken(db, subscription.blockchyp_token, amount.toFixed(2), description);
  },
};

function gatewaysOrDefault(gateways: MembershipBillingGateway[] | undefined): MembershipBillingGateway[] {
  return gateways && gateways.length > 0 ? gateways : [blockChypGateway];
}

function chooseGateway(
  subscription: MembershipBillingSubscription,
  gateways: MembershipBillingGateway[],
): MembershipBillingGateway {
  return gateways.find((gateway) => gateway.canCharge(subscription)) ?? gateways[0];
}

export function loadMembershipBillingSubscription(
  db: Database.Database,
  id: number,
): MembershipBillingSubscription | undefined {
  return db.prepare(`
    SELECT cs.*, mt.monthly_price, mt.name AS tier_name,
           c.first_name, c.last_name, c.email, c.email_opt_in
      FROM customer_subscriptions cs
      JOIN membership_tiers mt ON mt.id = cs.tier_id
      LEFT JOIN customers c ON c.id = cs.customer_id
     WHERE cs.id = ?
  `).get(id) as MembershipBillingSubscription | undefined;
}

function loadDueSubscriptions(
  db: Database.Database,
  now: Date,
  limit: number,
): MembershipBillingSubscription[] {
  const stamp = sqliteTimestamp(now);
  return db.prepare(`
    SELECT cs.*, mt.monthly_price, mt.name AS tier_name,
           c.first_name, c.last_name, c.email, c.email_opt_in
      FROM customer_subscriptions cs
      JOIN membership_tiers mt ON mt.id = cs.tier_id
      LEFT JOIN customers c ON c.id = cs.customer_id
     WHERE cs.status IN ('active', 'past_due')
       AND COALESCE(cs.auto_renew, 1) = 1
       AND cs.cancel_at_period_end = 0
       AND cs.current_period_end <= ?
       AND (cs.next_billing_attempt_at IS NULL OR cs.next_billing_attempt_at <= ?)
     ORDER BY cs.current_period_end ASC, cs.id ASC
     LIMIT ?
  `).all(stamp, stamp, limit) as MembershipBillingSubscription[];
}

function recordBillingFailure(input: {
  db: Database.Database;
  subscription: MembershipBillingSubscription;
  amount: number;
  paymentProvider: string | null;
  error: string;
  source: MembershipBillingSource;
  userId: number | null;
  ip: string;
  runId: number | null;
  now: Date;
}): BillingItemResult {
  const { db, subscription, amount, paymentProvider, error, source, userId, ip, runId, now } = input;
  const stamp = sqliteTimestamp(now);
  const failedCount = Number(subscription.failed_charge_count ?? 0) + 1;
  const retryDelayDays = RETRY_DELAY_DAYS[failedCount - 1];
  const nextAttemptAt = retryDelayDays === undefined ? null : addDays(now, retryDelayDays);
  const finalFailure = !nextAttemptAt;
  const message = capError(error);
  const dunningQueued = enqueueDunningEmail({
    db,
    subscription,
    error: message,
    failedCount,
    finalFailure,
    nextAttemptAt,
    scheduledAt: stamp,
  });

  db.prepare(`
    UPDATE customer_subscriptions
       SET status = 'past_due',
           failed_charge_count = ?,
           billing_retry_stage = ?,
           next_billing_attempt_at = ?,
           last_charge_failed_at = ?,
           last_charge_error = ?,
           billing_suspended_at = CASE WHEN ? = 1 THEN ? ELSE billing_suspended_at END,
           auto_renew = CASE WHEN ? = 1 THEN 0 ELSE auto_renew END,
           updated_at = ?
     WHERE id = ?
  `).run(
    failedCount,
    Math.min(failedCount, RETRY_DELAY_DAYS.length),
    nextAttemptAt,
    stamp,
    message,
    finalFailure ? 1 : 0,
    stamp,
    finalFailure ? 1 : 0,
    stamp,
    subscription.id,
  );

  db.prepare(`
    INSERT INTO subscription_payments
      (subscription_id, amount, status, error_message, billing_run_id, payment_provider)
    VALUES (?, ?, 'failed', ?, ?, ?)
  `).run(subscription.id, amount, message, runId, paymentProvider);

  audit(db, 'membership_billing_failed', userId, ip, {
    subscription_id: subscription.id,
    amount,
    error: message,
    source,
    failed_count: failedCount,
    next_attempt_at: nextAttemptAt,
    final_failure: finalFailure,
    dunning_queued: dunningQueued,
  });

  return {
    status: 'failed',
    subscription_id: subscription.id,
    customer_id: subscription.customer_id,
    tier_id: subscription.tier_id,
    amount,
    payment_provider: paymentProvider,
    previous_period_end: subscription.current_period_end ?? null,
    message,
    httpStatus: 402,
    next_attempt_at: nextAttemptAt,
    attempt_number: failedCount,
    final_failure: finalFailure,
    dunning_queued: dunningQueued,
  };
}

function recordBillingSuccess(input: {
  db: Database.Database;
  subscription: MembershipBillingSubscription;
  amount: number;
  paymentProvider: string | null;
  transactionId: string | null;
  source: MembershipBillingSource;
  userId: number | null;
  ip: string;
  runId: number | null;
  now: Date;
}): BillingItemResult {
  const { db, subscription, amount, paymentProvider, transactionId, source, userId, ip, runId, now } = input;
  const stamp = sqliteTimestamp(now);
  const previousPeriodEnd = subscription.current_period_end ?? null;
  const newPeriodEnd = addMonthsClamped(previousPeriodEnd, 1, now);
  const newPeriodStart = previousPeriodEnd ?? stamp;

  db.prepare(`
    UPDATE customer_subscriptions
       SET status = 'active',
           current_period_start = ?,
           current_period_end = ?,
           last_charge_at = ?,
           last_charge_amount = ?,
           failed_charge_count = 0,
           billing_retry_stage = 0,
           next_billing_attempt_at = NULL,
           last_charge_failed_at = NULL,
           last_charge_error = NULL,
           billing_suspended_at = NULL,
           auto_renew = 1,
           updated_at = ?
     WHERE id = ?
  `).run(newPeriodStart, newPeriodEnd, stamp, amount, stamp, subscription.id);

  const blockChypTransactionId = paymentProvider === 'blockchyp' ? transactionId : null;
  db.prepare(`
    INSERT INTO subscription_payments
      (subscription_id, amount, status, blockchyp_transaction_id, billing_run_id, payment_provider, processor_transaction_id)
    VALUES (?, ?, 'success', ?, ?, ?, ?)
  `).run(subscription.id, amount, blockChypTransactionId, runId, paymentProvider, transactionId);

  audit(db, 'membership_billing_success', userId, ip, {
    subscription_id: subscription.id,
    amount,
    transaction_id: transactionId,
    source,
    payment_provider: paymentProvider,
  });

  return {
    status: 'success',
    subscription_id: subscription.id,
    customer_id: subscription.customer_id,
    tier_id: subscription.tier_id,
    amount,
    payment_provider: paymentProvider,
    transaction_id: transactionId,
    previous_period_end: previousPeriodEnd,
    new_period_end: newPeriodEnd,
    message: 'Billing completed successfully',
  };
}

export async function billMembershipSubscription(
  db: Database.Database,
  subscription: MembershipBillingSubscription,
  options: BillMembershipOptions,
): Promise<BillingItemResult> {
  const force = options.force === true;
  const now = options.now ?? new Date();
  const userId = options.userId ?? null;
  const ip = options.ip ?? 'unknown';
  const runId = options.runId ?? null;
  const amount = Number(subscription.monthly_price);
  const previousPeriodEnd = subscription.current_period_end ?? null;

  if (subscription.status === 'cancelled') {
    return { status: 'skipped', subscription_id: subscription.id, customer_id: subscription.customer_id, tier_id: subscription.tier_id, amount, previous_period_end: previousPeriodEnd, message: 'Subscription is cancelled', httpStatus: 400 };
  }
  if (subscription.status === 'paused') {
    return { status: 'skipped', subscription_id: subscription.id, customer_id: subscription.customer_id, tier_id: subscription.tier_id, amount, previous_period_end: previousPeriodEnd, message: 'Subscription is paused', httpStatus: 400 };
  }
  if (subscription.cancel_at_period_end === 1 && !force) {
    return { status: 'skipped', subscription_id: subscription.id, customer_id: subscription.customer_id, tier_id: subscription.tier_id, amount, previous_period_end: previousPeriodEnd, message: 'Subscription is scheduled to cancel at period end', httpStatus: 409 };
  }
  if (subscription.auto_renew === 0 && !force) {
    return { status: 'skipped', subscription_id: subscription.id, customer_id: subscription.customer_id, tier_id: subscription.tier_id, amount, previous_period_end: previousPeriodEnd, message: 'Automatic renewal is disabled for this subscription', httpStatus: 409 };
  }
  if (!force && !isDue(subscription, now)) {
    return {
      status: 'skipped',
      subscription_id: subscription.id,
      customer_id: subscription.customer_id,
      tier_id: subscription.tier_id,
      amount,
      previous_period_end: previousPeriodEnd,
      next_attempt_at: subscription.next_billing_attempt_at ?? null,
      message: subscription.next_billing_attempt_at
        ? `Subscription retry is scheduled for ${subscription.next_billing_attempt_at}`
        : `Subscription is not due until ${subscription.current_period_end}`,
      httpStatus: 409,
    };
  }
  if (!Number.isFinite(amount) || amount < 0) {
    return recordBillingFailure({
      db,
      subscription,
      amount: Number.isFinite(amount) ? amount : 0,
      paymentProvider: subscription.payment_provider ?? null,
      error: 'Invalid subscription amount',
      source: options.source,
      userId,
      ip,
      runId,
      now,
    });
  }
  if (amount === 0) {
    return recordBillingSuccess({
      db,
      subscription,
      amount,
      paymentProvider: 'none',
      transactionId: null,
      source: options.source,
      userId,
      ip,
      runId,
      now,
    });
  }

  const gateways = gatewaysOrDefault(options.gateways);
  const gateway = chooseGateway(subscription, gateways);
  const unavailable = gateway.unavailableReason?.(db, subscription);
  if (unavailable) {
    return recordBillingFailure({
      db,
      subscription,
      amount,
      paymentProvider: gateway.key,
      error: unavailable,
      source: options.source,
      userId,
      ip,
      runId,
      now,
    });
  }

  let chargeResult: MembershipChargeResult;
  try {
    chargeResult = await gateway.charge(
      db,
      subscription,
      amount,
      `${subscription.tier_name} Membership renewal`,
    );
  } catch (err) {
    chargeResult = {
      success: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }

  if (!chargeResult.success) {
    return recordBillingFailure({
      db,
      subscription,
      amount,
      paymentProvider: gateway.key,
      error: chargeResult.error || 'Payment declined',
      source: options.source,
      userId,
      ip,
      runId,
      now,
    });
  }

  return recordBillingSuccess({
    db,
    subscription,
    amount,
    paymentProvider: gateway.key,
    transactionId: chargeResult.transactionId ?? null,
    source: options.source,
    userId,
    ip,
    runId,
    now,
  });
}

function normalizeLimit(value: number | undefined): number {
  if (!Number.isInteger(value) || !value || value <= 0) return DEFAULT_LIMIT;
  return Math.min(value, MAX_LIMIT);
}

function countStatus(results: BillingItemResult[], status: BillingItemResult['status']): number {
  return results.filter((result) => result.status === status).length;
}

function markStaleRuns(db: Database.Database, now: Date, staleAfterHours: number): void {
  const stamp = sqliteTimestamp(now);
  const staleBefore = sqliteTimestamp(new Date(now.getTime() - staleAfterHours * 60 * 60 * 1000));
  db.prepare(`
    UPDATE membership_billing_runs
       SET status = 'failed',
           finished_at = ?,
           error_message = 'Marked stale without completion',
           updated_at = ?
     WHERE status = 'running'
       AND started_at < ?
  `).run(stamp, stamp, staleBefore);
}

function loadActiveRun(db: Database.Database): MembershipBillingRunRow | undefined {
  return db.prepare(
    "SELECT * FROM membership_billing_runs WHERE status = 'running' ORDER BY started_at DESC LIMIT 1",
  ).get() as MembershipBillingRunRow | undefined;
}

function loadRun(db: Database.Database, runId: number): MembershipBillingRunRow | null {
  return (db.prepare('SELECT * FROM membership_billing_runs WHERE id = ?').get(runId) as MembershipBillingRunRow | undefined) ?? null;
}

function updateRunProgress(
  db: Database.Database,
  runId: number,
  results: BillingItemResult[],
  now: Date,
): void {
  db.prepare(`
    UPDATE membership_billing_runs
       SET charged_count = ?,
           failed_count = ?,
           skipped_count = ?,
           result_json = ?,
           updated_at = ?
     WHERE id = ?
  `).run(
    countStatus(results, 'success'),
    countStatus(results, 'failed'),
    countStatus(results, 'skipped'),
    JSON.stringify(results),
    sqliteTimestamp(now),
    runId,
  );
}

export async function runMembershipBillingOnce(
  db: Database.Database,
  options: RunMembershipBillingOptions,
): Promise<MembershipBillingRunResult> {
  const now = options.now ?? new Date();
  const stamp = sqliteTimestamp(now);
  const staleAfterHours = options.staleAfterHours ?? 2;
  const limit = normalizeLimit(options.limit);

  if (!tableExists(db, 'membership_billing_runs')) {
    return { run: null, results: [], skipped: true, message: 'membership_billing_runs table is missing' };
  }

  markStaleRuns(db, now, staleAfterHours);

  const activeRun = loadActiveRun(db);
  if (activeRun) {
    return {
      run: activeRun,
      results: [],
      skipped: true,
      message: 'A membership billing run is already in progress',
    };
  }

  const runResult = db.prepare(`
    INSERT INTO membership_billing_runs (status, mode, started_at, started_by, updated_at)
    VALUES ('running', ?, ?, ?, ?)
  `).run(options.mode, stamp, options.startedBy ?? null, stamp);
  const runId = Number(runResult.lastInsertRowid);
  const results: BillingItemResult[] = [];

  try {
    const dueSubscriptions = loadDueSubscriptions(db, now, limit);
    db.prepare(`
      UPDATE membership_billing_runs
         SET total_due = ?,
             result_json = ?,
             updated_at = ?
       WHERE id = ?
    `).run(dueSubscriptions.length, JSON.stringify(results), stamp, runId);

    for (const subscription of dueSubscriptions) {
      const item = await billMembershipSubscription(db, subscription, {
        force: false,
        source: options.source,
        userId: options.startedBy ?? null,
        ip: options.ip ?? 'cron',
        runId,
        now,
        gateways: options.gateways,
      });
      results.push(item);
      updateRunProgress(db, runId, results, now);
    }

    const completedAt = sqliteTimestamp(options.now ?? new Date());
    db.prepare(`
      UPDATE membership_billing_runs
         SET status = 'completed',
             finished_at = ?,
             charged_count = ?,
             failed_count = ?,
             skipped_count = ?,
             result_json = ?,
             updated_at = ?
       WHERE id = ?
    `).run(
      completedAt,
      countStatus(results, 'success'),
      countStatus(results, 'failed'),
      countStatus(results, 'skipped'),
      JSON.stringify(results),
      completedAt,
      runId,
    );

    audit(db, 'membership_billing_run_completed', options.startedBy ?? null, options.ip ?? 'cron', {
      run_id: runId,
      mode: options.mode,
      source: options.source,
      tenant_slug: options.tenantSlug ?? null,
      total_due: dueSubscriptions.length,
      charged: countStatus(results, 'success'),
      failed: countStatus(results, 'failed'),
      skipped: countStatus(results, 'skipped'),
    });

    return { run: loadRun(db, runId), results, skipped: false };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Billing run failed';
    const failedAt = sqliteTimestamp(new Date());
    db.prepare(`
      UPDATE membership_billing_runs
         SET status = 'failed',
             finished_at = ?,
             error_message = ?,
             result_json = ?,
             updated_at = ?
       WHERE id = ?
    `).run(failedAt, capError(message), JSON.stringify(results), failedAt, runId);
    audit(db, 'membership_billing_run_failed', options.startedBy ?? null, options.ip ?? 'cron', {
      run_id: runId,
      mode: options.mode,
      source: options.source,
      tenant_slug: options.tenantSlug ?? null,
      error: message,
    });
    throw err;
  }
}
