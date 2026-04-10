import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { generateSecret, verifySync } from 'otplib';
import QRCode from 'qrcode';
import { config } from '../config.js';
import { authMiddleware } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { logTenantAuthEvent } from '../utils/masterAudit.js';
import { checkWindowRate, recordWindowFailure, clearRateLimit, checkLockoutRate, recordLockoutFailure, cleanupExpiredEntries } from '../utils/rateLimiter.js';
import type { AsyncDb } from '../db/async-db.js';

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

// Helper: issue JWT tokens after successful auth
async function issueTokens(adb: AsyncDb, user: any, req: Request, res: Response, options?: { trustDevice?: boolean }): Promise<{ accessToken: string; refreshToken: string; user: any }> {
  const trust = options?.trustDevice === true;
  const refreshDays = trust ? 90 : 30;
  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + refreshDays * 24 * 60 * 60 * 1000).toISOString();
  await adb.run('INSERT INTO sessions (id, user_id, device_info, expires_at) VALUES (?, ?, ?, ?)',
    sessionId, user.id, req.headers['user-agent'] || 'unknown', expiresAt);

  const tenantSlug = (req as any).tenantSlug || null;
  const accessToken = jwt.sign({ userId: user.id, sessionId, role: user.role, tenantSlug }, config.jwtSecret, { expiresIn: '1h' });
  const refreshToken = jwt.sign({ userId: user.id, sessionId, type: 'refresh', tenantSlug }, config.jwtRefreshSecret, { expiresIn: `${refreshDays}d` });

  // Set refresh token as httpOnly cookie (always secure — server uses HTTPS with self-signed certs)
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
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

// POST /setup — First-time shop setup: create the initial admin account
// Requires a valid setup_token (generated during tenant provisioning, stored in store_config)
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

  // Validate setup token
  const [storedTokenRow, tokenExpiryRow] = await Promise.all([
    adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'setup_token'"),
    adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'setup_token_expires'"),
  ]);
  const storedToken = storedTokenRow?.value;
  const tokenExpiry = tokenExpiryRow?.value;

  if (!storedToken) {
    res.status(403).json({ success: false, message: 'Setup not available. Contact your administrator.' });
    return;
  }
  // Timing-safe comparison to prevent token-guessing via response-time analysis
  const tokensMatch = setup_token && storedToken &&
    typeof setup_token === 'string' && typeof storedToken === 'string' &&
    setup_token.length === storedToken.length &&
    crypto.timingSafeEqual(Buffer.from(setup_token), Buffer.from(storedToken));
  if (!tokensMatch) {
    res.status(403).json({ success: false, message: 'Invalid setup link. Request a new one from your administrator.' });
    return;
  }
  if (tokenExpiry && new Date(tokenExpiry) < new Date()) {
    res.status(403).json({ success: false, message: 'Setup link has expired. Request a new one from your administrator.' });
    return;
  }

  if (!username || typeof username !== 'string' || username.length < 3) {
    res.status(400).json({ success: false, message: 'Username must be at least 3 characters' });
    return;
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
    return;
  }

  const hash = bcrypt.hashSync(password, 12);
  const pinHash = bcrypt.hashSync('1234', 12);

  await adb.run(`
    INSERT INTO users (username, email, password_hash, password_set, pin, first_name, last_name, role, is_active, created_at, updated_at)
    VALUES (?, ?, ?, 1, ?, '', '', 'admin', 1, datetime('now'), datetime('now'))
  `, username, email || `${username}@shop.local`, hash, pinHash);

  // Consume the setup token (one-time use)
  await adb.run("DELETE FROM store_config WHERE key IN ('setup_token', 'setup_token_expires')");

  res.json({ success: true, data: { message: 'Admin account created. You can now log in.' } });
});

router.post('/login', async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkLoginRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many login attempts. Try again in 15 minutes.' });
    return;
  }

  const { username, password } = req.body;
  if (!username) {
    res.status(400).json({ success: false, message: 'Username required' });
    return;
  }

  // Check username-based rate limit (prevents credential stuffing against a single account)
  const tenantSlug = (req as any).tenantSlug || null;
  if (!checkUserLoginRateLimit(db, tenantSlug, username)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts for this account. Try again in 30 minutes.' });
    return;
  }

  const user = await adb.get<any>(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled, password_set FROM users WHERE username = ? AND is_active = 1',
    username
  );

  // Constant-time: always run bcrypt even for non-existent users to prevent timing oracle
  // $2b$12$ is a valid bcrypt hash prefix with 12 rounds — matches real hash cost
  const DUMMY_HASH = '$2b$12$LJ3m4ys3Lhmd0tSwUaGgmeoS89CINnom5eSvnfmEFYKaSwVKbHlrS';
  const hashToCheck = user?.password_hash || DUMMY_HASH;
  const passwordValid = password ? bcrypt.compareSync(password, hashToCheck) : false;

  if (!user) {
    recordLoginFailure(db, ip);
    recordUserLoginFailure(db, tenantSlug, username);
    audit(db, 'login_failed', null, ip, { username, reason: 'user_not_found' });
    logTenantAuthEvent('login_failed', req, null, username, { reason: 'user_not_found' });
    res.status(401).json({ success: false, message: 'Invalid credentials' });
    return;
  }

  // User hasn't set a password yet (created by admin without one)
  if (!user.password_set || !user.password_hash) {
    const challengeToken = createChallenge(user.id, tenantSlug);
    audit(db, 'login_password_setup', user.id, ip, { username });
    logTenantAuthEvent('login_password_setup', req, user.id, username, {});
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
    res.status(401).json({ success: false, message: 'Invalid credentials' });
    return;
  }

  // Check device trust cookie — if valid, skip 2FA entirely
  const deviceTrustCookie = req.cookies?.deviceTrust;
  if (user.totp_enabled && deviceTrustCookie) {
    try {
      const payload = jwt.verify(deviceTrustCookie, deviceTrustKey) as any;
      if (payload.type === 'device_trust' && payload.userId === user.id) {
        // Trusted device — issue tokens directly, skip 2FA
        audit(db, 'login_success', user.id, ip, { method: '2fa_trusted_device' });
        logTenantAuthEvent('login_success', req, user.id, user.username, { method: '2fa_trusted_device' });
        const tokens = await issueTokens(adb, user, req, res, { trustDevice: true });
        res.json({ success: true, data: { ...tokens, trustedDevice: true } });
        return;
      }
    } catch {
      // Invalid/expired trust cookie — fall through to normal 2FA flow
      res.clearCookie('deviceTrust', { path: '/' });
    }
  }

  const challengeToken = createChallenge(user.id, tenantSlug);

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
  if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }

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

  // Set device trust cookie if requested — allows skipping 2FA on future logins
  if (trustDevice) {
    const deviceToken = jwt.sign(
      { userId: user.id, type: 'device_trust', ua: (req.headers['user-agent'] || '').slice(0, 100) },
      deviceTrustKey,
      { expiresIn: '90d' }
    );
    res.cookie('deviceTrust', deviceToken, {
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
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
    const payload = jwt.verify(refreshToken, config.jwtRefreshSecret) as any;
    if (payload.type !== 'refresh') {
      res.status(401).json({ success: false, message: 'Invalid refresh token' });
      return;
    }

    const session = await adb.get<any>('SELECT id FROM sessions WHERE id = ? AND expires_at > datetime(\'now\')', payload.sessionId);
    if (!session) {
      res.status(401).json({ success: false, message: 'Session expired' });
      return;
    }

    const user = await adb.get<any>('SELECT id, username, email, first_name, last_name, role, avatar_url, permissions FROM users WHERE id = ? AND is_active = 1', payload.userId);
    if (!user) {
      res.status(401).json({ success: false, message: 'User not found' });
      return;
    }

    // SECURITY: Always derive tenant from request context (subdomain), never from old token
    const tenantSlug = (req as any).tenantSlug || null;
    const accessToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, role: user.role, tenantSlug },
      config.jwtSecret,
      { expiresIn: '1h' }
    );

    // Rotate refresh token
    const newRefreshToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, type: 'refresh', tenantSlug },
      config.jwtRefreshSecret,
      { expiresIn: '30d' }
    );
    res.cookie('refreshToken', newRefreshToken, {
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
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
router.post('/switch-user', authMiddleware, async (req: Request, res: Response) => {
  const adb = req.asyncDb;
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!checkPinRateLimit(db, ip)) {
    res.status(429).json({ success: false, message: 'Too many failed PIN attempts. Try again in 15 minutes.' });
    return;
  }

  const { pin } = req.body;
  if (!pin || typeof pin !== 'string' || pin.length < 1 || pin.length > 20) {
    res.status(400).json({ success: false, message: 'Valid PIN required (1-20 characters)' });
    return;
  }

  // Fetch all active users with PINs and compare via bcrypt (PINs are hashed)
  // Only accept bcrypt-hashed PINs (reject legacy plaintext)
  const usersWithPins = await adb.all<any>(
    "SELECT id, username, email, first_name, last_name, role, avatar_url, permissions, pin FROM users WHERE pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
  );

  const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));

  if (!user) {
    recordPinFailure(db, ip);
    audit(db, 'pin_switch_failed', null, ip, { reason: 'invalid_pin' });
    logTenantAuthEvent('pin_switch_failed', req, null, null, { reason: 'invalid_pin' });
    res.status(401).json({ success: false, message: 'Invalid PIN' });
    return;
  }
  // Remove pin from user object before returning
  delete user.pin;

  // Successful auth — clear failures for this IP
  clearPinFailures(db, ip);
  audit(db, 'pin_switch_success', user.id, ip, { switched_to: user.username });
  logTenantAuthEvent('pin_switch_success', req, user.id, user.username, { switched_to: user.username });

  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString(); // 8 hours for PIN sessions
  await adb.run('INSERT INTO sessions (id, user_id, device_info, expires_at) VALUES (?, ?, ?, ?)',
    sessionId, user.id, 'pin-switch', expiresAt);

  const tenantSlug = (req as any).tenantSlug || null;
  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role, tenantSlug },
    config.jwtSecret,
    { expiresIn: '1h' }
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh', tenantSlug },
    config.jwtRefreshSecret,
    { expiresIn: '8h' }
  );

  user.permissions = user.permissions ? JSON.parse(user.permissions) : null;

  // Set refresh token as httpOnly cookie (matching main login flow; always secure — HTTPS with self-signed certs)
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
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

  // Try to send email; fall back to console logging
  try {
    const { sendEmail } = await import('../services/email.js');
    const sent = await sendEmail(dbSync, {
      to: user.email,
      subject: 'Password Reset — Bizarre CRM',
      html: `<p>Hi ${user.username},</p><p>Click the link below to reset your password. This link expires in 1 hour.</p><p><a href="${resetUrl}">${resetUrl}</a></p><p>If you didn't request this, you can safely ignore this email.</p>`,
    });
    if (!sent) {
      console.log(`[Auth] Password reset link (SMTP not configured): ${resetUrl}`);
    }
  } catch {
    console.log(`[Auth] Password reset link (email failed): ${resetUrl}`);
  }

  res.json({ success: true, data: { message: genericMsg } });
});

// ENR-UX19: POST /reset-password — Consume a reset token and set a new password
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

  const hashedPassword = await bcrypt.hash(password, 12);
  await adb.run(
    'UPDATE users SET password = ?, reset_token = NULL, reset_token_expires = NULL, updated_at = datetime(\'now\') WHERE id = ?',
    hashedPassword, user.id
  );

  audit(dbSync, 'password_reset_completed', user.id, ip, {});
  logTenantAuthEvent('password_reset_completed', req, user.id, null, {});

  res.json({ success: true, data: { message: 'Password has been reset. You can now log in.' } });
});

// GET /me
router.get('/me', authMiddleware, (req: Request, res: Response) => {
  res.json({ success: true, data: req.user });
});

export default router;
