import express from 'express';
import cors from 'cors';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';
import { createServer } from 'http';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
import { WebSocketServer } from 'ws';
import { config } from './config.js';
import { db } from './db/connection.js';
import { runMigrations } from './db/migrate.js';
import { seedDatabase } from './db/seed.js';
import { errorHandler } from './middleware/errorHandler.js';
import { authMiddleware } from './middleware/auth.js';
import { setupWebSocket } from './ws/server.js';

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
import { smsInboundWebhookHandler } from './routes/sms.routes.js';
import { seedDeviceModels } from './db/device-models-seed-runner.js';
import { initSmsProvider } from './services/smsProvider.js';
import adminRoutes from './routes/admin.routes.js';
import { scheduleBackup } from './services/backup.js';
import { sendDailyReport } from './services/scheduledReports.js';

// Initialize database
runMigrations();
seedDatabase();
seedDeviceModels();

// Auto-sync inventory cost prices from supplier catalog
syncCostPricesFromCatalog();

// Initialize SMS provider
initSmsProvider(config.sms);

const app = express();
app.set('trust proxy', 1); // Trust first proxy (for rate limiting behind nginx/cloudflare)
const server = createServer(app);

// WebSocket
const wss = new WebSocketServer({ server });
setupWebSocket(wss);

// HTTPS redirect in production
if (config.nodeEnv === 'production') {
  app.use((req, res, next) => {
    if (req.headers['x-forwarded-proto'] !== 'https' && !req.secure) {
      return res.redirect(301, `https://${req.headers.host}${req.url}`);
    }
    next();
  });
}

// Middleware
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'"], // admin panel uses inline script
      styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
      imgSrc: ["'self'", 'data:', 'blob:'],
      connectSrc: ["'self'", 'ws:', 'wss:'],
      fontSrc: ["'self'", 'https://fonts.gstatic.com'],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"],
      baseUri: ["'self'"],
      formAction: ["'self'"],
    },
  },
  crossOriginEmbedderPolicy: false,
}));
const allowedOrigins = [
  'http://localhost:5173',
  'http://localhost:3020',
];
app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true); // allow non-browser requests (curl, Postman, etc.)
    if (allowedOrigins.includes(origin)) return callback(null, true);
    // Allow RFC1918 private IPs
    try {
      const url = new URL(origin);
      const ip = url.hostname;
      if (/^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(ip) || ip === 'localhost' || ip === '127.0.0.1') {
        return callback(null, true);
      }
    } catch {}
    callback(new Error('CORS not allowed'));
  },
  credentials: true,
}));
app.use(cookieParser());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Static files: serve uploaded files (restricted to uploadsPath, no traversal)
app.use('/uploads', (req, res, next) => {
  const decoded = decodeURIComponent(req.path);
  if (decoded.includes('..') || decoded.includes('\\')) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }
  // Resolve and verify the file is inside uploadsPath
  const resolved = path.resolve(config.uploadsPath, decoded.replace(/^\//, ''));
  if (!resolved.startsWith(path.resolve(config.uploadsPath))) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }
  next();
}, express.static(config.uploadsPath, {
  dotfiles: 'deny',
  index: false,
}));

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
  res.json({ success: true, data: { lan_ip: lanIp, port: config.port, server_url: `http://${lanIp}:${config.port}` } });
});

// API Routes (auth does NOT require middleware)
app.use('/api/v1/auth', authRoutes);

// SMS inbound webhook — public (no auth), providers POST here
app.post('/api/v1/sms/inbound-webhook', smsInboundWebhookHandler);

// Public ticket tracking (no auth)
app.use('/api/v1/track', trackingRoutes);

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

// TV display (no auth or simple token auth)
app.use('/api/v1/tv', tvRoutes);

// Admin panel (token-based auth handled in admin routes)
app.use('/api/v1/admin', adminRoutes);
app.get('/admin', (_req, res) => {
  res.sendFile(path.resolve(__dirname, 'admin/index.html'));
});

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
  console.log('  ║    Bizarre Electronics CRM Server        ║');
  console.log('  ╠══════════════════════════════════════════╣');
  console.log(`  ║  URL:  http://${config.host}:${config.port}            ║`);
  console.log(`  ║  Mode: ${config.nodeEnv.padEnd(33)}║`);
  console.log(`  ║  Admin: http://${config.host}:${config.port}/admin      ║`);
  console.log('  ╚══════════════════════════════════════════╝');
  console.log('');

  // Start backup scheduler
  scheduleBackup();

  // Periodic session cleanup (every hour)
  setInterval(() => {
    const result = db.prepare("DELETE FROM sessions WHERE expires_at < datetime('now')").run();
    if (result.changes > 0) console.log(`[Cleanup] Removed ${result.changes} expired sessions`);
  }, 60 * 60 * 1000);

  // Appointment reminder check (every 15 minutes)
  setInterval(async () => {
    try {
      const upcoming = db.prepare(`
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
      const { sendSms } = await import('./services/smsProvider.js');
      const storeRow = db.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as any;
      const storeName = storeRow?.value || 'our shop';

      for (const appt of upcoming) {
        const phone = appt.mobile || appt.phone;
        if (!phone) continue;
        const body = `Hi ${appt.first_name || 'there'}, reminder: you have an appointment at ${storeName} — ${appt.title}. See you soon!`;
        try {
          await sendSms(phone, body);
          db.prepare('UPDATE appointments SET reminder_sent = 1 WHERE id = ?').run(appt.id);
          console.log(`[Reminder] Sent to ${phone} for appointment ${appt.id}`);
        } catch {}
      }
    } catch {}
  }, 15 * 60 * 1000);

  // Daily report email (check every hour, send at ~7 AM)
  setInterval(async () => {
    const hour = new Date().getHours();
    if (hour === 7) {
      await sendDailyReport();
    }
  }, 60 * 60 * 1000);
});

// Health check endpoint
app.get('/health', (_req, res) => {
  try {
    db.prepare('SELECT 1').get();
    res.json({ status: 'ok', uptime: process.uptime() });
  } catch {
    res.status(503).json({ status: 'error', message: 'Database unavailable' });
  }
});

// Graceful shutdown
function shutdown(signal: string) {
  console.log(`\n[${signal}] Shutting down gracefully...`);
  server.close(() => {
    console.log('[Shutdown] HTTP server closed');
    try { db.close(); console.log('[Shutdown] Database closed'); } catch {}
    process.exit(0);
  });
  // Force exit after 10 seconds
  setTimeout(() => { console.error('[Shutdown] Forced exit after timeout'); process.exit(1); }, 10000);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

export { app, server, wss };
