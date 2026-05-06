import crypto from 'crypto';
import Stripe from 'stripe';
import type Database from 'better-sqlite3';
import { AppError } from '../middleware/errorHandler.js';
import { getConfigValue } from '../utils/configEncryption.js';
import { roundCents } from '../utils/validate.js';

const STRIPE_API_VERSION = '2026-03-25.dahlia';

const STRIPE_SECRET_RE = /^sk_(test|live)_[A-Za-z0-9_]+$/;
const STRIPE_PUBLISHABLE_RE = /^pk_(test|live)_[A-Za-z0-9_]+$/;
const STRIPE_WEBHOOK_SECRET_RE = /^whsec_[A-Za-z0-9_]+$/;
const STRIPE_PAYMENT_INTENT_RE = /^pi_[A-Za-z0-9_]+$/;

export interface TenantStripeConfig {
  secretKey: string;
  publishableKey: string;
  webhookSecret: string;
  enabled: boolean;
}

export interface TenantStripeTestInput {
  secretKey?: string;
  publishableKey?: string;
  webhookSecret?: string;
}

export interface TenantStripeTestResult {
  success: boolean;
  accountId?: string;
  displayName?: string | null;
  livemode?: boolean;
  error?: string;
}

interface StripeCheckoutInput {
  tenantSlug: string | null;
  paymentLinkId: number;
  token: string;
  amountCents: number;
  description: string;
  invoiceId?: number | null;
  customerId?: number | null;
  successUrl: string;
  cancelUrl: string;
}

interface TenantPaymentIntentInput {
  amountCents: number;
  invoiceId?: number | null;
  customerId?: number | null;
  source: 'pos' | 'invoice' | 'payment_link';
  createdByUserId?: number | null;
  idempotencyKey?: string | null;
}

export interface TenantStripePaymentIntentResult {
  paymentIntentId: string;
  clientSecret: string | null;
  publishableKey: string;
}

export interface VerifiedStripePaymentIntent {
  id: string;
  amountReceivedCents: number;
  currency: string;
  status: string;
  latestChargeId: string | null;
  paymentMethodDetail: string;
  raw: Record<string, unknown>;
}

export interface TenantStripeRefundResult {
  success: boolean;
  refundId?: string;
  status?: string;
  raw?: Record<string, unknown>;
  error?: string;
}

export interface TenantStripeWebhookResult {
  status: 'processed' | 'ignored' | 'duplicate';
  paymentLinkId?: number;
  paymentIntentId?: string | null;
  message?: string;
}

export interface VerifyTenantStripePaymentIntentOptions {
  expectedInvoiceId?: number | string | null;
  expectedCustomerId?: number | string | null;
  allowedSources?: Array<'pos' | 'invoice' | 'payment_link'>;
}

function clean(value: string | null | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}

function readStoreCurrency(db: Database.Database): string {
  const configured = clean(getConfigValue(db, 'store_currency')).toUpperCase();
  return /^[A-Z]{3}$/.test(configured) ? configured.toLowerCase() : 'usd';
}

function dollarsFromCents(cents: number): number {
  return roundCents(cents / 100);
}

function centsFromDollars(amount: number): number {
  return Math.round(roundCents(amount) * 100);
}

function summarizeStripeError(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err) {
    return String((err as { message?: unknown }).message || 'Stripe request failed');
  }
  return 'Stripe request failed';
}

function createStripeClient(secretKey: string): Stripe {
  return new Stripe(secretKey, {
    apiVersion: STRIPE_API_VERSION,
    timeout: 15_000,
    maxNetworkRetries: 2,
  });
}

function requireValidSecret(secretKey: string): void {
  if (!STRIPE_SECRET_RE.test(secretKey)) {
    throw new AppError('Stripe secret key must start with sk_test_ or sk_live_', 400);
  }
}

function normalizePaymentIntentId(value: string | null | undefined): string {
  const id = clean(value);
  if (!STRIPE_PAYMENT_INTENT_RE.test(id)) {
    throw new AppError('A valid Stripe PaymentIntent id is required', 400);
  }
  return id;
}

function normalizeStripeObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object') return {};
  const raw = value as Record<string, unknown>;
  return {
    id: raw.id,
    object: raw.object,
    amount: raw.amount,
    amount_received: raw.amount_received,
    amount_total: raw.amount_total,
    currency: raw.currency,
    status: raw.status,
    payment_status: raw.payment_status,
    payment_intent: raw.payment_intent,
    latest_charge: raw.latest_charge,
    livemode: raw.livemode,
    metadata: raw.metadata,
  };
}

export function getTenantStripeConfig(db: Database.Database): TenantStripeConfig {
  const secretKey = clean(getConfigValue(db, 'stripe_secret_key'));
  const publishableKey = clean(getConfigValue(db, 'stripe_publishable_key'));
  const webhookSecret = clean(getConfigValue(db, 'stripe_webhook_secret'));
  return {
    secretKey,
    publishableKey,
    webhookSecret,
    enabled: Boolean(secretKey && publishableKey),
  };
}

export function isTenantStripeEnabled(db: Database.Database): boolean {
  return getTenantStripeConfig(db).enabled;
}

export function isTenantStripeCheckoutEnabled(db: Database.Database): boolean {
  const cfg = getTenantStripeConfig(db);
  return Boolean(cfg.secretKey && cfg.publishableKey && cfg.webhookSecret);
}

export function getTenantStripeClient(db: Database.Database): Stripe {
  const cfg = getTenantStripeConfig(db);
  if (!cfg.secretKey) {
    throw new AppError('Tenant Stripe secret key is not configured', 400);
  }
  requireValidSecret(cfg.secretKey);
  return createStripeClient(cfg.secretKey);
}

export async function testTenantStripeConnection(input: TenantStripeTestInput): Promise<TenantStripeTestResult> {
  const secretKey = clean(input.secretKey);
  const publishableKey = clean(input.publishableKey);
  const webhookSecret = clean(input.webhookSecret);

  if (!STRIPE_SECRET_RE.test(secretKey)) {
    return { success: false, error: 'Secret key must start with sk_test_ or sk_live_' };
  }
  if (publishableKey && !STRIPE_PUBLISHABLE_RE.test(publishableKey)) {
    return { success: false, error: 'Publishable key must start with pk_test_ or pk_live_' };
  }
  if (webhookSecret && !STRIPE_WEBHOOK_SECRET_RE.test(webhookSecret)) {
    return { success: false, error: 'Webhook secret must start with whsec_' };
  }

  try {
    const stripe = createStripeClient(secretKey);
    const account = await stripe.accounts.retrieveCurrent();
    return {
      success: true,
      accountId: account.id,
      displayName: account.settings?.dashboard?.display_name ?? account.business_profile?.name ?? null,
      livemode: secretKey.startsWith('sk_live_'),
    };
  } catch (err) {
    return { success: false, error: summarizeStripeError(err) };
  }
}

export async function createTenantStripeCheckoutSession(
  db: Database.Database,
  input: StripeCheckoutInput,
): Promise<Stripe.Checkout.Session> {
  const cfg = getTenantStripeConfig(db);
  if (!cfg.enabled) {
    throw new AppError('Stripe checkout is not configured for this shop', 400);
  }
  if (!cfg.webhookSecret || !STRIPE_WEBHOOK_SECRET_RE.test(cfg.webhookSecret)) {
    throw new AppError('Stripe checkout requires a valid webhook signing secret', 400);
  }
  requireValidSecret(cfg.secretKey);

  const stripe = createStripeClient(cfg.secretKey);
  const currency = readStoreCurrency(db);
  const idempotencyKey = crypto
    .createHash('sha256')
    .update(`tenant-payment-link:${input.tenantSlug ?? 'single'}:${input.paymentLinkId}:${input.token}:${input.amountCents}`)
    .digest('hex');

  return stripe.checkout.sessions.create(
    {
      mode: 'payment',
      success_url: input.successUrl,
      cancel_url: input.cancelUrl,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency,
            unit_amount: input.amountCents,
            product_data: {
              name: input.description.slice(0, 120) || 'Invoice payment',
            },
          },
        },
      ],
      metadata: {
        source: 'payment_link',
        tenant_slug: input.tenantSlug ?? '',
        payment_link_id: String(input.paymentLinkId),
        payment_link_token: input.token,
        invoice_id: input.invoiceId ? String(input.invoiceId) : '',
        customer_id: input.customerId ? String(input.customerId) : '',
      },
      payment_intent_data: {
        metadata: {
          source: 'payment_link',
          tenant_slug: input.tenantSlug ?? '',
          payment_link_id: String(input.paymentLinkId),
          payment_link_token: input.token,
          invoice_id: input.invoiceId ? String(input.invoiceId) : '',
          customer_id: input.customerId ? String(input.customerId) : '',
        },
      },
    },
    { idempotencyKey },
  );
}

export async function createTenantStripePaymentIntent(
  db: Database.Database,
  input: TenantPaymentIntentInput,
): Promise<TenantStripePaymentIntentResult> {
  const cfg = getTenantStripeConfig(db);
  if (!cfg.enabled) {
    throw new AppError('Stripe is not configured for this shop', 400);
  }
  requireValidSecret(cfg.secretKey);

  const stripe = createStripeClient(cfg.secretKey);
  const currency = readStoreCurrency(db);
  const intent = await stripe.paymentIntents.create(
    {
      amount: input.amountCents,
      currency,
      automatic_payment_methods: { enabled: true },
      metadata: {
        source: input.source,
        invoice_id: input.invoiceId ? String(input.invoiceId) : '',
        customer_id: input.customerId ? String(input.customerId) : '',
        created_by_user_id: input.createdByUserId ? String(input.createdByUserId) : '',
      },
    },
    input.idempotencyKey ? { idempotencyKey: input.idempotencyKey } : undefined,
  );

  return {
    paymentIntentId: intent.id,
    clientSecret: intent.client_secret,
    publishableKey: cfg.publishableKey,
  };
}

export async function verifyTenantStripePaymentIntent(
  db: Database.Database,
  paymentIntentIdRaw: string | null | undefined,
  expectedAmountCents: number,
  options: VerifyTenantStripePaymentIntentOptions = {},
): Promise<VerifiedStripePaymentIntent> {
  const paymentIntentId = normalizePaymentIntentId(paymentIntentIdRaw);
  const stripe = getTenantStripeClient(db);
  const intent = await stripe.paymentIntents.retrieve(paymentIntentId, {
    expand: ['latest_charge'],
  });

  if (intent.status !== 'succeeded') {
    throw new AppError(`Stripe PaymentIntent is ${intent.status}, not succeeded`, 400);
  }

  const amountReceived = Number(intent.amount_received ?? intent.amount ?? 0);
  if (!Number.isFinite(amountReceived) || amountReceived !== expectedAmountCents) {
    throw new AppError('Stripe PaymentIntent amount does not match this payment', 400);
  }

  const expectedCurrency = readStoreCurrency(db);
  if (intent.currency && intent.currency.toLowerCase() !== expectedCurrency) {
    throw new AppError(`Stripe PaymentIntent currency ${intent.currency.toUpperCase()} does not match shop currency ${expectedCurrency.toUpperCase()}`, 400);
  }

  const metadata = intent.metadata ?? {};
  const source = clean(metadata.source);
  if (options.allowedSources?.length && !options.allowedSources.includes(source as 'pos' | 'invoice' | 'payment_link')) {
    throw new AppError('Stripe PaymentIntent was not created for this payment flow', 400);
  }
  if (options.expectedInvoiceId != null && clean(metadata.invoice_id) !== String(options.expectedInvoiceId)) {
    throw new AppError('Stripe PaymentIntent invoice metadata does not match this invoice', 400);
  }
  if (options.expectedCustomerId != null && clean(metadata.customer_id) !== String(options.expectedCustomerId)) {
    throw new AppError('Stripe PaymentIntent customer metadata does not match this invoice', 400);
  }

  const latestCharge = typeof intent.latest_charge === 'string'
    ? intent.latest_charge
    : intent.latest_charge?.id ?? null;
  const methodDetail = latestCharge ? `Stripe charge ${latestCharge}` : 'Stripe payment';

  return {
    id: intent.id,
    amountReceivedCents: amountReceived,
    currency: intent.currency,
    status: intent.status,
    latestChargeId: latestCharge,
    paymentMethodDetail: methodDetail,
    raw: normalizeStripeObject(intent),
  };
}

export async function refundTenantStripePayment(
  db: Database.Database,
  paymentIntentIdRaw: string,
  amountDollars: number,
  refundId: string,
): Promise<TenantStripeRefundResult> {
  try {
    const paymentIntentId = normalizePaymentIntentId(paymentIntentIdRaw);
    const stripe = getTenantStripeClient(db);
    const refund = await stripe.refunds.create(
      {
        payment_intent: paymentIntentId,
        amount: centsFromDollars(amountDollars),
        metadata: {
          source: 'bizarre_crm_refund',
          refund_id: refundId,
        },
      },
      { idempotencyKey: `tenant-refund:${refundId}:${paymentIntentId}:${centsFromDollars(amountDollars)}` },
    );
    return {
      success: true,
      refundId: refund.id,
      status: refund.status ?? undefined,
      raw: normalizeStripeObject(refund),
    };
  } catch (err) {
    return { success: false, error: summarizeStripeError(err) };
  }
}

export function verifyTenantStripeWebhook(
  db: Database.Database,
  payload: Buffer | string,
  signature: string,
): Stripe.Event {
  const cfg = getTenantStripeConfig(db);
  if (!cfg.secretKey || !cfg.webhookSecret) {
    throw new AppError('Stripe webhook is not configured for this shop', 400);
  }
  requireValidSecret(cfg.secretKey);
  const stripe = createStripeClient(cfg.secretKey);
  return stripe.webhooks.constructEvent(payload, signature, cfg.webhookSecret);
}

function getPaymentIntentId(value: Stripe.Checkout.Session | Stripe.PaymentIntent): string | null {
  const raw = 'payment_intent' in value ? value.payment_intent : value.id;
  if (typeof raw === 'string') return raw;
  if (raw && typeof raw === 'object' && 'id' in raw) return String(raw.id);
  return null;
}

function readWebhookEventRow(db: Database.Database, eventId: string): { status: string } | undefined {
  return db
    .prepare('SELECT status FROM tenant_stripe_webhook_events WHERE stripe_event_id = ?')
    .get(eventId) as { status: string } | undefined;
}

function reserveWebhookEvent(db: Database.Database, event: Stripe.Event): boolean {
  const existing = readWebhookEventRow(db, event.id);
  if (existing?.status === 'processed' || existing?.status === 'ignored') return false;
  if (existing?.status === 'failed') {
    db.prepare(`
      UPDATE tenant_stripe_webhook_events
         SET status = 'processing', error = NULL, updated_at = datetime('now')
       WHERE stripe_event_id = ?
    `).run(event.id);
    return true;
  }
  if (existing?.status === 'processing') return false;
  db.prepare(`
    INSERT INTO tenant_stripe_webhook_events (stripe_event_id, event_type, status)
    VALUES (?, ?, 'processing')
  `).run(event.id, event.type);
  return true;
}

function completeWebhookEvent(
  db: Database.Database,
  eventId: string,
  status: 'processed' | 'ignored' | 'failed',
  options: { paymentLinkId?: number | null; paymentIntentId?: string | null; error?: string | null } = {},
): void {
  db.prepare(`
    UPDATE tenant_stripe_webhook_events
       SET status = ?,
           payment_link_id = COALESCE(?, payment_link_id),
           payment_intent_id = COALESCE(?, payment_intent_id),
           error = ?,
           updated_at = datetime('now'),
           processed_at = datetime('now')
     WHERE stripe_event_id = ?
  `).run(status, options.paymentLinkId ?? null, options.paymentIntentId ?? null, options.error ?? null, eventId);
}

function resolveSystemUserId(db: Database.Database, preferred: number | null | undefined): number {
  if (preferred) {
    const preferredRow = db.prepare('SELECT id FROM users WHERE id = ?').get(preferred) as { id: number } | undefined;
    if (preferredRow?.id) return preferredRow.id;
  }
  const admin = db
    .prepare("SELECT id FROM users WHERE role IN ('admin', 'owner') AND is_active = 1 ORDER BY id ASC LIMIT 1")
    .get() as { id: number } | undefined;
  if (admin?.id) return admin.id;
  const anyUser = db
    .prepare('SELECT id FROM users WHERE is_active = 1 ORDER BY id ASC LIMIT 1')
    .get() as { id: number } | undefined;
  if (anyUser?.id) return anyUser.id;
  throw new AppError('Cannot record Stripe payment: no active user exists for payment attribution', 500);
}

function paymentLinkIdFromMetadata(metadata: Stripe.Metadata | null | undefined): number | null {
  const raw = clean(metadata?.payment_link_id);
  if (!/^\d+$/.test(raw)) return null;
  const id = Number(raw);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}

function markPaymentLinkPaidFromSession(
  db: Database.Database,
  tenantSlug: string | null,
  session: Stripe.Checkout.Session,
): { paymentLinkId: number; paymentIntentId: string | null } {
  const paymentLinkId = paymentLinkIdFromMetadata(session.metadata);
  const token = clean(session.metadata?.payment_link_token);
  if (!paymentLinkId || !token) {
    throw new AppError('Stripe session missing payment link metadata', 400);
  }

  const paymentIntentId = getPaymentIntentId(session);
  const amountTotal = Number(session.amount_total ?? 0);
  const link = db.prepare(`
    SELECT id, token, invoice_id, customer_id, amount_cents, status, created_by_user_id
      FROM payment_links
     WHERE id = ? AND token = ? AND provider = 'stripe'
  `).get(paymentLinkId, token) as {
    id: number;
    token: string;
    invoice_id: number | null;
    customer_id: number | null;
    amount_cents: number;
    status: string;
    created_by_user_id: number | null;
  } | undefined;

  if (!link) throw new AppError('Payment link not found for Stripe session', 404);
  if (link.status === 'paid') return { paymentLinkId: link.id, paymentIntentId };
  if (link.status !== 'active') throw new AppError(`Payment link is ${link.status}, not active`, 409);
  if (amountTotal !== Number(link.amount_cents)) {
    throw new AppError('Stripe session amount does not match payment link amount', 400);
  }
  if (session.payment_status && session.payment_status !== 'paid') {
    throw new AppError(`Stripe session payment_status is ${session.payment_status}`, 400);
  }

  const paymentAmount = dollarsFromCents(link.amount_cents);
  const responseJson = JSON.stringify(normalizeStripeObject(session));

  const tx = db.transaction(() => {
    db.prepare(`
      UPDATE payment_links
         SET status = 'paid',
             paid_at = datetime('now'),
             processor_checkout_id = ?,
             processor_payment_intent_id = ?,
             processor_checkout_url = COALESCE(?, processor_checkout_url),
             processor_status = 'paid',
             processor_response = ?
       WHERE id = ? AND status = 'active'
    `).run(session.id, paymentIntentId, session.url ?? null, responseJson, link.id);

    if (!link.invoice_id) return;

    const existingPayment = paymentIntentId
      ? db.prepare(`
          SELECT id FROM payments
           WHERE invoice_id = ?
             AND processor = 'stripe'
             AND COALESCE(processor_transaction_id, transaction_id, reference) = ?
           LIMIT 1
        `).get(link.invoice_id, paymentIntentId) as { id: number } | undefined
      : undefined;
    if (existingPayment) return;

    const invoice = db.prepare('SELECT id, total, amount_paid, status FROM invoices WHERE id = ?').get(link.invoice_id) as {
      id: number;
      total: number;
      amount_paid: number;
      status: string;
    } | undefined;
    if (!invoice) throw new AppError('Invoice not found for Stripe payment link', 404);
    if (invoice.status === 'void') throw new AppError('Cannot apply Stripe payment to a voided invoice', 400);

    const userId = resolveSystemUserId(db, link.created_by_user_id);
    db.prepare(`
      INSERT INTO payments (
        invoice_id, amount, method, method_detail, transaction_id,
        processor, reference, processor_transaction_id, processor_response,
        capture_state, notes, user_id, created_at, updated_at
      )
      VALUES (?, ?, 'Stripe', 'Stripe Checkout', ?, 'stripe', ?, ?, ?, 'captured', ?, ?, datetime('now'), datetime('now'))
    `).run(
      link.invoice_id,
      paymentAmount,
      paymentIntentId,
      session.id,
      paymentIntentId,
      responseJson,
      tenantSlug ? `Paid via Stripe checkout for ${tenantSlug}` : 'Paid via Stripe checkout',
      userId,
    );

    const newPaid = roundCents(Number(invoice.amount_paid || 0) + paymentAmount);
    const newDue = roundCents(Math.max(0, Number(invoice.total || 0) - newPaid));
    const newStatus = newDue <= 0 ? 'paid' : 'partial';
    db.prepare(`
      UPDATE invoices
         SET amount_paid = ?, amount_due = ?, status = ?, updated_at = datetime('now')
       WHERE id = ?
    `).run(newPaid, newDue, newStatus, invoice.id);
  });

  tx();
  return { paymentLinkId: link.id, paymentIntentId };
}

function markPaymentLinkPaidFromPaymentIntent(
  db: Database.Database,
  tenantSlug: string | null,
  intent: Stripe.PaymentIntent,
): { paymentLinkId: number; paymentIntentId: string | null } {
  const syntheticSession = {
    id: `pi-event:${intent.id}`,
    object: 'checkout.session',
    payment_intent: intent.id,
    payment_status: 'paid',
    amount_total: intent.amount_received || intent.amount,
    metadata: intent.metadata,
    url: null,
  } as unknown as Stripe.Checkout.Session;
  return markPaymentLinkPaidFromSession(db, tenantSlug, syntheticSession);
}

export function handleTenantStripeEvent(
  db: Database.Database,
  tenantSlug: string | null,
  event: Stripe.Event,
): TenantStripeWebhookResult {
  try {
    const processEvent = db.transaction((): TenantStripeWebhookResult => {
      const reserved = reserveWebhookEvent(db, event);
      if (!reserved) return { status: 'duplicate', message: 'Event already handled or currently processing' };

      if (event.type === 'checkout.session.completed' || event.type === 'checkout.session.async_payment_succeeded') {
        const session = event.data.object as Stripe.Checkout.Session;
        if (session.metadata?.source !== 'payment_link') {
          completeWebhookEvent(db, event.id, 'ignored');
          return { status: 'ignored', message: 'Checkout session source is not payment_link' };
        }
        const result = markPaymentLinkPaidFromSession(db, tenantSlug, session);
        completeWebhookEvent(db, event.id, 'processed', result);
        return { status: 'processed', ...result };
      }

      if (event.type === 'payment_intent.succeeded') {
        const intent = event.data.object as Stripe.PaymentIntent;
        if (intent.metadata?.source !== 'payment_link') {
          completeWebhookEvent(db, event.id, 'ignored', { paymentIntentId: intent.id });
          return { status: 'ignored', paymentIntentId: intent.id, message: 'PaymentIntent source is not payment_link' };
        }
        const result = markPaymentLinkPaidFromPaymentIntent(db, tenantSlug, intent);
        completeWebhookEvent(db, event.id, 'processed', result);
        return { status: 'processed', ...result };
      }

      completeWebhookEvent(db, event.id, 'ignored');
      return { status: 'ignored', message: `Unhandled event type ${event.type}` };
    });
    return processEvent();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    db.prepare(`
      INSERT INTO tenant_stripe_webhook_events (stripe_event_id, event_type, status, error, processed_at, updated_at)
      VALUES (?, ?, 'failed', ?, datetime('now'), datetime('now'))
      ON CONFLICT(stripe_event_id) DO UPDATE SET
        status = 'failed',
        error = excluded.error,
        processed_at = datetime('now'),
        updated_at = datetime('now')
    `).run(event.id, event.type, message);
    throw err;
  }
}
