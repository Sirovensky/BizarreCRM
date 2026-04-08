import { Router, Request, Response, NextFunction } from 'express';
import fs from 'fs';
import path from 'path';
import os from 'os';
import bcrypt from 'bcryptjs';
import { config } from '../config.js';
import {
  getBackupSettings, updateBackupSettings, runBackup,
  listBackups, deleteBackup, listDrives,
} from '../services/backup.js';
import { audit } from '../utils/audit.js';

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

// Admin login rate limiting
const adminLoginAttempts = new Map<string, { count: number; until: number }>();

// Login endpoint (no auth required)
router.post('/login', (req: Request, res: Response) => {
  const db = req.db;
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const entry = adminLoginAttempts.get(ip);
  if (entry && entry.count >= 5 && Date.now() < entry.until) {
    return res.status(429).json({ success: false, message: 'Too many attempts. Try again in 15 minutes.' });
  }

  const { username, password } = req.body;
  if (!username || !password) return res.status(400).json({ success: false, message: 'Credentials required' });
  const user = db.prepare("SELECT password_hash FROM users WHERE username = ? AND role = 'admin' AND is_active = 1").get(username) as AnyRow | undefined;
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    const e = adminLoginAttempts.get(ip);
    if (!e || Date.now() > e.until) { adminLoginAttempts.set(ip, { count: 1, until: Date.now() + 15 * 60 * 1000 }); }
    else { e.count++; }
    audit(db, 'admin_login_failed', null, ip, { username });
    return res.status(401).json({ success: false, message: 'Invalid credentials' });
  }
  audit(db, 'admin_login_success', null, ip, { username });
  const token = generateToken();
  adminTokens.set(token, { user: username, expires: Date.now() + TOKEN_TTL });
  res.json({ success: true, data: { token } });
});

// Logout
router.post('/logout', (req: Request, res: Response) => {
  const token = (req.headers['x-admin-token'] as string) || '';
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

// POST /admin/backup — run now (with concurrency lock)
let backupRunning = false;
router.post('/backup', async (req, res) => {
  const db = req.db;
  if (backupRunning) {
    res.status(429).json({ success: false, message: 'Backup already in progress' });
    return;
  }
  backupRunning = true;
  try {
    const result = await runBackup(db);
    res.json({ success: result.success, data: result });
  } finally {
    backupRunning = false;
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
