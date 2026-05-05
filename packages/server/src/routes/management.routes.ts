/**
 * Management Routes — Server administration dashboard API
 *
 * SECURITY: These routes are LOCALHOST-ONLY. Requests from external IPs are
 * rejected before any processing occurs. This ensures only the server device
 * (running the Electron dashboard) can access management functions.
 *
 * Uses the same admin token auth pattern as admin.routes.ts.
 *
 * SEC-M20 — Per-handler tenantId validation invariant.
 *
 * Every handler in this file that mutates tenant state MUST:
 *   (a) Accept the tenant identifier ONLY via the URL path param `:slug`
 *       (never via request body or query string — keeps the audit trail
 *       attached to a single, greppable source).
 *   (b) Run the identifier through `validateSlugParam` so we reject any
 *       shape other than `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` (<= 30 chars)
 *       BEFORE doing any DB work. Defends against SQLi-shaped slugs, path
 *       traversal attempts against the tenant DB file, and accidental
 *       fallthrough to the "default" tenant.
 *   (c) Look the slug up in the MASTER DB (`SELECT id, status FROM tenants
 *       WHERE slug = ?`) and 404 if not found. This converts "operator
 *       fat-fingered the slug" from a silent no-op into a loud error, and
 *       captures the current status for the audit row.
 *   (d) Route every state change through the canonical helpers in
 *       `services/tenant-provisioning.ts` (suspendTenant / activateTenant /
 *       deleteTenant) so the pool close, plan-cache bust, WebSocket
 *       disconnect, and soft-delete grace period all happen in the one
 *       right place.
 *   (e) Write a `managementAudit()` row with the resolved `tenant_id`, the
 *       previous status, and the operator's IP.
 *
 * All current handlers comply; the per-route invariants live next to each
 * handler. If you add a new mutating endpoint, follow this recipe.
 *
 * Note: the authenticated admin is ALWAYS a super admin (enforced by
 * `managementAuth` below — role must be `super_admin` and the `super_admins`
 * row must still be `is_active = 1`). A super admin has authority over any
 * slug in master DB, so there is no "admin's scope" to enforce beyond "does
 * this tenant actually exist" — that check is (c) above.
 */
import { Router, Request, Response, NextFunction } from 'express';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFile, execSync } from 'child_process';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { getCrashLog, getDisabledRoutes, reenableRoute, clearCrashLog, getCrashStats } from '../services/crashTracker.js';
import { getUpdateStatus, checkForUpdates, performUpdate } from '../services/githubUpdater.js';
import { getRequestsPerSecond, getRequestsPerMinute, getRequestsPerSecondPeak, getRequestsPerSecondCurrent, getAvgResponseTime, getP95ResponseTime } from '../utils/requestCounter.js';
import { getTenantRequestCounts } from '../middleware/requestLogger.js';
import { allClients } from '../ws/server.js';
import { getMasterDb } from '../db/master-connection.js';
import { getMetricsHistory } from '../services/metricsCollector.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES } from '../utils/errorCodes.js';
import { checkWindowRate, recordWindowAttempt } from '../utils/rateLimiter.js';

const router = Router();
const logger = createLogger('management');

// ── Audit helper for management actions (writes to master_audit_log) ──────
function managementAudit(action: string, ip: string, details?: Record<string, unknown>): void {
  try {
    const db = getMasterDb();
    if (!db) return;
    db.prepare(
      'INSERT INTO master_audit_log (action, details, ip_address) VALUES (?, ?, ?)'
    ).run(action, details ? JSON.stringify(details) : null, ip);
  } catch (err: unknown) {
    const code = err && typeof err === 'object' && 'code' in err ? String((err as { code: unknown }).code) : 'UNKNOWN';
    logger.warn('[ManagementAudit] Failed to write audit log', { code });
  }
}

// ── Localhost-only guard ───────────────────────────────────────────────
// CRITICAL: Block all requests that don't originate from localhost.
// This prevents external attackers from accessing server management.
//
// @audit-fixed: 'localhost' was in the set as a literal string, but
// req.socket.remoteAddress NEVER returns the string 'localhost' — only an
// IP. Removed the dead entry so the set's intent (loopback only) is exact
// and an operator skimming this code isn't misled into thinking we accept
// hostname-style entries.
const LOCALHOST_IPS = new Set([
  '127.0.0.1',
  '::1',
  '::ffff:127.0.0.1',
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

// ── First-run setup: create super admin account ─────────────────────────
// Only works when no super admins exist. No auth required (there's nobody to auth as).
//
// @audit-fixed (SCAN-874): Replaced in-memory Map rate limit with DB-backed
// checkWindowRate/recordWindowAttempt so the limit survives server restarts
// and cannot be bypassed by triggering a process reboot between the flood and
// the legitimate operator completing first-run setup.
const SETUP_RATE_CATEGORY = 'management_setup_attempt';
const SETUP_RATE_MAX = 5;
const SETUP_RATE_WINDOW_MS = 15 * 60 * 1000; // 15 min

router.post('/setup', async (req: Request, res: Response) => {
  const ip = req.socket?.remoteAddress ?? 'unknown';

  const masterDb = getMasterDb();
  if (!masterDb) {
    res.status(500).json({ success: false, code: ERROR_CODES.ERR_INT_DB_UNAVAILABLE, message: 'Master DB unavailable' });
    return;
  }

  if (!checkWindowRate(masterDb, SETUP_RATE_CATEGORY, ip, SETUP_RATE_MAX, SETUP_RATE_WINDOW_MS)) {
    logger.warn('setup rate limit exceeded', { ip });
    res.status(429).json({ success: false, message: 'Too many setup attempts. Wait and retry.' });
    return;
  }
  recordWindowAttempt(masterDb, SETUP_RATE_CATEGORY, ip, SETUP_RATE_WINDOW_MS);

  // Block if any super admin already exists
  const existing = masterDb.prepare('SELECT id FROM super_admins LIMIT 1').get();
  if (existing) {
    res.status(403).json({ success: false, code: ERROR_CODES.ERR_AUTH_ALREADY_SETUP, message: 'Setup already completed' });
    return;
  }

  const { username, password } = req.body;
  if (!username || typeof username !== 'string' || username.trim().length < 3) {
    res.status(400).json({ success: false, message: 'Username must be at least 3 characters' });
    return;
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
    return;
  }
  if (password.length > 128) {
    res.status(400).json({ success: false, message: 'Password too long' });
    return;
  }

  const bcrypt = await import('bcryptjs');
  const hash = bcrypt.default.hashSync(password, 12);

  const insertResult = masterDb.prepare(
    "INSERT INTO super_admins (username, email, password_hash, password_set) VALUES (?, ?, ?, 1)"
  ).run(username.trim().toLowerCase(), `${username.trim().toLowerCase()}@localhost`, hash);

  // Auto-enable management API
  masterDb.prepare("INSERT OR REPLACE INTO platform_config (key, value) VALUES ('management_api_enabled', 'true')").run();

  // T17: Previously this logged the username via console.log, leaking account
  // identifiers to stdout / shipped logs. Log only the numeric ID so an
  // operator can correlate without exposing the chosen username. Never log
  // passwords, hashes, or email addresses.
  logger.info('super admin created via first-run setup', {
    super_admin_id: Number(insertResult.lastInsertRowid),
  });

  res.json({ success: true, data: { message: 'Super admin account created. You can now log in.' } });
});

// ── Opt-in guard: management API must be enabled by super admin ──────────
// Exception: if no super admin exists yet (first-run), allow access for setup.

function managementApiGuard(req: Request, res: Response, next: NextFunction): void {
  if (req.path === '/setup-status' || req.path === '/setup') return next();

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

// @audit-fixed:
//   (a) Previously fell back from `superAdminSecret` to `jwtSecret` if the
//       former was empty, which meant in degraded configs a TENANT JWT signed
//       with jwtSecret could authenticate against the management API. We now
//       require superAdminSecret to be set; the route returns 503 otherwise.
//   (b) Previously did not check that the super admin is still active —
//       a revoked super admin's JWT remained valid until expiry. We now load
//       the row and require is_active = 1.
function managementAuth(req: Request, res: Response, next: NextFunction): void {
  if (req.path === '/setup-status' || req.path === '/setup') return next();

  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';

  if (!token) {
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_NO_TOKEN, message: 'Super admin authentication required' });
    return;
  }

  if (!config.superAdminSecret) {
    res.status(503).json({ success: false, code: ERROR_CODES.ERR_INT_DB_UNAVAILABLE, message: 'Super admin secret not configured' });
    return;
  }

  try {
    // AUD-M1: pin algorithm + issuer + audience to match the super-admin
    // sign flow in super-admin.routes.ts. Prevents alg=none and cross-audience
    // token reuse against this endpoint.
    const payload = jwt.verify(token, config.superAdminSecret, {
      algorithms: ['HS256'],
      issuer: 'bizarre-crm',
      audience: 'bizarre-crm-super-admin',
    }) as { role?: string; superAdminId?: number; sessionId?: string };
    if (payload.role !== 'super_admin') {
      res.status(403).json({ success: false, message: 'Super admin role required' });
      return;
    }

    const masterDb = getMasterDb();
    if (masterDb) {
      // Verify session still exists and is not expired.
      if (payload.sessionId) {
        const session = masterDb.prepare(
          "SELECT id, super_admin_id, expires_at FROM super_admin_sessions WHERE id = ?"
        ).get(payload.sessionId) as { id: string; super_admin_id: number; expires_at: string } | undefined;
        if (!session) {
          logger.warn('management auth: session row not found', {
            sessionId: payload.sessionId,
            superAdminId: payload.superAdminId,
            path: req.path,
          });
          res.status(401).json({ success: false, message: 'Session expired' });
          return;
        }
        const nowRow = masterDb.prepare("SELECT datetime('now') AS now").get() as { now: string };
        if (session.expires_at <= nowRow.now) {
          logger.warn('management auth: session expired', {
            sessionId: payload.sessionId,
            expires_at: session.expires_at,
            db_now: nowRow.now,
            path: req.path,
          });
          res.status(401).json({ success: false, message: 'Session expired' });
          return;
        }
      }
      // Verify the super admin row is still active.
      if (payload.superAdminId) {
        const adminRow = masterDb.prepare(
          'SELECT id FROM super_admins WHERE id = ? AND is_active = 1'
        ).get(payload.superAdminId);
        if (!adminRow) {
          logger.warn('management auth: account deactivated or missing', {
            superAdminId: payload.superAdminId,
            path: req.path,
          });
          res.status(401).json({ success: false, message: 'Account deactivated' });
          return;
        }
      }
    }

    next();
  } catch (err) {
    logger.warn('management auth: jwt verify threw', {
      error: err instanceof Error ? err.message : String(err),
      path: req.path,
    });
    res.status(401).json({ success: false, code: ERROR_CODES.ERR_AUTH_INVALID_TOKEN, message: 'Invalid or expired token' });
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

/**
 * Server build fingerprint — resolved ONCE at module load so every /stats
 * poll is cheap. Prefers a build-time-injected GIT_SHA env var (set by
 * setup.bat / CI); falls back to a synchronous `git rev-parse` against the
 * repo root. If both fail (packaged binary without git on PATH) we return
 * 'unknown' so the dashboard can render a dash instead of crashing.
 *
 * Also captures the wall-clock server-start timestamp so the dashboard can
 * show "started at …" alongside uptime — useful when an operator wants to
 * verify a recent restart actually landed.
 */
const SERVER_STARTED_AT = new Date().toISOString();
const GIT_SHA: string = (() => {
  const envSha = process.env.GIT_SHA;
  if (envSha && /^[a-f0-9]{7,40}$/i.test(envSha)) return envSha.slice(0, 12);
  try {
    const cwd = path.resolve(__dirname, '..', '..', '..', '..');
    const out = execSync('git rev-parse --short=12 HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'], timeout: 2000 })
      .toString()
      .trim();
    if (/^[a-f0-9]{7,40}$/i.test(out)) return out;
  } catch {
    /* git not available or not a git checkout */
  }
  return 'unknown';
})();

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
      gitSha: GIT_SHA,
      startedAt: SERVER_STARTED_AT,
      unacknowledgedSecurityAlerts: (() => {
        const db = getMasterDb();
        if (!db) return 0;
        try {
          const row = db.prepare('SELECT COUNT(*) as c FROM security_alerts WHERE acknowledged = 0').get() as { c: number };
          return row?.c || 0;
        } catch {
          return 0;
        }
      })(),
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
    managementAudit('route_reenabled', req.socket?.remoteAddress || 'unknown', { route });
    res.json({ success: true, message: `Route ${route} re-enabled` });
  } else {
    res.status(404).json({ success: false, code: ERROR_CODES.ERR_RESOURCE_NOT_FOUND, message: 'Route not found in disabled list' });
  }
});

router.post('/clear-crashes', (req: Request, res: Response) => {
  managementAudit('crash_log_cleared', req.socket?.remoteAddress || 'unknown');
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
    // E3: Never leak raw error messages — they can include filesystem paths
    // (`ENOENT: ... /var/crm/.../update.zip`), schema errors, etc. Log the
    // full error server-side and return a generic message to the client.
    logger.error('update check failed', {
      error: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });
    res.status(500).json({ success: false, code: ERROR_CODES.ERR_INT_GENERIC, message: 'Update check failed' });
  }
});

// UP6: Endpoints the Electron dashboard hits around update.bat.
//
// The real `git pull && rebuild` runs in the dashboard process (see
// `packages/management/src/main/ipc/management-api.ts`), which means the
// server never sees the spawn or its exit code. Without these endpoints
// the master audit log would show NOTHING for update events — including
// the operator's IP, the before/after SHAs, and success/failure.
//
//   1. `/audit-update-launch` is called from Electron AFTER the
//      pre-update snapshot is captured but BEFORE cmd.exe is spawned.
//      It records { entity_type: 'system_update', before_sha, status:
//      'launched', initiator_ip } so a failed update that never comes
//      back still leaves a trail.
//
//   2. `/audit-update-result` is called from Electron after the dashboard
//      restarts and the UpdatesPage confirms the new HEAD. It records
//      { after_sha, status: 'success' | 'failure', error_message }.
//
// Both endpoints require the super-admin JWT (enforced by the existing
// `managementAuth` middleware attached further up this file) so only a
// logged-in dashboard can write audit rows.
router.post('/audit-update-launch', (req: Request, res: Response) => {
  const ip = req.socket?.remoteAddress || 'unknown';
  const body = (req.body ?? {}) as { beforeSha?: unknown; source?: unknown };
  const beforeSha = typeof body.beforeSha === 'string' && /^[a-f0-9]{7,40}$/i.test(body.beforeSha)
    ? body.beforeSha
    : null;
  const source = typeof body.source === 'string' ? body.source.slice(0, 32) : 'dashboard';
  managementAudit('system_update', ip, {
    entity_type: 'system_update',
    status: 'launched',
    before_sha: beforeSha,
    after_sha: null,
    source,
  });
  res.json({ success: true, data: { recorded: true, before_sha: beforeSha } });
});

router.post('/audit-update-result', (req: Request, res: Response) => {
  const ip = req.socket?.remoteAddress || 'unknown';
  const body = (req.body ?? {}) as {
    beforeSha?: unknown;
    afterSha?: unknown;
    success?: unknown;
    errorMessage?: unknown;
  };
  const beforeSha = typeof body.beforeSha === 'string' && /^[a-f0-9]{7,40}$/i.test(body.beforeSha)
    ? body.beforeSha
    : null;
  const afterSha = typeof body.afterSha === 'string' && /^[a-f0-9]{7,40}$/i.test(body.afterSha)
    ? body.afterSha
    : null;
  const success = body.success === true;
  const errorMessage = typeof body.errorMessage === 'string'
    ? body.errorMessage.slice(0, 500)
    : null;
  managementAudit('system_update', ip, {
    entity_type: 'system_update',
    status: success ? 'success' : 'failure',
    before_sha: beforeSha,
    after_sha: afterSha,
    error_message: errorMessage,
  });
  res.json({ success: true, data: { recorded: true } });
});

router.post('/perform-update', async (req: Request, res: Response) => {
  const ip = req.socket?.remoteAddress || 'unknown';
  // UP6: capture the before-SHA so the audit entry reflects the actual
  // starting state. getUpdateStatus() returns the current commit info even
  // before the pull so we can snapshot it here. If the status call fails we
  // still proceed with the update but mark the before-SHA as unknown.
  let beforeSha: string | null = null;
  try {
    const pre = getUpdateStatus();
    beforeSha = (pre as { current?: string; currentSha?: string; sha?: string } | null | undefined)?.currentSha
      ?? (pre as { current?: string } | null | undefined)?.current
      ?? (pre as { sha?: string } | null | undefined)?.sha
      ?? null;
  } catch (preErr) {
    logger.warn('could not read pre-update status', {
      error: preErr instanceof Error ? preErr.message : String(preErr),
    });
  }

  try {
    const result = await performUpdate();
    // UP6: Capture the resulting SHA so the audit row reflects before AND
    // after, plus success state. Cast cautiously — we don't control the exact
    // shape of performUpdate's return but any `sha` / `commit` field is fine.
    const afterSha = (result as { sha?: string; commit?: string; newSha?: string } | null | undefined)?.newSha
      ?? (result as { sha?: string } | null | undefined)?.sha
      ?? (result as { commit?: string } | null | undefined)?.commit
      ?? null;
    managementAudit('server_update', ip, {
      before_sha: beforeSha,
      after_sha: afterSha,
      success: true,
      error_message: null,
    });
    res.json({ success: true, data: result });
  } catch (err) {
    // UP6: Audit the failure path too so an operator can see WHICH update
    // attempts failed and why (the error message goes to the audit log only,
    // NOT back to the client — see E3 above).
    const errorMessage = err instanceof Error ? err.message : String(err);
    managementAudit('server_update', ip, {
      before_sha: beforeSha,
      after_sha: null,
      success: false,
      error_message: errorMessage.slice(0, 500),
    });
    logger.error('server update failed', {
      error: errorMessage,
      stack: err instanceof Error ? err.stack : undefined,
      before_sha: beforeSha,
    });
    // E3: Generic message to client — never leak paths or stack traces.
    res.status(500).json({ success: false, code: ERROR_CODES.ERR_INT_GENERIC, message: 'Update failed' });
  }
});

// ── Server Control ─────────────────────────────────────────────────────

// SECURITY (EL4): Use `execFile` with an explicit argv array. Although
// the command name and arguments here are static constants, switching
// away from `exec(string)` removes the shell entirely so future edits
// can't accidentally introduce string-interpolation injection.
router.post('/restart', (req: Request, res: Response) => {
  managementAudit('server_restart', req.socket?.remoteAddress || 'unknown');
  res.json({ success: true, message: 'Restarting server...' });
  // Delay slightly so the response can be sent
  setTimeout(() => {
    execFile('pm2', ['restart', 'bizarre-crm'], (err) => {
      if (err) logger.error('pm2_restart_failed', { error: err.message });
    });
  }, 500);
});

router.post('/stop', (req: Request, res: Response) => {
  managementAudit('server_stop', req.socket?.remoteAddress || 'unknown');
  res.json({ success: true, message: 'Stopping server...' });
  setTimeout(() => {
    execFile('pm2', ['stop', 'bizarre-crm'], (err) => {
      if (err) logger.error('pm2_stop_failed', { error: err.message });
    });
  }, 500);
});

// ── Disk Space ────────────────────────────────────────────────────────

router.get('/disk-space', (_req: Request, res: Response) => {
  if (process.platform !== 'win32') {
    res.json({ success: true, data: [] });
    return;
  }
  // EL4: `execFile` + explicit argv avoids the shell entirely.
  execFile(
    'wmic',
    ['logicaldisk', 'get', 'caption,freespace,size', '/format:csv'],
    { timeout: 10_000 },
    (err, stdout) => {
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
    }
  );
});

// ── Tenant Management (read-only view + actions for dashboard) ────────
// Proxies to master DB so the management dashboard can manage tenants
// without needing a separate super-admin login.

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

// SEC-NEW: Per-tenant request metrics
router.get('/tenant-metrics', (_req: Request, res: Response) => {
  const counts = getTenantRequestCounts();
  res.json({ success: true, data: counts });
});

// @audit-fixed: Previously these routes:
//   (a) Suspended/activated by raw UPDATE without going through
//       suspendTenant()/activateTenant(), which meant the tenant pool was
//       NOT closed, the plan cache was NOT busted, and live WebSockets were
//       NOT terminated.
//   (b) Worst of all, DELETE was a raw `DELETE FROM tenants WHERE slug = ?`
//       — it removed the tenant ROW from master_db with no soft-delete, no
//       30-day grace period, no archive, and (because the tenant DB file
//       was never touched) left an orphaned DB on disk forever. This violated
//       the "tenant DBs are sacred" rule in CLAUDE.md AND deleted the only
//       record that could prove the slug had been used, opening a subdomain
//       takeover window if anyone re-provisioned the same slug.
//   (c) None of these endpoints validated the slug shape, returning a 200
//       success even when the slug didn't match any tenant — the management
//       UI could "delete" a non-existent tenant and never notice.
//   (d) Audit rows lacked the tenant_id and the previous status, making
//       post-mortem investigation hard.
//
// Fix: route every state change through the canonical helpers in
// services/tenant-provisioning.ts (suspendTenant/activateTenant/deleteTenant),
// validate the slug shape, look up the tenant first, audit with the row id,
// and on suspend/delete also disconnect the tenant's WebSockets via the same
// helper that super-admin.routes.ts uses.
//
// Imports added at top of file via dynamic require to avoid the circular
// init that an import-time `import` would trigger between this route file
// and tenant-provisioning.ts.
const SLUG_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;

function validateSlugParam(req: Request, res: Response): string | null {
  const slug = String(req.params.slug || '').toLowerCase();
  if (!slug || slug.length > 30 || !SLUG_REGEX.test(slug)) {
    res.status(400).json({ success: false, message: 'Invalid tenant slug' });
    return null;
  }
  return slug;
}

function disconnectTenantWebSockets(slug: string): number {
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

router.post('/tenants/:slug/suspend', async (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, code: ERROR_CODES.ERR_INT_DB_UNAVAILABLE, message: 'Master DB not available' }); return; }
  const slug = validateSlugParam(req, res);
  if (!slug) return;
  const before = masterDb.prepare('SELECT id, status FROM tenants WHERE slug = ?').get(slug) as { id: number; status: string } | undefined;
  if (!before) {
    res.status(404).json({ success: false, code: ERROR_CODES.ERR_TENANT_NOT_FOUND, message: 'Tenant not found' });
    return;
  }
  // Lazy-import the canonical helper so we share state with super-admin routes.
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const { suspendTenant } = require('../services/tenant-provisioning.js') as typeof import('../services/tenant-provisioning.js');
  const result = suspendTenant(slug);
  if (!result.success) {
    res.status(400).json({ success: false, message: result.error });
    return;
  }
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const tr = require('../middleware/tenantResolver.js') as { clearPlanCache?: (id: number) => void };
  tr.clearPlanCache?.(before.id);
  const wsClosed = disconnectTenantWebSockets(slug);
  managementAudit('tenant_suspended', req.socket?.remoteAddress || 'unknown', {
    slug,
    tenant_id: before.id,
    previous_status: before.status,
    websockets_closed: wsClosed,
  });
  res.json({ success: true, data: { message: `Tenant ${slug} suspended`, websockets_closed: wsClosed } });
});

router.post('/tenants/:slug/activate', (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, code: ERROR_CODES.ERR_INT_DB_UNAVAILABLE, message: 'Master DB not available' }); return; }
  const slug = validateSlugParam(req, res);
  if (!slug) return;
  const before = masterDb.prepare('SELECT id, status FROM tenants WHERE slug = ?').get(slug) as { id: number; status: string } | undefined;
  if (!before) {
    res.status(404).json({ success: false, code: ERROR_CODES.ERR_TENANT_NOT_FOUND, message: 'Tenant not found' });
    return;
  }
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const { activateTenant } = require('../services/tenant-provisioning.js') as typeof import('../services/tenant-provisioning.js');
  const result = activateTenant(slug);
  if (!result.success) {
    res.status(400).json({ success: false, message: result.error });
    return;
  }
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const tr = require('../middleware/tenantResolver.js') as { clearPlanCache?: (id: number) => void };
  tr.clearPlanCache?.(before.id);
  managementAudit('tenant_activated', req.socket?.remoteAddress || 'unknown', {
    slug,
    tenant_id: before.id,
    previous_status: before.status,
  });
  res.json({ success: true, data: { message: `Tenant ${slug} activated` } });
});

router.delete('/tenants/:slug', async (req: Request, res: Response) => {
  const masterDb = getMasterDb();
  if (!masterDb) { res.status(500).json({ success: false, code: ERROR_CODES.ERR_INT_DB_UNAVAILABLE, message: 'Master DB not available' }); return; }
  const slug = validateSlugParam(req, res);
  if (!slug) return;
  const before = masterDb.prepare('SELECT id, status FROM tenants WHERE slug = ?').get(slug) as { id: number; status: string } | undefined;
  if (!before) {
    res.status(404).json({ success: false, code: ERROR_CODES.ERR_TENANT_NOT_FOUND, message: 'Tenant not found' });
    return;
  }
  // Route through deleteTenant() so we get the 30-day grace period, the
  // Cloudflare DNS cleanup, and the safe archive instead of an unrecoverable
  // hard delete. This preserves the "tenant DBs are sacred" guarantee.
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const { deleteTenant } = require('../services/tenant-provisioning.js') as typeof import('../services/tenant-provisioning.js');
  const result = await deleteTenant(slug);
  if (!result.success) {
    res.status(400).json({ success: false, message: result.error });
    return;
  }
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const tr = require('../middleware/tenantResolver.js') as { clearPlanCache?: (id: number) => void };
  tr.clearPlanCache?.(before.id);
  const wsClosed = disconnectTenantWebSockets(slug);
  managementAudit('tenant_deleted', req.socket?.remoteAddress || 'unknown', {
    slug,
    tenant_id: before.id,
    previous_status: before.status,
    websockets_closed: wsClosed,
    soft_delete: true,
  });
  res.json({ success: true, data: { message: `Tenant ${slug} scheduled for deletion`, websockets_closed: wsClosed } });
});

export default router;
