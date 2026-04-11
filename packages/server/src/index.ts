process.title = 'BizarreCRM Server';

// SEC-L4: In production, suppress non-structured console.log output.
// Structured logs (prefixed with [ModuleName]) are preserved; casual debug logs are dropped.
// console.error / console.warn / console.info are NOT suppressed — only console.log.
// Gradual migration: move call sites to the structured logger (utils/logger.ts) over time.
if (process.env.NODE_ENV === 'production') {
  const originalLog = console.log;
  console.log = (...args: unknown[]) => {
    if (typeof args[0] === 'string' && args[0].startsWith('[')) {
      originalLog(...args);
    }
  };
}

import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import Database from 'better-sqlite3';
import express from 'express';
import cors from 'cors';
import path from 'path';
import os from 'os';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { createServer } from 'http';
import { createServer as createHttpsServer } from 'https';
import net from 'net';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { WebSocketServer } from 'ws';
import { config } from './config.js';
import { db } from './db/connection.js';
import { initWorkerPool, shutdownWorkerPool, getPoolStats } from './db/worker-pool.js';
import { createAsyncDb, type AsyncDb } from './db/async-db.js';
import { runMigrations } from './db/migrate.js';
import { seedDatabase } from './db/seed.js';
import { errorHandler } from './middleware/errorHandler.js';
import { authMiddleware } from './middleware/auth.js';
import { setupWebSocket, broadcast, allClients, stopWebSocketHeartbeat } from './ws/server.js';
import { crashGuardMiddleware, currentRequestRoute } from './middleware/crashResiliency.js';
import { recordCrash, resetDisabledRoutesOnStartup } from './services/crashTracker.js';
import { createLogger } from './utils/logger.js';

// Structured logger for this module — used by critical error handlers, cron error sinks,
// and shutdown diagnostics. Do NOT replace console.log wholesale — legacy call sites
// are being migrated incrementally.
const log = createLogger('server');

// Routes
import authRoutes from './routes/auth.routes.js';
import ticketRoutes from './routes/tickets.routes.js';
import customerRoutes from './routes/customers.routes.js';
import inventoryRoutes from './routes/inventory.routes.js';
// Inventory enrichment (criticalaudit.md §48).
import stocktakeRoutes from './routes/stocktake.routes.js';
import inventoryEnrichRoutes from './routes/inventoryEnrich.routes.js';
import posEnrichRoutes from './routes/posEnrich.routes.js';
import invoiceRoutes from './routes/invoices.routes.js';
import leadRoutes from './routes/leads.routes.js';
import estimateRoutes from './routes/estimates.routes.js';
import posRoutes from './routes/pos.routes.js';
import reportRoutes from './routes/reports.routes.js';
import smsRoutes from './routes/sms.routes.js';
import employeeRoutes from './routes/employees.routes.js';
import settingsRoutes from './routes/settings.routes.js';
import settingsExportRoutes from './routes/settingsExport.routes.js';
import automationRoutes from './routes/automations.routes.js';
import snippetRoutes from './routes/snippets.routes.js';
import notificationRoutes from './routes/notifications.routes.js';
import importRoutes from './routes/import.routes.js';
import searchRoutes from './routes/search.routes.js';
import tvRoutes from './routes/tv.routes.js';
import preferenceRoutes from './routes/preferences.routes.js';
import catalogRoutes, { syncCostPricesFromCatalog } from './routes/catalog.routes.js';
import { scrapeCatalog } from './services/catalogScraper.js';
import repairPricingRoutes from './routes/repairPricing.routes.js';
import trackingRoutes from './routes/tracking.routes.js';
import expenseRoutes from './routes/expenses.routes.js';
import loanerRoutes from './routes/loaners.routes.js';
import customFieldRoutes from './routes/customFields.routes.js';
import refundRoutes from './routes/refunds.routes.js';
import rmaRoutes from './routes/rma.routes.js';
import giftCardRoutes from './routes/giftCards.routes.js';
import tradeInRoutes from './routes/tradeIns.routes.js';
import blockchypRoutes from './routes/blockchyp.routes.js';
import accountRoutes from './routes/account.routes.js';
import onboardingRoutes from './routes/onboarding.routes.js';
import portalRoutes from './routes/portal.routes.js';
import portalEnrichRoutes from './routes/portal-enrich.routes.js';
import voiceRoutes, { voiceStatusWebhookHandler, voiceRecordingWebhookHandler, voiceTranscriptionWebhookHandler, voiceInstructionsHandler, voiceInboundWebhookHandler } from './routes/voice.routes.js';
// CRM + marketing enrichment (audit section 49): health score, LTV tier,
// segments, campaigns, wallet pass, photo mementos.
import crmRoutes from './routes/crm.routes.js';
import campaignsRoutes from './routes/campaigns.routes.js';
// Communications team inbox enrichment (audit section 51): shared assignment,
// tags, retry queue, sentiment, bulk SMS, template analytics, SLA stats.
import inboxRoutes from './routes/inbox.routes.js';
// Technician bench workflow (audit section 44): device templates + bench timer
// + QC sign-off + parts defect reporter. Cross-cutting with POS (43) and
// Inventory (48) via device_model_templates.
import deviceTemplateRoutes from './routes/deviceTemplates.routes.js';
import benchRoutes from './routes/bench.routes.js';
import { smsInboundWebhookHandler, smsStatusWebhookHandler } from './routes/sms.routes.js';
import { seedDeviceModels } from './db/device-models-seed-runner.js';
import { initSmsProvider } from './services/smsProvider.js';
import adminRoutes from './routes/admin.routes.js';
import billingRoutes, { webhookHandler as stripeWebhookHandler } from './routes/billing.routes.js';
import { scheduleBackup } from './services/backup.js';
import { sendDailyReport } from './services/scheduledReports.js';
// Multi-tenant imports
import { initMasterDb, getMasterDb, closeMasterDb } from './db/master-connection.js';
// buildTemplateDb is invoked internally by migrateAllTenants(); no direct import needed.
import { migrateAllTenants } from './db/migrate-all-tenants.js';
import { getTenantDb, closeAllTenantDbs } from './db/tenant-pool.js';
import { tenantResolver } from './middleware/tenantResolver.js';
import { requireFeature } from './middleware/tierGate.js';
import signupRoutes from './routes/signup.routes.js';
// Legacy master-admin routes REMOVED — security risk (no 2FA, default password 'changeme123')
// Use /super-admin/api instead (has mandatory 2FA, proper validation, session management)
// import masterAdminRoutes from './routes/master-admin.routes.js';
import superAdminRoutes from './routes/super-admin.routes.js';
import { setMasterDb } from './utils/masterAudit.js';

/**
 * Helper: iterate all active tenant DBs (multi-tenant) or just the global db (single-tenant).
 *
 * SEC-BG6: Previously opened a fresh `new Database(path)` handle per tenant on EVERY tick,
 * thrashing the filesystem and bypassing the LRU tenant pool in `db/tenant-pool.ts`. For
 * background jobs that touch all tenants hourly (session cleanup, reminders, catalog sync)
 * that meant opening/closing dozens of handles each tick across the fleet.
 *
 * Fix: route both variants through `getTenantDb(slug)` so we share the pool with request
 * handlers. The pool handles WAL+pragma setup, LRU eviction, and health checks. The callback
 * MUST NOT close the handle — the pool owns it.
 */
function forEachDb(callback: (slug: string | null, tenantDb: any) => void): void {
  if (!config.multiTenant) {
    callback(null, db);
    return;
  }
  const masterDb = getMasterDb();
  if (!masterDb) { callback(null, db); return; }
  const tenants = masterDb.prepare("SELECT slug FROM tenants WHERE status = 'active'").all() as { slug: string }[];
  for (const t of tenants) {
    try {
      // SEC-BG6: reuse the connection from tenant-pool.ts instead of opening a new handle.
      const pooled = getTenantDb(t.slug);
      callback(t.slug, pooled);
    } catch (err) {
      // Surface structured so ops can see when a tenant DB is unreachable.
      // eslint-disable-next-line @typescript-eslint/no-use-before-define
      log.error('forEachDb: tenant iteration failed', {
        tenantSlug: t.slug,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
}

/**
 * Async variant: for background tasks that need await (e.g., sending SMS).
 * SEC-BG6: Uses the tenant pool (same as `forEachDb`). Do NOT close the handle — pool-owned.
 */
async function forEachDbAsync(callback: (slug: string | null, tenantDb: any) => Promise<void>): Promise<void> {
  if (!config.multiTenant) {
    await callback(null, db);
    return;
  }
  const masterDb = getMasterDb();
  if (!masterDb) { await callback(null, db); return; }
  const tenants = masterDb.prepare("SELECT slug FROM tenants WHERE status = 'active'").all() as { slug: string }[];
  for (const t of tenants) {
    try {
      // SEC-BG6: reuse the pooled connection.
      const pooled = getTenantDb(t.slug);
      await callback(t.slug, pooled);
    } catch (err) {
      // eslint-disable-next-line @typescript-eslint/no-use-before-define
      log.error('forEachDbAsync: tenant iteration failed', {
        tenantSlug: t.slug,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
}

// ─── Startup validation ──────────────────────────────────────────────
import { validateStartupEnvironment } from './utils/startupValidation.js';
validateStartupEnvironment();

// Clear any routes that were auto-disabled by the crash tracker in a previous
// server session. Rationale: a fresh restart = fresh chance. If a route is
// still broken, it will re-disable itself within 3 requests. This unblocks the
// common operator flow of "I fixed the bug, I restarted, why is it still off?"
resetDisabledRoutesOnStartup();

// Initialize database (single-tenant)
runMigrations(db);
seedDatabase(db);
seedDeviceModels(db);

// Initialize async worker pool for non-blocking DB queries (pre-warms all threads)
await initWorkerPool(config.dbPath);

// Start persistent metrics collector (samples every 60s, hourly rollup)
import { startMetricsCollector } from './services/metricsCollector.js';
startMetricsCollector();

// Auto-encrypt any plaintext sensitive config values (one-time migration)
import { ENCRYPTED_CONFIG_KEYS, encryptConfigValue } from './utils/configEncryption.js';
{
  const rows = db.prepare('SELECT key, value FROM store_config').all() as { key: string; value: string }[];
  for (const row of rows) {
    if (ENCRYPTED_CONFIG_KEYS.has(row.key) && row.value && !row.value.startsWith('enc:v')) {
      db.prepare('UPDATE store_config SET value = ? WHERE key = ?').run(encryptConfigValue(row.value), row.key);
    }
  }
}

// Initialize multi-tenant infrastructure (no-op if MULTI_TENANT != true)
if (config.multiTenant) {
  initMasterDb();
  setMasterDb(getMasterDb());
  // migrateAllTenants() refreshes the template DB first AND walks every active
  // tenant to apply any new migrations. This prevents schema drift — without it,
  // new migration files only reached brand-new tenants (via template copy) while
  // existing tenants silently fell behind. Replaces the former direct buildTemplateDb()
  // call since migrateAllTenants() already calls it internally.
  // Fire-and-forget: failures are recorded to the master DB's failed_tenants table
  // and surfaced on the admin dashboard, so we don't block startup on slow/bad tenants.
  migrateAllTenants().catch((err) => {
    console.error('[startup] migrateAllTenants crashed:', err);
  });

  // First-run setup wizard grandfather pass (SSW1):
  // For every existing tenant that has already completed the original setup
  // (store_config.setup_completed = 'true') but doesn't yet have a wizard_completed
  // value, mark it as 'grandfathered' so the new wizard gate in App.tsx doesn't
  // force them back into the wizard. This is a one-shot idempotent write — it
  // only touches rows where wizard_completed IS NULL, so re-running is safe.
  // Brand-new tenants provisioned after this change will not have setup_completed
  // set initially (or will have it but no wizard_completed), and the wizard will
  // write wizard_completed=true/skipped at the end of its flow.
  {
    const masterDb = getMasterDb();
    if (masterDb) {
      try {
        const tenants = masterDb.prepare(
          "SELECT slug, db_path FROM tenants WHERE status = 'active'"
        ).all() as Array<{ slug: string; db_path: string }>;
        let grandfathered = 0;
        for (const t of tenants) {
          let tdb: Database.Database | null = null;
          try {
            const tenantPath = path.join(config.tenantDataDir, t.db_path);
            tdb = new Database(tenantPath);
            const setupRow = tdb.prepare(
              "SELECT value FROM store_config WHERE key = 'setup_completed'"
            ).get() as { value: string } | undefined;
            const wizardRow = tdb.prepare(
              "SELECT value FROM store_config WHERE key = 'wizard_completed'"
            ).get() as { value: string } | undefined;
            if (setupRow?.value === 'true' && !wizardRow) {
              tdb.prepare(
                "INSERT OR REPLACE INTO store_config (key, value) VALUES ('wizard_completed', 'grandfathered')"
              ).run();
              grandfathered++;
            }
          } catch (err) {
            console.error(`[Wizard-grandfather] Failed for tenant ${t.slug}:`, err);
          } finally {
            try { tdb?.close(); } catch { /* ignore */ }
          }
        }
        if (grandfathered > 0) {
          console.log(`[Wizard-grandfather] Marked ${grandfathered} existing tenant(s) as 'grandfathered' so they skip the new setup wizard`);
        }
      } catch (err) {
        console.error('[Wizard-grandfather] Pass failed:', err);
      }
    }
  }

  // Check if super admin exists — if not, prompt for setup via dashboard or web panel
  {
    const masterDb = getMasterDb();
    if (masterDb) {
      const existing = masterDb.prepare('SELECT id FROM super_admins LIMIT 1').get();
      if (!existing) {
        console.log('\n  ============================================');
        console.log('  No super admin configured.');
        console.log('  Open the Server Dashboard or visit /super-admin to set up.');
        console.log('  ============================================\n');
      }
    }
  }
}

// Safety check: refuse to start in production with default password, warn in development
try {
  const adminUser = db.prepare("SELECT password_hash FROM users WHERE username = 'admin'").get() as { password_hash: string } | undefined;
  if (adminUser) {
    const isDefault = bcrypt.compareSync('admin123', adminUser.password_hash);
    if (isDefault) {
      if (config.nodeEnv === 'production') {
        console.error('\n  FATAL: The default admin password (admin123) is still in use!');
        console.error('  Change the admin password before running in production.\n');
        process.exit(1);
      } else {
        console.warn('\n  WARNING: Admin account still uses the default password (admin123).');
        console.warn('  Change it before deploying to production.\n');
      }
    }
  }
} catch (err) {
  console.warn('[Startup] Could not verify admin password:', (err as Error).message);
}

// Auto-sync inventory cost prices from supplier catalog
syncCostPricesFromCatalog(db);

// Initialize SMS provider
initSmsProvider(db);

const app = express();
app.set('trust proxy', 1); // Trust first proxy (for rate limiting behind nginx/cloudflare)
// ENR-INFRA7: Enable weak ETags for JSON API responses (allows 304 Not Modified)
app.set('etag', 'weak');

// HTTPS: require SSL certs — refuse to start without them
const certsDir = path.resolve(__dirname, '../certs');
const hasCerts = fs.existsSync(path.join(certsDir, 'server.key')) && fs.existsSync(path.join(certsDir, 'server.cert'));
if (!hasCerts) {
  console.error('\n  FATAL: SSL certificates not found.');
  console.error(`  Expected: ${path.join(certsDir, 'server.key')} and ${path.join(certsDir, 'server.cert')}`);
  console.error('  Generate with: openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.cert -days 3650 -nodes -subj "/CN=localhost"');
  console.error('  The service cannot run over plain HTTP.\n');
  process.exit(1);
}

const tlsOptions = {
  key: fs.readFileSync(path.join(certsDir, 'server.key')),
  cert: fs.readFileSync(path.join(certsDir, 'server.cert')),
  minVersion: 'TLSv1.2' as const,
};

// The HTTPS server handles Express + WebSocket
const httpsServer = createHttpsServer(tlsOptions, app);
const protocol = 'https';

// SEC-H5: Sanitize host and URL before placing them in a Location header.
// - Strip CR/LF/NULL to block response-splitting.
// - Restrict host to legal hostname characters (letters, digits, dot, hyphen, colon for port).
// - `encodeURI` the path portion so any stray bytes get percent-encoded rather than injected raw.
function sanitizeRedirectHost(rawHost: string): string {
  const noCrlf = rawHost.replace(/[\r\n\0]/g, '').split(':')[0];
  // Allow only hostname-safe chars; fall back to 'localhost' on anything weird.
  if (!/^[a-zA-Z0-9.-]+$/.test(noCrlf) || noCrlf.length > 253) return 'localhost';
  return noCrlf;
}

function sanitizeRedirectUrl(rawUrl: string | undefined): string {
  if (!rawUrl) return '/';
  // Strip CR/LF/NULL to prevent header injection.
  const noCrlf = rawUrl.replace(/[\r\n\0]/g, '');
  // Only permit path-style URLs (reject protocol-relative // or schemes).
  if (!noCrlf.startsWith('/') || noCrlf.startsWith('//')) return '/';
  try {
    return encodeURI(decodeURI(noCrlf));
  } catch {
    return '/';
  }
}

// An HTTP server that only sends redirects (for plain HTTP hitting the same port)
const httpRedirectServer = createServer((req, res) => {
  const host = sanitizeRedirectHost(req.headers.host || '');
  const safeUrl = sanitizeRedirectUrl(req.url);
  const httpsHost = config.port === 443 ? host : `${host}:${config.port}`;
  res.writeHead(301, { Location: `https://${httpsHost}${safeUrl}` });
  res.end();
});

// SEC-BG7: Track every setInterval handle so shutdown() can cancel them explicitly.
// Background timers were previously .unref()'d, which lets the process exit when nothing
// else holds it — but does NOT cancel in-flight ticks. During a graceful shutdown a tick
// could still fire AFTER we start closing DB handles, causing "DB is closed" crashes in
// logs. trackInterval() is a drop-in wrapper: call it INSTEAD of setInterval().
//
// Accepts either a sync void callback or an async callback — the return value is
// deliberately discarded, matching setInterval's behavior.
const backgroundIntervals: NodeJS.Timeout[] = [];
function trackInterval(
  fn: () => void | Promise<void>,
  ms: number,
  options: { unref?: boolean } = {}
): NodeJS.Timeout {
  const handle = setInterval(() => {
    try {
      const result = fn();
      // If the callback returns a promise, catch any rejection so the timer never
      // triggers an unhandledRejection.
      if (result && typeof (result as Promise<void>).catch === 'function') {
        (result as Promise<void>).catch((err) => {
          log.error('trackInterval: async callback rejected', {
            error: err instanceof Error ? err.message : String(err),
          });
        });
      }
    } catch (err) {
      log.error('trackInterval: sync callback threw', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, ms);
  if (options.unref !== false) handle.unref();
  backgroundIntervals.push(handle);
  return handle;
}

// SEC-AL5: Audit log retention policy — default 730 days (2 years) for compliance.
// Override via env var AUDIT_LOG_RETENTION_DAYS. Values < 1 fall back to 730.
const AUDIT_LOG_RETENTION_DAYS = (() => {
  const n = parseInt(process.env.AUDIT_LOG_RETENTION_DAYS || '730', 10);
  return Number.isFinite(n) && n >= 1 ? n : 730;
})();

// TCP proxy: peek the first byte of each connection to detect TLS vs plain HTTP.
// TLS ClientHello starts with 0x16 — route to HTTPS. Anything else → HTTP redirect.
// @audit-fixed: Previously `buf[0] === 0x16` was evaluated without guarding
// against empty buffers. If a scanner sends a zero-byte probe (common for
// SYN+FIN probes), `buf.length === 0` and `buf[0]` is `undefined`, which is
// !== 0x16, so the socket was routed to httpRedirectServer. httpRedirectServer
// then tried to parse an empty payload as HTTP and emitted a parse error that
// could be seen in logs. Now we short-circuit on empty buffers by destroying
// the socket, mirroring the existing behavior for ECONNRESET probes.
const server = net.createServer((socket) => {
  socket.once('data', (buf) => {
    if (!buf || buf.length === 0) {
      try { socket.destroy(); } catch { /* already closed */ }
      return;
    }
    // Put the data back so the target server can read it
    socket.pause();
    const target = buf[0] === 0x16 ? httpsServer : httpRedirectServer;
    target.emit('connection', socket);
    socket.unshift(buf);
    socket.resume();
  });
  socket.on('error', () => {}); // Suppress ECONNRESET from scanners/probes
});

// SEC-WS1: WebSocket origin allowlist — mirrors the HTTP CORS allowlist.
// CORS does NOT apply to WebSocket upgrades, so we must manually verify the Origin
// header on the upgrade handshake to prevent Cross-Site WebSocket Hijacking (CSWH).
// Accepts:
//   - exact matches in allowedOrigins (defined below; we build a shared verifier)
//   - the configured BASE_DOMAIN and its subdomains (tenant slugs)
//   - RFC1918 private IPs + localhost variants (dev / LAN)
// Rejects anything else. Missing Origin header is rejected in production (unlike CORS
// which permits it for non-browser tools) because legitimate browser WS clients always
// send Origin on upgrade — curl/node clients can use /api/v1 HTTP endpoints instead.
function isWsOriginAllowed(origin: string | undefined): boolean {
  if (!origin) {
    // Dev: allow (native tooling/tests). Prod: reject — browsers always send Origin.
    return config.nodeEnv !== 'production';
  }
  // Exact allowlist (defined below in `allowedOrigins`)
  try {
    const envList = (process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean)) || [];
    const localExact = [
      `https://localhost:${config.port}`,
      `http://localhost:${config.port}`,
    ];
    if (envList.includes(origin) || localExact.includes(origin)) return true;

    const url = new URL(origin);
    const hostname = url.hostname;
    const base = config.baseDomain;
    if (base && (hostname === base || hostname.endsWith('.' + base))) return true;
    if (
      /^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(hostname) ||
      hostname === 'localhost' ||
      hostname === '127.0.0.1' ||
      hostname.endsWith('.localhost')
    ) {
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

// WebSocket (attaches to the HTTPS server, not the TCP proxy)
const wss = new WebSocketServer({
  server: httpsServer,
  maxPayload: 65536,
  verifyClient: (info, cb) => {
    const origin = info.req.headers.origin;
    if (isWsOriginAllowed(origin)) {
      cb(true);
    } else {
      log.warn('WebSocket upgrade rejected: disallowed origin', {
        origin: origin || '(none)',
        remoteAddr: info.req.socket.remoteAddress,
      });
      cb(false, 403, 'Forbidden origin');
    }
  },
});
setupWebSocket(wss);

// Redirect middleware for requests arriving via reverse proxy (x-forwarded-proto)
// SEC-H5: Sanitize host/URL to prevent CRLF injection in Location header.
app.use((req, res, next) => {
  if (req.headers['x-forwarded-proto'] === 'http') {
    const host = sanitizeRedirectHost(req.headers.host || '');
    const safeUrl = sanitizeRedirectUrl(req.url);
    return res.redirect(301, `https://${host}${safeUrl}`);
  }
  next();
});

// Middleware
import compression from 'compression';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';

// ENR-MW: Response compression (gzip/brotli) — reduces bandwidth for JSON API responses and static assets
app.use(compression({
  // Only compress responses above 1KB (small responses don't benefit from compression)
  threshold: 1024,
  // Skip compression for already-compressed assets and server-sent events
  filter: (req, res) => {
    if (req.headers['x-no-compression']) return false;
    // Don't compress WebSocket upgrade requests or SSE streams
    if (req.headers.accept === 'text/event-stream') return false;
    return compression.filter(req, res);
  },
}));
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      // MW3: 'unsafe-inline' removed from global CSP for security. Admin panel (/admin)
      // and super-admin panel get their own relaxed CSP via per-route override below.
      scriptSrc: ["'self'", 'https://static.cloudflareinsights.com'],
      scriptSrcAttr: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
      imgSrc: ["'self'", 'data:', 'blob:', 'https:'],
      connectSrc: ["'self'", 'ws:', 'wss:', 'https:', 'https://cloudflareinsights.com'],
      fontSrc: ["'self'", 'https://fonts.gstatic.com'],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"],
      baseUri: ["'self'"],
      formAction: ["'self'"],
    },
  },
  crossOriginEmbedderPolicy: false,
  hsts: {
    maxAge: 63072000, // 2 years
    includeSubDomains: true,
    preload: true,
  },
  // SEC-H3: Explicitly enable X-Content-Type-Options: nosniff (helmet default, pinned for clarity).
  noSniff: true,
  // SEC-H10: Referrer-Policy — strict-origin-when-cross-origin leaks only origin on cross-site,
  // and nothing on HTTPS→HTTP downgrades. Strong default for a CRM.
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
}));
// Permissions-Policy: disable browser features we don't use
app.use((_req, res, next) => {
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()');
  next();
});
const allowedOrigins = [
  `https://localhost:${config.port}`,
  `http://localhost:${config.port}`,
  // Production/custom domains from ALLOWED_ORIGINS env var (comma-separated)
  ...(process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean) || []),
];

// SEC-H7: In production, requests with no Origin header (curl/postman) are rejected
// for sensitive endpoints. Health and webhook paths remain accessible so infra probes
// and upstream providers still work. Note: CORS only affects browser fetches — tools
// like curl that don't send Origin can still hit the API directly via server-side calls.
// This closes the common browser-extension bypass where `fetch` omits the Origin header.
// SEC-H7 (post-enrichment): customer-facing public pay pages and the portal
// enrichment v2 endpoints are opened from email clients / mobile browsers that
// often omit Origin. Adding them here prevents the production Origin guard from
// 403'ing a real customer trying to pay or download a receipt.
const NO_ORIGIN_ALLOWED_PATHS = [
  '/health',
  '/api/v1/health',
  '/api/v1/info',
  '/api/v1/auth/', // login flows are rate-limited separately
  '/api/v1/track',
  '/api/v1/portal',
  '/api/v1/public/', // public payment-link pay page, and any future public customer pages
  '/portal/api/v2', // portal-enrich v2 routes (separate base from /api/v1/portal)
];
function isPathNoOriginExempt(path: string): boolean {
  return NO_ORIGIN_ALLOWED_PATHS.some((p) => path === p || path.startsWith(p));
}
function isPathWebhook(path: string): boolean {
  return path.includes('/webhook');
}

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) {
      // Dev: permissive (curl/postman OK). Prod: rely on middleware below to block.
      return callback(null, true);
    }
    if (allowedOrigins.includes(origin)) return callback(null, true);
    try {
      const url = new URL(origin);
      const hostname = url.hostname;
      // Allow BASE_DOMAIN and all its subdomains (tenant subdomains)
      const base = config.baseDomain;
      if (base && (hostname === base || hostname.endsWith('.' + base))) {
        return callback(null, true);
      }
      // Allow RFC1918 private IPs and localhost variants
      if (/^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(hostname) || hostname === 'localhost' || hostname === '127.0.0.1' || hostname.endsWith('.localhost')) {
        return callback(null, true);
      }
    } catch {}
    callback(new Error('CORS not allowed'));
  },
  credentials: true,
}));

// SEC-H7: Production guard — reject Origin-less requests on sensitive routes.
// Runs AFTER cors() so preflight still works; only the actual request is policed.
if (config.nodeEnv === 'production') {
  app.use((req, res, next) => {
    // Always let OPTIONS through — the cors() middleware above handled preflight.
    if (req.method === 'OPTIONS') return next();
    const origin = req.headers.origin;
    if (origin) return next();
    if (isPathNoOriginExempt(req.path) || isPathWebhook(req.path)) return next();
    // GETs to static assets and the SPA are fine without Origin.
    if (req.method === 'GET' && !req.path.startsWith('/api/')) return next();
    log.warn('Rejected request without Origin header', {
      method: req.method,
      path: req.path,
      ua: req.headers['user-agent'],
    });
    return res.status(403).json({ success: false, message: 'Origin header required' });
  });
}
app.use(cookieParser());

// SEC-H4: Rate limiter is placed BEFORE body parsing (express.json / compression).
// Why: express.json({ limit: '10mb' }) at 300 req/min = 3 GB of buffered JSON per IP per minute,
// which lets a single attacker exhaust memory by flooding huge bodies. By rate-limiting first,
// we bound the number of requests that can reach the parser. compression() is a response
// middleware so its position is less critical, but we keep it after the limiter for symmetry.
//
// SEC-H9: apiRateMap uses LRU eviction (not clear-all) to preserve hot entries and only drop
// the coldest 20% when size exceeds the cap. Prevents a single burst from wiping all state.
//
// SEC-H9: KNOWN LIMITATION — In-memory rate limiter resets when the server restarts.
// Production behind a reverse proxy should use Redis-backed rate limiting
// (e.g., rate-limiter-flexible with Redis store) or an upstream WAF/CDN.
interface RateEntry { count: number; resetAt: number; lastSeen: number }
const apiRateMap = new Map<string, RateEntry>();
const API_RATE_LIMIT = 300;
const API_RATE_WINDOW = 60_000; // 1 minute
const API_RATE_MAP_MAX = 10_000;
app.use('/api/v1', (req, res, next) => {
  // Skip endpoints that have their own rate limiting
  if (req.path.startsWith('/auth') || req.path.includes('webhook') || req.path.startsWith('/track') || req.path.startsWith('/portal')) {
    return next();
  }
  // Management routes: ALWAYS bypass rate limiter.
  // They're localhost-only + super admin JWT authenticated — can't be abused externally.
  // Super admin dashboard must never be blocked by tenant traffic.
  if (req.path.startsWith('/management')) {
    return next();
  }
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const now = Date.now();
  const entry = apiRateMap.get(ip);
  if (entry && now < entry.resetAt) {
    if (entry.count >= API_RATE_LIMIT) {
      res.setHeader('Retry-After', String(Math.ceil((entry.resetAt - now) / 1000)));
      return res.status(429).json({ success: false, message: 'Too many requests' });
    }
    entry.count++;
    entry.lastSeen = now;
  } else {
    apiRateMap.set(ip, { count: 1, resetAt: now + API_RATE_WINDOW, lastSeen: now });
  }
  next();
});

// SEC-H9: LRU eviction instead of full clear. Drops the oldest 20% once the map exceeds
// its cap, preserving hot entries so an attacker cannot flush rate state by flooding new IPs.
// SEC-BG7: Registered via trackInterval so shutdown() can clear it.
trackInterval(() => {
  const now = Date.now();
  // Pass 1: drop expired windows (cheap).
  for (const [ip, entry] of apiRateMap) {
    if (now >= entry.resetAt) apiRateMap.delete(ip);
  }
  // Pass 2: if still over cap, evict the coldest 20% by lastSeen.
  if (apiRateMap.size > API_RATE_MAP_MAX) {
    const entries = Array.from(apiRateMap.entries()).sort(
      (a, b) => a[1].lastSeen - b[1].lastSeen
    );
    const evictCount = Math.ceil(entries.length * 0.2);
    for (let i = 0; i < evictCount; i++) {
      apiRateMap.delete(entries[i][0]);
    }
  }
}, 60_000);

// Stripe webhook — must be mounted BEFORE express.json() because signature verification needs raw body.
// Kept here (after rate limiter, before json parser) so its own express.raw() limit applies.
app.post('/api/v1/billing/webhook', express.raw({ type: 'application/json', limit: '1mb' }), stripeWebhookHandler);

app.use(express.json({
  limit: '10mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; }, // Capture raw body for webhook signature verification
}));
// SEC-H6: Cap urlencoded payloads at 1mb — prevents unbounded form-body memory use.
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// HTTP request logging (ENR-INFRA3) — logs method, path, status, response time
import { requestLogger } from './middleware/requestLogger.js';
app.use(requestLogger);

// ENR-INFRA7: API Cache-Control headers — enable ETag-based conditional requests
// GET API responses include Cache-Control: private, no-cache (forces revalidation via If-None-Match)
// This enables 304 Not Modified responses when data hasn't changed, reducing bandwidth
app.use('/api/v1', (req, _res, next) => {
  if (req.method === 'GET') {
    _res.setHeader('Cache-Control', 'private, no-cache');
  }
  next();
});

// Inject database connection into every request
// In single-tenant mode: always the global db
// In multi-tenant mode: tenantResolver overrides req.db with the tenant's DB
app.use((req, _res, next) => {
  req.db = db; // Default to global db (single-tenant fallback)
  // Async DB: non-blocking worker thread version (for gradual migration)
  req.asyncDb = createAsyncDb(config.dbPath);
  next();
});
app.use(tenantResolver); // In multi-tenant mode, overrides req.db based on subdomain

// Bare domain "/" in multi-tenant mode — fall through to SPA (React LandingPage handles it)
// The SPA's isBareHostname() detects bare localhost/domain and renders the landing page component.

// CSRF protection: reject state-changing requests without JSON content type
// HTML forms can't send application/json, so this blocks cross-site form submissions
app.use((req, res, next) => {
  if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
    const ct = req.headers['content-type'] || '';
    // Allow: JSON, multipart (file uploads), webhooks
    if (ct.includes('application/json') || ct.includes('multipart/form-data') || req.path.includes('webhook') || req.path.includes('/setup')) {
      return next();
    }
    // Block non-JSON state-changing requests
    return res.status(403).json({ success: false, message: 'Invalid content type' });
  }
  next();
});

// Crash resiliency: block auto-disabled routes, track current route for crash attribution
// Placed after rate limiting and CSRF so disabled routes still count against rate limits
app.use(crashGuardMiddleware);

// QR code generation endpoint (local, no external service)
import QRCode from 'qrcode';
app.get('/api/v1/qr', authMiddleware, async (req, res) => {
  const data = req.query.data as string;
  if (!data || data.length > 2000) return res.status(400).send('Invalid data');
  try {
    const png = await QRCode.toBuffer(data, { width: 200, margin: 1 });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.send(png);
  } catch {
    res.status(500).send('QR generation failed');
  }
});

// Static files: serve uploaded files (restricted to uploadsPath, no traversal)
app.use('/uploads', (req, res, next) => {
  const decoded = decodeURIComponent(req.path);
  if (decoded.includes('..') || decoded.includes('\\')) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  // In multi-tenant mode, serve from uploads/{slug}/ subdirectory
  const basePath = req.tenantSlug
    ? path.join(config.uploadsPath, req.tenantSlug)
    : config.uploadsPath;

  // Resolve and verify the file is inside the appropriate uploads path
  const resolved = path.resolve(basePath, decoded.replace(/^\//, ''));
  if (!resolved.startsWith(path.resolve(basePath))) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  // Dynamically serve from the correct directory
  express.static(basePath, { dotfiles: 'deny', index: false })(req, res, next);
});

// Public info endpoint — returns server LAN address for QR codes etc.
app.get('/api/v1/info', (_req, res) => {
  const ifaces = os.networkInterfaces();
  let lanIp = 'localhost';
  for (const addrs of Object.values(ifaces)) {
    for (const addr of (addrs || [])) {
      if (addr.family === 'IPv4' && !addr.internal) { lanIp = addr.address; break; }
    }
    if (lanIp !== 'localhost') break;
  }
  res.json({ success: true, data: { lan_ip: lanIp, port: config.port, server_url: `${protocol}://${lanIp}:${config.port}`, protocol } });
});

// Multi-tenant routes (public signup + super admin panel)
app.use('/api/v1/signup', signupRoutes);
// app.use('/master/api', masterAdminRoutes); // REMOVED — use /super-admin/api instead
app.use('/super-admin/api', superAdminRoutes);
// Relaxed CSP for admin panels — they use inline scripts/onclick handlers
const adminCsp = "default-src 'self'; script-src 'self' 'unsafe-inline'; script-src-attr 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' ws: wss:; font-src 'self'; frame-ancestors 'none'";
app.get('/super-admin', (_req, res) => {
  if (!config.multiTenant) return res.status(404).send('Not available');
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/super-admin.html'));
});
app.get('/super-admin/*', (_req, res) => {
  if (!config.multiTenant) return res.status(404).send('Not available');
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/super-admin.html'));
});

// API Routes (auth does NOT require middleware)
app.use('/api/v1/auth', authRoutes);

// SMS webhooks — public (no auth), providers POST here
// In multi-tenant mode, webhooks must include tenant slug in the URL path for correct DB routing

// S9+S14: In-memory rate limiter for webhooks (60 req/min per IP)
// SEC-H9: Same in-memory limitation as the global rate limiter — resets on restart.
// See comment on apiRateMap above for production recommendations.
const webhookRateMap = new Map<string, { count: number; resetAt: number }>();
function webhookRateLimit(req: any, res: any, next: any) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const now = Date.now();
  const entry = webhookRateMap.get(ip);
  if (entry && now < entry.resetAt) {
    if (entry.count >= 60) {
      return res.status(429).json({ success: false, message: 'Too many webhook requests' });
    }
    entry.count++;
  } else {
    webhookRateMap.set(ip, { count: 1, resetAt: now + 60_000 });
  }
  next();
}
// Periodically clean stale entries (every 5 min)
// MW4: .unref() so this timer doesn't keep the process alive during shutdown
// SEC-BG7: Registered via trackInterval so shutdown() can clear it.
trackInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of webhookRateMap) { if (now >= entry.resetAt) webhookRateMap.delete(ip); }
}, 5 * 60_000);

app.post('/api/v1/sms/inbound-webhook', webhookRateLimit, smsInboundWebhookHandler);
app.post('/api/v1/sms/status-webhook', webhookRateLimit, smsStatusWebhookHandler);

// Voice webhooks — public (no auth)
app.post('/api/v1/voice/inbound-webhook', webhookRateLimit, voiceInboundWebhookHandler);
app.post('/api/v1/voice/status-webhook', webhookRateLimit, voiceStatusWebhookHandler);
app.post('/api/v1/voice/recording-webhook', webhookRateLimit, voiceRecordingWebhookHandler);
app.post('/api/v1/voice/transcription-webhook', webhookRateLimit, voiceTranscriptionWebhookHandler);
app.get('/api/v1/voice/instructions/:action', webhookRateLimit, voiceInstructionsHandler);

// Multi-tenant webhook routes with tenant slug in URL path
// Providers should be configured to POST to: https://{slug}.bizarrecrm.com/api/v1/sms/inbound-webhook
// The tenantResolver middleware handles DB routing via subdomain. These explicit slug routes
// are for providers that don't support custom subdomains (use path-based routing instead):
if (config.multiTenant) {
  const webhookTenantResolver = (req: any, res: any, next: any) => {
    const { slug } = req.params;
    if (!slug || !req.tenantSlug) {
      // Resolve tenant from path param instead of subdomain
      const masterDb = getMasterDb();
      if (!masterDb) return res.status(500).json({ success: false, message: 'Internal error' });
      const tenant = masterDb.prepare("SELECT id, slug FROM tenants WHERE slug = ? AND status = 'active'").get(slug) as any;
      if (!tenant) return res.status(404).json({ success: false, message: 'Tenant not found' });
      try {
        req.db = getTenantDb(tenant.slug);
        req.tenantSlug = tenant.slug;
        req.tenantId = tenant.id;
      } catch {
        return res.status(500).json({ success: false, message: 'Database error' });
      }
    }
    next();
  };
  app.post('/api/v1/t/:slug/sms/inbound-webhook', webhookRateLimit, webhookTenantResolver, smsInboundWebhookHandler);
  app.post('/api/v1/t/:slug/sms/status-webhook', webhookRateLimit, webhookTenantResolver, smsStatusWebhookHandler);
  app.post('/api/v1/t/:slug/voice/inbound-webhook', webhookRateLimit, webhookTenantResolver, voiceInboundWebhookHandler);
  app.post('/api/v1/t/:slug/voice/status-webhook', webhookRateLimit, webhookTenantResolver, voiceStatusWebhookHandler);
}

// Public ticket tracking (no auth)
app.use('/api/v1/track', trackingRoutes);

// Customer self-service portal (no auth — uses portal sessions)
app.use('/api/v1/portal', portalRoutes);
// SEC-H17 (post-enrichment): portal-enrich v2 endpoints return customer-scoped
// data: receipts, warranty certs, photo URLs, loyalty points. Default to
// no-store so browsers/proxies don't cache PII between sessions on shared
// devices. Also X-Frame-Options DENY because the portal must not be framed
// by an attacker to steal click-to-review / click-to-refer actions. Individual
// handlers still set their own Content-Type.
app.use('/portal/api/v2', (_req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  next();
});
// Customer portal enrichment v2 (criticalaudit.md §45): timeline, queue,
// tech card, photo gallery, PDFs, reviews, loyalty, referrals.
app.use('/portal/api/v2', portalEnrichRoutes);

// Protected API routes
app.use('/api/v1/tickets', authMiddleware, ticketRoutes);
app.use('/api/v1/customers', authMiddleware, customerRoutes);
app.use('/api/v1/inventory', authMiddleware, inventoryRoutes);
// Inventory enrichment (criticalaudit.md §48) — stocktake is its own namespace,
// enrichment hangs off /inventory-enrich so it doesn't conflict with the
// main inventory routes owned by the inventory agent.
app.use('/api/v1/stocktake', authMiddleware, stocktakeRoutes);
app.use('/api/v1/inventory-enrich', authMiddleware, inventoryEnrichRoutes);
app.use('/api/v1/invoices', authMiddleware, invoiceRoutes);
app.use('/api/v1/leads', authMiddleware, leadRoutes);
app.use('/api/v1/estimates', authMiddleware, estimateRoutes);
app.use('/api/v1/pos', authMiddleware, posRoutes);
// POS Daily Flow enrichment (criticalaudit.md §43) — cash drawer shifts,
// top-five quick-add tiles, training sandbox, and the manager PIN gate.
// Separate namespace so it never collides with pos.routes.ts owned by the
// POS agent.
app.use('/api/v1/pos-enrich', authMiddleware, posEnrichRoutes);
app.use('/api/v1/reports', authMiddleware, reportRoutes);
app.use('/api/v1/sms', authMiddleware, smsRoutes);
app.use('/api/v1/employees', authMiddleware, employeeRoutes);
app.use('/api/v1/settings', authMiddleware, settingsRoutes);
// Additional settings routes owned by the configuration-UX agent.
// Mounted under /settings-ext so settings.routes.ts (earlier agent) stays untouched.
app.use('/api/v1/settings-ext', authMiddleware, settingsExportRoutes);
app.use('/api/v1/automations', authMiddleware, requireFeature('automations'), automationRoutes);
app.use('/api/v1/snippets', authMiddleware, snippetRoutes);
app.use('/api/v1/notifications', authMiddleware, notificationRoutes);
// OAuth callback must be public (RD redirects browser here before CRM login)
app.use('/api/v1/import/oauth', importRoutes);
app.use('/api/v1/import', authMiddleware, importRoutes);
app.use('/api/v1/search', authMiddleware, searchRoutes);
app.use('/api/v1/preferences', authMiddleware, preferenceRoutes);
app.use('/api/v1/catalog', authMiddleware, catalogRoutes);
app.use('/api/v1/repair-pricing', authMiddleware, repairPricingRoutes);
app.use('/api/v1/expenses', authMiddleware, expenseRoutes);
app.use('/api/v1/loaners', authMiddleware, loanerRoutes);
app.use('/api/v1/custom-fields', authMiddleware, requireFeature('customFields'), customFieldRoutes);
app.use('/api/v1/refunds', authMiddleware, refundRoutes);
app.use('/api/v1/rma', authMiddleware, rmaRoutes);
app.use('/api/v1/gift-cards', authMiddleware, giftCardRoutes);
app.use('/api/v1/trade-ins', authMiddleware, tradeInRoutes);
app.use('/api/v1/blockchyp', authMiddleware, blockchypRoutes);
app.use('/api/v1/voice', authMiddleware, voiceRoutes);
// Audit 44 — Technician bench workflow (device templates + bench timer + QC + defects)
app.use('/api/v1/device-templates', authMiddleware, deviceTemplateRoutes);
app.use('/api/v1/bench', authMiddleware, benchRoutes);
// Audit 49 — CRM + marketing (health score, LTV, segments, campaigns, wallet pass)
// TODO(MEDIUM, §26): wire a daily cron that runs recalculateAllCustomerHealth()
// + the birthday/churn dispatch helpers. For now these endpoints are invoked
// on-demand from the UI or from the management dashboard scheduler. Not a
// blocker because the on-demand path works; the cron just automates it.
app.use('/api/v1/crm', authMiddleware, crmRoutes);
app.use('/api/v1/campaigns', authMiddleware, campaignsRoutes);
// Audit 51 — Communications team inbox enrichment (assignment, tags, retry,
// sentiment, bulk SMS, template analytics, SLA stats). Purely additive:
// sms.routes / portal.routes / automations.routes are not modified.
app.use('/api/v1/inbox', authMiddleware, inboxRoutes);
import membershipRoutes from './routes/membership.routes.js';
app.use('/api/v1/membership', authMiddleware, requireFeature('memberships'), membershipRoutes);
app.use('/api/v1/account', authMiddleware, accountRoutes);
// Day-1 onboarding: getting-started checklist, sample data, shop-type template.
// Section 42 of criticalaudit.md. See routes/onboarding.routes.ts for details.
app.use('/api/v1/onboarding', authMiddleware, onboardingRoutes);
// Stripe billing (checkout + portal). Webhook is mounted earlier with express.raw() before JSON parser.
app.use('/api/v1/billing', authMiddleware, billingRoutes);

// Audit §52 — Billing / Money Flow enrichment (payment links, dunning, deposits).
// Public `/public/payment-links/:token` endpoints mount WITHOUT auth so the
// customer-facing /pay/:token page can fetch + confirm without a login.
import { paymentLinksAuthedRouter, paymentLinksPublicRouter } from './routes/paymentLinks.routes.js';
import dunningRoutes from './routes/dunning.routes.js';
import depositRoutes from './routes/deposits.routes.js';

// SEC-H17 (post-enrichment): lock down the public pay endpoint. Because this
// URL is handed out in customer emails and rendered inside a React page the
// customer opens themselves:
//   - X-Frame-Options: DENY     — no clickjacking of the pay page
//   - Cache-Control: no-store  — do not cache invoice amounts / link status
//   - Referrer-Policy: no-referrer — tokens live in the path; never leak via Referer
//   - CORS handled by global cors() + NO_ORIGIN_ALLOWED_PATHS exemption above
app.use('/api/v1/public/payment-links', (_req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  next();
});
app.use('/api/v1/public/payment-links', paymentLinksPublicRouter);
app.use('/api/v1/payment-links', authMiddleware, paymentLinksAuthedRouter);
app.use('/api/v1/dunning', authMiddleware, dunningRoutes);
app.use('/api/v1/deposits', authMiddleware, depositRoutes);

// TV display (no auth or simple token auth)
app.use('/api/v1/tv', tvRoutes);

// Admin panel (token-based auth handled in admin routes)
// In multi-tenant mode, the per-tenant admin panel is disabled — use /master/api/ instead
app.use('/api/v1/admin', adminRoutes);

// Management dashboard API (localhost-only, token auth — for Electron dashboard)
import managementRoutes from './routes/management.routes.js';
app.use('/api/v1/management', managementRoutes);

// Team management — shifts, my-queue, handoffs, mentions, goals, payroll lock,
// custom roles, and internal chat. criticalaudit.md §53.
import teamRoutes from './routes/team.routes.js';
import rolesRoutes from './routes/roles.routes.js';
import teamChatRoutes from './routes/teamChat.routes.js';
app.use('/api/v1/team', authMiddleware, teamRoutes);
app.use('/api/v1/roles', authMiddleware, rolesRoutes);
app.use('/api/v1/team-chat', authMiddleware, teamChatRoutes);

app.get('/admin', (req, res) => {
  if (config.multiTenant && req.tenantSlug) {
    return res.status(403).send('Server administration is not available for tenant shops. Contact the platform administrator.');
  }
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));
});

// SEC-H2: Widget iframe embedding — strict per-tenant origin allowlist.
// Prior behavior was to set `X-Frame-Options: ALLOWALL` + `frame-ancestors *`, which lets
// any site frame the portal and perform clickjacking on session-backed actions.
//
// New behavior:
//   1. Read `widget_allowed_origins` from the tenant's store_config. This is expected to be
//      a JSON array of origin strings (e.g. `["https://shop.example.com","https://example.com"]`).
//   2. If the Origin header on the request (or the Sec-Fetch-Site / Referer as a fallback)
//      matches one of the allowed origins, set `Content-Security-Policy: frame-ancestors <origin>`
//      so only THAT origin can embed this specific response. Also set `X-Frame-Options: ALLOW-FROM <origin>`
//      (legacy browsers) — modern browsers rely on CSP frame-ancestors.
//   3. Otherwise, leave the default deny (`frame-ancestors 'none'` from global helmet CSP).
//
// Notes:
//   - We intentionally do NOT set `X-Frame-Options: ALLOWALL` anymore; that header had no
//     standard meaning and is equivalent to not setting it, allowing embedding by anyone
//     only because no CSP overrode it. The fix is to actively pin the allowed origin.
//   - `X-Frame-Options: ALLOW-FROM` is deprecated and only honored by IE/legacy Edge, but
//     including it doesn't hurt and provides defense in depth for older browsers.
function getWidgetAllowedOrigins(reqDb: any): string[] {
  try {
    const row = reqDb?.prepare?.("SELECT value FROM store_config WHERE key = 'widget_allowed_origins'").get() as { value?: string } | undefined;
    if (!row?.value) return [];
    const parsed = JSON.parse(row.value);
    if (Array.isArray(parsed)) return parsed.filter((o): o is string => typeof o === 'string');
    return [];
  } catch {
    return [];
  }
}
app.use('/customer-portal', (req, res, next) => {
  if (req.query.mode !== 'widget') return next();

  const origin = (req.headers.origin || '').toString();
  const allowed = getWidgetAllowedOrigins((req as any).db);

  if (origin && allowed.includes(origin)) {
    // Pin framing to the exact allowed origin, nothing else.
    res.setHeader('Content-Security-Policy', `frame-ancestors ${origin}`);
    res.setHeader('X-Frame-Options', `ALLOW-FROM ${origin}`);
  } else {
    // No matching origin → fall through to the global deny. Log once per request so operators
    // can diagnose why a legitimate embed is being blocked (missing config row).
    log.warn('Widget embed rejected: origin not in allowlist', {
      origin: origin || '(none)',
      tenantSlug: (req as any).tenantSlug,
      allowedCount: allowed.length,
    });
    res.setHeader('Content-Security-Policy', "frame-ancestors 'none'");
    res.setHeader('X-Frame-Options', 'DENY');
  }
  next();
});

// Health check endpoint (must be BEFORE SPA wildcard)
app.get('/health', (_req, res) => {
  try {
    db.prepare('SELECT 1').get();
    res.json({ status: 'ok', uptime: process.uptime() });
  } catch {
    res.status(503).json({ status: 'error', message: 'Database unavailable' });
  }
});

// ENR-INFRA4: JSON health check for load balancers (no auth required)
// Includes DB status, memory usage, worker pool stats, and DB file size
app.get('/api/v1/health', (_req, res) => {
  let dbStatus = 'connected';
  let dbSizeBytes: number | null = null;
  try {
    db.prepare('SELECT 1').get();
    // Get DB file size for monitoring growth
    try {
      const stats = fs.statSync(config.dbPath);
      dbSizeBytes = stats.size;
    } catch {}
  } catch {
    dbStatus = 'disconnected';
  }

  const mem = process.memoryUsage();
  const poolStats = getPoolStats();

  const payload = {
    status: dbStatus === 'connected' ? 'ok' : 'degraded',
    uptime: process.uptime(),
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    db: {
      status: dbStatus,
      sizeBytes: dbSizeBytes,
      sizeMB: dbSizeBytes !== null ? Math.round(dbSizeBytes / 1024 / 1024 * 100) / 100 : null,
    },
    memory: {
      rss: Math.round(mem.rss / 1024 / 1024),
      heapUsed: Math.round(mem.heapUsed / 1024 / 1024),
      heapTotal: Math.round(mem.heapTotal / 1024 / 1024),
      external: Math.round(mem.external / 1024 / 1024),
    },
    workerPool: poolStats ? {
      threads: poolStats.threads,
      queueSize: poolStats.queueSize,
      completed: poolStats.completed,
    } : null,
  };
  const statusCode = dbStatus === 'connected' ? 200 : 503;
  res.status(statusCode).json(payload);
});

// AUD-M15: Explicit API 404 handler — prevents SPA fallback from swallowing typo'd API URLs
app.all('/api/*', (_req, res) => {
  res.status(404).json({ success: false, message: 'API endpoint not found' });
});

// Serve APK downloads (public, no auth — for new shop owners to get the mobile app)
const downloadsPath = path.resolve(__dirname, '../downloads');
if (!fs.existsSync(downloadsPath)) fs.mkdirSync(downloadsPath, { recursive: true });
app.use('/downloads', express.static(downloadsPath, {
  dotfiles: 'deny',
  index: false,
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.apk')) {
      res.setHeader('Content-Type', 'application/vnd.android.package-archive');
      res.setHeader('Content-Disposition', 'attachment; filename="BizarreCRM.apk"');
    }
  },
}));

// SPA fallback: serve web frontend
const webDistPath = path.resolve(__dirname, '../../web/dist');
if (!fs.existsSync(webDistPath)) {
  console.warn(`[WARN] Web dist folder not found at: ${webDistPath}`);
  console.warn('       Run "npm run build" to build the frontend.');
} else {
  console.log(`[Web] Serving frontend from: ${webDistPath}`);
}
// ENR-INFRA7: Static asset caching — hashed filenames get long cache, index.html gets short cache
app.use(express.static(webDistPath, {
  etag: true,
  lastModified: true,
  setHeaders: (res, filePath) => {
    // Vite hashed assets (e.g., assets/index-a1b2c3.js) — cache for 1 year
    if (/\/assets\//.test(filePath) && /\.[0-9a-f]{8,}\.(js|css|woff2?)$/i.test(filePath)) {
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    } else if (filePath.endsWith('.html')) {
      // HTML files — short cache to pick up deploys
      res.setHeader('Cache-Control', 'no-cache');
    } else {
      // Other static assets — cache for 1 hour with revalidation
      res.setHeader('Cache-Control', 'public, max-age=3600, must-revalidate');
    }
  },
}));
app.get('*', (_req, res) => {
  // Don't serve index.html for static asset requests (prevents stale hash 500s)
  if (/\.(css|js|map|ico|png|jpg|jpeg|gif|svg|webp|woff2?|ttf|eot)$/i.test(_req.path)) {
    res.status(404).end();
    return;
  }
  res.sendFile(path.join(webDistPath, 'index.html'));
});

// Error handler
app.use(errorHandler);

server.listen(config.port, config.host, () => {
  console.log('');
  console.log('  ╔══════════════════════════════════════════╗');
  console.log('  ║    BizarreCRM Server                     ║');
  console.log('  ╠══════════════════════════════════════════╣');
  console.log(`  ║  URL:  ${protocol}://${config.host}:${config.port}           ║`);
  console.log(`  ║  Mode: ${config.nodeEnv.padEnd(33)}║`);
  console.log(`  ║  SSL:  ${hasCerts ? 'ENABLED (self-signed)' : 'DISABLED (HTTP)'}${hasCerts ? '           ' : '              '}║`);
  console.log(`  ║  Admin: ${protocol}://${config.host}:${config.port}/admin     ║`);
  console.log('  ╚══════════════════════════════════════════╝');
  console.log('');

  // ENR-INFRA9: Feature flags — log which optional integrations are configured
  console.log('[Features] SMS:', process.env.TCX_HOST ? 'configured' : 'not configured');
  console.log('[Features] Email:', process.env.SMTP_HOST ? 'configured' : 'not configured');
  console.log('[Features] BlockChyp:', 'via settings UI');

  // Start backup scheduler
  // Tier: in single-tenant (self-hosted) mode, run the global per-shop backup cron.
  // In multi-tenant mode, run a single daily cron that iterates Pro tenants and backs
  // up each one. Free tenants don't get automated backups.
  if (!config.multiTenant) {
    scheduleBackup(db);
  } else {
    // Lazy import to avoid circular dependency between backup.ts and tenant-pool.ts
    import('./services/backup.js').then(({ scheduleMultiTenantBackups }) => {
      import('./db/tenant-pool.js').then(({ getTenantDb: getTenantDbFn }) => {
        scheduleMultiTenantBackups(getMasterDb, getTenantDbFn);
      });
    }).catch((err) => {
      console.error('[Backup] Failed to schedule multi-tenant backups:', err);
    });
  }

  // Membership renewal cron — check daily for subscriptions due for renewal
  // Runs every hour, processes subscriptions where current_period_end <= now
  //
  // SEC-BG4: Previously spawned unawaited IIFEs per due subscription, so a tenant with
  // 100 due memberships fired 100 parallel BlockChyp charges at once — saturating the
  // card network, crushing rate limits, and making failures impossible to order/debug.
  // Fix: use a SERIAL async loop with `await` per subscription and wrap each iteration
  // in its own try/catch so one failure doesn't abort the batch. Cap to MAX_PER_RUN;
  // any remainder is naturally picked up on the next tick (1 hour later).
  const MEMBERSHIP_MAX_PER_RUN = 10;
  trackInterval(async () => {
    try {
      const { chargeToken } = await import('./services/blockchyp.js');

      // forEachDbAsync lets us await the charges within each tenant's work unit.
      await forEachDbAsync(async (slug: string | null, tenantDb: any) => {
        let dueSubscriptions: any[] = [];
        try {
          dueSubscriptions = tenantDb.prepare(`
            SELECT cs.id, cs.customer_id, cs.blockchyp_token, cs.tier_id, cs.failed_charge_count,
                   mt.monthly_price, mt.name AS tier_name,
                   c.first_name, c.mobile, c.phone
            FROM customer_subscriptions cs
            JOIN membership_tiers mt ON mt.id = cs.tier_id
            JOIN customers c ON c.id = cs.customer_id
            WHERE cs.status = 'active'
              AND cs.blockchyp_token IS NOT NULL
              AND cs.current_period_end <= datetime('now')
              AND cs.cancel_at_period_end = 0
            LIMIT ?
          `).all(MEMBERSHIP_MAX_PER_RUN) as any[];
        } catch (err) {
          log.error('Membership: failed to load due subscriptions', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
          return;
        }

        for (const sub of dueSubscriptions) {
          // Per-iteration try/catch: one failure must not abort the remaining batch.
          try {
            const result = await chargeToken(
              tenantDb,
              sub.blockchyp_token,
              sub.monthly_price.toFixed(2),
              `${sub.tier_name} Membership Renewal`
            );
            const now = new Date().toISOString().replace('T', ' ').substring(0, 19);

            if (result.success) {
              const newEnd = new Date();
              newEnd.setMonth(newEnd.getMonth() + 1);
              const newEndStr = newEnd.toISOString().replace('T', ' ').substring(0, 19);

              tenantDb.prepare(`
                UPDATE customer_subscriptions SET current_period_start = ?, current_period_end = ?,
                last_charge_at = ?, last_charge_amount = ?, failed_charge_count = 0, updated_at = ?
                WHERE id = ?
              `).run(now, newEndStr, now, sub.monthly_price, now, sub.id);

              tenantDb.prepare(
                'INSERT INTO subscription_payments (subscription_id, amount, status, blockchyp_transaction_id) VALUES (?, ?, ?, ?)'
              ).run(sub.id, sub.monthly_price, 'success', result.transactionId || null);

              console.log(`[Membership${slug ? `:${slug}` : ''}] Renewed ${sub.first_name}'s ${sub.tier_name} membership`);
            } else {
              const fails = (sub.failed_charge_count || 0) + 1;
              tenantDb.prepare(`
                UPDATE customer_subscriptions SET failed_charge_count = ?, status = ?, updated_at = ?
                WHERE id = ?
              `).run(fails, fails >= 3 ? 'past_due' : 'active', now, sub.id);

              tenantDb.prepare(
                'INSERT INTO subscription_payments (subscription_id, amount, status, error_message) VALUES (?, ?, ?, ?)'
              ).run(sub.id, sub.monthly_price, 'failed', result.error || 'Payment declined');

              log.warn('Membership renewal declined', {
                tenantSlug: slug,
                subscriptionId: sub.id,
                customer: sub.first_name,
                tier: sub.tier_name,
                error: result.error,
              });
            }
          } catch (err) {
            log.error('Membership: renewal error for subscription', {
              tenantSlug: slug,
              subscriptionId: sub.id,
              error: err instanceof Error ? err.message : String(err),
            });
            // Continue with next subscription — do NOT rethrow.
          }
        }
      });
    } catch (err) {
      log.error('Membership: renewal cron outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 3600_000); // Every hour

  // Start GitHub update checker (checks hourly for new commits)
  // SEC-T13: Initial-check failures were previously swallowed with `.catch(() => {})`.
  // Replaced with logger.error so operators can tell when the updater is broken (network
  // outage, rate-limited, bad credentials) vs. simply "no new commits".
  import('./services/githubUpdater.js').then(({ startUpdateChecker, checkForUpdates: checkNow }) => {
    startUpdateChecker();
    checkNow().catch((err) => {
      log.error('GitHub updater: initial boot check failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    });
  }).catch((err) => {
    log.error('GitHub updater: failed to load module', {
      error: err instanceof Error ? err.message : String(err),
    });
  });

  // Broadcast management stats every 5 seconds for the Electron dashboard
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  import('./utils/requestCounter.js').then(({ getRequestsPerSecond, getRequestsPerMinute }) => {
    trackInterval(() => {
      const mem = process.memoryUsage();
      broadcast('management:stats', {
        uptime: process.uptime(),
        memory: {
          rss: Math.round(mem.rss / 1024 / 1024),
          heapUsed: Math.round(mem.heapUsed / 1024 / 1024),
          heapTotal: Math.round(mem.heapTotal / 1024 / 1024),
        },
        activeConnections: allClients.size,
        requestsPerSecond: getRequestsPerSecond(),
        requestsPerMinute: getRequestsPerMinute(),
      });
    }, 5000);
  });

  // SEC-M16: Track last-run dates for daily cron jobs to prevent double-fire / missed runs
  // SEC-BG2: Entries older than 30 days are pruned on every write so the map cannot grow
  // unbounded. Without this, renaming cron jobs or cycling tenant slugs leaves stale keys
  // forever — a slow memory leak that only shows up weeks into production.
  const CRON_LAST_RUN_PRUNE_DAYS = 30;
  const cronLastRun = new Map<string, string>(); // jobName → 'YYYY-MM-DD'
  function pruneCronLastRun(today: string): void {
    // Compute the cutoff date (YYYY-MM-DD format) CRON_LAST_RUN_PRUNE_DAYS before `today`.
    const cutoff = new Date(today + 'T00:00:00Z');
    cutoff.setUTCDate(cutoff.getUTCDate() - CRON_LAST_RUN_PRUNE_DAYS);
    const cutoffStr = cutoff.toISOString().slice(0, 10);
    for (const [key, dateStr] of cronLastRun) {
      if (dateStr < cutoffStr) cronLastRun.delete(key);
    }
  }
  function shouldRunDaily(jobName: string, tz: string): boolean {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: tz }); // YYYY-MM-DD
    if (cronLastRun.get(jobName) === today) return false;
    cronLastRun.set(jobName, today);
    pruneCronLastRun(today);
    return true;
  }

  // Periodic session cleanup (every hour) — iterates all tenant DBs in multi-tenant mode
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(() => {
    try {
      forEachDb((slug, tenantDb) => {
        try {
          const result = tenantDb.prepare("DELETE FROM sessions WHERE expires_at < datetime('now')").run();
          if (result.changes > 0) console.log(`[Cleanup${slug ? `:${slug}` : ''}] Removed ${result.changes} expired sessions`);
          // Clean up expired portal sessions and verification codes
          const portalResult = tenantDb.prepare("DELETE FROM portal_sessions WHERE expires_at < datetime('now')").run();
          if (portalResult.changes > 0) console.log(`[Cleanup${slug ? `:${slug}` : ''}] Removed ${portalResult.changes} expired portal sessions`);
          tenantDb.prepare("DELETE FROM portal_verification_codes WHERE expires_at < datetime('now') OR used = 1").run();
        } catch (err) {
          log.error('Session cleanup: tenant error', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.error('Session cleanup: failed to enumerate tenants', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000);

  // ENR-DB2: Data retention cleanup (daily at ~2 AM store timezone)
  // Removes old audit logs, read notifications, failed SMS messages, and stale portal codes.
  // SEC-AL5: Audit log retention now defaults to 2 years (AUDIT_LOG_RETENTION_DAYS env var).
  // The previous 90-day window was too aggressive for SOC2/HIPAA-style compliance regimes.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(() => {
    try {
      forEachDb((slug, tenantDb) => {
        const label = slug ? `:${slug}` : '';
        const tzRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get() as any;
        const tz = tzRow?.value || 'America/Denver';
        const localHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tz }));
        if (localHour !== 2 || !shouldRunDaily(`data-retention${label}`, tz)) return;

        try {
          // SEC-AL5: Audit logs older than AUDIT_LOG_RETENTION_DAYS (default 730 = 2 years).
          // SQLite `datetime('now', '-N days')` needs a literal, but we can safely interpolate
          // AUDIT_LOG_RETENTION_DAYS because it's parsed as an integer at startup.
          const retentionModifier = `-${AUDIT_LOG_RETENTION_DAYS} days`;
          const auditResult = tenantDb.prepare(
            "DELETE FROM audit_logs WHERE created_at < datetime('now', ?)"
          ).run(retentionModifier);
          if (auditResult.changes > 0) {
            console.log(`[DataRetention${label}] Purged ${auditResult.changes} audit logs (>${AUDIT_LOG_RETENTION_DAYS} days)`);
          }

          // Read notifications older than 30 days
          const notifResult = tenantDb.prepare(
            "DELETE FROM notifications WHERE is_read = 1 AND created_at < datetime('now', '-30 days')"
          ).run();
          if (notifResult.changes > 0) {
            console.log(`[DataRetention${label}] Purged ${notifResult.changes} read notifications (>30 days)`);
          }

          // Failed SMS messages older than 60 days (keep sent/delivered for records)
          const smsResult = tenantDb.prepare(
            "DELETE FROM sms_messages WHERE status = 'failed' AND created_at < datetime('now', '-60 days')"
          ).run();
          if (smsResult.changes > 0) {
            console.log(`[DataRetention${label}] Purged ${smsResult.changes} failed SMS messages (>60 days)`);
          }

          // Expired portal verification codes older than 7 days (already cleaned hourly, this is a safety net)
          tenantDb.prepare(
            "DELETE FROM portal_verification_codes WHERE created_at < datetime('now', '-7 days')"
          ).run();

          // SQLite optimization: reclaim space after bulk deletes
          // PRAGMA incremental_vacuum is safe for WAL mode and non-blocking
          try { tenantDb.pragma('incremental_vacuum(100)'); } catch {}
        } catch (err) {
          log.error('Data retention: tenant error', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.error('Data retention: failed to enumerate tenants', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Check every hour, run at 2 AM

  // Appointment reminder check (every 15 minutes) -- iterates all tenant DBs in multi-tenant mode
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const upcoming = tenantDb.prepare(`
          SELECT a.id, a.title, a.start_time, a.customer_id,
            c.first_name, c.mobile, c.phone
          FROM appointments a
          LEFT JOIN customers c ON c.id = a.customer_id
          WHERE a.reminder_sent = 0
            AND a.status = 'scheduled'
            AND a.start_time > datetime('now')
            AND a.start_time <= datetime('now', '+24 hours')
        `).all() as any[];

        if (upcoming.length === 0) return;
        // SEC-M15: Use tenant-aware SMS provider (reads provider config from tenant's store_config)
        const { sendSmsTenant } = await import('./services/smsProvider.js');
        const storeRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as any;
        const storeName = storeRow?.value || 'our shop';

        for (const appt of upcoming) {
          const phone = appt.mobile || appt.phone;
          if (!phone) continue;
          const body = `Hi ${appt.first_name || 'there'}, reminder: you have an appointment at ${storeName} — ${appt.title}. See you soon!`;
          try {
            await sendSmsTenant(tenantDb, slug, phone, body);
            tenantDb.prepare('UPDATE appointments SET reminder_sent = 1 WHERE id = ?').run(appt.id);
            console.log(`[Reminder${slug ? `:${slug}` : ''}] Sent to ${phone} for appointment ${appt.id}`);
          } catch (err) {
            // SEC-T13: surfaced instead of silently swallowed.
            log.error('Appointment reminder: SMS send failed', {
              tenantSlug: slug,
              appointmentId: appt.id,
              phone,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      });
    } catch (err) {
      log.error('Appointment reminder: cron outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 15 * 60 * 1000);

  // ENR-SMS1: Scheduled SMS cron (every 60 seconds) — send messages where send_at <= now
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const due = tenantDb.prepare(`
          SELECT * FROM sms_messages
          WHERE status = 'scheduled' AND send_at IS NOT NULL AND send_at <= datetime('now')
          ORDER BY send_at ASC LIMIT 10
        `).all() as any[];

        if (due.length === 0) return;
        // SEC-M15: Use tenant-aware SMS provider for scheduled messages
        const { sendSmsTenant } = await import('./services/smsProvider.js');

        for (const msg of due) {
          try {
            // Parse media if present
            let mediaItems: { url: string; contentType: string }[] | undefined;
            if (msg.media_urls) {
              const urls = JSON.parse(msg.media_urls);
              const types = msg.media_types ? JSON.parse(msg.media_types) : [];
              mediaItems = urls.map((url: string, i: number) => ({ url, contentType: types[i] || 'image/jpeg' }));
            }

            const result = await sendSmsTenant(tenantDb, slug, msg.to_number, msg.message, msg.from_number, mediaItems);
            if (result.success) {
              tenantDb.prepare(`
                UPDATE sms_messages SET status = 'sent', provider = ?, provider_message_id = ?, updated_at = datetime('now')
                WHERE id = ?
              `).run(result.providerName, result.providerId || null, msg.id);
            } else {
              tenantDb.prepare(`
                UPDATE sms_messages SET status = 'failed', provider = ?, error = ?, updated_at = datetime('now')
                WHERE id = ?
              `).run(result.providerName, result.error || 'Unknown error', msg.id);
            }
            console.log(`[ScheduledSMS${slug ? `:${slug}` : ''}] Sent scheduled message ${msg.id} to ${msg.to_number}: ${result.success ? 'OK' : 'FAILED'}`);
          } catch (err) {
            tenantDb.prepare(`UPDATE sms_messages SET status = 'failed', error = ?, updated_at = datetime('now') WHERE id = ?`)
              .run((err as Error).message, msg.id);
            log.error('Scheduled SMS: send failed', {
              tenantSlug: slug,
              messageId: msg.id,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      });
    } catch (err) {
      log.error('Scheduled SMS: cron outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 1000); // Every 60 seconds

  // Daily report email (check every hour, send at ~7 AM in store timezone) — iterates all tenant DBs in multi-tenant mode
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (_slug, tenantDb) => {
        // SW-D16: Use store_timezone for daily report scheduling
        const tzRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get() as any;
        const tz = tzRow?.value || 'America/Denver';
        const localHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tz }));
        // SEC-M16: Guard against double-fire — only run once per calendar day per tenant
        if (localHour !== 7 || !shouldRunDaily(`daily-report:${_slug || 'default'}`, tz)) return;

        // Tier: scheduled reports are a Pro feature.
        // In multi-tenant mode, look up the tenant's plan in master DB and skip free-plan tenants.
        // In single-tenant mode (_slug === null), run as before — scheduled reports work for self-hosted.
        if (config.multiTenant && _slug) {
          const masterDb = getMasterDb();
          if (!masterDb) return;
          const tenantRow = masterDb
            .prepare('SELECT plan, trial_ends_at FROM tenants WHERE slug = ?')
            .get(_slug) as { plan: string; trial_ends_at: string | null } | undefined;
          if (!tenantRow) return;
          const trialEnd = tenantRow.trial_ends_at ? new Date(tenantRow.trial_ends_at) : null;
          const trialActive = !!trialEnd && !Number.isNaN(trialEnd.getTime()) && trialEnd.getTime() > Date.now();
          const effectivePlan = trialActive ? 'pro' : (tenantRow.plan || 'free');
          if (effectivePlan !== 'pro') return;
        }

        await sendDailyReport(tenantDb);
      });
    } catch (err) {
      log.error('Daily report: cron failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000);

  // Daily supplier catalog sync — scrape into TEMPLATE first, then copy to tenants
  // SEC-TZ2: Previously hardcoded to America/Denver at 3 AM. In multi-tenant mode this
  // fired at 3 AM Denver for everyone — painful for European/Asian shops. Now:
  //   Phase 1 (template scrape): still uses a single "anchor" timezone (server default)
  //     since the scrape hits external supplier sites ONCE per day regardless of tenant.
  //     The anchor can be customized via SUPPLIER_SCRAPE_TIMEZONE env var.
  //   Phase 2 (per-tenant copy): runs when that tenant's OWN store_timezone hits 3 AM,
  //     guarded per-tenant via shouldRunDaily('catalog-copy:<slug>', tenantTz).
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  const CATALOG_SCRAPE_TZ = process.env.SUPPLIER_SCRAPE_TIMEZONE || 'America/Denver';
  trackInterval(async () => {
    try {
      // Phase 1: server-local scrape into template DB (runs once globally per day).
      const scrapeHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: CATALOG_SCRAPE_TZ }));
      if (scrapeHour === 3 && shouldRunDaily('catalog-sync-template', CATALOG_SCRAPE_TZ)) {
        try {
          const BetterSqlite3 = (await import('better-sqlite3')).default;
          const templateDb = new BetterSqlite3(config.templateDbPath);
          console.log('[CatalogSync] Phase 1: Scraping into template DB...');
          for (const source of ['mobilesentrix', 'phonelcdparts'] as const) {
            try {
              await scrapeCatalog(templateDb, source);
              console.log(`[CatalogSync] Template scraped: ${source}`);
            } catch (err: unknown) {
              log.warn('CatalogSync: template scrape failed', {
                source,
                error: err instanceof Error ? err.message : String(err),
              });
            }
          }
          templateDb.close();
        } catch (err) {
          log.error('CatalogSync: phase 1 outer failure', {
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }

      // Phase 2: Copy to each tenant at THEIR OWN 3 AM, guarded with a per-tenant key.
      // SEC-TZ2: Each tenant's store_timezone is honored, so a Berlin shop's sync runs at
      // Berlin 3 AM, not Denver 3 AM. Since trackInterval fires hourly, each tenant will
      // be evaluated 24 times/day and will only copy once its local hour hits 3.
      const { copyTemplateCatalogToTenant } = await import('./services/catalogSync.js');
      await forEachDbAsync(async (_slug, tenantDb) => {
        try {
          const tzRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get() as { value?: string } | undefined;
          const tenantTz = tzRow?.value || CATALOG_SCRAPE_TZ;
          const localHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tenantTz }));
          if (localHour !== 3) return;
          if (!shouldRunDaily(`catalog-copy:${_slug || 'default'}`, tenantTz)) return;

          const autoSync = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'catalog_auto_sync'").get() as any;
          if (autoSync?.value === '1') {
            const result = copyTemplateCatalogToTenant(tenantDb);
            if (result.copied > 0) {
              console.log(`[CatalogSync] Copied ${result.copied} items to tenant ${_slug || 'default'} (tz=${tenantTz})`);
            }
          }
        } catch (err) {
          log.error('CatalogSync: tenant copy failed', {
            tenantSlug: _slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.error('CatalogSync: daily sync outer failure', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Check every hour

  // ENR-A1: Stale ticket auto-SMS (every 15 minutes)
  // Sends a single follow-up SMS to the customer when a ticket has no activity for N days.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        // Check store_config for stall_followup_days (default: disabled / 0)
        const cfgRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'stall_followup_days'").get() as any;
        const stallDays = parseInt(cfgRow?.value || '0', 10);
        if (stallDays <= 0) return; // Feature disabled

        const { isAutoSmsAllowed } = await import('./services/notifications.js');

        // Find tickets with no recent activity:
        // - Not closed/completed
        // - No ticket_notes and no ticket_history entries in the last N days
        // - stall_followup_sent = 0 (not already sent)
        const staleTickets = tenantDb.prepare(`
          SELECT t.id, t.order_id, t.customer_id,
            c.first_name AS customer_name, c.mobile AS customer_phone, c.phone AS customer_phone2
          FROM tickets t
          LEFT JOIN customers c ON c.id = t.customer_id
          LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
          WHERE t.is_deleted = 0
            AND t.stall_followup_sent = 0
            AND ts.name NOT IN ('completed', 'closed', 'cancelled', 'delivered')
            AND t.updated_at < datetime('now', '-' || ? || ' days')
            AND NOT EXISTS (
              SELECT 1 FROM ticket_notes tn
              WHERE tn.ticket_id = t.id AND tn.created_at > datetime('now', '-' || ? || ' days')
            )
            AND NOT EXISTS (
              SELECT 1 FROM ticket_history th
              WHERE th.ticket_id = t.id AND th.created_at > datetime('now', '-' || ? || ' days')
            )
          LIMIT 20
        `).all(stallDays, stallDays, stallDays) as any[];

        if (staleTickets.length === 0) return;

        const { sendSmsTenant } = await import('./services/smsProvider.js');
        const storeRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as any;
        const storeName = storeRow?.value || 'our shop';
        const storePhoneRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_phone'").get() as any;
        const storePhone = storePhoneRow?.value || '';

        for (const ticket of staleTickets) {
          const phone = ticket.customer_phone || ticket.customer_phone2;
          if (!phone) continue;

          // ENR-A5: Rate limit check
          if (!isAutoSmsAllowed(tenantDb, phone)) {
            console.log(`[StaleTicket${slug ? `:${slug}` : ''}] Rate-limited: skipping ${phone} for ticket ${ticket.order_id}`);
            continue;
          }

          const body = `Hi ${ticket.customer_name || 'there'}, your repair (${ticket.order_id}) is still in progress at ${storeName}. We'll update you soon.`;
          try {
            await sendSmsTenant(tenantDb, slug, phone, body);
            // Record the SMS in sms_messages
            tenantDb.prepare(`
              INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
              VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto', 'ticket', ?, datetime('now'), datetime('now'))
            `).run(storePhone, phone, phone.replace(/\D/g, '').replace(/^1/, ''), body, ticket.id);
            // Mark as sent so we don't send again
            tenantDb.prepare('UPDATE tickets SET stall_followup_sent = 1 WHERE id = ?').run(ticket.id);
            console.log(`[StaleTicket${slug ? `:${slug}` : ''}] Sent follow-up to ${phone} for ticket ${ticket.order_id}`);
          } catch (err) {
            log.error('StaleTicket: SMS send failed', {
              tenantSlug: slug,
              ticketId: ticket.id,
              phone,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      });
    } catch (err) {
      log.error('StaleTicket: cron failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 15 * 60 * 1000); // Every 15 minutes

  // ENR-A2: Overdue invoice auto-reminders (every hour)
  // Sends SMS reminder for unpaid invoices older than N days, if the setting is enabled.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        // Check if feature is enabled
        const enabledRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'invoice_auto_reminder'").get() as any;
        if (enabledRow?.value !== '1') return; // Off by default

        const daysRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'invoice_reminder_days'").get() as any;
        const reminderDays = parseInt(daysRow?.value || '15', 10);
        if (reminderDays <= 0) return;

        const { isAutoSmsAllowed } = await import('./services/notifications.js');

        // Find unpaid invoices older than N days that haven't had a recent reminder
        const overdueInvoices = tenantDb.prepare(`
          SELECT i.id, i.order_id, i.amount_due, i.customer_id, i.created_at,
            c.first_name AS customer_name, c.mobile AS customer_phone, c.phone AS customer_phone2
          FROM invoices i
          LEFT JOIN customers c ON c.id = i.customer_id
          WHERE i.status IN ('sent', 'partial', 'overdue')
            AND i.amount_due > 0
            AND i.created_at < datetime('now', '-' || ? || ' days')
            AND (i.reminder_sent_at IS NULL OR i.reminder_sent_at < datetime('now', '-' || ? || ' days'))
          LIMIT 20
        `).all(reminderDays, reminderDays) as any[];

        if (overdueInvoices.length === 0) return;

        const { sendSmsTenant } = await import('./services/smsProvider.js');
        const storeRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as any;
        const storeName = storeRow?.value || 'our shop';
        const storePhoneRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_phone'").get() as any;
        const storePhone = storePhoneRow?.value || '';
        const templateRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'invoice_reminder_template'").get() as any;
        const customTemplate = templateRow?.value || '';

        for (const inv of overdueInvoices) {
          const phone = inv.customer_phone || inv.customer_phone2;
          if (!phone) continue;

          // ENR-A5: Rate limit check
          if (!isAutoSmsAllowed(tenantDb, phone)) {
            console.log(`[InvoiceReminder${slug ? `:${slug}` : ''}] Rate-limited: skipping ${phone} for invoice ${inv.order_id}`);
            continue;
          }

          const body = customTemplate
            ? customTemplate
                .replace(/\{name\}/g, inv.customer_name || 'there')
                .replace(/\{order_id\}/g, inv.order_id)
                .replace(/\{amount_due\}/g, Number(inv.amount_due).toFixed(2))
                .replace(/\{store_name\}/g, storeName)
            : `Hi ${inv.customer_name || 'there'}, this is a reminder from ${storeName} that invoice ${inv.order_id} has an outstanding balance of $${Number(inv.amount_due).toFixed(2)}. Please contact us if you have any questions.`;
          try {
            await sendSmsTenant(tenantDb, slug, phone, body);
            // Record the SMS
            tenantDb.prepare(`
              INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
              VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto', 'invoice', ?, datetime('now'), datetime('now'))
            `).run(storePhone, phone, phone.replace(/\D/g, '').replace(/^1/, ''), body, inv.id);
            // Update reminder timestamp
            tenantDb.prepare("UPDATE invoices SET reminder_sent_at = datetime('now') WHERE id = ?").run(inv.id);
            console.log(`[InvoiceReminder${slug ? `:${slug}` : ''}] Sent to ${phone} for invoice ${inv.order_id}`);
          } catch (err) {
            log.error('InvoiceReminder: SMS send failed', {
              tenantSlug: slug,
              invoiceId: inv.id,
              phone,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      });
    } catch (err) {
      log.error('InvoiceReminder: cron failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Every hour

  // ENR-LE8: Estimate auto-follow-up (every hour)
  // Sends SMS to customers with estimates in 'sent' status older than N days (default 3).
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const cfgRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'estimate_followup_days'").get() as any;
        const followupDays = parseInt(cfgRow?.value || '3', 10);
        if (followupDays <= 0) return;

        // Find estimates with status='sent' and sent_at older than N days, not yet followed up
        const estimates = tenantDb.prepare(`
          SELECT e.id, e.order_id, e.customer_id, e.sent_at, e.total,
            c.first_name AS customer_name, c.mobile AS customer_phone, c.phone AS customer_phone2
          FROM estimates e
          LEFT JOIN customers c ON c.id = e.customer_id
          WHERE e.status = 'sent'
            AND e.sent_at IS NOT NULL
            AND e.sent_at < datetime('now', '-' || ? || ' days')
            AND e.followup_sent_at IS NULL
          LIMIT 20
        `).all(followupDays) as any[];

        if (estimates.length === 0) return;

        const { sendSmsTenant } = await import('./services/smsProvider.js');
        const { isAutoSmsAllowed } = await import('./services/notifications.js');
        const storeRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as any;
        const storeName = storeRow?.value || 'our shop';
        const storePhoneRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_phone'").get() as any;
        const storePhone = storePhoneRow?.value || '';

        for (const est of estimates) {
          const phone = est.customer_phone || est.customer_phone2;
          if (!phone) continue;

          if (!isAutoSmsAllowed(tenantDb, phone)) {
            console.log(`[EstimateFollowup${slug ? `:${slug}` : ''}] Rate-limited: skipping ${phone} for estimate ${est.order_id}`);
            continue;
          }

          const body = `Hi ${est.customer_name || 'there'}, we sent you an estimate (${est.order_id}) from ${storeName}. Would you like to proceed? Reply or call us at ${storePhone}.`;
          try {
            await sendSmsTenant(tenantDb, slug, phone, body);
            tenantDb.prepare(`
              INSERT INTO sms_messages (from_number, to_number, conv_phone, message, status, direction, provider, entity_type, entity_id, created_at, updated_at)
              VALUES (?, ?, ?, ?, 'sent', 'outbound', 'auto', 'estimate', ?, datetime('now'), datetime('now'))
            `).run(storePhone, phone, phone.replace(/\D/g, '').replace(/^1/, ''), body, est.id);
            tenantDb.prepare("UPDATE estimates SET followup_sent_at = datetime('now') WHERE id = ?").run(est.id);
            console.log(`[EstimateFollowup${slug ? `:${slug}` : ''}] Sent to ${phone} for estimate ${est.order_id}`);
          } catch (err) {
            log.error('EstimateFollowup: SMS send failed', {
              tenantSlug: slug,
              estimateId: est.id,
              phone,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      });
    } catch (err) {
      log.error('EstimateFollowup: cron failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Every hour

  // ENR-A7: Persistent notification queue processor (every 60 seconds)
  // Processes pending items from the notification_queue table (migration 060).
  // Supports 'sms' and 'email' types. Failed items are retried up to max_retries.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const pending = tenantDb.prepare(`
          SELECT * FROM notification_queue
          WHERE status = 'pending'
            AND (scheduled_at IS NULL OR scheduled_at <= datetime('now'))
          ORDER BY created_at ASC
          LIMIT 10
        `).all() as any[];

        if (pending.length === 0) return;

        const label = slug ? `:${slug}` : '';

        for (const item of pending) {
          try {
            if (item.type === 'sms') {
              const { sendSmsTenant } = await import('./services/smsProvider.js');
              const result = await sendSmsTenant(tenantDb, slug, item.recipient, item.body);
              if (result.success) {
                tenantDb.prepare(
                  "UPDATE notification_queue SET status = 'sent', sent_at = datetime('now') WHERE id = ?"
                ).run(item.id);
                console.log(`[JobQueue${label}] SMS sent to ${item.recipient}`);
              } else {
                throw new Error(result.error || 'SMS send failed');
              }
            } else if (item.type === 'email') {
              const { sendEmail } = await import('./services/email.js');
              const sent = await sendEmail(tenantDb, {
                to: item.recipient,
                subject: item.subject || 'Notification',
                html: item.body,
              });
              if (sent) {
                tenantDb.prepare(
                  "UPDATE notification_queue SET status = 'sent', sent_at = datetime('now') WHERE id = ?"
                ).run(item.id);
                console.log(`[JobQueue${label}] Email sent to ${item.recipient}`);
              } else {
                throw new Error('Email send failed (SMTP not configured or send error)');
              }
            } else {
              // Unknown type — mark as failed permanently
              tenantDb.prepare(
                "UPDATE notification_queue SET status = 'failed', error = ? WHERE id = ?"
              ).run(`Unknown notification type: ${item.type}`, item.id);
              console.warn(`[JobQueue${label}] Unknown type '${item.type}' for queue item ${item.id}`);
            }
          } catch (err: unknown) {
            const errMsg = err instanceof Error ? err.message : 'Unknown error';
            const newRetryCount = (item.retry_count || 0) + 1;
            const maxRetries = item.max_retries || 3;
            const newStatus = newRetryCount >= maxRetries ? 'failed' : 'pending';
            // Exponential backoff: schedule next retry at 2^retryCount minutes from now
            const backoffMinutes = Math.pow(2, newRetryCount);
            tenantDb.prepare(`
              UPDATE notification_queue
              SET status = ?, error = ?, retry_count = ?,
                  scheduled_at = CASE WHEN ? = 'pending' THEN datetime('now', '+' || ? || ' minutes') ELSE scheduled_at END
              WHERE id = ?
            `).run(newStatus, errMsg, newRetryCount, newStatus, backoffMinutes, item.id);
            console.error(`[JobQueue${label}] Failed item ${item.id} (retry ${newRetryCount}/${maxRetries}): ${errMsg}`);
          }
        }
      });
    } catch (err) {
      console.error('[JobQueue] Cron failed:', err);
    }
  }, 60 * 1000); // Every 60 seconds

  // ENR-A4: Notification retry queue processor (every 5 minutes)
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const { processRetryQueue } = await import('./services/notifications.js');
        await processRetryQueue(tenantDb, slug);
      });
    } catch (err) {
      log.error('NotificationRetry: cron failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 5 * 60 * 1000); // Every 5 minutes

  // Daily storage recalculation (multi-tenant only) — corrects drift from incremental tracking
  // by walking each tenant's upload directory and writing the true byte total back to tenant_usage.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  if (config.multiTenant) {
    trackInterval(async () => {
      try {
        const { getMasterDb } = await import('./db/master-connection.js');
        const { calculateDirectorySize, setStorageBytes } = await import('./services/usageTracker.js');
        const masterDb = getMasterDb();
        if (!masterDb) return;
        const tenants = masterDb.prepare("SELECT id, slug FROM tenants WHERE status = 'active'").all() as Array<{ id: number; slug: string }>;
        for (const t of tenants) {
          const tenantUploadDir = path.join(config.uploadsPath, t.slug);
          const bytes = calculateDirectorySize(tenantUploadDir);
          setStorageBytes(t.id, bytes);
        }
        console.log(`[StorageRecalc] Refreshed storage usage for ${tenants.length} tenant(s)`);
      } catch (err) {
        log.error('StorageRecalc: daily refresh failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }, 24 * 60 * 60 * 1000); // 24 hours
  }

  // ─── Post-enrichment crons (weekly summary, dunning, health score) ──
  // All three are wired via trackInterval so shutdown() cancels them cleanly.
  // Each walks tenants serially via forEachDbAsync (NOT Promise.all) — we
  // don't want 100 parallel DB writers fighting over SQLite's single-writer
  // lock. One tenant's failure is caught per-iteration so it cannot kill
  // the batch.

  // ENR-REPORT: Weekly summary emailer (check every 5 minutes, fires once
  // per tenant per Monday 08:00-08:14 local). The reportEmailer service
  // enforces a 6-day idempotency window via a store_config sentinel so a
  // fast restart loop or overlapping ticks cannot duplicate inboxes.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      const { runReportEmailerTick } = await import('./services/reportEmailer.js');
      await runReportEmailerTick(async () => {
        const targets: Array<{
          db: any;
          adb: AsyncDb;
          recipients: string[];
          timezone: string;
          tenantSlug: string | null;
        }> = [];

        // Build per-tenant DeliveryTargets via the pool (SEC-BG6 — do NOT
        // open a new handle; the pool owns the lifetime).
        if (config.multiTenant) {
          const masterDb = getMasterDb();
          if (!masterDb) return [];
          const rows = masterDb.prepare(
            "SELECT slug, db_path FROM tenants WHERE status = 'active'",
          ).all() as Array<{ slug: string; db_path: string }>;

          for (const t of rows) {
            try {
              const tenantDb = getTenantDb(t.slug);
              const tzRow = tenantDb
                .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
                .get() as { value?: string } | undefined;
              const emailRow = tenantDb
                .prepare("SELECT value FROM store_config WHERE key = 'owner_email'")
                .get() as { value?: string } | undefined;
              const tenantDbPath = path.join(
                config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'),
                `${t.slug}.db`,
              );
              targets.push({
                db: tenantDb,
                adb: createAsyncDb(tenantDbPath),
                recipients: emailRow?.value ? [emailRow.value] : [],
                timezone: tzRow?.value || 'UTC',
                tenantSlug: t.slug,
              });
            } catch (err) {
              log.error('ReportEmailer: failed to build target for tenant', {
                tenantSlug: t.slug,
                error: err instanceof Error ? err.message : String(err),
              });
            }
          }
        } else {
          // Single-tenant: one target against the global db.
          try {
            const tzRow = db
              .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
              .get() as { value?: string } | undefined;
            const emailRow = db
              .prepare("SELECT value FROM store_config WHERE key = 'owner_email'")
              .get() as { value?: string } | undefined;
            targets.push({
              db,
              adb: createAsyncDb(config.dbPath),
              recipients: emailRow?.value ? [emailRow.value] : [],
              timezone: tzRow?.value || 'UTC',
              tenantSlug: null,
            });
          } catch (err) {
            log.error('ReportEmailer: failed to build single-tenant target', {
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }

        return targets;
      });
    } catch (err) {
      log.error('ReportEmailer: outer tick failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 5 * 60 * 1000); // Every 5 minutes

  // ENR-DUN: Dunning cron (hourly eval; per-tenant 24h guard via
  // shouldRunDaily + durable 20h rate-limit inside runDunningIfDue).
  // Each tenant runs serially so we never hammer SQLite with parallel
  // writers, and every tenant's failure is caught so one bad shop cannot
  // kill the batch.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      const { runDunningIfDue } = await import('./services/dunningScheduler.js');
      await forEachDbAsync(async (slug, tenantDb) => {
        try {
          // Per-tenant timezone gate: only run when their local hour hits ~3 AM.
          // The durable 20h guard inside runDunningIfDue() is defense-in-depth
          // for fast-restart scenarios where shouldRunDaily's in-memory map was lost.
          const tzRow = tenantDb
            .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
            .get() as { value?: string } | undefined;
          const tz = tzRow?.value || 'UTC';
          const localHour = Number.parseInt(
            new Date().toLocaleString('en-US', {
              hour: 'numeric',
              hour12: false,
              timeZone: tz,
            }),
            10,
          );
          if (localHour !== 3) return;
          if (!shouldRunDaily(`dunning:${slug || 'default'}`, tz)) return;

          const summary = runDunningIfDue(tenantDb);
          if (summary.rate_limited) {
            log.info('Dunning: rate-limited for tenant', {
              tenantSlug: slug,
              timezone: tz,
            });
          } else {
            log.info('Dunning: ran for tenant', {
              tenantSlug: slug,
              timezone: tz,
              sequences_evaluated: summary.sequences_evaluated,
              invoices_touched: summary.invoices_touched,
              steps_recorded_pending_dispatch: summary.steps_recorded_pending_dispatch,
              warnings: summary.warnings,
            });
          }
        } catch (err) {
          // Per-tenant try/catch: one tenant's failure cannot kill the rest.
          log.error('Dunning: per-tenant run failed', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.error('Dunning: cron outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Every hour

  // ENR-HEALTH: Customer health score recompute (hourly eval, per-tenant
  // 24h guard; batches of 200 so one big shop can't hog the worker pool).
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      const { recalculateAllCustomerHealth } = await import('./services/customerHealthScore.js');
      if (config.multiTenant) {
        const masterDb = getMasterDb();
        if (!masterDb) return;
        const rows = masterDb.prepare(
          "SELECT slug, db_path FROM tenants WHERE status = 'active'",
        ).all() as Array<{ slug: string; db_path: string }>;

        for (const t of rows) {
          // Serial — never parallel. SQLite single-writer + worker-pool budget
          // mean parallel fleets only create lock contention.
          try {
            const tenantDbHandle = getTenantDb(t.slug); // pool-owned, do not close
            const tzRow = tenantDbHandle
              .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
              .get() as { value?: string } | undefined;
            const tz = tzRow?.value || 'UTC';
            const localHour = Number.parseInt(
              new Date().toLocaleString('en-US', {
                hour: 'numeric',
                hour12: false,
                timeZone: tz,
              }),
              10,
            );
            if (localHour !== 4) continue;
            if (!shouldRunDaily(`health-score:${t.slug}`, tz)) continue;

            const tenantDbPath = path.join(
              config.tenantDataDir || path.join(path.dirname(config.dbPath), 'tenants'),
              `${t.slug}.db`,
            );
            const adb = createAsyncDb(tenantDbPath);
            const result = await recalculateAllCustomerHealth(adb);
            log.info('HealthScore: tenant recompute done', {
              tenantSlug: t.slug,
              total: result.total,
              updated: result.updated,
            });
          } catch (err) {
            log.error('HealthScore: per-tenant recompute failed', {
              tenantSlug: t.slug,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      } else {
        // Single-tenant path.
        try {
          const tzRow = db
            .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
            .get() as { value?: string } | undefined;
          const tz = tzRow?.value || 'UTC';
          const localHour = Number.parseInt(
            new Date().toLocaleString('en-US', {
              hour: 'numeric',
              hour12: false,
              timeZone: tz,
            }),
            10,
          );
          if (localHour !== 4) return;
          if (!shouldRunDaily('health-score:default', tz)) return;

          const adb = createAsyncDb(config.dbPath);
          const result = await recalculateAllCustomerHealth(adb);
          log.info('HealthScore: single-tenant recompute done', {
            total: result.total,
            updated: result.updated,
          });
        } catch (err) {
          log.error('HealthScore: single-tenant recompute failed', {
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
    } catch (err) {
      log.error('HealthScore: cron outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Every hour
});

// Graceful shutdown
// SEC-BG7: Previously closed HTTP + DB but did NOT cancel in-flight setInterval timers.
// A tick could still fire AFTER DB handles were closed, crashing the shutdown path with
// "database is closed" errors. Fix: clear every handle we registered via trackInterval()
// BEFORE we tear down the DB connections, then close server + DBs in the usual order.
let shuttingDown = false;
function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info(`Shutting down gracefully (${signal})`);

  // SEC-BG7: Cancel every tracked background interval. This covers membership renewal,
  // session cleanup, data retention, SMS dispatch, catalog sync, and all other timers.
  let cleared = 0;
  for (const handle of backgroundIntervals) {
    try { clearInterval(handle); cleared++; } catch { /* ignore */ }
  }
  backgroundIntervals.length = 0;
  log.info('Cleared background intervals', { count: cleared });

  // @audit-fixed: WebSocket heartbeat was previously a detached setInterval in
  // ws/server.ts that was never cancelled on shutdown. Cancel it now so the
  // timer cannot fire after sockets / DB handles are torn down.
  try { stopWebSocketHeartbeat(); log.info('WebSocket heartbeat stopped'); } catch (err) {
    log.error('Failed to stop WebSocket heartbeat', {
      error: err instanceof Error ? err.message : String(err),
    });
  }

  server.close(() => {
    log.info('HTTP server closed');
    // Close tenant pool connections first (multi-tenant)
    try { closeAllTenantDbs(); log.info('Tenant pool closed'); } catch (err) {
      log.error('Failed to close tenant pool', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
    // Close master DB (multi-tenant)
    try { closeMasterDb(); log.info('Master database closed'); } catch (err) {
      log.error('Failed to close master DB', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
    // Close single-tenant DB
    try { db.close(); log.info('Database closed'); } catch (err) {
      log.error('Failed to close primary DB', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
    // Shutdown worker pool
    // SEC-T13: worker-pool shutdown failures were silently swallowed. Log them so a truly
    // stuck pool doesn't hide behind `.catch(() => {})`.
    shutdownWorkerPool()
      .catch((err) => {
        log.error('Worker pool shutdown failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      })
      .finally(() => {
        log.info('Worker pool closed');
        process.exit(0);
      });
  });
  // Force exit after 10 seconds
  setTimeout(() => {
    log.error('Forced exit after shutdown timeout');
    process.exit(1);
  }, 10000);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// SEC-E6: Structured logging for crash diagnostics.
// Previously dumped full Error objects to stdout via `console.error`, which mixed untrusted
// user data (route paths, request bodies captured in stack traces) with server logs and made
// downstream log aggregators hard to parse. Now:
//   - `message` goes to the structured logger at `error` level.
//   - `stack` is sent as a separate field so log pipelines can route it to a secure sink.
//   - In production, the stack field is emitted only when LOG_INCLUDE_STACKS=true, so the
//     default behavior does NOT splatter full stack traces to stdout where ops dashboards
//     might capture sensitive data.
const INCLUDE_STACKS_IN_LOGS =
  config.nodeEnv !== 'production' || process.env.LOG_INCLUDE_STACKS === 'true';
function emitCrashLog(type: 'uncaughtException' | 'unhandledRejection', route: string, error: Error) {
  const meta: Record<string, unknown> = {
    type,
    route,
    errorName: error.name,
    errorMessage: error.message,
  };
  if (INCLUDE_STACKS_IN_LOGS && error.stack) {
    meta.stack = error.stack;
  }
  log.error('Process crash', meta);
}

// Crash resiliency: catch unhandled errors, log them, and let PM2 handle restarts
process.on('uncaughtException', (error) => {
  const route = currentRequestRoute || 'unknown';
  try {
    const entry = recordCrash(route, error, 'uncaughtException');
    emitCrashLog('uncaughtException', route, error);
    broadcast('management:crash', entry);
  } catch (trackingError) {
    log.error('Failed to track crash', {
      trackingError: trackingError instanceof Error ? trackingError.message : String(trackingError),
      originalError: error.message,
    });
  }
  // Do NOT exit — PM2 will restart if the process is truly unstable.
  // Many uncaught exceptions in Express apps are non-fatal (missed .catch(), bad property access).
  // The 3-consecutive-crash auto-disable handles truly broken routes.
});

process.on('unhandledRejection', (reason) => {
  const error = reason instanceof Error ? reason : new Error(String(reason));
  const route = currentRequestRoute || 'unknown';
  try {
    const entry = recordCrash(route, error, 'unhandledRejection');
    emitCrashLog('unhandledRejection', route, error);
    broadcast('management:crash', entry);
  } catch (trackingError) {
    log.error('Failed to track rejection', {
      trackingError: trackingError instanceof Error ? trackingError.message : String(trackingError),
      originalError: error.message,
    });
  }
});

export { app, server, wss };
