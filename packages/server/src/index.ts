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
import jwt from 'jsonwebtoken';
import Database from 'better-sqlite3';
import express, { type Request, type Response, type NextFunction } from 'express';
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

// TPH7: enable Node's native crash report for libuv/V8/native-module aborts.
// Pure-JS `uncaughtException` handlers never fire for these (exit code
// 3221226505 / SIGABRT equivalents). `process.report` writes a diagnostic
// JSON post-mortem so the next provisioning crash leaves forensic evidence
// on disk. Directory is gitignored.
try {
  const crashReportDir = path.resolve(__dirname, '../data/crash-reports');
  if (!fs.existsSync(crashReportDir)) fs.mkdirSync(crashReportDir, { recursive: true });
  process.report.reportOnFatalError = true;
  process.report.directory = crashReportDir;
} catch {}
import { WebSocketServer } from 'ws';
import { config } from './config.js';
import { db } from './db/connection.js';
import { initWorkerPool, shutdownWorkerPool, getPoolStats } from './db/worker-pool.js';
import { createAsyncDb, type AsyncDb } from './db/async-db.js';
import { runMigrations } from './db/migrate.js';
import { seedDatabase } from './db/seed.js';
import { backfillGiftCardCodeHashes } from './services/giftCardCodeHashBackfill.js';
import { backfillEstimateApprovalTokenHashes } from './services/estimateApprovalTokenHashBackfill.js';
import { errorHandler } from './middleware/errorHandler.js';
import { authMiddleware } from './middleware/auth.js';
import { setupWebSocket, broadcast, allClients, stopWebSocketHeartbeat } from './ws/server.js';
import { crashGuardMiddleware, currentRequestRoute } from './middleware/crashResiliency.js';
import { recordCrash, resetDisabledRoutesOnStartup } from './services/crashTracker.js';
import { createLogger } from './utils/logger.js';
import { consumeWindowRate } from './utils/rateLimiter.js';

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
// PROD58: Per-tenant "download all my data" capability (GDPR/CCPA basics).
// Separate file so the admin-panel routes in admin.routes.ts (which are
// disabled in multi-tenant mode) stay untouched — this endpoint must work
// PER TENANT after tenantResolver + authMiddleware resolve the shop DB.
import dataExportRoutes from './routes/dataExport.routes.js';
// SEC-H59 / P3-PII-16: Full tenant export (encrypted zip, signed download token).
import tenantExportRoutes, { downloadRouter as tenantExportDownloadRouter } from './routes/tenantExport.routes.js';
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
// Web-parity backend (2026-04-23) — mobile apps already consume these or will.
// Each route file handles its own role/permission gates + rate limits internally.
import shiftsScheduleRoutes from './routes/shiftsSchedule.routes.js';
import timeOffRoutes from './routes/timeOff.routes.js';
import timesheetRoutes from './routes/timesheet.routes.js';
import { variantsRouter as inventoryVariantsRoutes, bundlesRouter as inventoryBundlesRoutes } from './routes/inventoryVariants.routes.js';
import recurringInvoicesRoutes from './routes/recurringInvoices.routes.js';
import creditNotesRoutes from './routes/creditNotes.routes.js';
import activityRoutes from './routes/activity.routes.js';
import notificationPrefsRoutes from './routes/notificationPrefs.routes.js';
import heldCartsRoutes from './routes/heldCarts.routes.js';
import { startRecurringInvoicesCron } from './services/recurringInvoicesCron.js';
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
import superAdminRoutes from './routes/super-admin.routes.js';
import { localhostOnly } from './middleware/localhostOnly.js';
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
// SEC-M31: per-tenant callback timeout. A hung tenant callback (stuck
// query, blocked file handle, locked WAL) would otherwise stall the
// whole sweep for every other tenant behind it. 30s is generous enough
// for any legitimate cron work (retention sweeps, reminder checks,
// notifications) and short enough that a bad tenant doesn't hold up the
// fleet. Timeout exits the callback for THAT tenant only — iteration
// continues to the next.
const PER_TENANT_CRON_TIMEOUT_MS = 30_000;

function withTimeout<T>(promise: Promise<T>, ms: number, slug: string | null): Promise<T | 'timeout'> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve('timeout'), ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}

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
      // SEC-M31: race the callback against a timeout so one hung tenant
      // can't stall the whole iteration.
      const outcome = await withTimeout(callback(t.slug, pooled), PER_TENANT_CRON_TIMEOUT_MS, t.slug);
      if (outcome === 'timeout') {
        // eslint-disable-next-line @typescript-eslint/no-use-before-define
        log.error('forEachDbAsync: tenant callback timed out', {
          tenantSlug: t.slug,
          timeoutMs: PER_TENANT_CRON_TIMEOUT_MS,
        });
      }
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

// SEC-H38: populate gift_cards.code_hash for any rows that predate
// migration 104. Idempotent — only updates rows where code_hash IS NULL.
try {
  backfillGiftCardCodeHashes(db);
} catch (err) {
  log.warn('gift card code hash backfill failed', {
    error: err instanceof Error ? err.message : String(err),
  });
}

// SEC-H52: populate estimates.approval_token_hash for any rows that predate
// migration 107. Idempotent — only updates rows where approval_token_hash
// IS NULL AND approval_token IS NOT NULL.
try {
  backfillEstimateApprovalTokenHashes(db);
} catch (err) {
  log.warn('estimate approval token hash backfill failed', {
    error: err instanceof Error ? err.message : String(err),
  });
}

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

// Initialize multi-tenant master DB before creating the readiness promise. The
// readiness promise runs migrateAllTenants(), which needs getMasterDb() to be
// available immediately.
if (config.multiTenant) {
  initMasterDb();
  setMasterDb(getMasterDb());
}

// @audit-fixed: #7 (boot race) — in single-tenant mode runMigrations(db) above already
// blocks. In multi-tenant mode, migrateAllTenants() used to be fire-and-forget, meaning
// server.listen() could accept requests before any tenant finished migrating, exposing
// partially-applied schemas. We now build a `readyPromise` that the HTTP listen callback
// awaits, and expose a `/api/v1/health/ready` probe that returns 503 until the promise
// resolves. Per-tenant migration failures are still non-fatal (they get flagged on the
// admin dashboard via the existing failed_tenants mechanism) so one bad tenant cannot
// block the fleet from starting.
let isReady = false;
let readyError: Error | null = null;
const readyPromise: Promise<void> = (async () => {
  if (!config.multiTenant) {
    // Single-tenant: runMigrations(db) already ran synchronously above. Mark ready.
    return;
  }
  try {
    // migrateAllTenants() refreshes the template DB first AND walks every active
    // tenant to apply any new migrations. Errors are logged loudly but do not block
    // boot — the admin dashboard surfaces per-tenant failures via failed_tenants.
    await migrateAllTenants();
    // TPH2: post-migration sweep — detect (not delete) stuck provisioning rows.
    try {
      const { detectStaleProvisioningRecords } = await import('./services/tenant-provisioning.js');
      detectStaleProvisioningRecords();
    } catch (err) {
      log.warn('Stale-provisioning detection sweep failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // SEC-L35: zombie SMS recovery. Any row stuck in `status='sending'`
    // older than 10 minutes was almost certainly stranded by a server
    // crash between the INSERT and the provider dispatch. Mark them
    // failed with an explanatory error so operators can retry via the
    // UI rather than leaving customer-visible "still sending…" chips
    // hanging forever. Runs once at boot, per tenant.
    try {
      forEachDb((_slug, tenantDb) => {
        try {
          const result = tenantDb.prepare(
            "UPDATE sms_messages SET status = 'failed', error = 'zombie-recovery: stuck in sending > 10m after server restart', updated_at = datetime('now') WHERE status = 'sending' AND created_at < datetime('now', '-10 minutes')"
          ).run();
          if (result.changes > 0) {
            log.warn('zombie sms recovery: marked stuck-in-sending rows as failed', {
              tenantSlug: _slug ?? null,
              count: result.changes,
            });
          }
        } catch (err) {
          // Schema may be pre-migration on a brand-new tenant; don't crash boot.
          log.warn('zombie sms recovery: per-tenant sweep failed', {
            tenantSlug: _slug ?? null,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.warn('zombie sms recovery: iteration failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // SEC-H38: per-tenant backfill of gift_cards.code_hash. Companion to
    // migration 104 which adds the column but can't populate it in pure
    // SQL (SQLite has no sha256). Idempotent — each tenant sweep only
    // touches rows where code_hash IS NULL.
    try {
      forEachDb((_slug, tenantDb) => {
        try {
          backfillGiftCardCodeHashes(tenantDb);
        } catch (err) {
          log.warn('gift card code hash backfill: per-tenant sweep failed', {
            tenantSlug: _slug ?? null,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.warn('gift card code hash backfill: iteration failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // SEC-H52: per-tenant backfill of estimates.approval_token_hash. Companion
    // to migration 107 which adds the column but can't populate it in pure
    // SQL (SQLite has no sha256). Idempotent — each tenant sweep only
    // touches rows where approval_token_hash IS NULL AND approval_token IS NOT NULL.
    try {
      forEachDb((_slug, tenantDb) => {
        try {
          backfillEstimateApprovalTokenHashes(tenantDb);
        } catch (err) {
          log.warn('estimate approval token hash backfill: per-tenant sweep failed', {
            tenantSlug: _slug ?? null,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.warn('estimate approval token hash backfill: iteration failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // SEC-L38: zombie import_runs recovery. Anything still in
    // status='running' or 'pending' at boot must be from a process
    // crashed mid-import — the background worker is gone and the row
    // will never complete on its own. Mark them failed with a tag so
    // the UI surfaces a retry affordance and operators can distinguish
    // crash-stranded runs from real data failures. Also releases any
    // import lock rows that keyed off the seed so new runs can start.
    try {
      forEachDb((_slug, tenantDb) => {
        try {
          const result = tenantDb.prepare(
            "UPDATE import_runs SET status = 'failed', completed_at = datetime('now'), error_log = json_array(json_object('record_id', 'zombie', 'message', 'zombie-recovery: import crashed / server restarted before completion', 'timestamp', datetime('now'))) WHERE status IN ('running', 'pending')"
          ).run();
          if (result.changes > 0) {
            log.warn('zombie import recovery: marked stuck import_runs as failed', {
              tenantSlug: _slug ?? null,
              count: result.changes,
            });
          }
          // Best-effort lock release — table may not exist on a brand-new tenant.
          try {
            tenantDb.prepare('DELETE FROM import_locks').run();
          } catch {
            // no-op — schema may be pre-migration, no import_locks yet.
          }
        } catch (err) {
          // import_runs table may not exist on a brand-new tenant; don't crash boot.
          log.warn('zombie import recovery: per-tenant sweep failed', {
            tenantSlug: _slug ?? null,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.warn('zombie import recovery: iteration failed', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  } catch (err) {
    const wrapped = err instanceof Error ? err : new Error(String(err));
    log.error('Tenant migrations failed during boot (continuing anyway)', {
      error: wrapped.message,
      stack: wrapped.stack,
    });
    readyError = wrapped;
    // Do NOT rethrow — we want the server to come up so operators can triage.
  }
})();

// Initialize multi-tenant infrastructure (no-op if MULTI_TENANT != true)
if (config.multiTenant) {
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
// SEC-H84: trust proxy = explicit IPs from config.trustedProxyIps (TRUSTED_PROXY_IPS env),
// falling back to loopback only. Previously `1` which trusted the first hop unconditionally —
// an attacker able to reach the socket directly (rogue egress from a co-located service,
// misconfigured firewall) could spoof X-Forwarded-For and defeat IP-based rate limits + audit
// trails. Explicit allowlist ensures only the known reverse-proxy(es) are honored.
const TRUST_PROXY_ALLOWLIST = config.trustedProxyIps.length
  ? [...config.trustedProxyIps, '127.0.0.1', '::1']
  : ['loopback'];
app.set('trust proxy', TRUST_PROXY_ALLOWLIST);
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

// SEC-L33: pin the TLS cipher list and enforce server-preferred ordering.
// Without `ciphers` + `honorCipherOrder`, Node falls back to its defaults
// which on older runtimes still include CBC-mode AES and some TLSv1.2
// combinations that are acceptable but not preferred. Whitelisting the
// modern AEAD suites (ECDHE + AES-GCM / ChaCha20-Poly1305) and telling
// the TLS stack to honour the server's ordering means a downgrade-happy
// client can't coax us into a weaker cipher than we'd pick ourselves.
// Order roughly matches the Mozilla "intermediate" guidance — strong
// ECDHE-ECDSA first (if the cert carries one), then ECDHE-RSA.
const TLS_CIPHERS = [
  'TLS_AES_256_GCM_SHA384',
  'TLS_CHACHA20_POLY1305_SHA256',
  'TLS_AES_128_GCM_SHA256',
  'ECDHE-ECDSA-AES256-GCM-SHA384',
  'ECDHE-RSA-AES256-GCM-SHA384',
  'ECDHE-ECDSA-CHACHA20-POLY1305',
  'ECDHE-RSA-CHACHA20-POLY1305',
  'ECDHE-ECDSA-AES128-GCM-SHA256',
  'ECDHE-RSA-AES128-GCM-SHA256',
].join(':');

const tlsOptions = {
  key: fs.readFileSync(path.join(certsDir, 'server.key')),
  cert: fs.readFileSync(path.join(certsDir, 'server.cert')),
  minVersion: 'TLSv1.2' as const,
  ciphers: TLS_CIPHERS,
  honorCipherOrder: true,
};

// The HTTPS server handles Express + WebSocket
const httpsServer = createHttpsServer(tlsOptions, app);
httpsServer.requestTimeout = 40_000;
httpsServer.headersTimeout = 45_000;
httpsServer.keepAliveTimeout = 65_000;
const protocol = 'https';

// SEC-H5 / SEC-H90: Sanitize host and URL before placing them in a Location header.
// - Strip CR/LF/NULL to block response-splitting.
// - Restrict host to legal hostname characters (letters, digits, dot, hyphen, colon for port).
// - SEC-H90: reject hosts not matching `config.baseDomain` OR a subdomain of it; fall back
//   to the configured baseDomain on mismatch. Prevents an attacker-supplied `Host:` header
//   (`Host: evil.com`) from steering the HTTPS redirect at a phishing origin.
// - `encodeURI` the path portion so any stray bytes get percent-encoded rather than injected raw.
function sanitizeRedirectHost(rawHost: string): string {
  const noCrlf = rawHost.replace(/[\r\n\0]/g, '').split(':')[0].toLowerCase();
  // Allow only hostname-safe chars; fall back to baseDomain on anything weird.
  if (!/^[a-zA-Z0-9.-]+$/.test(noCrlf) || noCrlf.length > 253) return config.baseDomain;
  // SEC-H90: validate against baseDomain. Single-tenant / localhost deployments allow
  // bare 'localhost' + '127.0.0.1'. Multi-tenant allows baseDomain AND *.baseDomain
  // (subdomains are the per-tenant URLs). Anything else → rewrite to baseDomain.
  if (noCrlf === 'localhost' || noCrlf === '127.0.0.1') return noCrlf;
  if (noCrlf === config.baseDomain) return noCrlf;
  if (noCrlf.endsWith('.' + config.baseDomain)) return noCrlf;
  return config.baseDomain;
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
  // Exact allowlist (defined below in `allowedOrigins`). Normalize both
  // sides so protocol-default ports (https=443, http=80) don't defeat
  // the equality check when a browser omits the port from Origin.
  try {
    const envList = (process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean)) || [];
    const localExact = [
      `https://localhost:${config.port}`,
      `http://localhost:${config.port}`,
    ];
    const normalizedOrigin = (() => {
      try {
        const u = new URL(origin);
        const isDefault =
          (u.protocol === 'https:' && (u.port === '' || u.port === '443')) ||
          (u.protocol === 'http:' && (u.port === '' || u.port === '80'));
        return isDefault
          ? `${u.protocol}//${u.hostname}`
          : `${u.protocol}//${u.hostname}:${u.port}`;
      } catch {
        return origin;
      }
    })();
    const normalizedAllow = [...envList, ...localExact].map(raw => {
      try {
        const u = new URL(raw);
        const isDefault =
          (u.protocol === 'https:' && (u.port === '' || u.port === '443')) ||
          (u.protocol === 'http:' && (u.port === '' || u.port === '80'));
        return isDefault
          ? `${u.protocol}//${u.hostname}`
          : `${u.protocol}//${u.hostname}:${u.port}`;
      } catch {
        return raw;
      }
    });
    if (normalizedAllow.includes(normalizedOrigin)) return true;

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

// PROD52: Correlation ID per request. Prefer the client-supplied
// X-Request-Id if present (for log-chaining across services / retry
// flows), else mint a fresh UUID. Echoed back in the response header
// so support can match a user-reported "reference prov-abcd1234"
// style error to the exact log line in the aggregator. Attached to
// `res.locals.requestId` so downstream middleware can grab it without
// re-parsing the header. Kept before helmet/cors so even pre-body
// responses (e.g. 400 from body parser) carry the header.
app.use((req, res, next) => {
  const incoming = typeof req.headers['x-request-id'] === 'string'
    ? req.headers['x-request-id']
    : null;
  // Constrain incoming header so a hostile client can't inject CRLF / log
  // separators through this path. 128 chars is plenty for any UUID variant.
  const safeIncoming = incoming && /^[A-Za-z0-9_.:+-]{1,128}$/.test(incoming)
    ? incoming
    : null;
  const requestId = safeIncoming || crypto.randomUUID();
  res.locals.requestId = requestId;
  res.setHeader('X-Request-Id', requestId);
  next();
});

// Middleware
import compression from 'compression';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import { errorEnvelopeMiddleware } from './middleware/errorEnvelope.js';

// Error-envelope enricher — monkey-patches res.json so every 4xx/5xx body
// carries code + request_id even if the individual route handler wrote a
// bare `{success:false,message:'x'}` envelope. Must run AFTER the request-id
// middleware above (so res.locals.requestId is populated) but BEFORE any
// route handler (so the patch is in place when handlers call res.json).
app.use(errorEnvelopeMiddleware);

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
// SEC-L25: Explicitly strip the X-Powered-By: Express header. Helmet already
// removes this, but the explicit disable makes the intent visible to reviewers
// and survives any future helmet downgrade.
app.disable('x-powered-by');
// PROD32: HSTS is only emitted in production. Dev uses a self-signed cert, so
// burning HSTS into a browser during local testing forces HTTPS for every
// subdomain of localhost / LAN IPs and requires a manual chrome://net-internals
// reset to recover. Production gets 180 days (15552000s) + includeSubDomains;
// `preload` is intentionally omitted — registering on hstspreload.org is a
// separate opt-in decision once the operator has a real cert on a real apex
// domain. See PROD32 in TODO.md.
const hstsConfig = config.nodeEnv === 'production'
  ? { maxAge: 15552000, includeSubDomains: true } // 180 days
  : false as const;
// PROD34 CSP posture (verify-only — already tight, no change to script-src):
//   default-src  'self'                  tight default, every directive below is explicit
//   script-src   'self' + cloudflareinsights  no 'unsafe-inline' in global CSP (prod OR dev);
//                                        Vite dev HMR uses <script src=> + eventsource,
//                                        not inline scripts, so dev does not need to relax.
//   script-src-attr 'self'               no inline event handlers (onclick=) allowed.
//   style-src    'unsafe-inline' kept    Tailwind runtime utilities and React-injected
//                                        <style> tags need it; CSS-injection blast radius
//                                        is far smaller than script injection.
//   frame-ancestors 'none' globally       /widget routes override to a strict per-tenant
//                                        allowlist (see getWidgetAllowedOrigins below).
//   img-src      'self' data: blob: https:  broad on purpose — PWA fetches supplier CDN
//                                        thumbnails across many hosts.
// Documented exceptions:
//   - /admin and /super-admin HTML pages set a relaxed per-route CSP with
//     'unsafe-inline' for scripts (see adminCsp below). Both routes are
//     localhost-only and serve legacy inline onclick handlers in the backup
//     panel. Scoped override, not a global relaxation.
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      // MW3 / PROD34: 'unsafe-inline' removed from global CSP for security.
      // Admin panel (/admin) and super-admin panel get their own relaxed CSP
      // via per-route override below.
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
  hsts: hstsConfig,
  // SEC-H3: Explicitly enable X-Content-Type-Options: nosniff (helmet default, pinned for clarity).
  noSniff: true,
  // SEC-H10: Referrer-Policy — strict-origin-when-cross-origin leaks only origin on cross-site,
  // and nothing on HTTPS→HTTP downgrades. Strong default for a CRM.
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
  // SEC-L26: X-Frame-Options: DENY — stricter than helmet's default SAMEORIGIN.
  // CSP's `frame-ancestors: 'none'` above covers modern browsers; this header is
  // the legacy belt-and-suspenders for older clients that ignore CSP.
  frameguard: { action: 'deny' },
}));
// Permissions-Policy: disable browser features we don't use
app.use((_req, res, next) => {
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()');
  next();
});
// Normalize an origin string so protocol-default ports don't defeat
// an equality check. Browsers OMIT port 443 from the Origin header when
// the client is on HTTPS/443 (same for 80/HTTP) — so a server allowlist
// containing `https://localhost:443` never matches a real request whose
// Origin is `https://localhost`. This caused every dashboard API call
// to 403 with "CORS origin rejected: https://localhost" on the
// production box, even though operators had added `https://localhost:443`
// to ALLOWED_ORIGINS. Strip the default port from both sides before
// comparing so `https://localhost` ≡ `https://localhost:443` and
// `http://host.com` ≡ `http://host.com:80`.
function normalizeOrigin(raw: string): string {
  try {
    const url = new URL(raw);
    const isDefaultPort =
      (url.protocol === 'https:' && (url.port === '' || url.port === '443')) ||
      (url.protocol === 'http:' && (url.port === '' || url.port === '80'));
    const host = isDefaultPort ? url.hostname : `${url.hostname}:${url.port}`;
    return `${url.protocol}//${host}`;
  } catch {
    return raw;
  }
}

const rawAllowedOrigins = [
  `https://localhost:${config.port}`,
  `http://localhost:${config.port}`,
  // Production/custom domains from ALLOWED_ORIGINS env var (comma-separated)
  ...(process.env.ALLOWED_ORIGINS?.split(',').map(o => o.trim()).filter(Boolean) || []),
];
const allowedOrigins = rawAllowedOrigins.map(normalizeOrigin);

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

// SEC-M52: In production, CORS is restricted to the explicit allowlist + base
// domain (+ subdomains). RFC1918 private ranges (10/8, 172.16/12, 192.168/16)
// and CGNAT (100.64/10) are NOT auto-accepted in production because a shared-
// hosting neighbor or compromised LAN device can spoof a LAN origin against
// the public API and bypass CORS entirely. Dev keeps the permissive LAN rules
// because tablets/phones on the shop network hit the server by IP during
// testing. If an operator legitimately needs to whitelist a LAN origin in
// prod, they must add it explicitly to ALLOWED_ORIGINS.
//
// PROD36: `credentials: true` is set below, so we MUST NEVER echo
// `Access-Control-Allow-Origin: *` or reflect an unvetted origin —
// browsers reject that pairing per CORS spec, but worse, some older
// browsers / polyfills trust reflected origins. The `origin` callback below
// only returns `true` for:
//   - the static allowedOrigins list (localhost:PORT + ALLOWED_ORIGINS env)
//   - the configured BASE_DOMAIN and its subdomains (tenant slugs)
//   - RFC1918 / CGNAT / loopback ONLY in non-production
//   - the no-Origin case (CORS headers aren't emitted, credentials is moot)
// Every other path rejects the CORS handshake, so `Access-Control-Allow-
// Credentials: true` can only ever ride on a reflected explicit origin.
function isCorsOriginAllowed(origin: string): boolean {
  // Compare with default-port normalization on both sides so an Origin
  // of `https://localhost` (port implicit) matches an allowlist entry
  // of `https://localhost:443` and vice versa.
  if (allowedOrigins.includes(normalizeOrigin(origin))) return true;
  try {
    const url = new URL(origin);
    const hostname = url.hostname;
    const base = config.baseDomain;
    if (base && (hostname === base || hostname.endsWith('.' + base))) {
      return true;
    }
    // SEC-M52: LAN / loopback auto-accept is DEV ONLY.
    if (config.nodeEnv !== 'production') {
      if (/^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|100\.)/.test(hostname) || hostname === 'localhost' || hostname === '127.0.0.1' || hostname.endsWith('.localhost')) {
        return true;
      }
    }
  } catch {
    return false;
  }
  return false;
}
// PROD36: rejected-origin log throttle so a misconfigured client doesn't
// spam the log file with one line per request. We keep a per-origin
// timestamp and emit at most once per 60s per origin — still visible
// enough that an operator finds it quickly, but not log-flood territory.
const corsRejectionLog = new Map<string, number>();
function logCorsRejection(origin: string): void {
  const now = Date.now();
  const last = corsRejectionLog.get(origin) ?? 0;
  if (now - last < 60_000) return;
  corsRejectionLog.set(origin, now);
  log.warn('CORS origin rejected', {
    origin,
    allowedOrigins,
    baseDomain: config.baseDomain,
    hint: 'Add this origin to ALLOWED_ORIGINS in .env (comma-separated) or set BASE_DOMAIN to match.',
  });
}

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) {
      // No Origin header: CORS spec says ACAO is not emitted here, so
      // credentials: true is moot. Allow the request to proceed to the
      // no-origin middleware below (which blocks sensitive paths in prod).
      return callback(null, true);
    }
    if (isCorsOriginAllowed(origin)) {
      // PROD36: cors library reflects the specific origin (NOT '*') when
      // we return `true` with an origin present, which is the only spec-
      // safe pairing with credentials: true.
      return callback(null, true);
    }
    // Log the rejected origin so operators can diagnose "Error: CORS not
    // allowed" without grep-hunting. Previous behaviour threw with no
    // context, which meant an admin hitting the server from a custom
    // hostname or the Electron dashboard saw identical opaque errors
    // with no way to tell them apart.
    logCorsRejection(origin);
    callback(new Error(`CORS not allowed: ${origin} — add to ALLOWED_ORIGINS or BASE_DOMAIN`));
  },
  credentials: true,
}));

// SEC-H7: Production guard — reject Origin-less requests on sensitive routes.
// Runs AFTER cors() so preflight still works; only the actual request is policed.
//
// Origin header is a CSRF defense: browsers set it on state-changing requests
// (POST/PUT/PATCH/DELETE) and on cross-origin GETs. Some browsers OMIT it on
// same-origin GETs (seen in Firefox 149 + HTTP/3 via Cloudflare), which used
// to trip this guard and loop the SPA on /api/v1/settings/setup-status with
// 403. Policy now matches the actual threat model: only block Origin-less
// state-changing API requests. GETs without Origin are safe to serve — a
// drive-by <img src> or <script src> can read the response only if the
// browser is already same-origin, which a real attacker cannot assume.
if (config.nodeEnv === 'production') {
  app.use((req, res, next) => {
    // Always let OPTIONS through — the cors() middleware above handled preflight.
    if (req.method === 'OPTIONS') return next();
    const origin = req.headers.origin;
    if (origin) return next();
    if (isPathNoOriginExempt(req.path) || isPathWebhook(req.path)) return next();
    // Any GET is safe without Origin — CSRF is not a GET-read concern.
    if (req.method === 'GET' || req.method === 'HEAD') return next();
    // Non-API paths (SPA bundle, static) were already allow-listed by the
    // cors() pass above; keep the explicit skip here for defence-in-depth.
    if (!req.path.startsWith('/api/')) return next();
    log.warn('Rejected request without Origin header', {
      method: req.method,
      path: req.path,
      ua: req.headers['user-agent'],
      requestId: res.locals.requestId,
    });
    return res.status(403).json({
      success: false,
      code: 'ERR_ORIGIN_MISSING',
      message: 'Origin header required for state-changing requests.',
      request_id: res.locals.requestId,
    });
  });
}
app.use(cookieParser());

// SEC-H4: Rate limiter is placed BEFORE body parsing (express.json / compression).
// Why: express.json({ limit: '10mb' }) at 300 req/min = 3 GB of buffered JSON per IP per minute,
// which lets a single attacker exhaust memory by flooding huge bodies. By rate-limiting first,
// we bound the number of requests that can reach the parser. compression() is a response
// middleware so its position is less critical, but we keep it after the limiter for symmetry.
//
// SEC-H83: DB-backed rate limiter — survives server restarts and works correctly in
// multi-process deployments. Uses the same consumeWindowRate helper as auth paths
// (migration 069). Eviction is handled by the retention sweeper in the rate_limits table;
// no periodic in-process cleanup is needed.
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
  // Use req.db when available (tenant context), fall back to the module-level db
  // for unauthenticated requests that arrive before tenantResolver runs.
  const limitDb = (req as any).db ?? db;
  const result = consumeWindowRate(limitDb, 'api_v1', ip, API_RATE_LIMIT, API_RATE_WINDOW);
  if (!result.allowed) {
    res.setHeader('Retry-After', String(result.retryAfterSeconds));
    return res.status(429).json({
      success: false,
      code: 'ERR_RATE_API',
      message: 'Too many requests',
      request_id: res.locals.requestId,
      retry_after_seconds: result.retryAfterSeconds,
    });
  }
  next();
});

// Stripe webhook — must be mounted BEFORE express.json() because signature verification needs raw body.
// Kept here (after rate limiter, before json parser) so its own express.raw() limit applies.
app.post('/api/v1/billing/webhook', express.raw({ type: 'application/json', limit: '1mb' }), stripeWebhookHandler);

// SEC-H81: Per-route body-parser carve-outs for endpoints that legitimately receive
// >1mb JSON bodies.  These MUST be registered BEFORE the global express.json() below
// so that Express buffers the larger body on this path first; the global 1mb parser
// then skips re-parsing because req.body is already populated.
//
// Current carve-outs:
//   POST /api/v1/catalog/bulk-import — up to 5 000 catalog items (MAX_BULK_ITEMS).
//     At ~500 bytes/item the payload can reach ~2.5 MB.  Admin-only.
app.post(
  '/api/v1/catalog/bulk-import',
  express.json({ limit: '10mb' }),
);

// SEC-H81: Global cap reduced to 1mb — prevents DoS via large JSON payloads.
app.use(express.json({
  limit: '1mb',
  verify: (req: any, _res, buf) => { req.rawBody = buf; }, // Capture raw body for webhook signature verification
}));
// SEC-H6: Cap urlencoded payloads at 1mb — prevents unbounded form-body memory use.
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// HTTP request logging (ENR-INFRA3) — logs method, path, status, response time
import { requestLogger } from './middleware/requestLogger.js';
app.use(requestLogger);

// ENR-INFRA7 + SEC-M53: API Cache-Control headers.
// - Default (ENR-INFRA7): `private, no-cache` for GETs — forces conditional
//   revalidation via If-None-Match / ETag, still enabling 304 responses.
// - PII endpoints (SEC-M53): `private, no-store, max-age=0` — prevents any
//   on-disk caching of customer/ticket/invoice/auth-me payloads by browsers
//   or intermediate proxies. Applied to every method, not only GET, so PATCH
//   responses echoing customer records can't be cached either.
const PII_PATH_PREFIXES = [
  '/api/v1/customers',
  '/api/v1/tickets',
  '/api/v1/invoices',
  '/api/v1/auth/me',
];
app.use('/api/v1', (req, _res, next) => {
  const isPii = PII_PATH_PREFIXES.some((p) => req.path === p || req.path.startsWith(p + '/'));
  if (isPii) {
    _res.setHeader('Cache-Control', 'private, no-store, max-age=0');
  } else if (req.method === 'GET') {
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
    return res.status(403).json({
      success: false,
      code: 'ERR_CONTENT_TYPE',
      message: 'State-changing requests must use application/json or multipart/form-data.',
      request_id: res.locals.requestId,
    });
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

// SEC-H54: /uploads/* is now auth-gated instead of plain static serving.
// Authenticated users hit /uploads/... with their Bearer token. Public
// customer contexts (email receipts, MMS media, portal approvals) must
// use the signed-URL endpoint further below (/signed-url/:type/:slug/:file)
// which verifies an HMAC over (type + slug + file + exp).
//
// Prior behaviour: express.static() served any file under config.uploadsPath
// to any caller with the URL. Filenames are long random hex strings so the
// risk was information-disclosure via URL leakage (log files, email forwards,
// browser history sync). Auth-gating closes that vector.
import { verifySignedUpload } from './utils/signedUploads.js';
app.use('/uploads', authMiddleware, (req, res, next) => {
  const decoded = decodeURIComponent(req.path);
  if (decoded.includes('..') || decoded.includes('\\')) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  // In multi-tenant mode, serve from uploads/{slug}/ subdirectory.
  // Cross-tenant reads are blocked by authMiddleware's tenant check
  // (token.tenantSlug must match req.tenantSlug), but we still verify
  // the resolved path stays inside the tenant's own directory.
  const basePath = req.tenantSlug
    ? path.join(config.uploadsPath, req.tenantSlug)
    : config.uploadsPath;

  const resolved = path.resolve(basePath, decoded.replace(/^\//, ''));
  if (!resolved.startsWith(path.resolve(basePath))) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  express.static(basePath, { dotfiles: 'deny', index: false })(req, res, next);
});

// SEC-H54: signed-URL endpoint for public customer contexts. Clients that
// can't carry a JWT (email clients, SMS/MMS image previews, portal pages
// opened from a cold link) fetch /signed-url/:type/:slug/:file?exp=...&sig=...
// The HMAC is verified against config.uploadsSecret before streaming the file.
// No auth middleware — the signature IS the auth.
app.get(/^\/signed-url\/([^/]+)\/([^/]+)\/(.+)$/, (req, res) => {
  const type = req.params[0];
  const slug = req.params[1];
  const file = req.params[2];
  const { exp, sig } = req.query as { exp?: string; sig?: string };

  const verdict = verifySignedUpload(type, slug, file, exp, sig);
  if (!verdict.ok) {
    if (verdict.reason === 'expired') {
      return res.status(410).json({ success: false, message: 'Link expired' });
    }
    return res.status(403).json({ success: false, message: 'Invalid signature' });
  }

  // Reject any traversal attempt even after successful signature verify —
  // defence-in-depth in case uploadsSecret leaks and a signature can be forged.
  const decodedFile = decodeURIComponent(file);
  if (decodedFile.includes('..') || decodedFile.includes('\\')) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  // Only 'uploads' maps directly to uploadsPath; other types use subdirs
  // (mms, recordings, bench, shrinkage, inventory) that already live under
  // uploadsPath/<slug>/<type>/ by convention in the relevant upload routes.
  const baseDir = path.join(config.uploadsPath, slug);
  const relative = type === 'uploads' ? decodedFile : path.join(type, decodedFile);
  const resolved = path.resolve(baseDir, relative);
  if (!resolved.startsWith(path.resolve(baseDir))) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  res.sendFile(resolved, (err) => {
    if (err && !res.headersSent) {
      res.status(404).json({ success: false, message: 'File not found' });
    }
  });
});

// SEC-H54: separate /admin-uploads/* for super-admin-only artefacts
// (tenant license docs, signed agreements, KYC attachments). Localhost
// + super-admin session required — this path NEVER serves tenant-user
// uploads, so a tenant compromise can't exfiltrate these files.
app.use('/admin-uploads', localhostOnly, (req, res, next) => {
  // Minimal inline super-admin check (mirrors super-admin.routes.ts
  // superAdminAuth, without importing the whole router for one handler).
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Super admin authentication required' });
  }
  try {
    const token = authHeader.slice(7);
    const payload = jwt.verify(token, config.superAdminSecret, {
      algorithms: ['HS256'],
      issuer: 'bizarre-crm',
      audience: 'bizarre-crm-super-admin',
    }) as { role?: string };
    if (!payload || payload.role !== 'super_admin') {
      return res.status(403).json({ success: false, message: 'Super admin access required' });
    }
  } catch {
    return res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }

  const decoded = decodeURIComponent(req.path);
  if (decoded.includes('..') || decoded.includes('\\')) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }
  const resolved = path.resolve(config.adminUploadsPath, decoded.replace(/^\//, ''));
  if (!resolved.startsWith(path.resolve(config.adminUploadsPath))) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }
  express.static(config.adminUploadsPath, { dotfiles: 'deny', index: false })(req, res, next);
});

// Public info endpoint — returns server LAN address for QR codes etc.
// SEC-L24: in multi-tenant (SaaS) mode this leaks the host's LAN IP, which
// is information that only authenticated tenant users should be able to see.
// In single-tenant mode the shop owner controls both the server and the
// requesting device, so the legacy public access is preserved for
// compatibility with the existing Android app's QR bootstrap flow.
const infoAuthGate = (req: Request, res: Response, next: NextFunction): void => {
  if (!config.multiTenant) {
    next();
    return;
  }
  authMiddleware(req, res, next);
};
app.get('/api/v1/info', infoAuthGate, (_req, res) => {
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
// SECURITY (BH-S002 mitigation): Super admin API + HTML panel are restricted to
// localhost only. Operator must RDP/SSH into the server host and access via
// http(s)://127.0.0.1 or run the Electron management app locally. An attacker
// with a leaked SUPER_ADMIN_SECRET cannot hit /super-admin/* from anywhere on
// the internet — the TCP connection source must be loopback (checked against
// req.socket.remoteAddress, not spoofable req.ip).
app.use('/super-admin/api', localhostOnly, superAdminRoutes);
// SEC-H89 / PROD34: Admin panel CSP — 'unsafe-inline' removed from script-src now that
// all inline scripts have been extracted to /admin/js/admin.js and /admin/js/super-admin.js.
// script-src-attr is kept 'none' (no inline event handlers). style-src keeps 'unsafe-inline'
// because the panels embed all CSS inline in <style> blocks (no XSS risk from style injection
// compared to script injection). Both panels are localhost-only / super-admin-gated.
const adminCsp = "default-src 'self'; script-src 'self'; script-src-attr 'none'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' ws: wss:; font-src 'self'; frame-ancestors 'none'";
// Serve the extracted admin JS files under /admin/js/ (needed by both panels).
app.use('/admin/js', express.static(path.resolve(__dirname, 'admin/js'), { index: false }));
app.get('/super-admin', localhostOnly, (_req, res) => {
  if (!config.multiTenant) return res.status(404).send('Not available');
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/super-admin.html'));
});
app.get('/super-admin/*', localhostOnly, (_req, res) => {
  if (!config.multiTenant) return res.status(404).send('Not available');
  res.setHeader('Content-Security-Policy', adminCsp);
  res.sendFile(path.resolve(__dirname, 'admin/super-admin.html'));
});

// API Routes (auth does NOT require middleware)
app.use('/api/v1/auth', authRoutes);

// SMS webhooks — public (no auth), providers POST here
// In multi-tenant mode, webhooks must include tenant slug in the URL path for correct DB routing

// SEC-H83: DB-backed webhook rate limiter (60 req/min per IP). Survives restarts.
// Uses the same consumeWindowRate helper as auth paths and the global API limiter.
const WEBHOOK_RATE_LIMIT = 60;
const WEBHOOK_RATE_WINDOW = 60_000; // 1 minute
function webhookRateLimit(req: any, res: any, next: any) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const result = consumeWindowRate(db, 'webhook', ip, WEBHOOK_RATE_LIMIT, WEBHOOK_RATE_WINDOW);
  if (!result.allowed) {
    res.setHeader('Retry-After', String(result.retryAfterSeconds));
    return res.status(429).json({
      success: false,
      code: 'ERR_RATE_WEBHOOK',
      message: 'Too many webhook requests',
      request_id: res.locals.requestId,
      retry_after_seconds: result.retryAfterSeconds,
    });
  }
  next();
}

app.post('/api/v1/sms/inbound-webhook', webhookRateLimit, smsInboundWebhookHandler);
app.post('/api/v1/sms/status-webhook', webhookRateLimit, smsStatusWebhookHandler);

// Voice webhooks — public (no auth)
app.post('/api/v1/voice/inbound-webhook', webhookRateLimit, voiceInboundWebhookHandler);
app.post('/api/v1/voice/status-webhook', webhookRateLimit, voiceStatusWebhookHandler);
app.post('/api/v1/voice/recording-webhook', webhookRateLimit, voiceRecordingWebhookHandler);
app.post('/api/v1/voice/transcription-webhook', webhookRateLimit, voiceTranscriptionWebhookHandler);
app.get('/api/v1/voice/instructions/:action', webhookRateLimit, voiceInstructionsHandler);

// Multi-tenant webhook routes with tenant slug in URL path
// Providers should be configured to POST to: https://{slug}.{BASE_DOMAIN}/api/v1/sms/inbound-webhook
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
// PROD58: per-tenant GDPR/CCPA data export. Mounted under /data-export so
// the path is distinct from the settings-level export (/settings-ext/export.json
// only covers store_config). Admin-only gate lives inside the router.
app.use('/api/v1/data-export', authMiddleware, dataExportRoutes);
// SEC-H59 / P3-PII-16: Full encrypted tenant export (all tables + uploads,
// passphrase-encrypted zip, signed single-use download token).
// The /download/:signedToken path is public (token IS the credential — no JWT
// required). Mount it WITHOUT authMiddleware so browsers can follow the link
// directly. All other tenant/export endpoints require admin + step-up TOTP.
app.use('/api/v1/tenant/export', tenantExportDownloadRouter);
app.use('/api/v1/tenant/export', authMiddleware, tenantExportRoutes);
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
// Web-parity backend (2026-04-23) — mobile apps (android + iOS) already plan/consume these.
// See android/ActionPlan.md + ios/ActionPlan.md for request/response contracts.
// Role/permission gates + rate limits are applied inside each router file.
app.use('/api/v1/schedule', authMiddleware, shiftsScheduleRoutes);
app.use('/api/v1/time-off', authMiddleware, timeOffRoutes);
app.use('/api/v1/timesheet', authMiddleware, timesheetRoutes);
app.use('/api/v1/inventory-variants', authMiddleware, inventoryVariantsRoutes);
app.use('/api/v1/inventory-bundles', authMiddleware, inventoryBundlesRoutes);
app.use('/api/v1/recurring-invoices', authMiddleware, recurringInvoicesRoutes);
app.use('/api/v1/credit-notes', authMiddleware, creditNotesRoutes);
app.use('/api/v1/activity', authMiddleware, activityRoutes);
app.use('/api/v1/notification-preferences', authMiddleware, notificationPrefsRoutes);
app.use('/api/v1/pos/held-carts', authMiddleware, heldCartsRoutes);
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

// @audit-fixed: #9 (health info leak) — the old /health and /api/v1/health routes
// returned heap/rss, DB file size, worker queue depth, uptime, version, and timestamp
// WITHOUT any auth, exposing internal state to anyone probing the server. Split into:
//   - /health                       : plain liveness probe, 200 once the process is up.
//   - /api/v1/health                : liveness probe in the API envelope, { status:'ok' }.
//   - /api/v1/health/ready          : readiness probe; 503 until migrations finish.
//   - /api/v1/health/internal       : full internal state, admin-only (authMiddleware + role).
// Load balancers and uptime monitors should use /health or /api/v1/health (liveness) and
// /api/v1/health/ready (readiness). Operators wanting heap/db stats hit /internal.

// SEC-M29: Liveness now round-trips the master DB with `SELECT 1` so that
// an LB can actually tell the difference between "process alive" and
// "process alive but DB handle is dead" (e.g. disk full, file locked,
// connection pool wedged). Response stays minimal so this endpoint is
// safe to publish; failures return 503.
function probeMasterDb(): boolean {
  try {
    db.prepare('SELECT 1').get();
    return true;
  } catch {
    return false;
  }
}

app.get('/health', (_req, res) => {
  if (!probeMasterDb()) {
    res.status(503).json({ success: false, message: 'db unreachable' });
    return;
  }
  res.json({ success: true, data: { status: 'ok' } });
});

app.get('/api/v1/health', (_req, res) => {
  if (!probeMasterDb()) {
    res.status(503).json({ success: false, message: 'db unreachable' });
    return;
  }
  res.json({ success: true, data: { status: 'ok' } });
});

// @audit-fixed: #7 (boot race) — readiness probe. Returns 503 until migrateAllTenants()
// has resolved so load balancers / container orchestrators can hold traffic until the
// fleet is actually safe to serve. readyError is set if migrations failed; we still
// return 200 in that case because the prior behavior (per-tenant failure tracking) is
// the source of truth for which tenants are usable.
app.get('/api/v1/health/ready', (_req, res) => {
  if (!isReady) {
    res.status(503).json({
      success: false,
      message: 'Server is still starting',
    });
    return;
  }
  // SEC-M29: in addition to the boot-phase `isReady` flag, round-trip the
  // master DB by reading `PRAGMA user_version` — catches post-boot DB
  // degradation (file pulled out from under us, schema migration in flight,
  // WAL corruption) that pure `isReady` cannot detect. Returns 503 so that
  // orchestrators drain traffic instead of sending requests that'll 500.
  let userVersion: number | null = null;
  try {
    const row = db.prepare('PRAGMA user_version').get() as { user_version?: number } | undefined;
    userVersion = row?.user_version ?? null;
  } catch {
    res.status(503).json({ success: false, message: 'db unreachable' });
    return;
  }
  res.json({
    success: true,
    data: {
      status: 'ready',
      degraded: readyError !== null,
      schemaVersion: userVersion,
    },
  });
});

// Admin-only internal health — heap, DB size, worker pool stats. Was previously public.
app.get('/api/v1/health/internal', authMiddleware, (req, res) => {
  if (req.user?.role !== 'admin') {
    res.status(403).json({ success: false, message: 'Admin role required' });
    return;
  }

  let dbStatus = 'connected';
  let dbSizeBytes: number | null = null;
  try {
    db.prepare('SELECT 1').get();
    try {
      const stats = fs.statSync(config.dbPath);
      dbSizeBytes = stats.size;
    } catch { /* ignore stat failures */ }
  } catch {
    dbStatus = 'disconnected';
  }

  const mem = process.memoryUsage();
  const poolStats = getPoolStats();

  const payload = {
    status: dbStatus === 'connected' ? 'ok' : 'degraded',
    ready: isReady,
    readyError: readyError ? readyError.message : null,
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
  res.status(statusCode).json({ success: true, data: payload });
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

server.listen(config.port, config.host, async () => {
  // @audit-fixed: #7 (boot race) — block the "server ready" log AND readiness probe
  // until the multi-tenant migration pass finishes. The TCP listener is already open
  // by the time this callback fires (Node binds the socket before invoking the
  // callback), but requests that depend on schema state will get 503 from
  // /api/v1/health/ready and operators can wait on that before rotating traffic.
  await readyPromise;
  isReady = true;
  log.info('Server ready — readyPromise resolved', { degraded: readyError !== null });
  if (typeof process.send === 'function') {
    process.send('ready');
  }

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
  //
  // SEC-L46: Previously capped at 10 per tenant per hour, which is too low for
  // any shop with >10 active monthly memberships — they'd accumulate debt
  // faster than the cron could drain it. Bumped to 100 and wrapped each
  // tenant's work unit in a 10-minute timeout so a wedged BlockChyp call
  // can't stall the whole cron indefinitely. The timeout uses Promise.race
  // against a rejected timer — there's no AbortSignal plumbed into the
  // BlockChyp SDK yet, but the timeout at least lets the cron progress to
  // the next tenant; any orphaned in-flight charges continue in the
  // background and log-record themselves the same as any other async call.
  // Recurring invoices cron (SCAN-478 / web-parity 2026-04-23).
  // Runs every 15 min; creates invoices from active `invoice_templates` whose
  // next_run_at <= now(). startRecurringInvoicesCron owns its internal setInterval
  // and returns the handle, so push directly into backgroundIntervals for graceful
  // shutdown (same contract as trackInterval's tracked handles).
  try {
    const recurringInvoicesTimer = startRecurringInvoicesCron(() => {
      const entries: Array<{ slug: string; db: any }> = [];
      forEachDb((slug, db) => {
        if (slug && db) entries.push({ slug, db });
      });
      return entries as unknown as Iterable<import('./services/recurringInvoicesCron.js').TenantDbEntry>;
    });
    backgroundIntervals.push(recurringInvoicesTimer);
  } catch (err) {
    log.error('Failed to start recurring invoices cron', {
      error: err instanceof Error ? err.message : String(err),
    });
  }
  const MEMBERSHIP_MAX_PER_RUN = 100;
  const MEMBERSHIP_PER_TENANT_TIMEOUT_MS = 10 * 60 * 1000; // 10 min
  trackInterval(async () => {
    let chargeToken: typeof import('./services/blockchyp.js').chargeToken;
    try {
      ({ chargeToken } = await import('./services/blockchyp.js'));
    } catch (err) {
      log.error('Membership: renewal cron failed to load blockchyp module', {
        error: err instanceof Error ? err.message : String(err),
      });
      return;
    }

    try {
      // forEachDbAsync lets us await the charges within each tenant's work unit.
      await forEachDbAsync(async (slug: string | null, tenantDb: any) => {
        // SEC-L46: per-tenant timeout wrapper so one hung tenant can't stall
        // the whole membership cron. The Promise.race pattern resolves with
        // whatever finishes first; if the timer wins we log and return, and
        // the actual tenant work keeps running in the background (we can't
        // abort it without AbortSignal plumbing that doesn't exist yet).
        let timer: NodeJS.Timeout | null = null;
        const timeout = new Promise<void>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error(`Membership cron timeout (${MEMBERSHIP_PER_TENANT_TIMEOUT_MS}ms)`)),
            MEMBERSHIP_PER_TENANT_TIMEOUT_MS,
          );
        });
        try {
          await Promise.race([membershipTenantWork(slug, tenantDb), timeout]);
        } catch (err) {
          log.error('Membership: tenant work timed out or failed', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
        } finally {
          if (timer) clearTimeout(timer);
        }
      });
    } catch (err) {
      log.error('Membership: renewal cron outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    async function membershipTenantWork(slug: string | null, tenantDb: any): Promise<void> {
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
    }
  }, 3600_000); // Every hour

  // SEC-M42: payment_idempotency janitor — sweep every 5 min to flip rows
  // stuck in 'pending' longer than the threshold (inside sweepStuckPaymentIdempotency)
  // over to 'failed'. Without this, a server crash between INSERT and the
  // BlockChyp-response UPDATE leaves the idempotency key locked forever,
  // preventing the client from retrying the charge with the same invoice.
  trackInterval(async () => {
    try {
      const { sweepStuckPaymentIdempotency } = await import('./services/blockchyp.js');
      forEachDb((slug, tenantDb) => {
        try {
          const fixed = sweepStuckPaymentIdempotency(tenantDb);
          if (fixed > 0) {
            console.log(`[PaymentJanitor${slug ? `:${slug}` : ''}] Flipped ${fixed} stuck pending rows to failed`);
          }
        } catch (err) {
          log.error('PaymentJanitor: tenant sweep failed', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.error('PaymentJanitor: outer error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 5 * 60 * 1000); // Every 5 minutes

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

  // SEC-L18: Per-tenant failure circuit for cron handlers. One bad tenant
  // (corrupt DB, schema drift, wedged SMS provider) used to burn CPU on every
  // cron tick forever — the surrounding per-tenant try/catch swallowed errors
  // but kept calling the same doomed code path. Circuit tracks consecutive
  // failures per (cronName, tenantSlug) pair; after CRON_CIRCUIT_MAX_FAILURES
  // in a row we skip the tenant for CRON_CIRCUIT_COOLDOWN_MS before retrying.
  // Counter resets on the first success. The slug 'default' is used for
  // single-tenant mode so the same key space works in both modes.
  const CRON_CIRCUIT_MAX_FAILURES = 5;
  const CRON_CIRCUIT_COOLDOWN_MS = 10 * 60 * 1000;
  interface CircuitEntry {
    consecutiveFailures: number;
    /** Unix-ms timestamp when the tenant becomes eligible to retry. 0 = open now. */
    openUntil: number;
  }
  const cronCircuits = new Map<string, CircuitEntry>();
  function circuitKey(cronName: string, tenantSlug: string | null | undefined): string {
    return `${cronName}:${tenantSlug ?? 'default'}`;
  }
  function circuitAllowsRun(cronName: string, tenantSlug: string | null | undefined): boolean {
    const key = circuitKey(cronName, tenantSlug);
    const entry = cronCircuits.get(key);
    if (!entry) return true;
    if (entry.openUntil <= Date.now()) return true;
    return false;
  }
  function recordCircuitSuccess(cronName: string, tenantSlug: string | null | undefined): void {
    const key = circuitKey(cronName, tenantSlug);
    const entry = cronCircuits.get(key);
    if (!entry) return;
    // Reset on success — counter + open window both cleared so future failures
    // have to accumulate from zero again.
    cronCircuits.delete(key);
  }
  function recordCircuitFailure(cronName: string, tenantSlug: string | null | undefined): boolean {
    const key = circuitKey(cronName, tenantSlug);
    const entry = cronCircuits.get(key) ?? { consecutiveFailures: 0, openUntil: 0 };
    entry.consecutiveFailures += 1;
    if (entry.consecutiveFailures >= CRON_CIRCUIT_MAX_FAILURES) {
      entry.openUntil = Date.now() + CRON_CIRCUIT_COOLDOWN_MS;
    }
    cronCircuits.set(key, entry);
    return entry.openUntil > Date.now();
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

  // SEC-M49: Per-tenant DB size monitor. Once per UTC day inside the 02:00
  // hour (nominally 02:15 UTC — lands just after the 02:00 tenant-timezone
  // retention sweeps above and an hour before the 03:00 master retention
  // sweep). We do NOT archive or delete anything here — that belongs to
  // SEC-AL5 (audit logs) and the tenant retention sweeper respectively.
  // This cron is pure observability: one `log.info` line per tenant per day
  // so ops can chart DB growth, catch runaway tables, and pre-empt a full
  // disk before a tenant's WAL stalls the whole node.
  // Budget: ~1 syscall (`fs.statSync`) per tenant per day — negligible.
  // `shouldRunDaily('tenant-db-size-monitor', 'UTC')` guarantees a single
  // fire per UTC day even if the interval lands multiple times in hour 02.
  trackInterval(() => {
    try {
      const utcHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: 'UTC' }));
      if (utcHour !== 2) return;
      if (!shouldRunDaily('tenant-db-size-monitor', 'UTC')) return;

      forEachDb((slug, tenantDb) => {
        try {
          const dbFile = (tenantDb as { name?: string })?.name;
          if (!dbFile) return;
          const size = fs.statSync(dbFile).size;
          log.info('tenant db size', {
            slug: slug ?? 'default',
            sizeBytes: size,
            sizeMB: +(size / 1e6).toFixed(2),
          });
        } catch (err) {
          log.error('tenant db size monitor: per-tenant error', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      });
    } catch (err) {
      log.error('tenant db size monitor: scheduling error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Check every hour, execute during hour 02 UTC

  // PROD59: Daily sweep of the `deleted/` directory. Anything older than
  // TERMINATION_GRACE_DAYS (30) is physically unlinked. Runs once per UTC
  // day inside hour 03 (after the 02:00 retention sweeps above). We also
  // kick the purge once at startup so a server that was offline through a
  // scheduled deletion catches up on boot — the "never delete a tenant DB
  // earlier than scheduled" invariant still holds because the cutoff is
  // mtime-based, not cron-tick-based.
  if (config.multiTenant) {
    import('./services/tenantTermination.js')
      .then(({ purgeExpiredDeletions }) => {
        try {
          purgeExpiredDeletions();
        } catch (err) {
          log.error('[PROD59] Startup purge failed', {
            error: err instanceof Error ? err.message : String(err),
          });
        }
        trackInterval(() => {
          try {
            const utcHour = parseInt(
              new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: 'UTC' }),
            );
            if (utcHour !== 3) return;
            if (!shouldRunDaily('tenant-termination-purge', 'UTC')) return;
            purgeExpiredDeletions();
          } catch (err) {
            log.error('[PROD59] Purge sweep tick failed', {
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }, 60 * 60 * 1000);
      })
      .catch((err) => {
        log.error('[PROD59] Failed to load tenantTermination service', {
          error: err instanceof Error ? err.message : String(err),
        });
      });
  }

  // TP§26: Daily archive sweep — moves tenant DB files queued for deletion to
  // the deleted/ directory once their grace period has elapsed. Only meaningful
  // in multi-tenant mode (single-tenant has no tenant lifecycle).
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  if (config.multiTenant && process.env.NODE_ENV !== 'test') {
    trackInterval(async () => {
      try {
        if (!shouldRunDaily('archive-due-tenants', 'UTC')) return;
        const { archiveDueTenants } = await import('./services/tenant-provisioning.js');
        const archived = await archiveDueTenants();
        if (archived.length > 0) {
          log.info('archiveDueTenants: archived tenants', { slugs: archived });
        }
      } catch (err) {
        log.error('archiveDueTenants: daily sweep failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }, 24 * 60 * 60 * 1000);
  }

  // Audit issue #23: Retention sweeper for unbounded log/queue tables.
  // Separate cron from the audit_logs purge above because:
  //  (1) runRetentionSweep is async (forEachDbAsync), the audit purge uses sync forEachDb,
  //  (2) we intentionally do NOT touch audit_logs retention here — SEC-AL5 already owns that
  //      policy (>=1 year via AUDIT_LOG_RETENTION_DAYS). Keeping the two blocks separate makes
  //      it impossible to accidentally regress the audit retention window.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const label = slug ? `:${slug}` : '';
        // SEC-L18: skip tenants whose circuit is open.
        if (!circuitAllowsRun('retention-sweep', slug)) return;
        try {
          const tzRow = tenantDb
            .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
            .get() as any;
          const tz = tzRow?.value || 'America/Denver';
          const localHour = parseInt(
            new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tz })
          );
          // Only sweep once per tenant per local day, anchored at 2 AM like the audit purge
          // above so both cleanups share the same nightly window.
          if (localHour !== 2 || !shouldRunDaily(`retention-sweep${label}`, tz)) return;

          const { runRetentionSweep } = await import('./services/retentionSweeper.js');
          const result = await runRetentionSweep(tenantDb, config.uploadsPath, slug ?? '');
          if (result.totalDeleted > 0) {
            console.log(
              `[RetentionSweep${label}] Deleted ${result.totalDeleted} rows across ${
                Object.keys(result.perTable).length
              } tables`
            );
          }
          // SEC-L18: success clears any prior failure streak for this tenant.
          recordCircuitSuccess('retention-sweep', slug);
        } catch (err) {
          // Per-tenant isolation: one bad tenant must not kill the sweep for the others.
          // SEC-L18: bump the tenant's failure counter; once it crosses
          // CRON_CIRCUIT_MAX_FAILURES the tenant is skipped for
          // CRON_CIRCUIT_COOLDOWN_MS.
          const nowOpen = recordCircuitFailure('retention-sweep', slug);
          log.error('Retention sweep: tenant error', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
            circuitOpen: nowOpen,
          });
        }
      });
    } catch (err) {
      log.error('Retention sweep: failed to enumerate tenants', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Check every hour, run at 2 AM

  // SEC-H114 (LOGIC-004): Gift-card expiry sweep — daily at 1 AM store timezone.
  // Flips gift_cards.status from 'active' → 'expired' for any card whose
  // expires_at has passed. The redeem-time atomic guard already prevents
  // expired cards from being redeemed regardless of status, so this sweep is
  // a reporting-accuracy pass rather than a security boundary. Running at 1 AM
  // (one hour before the 2 AM retention sweeps) keeps nightly disk I/O spread.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(async () => {
    try {
      const { sweepExpiredGiftCards } = await import('./services/giftCardExpirySweep.js');
      await forEachDbAsync(async (slug, tenantDb) => {
        const label = slug ? `:${slug}` : '';
        if (!circuitAllowsRun('gift-card-expiry', slug)) return;
        try {
          const tzRow = tenantDb
            .prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
            .get() as { value?: string } | undefined;
          const tz = tzRow?.value || 'America/Denver';
          const localHour = Number.parseInt(
            new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: tz }),
            10,
          );
          if (localHour !== 1 || !shouldRunDaily(`gift-card-expiry${label}`, tz)) return;

          const count = sweepExpiredGiftCards(tenantDb);
          if (count > 0) {
            log.info(`GiftCardExpiry${label}: expired ${count} gift card(s)`);
          }
          recordCircuitSuccess('gift-card-expiry', slug);
        } catch (err) {
          const nowOpen = recordCircuitFailure('gift-card-expiry', slug);
          log.error('GiftCardExpiry: tenant error', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
            circuitOpen: nowOpen,
          });
        }
      });
    } catch (err) {
      log.error('GiftCardExpiry: failed to enumerate tenants', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Check every hour, run at 1 AM

  // SEC-M27: Master DB retention sweep — master_audit_log, tenant_auth_events,
  // security_alerts are append-only tables that grow forever without a cron.
  // Runs once per UTC day at 03:00 (an hour after tenant sweeps so we don't
  // pile disk I/O on the same minute). Retention windows chosen to mirror
  // SOC2-style defaults while keeping volume manageable:
  //   - master_audit_log:    730 days (super-admin ops log, compliance)
  //   - tenant_auth_events:   90 days (high-volume login/2FA firehose)
  //   - security_alerts:     730 days if unacked, 180 days if acked
  // shouldRunDaily keyed to 'UTC' so we don't retrigger per tenant.
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  trackInterval(() => {
    try {
      const utcHour = parseInt(new Date().toLocaleString('en-US', { hour: 'numeric', hour12: false, timeZone: 'UTC' }));
      if (utcHour !== 3 || !shouldRunDaily('master-retention', 'UTC')) return;

      const masterDb = getMasterDb();
      if (!masterDb) return;
      try {
        const auditResult = masterDb.prepare(
          "DELETE FROM master_audit_log WHERE created_at < datetime('now', '-730 days')"
        ).run();
        if (auditResult.changes > 0) {
          console.log(`[MasterRetention] Purged ${auditResult.changes} master_audit_log rows (>730d)`);
        }

        const authResult = masterDb.prepare(
          "DELETE FROM tenant_auth_events WHERE created_at < datetime('now', '-90 days')"
        ).run();
        if (authResult.changes > 0) {
          console.log(`[MasterRetention] Purged ${authResult.changes} tenant_auth_events rows (>90d)`);
        }

        const ackedAlertResult = masterDb.prepare(
          "DELETE FROM security_alerts WHERE acknowledged = 1 AND created_at < datetime('now', '-180 days')"
        ).run();
        const unackedAlertResult = masterDb.prepare(
          "DELETE FROM security_alerts WHERE acknowledged = 0 AND created_at < datetime('now', '-730 days')"
        ).run();
        const alertPurged = ackedAlertResult.changes + unackedAlertResult.changes;
        if (alertPurged > 0) {
          console.log(`[MasterRetention] Purged ${alertPurged} security_alerts rows`);
        }

        try { masterDb.pragma('incremental_vacuum(100)'); } catch { /* WAL may not have pages to free */ }
      } catch (err) {
        log.error('Master retention: sweep error', {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    } catch (err) {
      log.error('Master retention: scheduling error', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, 60 * 60 * 1000); // Check every hour, execute at 03:00 UTC

  // Appointment reminder check (every 15 minutes) -- iterates all tenant DBs in multi-tenant mode
  // SEC-BG7: Registered via trackInterval so shutdown() can clear it.
  // SEC-L18: Per-tenant failure circuit — a tenant whose appointments table or
  // SMS provider has been failing for 5 consecutive ticks is skipped for 10
  // minutes. Prevents a wedged BizarreSMS HTTPS endpoint for one tenant from
  // burning every subsequent 15-min tick forever.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        if (!circuitAllowsRun('appointment-reminder', slug)) return;
        try {
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

          if (upcoming.length === 0) {
            // A no-op tick is a success — clears any prior failure streak.
            recordCircuitSuccess('appointment-reminder', slug);
            return;
          }
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
              // NOTE: a single SMS failure does NOT count as a per-tenant
              // cron failure — bad phone numbers and provider transient errors
              // are expected. Only an uncaught failure in the surrounding
              // tenant work counts.
              log.error('Appointment reminder: SMS send failed', {
                tenantSlug: slug,
                appointmentId: appt.id,
                phone,
                error: err instanceof Error ? err.message : String(err),
              });
            }
          }
          // Loop completed (even with per-message failures) — counts as a
          // success for the circuit. The per-message failures don't roll up
          // into the tenant-level circuit because they're bounded by design.
          recordCircuitSuccess('appointment-reminder', slug);
        } catch (err) {
          const nowOpen = recordCircuitFailure('appointment-reminder', slug);
          log.error('Appointment reminder: tenant work failed', {
            tenantSlug: slug,
            error: err instanceof Error ? err.message : String(err),
            circuitOpen: nowOpen,
          });
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
  // SEC-H69: Atomic claim via status='processing'. SELECT candidates, then
  // UPDATE WHERE id=? AND status='pending' (changes===1 gate). Concurrent
  // workers that race to the same row see changes===0 and skip it.
  trackInterval(async () => {
    try {
      await forEachDbAsync(async (slug, tenantDb) => {
        const candidates = tenantDb.prepare(`
          SELECT * FROM notification_queue
          WHERE status = 'pending'
            AND (scheduled_at IS NULL OR scheduled_at <= datetime('now'))
          ORDER BY created_at ASC
          LIMIT 10
        `).all() as any[];

        if (candidates.length === 0) return;

        const label = slug ? `:${slug}` : '';

        for (const item of candidates) {
          // SEC-H69: Atomic claim — flip status to 'processing' only if the row
          // is still 'pending'. If another worker already claimed it, changes===0.
          const claim = tenantDb.prepare(
            "UPDATE notification_queue SET status = 'processing' WHERE id = ? AND status = 'pending'"
          ).run(item.id) as { changes: number };
          if (claim.changes === 0) continue; // already claimed — skip

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
            // Exponential backoff (2^retryCount minutes) + jitter seconds (0-59).
            const backoffMinutes = Math.pow(2, newRetryCount);
            const jitterSeconds = Math.floor(Math.random() * 60);
            const backoffSeconds = backoffMinutes * 60 + jitterSeconds;
            tenantDb.prepare(`
              UPDATE notification_queue
              SET status = ?, error = ?, retry_count = ?,
                  scheduled_at = CASE WHEN ? = 'pending' THEN datetime('now', '+' || ? || ' seconds') ELSE scheduled_at END
              WHERE id = ?
            `).run(newStatus, errMsg, newRetryCount, newStatus, backoffSeconds, item.id);
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

          const summary = await runDunningIfDue(tenantDb);
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
// @audit-fixed: #8 — when called from the fatal-error handler (signal starts with
// "uncaughtException" / "unhandledRejection"), exit with code 1 so PM2/systemd treats
// the restart as a crash rather than a clean stop.
let shuttingDown = false;
function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  const isFatal = signal === 'uncaughtException' || signal === 'unhandledRejection';
  const exitCode = isFatal ? 1 : 0;
  log.info(`Shutting down gracefully (${signal})`, { exitCode });

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
        process.exit(exitCode);
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

// @audit-fixed: #8 (unhandled exceptions) — the previous handlers logged the crash
// and continued running. Node documents that V8/GC state may be corrupted after an
// uncaught throw, so recovery is unsafe. The new policy:
//   1. Log the error (full stack) via the structured logger.
//   2. Record the crash for the dashboard / auto-disable route gate.
//   3. Start a graceful shutdown (close HTTP, clear intervals, close DB handles).
//   4. Force-exit after a 10s grace period even if graceful shutdown stalls.
//   5. PM2 / systemd is expected to restart us.
// We deliberately do NOT attempt to keep serving requests.
let fatalShuttingDown = false;
function handleFatal(type: 'uncaughtException' | 'unhandledRejection', error: Error): void {
  if (fatalShuttingDown) {
    // A second fatal during shutdown — just log. Do not recurse into shutdown().
    log.error('Additional fatal error during shutdown', {
      type,
      errorName: error.name,
      errorMessage: error.message,
      stack: error.stack,
    });
    return;
  }
  fatalShuttingDown = true;

  const route = currentRequestRoute || 'unknown';
  log.error('FATAL: unrecoverable process error — initiating shutdown', {
    type,
    route,
    errorName: error.name,
    errorMessage: error.message,
    stack: error.stack,
  });

  // Fire-and-forget crash tracking; wrapped so a tracker bug cannot block exit.
  try {
    const entry = recordCrash(route, error, type);
    emitCrashLog(type, route, error);
    try { broadcast('management:crash', entry); } catch { /* ws may already be closing */ }
  } catch (trackingError) {
    log.error('Failed to track fatal crash', {
      trackingError: trackingError instanceof Error ? trackingError.message : String(trackingError),
      originalError: error.message,
    });
  }

  // Belt-and-braces: if the graceful shutdown path hangs for any reason, force-exit.
  // shutdown() already installs its own 10s safety timer, but we add another one here
  // so a bug in shutdown() cannot leave a zombie process behind.
  const forceExit = setTimeout(() => {
    log.error('Forced exit after fatal shutdown timeout (10s)');
    process.exit(1);
  }, 10000);
  // Allow the event loop to exit naturally if everything else finishes cleanly.
  if (typeof forceExit.unref === 'function') forceExit.unref();

  try {
    shutdown(type);
  } catch (shutdownErr) {
    log.error('shutdown() threw during fatal handler', {
      error: shutdownErr instanceof Error ? shutdownErr.message : String(shutdownErr),
    });
    process.exit(1);
  }
}

process.on('uncaughtException', (error) => {
  handleFatal('uncaughtException', error);
});

process.on('unhandledRejection', (reason) => {
  const error = reason instanceof Error ? reason : new Error(String(reason));
  handleFatal('unhandledRejection', error);
});

export { app, server, wss };
