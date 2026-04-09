process.title = 'BizarreCRM Server';

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
import { setupWebSocket, broadcast, allClients } from './ws/server.js';
import { crashGuardMiddleware, currentRequestRoute } from './middleware/crashResiliency.js';
import { recordCrash } from './services/crashTracker.js';

// Routes
import authRoutes from './routes/auth.routes.js';
import ticketRoutes from './routes/tickets.routes.js';
import customerRoutes from './routes/customers.routes.js';
import inventoryRoutes from './routes/inventory.routes.js';
import invoiceRoutes from './routes/invoices.routes.js';
import leadRoutes from './routes/leads.routes.js';
import estimateRoutes from './routes/estimates.routes.js';
import posRoutes from './routes/pos.routes.js';
import reportRoutes from './routes/reports.routes.js';
import smsRoutes from './routes/sms.routes.js';
import employeeRoutes from './routes/employees.routes.js';
import settingsRoutes from './routes/settings.routes.js';
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
import portalRoutes from './routes/portal.routes.js';
import voiceRoutes, { voiceStatusWebhookHandler, voiceRecordingWebhookHandler, voiceTranscriptionWebhookHandler, voiceInstructionsHandler, voiceInboundWebhookHandler } from './routes/voice.routes.js';
import { smsInboundWebhookHandler, smsStatusWebhookHandler } from './routes/sms.routes.js';
import { seedDeviceModels } from './db/device-models-seed-runner.js';
import { initSmsProvider } from './services/smsProvider.js';
import adminRoutes from './routes/admin.routes.js';
import { scheduleBackup } from './services/backup.js';
import { sendDailyReport } from './services/scheduledReports.js';
// Multi-tenant imports
import { initMasterDb, getMasterDb, closeMasterDb } from './db/master-connection.js';
import { buildTemplateDb } from './db/template.js';
import { getTenantDb, closeAllTenantDbs } from './db/tenant-pool.js';
import { tenantResolver } from './middleware/tenantResolver.js';
import signupRoutes from './routes/signup.routes.js';
// Legacy master-admin routes REMOVED — security risk (no 2FA, default password 'changeme123')
// Use /super-admin/api instead (has mandatory 2FA, proper validation, session management)
// import masterAdminRoutes from './routes/master-admin.routes.js';
import superAdminRoutes from './routes/super-admin.routes.js';
import { setMasterDb } from './utils/masterAudit.js';

/**
 * Helper: iterate all active tenant DBs (multi-tenant) or just the global db (single-tenant).
 * Uses temporary connections for background tasks to avoid thrashing the tenant pool.
 * The callback receives a DB connection that is closed after the callback returns.
 */
function forEachDb(callback: (slug: string | null, tenantDb: any) => void): void {
  if (!config.multiTenant) {
    callback(null, db);
    return;
  }
  const masterDb = getMasterDb();
  if (!masterDb) { callback(null, db); return; }
  const tenants = masterDb.prepare("SELECT slug, db_path FROM tenants WHERE status = 'active'").all() as { slug: string; db_path: string }[];
  for (const t of tenants) {
    let tempDb: any = null;
    try {
      const dbFilePath = path.join(config.tenantDataDir, t.db_path);
      tempDb = new Database(dbFilePath);
      tempDb.pragma('journal_mode = WAL');
      tempDb.pragma('busy_timeout = 5000');
      callback(t.slug, tempDb);
    } catch (err) {
      console.error(`[forEachDb] Error on ${t.slug}:`, err);
    } finally {
      try { tempDb?.close(); } catch {}
    }
  }
}

/**
 * Async variant: for background tasks that need await (e.g., sending SMS).
 * Each DB is opened, used, then closed before moving to the next tenant.
 */
async function forEachDbAsync(callback: (slug: string | null, tenantDb: any) => Promise<void>): Promise<void> {
  if (!config.multiTenant) {
    await callback(null, db);
    return;
  }
  const masterDb = getMasterDb();
  if (!masterDb) { await callback(null, db); return; }
  const tenants = masterDb.prepare("SELECT slug, db_path FROM tenants WHERE status = 'active'").all() as { slug: string; db_path: string }[];
  for (const t of tenants) {
    let tempDb: any = null;
    try {
      const dbFilePath = path.join(config.tenantDataDir, t.db_path);
      tempDb = new Database(dbFilePath);
      tempDb.pragma('journal_mode = WAL');
      tempDb.pragma('busy_timeout = 5000');
      await callback(t.slug, tempDb);
    } catch (err) {
      console.error(`[forEachDbAsync] Error on ${t.slug}:`, err);
    } finally {
      try { tempDb?.close(); } catch {}
    }
  }
}

// ─── Startup validation ──────────────────────────────────────────────
import { validateStartupEnvironment } from './utils/startupValidation.js';
validateStartupEnvironment();

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
  buildTemplateDb();
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

// Production safety check: refuse to start if admin user still has default password
if (config.nodeEnv === 'production') {
  try {
    const adminUser = db.prepare("SELECT password_hash FROM users WHERE username = 'admin'").get() as { password_hash: string } | undefined;
    if (adminUser) {
      const isDefault = bcrypt.compareSync('admin123', adminUser.password_hash);
      if (isDefault) {
        console.error('\n  FATAL: The default admin password (admin123) is still in use!');
        console.error('  Change the admin password before running in production.\n');
        process.exit(1);
      }
    }
  } catch (err) {
    console.warn('[Startup] Could not verify admin password:', (err as Error).message);
  }
}

// Auto-sync inventory cost prices from supplier catalog
syncCostPricesFromCatalog(db);

// Initialize SMS provider
initSmsProvider(db);

const app = express();
app.set('trust proxy', 1); // Trust first proxy (for rate limiting behind nginx/cloudflare)

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

// An HTTP server that only sends redirects (for plain HTTP hitting the same port)
const httpRedirectServer = createServer((req, res) => {
  const host = (req.headers.host || '').split(':')[0];
  const httpsHost = config.port === 443 ? host : `${host}:${config.port}`;
  res.writeHead(301, { Location: `https://${httpsHost}${req.url}` });
  res.end();
});

// TCP proxy: peek the first byte of each connection to detect TLS vs plain HTTP.
// TLS ClientHello starts with 0x16 — route to HTTPS. Anything else → HTTP redirect.
const server = net.createServer((socket) => {
  socket.once('data', (buf) => {
    // Put the data back so the target server can read it
    socket.pause();
    const target = buf[0] === 0x16 ? httpsServer : httpRedirectServer;
    target.emit('connection', socket);
    socket.unshift(buf);
    socket.resume();
  });
  socket.on('error', () => {}); // Suppress ECONNRESET from scanners/probes
});

// WebSocket (attaches to the HTTPS server, not the TCP proxy)
const wss = new WebSocketServer({ server: httpsServer, maxPayload: 65536 });
setupWebSocket(wss);

// Redirect middleware for requests arriving via reverse proxy (x-forwarded-proto)
app.use((req, res, next) => {
  if (req.headers['x-forwarded-proto'] === 'http') {
    return res.redirect(301, `https://${req.headers.host}${req.url}`);
  }
  next();
});

// Middleware
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      // MW3: 'unsafe-inline' is required because the admin panel (/admin/index.html) and
      // super-admin panel use inline scripts and onclick handlers. In production, these
      // should be replaced with nonce-based CSP (generate per-request nonce, inject into
      // script tags, and use 'nonce-<value>' directive instead of 'unsafe-inline').
      scriptSrc: ["'self'", "'unsafe-inline'"],
      scriptSrcAttr: ["'unsafe-inline'"],
      styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
      imgSrc: ["'self'", 'data:', 'blob:', 'https:'],
      connectSrc: ["'self'", 'ws:', 'wss:', 'https:'],
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
app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true); // allow non-browser requests (curl, Postman, etc.)
    if (allowedOrigins.includes(origin)) return callback(null, true);
    // Allow RFC1918 private IPs
    try {
      const url = new URL(origin);
      const ip = url.hostname;
      if (/^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(ip) || ip === 'localhost' || ip === '127.0.0.1' || ip.endsWith('.localhost')) {
        return callback(null, true);
      }
    } catch {}
    callback(new Error('CORS not allowed'));
  },
  credentials: true,
}));
app.use(cookieParser());
app.use(express.json({
  limit: '10mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; }, // Capture raw body for webhook signature verification
}));
app.use(express.urlencoded({ extended: true }));

// HTTP request logging (ENR-INFRA3) — logs method, path, status, response time
import { requestLogger } from './middleware/requestLogger.js';
app.use(requestLogger);

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

// Global API rate limiting: 300 requests per minute per IP for authenticated endpoints
// (Auth + webhook endpoints have their own stricter limits)
// SEC-H9: KNOWN LIMITATION — This in-memory rate limiter resets when the server restarts.
// An attacker could exploit restarts to bypass rate limits. A production deployment behind
// a reverse proxy should use Redis-backed rate limiting (e.g., rate-limiter-flexible with
// Redis store) or rely on an upstream WAF/CDN rate limiter (Cloudflare, nginx limit_req).
const apiRateMap = new Map<string, { count: number; resetAt: number }>();
const API_RATE_LIMIT = 300;
const API_RATE_WINDOW = 60_000; // 1 minute
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
  } else {
    apiRateMap.set(ip, { count: 1, resetAt: now + API_RATE_WINDOW });
  }
  next();
});
// Clean stale API rate limit entries every minute + enforce max size
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of apiRateMap) { if (now >= entry.resetAt) apiRateMap.delete(ip); }
  // Safety valve: if map grows too large, clear it entirely
  if (apiRateMap.size > 10_000) apiRateMap.clear();
}, 60_000);

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
app.get('/api/v1/info', authMiddleware, (_req, res) => {
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
app.get('/super-admin', (_req, res) => {
  if (!config.multiTenant) return res.status(404).send('Not available');
  res.sendFile(path.resolve(__dirname, 'admin/super-admin.html'));
});
app.get('/super-admin/*', (_req, res) => {
  if (!config.multiTenant) return res.status(404).send('Not available');
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
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of webhookRateMap) { if (now >= entry.resetAt) webhookRateMap.delete(ip); }
}, 5 * 60_000).unref();

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

// Protected API routes
app.use('/api/v1/tickets', authMiddleware, ticketRoutes);
app.use('/api/v1/customers', authMiddleware, customerRoutes);
app.use('/api/v1/inventory', authMiddleware, inventoryRoutes);
app.use('/api/v1/invoices', authMiddleware, invoiceRoutes);
app.use('/api/v1/leads', authMiddleware, leadRoutes);
app.use('/api/v1/estimates', authMiddleware, estimateRoutes);
app.use('/api/v1/pos', authMiddleware, posRoutes);
app.use('/api/v1/reports', authMiddleware, reportRoutes);
app.use('/api/v1/sms', authMiddleware, smsRoutes);
app.use('/api/v1/employees', authMiddleware, employeeRoutes);
app.use('/api/v1/settings', authMiddleware, settingsRoutes);
app.use('/api/v1/automations', authMiddleware, automationRoutes);
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
app.use('/api/v1/custom-fields', authMiddleware, customFieldRoutes);
app.use('/api/v1/refunds', authMiddleware, refundRoutes);
app.use('/api/v1/rma', authMiddleware, rmaRoutes);
app.use('/api/v1/gift-cards', authMiddleware, giftCardRoutes);
app.use('/api/v1/trade-ins', authMiddleware, tradeInRoutes);
app.use('/api/v1/blockchyp', authMiddleware, blockchypRoutes);
app.use('/api/v1/voice', authMiddleware, voiceRoutes);

// TV display (no auth or simple token auth)
app.use('/api/v1/tv', tvRoutes);

// Admin panel (token-based auth handled in admin routes)
// In multi-tenant mode, the per-tenant admin panel is disabled — use /master/api/ instead
app.use('/api/v1/admin', adminRoutes);

// Management dashboard API (localhost-only, token auth — for Electron dashboard)
import managementRoutes from './routes/management.routes.js';
app.use('/api/v1/management', managementRoutes);
app.get('/admin', (req, res) => {
  if (config.multiTenant && req.tenantSlug) {
    return res.status(403).send('Server administration is not available for tenant shops. Contact the platform administrator.');
  }
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));
});

// CSP override for portal widget mode (allow iframe embedding)
// AUD-M12: frame-ancestors * is intentional — the customer portal widget is designed to be
// embedded on any customer's website via iframe. Restricting to specific origins would break
// the widget for all customers. The widget endpoint serves only public repair-status data
// and requires a portal session token, so the risk is acceptable.
app.use('/customer-portal', (req, res, next) => {
  if (req.query.mode === 'widget') {
    res.setHeader('X-Frame-Options', 'ALLOWALL');
    res.setHeader('Content-Security-Policy', "frame-ancestors *");
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
app.get('/api/v1/health', (_req, res) => {
  let dbStatus = 'connected';
  try {
    db.prepare('SELECT 1').get();
  } catch {
    dbStatus = 'disconnected';
  }
  const payload = {
    status: dbStatus === 'connected' ? 'ok' : 'degraded',
    uptime: process.uptime(),
    version: '1.0.0',
    db: dbStatus,
    timestamp: new Date().toISOString(),
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
app.use(express.static(webDistPath));
app.get('*', (_req, res) => {
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

  // Start backup scheduler
  scheduleBackup(db);

  // Start GitHub update checker (checks hourly for new commits)
  import('./services/githubUpdater.js').then(({ startUpdateChecker, checkForUpdates: checkNow }) => {
    startUpdateChecker();
    checkNow().catch(() => {}); // Initial check on boot
  });

  // Broadcast management stats every 5 seconds for the Electron dashboard
  import('./utils/requestCounter.js').then(({ getRequestsPerSecond, getRequestsPerMinute }) => {
    setInterval(() => {
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
    }, 5000).unref();
  });

  // SEC-M16: Track last-run dates for daily cron jobs to prevent double-fire / missed runs
  const cronLastRun = new Map<string, string>(); // jobName → 'YYYY-MM-DD'
  function shouldRunDaily(jobName: string, tz: string): boolean {
    const today = new Date().toLocaleDateString('en-CA', { timeZone: tz }); // YYYY-MM-DD
    if (cronLastRun.get(jobName) === today) return false;
    cronLastRun.set(jobName, today);
    return true;
  }

  // Periodic session cleanup (every hour) — iterates all tenant DBs in multi-tenant mode
  setInterval(() => {
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
          console.error(`[Cleanup${slug ? `:${slug}` : ''}] Error:`, err);
        }
      });
    } catch (err) {
      console.error('[Cleanup] Failed to enumerate tenants:', err);
    }
  }, 60 * 60 * 1000);

  // Appointment reminder check (every 15 minutes) -- iterates all tenant DBs in multi-tenant mode
  setInterval(async () => {
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
          } catch {}
        }
      });
    } catch (err) {
      console.error('[Reminder] Failed:', err);
    }
  }, 15 * 60 * 1000);

  // ENR-SMS1: Scheduled SMS cron (every 60 seconds) — send messages where send_at <= now
  setInterval(async () => {
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
            console.error(`[ScheduledSMS${slug ? `:${slug}` : ''}] Error sending ${msg.id}:`, (err as Error).message);
          }
        }
      });
    } catch (err) {
      console.error('[ScheduledSMS] Failed:', err);
    }
  }, 60 * 1000); // Every 60 seconds

  // Daily report email (check every hour, send at ~7 AM in store timezone) — iterates all tenant DBs in multi-tenant mode
  setInterval(async () => {
    try {
      await forEachDbAsync(async (_slug, tenantDb) => {
        // SW-D16: Use store_timezone for daily report scheduling
        const tzRow = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get() as any;
        const tz = tzRow?.value || 'America/Denver';
        const localHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tz }));
        // SEC-M16: Guard against double-fire — only run once per calendar day per tenant
        if (localHour === 7 && shouldRunDaily(`daily-report:${_slug || 'default'}`, tz)) {
          await sendDailyReport(tenantDb);
        }
      });
    } catch (err) {
      console.error('[DailyReport] Failed:', err);
    }
  }, 60 * 60 * 1000);

  // Daily supplier catalog sync (~3 AM) — scrape into TEMPLATE first, then copy to tenants
  setInterval(async () => {
    try {
      // Check timezone — use a default for template scraping
      const tz = 'America/Denver';
      const localHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tz }));
      // SEC-M16: Guard against double-fire
      if (localHour !== 3 || !shouldRunDaily('catalog-sync', tz)) return;

      // Phase 1: Scrape into template DB (central, once)
      const BetterSqlite3 = (await import('better-sqlite3')).default;
      const templateDb = new BetterSqlite3(config.templateDbPath);
      console.log('[CatalogSync] Phase 1: Scraping into template DB...');
      for (const source of ['mobilesentrix', 'phonelcdparts'] as const) {
        try {
          await scrapeCatalog(templateDb, source);
          console.log(`[CatalogSync] Template scraped: ${source}`);
        } catch (err: any) {
          console.warn(`[CatalogSync] Template scrape ${source} failed:`, err.message);
        }
      }
      templateDb.close();

      // Phase 2: Copy to tenants with auto-sync enabled
      const { copyTemplateCatalogToTenant } = await import('./services/catalogSync.js');
      await forEachDbAsync(async (_slug, tenantDb) => {
        const autoSync = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'catalog_auto_sync'").get() as any;
        if (autoSync?.value === '1') {
          const result = copyTemplateCatalogToTenant(tenantDb);
          if (result.copied > 0) console.log(`[CatalogSync] Copied ${result.copied} items to tenant ${_slug}`);
        }
      });
      console.log('[CatalogSync] Daily sync complete');
    } catch (err) {
      console.error('[CatalogSync] Daily sync failed:', err);
    }
  }, 60 * 60 * 1000); // Check every hour, run at 3 AM

  // ENR-A1: Stale ticket auto-SMS (every 15 minutes)
  // Sends a single follow-up SMS to the customer when a ticket has no activity for N days.
  setInterval(async () => {
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
            console.error(`[StaleTicket${slug ? `:${slug}` : ''}] Failed to send to ${phone}:`, err);
          }
        }
      });
    } catch (err) {
      console.error('[StaleTicket] Failed:', err);
    }
  }, 15 * 60 * 1000); // Every 15 minutes

  // ENR-A2: Overdue invoice auto-reminders (every hour)
  // Sends SMS reminder for unpaid invoices older than N days, if the setting is enabled.
  setInterval(async () => {
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

        for (const inv of overdueInvoices) {
          const phone = inv.customer_phone || inv.customer_phone2;
          if (!phone) continue;

          // ENR-A5: Rate limit check
          if (!isAutoSmsAllowed(tenantDb, phone)) {
            console.log(`[InvoiceReminder${slug ? `:${slug}` : ''}] Rate-limited: skipping ${phone} for invoice ${inv.order_id}`);
            continue;
          }

          const body = `Hi ${inv.customer_name || 'there'}, this is a reminder from ${storeName} that invoice ${inv.order_id} has an outstanding balance of $${Number(inv.amount_due).toFixed(2)}. Please contact us if you have any questions.`;
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
            console.error(`[InvoiceReminder${slug ? `:${slug}` : ''}] Failed to send to ${phone}:`, err);
          }
        }
      });
    } catch (err) {
      console.error('[InvoiceReminder] Failed:', err);
    }
  }, 60 * 60 * 1000); // Every hour

  // ENR-LE8: Estimate auto-follow-up (every hour)
  // Sends SMS to customers with estimates in 'sent' status older than N days (default 3).
  setInterval(async () => {
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
            console.error(`[EstimateFollowup${slug ? `:${slug}` : ''}] Failed for ${phone}:`, err);
          }
        }
      });
    } catch (err) {
      console.error('[EstimateFollowup] Failed:', err);
    }
  }, 60 * 60 * 1000); // Every hour

  // ENR-A4: Notification retry queue processor (every 5 minutes)
  setInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const { processRetryQueue } = await import('./services/notifications.js');
        await processRetryQueue(tenantDb, slug);
      });
    } catch (err) {
      console.error('[NotificationRetry] Cron failed:', err);
    }
  }, 5 * 60 * 1000); // Every 5 minutes
});

// Graceful shutdown
function shutdown(signal: string) {
  console.log(`\n[${signal}] Shutting down gracefully...`);
  server.close(() => {
    console.log('[Shutdown] HTTP server closed');
    // Close tenant pool connections first (multi-tenant)
    try { closeAllTenantDbs(); console.log('[Shutdown] Tenant pool closed'); } catch {}
    // Close master DB (multi-tenant)
    try { closeMasterDb(); console.log('[Shutdown] Master database closed'); } catch {}
    // Close single-tenant DB
    try { db.close(); console.log('[Shutdown] Database closed'); } catch {}
    // Shutdown worker pool
    shutdownWorkerPool().catch(() => {}).finally(() => {
      console.log('[Shutdown] Worker pool closed');
      process.exit(0);
    });
  });
  // Force exit after 10 seconds
  setTimeout(() => { console.error('[Shutdown] Forced exit after timeout'); process.exit(1); }, 10000);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Crash resiliency: catch unhandled errors, log them, and let PM2 handle restarts
process.on('uncaughtException', (error) => {
  const route = currentRequestRoute || 'unknown';
  try {
    const entry = recordCrash(route, error, 'uncaughtException');
    console.error(`[CRASH] uncaughtException on route ${route}:`, error);
    broadcast('management:crash', entry);
  } catch (trackingError) {
    console.error('[CRASH] Failed to track crash:', trackingError);
    console.error('[CRASH] Original error:', error);
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
    console.error(`[CRASH] unhandledRejection on route ${route}:`, error);
    broadcast('management:crash', entry);
  } catch (trackingError) {
    console.error('[CRASH] Failed to track rejection:', trackingError);
    console.error('[CRASH] Original reason:', reason);
  }
});

export { app, server, wss };
// Update test - 2026-04-09_13:23
// update test 13:28:54
// update test v3 13:33:31
// v4 13:36:08
// v5 13:52:11
// v6 14:05:33
// v7 14:18:40
// v8 14:20:56
