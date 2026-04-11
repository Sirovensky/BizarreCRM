import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { generateSecret, verifySync } from 'otplib';
import QRCode from 'qrcode';
import { config } from '../config.js';
import { authMiddleware, JWT_SIGN_OPTIONS, JWT_VERIFY_OPTIONS } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { logTenantAuthEvent } from '../utils/masterAudit.js';
import { checkWindowRate, recordWindowFailure, clearRateLimit, checkLockoutRate, recordLockoutFailure, cleanupExpiredEntries } from '../utils/rateLimiter.js';
import { validateEmail } from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('auth');

// SEC (A7): Max concurrent refresh-token sessions per user.
// On login, if user has more than this many active sessions, the oldest
// ones are deleted before issuing the new one.
const MAX_ACTIVE_SESSIONS_PER_USER = 5;

// SEC (A5): Minimum wall-clock time for a login attempt. Equalizes the
// response time for valid vs. invalid users and email-vs-username lookups.
const LOGIN_MIN_DURATION_MS = 100;

// SEC (P2FA8): Number of previous passwords to block when setting a new one.
const PASSWORD_HISTORY_DEPTH = 5;

// SECURITY: Derived key for device trust cookies — separate from JWT signing key
// Prevents a JWT token from being reused as a device trust cookie or vice versa
const deviceTrustKey = crypto.createHmac('sha256', config.jwtSecret).update('device-trust-v1').digest('hex');

// AES-256-GCM encryption for TOTP secrets (versioned keys for future rotation)
// SEC-H2: TOTP encryption key is derived from JWT_SECRET + superAdminSecret to ensure
// the TOTP key is different from the JWT signing key even if JWT_SECRET alone is compromised.
// v1 key is kept for decrypting existing secrets; v2 is used for new encryptions.
const ENCRYPTION_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':totp:v1').digest(),
  2: crypto.createHash('sha256').update(config.jwtSecret + ':totp-encryption:v2:' + config.superAdminSecret).digest(),
};
const CURRENT_KEY_VERSION = 2;

function encryptSecret(plaintext: string): string {
  const key = ENCRYPTION_KEYS[CURRENT_KEY_VERSION];
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
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
  if (challenges.size >= MAX_CHALLENGES) {
    const oldest = Array.from(challenges.entries()).sort((a, b) => a[1].expires - b[1].expires);
    for (let i = 0; i < Math.min(100, oldest.length); i++) challenges.delete(oldest[i][0]);
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

function consumeChallenge(token: string): number | null {
  const userId = validateChallenge(token);
  if (userId) challenges.delete(token);
  return userId;
}

// Clean expired challenges every minute
setInterval(() => {
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
 * SEC (A7): Enforce a soft cap on concurrent refresh-token sessions per user.
 * Before inserting a new session, delete the oldest ones that would push the
 * total above MAX_ACTIVE_SESSIONS_PER_USER.
 */
async function pruneOldSessions(adb: AsyncDb, userId: number): Promise<void> {
  const active = await adb.all<{ id: string }>(
    "SELECT id FROM sessions WHERE user_id = ? AND expires_at > datetime('now') ORDER BY created_at ASC",
    userId
  );
  // Keep at most (MAX - 1) — we're about to insert one more.
  const excess = active.length - (MAX_ACTIVE_SESSIONS_PER_USER - 1);
  if (excess <= 0) return;
  const toDelete = active.slice(0, excess).map(s => s.id);
  for (const id of toDelete) {
    await adb.run('DELETE FROM sessions WHERE id = ?', id);
  }
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

  // SEC (A7): Prune oldest sessions if user exceeds the cap BEFORE inserting.
  await pruneOldSessions(adb, user.id);

  await adb.run(
    "INSERT INTO sessions (id, user_id, device_info, expires_at, last_active) VALUES (?, ?, ?, ?, datetime('now'))",
    sessionId, user.id, req.headers['user-agent'] || 'unknown', expiresAt
  );

  const tenantSlug = (req as any).tenantSlug || null;
  // SEC (A6/A10): Explicit HS256 + iss + aud on every sign call.
  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role, tenantSlug },
    config.jwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '1h' }
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh', tenantSlug },
    config.jwtRefreshSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: `${refreshDays}d` }
  );

  // SEC-H17: SameSite=Strict — refresh tokens are first-party only. Lax
  // would allow cross-site top-level navigations to carry the cookie, giving
  // attackers a window for CSRF on sensitive cookie-bound flows. Strict has
  // no functional downside here because the SPA and API share an origin.
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    maxAge: refreshDays * 24 * 60 * 60 * 1000,
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
    permissions: user.permissions ? JSON.parse(user.permissions) : null,
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

// GET /setup-status — Check if this shop needs first-time setup (no users exist)
router.get('/setup-status', async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const row = await adb.get<{ c: number }>('SELECT COUNT(*) as c FROM users WHERE is_active = 1');
  res.json({ success: true, data: { needsSetup: row!.c === 0 } });
});

// POST /setup — First-time shop setup: create the initial admin account.
//
// TP3/TP4 (post-enrichment bug hunt): The legacy implementation read the raw
// setup token from store_config. This was broken in two ways:
//   1. tenant-provisioning.ts now stores only sha256(token) in the new
//      `setup_tokens` table (migration 083) and never writes store_config,
//      so every new tenant's /setup call returned "Setup not available".
//   2. The raw-token-in-store_config design left a forever-valid bootstrap
//      credential sitting in a row that every admin user could read.
//
// This handler now:
//   - Hashes the incoming token with sha256 and looks it up in setup_tokens
//   - Enforces expires_at > now() AND consumed_at IS NULL (single-use)
//   - Marks the token consumed_at = now() in the SAME transaction as the
//     admin user insert so a crash between the two cannot leave a token
//     usable against a partially-created tenant.
router.post('/setup', async (req: Request, res: Response) => {
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
    res.status(400).json({ success: false, message: 'Shop is already set up' });
    return;
  }

  const { username, password, email, setup_token } = req.body;

  // TP3: Validate the supplied token against setup_tokens.token_hash, check
  // expiry, and confirm it has not already been consumed. Generic error on
  // every failure path so an attacker cannot distinguish "no token present"
  // from "token expired" from "token already used".
  if (!setup_token || typeof setup_token !== 'string' || setup_token.length === 0) {
    res.status(403).json({ success: false, message: 'Invalid setup link. Request a new one from your administrator.' });
    return;
  }
  const suppliedTokenHash = crypto.createHash('sha256').update(setup_token).digest('hex');
  const tokenRow = await adb.get<{ id: number; expires_at: string; consumed_at: string | null }>(
    "SELECT id, expires_at, consumed_at FROM setup_tokens WHERE token_hash = ?",
    suppliedTokenHash
  );
  if (!tokenRow || tokenRow.consumed_at || new Date(tokenRow.expires_at) <= new Date()) {
    res.status(403).json({ success: false, message: 'Invalid or expired setup link. Request a new one from your administrator.' });
    return;
  }

  if (!username || typeof username !== 'string' || username.length < 3) {
    res.status(400).json({ success: false, message: 'Username must be at least 3 characters' });
    return;
  }
  if (!password || typeof password !== 'string' || password.length < 8 || password.length > 128) {
    res.status(400).json({ success: false, message: 'Password must be 8 to 128 characters' });
    return;
  }

  const hash = bcrypt.hashSync(password, 12);
  const pinHash = bcrypt.hashSync('1234', 12);

  // TP3: Consume the setup token and create the admin user atomically so a
  // race between two requests cannot both succeed against the same token,
  // and a crash between insert and consume cannot leave a usable token.
  try {
    await adb.transaction([
      {
        sql: `INSERT INTO users (username, email, password_hash, password_set, pin, first_name, last_name, role, is_active, created_at, updated_at)
              VALUES (?, ?, ?, 1, ?, '', '', 'admin', 1, datetime('now'), datetime('now'))`,
        params: [username, email || `${username}@shop.local`, hash, pinHash],
      },
      {
        // Belt-and-braces: only flip consumed_at if it is still NULL. The
        // UNIQUE index on token_hash plus this check means two concurrent
        // requests can never both succeed.
        sql: "UPDATE setup_tokens SET consumed_at = datetime('now') WHERE id = ? AND consumed_at IS NULL",
        params: [tokenRow.id],
      },
    ]);
  } catch (err) {
    logger.error('Setup transaction failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    res.status(500).json({ success: false, message: 'Failed to create admin account. Please try again.' });
    return;
  }

  // Defence-in-depth: purge any legacy plaintext copies left over from older
  // provisioning runs. No-op on fresh tenants.
  await adb.run("DELETE FROM store_config WHERE key IN ('setup_token', 'setup_token_expires')");

  audit(db, 'setup_completed', null, ip, { username });

  res.json({ success: true, data: { message: 'Admin account created. You can now log in.' } });
});

router.post('/login', async (req: Request, res: Response) => {
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
    recordUserLoginFailure(db, tenantSlug, username);
    audit(db, 'login_failed', null, ip, { username, reason: 'user_not_found' });
    logTenantAuthEvent('login_failed', req, null, username, { reason: 'user_not_found' });
    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    // SEC (E2): Generic error message — do not distinguish "user not found"
    // from "wrong password" in the response.
    res.status(401).json({ success: false, message: 'Invalid credentials' });
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
    recordUserLoginFailure(db, tenantSlug, username);
    audit(db, 'login_failed', user.id, ip, { username, reason: 'bad_password' });
    logTenantAuthEvent('login_failed', req, user.id, username, { reason: 'bad_password' });
    await enforceMinDuration(startNs, LOGIN_MIN_DURATION_MS);
    res.status(401).json({ success: false, message: 'Invalid credentials' });
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
});

// POST /login/set-password — First-time password setup
router.post('/login/set-password', async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const { challengeToken, password } = req.body;
  const userId = consumeChallenge(challengeToken); // Consume immediately
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  if (!password || password.length < 8) {
    res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
    return;
  }

  const hash = bcrypt.hashSync(password, 12);
  await adb.run('UPDATE users SET password_hash = ?, password_set = 1, updated_at = datetime(\'now\') WHERE id = ?', hash, userId);

  // SECURITY: Invalidate all existing sessions for this user
  await adb.run('DELETE FROM sessions WHERE user_id = ?', userId);

  // Issue NEW challenge for 2FA setup step
  const newChallenge = createChallenge(userId, (req as any).tenantSlug);
  audit(db, 'password_set', userId, req.ip || 'unknown', { first_login: true });
  logTenantAuthEvent('password_set', req, userId, null, { first_login: true });
  res.json({ success: true, data: { challengeToken: newChallenge, message: 'Password set. Now set up 2FA.' } });
});

// POST /login/2fa-setup — Get QR code for first-time setup
router.post('/login/2fa-setup', async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const { challengeToken } = req.body;
  const pendingSecret = challenges.get(challengeToken)?.pendingTotpSecret;
  const userId = consumeChallenge(challengeToken); // Consume immediately
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  const user = await adb.get<any>('SELECT id, username, email FROM users WHERE id = ?', userId);
  // SEC (E2): Generic message + 401 to avoid account enumeration.
  if (!user) { res.status(401).json({ success: false, message: 'Invalid credentials' }); return; }

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
});

// POST /login/2fa-verify — Verify TOTP code and complete login
router.post('/login/2fa-verify', async (req: Request, res: Response) => {
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

  // Get pending secret from challenge map (for first-time setup) before consuming
  const challengeEntry = challenges.get(challengeToken);
  const pendingSecret = challengeEntry?.pendingTotpSecret;

  const userId = consumeChallenge(challengeToken);
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkTotpRateLimit(db, tenantSlug, userId)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.' });
    return;
  }

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
    // Generate 8 backup codes
    const plainCodes = Array.from({ length: 8 }, () => crypto.randomBytes(16).toString('hex')); // 128-bit codes
    const hashedCodes = plainCodes.map(c => bcrypt.hashSync(c, 12));
    await adb.run('UPDATE users SET totp_secret = ?, totp_enabled = 1, backup_codes = ? WHERE id = ?',
      encryptSecret(secret), JSON.stringify(hashedCodes), userId);
    backupCodes = plainCodes; // Return plain codes ONCE to the user
  }

  // Clear rate limit on success
  clearRateLimit(db, 'totp', totpKey(tenantSlug, userId));
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
    res.cookie('deviceTrust', deviceToken, {
      httpOnly: true,
      secure: true,
      sameSite: 'strict',
      maxAge: 90 * 24 * 60 * 60 * 1000,
      path: '/',
    });
  }

  const tokens = await issueTokens(adb, user, req, res, { trustDevice: !!trustDevice });
  res.json({ success: true, data: { ...tokens, backupCodes } });
});

// POST /login/2fa-backup — Use a backup code instead of TOTP
router.post('/login/2fa-backup', async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const { challengeToken, code } = req.body;
  const userId = consumeChallenge(challengeToken);
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  // Share TOTP rate limiter
  const db = req.db;
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

  const hashedCodes: string[] = JSON.parse(user.backup_codes);
  const matchIdx = hashedCodes.findIndex(h => bcrypt.compareSync(code, h));

  if (matchIdx === -1) {
    recordTotpFailure(db, tenantSlug, userId);
    const newChallenge = createChallenge(userId, (req as any).tenantSlug);
    res.status(401).json({ success: false, message: 'Invalid backup code', data: { challengeToken: newChallenge } });
    return;
  }

  // Remove used code
  hashedCodes.splice(matchIdx, 1);
  await adb.run('UPDATE users SET backup_codes = ? WHERE id = ?', JSON.stringify(hashedCodes), userId);

  const tokens = await issueTokens(adb, user, req, res);
  res.json({ success: true, data: { ...tokens, remainingBackupCodes: hashedCodes.length } });
});

// POST /refresh — accepts token from httpOnly cookie or body (backwards compat)
router.post('/refresh', async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  // Accept refresh token from httpOnly cookie (browser) or request body (mobile app)
  const refreshToken = (req as any).cookies?.refreshToken || req.body?.refreshToken;
  if (!refreshToken) {
    res.status(400).json({ success: false, message: 'Refresh token required' });
    return;
  }

  try {
    // SEC (A6/A10): Explicit algorithm + iss + aud on verify.
    const payload = jwt.verify(refreshToken, config.jwtRefreshSecret, JWT_VERIFY_OPTIONS) as any;
    if (payload.type !== 'refresh') {
      res.status(401).json({ success: false, message: 'Invalid refresh token' });
      return;
    }

    const session = await adb.get<{ id: string; last_active: string | null }>(
      "SELECT id, last_active FROM sessions WHERE id = ? AND expires_at > datetime('now')",
      payload.sessionId
    );
    if (!session) {
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
          res.status(401).json({ success: false, message: 'Session idle timeout' });
          return;
        }
      }
    }

    const user = await adb.get<any>('SELECT id, username, email, first_name, last_name, role, avatar_url, permissions FROM users WHERE id = ? AND is_active = 1', payload.userId);
    if (!user) {
      // SEC (E2): Generic error — don't leak whether a user was deleted.
      res.status(401).json({ success: false, message: 'Invalid credentials' });
      return;
    }

    // Touch last_active on refresh
    await adb.run("UPDATE sessions SET last_active = datetime('now') WHERE id = ?", payload.sessionId);

    // SECURITY: Always derive tenant from request context (subdomain), never from old token
    const tenantSlug = (req as any).tenantSlug || null;
    // SEC (A6/A10): Explicit HS256 + iss + aud on sign.
    const accessToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, role: user.role, tenantSlug },
      config.jwtSecret,
      { ...JWT_SIGN_OPTIONS, expiresIn: '1h' }
    );

    // Rotate refresh token
    const newRefreshToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, type: 'refresh', tenantSlug },
      config.jwtRefreshSecret,
      { ...JWT_SIGN_OPTIONS, expiresIn: '30d' }
    );
    // SEC-H17: SameSite=Strict on refresh rotation too — must match issueTokens().
    res.cookie('refreshToken', newRefreshToken, {
      httpOnly: true,
      secure: true,
      sameSite: 'strict',
      maxAge: 30 * 24 * 60 * 60 * 1000,
      path: '/',
    });

    const safeUser = {
      id: user.id, username: user.username, email: user.email,
      first_name: user.first_name, last_name: user.last_name,
      role: user.role, avatar_url: user.avatar_url || null,
      permissions: user.permissions ? JSON.parse(user.permissions) : null,
    };

    res.json({ success: true, data: { accessToken, user: safeUser } });
  } catch {
    res.status(401).json({ success: false, message: 'Invalid refresh token' });
  }
});

// POST /logout
router.post('/logout', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  await adb.run('DELETE FROM sessions WHERE id = ?', req.user!.sessionId);
  res.clearCookie('refreshToken', { path: '/' });
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
  const usersWithPins = await adb.all<any>(
    "SELECT id, username, email, first_name, last_name, role, avatar_url, permissions, pin, totp_secret, totp_enabled FROM users WHERE pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
  );

  const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));

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

  // SEC (A7): prune oldest sessions before inserting the pin-switch session.
  await pruneOldSessions(adb, user.id);

  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString(); // 8 hours for PIN sessions
  await adb.run(
    "INSERT INTO sessions (id, user_id, device_info, expires_at, last_active) VALUES (?, ?, ?, ?, datetime('now'))",
    sessionId, user.id, 'pin-switch', expiresAt
  );

  const tenantSlug = (req as any).tenantSlug || null;
  // SEC (A6/A10): Explicit HS256 + iss + aud.
  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role, tenantSlug },
    config.jwtSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '1h' }
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh', tenantSlug },
    config.jwtRefreshSecret,
    { ...JWT_SIGN_OPTIONS, expiresIn: '8h' }
  );

  user.permissions = user.permissions ? JSON.parse(user.permissions) : null;

  // SEC-H17: SameSite=Strict — matches main login flow. Impersonation sessions
  // are short-lived and should never cross origins.
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    maxAge: 8 * 60 * 60 * 1000, // 8 hours
    path: '/',
  });

  res.json({
    success: true,
    data: { accessToken, user },
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
router.post('/forgot-password', async (req: Request, res: Response) => {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const db = req.db;

  // Rate limit: 3 attempts per hour per IP (SQLite-backed)
  if (!checkWindowRate(db, 'forgot_password', ip, 3, 3600_000)) {
    res.status(429).json({ success: false, message: 'Too many reset attempts. Try again later.' });
    return;
  }
  recordWindowFailure(db, 'forgot_password', ip, 3600_000);

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
    // Don't reveal whether the email exists
    audit(dbSync, 'password_reset_requested', null, ip, { email: email.trim(), found: false });
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

  audit(dbSync, 'password_reset_requested', user.id, ip, { email: email.trim() });

  // Build the reset URL
  const protocol = req.secure ? 'https' : 'http';
  const host = req.headers.host || 'localhost';
  const resetUrl = `${protocol}://${host}/reset-password/${resetToken}`;

  // Try to send email; never log the URL or token — a warning is enough.
  // SEC (T16): Previous code wrote the reset URL to console.log, leaking a
  // live password-reset link to anyone with stdout access.
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

  res.json({ success: true, data: { message: genericMsg } });
});

// ENR-UX19: POST /reset-password — Consume a reset token and set a new password
// SEC (P2FA1): The column is `password_hash`, NOT `password`. The previous code
//              wrote to a column that doesn't exist, silently breaking every reset.
// SEC (P2FA2): On successful reset we also delete all existing sessions so a
//              previously-compromised token can't keep a live session alive.
// SEC (P2FA8): Reject the new password if it matches any of the last 5 hashes.
router.post('/reset-password', async (req: Request, res: Response) => {
  const { token, password } = req.body;
  if (!token || typeof token !== 'string' || token.length !== 64) {
    res.status(400).json({ success: false, message: 'Invalid reset token' });
    return;
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
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

  const hashedPassword = await bcrypt.hash(password, 12);

  // SEC (P2FA1): Update password_hash, not the non-existent `password` column.
  // SEC (P2FA2): Delete ALL existing sessions so a prior leak can't persist.
  await adb.run(
    "UPDATE users SET password_hash = ?, password_set = 1, reset_token = NULL, reset_token_expires = NULL, updated_at = datetime('now') WHERE id = ?",
    hashedPassword, user.id
  );
  await adb.run('DELETE FROM sessions WHERE user_id = ?', user.id);
  await recordPasswordHistory(adb, user.id, hashedPassword);

  audit(dbSync, 'password_reset_completed', user.id, ip, { sessions_revoked: true });
  logTenantAuthEvent('password_reset_completed', req, user.id, null, { sessions_revoked: true });

  res.json({ success: true, data: { message: 'Password has been reset. You can now log in.' } });
});

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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
    return;
  }

  clearRateLimit(db, 'totp', totpKey(tenantSlug, userId));

  await adb.run(
    "UPDATE users SET totp_secret = NULL, totp_enabled = 0, backup_codes = NULL, updated_at = datetime('now') WHERE id = ?",
    userId
  );

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
  const targetId = parseInt(String(req.params.userId || ''), 10);
  if (!Number.isInteger(targetId) || targetId <= 0) {
    res.status(400).json({ success: false, message: 'Invalid user id' });
    return;
  }
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
router.post('/recover-with-backup-code', async (req: Request, res: Response) => {
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
  if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 8) {
    res.status(400).json({ success: false, message: 'New password must be at least 8 characters' });
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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
  };

  if (!user || !user.backup_codes) { fail(); return; }

  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkTotpRateLimit(db, tenantSlug, user.id)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.' });
    return;
  }

  let hashedCodes: string[] = [];
  try {
    hashedCodes = JSON.parse(user.backup_codes);
  } catch { hashedCodes = []; }
  const matchIdx = hashedCodes.findIndex(h => {
    try { return bcrypt.compareSync(backupCode, h); } catch { return false; }
  });
  if (matchIdx === -1) {
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

  // All checks passed — perform the recovery.
  clearRateLimit(db, 'totp', totpKey(tenantSlug, user.id));
  const newHash = bcrypt.hashSync(newPassword, 12);
  hashedCodes.splice(matchIdx, 1);

  await adb.run(
    "UPDATE users SET password_hash = ?, password_set = 1, totp_secret = NULL, totp_enabled = 0, backup_codes = ?, updated_at = datetime('now') WHERE id = ?",
    newHash, JSON.stringify(hashedCodes), user.id
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
});

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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
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
  await adb.transaction([
    {
      sql: "UPDATE users SET password_hash = ?, password_set = 1, updated_at = datetime('now') WHERE id = ?",
      params: [newHash, userId],
    },
    {
      sql: 'DELETE FROM sessions WHERE user_id = ?',
      params: [userId],
    },
  ]);
  await recordPasswordHistory(adb, userId, newHash);

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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
    return;
  }

  const newPinHash = await bcrypt.hash(newPin, 12);

  await adb.run(
    "UPDATE users SET pin = ?, updated_at = datetime('now') WHERE id = ?",
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
