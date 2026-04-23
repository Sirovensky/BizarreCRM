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
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { createLogger } from '../utils/logger.js';
import { audit } from '../utils/audit.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
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

function dollarsToCents(amount: unknown): number {
  const dollars = validatePositiveAmount(amount);
  return Math.round(dollars * 100);
}

// ---------------------------------------------------------------------------
// AUTHED endpoints — staff-facing CRUD
// ---------------------------------------------------------------------------

/** GET / — list payment links, newest first, filterable by status. */
authedRouter.get('/', asyncHandler(async (req: Request, res: Response) => {
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
  const id = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);
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
  if (invoice_id !== undefined && invoice_id !== null) {
    invoiceIdClean = validateIntegerQuantity(invoice_id, 'invoice_id');
    const inv = await adb.get('SELECT id FROM invoices WHERE id = ?', invoiceIdClean);
    if (!inv) throw new AppError('Invoice not found', 404);
  }
  let customerIdClean: number | null = null;
  if (customer_id !== undefined && customer_id !== null) {
    customerIdClean = validateIntegerQuantity(customer_id, 'customer_id');
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

  const existing = await req.asyncDb.get<Row>('SELECT status FROM payment_links WHERE id = ?', id);
  if (!existing) throw new AppError('Payment link not found', 404);
  if (existing.status === 'paid') throw new AppError('Cannot cancel a paid link', 409);

  await req.asyncDb.run(
    `UPDATE payment_links SET status = 'cancelled' WHERE id = ?`,
    id,
  );

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
  if (row.status === 'active' && row.expires_at && new Date(row.expires_at).getTime() < Date.now()) {
    await req.asyncDb.run(`UPDATE payment_links SET status = 'expired' WHERE id = ?`, row.id);
    row.status = 'expired';
  }

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
  if (row.expires_at && new Date(row.expires_at).getTime() < Date.now()) {
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
 * POST /:token/pay - intentionally disabled.
 *
 * Public payment links do not currently create a Stripe Checkout Session,
 * BlockChyp hosted link, or any other provider-hosted authorization. Until a
 * provider checkout/webhook path is wired end to end, this endpoint must fail
 * closed and never mutate payment state.
 */
publicRouter.post('/:token/pay', asyncHandler(async (req: Request, res: Response) => {
  // This endpoint is intentionally fail-closed until payment links create a
  // real provider-hosted checkout and reconcile completion through webhooks.
  guardPublicRate(req, PUBLIC_PAYMENT_CATEGORY + ':pay', PUBLIC_PAY_MAX, PUBLIC_PAY_WINDOW_MS);
  const token = String(req.params.token || '').trim();
  if (!TOKEN_REGEX.test(token)) throw new AppError('Invalid token', 400);

  // SEC-M60: select expires_at so the /pay endpoint can reject stale links
  // without waiting for a prior GET to have flipped the row. When the check
  // fires we also mutate status -> 'expired' to keep DB state consistent.
  const row = await req.asyncDb.get<Row>(
    `SELECT id, status, invoice_id, amount_cents, provider, expires_at FROM payment_links WHERE token = ?`,
    token,
  );
  if (!row) throw new AppError('Payment link not found', 404);
  if (row.status !== 'active') {
    res.status(409).json({ success: false, message: 'Payment link is not active' });
    return;
  }
  // SEC-M60: reject a pay attempt on an active-but-expired row and flip
  // status. 410 Gone signals a permanently unavailable resource so portal
  // UI can render a "contact shop for a new link" state instead of looking
  // like a transient failure.
  if (row.expires_at && new Date(row.expires_at).getTime() < Date.now()) {
    await req.asyncDb.run(`UPDATE payment_links SET status = 'expired' WHERE id = ?`, row.id);
    throw new AppError('Payment link has expired', 410);
  }

  audit(req.db, 'payment_link.pay_blocked', null, req.ip ?? '', {
    id: row.id,
    invoice_id: row.invoice_id,
    amount_cents: row.amount_cents,
    provider: row.provider,
    reason: 'hosted_checkout_not_configured',
    token_prefix: token.slice(0, 8),
  });

  logger.warn('Blocked public payment-link pay attempt because hosted checkout is not configured', {
    id: row.id,
    invoice_id: row.invoice_id,
    provider: row.provider,
  });

  res.status(501).json({
    success: false,
    message: 'Online card checkout is not configured for this payment link. Please contact the shop to complete payment.',
    data: {
      id: row.id,
      status: row.status,
      checkout_available: false,
    },
  });
}));

export { authedRouter as paymentLinksAuthedRouter, publicRouter as paymentLinksPublicRouter };
export default authedRouter;
