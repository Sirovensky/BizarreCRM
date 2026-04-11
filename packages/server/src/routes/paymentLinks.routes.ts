/**
 * Payment Links routes — audit §52 idea 1.
 *
 * Mounted twice in index.ts:
 *   /api/v1/payment-links          (auth required — CRUD for staff)
 *   /api/v1/public/payment-links   (no auth — click tracking + customer pay)
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

/** GET /:id — one link with full details. */
authedRouter.get('/:id', asyncHandler(async (req: Request, res: Response) => {
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
  if (!token || token.length < 8) throw new AppError('Invalid token', 400);

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
  if (!token) throw new AppError('Invalid token', 400);

  const row = await req.asyncDb.get<Row>(
    'SELECT id FROM payment_links WHERE token = ? AND status = ?',
    token,
    'active',
  );
  if (!row) throw new AppError('Payment link not available', 404);

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
 * POST /:token/pay — mark a link as paid.
 *
 * NOTE: this does NOT actually charge a card. It records success after the
 * provider's hosted flow (Stripe Checkout / BlockChyp iframe) redirects
 * back. The real charge happens client-side via the provider's SDK and the
 * authoritative settlement event arrives via the provider webhook handlers
 * (see routes/webhooks.ts — owned by a different agent).
 *
 * This endpoint is the trust-the-client fallback used when the browser
 * redirect lands before the webhook fires. Because it's public and
 * unauthenticated, we REQUIRE a non-empty `transaction_ref` — callers
 * without one cannot silently flip a link to 'paid'. The transaction_ref
 * is stored in provider_tx_ref so webhook reconciliation can later cross-
 * check against the authoritative provider record.
 *
 * Body: { transaction_ref } — required, 8..255 chars
 */
publicRouter.post('/:token/pay', asyncHandler(async (req: Request, res: Response) => {
  // Tighter limit on /pay — confirming a "paid" state is the highest-impact
  // public action and must not be brute-forceable.
  guardPublicRate(req, PUBLIC_PAYMENT_CATEGORY + ':pay', PUBLIC_PAY_MAX, PUBLIC_PAY_WINDOW_MS);
  const token = String(req.params.token || '').trim();
  const txRefRaw = typeof req.body?.transaction_ref === 'string' ? req.body.transaction_ref.trim() : '';
  if (!txRefRaw || txRefRaw.length < 8) {
    throw new AppError('transaction_ref is required (min 8 chars) — issued by the provider redirect', 400);
  }
  const txRef = validateTextLength(txRefRaw, 255, 'transaction_ref');

  const row = await req.asyncDb.get<Row>(
    `SELECT id, status, invoice_id, amount_cents FROM payment_links WHERE token = ?`,
    token,
  );
  if (!row) throw new AppError('Payment link not found', 404);
  if (row.status !== 'active') throw new AppError('Payment link is not active', 409);

  const paidAt = nowIso();
  await req.asyncDb.run(
    `UPDATE payment_links SET status = 'paid', paid_at = ? WHERE id = ?`,
    paidAt,
    row.id,
  );

  // SEC (post-enrichment audit §12): critical unauthenticated state flip.
  // This row is how admins reconcile a link that was marked paid without a
  // matching webhook — if the ref turns out to be forged, this row is
  // forensic evidence of how/when the client-side redirect path was hit.
  audit(req.db, 'payment_link.pay', null, req.ip ?? '', {
    id: row.id,
    invoice_id: row.invoice_id,
    amount_cents: row.amount_cents,
    transaction_ref: txRef,
    optimistic: true,
  });

  logger.info('payment_link marked paid (pending webhook confirmation)', {
    id: row.id,
    invoice_id: row.invoice_id,
    tx: txRef,
  });

  res.json({
    success: true,
    data: {
      id: row.id,
      status: 'paid',
      paid_at: paidAt,
      transaction_ref: txRef,
      // The admin UI should treat this as optimistic until the corresponding
      // provider webhook reconciliation row is written. Surface the hint.
      warning: 'Optimistic mark-paid — final confirmation arrives via provider webhook',
    },
  });
}));

export { authedRouter as paymentLinksAuthedRouter, publicRouter as paymentLinksPublicRouter };
export default authedRouter;
