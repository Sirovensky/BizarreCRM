import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import { config } from '../config.js';

interface PoolEntry {
  db: Database.Database;
  lastUsed: number;
  lastHealthCheck: number;
}

const HEALTH_CHECK_INTERVAL_MS = 30_000; // Only verify connection health every 30 seconds

const pool = new Map<string, PoolEntry>();
const MAX_POOL_SIZE = 50;

/**
 * Get or open a tenant database connection.
 * Uses an LRU cache to limit open file handles.
 *
 * SECURITY: The slug is validated against the master DB before reaching here.
 * Only slugs that exist in the tenants table are accepted — no user input
 * is used to construct file paths without prior validation.
 */
export function getTenantDb(slug: string): Database.Database {
  // Check cache first
  const now = Date.now();
  const entry = pool.get(slug);
  if (entry) {
    // Periodically verify the cached connection is still usable
    // (DB file may have been deleted or corrupted externally)
    if (now - entry.lastHealthCheck > HEALTH_CHECK_INTERVAL_MS) {
      try {
        entry.db.prepare('SELECT 1').get();
        entry.lastHealthCheck = now;
      } catch {
        // Connection is dead — remove from pool and re-open below
        try { entry.db.close(); } catch {}
        pool.delete(slug);
        // Fall through to re-open
        return getTenantDb(slug);
      }
    }
    entry.lastUsed = now;
    return entry.db;
  }

  // Evict least recently used if at capacity
  // @audit-fixed: LRU eviction previously called .close() inline without a
  // try/catch. If an in-flight request was mid-query on the evicted connection,
  // better-sqlite3 throws synchronously and the exception bubbles up to the
  // request handler for a DIFFERENT tenant, causing a confusing 500. We still
  // close the handle (no other option for LRU), but swallow + log the error so
  // the OPEN for the new tenant is never aborted by an eviction failure.
  if (pool.size >= MAX_POOL_SIZE) {
    let oldestKey: string | null = null;
    let oldestTime = Infinity;
    for (const [key, e] of pool.entries()) {
      if (e.lastUsed < oldestTime) {
        oldestTime = e.lastUsed;
        oldestKey = key;
      }
    }
    if (oldestKey) {
      const evicted = pool.get(oldestKey);
      pool.delete(oldestKey);
      if (evicted) {
        try {
          evicted.db.close();
        } catch (err) {
          console.warn(
            `[tenant-pool] LRU eviction close failed for ${oldestKey}:`,
            err instanceof Error ? err.message : String(err)
          );
        }
      }
    }
  }

  // SECURITY: Validate slug contains only safe characters (alphanumeric + hyphens)
  // This prevents path traversal even though the slug was already validated by the master DB lookup
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug)) {
    throw new Error(`Invalid tenant slug: ${slug}`);
  }

  const dbPath = path.join(config.tenantDataDir, `${slug}.db`);

  // Verify the file exists (provisioning creates it)
  if (!fs.existsSync(dbPath)) {
    throw new Error(`Tenant database not found: ${slug}`);
  }

  // Verify the resolved path is inside tenantDataDir (prevent traversal)
  const resolved = path.resolve(dbPath);
  if (!resolved.startsWith(path.resolve(config.tenantDataDir))) {
    throw new Error(`Path traversal attempt blocked for slug: ${slug}`);
  }

  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('synchronous = NORMAL');
  db.pragma('cache_size = -64000');
  db.pragma('busy_timeout = 5000');

  const openedAt = Date.now();
  pool.set(slug, { db, lastUsed: openedAt, lastHealthCheck: openedAt });
  return db;
}

/**
 * Close a specific tenant's database connection and remove from pool.
 */
export function closeTenantDb(slug: string): void {
  const entry = pool.get(slug);
  if (entry) {
    entry.db.close();
    pool.delete(slug);
  }
}

/**
 * Close all tenant database connections (for graceful shutdown).
 *
 * @audit-fixed: Previously called entry.db.close() without a try/catch, so the
 * first failing close aborted the shutdown loop and left subsequent tenant DBs
 * with open handles (and their WAL files un-checkpointed). Now each close is
 * guarded independently so shutdown always clears the full pool.
 */
export function closeAllTenantDbs(): void {
  for (const [slug, entry] of pool) {
    try {
      entry.db.close();
    } catch (err) {
      console.warn(
        `[tenant-pool] shutdown close failed for ${slug}:`,
        err instanceof Error ? err.message : String(err)
      );
    }
  }
  pool.clear();
}

/**
 * Get pool statistics for monitoring.
 */
export function getPoolStats(): { size: number; maxSize: number; slugs: string[] } {
  return {
    size: pool.size,
    maxSize: MAX_POOL_SIZE,
    slugs: Array.from(pool.keys()),
  };
}
