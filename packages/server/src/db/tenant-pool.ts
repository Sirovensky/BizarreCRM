import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import { config } from '../config.js';

interface PoolEntry {
  db: Database.Database;
  lastUsed: number;
  lastHealthCheck: number;
  refcount: number; // how many in-flight requests hold this handle
}

const HEALTH_CHECK_INTERVAL_MS = 30_000; // Only verify connection health every 30 seconds

// MAX_POOL_SIZE: maximum number of tenant DB handles kept open at idle.
// 50 is a reasonable default for a single-process repair-shop host:
//   50 handles × 16 MiB page-cache = 800 MiB worst-case RSS (set in SEC-M30).
// Override with TENANT_MAX_POOL_SIZE env var if you host more tenants.
const MAX_POOL_SIZE: number = Number(process.env['TENANT_MAX_POOL_SIZE'] ?? 50);

const pool = new Map<string, PoolEntry>();

// refcounts shadows pool's own refcount field but lives separately so
// evict-on-release can check it without reading a deleted PoolEntry.
// Invariant: refcounts.get(slug) === pool.get(slug)?.refcount for every slug
// in the pool, and refcounts entries are removed when a handle is closed.
const refcounts = new Map<string, number>();

// ─── per-slug serialization mutex ────────────────────────────────────────────
//
// SCAN-898 / SCAN-902: Without serialization, two concurrent callers for the
// same slug can both see a stale/missing pool entry and both open a new handle,
// OR both see pool.size === MAX_POOL_SIZE-1 and both skip eviction, driving the
// pool to MAX_POOL_SIZE+1.  A per-slug promise chain makes open+health-check+
// insert atomic with respect to other callers for the same slug.
//
// Node.js is single-threaded, so "concurrent" here means two async callers
// that both reach getTenantDb before either has inserted into the pool (e.g.
// two overlapping cron ticks, WS + HTTP arriving in the same turn, etc.).

const slugLocks = new Map<string, Promise<void>>();

function withSlugLock<T>(slug: string, fn: () => Promise<T>): Promise<T> {
  const prev = slugLocks.get(slug) ?? Promise.resolve();
  let release!: () => void;
  const next = new Promise<void>((r) => { release = r; });
  // Chain: next turn waits for prev to settle before fn() runs.
  slugLocks.set(slug, prev.then(() => next));
  return prev.then(async () => {
    try {
      return await fn();
    } finally {
      release();
      // Remove the chain tail once this lock is released so the Map doesn't grow unbounded.
      if (slugLocks.get(slug) === next) slugLocks.delete(slug);
    }
  });
}

// ─── internal helpers ─────────────────────────────────────────────────────────

function openDb(slug: string): Database.Database {
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
  // SEC-M30: 16 MiB page-cache per handle; full-pool ceiling ≈ 800 MiB.
  db.pragma('cache_size = -16000');
  // SEC-M50: 5 s busy_timeout lets cron writers serialize without failing.
  db.pragma('busy_timeout = 5000');
  return db;
}

function closeEntry(slug: string, entry: PoolEntry): void {
  try {
    entry.db.close();
  } catch (err) {
    console.warn(
      `[tenant-pool] close failed for ${slug}:`,
      err instanceof Error ? err.message : String(err)
    );
  }
  pool.delete(slug);
  refcounts.delete(slug);
}

/**
 * Evict the least-recently-used handle whose refcount === 0.
 * Returns true if an eviction occurred, false if every handle is in use.
 */
function evictLRU(): boolean {
  let oldestKey: string | null = null;
  let oldestTime = Infinity;

  for (const [key, e] of pool.entries()) {
    // REFCOUNT INVARIANT: never evict a handle that is in use
    if (e.refcount > 0) continue;
    if (e.lastUsed < oldestTime) {
      oldestTime = e.lastUsed;
      oldestKey = key;
    }
  }

  if (oldestKey === null) return false;

  const evicted = pool.get(oldestKey);
  if (evicted) closeEntry(oldestKey, evicted);
  return true;
}

// ─── public API ───────────────────────────────────────────────────────────────

/**
 * Acquire a tenant database connection.
 *
 * Callers MUST call releaseTenantDb(slug) when the request/operation
 * finishes, or the handle will never be eligible for LRU eviction.
 *
 * SECURITY: The slug is validated against the master DB before reaching here.
 * Only slugs that exist in the tenants table are accepted — no user input
 * is used to construct file paths without prior validation.
 *
 * DoS / pool-exhaustion policy (SEC-H124):
 *   If pool is at MAX_POOL_SIZE and every handle has refcount > 0 (all in
 *   use), we cannot evict.  We open an extra handle, log a warning, and
 *   evict it on release (evict-on-release path in releaseTenantDb).
 *   This prevents a slow-request flood from starving new tenants while
 *   still bounding steady-state memory.
 *
 * CALLER CONTRACT: always pair getTenantDb() with releaseTenantDb() in a
 * try/finally block.  Failure to release leaks the refcount and prevents
 * LRU eviction of that handle.  Node's FinalizationRegistry is NOT used
 * here because it fires non-deterministically; caller-side try/finally is
 * the only guarantee.
 *
 * SCAN-898 / SCAN-902 / SCAN-906: The open+health-check+insert path is
 * serialized per slug via withSlugLock() so two concurrent callers cannot
 * both open a new handle or both skip the eviction step.
 */
export function getTenantDb(slug: string): Promise<Database.Database> {
  return withSlugLock(slug, async () => {
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
          // Connection is dead — remove from pool and re-open below.
          // SCAN-898: recursive call is now safe; withSlugLock serializes
          // concurrent openers so only one reaches openDb() at a time.
          closeEntry(slug, entry);
          // Fall through to open a fresh handle (no recursive call needed;
          // the pool entry was just deleted so the code below will open it).
        }
      }
      // Re-read after potential closeEntry above.
      const current = pool.get(slug);
      if (current) {
        current.lastUsed = now;
        current.refcount += 1;
        refcounts.set(slug, current.refcount);
        return current.db;
      }
    }

    // Pool is at capacity — try to evict an idle handle first.
    // SCAN-902: this check+evict+insert is now atomic per slug because we
    // are inside withSlugLock; no second concurrent caller for this slug
    // can reach this point until we return.
    if (pool.size >= MAX_POOL_SIZE) {
      const evicted = evictLRU();
      if (!evicted) {
        // All handles are in use (refcount > 0). Open an extra handle and
        // mark it for immediate evict-on-release so it doesn't permanently
        // bloat the pool.
        console.warn(
          `[tenant-pool] pool exhausted (${pool.size}/${MAX_POOL_SIZE}, all in use) — ` +
          `opening extra handle for ${slug}; will close on release. ` +
          'Consider raising TENANT_MAX_POOL_SIZE if this is frequent.'
        );
        const db = openDb(slug);
        const overflowEntry: PoolEntry = { db, lastUsed: now, lastHealthCheck: now, refcount: 1 };
        pool.set(slug, overflowEntry);
        refcounts.set(slug, 1);
        return db;
      }
    }

    const db = openDb(slug);
    const newEntry: PoolEntry = { db, lastUsed: now, lastHealthCheck: now, refcount: 1 };
    pool.set(slug, newEntry);
    refcounts.set(slug, 1);
    return db;
  });
}

/**
 * Release a tenant database connection acquired via getTenantDb().
 *
 * Decrements the refcount. If the pool is over MAX_POOL_SIZE (overflow
 * handle) and this was the last reference, the handle is closed immediately
 * instead of being kept for the next request.
 */
export function releaseTenantDb(slug: string): void {
  const entry = pool.get(slug);
  if (!entry) return; // already evicted (e.g. closeTenantDb was called directly)

  entry.refcount = Math.max(0, entry.refcount - 1);
  refcounts.set(slug, entry.refcount);

  // Evict-on-release: if pool is over capacity and this handle is now idle,
  // close it immediately to bring the pool back to steady state.
  if (entry.refcount === 0 && pool.size > MAX_POOL_SIZE) {
    console.warn(`[tenant-pool] evict-on-release for ${slug} (pool size ${pool.size})`);
    closeEntry(slug, entry);
  }
}

/**
 * Close a specific tenant's database connection and remove from pool.
 * Prefer releaseTenantDb() for normal request teardown.
 */
export function closeTenantDb(slug: string): void {
  const entry = pool.get(slug);
  if (entry) {
    closeEntry(slug, entry);
  }
}

/**
 * Close all tenant database connections (for graceful shutdown).
 *
 * @audit-fixed: Each close is guarded independently so shutdown always
 * clears the full pool even if one close throws.
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
  refcounts.clear();
}

/**
 * Get pool statistics for monitoring.
 */
export function getPoolStats(): {
  size: number;
  maxSize: number;
  slugs: string[];
  inUse: number;
} {
  let inUse = 0;
  for (const e of pool.values()) {
    if (e.refcount > 0) inUse++;
  }
  return {
    size: pool.size,
    maxSize: MAX_POOL_SIZE,
    slugs: Array.from(pool.keys()),
    inUse,
  };
}
