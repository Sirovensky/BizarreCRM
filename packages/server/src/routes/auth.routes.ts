import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { generateSecret, verifySync } from 'otplib';
import QRCode from 'qrcode';
import { db } from '../db/connection.js';
import { config } from '../config.js';
import { authMiddleware } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';

// AES-256-GCM encryption for TOTP secrets (versioned keys for future rotation)
const ENCRYPTION_KEYS: Record<number, Buffer> = {
  1: crypto.createHash('sha256').update(config.jwtSecret + ':totp:v1').digest(),
};
const CURRENT_KEY_VERSION = 1;

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
const challenges = new Map<string, { userId: number; expires: number; pendingTotpSecret?: string }>();
const CHALLENGE_TTL = 5 * 60 * 1000;
const MAX_CHALLENGES = 10000;

function createChallenge(userId: number): string {
  // Evict oldest if over limit (DoS protection)
  if (challenges.size >= MAX_CHALLENGES) {
    const oldest = Array.from(challenges.entries()).sort((a, b) => a[1].expires - b[1].expires);
    for (let i = 0; i < Math.min(100, oldest.length); i++) challenges.delete(oldest[i][0]);
  }
  const token = uuidv4();
  challenges.set(token, { userId, expires: Date.now() + CHALLENGE_TTL });
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

// 2FA rate limiting
const totpFailures = new Map<number, { count: number; lockedUntil: number }>();

function checkTotpRateLimit(userId: number): boolean {
  const entry = totpFailures.get(userId);
  if (!entry) return true;
  if (Date.now() > entry.lockedUntil) { totpFailures.delete(userId); return true; }
  return entry.count < 5;
}

function recordTotpFailure(userId: number): void {
  const entry = totpFailures.get(userId);
  if (!entry) {
    totpFailures.set(userId, { count: 1, lockedUntil: Date.now() + 15 * 60 * 1000 });
  } else {
    entry.count++;
  }
}

// ---------------------------------------------------------------------------
// Simple in-memory rate limiter for PIN switch-user
// ---------------------------------------------------------------------------
const PIN_RATE_LIMIT = {
  maxAttempts: 5,
  windowMs: 15 * 60 * 1000, // 15 minutes
};

const pinFailures = new Map<string, { count: number; firstAttempt: number }>();

function checkPinRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = pinFailures.get(ip);
  if (!entry) return true;
  // Window expired — reset
  if (now - entry.firstAttempt > PIN_RATE_LIMIT.windowMs) {
    pinFailures.delete(ip);
    return true;
  }
  return entry.count < PIN_RATE_LIMIT.maxAttempts;
}

function recordPinFailure(ip: string): void {
  const now = Date.now();
  const entry = pinFailures.get(ip);
  if (!entry || now - entry.firstAttempt > PIN_RATE_LIMIT.windowMs) {
    pinFailures.set(ip, { count: 1, firstAttempt: now });
  } else {
    entry.count++;
  }
}

function clearPinFailures(ip: string): void {
  pinFailures.delete(ip);
}

// Periodically clean up stale entries (every 15 min)
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of pinFailures) {
    if (now - entry.firstAttempt > PIN_RATE_LIMIT.windowMs) {
      pinFailures.delete(ip);
    }
  }
}, PIN_RATE_LIMIT.windowMs);

// Helper: issue JWT tokens after successful auth
function issueTokens(user: any, req: Request, res: Response, options?: { trustDevice?: boolean }): { accessToken: string; refreshToken: string; user: any } {
  const trust = options?.trustDevice === true;
  const refreshDays = trust ? 90 : 30;
  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + refreshDays * 24 * 60 * 60 * 1000).toISOString();
  db.prepare('INSERT INTO sessions (id, user_id, device_info, expires_at) VALUES (?, ?, ?, ?)')
    .run(sessionId, user.id, req.headers['user-agent'] || 'unknown', expiresAt);

  const accessToken = jwt.sign({ userId: user.id, sessionId, role: user.role }, config.jwtSecret, { expiresIn: '1h' });
  const refreshToken = jwt.sign({ userId: user.id, sessionId, type: 'refresh' }, config.jwtRefreshSecret, { expiresIn: `${refreshDays}d` });

  // Set refresh token as httpOnly cookie
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: config.nodeEnv === 'production',
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
// Login rate limiting (same pattern as PIN)
const loginFailures = new Map<string, { count: number; firstAttempt: number }>();

function checkLoginRateLimit(ip: string): boolean {
  const entry = loginFailures.get(ip);
  if (!entry) return true;
  if (Date.now() - entry.firstAttempt > PIN_RATE_LIMIT.windowMs) { loginFailures.delete(ip); return true; }
  return entry.count < PIN_RATE_LIMIT.maxAttempts;
}

function recordLoginFailure(ip: string): void {
  const now = Date.now();
  const entry = loginFailures.get(ip);
  if (!entry || now - entry.firstAttempt > PIN_RATE_LIMIT.windowMs) {
    loginFailures.set(ip, { count: 1, firstAttempt: now });
  } else { entry.count++; }
}

router.post('/login', (req: Request, res: Response) => {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkLoginRateLimit(ip)) {
    res.status(429).json({ success: false, message: 'Too many login attempts. Try again in 15 minutes.' });
    return;
  }

  const { username, password } = req.body;
  if (!username) {
    res.status(400).json({ success: false, message: 'Username required' });
    return;
  }

  const user = db.prepare(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled, password_set FROM users WHERE username = ? AND is_active = 1'
  ).get(username) as any;

  if (!user) {
    recordLoginFailure(ip);
    audit('login_failed', null, ip, { username, reason: 'user_not_found' });
    res.status(401).json({ success: false, message: 'Invalid credentials' });
    return;
  }

  // User hasn't set a password yet (created by admin without one)
  if (!user.password_set || !user.password_hash) {
    const challengeToken = createChallenge(user.id);
    audit('login_password_setup', user.id, ip, { username });
    res.json({
      success: true,
      data: { challengeToken, requiresPasswordSetup: true },
    });
    return;
  }

  if (!password || !bcrypt.compareSync(password, user.password_hash)) {
    recordLoginFailure(ip);
    audit('login_failed', user.id, ip, { username, reason: 'bad_password' });
    res.status(401).json({ success: false, message: 'Invalid credentials' });
    return;
  }

  const challengeToken = createChallenge(user.id);

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
router.post('/login/set-password', (req: Request, res: Response) => {
  const { challengeToken, password } = req.body;
  const userId = consumeChallenge(challengeToken); // Consume immediately
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  if (!password || password.length < 8) {
    res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
    return;
  }

  const hash = bcrypt.hashSync(password, 12);
  db.prepare('UPDATE users SET password_hash = ?, password_set = 1, updated_at = datetime(\'now\') WHERE id = ?').run(hash, userId);

  // Issue NEW challenge for 2FA setup step
  const newChallenge = createChallenge(userId);
  audit('password_set', userId, req.ip || 'unknown', { first_login: true });
  res.json({ success: true, data: { challengeToken: newChallenge, message: 'Password set. Now set up 2FA.' } });
});

// POST /login/2fa-setup — Get QR code for first-time setup
router.post('/login/2fa-setup', async (req: Request, res: Response) => {
  const { challengeToken } = req.body;
  const pendingSecret = challenges.get(challengeToken)?.pendingTotpSecret;
  const userId = consumeChallenge(challengeToken); // Consume immediately
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  const user = db.prepare('SELECT id, username, email FROM users WHERE id = ?').get(userId) as any;
  if (!user) { res.status(404).json({ success: false, message: 'User not found' }); return; }

  // Generate new TOTP secret
  const secret = generateSecret();
  const account = encodeURIComponent(user.email || user.username);
  const otpauth = `otpauth://totp/Bizarre%20CRM:${account}?secret=${secret}&issuer=Bizarre%20CRM`;

  try {
    const qrDataUrl = await QRCode.toDataURL(otpauth);
    // Issue new challenge with pending TOTP secret
    const newChallenge = createChallenge(userId);
    const newEntry = challenges.get(newChallenge);
    if (newEntry) newEntry.pendingTotpSecret = secret;

    res.json({ success: true, data: { qr: qrDataUrl, secret, manualEntry: secret, challengeToken: newChallenge } });
  } catch {
    // Issue recovery challenge so user can retry without re-entering password
    const recoveryChallenge = createChallenge(userId);
    const recoveryEntry = challenges.get(recoveryChallenge);
    if (recoveryEntry) recoveryEntry.pendingTotpSecret = secret;
    res.status(500).json({ success: false, message: 'Failed to generate QR code. Please try again.', data: { challengeToken: recoveryChallenge } });
  }
});

// POST /login/2fa-verify — Verify TOTP code and complete login
router.post('/login/2fa-verify', (req: Request, res: Response) => {
  // IP-based rate limit (reuse login rate limiter)
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkLoginRateLimit(ip)) {
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

  if (!checkTotpRateLimit(userId)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.' });
    return;
  }

  const user = db.prepare(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled FROM users WHERE id = ? AND is_active = 1'
  ).get(userId) as any;

  // Use pending secret (first-time setup) or existing encrypted secret from DB
  const secret = pendingSecret || (user.totp_secret ? decryptSecret(user.totp_secret) : null);
  if (!user || !secret) {
    res.status(401).json({ success: false, message: 'TOTP not configured' });
    return;
  }

  const result = verifySync({ token: code, secret });
  const isValid = result && (result as any).valid === true;
  if (!isValid) {
    recordTotpFailure(userId);
    const newChallenge = createChallenge(userId);
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
    db.prepare('UPDATE users SET totp_secret = ?, totp_enabled = 1, backup_codes = ? WHERE id = ?')
      .run(encryptSecret(secret), JSON.stringify(hashedCodes), userId);
    backupCodes = plainCodes; // Return plain codes ONCE to the user
  }

  // Clear rate limit on success
  totpFailures.delete(userId);
  audit('login_success', userId, req.ip || 'unknown', { method: backupCodes ? '2fa_setup' : '2fa_verify' });

  const tokens = issueTokens(user, req, res, { trustDevice: !!trustDevice });
  res.json({ success: true, data: { ...tokens, backupCodes } });
});

// POST /login/2fa-backup — Use a backup code instead of TOTP
router.post('/login/2fa-backup', (req: Request, res: Response) => {
  const { challengeToken, code } = req.body;
  const userId = consumeChallenge(challengeToken);
  if (!userId) { res.status(401).json({ success: false, message: 'Challenge expired' }); return; }

  // Share TOTP rate limiter
  if (!checkTotpRateLimit(userId)) {
    res.status(429).json({ success: false, message: 'Too many failed attempts. Try again in 15 minutes.' });
    return;
  }

  const user = db.prepare(
    'SELECT id, username, email, password_hash, first_name, last_name, role, avatar_url, permissions, totp_secret, totp_enabled, backup_codes FROM users WHERE id = ? AND is_active = 1'
  ).get(userId) as any;

  if (!user || !user.backup_codes) {
    res.status(401).json({ success: false, message: 'No backup codes available' });
    return;
  }

  const hashedCodes: string[] = JSON.parse(user.backup_codes);
  const matchIdx = hashedCodes.findIndex(h => bcrypt.compareSync(code, h));

  if (matchIdx === -1) {
    recordTotpFailure(userId);
    const newChallenge = createChallenge(userId);
    res.status(401).json({ success: false, message: 'Invalid backup code', data: { challengeToken: newChallenge } });
    return;
  }

  // Remove used code
  hashedCodes.splice(matchIdx, 1);
  db.prepare('UPDATE users SET backup_codes = ? WHERE id = ?').run(JSON.stringify(hashedCodes), userId);

  const tokens = issueTokens(user, req, res);
  res.json({ success: true, data: { ...tokens, remainingBackupCodes: hashedCodes.length } });
});

// POST /refresh — accepts token from httpOnly cookie or body (backwards compat)
router.post('/refresh', (req: Request, res: Response) => {
  const refreshToken = (req as any).cookies?.refreshToken;
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

    const session = db.prepare('SELECT id FROM sessions WHERE id = ? AND expires_at > datetime(\'now\')').get(payload.sessionId) as any;
    if (!session) {
      res.status(401).json({ success: false, message: 'Session expired' });
      return;
    }

    const user = db.prepare('SELECT id, role FROM users WHERE id = ? AND is_active = 1').get(payload.userId) as any;
    if (!user) {
      res.status(401).json({ success: false, message: 'User not found' });
      return;
    }

    const accessToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, role: user.role },
      config.jwtSecret,
      { expiresIn: '1h' }
    );

    // Rotate refresh token
    const newRefreshToken = jwt.sign(
      { userId: user.id, sessionId: payload.sessionId, type: 'refresh' },
      config.jwtRefreshSecret,
      { expiresIn: '30d' }
    );
    res.cookie('refreshToken', newRefreshToken, {
      httpOnly: true,
      secure: config.nodeEnv === 'production',
      sameSite: 'lax',
      maxAge: 30 * 24 * 60 * 60 * 1000,
      path: '/',
    });

    res.json({ success: true, data: { accessToken } });
  } catch {
    res.status(401).json({ success: false, message: 'Invalid refresh token' });
  }
});

// POST /logout
router.post('/logout', authMiddleware, (req: Request, res: Response) => {
  db.prepare('DELETE FROM sessions WHERE id = ?').run(req.user!.sessionId);
  res.clearCookie('refreshToken', { path: '/' });
  res.json({ success: true, data: { message: 'Logged out' } });
});

// POST /switch-user (rate-limited, requires existing auth session)
router.post('/switch-user', authMiddleware, (req: Request, res: Response) => {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!checkPinRateLimit(ip)) {
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
  const usersWithPins = db.prepare(
    "SELECT id, username, email, first_name, last_name, role, avatar_url, permissions, pin FROM users WHERE pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
  ).all() as any[];

  const user = usersWithPins.find(u => bcrypt.compareSync(pin, u.pin));

  if (!user) {
    recordPinFailure(ip);
    audit('pin_switch_failed', null, ip, { reason: 'invalid_pin' });
    res.status(401).json({ success: false, message: 'Invalid PIN' });
    return;
  }
  // Remove pin from user object before returning
  delete user.pin;

  // Successful auth — clear failures for this IP
  clearPinFailures(ip);
  audit('pin_switch_success', user.id, ip, { switched_to: user.username });

  const sessionId = uuidv4();
  const expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString(); // 8 hours for PIN sessions
  db.prepare('INSERT INTO sessions (id, user_id, device_info, expires_at) VALUES (?, ?, ?, ?)')
    .run(sessionId, user.id, 'pin-switch', expiresAt);

  const accessToken = jwt.sign(
    { userId: user.id, sessionId, role: user.role },
    config.jwtSecret,
    { expiresIn: '1h' }
  );
  const refreshToken = jwt.sign(
    { userId: user.id, sessionId, type: 'refresh' },
    config.jwtRefreshSecret,
    { expiresIn: '8h' }
  );

  user.permissions = user.permissions ? JSON.parse(user.permissions) : null;

  // Set refresh token as httpOnly cookie (matching main login flow)
  res.cookie('refreshToken', refreshToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
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
router.post('/verify-pin', authMiddleware, (req: Request, res: Response) => {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!checkPinRateLimit(ip)) {
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

  const row = db.prepare(
    "SELECT pin FROM users WHERE id = ? AND pin IS NOT NULL AND pin LIKE '$2%' AND is_active = 1"
  ).get(userId) as { pin: string } | undefined;

  if (!row || !bcrypt.compareSync(pin, row.pin)) {
    recordPinFailure(ip);
    audit('pin_verify_failed', userId, ip, { reason: 'invalid_pin' });
    res.status(401).json({ success: false, message: 'Invalid PIN' });
    return;
  }

  clearPinFailures(ip);
  audit('pin_verify_success', userId, ip, {});
  res.json({ success: true, data: { verified: true } });
});

// GET /me
router.get('/me', authMiddleware, (req: Request, res: Response) => {
  res.json({ success: true, data: { user: req.user } });
});

export default router;
