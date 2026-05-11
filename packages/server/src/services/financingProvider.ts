/**
 * Financing provider abstraction — WEB-UNWIRED-007.
 *
 * Wraps Affirm and Klarna behind one interface so the route handler is
 * provider-agnostic. Real provider HTTP calls are gated on credentials —
 * with an empty `provider_key` we return `not_configured` so the UI can
 * surface a clear "Settings → Payments" prompt instead of shipping a
 * silently-broken integration.
 *
 * Adding a real provider:
 *   1. Drop the API key into Settings → Payments → Financing.
 *   2. Implement the matching `createCheckoutSession()` body below
 *      (Affirm: POST /api/v2/checkout; Klarna: POST /payments/v1/sessions).
 *   3. Implement `verifyWebhookSignature()` for that provider's HMAC spec.
 *   4. Add the success/failure status mapping in `parseWebhookEvent()`.
 *
 * No live HTTP call is made in this file yet. Doing so without real
 * sandbox credentials would create an unverifiable money-flow stub, which
 * is exactly what WEB-UNWIRED-007 explicitly forbids.
 */
import crypto from 'crypto';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('financingProvider');

export type FinancingProvider = 'affirm' | 'klarna';

export interface FinancingConfig {
  enabled: boolean;
  minCents: number;
  provider: FinancingProvider | null;
  providerKey: string;
  webhookSecret: string;
  returnUrl: string;
  cancelUrl: string;
}

export interface CheckoutSessionRequest {
  invoiceId: number;
  amountCents: number;
  currency: string;
  customer: {
    email: string | null;
    firstName: string | null;
    lastName: string | null;
    phone: string | null;
  };
  metadata: Record<string, string | number>;
}

export type CheckoutSessionResult =
  | { ok: true; redirectUrl: string; providerSessionId: string; provider: FinancingProvider }
  | { ok: false; code: 'not_configured' | 'unsupported_provider' | 'amount_below_minimum' | 'provider_error'; message: string };

export type WebhookEvent =
  | { ok: true; provider: FinancingProvider; eventType: 'authorized' | 'captured' | 'declined' | 'voided'; providerSessionId: string; amountCents: number | null }
  | { ok: false; code: 'invalid_signature' | 'unsupported_provider' | 'malformed_payload'; message: string };

/**
 * Decide whether a financing-checkout request is acceptable + which
 * provider to hand it to. Pure function over config + request — does not
 * perform any HTTP call, so it is safe to call eagerly to gate the UI.
 */
export function classifyCheckoutRequest(
  cfg: FinancingConfig,
  req: CheckoutSessionRequest,
): { ok: true } | { ok: false; code: 'not_configured' | 'unsupported_provider' | 'amount_below_minimum'; message: string } {
  if (!cfg.enabled) {
    return { ok: false, code: 'not_configured', message: 'Financing is not enabled for this shop.' };
  }
  if (!cfg.provider) {
    return { ok: false, code: 'unsupported_provider', message: 'No financing provider selected. Settings → Payments → Financing.' };
  }
  if (cfg.provider !== 'affirm' && cfg.provider !== 'klarna') {
    return { ok: false, code: 'unsupported_provider', message: `Unsupported financing provider "${cfg.provider}".` };
  }
  if (!cfg.providerKey.trim()) {
    return { ok: false, code: 'not_configured', message: 'Financing API key missing. Settings → Payments → Financing.' };
  }
  if (!Number.isFinite(req.amountCents) || req.amountCents < cfg.minCents) {
    return { ok: false, code: 'amount_below_minimum', message: `Minimum financed amount is ${(cfg.minCents / 100).toFixed(2)}.` };
  }
  return { ok: true };
}

/**
 * Create a hosted-checkout session with the configured provider. Until live
 * sandbox credentials land, this returns `not_configured` so the UI surfaces
 * "needs setup" rather than a fake redirect.
 *
 * The two TODOs below are the only places to fill in once Affirm/Klarna
 * sandbox keys are provisioned in Settings → Payments → Financing.
 */
export async function createCheckoutSession(
  cfg: FinancingConfig,
  req: CheckoutSessionRequest,
): Promise<CheckoutSessionResult> {
  const classify = classifyCheckoutRequest(cfg, req);
  if (!classify.ok) {
    return classify;
  }
  // Below this point cfg.provider, cfg.providerKey, and the amount are all
  // validated. cfg.provider is narrowed to 'affirm' | 'klarna'.
  const provider = cfg.provider!;

  // TODO(WEB-UNWIRED-007 follow-up): replace the stub with the real call.
  //   Affirm:  POST https://api.affirm.com/api/v2/checkout
  //   Klarna:  POST https://api.klarna.com/payments/v1/sessions
  // Use `cfg.providerKey` for Basic auth (Affirm) or HTTP-Basic
  // public:private (Klarna). On success return ok=true + redirectUrl.
  logger.info('financing.createCheckoutSession invoked (stub)', {
    provider, invoiceId: req.invoiceId, amountCents: req.amountCents,
  });
  return {
    ok: false,
    code: 'not_configured',
    message: 'Financing provider integration is scaffolded but not yet implemented. Provide sandbox credentials and complete the TODO in services/financingProvider.ts.',
  };
}

/**
 * Verify the HMAC signature on an inbound financing webhook payload.
 * Each provider uses a different scheme — Affirm: HMAC-SHA256 over the
 * raw body, header `X-Affirm-Signature`; Klarna: ECDSA signed against
 * payload + nonce, header `Klarna-Signature`. Until the matching key
 * lands in `billing_financing_webhook_secret`, every signature is
 * rejected so unauthenticated callers cannot forge an "authorized"
 * event.
 */
export function verifyWebhookSignature(
  cfg: FinancingConfig,
  provider: FinancingProvider,
  signatureHeader: string | null,
  rawBody: Buffer,
): boolean {
  if (!cfg.webhookSecret) return false;
  if (!signatureHeader) return false;

  // Generic HMAC-SHA256 verification (works for Affirm and any
  // provider that uses raw-body HMAC). Klarna's ECDSA scheme needs a
  // separate code path; left as TODO when their integration lands.
  if (provider === 'affirm') {
    const expected = crypto
      .createHmac('sha256', cfg.webhookSecret)
      .update(rawBody)
      .digest('hex');
    try {
      return crypto.timingSafeEqual(
        Buffer.from(expected, 'hex'),
        Buffer.from(signatureHeader.replace(/^sha256=/, ''), 'hex'),
      );
    } catch {
      return false;
    }
  }
  if (provider === 'klarna') {
    // TODO(WEB-UNWIRED-007 follow-up): Klarna uses ECDSA over the body +
    // a nonce. Implement when the Klarna webhook key + cert land.
    logger.warn('klarna webhook verification not implemented — rejecting');
    return false;
  }
  return false;
}

/**
 * Map a verified provider payload onto our internal event shape.
 * No-ops with `unsupported_provider` until the provider integration is
 * filled in — keeps the receiver side ready without acting on bad data.
 */
export function parseWebhookEvent(
  provider: FinancingProvider,
  _payload: unknown,
): WebhookEvent {
  // TODO(WEB-UNWIRED-007 follow-up): map provider event shapes.
  return {
    ok: false,
    code: 'unsupported_provider',
    message: `Webhook parsing for ${provider} is scaffolded but not yet implemented.`,
  };
}
