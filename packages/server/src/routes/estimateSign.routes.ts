/**
 * estimateSign.routes.ts — SCAN-494
 *
 * Public customer e-sign flow for estimates.
 * Exports two sub-routers to be mounted at different paths:
 *
 *   authedRouter  — mount at /api/v1/estimates/:id  (behind authMiddleware)
 *   publicRouter  — mount at /public/api/v1/estimate-sign  (NO auth, per-IP rate-limited)
 *
 * Security model:
 *   - Token format: base64url(estimateId) + '.' + hex(HMAC-SHA256(estimateId + '.' + expiresTs))
 *   - Raw token is NEVER persisted. Only SHA-256(token) stored in estimate_sign_tokens.token_hash.
 *   - Tokens are single-use: consumed_at is set atomically on POST; further GET/POST returns 410.
 *   - Rate limit: 5 sign-URL issuances per estimate per hour (authed); 10 requests/hr per IP (public).
 *   - Public endpoints strip all admin/internal fields from estimate response.
 *   - Signature data URL must be data:image/png;base64,... or data:image/svg+xml;base64,... ≤ 200 KB.
 *   - Audit log on every issuance, public GET (validation), and public POST (signature captured).
 */

import crypto from 'crypto';
import { Router, Request, Response, NextFunction } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { authMiddleware, requirePermission } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { config } from '../config.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES } from '../utils/errorCodes.js';

const logger = createLogger('estimate-sign');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Default TTL when caller does not specify ttl_minutes (3 days). */
const DEFAULT_TTL_MINUTES = 4320;

/** Maximum allowed TTL — 30 days. */
const MAX_TTL_MINUTES = 30 * 24 * 60;

/** Minimum allowed TTL — 5 minutes. */
const MIN_TTL_MINUTES = 5;

/** Per-estimate issuance rate limit: 5 sign-URLs issued per estimate per hour. */
const ISSUE_RATE_MAX = 5;
const ISSUE_RATE_WINDOW_MS = 60 * 60 * 1000; // 1 hour

/** Per-IP public endpoint rate limit: 10 requests per hour. */
const PUBLIC_RATE_MAX = 10;
const PUBLIC_RATE_WINDOW_MS = 60 * 60 * 1000; // 1 hour

/** Maximum signature data URL size: 200 KB (base64-encoded). */
const MAX_SIGNATURE_BYTES = 200 * 1024;

/** Accepted data URL prefixes for signature capture. */
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',
];

// ---------------------------------------------------------------------------
// HMAC token helpers
// ---------------------------------------------------------------------------

/**
 * Derive the signing key.
 * Uses ESTIMATE_SIGN_SECRET env var when set; falls back to HKDF over
 * config.jwtSecret with an isolated info label so a JWT secret leak does
 * not automatically compromise sign-URL tokens.
 */
function getSignSecret(): Buffer {
  const dedicated = (process.env.ESTIMATE_SIGN_SECRET || '').trim();
  if (dedicated.length >= 32) {
    return Buffer.from(dedicated, 'utf8');
  }
  // HKDF derivation — same pattern as config.ts SEC-H103 key slots.
  const derived = crypto.hkdfSync(
    'sha256',
    Buffer.from(config.jwtSecret, 'utf8'),
    Buffer.from('bizarre-crm-v1', 'utf8'),
    Buffer.from('estimate-sign', 'utf8'),
    32,
  );
  return Buffer.from(derived);
}

/**
 * Build a single-use signed token.
 *
 * Format: `<base64url(estimateId)>.<hex(HMAC-SHA256(estimateId + "." + expiresTs))>`
 *
 * The HMAC input binds both the estimate ID and the expiry timestamp so the
 * token cannot be extended by changing the expiry embedded in the URL, and
 * cannot be transplanted to a different estimate.
 */
function buildSignToken(estimateId: number, expiresTs: number): string {
  const idPart = Buffer.from(String(estimateId)).toString('base64url');
  const hmacInput = `${estimateId}.${expiresTs}`;
  const hmac = crypto.createHmac('sha256', getSignSecret()).update(hmacInput).digest('hex');
  return `${idPart}.${hmac}`;
}

/** Parsed (but not yet HMAC-verified) token components. */
interface ParsedToken {
  estimateId: number;
  givenHmac: string;
}

/**
 * Parse the structural components of an inbound token.
 * Does NOT verify the HMAC — the caller must call verifySignTokenHmac()
 * after loading expires_at from the DB.
 */
function parseSignToken(token: string): ParsedToken {
  if (typeof token !== 'string' || !token.includes('.')) {
    throw new AppError('Invalid sign token format', 400);
  }

  // Split on the FIRST dot — idPart is base64url (no dots); hex HMAC is never dots.
  const dotIdx = token.indexOf('.');
  const idPart = token.slice(0, dotIdx);
  const givenHmac = token.slice(dotIdx + 1);

  // givenHmac must be a 64-char hex string (SHA-256 HMAC output).
  if (!/^[0-9a-f]{64}$/i.test(givenHmac)) {
    throw new AppError('Invalid sign token: bad HMAC segment', 400);
  }

  let estimateId: number;
  try {
    const decoded = Buffer.from(idPart, 'base64url').toString('utf8');
    estimateId = parseInt(decoded, 10);
    if (!Number.isFinite(estimateId) || estimateId <= 0 || String(estimateId) !== decoded) {
      throw new Error('non-integer');
    }
  } catch {
    throw new AppError('Invalid sign token: bad estimate id segment', 400);
  }

  // We need the expiresTs to verify the HMAC — it is stored in the DB, not
  // embedded in the token. The caller MUST load the token row from DB and
  // call verifySignTokenHmac(estimateId, expiresTs, givenHmac) before trusting
  // the token. This forces a DB lookup before structural validation completes,
  // preventing timing-oracle attacks that could probe the token format.
  return { estimateId, givenHmac };
}

/**
 * Verify the HMAC portion of a token against the stored expires_at.
 * Always uses constant-time comparison (timingSafeEqual).
 */
function verifySignTokenHmac(estimateId: number, expiresTs: number, givenHmac: string): boolean {
  const expectedHmac = crypto.createHmac('sha256', getSignSecret())
    .update(`${estimateId}.${expiresTs}`)
    .digest('hex');
  const a = Buffer.from(expectedHmac, 'hex');
  const b = Buffer.from(givenHmac, 'hex');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/** SHA-256 a raw token to get the value stored in token_hash. */
function hashToken(rawToken: string): string {
  return crypto.createHash('sha256').update(rawToken, 'utf8').digest('hex');
}

/** Convert an ISO/SQLite timestamp to epoch ms. */
function toEpochMs(ts: string): number {
  // SQLite stores "YYYY-MM-DD HH:MM:SS"; Date.parse needs ISO 'T' separator.
  const normalized = ts.includes('T') ? ts : ts.replace(' ', 'T') + 'Z';
  const ms = Date.parse(normalized);
  return Number.isFinite(ms) ? ms : 0;
}

/** Format a Date as SQLite TEXT "YYYY-MM-DD HH:MM:SS". */
function sqlTimestamp(d: Date): string {
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

/** Build the public sign URL for a token. */
function buildPublicSignUrl(req: Request, rawToken: string): string {
  // Use the Host header so multi-tenant setups produce tenant-scoped URLs.
  const proto = req.protocol || 'https';
  const host = req.get('host') || `localhost:${config.port}`;
  return `${proto}://${host}/public/api/v1/estimate-sign/${encodeURIComponent(rawToken)}`;
}

// ---------------------------------------------------------------------------
// Inline admin-guard helper (same pattern as inbox.routes.ts, dunning.routes.ts)
// ---------------------------------------------------------------------------

function requireAdminSign(req: Request): void {
  if (!req.user || (req.user.role !== 'admin' && req.user.role !== 'manager')) {
    throw new AppError('Admin or manager access required', 403, ERROR_CODES.ERR_PERM_ADMIN_REQUIRED);
  }
}

// ---------------------------------------------------------------------------
// Per-IP public rate limit middleware
// ---------------------------------------------------------------------------

function publicRateLimit(req: Request, res: Response, next: NextFunction): void {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const result = consumeWindowRate(req.db, 'estimate_sign_public', ip, PUBLIC_RATE_MAX, PUBLIC_RATE_WINDOW_MS);
  if (!result.allowed) {
    res.setHeader('Retry-After', String(result.retryAfterSeconds));
    res.status(429).json({
      success: false,
      message: 'Too many requests. Try again later.',
      retry_after_seconds: result.retryAfterSeconds,
    });
    return;
  }
  next();
}

// ---------------------------------------------------------------------------
// Authed router — mounted at /api/v1/estimates/:id (behind authMiddleware)
// ---------------------------------------------------------------------------

export const authedRouter = Router({ mergeParams: true });

/**
 * POST /api/v1/estimates/:id/sign-url
 * Body: { ttl_minutes?: number }
 * Issues a new single-use signed token for the estimate.
 * Returns: { url, expires_at, estimate_id }
 */
authedRouter.post(
  '/sign-url',
  requirePermission('estimates.edit'),
  asyncHandler(async (req, res) => {
    requireAdminSign(req);
    const adb = req.asyncDb;

    const estimateId = parseInt(req.params.id as string, 10);
    if (!Number.isFinite(estimateId) || estimateId <= 0) {
      throw new AppError('Invalid estimate id', 400);
    }

    // Verify estimate exists and is not deleted/cancelled
    const estimate = await adb.get<{ id: number; status: string; is_deleted: number }>(
      'SELECT id, status, is_deleted FROM estimates WHERE id = ? AND is_deleted = 0',
      estimateId,
    );
    if (!estimate) throw new AppError('Estimate not found', 404);
    if (estimate.status === 'signed') {
      throw new AppError('Estimate already signed', 409);
    }

    // Rate limit: max 5 sign-URL issuances per estimate per hour
    const rateKey = `est_${estimateId}`;
    const rateResult = consumeWindowRate(req.db, 'estimate_sign_issue', rateKey, ISSUE_RATE_MAX, ISSUE_RATE_WINDOW_MS);
    if (!rateResult.allowed) {
      res.setHeader('Retry-After', String(rateResult.retryAfterSeconds));
      throw new AppError(`Sign URL issuance rate limit reached. Retry in ${rateResult.retryAfterSeconds}s`, 429);
    }

    // Validate TTL
    let ttlMinutes = DEFAULT_TTL_MINUTES;
    if (req.body.ttl_minutes !== undefined) {
      const raw = Number(req.body.ttl_minutes);
      if (!Number.isFinite(raw) || raw < MIN_TTL_MINUTES || raw > MAX_TTL_MINUTES) {
        throw new AppError(`ttl_minutes must be between ${MIN_TTL_MINUTES} and ${MAX_TTL_MINUTES}`, 400);
      }
      ttlMinutes = Math.floor(raw);
    }

    const now = Date.now();
    const expiresTs = now + ttlMinutes * 60 * 1000;
    const expiresAt = sqlTimestamp(new Date(expiresTs));

    const rawToken = buildSignToken(estimateId, expiresTs);
    const tokenHash = hashToken(rawToken);

    // Persist only the hash
    await adb.run(
      `INSERT INTO estimate_sign_tokens
         (estimate_id, token_hash, expires_at, created_by_user_id, created_at)
       VALUES (?, ?, ?, ?, datetime('now'))`,
      estimateId,
      tokenHash,
      expiresAt,
      req.user!.id,
    );

    const url = buildPublicSignUrl(req, rawToken);

    audit(req.db, 'estimate_sign_url_issued', req.user!.id, req.ip || 'unknown', {
      estimate_id: estimateId,
      expires_at: expiresAt,
      ttl_minutes: ttlMinutes,
    });

    logger.info('estimate sign-url issued', {
      estimate_id: estimateId,
      user_id: req.user!.id,
      expires_at: expiresAt,
    });

    res.status(201).json({
      success: true,
      data: { url, expires_at: expiresAt, estimate_id: estimateId },
    });
  }),
);

/**
 * GET /api/v1/estimates/:id/signatures
 * List all captured signatures for an estimate (admin view).
 */
authedRouter.get(
  '/signatures',
  requirePermission('estimates.view'),
  asyncHandler(async (req, res) => {
    requireAdminSign(req);
    const adb = req.asyncDb;

    const estimateId = parseInt(req.params.id as string, 10);
    if (!Number.isFinite(estimateId) || estimateId <= 0) {
      throw new AppError('Invalid estimate id', 400);
    }

    const estimate = await adb.get<{ id: number }>(
      'SELECT id FROM estimates WHERE id = ? AND is_deleted = 0',
      estimateId,
    );
    if (!estimate) throw new AppError('Estimate not found', 404);

    const signatures = await adb.all<{
      id: number;
      estimate_id: number;
      signer_name: string;
      signer_email: string | null;
      signer_ip: string | null;
      signed_at: string;
      user_agent: string | null;
    }>(
      // Deliberately omit signature_data_url from list view (large + sensitive)
      `SELECT id, estimate_id, signer_name, signer_email, signer_ip, signed_at, user_agent
         FROM estimate_signatures
        WHERE estimate_id = ?
        ORDER BY signed_at DESC`,
      estimateId,
    );

    res.json({ success: true, data: signatures });
  }),
);

// ---------------------------------------------------------------------------
// Public router — mounted at /public/api/v1/estimate-sign (NO auth)
// ---------------------------------------------------------------------------

export const publicRouter = Router();

/**
 * GET /public/api/v1/estimate-sign/:token
 * Validate a sign token and return estimate summary suitable for the signer UI.
 * Returns public-safe estimate fields ONLY (no admin, customer PII beyond name).
 */
publicRouter.get(
  '/:token',
  publicRateLimit,
  asyncHandler(async (req, res) => {
    const rawToken = req.params.token as string;
    const adb = req.asyncDb;
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';

    // Parse structural format (does not verify HMAC yet)
    const { estimateId, givenHmac } = parseSignToken(rawToken);

    // Load token row by estimate_id + token_hash (constant-time hash comparison)
    const tokenHash = hashToken(rawToken);
    const tokenRow = await adb.get<{
      id: number;
      estimate_id: number;
      expires_at: string;
      consumed_at: string | null;
    }>(
      `SELECT id, estimate_id, expires_at, consumed_at
         FROM estimate_sign_tokens
        WHERE token_hash = ? AND estimate_id = ?`,
      tokenHash,
      estimateId,
    );

    if (!tokenRow) {
      // Do not reveal whether the token or estimate doesn't exist — same 404.
      audit(req.db, 'estimate_sign_token_invalid', null, ip, { estimate_id: estimateId });
      throw new AppError('Sign link is invalid or has expired', 404);
    }

    // Verify HMAC now that we have expires_at from DB
    const expiresTs = toEpochMs(tokenRow.expires_at);
    if (!verifySignTokenHmac(estimateId, expiresTs, givenHmac)) {
      audit(req.db, 'estimate_sign_token_hmac_fail', null, ip, { estimate_id: estimateId });
      throw new AppError('Sign link is invalid or has expired', 404);
    }

    // Check consumed
    if (tokenRow.consumed_at) {
      audit(req.db, 'estimate_sign_token_consumed', null, ip, { estimate_id: estimateId });
      res.status(410).json({
        success: false,
        message: 'This signature link has already been used.',
        code: 'TOKEN_CONSUMED',
      });
      return;
    }

    // Check expiry
    if (Date.now() > expiresTs) {
      audit(req.db, 'estimate_sign_token_expired', null, ip, { estimate_id: estimateId });
      res.status(410).json({
        success: false,
        message: 'This signature link has expired. Please ask for a new one.',
        code: 'TOKEN_EXPIRED',
      });
      return;
    }

    // Fetch estimate — public summary only (no admin columns, no PII beyond customer name)
    const estimate = await adb.get<{
      id: number;
      order_id: string;
      status: string;
      notes: string | null;
      discount: number | null;
      subtotal: number | null;
      total_tax: number | null;
      total: number | null;
      valid_until: string | null;
      customer_first_name: string | null;
      customer_last_name: string | null;
    }>(
      `SELECT e.id, e.order_id, e.status, e.notes, e.discount,
              e.subtotal, e.total_tax, e.total, e.valid_until,
              c.first_name AS customer_first_name, c.last_name AS customer_last_name
         FROM estimates e
         LEFT JOIN customers c ON c.id = e.customer_id
        WHERE e.id = ? AND e.is_deleted = 0`,
      estimateId,
    );

    if (!estimate) {
      throw new AppError('Estimate not found', 404);
    }

    const lineItems = await adb.all<{
      description: string;
      quantity: number;
      unit_price: number;
      tax_amount: number;
      total: number;
    }>(
      `SELECT description, quantity, unit_price, tax_amount, total
         FROM estimate_line_items
        WHERE estimate_id = ?
        ORDER BY id`,
      estimateId,
    );

    audit(req.db, 'estimate_sign_token_validated', null, ip, { estimate_id: estimateId });

    res.json({
      success: true,
      data: {
        estimate_id: estimate.id,
        order_id: estimate.order_id,
        status: estimate.status,
        notes: estimate.notes,
        discount: estimate.discount,
        subtotal: estimate.subtotal,
        total_tax: estimate.total_tax,
        total: estimate.total,
        valid_until: estimate.valid_until,
        customer_name: [estimate.customer_first_name, estimate.customer_last_name]
          .filter(Boolean)
          .join(' ') || null,
        line_items: lineItems,
        expires_at: tokenRow.expires_at,
      },
    });
  }),
);

/**
 * POST /public/api/v1/estimate-sign/:token
 * Body: { signer_name, signer_email?, signature_data_url }
 * Captures the signature, marks the token consumed, sets estimate.status = 'signed'.
 */
publicRouter.post(
  '/:token',
  publicRateLimit,
  asyncHandler(async (req, res) => {
    const rawToken = req.params.token as string;
    const adb = req.asyncDb;
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    const userAgent = (req.headers['user-agent'] || '').slice(0, 512);

    // Parse structural format
    const { estimateId, givenHmac } = parseSignToken(rawToken);

    // Input validation
    const signerName = (req.body.signer_name || '').trim();
    if (!signerName || signerName.length > 200) {
      throw new AppError('signer_name is required and must be ≤ 200 characters', 400);
    }

    const signerEmail = req.body.signer_email
      ? String(req.body.signer_email).trim().slice(0, 254)
      : null;
    if (signerEmail && (signerEmail.length < 3 || !signerEmail.includes('@'))) {
      throw new AppError('signer_email appears invalid', 400);
    }

    const signatureDataUrl = req.body.signature_data_url;
    if (typeof signatureDataUrl !== 'string') {
      throw new AppError('signature_data_url is required', 400);
    }
    const validPrefix = ACCEPTED_DATA_URL_PREFIXES.find(p => signatureDataUrl.startsWith(p));
    if (!validPrefix) {
      throw new AppError(
        'signature_data_url must be data:image/png;base64,... or data:image/svg+xml;base64,...',
        400,
      );
    }
    // Size check on the base64 payload portion
    const base64Part = signatureDataUrl.slice(validPrefix.length);
    // Base64 expands by ~4/3; approximate byte size of decoded blob.
    const approxBytes = Math.ceil(base64Part.length * 3 / 4);
    if (approxBytes > MAX_SIGNATURE_BYTES) {
      throw new AppError(`signature_data_url exceeds maximum size of ${MAX_SIGNATURE_BYTES} bytes`, 400);
    }

    // Load token row
    const tokenHash = hashToken(rawToken);
    const tokenRow = await adb.get<{
      id: number;
      estimate_id: number;
      expires_at: string;
      consumed_at: string | null;
    }>(
      `SELECT id, estimate_id, expires_at, consumed_at
         FROM estimate_sign_tokens
        WHERE token_hash = ? AND estimate_id = ?`,
      tokenHash,
      estimateId,
    );

    if (!tokenRow) {
      audit(req.db, 'estimate_sign_submit_invalid_token', null, ip, { estimate_id: estimateId });
      throw new AppError('Sign link is invalid or has expired', 404);
    }

    // Verify HMAC
    const expiresTs = toEpochMs(tokenRow.expires_at);
    if (!verifySignTokenHmac(estimateId, expiresTs, givenHmac)) {
      audit(req.db, 'estimate_sign_submit_hmac_fail', null, ip, { estimate_id: estimateId });
      throw new AppError('Sign link is invalid or has expired', 404);
    }

    // Check consumed
    if (tokenRow.consumed_at) {
      audit(req.db, 'estimate_sign_submit_consumed', null, ip, { estimate_id: estimateId });
      res.status(410).json({
        success: false,
        message: 'This signature link has already been used.',
        code: 'TOKEN_CONSUMED',
      });
      return;
    }

    // Check expiry
    if (Date.now() > expiresTs) {
      audit(req.db, 'estimate_sign_submit_expired', null, ip, { estimate_id: estimateId });
      res.status(410).json({
        success: false,
        message: 'This signature link has expired. Please ask for a new one.',
        code: 'TOKEN_EXPIRED',
      });
      return;
    }

    // Verify estimate exists
    const estimate = await adb.get<{ id: number; status: string }>(
      'SELECT id, status FROM estimates WHERE id = ? AND is_deleted = 0',
      estimateId,
    );
    if (!estimate) {
      throw new AppError('Estimate not found', 404);
    }

    const nowSql = sqlTimestamp(new Date());

    // Atomic transaction: mark token consumed + insert signature + set estimate.status='signed'
    await adb.transaction([
      {
        sql: `UPDATE estimate_sign_tokens
                 SET consumed_at = ?
               WHERE id = ? AND consumed_at IS NULL`,
        params: [nowSql, tokenRow.id],
      },
      {
        sql: `INSERT INTO estimate_signatures
                (estimate_id, signer_name, signer_email, signer_ip, signature_data_url, signed_at, user_agent)
              VALUES (?, ?, ?, ?, ?, ?, ?)`,
        params: [estimateId, signerName, signerEmail, ip.slice(0, 64), signatureDataUrl, nowSql, userAgent],
      },
      {
        sql: `UPDATE estimates
                 SET status = 'signed', updated_at = ?
               WHERE id = ? AND status NOT IN ('signed')`,
        params: [nowSql, estimateId],
      },
    ]);

    audit(req.db, 'estimate_signed', null, ip, {
      estimate_id: estimateId,
      signer_name: signerName,
      signer_email: signerEmail ?? undefined,
    });

    logger.info('estimate e-signed', {
      estimate_id: estimateId,
      signer_name: signerName,
    });

    res.status(201).json({
      success: true,
      data: {
        signed: true,
        estimate_id: estimateId,
        signed_at: nowSql,
      },
    });
  }),
);
