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

router.use((req, res, next) => {
  // Skip auth for login endpoint
  if (req.path === '/login') return next();
  adminAuth(req, res, next);
});

// SECURITY: In multi-tenant mode, the filesystem browser, backup management,
// and server status endpoints are DISABLED for tenant admins.
// These expose server-level info (file paths, other tenants, .env location).
// Only the super-admin (via /master/api/) should manage backups in multi-tenant mode.
router.use((req: Request, res: Response, next: NextFunction) => {
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

  restoreInProgress = true;
  audit(db, 'admin_backup_restore_start', null, ip, { filename });

  try {
    const result = await restoreBackup(db, filename, {
      targetDbPath: config.dbPath,
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
      audit(db, 'admin_backup_restore_failed', null, ip, { filename, error: result.message });
      res.status(500).json({ success: false, message: result.message });
      return;
    }

    audit(db, 'admin_backup_restore_success', null, ip, {
      filename,
      hash: result.hash,
      safetyBackup: result.safetyBackup ? path.basename(result.safetyBackup) : undefined,
    });

    res.json({
      success: true,
      data: {
        message: 'Restore completed. Server must be restarted to reopen the DB handle.',
        hash: result.hash,
        safetyBackup: result.safetyBackup ? path.basename(result.safetyBackup) : undefined,
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
