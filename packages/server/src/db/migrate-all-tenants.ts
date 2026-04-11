import Database from 'better-sqlite3';
import path from 'path';
import { config } from '../config.js';
import { getMasterDb } from './master-connection.js';
import { runMigrations } from './migrate.js';
import { buildTemplateDb } from './template.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('migrate-all-tenants');

interface FailedTenant {
  slug: string;
  error: string;
}

interface MigrationResult {
  succeeded: string[];
  failed: FailedTenant[];
}

/** Default per-tenant migration timeout (30 seconds). */
const DEFAULT_TENANT_MIGRATION_TIMEOUT_MS = 30_000;

/**
 * Resolve the per-tenant migration timeout from env (TENANT_MIGRATION_TIMEOUT_MS)
 * falling back to DEFAULT_TENANT_MIGRATION_TIMEOUT_MS. Invalid values fall back
 * to the default rather than throwing so startup is never blocked by a typo.
 */
function getTimeoutMs(): number {
  const raw = process.env.TENANT_MIGRATION_TIMEOUT_MS;
  if (!raw) return DEFAULT_TENANT_MIGRATION_TIMEOUT_MS;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    log.warn('Invalid TENANT_MIGRATION_TIMEOUT_MS, using default', {
      value: raw,
      default: DEFAULT_TENANT_MIGRATION_TIMEOUT_MS,
    });
    return DEFAULT_TENANT_MIGRATION_TIMEOUT_MS;
  }
  return parsed;
}

/**
 * Ensure the failed_tenants tracking table exists in the master DB. Created
 * inline here (not in a migration) so this module remains self-contained and
 * the dashboard always has a place to read recent failures from.
 */
function ensureFailedTenantsTable(masterDb: Database.Database): void {
  masterDb.exec(`
    CREATE TABLE IF NOT EXISTS failed_tenants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      slug TEXT NOT NULL,
      error TEXT NOT NULL,
      failed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_failed_tenants_slug ON failed_tenants(slug);
    CREATE INDEX IF NOT EXISTS idx_failed_tenants_failed_at ON failed_tenants(failed_at);
  `);
}

/**
 * Record a failed migration in the master DB so the admin dashboard can
 * surface it as a CRITICAL ISSUE. Failures to record are logged but never
 * thrown — recording must not itself break startup.
 */
function recordFailure(masterDb: Database.Database, slug: string, error: string): void {
  try {
    masterDb
      .prepare('INSERT INTO failed_tenants (slug, error) VALUES (?, ?)')
      .run(slug, error);
  } catch (err) {
    log.error('Failed to record tenant failure in master DB', {
      slug,
      recordError: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Run `runMigrations` on a single tenant DB with a hard timeout. Because
 * better-sqlite3 is synchronous, we can't truly cancel the work — but we CAN
 * race a timer against it so a hung or infinitely-looping migration doesn't
 * block startup forever. The migration keeps running in the background and
 * the connection is closed in the outer finally.
 */
function runWithTimeout(
  migrationDb: Database.Database,
  slug: string,
  timeoutMs: number
): Promise<void> {
  const migrationPromise = new Promise<void>((resolve, reject) => {
    try {
      runMigrations(migrationDb);
      resolve();
    } catch (err) {
      reject(err);
    }
  });

  const timeoutPromise = new Promise<void>((_, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`Migration timed out after ${timeoutMs}ms for tenant ${slug}`));
    }, timeoutMs);
    // Allow the process to exit if only this timer is left
    if (typeof timer.unref === 'function') timer.unref();
  });

  return Promise.race([migrationPromise, timeoutPromise]);
}

/**
 * Migrate a single tenant. Opens a fresh connection (separate from the pool),
 * runs migrations with a timeout, and always closes. Errors are caught and
 * returned so the outer loop can continue to the next tenant.
 */
async function migrateOneTenant(
  slug: string,
  dbPath: string,
  timeoutMs: number
): Promise<void> {
  let migrationDb: Database.Database | null = null;
  try {
    migrationDb = new Database(dbPath);
    migrationDb.pragma('journal_mode = WAL');
    migrationDb.pragma('foreign_keys = ON');
    migrationDb.pragma('busy_timeout = 10000');

    await runWithTimeout(migrationDb, slug, timeoutMs);
  } finally {
    try {
      migrationDb?.close();
    } catch {
      // swallow close errors — connection may already be invalid
    }
  }
}

/**
 * Run migrations on all active tenant databases.
 * Also refreshes the template DB so new tenants get the latest schema.
 *
 * Uses SEPARATE database connections (not the tenant pool) to avoid evicting
 * active request connections during bulk migration. Each connection is opened,
 * migrated, and closed immediately.
 *
 * Per-tenant timeout (default 30s, override via TENANT_MIGRATION_TIMEOUT_MS)
 * prevents one corrupt or slow tenant from blocking server startup. Failed
 * tenants are logged, recorded to the master DB's `failed_tenants` table, and
 * skipped — the server will still come up and serve healthy tenants.
 *
 * Returns a summary of which tenants succeeded and which failed.
 */
export async function migrateAllTenants(): Promise<MigrationResult> {
  const result: MigrationResult = { succeeded: [], failed: [] };

  if (!config.multiTenant) {
    return result;
  }

  const masterDb = getMasterDb();
  if (!masterDb) {
    return result;
  }

  // Make sure the failures table exists before we might write to it
  try {
    ensureFailedTenantsTable(masterDb);
  } catch (err) {
    log.error('Failed to ensure failed_tenants table', {
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // Refresh template DB first so it's up to date for any new provisioning
  try {
    buildTemplateDb();
    log.info('Template DB refreshed');
  } catch (err) {
    log.error('Failed to refresh template DB', {
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // Get all active tenants
  const tenants = masterDb
    .prepare("SELECT slug, db_path FROM tenants WHERE status = 'active'")
    .all() as { slug: string; db_path: string }[];

  const timeoutMs = getTimeoutMs();
  log.info('Running migrations on tenants', {
    count: tenants.length,
    perTenantTimeoutMs: timeoutMs,
  });

  for (const tenant of tenants) {
    const dbPath = path.join(config.tenantDataDir, tenant.db_path);
    try {
      await migrateOneTenant(tenant.slug, dbPath, timeoutMs);
      result.succeeded.push(tenant.slug);
      log.info('Tenant migration succeeded', { slug: tenant.slug });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      result.failed.push({ slug: tenant.slug, error: message });
      log.error('Tenant migration failed — skipping', {
        slug: tenant.slug,
        error: message,
      });
      recordFailure(masterDb, tenant.slug, message);
      // Intentionally continue to next tenant — do NOT throw
    }
  }

  log.info('Tenant migrations complete', {
    succeeded: result.succeeded.length,
    failed: result.failed.length,
    failedSlugs: result.failed.map((f) => f.slug),
  });

  return result;
}
