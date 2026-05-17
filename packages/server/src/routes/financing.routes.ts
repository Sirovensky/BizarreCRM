/**
 * Financing routes — WEB-UNWIRED-007.
 *
 * POST /api/v1/financing/checkout-session — staff-authenticated. Reads
 *   the tenant's per-store financing config (provider / API key /
 *   thresholds), validates the invoice + amount, and returns either a
 *   provider redirect URL or `not_configured` with a clear remediation
 *   message. Real provider HTTP call is stubbed in services/financingProvider
 *   until live sandbox credentials are provisioned (intentional — see
 *   WEB-UNWIRED-007 acceptance criteria).
 *
 * POST /api/v1/financing/webhook/:provider — unauthenticated. Verifies
 *   HMAC signature using the tenant's `billing_financing_webhook_secret`
 *   then dispatches to the provider-specific event parser. Until the
 *   provider integration lands, signatures are rejected by default so a
 *   forged "authorized" event cannot mark an invoice paid.
 */
import { Router, Request, Response } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { authMiddleware } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  createCheckoutSession,
  verifyWebhookSignature,
  parseWebhookEvent,
  type FinancingConfig,
  type FinancingProvider,
} from '../services/financingProvider.js';
import { ENCRYPTED_CONFIG_KEYS, decryptConfigValue } from '../utils/configEncryption.js';

const router = Router();
const logger = createLogger('financing.routes');

type AnyRow = Record<string, unknown>;

async function loadFinancingConfig(asyncDb: Request['asyncDb']): Promise<FinancingConfig> {
  const rows = await asyncDb.all<AnyRow>(
    `SELECT key, value FROM store_config WHERE key IN (
      'billing_financing_enabled', 'billing_financing_min_cents',
      'billing_financing_provider', 'billing_financing_provider_key',
      'billing_financing_webhook_secret', 'billing_financing_return_url',
      'billing_financing_cancel_url'
    )`,
  );
  const map: Record<string, string> = {};
  for (const row of rows) {
    const key = row.key as string;
    const raw = (row.value as string | null) ?? '';
    map[key] = ENCRYPTED_CONFIG_KEYS.has(key) ? decryptConfigValue(raw) : raw;
  }
  const providerRaw = (map.billing_financing_provider || '').trim().toLowerCase();
  return {
    enabled: map.billing_financing_enabled === '1',
    minCents: Number.isFinite(Number(map.billing_financing_min_cents))
      ? Number(map.billing_financing_min_cents)
      : 50_000,
    provider: providerRaw === 'affirm' || providerRaw === 'klarna' ? providerRaw : null,
    providerKey: map.billing_financing_provider_key || '',
    webhookSecret: map.billing_financing_webhook_secret || '',
    returnUrl: map.billing_financing_return_url || '',
    cancelUrl: map.billing_financing_cancel_url || '',
  };
}

router.post('/checkout-session', authMiddleware, asyncHandler(async (req: Request, res: Response) => {
  const cfg = await loadFinancingConfig(req.asyncDb);
  const { invoice_id, amount_cents, customer_email, customer_first_name, customer_last_name, customer_phone } = req.body ?? {};
  const invoiceId = Number(invoice_id);
  const amountCents = Number(amount_cents);
  if (!Number.isInteger(invoiceId) || invoiceId <= 0) {
    res.status(400).json({ success: false, message: 'invoice_id is required' });
    return;
  }
  if (!Number.isFinite(amountCents) || amountCents <= 0) {
    res.status(400).json({ success: false, message: 'amount_cents must be a positive number' });
    return;
  }

  const invoice = await req.asyncDb.get<AnyRow>(
    'SELECT id, customer_id, total, amount_paid, amount_due FROM invoices WHERE id = ?',
    invoiceId,
  );
  if (!invoice) {
    res.status(404).json({ success: false, message: 'Invoice not found' });
    return;
  }

  // SEC: cap financing amount at invoice.amount_due to prevent a cashier
  // sending amount_cents=1 to finance a near-zero portion of a $500 invoice,
  // or amount_cents=999999 to over-finance.
  const dueCents = Math.round(Number(invoice.amount_due ?? 0) * 100);
  if (amountCents > dueCents) {
    res.status(400).json({ success: false, message: 'amount_cents exceeds invoice balance' });
    return;
  }

  const result = await createCheckoutSession(cfg, {
    invoiceId,
    amountCents,
    currency: 'USD',
    customer: {
      email: typeof customer_email === 'string' ? customer_email : null,
      firstName: typeof customer_first_name === 'string' ? customer_first_name : null,
      lastName: typeof customer_last_name === 'string' ? customer_last_name : null,
      phone: typeof customer_phone === 'string' ? customer_phone : null,
    },
    metadata: { invoice_id: invoiceId, tenant: (req as any).tenantSlug || 'single' },
  });

  if (!result.ok) {
    const status = result.code === 'not_configured' || result.code === 'unsupported_provider'
      ? 503
      : 400;
    audit(req.db, 'financing_checkout_session_rejected', req.user!.id, req.ip || 'unknown', {
      invoice_id: invoiceId, amount_cents: amountCents, reason: result.code,
    });
    res.status(status).json({ success: false, code: result.code, message: result.message });
    return;
  }

  audit(req.db, 'financing_checkout_session_created', req.user!.id, req.ip || 'unknown', {
    invoice_id: invoiceId, amount_cents: amountCents, provider: result.provider, provider_session_id: result.providerSessionId,
  });
  res.json({ success: true, data: { redirect_url: result.redirectUrl, provider: result.provider, provider_session_id: result.providerSessionId } });
}));

router.post('/webhook/:provider', asyncHandler(async (req: Request, res: Response) => {
  const providerParam = String(req.params.provider).toLowerCase();
  if (providerParam !== 'affirm' && providerParam !== 'klarna') {
    res.status(404).json({ success: false, code: 'unsupported_provider', message: 'Unknown financing provider.' });
    return;
  }
  const provider = providerParam as FinancingProvider;

  const cfg = await loadFinancingConfig(req.asyncDb);
  if (!cfg.enabled || !cfg.webhookSecret) {
    res.status(503).json({ success: false, code: 'not_configured', message: 'Financing webhook is not configured for this shop.' });
    return;
  }
  // Webhook receiver expects the raw body for HMAC verification; the
  // raw-body middleware should be wired ahead of this route. If req.body
  // is already parsed JSON, re-stringify for the verification step.
  const rawBody: Buffer = (req as any).rawBody
    ? (req as any).rawBody as Buffer
    : Buffer.from(JSON.stringify(req.body ?? {}), 'utf8');

  const signatureHeader = req.get('X-Affirm-Signature') || req.get('Klarna-Signature') || null;
  const ok = verifyWebhookSignature(cfg, provider, signatureHeader, rawBody);
  if (!ok) {
    logger.warn('financing webhook signature rejected', { provider, ip: req.ip });
    res.status(401).json({ success: false, code: 'invalid_signature', message: 'Signature verification failed.' });
    return;
  }

  // classifyCheckoutRequest is gated for staff-driven creations only;
  // webhook events bypass it. The parsing layer is stubbed for now.
  const event = parseWebhookEvent(provider, req.body);
  if (!event.ok) {
    logger.warn('financing webhook parse failed', { provider, code: event.code });
    res.status(501).json({ success: false, code: event.code, message: event.message });
    return;
  }

  // TODO(WEB-UNWIRED-007 follow-up): on 'authorized' / 'captured', insert
  // a payment row against the invoice and mark it paid; on 'declined' /
  // 'voided', flip the checkout-session status. Today the parser
  // returns unsupported_provider so we never reach here.
  audit(req.db, 'financing_webhook_received', null, req.ip || 'unknown', {
    provider, event_type: event.eventType, provider_session_id: event.providerSessionId,
  });
  res.json({ success: true });
}));

export default router;
