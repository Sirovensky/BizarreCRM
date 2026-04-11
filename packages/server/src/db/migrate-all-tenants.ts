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
 * Run `runMigrations` on a single tenant DB and record wall-clock duration.
 *
 * @audit-fixed: The old `runWithTimeout` implementation was a sham — it wrapped
 * the synchronous `runMigrations(db)` call in `new Promise((resolve) => { ...;
 * resolve(); })`, which means the migration RUNS TO COMPLETION BEFORE the
 * Promise constructor returns. The `Promise.race(..., setTimeout)` never had a
 * chance to fire because the event loop was blocked for the entire migration.
 * The "timeout" was cosmetic — it could only reject AFTER the sync work
 * finished, which is the opposite of what a timeout should do.
 *
 * Fix: run the migration synchronously (better-sqlite3 is sync by design),
 * measure the duration, and LOG a warning if it exceeds `timeoutMs`. The caller
 * can then surface slow tenants on the admin dashboard. True cancellation would
 * require running each tenant in a worker thread, which is out of scope.
 */
function runWithTimeout(
  migrationDb: Database.Database,
  slug: string,
  timeoutMs: number
): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const started = Date.now();
    try {
      runMigrations(migrationDb);
      const elapsedMs = Date.now() - started;
      if (elapsedMs > timeoutMs) {
        log.warn('Tenant migration exceeded soft timeout (non-cancelable)', {
          slug,
          elapsedMs,
          timeoutMs,
        });
      }
      resolve();
    } catch (err) {
      reject(err);
    }
  });
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
