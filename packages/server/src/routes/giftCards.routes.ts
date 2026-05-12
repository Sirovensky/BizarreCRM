import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { requirePermission, hasPermission } from '../middleware/auth.js';
import { roundCurrency } from '../utils/currency.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import { validatePositiveAmount, validatePaginationOffset, validateId, validateTextLength, validateIsoDate } from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import { sendEmail, isEmailConfigured } from '../services/email.js';

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

// SCAN-783: null-safe expiry check. null/undefined means "never expires".
// Malformed dates fail-open (warn + return false) so a bad DB value never
// blocks a valid card.
//
// WEB-UIUX-1434: bare YYYY-MM-DD values (the common storage shape — write
// path runs validateIsoDate which trims to date-only) are interpreted as
// END of that day UTC. Previously Date.parse('2026-12-31') resolved to
// midnight UTC, killing a card 4–8h before the user expected on
// US-East/-West clocks. End-of-UTC-day gives a small false-negative bias
// (card stays valid up to ~24h longer in the worst-case eastern timezone)
// — far better than striking it early. Tenant-tz aware refinement is
// tracked separately; this UTC-end-of-day shift is the safe minimum.
function isExpired(expiresAt: string | null | undefined): boolean {
  if (!expiresAt) return false;
  const normalized = /^\d{4}-\d{2}-\d{2}$/.test(expiresAt)
    ? `${expiresAt}T23:59:59.999Z`
    : expiresAt;
  const ts = Date.parse(normalized);
  if (Number.isNaN(ts)) {
    logger.warn('gift card has unparseable expires_at', { raw: expiresAt });
    return false;
  }
  return ts < Date.now();
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

  // SEC-H121: Always filter out soft-deleted cards at the list boundary.
  const conditions: string[] = ['gc.is_deleted = 0'];
  const params: unknown[] = [];
  if (keyword) {
    conditions.push("(gc.code LIKE ? ESCAPE '\\' OR gc.recipient_name LIKE ? ESCAPE '\\')");
    const k = `%${escapeLike(keyword)}%`;
    params.push(k, k);
  }
  // WEB-UIUX-1555: 'expired' is a derived (virtual) status — the column never
  // stores 'expired' because expiry is computed at lookup/redeem time. Without
  // this branch the client option "Expired" returns zero rows. Translate it
  // to a date predicate that surfaces every still-active row whose window has
  // passed (excluding disabled/used so cards aren't double-counted under two
  // filters). Real persisted statuses ('active','used','disabled') stay as
  // direct equality matches.
  if (status === 'expired') {
    conditions.push("gc.expires_at IS NOT NULL");
    // WEB-UIUX-1434: bare YYYY-MM-DD storage means "valid through end of
    // that day". `datetime(substr(expires_at,1,10), '+1 day')` resolves
    // to next-day midnight UTC; comparing < now() flags as expired only
    // after the full local-day window has elapsed (UTC-end-of-day bias,
    // safe in every tz).
    conditions.push("datetime(substr(gc.expires_at, 1, 10), '+1 day') < datetime('now')");
    conditions.push("gc.status NOT IN ('used','disabled')");
  } else if (status) {
    conditions.push('gc.status = ?');
    params.push(status);
  }

  const whereClause = 'WHERE ' + conditions.join(' AND ');

  const page = parsePage(req.query.page);
  const perPage = parsePageSize(req.query.per_page, 50);
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
      WHERE is_deleted = 0
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
    'SELECT * FROM gift_cards WHERE code_hash = ? AND is_deleted = 0',
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
  if (isExpired(card.expires_at)) {
    recordAndMaybeAudit('expired');
    throw new AppError('Gift card expired', 400);
  }

  // BUGHUNT-2026-05-10-07: also burn the window counter on success so an
  // authenticated attacker can't enumerate by inferring validity from
  // 200/409 vs 404. Threshold (LOOKUP_RATE_LIMIT) is generous enough that
  // legitimate cashier traffic (typically <2 lookups/minute per terminal)
  // never trips it, but a scripted scanner with 50 known-good codes hits
  // it on the same per-minute budget.
  recordWindowFailure(db, 'gift_card_lookup', userKey, LOOKUP_RATE_WINDOW);
  recordWindowFailure(db, 'gift_card_lookup_ip', ipKey, LOOKUP_RATE_WINDOW);
  res.json({ success: true, data: card });
}));

// POST / — Issue new gift card
// SEC-H21: Minting bearer-value cards is a privileged action (effectively cash
// issuance) — require admin or manager. A base-role authed user can still
// redeem via the dedicated redeem route but cannot create new cards.
// SEC-H25: gate behind gift_cards.issue permission. The inline role check below
// is kept as defence-in-depth.
router.post('/', requirePermission('gift_cards.issue'), asyncHandler(async (req, res) => {
  // Defence-in-depth: requirePermission above is authoritative.
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

  // SCAN-1124: validate free-text + optional FK before INSERT so a caller
  // can't stash multi-MB strings or point the card at a non-existent /
  // soft-deleted customer (FK violation surfaces as 500 otherwise).
  let validatedCustomerId: number | null = null;
  if (customer_id != null && customer_id !== '') {
    validatedCustomerId = validateId(customer_id, 'customer_id');
    const cust = await adb.get(
      'SELECT 1 FROM customers WHERE id = ? AND is_deleted = 0',
      validatedCustomerId,
    );
    if (!cust) throw new AppError('Customer not found', 404);
  }
  const validatedRecipientName = recipient_name != null && recipient_name !== ''
    ? validateTextLength(recipient_name, 120, 'recipient_name')
    : null;
  const validatedRecipientEmail = recipient_email != null && recipient_email !== ''
    ? validateTextLength(recipient_email, 200, 'recipient_email')
    : null;
  const validatedNotes = notes != null && notes !== ''
    ? validateTextLength(notes, 1000, 'notes')
    : null;
  const validatedExpiresAt = expires_at != null && expires_at !== ''
    ? validateIsoDate(expires_at, 'expires_at', false)
    : null;
  // WEB-UIUX-1548: reject past expiry dates — silently-expired cards
  // burn cashier trust ("I just sold them this card and it doesn't
  // work"). Compare against `today` in UTC (date-only) so a card
  // issued at 23:59 with `expires_at=today` is allowed for the
  // remainder of the day.
  if (validatedExpiresAt) {
    const exp = new Date(validatedExpiresAt + (validatedExpiresAt.length === 10 ? 'T23:59:59Z' : ''));
    if (Number.isFinite(exp.getTime()) && exp.getTime() < Date.now()) {
      throw new AppError(
        `expires_at (${validatedExpiresAt}) is in the past — pick today or later.`,
        400,
      );
    }
  }

  // WEB-UIUX-1001: dual-control gate for manager-tier issuance. Admins still
  // mint cards directly. Manager-tier user requesting >= threshold lands a
  // pending row that an admin (different user) must approve before the card
  // is actually minted. Threshold lives in store_config; default $500
  // (50000 cents) when unset or invalid.
  if (role === 'manager') {
    const thresholdRow = await adb.get<{ value: string }>(
      "SELECT value FROM store_config WHERE key = 'gift_card_dual_control_threshold_cents'",
    );
    const thresholdCents = Number(thresholdRow?.value);
    const effectiveThresholdCents = Number.isFinite(thresholdCents) && thresholdCents > 0
      ? thresholdCents
      : 50_000;
    const amountCents = Math.round(amount * 100);
    if (amountCents >= effectiveThresholdCents) {
      const pendingResult = await adb.run(
        `INSERT INTO gift_card_pending_issuances
           (amount, customer_id, recipient_name, recipient_email, expires_at, notes, requester_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        amount, validatedCustomerId, validatedRecipientName, validatedRecipientEmail,
        validatedExpiresAt, validatedNotes, req.user!.id,
      );
      audit(req.db, 'gift_card_pending_issuance_requested', req.user!.id, req.ip || 'unknown', {
        pending_issuance_id: Number(pendingResult.lastInsertRowid),
        amount,
        amount_cents: amountCents,
        threshold_cents: effectiveThresholdCents,
        customer_id: validatedCustomerId,
      });
      res.status(202).json({
        success: true,
        data: {
          pending_issuance_id: Number(pendingResult.lastInsertRowid),
          status: 'pending_approval',
          amount,
          threshold_cents: effectiveThresholdCents,
          message: 'Awaiting admin approval — issuance over the dual-control threshold.',
        },
      });
      return;
    }
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
  `, code, codeHash, amount, amount, validatedCustomerId, validatedRecipientName, validatedRecipientEmail,
    validatedExpiresAt, validatedNotes, req.user!.id, now(), now());

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
    customer_id: validatedCustomerId,
  });

  // WEB-UIUX-984: deliver the plaintext code to the recipient by email if
  // (a) the issuer captured a `recipient_email`, (b) the tenant has email
  // configured, and (c) the caller did not opt out via `send_email=false`.
  // The plaintext only leaves the server twice — once in this response
  // (returned to the cashier UI), and once in this outbound email — and is
  // never written to disk in plaintext (only the hash). Failure is logged
  // but never blocks the issue flow.
  let recipientEmailSent = false;
  const requestedSend = req.body?.send_email !== false; // default true
  if (
    requestedSend
    && validatedRecipientEmail
    && isEmailConfigured(req.db)
  ) {
    try {
      const storeName = (req.db
        .prepare("SELECT value FROM store_config WHERE key = 'store_name'")
        .get() as { value: string } | undefined)?.value
        || 'Your repair shop';
      const formattedAmount = (Math.round(amount * 100) / 100).toFixed(2);
      const subject = `Your $${formattedAmount} gift card from ${storeName}`;
      const html = `
        <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto;">
          <h2>${storeName} gift card</h2>
          <p>Hello${validatedRecipientName ? ` ${validatedRecipientName}` : ''},</p>
          <p>You've received a gift card worth <strong>$${formattedAmount}</strong>.</p>
          <p>Present this code at checkout or quote it over the phone:</p>
          <div style="font-family: 'Courier New', monospace; font-size: 24px; letter-spacing: 4px;
                      background: #f3f4f6; padding: 16px; text-align: center; border-radius: 8px;">
            ${code}
          </div>
          ${validatedExpiresAt ? `<p>Expires: ${validatedExpiresAt}</p>` : ''}
          <p style="color: #6b7280; font-size: 12px; margin-top: 24px;">
            Keep this code safe — anyone with it can redeem the card.
          </p>
        </div>
      `;
      recipientEmailSent = await sendEmail(req.db, {
        to: validatedRecipientEmail,
        subject,
        html,
      });
    } catch (emailErr) {
      logger.warn('gift_card_recipient_email_failed', {
        gift_card_id: Number(result.lastInsertRowid),
        error: emailErr instanceof Error ? emailErr.message : String(emailErr),
      });
    }
  }

  // Plaintext code returned to the caller ONCE — this is the only time it
  // leaves the server. The UI is expected to surface it to the cashier on
  // the issue-success screen and never persist it client-side.
  res.status(201).json({
    success: true,
    data: {
      id: result.lastInsertRowid,
      code,
      recipient_email_sent: recipientEmailSent,
    },
  });
}));

// --------------------------------------------------------------------------
// POST /bulk — WEB-UIUX-1556: bulk issue (HR holiday-card style).
// Accepts `{ rows: [{ amount, customer_id?, recipient_name?, recipient_email?,
// expires_at?, notes?, send_email? }] }`. Each row is independently validated
// and minted; per-row failures are reported in the response without aborting
// the batch. Defaults `send_email=false` so a 500-row drop does not blast 500
// outbound emails unless the caller explicitly opts each row in.
// Admin-only: the manager dual-control gate on POST / does not extend cleanly
// to a 500-row batch (each row would have to enqueue its own pending row),
// so this endpoint requires admin to keep the contract simple.
// --------------------------------------------------------------------------
const BULK_ISSUE_ROW_CAP = 500;

router.post('/bulk', requirePermission('gift_cards.issue'), asyncHandler(async (req, res) => {
  const role = req.user?.role;
  if (role !== 'admin') {
    throw new AppError('Admin role required for bulk gift card issuance', 403);
  }
  const adb: AsyncDb = req.asyncDb;
  const rowsRaw = (req.body?.rows ?? []) as Array<Record<string, unknown>>;
  if (!Array.isArray(rowsRaw) || rowsRaw.length === 0) {
    throw new AppError('rows array required (at least one row)', 400);
  }
  if (rowsRaw.length > BULK_ISSUE_ROW_CAP) {
    throw new AppError(`rows capped at ${BULK_ISSUE_ROW_CAP} per upload`, 400);
  }

  type RowStatus = 'ok' | 'invalid_amount' | 'amount_exceeds_max'
    | 'customer_not_found' | 'invalid_recipient_name' | 'invalid_recipient_email'
    | 'invalid_notes' | 'invalid_expires_at' | 'expires_at_in_past' | 'error';
  const results: Array<{
    index: number;
    status: RowStatus;
    id?: number;
    code?: string;
    code_prefix?: string;
    recipient_email_sent?: boolean;
    message?: string;
  }> = [];
  let okCount = 0;

  const emailConfigured = isEmailConfigured(req.db);
  const storeName = (req.db
    .prepare("SELECT value FROM store_config WHERE key = 'store_name'")
    .get() as { value: string } | undefined)?.value
    || 'Your repair shop';

  for (let i = 0; i < rowsRaw.length; i++) {
    const row = rowsRaw[i];
    try {
      let amount: number;
      try {
        amount = validatePositiveAmount(row.amount, 'amount');
      } catch {
        results.push({ index: i, status: 'invalid_amount', message: 'amount must be a positive number' });
        continue;
      }
      if (amount > GIFT_CARD_MAX_AMOUNT) {
        results.push({ index: i, status: 'amount_exceeds_max', message: `amount cannot exceed $${GIFT_CARD_MAX_AMOUNT.toLocaleString()}` });
        continue;
      }

      let validatedCustomerId: number | null = null;
      if (row.customer_id != null && row.customer_id !== '') {
        try {
          validatedCustomerId = validateId(row.customer_id, 'customer_id');
        } catch {
          results.push({ index: i, status: 'customer_not_found', message: 'customer_id invalid' });
          continue;
        }
        const cust = await adb.get(
          'SELECT 1 FROM customers WHERE id = ? AND is_deleted = 0',
          validatedCustomerId,
        );
        if (!cust) {
          results.push({ index: i, status: 'customer_not_found', message: `customer ${validatedCustomerId} not found` });
          continue;
        }
      }

      let validatedRecipientName: string | null = null;
      if (row.recipient_name != null && row.recipient_name !== '') {
        try {
          validatedRecipientName = validateTextLength(String(row.recipient_name), 120, 'recipient_name');
        } catch {
          results.push({ index: i, status: 'invalid_recipient_name', message: 'recipient_name too long (max 120)' });
          continue;
        }
      }

      let validatedRecipientEmail: string | null = null;
      if (row.recipient_email != null && row.recipient_email !== '') {
        try {
          validatedRecipientEmail = validateTextLength(String(row.recipient_email), 200, 'recipient_email');
        } catch {
          results.push({ index: i, status: 'invalid_recipient_email', message: 'recipient_email too long (max 200)' });
          continue;
        }
      }

      let validatedNotes: string | null = null;
      if (row.notes != null && row.notes !== '') {
        try {
          validatedNotes = validateTextLength(String(row.notes), 1000, 'notes');
        } catch {
          results.push({ index: i, status: 'invalid_notes', message: 'notes too long (max 1000)' });
          continue;
        }
      }

      let validatedExpiresAt: string | null = null;
      if (row.expires_at != null && row.expires_at !== '') {
        try {
          validatedExpiresAt = validateIsoDate(row.expires_at, 'expires_at', false);
        } catch {
          results.push({ index: i, status: 'invalid_expires_at', message: 'expires_at must be ISO date' });
          continue;
        }
        if (validatedExpiresAt) {
          const exp = new Date(validatedExpiresAt + (validatedExpiresAt.length === 10 ? 'T23:59:59Z' : ''));
          if (Number.isFinite(exp.getTime()) && exp.getTime() < Date.now()) {
            results.push({ index: i, status: 'expires_at_in_past', message: `expires_at (${validatedExpiresAt}) is in the past` });
            continue;
          }
        }
      }

      const code = generateCode();
      const codeHash = hashCode(code);
      const result = await adb.run(`
        INSERT INTO gift_cards (code, code_hash, initial_balance, current_balance, status, customer_id, recipient_name, recipient_email, expires_at, notes, created_by, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?)
      `, code, codeHash, amount, amount, validatedCustomerId, validatedRecipientName, validatedRecipientEmail,
        validatedExpiresAt, validatedNotes, req.user!.id, now(), now());

      await adb.run(
        'INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        result.lastInsertRowid, 'purchase', amount, 'Initial load (bulk)', req.user!.id, now(),
      );

      audit(req.db, 'gift_card_issued', req.user!.id, req.ip || 'unknown', {
        gift_card_id: Number(result.lastInsertRowid),
        code_prefix: code.slice(0, 4),
        code_hash: codeHash,
        amount,
        customer_id: validatedCustomerId,
        bulk: true,
      });

      let emailSent = false;
      const requestedSend = row.send_email === true; // bulk default: opt-IN per row
      if (requestedSend && validatedRecipientEmail && emailConfigured) {
        try {
          const formattedAmount = (Math.round(amount * 100) / 100).toFixed(2);
          const subject = `Your $${formattedAmount} gift card from ${storeName}`;
          const html = `
            <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto;">
              <h2>${storeName} gift card</h2>
              <p>Hello${validatedRecipientName ? ` ${validatedRecipientName}` : ''},</p>
              <p>You've received a gift card worth <strong>$${formattedAmount}</strong>.</p>
              <p>Present this code at checkout or quote it over the phone:</p>
              <div style="font-family: 'Courier New', monospace; font-size: 24px; letter-spacing: 4px;
                          background: #f3f4f6; padding: 16px; text-align: center; border-radius: 8px;">
                ${code}
              </div>
              ${validatedExpiresAt ? `<p>Expires: ${validatedExpiresAt}</p>` : ''}
              <p style="color: #6b7280; font-size: 12px; margin-top: 24px;">
                Keep this code safe — anyone with it can redeem the card.
              </p>
            </div>
          `;
          emailSent = await sendEmail(req.db, {
            to: validatedRecipientEmail,
            subject,
            html,
          });
        } catch (emailErr) {
          logger.warn('gift_card_recipient_email_failed', {
            gift_card_id: Number(result.lastInsertRowid),
            bulk: true,
            error: emailErr instanceof Error ? emailErr.message : String(emailErr),
          });
        }
      }

      results.push({
        index: i,
        status: 'ok',
        id: Number(result.lastInsertRowid),
        code,
        code_prefix: code.slice(0, 4),
        recipient_email_sent: emailSent,
      });
      okCount++;
    } catch (rowErr) {
      logger.warn('gift_card_bulk_row_error', {
        index: i,
        error: rowErr instanceof Error ? rowErr.message : String(rowErr),
      });
      results.push({
        index: i,
        status: 'error',
        message: rowErr instanceof Error ? rowErr.message : 'Unexpected error',
      });
    }
  }

  audit(req.db, 'gift_card_bulk_issued', req.user!.id, req.ip || 'unknown', {
    row_count: rowsRaw.length,
    ok_count: okCount,
    reject_count: rowsRaw.length - okCount,
  });

  res.status(okCount > 0 ? 201 : 400).json({
    success: okCount > 0,
    data: {
      ok_count: okCount,
      reject_count: rowsRaw.length - okCount,
      results,
    },
  });
}));

// POST /:id/redeem — Redeem gift card (at POS)
// SC3-equivalent: Guarded atomic decrement prevents parallel double-spend.
// SEC-H25: redeeming a gift card is a financial write — gate behind gift_cards.redeem.
router.post('/:id/redeem', requirePermission('gift_cards.redeem'), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const cardId = validateId(req.params.id, 'id');

  const amount = validatePositiveAmount(req.body.amount, 'amount');
  const invoiceIdRaw = req.body.invoice_id;
  let invoiceId: number | null = null;
  if (invoiceIdRaw !== undefined && invoiceIdRaw !== null && invoiceIdRaw !== '') {
    invoiceId = Number(invoiceIdRaw);
    if (!Number.isInteger(invoiceId) || invoiceId <= 0) {
      throw new AppError('invoice_id must be a positive integer', 400);
    }
  }

  const card = await adb.get<GiftCardRow>('SELECT * FROM gift_cards WHERE id = ? AND is_deleted = 0', cardId);
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status !== 'active') throw new AppError(`Gift card is ${card.status}`, 400);
  if (isExpired(card.expires_at)) {
    throw new AppError('Gift card expired', 400);
  }

  // Guarded atomic decrement — prevents race where two parallel requests both
  // pass a naive balance check. S20-G2: flip status to 'used' in the same
  // UPDATE so we never leak a window where a drained card still reads as
  // active. SEC-H114: also re-check expires_at in the WHERE clause so a card
  // that crosses its expiry boundary between the SELECT above and this UPDATE
  // cannot be redeemed.
  // BUGHUNT-2026-05-10-24: bump version stamp inside the guarded UPDATE so
  // another tab's stale balance + version becomes detectable via the
  // version field in the redeem/reload response.
  const dec = await adb.run(
    `UPDATE gift_cards
        SET current_balance = current_balance - ?,
            status = CASE
                       WHEN current_balance - ? <= 0 THEN 'used'
                       ELSE status
                     END,
            version = version + 1,
            updated_at = ?
      WHERE id = ? AND status = 'active' AND current_balance >= ?
        AND (expires_at IS NULL
             OR datetime(substr(expires_at, 1, 10), '+1 day') > datetime('now'))`,
    amount, amount, now(), cardId, amount,
  );
  if (dec.changes === 0) {
    throw new AppError('Gift card balance insufficient or expired', 409);
  }

  // Re-read committed balance + status for the response (avoid stale values).
  // BUGHUNT-2026-05-10-24: include version so concurrent-tab consumers can
  // detect a stale view.
  const fresh = await adb.get<GiftCardRow>(
    'SELECT current_balance, status, version FROM gift_cards WHERE id = ?',
    cardId,
  );
  const newBalance = roundCurrency(fresh?.current_balance ?? 0);
  const newStatus = fresh?.status ?? 'active';
  const newVersion = (fresh as any)?.version ?? null;

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
  res.json({ success: true, data: { new_balance: newBalance, status: newStatus, version: newVersion } });
}));

// POST /:id/reload — Add balance to gift card
// SEC-H25: reloading a gift card adds monetary value — gate behind gift_cards.reload.
router.post('/:id/reload', requirePermission('gift_cards.reload'), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const cardId = validateId(req.params.id, 'id');

  const amount = validatePositiveAmount(req.body.amount, 'amount');
  if (amount > GIFT_CARD_MAX_AMOUNT) {
    throw new AppError(`Reload amount cannot exceed $${GIFT_CARD_MAX_AMOUNT.toLocaleString()}`, 400);
  }

  const card = await adb.get<GiftCardRow>('SELECT * FROM gift_cards WHERE id = ? AND is_deleted = 0', cardId);
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status === 'disabled') throw new AppError('Gift card is disabled', 400);

  // Differential balance + ? (not SET to a fixed value) so two concurrent
  // reload requests don't race-overwrite each other's credit. AND is_deleted = 0
  // closes the window where a card is logically deleted between the SELECT
  // precheck and this write (SEC-H62 reload guard).
  // BUGHUNT-2026-05-10-24: bump version on reload too.
  const reloadResult = await adb.run(
    "UPDATE gift_cards SET current_balance = current_balance + ?, status = 'active', version = version + 1, updated_at = ? WHERE id = ? AND is_deleted = 0",
    amount, now(), cardId,
  );
  if (reloadResult.changes === 0) {
    throw new AppError('Gift card not found or was deleted (concurrent request)', 409);
  }
  await adb.run(
    'INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    cardId, 'adjustment', amount, 'Reloaded', req.user!.id, now(),
  );

  // Re-read committed balance for accuracy (avoid stale computed values).
  // BUGHUNT-2026-05-10-24: include version for concurrent-tab detection.
  const fresh = await adb.get<GiftCardRow>(
    'SELECT current_balance, version FROM gift_cards WHERE id = ?',
    cardId,
  );
  const newBalance = roundCurrency(fresh?.current_balance ?? 0);
  const newVersion = (fresh as any)?.version ?? null;
  audit(db, 'gift_card_reloaded', req.user!.id, req.ip || 'unknown', {
    gift_card_id: cardId,
    amount,
    new_balance: newBalance,
  });
  res.json({ success: true, data: { new_balance: newBalance, version: newVersion } });
}));

// GET /:id — Gift card details with transactions
router.get('/:id', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const cardId = validateId(req.params.id, 'id');
  // WEB-UIUX-1452: join customers so the detail page can render a click-
  // through link to the linked customer (list view already joins).
  const card = await adb.get<GiftCardRow & {
    customer_first_name?: string | null;
    customer_last_name?: string | null;
  }>(
    `SELECT gc.*,
            c.first_name AS customer_first_name,
            c.last_name AS customer_last_name
       FROM gift_cards gc
       LEFT JOIN customers c ON c.id = gc.customer_id
      WHERE gc.id = ? AND gc.is_deleted = 0`,
    cardId,
  );
  if (!card) throw new AppError('Gift card not found', 404);
  // WEB-UIUX-991 / 992: hydrate `by` (user first/last) and `invoice_order_id`
  // so the detail page transactions table can show audit context. LEFT JOIN
  // keeps legacy rows (user_id NULL) renderable. invoice_order_id lets the
  // operator pivot from gift-card-tx → invoice without hand-mapping ids.
  const transactions = await adb.all(
    `SELECT t.*,
            u.first_name AS by_first_name,
            u.last_name  AS by_last_name,
            i.order_id   AS invoice_order_id
       FROM gift_card_transactions t
       LEFT JOIN users u ON u.id = t.user_id
       LEFT JOIN invoices i ON i.id = t.invoice_id
      WHERE t.gift_card_id = ?
      ORDER BY t.created_at DESC`,
    cardId,
  );
  // WEB-UIUX-1544: gate plaintext `code` reveal on permission. Any user with
  // gift_cards.issue OR gift_cards.redeem (the operators who actually need
  // the code to mint or apply a card) sees the full value + the reveal is
  // audited so a future investigation has a per-call trail. Users without
  // either permission (analytics-only roles, kiosks, etc.) get a masked
  // form (`first 4 + last 4`) so the page still renders sensibly while not
  // leaking the redemption secret. Closes the "any authed user can iterate
  // /gift-cards/:id and harvest plaintext" path from the audit.
  const canRevealCode =
    hasPermission(req.user, 'gift_cards.issue')
    || hasPermission(req.user, 'gift_cards.redeem');
  const fullCode = String(card.code ?? '');
  let exposedCode: string | null;
  if (canRevealCode) {
    exposedCode = fullCode;
    audit(req.db, 'gift_card_code_revealed', req.user!.id, req.ip || 'unknown', {
      gift_card_id: cardId,
    });
  } else {
    exposedCode = fullCode.length > 8
      ? `${fullCode.slice(0, 4)}****${fullCode.slice(-4)}`
      : null;
  }
  res.json({
    success: true,
    data: {
      ...card,
      code: exposedCode,
      code_revealed: canRevealCode,
      transactions,
    },
  });
}));

// WEB-UIUX-1546: POST /:id/disable — mark a gift card as disabled so a
// reported-stolen / lost card can no longer be redeemed. Manager/admin
// only; audited. Re-using the existing `disabled` status enum value
// (`gift_cards.status` already accepts it via column check). Reversal
// path is `/:id/enable`.
router.post('/:id/disable', requirePermission('gift_cards.reload'), asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const db = req.db;
  const cardId = validateId(req.params.id, 'id');
  const reasonRaw = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
  const reason = reasonRaw.length > 0 ? reasonRaw.slice(0, 500) : null;

  const card = await adb.get<GiftCardRow>(
    'SELECT * FROM gift_cards WHERE id = ? AND is_deleted = 0',
    cardId,
  );
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status === 'disabled') {
    throw new AppError('Gift card is already disabled', 400);
  }
  if (card.status === 'used') {
    throw new AppError('Cannot disable a fully-redeemed card', 400);
  }

  // BUGHUNT-2026-05-10-24: bump version on disable.
  await adb.run(
    "UPDATE gift_cards SET status = 'disabled', version = version + 1, updated_at = datetime('now') WHERE id = ?",
    cardId,
  );

  // Audit entry — capture who, when, why, and the prior status so a
  // mis-clicked disable can be reverted via /enable with full context.
  audit(db, 'gift_card_disabled', req.user!.id, req.ip || 'unknown', {
    gift_card_id: cardId,
    prior_status: card.status,
    current_balance: card.current_balance,
    reason,
  });

  res.json({ success: true, data: { id: cardId, status: 'disabled' } });
}));

// WEB-UIUX-1546: POST /:id/enable — reverse a previous disable so an
// admin can revive a mistakenly disabled card. Re-uses the manager+
// permission gate. Refuses if the card is fully redeemed (status='used')
// since revival would have zero balance regardless.
router.post('/:id/enable', requirePermission('gift_cards.reload'), asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const db = req.db;
  const cardId = validateId(req.params.id, 'id');

  const card = await adb.get<GiftCardRow>(
    'SELECT * FROM gift_cards WHERE id = ? AND is_deleted = 0',
    cardId,
  );
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status !== 'disabled') {
    throw new AppError(`Cannot enable a card in status '${card.status}'`, 400);
  }

  // Restore to 'active' when balance remains; otherwise let the next
  // redemption attempt fail explicitly on the balance check.
  const restoredStatus = Number(card.current_balance) > 0 ? 'active' : 'used';
  // BUGHUNT-2026-05-10-24: bump version on enable.
  await adb.run(
    "UPDATE gift_cards SET status = ?, version = version + 1, updated_at = datetime('now') WHERE id = ?",
    restoredStatus,
    cardId,
  );

  audit(db, 'gift_card_enabled', req.user!.id, req.ip || 'unknown', {
    gift_card_id: cardId,
    new_status: restoredStatus,
  });

  res.json({ success: true, data: { id: cardId, status: restoredStatus } });
}));

// ────────────────────────────────────────────────────────────────────
// WEB-UIUX-1000: resend gift-card code to recipient email
// ────────────────────────────────────────────────────────────────────
// Customer lost the original delivery email or paper slip. Staff with the
// gift_cards.issue permission can re-send the plaintext code via email,
// using either the stored recipient_email or an override supplied in the
// request body. Rate-limited at 5 sends per card per hour to make
// brute-force enumeration unviable; audit-logged with the override email
// when present so the trail captures who got the code.
router.post('/:id/resend-code', requirePermission('gift_cards.issue'), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb: AsyncDb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const role = req.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }

  // Rate limit — 5 per card per hour. Reuses checkWindowRate so the cap is
  // shared across multiple sessions of the same shop.
  const rateKey = `resend:${id}`;
  if (!checkWindowRate(db, 'gift_card_resend', rateKey, 5, 3600_000)) {
    res.status(429).json({
      success: false,
      message: 'Too many resend attempts for this card. Try again in an hour.',
    });
    return;
  }

  const card = await adb.get<{
    id: number;
    code: string | null;
    current_balance: number;
    initial_balance: number;
    status: string;
    recipient_email: string | null;
    recipient_name: string | null;
    expires_at: string | null;
  }>(
    `SELECT id, code, current_balance, initial_balance, status,
            recipient_email, recipient_name, expires_at
       FROM gift_cards WHERE id = ?`,
    id,
  );
  if (!card) throw new AppError('Gift card not found', 404);
  if (card.status !== 'active') {
    throw new AppError(`Cannot resend code for a ${card.status} card.`, 409);
  }
  if (!card.code) {
    // SEC-H38 follow-up: post-rollover the plaintext column will be dropped
    // and this path will need a different recovery flow (e.g. re-issue +
    // void). Until then the plaintext is still on the row.
    throw new AppError('Original plaintext code is no longer stored for this card.', 409);
  }

  const overrideEmailRaw = typeof req.body?.email === 'string' ? req.body.email.trim() : '';
  const targetEmail = overrideEmailRaw
    ? validateTextLength(overrideEmailRaw, 200, 'email')
    : card.recipient_email;
  if (!targetEmail) {
    throw new AppError(
      'No recipient email on file — pass `email` in the request body to resend.',
      400,
    );
  }

  if (!isEmailConfigured(db)) {
    throw new AppError(
      'Email is not configured for this shop — cannot resend the code.',
      503,
    );
  }

  const storeName = (db
    .prepare("SELECT value FROM store_config WHERE key = 'store_name'")
    .get() as { value: string } | undefined)?.value || 'Your repair shop';
  const formattedAmount = (Math.round(card.current_balance * 100) / 100).toFixed(2);
  const subject = `Your gift card code from ${storeName}`;
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto;">
      <h2>${storeName} gift card</h2>
      <p>Hello${card.recipient_name ? ` ${card.recipient_name}` : ''},</p>
      <p>Re-sending the code for your gift card. Current balance: <strong>$${formattedAmount}</strong>.</p>
      <p>Present this code at checkout or quote it over the phone:</p>
      <div style="font-family: 'Courier New', monospace; font-size: 24px; letter-spacing: 4px;
                  background: #f3f4f6; padding: 16px; text-align: center; border-radius: 8px;">
        ${card.code}
      </div>
      ${card.expires_at ? `<p>Expires: ${card.expires_at}</p>` : ''}
      <p style="color: #6b7280; font-size: 12px; margin-top: 24px;">
        Keep this code safe — anyone with it can redeem the card.
      </p>
    </div>
  `;
  const sent = await sendEmail(db, { to: targetEmail, subject, html });
  if (!sent) {
    recordWindowFailure(db, 'gift_card_resend', rateKey, 3600_000);
    throw new AppError('Email send failed — check SMTP configuration.', 502);
  }

  audit(db, 'gift_card_code_resent', req.user!.id, req.ip || 'unknown', {
    gift_card_id: id,
    code_prefix: card.code.slice(0, 4),
    delivered_to: targetEmail,
    override: !!overrideEmailRaw,
  });
  res.json({ success: true, data: { gift_card_id: id, delivered_to: targetEmail } });
}));

// ────────────────────────────────────────────────────────────────────
// WEB-UIUX-1001: dual-control pending-issuance queue
// ────────────────────────────────────────────────────────────────────

// GET /gift-cards/pending-issuances — admin queue of awaiting-approval rows.
// Filters: ?status=pending (default) | approved | declined | cancelled | all.
router.get('/pending-issuances', asyncHandler(async (req, res) => {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin role required to view the pending-issuance queue', 403);
  }
  const adb = req.asyncDb;
  const statusRaw = typeof req.query.status === 'string' ? req.query.status.trim().toLowerCase() : 'pending';
  const allowed = ['pending', 'approved', 'declined', 'cancelled', 'all'];
  const status = allowed.includes(statusRaw) ? statusRaw : 'pending';
  const where = status === 'all' ? '' : 'WHERE p.status = ?';
  const args = status === 'all' ? [] : [status];
  const rows = await adb.all(`
    SELECT p.*, u.first_name AS requester_first, u.last_name AS requester_last,
           a.first_name AS approver_first, a.last_name AS approver_last,
           c.first_name AS customer_first, c.last_name AS customer_last
      FROM gift_card_pending_issuances p
      LEFT JOIN users u ON u.id = p.requester_id
      LEFT JOIN users a ON a.id = p.approver_id
      LEFT JOIN customers c ON c.id = p.customer_id
      ${where}
      ORDER BY p.created_at DESC
      LIMIT 200
  `, ...args);
  res.json({ success: true, data: rows });
}));

// POST /gift-cards/pending-issuances/:id/approve — admin approves + mints.
router.post('/pending-issuances/:id/approve', asyncHandler(async (req, res) => {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin role required to approve gift-card issuance', 403);
  }
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const pending = await adb.get<{
    id: number;
    amount: number;
    customer_id: number | null;
    recipient_name: string | null;
    recipient_email: string | null;
    expires_at: string | null;
    notes: string | null;
    requester_id: number;
    status: string;
  }>(`SELECT id, amount, customer_id, recipient_name, recipient_email, expires_at, notes,
             requester_id, status
        FROM gift_card_pending_issuances WHERE id = ?`, id);
  if (!pending) throw new AppError('Pending issuance not found', 404);
  if (pending.status !== 'pending') {
    throw new AppError(`Pending issuance is ${pending.status}; cannot approve.`, 409);
  }
  // Approver cannot be the requester — dual-control invariant.
  if (pending.requester_id === req.user!.id) {
    throw new AppError(
      'Different admin must approve — the requester cannot approve their own pending issuance.',
      403,
    );
  }

  const code = generateCode();
  const codeHash = hashCode(code);
  const inserted = await adb.run(
    `INSERT INTO gift_cards (code, code_hash, initial_balance, current_balance, status,
       customer_id, recipient_name, recipient_email, expires_at, notes, created_by,
       created_at, updated_at)
     VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?)`,
    code, codeHash, pending.amount, pending.amount, pending.customer_id,
    pending.recipient_name, pending.recipient_email, pending.expires_at, pending.notes,
    pending.requester_id, now(), now(),
  );
  const giftCardId = Number(inserted.lastInsertRowid);
  await adb.run(
    `INSERT INTO gift_card_transactions (gift_card_id, type, amount, notes, user_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    giftCardId, 'purchase', pending.amount,
    `Dual-control issuance (pending #${id})`, pending.requester_id, now(),
  );
  await adb.run(
    `UPDATE gift_card_pending_issuances
        SET status = 'approved', approver_id = ?, decided_at = datetime('now'), gift_card_id = ?
      WHERE id = ? AND status = 'pending'`,
    req.user!.id, giftCardId, id,
  );

  audit(req.db, 'gift_card_pending_issuance_approved', req.user!.id, req.ip || 'unknown', {
    pending_issuance_id: id,
    gift_card_id: giftCardId,
    code_prefix: code.slice(0, 4),
    code_hash: codeHash,
    amount: pending.amount,
    requester_id: pending.requester_id,
  });
  res.json({
    success: true,
    data: {
      pending_issuance_id: id,
      gift_card_id: giftCardId,
      code,
      amount: pending.amount,
    },
  });
}));

// POST /gift-cards/pending-issuances/:id/decline — admin declines without minting.
router.post('/pending-issuances/:id/decline', asyncHandler(async (req, res) => {
  if (req.user?.role !== 'admin') {
    throw new AppError('Admin role required to decline gift-card issuance', 403);
  }
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const reason = typeof req.body?.reason === 'string'
    ? validateTextLength(req.body.reason, 500, 'reason')
    : null;
  const result = await adb.run(
    `UPDATE gift_card_pending_issuances
        SET status = 'declined', approver_id = ?, decline_reason = ?, decided_at = datetime('now')
      WHERE id = ? AND status = 'pending'`,
    req.user!.id, reason, id,
  );
  if (result.changes === 0) {
    throw new AppError('Pending issuance not found or no longer pending', 404);
  }
  audit(req.db, 'gift_card_pending_issuance_declined', req.user!.id, req.ip || 'unknown', {
    pending_issuance_id: id,
    reason,
  });
  res.json({ success: true, data: { pending_issuance_id: id } });
}));

export default router;
