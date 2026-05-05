/**
 * CSRF protection — double-submit cookie pattern.
 *
 * When a portal session is created, we issue a random CSRF token in a
 * non-HttpOnly cookie (so JS can read it). Every state-changing POST request
 * must include the same token in an `X-CSRF-Token` header. Because the
 * SameSite=lax cookie only travels with same-site requests AND cross-site
 * attackers can't read the cookie to copy it into a header, this blocks
 * classic CSRF without requiring server-side token storage.
 *
 * Tokens are compared with a constant-time equality check to avoid leaking
 * length via timing. A dedicated `portalCsrf` cookie is used (separate from
 * the `portalToken` auth cookie) so that the auth cookie stays HttpOnly.
 */
import type { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { config } from '../config.js';

export const CSRF_COOKIE_NAME = 'portalCsrfToken';
export const CSRF_HEADER_NAME = 'x-csrf-token';

/** Generate a fresh random CSRF token (32 bytes → 64 hex chars). */
export function generateCsrfToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

/**
 * Issue a CSRF token cookie on the given response. Called right after a
 * portal session is created so that the portal JS can read it and send it
 * back on every POST.
 */
export function issueCsrfCookie(res: Response, token: string, maxAgeMs: number): void {
  // PROD33: Secure flag only in production. httpOnly is intentionally false —
  // the portal JS needs to read this cookie and echo it in the X-CSRF-Token
  // header (double-submit pattern).
  // SCAN-777: sameSite='strict' so the CSRF token cookie is never sent on
  // cross-site navigations (e.g. portal link clicks from email will arrive
  // without the cookie, which is acceptable — the portal JS re-reads it after
  // the page loads). 'strict' is stronger than 'lax' and removes the residual
  // risk of a CSRF attack via top-level cross-site GET that triggers a state
  // change before the CSRF check runs.
  res.cookie(CSRF_COOKIE_NAME, token, {
    httpOnly: false, // must be readable by JS so frontend can echo it
    secure: config.nodeEnv === 'production',
    sameSite: 'strict',
    maxAge: maxAgeMs,
    path: '/',
  });
}

/** Constant-time equality for two hex strings of any length. */
function safeEquals(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  try {
    return crypto.timingSafeEqual(bufA, bufB);
  } catch {
    return false;
  }
}

/**
 * Express middleware — require a matching CSRF token on state-changing
 * requests. Attach this to every non-GET portal route that mutates state.
 */
export function requireCsrfToken(req: Request, res: Response, next: NextFunction): void {
  const cookieToken = (req.cookies as Record<string, string> | undefined)?.[CSRF_COOKIE_NAME];
  const headerToken = req.header(CSRF_HEADER_NAME);

  if (!cookieToken || !headerToken) {
    res.status(403).json({ success: false, message: 'CSRF token missing' });
    return;
  }

  if (!safeEquals(cookieToken, headerToken)) {
    res.status(403).json({ success: false, message: 'CSRF token invalid' });
    return;
  }

  next();
}
