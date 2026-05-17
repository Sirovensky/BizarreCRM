/**
 * Payment Links routes — audit §52 idea 1.
 *
 * Mounted twice in index.ts:
 *   /api/v1/payment-links          (auth required - CRUD for staff)
 *   /api/v1/public/payment-links   (no auth - read-only lookup + click tracking)
 *
 * Response shape: `{ success: true, data: X }`.
 * All money is INTEGER cents.
 */
import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import { config } from '../config.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { createPaymentLink, isBlockChypEnabled } from '../services/blockchyp.js';
import { createTenantStripeCheckoutSession, isTenantStripeCheckoutEnabled } from '../services/tenantStripe.js';
import {
  validatePositiveAmount,
  validateIsoDate,
  validateEnum,
  validateTextLength,
  validateIntegerQuantity,
} from '../utils/validate.js';

const logger = createLogger('billing-enrich');

type Row = Record<string, any>;

const authedRouter = Router();
const publicRouter = Router();

// SEC (post-enrichment audit §6): payment-link creation/cancellation is
// manager/admin only — the link is an implicit invoice-to-pay authorization.
function requireManagerOrAdmin(req: Request): void {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function generateToken(): string {
  // 24 bytes → 32-char URL-safe string. Plenty of entropy for a public token.
  return crypto.randomBytes(24).toString('base64url');
}

// SEC-L29: validate the token shape on public endpoints. Prior guard only
// required `length >= 8`, which let an attacker submit any 8-char string
// into DB lookups — enumerating the 62^8 space is fast enough on a public
// URL. The generator always emits a 32-char base64url string (24 bytes),
// so a stricter regex matches the generator exactly and rejects anything
// that can't possibly be a real token.
const TOKEN_REGEX = /^[A-Za-z0-9_-]{32}$/;

function nowIso(): string {
  return new Date().toISOString();
}

// BUGHUNT-2026-05-16: the /pay and /:token/pay handlers are PUBLIC (no auth)
// and were composing redirect / webhook URLs from req.headers['x-forwarded-host']
// and req.headers['x-forwarded-proto'] without verifying the request actually
// came from a trusted reverse proxy. An unauthenticated attacker could send a
// crafted POST with X-Forwarded-Host: attacker.com and Stripe / BlockChyp
// would then redirect the customer (or POST the paid-callback webhook) to the
// attacker's host — host-header injection that hijacks payment flow.
//
// Mirror the trusted-proxy gate from middleware/tenantResolver.ts:
// only honour X-Forwarded-* when the socket's remoteAddress is in
// config.trustedProxyIps; otherwise fall back to the direct Host header /
// req.secure. IPv4-mapped IPv6 (::ffff:1.2.3.4) is normalised to bare v4 to
// match how operators usually list trusted IPs.
function normalizeProxyIp(ip: string): string {
  if (!ip) return '';
  const lower = ip.toLowerCase();
  return lower.startsWith('::ffff:') ? lower.slice('::ffff:'.length) : lower;
}

function resolveSafeOrigin(req: Request): string {
  const trustedIps = (config.trustedProxyIps ?? []).map(normalizeProxyIp);
  const socketIp = normalizeProxyIp(req.socket?.remoteAddress || '');
  const proxyTrusted = trustedIps.length > 0 && trustedIps.includes(socketIp);

  let proto: string;
  let host: string;
  if (proxyTrusted) {
    const xfProto = req.headers['x-forwarded-proto'];
    const xfHost = req.headers['x-forwarded-host'];
    const protoVal = (Array.isArray(xfProto) ? xfProto[0] : xfProto)?.split(',')[0]?.trim();
    const hostVal = (Array.isArray(xfHost) ? xfHost[0] : xfHost)?.split(',')[0]?.trim();
    proto = protoVal || (req.secure ? 'https' : 'http');
    host = hostVal || req.headers.host || 'localhost';
  } else {
    proto = req.secure ? 'https' : 'http';
    host = req.headers.host || 'localhost';
  }
  // Drop anything outside a safe hostname:port shape so a wild Host header
  // can't smuggle path or query content into the constructed URL.
  if (!/^[A-Za-z0-9_.\-:]+$/.test(host)) {
    host = 'localhost';
  }
  return `${proto}://${host}`;
}

// SCAN-785: null-safe expiry check. null/undefined means "never expires".
function isLinkExpired(expiresAt: string | null | undefined): boolean {
  if (!expiresAt) return false;
  const ts = Date.parse(expiresAt);
  if (Number.isNaN(ts)) return false;
  return ts < Date.now();
}

function dollarsToCents(amount: unknown): number {
  const dollars = validatePositiveAmount(amount);
  // SCAN-893: toFixed(2) eliminates binary-FP drift (e.g. 1.005*100 = 100.499...)
  // before scaling, so Math.round always gets a value within 0.5 of the true cent.
  return Math.round(Number(dollars.toFixed(2)) * 100);
}

// ---------------------------------------------------------------------------
// AUTHED endpoints — staff-facing CRUD
// ---------------------------------------------------------------------------

/** GET / — list payment links, newest first, filterable by status.
 *  SCAN-1097 [CRIT]: previously ungated. `SELECT pl.*` returns the raw
 *  token column, which is the bearer secret used to authenticate the
 *  public payment page. Any authenticated user (cashier/technician) could
 *  enumerate active tokens and redirect payments. Mirrors the existing
 *  `requireManagerOrAdmin` gate on GET `/:id`. */
authedRouter.get('/', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const statusFilter = validateEnum(
    req.query.status,
    ['active', 'paid', 'expired', 'cancelled'] as const,
    'status',
    false,
  );

  const rows = await adb.all<Row>(
    `SELECT pl.*, c.first_name AS customer_first, c.last_name AS customer_last
       FROM payment_links pl
       LEFT JOIN customers c ON c.id = pl.customer_id
      ${statusFilter ? 'WHERE pl.status = ?' : ''}
      ORDER BY pl.id DESC
      LIMIT 500`,
    ...(statusFilter ? [statusFilter] : []),
  );

  res.json({ success: true, data: rows });
}));

/** GET /:id — one link with full details (admin/manager only). */
authedRouter.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  // SCAN-1115: `Number.isFinite(parseInt('0'))` is true, `parseInt('-1')` is
  // also finite. A negative or zero id reached the `WHERE id = ?` lookup and
  // always returned 404, but it still consumed a DB round-trip and allowed
  // enumeration probing. Tighten to positive-integer, matching the id check
  // used on sibling routes.
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isInteger(id) || id <= 0) throw new AppError('Invalid id', 400);
  const row = await req.asyncDb.get<Row>('SELECT * FROM payment_links WHERE id = ?', id);
  if (!row) throw new AppError('Payment link not found', 404);
  res.json({ success: true, data: row });
}));

/** POST / — create new payment link. Body: { invoice_id?, customer_id?, amount, description?, provider?, expires_at? } */
authedRouter.post('/', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const adb = req.asyncDb;
  const { invoice_id, customer_id, amount, description, provider, expires_at } = req.body ?? {};

  const amountCents = dollarsToCents(amount);
  const providerVal = validateEnum(
    provider ?? 'stripe',
    ['stripe', 'blockchyp'] as const,
    'provider',
  )!;
  const expires = validateIsoDate(expires_at, 'expires_at', false);
  const desc = validateTextLength(
    typeof description === 'string' ? description : undefined,
    500,
    'description',
  );

  // FK existence checks — guarantee the link points to a real invoice/customer
  // so we don't create an orphan row that breaks the admin list view.
  let invoiceIdClean: number | null = null;
  let invoiceCustomerId: number | null = null;
  if (invoice_id !== undefined && invoice_id !== null) {
    invoiceIdClean = validateIntegerQuantity(invoice_id, 'invoice_id');
    const inv = await adb.get<{ id: number; amount_due: number; status: string; customer_id: number | null }>(
      'SELECT id, amount_due, status, customer_id FROM invoices WHERE id = ?',
      invoiceIdClean,
    );
    if (!inv) throw new AppError('Invoice not found', 404);
    invoiceCustomerId = inv.customer_id == null ? null : Number(inv.customer_id);
    if (inv.status === 'void' || inv.status === 'paid') {
      throw new AppError(`Cannot create payment link for a ${inv.status} invoice`, 400);
    }
    const dueCents = Math.round(Number(inv.amount_due ?? 0) * 100);
    if (amountCents > dueCents) {
      throw new AppError('Payment link amount exceeds invoice balance due', 400);
    }
  }
  let customerIdClean: number | null = null;
  if (customer_id !== undefined && customer_id !== null) {
    customerIdClean = validateIntegerQuantity(customer_id, 'customer_id');
  }
  if (invoiceIdClean !== null) {
    if (invoiceCustomerId !== null) {
      if (customerIdClean !== null && customerIdClean !== invoiceCustomerId) {
        throw new AppError('Invoice customer does not match customer_id', 400);
      }
      customerIdClean = invoiceCustomerId;
    } else if (customerIdClean !== null) {
      throw new AppError('Invoice is not assigned to a customer', 400);
    }
  }
  if (customerIdClean !== null) {
    const cust = await adb.get('SELECT id FROM customers WHERE id = ?', customerIdClean);
    if (!cust) throw new AppError('Customer not found', 404);
  }

  const token = generateToken();

  const result = await adb.run(
    `INSERT INTO payment_links
       (token, invoice_id, customer_id, amount_cents, description, provider, status, expires_at, created_by_user_id)
     VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)`,
    token,
    invoiceIdClean,
    customerIdClean,
    amountCents,
    desc || null,
    providerVal,
    expires,
    req.user?.id ?? null,
  );

  audit(req.db, 'payment_link.create', req.user?.id ?? null, req.ip ?? '', {
    id: result.lastInsertRowid,
    amount_cents: amountCents,
    provider: providerVal,
  });

  logger.info('payment_link created', { id: result.lastInsertRowid, provider: providerVal });

  res.status(201).json({
    success: true,
    data: { id: result.lastInsertRowid, token },
  });
}));

/** DELETE /:id — cancel (soft). */
authedRouter.delete('/:id', asyncHandler(async (req: Request, res: Response) => {
  requireManagerOrAdmin(req);
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

  const result = await req.asyncDb.run(
    `UPDATE payment_links SET status = 'cancelled' WHERE id = ? AND status NOT IN ('paid','cancelled')`,
    id,
  );
  if (result.changes === 0) {
    const existing = await req.asyncDb.get<Row>('SELECT status FROM payment_links WHERE id = ?', id);
    if (!existing) throw new AppError('Payment link not found', 404);
    throw new AppError(`cannot cancel link in ${existing.status} status`, 409);
  }

  audit(req.db, 'payment_link.cancel', req.user?.id ?? null, req.ip ?? '', { id });

  res.json({ success: true, data: { id, status: 'cancelled' } });
}));

// ---------------------------------------------------------------------------
// PUBLIC endpoints — tokenized, no auth required
// ---------------------------------------------------------------------------
// SEC-H33: explicit tenant scoping is achieved at the DB level — the global
// `tenantResolver` middleware (index.ts:967) rewrites req.asyncDb / req.db
// to the per-tenant SQLite file based on the Host header (subdomain
// lookup). payment_links rows live inside the tenant DB so a token from
// tenant A cannot surface via tenant B's Host header — the SELECT simply
// misses. No row-level `tenant_id` column is required. Verified 2026-04-17:
// payment_links schema (migration 095_billing_enrichment.sql) has no
// tenant_id column because isolation is DB-file-level.

// Post-enrichment audit §9: DB-backed IP rate limiter for every public
// endpoint. The /pay page is token-auth only, and the global /api/v1 limiter
// is in-memory and resets on restart — a cold start would re-enable token
// brute-force. Persist limits in `rate_limits` so the guard survives crashes.
const PUBLIC_PAYMENT_CATEGORY = 'public_payment_link';
const PUBLIC_PAYMENT_MAX = 30;               // 30 requests per IP
const PUBLIC_PAYMENT_WINDOW_MS = 60_000;      // per minute
const PUBLIC_PAY_MAX = 6;                     // 6 pay attempts per IP
const PUBLIC_PAY_WINDOW_MS = 60_000;          // per minute

/** IP rate-limit guard for public (no auth) token endpoints. */
function guardPublicRate(
  req: Request,
  category: string,
  maxAttempts: number,
  windowMs: number,
): void {
  const ip = req.ip ?? req.socket?.remoteAddress ?? 'unknown';
  const result = consumeWindowRate(req.db, category, ip, maxAttempts, windowMs);
  if (!result.allowed) {
    throw new AppError(
      `Too many requests — try again in ${result.retryAfterSeconds}s`,
      429,
    );
  }
}

/**
 * GET /:token — read-only lookup used by the /pay/:token React page.
 * Does NOT increment click_count — use POST /:token/click for that so the
 * React page can fetch and re-render without inflating the counter.
 */
publicRouter.get('/:token', asyncHandler(async (req: Request, res: Response) => {
  guardPublicRate(req, PUBLIC_PAYMENT_CATEGORY, PUBLIC_PAYMENT_MAX, PUBLIC_PAYMENT_WINDOW_MS);
  const token = String(req.params.token || '').trim();
  if (!TOKEN_REGEX.test(token)) throw new AppError('Invalid token', 400);

  const row = await req.asyncDb.get<Row>(
    `SELECT pl.id, pl.token, pl.invoice_id, pl.customer_id, pl.amount_cents,
            pl.description, pl.provider, pl.status, pl.expires_at, pl.paid_at,
            i.order_id AS invoice_order_id, i.total AS invoice_total, i.amount_due
       FROM payment_links pl
       LEFT JOIN invoices i ON i.id = pl.invoice_id
      WHERE pl.token = ?`,
    token,
  );

  if (!row) throw new AppError('Payment link not found', 404);

  // Expire automatically if the expires_at has passed.
  if (row.status === 'active' && isLinkExpired(row.expires_at)) {
    await req.asyncDb.run(`UPDATE payment_links SET status = 'expired' WHERE id = ?`, row.id);
    row.status = 'expired';
  }

  // WEB-UIUX-172: include merchant identity so the public page shows
  // phishing-protection signals (name, address, phone).
  const storeConfigRows = await req.asyncDb.all<{ key: string; value: string }>(
    `SELECT key, value FROM store_config WHERE key IN ('store_name','store_phone','store_address')`,
  );
  const storeConfig: Record<string, string> = {};
  for (const r of storeConfigRows) storeConfig[r.key] = r.value ?? '';
  row.merchant_name    = storeConfig['store_name']    ?? null;
  row.merchant_phone   = storeConfig['store_phone']   ?? null;
  row.merchant_address = storeConfig['store_address'] ?? null;

  res.json({ success: true, data: row });
}));

/** POST /:token/click — increments click_count + last_clicked_at. */
publicRouter.post('/:token/click', asyncHandler(async (req: Request, res: Response) => {
  guardPublicRate(req, PUBLIC_PAYMENT_CATEGORY, PUBLIC_PAYMENT_MAX, PUBLIC_PAYMENT_WINDOW_MS);
  const token = String(req.params.token || '').trim();
  if (!TOKEN_REGEX.test(token)) throw new AppError('Invalid token', 400);

  // SEC-M60: select expires_at too so we can auto-expire on the click path.
  // The GET handler above already flips stale rows to 'expired' but the
  // /click and /pay mutation endpoints were relying on a prior GET having
  // run — a client that posts /click before ever GETing the link could
  // otherwise accept and audit a click on a link that should be dead.
  const row = await req.asyncDb.get<Row>(
    'SELECT id, expires_at FROM payment_links WHERE token = ? AND status = ?',
    token,
    'active',
  );
  if (!row) throw new AppError('Payment link not available', 404);

  // SEC-M60: hard-fail a click on an active-but-expired row and flip the
  // status to 'expired' so subsequent requests are cheap-404d at the
  // status = 'active' filter above.
  if (isLinkExpired(row.expires_at)) {
    await req.asyncDb.run(`UPDATE payment_links SET status = 'expired' WHERE id = ?`, row.id);
    throw new AppError('Payment link has expired', 410);
  }

  await req.asyncDb.run(
    `UPDATE payment_links
        SET click_count = click_count + 1, last_clicked_at = ?
      WHERE id = ?`,
    nowIso(),
    row.id,
  );

  // Public (unauthenticated) — userId is null. IP is still captured so admins
  // can correlate suspicious click bursts with an attacker address.
  audit(req.db, 'payment_link.click', null, req.ip ?? '', {
    id: row.id,
    token_prefix: token.slice(0, 8),
  });

  res.json({ success: true, data: { id: row.id } });
}));

/**
 * POST /:token/pay — WEB-W3-005.
 *
 * Creates a BlockChyp Hosted Checkout link for the amount on this payment link
 * and returns the provider URL. The customer's browser then navigates to the
 * BlockChyp-hosted card-entry page. On success/failure BlockChyp fires a
 * callbackUrl webhook back to this server (not yet wired) to mark the link paid.
 *
 * If BlockChyp is not configured for this tenant the endpoint still returns a
 * 200 with `checkout_available: false` so the UI can show the "call shop" fallback.
 */
publicRouter.post('/:token/pay', asyncHandler(async (req: Request, res: Response) => {
  guardPublicRate(req, PUBLIC_PAYMENT_CATEGORY + ':pay', PUBLIC_PAY_MAX, PUBLIC_PAY_WINDOW_MS);
  const token = String(req.params.token || '').trim();
  if (!TOKEN_REGEX.test(token)) throw new AppError('Invalid token', 400);

  const adb = req.asyncDb;

  // SEC-M60: select expires_at so we can reject stale links and flip status.
  const row = await adb.get<Row>(
    `SELECT pl.id, pl.status, pl.invoice_id, pl.customer_id, pl.amount_cents, pl.description, pl.provider, pl.expires_at,
            i.order_id AS invoice_order_id
       FROM payment_links pl
       LEFT JOIN invoices i ON i.id = pl.invoice_id
      WHERE pl.token = ?`,
    token,
  );
  if (!row) throw new AppError('Payment link not found', 404);
  if (row.status !== 'active') {
    res.status(409).json({ success: false, message: 'Payment link is not active' });
    return;
  }
  // SEC-M60: reject pay attempt on active-but-expired row.
  if (isLinkExpired(row.expires_at)) {
    await adb.run(`UPDATE payment_links SET status = 'expired' WHERE id = ?`, row.id);
    throw new AppError('Payment link has expired', 410);
  }

  if (row.provider === 'stripe') {
    if (!isTenantStripeCheckoutEnabled(req.db)) {
      audit(req.db, 'payment_link.pay_unavailable', null, req.ip ?? '', {
        id: row.id,
        reason: 'stripe_checkout_not_configured',
        token_prefix: token.slice(0, 8),
      });
      res.json({
        success: true,
        data: {
          id: row.id,
          checkout_available: false,
          error: 'Online Stripe checkout requires Stripe keys and a webhook signing secret.',
        },
      });
      return;
    }

    const origin = resolveSafeOrigin(req);
    const description = row.description
      || (row.invoice_order_id ? `Invoice ${row.invoice_order_id}` : 'Payment');

    audit(req.db, 'payment_link.checkout_started', null, req.ip ?? '', {
      id: row.id,
      invoice_id: row.invoice_id,
      amount_cents: row.amount_cents,
      provider: 'stripe',
      token_prefix: token.slice(0, 8),
    });

    const session = await createTenantStripeCheckoutSession(req.db, {
      tenantSlug: req.tenantSlug ?? null,
      paymentLinkId: Number(row.id),
      token,
      amountCents: Number(row.amount_cents),
      description,
      invoiceId: row.invoice_id ? Number(row.invoice_id) : null,
      customerId: row.customer_id ? Number(row.customer_id) : null,
      successUrl: `${origin}/pay/${encodeURIComponent(token)}?stripe=success`,
      cancelUrl: `${origin}/pay/${encodeURIComponent(token)}?stripe=cancelled`,
    });
    if (!session.url) {
      throw new AppError('Stripe did not return a checkout URL', 502);
    }

    await adb.run(
      `UPDATE payment_links
          SET processor_checkout_id = ?,
              processor_checkout_url = ?,
              processor_status = ?
        WHERE id = ?`,
      session.id,
      session.url,
      session.status ?? null,
      row.id,
    );

    res.json({
      success: true,
      data: {
        id: row.id,
        checkout_available: true,
        checkout_url: session.url,
        checkout_id: session.id,
      },
    });
    return;
  }

  // If BlockChyp is not configured for this tenant, return graceful fallback.
  if (!isBlockChypEnabled(req.db)) {
    audit(req.db, 'payment_link.pay_unavailable', null, req.ip ?? '', {
      id: row.id,
      reason: 'blockchyp_not_configured',
      token_prefix: token.slice(0, 8),
    });
    res.json({
      success: true,
      data: { id: row.id, checkout_available: false },
    });
    return;
  }

  // Amount in dollars (BlockChyp expects "10.00" strings).
  const dollars = (row.amount_cents / 100).toFixed(2);
  const description = row.description
    || (row.invoice_order_id ? `Invoice ${row.invoice_order_id}` : 'Payment');

  // Construct the callbackUrl from the request origin so BlockChyp can POST
  // back to us when the customer completes payment. Webhook handler is not yet
  // implemented — this wires the plumbing for it without blocking the flow.
  const callbackOrigin = resolveSafeOrigin(req);
  const callbackUrl = `${callbackOrigin}/api/v1/public/payment-links/${encodeURIComponent(token)}/paid-callback`;

  audit(req.db, 'payment_link.checkout_started', null, req.ip ?? '', {
    id: row.id,
    invoice_id: row.invoice_id,
    amount_cents: row.amount_cents,
    token_prefix: token.slice(0, 8),
  });

  const result = await createPaymentLink(req.db, dollars, description, callbackUrl);

  if (!result.success || !result.linkUrl) {
    logger.error('BlockChyp createPaymentLink failed for public pay page', {
      id: row.id,
      error: result.error,
    });
    audit(req.db, 'payment_link.checkout_failed', null, req.ip ?? '', {
      id: row.id,
      error: result.error,
      token_prefix: token.slice(0, 8),
    });
    // Return graceful fallback so UI shows "call shop" instead of a crash.
    res.json({
      success: true,
      data: {
        id: row.id,
        checkout_available: false,
        error: result.error ?? 'Checkout unavailable',
      },
    });
    return;
  }

  logger.info('BlockChyp hosted checkout created for payment link', {
    id: row.id,
    linkCode: result.linkCode,
  });

  res.json({
    success: true,
    data: {
      id: row.id,
      checkout_available: true,
      checkout_url: result.linkUrl,
      link_code: result.linkCode ?? null,
    },
  });
}));

export { authedRouter as paymentLinksAuthedRouter, publicRouter as paymentLinksPublicRouter };
export default authedRouter;
