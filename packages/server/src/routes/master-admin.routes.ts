import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { masterAuthMiddleware, type MasterAuthPayload } from '../middleware/masterAuth.js';
import { provisionTenant, suspendTenant, activateTenant, deleteTenant, listTenants } from '../services/tenant-provisioning.js';
import { getTenantDb, getPoolStats } from '../db/tenant-pool.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('master-admin');

// Q4: Hard-coded whitelist of columns that master admins may set on a tenant
// row via PUT /tenants/:slug. Declared inside this file (NOT imported from
// shared) so the authoritative SQLi surface lives next to the UPDATE.
// Unit-test note: every key MUST correspond to an existing column on the
// `tenants` table; any request key NOT in this set must be rejected with 400.
const MASTER_TENANT_UPDATE_WHITELIST: ReadonlySet<string> = new Set([
  'plan',
  'max_users',
  'max_tickets_month',
  'storage_limit_mb',
  'name',
]);

// @audit-fixed: this entire router is LEGACY and is no longer mounted in
// index.ts (see commit message "Legacy master-admin routes REMOVED — security
// risk (no 2FA, default password 'changeme123')"). It's preserved on disk so
// older imports compile, but as a hardening pass we add an additional kill
// switch here so even if a future refactor accidentally mounts the router
// again, every request is rejected. The kill switch can be lifted in code by
// setting the env var below to "true" — done deliberately by an operator.
const MASTER_ADMIN_LEGACY_DISABLED = process.env.MASTER_ADMIN_LEGACY_ENABLED !== 'true';

router.use((_req, res, next) => {
  if (MASTER_ADMIN_LEGACY_DISABLED) {
    return res.status(410).json({
      success: false,
      message: 'Legacy master-admin API removed. Use /super-admin/api/ instead.',
    });
  }
  next();
});

// Guard: only available in multi-tenant mode
router.use((req, res, next) => {
  if (!config.multiTenant) {
    return res.status(404).json({ success: false, message: 'Multi-tenant mode is not enabled' });
  }
  next();
});

// ─── Master admin login rate limiting ────────────────────────────────
const masterLoginFailures = new Map<string, { count: number; lockedUntil: number }>();
const MASTER_LOGIN_MAX = 5;
const MASTER_LOGIN_WINDOW = 15 * 60 * 1000; // 15 minutes

// Cleanup stale entries every 10 minutes
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of masterLoginFailures) {
    if (v.lockedUntil < now) masterLoginFailures.delete(k);
  }
}, 10 * 60 * 1000);

// ─── Public: Login ──────────────────────────────────────────────────

// @audit-fixed: Even though this router is dead-code, the login handler had:
//   (a) no constant-time bcrypt path on user-not-found — clear timing oracle
//       to enumerate super admin usernames;
//   (b) JWT issued without 2FA, with an 8h TTL, no session table entry;
//   (c) rate limit kept in a process-local Map — restart wipes the lockout.
// We add a constant-time bcrypt compare on the not-found path. The other
// issues are intentionally addressed by the kill switch above (rejecting all
// requests) — fixing them in the legacy handler would imply we plan to use it.
const MASTER_LOGIN_DUMMY_HASH = '$2a$12$LJ3m4ys3Rl4gTMGaUpVWaeOpMxDkx5JH3gXsIQr7gJSNVMmOG0OO2';

router.post('/login', async (req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(404).json({ success: false, message: 'Multi-tenant not enabled' });

  // Rate limiting
  const ip = req.ip || 'unknown';
  const bucket = masterLoginFailures.get(ip);
  if (bucket && bucket.lockedUntil > Date.now() && bucket.count >= MASTER_LOGIN_MAX) {
    return res.status(429).json({ success: false, message: 'Too many login attempts. Try again later.' });
  }

  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ success: false, message: 'Username and password required' });
  // Guard against bcrypt DoS (bcrypt has 72-byte max anyway, but prevent multi-MB strings)
  if (typeof password !== 'string' || password.length > 128 || typeof username !== 'string' || username.length > 64) {
    return res.status(400).json({ success: false, message: 'Invalid credentials format' });
  }

  const admin = masterDb.prepare('SELECT * FROM super_admins WHERE username = ? AND is_active = 1').get(username) as any;
  if (!admin) {
    // Constant-time bcrypt path so attacker cannot enumerate usernames via timing.
    await bcrypt.compare(password, MASTER_LOGIN_DUMMY_HASH);
    const now = Date.now();
    const existing = masterLoginFailures.get(ip);
    masterLoginFailures.set(ip, { count: (existing?.count || 0) + 1, lockedUntil: now + MASTER_LOGIN_WINDOW });
    return res.status(401).json({ success: false, message: 'Invalid credentials' });
  }

  const valid = await bcrypt.compare(password, admin.password_hash);
  if (!valid) {
    const now = Date.now();
    const existing = masterLoginFailures.get(ip);
    masterLoginFailures.set(ip, { count: (existing?.count || 0) + 1, lockedUntil: now + MASTER_LOGIN_WINDOW });
    return res.status(401).json({ success: false, message: 'Invalid credentials' });
  }

  // Clear failures on success
  masterLoginFailures.delete(ip);

  const payload: MasterAuthPayload = { superAdminId: admin.id, username: admin.username, role: 'super_admin' };
  const token = jwt.sign(payload, config.superAdminSecret, { expiresIn: '8h' });

  // Audit
  masterDb.prepare('INSERT INTO master_audit_log (super_admin_id, action, ip_address) VALUES (?, ?, ?)').run(admin.id, 'login', req.ip);

  res.json({ success: true, data: { token, username: admin.username, email: admin.email } });
});

// ─── Protected routes ───────────────────────────────────────────────

router.use(masterAuthMiddleware);

// GET /dashboard — aggregate stats
router.get('/dashboard', (_req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Database unavailable' });

  const totalTenants = (masterDb.prepare("SELECT COUNT(*) as c FROM tenants WHERE status != 'deleted'").get() as any).c;
  const activeTenants = (masterDb.prepare("SELECT COUNT(*) as c FROM tenants WHERE status = 'active'").get() as any).c;
  const suspendedTenants = (masterDb.prepare("SELECT COUNT(*) as c FROM tenants WHERE status = 'suspended'").get() as any).c;

  const planCounts = masterDb.prepare(
    "SELECT plan, COUNT(*) as count FROM tenants WHERE status != 'deleted' GROUP BY plan"
  ).all();

  const pool = getPoolStats();

  // Total DB size
  let totalDbSizeMb = 0;
  if (fs.existsSync(config.tenantDataDir)) {
    const files = fs.readdirSync(config.tenantDataDir).filter(f => f.endsWith('.db'));
    for (const f of files) {
      try {
        totalDbSizeMb += fs.statSync(path.join(config.tenantDataDir, f)).size / (1024 * 1024);
      } catch {}
    }
  }

  res.json({
    success: true,
    data: {
      total_tenants: totalTenants,
      active_tenants: activeTenants,
      suspended_tenants: suspendedTenants,
      plan_distribution: planCounts,
      pool_stats: pool,
      total_db_size_mb: Math.round(totalDbSizeMb * 100) / 100,
    },
  });
});

// GET /tenants — list all tenants
router.get('/tenants', (req, res) => {
  const { status, plan } = req.query as Record<string, string>;
  const tenants = listTenants({ status, plan });

  // Enrich with DB size
  const enriched = tenants.map((t: any) => {
    let dbSizeMb = 0;
    try {
      const dbPath = path.join(config.tenantDataDir, t.db_path);
      dbSizeMb = Math.round(fs.statSync(dbPath).size / (1024 * 1024) * 100) / 100;
    } catch {}
    return { ...t, db_size_mb: dbSizeMb };
  });

  res.json({ success: true, data: { tenants: enriched } });
});

// @audit-fixed: Previously defaulted admin_password to the literal string
// 'changeme123' if the caller omitted it. That meant ANY tenant created via
// this legacy route had an attacker-known initial password until the shop
// owner manually changed it. We now require an admin_password and reject
// shorter-than-10-character passwords. (The router-level kill switch above
// blocks the route entirely; this is the second line of defense in case the
// kill switch is disabled.)
const MASTER_ADMIN_INITIAL_PASSWORD_MIN = 10;

// POST /tenants — create tenant
router.post('/tenants', async (req, res) => {
  const { slug, shop_name, admin_email, admin_password, plan, admin_first_name, admin_last_name } = req.body;

  if (typeof admin_password !== 'string' || admin_password.length < MASTER_ADMIN_INITIAL_PASSWORD_MIN) {
    return res.status(400).json({
      success: false,
      message: `admin_password is required and must be at least ${MASTER_ADMIN_INITIAL_PASSWORD_MIN} characters. The legacy fallback to "changeme123" has been removed.`,
    });
  }
  if (admin_password.length > 128) {
    return res.status(400).json({ success: false, message: 'admin_password too long' });
  }

  const result = await provisionTenant({
    slug: slug?.toLowerCase().trim(),
    name: shop_name,
    adminEmail: admin_email,
    adminPassword: admin_password,
    adminFirstName: admin_first_name,
    adminLastName: admin_last_name,
    plan,
  });

  if (!result.success) {
    return res.status(400).json({ success: false, message: result.error });
  }

  // Audit
  const masterDb = getMasterDb()!;
  const superAdmin = req.superAdmin!;
  masterDb.prepare('INSERT INTO master_audit_log (super_admin_id, action, entity_type, entity_id) VALUES (?, ?, ?, ?)').run(
    superAdmin.superAdminId, 'create_tenant', 'tenant', result.slug,
  );

  res.status(201).json({
    success: true,
    data: { tenant_id: result.tenantId, slug: result.slug, url: `https://${result.slug}.${config.baseDomain}` },
  });
});

// GET /tenants/:slug — tenant detail
router.get('/tenants/:slug', (req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Database unavailable' });

  const tenant = masterDb.prepare('SELECT * FROM tenants WHERE slug = ?').get(req.params.slug) as any;
  if (!tenant) return res.status(404).json({ success: false, message: 'Tenant not found' });

  // Get stats from tenant DB
  let userCount = 0;
  let ticketCount = 0;
  let customerCount = 0;
  try {
    const tdb = getTenantDb(tenant.slug);
    userCount = (tdb.prepare('SELECT COUNT(*) as c FROM users WHERE is_active = 1').get() as any).c;
    ticketCount = (tdb.prepare('SELECT COUNT(*) as c FROM tickets WHERE is_deleted = 0').get() as any).c;
    customerCount = (tdb.prepare('SELECT COUNT(*) as c FROM customers WHERE is_deleted = 0').get() as any).c;
  } catch {}

  let dbSizeMb = 0;
  try {
    dbSizeMb = Math.round(fs.statSync(path.join(config.tenantDataDir, tenant.db_path)).size / (1024 * 1024) * 100) / 100;
  } catch {}

  res.json({
    success: true,
    data: {
      ...tenant,
      user_count: userCount,
      ticket_count: ticketCount,
      customer_count: customerCount,
      db_size_mb: dbSizeMb,
    },
  });
});

// PUT /tenants/:slug — update tenant
// Q4: Reject any unknown body key with 400 before we reach the dynamic UPDATE.
// The in-file whitelist (MASTER_TENANT_UPDATE_WHITELIST) is the only source
// of truth for which columns can be written; any refactor that drops it will
// fail loudly here instead of opening a live SQLi hole.
router.put('/tenants/:slug', (req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Database unavailable' });

  const errors: string[] = [];
  if (!req.body || typeof req.body !== 'object') {
    return res.status(400).json({ success: false, message: 'Request body must be an object' });
  }

  // Q4: whitelist check BEFORE building the UPDATE — explicit rejection.
  for (const key of Object.keys(req.body)) {
    if (!MASTER_TENANT_UPDATE_WHITELIST.has(key)) {
      errors.push(`unknown or disallowed field: ${key}`);
    }
  }
  if (errors.length > 0) {
    return res.status(400).json({ success: false, message: errors.join('; ') });
  }

  // Whitelist approach: only hardcoded field names, values from user input
  const allowedFields: Record<string, any> = {};
  if (req.body.plan !== undefined) allowedFields['plan'] = req.body.plan;
  if (req.body.max_users !== undefined) allowedFields['max_users'] = req.body.max_users;
  if (req.body.max_tickets_month !== undefined) allowedFields['max_tickets_month'] = req.body.max_tickets_month;
  if (req.body.storage_limit_mb !== undefined) allowedFields['storage_limit_mb'] = req.body.storage_limit_mb;
  if (req.body.name !== undefined) allowedFields['name'] = req.body.name;

  const keys = Object.keys(allowedFields);
  if (keys.length === 0) return res.status(400).json({ success: false, message: 'No fields to update' });

  // Q4: Final paranoid check — every key passed to string interpolation MUST
  // be in the in-file whitelist. Belt-and-suspenders.
  for (const k of keys) {
    if (!MASTER_TENANT_UPDATE_WHITELIST.has(k)) {
      logger.error('master tenant update blocked: whitelist bypass attempt', { key: k, slug: req.params.slug });
      return res.status(400).json({ success: false, message: `disallowed field: ${k}` });
    }
  }

  // keys are from our hardcoded whitelist, safe for interpolation
  const setClause = keys.map(k => `${k} = ?`).join(', ');
  const params = keys.map(k => allowedFields[k]);
  params.push(req.params.slug);

  masterDb.prepare(`UPDATE tenants SET ${setClause}, updated_at = datetime('now') WHERE slug = ?`).run(...params);
  const tenant = masterDb.prepare('SELECT * FROM tenants WHERE slug = ?').get(req.params.slug);
  res.json({ success: true, data: tenant });
});

// POST /tenants/:slug/suspend
router.post('/tenants/:slug/suspend', (req, res) => {
  const result = suspendTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  res.json({ success: true, data: { message: `${req.params.slug} suspended` } });
});

// POST /tenants/:slug/activate
router.post('/tenants/:slug/activate', (req, res) => {
  const result = activateTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });
  res.json({ success: true, data: { message: `${req.params.slug} activated` } });
});

// DELETE /tenants/:slug
router.delete('/tenants/:slug', async (req, res) => {
  const result = await deleteTenant(req.params.slug);
  if (!result.success) return res.status(400).json({ success: false, message: result.error });

  const masterDb = getMasterDb()!;
  const superAdmin = req.superAdmin!;
  masterDb.prepare('INSERT INTO master_audit_log (super_admin_id, action, entity_type, entity_id) VALUES (?, ?, ?, ?)').run(
    superAdmin.superAdminId, 'delete_tenant', 'tenant', req.params.slug,
  );

  res.json({ success: true, data: { message: `${req.params.slug} deleted` } });
});

// GET /health — system health
router.get('/health', (_req, res) => {
  const pool = getPoolStats();
  const memUsage = process.memoryUsage();

  res.json({
    success: true,
    data: {
      uptime_seconds: Math.floor(process.uptime()),
      memory_mb: {
        rss: Math.round(memUsage.rss / 1024 / 1024),
        heap_used: Math.round(memUsage.heapUsed / 1024 / 1024),
        heap_total: Math.round(memUsage.heapTotal / 1024 / 1024),
      },
      pool: pool,
      node_version: process.version,
    },
  });
});

// GET /announcements
router.get('/announcements', (_req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Database unavailable' });
  const items = masterDb.prepare('SELECT * FROM announcements ORDER BY created_at DESC').all();
  res.json({ success: true, data: { announcements: items } });
});

// POST /announcements
router.post('/announcements', (req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Database unavailable' });
  const { title, body } = req.body;
  if (!title || !body) return res.status(400).json({ success: false, message: 'Title and body required' });
  const result = masterDb.prepare('INSERT INTO announcements (title, body) VALUES (?, ?)').run(title, body);
  const item = masterDb.prepare('SELECT * FROM announcements WHERE id = ?').get(result.lastInsertRowid);
  res.status(201).json({ success: true, data: item });
});

// GET /audit-log
// AL2: Defense-in-depth — although router.use(masterAuthMiddleware) above
// already gates every subsequent route, we attach the middleware explicitly
// here so any future refactor that reorders or drops the global router.use()
// cannot silently expose the super-admin audit log to unauthenticated clients.
// This route MUST NEVER be reachable without a valid master admin JWT.
router.get('/audit-log', masterAuthMiddleware, (req, res) => {
  const masterDb = getMasterDb();
  if (!masterDb) return res.status(500).json({ success: false, message: 'Database unavailable' });
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
  const logs = masterDb.prepare(`
    SELECT al.*, sa.username as admin_username
    FROM master_audit_log al
    LEFT JOIN super_admins sa ON sa.id = al.super_admin_id
    ORDER BY al.created_at DESC LIMIT ?
  `).all(limit);
  res.json({ success: true, data: { logs } });
});

export default router;
