/**
 * SA1-1: Graceful JWT secret rotation.
 *
 * Problem: before this module, every `jwt.verify(token, config.jwtSecret, ...)`
 * call used exactly ONE secret. Rotating `JWT_SECRET` meant every already-issued
 * access + refresh token failed verification the instant the server restarted,
 * kicking every logged-in user out of the app. Operators therefore avoided
 * rotating JWT secrets even when they had reason to (suspected leak, routine
 * credential hygiene, staff offboarding with access to the deploy shell).
 *
 * Solution: allow two secrets at once.
 *   - JWT_SECRET             → current. Used for ALL new signatures.
 *   - JWT_SECRET_PREVIOUS    → optional. Only used to VERIFY existing tokens
 *                              until they naturally expire.
 *
 * Rotation procedure (see docs/operator-guide.md):
 *   1. JWT_SECRET_PREVIOUS = <old value>
 *   2. JWT_SECRET          = <new 64-byte hex>
 *   3. Restart the server — new logins sign with the new secret, old tokens
 *      keep verifying against the previous one.
 *   4. Wait long enough for access tokens to expire (access TTL is 1h; give
 *      a small safety buffer — 90 minutes is plenty).
 *   5. Remove JWT_SECRET_PREVIOUS and restart again. Old tokens are now
 *      invalid — any session that hasn't refreshed in that window is
 *      forced to re-authenticate (which is the intended behaviour of a
 *      rotation: you want cold sessions to re-prove identity).
 *
 * The same pattern applies to JWT_REFRESH_SECRET / JWT_REFRESH_SECRET_PREVIOUS.
 *
 * Implementation notes:
 *  - Verification always tries the CURRENT secret first. Only on a signature
 *    failure (`JsonWebTokenError`) does it fall back to the previous secret.
 *    Expired/not-before errors are NOT retried with the previous secret —
 *    those errors mean the signature was valid but the token has simply
 *    expired, and trying the previous secret wouldn't change that verdict.
 *  - The previous secret is ONLY used for verification, never for signing.
 *    If operators leave `JWT_SECRET_PREVIOUS` set forever by accident, no
 *    new tokens will ever be signed with it — the rotation does still occur.
 *  - A one-time boot warning fires when either PREVIOUS is set, so operators
 *    get a reminder to remove it after the safety window elapses.
 */
import jwt, { type VerifyOptions, type JwtPayload } from 'jsonwebtoken';
import { config } from '../config.js';

// `jsonwebtoken` is a CommonJS module. Under ESM-native Node (production
// runs `node dist/index.js`, not tsx), CJS default exports are exposed as
// a default namespace object rather than true named exports. Pull
// `JsonWebTokenError` off the default export instead of destructuring in
// the import statement — the named-import form crashed at module load
// time with: `SyntaxError: Named export 'JsonWebTokenError' not found`.
const { JsonWebTokenError } = jwt;

/**
 * Verify a JWT using the current secret, falling back to the previous secret
 * (if configured) on signature failure. Returns the decoded payload or throws
 * the underlying `jsonwebtoken` error, so callers that already wrap
 * `jwt.verify` in try/catch continue to work unchanged.
 *
 * @param token    JWT bearer token
 * @param purpose  which secret pair to use — 'access' or 'refresh'
 * @param options  standard jsonwebtoken verify options (audience, issuer, algs)
 */
export function verifyJwtWithRotation(
  token: string,
  purpose: 'access' | 'refresh',
  options: VerifyOptions,
): JwtPayload | string {
  // SEC-H103: Use the dedicated per-purpose key for signing and primary verify.
  // accessJwtSecret / refreshJwtSecret are either the dedicated env var value
  // or an HKDF derivation from JWT_SECRET. Either way they are the current
  // authoritative secrets going forward.
  const current = purpose === 'access' ? config.accessJwtSecret : config.refreshJwtSecret;
  const previous =
    purpose === 'access' ? config.jwtSecretPrevious : config.jwtRefreshSecretPrevious;

  // SEC-H103 transition-period fallback: tokens signed BEFORE this deployment
  // were signed with the raw JWT_SECRET (not the HKDF-derived or dedicated
  // key). During the transition window (max 30 days — the refresh-token TTL),
  // we accept the raw JWT_SECRET as a second fallback verify key so existing
  // sessions are not invalidated. Remove this fallback once the rollout has
  // been live long enough for all pre-existing refresh tokens to expire.
  //
  // The transition secret is ONLY used for verification (reading existing
  // tokens), never for signing new ones. It is skipped if it is identical to
  // `current` (i.e. ACCESS_JWT_SECRET / REFRESH_JWT_SECRET was not set and the
  // HKDF-derived value happens to equal the raw secret — impossible in practice
  // but guard anyway).
  const rawJwtSecret =
    purpose === 'access' ? config.jwtSecret : config.jwtRefreshSecret;
  const transitionSecret =
    rawJwtSecret !== current ? rawJwtSecret : undefined;

  try {
    return jwt.verify(token, current, options);
  } catch (primaryErr) {
    // Only retry against the previous/transition secrets when the failure is
    // specifically a signature-verification failure (JsonWebTokenError with
    // message like 'invalid signature'). Do NOT retry for TokenExpiredError /
    // NotBeforeError — those errors accepted the signature but rejected on
    // time, and retrying with a different key cannot rescue them.
    if (!(primaryErr instanceof JsonWebTokenError)) throw primaryErr;
    if (primaryErr.name !== 'JsonWebTokenError') throw primaryErr;

    // Try the explicitly rotated-out previous secret first (SA1-1 rotation
    // window), then the pre-H103 transition secret.
    const fallbacks = [previous, transitionSecret].filter((s): s is string => !!s);
    if (fallbacks.length === 0) throw primaryErr;

    let lastErr: unknown = primaryErr;
    for (const fallback of fallbacks) {
      try {
        return jwt.verify(token, fallback, options);
      } catch (err) {
        lastErr = err;
        // If the error is NOT a signature failure, propagate immediately —
        // trying the next secret won't help (token is expired, etc.).
        if (!(err instanceof JsonWebTokenError) || err.name !== 'JsonWebTokenError') {
          throw err;
        }
      }
    }
    throw lastErr;
  }
}

/**
 * One-time boot-time warning for operators when a PREVIOUS secret is still
 * configured. Called from startupValidation.ts.
 */
export function warnIfPreviousSecretsSet(): void {
  const hasAccessPrev = !!config.jwtSecretPrevious;
  const hasRefreshPrev = !!config.jwtRefreshSecretPrevious;
  // SEC-H103: also remind operators if they are still relying on the
  // JWT_SECRET transition fallback (no dedicated ACCESS_JWT_SECRET set).
  const hasTransitionActive =
    !process.env.ACCESS_JWT_SECRET || !process.env.REFRESH_JWT_SECRET;
  if (hasTransitionActive && (process.env.NODE_ENV || 'development') === 'production') {
    // eslint-disable-next-line no-console
    console.warn('\n  [SEC-H103] Transition mode: ACCESS_JWT_SECRET / REFRESH_JWT_SECRET not set.');
    // eslint-disable-next-line no-console
    console.warn('  [SEC-H103] New tokens are signed with HKDF-derived keys; old tokens verify via JWT_SECRET fallback.');
    // eslint-disable-next-line no-console
    console.warn('  [SEC-H103] Set ACCESS_JWT_SECRET and REFRESH_JWT_SECRET, then after 30 days remove the JWT_SECRET transition fallback in utils/jwtSecrets.ts.\n');
  }
  if (!hasAccessPrev && !hasRefreshPrev) return;

  // eslint-disable-next-line no-console
  console.warn('');
  // eslint-disable-next-line no-console
  console.warn('  [JWT Rotation] PREVIOUS secret fallback verifier is ACTIVE:');
  if (hasAccessPrev) {
    // eslint-disable-next-line no-console
    console.warn('    - JWT_SECRET_PREVIOUS is set — old access tokens still verify.');
  }
  if (hasRefreshPrev) {
    // eslint-disable-next-line no-console
    console.warn('    - JWT_REFRESH_SECRET_PREVIOUS is set — old refresh tokens still verify.');
  }
  // eslint-disable-next-line no-console
  console.warn('  [JWT Rotation] Remove PREVIOUS env vars and restart once access-token TTL');
  // eslint-disable-next-line no-console
  console.warn('  [JWT Rotation] has elapsed (default 1h access TTL → wait ~90 minutes).');
  // eslint-disable-next-line no-console
  console.warn('  [JWT Rotation] See docs/operator-guide.md → "JWT Secret Rotation".');
  // eslint-disable-next-line no-console
  console.warn('');
}

/**
 * Generate a fresh 64-byte (128-char hex) JWT secret. Exposed as a utility so
 * the super-admin rotation endpoint and any future CLI tool can share the
 * same generator shape.
 */
export function generateJwtSecret(): string {
  // Lazy require to keep this module import-order-safe in edge cases.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const nodeCrypto = require('crypto') as typeof import('crypto');
  return nodeCrypto.randomBytes(64).toString('hex');
}
