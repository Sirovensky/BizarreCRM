import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { generateSecret, verifySync } from 'otplib';
import QRCode from 'qrcode';
import { config } from '../config.js';
import { authMiddleware, JWT_SIGN_OPTIONS, JWT_VERIFY_OPTIONS } from '../middleware/auth.js';
import { verifyJwtWithRotation } from '../utils/jwtSecrets.js';
import { audit } from '../utils/audit.js';
import { logTenantAuthEvent } from '../utils/masterAudit.js';
import { checkWindowRate, recordWindowFailure, clearRateLimit, checkLockoutRate, recordLockoutFailure, cleanupExpiredEntries } from '../utils/rateLimiter.js';
import { validateEmail, validateId } from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import { verifyHcaptcha, countRecentLoginFailures, countRateLimitAttempts, CAPTCHA_FAILURE_THRESHOLD } from '../utils/hcaptcha.js';
import type { AsyncDb } from '../db/async-db.js';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { trackInterval } from '../utils/trackInterval.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const logger = createLogger('auth');

// SCAN-646: Safe JSON parse for user.permissions — returns null on any parse/shape error.
function safeParsePermissions(raw: string | null | undefined): Record<string, boolean> | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    // Validate values are boolean (per SCAN-184 policy):
    const safe: Record<string, boolean> = {};
    for (const [k, v] of Object.entries(parsed)) {
      if (typeof v === 'boolean') safe[k] = v;
    }
    return safe;
  } catch { return null; }
}

// SEC (A7): Max concurrent refresh-token sessions per user.
// On login, if user has more than this many active sessions, the oldest
// ones are deleted before issuing the new one.
const MAX_ACTIVE_SESSIONS_PER_USER = 5;

// SEC (A5): Minimum wall-clock time for a login attempt. Equalizes the
// response time for valid vs. invalid users and email-vs-username lookups.
const LOGIN_MIN_DURATION_MS = 250;

// SEC (P2FA8): Number of previous passwords to block when setting a new one.
const PASSWORD_HISTORY_DEPTH = 5;

// SECURITY: Derived key for device trust cookies — separate from JWT signing key
// Prevents a JWT token from being reused as a device trust cookie or vice versa
//
// SCAN-904: Prefer a dedicated DEVICE_TRUST_SECRET env var so the device-trust
// key can be rotated independently of JWT secrets (SEC-H103).
// If unset, falls back to jwtSecret (existing behaviour — no cookie breakage).
// WARNING: changing DEVICE_TRUST_SECRET invalidates all existing device-trust
// cookies; users will need to re-confirm trusted devices on next 2FA login.
const _deviceTrustBase = process.env.DEVICE_TRUST_SECRET || config.jwtSecret;
if (!process.env.DEVICE_TRUST_SECRET) {
  logger.warn('DEVICE_TRUST_SECRET not set; device-trust cookies share key material with JWT — set DEVICE_TRUST_SECRET to a dedicated 64-byte hex for independent rotation (SEC-H103)');
}
const deviceTrustKey = crypto.createHmac('sha256', _deviceTrustBase).update('device-trust-v1').digest('hex');

// AES-256-GCM encryption for TOTP secrets (versioned keys for future rotation)
//
// SEC-H2: TOTP encryption key is derived from JWT_SECRET + superAdminSecret to ensure
// the TOTP key is different from the JWT signing key even if JWT_SECRET alone is compromised.
//
// SEC-M51: v3 switches from raw SHA-256 (`sha256(jwtSecret + ':totp-encryption:v2:' + sa)`)
// to an HKDF-based derivation with explicit salt + info parameters, and binds
// the version tag into AES-GCM as Additional Authenticated Data (AAD).
//
// Why HKDF vs raw SHA-256:
//  - HKDF's two-step extract/expand pattern gives a proper PRF with salt
//    injection and domain separation between IKM / salt / info. Raw SHA-256
//    over a concatenated string offers none of that — salt and context are
//    just byte prefixes an attacker could attempt to manipulate.
//  - Future key rotation is cleaner: bump salt or info and version tag in
//    one place; legacy versions stay decrypt-only via their own entries.
//
// Why AAD on the version tag:
//  - Without AAD, the version prefix on the ciphertext ("v3:iv:tag:data") is
//    just advisory. Binding `v3` as AAD makes the GCM auth tag reject any
//    ciphertext whose version prefix doesn't match the AAD that decrypt
//    expects — closing a theoretical downgrade-by-prefix-rewrite attack.
//  - Legacy v2/v1 values continue to decrypt via their legacy key entries
//    with NO AAD (they were encrypted without it), so this is
//    backward-compatible on read. All new encrypts go through v3.
const V1_LEGACY_KEY: Buffer = crypto
  .createHash('sha256')
  .update(config.jwtSecret + ':totp:v1')
  .digest();
const V2_LEGACY_KEY: Buffer = crypto
  .createHash('sha256')
  .update(config.jwtSecret + ':totp-encryption:v2:' + config.superAdminSecret)
  .digest();

function hkdfKey(
  ikmParts: ReadonlyArray<string>,
  salt: string,
  info: string,
  length = 32,
): Buffer {
  // Node 18+ exposes crypto.hkdfSync returning an ArrayBuffer — wrap for
  // AES-256-GCM which takes a Buffer/Uint8Array.
  const ikm = Buffer.from(ikmParts.join(''));
  const derived = crypto.hkdfSync('sha256', ikm, Buffer.from(salt), Buffer.from(info), length);
  return Buffer.from(derived);
}

const V3_KEY: Buffer = hkdfKey(
  [config.jwtSecret, config.superAdminSecret],
  'bizarre-totp-salt-v3',
  'totp-key-v3',
  32,
);

const ENCRYPTION_KEYS: Record<number, Buffer> = {
  1: V1_LEGACY_KEY,
  2: V2_LEGACY_KEY,
  3: V3_KEY,
};
const CURRENT_KEY_VERSION = 3;

function encryptSecret(plaintext: string): string {
  const key = ENCRYPTION_KEYS[CURRENT_KEY_VERSION];
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  // SEC-M51: bind the version tag as AAD so a ciphertext rewritten to claim
  // a different version would fail auth-tag verification on decrypt.
  cipher.setAAD(Buffer.from(`v${CURRENT_KEY_VERSION}`));
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  // Format: v{version}:{iv}:{tag}:{data}
  return `v${CURRENT_KEY_VERSION}:${iv.toString('hex')}:${tag.toString('hex')}:${encrypted.toString('hex')}`;
}

function decryptSecret(ciphertext: string): string {
  // Legacy unencrypted (plain base32)
  if (!ciphertext.includes(':')) return ciphertext;

  // Legacy v0 format (no version prefix): iv:tag:data
  if (!ciphertext.startsWith('v')) {
    const key = crypto.createHash('sha256').update(config.jwtSecret).digest();
    const [ivHex, tagHex, encHex] = ciphertext.split(':');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
    return decipher.update(Buffer.from(encHex, 'hex')) + decipher.final('utf8');
  }

  // Versioned format: v{n}:{iv}:{tag}:{data}
  const [vStr, ivHex, tagHex, encHex] = ciphertext.split(':');
  const version = parseInt(vStr.slice(1), 10);
  const key = ENCRYPTION_KEYS[version];
  if (!key) throw new Error(`Unknown encryption key version: ${version}`);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  // SEC-M51: v3+ ciphertexts were encrypted with AAD = `v{version}`. v1/v2
  // were not, so only set AAD when reading a ciphertext we know wrote it.
  if (version >= 3) {
    decipher.setAAD(Buffer.from(`v${version}`));
  }
  return decipher.update(Buffer.from(encHex, 'hex')) + decipher.final('utf8');
}

const router = Router();

// ─── 2FA Challenge tokens (in-memory, 5-min TTL) ──────────────────
// SECURITY: Challenge tokens include tenantSlug to prevent cross-tenant 2FA reuse
const challenges = new Map<string, { userId: number; tenantSlug: string | null; expires: number; pendingTotpSecret?: string }>();
const CHALLENGE_TTL = 5 * 60 * 1000;
const MAX_CHALLENGES = 10000;

function createChallenge(userId: number, tenantSlug?: string | null): string {
  // Evict oldest if over limit (DoS protection)
  // SCAN-861: Map preserves insertion order; first key is oldest — O(1) vs O(n log n) sort.
  if (challenges.size >= MAX_CHALLENGES) {
    const oldest = challenges.keys().next().value;
    if (oldest !== undefined) {
      challenges.delete(oldest);
      logger.warn('challenges Map over cap; evicted oldest', { evicted_key_preview: String(oldest).slice(0, 8) });
    }
  }
  const token = crypto.randomBytes(32).toString('hex');
  challenges.set(token, { userId, tenantSlug: tenantSlug || null, expires: Date.now() + CHALLENGE_TTL });
  return token;
}

function validateChallenge(token: string): number | null {
  const entry = challenges.get(token);
  if (!entry || entry.expires < Date.now()) { challenges.delete(token); return null; }
  return entry.userId;
}

// SCAN-881: TTL reaper — purges expired challenge entries on a 5-min interval
// so memory is not held indefinitely between cap-based evictions.
const CHALLENGE_REAPER_INTERVAL_MS = 5 * 60 * 1000;

export function startChallengeReaper(): void {
  trackInterval(() => {
    const now = Date.now();
    for (const [key, record] of challenges) {
      if (record.expires <= now) challenges.delete(key);
    }
  }, CHALLENGE_REAPER_INTERVAL_MS);
}

function consumeChallenge(token: string): number | null {
  const userId = validateChallenge(token);
  if (userId) challenges.delete(token);
  return userId;
}

// Clean expired challenges every minute
trackInterval(() => {
  const now = Date.now();
  for (const [k, v] of challenges) { if (v.expires < now) challenges.delete(k); }
}, 60_000);

// 2FA rate limiting (keyed by tenant:userId to prevent cross-tenant collision)
// SEC-H9: RESOLVED — Rate limiters now use SQLite (migration 069) and persist across restarts.
const TOTP_MAX_ATTEMPTS = 5;
const TOTP_LOCKOUT_MS = 15 * 60 * 1000; // 15 minutes

function totpKey(tenantSlug: string | null | undefined, userId: number): string {
  return `${tenantSlug || 'default'}:${userId}`;
}

function checkTotpRateLimit(db: import('better-sqlite3').Database, tenantSlug: string | null | undefined, userId: number): boolean {
  return checkLockoutRate(db, 'totp', totpKey(tenantSlug, userId), TOTP_MAX_ATTEMPTS);
}

function recordTotpFailure(db: import('better-sqlite3').Database, tenantSlug: string | null | undefined, userId: number): void {
  recordLockoutFailure(db, 'totp', totpKey(tenantSlug, userId), TOTP_LOCKOUT_MS);
}

// ---------------------------------------------------------------------------
// SQLite-backed rate limiter for PIN switch-user
// ---------------------------------------------------------------------------
const PIN_RATE_LIMIT = {
  maxAttempts: 5,
  windowMs: 15 * 60 * 1000, // 15 minutes
};

function checkPinRateLimit(db: import('better-sqlite3').Database, ip: string): boolean {
  return checkWindowRate(db, 'pin', ip, PIN_RATE_LIMIT.maxAttempts, PIN_RATE_LIMIT.windowMs);
}

function recordPinFailure(db: import('better-sqlite3').Database, ip: string): void {
  recordWindowFailure(db, 'pin', ip, PIN_RATE_LIMIT.windowMs);
}

function clearPinFailures(db: import('better-sqlite3').Database, ip: string): void {
  clearRateLimit(db, 'pin', ip);
}

/**
 * SEC (A7 / SEC-H66): Atomically prune oldest sessions and insert the new one
 * in a single transaction so concurrent logins cannot interleave the DELETE
 * and INSERT, which would let session counts exceed the cap or evict the wrong
 * rows.
 *
 * Strategy: inside the transaction, DELETE the oldest (COUNT - 4) non-expired
 * sessions first (leaving at most 4), then INSERT the new one, resulting in at
 * most MAX_ACTIVE_SESSIONS_PER_USER (5) live sessions.  The LIMIT expression
 * is evaluated atomically at DELETE time, so no concurrent read is needed.
 */
async function pruneAndInsertSession(
  adb: AsyncDb,
  userId: number,
  sessionId: string,
  deviceInfo: string,
  expiresAt: string,
): Promise<void> {
  // Keep (MAX - 1) = 4 existing sessions so after the INSERT the total is MAX.
  const keepCount = MAX_ACTIVE_SESSIONS_PER_USER - 1;
  await adb.transaction([
    {
      // Delete the oldest non-expired sessions beyond the keep quota.
      // max(0, COUNT - keepCount) prevents a negative LIMIT, which SQLite
      // would treat as unlimited.  All evaluated inside the same serialised
      // write-lock, so no concurrent login can slip an INSERT between the
      // DELETE and our INSERT below.
      sql: `
        DELETE FROM sessions
        WHERE user_id = ?
          AND id IN (
            SELECT id FROM sessions
            WHERE user_id = ?
              AND expires_at > datetime('now')
            ORDER BY created_at ASC
            LIMIT max(0, (
              SELECT COUNT(*) FROM sessions
              WHERE user_id = ?
                AND expires_at > datetime('now')
            ) - ?)
          )`,
      params: [userId, userId, userId, keepCount],
    },
    {
      sql: "INSERT INTO sessions (id, user_id, device_info, expires_at, last_active) VALUES (?, ?, ?, ?, datetime('now'))",
      params: [sessionId, userId, deviceInfo, expiresAt],
    },
  ]);
}

/**
 * SEC (P2FA8): Reject a new password if it matches any of the user's last N
 * bcrypt hashes stored in password_history.
 */
async function isPasswordReused(adb: AsyncDb, userId: number, plaintext: string): Promise<boolean> {
  const rows = await adb.all<{ password_hash: string }>(
    'SELECT password_hash FROM password_history WHERE user_id = ? ORDER BY created_at DESC LIMIT ?',
    userId, PASSWORD_HISTORY_DEPTH
  );
  // Also block reuse of the current password (before history row is written).
  const current = await adb.get<{ password_hash: string | null }>(
    'SELECT password_hash FROM users WHERE id = ?', userId
  );
  if (current?.password_hash) {
    try { if (bcrypt.compareSync(plaintext, current.password_hash)) return true; } catch { /* ignore */ }
  }
  for (const row of rows) {
    try { if (bcrypt.compareSync(plaintext, row.password_hash)) return true; } catch { /* ignore */ }
  }
  return false;
}

/**
 * SEC (P2FA8): Record a new bcrypt password hash in history and prune to
 * the most recent PASSWORD_HISTORY_DEPTH rows.
 */
async function recordPasswordHistory(adb: AsyncDb, userId: number, passwordHash: string): Promise<void> {
  await adb.run(
    'INSERT INTO password_history (user_id, password_hash) VALUES (?, ?)',
    userId, passwordHash
  );
  // Keep only the most recent PASSWORD_HISTORY_DEPTH rows per user.
  await adb.run(
    `DELETE FROM password_history
       WHERE user_id = ?
         AND id NOT IN (
           SELECT id FROM password_history
             WHERE user_id = ?
             ORDER BY created_at DESC
             LIMIT ?
         )`,
    userId, userId, PASSWORD_HISTORY_DEPTH
  );
}

/**
 * SEC (P2FA5): Build a device-trust fingerprint bound to the UA + client IP hash.
 * This is stored inside the signed trust cookie and re-checked on subsequent
 * logins; a cookie lifted from another device will fail the fingerprint check.
 */
function buildDeviceFingerprint(req: Request): string {
  const ua = (req.headers['user-agent'] || '').slice(0, 200);
  const ip = req.ip || req.socket?.remoteAddress || '';
  return crypto.createHash('sha256').update(`${ua}|${ip}`).digest('hex');
}

/**
 * SEC (A5): Ensure a request takes at least LOGIN_MIN_DURATION_MS to respond,
 * equalizing timing across success / wrong-password / user-not-found paths.
 */
async function enforceMinDuration(startNs: bigint, minMs: number): Promise<void> {
  const elapsedMs = Number(process.hrtime.bigint() - startNs) / 1_000_000;
  const waitMs = minMs - elapsedMs;
  if (waitMs > 0) await new Promise(resolve => setTimeout(resolve, waitMs));
}

// Helper: issue JWT tokens after successful auth
async function issueTokens(adb: AsyncDb, user: any, req: Request, res: Response, options?: { trustDevice?: boolean }): Promise<{ accessToken: string; refreshToken: string; user: any }> {
  const trust = options?.trustDevice === true;
  const refreshDays = trust ? 90 : 30;
  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + refreshDays * 24 * 60 * 60 * 1000).toISOString();

  // SEC (A7 / SEC-H66): Prune + insert atomically so concurrent logins
  // cannot race between the DELETE and INSERT.
  await pruneAndInsertSession(adb, user.id, sessionId, req.headers['user-agent'] || 'unknown', expiresAt);

  const tenantSlug = (req as any).tenantSlug || null;
  // SEC (A6/A10): Explicit HS256 + iss + aud on every sign call.
  // SEC-L34: `jti` uniquely identifies each issued token so future revocation lists
  // (see sessions table) can target a specific token rather than an entire session.
  // SEC-H103: sign with the dedicated per-purpose secret, not the shared JWT_SECRET.
  // SEC (SCAN-613): Explicit type:'access' so the auth middleware strict check
  // can reject any token without the field (refresh, scoped, super-admin, etc.).
  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role, tenantSlug, type: 'access', jti: crypto.randomUUID() },
    config.accessJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '1h' }
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh', tenantSlug, jti: crypto.randomUUID() },
    config.refreshJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: `${refreshDays}d` }
  );

  // SEC-H17: SameSite=Strict — refresh tokens are first-party only. Lax
  // would allow cross-site top-level navigations to carry the cookie, giving
  // attackers a window for CSRF on sensitive cookie-bound flows. Strict has
  // no functional downside here because the SPA and API share an origin.
  // SCAN-905: Use req.secure (which honours trust-proxy / X-Forwarded-Proto)
  // OR fall back to nodeEnv === 'production'. This ensures staging environments
  // running HTTPS with nodeEnv != 'production' still set the Secure flag.
  // NOTE: for req.secure to reflect HTTPS behind a reverse proxy, ensure
  // `app.set('trust proxy', 'loopback')` (or similar) is enabled in index.ts.
  const isSecureConnection = req.secure || config.nodeEnv === 'production';
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: isSecureConnection,
    sameSite: 'strict',
    maxAge: refreshDays * 24 * 60 * 60 * 1000,
    path: '/',
  });

  // SEC-H89: CSRF double-submit cookie for POST /auth/refresh.
  // The refreshToken cookie is httpOnly so JS cannot read it — but a cross-origin
  // attacker can still trigger a cookie-carrying POST (CSRF). The defence is a
  // second cookie, csrf_token, which is NOT httpOnly so the SPA's JS can read it
  // and forward it as the X-CSRF-Token request header. The refresh handler then
  // compares the header value against the cookie value (double-submit pattern).
  // SameSite=Strict ensures browsers won't send this cookie on cross-site requests
  // at all (defence-in-depth), but the header check is the primary enforcement
  // that covers any Lax-fallback or non-browser client behaviour.
  const csrfToken = crypto.randomBytes(24).toString('base64url');
  res.cookie('csrf_token', csrfToken, {
    httpOnly: false,                               // must be readable by JS
    secure: isSecureConnection,
    sameSite: 'strict',
    maxAge: refreshDays * 24 * 60 * 60 * 1000,    // lifetime matches refreshToken
    path: '/',
  });

  // Strict allowlist — never leak internal fields
  const safeUser = {
    id: user.id,
    username: user.username,
    email: user.email,
    first_name: user.first_name,
    last_name: user.last_name,
    role: user.role,
    avatar_url: user.avatar_url || null,
    permissions: safeParsePermissions(user.permissions),
  };
  return { accessToken, refreshToken, user: safeUser };
}

// POST /login — Step 1: password check, returns challenge token
// SQLite-backed login rate limiting (IP-based, same limits as PIN)
function checkLoginRateLimit(db: import('better-sqlite3').Database, ip: string): boolean {
  return checkWindowRate(db, 'login_ip', ip, PIN_RATE_LIMIT.maxAttempts, PIN_RATE_LIMIT.windowMs);
}

function recordLoginFailure(db: import('better-sqlite3').Database, ip: string): void {
  recordWindowFailure(db, 'login_ip', ip, PIN_RATE_LIMIT.windowMs);
}

// Username-based login rate limiting (prevents credential stuffing against a single account)
// Keyed by tenantSlug:username to prevent cross-tenant collision
const USER_LOGIN_RATE_LIMIT = {
  maxAttempts: 10,
  windowMs: 30 * 60 * 1000, // 30 minutes
};

function checkUserLoginRateLimit(db: import('better-sqlite3').Database, tenantSlug: string | null | undefined, username: string): boolean {
  const key = `${tenantSlug || 'default'}:${username}`;
  return checkWindowRate(db, 'login_user', key, USER_LOGIN_RATE_LIMIT.maxAttempts, USER_LOGIN_RATE_LIMIT.windowMs);
}

function recordUserLoginFailure(db: import('better-sqlite3').Database, tenantSlug: string | null | undefined, username: string): void {
  const key = `${tenantSlug || 'default'}:${username}`;
  recordWindowFailure(db, 'login_user', key, USER_LOGIN_RATE_LIMIT.windowMs);
}

// GET /setup-status — Check if this shop needs first-time setup (no users exist).
// Also reports whether the server is running in multi-tenant mode so the web
// frontend can decide whether the bare hostname should show the SaaS landing
// page or go straight to the single-tenant first-run wizard.
router.get('/setup-status', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const row = await adb.get<{ c: number }>('SELECT COUNT(*) as c FROM users WHERE is_active = 1');
  res.json({
    success: true,
    data: {
      needsSetup: row!.c === 0,
      isMultiTenant: config.multiTenant === true,
    },
  });
}));

// POST /setup — First-time shop setup: create the initial admin account.
//
// Two distinct flows:
//   1. MULTI-TENANT (config.multiTenant === true): the provisioning flow
//      mints a one-time setup token, stored as sha256 in the setup_tokens
//      table. The request MUST include `setup_token` matching a row with
//      consumed_at IS NULL and expires_at > now(). The token is consumed
//      inside the same transaction as the user insert.
//   2. SINGLE-TENANT (config.multiTenant !== true): no provisioning flow
//      exists — the shop owner clones the repo and runs `npm start`. The
//      bare `no active users exist` check IS the gate. No setup token is
//      required, but the handler also writes store_config defaults so the
//      dashboard isn't a pile of $0 KPIs after first login.
//
// Both flows require:
//   - At most 3 attempts per hour per IP (rate_limits table).
//   - Username ≥ 3 chars, password 8-128 chars.
//   - A valid email (the single-tenant path mandates it; the multi-tenant
//     path falls back to `${username}@shop.local` for legacy signups).
router.post('/setup', asyncHandler(async (req: Request, res: Response) => {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const db = req.db;
  // Setup rate limiting (3 attempts per hour per IP) — SQLite-backed
  if (!checkWindowRate(db, 'setup', ip, 3, 3600_000)) {
    res.status(429).json({ success: false, message: 'Too many setup attempts. Try again later.' });
    return;
  }
  recordWindowFailure(db, 'setup', ip, 3600_000);
  const adb = req.asyncDb;
  // Only allow if no active users exist
  const countRow = await adb.get<{ c: number }>('SELECT COUNT(*) as c FROM users WHERE is_active = 1');
  if (countRow!.c > 0) {
    res.status(400).json({ success: false, code: ERROR_CODES.ERR_AUTH_ALREADY_SETUP, message: 'Shop is already set up' });
    return;
  }

  const {
    username,
    password,
    email,
    first_name,
    last_name,
    store_name,
    setup_token,
  } = req.body;

  const isSingleTenant = config.multiTenant !== true;

  // Multi-tenant mode MUST validate the setup token. Single-tenant mode has
  // no provisioning flow, so the "no users exist" check is the only gate.
  let tokenRow: { id: number; expires_at: string; consumed_at: string | null } | undefined;
  if (!isSingleTenant) {
    if (!setup_token || typeof setup_token !== 'string' || setup_token.length === 0) {
      res.status(403).json({ success: false, code: ERROR_CODES.ERR_AUTH_SETUP_LINK_INVALID, message: 'Invalid setup link. Request a new one from your administrator.' });
      return;
    }
    const suppliedTokenHash = crypto.createHash('sha256').update(setup_token).digest('hex');
    tokenRow = await adb.get<{ id: number; expires_at: string; consumed_at: string | null }>(
      "SELECT id, expires_at, consumed_at FROM setup_tokens WHERE token_hash = ?",
      suppliedTokenHash
    );
    if (!tokenRow || tokenRow.consumed_at || new Date(tokenRow.expires_at) <= new Date()) {
      res.status(403).json({ success: false, code: ERROR_CODES.ERR_AUTH_SETUP_LINK_INVALID, message: 'Invalid or expired setup link. Request a new one from your administrator.' });
      return;
    }
  }

  if (!username || typeof username !== 'string' || username.trim().length < 3) {
    res.status(400).json({ success: false, message: 'Username must be at least 3 characters' });
    return;
  }
  if (!password || typeof password !== 'string' || password.length < 8 || password.length > 128) {
    res.status(400).json({ success: false, message: 'Password must be 8 to 128 characters' });
    return;
  }

  // Single-tenant requires a real email; multi-tenant keeps the legacy fallback.
  let validatedEmail: string | null = null;
  try {
    validatedEmail = validateEmail(email, 'email', isSingleTenant);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Invalid email';
    res.status(400).json({ success: false, message });
    return;
  }
  const resolvedEmail = validatedEmail || `${username.trim()}@shop.local`;

  // First / last name: optional for multi-tenant (historic), required for
  // single-tenant first-run (matches the user's product intent).
  const rawFirst = typeof first_name === 'string' ? first_name.trim() : '';
  const rawLast = typeof last_name === 'string' ? last_name.trim() : '';
  if (isSingleTenant && (!rawFirst || !rawLast)) {
    res.status(400).json({ success: false, message: 'First name and last name are required' });
    return;
  }
  if (rawFirst.length > 100 || rawLast.length > 100) {
    res.status(400).json({ success: false, message: 'Name fields must be 100 characters or less' });
    return;
  }

  const trimmedUsername = username.trim();
  const hash = bcrypt.hashSync(password, 12);
  const pinHash = bcrypt.hashSync('1234', 12);

  // Consume the setup token (multi-tenant only) and create the admin user
  // atomically so a race between two requests cannot both succeed against
  // the same token, and a crash between insert and consume cannot leave a
  // usable token. Single-tenant just inserts the user.
  const operations: Array<{ sql: string; params: unknown[] }> = [
    {
      sql: `INSERT INTO users (username, email, password_hash, password_set, pin, first_name, last_name, role, is_active, created_at, updated_at)
            VALUES (?, ?, ?, 1, ?, ?, ?, 'admin', 1, datetime('now'), datetime('now'))`,
      params: [trimmedUsername, resolvedEmail, hash, pinHash, rawFirst, rawLast],
    },
  ];
  if (!isSingleTenant && tokenRow) {
    operations.push({
      // Belt-and-braces: only flip consumed_at if it is still NULL. The
      // UNIQUE index on token_hash plus this check means two concurrent
      // requests can never both succeed.
      sql: "UPDATE setup_tokens SET consumed_at = datetime('now') WHERE id = ? AND consumed_at IS NULL",
      params: [tokenRow.id],
    });
  }
  // Single-tenant first-run: seed store_name + setup_completed flag so the
  // wizard gate in ProtectedRoute transitions cleanly to the main app.
  if (isSingleTenant) {
    const trimmedStore = typeof store_name === 'string' ? store_name.trim().slice(0, 200) : '';
    if (trimmedStore) {
      operations.push({
        sql: "INSERT INTO store_config (key, value) VALUES ('store_name', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params: [trimmedStore],
      });
    }
    operations.push({
      sql: "INSERT INTO store_config (key, value) VALUES ('setup_completed', '1') ON CONFLICT(key) DO UPDATE SET value = '1'",
      params: [],
    });
  }

  try {
    await adb.transaction(operations);
  } catch (err) {
    logger.error('Setup transaction failed', {
      error: err instanceof Error ? err.message : String(err),
      mode: isSingleTenant ? 'single' : 'multi',
    });
    res.status(500).json({ success: false, message: 'Failed to create admin account. Please try again.' });
    return;
  }

  // Defence-in-depth: purge any legacy plaintext copies left over from older
  // provisioning runs. No-op on fresh tenants.
  await adb.run("DELETE FROM store_config WHERE key IN ('setup_token', 'setup_token_expires')");

  audit(db, 'setup_completed', null, ip, { username: trimmedUsername, mode: isSingleTenant ? 'single' : 'multi' });

  res.json({ success: true, data: { message: 'Admin account created. You can now log in.' } });
}));

router.post('/login', asyncHandler(async (req: Request, res: Response) => {
  // SEC (A5): Anchor min response time at the start of the handler.
  const startNs = process.hrtime.bigint();
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkLoginRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many login attempts. Try again in 15 minutes.' });
    return;
  }

  const { username, password } = req.body;
  if (!username) {
    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    res.status(400).json({ success: false, message: 'Username required' });
    return;
  }

  // Check username-based rate limit (prevents credential stuffing against a single account)
  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkUserLoginRateLimit(db, tenantSlug, username)) {
    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    res.status(429).json({ success: false, message: 'Too many failed attempts for this account. Try again in 30 minutes.' });
    return;
  }

  // Accept either username OR email as the login identifier. Signup derives
  // username from the email prefix (e.g. admin@shop.com -> 'admin'), which
  // is non-obvious to users typing 'admin@shop.com' at the login form. Now
  // both inputs resolve the same account. Parameterized, so no injection risk.
  // If a user's username happens to collide with another user's email, the
  // first match wins -- username column has UNIQUE, so it's deterministic.
  const user = await adb.get<any>(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled, password_set FROM users WHERE (username = ? OR email = ?) AND is_active = 1',
    username,
    username
  );

  // SEC (A5): Constant-time password comparison. Always run bcrypt against a
  // dummy hash if the user is missing to prevent timing oracle. Additionally,
  // use crypto.timingSafeEqual on the resulting booleans expressed as bytes
  // so even the comparison itself can't leak via branch timing.
  // $2b$12$ is a valid bcrypt hash prefix with 12 rounds — matches real hash cost.
  const DUMMY_HASH = '$2b$12$LJ3m4ys3Lhmd0tSwUaGgmeoS89CINnom5eSvnfmEFYKaSwVKbHlrS';
  const hashToCheck = user?.password_hash || DUMMY_HASH;
  const bcryptResult = password ? bcrypt.compareSync(password, hashToCheck) : false;
  // Always run timingSafeEqual unconditionally so the comparison itself
  // doesn't leak whether a user exists. If no user exists we force the
  // "actual" byte to 0 regardless of bcrypt's result.
  const userExistsByte = user ? 1 : 0;
  const expectedBuf = Buffer.from([1]);
  const actualBuf = Buffer.from([(bcryptResult ? 1 : 0) & userExistsByte]);
  const passwordValid = crypto.timingSafeEqual(expectedBuf, actualBuf);

  if (!user) {
    recordLoginFailure(db, ip);
    // SEC-L43: Do not persist attacker-supplied username on unknown-user path.
    // Record only the intent + IP so audit logs can't be polluted with
    // arbitrary user-controlled strings.
    recordUserLoginFailure(db, tenantSlug, '<unknown-user>');
    audit(db, 'login_failed', null, ip, { username: '<unknown-user>', reason: 'user_not_found' });
    logTenantAuthEvent('login_failed', req, null, '<unknown-user>', { reason: 'user_not_found' });

    // SEC-H85: captcha gate — checked on BOTH failure paths with identical
    // response shape so the captcha_required flag cannot reveal account existence.
    // countRecentLoginFailures uses the same 'login_failed' rows just written.
    const failCount = countRecentLoginFailures(db, ip, '');
    if (failCount >= CAPTCHA_FAILURE_THRESHOLD) {
      const captchaResult = await verifyHcaptcha(req.body?.captcha_token, ip);
      if (!captchaResult.ok) {
        await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
        res.status(429).json({
          success: false,
          message: 'Too many attempts, captcha required',
          captcha_required: true,
        });
        return;
      }
    }

    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    // SEC (E2): Generic error message — do not distinguish "user not found"
    // from "wrong password" in the response.
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  // User hasn't set a password yet (created by admin without one)
  if (!user.password_set || !user.password_hash) {
    const challengeToken = createChallenge(user.id, tenantSlug);
    audit(db, 'login_password_setup', user.id, ip, { username });
    logTenantAuthEvent('login_password_setup', req, user.id, username, {});
    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    res.json({
      success: true,
      data: { challengeToken, requiresPasswordSetup: true },
    });
    return;
  }

  if (!passwordValid) {
    recordLoginFailure(db, ip);
    // SEC-L43: Use the resolved user's canonical username rather than the
    // attacker-supplied input (could be an email or a mixed-case variant).
    recordUserLoginFailure(db, tenantSlug, user.username);
    audit(db, 'login_failed', user.id, ip, { username: user.username, reason: 'bad_password' });
    logTenantAuthEvent('login_failed', req, user.id, user.username, { reason: 'bad_password' });

    // SEC-H85: captcha gate — mirrors the user_not_found path exactly so the
    // captcha_required flag is indistinguishable between the two failure kinds.
    // We pass user.email so audit rows carrying $.email also count toward the
    // per-email threshold (attacker using the email as the login identifier).
    const failCount = countRecentLoginFailures(db, ip, user.email ?? '');
    if (failCount >= CAPTCHA_FAILURE_THRESHOLD) {
      const captchaResult = await verifyHcaptcha(req.body?.captcha_token, ip);
      if (!captchaResult.ok) {
        await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
        res.status(429).json({
          success: false,
          message: 'Too many attempts, captcha required',
          captcha_required: true,
        });
        return;
      }
    }

    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  // SEC (P2FA5): Evaluate whether 2FA is required BEFORE we consult the
  // device-trust cookie. A stolen trust cookie must not be able to skip
  // the 2FA challenge if 2FA isn't even required in the first place, AND
  // if 2FA is required we further validate a fingerprint bound to UA+IP.
  const requires2fa = !!user.totp_enabled;

  if (requires2fa) {
    const deviceTrustCookie = req.cookies?.deviceTrust;
    if (deviceTrustCookie) {
      try {
        // Device-trust tokens are bound to userId + fingerprint. If the
        // fingerprint changes (cookie stolen to a different device/network),
        // the trust cookie is rejected and the user is forced through 2FA.
        const payload = jwt.verify(deviceTrustCookie, deviceTrustKey, JWT_VERIFY_OPTIONS) as any;
        const expectedFp = buildDeviceFingerprint(req);
        const fingerprintValid =
          typeof payload.fp === 'string' &&
          payload.fp.length === expectedFp.length &&
          crypto.timingSafeEqual(Buffer.from(payload.fp), Buffer.from(expectedFp));
        if (payload.type === 'device_trust' && payload.userId === user.id && fingerprintValid) {
          // Trusted device — issue tokens directly, skip 2FA
          audit(db, 'login_success', user.id, ip, { method: '2fa_trusted_device' });
          logTenantAuthEvent('login_success', req, user.id, user.username, { method: '2fa_trusted_device' });
          const tokens = await issueTokens(adb, user, req, res, { trustDevice: true });
          await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
          res.json({ success: true, data: { ...tokens, trustedDevice: true } });
          return;
        }
        // Valid signature but mismatched binding — clear the cookie so a
        // future login can't reuse it.
        res.clearCookie('deviceTrust', { path: '/' });
      } catch {
        // Invalid/expired trust cookie — fall through to normal 2FA flow
        res.clearCookie('deviceTrust', { path: '/' });
      }
    }
  }

  const challengeToken = createChallenge(user.id, tenantSlug);

  await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
  res.json({
    success: true,
    data: {
      challengeToken,
      totpEnabled: !!user.totp_enabled,
      requires2faSetup: !user.totp_enabled,
      requiresPasswordSetup: false,
    },
  });
}));

// POST /login/set-password — First-time password setup
router.post('/login/set-password', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const { challengeToken, password } = req.body;
  const userId = consumeChallenge(challengeToken); // Consume immediately
  if (!userId) { res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_CHALLENGE_EXPIRED, message: 'Challenge expired' }); return; }

  if (!password || password.length < 8 || password.length > 128) {
    res.status(400).json({ success: false, message: 'Password must be 8 to 128 characters' });
    return;
  }

  // SEC-H9: Verify the account is still in the "no password yet" state BEFORE
  // overwriting. Even with challenge tokens consumed on use, a race between a
  // legitimate /login/set-password flow and a /login flow from the same user
  // could let a challenge issued during the first-run window overwrite a
  // password that was already set on another tab. Guard the UPDATE with an
  // explicit `AND password_set = 0` so a consumed challenge cannot silently
  // replace an already-set password.
  const hash = bcrypt.hashSync(password, 12);
  const updateResult = await adb.run(
    "UPDATE users SET password_hash = ?, password_set = 1, updated_at = datetime('now') WHERE id = ? AND password_set = 0",
    hash, userId
  );
  if (updateResult.changes === 0) {
    // Either the user went away or password_set has already flipped to 1.
    // Return a generic 401 to avoid leaking which condition tripped.
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  // SECURITY: Invalidate all existing sessions for this user
  await adb.run('DELETE FROM sessions WHERE user_id = ?', userId);

  // Issue NEW challenge for 2FA setup step
  const newChallenge = createChallenge(userId, (req as any).tenantSlug);
  audit(db, 'password_set', userId, req.ip || 'unknown', { first_login: true });
  logTenantAuthEvent('password_set', req, userId, null, { first_login: true });
  res.json({ success: true, data: { challengeToken: newChallenge, message: 'Password set. Now set up 2FA.' } });
}));

// POST /login/2fa-setup — Get QR code for first-time setup
router.post('/login/2fa-setup', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const { challengeToken } = req.body;
  const pendingSecret = challenges.get(challengeToken)?.pendingTotpSecret;
  const userId = consumeChallenge(challengeToken); // Consume immediately
  if (!userId) { res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_CHALLENGE_EXPIRED, message: 'Challenge expired' }); return; }

  const user = await adb.get<any>('SELECT id, username, email FROM users WHERE id = ?', userId);
  // SEC (E2): Generic message + 401 to avoid account enumeration.
  if (!user) { res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' }); return; }

  // Generate new TOTP secret
  const secret = generateSecret();
  const account = encodeURIComponent(user.email || user.username);
  const otpauth = `otpauth://totp/Bizarre%20CRM:${account}?secret=${secret}&issuer=Bizarre%20CRM`;

  try {
    const qrDataUrl = await QRCode.toDataURL(otpauth);
    // Issue new challenge with pending TOTP secret
    const newChallenge = createChallenge(userId, (req as any).tenantSlug);
    const newEntry = challenges.get(newChallenge);
    if (newEntry) newEntry.pendingTotpSecret = secret;

    res.json({ success: true, data: { qr: qrDataUrl, secret, manualEntry: secret, challengeToken: newChallenge } });
  } catch {
    // Issue recovery challenge so user can retry without re-entering password
    const recoveryChallenge = createChallenge(userId, (req as any).tenantSlug);
    const recoveryEntry = challenges.get(recoveryChallenge);
    if (recoveryEntry) recoveryEntry.pendingTotpSecret = secret;
    res.status(500).json({ success: false, message: 'Failed to generate QR code. Please try again.', data: { challengeToken: recoveryChallenge } });
  }
}));

// POST /login/2fa-verify — Verify TOTP code and complete login
router.post('/login/2fa-verify', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  // IP-based rate limit (reuse login rate limiter)
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkLoginRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Try again later.' });
    return;
  }

  const { challengeToken, code, trustDevice } = req.body;

  // Validate TOTP code format: exactly 6 digits
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) {
    res.status(400).json({ success: false, message: 'Code must be 6 digits' });
    return;
  }

  // Get pending secret from challenge map (for first-time setup) before consuming.
  // Validate challenge existence WITHOUT consuming it so that if the TOTP rate
  // limiter fires we can still issue a fresh challengeToken to the client.
  const challengeEntry = challenges.get(challengeToken);
  const pendingSecret = challengeEntry?.pendingTotpSecret;

  const userId = validateChallenge(challengeToken);
  if (!userId) { res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_CHALLENGE_EXPIRED, message: 'Challenge expired' }); return; }

  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkTotpRateLimit(db, tenantSlug, userId)) {
    // Do NOT consume the challenge — re-issue a new one so the client can show
    // the correct "try again later" state without being permanently stranded.
    const retryChallenge = createChallenge(userId, tenantSlug);
    if (pendingSecret) {
      const nc = challenges.get(retryChallenge);
      if (nc) nc.pendingTotpSecret = pendingSecret;
    }
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.', data: { challengeToken: retryChallenge } });
    return;
  }

  // Safe to consume now that all pre-checks have passed.
  consumeChallenge(challengeToken);

  const user = await adb.get<any>(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled FROM users WHERE id = ? AND is_active = 1',
    userId
  );

  // Use pending secret (first-time setup) or existing encrypted secret from DB
  const secret = pendingSecret || (user.totp_secret ? decryptSecret(user.totp_secret) : null);
  if (!user || !secret) {
    res.status(401).json({ success: false, message: 'TOTP not configured' });
    return;
  }

  // verifySync returns boolean directly (not an object with .valid)
  const isValid = verifySync({ token: code, secret });
  if (!isValid) {
    recordTotpFailure(db, tenantSlug, userId);
    const newChallenge = createChallenge(userId, tenantSlug);
    // Preserve pending secret for retry
    if (pendingSecret) {
      const nc = challenges.get(newChallenge);
      if (nc) nc.pendingTotpSecret = pendingSecret;
    }
    res.status(401).json({ success: false, message: 'Invalid code', data: { challengeToken: newChallenge } });
    return;
  }

  // First-time setup: persist encrypted secret, generate backup codes
  let backupCodes: string[] | null = null;
  if (!user.totp_enabled || pendingSecret) {
    // SEC-L44: backup codes switched from hex (0-9a-f) to Crockford base32
    // (0-9 A-Z excluding I, L, O, U) so users typing them off paper don't
    // confuse 0/O, 1/L/I, etc. Alphabet has 32 symbols so each char
    // carries 5 bits vs hex's 4 — a 16-char Crockford code carries
    // 80 bits of entropy, down from the hex 128 but still well above
    // NIST's 10^-6 guess-rate bar for 8 codes × short lifetime. Verify
    // path compares plaintext against stored bcrypt hash without
    // caring what alphabet was used, so existing enrolled users who
    // still hold hex codes are unaffected.
    const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    const genCrockford = (len: number): string => {
      const bytes = crypto.randomBytes(len);
      let out = '';
      for (let i = 0; i < len; i++) {
        out += CROCKFORD[bytes[i] & 0x1f]; // mask top 3 bits → 0..31
      }
      // Format as XXXX-XXXX-XXXX-XXXX for readability on paper.
      return out.match(/.{1,4}/g)?.join('-') || out;
    };
    const plainCodes = Array.from({ length: 8 }, () => genCrockford(16));
    const hashedCodes = plainCodes.map(c => bcrypt.hashSync(c, 12));
    await adb.run('UPDATE users SET totp_secret = ?, totp_enabled = 1, backup_codes = ? WHERE id = ?',
      encryptSecret(secret), JSON.stringify(hashedCodes), userId);
    backupCodes = plainCodes; // Return plain codes ONCE to the user
  }

  // Clear rate limit on success
  clearRateLimit(db, 'totp', totpKey(tenantSlug, userId));
  // SEC-H10: Also clear the password-stage IP and user-login counters. The
  // /login endpoint records failures keyed by both IP and (tenant:username),
  // and a full password-then-2FA success proves this isn't an attack — leaving
  // the counters in place would let a bad actor DoS a legitimate user into
  // the 30-minute username lockout by spraying bad passwords from any IP.
  clearRateLimit(db, 'login_ip', req.ip || req.socket.remoteAddress || 'unknown');
  clearRateLimit(db, 'login_user', `${tenantSlug || 'default'}:${user.username}`);
  audit(db, 'login_success', userId, req.ip || 'unknown', { method: backupCodes ? '2fa_setup' : '2fa_verify' });
  logTenantAuthEvent('login_success', req, userId, user.username, { method: backupCodes ? '2fa_setup' : '2fa_verify' });

  // Set device trust cookie if requested — allows skipping 2FA on future logins.
  // SEC (P2FA5): The cookie is bound to a fingerprint (UA + IP hash) that the
  // login endpoint re-checks, so a cookie lifted from another device will fail.
  if (trustDevice) {
    const fingerprint = buildDeviceFingerprint(req);
    const deviceToken = jwt.sign(
      { userId: user.id, type: 'device_trust', fp: fingerprint },
      deviceTrustKey,
      { ...JWT_SIGN_OPTIONS, expiresIn: '90d' }
    );
    // SEC-H17: SameSite=Strict to match refreshToken — device trust is first-party only.
    // SCAN-905: req.secure honours trust-proxy / X-Forwarded-Proto; production fallback
    // ensures the flag is set even if req.secure is somehow false in prod.
    res.cookie('deviceTrust', deviceToken, {
      httpOnly: true,
      secure: req.secure || config.nodeEnv === 'production',
      sameSite: 'strict',
      maxAge: 90 * 24 * 60 * 60 * 1000,
      path: '/',
    });
  }

  const tokens = await issueTokens(adb, user, req, res, { trustDevice: !!trustDevice });
  res.json({ success: true, data: { ...tokens, backupCodes } });
}));

// POST /login/2fa-backup — Use a backup code instead of TOTP
router.post('/login/2fa-backup', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  // SEC-H5: IP-keyed rate limit BEFORE the user-keyed TOTP limiter. Without this,
  // an attacker who enumerated challenge tokens could spray backup-code guesses
  // across many users from a single IP without tripping any limiter — the
  // user-keyed limiter only fires after matching a specific userId.
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkLoginRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Try again later.' });
    return;
  }

  const { challengeToken, code } = req.body;
  const userId = consumeChallenge(challengeToken);
  if (!userId) { res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_CHALLENGE_EXPIRED, message: 'Challenge expired' }); return; }

  // Share TOTP rate limiter
  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkTotpRateLimit(db, tenantSlug, userId)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.' });
    return;
  }

  const user = await adb.get<any>(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled, backup_codes FROM users WHERE id = ? AND is_active = 1',
    userId
  );

  if (!user || !user.backup_codes) {
    res.status(401).json({ success: false, message: 'No backup codes available' });
    return;
  }

  // SEC-H73: Atomic consume — retry up to 3 times so a concurrent POST that
  // removes the element at our matchIdx before our UPDATE lands is handled
  // gracefully. Inside the transaction the WHERE json_extract(...) = ? guard
  // ensures the UPDATE is a no-op (changes === 0) if the element was already
  // removed by a racing write. We then re-SELECT and re-search.
  const MAX_CONSUME_ATTEMPTS = 3;
  let remainingAfterConsume = 0;
  let consumed = false;

  let currentBackupCodes: string = user.backup_codes;

  for (let attempt = 0; attempt < MAX_CONSUME_ATTEMPTS; attempt++) {
    // SCAN-645: Guard against malformed backup_codes in the DB.
    let hashedCodes: string[];
    try {
      const parsed = JSON.parse(currentBackupCodes);
      if (!Array.isArray(parsed)) {
        res.json({ valid: false }); return;
      }
      hashedCodes = parsed as string[];
    } catch {
      res.json({ valid: false }); return;
    }
    const matchIdx = hashedCodes.findIndex(h => bcrypt.compareSync(code, h));

    if (matchIdx === -1) {
      // Code not found in this snapshot — break to the "invalid" branch below.
      break;
    }

    // Atomic conditional UPDATE: JSON_REMOVE only executes if the element at
    // $[matchIdx] still equals the matched hash (i.e. no concurrent consume
    // has shifted the array since we read it).
    const updateResult = await adb.run(
      `UPDATE users SET backup_codes = JSON_REMOVE(backup_codes, '$[${matchIdx}]')
       WHERE id = ? AND json_extract(backup_codes, '$[${matchIdx}]') = ?`,
      userId, hashedCodes[matchIdx]
    );

    if (updateResult.changes > 0) {
      // Success — code was consumed atomically.
      remainingAfterConsume = hashedCodes.length - 1;
      consumed = true;
      break;
    }

    // changes === 0: a concurrent POST consumed the element before us.
    // Re-read the current row and retry.
    const freshUser = await adb.get<{ backup_codes: string }>(
      'SELECT backup_codes FROM users WHERE id = ? AND is_active = 1',
      userId
    );
    if (!freshUser?.backup_codes) break;
    currentBackupCodes = freshUser.backup_codes;
  }

  if (!consumed) {
    recordTotpFailure(db, tenantSlug, userId);
    // SEC-H5: Advance the IP counter on failure so the guard added at the top
    // actually trips after enough attempts from the same source.
    recordLoginFailure(db, ip);
    const newChallenge = createChallenge(userId, (req as any).tenantSlug);
    res.status(401).json({ success: false, message: 'Invalid backup code', data: { challengeToken: newChallenge } });
    return;
  }

  // SEC-H10: Successful password-then-backup-code login also clears the
  // password-stage counters so a prior flurry of bad passwords can't leave
  // the user locked out of their own account after they recover via backup.
  clearRateLimit(db, 'totp', totpKey(tenantSlug, userId));
  clearRateLimit(db, 'login_ip', ip);
  clearRateLimit(db, 'login_user', `${tenantSlug || 'default'}:${user.username}`);

  const tokens = await issueTokens(adb, user, req, res);
  res.json({ success: true, data: { ...tokens, remainingBackupCodes: remainingAfterConsume } });
}));

// POST /refresh — accepts token from httpOnly cookie or body (backwards compat)
router.post('/refresh', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';

  // SEC-H89: CSRF double-submit check.
  // Cookie-based refresh is vulnerable to CSRF because the browser sends the
  // httpOnly refreshToken cookie automatically on any cross-origin POST.
  // Defence: at login we also set a non-httpOnly `csrf_token` cookie that JS
  // can read. The SPA must forward it as `X-CSRF-Token`. We compare header vs
  // cookie using timingSafeEqual to avoid timing oracle attacks.
  // Mobile clients (Android app) send the refreshToken in the request body
  // rather than a cookie, so they are not cookie-CSRF-vulnerable and we skip
  // the check for them (body token present = non-browser client path).
  const cookieRefreshToken = (req as any).cookies?.refreshToken;
  const bodyRefreshToken = req.body?.refreshToken;
  if (cookieRefreshToken && !bodyRefreshToken) {
    // Browser path — enforce double-submit CSRF check.
    const csrfHeader = (req.headers['x-csrf-token'] as string | undefined) ?? '';
    const csrfCookie = (req as any).cookies?.csrf_token ?? '';
    const headerOk = csrfHeader.length > 0 && csrfCookie.length > 0;
    const match = headerOk && (() => {
      try {
        const hBuf = Buffer.from(csrfHeader, 'utf8');
        const cBuf = Buffer.from(csrfCookie, 'utf8');
        return hBuf.length === cBuf.length && crypto.timingSafeEqual(hBuf, cBuf);
      } catch { return false; }
    })();
    if (!match) {
      audit(db, 'refresh_failed', null, ip, { reason: 'csrf_mismatch' });
      logTenantAuthEvent('refresh_failed', req, null, null, { reason: 'csrf_mismatch' });
      res.status(403).json({ success: false, message: 'CSRF token invalid' });
      return;
    }
  }

  // Accept refresh token from httpOnly cookie (browser) or request body (mobile app)
  const refreshToken = cookieRefreshToken || bodyRefreshToken;
  if (!refreshToken) {
    // SEC-M10: Audit every failure path so brute-forcing / stolen-token use
    // is visible in tenant_auth_events.
    audit(db, 'refresh_failed', null, ip, { reason: 'missing_token' });
    logTenantAuthEvent('refresh_failed', req, null, null, { reason: 'missing_token' });
    res.status(400).json({ success: false, message: 'Refresh token required' });
    return;
  }

  try {
    // SEC (A6/A10): Explicit algorithm + iss + aud on verify.
    // SA1-1: rotation-aware verify — accepts tokens signed with
    // JWT_REFRESH_SECRET_PREVIOUS during the rotation window so already-
    // issued refresh tokens continue to work until operators retire the
    // previous secret (see docs/operator-guide.md).
    const payload = verifyJwtWithRotation(refreshToken, 'refresh', JWT_VERIFY_OPTIONS) as any;
    if (payload.type !== 'refresh') {
      audit(db, 'refresh_failed', payload?.userId ?? null, ip, { reason: 'wrong_type' });
      logTenantAuthEvent('refresh_failed', req, payload?.userId ?? null, null, { reason: 'wrong_type' });
      res.status(401).json({ success: false, message: 'Invalid refresh token' });
      return;
    }

    // SEC-H12: Assert the refresh token was issued for the tenant the request
    // is currently hitting. Tokens cross-tenant replay (e.g. a valid refresh
    // token for tenant-a.crm.example.com presented on tenant-b.crm.example.com)
    // must be rejected even though the JWT signature itself is valid — both
    // tenants share the same jwtRefreshSecret. Compare as equal-length buffers
    // via crypto.timingSafeEqual so the check doesn't leak slug length either.
    const requestTenantSlug = (req as any).tenantSlug || null;
    const payloadTenantStr = typeof payload.tenantSlug === 'string' ? payload.tenantSlug : '';
    const requestTenantStr = typeof requestTenantSlug === 'string' ? requestTenantSlug : '';
    const payloadBuf = Buffer.from(payloadTenantStr, 'utf8');
    const requestBuf = Buffer.from(requestTenantStr, 'utf8');
    const tenantMatches =
      payloadBuf.length === requestBuf.length &&
      crypto.timingSafeEqual(payloadBuf, requestBuf);
    if (!tenantMatches) {
      audit(db, 'refresh_failed', payload.userId ?? null, ip, { reason: 'tenant_mismatch' });
      logTenantAuthEvent('refresh_failed', req, payload.userId ?? null, null, { reason: 'tenant_mismatch' });
      res.status(401).json({ success: false, message: 'Invalid refresh token' });
      return;
    }

    const session = await adb.get<{ id: string; last_active: string | null }>(
      "SELECT id, last_active FROM sessions WHERE id = ? AND expires_at > datetime('now')",
      payload.sessionId
    );
    if (!session) {
      audit(db, 'refresh_failed', payload.userId ?? null, ip, { reason: 'session_expired' });
      logTenantAuthEvent('refresh_failed', req, payload.userId ?? null, null, { reason: 'session_expired' });
      res.status(401).json({ success: false, message: 'Session expired' });
      return;
    }

    // SEC (A8): Enforce idle-session timeout on refresh as well. Otherwise
    // a dormant refresh token could be used to resurrect a session.
    if (session.last_active) {
      const lastActiveMs = new Date(session.last_active).getTime();
      if (!Number.isNaN(lastActiveMs)) {
        const idleDays = (Date.now() - lastActiveMs) / (24 * 60 * 60 * 1000);
        if (idleDays > 14) {
          await adb.run('DELETE FROM sessions WHERE id = ?', payload.sessionId);
          audit(db, 'refresh_failed', payload.userId ?? null, ip, { reason: 'idle_timeout' });
          logTenantAuthEvent('refresh_failed', req, payload.userId ?? null, null, { reason: 'idle_timeout' });
          res.status(401).json({ success: false, message: 'Session idle timeout' });
          return;
        }
      }
    }

    const user = await adb.get<any>('SELECT id, username, email, first_name, last_name, role, avatar_url, permissions FROM users WHERE id = ? AND is_active = 1', payload.userId);
    if (!user) {
      // SEC-M11: If the user no longer exists or has been deactivated, the
      // session row is orphaned and must be deleted so a later re-activation
      // of the same user id cannot silently resurrect an old refresh-token
      // session. Also prevents the session table from retaining rows tied to
      // deactivated accounts indefinitely.
      await adb.run('DELETE FROM sessions WHERE id = ?', payload.sessionId);
      // SEC (E2): Generic error — don't leak whether a user was deleted.
      audit(db, 'refresh_failed', payload.userId ?? null, ip, { reason: 'user_missing_or_inactive' });
      logTenantAuthEvent('refresh_failed', req, payload.userId ?? null, null, { reason: 'user_missing_or_inactive' });
      res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
      return;
    }

    // Touch last_active on refresh
    await adb.run("UPDATE sessions SET last_active = datetime('now') WHERE id = ?", payload.sessionId);

    // SECURITY: Always derive tenant from request context (subdomain), never from old token
    const tenantSlug = (req as any).tenantSlug || null;
    // SEC (A6/A10): Explicit HS256 + iss + aud on sign.
    // SEC-L34: fresh `jti` on every rotation so refreshed tokens are distinguishable
    // from their predecessors.
    // SEC-H103: sign with dedicated per-purpose secret.
    // SEC (SCAN-613): Explicit type:'access' on every rotated access token.
    const accessToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, role: user.role, tenantSlug, type: 'access', jti: crypto.randomUUID() },
      config.accessJwtSecret,
      { ...JWT_SIGN_OPTIONS, expiresIn: '1h' }
    );

    // SEC-M9: Preserve the ORIGINAL refresh-token lifetime across rotation.
    // Standard login issues 30d, trustDevice login issues 90d. If we always
    // re-issued 30d here, a trustDevice user would silently have their session
    // shortened on every refresh — or, worse, if we always re-issued 90d
    // everyone could extend their session indefinitely by refreshing. Read
    // the original window from the incoming payload's `exp - iat` (seconds)
    // and re-use it, clamped to a sane [1h .. 90d] range as defence-in-depth.
    const originalWindowSec =
      typeof payload.exp === 'number' && typeof payload.iat === 'number'
        ? Math.max(3600, Math.min(90 * 24 * 3600, payload.exp - payload.iat))
        : 30 * 24 * 3600;
    // SEC-H103: sign with dedicated per-purpose secret.
    const newRefreshToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, type: 'refresh', tenantSlug, jti: crypto.randomUUID() },
      config.refreshJwtSecret,
      { ...JWT_SIGN_OPTIONS, expiresIn: originalWindowSec }
    );
    // SEC-H17: SameSite=Strict on refresh rotation too — must match issueTokens().
    // SCAN-905: use req.secure so staging/dev HTTPS also sets the Secure flag.
    const isSecureConnection = req.secure || config.nodeEnv === 'production';
    res.cookie('refreshToken', newRefreshToken, {
      httpOnly: true,
      secure: isSecureConnection,
      sameSite: 'strict',
      maxAge: originalWindowSec * 1000,
      path: '/',
    });
    // SEC-H89: Rotate csrf_token in sync with refreshToken so the pair stays valid.
    const newCsrfToken = crypto.randomBytes(24).toString('base64url');
    res.cookie('csrf_token', newCsrfToken, {
      httpOnly: false,
      secure: isSecureConnection,
      sameSite: 'strict',
      maxAge: originalWindowSec * 1000,
      path: '/',
    });

    const safeUser = {
      id: user.id, username: user.username, email: user.email,
      first_name: user.first_name, last_name: user.last_name,
      role: user.role, avatar_url: user.avatar_url || null,
      permissions: safeParsePermissions(user.permissions),
    };

    // SEC-M10: Audit successful rotation so the full refresh lifecycle shows up
    // in the tenant audit trail (useful when tracing a compromised session's
    // activity — you can see exactly how long the stolen token stayed alive).
    audit(db, 'refresh_success', user.id, ip, { sessionId: payload.sessionId });
    logTenantAuthEvent('refresh_success', req, user.id, user.username, { sessionId: payload.sessionId });

    res.json({ success: true, data: { accessToken, user: safeUser } });
  } catch (err) {
    // SEC-M10: Catch-block covers `jwt.verify` failures (bad signature, expired,
    // malformed) and any async DB failures above. Keep the 401 generic.
    audit(db, 'refresh_failed', null, ip, {
      reason: 'verify_error',
      error: err instanceof Error ? err.name : 'unknown',
    });
    logTenantAuthEvent('refresh_failed', req, null, null, {
      reason: 'verify_error',
      error: err instanceof Error ? err.name : 'unknown',
    });
    res.status(401).json({ success: false, message: 'Invalid refresh token' });
  }
}));

// POST /logout
router.post('/logout', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  await adb.run('DELETE FROM sessions WHERE id = ?', req.user!.sessionId);
  res.clearCookie('refreshToken', { path: '/' });
  // SEC-H89: Clear csrf_token alongside refreshToken on logout.
  res.clearCookie('csrf_token', { path: '/' });
  res.json({ success: true, data: { message: 'Logged out' } });
});

// POST /switch-user (rate-limited, requires existing auth session)
// SEC (A4): If the target user has 2FA enabled, the caller must also supply
// a current TOTP code for that target user. PIN alone is not enough to bypass
// 2FA when the target account has it turned on.
router.post('/switch-user', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!checkPinRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many failed PIN attempts. Try again in 15 minutes.' });
    return;
  }

  const { pin, totpCode } = req.body;
  if (!pin || typeof pin !== 'string' || pin.length < 1 || pin.length > 20) {
    res.status(400).json({ success: false, message: 'Valid PIN required (1-20 characters)' });
    return;
  }

  // Fetch all active users with PINs and compare via bcrypt (PINs are hashed)
  // Only accept bcrypt-hashed PINs (reject legacy plaintext)
  // SEC (A4): also pull totp_secret + totp_enabled so we can enforce 2FA on the target.
  // PROD12: also pull pin_set so we can force the user to change the default
  // PIN '1234' on first switch-user instead of silently accepting it.
  const usersWithPins = await adb.all<any>(
    "SELECT id, username, email, first_name, last_name, role, avatar_url, permissions, pin, pin_set, totp_secret, totp_enabled FROM users WHERE pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
  );

  const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));

  // PROD12: if the matched user still has pin_set = 0 they're using the
  // provisioning-default PIN (bcrypt of '1234'). Refuse to complete the
  // switch until they rotate it via /auth/change-pin. Returns 403 with a
  // sentinel message the Android/Web clients can catch and redirect the
  // user into a PIN-change flow. The admin's first real login already
  // forces a password change via password_set=0; this gives PIN parity.
  if (user && user.pin_set === 0) {
    res.status(403).json({
      success: false,
      message: 'Default PIN must be changed before first use. Open Settings → Change PIN.',
      code: 'PIN_NOT_SET',
    });
    return;
  }

  if (!user) {
    recordPinFailure(db, ip);
    audit(db, 'pin_switch_failed', null, ip, { reason: 'invalid_pin' });
    logTenantAuthEvent('pin_switch_failed', req, null, null, { reason: 'invalid_pin' });
    res.status(401).json({ success: false, message: 'Invalid PIN' });
    return;
  }

  // SEC (A4): If target has 2FA enabled, require a valid TOTP code.
  if (user.totp_enabled && user.totp_secret) {
    if (typeof totpCode !== 'string' || !/^\d{6}$/.test(totpCode)) {
      // Don't consume a PIN failure — PIN was correct, the client just hasn't
      // sent the second factor yet.
      audit(db, 'pin_switch_requires_2fa', user.id, ip, { user_id: user.id });
      res.status(401).json({
        success: false,
        message: '2FA code required',
        data: { requires2fa: true },
      });
      return;
    }
    const tenantSlugForRate = (req as any).tenantSlug || null;
    if (!checkTotpRateLimit(db, tenantSlugForRate, user.id)) {
      res.status(429).json({ success: false, message: 'Too many 2FA attempts. Try again in 15 minutes.' });
      return;
    }
    let isValid = false;
    try {
      const secret = decryptSecret(user.totp_secret);
      isValid = Boolean(verifySync({ token: totpCode, secret }));
    } catch {
      isValid = false;
    }
    if (!isValid) {
      recordTotpFailure(db, tenantSlugForRate, user.id);
      audit(db, 'pin_switch_failed', user.id, ip, { reason: 'invalid_2fa' });
      logTenantAuthEvent('pin_switch_failed', req, user.id, user.username, { reason: 'invalid_2fa' });
      res.status(401).json({ success: false, message: 'Invalid 2FA code' });
      return;
    }
    clearRateLimit(db, 'totp', totpKey(tenantSlugForRate, user.id));
  }

  // Remove pin and totp_secret from user object before returning
  delete user.pin;
  delete user.totp_secret;
  delete user.totp_enabled;

  // Successful auth — clear failures for this IP
  clearPinFailures(db, ip);
  audit(db, 'pin_switch_success', user.id, ip, { switched_to: user.username });
  logTenantAuthEvent('pin_switch_success', req, user.id, user.username, { switched_to: user.username });

  // SEC (A7 / SEC-H66): Prune + insert atomically so concurrent PIN switches
  // cannot race between the DELETE and INSERT.
  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString(); // 8 hours for PIN sessions
  await pruneAndInsertSession(adb, user.id, sessionId, 'pin-switch', expiresAt);

  const tenantSlug = (req as any).tenantSlug || null;
  // SEC (A6/A10): Explicit HS256 + iss + aud.
  // SEC-L34: unique `jti` per token issuance.
  // SEC-H103: sign with dedicated per-purpose secret.
  // SEC (SCAN-613): Explicit type:'access' on PIN-switch access tokens.
  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role, tenantSlug, type: 'access', jti: crypto.randomUUID() },
    config.accessJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '1h' }
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh', tenantSlug, jti: crypto.randomUUID() },
    config.refreshJwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '8h' }
  );

  // SCAN-646: Parse permissions without mutating user — use a response-only copy.
  const userForResponse = { ...user, permissions: safeParsePermissions(user.permissions) };

  // SEC-H17: SameSite=Strict — matches main login flow. Impersonation sessions
  // are short-lived and should never cross origins.
  // SCAN-905: req.secure honours trust-proxy; production fallback as safety net.
  const isSecureConnection = req.secure || config.nodeEnv === 'production';
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: isSecureConnection,
    sameSite: 'strict',
    maxAge: 8 * 60 * 60 * 1000, // 8 hours
    path: '/',
  });

  // SEC-H89: Set the matching csrf_token cookie so POST /auth/refresh passes
  // the double-submit CSRF check for this switch-user session.
  // Without this, the first /refresh call from the switched session would fail
  // with 403 "CSRF token invalid" and log out the user immediately.
  const switchCsrfToken = crypto.randomBytes(24).toString('base64url');
  res.cookie('csrf_token', switchCsrfToken, {
    httpOnly: false,
    secure: isSecureConnection,
    sameSite: 'strict',
    maxAge: 8 * 60 * 60 * 1000,
    path: '/',
  });

  res.json({
    success: true,
    data: { accessToken, user: userForResponse },
  });
});

// POST /verify-pin — verify current user's PIN without switching user
router.post('/verify-pin', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!checkPinRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many failed PIN attempts. Try again in 15 minutes.' });
    return;
  }

  const { pin } = req.body;
  if (!pin || typeof pin !== 'string' || pin.length < 1 || pin.length > 20) {
    res.status(400).json({ success: false, message: 'Valid PIN required' });
    return;
  }

  const userId = (req as any).user?.id;
  if (!userId) {
    res.status(401).json({ success: false, message: 'Not authenticated' });
    return;
  }

  const row = await adb.get<{ pin: string }>(
    "SELECT pin FROM users WHERE id = ? AND pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1",
    userId
  );

  if (!row || !bcrypt.compareSync(pin, row.pin)) {
    recordPinFailure(db, ip);
    audit(db, 'pin_verify_failed', userId, ip, { reason: 'invalid_pin' });
    logTenantAuthEvent('pin_verify_failed', req, userId, null, { reason: 'invalid_pin' });
    res.status(401).json({ success: false, message: 'Invalid PIN' });
    return;
  }

  clearPinFailures(db, ip);
  audit(db, 'pin_verify_success', userId, ip, {});
  logTenantAuthEvent('pin_verify_success', req, userId, null, {});
  res.json({ success: true, data: { verified: true } });
});

// ENR-UX19: POST /forgot-password — Request a password reset token
// Generates a reset token, stores it in the DB, and emails it (or logs to console if SMTP is not configured).
//
// SEC-M32: The existing-vs-nonexisting email paths previously took very
// different amounts of time (bcrypt-free not-found path returned immediately,
// while the found path did crypto.randomBytes + UPDATE + SMTP round-trip).
// That gave an attacker a reliable timing oracle for account enumeration.
// We now (a) always run a dummy bcrypt compare on the not-found path, and
// (b) pin every response to a minimum duration via enforceMinDuration. The
// real sendEmail call is detached so slow SMTP can't leak the found path.
const FORGOT_PASSWORD_MIN_DURATION_MS = 500;
// $2b$12$ dummy hash; 12 rounds to match real cost (same constant as login).
const FORGOT_PASSWORD_DUMMY_HASH = '$2b$12$LJ3m4ys3Lhmd0tSwUaGgmeoS89CINnom5eSvnfmEFYKaSwVKbHlrS';
router.post('/forgot-password', asyncHandler(async (req: Request, res: Response) => {
  const startNs = process.hrtime.bigint();
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const db = req.db;

  // Rate limit: 3 attempts per hour per IP (SQLite-backed)
  if (!checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)) {
    res.status(429).json({ success: false, message: 'Too many reset attempts. Try again later.' });
    return;
  }
  recordWindowFailure(db, 'forgot_password', ip, 3600_000);

  // SEC-H85: captcha gate — after threshold attempts from this IP within the
  // rate-limit window, require a valid hCaptcha token. countRateLimitAttempts
  // reads the already-incremented rate_limits row so no extra query is needed.
  const forgotAttempts = countRateLimitAttempts(db, 'forgot_password', ip);
  if (forgotAttempts >= CAPTCHA_FAILURE_THRESHOLD) {
    const captchaResult = await verifyHcaptcha(req.body?.captcha_token, ip);
    if (!captchaResult.ok) {
      res.status(429).json({
        success: false,
        message: 'Too many attempts, captcha required',
        captcha_required: true,
      });
      return;
    }
  }

  const { email } = req.body;
  if (!email || typeof email !== 'string' || !email.includes('@')) {
    res.status(400).json({ success: false, message: 'Valid email is required' });
    return;
  }

  // Always return success to prevent email enumeration
  const genericMsg = 'If an account with that email exists, a reset link has been sent.';

  const adb = req.asyncDb;
  const dbSync = req.db;
  const user = await adb.get<any>(
    'SELECT id, username, email FROM users WHERE email = ? AND is_active = 1',
    email.trim().toLowerCase()
  );

  if (!user) {
    // Don't reveal whether the email exists. Do not persist the attacker-
    // supplied email either — it can be used to pollute audit logs with
    // arbitrary strings (SEC-L43).
    audit(dbSync, 'password_reset_requested', null, ip, { email: '<unknown-user>', found: false });
    // SEC-M32: run a dummy bcrypt compare so the not-found path does the
    // same CPU work as the found path (which will sha256 + write + send
    // email). The return value is discarded. bcrypt.compareSync is 12-round
    // so it dominates the timing signal that would otherwise exist.
    bcrypt.compareSync(email, FORGOT_PASSWORD_DUMMY_HASH);
    await enforceMinDuration(startNs, FORGOT_PASSWORD_MIN_DURATION_MS);
    res.json({ success: true, data: { message: genericMsg } });
    return;
  }

  // Generate a secure reset token with 1-hour expiry
  const resetToken = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  // Store the token (hashed) in the user record
  const tokenHash = crypto.createHash('sha256').update(resetToken).digest('hex');
  await adb.run(
    'UPDATE users SET reset_token = ?, reset_token_expires = ? WHERE id = ?',
    tokenHash, expiresAt, user.id
  );

  // SCAN-883: audit the reset attempt without persisting the raw email (SEC-L43).
  audit(dbSync, 'password_reset_requested', user.id, ip, {
    email_hash: crypto.createHash('sha256').update(email.trim().toLowerCase()).digest('hex').slice(0, 16),
  });

  // Build the reset URL.
  // SEC-H7: Use config.baseDomain rather than req.headers.host so an attacker
  // cannot send a malicious Host header (or X-Forwarded-Host) and get the
  // server to mint a phishing URL pointing at their own domain. The reset URL
  // is emailed verbatim, so host-header injection here turns the reset email
  // into a credential-harvesting link. In multi-tenant mode the tenant subdomain
  // is preserved by resolving against the request's tenantSlug when present.
  const tenantSlug = (req as any).tenantSlug || null;
  const host = tenantSlug ? `${tenantSlug}.${config.baseDomain}` : config.baseDomain;
  const resetUrl = `https://${host}/reset-password/${resetToken}`;

  // SEC-M32: detach email delivery so SMTP latency doesn't give attackers a
  // timing oracle. The token is already persisted in the DB by this point,
  // so losing the email to a transient SMTP failure is recoverable via the
  // tenant admin logs — same behavior as before, just no longer in the
  // response-time critical path.
  //
  // SEC (T16): Previous code wrote the reset URL to console.log, leaking a
  // live password-reset link to anyone with stdout access. Never do that.
  void (async () => {
    try {
      const { sendEmail } = await import('../services/email.js');
      const sent = await sendEmail(dbSync, {
        to: user.email,
        subject: 'Password Reset — Bizarre CRM',
        html: `<p>Hi ${user.username},</p><p>Click the link below to reset your password. This link expires in 1 hour.</p><p><a href="${resetUrl}">${resetUrl}</a></p><p>If you didn't request this, you can safely ignore this email.</p>`,
      });
      if (!sent) {
        logger.warn('Reset token generated but email delivery failed (SMTP not configured)', {
          userId: user.id,
        });
      }
    } catch (err) {
      logger.warn('Reset token generated but email delivery failed', {
        userId: user.id,
        error: err instanceof Error ? err.message : 'unknown',
      });
    }
  })();

  await enforceMinDuration(startNs, FORGOT_PASSWORD_MIN_DURATION_MS);
  res.json({ success: true, data: { message: genericMsg } });
}));

// ENR-UX19: POST /reset-password — Consume a reset token and set a new password
// SEC (P2FA1): The column is `password_hash`, NOT `password`. The previous code
//              wrote to a column that doesn't exist, silently breaking every reset.
// SEC (P2FA2): On successful reset we also delete all existing sessions so a
//              previously-compromised token can't keep a live session alive.
// SEC (P2FA8): Reject the new password if it matches any of the last 5 hashes.
router.post('/reset-password', asyncHandler(async (req: Request, res: Response) => {
  const { token, password } = req.body;
  if (!token || typeof token !== 'string' || token.length !== 64) {
    res.status(400).json({ success: false, message: 'Invalid reset token' });
    return;
  }
  if (!password || typeof password !== 'string' || password.length < 8 || password.length > 128) {
    res.status(400).json({ success: false, message: 'Password must be 8 to 128 characters' });
    return;
  }

  const adb = req.asyncDb;
  const dbSync = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

  const user = await adb.get<any>(
    "SELECT id, username FROM users WHERE reset_token = ? AND reset_token_expires > datetime('now') AND is_active = 1",
    tokenHash
  );

  if (!user) {
    res.status(400).json({ success: false, message: 'Invalid or expired reset token' });
    return;
  }

  // SEC (P2FA8): Block reuse of the last N passwords (incl. current).
  if (await isPasswordReused(adb, user.id, password)) {
    res.status(400).json({
      success: false,
      message: `Password must be different from your last ${PASSWORD_HISTORY_DEPTH} passwords.`,
    });
    return;
  }

  // SEC-H65: Hash BEFORE the transaction so bcrypt's CPU cost doesn't hold the
  // SQLite write lock while concurrent requests queue behind it.
  const hashedPassword = await bcrypt.hash(password, 12);

  // SEC (P2FA1): Update password_hash, not the non-existent `password` column.
  // SEC (P2FA2): Delete ALL existing sessions so a prior leak can't persist.
  // SEC-H1: Wrap the UPDATE + DELETE in a single atomic transaction. Previously
  //         a partial failure between the two statements could leave the new
  //         password live while stale sessions remained authenticated.
  // SEC-H65: The UPDATE WHERE clause re-checks reset_token = ? AND
  //          reset_token_expires > datetime('now') inside the write lock so two
  //          concurrent POSTs carrying the same token can only succeed once —
  //          the second finds changes === 0 and is rejected. Also, password
  //          history is recorded inside the same transaction (SEC-M24) so a
  //          crash between statements cannot leave history missing.
  const results = await adb.transaction([
    {
      sql: "UPDATE users SET password_hash = ?, password_set = 1, reset_token = NULL, reset_token_expires = NULL, updated_at = datetime('now') WHERE id = ? AND reset_token = ? AND reset_token_expires > datetime('now')",
      params: [hashedPassword, user.id, tokenHash],
    },
    {
      sql: 'DELETE FROM sessions WHERE user_id = ?',
      params: [user.id],
    },
    {
      sql: 'INSERT INTO password_history (user_id, password_hash) VALUES (?, ?)',
      params: [user.id, hashedPassword],
    },
    {
      sql: `DELETE FROM password_history
             WHERE user_id = ?
               AND id NOT IN (
                 SELECT id FROM password_history
                   WHERE user_id = ?
                   ORDER BY created_at DESC
                   LIMIT ?
               )`,
      params: [user.id, user.id, PASSWORD_HISTORY_DEPTH],
    },
  ]);

  // SEC-H65: If the UPDATE touched zero rows the token was already consumed
  // (or expired between the SELECT above and the write lock). Reject immediately
  // without leaking which branch fired — same message as the SELECT-based check.
  if (results[0].changes === 0) {
    res.status(400).json({ success: false, message: 'Invalid or expired reset token' });
    return;
  }

  audit(dbSync, 'password_reset_completed', user.id, ip, { sessions_revoked: true });
  logTenantAuthEvent('password_reset_completed', req, user.id, null, { sessions_revoked: true });

  res.json({ success: true, data: { message: 'Password has been reset. You can now log in.' } });
}));

// ---------------------------------------------------------------------------
// P2FA3: POST /account/2fa/disable
// ---------------------------------------------------------------------------
// Allow an authenticated user to voluntarily disable their own 2FA.
// Requires BOTH: current password AND a current TOTP code. Clears the totp_secret,
// totp_enabled flag, and any backup codes. Every disable is written to the audit log.
router.post('/account/2fa/disable', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const userId = req.user!.id;
  const tenantSlug = (req as any).tenantSlug || null;

  const { currentPassword, totpCode } = req.body || {};
  if (!currentPassword || typeof currentPassword !== 'string') {
    res.status(400).json({ success: false, message: 'Current password is required' });
    return;
  }
  if (typeof totpCode !== 'string' || !/^\d{6}$/.test(totpCode)) {
    res.status(400).json({ success: false, message: 'Valid 6-digit 2FA code is required' });
    return;
  }

  const user = await adb.get<any>(
    'SELECT id, username, password_hash, totp_secret, totp_enabled FROM users WHERE id = ? AND is_active = 1',
    userId
  );
  if (!user) {
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }
  if (!user.totp_enabled || !user.totp_secret) {
    res.status(400).json({ success: false, message: '2FA is not currently enabled' });
    return;
  }

  // Rate-limit both the password check and the TOTP check on this user.
  if (!checkTotpRateLimit(db, tenantSlug, userId)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Try again in 15 minutes.' });
    return;
  }

  let passwordValid = false;
  try {
    passwordValid = bcrypt.compareSync(currentPassword, user.password_hash);
  } catch {
    passwordValid = false;
  }

  let totpValid = false;
  try {
    const secret = decryptSecret(user.totp_secret);
    totpValid = Boolean(verifySync({ token: totpCode, secret }));
  } catch {
    totpValid = false;
  }

  if (!passwordValid || !totpValid) {
    recordTotpFailure(db, tenantSlug, userId);
    audit(db, '2fa_disable_failed', userId, ip, {
      reason: !passwordValid ? 'bad_password' : 'bad_totp',
    });
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  clearRateLimit(db, 'totp', totpKey(tenantSlug, userId));

  await adb.run(
    "UPDATE users SET totp_secret = NULL, totp_enabled = 0, backup_codes = NULL, updated_at = datetime('now') WHERE id = ?",
    userId
  );

  // SEC-H8: Disabling 2FA is a security-sensitive state change — any other
  // session (on a different device / stolen cookie) must be forced through a
  // fresh login so an attacker who grabbed a refresh token can't ride along
  // post-disable. Keep the caller's current session so they don't get logged
  // out of the very request they just made. Also clear any deviceTrust cookie
  // on this browser so "remember this device" from a prior 2FA-enabled state
  // doesn't grant silent re-entry.
  await adb.run(
    'DELETE FROM sessions WHERE user_id = ? AND id != ?',
    userId, req.user!.sessionId
  );
  res.clearCookie('deviceTrust', { path: '/' });

  audit(db, '2fa_disabled', userId, ip, { self_service: true });
  logTenantAuthEvent('2fa_disabled', req, userId, user.username, { self_service: true });

  res.json({ success: true, data: { message: '2FA has been disabled on your account.' } });
});

// ---------------------------------------------------------------------------
// P2FA6: POST /auth/force-disable-2fa/:userId
// ---------------------------------------------------------------------------
// In-tenant admin override — lets a shop admin clear a user's 2FA config when
// that user is locked out. Requires req.user.role === 'admin' and targets a
// user in the SAME tenant (all queries run against the tenant DB via req.asyncDb).
// Also revokes the target user's refresh tokens so they must re-authenticate.
router.post('/force-disable-2fa/:userId', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const actor = req.user!;
  if (actor.role !== 'admin') {
    res.status(403).json({ success: false, message: 'Admin role required' });
    return;
  }
  const targetId = validateId(req.params.userId, 'userId');
  if (targetId === actor.id) {
    res.status(400).json({ success: false, message: 'Use /account/2fa/disable for your own account' });
    return;
  }

  const target = await adb.get<any>(
    'SELECT id, username, totp_enabled FROM users WHERE id = ? AND is_active = 1',
    targetId
  );
  if (!target) {
    res.status(404).json({ success: false, message: 'User not found' });
    return;
  }
  if (!target.totp_enabled) {
    res.status(400).json({ success: false, message: '2FA is not enabled on that account' });
    return;
  }

  await adb.run(
    "UPDATE users SET totp_secret = NULL, totp_enabled = 0, backup_codes = NULL, updated_at = datetime('now') WHERE id = ?",
    targetId
  );
  // Force re-login by nuking any active sessions for the target.
  await adb.run('DELETE FROM sessions WHERE user_id = ?', targetId);

  audit(db, '2fa_force_disabled', actor.id, ip, {
    target_user_id: targetId,
    target_username: target.username,
  });
  logTenantAuthEvent('2fa_force_disabled', req, actor.id, actor.username, {
    target_user_id: targetId,
    target_username: target.username,
  });

  res.json({
    success: true,
    data: {
      message: `2FA has been force-disabled for user ${target.username}. They must re-enroll on next login.`,
    },
  });
});

// ---------------------------------------------------------------------------
// P2FA7: POST /auth/recover-with-backup-code
// ---------------------------------------------------------------------------
// Emergency recovery path — a user who has lost their 2FA device can log in
// with email + a one-time backup code + a new password. On success:
//   - the matching backup code is consumed,
//   - the new password is written to password_hash and recorded in history,
//   - all existing sessions are revoked,
//   - 2FA is disabled (user must re-enroll on next login).
router.post('/recover-with-backup-code', asyncHandler(async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';

  // IP-level rate limit (reuse login rate limiter).
  if (!checkLoginRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many attempts. Try again later.' });
    return;
  }

  const { email, backupCode, newPassword } = req.body || {};
  let normalizedEmail: string | null;
  try {
    normalizedEmail = validateEmail(email, 'email', true);
  } catch {
    res.status(400).json({ success: false, message: 'Valid email is required' });
    return;
  }
  if (!backupCode || typeof backupCode !== 'string' || backupCode.length < 16) {
    res.status(400).json({ success: false, message: 'Valid backup code is required' });
    return;
  }
  if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 8 || newPassword.length > 128) {
    res.status(400).json({ success: false, message: 'New password must be 8 to 128 characters' });
    return;
  }

  const user = await adb.get<any>(
    'SELECT id, username, email, backup_codes, totp_enabled FROM users WHERE email = ? AND is_active = 1',
    normalizedEmail
  );

  // Generic failure message to avoid leaking whether the email exists.
  const fail = () => {
    recordLoginFailure(db, ip);
    audit(db, 'backup_code_recovery_failed', user?.id ?? null, ip, { email: normalizedEmail });
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
  };

  if (!user || !user.backup_codes) { fail(); return; }

  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkTotpRateLimit(db, tenantSlug, user.id)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.' });
    return;
  }

  // SEC-H73: Atomic consume with retry — find the matching hash, then use a
  // conditional UPDATE (json_extract guard) so two concurrent POSTs carrying
  // the same code can only consume it once. Retry up to 3 times if a racing
  // write removes the element before our UPDATE acquires the write lock.
  const MAX_CONSUME_ATTEMPTS_RECOVERY = 3;
  let matchedHash: string | null = null;
  let recoveryConsumed = false;

  let currentCodesJson: string = user.backup_codes;

  for (let attempt = 0; attempt < MAX_CONSUME_ATTEMPTS_RECOVERY; attempt++) {
    let hashedCodes: string[] = [];
    try { hashedCodes = JSON.parse(currentCodesJson); } catch { hashedCodes = []; }

    const matchIdx = hashedCodes.findIndex(h => {
      try { return bcrypt.compareSync(backupCode, h); } catch { return false; }
    });
    if (matchIdx === -1) break; // Code not found in this snapshot.

    matchedHash = hashedCodes[matchIdx];

    // Atomic conditional UPDATE: only removes $[matchIdx] if the element is
    // still the hash we matched — guards against concurrent removal.
    const consumeResult = await adb.run(
      `UPDATE users SET backup_codes = JSON_REMOVE(backup_codes, '$[${matchIdx}]')
       WHERE id = ? AND json_extract(backup_codes, '$[${matchIdx}]') = ?`,
      user.id, matchedHash
    );

    if (consumeResult.changes > 0) {
      recoveryConsumed = true;
      break;
    }

    // changes === 0: concurrent consume beat us. Re-read and retry.
    const freshUser = await adb.get<{ backup_codes: string }>(
      'SELECT backup_codes FROM users WHERE id = ? AND is_active = 1',
      user.id
    );
    if (!freshUser?.backup_codes) break;
    currentCodesJson = freshUser.backup_codes;
  }

  if (!recoveryConsumed) {
    recordTotpFailure(db, tenantSlug, user.id);
    fail();
    return;
  }

  // Enforce password history.
  if (await isPasswordReused(adb, user.id, newPassword)) {
    res.status(400).json({
      success: false,
      message: `Password must be different from your last ${PASSWORD_HISTORY_DEPTH} passwords.`,
    });
    return;
  }

  // All checks passed — perform the recovery. The backup code was already
  // atomically removed above; this UPDATE finalises the password reset and
  // disables 2FA. backup_codes column is left as-is (already updated).
  clearRateLimit(db, 'totp', totpKey(tenantSlug, user.id));
  const newHash = bcrypt.hashSync(newPassword, 12);

  await adb.run(
    // SEC-H17: stamp last_backup_recovery_at so role / permission mutations
    // can enforce a 24 h cooldown post-recovery. Column added in migration
    // 100_recovery_cooldown.sql.
    "UPDATE users SET password_hash = ?, password_set = 1, totp_secret = NULL, totp_enabled = 0, last_backup_recovery_at = datetime('now'), updated_at = datetime('now') WHERE id = ?",
    newHash, user.id
  );
  await adb.run('DELETE FROM sessions WHERE user_id = ?', user.id);
  await recordPasswordHistory(adb, user.id, newHash);

  audit(db, 'backup_code_recovery_success', user.id, ip, {
    sessions_revoked: true,
    twofa_reset: true,
  });
  logTenantAuthEvent('backup_code_recovery_success', req, user.id, user.username, {
    sessions_revoked: true,
    twofa_reset: true,
  });

  res.json({
    success: true,
    data: {
      message: 'Password reset and 2FA disabled. Please log in and re-enroll 2FA.',
    },
  });
}));

// ---------------------------------------------------------------------------
// POST /auth/change-password — Authenticated user changes their own password
// ---------------------------------------------------------------------------
// Android ProfileScreen entry point. Requires the current password, enforces
// the same history / length rules as /reset-password, updates password_hash,
// records to password_history, and revokes ALL sessions (force re-login on
// every device). Update + session delete run atomically via adb.transaction.
router.post('/change-password', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const userId = req.user!.id;

  const { current_password: currentPassword, new_password: newPassword } = req.body || {};

  if (!currentPassword || typeof currentPassword !== 'string') {
    res.status(400).json({ success: false, message: 'Current password is required' });
    return;
  }
  if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 8) {
    res.status(400).json({ success: false, message: 'New password must be at least 8 characters' });
    return;
  }
  if (newPassword.length > 256) {
    res.status(400).json({ success: false, message: 'New password is too long' });
    return;
  }

  const user = await adb.get<{ id: number; username: string; password_hash: string | null }>(
    'SELECT id, username, password_hash FROM users WHERE id = ? AND is_active = 1',
    userId
  );
  if (!user || !user.password_hash) {
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  let passwordValid = false;
  try {
    passwordValid = bcrypt.compareSync(currentPassword, user.password_hash);
  } catch {
    passwordValid = false;
  }
  if (!passwordValid) {
    audit(db, 'password_change_failed', userId, ip, { reason: 'bad_current_password' });
    logTenantAuthEvent('password_change_failed', req, userId, user.username, { reason: 'bad_current_password' });
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  // SEC (P2FA8): Block reuse of the last N passwords (incl. current).
  if (await isPasswordReused(adb, userId, newPassword)) {
    res.status(400).json({
      success: false,
      message: `Password must be different from your last ${PASSWORD_HISTORY_DEPTH} passwords.`,
    });
    return;
  }

  const newHash = await bcrypt.hash(newPassword, 12);

  // Atomic: update password_hash AND revoke all sessions in the same transaction
  // so a prior leak can't persist if only half the update lands.
  // SEC-M12: Also wipe reset_token / reset_token_expires in the same UPDATE.
  // A pending password-reset token that was outstanding when the user changed
  // their password must not stay valid — otherwise an attacker who phished a
  // reset link could still consume it after the legitimate owner changed the
  // password, locking the owner back out.
  // SEC-M24: record the new password hash in password_history INSIDE the same
  // transaction. Previously the history INSERT happened in a separate call
  // after the UPDATE — a process crash between the two statements would
  // rotate the password but leave history missing, letting the user reuse
  // the new password on the next rotation and bypass the P2FA8 reuse check.
  await adb.transaction([
    {
      sql: "UPDATE users SET password_hash = ?, password_set = 1, reset_token = NULL, reset_token_expires = NULL, updated_at = datetime('now') WHERE id = ?",
      params: [newHash, userId],
    },
    {
      sql: 'DELETE FROM sessions WHERE user_id = ?',
      params: [userId],
    },
    {
      sql: 'INSERT INTO password_history (user_id, password_hash) VALUES (?, ?)',
      params: [userId, newHash],
    },
    {
      sql: `DELETE FROM password_history
             WHERE user_id = ?
               AND id NOT IN (
                 SELECT id FROM password_history
                   WHERE user_id = ?
                   ORDER BY created_at DESC
                   LIMIT ?
               )`,
      params: [userId, userId, PASSWORD_HISTORY_DEPTH],
    },
  ]);

  audit(db, 'password_changed', userId, ip, { sessions_revoked: true, self_service: true });
  logTenantAuthEvent('password_changed', req, userId, user.username, { sessions_revoked: true, self_service: true });
  logger.info('Password changed by user', { userId });

  res.json({ success: true, data: { message: 'Password changed successfully' } });
});

// ---------------------------------------------------------------------------
// POST /auth/change-pin — Authenticated user changes their own PIN
// ---------------------------------------------------------------------------
// Android ProfileScreen entry point. Requires the current password (not the
// old PIN — the PIN is a lower-trust credential), validates the new PIN is
// 4-6 digits, hashes with bcrypt, and updates users.pin.
router.post('/change-pin', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const userId = req.user!.id;

  const { current_password: currentPassword, new_pin: newPin } = req.body || {};

  if (!currentPassword || typeof currentPassword !== 'string') {
    res.status(400).json({ success: false, message: 'Current password is required' });
    return;
  }
  if (!newPin || typeof newPin !== 'string' || !/^\d{4,6}$/.test(newPin)) {
    res.status(400).json({ success: false, message: 'PIN must be 4-6 digits' });
    return;
  }

  const user = await adb.get<{ id: number; username: string; password_hash: string | null }>(
    'SELECT id, username, password_hash FROM users WHERE id = ? AND is_active = 1',
    userId
  );
  if (!user || !user.password_hash) {
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  let passwordValid = false;
  try {
    passwordValid = bcrypt.compareSync(currentPassword, user.password_hash);
  } catch {
    passwordValid = false;
  }
  if (!passwordValid) {
    audit(db, 'pin_change_failed', userId, ip, { reason: 'bad_current_password' });
    logTenantAuthEvent('pin_change_failed', req, userId, user.username, { reason: 'bad_current_password' });
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_CREDENTIALS, message: 'Invalid credentials' });
    return;
  }

  const newPinHash = await bcrypt.hash(newPin, 12);

  // PROD12: flip pin_set → 1 so the switch-user gate (see /switch-user)
  // stops force-blocking this user with the PIN_NOT_SET sentinel.
  await adb.run(
    "UPDATE users SET pin = ?, pin_set = 1, updated_at = datetime('now') WHERE id = ?",
    newPinHash, userId
  );

  audit(db, 'pin_changed', userId, ip, { self_service: true });
  logTenantAuthEvent('pin_changed', req, userId, user.username, { self_service: true });
  logger.info('PIN changed by user', { userId });

  res.json({ success: true, data: { message: 'PIN changed successfully' } });
});

// GET /me
router.get('/me', authMiddleware, (req: Request, res: Response) => {
  res.json({ success: true, data: req.user });
});

export default router;
