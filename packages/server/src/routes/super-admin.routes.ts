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
import { checkWindowRate, recordWindowFailure, clearRateLimit } from '../utils/rateLimiter.js';
import { clearPlanCache } from '../middleware/tenantResolver.js';
import { createLogger } from '../utils/logger.js';
import { PLAN_DEFINITIONS, type TenantPlan } from '@bizarre-crm/shared';

const router = Router();
const logger = createLogger('super-admin');
type AnyRow = Record<string, any>;

// Q3: hard-coded whitelist of fields that super admins may set on a tenant
// row via PUT /tenants/:slug. Duplicated here (NOT imported) so the authoritative
// SQLi surface lives in the same file as the UPDATE statement — any future
// refactor that loses this whitelist is immediately visible next to the SQL.
// Unit-test note: every key in this set MUST correspond to an existing column
// in the `tenants` table, and any request key NOT in this set must be rejected
// with HTTP 400 by the route handler.
const TENANT_UPDATE_FIELD_WHITELIST: ReadonlySet<string> = new Set([
  'plan',
  'max_users',
  'max_tickets_month',
  'storage_limit_mb',
  'name',
  'trial_ends_at',
]);

// PL1: fields that define the billing tier for a tenant. Snapshotted before
// and after a plan change so the audit trail captures both sides of a super
// admin mutation (PL2).
const TIER_AUDIT_FIELDS: readonly string[] = [
  'plan',
  'max_users',
  'max_tickets_month',
  'storage_limit_mb',
  'trial_ends_at',
  'stripe_customer_id',
  'stripe_subscription_id',
];

function snapshotTierFields(row: AnyRow | undefined): Record<string, unknown> {
  if (!row) return {};
  const out: Record<string, unknown> = {};
  for (const f of TIER_AUDIT_FIELDS) {
    if (f in row) out[f] = row[f];
  }
  return out;
}

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

// ─── Rate Limiting (SQLite-backed via rateLimiter utility) ──────────

const MAX_LOGIN_ATTEMPTS = 7;
const LOCKOUT_DURATION = 15 * 60 * 1000; // 15 minutes

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

  if (!checkWindowRate(masterDb, 'super_admin_login', ip, MAX_LOGIN_ATTEMPTS, LOCKOUT_DURATION)) {
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
    recordWindowFailure(masterDb, 'super_admin_login', ip, LOCKOUT_DURATION);
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
    recordWindowFailure(masterDb, 'super_admin_login', ip, LOCKOUT_DURATION);
    const fails = (admin.failed_login_count || 0) + 1;
    const updates: any[] = [fails];
    let lockUntil: string | null = null;
    if (fails >= 7) {
      lockUntil = new Date(Date.now() + 30 * 60 * 1000).toISOString(); // Lock 30 minutes
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

  clearRateLimit(masterDb, 'super_admin_login', ip);

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

// @audit-fixed: Previously this route called provisionTenant() with whatever
// arrived in req.body, including non-string slugs. provisionTenant() does its
// own validation but blew up with a TypeError on `slug.toLowerCase()` when a
// non-string was supplied — surfacing as a generic 500 instead of a clean 400.
// We now type-guard every input here so the route returns structured 400s and
// also audits failed provisioning attempts (so brute-force slug enumeration
// shows up in master_audit_log instead of disappearing into the noise).
router.post('/tenants', async (req, res) => {
  const body = (req.body ?? {}) as Record<string, unknown>;
  const slug = body.slug;
  const shop_name = body.shop_name;
  const admin_email = body.admin_email;
  const plan = body.plan;
  const admin_first_name = body.admin_first_name;
  const admin_last_name = body.admin_last_name;

  if (typeof slug !== 'string' || slug.trim().length === 0) {
    return res.status(400).json({ success: false, message: 'slug must be a non-empty string' });
  }
  if (typeof shop_name !== 'string' || shop_name.trim().length === 0) {
    return res.status(400).json({ success: false, message: 'shop_name must be a non-empty string' });
  }
  if (typeof admin_email !== 'string' || !admin_email.includes('@')) {
    return res.status(400).json({ success: false, message: 'admin_email must be a valid email' });
  }
  if (plan !== undefined && typeof plan !== 'string') {
    return res.status(400).json({ success: false, message: 'plan must be a string' });
  }
  if (admin_first_name !== undefined && typeof admin_first_name !== 'string') {
    return res.status(400).json({ success: false, message: 'admin_first_name must be a string' });
  }
  if (admin_last_name !== undefined && typeof admin_last_name !== 'string') {
    return res.status(400).json({ success: false, message: 'admin_last_name must be a string' });
  }

  // No admin_password — shop admin sets their own password on first login (password_set = 0)
  const result = await provisionTenant({
    slug: slug.toLowerCase().trim(),
    name: shop_name,
    adminEmail: admin_email,
    adminFirstName: admin_first_name,
    adminLastName: admin_last_name,
    plan,
  });
  if (!result.success) {
    auditLog('tenant_create_failed', req.superAdmin!.superAdminId, req.ip || 'unknown', {
      slug: slug.toLowerCase().trim(),
      reason: result.error,
    });
    return res.status(400).json({ success: false, message: result.error });
  }
  auditLog('tenant_created', req.superAdmin!.superAdminId, req.ip || 'unknown', {
    slug: result.slug,
    tenant_id: result.tenantId,
    plan: plan ?? 'free',
  });
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

router.put('/tenants/:slug', async (req, res) => {
  const masterDb = getMasterDb()!;
  const ALLOWED_PLANS: readonly TenantPlan[] = ['free', 'pro'];
  const errors: string[] = [];

  // Q3: Reject any body key that is NOT in the hard-coded whitelist. This is
  // belt-and-suspenders over the per-key `if (req.body.X !== undefined)` logic
  // below — if anyone adds a new conditional without also updating the
  // whitelist, the request will be rejected with a clear error.
  if (req.body && typeof req.body === 'object') {
    for (const key of Object.keys(req.body)) {
      if (!TENANT_UPDATE_FIELD_WHITELIST.has(key)) {
        errors.push(`unknown or disallowed field: ${key}`);
      }
    }
  } else {
    errors.push('request body must be an object');
  }

  // Validate plan
  if (req.body.plan !== undefined) {
    if (typeof req.body.plan !== 'string' || !ALLOWED_PLANS.includes(req.body.plan as TenantPlan)) {
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

  // Validate trial_ends_at: null clears, 'clear' clears, ISO 8601 string sets
  let trialEndsAtValue: string | null | undefined; // undefined = no change
  if (req.body.trial_ends_at !== undefined) {
    const raw = req.body.trial_ends_at;
    if (raw === null || raw === 'clear') {
      trialEndsAtValue = null;
    } else if (typeof raw === 'string' && raw.trim().length > 0) {
      const parsed = new Date(raw);
      if (Number.isNaN(parsed.getTime())) {
        errors.push('trial_ends_at must be null, "clear", or a valid ISO 8601 timestamp');
      } else {
        trialEndsAtValue = parsed.toISOString();
      }
    } else {
      errors.push('trial_ends_at must be null, "clear", or a valid ISO 8601 timestamp');
    }
  }

  if (errors.length > 0) {
    return res.status(400).json({ success: false, message: errors.join('; ') });
  }

  // Look up tenant FIRST so we can capture the tenant id for cache invalidation
  // and so unknown slugs return 404 instead of silently no-oping the UPDATE.
  // PL2: fetch the full row so we can snapshot tier fields before the change.
  const existing = masterDb
    .prepare('SELECT * FROM tenants WHERE slug = ?')
    .get(req.params.slug) as AnyRow | undefined;
  if (!existing) {
    return res.status(404).json({ success: false, message: 'Tenant not found' });
  }

  const beforeSnapshot = snapshotTierFields(existing);

  const allowedFields: Record<string, any> = {};
  if (req.body.plan !== undefined) allowedFields['plan'] = req.body.plan;
  if (req.body.max_users !== undefined) allowedFields['max_users'] = req.body.max_users;
  if (req.body.max_tickets_month !== undefined) allowedFields['max_tickets_month'] = req.body.max_tickets_month;
  if (req.body.storage_limit_mb !== undefined) allowedFields['storage_limit_mb'] = req.body.storage_limit_mb;
  if (req.body.name !== undefined) allowedFields['name'] = req.body.name.trim();
  if (trialEndsAtValue !== undefined) allowedFields['trial_ends_at'] = trialEndsAtValue;

  // When the plan changes and the caller did NOT also override the limits, snap
  // every limit to the plan definition from @bizarre-crm/shared so the tier ↔ limit
  // contract stays consistent. Callers can still override individual limits explicitly.
  if (req.body.plan !== undefined) {
    const planDef = PLAN_DEFINITIONS[req.body.plan as TenantPlan];
    if (planDef) {
      if (req.body.max_tickets_month === undefined) {
        allowedFields['max_tickets_month'] = planDef.limits.maxTicketsMonth ?? 999999;
      }
      if (req.body.max_users === undefined) {
        allowedFields['max_users'] = planDef.limits.maxUsers ?? 999999;
      }
      if (req.body.storage_limit_mb === undefined) {
        allowedFields['storage_limit_mb'] = planDef.limits.storageLimitMb ?? 999999;
      }
    }
  }

  const keys = Object.keys(allowedFields);
  if (keys.length === 0) return res.status(400).json({ success: false, message: 'No fields to update' });

  // Q3: Final paranoid check — every key passed to string interpolation MUST
  // be in the hard-coded whitelist. If something slipped through the earlier
  // check, bail hard rather than issue arbitrary SQL.
  for (const k of keys) {
    if (!TENANT_UPDATE_FIELD_WHITELIST.has(k)) {
      logger.error('tenant update blocked: whitelist bypass attempt', { key: k, slug: req.params.slug });
      return res.status(400).json({ success: false, message: `disallowed field: ${k}` });
    }
  }

  const setClause = keys.map(k => `${k} = ?`).join(', ');
  const params = keys.map(k => allowedFields[k]);
  params.push(req.params.slug);
  masterDb.prepare(`UPDATE tenants SET ${setClause}, updated_at = datetime('now') WHERE slug = ?`).run(...params);

  // PL1: If the plan changed, reconcile the Stripe subscription. Without this,
  // downgrading Pro -> Free leaves the Stripe subscription active (customer
  // keeps getting billed). Upgrading Free -> Pro would leave the tenant
  // without a subscription row (no future invoices). Only tenants that have
  // `stripe_customer_id` have ever been on Stripe; otherwise skip silently.
  //
  // services/stripe.ts now exposes `updateSubscription(tenantId, newPlan)`
  // which:
  //   - if newPlan === 'free': cancels the active subscription and clears the
  //     subscription row on the tenant
  //   - if newPlan === 'pro' | 'enterprise': swaps the price on the existing
  //     subscription (or throws if the tenant has no subscription row — they
  //     must go through Checkout first)
  // On Stripe API failure the helper throws; this route then rolls back the
  // DB change using beforeSnapshot and returns 502 so DB and Stripe stay in
  // sync. Dynamic import keeps the route loadable even when STRIPE_* env vars
  // are absent in local/dev setups.
  if (req.body.plan !== undefined && existing.plan !== req.body.plan) {
    const hadStripeCustomer = Boolean(existing.stripe_customer_id);
    let stripeSyncApplied = false;
    let stripeRollback = false;
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const stripeModule: any = await import('../services/stripe.js');
      if (typeof stripeModule.updateSubscription === 'function' && hadStripeCustomer) {
        await stripeModule.updateSubscription(existing.id, req.body.plan);
        stripeSyncApplied = true;
      } else if (!hadStripeCustomer) {
        logger.info('Plan change skipped Stripe sync — tenant never subscribed via Stripe', {
          slug: req.params.slug,
          tenant_id: existing.id,
          from: existing.plan,
          to: req.body.plan,
        });
      } else {
        // Function not yet implemented — log and keep the DB change; do NOT
        // silently lose the downgrade. This is the explicit TODO documented
        // above and the visible alert that the reconciliation is pending.
        logger.error('services/stripe.updateSubscription NOT IMPLEMENTED — plan changed in DB without Stripe reconciliation', {
          slug: req.params.slug,
          tenant_id: existing.id,
          from: existing.plan,
          to: req.body.plan,
          stripe_customer_id: existing.stripe_customer_id,
          stripe_subscription_id: existing.stripe_subscription_id,
        });
      }
    } catch (err) {
      stripeRollback = true;
      logger.error('Stripe subscription reconciliation failed — rolling back tenant update', {
        slug: req.params.slug,
        tenant_id: existing.id,
        error: err instanceof Error ? err.message : 'unknown',
      });
    }

    if (stripeRollback) {
      // Roll back the DB change to the before-snapshot so the DB and Stripe
      // agree (both unchanged) rather than diverge.
      try {
        const rollbackKeys: string[] = [];
        const rollbackParams: unknown[] = [];
        for (const f of TIER_AUDIT_FIELDS) {
          if (f in existing && TENANT_UPDATE_FIELD_WHITELIST.has(f)) {
            rollbackKeys.push(`${f} = ?`);
            rollbackParams.push(existing[f]);
          }
        }
        if (rollbackKeys.length > 0) {
          rollbackParams.push(req.params.slug);
          masterDb
            .prepare(`UPDATE tenants SET ${rollbackKeys.join(', ')}, updated_at = datetime('now') WHERE slug = ?`)
            .run(...rollbackParams);
        }
      } catch (rollbackErr) {
        logger.error('Rollback also failed — DB is in an inconsistent state', {
          slug: req.params.slug,
          error: rollbackErr instanceof Error ? rollbackErr.message : 'unknown',
        });
      }
      clearPlanCache(existing.id);
      auditLog('tenant_update_rolled_back', req.superAdmin!.superAdminId, req.ip || 'unknown', {
        slug: req.params.slug,
        reason: 'stripe_sync_failed',
        before: beforeSnapshot,
        attempted_after: allowedFields,
      });
      return res.status(502).json({
        success: false,
        message: 'Stripe subscription sync failed — plan change rolled back. Try again or contact support.',
      });
    }

    // Attach Stripe sync status to audit payload below
    (allowedFields as Record<string, unknown>)._stripeSyncApplied = stripeSyncApplied;
  }

  // Bust the in-memory plan cache so the next request sees the new plan/limits/trial
  // immediately instead of waiting up to 60s for the TTL to expire.
  clearPlanCache(existing.id);

  // PL2: capture the after-snapshot and include both before/after in the audit
  // entry so a forensic review can see exactly what changed and which super
  // admin made the change. Previously the audit only logged the list of keys.
  const afterRow = masterDb
    .prepare('SELECT * FROM tenants WHERE slug = ?')
    .get(req.params.slug) as AnyRow | undefined;
  const afterSnapshot = snapshotTierFields(afterRow);
  const stripeSyncApplied = (allowedFields as Record<string, unknown>)._stripeSyncApplied;
  auditLog('tenant_updated', req.superAdmin!.superAdminId, req.ip || 'unknown', {
    slug: req.params.slug,
    fields: keys,
    before: beforeSnapshot,
    after: afterSnapshot,
    ...(stripeSyncApplied !== undefined ? { stripe_sync_applied: stripeSyncApplied } : {}),
  });

  res.json({ success: true, data: afterRow });
});

// Usage summary for a single tenant: current-month counters, 12-month history,
// plan/limit snapshot, and whether the trial is still active.
router.get('/tenants/:slug/usage', (req, res) => {
  const masterDb = getMasterDb()!;
  const tenant = masterDb
    .prepare(
      'SELECT id, slug, plan, max_tickets_month, max_users, storage_limit_mb, trial_ends_at FROM tenants WHERE slug = ?'
    )
    .get(req.params.slug) as AnyRow | undefined;
  if (!tenant) {
    res.status(404).json({ success: false, message: 'Tenant not found' });
    return;
  }

  const currentMonth = new Date().toISOString().slice(0, 7);
  const current = masterDb
    .prepare('SELECT * FROM tenant_usage WHERE tenant_id = ? AND month = ?')
    .get(tenant.id, currentMonth) as AnyRow | undefined;
  const history = masterDb
    .prepare('SELECT * FROM tenant_usage WHERE tenant_id = ? ORDER BY month DESC LIMIT 12')
    .all(tenant.id) as AnyRow[];
  const trialActive = !!tenant.trial_ends_at && tenant.trial_ends_at > new Date().toISOString();

  res.json({
    success: true,
    data: {
      tenant,
      current_month: current || {
        month: currentMonth,
        tickets_created: 0,
        sms_sent: 0,
        storage_bytes: 0,
        active_users: 0,
      },
      history,
      trial_active: trialActive,
    },
  });
});

// @audit-fixed: suspend / activate / delete previously did not invalidate
// the in-memory plan cache OR kick existing tenant WebSocket sessions, so a
// suspended shop kept serving traffic for up to 60s (cache TTL) and any
// already-connected WS client kept publishing messages indefinitely. We now
// snapshot the tenant id, run the lifecycle action, then bust the plan cache
// and force-close every WS the tenant has open. Audit rows now include the
// tenant_id so post-mortem queries can join master_audit_log <-> tenants by
// id even when the slug has since been recycled (it can't be — see TP1/TP2 —
// but defense in depth).
function lookupTenantBySlug(slug: string): { id: number; status: string } | null {
  const masterDb = getMasterDb();
  if (!masterDb) return null;
  const row = masterDb
    .prepare('SELECT id, status FROM tenants WHERE slug = ?')
    .get(slug) as { id: number; status: string } | undefined;
  return row ?? null;
}

function disconnectTenantWebSockets(slug: string): number {
  // Lazy-import to avoid circular dependencies between routes and ws/server.
  // We close any AuthenticatedSocket whose tenantSlug matches.
  let closed = 0;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
    const wsMod = require('../ws/server.js') as { allClients?: Set<{ tenantSlug?: string | null; close?: () => void; terminate?: () => void }> };
    const sockets = wsMod.allClients;
    if (!sockets) return 0;
    for (const ws of sockets) {
      if (ws.tenantSlug === slug) {
        try { ws.close?.(); } catch { /* ignore */ }
        try { ws.terminate?.(); } catch { /* ignore */ }
        closed += 1;
      }
    }
  } catch (err) {
    logger.warn('Failed to disconnect tenant WebSockets', {
      slug,
      error: err instanceof Error ? err.message : String(err),
    });
  }
  return closed;
}

router.post('/tenants/:slug/suspend', (req, res) => {
  const before = lookupTenantBySlug(req.params.slug);
  const result = suspendTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  if (before) clearPlanCache(before.id);
  const wsClosed = disconnectTenantWebSockets(req.params.slug);
  auditLog('tenant_suspended', req.superAdmin!.superAdminId, req.ip || 'unknown', {
    slug: req.params.slug,
    tenant_id: before?.id ?? null,
    previous_status: before?.status ?? null,
    websockets_closed: wsClosed,
  });
  res.json({ success: true, data: { message: `${req.params.slug} suspended`, websockets_closed: wsClosed } });
});

router.post('/tenants/:slug/activate', (req, res) => {
  const before = lookupTenantBySlug(req.params.slug);
  const result = activateTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  if (before) clearPlanCache(before.id);
  auditLog('tenant_activated', req.superAdmin!.superAdminId, req.ip || 'unknown', {
    slug: req.params.slug,
    tenant_id: before?.id ?? null,
    previous_status: before?.status ?? null,
  });
  res.json({ success: true, data: { message: `${req.params.slug} activated` } });
});

router.delete('/tenants/:slug', async (req, res) => {
  const before = lookupTenantBySlug(req.params.slug);
  const result = await deleteTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  if (before) clearPlanCache(before.id);
  const wsClosed = disconnectTenantWebSockets(req.params.slug);
  auditLog('tenant_deleted', req.superAdmin!.superAdminId, req.ip || 'unknown', {
    slug: req.params.slug,
    tenant_id: before?.id ?? null,
    previous_status: before?.status ?? null,
    websockets_closed: wsClosed,
  });
  res.json({ success: true, data: { message: `${req.params.slug} deleted`, websockets_closed: wsClosed } });
});

// ─── Force-disable 2FA on a tenant user (platform override) ─────────
//
// TP-post-enrichment-#7: There was no super-admin path to clear 2FA on a
// compromised tenant admin. The tenant-level /force-disable-2fa route only
// works if the actor is already logged in to that tenant as an admin — which
// is exactly the credential the attacker has stolen. This endpoint lets the
// platform super admin break-glass a tenant user whose 2FA device is lost
// or whose account is confirmed compromised.
//
// Safety rails:
//   - Super-admin auth already enforced by router.use(superAdminAuth) above.
//   - Only operates on ACTIVE tenants (not pending_deletion / deleted), so a
//     deleted tenant's archived DB is never touched.
//   - Clears totp_secret, totp_enabled, backup_codes, AND revokes every
//     session for that user so a stolen refresh token can't keep a zombie
//     session alive.
//   - Everything is written to master_audit_log with before/after fields,
//     including the tenant slug, target user id + username, and the super
//     admin actor — a full paper trail for post-incident review.
router.post('/tenants/:slug/users/:userId/force-disable-2fa', (req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) {
    return res.status(500).json({ success: false, message: 'Master DB unavailable' });
  }

  const slug = String(req.params.slug || '').toLowerCase().trim();
  const targetId = parseInt(String(req.params.userId || ''), 10);
  const actorId = req.superAdmin!.superAdminId;
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';

  if (!Number.isInteger(targetId) || targetId <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid user id' });
  }

  const tenant = masterDb
    .prepare("SELECT id, slug, status FROM tenants WHERE slug = ?")
    .get(slug) as AnyRow | undefined;
  if (!tenant) {
    return res.status(404).json({ success: false, message: 'Tenant not found' });
  }
  if (tenant.status !== 'active' && tenant.status !== 'suspended') {
    return res.status(400).json({
      success: false,
      message: `Cannot modify tenant in status "${tenant.status}"`,
    });
  }

  let tdb;
  try {
    tdb = getTenantDb(slug);
  } catch (err) {
    logger.error('Failed to open tenant DB for 2FA force-disable', {
      slug,
      error: err instanceof Error ? err.message : String(err),
    });
    return res.status(500).json({ success: false, message: 'Failed to open tenant database' });
  }

  const target = tdb
    .prepare('SELECT id, username, email, totp_enabled FROM users WHERE id = ? AND is_active = 1')
    .get(targetId) as AnyRow | undefined;
  if (!target) {
    return res.status(404).json({ success: false, message: 'User not found in tenant' });
  }

  const wasEnabled = Boolean(target.totp_enabled);

  // Atomic: clear 2FA AND revoke every session for this user in one transaction.
  // If either statement fails we want neither to land.
  const tx = tdb.transaction(() => {
    tdb
      .prepare(
        "UPDATE users SET totp_secret = NULL, totp_enabled = 0, backup_codes = NULL, updated_at = datetime('now') WHERE id = ?"
      )
      .run(targetId);
    tdb.prepare('DELETE FROM sessions WHERE user_id = ?').run(targetId);
  });
  try {
    tx();
  } catch (err) {
    logger.error('Force-disable 2FA transaction failed', {
      slug,
      targetId,
      error: err instanceof Error ? err.message : String(err),
    });
    return res.status(500).json({ success: false, message: 'Failed to disable 2FA' });
  }

  auditLog('tenant_user_2fa_force_disabled', actorId, ip, {
    tenant_slug: slug,
    tenant_id: tenant.id,
    target_user_id: target.id,
    target_username: target.username,
    target_email: target.email,
    was_2fa_enabled: wasEnabled,
    sessions_revoked: true,
  });

  res.json({
    success: true,
    data: {
      message: `2FA force-disabled for ${target.username} (${slug}). Sessions revoked.`,
      tenant_slug: slug,
      user_id: target.id,
      was_2fa_enabled: wasEnabled,
    },
  });
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

// @audit-fixed: Previously this route silently DELETEd any super_admin_sessions
// row by id with no context — no record of WHOSE session was revoked, no
// distinction between "I revoked my own session" and "I kicked another super
// admin out of the platform". We now look up the target session FIRST so the
// audit trail captures the target user, and we record whether the actor was
// revoking themselves (acceptable) or another super admin (security event).
router.delete('/sessions/:id', (req, res) => {
  const masterDb = getMasterDb()!;
  const target = masterDb
    .prepare(
      `SELECT s.id, s.super_admin_id, sa.username
         FROM super_admin_sessions s
         LEFT JOIN super_admins sa ON sa.id = s.super_admin_id
        WHERE s.id = ?`
    )
    .get(req.params.id) as { id: string; super_admin_id: number; username: string | null } | undefined;
  if (!target) {
    return res.status(404).json({ success: false, message: 'Session not found' });
  }
  const actorId = req.superAdmin!.superAdminId;
  masterDb.prepare('DELETE FROM super_admin_sessions WHERE id = ?').run(req.params.id);
  auditLog('session_revoked', actorId, req.ip || 'unknown', {
    sessionId: req.params.id,
    target_super_admin_id: target.super_admin_id,
    target_username: target.username,
    revoked_self: target.super_admin_id === actorId,
  });
  res.json({ success: true, data: { revoked: true } });
});

// ─── Announcements ──────────────────────────────────────────────────

router.get('/announcements', (_req, res) => {
  const masterDb = getMasterDb()!;
  const items = masterDb.prepare('SELECT * FROM announcements WHERE is_active = 1 ORDER BY created_at DESC').all();
  res.json({ success: true, data: { announcements: items } });
});

// @audit-fixed: POST /announcements previously had no input validation —
// title and body could be any type, any length. An attacker (or buggy client)
// could store a 50MB string per row, exhaust DB space, or attempt stored
// XSS. The frontend escapes when rendering, but DB-side limits are also
// required as defense in depth and to prevent storage abuse.
const ANNOUNCEMENT_TITLE_MAX = 200;
const ANNOUNCEMENT_BODY_MAX = 10_000;
router.post('/announcements', (req, res) => {
  const masterDb = getMasterDb()!;
  const { title, body } = req.body ?? {};
  if (typeof title !== 'string' || title.trim().length === 0) {
    return res.status(400).json({ success: false, message: 'Title must be a non-empty string' });
  }
  if (typeof body !== 'string' || body.trim().length === 0) {
    return res.status(400).json({ success: false, message: 'Body must be a non-empty string' });
  }
  if (title.length > ANNOUNCEMENT_TITLE_MAX) {
    return res.status(400).json({ success: false, message: `Title exceeds ${ANNOUNCEMENT_TITLE_MAX} chars` });
  }
  if (body.length > ANNOUNCEMENT_BODY_MAX) {
    return res.status(400).json({ success: false, message: `Body exceeds ${ANNOUNCEMENT_BODY_MAX} chars` });
  }
  const trimmedTitle = title.trim();
  const trimmedBody = body.trim();
  const result = masterDb.prepare('INSERT INTO announcements (title, body) VALUES (?, ?)').run(trimmedTitle, trimmedBody);
  const item = masterDb.prepare('SELECT * FROM announcements WHERE id = ?').get(result.lastInsertRowid);
  auditLog('announcement_created', req.superAdmin!.superAdminId, req.ip || 'unknown', { title: trimmedTitle, body_chars: trimmedBody.length });
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

// @audit-fixed: Previously this route accepted any tenant_slug query param
// and used it as a literal in `tenant_slug = ?`. SQLi-safe (parameterized),
// but it returned an empty result for unknown slugs, giving an attacker the
// same response shape whether the tenant exists or not — a useful side-channel
// for slug enumeration. We now validate and reject the request when the slug
// doesn't match a real tenant. We also reject query strings whose length or
// shape clearly can't match a real tenant slug to keep junk out of the SQL.
router.get('/tenant-auth-events', (req, res) => {
  const masterDb = getMasterDb()!;
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const limit = Math.min(Math.max(1, parseInt(req.query.limit as string) || 50), 500);
  const offset = (page - 1) * limit;

  const conditions: string[] = [];
  const params: any[] = [];

  if (req.query.tenant_slug) {
    const slugQ = String(req.query.tenant_slug);
    if (slugQ.length > 30 || !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slugQ)) {
      return res.status(400).json({ success: false, message: 'Invalid tenant_slug' });
    }
    const exists = masterDb.prepare('SELECT 1 FROM tenants WHERE slug = ?').get(slugQ);
    if (!exists) {
      return res.status(404).json({ success: false, message: 'Tenant not found' });
    }
    conditions.push('tenant_slug = ?');
    params.push(slugQ);
  }
  if (req.query.ip) {
    const ipQ = String(req.query.ip);
    if (ipQ.length > 64) {
      return res.status(400).json({ success: false, message: 'Invalid ip' });
    }
    conditions.push('ip_address = ?');
    params.push(ipQ);
  }
  if (req.query.event) {
    const evQ = String(req.query.event);
    if (evQ.length > 64) {
      return res.status(400).json({ success: false, message: 'Invalid event' });
    }
    conditions.push('event = ?');
    params.push(evQ);
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

// @audit-fixed: PUT /config previously had three bugs:
//   (a) it read req.superAdminId (does not exist; correct path is
//       req.superAdmin.superAdminId), so every audit row was super_admin_id
//       NULL — i.e. unattributable;
//   (b) it returned `{success, message}` with no `data` field, breaking the
//       documented `{success, data}` shape contract every other route honors;
//   (c) unknown body keys were silently dropped, so a buggy or malicious
//       client could believe a write succeeded when nothing happened.
// All three are fixed below.
router.put('/config', (req: Request, res: Response) => {
  const masterDb = (req as any).masterDb || getMasterDb();
  if (!masterDb) {
    res.status(500).json({ success: false, message: 'Master DB not available' });
    return;
  }

  const updates = req.body;
  if (!updates || typeof updates !== 'object' || Array.isArray(updates)) {
    res.status(400).json({ success: false, message: 'Object body required' });
    return;
  }

  // Only allow known config keys (hard-coded whitelist — must match
  // master DB platform_config schema). Reject unknown keys with 400.
  const ALLOWED_CONFIG_KEYS = new Set(['management_api_enabled', 'management_rate_limit_bypass']);
  const rejected: string[] = [];
  for (const key of Object.keys(updates)) {
    if (!ALLOWED_CONFIG_KEYS.has(key)) rejected.push(key);
  }
  if (rejected.length > 0) {
    return res.status(400).json({
      success: false,
      message: `disallowed config key(s): ${rejected.join(', ')}`,
    });
  }

  const stmt = masterDb.prepare('INSERT OR REPLACE INTO platform_config (key, value, updated_at) VALUES (?, ?, datetime(?))');
  const applied: Record<string, string> = {};
  for (const [key, value] of Object.entries(updates)) {
    if (!ALLOWED_CONFIG_KEYS.has(key)) continue; // belt-and-suspenders
    const stringValue = String(value);
    stmt.run(key, stringValue, new Date().toISOString());
    applied[key] = stringValue;
  }

  // Audit log (uses the proper auditLog helper so attribution is correct).
  auditLog('update_config', req.superAdmin?.superAdminId ?? null, req.ip || req.socket?.remoteAddress || 'unknown', applied);

  res.json({ success: true, data: { applied } });
});

export default router;
