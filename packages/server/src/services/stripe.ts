/**
 * Stripe billing service.
 *
 * Handles Checkout session creation, Billing Portal sessions, webhook
 * verification, webhook event processing, and direct subscription updates
 * for the super-admin agent.
 *
 * Pre-production audit fixes (see criticalaudit.md §30):
 *
 *   BL1  — `handleWebhookEvent` rejects any event whose `created` timestamp
 *          is older than 300s. This prevents a replay attack where an
 *          attacker takes a real webhook from weeks ago (e.g.
 *          `invoice.payment_failed`) and re-delivers it today, forcibly
 *          downgrading a paying customer.
 *
 *   BL2  — Idempotency moved from SELECT-then-INSERT to `INSERT OR IGNORE`,
 *          checking `result.changes === 0` to detect "already processed".
 *          The primary key on `stripe_event_id` remains the authoritative
 *          guarantee, but the new flow is race-safe under concurrent
 *          deliveries from the Stripe retry queue.
 *
 *   BL3  — `invoice.payment_failed` now:
 *            1. Increments `failed_charge_count` on the tenant.
 *            2. At `>= 3`, downgrades plan to 'free' and resets the counter.
 *            3. Enqueues an email to the tenant owner
 *               (`stripe_payment_failure_emails` queue).
 *            4. Below 3 attempts, keeps the plan but sets
 *               `payment_past_due = 1`.
 *
 *   BL4  — `createCheckoutSession` acquires `stripe_customer_lock` on the
 *          tenant row before building the Checkout session. Two concurrent
 *          upgrade clicks now see one grab the lock and the other get a 409.
 *          The lock is released after the session is created (success or
 *          failure) so a subsequent retry can proceed.
 *
 *   BL5  — `stripe_webhook_events.stripe_event_id` is the primary key; the
 *          uniqueness constraint at the DB layer is the final line of
 *          defence. This comment documents that invariant.
 *
 *   BL11 — Stripe Checkout session creation now passes an idempotency key
 *          (16 random bytes, hex-encoded) as the 2nd argument to
 *          `stripe.checkout.sessions.create`. The key is stored in
 *          `stripe_checkout_idempotency` keyed by tenant; a repeat click
 *          within the TTL reuses the same key so Stripe returns the same
 *          Checkout Session object instead of creating a duplicate.
 *
 *   BL12 — `tenants.stripe_customer_id` was previously nullable with no
 *          uniqueness guarantee. A clock race or cross-wired webhook could
 *          assign the same Stripe Customer ID to two tenants, which would
 *          misroute subscription / invoice events. `ensureStripeSchema` now
 *          creates a partial unique index (NULL values are still allowed
 *          for tenants on the free plan, matching SQLite's partial-index
 *          semantics). `checkout.session.completed` does a SELECT-then-UPDATE
 *          inside a transaction so a duplicate Stripe Customer ID from a
 *          forged/replayed event fails loudly instead of silently corrupting
 *          ownership.
 *
 *   BL13 — `enrollCard`, `chargeToken`, and BlockChyp payment-link creation
 *          still used `payment-${Date.now()}` as their transactionRef —
 *          the same class of double-charge bug BL6 fixed for
 *          `processPayment`. They now go through `buildUniqueTransactionRef`.
 *          See `services/blockchyp.ts` for the fix.
 *
 * Master DB schema additions are created via `ensureStripeSchema()` on first
 * call. Migrations don't run against the master DB (that's tenant-DB only),
 * so this file owns its own schema bootstrapping. All ALTER statements are
 * wrapped in try/catch to keep them idempotent.
 */

import crypto from 'crypto';
import Stripe from 'stripe';
import Database from 'better-sqlite3';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { clearPlanCache } from '../middleware/tenantResolver.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('stripe');

let stripeClient: Stripe | null = null;
let schemaEnsured = false;

/** Reject webhooks older than this many seconds (BL1). */
const WEBHOOK_MAX_AGE_SECONDS = 300;

/** Failed charge attempts before automatic downgrade (BL3). */
const FAILED_CHARGE_DOWNGRADE_THRESHOLD = 3;

/** TTL for idempotency keys stored in `stripe_checkout_idempotency` (BL11). */
const CHECKOUT_IDEMPOTENCY_TTL_SECONDS = 24 * 60 * 60; // 24 hours

type PlanName = 'free' | 'pro' | 'enterprise';

function getStripe(): Stripe {
  if (!stripeClient) {
    if (!config.stripeSecretKey) {
      throw new Error('STRIPE_SECRET_KEY not configured');
    }
    stripeClient = new Stripe(config.stripeSecretKey, {
      apiVersion: '2024-12-18.acacia' as any,
    });
  }
  return stripeClient;
}

/**
 * Bootstrap Stripe-specific schema on the master DB. This is a no-op after
 * the first call. Each ALTER is wrapped in try/catch because SQLite doesn't
 * support `ADD COLUMN IF NOT EXISTS`.
 */
function ensureStripeSchema(masterDb: Database.Database): void {
  if (schemaEnsured) return;

  // BL4: stripe_customer_lock prevents concurrent Checkout creations from
  // spawning two Stripe Customer objects for the same tenant.
  try {
    masterDb.exec('ALTER TABLE tenants ADD COLUMN stripe_customer_lock INTEGER DEFAULT 0');
  } catch {
    /* column already exists */
  }

  // BL3: counter for sequential payment failures and a "grace period" flag.
  try {
    masterDb.exec('ALTER TABLE tenants ADD COLUMN failed_charge_count INTEGER NOT NULL DEFAULT 0');
  } catch {
    /* column already exists */
  }
  try {
    masterDb.exec('ALTER TABLE tenants ADD COLUMN payment_past_due INTEGER NOT NULL DEFAULT 0');
  } catch {
    /* column already exists */
  }

  // BL11: per-tenant idempotency keys for Stripe Checkout creations.
  // key = randomBytes(16).toString('hex'); rows expire via TTL check in code.
  masterDb.exec(`
    CREATE TABLE IF NOT EXISTS stripe_checkout_idempotency (
      tenant_id       INTEGER PRIMARY KEY REFERENCES tenants(id),
      idempotency_key TEXT NOT NULL,
      created_at      INTEGER NOT NULL
    );
  `);

  // BL12: partial unique index on tenants.stripe_customer_id. NULLs are
  // permitted (free-tier tenants have no Stripe Customer yet), but once a
  // customer id is assigned it must be globally unique across all tenants.
  // Wrapped in try/catch: existing rows with duplicate values will fail the
  // CREATE, but the next run after a dedupe migration will succeed. We never
  // silently drop rows here — operators must fix duplicates manually first.
  try {
    masterDb.exec(
      `CREATE UNIQUE INDEX IF NOT EXISTS idx_tenants_stripe_customer_id_unique
         ON tenants(stripe_customer_id)
         WHERE stripe_customer_id IS NOT NULL`,
    );
  } catch (err: unknown) {
    logger.error('Could not create unique index on tenants.stripe_customer_id — possible duplicate rows', {
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // BL3: enqueue payment-failure notifications instead of trying to send them
  // inline from the webhook handler. A future worker drains this table and
  // delivers the emails via the platform's SMTP config.
  masterDb.exec(`
    CREATE TABLE IF NOT EXISTS stripe_payment_failure_emails (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      tenant_id      INTEGER NOT NULL REFERENCES tenants(id),
      admin_email    TEXT NOT NULL,
      attempt_count  INTEGER NOT NULL,
      subscription_id TEXT,
      stripe_event_id TEXT,
      status         TEXT NOT NULL DEFAULT 'queued'
                     CHECK(status IN ('queued', 'sent', 'failed')),
      created_at     TEXT NOT NULL DEFAULT (datetime('now')),
      sent_at        TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_stripe_payment_failure_emails_status
      ON stripe_payment_failure_emails(status);
  `);

  schemaEnsured = true;
}

/** Strictly parse a tenant ID from a string. Returns null for any invalid/unsafe value. */
function parseTenantId(value: string | null | undefined): number | null {
  if (!value) return null;
  // Reject anything that isn't a string of digits (parseInt is too forgiving)
  if (!/^\d+$/.test(value)) return null;
  const parsed = parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0 || !Number.isSafeInteger(parsed)) return null;
  return parsed;
}

/** Resolve the Stripe price ID for a given plan. */
function resolvePriceIdForPlan(plan: 'pro' | 'enterprise'): string {
  if (plan === 'pro') {
    if (!config.stripeProPriceId) {
      throw new Error('STRIPE_PRO_PRICE_ID not configured');
    }
    return config.stripeProPriceId;
  }
  const enterpriseId = process.env.STRIPE_ENTERPRISE_PRICE_ID || '';
  if (!enterpriseId) {
    throw new Error('STRIPE_ENTERPRISE_PRICE_ID not configured');
  }
  return enterpriseId;
}

/**
 * SEC-M40: resolve the proration behavior used when swapping a tenant's
 * Stripe subscription price. Operators can override via
 * STRIPE_PRORATION_BEHAVIOR in `.env`; unknown / missing values fall back
 * to 'create_prorations' (Stripe's own default), which bills the tenant a
 * pro-rated difference on the next invoice. Allowed values are the three
 * Stripe supports on `subscriptions.update`.
 */
const PRORATION_BEHAVIOR_ALLOWED = ['create_prorations', 'none', 'always_invoice'] as const;
type ProrationBehavior = typeof PRORATION_BEHAVIOR_ALLOWED[number];
function resolveProrationBehavior(): ProrationBehavior {
  const raw = (process.env.STRIPE_PRORATION_BEHAVIOR || '').trim();
  if ((PRORATION_BEHAVIOR_ALLOWED as readonly string[]).includes(raw)) {
    return raw as ProrationBehavior;
  }
  return 'create_prorations';
}

/**
 * Allocate or reuse an idempotency key for a tenant's Checkout Session
 * creation (BL11). Keys expire after CHECKOUT_IDEMPOTENCY_TTL_SECONDS so
 * genuine new upgrades after 24 hours are never blocked.
 */
function getOrCreateCheckoutIdempotencyKey(
  masterDb: Database.Database,
  tenantId: number,
): string {
  const now = Math.floor(Date.now() / 1000);
  const cutoff = now - CHECKOUT_IDEMPOTENCY_TTL_SECONDS;

  // Drop stale rows first. Keeps the table tiny and avoids reusing keys
  // from old upgrade flows.
  masterDb
    .prepare('DELETE FROM stripe_checkout_idempotency WHERE created_at < ?')
    .run(cutoff);

  const existing = masterDb
    .prepare(
      'SELECT idempotency_key FROM stripe_checkout_idempotency WHERE tenant_id = ? AND created_at >= ?',
    )
    .get(tenantId, cutoff) as { idempotency_key: string } | undefined;

  if (existing?.idempotency_key) return existing.idempotency_key;

  const fresh = crypto.randomBytes(16).toString('hex');
  masterDb
    .prepare(
      `INSERT OR REPLACE INTO stripe_checkout_idempotency
         (tenant_id, idempotency_key, created_at)
       VALUES (?, ?, ?)`,
    )
    .run(tenantId, fresh, now);
  return fresh;
}

/**
 * Acquire the per-tenant "creating-stripe-customer" lock. Returns true if the
 * lock was acquired by this call, false if another concurrent caller holds it.
 *
 * Uses a conditional UPDATE that only sets the flag if it is currently 0
 * (or NULL — for tenants that existed before the column was added).
 */
function acquireCustomerLock(masterDb: Database.Database, tenantId: number): boolean {
  const result = masterDb
    .prepare(
      `UPDATE tenants
          SET stripe_customer_lock = 1
        WHERE id = ?
          AND (stripe_customer_lock IS NULL OR stripe_customer_lock = 0)`,
    )
    .run(tenantId);
  return result.changes === 1;
}

/** Release the per-tenant "creating-stripe-customer" lock unconditionally. */
function releaseCustomerLock(masterDb: Database.Database, tenantId: number): void {
  try {
    masterDb
      .prepare('UPDATE tenants SET stripe_customer_lock = 0 WHERE id = ?')
      .run(tenantId);
  } catch (err: unknown) {
    logger.error('Failed to release stripe_customer_lock', {
      tenantId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Create a Checkout Session for a Pro subscription. Returns the checkout URL.
 *
 * BL4: wraps customer lookup inside a per-tenant lock so two concurrent upgrade
 *      clicks can't both create new Stripe Customer objects.
 * BL11: passes a Stripe-level idempotency key so the Stripe API itself
 *       collapses retries into a single Checkout Session.
 */
export async function createCheckoutSession(
  tenantId: number,
  tenantSlug: string,
  adminEmail: string,
  baseUrl: string,
): Promise<string> {
  if (!config.stripeProPriceId) {
    throw new Error('STRIPE_PRO_PRICE_ID not configured');
  }
  const stripe = getStripe();

  const masterDb = getMasterDb();
  if (!masterDb) {
    throw new Error('Master DB not initialized');
  }
  ensureStripeSchema(masterDb);

  // BL4: acquire the lock. If another request is in-flight, bail with a
  // typed error the route handler can translate into a 409.
  if (!acquireCustomerLock(masterDb, tenantId)) {
    const err = new Error('Another upgrade is already in progress for this tenant');
    (err as Error & { code?: string }).code = 'STRIPE_UPGRADE_IN_PROGRESS';
    throw err;
  }

  try {
    // Now that we hold the lock, read the current stripe_customer_id and
    // make the create call. Any concurrent reader is stuck on the lock.
    const tenant = masterDb
      .prepare('SELECT stripe_customer_id FROM tenants WHERE id = ?')
      .get(tenantId) as { stripe_customer_id: string | null } | undefined;

    // BL11: reuse (or allocate) a stable idempotency key per tenant per
    // 24-hour window. Stripe returns the same Session for identical requests
    // with the same key, preventing duplicates from double-clicks.
    const idempotencyKey = getOrCreateCheckoutIdempotencyKey(masterDb, tenantId);

    const session = await stripe.checkout.sessions.create(
      {
        mode: 'subscription',
        payment_method_types: ['card'],
        line_items: [{ price: config.stripeProPriceId, quantity: 1 }],
        customer: tenant?.stripe_customer_id || undefined,
        customer_email: tenant?.stripe_customer_id ? undefined : adminEmail,
        client_reference_id: String(tenantId),
        metadata: { tenant_id: String(tenantId), tenant_slug: tenantSlug },
        success_url: `${baseUrl}/settings/billing?upgraded=1`,
        cancel_url: `${baseUrl}/settings/billing?cancelled=1`,
        subscription_data: {
          metadata: { tenant_id: String(tenantId), tenant_slug: tenantSlug },
        },
      },
      { idempotencyKey },
    );

    if (!session.url) throw new Error('Stripe did not return a checkout URL');
    return session.url;
  } finally {
    releaseCustomerLock(masterDb, tenantId);
  }
}

/** Create a Billing Portal session for managing existing subscription. */
export async function createBillingPortalSession(
  stripeCustomerId: string,
  returnUrl: string,
): Promise<string> {
  const stripe = getStripe();
  const session = await stripe.billingPortal.sessions.create({
    customer: stripeCustomerId,
    return_url: returnUrl,
  });
  return session.url;
}

/**
 * Verify webhook signature and return the event.
 *
 * SEC-M38: We pass an explicit tolerance (in seconds) rather than relying on
 * Stripe's built-in default (currently 300s but not formally guaranteed
 * across SDK revisions). 300s = 5 minutes of clock skew / network delay
 * tolerance. Anything older than that gets rejected with a
 * SignatureVerificationError — which prevents a leaked signature from being
 * replayed days later. If the host clock is drifting more than 5 min from
 * real time, webhook verification will start failing — that's intentional.
 */
const WEBHOOK_TOLERANCE_SECONDS = 300;
export function verifyWebhook(payload: Buffer, signature: string): Stripe.Event {
  if (!config.stripeWebhookSecret) {
    throw new Error('STRIPE_WEBHOOK_SECRET not configured');
  }
  const stripe = getStripe();
  return stripe.webhooks.constructEvent(
    payload,
    signature,
    config.stripeWebhookSecret,
    WEBHOOK_TOLERANCE_SECONDS,
  );
}

/**
 * Enqueue a payment-failure notification email. Runs inline with the webhook
 * so at least one durable record exists. A background worker (out of scope
 * for this change) drains the queue and actually sends the message.
 */
function enqueuePaymentFailureEmail(
  masterDb: Database.Database,
  tenantId: number,
  adminEmail: string | null | undefined,
  attemptCount: number,
  subscriptionId: string | null,
  stripeEventId: string,
): void {
  // BL18: guard against empty admin_email. Without a recipient the background
  // worker would silently fail every delivery attempt; fail fast at enqueue.
  const trimmedEmail = typeof adminEmail === 'string' ? adminEmail.trim() : '';
  if (!trimmedEmail) {
    logger.error('Cannot enqueue payment failure email — tenant has no admin_email', {
      tenantId,
      attemptCount,
      stripeEventId,
    });
    return;
  }
  try {
    masterDb
      .prepare(
        `INSERT INTO stripe_payment_failure_emails
           (tenant_id, admin_email, attempt_count, subscription_id, stripe_event_id)
         VALUES (?, ?, ?, ?, ?)`,
      )
      .run(tenantId, trimmedEmail, attemptCount, subscriptionId, stripeEventId);
  } catch (err: unknown) {
    logger.error('Failed to enqueue payment failure email', {
      tenantId,
      attemptCount,
      stripeEventId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Handle `invoice.payment_failed` — increment the counter, downgrade to free
 * at threshold, otherwise mark the tenant past-due and enqueue an email.
 */
function processPaymentFailed(
  masterDb: Database.Database,
  event: Stripe.Event,
): number | null {
  const invoice = event.data.object as Stripe.Invoice;
  // `subscription` is not on the strict Invoice type in newer API versions,
  // but is still present in webhook payloads. Cast through unknown for safe access.
  const subscriptionRef = (invoice as unknown as {
    subscription?: string | { id: string } | null;
  }).subscription;
  const subscriptionId =
    typeof subscriptionRef === 'string' ? subscriptionRef : subscriptionRef?.id ?? null;

  if (!subscriptionId) {
    logger.warn('invoice.payment_failed has no subscription reference', {
      eventId: event.id,
    });
    return null;
  }

  const tenantRow = masterDb
    .prepare(
      'SELECT id, admin_email, failed_charge_count FROM tenants WHERE stripe_subscription_id = ?',
    )
    .get(subscriptionId) as
    | { id: number; admin_email: string; failed_charge_count: number | null }
    | undefined;

  if (!tenantRow) {
    logger.warn('invoice.payment_failed for unknown subscription', {
      subscriptionId,
      eventId: event.id,
    });
    return null;
  }

  const newCount = (tenantRow.failed_charge_count ?? 0) + 1;

  if (newCount >= FAILED_CHARGE_DOWNGRADE_THRESHOLD) {
    // BL3: downgrade to free, reset counter, keep past_due flag on for audit.
    masterDb
      .prepare(
        `UPDATE tenants
            SET plan = 'free',
                stripe_subscription_id = NULL,
                failed_charge_count = 0,
                payment_past_due = 1,
                updated_at = datetime('now')
          WHERE id = ?`,
      )
      .run(tenantRow.id);

    clearPlanCache(tenantRow.id);
    logger.error('Tenant downgraded to free after repeated payment failures', {
      tenantId: tenantRow.id,
      attempts: newCount,
      subscriptionId,
      eventId: event.id,
    });
  } else {
    // BL3 grace period: keep paid plan active but flag past_due.
    masterDb
      .prepare(
        `UPDATE tenants
            SET failed_charge_count = ?,
                payment_past_due = 1,
                updated_at = datetime('now')
          WHERE id = ?`,
      )
      .run(newCount, tenantRow.id);

    logger.warn('Tenant payment failed — grace period', {
      tenantId: tenantRow.id,
      attempts: newCount,
      threshold: FAILED_CHARGE_DOWNGRADE_THRESHOLD,
      subscriptionId,
      eventId: event.id,
    });
  }

  // BL3: enqueue notification regardless of whether we downgraded.
  enqueuePaymentFailureEmail(
    masterDb,
    tenantRow.id,
    tenantRow.admin_email,
    newCount,
    subscriptionId,
    event.id,
  );

  return tenantRow.id;
}

/**
 * Apply a Stripe webhook event to the master DB (update tenant plan,
 * subscription ID, etc.).
 *
 * Idempotency: enforced by the PRIMARY KEY on
 * `stripe_webhook_events.stripe_event_id` (BL5) and checked via
 * `INSERT OR IGNORE` (BL2). A duplicate delivery short-circuits before
 * any tenant state is touched.
 *
 * Replay protection: BL1 — reject events older than 300s based on
 * `event.created` to prevent weeks-old events from being replayed.
 */
export function handleWebhookEvent(event: Stripe.Event): void {
  const masterDb = getMasterDb();
  if (!masterDb) return;

  ensureStripeSchema(masterDb);

  // BL1: event-age check. `event.created` is in seconds since epoch.
  const nowSeconds = Math.floor(Date.now() / 1000);
  const ageSeconds = nowSeconds - (event.created ?? 0);
  if (ageSeconds > WEBHOOK_MAX_AGE_SECONDS) {
    logger.error('Rejecting stale Stripe webhook (replay protection)', {
      eventId: event.id,
      eventType: event.type,
      ageSeconds,
      maxAgeSeconds: WEBHOOK_MAX_AGE_SECONDS,
    });
    return;
  }

  // BL2: claim the event using INSERT OR IGNORE. If 0 rows changed, another
  // delivery already processed this event and we skip. We initially store
  // tenant_id = NULL and UPDATE it after the handler runs so the handler
  // itself is serialized by the PK.
  const claimResult = masterDb
    .prepare(
      `INSERT OR IGNORE INTO stripe_webhook_events (stripe_event_id, event_type, tenant_id)
       VALUES (?, ?, NULL)`,
    )
    .run(event.id, event.type);

  if (claimResult.changes === 0) {
    logger.info('Stripe webhook already processed — idempotent skip', {
      eventId: event.id,
      eventType: event.type,
    });
    return;
  }

  let recordedTenantId: number | null = null;

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const tenantId = parseTenantId(session.client_reference_id);
        if (!tenantId) {
          logger.warn('checkout.session.completed missing/invalid client_reference_id', {
            clientReferenceId: session.client_reference_id,
            eventId: event.id,
          });
          break;
        }

        // Validate tenant exists BEFORE updating.
        const existingTenant = masterDb
          .prepare('SELECT id FROM tenants WHERE id = ?')
          .get(tenantId) as { id: number } | undefined;
        if (!existingTenant) {
          logger.warn('checkout.session.completed for unknown tenant', {
            tenantId,
            eventId: event.id,
          });
          break;
        }

        const customerId =
          typeof session.customer === 'string' ? session.customer : session.customer?.id;
        const subscriptionId =
          typeof session.subscription === 'string'
            ? session.subscription
            : session.subscription?.id;

        // BL12: run the SELECT-cross-check and UPDATE inside a transaction.
        // If a DIFFERENT tenant row already holds this stripe_customer_id,
        // the BL12 unique index would throw on UPDATE — but we prefer to
        // detect it explicitly so we can log with BOTH tenant IDs for ops.
        // Either way we bail without mutating state.
        const applyCheckoutUpgrade = masterDb.transaction(() => {
          if (customerId) {
            const collision = masterDb
              .prepare(
                `SELECT id FROM tenants WHERE stripe_customer_id = ? AND id != ?`,
              )
              .get(customerId, tenantId) as { id: number } | undefined;
            if (collision) {
              logger.error('Refusing checkout.session.completed: stripe_customer_id collision', {
                eventId: event.id,
                targetTenantId: tenantId,
                conflictingTenantId: collision.id,
                customerId,
              });
              throw new Error('STRIPE_CUSTOMER_ID_COLLISION');
            }
          }

          masterDb
            .prepare(
              `UPDATE tenants
                  SET plan = 'pro',
                      trial_ends_at = NULL,
                      stripe_customer_id = ?,
                      stripe_subscription_id = ?,
                      failed_charge_count = 0,
                      payment_past_due = 0,
                      updated_at = datetime('now')
                WHERE id = ?`,
            )
            .run(customerId || null, subscriptionId || null, tenantId);
        });

        try {
          applyCheckoutUpgrade();
        } catch (err: unknown) {
          const msg = err instanceof Error ? err.message : String(err);
          if (msg === 'STRIPE_CUSTOMER_ID_COLLISION') {
            // Already logged inside the transaction. Leave the webhook
            // idempotency row in place so Stripe retries don't re-enter.
            break;
          }
          // Re-throw anything else so the outer catch logs + the DB row still
          // exists from the BL2 claim.
          throw err;
        }

        clearPlanCache(tenantId);
        recordedTenantId = tenantId;
        logger.info('Tenant upgraded to Pro via checkout', {
          tenantId,
          eventId: event.id,
        });
        break;
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const tenantWithSub = masterDb
          .prepare('SELECT id FROM tenants WHERE stripe_subscription_id = ?')
          .get(sub.id) as { id: number } | undefined;

        if (!tenantWithSub) {
          logger.warn('subscription.deleted for unknown subscription', {
            subscriptionId: sub.id,
            eventId: event.id,
          });
          break;
        }

        masterDb
          .prepare(
            `UPDATE tenants
                SET plan = 'free',
                    stripe_subscription_id = NULL,
                    updated_at = datetime('now')
              WHERE id = ?`,
          )
          .run(tenantWithSub.id);

        clearPlanCache(tenantWithSub.id);
        recordedTenantId = tenantWithSub.id;
        logger.info('Subscription cancelled, tenant downgraded to Free', {
          subscriptionId: sub.id,
          tenantId: tenantWithSub.id,
          eventId: event.id,
        });
        break;
      }

      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription;
        const tenantWithSub = masterDb
          .prepare('SELECT id FROM tenants WHERE stripe_subscription_id = ?')
          .get(sub.id) as { id: number } | undefined;

        if (!tenantWithSub) {
          logger.warn('subscription.updated for unknown subscription', {
            subscriptionId: sub.id,
            eventId: event.id,
          });
          break;
        }

        if (sub.status === 'active') {
          masterDb
            .prepare(
              `UPDATE tenants
                  SET plan = 'pro',
                      failed_charge_count = 0,
                      payment_past_due = 0,
                      updated_at = datetime('now')
                WHERE id = ?`,
            )
            .run(tenantWithSub.id);
          logger.info('Tenant subscription active', {
            tenantId: tenantWithSub.id,
            eventId: event.id,
          });
        } else if (sub.status === 'canceled' || sub.status === 'unpaid') {
          masterDb
            .prepare(
              `UPDATE tenants
                  SET plan = 'free',
                      updated_at = datetime('now')
                WHERE id = ?`,
            )
            .run(tenantWithSub.id);
          logger.info('Tenant subscription ended — downgraded to Free', {
            tenantId: tenantWithSub.id,
            subStatus: sub.status,
            eventId: event.id,
          });
        }

        clearPlanCache(tenantWithSub.id);
        recordedTenantId = tenantWithSub.id;
        break;
      }

      case 'invoice.payment_failed': {
        recordedTenantId = processPaymentFailed(masterDb, event);
        break;
      }
    }
  } catch (err: unknown) {
    logger.error('Stripe webhook handler threw', {
      eventId: event.id,
      eventType: event.type,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // BL2: fill in the tenant_id we actually touched (if any). The row already
  // exists from the INSERT OR IGNORE above; we just enrich it.
  if (recordedTenantId !== null) {
    try {
      masterDb
        .prepare(
          'UPDATE stripe_webhook_events SET tenant_id = ? WHERE stripe_event_id = ?',
        )
        .run(recordedTenantId, event.id);
    } catch (err: unknown) {
      logger.error('Failed to backfill tenant_id on webhook event record', {
        eventId: event.id,
        tenantId: recordedTenantId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
}

/**
 * Super-admin entry point: change a tenant's subscription plan directly via
 * Stripe. Used by the super-admin dashboard to comp, upgrade, or cancel on
 * behalf of a tenant without clicking through the Billing Portal.
 *
 * Behaviour by target plan:
 *   - 'free'       — cancel the active subscription at period end and
 *                    immediately downgrade the tenant row so the app UI
 *                    reflects the change without waiting for the webhook.
 *   - 'pro'        — if a subscription exists, swap its item to the pro
 *                    price. Otherwise the tenant has to go through Checkout
 *                    (there is no payment method on file to auto-charge).
 *   - 'enterprise' — same as 'pro' but targeting STRIPE_ENTERPRISE_PRICE_ID.
 *
 * Throws on missing config, unknown tenant, or Stripe API errors. Callers
 * should wrap in try/catch and translate into an HTTP response.
 */
export async function updateSubscription(
  tenantId: number,
  newPlan: PlanName,
): Promise<{ tenantId: number; plan: PlanName; subscriptionId: string | null }> {
  const masterDb = getMasterDb();
  if (!masterDb) {
    throw new Error('Master DB not initialized');
  }
  ensureStripeSchema(masterDb);

  const tenant = masterDb
    .prepare(
      'SELECT id, stripe_customer_id, stripe_subscription_id FROM tenants WHERE id = ?',
    )
    .get(tenantId) as
    | { id: number; stripe_customer_id: string | null; stripe_subscription_id: string | null }
    | undefined;

  if (!tenant) {
    throw new Error(`Tenant ${tenantId} not found`);
  }

  const stripe = getStripe();

  if (newPlan === 'free') {
    if (tenant.stripe_subscription_id) {
      try {
        await stripe.subscriptions.cancel(tenant.stripe_subscription_id);
      } catch (err: unknown) {
        logger.error('Failed to cancel Stripe subscription', {
          tenantId,
          subscriptionId: tenant.stripe_subscription_id,
          error: err instanceof Error ? err.message : String(err),
        });
        throw err;
      }
    }

    masterDb
      .prepare(
        `UPDATE tenants
            SET plan = 'free',
                stripe_subscription_id = NULL,
                failed_charge_count = 0,
                payment_past_due = 0,
                updated_at = datetime('now')
          WHERE id = ?`,
      )
      .run(tenantId);

    clearPlanCache(tenantId);
    logger.info('Tenant downgraded to free via updateSubscription', { tenantId });
    return { tenantId, plan: 'free', subscriptionId: null };
  }

  // 'pro' or 'enterprise' — both require an existing Stripe subscription
  // to swap the price on. Without a subscription we can't charge without
  // a payment method, so the super-admin must send the tenant through
  // Checkout first.
  if (!tenant.stripe_subscription_id) {
    throw new Error(
      `Tenant ${tenantId} has no active Stripe subscription — cannot move to ${newPlan} directly. Send them through Checkout first.`,
    );
  }

  const newPriceId = resolvePriceIdForPlan(newPlan);

  let updatedSubscription: Stripe.Subscription;
  try {
    const current = await stripe.subscriptions.retrieve(tenant.stripe_subscription_id);
    const firstItem = current.items.data[0];
    if (!firstItem) {
      throw new Error(
        `Stripe subscription ${tenant.stripe_subscription_id} has no items`,
      );
    }

    updatedSubscription = await stripe.subscriptions.update(
      tenant.stripe_subscription_id,
      {
        items: [{ id: firstItem.id, price: newPriceId }],
        // SEC-M40: proration_behavior pinned explicitly rather than relying
        // on Stripe's API default. 'create_prorations' = tenant is billed a
        // pro-rated difference on the next invoice for any plan swap that
        // happens mid-cycle. Operators who want a different policy (for
        // example 'none' for a hard mid-cycle swap with no retroactive
        // charge, or 'always_invoice' for an immediate invoice) can set the
        // STRIPE_PRORATION_BEHAVIOR env var. Unknown values fall back to
        // 'create_prorations' so a typo can't silently disable proration.
        proration_behavior: resolveProrationBehavior(),
        metadata: { tenant_id: String(tenantId), target_plan: newPlan },
      },
    );
  } catch (err: unknown) {
    logger.error('Failed to update Stripe subscription', {
      tenantId,
      subscriptionId: tenant.stripe_subscription_id,
      newPlan,
      error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }

  masterDb
    .prepare(
      `UPDATE tenants
          SET plan = ?,
              failed_charge_count = 0,
              payment_past_due = 0,
              updated_at = datetime('now')
        WHERE id = ?`,
    )
    .run(newPlan, tenantId);

  clearPlanCache(tenantId);
  logger.info('Tenant subscription updated via updateSubscription', {
    tenantId,
    newPlan,
    subscriptionId: updatedSubscription.id,
  });

  return {
    tenantId,
    plan: newPlan,
    subscriptionId: updatedSubscription.id,
  };
}
