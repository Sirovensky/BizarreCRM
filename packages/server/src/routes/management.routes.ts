/**
 * Management Routes — Server administration dashboard API
 *
 * SECURITY: These routes are LOCALHOST-ONLY. Requests from external IPs are
 * rejected before any processing occurs. This ensures only the server device
 * (running the Electron dashboard) can access management functions.
 *
 * Uses the same admin token auth pattern as admin.routes.ts.
 */
import { Router, Request, Response, NextFunction } from 'express';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { exec } from 'child_process';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { getCrashLog, getDisabledRoutes, reenableRoute, clearCrashLog, getCrashStats } from '../services/crashTracker.js';
import { getUpdateStatus, checkForUpdates, performUpdate } from '../services/githubUpdater.js';
import { getRequestsPerSecond, getRequestsPerMinute, getRequestsPerSecondPeak, getRequestsPerSecondCurrent, getAvgResponseTime, getP95ResponseTime } from '../utils/requestCounter.js';
import { allClients } from '../ws/server.js';
import { getMasterDb } from '../db/master-connection.js';
import { getMetricsHistory } from '../services/metricsCollector.js';

const router = Router();

// ── Localhost-only guard ───────────────────────────────────────────────
// CRITICAL: Block all requests that don't originate from localhost.
// This prevents external attackers from accessing server management.

const LOCALHOST_IPS = new Set([
  '127.0.0.1',
  '::1',
  '::ffff:127.0.0.1',
  'localhost',
]);

function localhostOnly(req: Request, res: Response, next: NextFunction): void {
  // SECURITY: Use req.socket.remoteAddress (actual TCP connection source), NOT req.ip.
  // req.ip is affected by trust proxy settings and can be spoofed via X-Forwarded-For.
  const ip = req.socket?.remoteAddress || '';
  if (!LOCALHOST_IPS.has(ip)) {
    res.status(403).json({
      success: false,
      message: 'Management API is only accessible from the server device.',
    });
    return;
  }
  next();
}

router.use(localhostOnly);

// ── Pre-auth endpoint: check if setup is needed ──────────────────────────
// Always accessible (no auth) so the dashboard can detect first-run state.

router.get('/setup-status', (_req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) {
    res.json({ success: true, data: { needsSetup: true, multiTenant: false } });
    return;
  }
  const existing = masterDb.prepare('SELECT id FROM super_admins LIMIT 1').get();
  const configRow = masterDb.prepare("SELECT value FROM platform_config WHERE key = 'management_api_enabled'").get() as { value: string } | undefined;
  res.json({
    success: true,
    data: {
      needsSetup: !existing,
      managementApiEnabled: configRow?.value === 'true',
      multiTenant: config.multiTenant === true,
    },
  });
});

// ── Opt-in guard: management API must be enabled by super admin ──────────
// Exception: if no super admin exists yet (first-run), allow access for setup.

function managementApiGuard(req: Request, res: Response, next: NextFunction): void {
  if (req.path === '/setup-status') return next();

  const masterDb = getMasterDb();
  if (!masterDb || !config.multiTenant) {
    // Single-tenant mode: management API always available
    return next();
  }

  // First-run exception: if no super admin exists, allow setup
  const existing = masterDb.prepare('SELECT id FROM super_admins LIMIT 1').get();
  if (!existing) return next();

  // Check if management API is enabled
  const configRow = masterDb.prepare("SELECT value FROM platform_config WHERE key = 'management_api_enabled'").get() as { value: string } | undefined;
  if (configRow?.value !== 'true') {
    res.status(403).json({
      success: false,
      message: 'Management API is disabled. Enable it from the super admin panel (/super-admin).',
    });
    return;
  }
  next();
}

router.use(managementApiGuard);

// ── Super admin JWT auth ─────────────────────────────────────────────────
// The dashboard authenticates via super admin 2FA flow and sends the JWT.

function managementAuth(req: Request, res: Response, next: NextFunction): void {
  if (req.path === '/setup-status') return next();

  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';

  if (!token) {
    res.status(401).json({ success: false, message: 'Super admin authentication required' });
    return;
  }

  try {
    const payload = jwt.verify(token, config.superAdminSecret || config.jwtSecret) as { role?: string; superAdminId?: number; sessionId?: string };
    if (payload.role !== 'super_admin') {
      res.status(403).json({ success: false, message: 'Super admin role required' });
      return;
    }

    // Verify session still exists and is not expired
    const masterDb = getMasterDb();
    if (masterDb && payload.sessionId) {
      const session = masterDb.prepare(
        "SELECT id FROM super_admin_sessions WHERE id = ? AND expires_at > datetime('now')"
      ).get(payload.sessionId);
      if (!session) {
        res.status(401).json({ success: false, message: 'Session expired' });
        return;
      }
    }

    next();
  } catch {
    res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }
}

router.use(managementAuth);

// ── Stats ──────────────────────────────────────────────────────────────

const MAX_DIR_DEPTH = 10;

function getUploadsSize(dirPath: string, seen = new Set<string>(), depth = 0): number {
  if (depth > MAX_DIR_DEPTH) return 0; // Prevent excessive recursion
  try {
    const realPath = fs.realpathSync(dirPath);
    if (seen.has(realPath)) return 0; // Prevent symlink loops
    seen.add(realPath);

    if (!fs.existsSync(realPath)) return 0;
    let total = 0;
    const entries = fs.readdirSync(realPath, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(realPath, entry.name);
      if (entry.isSymbolicLink()) continue; // Skip symlinks entirely
      if (entry.isFile()) {
        total += fs.statSync(fullPath).size;
      } else if (entry.isDirectory()) {
        total += getUploadsSize(fullPath, seen, depth + 1);
      }
    }
    return total;
  } catch {
    return 0;
  }
}

router.get('/stats', (_req: Request, res: Response) => {
  const mem = process.memoryUsage();
  const cpuUsage = process.cpuUsage();

  let dbSize = 0;
  try {
    dbSize = fs.statSync(config.dbPath).size;
  } catch { /* DB not found */ }

  const uploadsSize = getUploadsSize(config.uploadsPath);

  res.json({
    success: true,
    data: {
      uptime: process.uptime(),
      memory: {
        rss: Math.round(mem.rss / 1024 / 1024),
        heapUsed: Math.round(mem.heapUsed / 1024 / 1024),
        heapTotal: Math.round(mem.heapTotal / 1024 / 1024),
      },
      cpu: {
        user: cpuUsage.user,
        system: cpuUsage.system,
      },
      dbSizeBytes: dbSize,
      dbSizeMB: Math.round(dbSize / 1024 / 1024 * 100) / 100,
      uploadsSizeBytes: uploadsSize,
      uploadsSizeMB: Math.round(uploadsSize / 1024 / 1024 * 100) / 100,
      activeConnections: allClients.size,
      requestsPerSecond: getRequestsPerSecondCurrent(),
      requestsPerSecondAvg: getRequestsPerSecond(),
      requestsPerSecondPeak: getRequestsPerSecondPeak(),
      requestsPerMinute: getRequestsPerMinute(),
      avgResponseMs: getAvgResponseTime(),
      p95ResponseMs: getP95ResponseTime(),
      nodeVersion: process.version,
      platform: process.platform,
      hostname: os.hostname(),
      pm2Managed: !!process.env.PM2_HOME || !!process.env.pm_id,
      multiTenant: config.multiTenant === true,
      nodeEnv: process.env.NODE_ENV || 'development',
    },
  });
});

// ── Historical Metrics ────────────────────────────────────────────────

router.get('/stats/history', (req: Request, res: Response) => {
  const range = (req.query.range as string) || '1h';
  const validRanges = ['1h', '6h', '1d', '1w', '1m', '6m'];
  if (!validRanges.includes(range)) {
    return res.status(400).json({ success: false, message: `Invalid range. Use: ${validRanges.join(', ')}` });
  }

  const data = getMetricsHistory(range);
  res.json({ success: true, data });
});

// ── Crash Management ───────────────────────────────────────────────────

router.get('/crashes', (_req: Request, res: Response) => {
  res.json({ success: true, data: getCrashLog() });
});

router.get('/crash-stats', (_req: Request, res: Response) => {
  res.json({ success: true, data: getCrashStats() });
});

router.get('/disabled-routes', (_req: Request, res: Response) => {
  res.json({ success: true, data: getDisabledRoutes() });
});

router.post('/reenable-route', (req: Request, res: Response) => {
  const { route } = req.body;
  if (!route || typeof route !== 'string') {
    res.status(400).json({ success: false, message: 'Route string required' });
    return;
  }
  const result = reenableRoute(route);
  if (result) {
    res.json({ success: true, message: `Route ${route} re-enabled` });
  } else {
    res.status(404).json({ success: false, message: 'Route not found in disabled list' });
  }
});

router.post('/clear-crashes', (_req: Request, res: Response) => {
  clearCrashLog();
  res.json({ success: true, message: 'Crash log cleared' });
});

// ── GitHub Updates ─────────────────────────────────────────────────────

router.get('/update-status', (_req: Request, res: Response) => {
  res.json({ success: true, data: getUpdateStatus() });
});

router.post('/check-updates', async (_req: Request, res: Response) => {
  try {
    const status = await checkForUpdates();
    res.json({ success: true, data: status });
  } catch (err) {
    res.status(500).json({ success: false, message: err instanceof Error ? err.message : 'Update check failed' });
  }
});

router.post('/perform-update', async (_req: Request, res: Response) => {
  try {
    const result = await performUpdate();
    res.json({ success: true, data: result });
  } catch (err) {
    res.status(500).json({ success: false, message: err instanceof Error ? err.message : 'Update failed' });
  }
});

// ── Server Control ─────────────────────────────────────────────────────

router.post('/restart', (_req: Request, res: Response) => {
  res.json({ success: true, message: 'Restarting server...' });
  // Delay slightly so the response can be sent
  setTimeout(() => {
    exec('pm2 restart bizarre-crm', (err) => {
      if (err) console.error('[Management] PM2 restart failed:', err.message);
    });
  }, 500);
});

router.post('/stop', (_req: Request, res: Response) => {
  res.json({ success: true, message: 'Stopping server...' });
  setTimeout(() => {
    exec('pm2 stop bizarre-crm', (err) => {
      if (err) console.error('[Management] PM2 stop failed:', err.message);
    });
  }, 500);
});

// ── Disk Space ────────────────────────────────────────────────────────

router.get('/disk-space', (_req: Request, res: Response) => {
  if (process.platform !== 'win32') {
    res.json({ success: true, data: [] });
    return;
  }
  exec('wmic logicaldisk get caption,freespace,size /format:csv', { timeout: 10_000 }, (err, stdout) => {
    if (err) {
      res.json({ success: true, data: [] });
      return;
    }
    const lines = stdout.trim().split('\n').filter(l => l.trim() && !l.startsWith('Node'));
    const drives = lines.map(line => {
      const parts = line.trim().split(',');
      if (parts.length < 4) return null;
      const mount = parts[1];
      const free = parseInt(parts[2], 10);
      const total = parseInt(parts[3], 10);
      if (!mount || isNaN(free) || isNaN(total) || total === 0) return null;
      return { mount, total, free, used: total - free };
    }).filter(Boolean);
    res.json({ success: true, data: drives });
  });
});

// ── Tenant Management (read-only view + actions for dashboard) ────────
// Proxies to master DB so the management dashboard can manage tenants
// without needing a separate super-admin login.

import { getMasterDb } from '../db/master-connection.js';

router.get('/tenants', (_req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) {
    res.json({ success: true, data: [] });
    return;
  }
  try {
    const tenants = masterDb.prepare(`
      SELECT id, slug, name, status, plan, created_at,
             max_users, max_tickets_month, storage_limit_mb
      FROM tenants ORDER BY created_at DESC
    `).all();

    // Get DB sizes for each tenant
    const tenantsWithSize = (tenants as any[]).map(t => {
      try {
        const dbPath = path.join(config.tenantDataDir || 'data/tenants', `${t.slug}.db`);
        const stats = fs.statSync(dbPath);
        return { ...t, db_size_bytes: stats.size };
      } catch {
        return { ...t, db_size_bytes: 0 };
      }
    });

    res.json({ success: true, data: tenantsWithSize });
  } catch (err) {
    res.json({ success: true, data: [] });
  }
});

router.post('/tenants/:slug/suspend', (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, message: 'Master DB not available' }); return; }
  const { slug } = req.params;
  masterDb.prepare("UPDATE tenants SET status = 'suspended' WHERE slug = ?").run(slug);
  res.json({ success: true, message: `Tenant ${slug} suspended` });
});

router.post('/tenants/:slug/activate', (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, message: 'Master DB not available' }); return; }
  const { slug } = req.params;
  masterDb.prepare("UPDATE tenants SET status = 'active' WHERE slug = ?").run(slug);
  res.json({ success: true, message: `Tenant ${slug} activated` });
});

router.delete('/tenants/:slug', (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, message: 'Master DB not available' }); return; }
  const { slug } = req.params;
  masterDb.prepare("DELETE FROM tenants WHERE slug = ?").run(slug);
  res.json({ success: true, message: `Tenant ${slug} deleted` });
});

export default router;
