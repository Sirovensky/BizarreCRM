import Database from 'better-sqlite3';
import path from 'path';
import { config } from '../config.js';
import { getMasterDb } from './master-connection.js';
import { runMigrations } from './migrate.js';
import { buildTemplateDb } from './template.js';

interface MigrationResult {
  succeeded: string[];
  failed: { slug: string; error: string }[];
}

/**
 * Run migrations on all active tenant databases.
 * Also refreshes the template DB so new tenants get the latest schema.
 *
 * Uses SEPARATE database connections (not the tenant pool) to avoid evicting
 * active request connections during bulk migration. Each connection is opened,
 * migrated, and closed immediately.
 *
 * Returns a summary of which tenants succeeded and which failed.
 */
export function migrateAllTenants(): MigrationResult {
  const result: MigrationResult = { succeeded: [], failed: [] };

  if (!config.multiTenant) {
    return result;
  }

  const masterDb = getMasterDb();
  if (!masterDb) {
    return result;
  }

  // Refresh template DB first so it's up to date for any new provisioning
  try {
    buildTemplateDb();
    console.log('[migrate-all] Template DB refreshed');
  } catch (err) {
    console.error('[migrate-all] Failed to refresh template DB:', err);
  }

  // Get all active tenants
  const tenants = masterDb.prepare(
    "SELECT slug, db_path FROM tenants WHERE status = 'active'"
  ).all() as { slug: string; db_path: string }[];

  console.log(`[migrate-all] Running migrations on ${tenants.length} tenant(s)...`);

  for (const tenant of tenants) {
    let migrationDb: Database.Database | null = null;
    try {
      // Open a SEPARATE connection for migration (don't disturb the pool)
      const dbPath = path.join(config.tenantDataDir, tenant.db_path);
      migrationDb = new Database(dbPath);
      migrationDb.pragma('journal_mode = WAL');
      migrationDb.pragma('foreign_keys = ON');
      migrationDb.pragma('busy_timeout = 10000');

      runMigrations(migrationDb);
      result.succeeded.push(tenant.slug);
      console.log(`[migrate-all] ${tenant.slug}: OK`);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      result.failed.push({ slug: tenant.slug, error: message });
      console.error(`[migrate-all] ${tenant.slug}: FAILED - ${message}`);
    } finally {
      // Always close the migration connection
      try { migrationDb?.close(); } catch {}
    }
  }

  console.log(`[migrate-all] Done. ${result.succeeded.length} succeeded, ${result.failed.length} failed.`);
  return result;
}
