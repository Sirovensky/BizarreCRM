/**
 * Shared hCaptcha verification helper — SEC-H85 (PUB-013, PUB-014).
 *
 * Used by:
 *   - signup.routes.ts  (tenant signup flow — pre-existing use)
 *   - auth.routes.ts    (login + forgot-password CAPTCHA-on-N-failures gate)
 *
 * NOTE: SEC-H94 agent may also generate this file. Last writer wins —
 * the interface and dev-bypass behaviour are intentionally minimal so
 * both agents converge on the same shape.
 */
import { config } from '../config.js';
import { createLogger } from './logger.js';

const logger = createLogger('hcaptcha');

const HCAPTCHA_VERIFY_URL = 'https://api.hcaptcha.com/siteverify';
const CAPTCHA_VERIFY_TIMEOUT_MS = 8_000;

export interface HCaptchaResult {
  /** true when the token is valid (or bypassed in dev). */
  ok: boolean;
  /** Human-readable reason when ok === false. */
  reason?: string;
}

interface HCaptchaApiResponse {
  success?: boolean;
  challenge_ts?: string;
  hostname?: string;
  'error-codes'?: string[];
}

/**
 * Verify an hCaptcha response token.
 *
 * Behaviour matrix:
 *
 * | NODE_ENV   | HCAPTCHA_SECRET | token                | result          |
 * |------------|-----------------|----------------------|-----------------|
 * | any        | any             | 'dev-captcha-token'* | ok (dev bypass) |
 * | production | absent          | any                  | fail-closed     |
 * | non-prod   | absent          | any                  | ok (fail-open)  |
 * | any        | present         | empty/missing        | fail            |
 * | any        | present         | valid token          | ok              |
 * | any        | present         | invalid token        | fail            |
 *
 * *Dev bypass only fires when NODE_ENV !== 'production'.
 *
 * SEC-H85: In production, fail-closed when HCAPTCHA_SECRET is missing so
 * an unconfigured deployment doesn't silently accept all brute-force attempts
 * once the threshold is crossed. In development, fail-open so local smoke
 * tests work without editing .env.
 */
export async function verifyHcaptcha(
  token: unknown,
  remoteIp: string,
): Promise<HCaptchaResult> {
  const responseToken = typeof token === 'string' ? token.trim() : '';
  const isProd = config.nodeEnv === 'production';

  // Dev bypass — must NOT fire in production.
  if (!isProd && responseToken === 'dev-captcha-token') {
    return { ok: true };
  }

  // Fail-closed in production when secret is not configured.
  if (!config.hCaptchaEnabled) {
    if (isProd) {
      logger.warn('hCaptcha not configured — blocking captcha-required request in production', { remoteIp });
      return { ok: false, reason: 'Captcha service not configured' };
    }
    // Non-production, no secret — fail-open (local dev convenience).
    return { ok: true };
  }

  // Token is required once hCaptcha is enabled.
  if (!responseToken) {
    return { ok: false, reason: 'captcha_token is required' };
  }

  const secret = config.hCaptchaSecret.trim();
  const body = new URLSearchParams({ secret, response: responseToken });
  if (remoteIp && remoteIp !== 'unknown') {
    body.set('remoteip', remoteIp);
  }

  const controller = new AbortController();
  const timeoutHandle = setTimeout(() => controller.abort(), CAPTCHA_VERIFY_TIMEOUT_MS);

  try {
    const response = await fetch(HCAPTCHA_VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
      signal: controller.signal,
    });

    if (!response.ok) {
      logger.warn('hCaptcha API returned non-2xx status', { remoteIp, status: response.status });
      return { ok: false, reason: 'Captcha verification failed' };
    }

    const result = await response.json() as HCaptchaApiResponse;
    if (result.success === true) {
      return { ok: true };
    }

    logger.warn('hCaptcha verification rejected token', {
      remoteIp,
      hostname: result.hostname,
      errors: result['error-codes'] ?? [],
    });
    return { ok: false, reason: 'Captcha verification failed' };
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    logger.warn('hCaptcha verification request threw', { remoteIp, error: errorMsg });
    return { ok: false, reason: 'Captcha verification failed' };
  } finally {
    clearTimeout(timeoutHandle);
  }
}

/**
 * Count recent login_failed audit events attributed to an IP or email
 * within the last hour. Used to decide whether captcha is required.
 *
 * SEC-H85: Both parameters are bound — no string interpolation, no injection
 * risk. The query uses the existing idx_audit_logs_event_created composite
 * index (migration 098) for sub-millisecond reads even on large audit tables.
 *
 * Timing note: this helper reads the audit_logs table synchronously
 * (better-sqlite3). It is called from within the enforceMinDuration window
 * of the login handler, so it does not widen the timing oracle.
 *
 * @param db    better-sqlite3 Database instance (sync).
 * @param ip    Originating IP address.
 * @param email Optionally also count failures that logged this email in details.
 */
export function countRecentLoginFailures(
  db: import('better-sqlite3').Database,
  ip: string,
  email: string,
): number {
  // SEC-H85: Single COUNT(*) query — both predicates are parameterized.
  // JSON_EXTRACT is a SQLite built-in; the value extracted is compared via
  // = so there is no injection surface.  email here is the canonical
  // value derived from the request body, already trimmed/lowercased by
  // the caller (same value stored in details by the audit helper).
  const row = db.prepare<[string, string], { n: number }>(`
    SELECT COUNT(*) AS n
    FROM audit_logs
    WHERE event = 'login_failed'
      AND (ip_address = ? OR JSON_EXTRACT(details, '$.email') = ?)
      AND created_at > datetime('now', '-1 hour')
  `).get(ip, email);

  return row?.n ?? 0;
}

/** Threshold: captcha is required once this many failures are recorded. */
export const CAPTCHA_FAILURE_THRESHOLD = 5;

/**
 * Count recent attempts of a given rate-limit category for a key
 * (IP or combined key) from the rate_limits table.
 *
 * SEC-H85: Used by /forgot-password to avoid a second audit_logs scan.
 * The rate_limits row for 'forgot_password' is updated on every attempt,
 * so its count reflects all attempts within the current window.
 */
export function countRateLimitAttempts(
  db: import('better-sqlite3').Database,
  category: string,
  key: string,
): number {
  const row = db.prepare<[string, string], { count: number }>(
    'SELECT count FROM rate_limits WHERE category = ? AND key = ?'
  ).get(category, key);
  return row?.count ?? 0;
}
