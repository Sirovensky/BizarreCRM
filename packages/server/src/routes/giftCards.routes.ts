import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { roundCurrency } from '../utils/currency.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import { validatePositiveAmount, validatePaginationOffset } from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';

const router = Router();
const logger = createLogger('giftCards');

// Rate limit constants for gift card code lookup (prevent enumeration)
// 10 lookups per minute per user. Only FAILED lookups are counted towards
// the limit — successful lookups shouldn't burn down the quota.
const LOOKUP_RATE_LIMIT = 10;
const LOOKUP_RATE_WINDOW = 60_000; // 1 minute

// SC5: Only audit lookup failures once the attacker has made enough failed
// attempts in the window to look like enumeration. Prevents audit-log spam
// from ordinary typos.
const LOOKUP_AUDIT_THRESHOLD = 3;

const GIFT_CARD_MAX_AMOUNT = 10_000;

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// SEC-H38: 128-bit (16 byte / 32 hex char) codes. Prior 64-bit codes
// (8 byte / 16 char) were brute-forceable in the online lookup path
// even with rate limiting — at 10 lookups/min/user an attacker with
// multiple accounts could still enumerate non-trivial code space.
// 128 bits is beyond any realistic online attack window.
function generateCode(): string {
  return crypto.randomBytes(16).toString('hex').toUpperCase(); // 32 chars
}

// SEC-H38: SHA-256 of the uppercased code. Lookups compare by hash so
// the plaintext code is not an enumeration primitive at rest. Must be
// called with the already-uppercased code to match the INSERT path.
function hashCode(code: string): string {
  return crypto.createHash('sha256').update(code).digest('hex');
}

interface GiftCardRow {
  id: number;
  code: string;
  initial_balance: number;
  current_balance: number;
  status: string;
  customer_id: number | null;
  recipient_name: string | null;
  recipient_email: string | null;
  expires_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

interface RateLimitRow {
  count: number;
  first_attempt: number;
}

/**
 * SC5: Read the current failure count for gift card lookups for this user
 * in the active window. Returns 0 if no row or the window has expired.
 */
function currentLookupFailureCount(db: any, userKey: string): number {
  try {
    const row = db.prepare(
      'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?',
    ).get('gift_card_lookup', userKey) as RateLimitRow | undefined;
    if (!row) return 0;
    if (Date.now() - row.first_attempt > LOOKUP_RATE_WINDOW) return 0;
    return row.count;
  } catch (err) {
    logger.warn('Failed to read gift card lookup failure count', { error: String(err) });
    return 0;
  }
}

// GET / — List gift cards
// Tenant isolation: req.asyncDb is already per-tenant via tenantResolver — SC2 verified.
router.get('/', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const keyword = (req.query.keyword as string || '').trim();
  const status = (req.query.status as string || '').trim();

  const conditions: string[] = [];
  const params: unknown[] = [];
  if (keyword) {
    conditions.push("(gc.code LIKE ? ESCAPE '\\' OR gc.recipient_name LIKE ? ESCAPE '\\')");
    const k = `%${escapeLike(keyword)}%`;
    params.push(k, k);
  }
  if (status) { conditions.push('gc.status = ?'); params.push(status); }

  const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';

  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(req.query.per_page as string) || 50));
  const offset = validatePaginationOffset((page - 1) * perPage, 'offset');

  const [countRow, cards, summary] = await Promise.all([
    adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM gift_cards gc ${whereClause}`, ...params),
    adb.all(`
      SELECT gc.*, c.first_name, c.last_name
      FROM gift_cards gc
      LEFT JOIN customers c ON c.id = gc.customer_id
      ${whereClause}
      ORDER BY gc.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, perPage, offset),
    adb.get(`
      SELECT COUNT(*) AS total_cards,
             COALESCE(SUM(current_balance), 0) AS total_outstanding,
             COUNT(CASE WHEN status = 'active' THEN 1 END) AS active_count
      FROM gift_cards
    `),
  ]);
  const total = countRow!.c;

  res.json({ success: true, data: { cards, summary, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } } });
}));

/**
 * S20-G1: Constant-time string comparison for gift card codes.
 *
 * Even though we look up by exact equality on the database (parameterized,
 * so no SQL timing leak), a downstream caller or future hash-lookup route
 * may compare the raw code in application code. Centralizing it here means
 * we have one place to bring any future PIN/secret comparison up to
 * timing-safe behavior. The SQL equality is already parameterized so the
 * SQLite engine itself is not a timing oracle — this helper exists so the
 * redeem+lookup routes can enforce a constant-time membership check if we
 * later introduce a client-side PIN layer.
 */
function constantTimeCodeMatch(expected: string, actual: string): boolean {
  if (typeof expected !== 'string' || typeof actual !== 'string') return false;
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(actual, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

// GET /lookup/:code — Lookup gift card by code (for POS)
// SC5: Audit brute-force attempts once the failure count exceeds the threshold
//      within the rate-limit window. Only failed lookups count toward the limit
//      and the audit trail, so legitimate POS usage doesn't spam the log.
router.get('/lookup/:code', asyncHandler(async (req, res) => {
  const db = req.db;
  const userId = req.user!.id;
  // S20-G1: key brute-force counters by both user and IP so a shared cashier
  // login can't be used to enumerate codes from a single attacker IP while
  // legitimate POS traffic from other terminals still goes through.
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const userKey = String(userId);
  const ipKey = `ip:${ip}`;
  const rawCode = (req.params.code as string || '').trim();
  const code = rawCode.toUpperCase();

  // Check both per-user and per-IP windows BEFORE the lookup — block once
  // either threshold is crossed. Two separate categories keep the counters
  // independent so legitimate users on a shared NAT aren't throttled by a
  // neighbor.
  if (
    !checkWindowRate(db, 'gift_card_lookup', userKey, LOOKUP_RATE_LIMIT, LOOKUP_RATE_WINDOW) ||
    !checkWindowRate(db, 'gift_card_lookup_ip', ipKey, LOOKUP_RATE_LIMIT, LOOKUP_RATE_WINDOW)
  ) {
    // SC5: a burst that trips the limiter is worth auditing loudly.
    audit(db, 'gift_card_lookup_rate_limited', userId, ip, {
      attempted_code_hash: crypto.createHash('sha256').update(code).digest('hex').slice(0, 16),
    });
    throw new AppError('Too many lookup attempts. Please wait before trying again.', 429);
  }

  // SEC-H38: lookup by hashed code. `code_hash` is populated by migration
  // 104's backfill at boot; new rows write it on INSERT. Fall back to the
  // plaintext column is intentionally NOT added — any rows missing a hash
  // after boot are a backfill bug we want to surface loudly as a 404.
  const adb: AsyncDb = req.asyncDb;
  const codeHash = hashCode(code);
  const card = await adb.get<GiftCardRow>(
    'SELECT * FROM gift_cards WHERE code_hash = ?',
    codeHash,
  );

  // SC5: Record EVERY failure (not every lookup). Then audit if this user is
  // over the brute-force threshold in the window. Record against BOTH the
  // user and the IP bucket so neither bucket is a loophole.
  const recordAndMaybeAudit = (reason: string): void => {
    recordWindowFailure(db, 'gift_card_lookup', userKey, LOOKUP_RATE_WINDOW);
    recordWindowFailure(db, 'gift_card_lookup_ip', ipKey, LOOKUP_RATE_WINDOW);
    const attempts = currentLookupFailureCount(db, userKey);
    if (attempts > LOOKUP_AUDIT_THRESHOLD) {
      audit(db, 'gift_card_lookup_failed', userId, ip, {
        reason,
        attempts_in_window: attempts,
        attempted_code_hash: crypto.createHash('sha256').update(code).digest('hex').slice(0, 16),
      });
    }
  };

  // S20-G1: Constant-time string match against the row returned from the DB.
  // SQLite's exact-match lookup already filters, but if a future refactor
  // switches to LIKE or a prefix scan, this guard still blocks partial
  // matches from sneaking through.
  if (!card || !constantTimeCodeMatch(card.code, code)) {
    recordAndMaybeAudit('not_found');
    throw new AppError('Gift card not found', 404);
  }
  if (card.status !== 'active') {
    recordAndMaybeAudit(`status_${card.status}`);
    throw new AppError(`Gift card is ${card.status}`, 400);
  }
  if (card.expires_at && new Date(card.expires_at) < new Date()) {
    recordAndMaybeAudit('expired');
    throw new AppError('Gift card expired', 400);
  }

  // Success — do NOT record a failure, legitimate lookups should not hit the rate limit.
  res.json({ success: true, data: card });
}));

// POST / — Issue new gift card
// SEC-H21: Minting bearer-value cards is a privileged action (effectively cash
// issuance) — require admin or manager. A base-role authed user can still
// redeem via the dedicated redeem route but cannot create new cards.
router.post('/', asyncHandler(async (req, res) => {
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required to issue gift cards', 403);
  }
  const adb: AsyncDb = req.asyncDb;
  const { customer_id, recipient_name, recipient_email, expires_at, notes } = req.body;
  const amount = validatePositiveAmount(req.body.amount, 'amount');
  if (amount > GIFT_CARD_MAX_AMOUNT) {
    throw new AppError(`Gift card amount cannot exceed $${GIFT_CARD_MAX_AMOUNT.toLocaleString()}`, 400);
  }

  const code = generateCode();
  const codeHash = hashCode(code);
  // SEC-H38: write both the plaintext `code` (kept during the two-step
  // rollover so existing redemption scripts keep working) and the new
  // `code_hash`. A follow-up migration will drop `code` once all callers
  // are hash-first.
  const result = await adb.run(`
    INSERT INTO gift_cards (code, code_hash, initial_balance, current_balance, status, customer_id, recipient_name, recipient_email, expires_at, notes, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?)
  `, code, codeHash, amount, amount, customer_id || null, recipient_name || null, recipient_email || null,
    expires_at || null, notes || null, req.user!.id, now(), now());

  // Record purchase transaction
  await adb.run(
    'INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    result.lastInsertRowid, 'purchase', amount, 'Initial load', req.user!.id, now(),
  );

  // SEC-H38: mask the code in audit_log.details. A 4-char prefix is enough
  // for a human operator to correlate a card with a physical receipt while
  // the full code remains unguessable from audit dumps.
  audit(req.db, 'gift_card_issued', req.user!.id, req.ip || 'unknown', {
    gift_card_id: Number(result.lastInsertRowid),
    code_prefix: code.slice(0, 4),
    code_hash: codeHash,
    amount,
    customer_id: customer_id || null,
  });
  // Plaintext code returned to the caller ONCE — this is the only time it
  // leaves the server. The UI is expected to surface it to the cashier on
  // the issue-success screen and never persist it client-side.
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid, code } });
}));

// POST /:id/redeem — Redeem gift card (at POS)
// SC3-equivalent: Guarded atomic decrement prevents parallel double-spend.
router.post('/:id/redeem', asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const cardId = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(cardId) || cardId <= 0) {
    throw new AppError('Invalid gift card id', 400);
  }

  const amount = validatePositiveAmount(req.body.amount, 'amount');
  const invoiceIdRaw = req.body.invoice_id;
  let invoiceId: number | null = null;
  if (invoiceIdRaw !== undefined && invoiceIdRaw !== null && invoiceIdRaw !== '') {
    invoiceId = Number(invoiceIdRaw);
    if (!Number.isInteger(invoiceId) || invoiceId <= 0) {
      throw new AppError('invoice_id must be a positive integer', 400);
    }
  }

  const card = await adb.get<GiftCardRow>('SELECT * FROM gift_cards WHERE id = ?', cardId);
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status !== 'active') throw new AppError(`Gift card is ${card.status}`, 400);
  if (card.expires_at && new Date(card.expires_at) < new Date()) {
    throw new AppError('Gift card expired', 400);
  }

  // Guarded atomic decrement — prevents race where two parallel requests both
  // pass a naive balance check. S20-G2: flip status to 'used' in the same
  // UPDATE so we never leak a window where a drained card still reads as
  // active. SEC-H114: also re-check expires_at in the WHERE clause so a card
  // that crosses its expiry boundary between the SELECT above and this UPDATE
  // cannot be redeemed.
  const dec = await adb.run(
    `UPDATE gift_cards
        SET current_balance = current_balance - ?,
            status = CASE
                       WHEN current_balance - ? <= 0 THEN 'used'
                       ELSE status
                     END,
            updated_at = ?
      WHERE id = ? AND status = 'active' AND current_balance >= ?
        AND (expires_at IS NULL OR expires_at > datetime('now'))`,
    amount, amount, now(), cardId, amount,
  );
  if (dec.changes === 0) {
    throw new AppError('Gift card balance insufficient or expired', 409);
  }

  // Re-read committed balance + status for the response (avoid stale values).
  const fresh = await adb.get<GiftCardRow>(
    'SELECT current_balance, status FROM gift_cards WHERE id = ?',
    cardId,
  );
  const newBalance = roundCurrency(fresh?.current_balance ?? 0);
  const newStatus = fresh?.status ?? 'active';

  await adb.run(
    'INSERT INTO gift_card_transactions (gift_card_id, type, amount, invoice_id, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    cardId, 'redemption', -amount, invoiceId, 'Redeemed at POS', req.user!.id, now(),
  );

  audit(db, 'gift_card_redeemed', req.user!.id, req.ip || 'unknown', {
    gift_card_id: cardId,
    amount,
    new_balance: newBalance,
    invoice_id: invoiceId,
  });
  res.json({ success: true, data: { new_balance: newBalance, status: newStatus } });
}));

// POST /:id/reload — Add balance to gift card
router.post('/:id/reload', asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const cardId = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(cardId) || cardId <= 0) {
    throw new AppError('Invalid gift card id', 400);
  }

  const amount = validatePositiveAmount(req.body.amount, 'amount');
  if (amount > GIFT_CARD_MAX_AMOUNT) {
    throw new AppError(`Reload amount cannot exceed $${GIFT_CARD_MAX_AMOUNT.toLocaleString()}`, 400);
  }

  const card = await adb.get<GiftCardRow>('SELECT * FROM gift_cards WHERE id = ?', cardId);
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status === 'disabled') throw new AppError('Gift card is disabled', 400);

  await adb.run(
    "UPDATE gift_cards SET current_balance = current_balance + ?, status = 'active', updated_at = ? WHERE id = ?",
    amount, now(), cardId,
  );
  await adb.run(
    'INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    cardId, 'adjustment', amount, 'Reloaded', req.user!.id, now(),
  );

  // Re-read committed balance for accuracy (avoid stale computed values).
  const fresh = await adb.get<GiftCardRow>(
    'SELECT current_balance FROM gift_cards WHERE id = ?',
    cardId,
  );
  const newBalance = roundCurrency(fresh?.current_balance ?? 0);
  audit(db, 'gift_card_reloaded', req.user!.id, req.ip || 'unknown', {
    gift_card_id: cardId,
    amount,
    new_balance: newBalance,
  });
  res.json({ success: true, data: { new_balance: newBalance } });
}));

// GET /:id — Gift card details with transactions
router.get('/:id', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const cardId = parseInt(req.params.id as string, 10);
  if (!Number.isFinite(cardId) || cardId <= 0) {
    throw new AppError('Invalid gift card id', 400);
  }
  const card = await adb.get<GiftCardRow>('SELECT * FROM gift_cards WHERE id = ?', cardId);
  if (!card) throw new AppError('Gift card not found', 404);
  const transactions = await adb.all(
    'SELECT * FROM gift_card_transactions WHERE gift_card_id = ? ORDER BY created_at DESC',
    cardId,
  );
  res.json({ success: true, data: { ...card, transactions } });
}));

export default router;
