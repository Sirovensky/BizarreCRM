import { Router, Request, Response, NextFunction } from 'express';
import fs from 'fs';
import path from 'path';
import os from 'os';
import bcrypt from 'bcryptjs';
import { config } from '../config.js';
import {
  getBackupSettings, updateBackupSettings, runBackup,
  listBackups, deleteBackup, listDrives,
  resolveBackupPath, restoreBackup,
  isTenantBackupRunning,
} from '../services/backup.js';
import { audit } from '../utils/audit.js';
import { logger } from '../utils/logger.js';
import { checkWindowRate, recordWindowFailure, clearRateLimit } from '../utils/rateLimiter.js';
import { authMiddleware } from '../middleware/auth.js';
import {
  requestTermination,
  confirmTerminationSlug,
  finalizeTermination,
  TERMINATION_GRACE_DAYS,
} from '../services/tenantTermination.js';

const router = Router();
const startTime = Date.now();
type AnyRow = Record<string, any>;

// Token-based admin auth (short-lived, in-memory)
const adminTokens = new Map<string, { user: string; expires: number }>();
const TOKEN_TTL = 30 * 60 * 1000; // 30 minutes

import crypto from 'crypto';

function generateToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

const ADMIN_LOGIN_MAX_ATTEMPTS = 5;
const ADMIN_LOGIN_WINDOW_MS = 15 * 60 * 1000; // 15 minutes

// Login endpoint (no auth required)
router.post('/login', async (req: Request, res: Response) => {
  const db = req.db;
  const adb = req.asyncDb;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (!checkWindowRate(db, 'admin_login', ip, ADMIN_LOGIN_MAX_ATTEMPTS, ADMIN_LOGIN_WINDOW_MS)) {
    return res.status(429).json({ success: false, message: 'Too many attempts. Try again in 15 minutes.' });
  }

  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ success: false, message: 'Credentials required' });
  const user = await adb.get<AnyRow>("SELECT password_hash FROM users WHERE username = ? AND role = 'admin' AND is_active = 1", username);
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    recordWindowFailure(db, 'admin_login', ip, ADMIN_LOGIN_WINDOW_MS);
    audit(db, 'admin_login_failed', null, ip, { username });
    return res.status(401).json({ success: false, message: 'Invalid credentials' });
  }
  audit(db, 'admin_login_success', null, ip, { username });
  const token = generateToken();
  adminTokens.set(token, { user: username, expires: Date.now() + TOKEN_TTL });
  res.json({ success: true, data: { token } });
});

// Logout (AL7: audit logout)
router.post('/logout', (req: Request, res: Response) => {
  const db = req.db;
  const token = (req.headers['x-admin-token'] as string) || '';
  const session = adminTokens.get(token);
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  if (session) {
    audit(db, 'admin_logout', null, ip, { username: session.user });
  }
  adminTokens.delete(token);
  res.json({ success: true });
});

// Auth middleware for all other admin routes
function adminAuth(req: Request, res: Response, next: NextFunction) {
  const token = (req.headers['x-admin-token'] as string) || '';
  const session = adminTokens.get(token);
  if (!session || session.expires < Date.now()) {
    adminTokens.delete(token);
    return res.status(401).json({ success: false, message: 'Not authenticated' });
  }
  // Extend session on activity
  session.expires = Date.now() + TOKEN_TTL;
  next();
}

// Clean expired tokens periodically
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of adminTokens) { if (v.expires < now) adminTokens.delete(k); }
}, 60_000);

// PROD59: Tenant self-service termination uses the tenant JWT (NOT the
// token-based admin-panel auth above). Mounted BEFORE both kill-switches so
// it's reachable from a shop's own Settings > Danger Zone in both single-
// tenant and multi-tenant mode. Role gate (admin) is enforced inline.
router.post(
  '/terminate-tenant',
  authMiddleware,
  async (req: Request, res: Response) => {
    const tenantDb = req.db;
    if (!tenantDb) {
      return res.status(500).json({ success: false, message: 'Database unavailable' });
    }
    if (!req.user) {
      return res.status(401).json({ success: false, message: 'Not authenticated' });
    }
    if (req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only shop administrators may terminate the account',
      });
    }

    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const action = req.body?.action;

    // ── Step 1: request token ─────────────────────────────────────────
    if (action === 'request') {
      if (!config.multiTenant || !req.tenantSlug || !req.tenantId) {
        audit(tenantDb, 'tenant_terminate_refused_single_tenant', req.user.id, ip, {});
        return res.status(400).json({
          success: false,
          message:
            'Self-service termination is only available in multi-tenant mode. Remove your self-hosted install manually.',
        });
      }
      const proto = req.protocol;
      const host = req.get('host') || `${req.tenantSlug}.${config.baseDomain}`;
      const appUrl = `${proto}://${host}`;
      const { token, expiresAt } = await requestTermination({
        slug: req.tenantSlug,
        tenantId: req.tenantId,
        adminUserId: req.user.id,
        adminUsername: req.user.username,
        adminEmail: req.user.email || null,
        tenantDb,
        appUrl,
        requestIp: ip,
      });
      audit(tenantDb, 'tenant_terminate_step1_request', req.user.id, ip, {
        slug: req.tenantSlug,
        expiresAt,
      });
      return res.json({ success: true, data: { token, expires_at: expiresAt } });
    }

    // ── Step 2: confirm slug ──────────────────────────────────────────
    if (action === 'confirm') {
      const token = typeof req.body?.token === 'string' ? req.body.token : '';
      const typedSlug = typeof req.body?.typed_slug === 'string' ? req.body.typed_slug : '';
      if (!token || !typedSlug) {
        return res
          .status(400)
          .json({ success: false, message: 'token and typed_slug are required' });
      }
      const result = confirmTerminationSlug(token, typedSlug);
      audit(tenantDb, 'tenant_terminate_step2_confirm', req.user.id, ip, {
        slug: req.tenantSlug,
        matched: result.ok,
      });
      if (!result.ok) {
        return res.status(400).json({ success: false, message: result.error });
      }
      return res.json({ success: true, data: { stage: 'slug_confirmed' } });
    }

    // ── Step 3: finalize ──────────────────────────────────────────────
    if (action === 'finalize') {
      const token = typeof req.body?.token === 'string' ? req.body.token : '';
      const typedSlug = typeof req.body?.typed_slug === 'string' ? req.body.typed_slug : '';
      const typedPhrase =
        typeof req.body?.typed_phrase === 'string' ? req.body.typed_phrase : '';
      if (!token || !typedSlug || !typedPhrase) {
        return res.status(400).json({
          success: false,
          message: 'token, typed_slug, and typed_phrase are required',
        });
      }
      audit(tenantDb, 'tenant_terminate_step3_finalize_attempt', req.user.id, ip, {
        slug: req.tenantSlug,
      });
      const result = await finalizeTermination({ token, typedSlug, typedPhrase });
      if (!result.ok) {
        audit(tenantDb, 'tenant_terminate_step3_finalize_rejected', req.user.id, ip, {
          slug: req.tenantSlug,
          reason: result.error,
        });
        return res.status(400).json({ success: false, message: result.error });
      }
      // Audit writes below may race the rename — swallow any failure since
      // the termination itself succeeded and is already audited in the
      // master_audit_log via executeTermination().
      try {
        audit(tenantDb, 'tenant_terminate_finalized', req.user.id, ip, {
          slug: req.tenantSlug,
          deletionScheduledAt: result.data.deletionScheduledAt,
          permanentDeleteAt: result.data.permanentDeleteAt,
        });
      } catch {}
      return res.json({
        success: true,
        deletion_scheduled_at: result.data.deletionScheduledAt,
        permanent_delete_at: result.data.permanentDeleteAt,
        grace_days: TERMINATION_GRACE_DAYS,
      });
    }

    return res
      .status(400)
      .json({ success: false, message: 'Invalid action — must be request, confirm, or finalize' });
  },
);

router.use((req, res, next) => {
  // Skip auth for login endpoint + tenant self-termination endpoint (handled above)
  if (req.path === '/login' || req.path === '/terminate-tenant') return next();
  adminAuth(req, res, next);
});

// SECURITY: In multi-tenant mode, the filesystem browser, backup management,
// and server status endpoints are DISABLED for tenant admins.
// These expose server-level info (file paths, other tenants, .env location).
// Only the super-admin (via /master/api/) should manage backups in multi-tenant mode.
router.use((req: Request, res: Response, next: NextFunction) => {
  // PROD59: the tenant self-termination endpoint is handled earlier in the
  // router and must bypass this kill-switch — super-admin backup routes
  // stay blocked, tenant self-service termination is allowed.
  if (req.path === '/terminate-tenant') return next();
  if (config.multiTenant) {
    return res.status(403).json({
      success: false,
      message: 'Server administration is managed by the platform administrator in multi-tenant mode. Use Settings for shop-level configuration.',
    });
  }
  next();
});

// GET /admin/status
router.get('/status', (req, res) => {
  const db = req.db;
  const dbSize = fs.existsSync(config.dbPath) ? fs.statSync(config.dbPath).size : 0;
  const uploadsSize = fs.existsSync(config.uploadsPath)
    ? fs.readdirSync(config.uploadsPath).reduce((sum, f) => {
        try { return sum + fs.statSync(path.join(config.uploadsPath, f)).size; } catch { return sum; }
      }, 0)
    : 0;

  res.json({
    success: true,
    data: {
      uptime: Math.floor((Date.now() - startTime) / 1000),
      dbSize,
      uploadsSize,
      port: config.port,
      platform: process.platform,
      hostname: require('os').hostname(),
      nodeVersion: process.version,
      nodeEnv: config.nodeEnv,
      backup: getBackupSettings(db),
    },
  });
});

// GET /admin/drives
router.get('/drives', (_req, res) => {
  res.json({ success: true, data: listDrives() });
});

// GET /admin/drives/browse?path=...
router.get('/drives/browse', (req, res) => {
  const dirPath = (req.query.path as string) || (process.platform === 'win32' ? 'C:\\' : '/');

  // Block access to sensitive system directories
  const blocked = ['/etc', '/proc', '/sys', '/dev', '/root', 'C:\\Windows', 'C:\\Program Files', 'C:\\ProgramData'];
  const normalized = path.resolve(dirPath);
  if (blocked.some(b => normalized.toLowerCase().startsWith(b.toLowerCase()))) {
    res.json({ success: true, data: { current: dirPath, folders: [] } });
    return;
  }

  try {
    // Resolve symlinks to check real path
    const realDir = fs.existsSync(dirPath) ? fs.realpathSync(dirPath) : dirPath;
    if (blocked.some(b => realDir.toLowerCase().startsWith(path.normalize(b).toLowerCase()))) {
      res.json({ success: true, data: { current: dirPath, folders: [] } });
      return;
    }
    const entries = fs.readdirSync(realDir, { withFileTypes: true })
      .filter(d => d.isDirectory() && !d.name.startsWith('.') && !d.name.startsWith('$'))
      .map(d => {
        const fullPath = path.join(realDir, d.name);
        try {
          const realSub = fs.realpathSync(fullPath);
          if (blocked.some(b => realSub.toLowerCase().startsWith(path.normalize(b).toLowerCase()))) return null;
          return { name: d.name, path: fullPath };
        } catch { return { name: d.name, path: fullPath }; }
      })
      .filter(Boolean)
      .slice(0, 100);
    res.json({ success: true, data: { current: dirPath, folders: entries } });
  } catch {
    res.json({ success: true, data: { current: dirPath, folders: [] } });
  }
});

// POST /admin/drives/mkdir
router.post('/drives/mkdir', (req, res) => {
  const { path: dirPath, name } = req.body;
  if (!dirPath || !name) return res.status(400).json({ success: false, message: 'path and name required' });

  // Reject path traversal and path separators in name
  if (name.includes('..') || name.includes('/') || name.includes('\\')) {
    return res.status(400).json({ success: false, message: 'Invalid folder name' });
  }

  const fullPath = path.resolve(dirPath, name);

  // Block sensitive system directories (same check as browse endpoint)
  const blocked = ['/etc', '/proc', '/sys', '/dev', '/root', 'C:\\Windows', 'C:\\Program Files', 'C:\\ProgramData'];
  if (blocked.some(b => fullPath.toLowerCase().startsWith(path.normalize(b).toLowerCase()))) {
    return res.status(403).json({ success: false, message: 'Cannot create folders in system directories' });
  }

  try {
    fs.mkdirSync(fullPath, { recursive: true });
    res.json({ success: true, data: { path: fullPath } });
  } catch (err: unknown) {
    res.status(500).json({ success: false, message: err instanceof Error ? err.message : 'Failed to create folder' });
  }
});

// GET /admin/backups
router.get('/backups', (req, res) => {
  const db = req.db;
  res.json({ success: true, data: listBackups(db) });
});

// POST /admin/backup — run now. Per-tenant lock lives inside runBackup() itself
// (acquires/releases via acquireTenantBackupLock). The route just needs to
// fail-fast if this tenant already has a backup in flight. In single-tenant
// mode the lock key is "__single__".
router.post('/backup', async (req, res) => {
  const db = req.db;
  if (isTenantBackupRunning()) {
    res.status(429).json({ success: false, message: 'Backup already in progress for this shop' });
    return;
  }
  const result = await runBackup(db);
  res.json({ success: result.success, data: result });
});

// GET /admin/backups/:filename/download — stream the encrypted file for off-site copy.
// Requires adminAuth (already applied via router.use above).
router.get('/backups/:filename/download', (req: Request, res: Response) => {
  const db = req.db;
  const filename = String(req.params.filename || '');
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  // Reject path traversal
  if (!filename || filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    res.status(400).json({ success: false, message: 'Invalid filename' });
    return;
  }

  const fullPath = resolveBackupPath(db, filename);
  if (!fullPath) {
    res.status(404).json({ success: false, message: 'Backup not found' });
    return;
  }

  audit(db, 'admin_backup_download', null, ip, { filename });

  const stat = fs.statSync(fullPath);
  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Length', stat.size);
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

  const stream = fs.createReadStream(fullPath);
  stream.on('error', (err) => {
    logger.error('Backup download stream error', { module: 'admin', error: err.message });
    if (!res.headersSent) {
      res.status(500).json({ success: false, message: 'Stream error' });
    }
  });
  stream.pipe(res);
});

// POST /admin/backups/:filename/restore — decrypt, integrity-check, safety-backup, swap in.
// Simple global restore mutex: one restore at a time.
let restoreInProgress = false;
router.post('/backups/:filename/restore', async (req: Request, res: Response) => {
  const db = req.db;
  const filename = String(req.params.filename || '');
  const ip = req.ip || req.socket.remoteAddress || 'unknown';

  if (!filename || filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    res.status(400).json({ success: false, message: 'Invalid filename' });
    return;
  }
  if (restoreInProgress) {
    res.status(429).json({ success: false, message: 'Another restore is already in progress' });
    return;
  }
  // Don't restore while a backup is running for this tenant — they race for the same file.
  if (isTenantBackupRunning()) {
    res.status(409).json({ success: false, message: 'Cannot restore while a backup is running' });
    return;
  }

  // SEC-H60: the admin panel is the single-tenant route, so target tenant is
  // always the stable placeholder `bizarre-crm` / 0. Multi-tenant restores
  // flow through a separate super-admin path that would thread the real
  // (slug, tenantId) via req.params.slug lookup — that path isn't wired yet
  // (see super-admin.routes.ts backup management section) and admin.routes
  // is explicitly blocked in multi-tenant mode by the kill-switch above, so
  // this placeholder pair is safe for all callers that reach this handler.
  const expectedSlug = 'bizarre-crm';
  const expectedTenantId = 0;
  // Caller may explicitly opt in to restoring a pre-SEC-H60 backup that has
  // no HMAC sidecar. Default is to REFUSE — the UI must send the flag
  // alongside an operator-facing confirmation dialog.
  const allowUnsigned = req.body?.allow_unsigned === true;

  restoreInProgress = true;
  audit(db, 'admin_backup_restore_start', null, ip, { filename, allowUnsigned });

  try {
    const result = await restoreBackup(db, filename, {
      targetDbPath: config.dbPath,
      expectedSlug,
      expectedTenantId,
      allowUnsigned,
      onBeforeReplace: () => {
        // Close the request DB handle so the file swap can rename over it.
        // The request `db` is the single-tenant shared handle; closing it here
        // means the process must re-open it. We log loud and rely on the
        // next request to trip the pool's lazy-reopen path. In single-tenant
        // mode the handle is owned by index.ts.
        try {
          if (typeof (db as any).close === 'function') {
            (db as any).close();
          }
        } catch (err) {
          logger.warn('Could not close live DB before restore swap', {
            module: 'admin',
            error: err instanceof Error ? err.message : String(err),
          });
        }
      },
    });

    if (!result.success) {
      audit(db, 'admin_backup_restore_failed', null, ip, {
        filename,
        error: result.message,
        // Surface the unsigned marker in the audit trail so an operator
        // reviewing the log can see why the request was rejected.
        unsigned: Boolean(result.unsigned),
      });
      // 400 for user-correctable errors (wrong tenant, unsigned-without-flag,
      // tamper detection) — 500 only for genuine server faults. The client
      // UI reads `success:false` + `message` for the user-facing toast.
      const status = result.unsigned || /sidecar|tenant|slug/i.test(result.message) ? 400 : 500;
      res.status(status).json({ success: false, message: result.message, unsigned: result.unsigned });
      return;
    }

    audit(db, 'admin_backup_restore_success', null, ip, {
      filename,
      hash: result.hash,
      safetyBackup: result.safetyBackup ? path.basename(result.safetyBackup) : undefined,
      unsigned: Boolean(result.unsigned),
      allowUnsigned,
    });

    res.json({
      success: true,
      data: {
        message: 'Restore completed. Server must be restarted to reopen the DB handle.',
        hash: result.hash,
        safetyBackup: result.safetyBackup ? path.basename(result.safetyBackup) : undefined,
        unsigned: Boolean(result.unsigned),
      },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    audit(db, 'admin_backup_restore_failed', null, ip, { filename, error: msg });
    logger.error('Restore route crashed', { module: 'admin', error: msg });
    res.status(500).json({ success: false, message: msg });
  } finally {
    restoreInProgress = false;
  }
});

// PUT /admin/backup-settings
router.put('/backup-settings', (req, res) => {
  const db = req.db;
  updateBackupSettings(db, req.body);
  res.json({ success: true, data: getBackupSettings(db) });
});

// DELETE /admin/backups/:filename
router.delete('/backups/:filename', (req, res) => {
  const db = req.db;
  const filename = req.params.filename;
  // Prevent path traversal
  if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    res.status(400).json({ success: false, message: 'Invalid filename' });
    return;
  }
  deleteBackup(db, filename);
  res.json({ success: true });
});

export default router;
