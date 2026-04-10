import Stripe from 'stripe';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { clearPlanCache } from '../middleware/tenantResolver.js';

let stripeClient: Stripe | null = null;

function getStripe(): Stripe {
  if (!stripeClient) {
    if (!config.stripeSecretKey) {
      throw new Error('STRIPE_SECRET_KEY not configured');
    }
    stripeClient = new Stripe(config.stripeSecretKey, { apiVersion: '2024-12-18.acacia' as any });
  }
  return stripeClient;
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

/** Create a Checkout Session for Pro subscription. Returns the checkout URL. */
export async function createCheckoutSession(tenantId: number, tenantSlug: string, adminEmail: string, baseUrl: string): Promise<string> {
  if (!config.stripeProPriceId) {
    throw new Error('STRIPE_PRO_PRICE_ID not configured');
  }
  const stripe = getStripe();

  // Reuse existing Stripe customer if we have one
  const masterDb = getMasterDb();
  const tenant = masterDb?.prepare('SELECT stripe_customer_id FROM tenants WHERE id = ?').get(tenantId) as { stripe_customer_id: string | null } | undefined;

  const session = await stripe.checkout.sessions.create({
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
  });

  if (!session.url) throw new Error('Stripe did not return a checkout URL');
  return session.url;
}

/** Create a Billing Portal session for managing existing subscription. */
export async function createBillingPortalSession(stripeCustomerId: string, returnUrl: string): Promise<string> {
  const stripe = getStripe();
  const session = await stripe.billingPortal.sessions.create({
    customer: stripeCustomerId,
    return_url: returnUrl,
  });
  return session.url;
}

/** Verify webhook signature and return the event. */
export function verifyWebhook(payload: Buffer, signature: string): Stripe.Event {
  if (!config.stripeWebhookSecret) {
    throw new Error('STRIPE_WEBHOOK_SECRET not configured');
  }
  const stripe = getStripe();
  return stripe.webhooks.constructEvent(payload, signature, config.stripeWebhookSecret);
}

/** Apply Stripe webhook event to master DB (update tenant plan, subscription ID).
 *  Idempotent — events that have already been processed are silently skipped. */
export function handleWebhookEvent(event: Stripe.Event): void {
  const masterDb = getMasterDb();
  if (!masterDb) return;

  // Idempotency check — skip events we've already processed
  const existing = masterDb.prepare(
    'SELECT 1 FROM stripe_webhook_events WHERE stripe_event_id = ?'
  ).get(event.id);
  if (existing) {
    console.log(`[Stripe] Event ${event.id} already processed — skipping`);
    return;
  }

  let recordedTenantId: number | null = null;

  switch (event.type) {
    case 'checkout.session.completed': {
      const session = event.data.object as Stripe.Checkout.Session;
      const tenantId = parseTenantId(session.client_reference_id);
      if (!tenantId) {
        console.warn(`[Stripe] checkout.session.completed missing/invalid client_reference_id: ${session.client_reference_id}`);
        break;
      }

      // Validate tenant exists BEFORE updating
      const existingTenant = masterDb.prepare('SELECT id FROM tenants WHERE id = ?').get(tenantId) as { id: number } | undefined;
      if (!existingTenant) {
        console.warn(`[Stripe] checkout.session.completed for unknown tenant ${tenantId} — rejecting`);
        break;
      }

      const customerId = typeof session.customer === 'string' ? session.customer : session.customer?.id;
      const subscriptionId = typeof session.subscription === 'string' ? session.subscription : session.subscription?.id;

      masterDb.prepare(`
        UPDATE tenants
        SET plan = 'pro', trial_ends_at = NULL, stripe_customer_id = ?, stripe_subscription_id = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(customerId || null, subscriptionId || null, tenantId);

      // Bust the plan cache so the upgrade is visible immediately
      clearPlanCache(tenantId);
      recordedTenantId = tenantId;
      console.log(`[Stripe] Tenant ${tenantId} upgraded to Pro via checkout (event ${event.id})`);
      break;
    }

    case 'customer.subscription.deleted': {
      const sub = event.data.object as Stripe.Subscription;
      // Validate the subscription belongs to a known tenant before downgrading
      const tenantWithSub = masterDb.prepare(
        'SELECT id FROM tenants WHERE stripe_subscription_id = ?'
      ).get(sub.id) as { id: number } | undefined;

      if (!tenantWithSub) {
        console.warn(`[Stripe] subscription.deleted for unknown subscription ${sub.id} — ignoring`);
        break;
      }

      masterDb.prepare(`
        UPDATE tenants SET plan = 'free', stripe_subscription_id = NULL, updated_at = datetime('now')
        WHERE id = ?
      `).run(tenantWithSub.id);

      clearPlanCache(tenantWithSub.id);
      recordedTenantId = tenantWithSub.id;
      console.log(`[Stripe] Subscription ${sub.id} cancelled, tenant ${tenantWithSub.id} downgraded to Free (event ${event.id})`);
      break;
    }

    case 'customer.subscription.updated': {
      const sub = event.data.object as Stripe.Subscription;
      // Validate the subscription belongs to a known tenant
      const tenantWithSub = masterDb.prepare(
        'SELECT id FROM tenants WHERE stripe_subscription_id = ?'
      ).get(sub.id) as { id: number } | undefined;

      if (!tenantWithSub) {
        console.warn(`[Stripe] subscription.updated for unknown subscription ${sub.id} — ignoring`);
        break;
      }

      if (sub.status === 'active') {
        masterDb.prepare(
          `UPDATE tenants SET plan = 'pro', updated_at = datetime('now') WHERE id = ?`
        ).run(tenantWithSub.id);
        console.log(`[Stripe] Tenant ${tenantWithSub.id} subscription active (event ${event.id})`);
      } else if (sub.status === 'canceled' || sub.status === 'unpaid') {
        masterDb.prepare(
          `UPDATE tenants SET plan = 'free', updated_at = datetime('now') WHERE id = ?`
        ).run(tenantWithSub.id);
        console.log(`[Stripe] Tenant ${tenantWithSub.id} subscription ${sub.status} — downgraded to Free (event ${event.id})`);
      }

      clearPlanCache(tenantWithSub.id);
      recordedTenantId = tenantWithSub.id;
      break;
    }

    case 'invoice.payment_failed': {
      // Log warning, optionally mark tenant
      const invoice = event.data.object as Stripe.Invoice;
      // `subscription` is not on the strict Invoice type in newer API versions,
      // but is still present in webhook payloads. Cast to unknown for safe access.
      const subscriptionRef = (invoice as unknown as { subscription?: string | { id: string } | null }).subscription;
      const subscriptionId = typeof subscriptionRef === 'string' ? subscriptionRef : subscriptionRef?.id ?? 'unknown';

      // Try to look up the tenant for audit purposes
      if (subscriptionId !== 'unknown') {
        const tenantWithSub = masterDb.prepare(
          'SELECT id FROM tenants WHERE stripe_subscription_id = ?'
        ).get(subscriptionId) as { id: number } | undefined;
        recordedTenantId = tenantWithSub?.id ?? null;
      }
      console.warn(`[Stripe] Payment failed for subscription ${subscriptionId} (event ${event.id})`);
      break;
    }
  }

  // Record this event as processed (idempotency) — wrapped in try/catch so a duplicate
  // INSERT (race between concurrent webhook deliveries) doesn't crash the handler.
  try {
    masterDb.prepare(
      'INSERT INTO stripe_webhook_events (stripe_event_id, event_type, tenant_id) VALUES (?, ?, ?)'
    ).run(event.id, event.type, recordedTenantId);
  } catch (err) {
    console.error('[Stripe] Failed to record webhook event:', (err as Error).message);
  }
}
