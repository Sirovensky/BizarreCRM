/**
 * requirePosPin — Server-side gate for POS tendering and ticket creation.
 *
 * When `pos_require_pin_sale` or `pos_require_pin_ticket` is enabled in
 * store_config the client must first call `POST /auth/verify-pin`, which on
 * success sets a short-lived (15 min) httpOnly cookie `pos_pin_token`
 * containing an HMAC-signed token bound to the authenticated user_id.  This
 * middleware validates that cookie token against the current request's
 * user_id and rejects with 403 when missing/invalid/expired.
 *
 * The actual PIN hash comparison happens in `/auth/verify-pin` (bcrypt,
 * rate-limited); this middleware only enforces that the step was completed.
 *
 * BUGHUNT-2026-05-16: previously this gate trusted a client-set
 * `X-Pos-Pin-Verified: 1` header. Any authenticated user could spoof that
 * header and bypass the PIN entirely. The cookie token is signed server-side
 * and bound to (user_id, expiry) so it cannot be forged or replayed across
 * users.
 *
 * Usage:
 *   router.post('/transaction', requirePosPinSale, asyncHandler(...))
 *   router.post('/checkout-with-ticket', requirePosPinSale, asyncHandler(...))
 *   // For ticket-only creation use requirePosPinTicket.
 */

import crypto from 'crypto';
import { Request, Response, NextFunction } from 'express';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';
import { config } from '../config.js';

function getConfigBool(db: any, key: string): boolean {
  try {
    const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value: string } | undefined;
    return row?.value === '1' || row?.value === 'true';
  } catch {
    return false;
  }
}

// BUGHUNT-2026-05-16: the previous "PIN gate" trusted a client-set
// `X-Pos-Pin-Verified: 1` header. Any authenticated user could spoof it.
// /auth/verify-pin now issues a short-lived HMAC-signed token bound to the
// user_id and an expiry, and sets it as an httpOnly cookie. The middleware
// below validates that token. The header is no longer consulted.
export const POS_PIN_COOKIE = 'pos_pin_token';
export const POS_PIN_TTL_SEC = 15 * 60;
const POS_PIN_KEY_LABEL = 'bizarre-crm:pos-pin-verified:v1';

function derivePosPinKey(): Buffer {
  return crypto.createHmac('sha256', POS_PIN_KEY_LABEL).update(config.jwtSecret).digest();
}

export function issuePosPinToken(userId: number, ttlSec: number = POS_PIN_TTL_SEC): string {
  const expiry = Math.floor(Date.now() / 1000) + ttlSec;
  const payload = `${userId}.${expiry}`;
  const sig = crypto.createHmac('sha256', derivePosPinKey()).update(payload).digest('hex');
  return `${payload}.${sig}`;
}

export function verifyPosPinToken(token: string, userId: number): boolean {
  if (typeof token !== 'string') return false;
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  const [uidStr, expiryStr, sigHex] = parts;
  const uid = parseInt(uidStr, 10);
  const expiry = parseInt(expiryStr, 10);
  if (!Number.isFinite(uid) || !Number.isFinite(expiry)) return false;
  if (uid !== userId) return false;
  if (Math.floor(Date.now() / 1000) >= expiry) return false;
  const payload = `${uid}.${expiry}`;
  const expected = crypto.createHmac('sha256', derivePosPinKey()).update(payload).digest('hex');
  try {
    const a = Buffer.from(sigHex, 'hex');
    const b = Buffer.from(expected, 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

function readPinCookie(req: Request): string | undefined {
  const raw = (req as unknown as { cookies?: Record<string, string> }).cookies?.[POS_PIN_COOKIE];
  return typeof raw === 'string' ? raw : undefined;
}

function currentUserId(req: Request): number | null {
  const id = (req as any).user?.id;
  return typeof id === 'number' && Number.isFinite(id) ? id : null;
}

/**
 * Gate for POS sale completion (POST /pos/transaction and
 * POST /pos/checkout-with-ticket when mode=checkout).
 *
 * When `pos_require_pin_sale` is enabled the request must carry the header
 * `X-Pos-Pin-Verified: 1` to proceed.
 */
export function requirePosPinSale(req: Request, res: Response, next: NextFunction): void {
  const db = (req as any).db;
  if (!db) { next(); return; }

  const flagOn = getConfigBool(db, 'pos_require_pin_sale');
  if (!flagOn) { next(); return; }

  const userId = currentUserId(req);
  const token = readPinCookie(req);
  if (userId !== null && token && verifyPosPinToken(token, userId)) { next(); return; }

  const rid = res.locals.requestId as string | undefined;
  res.status(403).json(errorBody(
    ERROR_CODES.ERR_PERM_INSUFFICIENT,
    'PIN verification required to complete sale. Verify your PIN in the POS screen first.',
    rid,
  ));
}

/**
 * Gate for POS ticket creation (POST /pos/checkout-with-ticket when
 * mode=create_ticket).
 *
 * When `pos_require_pin_ticket` is enabled the request must carry the header
 * `X-Pos-Pin-Verified: 1` to proceed.
 */
export function requirePosPinTicket(req: Request, res: Response, next: NextFunction): void {
  const db = (req as any).db;
  if (!db) { next(); return; }

  const flagOn = getConfigBool(db, 'pos_require_pin_ticket');
  if (!flagOn) { next(); return; }

  const userId = currentUserId(req);
  const token = readPinCookie(req);
  if (userId !== null && token && verifyPosPinToken(token, userId)) { next(); return; }

  const rid = res.locals.requestId as string | undefined;
  res.status(403).json(errorBody(
    ERROR_CODES.ERR_PERM_INSUFFICIENT,
    'PIN verification required to create ticket. Verify your PIN in the POS screen first.',
    rid,
  ));
}

/**
 * Mode-aware gate for POST /pos/checkout-with-ticket.
 *
 * Reads `req.body.mode` to choose the right flag:
 *   checkout      → pos_require_pin_sale
 *   create_ticket → pos_require_pin_ticket
 *
 * Falls through if body is not yet parsed or mode is unknown.
 */
export function requirePosPinByMode(req: Request, res: Response, next: NextFunction): void {
  const db = (req as any).db;
  if (!db) { next(); return; }

  const mode = req.body?.mode;
  const configKey =
    mode === 'checkout' ? 'pos_require_pin_sale' :
    mode === 'create_ticket' ? 'pos_require_pin_ticket' :
    null;

  if (!configKey) { next(); return; }

  const flagOn = getConfigBool(db, configKey);
  if (!flagOn) { next(); return; }

  const userId = currentUserId(req);
  const token = readPinCookie(req);
  if (userId !== null && token && verifyPosPinToken(token, userId)) { next(); return; }

  const rid = res.locals.requestId as string | undefined;
  const msg = mode === 'checkout'
    ? 'PIN verification required to complete sale. Verify your PIN in the POS screen first.'
    : 'PIN verification required to create ticket. Verify your PIN in the POS screen first.';
  res.status(403).json(errorBody(ERROR_CODES.ERR_PERM_INSUFFICIENT, msg, rid));
}
