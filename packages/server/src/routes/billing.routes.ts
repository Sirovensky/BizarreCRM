import { Router, Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import { createCheckoutSession, createBillingPortalSession, verifyWebhook, handleWebhookEvent } from '../services/stripe.js';
import { getMasterDb } from '../db/master-connection.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';

const router = Router();

const BILLING_RATE_LIMIT_MAX = 10;       // 10 attempts
const BILLING_RATE_LIMIT_WINDOW = 600_000; // per 10 minutes

/** Per-tenant rate limit on billing endpoints to prevent DoS against Stripe API. */
function billingRateLimit(req: Request, res: Response, next: NextFunction): void {
  if (!req.tenantId) {
    next();
    return;
  }
  const key = String(req.tenantId);
  if (!checkWindowRate(req.db, 'billing', key, BILLING_RATE_LIMIT_MAX, BILLING_RATE_LIMIT_WINDOW)) {
    res.status(429).json({ success: false, message: 'Too many billing requests. Please wait a few minutes.' });
    return;
  }
  recordWindowFailure(req.db, 'billing', key, BILLING_RATE_LIMIT_WINDOW);
  next();
}

/** Validate that base domain is configured for production billing redirects. */
function validateBaseDomain(req: Request, res: Response): string | null {
  if (!config.baseDomain || config.baseDomain === 'localhost') {
    if (config.nodeEnv === 'production') {
      console.error('[Billing] BASE_DOMAIN must be set in production for billing redirects');
      res.status(500).json({ success: false, message: 'Billing is not configured. Please contact support.' });
      return null;
    }
  }
  return `https://${req.tenantSlug}.${config.baseDomain || 'localhost'}`;
}

// POST /api/v1/billing/checkout — Create Stripe Checkout session
router.post('/checkout', billingRateLimit, async (req: Request, res: Response) => {
  if (!config.multiTenant || !req.tenantId || !req.tenantSlug) {
    res.status(400).json({ success: false, message: 'Billing is only available for hosted tenants' });
    return;
  }

  try {
    const masterDb = getMasterDb();
    const tenant = masterDb?.prepare('SELECT admin_email FROM tenants WHERE id = ?').get(req.tenantId) as { admin_email: string } | undefined;
    if (!tenant) {
      res.status(404).json({ success: false, message: 'Tenant not found' });
      return;
    }

    const baseUrl = validateBaseDomain(req, res);
    if (!baseUrl) return; // response already sent

    const url = await createCheckoutSession(req.tenantId, req.tenantSlug, tenant.admin_email, baseUrl);
    res.json({ success: true, data: { url } });
  } catch (e: unknown) {
    const err = e as Error;
    console.error('[Billing] Checkout error:', err.message);
    res.status(500).json({ success: false, message: 'Unable to start checkout. Please try again or contact support.' });
  }
});

// GET /api/v1/billing/portal — Get Stripe Customer Portal URL
router.get('/portal', billingRateLimit, async (req: Request, res: Response) => {
  if (!config.multiTenant || !req.tenantId || !req.tenantSlug) {
    res.status(400).json({ success: false, message: 'Billing is only available for hosted tenants' });
    return;
  }

  try {
    const masterDb = getMasterDb();
    const tenant = masterDb?.prepare('SELECT stripe_customer_id FROM tenants WHERE id = ?').get(req.tenantId) as { stripe_customer_id: string | null } | undefined;
    if (!tenant?.stripe_customer_id) {
      res.status(400).json({ success: false, message: 'No Stripe customer found. Please upgrade to Pro first.' });
      return;
    }

    const baseUrl = validateBaseDomain(req, res);
    if (!baseUrl) return;

    const url = await createBillingPortalSession(tenant.stripe_customer_id, `${baseUrl}/settings/billing`);
    res.json({ success: true, data: { url } });
  } catch (e: unknown) {
    const err = e as Error;
    console.error('[Billing] Portal error:', err.message);
    res.status(500).json({ success: false, message: 'Unable to open billing portal. Please try again or contact support.' });
  }
});

// POST /api/v1/billing/webhook — Stripe webhook handler (raw body required)
// Mounted separately in index.ts with express.raw()
export const webhookHandler = async (req: Request, res: Response) => {
  const sig = req.headers['stripe-signature'] as string;
  if (!sig) {
    res.status(400).send('Missing stripe-signature header');
    return;
  }

  try {
    const event = verifyWebhook(req.body, sig);
    handleWebhookEvent(event);
    res.json({ received: true });
  } catch (e: unknown) {
    const err = e as Error;
    console.error('[Stripe Webhook] Verification failed:', err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
  }
};

export default router;
