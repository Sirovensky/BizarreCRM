/**
 * requirePosPin — Server-side gate for POS tendering and ticket creation.
 *
 * When `pos_require_pin_sale` or `pos_require_pin_ticket` is enabled in
 * store_config the client is expected to verify the user's PIN via
 * `POST /auth/verify-pin` and pass the resulting session token as the
 * `X-Pos-Pin-Verified` header (value: `1`).  This middleware reads both
 * the store_config flag and the header, and rejects the request with 403
 * when the flag is on but the header is absent or falsy.
 *
 * The actual PIN hash comparison happens in `/auth/verify-pin` (bcrypt,
 * rate-limited); this middleware only enforces that the step was completed.
 *
 * Usage:
 *   router.post('/transaction', requirePosPinSale, asyncHandler(...))
 *   router.post('/checkout-with-ticket', requirePosPinSale, asyncHandler(...))
 *   // For ticket-only creation use requirePosPinTicket.
 */

import { Request, Response, NextFunction } from 'express';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';

function getConfigBool(db: any, key: string): boolean {
  try {
    const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value: string } | undefined;
    return row?.value === '1' || row?.value === 'true';
  } catch {
    return false;
  }
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

  const header = req.headers['x-pos-pin-verified'];
  if (header === '1') { next(); return; }

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

  const header = req.headers['x-pos-pin-verified'];
  if (header === '1') { next(); return; }

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

  const header = req.headers['x-pos-pin-verified'];
  if (header === '1') { next(); return; }

  const rid = res.locals.requestId as string | undefined;
  const msg = mode === 'checkout'
    ? 'PIN verification required to complete sale. Verify your PIN in the POS screen first.'
    : 'PIN verification required to create ticket. Verify your PIN in the POS screen first.';
  res.status(403).json(errorBody(ERROR_CODES.ERR_PERM_INSUFFICIENT, msg, rid));
}
