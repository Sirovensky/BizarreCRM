/**
 * Super Admin API Routes
 *
 * Accessible at /super-admin/api/
 * Separate auth system from tenant auth (different JWT secret, different 2FA)
 * Maximum security: rate limiting, audit logging, session tracking
 */
import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import QRCode from 'qrcode';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { provisionTenant, suspendTenant, activateTenant, deleteTenant, listTenants } from '../services/tenant-provisioning.js';
import { getTenantDb, getPoolStats, closeAllTenantDbs } from '../db/tenant-pool.js';

const router = Router();
type AnyRow = Record<string, any>;

// ─── Guards ─────────────────────────────────────────────────────────

router.use((_req, res, next) => {
  if (!config.multiTenant) {
    return res.status(404).json({ success: false, message: 'Multi-tenant mode is not enabled' });
  }
  next();
});

// ─── TOTP Encryption (same pattern as tenant auth) ──────────────────

function deriveKey(): Buffer {
  return crypto.createHash('sha256').update(config.superAdminSecret + ':totp:superadmin').digest();
}

function encryptTotp(secret: string): { enc: string; iv: string; tag: string } {
  const key = deriveKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  let encrypted = cipher.update(secret, 'utf8', 'hex');
  encrypted += cipher.final('hex');
  return { enc: encrypted, iv: iv.toString('hex'), tag: (cipher as any).getAuthTag().toString('hex') };
}

function decryptTotp(enc: string, iv: string, tag: string): string {
  const key = deriveKey();
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'hex'));
  (decipher as any).setAuthTag(Buffer.from(tag, 'hex'));
  let decrypted = decipher.update(enc, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}

// ─── Rate Limiting ──────────────────────────────────────────────────

const loginAttempts = new Map<string, { count: number; resetAt: number }>();
const MAX_LOGIN_ATTEMPTS = 3; // Very strict for super admin
const LOCKOUT_DURATION = 30 * 60 * 1000; // 30 minutes

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of loginAttempts) { if (v.resetAt < now) loginAttempts.delete(k); }
}, 5 * 60 * 1000);

function checkRateLimit(ip: string): boolean {
  const entry = loginAttempts.get(ip);
  if (entry && entry.resetAt > Date.now() && entry.count >= MAX_LOGIN_ATTEMPTS) return false;
  return true;
}

function recordFailure(ip: string): void {
  const entry = loginAttempts.get(ip);
  if (entry && entry.resetAt > Date.now()) {
    entry.count++;
  } else {
    loginAttempts.set(ip, { count: 1, resetAt: Date.now() + LOCKOUT_DURATION });
  }
}

function clearFailures(ip: string): void {
  loginAttempts.delete(ip);
}

// ─── Audit Logging ──────────────────────────────────────────────────

function auditLog(action: string, adminId: number | null, ip: string, details?: any): void {
  const masterDb = getMasterDb();
  if (!masterDb) return;
  try {
    masterDb.prepare(
      'INSERT INTO master_audit_log (super_admin_id, action, details, ip_address) VALUES (?, ?, ?, ?)'
    ).run(adminId, action, details ? JSON.stringify(details) : null, ip);
  } catch (err) { console.error('[SuperAdmin Audit]', err); }
}

// ─── Challenge Tokens (in-memory, short-lived) ──────────────────────

interface Challenge {
  adminId: number;
  expires: number;
  pendingTotpSecret?: string; // Only during 2FA setup
}

const challenges = new Map<string, Challenge>();

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of challenges) { if (v.expires < now) challenges.delete(k); }
}, 60_000);

function createChallenge(adminId: number, pendingTotpSecret?: string): string {
  const token = crypto.randomBytes(32).toString('hex');
  challenges.set(token, { adminId, expires: Date.now() + 5 * 60 * 1000, pendingTotpSecret });
  return token;
}

function consumeChallenge(token: string): Challenge | null {
  const entry = challenges.get(token);
  if (!entry || entry.expires < Date.now()) { challenges.delete(token); return null; }
  challenges.delete(token);
  return entry;
}

// ─── Session Management ─────────────────────────────────────────────

function createSession(masterDb: any, adminId: number, ip: string, userAgent: string): string {
  const sessionId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString(); // 4 hours
  masterDb.prepare(
    'INSERT INTO super_admin_sessions (id, super_admin_id, ip_address, user_agent, expires_at) VALUES (?, ?, ?, ?, ?)'
  ).run(sessionId, adminId, ip, userAgent?.substring(0, 200) || '', expiresAt);
  return sessionId;
}

// ─── Auth Middleware ────────────────────────────────────────────────

function superAdminAuth(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ success: false, message: 'Authentication required' });
    return;
  }

  const token = authHeader.substring(7);
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, message: 'Master DB unavailable' }); return; }

  try {
    const payload = jwt.verify(token, config.superAdminSecret) as {
      superAdminId: number; sessionId: string; role: 'super_admin';
    };

    if (payload.role !== 'super_admin') {
      res.status(403).json({ success: false, message: 'Super admin access required' });
      return;
    }

    // Verify session is still valid
    const session = masterDb.prepare(
      "SELECT id FROM super_admin_sessions WHERE id = ? AND super_admin_id = ? AND expires_at > datetime('now')"
    ).get(payload.sessionId, payload.superAdminId) as any;

    if (!session) {
      res.status(401).json({ success: false, message: 'Session expired' });
      return;
    }

    // Verify admin still active
    const admin = masterDb.prepare('SELECT id, username FROM super_admins WHERE id = ? AND is_active = 1').get(payload.superAdminId) as any;
    if (!admin) {
      res.status(401).json({ success: false, message: 'Account deactivated' });
      return;
    }

    req.superAdmin = { superAdminId: admin.id, username: admin.username, role: 'super_admin' };
    next();
  } catch {
    res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }
}

// ═══════════════════════════════════════════════════════════════════
// PUBLIC ROUTES (no auth)
// ═══════════════════════════════════════════════════════════════════

// POST /login — Step 1: verify password, return challenge
router.post('/login', async (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Master DB unavailable' });

  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!checkRateLimit(ip)) {
    auditLog('super_admin_login_rate_limited', null, ip);
    return res.status(429).json({ success: false, message: 'Too many attempts. Try again in 30 minutes.' });
  }

  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ success: false, message: 'Credentials required' });

  // Length limits (prevent bcrypt DoS)
  if (typeof password !== 'string' || password.length > 128) {
    return res.status(400).json({ success: false, message: 'Invalid credentials' });
  }

  const admin = masterDb.prepare(
    'SELECT * FROM super_admins WHERE username = ? AND is_active = 1'
  ).get(username) as AnyRow | undefined;

  // Always run bcrypt.compare even when admin not found to prevent timing oracle
  // (attacker cannot distinguish "user not found" from "wrong password" via response time)
  const DUMMY_HASH = '$2a$12$LJ3m4ys3Rl4gTMGaUpVWaeOpMxDkx5JH3gXsIQr7gJSNVMmOG0OO2';

  if (!admin) {
    await bcrypt.compare(password, DUMMY_HASH);
    recordFailure(ip);
    auditLog('super_admin_login_failed', null, ip, { username, reason: 'user_not_found' });
    return res.status(401).json({ success: false, message: 'Invalid credentials' });
  }

  // Check account lock
  if (admin.locked_until && new Date(admin.locked_until) > new Date()) {
    auditLog('super_admin_login_locked', admin.id, ip);
    return res.status(423).json({ success: false, message: 'Account temporarily locked. Contact another super admin.' });
  }

  const valid = await bcrypt.compare(password, admin.password_hash);
  if (!valid) {
    recordFailure(ip);
    const fails = (admin.failed_login_count || 0) + 1;
    const updates: any[] = [fails];
    let lockUntil: string | null = null;
    if (fails >= 5) {
      lockUntil = new Date(Date.now() + 60 * 60 * 1000).toISOString(); // Lock 1 hour
      updates.push(lockUntil);
      masterDb.prepare('UPDATE super_admins SET failed_login_count = ?, locked_until = ? WHERE id = ?').run(fails, lockUntil, admin.id);
    } else {
      masterDb.prepare('UPDATE super_admins SET failed_login_count = ? WHERE id = ?').run(fails, admin.id);
    }
    auditLog('super_admin_login_failed', admin.id, ip, { username, attempt: fails, locked: !!lockUntil });
    return res.status(401).json({ success: false, message: 'Invalid credentials' });
  }

  // Password OK — check if password setup needed
  if (!admin.password_set) {
    const challengeToken = createChallenge(admin.id);
    auditLog('super_admin_password_setup_required', admin.id, ip);
    return res.json({ success: true, data: { challengeToken, requiresPasswordSetup: true } });
  }

  // Check if 2FA is set up
  if (!admin.totp_enabled) {
    const challengeToken = createChallenge(admin.id);
    auditLog('super_admin_2fa_setup_required', admin.id, ip);
    return res.json({ success: true, data: { challengeToken, requires2faSetup: true } });
  }

  // Password OK, 2FA enabled — return challenge for TOTP verification
  const challengeToken = createChallenge(admin.id);
  auditLog('super_admin_login_challenge', admin.id, ip);
  res.json({ success: true, data: { challengeToken, totpEnabled: true } });
});

// POST /login/set-password — First-time password setup
router.post('/login/set-password', async (req: Request, res: Response) => {
  const { challengeToken, password } = req.body;
  const challenge = consumeChallenge(challengeToken);
  if (!challenge) return res.status(401).json({ success: false, message: 'Invalid or expired challenge' });

  if (!password || typeof password !== 'string' || password.length < 10) {
    return res.status(400).json({ success: false, message: 'Password must be at least 10 characters' });
  }
  if (password.length > 128) {
    return res.status(400).json({ success: false, message: 'Password too long' });
  }

  const masterDb = getMasterDb()!;
  const hash = await bcrypt.hash(password, 14); // Higher cost for super admin
  masterDb.prepare('UPDATE super_admins SET password_hash = ?, password_set = 1, updated_at = datetime(?) WHERE id = ?')
    .run(hash, new Date().toISOString(), challenge.adminId);

  const newChallenge = createChallenge(challenge.adminId);
  const ip = req.ip || 'unknown';
  auditLog('super_admin_password_set', challenge.adminId, ip);

  res.json({ success: true, data: { challengeToken: newChallenge, requires2faSetup: true } });
});

// POST /login/2fa-setup — Generate TOTP secret + QR code
router.post('/login/2fa-setup', async (req: Request, res: Response) => {
  const { challengeToken } = req.body;
  const challenge = consumeChallenge(challengeToken);
  if (!challenge) return res.status(401).json({ success: false, message: 'Invalid or expired challenge' });

  const masterDb = getMasterDb()!;
  const admin = masterDb.prepare('SELECT username FROM super_admins WHERE id = ?').get(challenge.adminId) as any;

  // Generate a proper random secret (20 bytes = 160 bits, standard for TOTP)
  const secretBytes = crypto.randomBytes(20);
  // Proper RFC 4648 Base32 encoding
  const base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let base32 = '';
  let bits = 0;
  let value = 0;
  for (const byte of secretBytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      base32 += base32Chars[(value >> bits) & 0x1f];
    }
  }
  if (bits > 0) {
    base32 += base32Chars[(value << (5 - bits)) & 0x1f];
  }

  const issuer = 'BizarreCRM Super Admin';
  const otpauthUrl = `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(admin.username)}?secret=${base32}&issuer=${encodeURIComponent(issuer)}&digits=6&period=30`;
  // Generate QR code locally as data URL — NEVER send TOTP secret to external service
  let qrDataUrl: string;
  try {
    qrDataUrl = await QRCode.toDataURL(otpauthUrl, { width: 200, margin: 2 });
  } catch {
    qrDataUrl = ''; // Fallback: user can enter secret manually
  }

  // Store pending secret in new challenge (not in DB yet — only after verification)
  const newChallenge = createChallenge(challenge.adminId, base32);

  const ip = req.ip || 'unknown';
  auditLog('super_admin_2fa_setup_started', challenge.adminId, ip);

  res.json({
    success: true,
    data: { challengeToken: newChallenge, qr: qrDataUrl, secret: base32, manualEntry: base32 },
  });
});

// POST /login/2fa-verify — Verify TOTP code and complete login
router.post('/login/2fa-verify', (req: Request, res: Response) => {
  const { challengeToken, code } = req.body;
  const challenge = consumeChallenge(challengeToken);
  if (!challenge) return res.status(401).json({ success: false, message: 'Invalid or expired challenge' });

  if (!code || typeof code !== 'string' || code.length !== 6 || !/^\d{6}$/.test(code)) {
    return res.status(400).json({ success: false, message: 'Enter a 6-digit code' });
  }

  const masterDb = getMasterDb()!;
  const admin = masterDb.prepare('SELECT * FROM super_admins WHERE id = ? AND is_active = 1').get(challenge.adminId) as any;
  if (!admin) return res.status(401).json({ success: false, message: 'Account not found' });

  let totpSecret: string;

  if (challenge.pendingTotpSecret) {
    // First-time setup — verify against the pending secret
    totpSecret = challenge.pendingTotpSecret;
  } else if (admin.totp_enabled && admin.totp_secret_enc) {
    // Existing 2FA — decrypt stored secret
    try {
      totpSecret = decryptTotp(admin.totp_secret_enc, admin.totp_secret_iv, admin.totp_secret_tag);
    } catch {
      return res.status(500).json({ success: false, message: 'Failed to verify 2FA. Contact support.' });
    }
  } else {
    return res.status(400).json({ success: false, message: '2FA not configured' });
  }

  // Verify TOTP code (check current + previous + next window for clock skew)
  const { createHmac } = crypto;
  const now = Math.floor(Date.now() / 1000);
  let verified = false;

  // Proper RFC 4648 Base32 decoding
  const base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const c of totpSecret.toUpperCase()) {
    const idx = base32Chars.indexOf(c);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((value >> bits) & 0xff);
    }
  }
  const keyBytes = Buffer.from(bytes);

  for (const offset of [-1, 0, 1]) {
    const counter = Math.floor(now / 30) + offset;
    const counterBuf = Buffer.alloc(8);
    counterBuf.writeBigUInt64BE(BigInt(counter));
    const hmac = createHmac('sha1', keyBytes).update(counterBuf).digest();
    const off = hmac[hmac.length - 1] & 0x0f;
    const otp = ((hmac.readUInt32BE(off) & 0x7fffffff) % 1000000).toString().padStart(6, '0');
    if (otp === code) { verified = true; break; }
  }

  if (!verified) {
    const ip = req.ip || 'unknown';
    auditLog('super_admin_2fa_failed', admin.id, ip);
    return res.status(401).json({ success: false, message: 'Invalid code. Try again.' });
  }

  // If first-time setup, store the encrypted TOTP secret
  if (challenge.pendingTotpSecret) {
    const { enc, iv, tag } = encryptTotp(totpSecret);
    masterDb.prepare(
      'UPDATE super_admins SET totp_secret_enc = ?, totp_secret_iv = ?, totp_secret_tag = ?, totp_enabled = 1, updated_at = datetime(?) WHERE id = ?'
    ).run(enc, iv, tag, new Date().toISOString(), admin.id);
  }

  // Login successful — create session + JWT
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const userAgent = req.headers['user-agent'] || '';
  const sessionId = createSession(masterDb, admin.id, ip, userAgent);

  // Reset failed login count
  masterDb.prepare(
    "UPDATE super_admins SET failed_login_count = 0, locked_until = NULL, last_login_at = datetime(?), last_login_ip = ? WHERE id = ?"
  ).run(new Date().toISOString(), ip, admin.id);

  clearFailures(ip);

  const token = jwt.sign(
    { superAdminId: admin.id, sessionId, role: 'super_admin' as const },
    config.superAdminSecret,
    { expiresIn: '4h' },
  );

  auditLog('super_admin_login_success', admin.id, ip, { method: '2fa' });

  res.json({
    success: true,
    data: {
      token,
      admin: { id: admin.id, username: admin.username, email: admin.email },
    },
  });
});

// ═══════════════════════════════════════════════════════════════════
// PROTECTED ROUTES (require super admin auth)
// ═══════════════════════════════════════════════════════════════════

router.use(superAdminAuth);

// POST /logout
router.post('/logout', (req, res) => {
  const masterDb = getMasterDb()!;
  const authHeader = req.headers.authorization!;
  try {
    const payload = jwt.verify(authHeader.substring(7), config.superAdminSecret) as any;
    masterDb.prepare('DELETE FROM super_admin_sessions WHERE id = ?').run(payload.sessionId);
  } catch {}
  auditLog('super_admin_logout', req.superAdmin!.superAdminId, req.ip || 'unknown');
  res.json({ success: true });
});

// GET /me
router.get('/me', (req, res) => {
  const masterDb = getMasterDb()!;
  const admin = masterDb.prepare('SELECT id, username, email, last_login_at, created_at FROM super_admins WHERE id = ?')
    .get(req.superAdmin!.superAdminId);
  res.json({ success: true, data: admin });
});

// ─── Dashboard ──────────────────────────────────────────────────────

router.get('/dashboard', (_req, res) => {
  const masterDb = getMasterDb()!;
  const totalTenants = (masterDb.prepare("SELECT COUNT(*) as c FROM tenants WHERE status != 'deleted'").get() as any).c;
  const activeTenants = (masterDb.prepare("SELECT COUNT(*) as c FROM tenants WHERE status = 'active'").get() as any).c;
  const suspendedTenants = (masterDb.prepare("SELECT COUNT(*) as c FROM tenants WHERE status = 'suspended'").get() as any).c;
  const planCounts = masterDb.prepare("SELECT plan, COUNT(*) as count FROM tenants WHERE status != 'deleted' GROUP BY plan").all();
  const pool = getPoolStats();

  let totalDbSizeMb = 0;
  if (fs.existsSync(config.tenantDataDir)) {
    for (const f of fs.readdirSync(config.tenantDataDir).filter(f => f.endsWith('.db'))) {
      try { totalDbSizeMb += fs.statSync(path.join(config.tenantDataDir, f)).size / (1024 * 1024); } catch {}
    }
  }

  let unacknowledgedAlerts = 0;
  try {
    unacknowledgedAlerts = (masterDb.prepare('SELECT COUNT(*) as c FROM security_alerts WHERE acknowledged = 0').get() as any).c;
  } catch {}

  res.json({
    success: true,
    data: {
      total_tenants: totalTenants,
      active_tenants: activeTenants,
      suspended_tenants: suspendedTenants,
      plan_distribution: planCounts,
      pool_stats: { size: pool.size, maxSize: pool.maxSize },
      total_db_size_mb: Math.round(totalDbSizeMb * 100) / 100,
      memory_mb: Math.round(process.memoryUsage().rss / 1024 / 1024),
      uptime_hours: Math.round(process.uptime() / 3600 * 10) / 10,
      unacknowledged_alerts: unacknowledgedAlerts,
    },
  });
});

// ─── Tenant Management ──────────────────────────────────────────────

router.get('/tenants', (req, res) => {
  const { status, plan } = req.query as Record<string, string>;
  const tenants = listTenants({ status, plan });
  const enriched = tenants.map((t: any) => {
    let dbSizeMb = 0;
    try { dbSizeMb = Math.round(fs.statSync(path.join(config.tenantDataDir, t.db_path)).size / (1024 * 1024) * 100) / 100; } catch {}
    return { ...t, db_size_mb: dbSizeMb };
  });
  res.json({ success: true, data: { tenants: enriched } });
});

router.post('/tenants', async (req, res) => {
  const { slug, shop_name, admin_email, plan, admin_first_name, admin_last_name } = req.body;
  // No admin_password — shop admin sets their own password on first login (password_set = 0)
  const result = await provisionTenant({
    slug: slug?.toLowerCase().trim(),
    name: shop_name,
    adminEmail: admin_email,
    adminFirstName: admin_first_name,
    adminLastName: admin_last_name,
    plan,
  });
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  auditLog('tenant_created', req.superAdmin!.superAdminId, req.ip || 'unknown', { slug: result.slug });
  const port = config.port !== 443 ? `:${config.port}` : '';
  const baseUrl = `https://${result.slug}.${config.baseDomain}${port}`;
  const setupUrl = `${baseUrl}/setup/${result.setupToken}`;
  res.status(201).json({ success: true, data: { tenant_id: result.tenantId, slug: result.slug, url: baseUrl, setup_url: setupUrl } });
});

router.get('/tenants/:slug', (req, res) => {
  const masterDb = getMasterDb()!;
  const tenant = masterDb.prepare('SELECT * FROM tenants WHERE slug = ?').get(req.params.slug) as any;
  if (!tenant) return res.status(404).json({ success: false, message: 'Tenant not found' });

  let userCount = 0, ticketCount = 0, customerCount = 0;
  try {
    const tdb = getTenantDb(tenant.slug);
    userCount = (tdb.prepare('SELECT COUNT(*) as c FROM users WHERE is_active = 1').get() as any).c;
    ticketCount = (tdb.prepare('SELECT COUNT(*) as c FROM tickets WHERE is_deleted = 0').get() as any).c;
    customerCount = (tdb.prepare('SELECT COUNT(*) as c FROM customers WHERE is_deleted = 0').get() as any).c;
  } catch {}

  let dbSizeMb = 0;
  try { dbSizeMb = Math.round(fs.statSync(path.join(config.tenantDataDir, tenant.db_path)).size / (1024 * 1024) * 100) / 100; } catch {}

  res.json({ success: true, data: { ...tenant, user_count: userCount, ticket_count: ticketCount, customer_count: customerCount, db_size_mb: dbSizeMb } });
});

router.put('/tenants/:slug', (req, res) => {
  const masterDb = getMasterDb()!;
  const ALLOWED_PLANS = ['free', 'starter', 'professional', 'enterprise', 'custom'];
  const errors: string[] = [];

  // Validate plan
  if (req.body.plan !== undefined) {
    if (typeof req.body.plan !== 'string' || !ALLOWED_PLANS.includes(req.body.plan)) {
      errors.push(`plan must be one of: ${ALLOWED_PLANS.join(', ')}`);
    }
  }

  // Validate max_users (positive integer)
  if (req.body.max_users !== undefined) {
    const v = req.body.max_users;
    if (v !== null && (!Number.isInteger(v) || v < 1)) {
      errors.push('max_users must be a positive integer or null');
    }
  }

  // Validate max_tickets_month (positive integer or null)
  if (req.body.max_tickets_month !== undefined) {
    const v = req.body.max_tickets_month;
    if (v !== null && (!Number.isInteger(v) || v < 1)) {
      errors.push('max_tickets_month must be a positive integer or null');
    }
  }

  // Validate storage_limit_mb (positive integer or null)
  if (req.body.storage_limit_mb !== undefined) {
    const v = req.body.storage_limit_mb;
    if (v !== null && (!Number.isInteger(v) || v < 1)) {
      errors.push('storage_limit_mb must be a positive integer or null');
    }
  }

  // Validate name (non-empty string, reasonable length)
  if (req.body.name !== undefined) {
    if (typeof req.body.name !== 'string' || req.body.name.trim().length === 0 || req.body.name.length > 200) {
      errors.push('name must be a non-empty string (max 200 characters)');
    }
  }

  if (errors.length > 0) {
    return res.status(400).json({ success: false, message: errors.join('; ') });
  }

  const allowedFields: Record<string, any> = {};
  if (req.body.plan !== undefined) allowedFields['plan'] = req.body.plan;
  if (req.body.max_users !== undefined) allowedFields['max_users'] = req.body.max_users;
  if (req.body.max_tickets_month !== undefined) allowedFields['max_tickets_month'] = req.body.max_tickets_month;
  if (req.body.storage_limit_mb !== undefined) allowedFields['storage_limit_mb'] = req.body.storage_limit_mb;
  if (req.body.name !== undefined) allowedFields['name'] = req.body.name.trim();

  const keys = Object.keys(allowedFields);
  if (keys.length === 0) return res.status(400).json({ success: false, message: 'No fields to update' });

  const setClause = keys.map(k => `${k} = ?`).join(', ');
  const params = keys.map(k => allowedFields[k]);
  params.push(req.params.slug);
  masterDb.prepare(`UPDATE tenants SET ${setClause}, updated_at = datetime('now') WHERE slug = ?`).run(...params);
  auditLog('tenant_updated', req.superAdmin!.superAdminId, req.ip || 'unknown', { slug: req.params.slug, fields: keys });
  const tenant = masterDb.prepare('SELECT * FROM tenants WHERE slug = ?').get(req.params.slug);
  res.json({ success: true, data: tenant });
});

router.post('/tenants/:slug/suspend', (req, res) => {
  const result = suspendTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  auditLog('tenant_suspended', req.superAdmin!.superAdminId, req.ip || 'unknown', { slug: req.params.slug });
  res.json({ success: true, data: { message: `${req.params.slug} suspended` } });
});

router.post('/tenants/:slug/activate', (req, res) => {
  const result = activateTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  auditLog('tenant_activated', req.superAdmin!.superAdminId, req.ip || 'unknown', { slug: req.params.slug });
  res.json({ success: true, data: { message: `${req.params.slug} activated` } });
});

router.delete('/tenants/:slug', (req, res) => {
  const result = deleteTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  auditLog('tenant_deleted', req.superAdmin!.superAdminId, req.ip || 'unknown', { slug: req.params.slug });
  res.json({ success: true, data: { message: `${req.params.slug} deleted` } });
});

// ─── Backup Management ──────────────────────────────────────────────

router.get('/backups', (_req, res) => {
  // List all tenant DB files with sizes
  const tenants = listTenants({});
  const backups = tenants.map((t: any) => {
    const dbPath = path.join(config.tenantDataDir, t.db_path);
    let sizeMb = 0;
    let lastModified = '';
    try {
      const stat = fs.statSync(dbPath);
      sizeMb = Math.round(stat.size / (1024 * 1024) * 100) / 100;
      lastModified = stat.mtime.toISOString();
    } catch {}
    return { slug: t.slug, name: t.name, db_size_mb: sizeMb, last_modified: lastModified, status: t.status };
  });

  // Master DB size
  let masterSizeMb = 0;
  try { masterSizeMb = Math.round(fs.statSync(config.masterDbPath).size / (1024 * 1024) * 100) / 100; } catch {}

  res.json({ success: true, data: { tenants: backups, master_db_size_mb: masterSizeMb } });
});

// ─── System Health ──────────────────────────────────────────────────

router.get('/health', (_req, res) => {
  const pool = getPoolStats();
  const mem = process.memoryUsage();
  res.json({
    success: true,
    data: {
      uptime_seconds: Math.floor(process.uptime()),
      memory_mb: { rss: Math.round(mem.rss / 1024 / 1024), heap_used: Math.round(mem.heapUsed / 1024 / 1024), heap_total: Math.round(mem.heapTotal / 1024 / 1024) },
      pool,
      node_version: process.version,
      platform: process.platform,
    },
  });
});

// ─── Audit Log ──────────────────────────────────────────────────────

router.get('/audit-log', (req, res) => {
  const masterDb = getMasterDb()!;
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 500);
  const logs = masterDb.prepare(`
    SELECT al.*, sa.username as admin_username
    FROM master_audit_log al
    LEFT JOIN super_admins sa ON sa.id = al.super_admin_id
    ORDER BY al.created_at DESC LIMIT ?
  `).all(limit);
  res.json({ success: true, data: { logs } });
});

// ─── Active Sessions ────────────────────────────────────────────────

router.get('/sessions', (req, res) => {
  const masterDb = getMasterDb()!;
  const sessions = masterDb.prepare(`
    SELECT s.id, s.ip_address, s.user_agent, s.created_at, s.expires_at, sa.username
    FROM super_admin_sessions s
    JOIN super_admins sa ON sa.id = s.super_admin_id
    WHERE s.expires_at > datetime('now')
    ORDER BY s.created_at DESC
  `).all();
  res.json({ success: true, data: { sessions } });
});

router.delete('/sessions/:id', (req, res) => {
  const masterDb = getMasterDb()!;
  masterDb.prepare('DELETE FROM super_admin_sessions WHERE id = ?').run(req.params.id);
  auditLog('session_revoked', req.superAdmin!.superAdminId, req.ip || 'unknown', { sessionId: req.params.id });
  res.json({ success: true });
});

// ─── Announcements ──────────────────────────────────────────────────

router.get('/announcements', (_req, res) => {
  const masterDb = getMasterDb()!;
  const items = masterDb.prepare('SELECT * FROM announcements WHERE is_active = 1 ORDER BY created_at DESC').all();
  res.json({ success: true, data: { announcements: items } });
});

router.post('/announcements', (req, res) => {
  const masterDb = getMasterDb()!;
  const { title, body } = req.body;
  if (!title || !body) return res.status(400).json({ success: false, message: 'Title and body required' });
  const result = masterDb.prepare('INSERT INTO announcements (title, body) VALUES (?, ?)').run(title, body);
  const item = masterDb.prepare('SELECT * FROM announcements WHERE id = ?').get(result.lastInsertRowid);
  auditLog('announcement_created', req.superAdmin!.superAdminId, req.ip || 'unknown', { title });
  res.status(201).json({ success: true, data: item });
});

// ─── Security Alerts ────────────────────────────────────────────────

router.get('/security-alerts', (req, res) => {
  const masterDb = getMasterDb()!;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const limit = Math.min(Math.max(1, parseInt(req.query.limit as string) || 50), 500);
  const offset = (page - 1) * limit;

  const conditions: string[] = [];
  const params: any[] = [];

  if (req.query.severity) {
    conditions.push('severity = ?');
    params.push(req.query.severity);
  }
  if (req.query.acknowledged !== undefined) {
    conditions.push('acknowledged = ?');
    params.push(parseInt(req.query.acknowledged as string) || 0);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const total = (masterDb.prepare(`SELECT COUNT(*) as c FROM security_alerts ${where}`).get(...params) as any).c;
  const alerts = masterDb.prepare(
    `SELECT * FROM security_alerts ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`
  ).all(...params, limit, offset);

  res.json({
    success: true,
    data: {
      alerts,
      pagination: { page, limit, total, total_pages: Math.ceil(total / limit) },
    },
  });
});

router.post('/security-alerts/:id/acknowledge', (req, res) => {
  const masterDb = getMasterDb()!;
  const alertId = parseInt(req.params.id);
  if (!alertId || isNaN(alertId)) {
    return res.status(400).json({ success: false, message: 'Invalid alert ID' });
  }

  const alert = masterDb.prepare('SELECT id FROM security_alerts WHERE id = ?').get(alertId) as any;
  if (!alert) {
    return res.status(404).json({ success: false, message: 'Alert not found' });
  }

  masterDb.prepare('UPDATE security_alerts SET acknowledged = 1 WHERE id = ?').run(alertId);
  auditLog('security_alert_acknowledged', req.superAdmin!.superAdminId, req.ip || 'unknown', { alert_id: alertId });
  res.json({ success: true, data: { message: 'Alert acknowledged' } });
});

// ─── Tenant Auth Events ─────────────────────────────────────────────

router.get('/tenant-auth-events', (req, res) => {
  const masterDb = getMasterDb()!;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const limit = Math.min(Math.max(1, parseInt(req.query.limit as string) || 50), 500);
  const offset = (page - 1) * limit;

  const conditions: string[] = [];
  const params: any[] = [];

  if (req.query.tenant_slug) {
    conditions.push('tenant_slug = ?');
    params.push(req.query.tenant_slug);
  }
  if (req.query.ip) {
    conditions.push('ip_address = ?');
    params.push(req.query.ip);
  }
  if (req.query.event) {
    conditions.push('event = ?');
    params.push(req.query.event);
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const total = (masterDb.prepare(`SELECT COUNT(*) as c FROM tenant_auth_events ${where}`).get(...params) as any).c;
  const events = masterDb.prepare(
    `SELECT * FROM tenant_auth_events ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`
  ).all(...params, limit, offset);

  res.json({
    success: true,
    data: {
      events,
      pagination: { page, limit, total, total_pages: Math.ceil(total / limit) },
    },
  });
});

// ── Platform Config ────────────────────────────────────────────────────

router.get('/config', (req: Request, res: Response) => {
  const masterDb = (req as any).masterDb || getMasterDb();
  if (!masterDb) {
    res.status(500).json({ success: false, message: 'Master DB not available' });
    return;
  }

  const rows = masterDb.prepare('SELECT key, value, updated_at FROM platform_config').all() as { key: string; value: string; updated_at: string }[];
  const config: Record<string, string> = {};
  for (const row of rows) {
    config[row.key] = row.value;
  }
  res.json({ success: true, data: config });
});

router.put('/config', (req: Request, res: Response) => {
  const masterDb = (req as any).masterDb || getMasterDb();
  if (!masterDb) {
    res.status(500).json({ success: false, message: 'Master DB not available' });
    return;
  }

  const updates = req.body;
  if (!updates || typeof updates !== 'object') {
    res.status(400).json({ success: false, message: 'Object body required' });
    return;
  }

  // Only allow known config keys
  const allowedKeys = new Set(['management_api_enabled', 'management_rate_limit_bypass']);
  const stmt = masterDb.prepare('INSERT OR REPLACE INTO platform_config (key, value, updated_at) VALUES (?, ?, datetime(?))');

  for (const [key, value] of Object.entries(updates)) {
    if (!allowedKeys.has(key)) continue;
    stmt.run(key, String(value), new Date().toISOString());
  }

  // Audit log
  try {
    const adminId = (req as any).superAdminId;
    masterDb.prepare(
      "INSERT INTO master_audit_log (super_admin_id, action, entity_type, details, ip_address, created_at) VALUES (?, 'update_config', 'platform_config', ?, ?, datetime(?))"
    ).run(adminId || null, JSON.stringify(updates), req.ip || req.socket?.remoteAddress, new Date().toISOString());
  } catch { /* audit log is best-effort */ }

  res.json({ success: true, message: 'Config updated' });
});

export default router;
