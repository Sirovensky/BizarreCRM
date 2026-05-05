/**
 * DB Worker Thread — Executes SQLite queries in a worker thread.
 * Each worker maintains its own connection cache (one per DB path).
 * Written as .mjs to avoid TypeScript compilation in worker threads.
 *
 * @audit-fixed (#11): The cache was an unbounded Map<string, Database>, so with
 * 500+ tenants × 8 workers the per-worker file-handle count grew without limit
 * and hit Windows per-process handle ceilings. It is now an LRU cache capped at
 * MAX_CACHED_DBS entries per worker — oldest connections are evicted and closed
 * when the cap is reached. Map insertion-order iteration gives us LRU for free:
 * every access deletes + re-inserts to move the entry to the newest position,
 * so `cache.keys().next().value` is always the oldest.
 */
import Database from 'better-sqlite3';

/**
 * Per-worker LRU cap. With Piscina defaulting to (cpus-1) workers, typical
 * worst-case is ~8 workers × 64 = 512 open handles total across the process,
 * well under Windows limits. Bumping this is safe if a deployment has fewer
 * workers but many tenants.
 */
const MAX_CACHED_DBS = 64;

/** @type {Map<string, import('better-sqlite3').Database>} */
const cache = new Map();

/**
 * Open a fresh better-sqlite3 handle with all the tuned pragmas.
 * Factored out so getConnection() stays focused on cache bookkeeping.
 * @param {string} dbPath
 * @returns {import('better-sqlite3').Database}
 */
function openDb(dbPath) {
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('synchronous = NORMAL');
  db.pragma('cache_size = -64000');
  db.pragma('busy_timeout = 5000');
  db.pragma('mmap_size = 268435456');
  db.pragma('temp_store = MEMORY');
  db.pragma('wal_autocheckpoint = 10000'); // reduce checkpoint frequency (default 1000 pages)
  return db;
}

/**
 * LRU accessor. On hit, moves the entry to the newest position. On miss,
 * evicts the oldest entry (closing its DB handle) if the cache is at cap,
 * then opens a fresh connection.
 * @param {string} dbPath
 * @returns {import('better-sqlite3').Database}
 */
function getConnection(dbPath) {
  const existing = cache.get(dbPath);
  if (existing) {
    // Move to most-recently-used position by re-inserting
    cache.delete(dbPath);
    cache.set(dbPath, existing);
    return existing;
  }

  if (cache.size >= MAX_CACHED_DBS) {
    // Evict oldest (first-inserted / least-recently-used)
    const oldestKey = cache.keys().next().value;
    if (oldestKey !== undefined) {
      const oldest = cache.get(oldestKey);
      cache.delete(oldestKey);
      if (oldest) {
        try {
          oldest.close();
        } catch (err) {
          // Swallow close errors so eviction never aborts the OPEN for a new
          // tenant. Log to stderr for observability.
          const msg = err instanceof Error ? err.message : String(err);
          console.warn(`[db-worker] LRU eviction close failed for ${oldestKey}: ${msg}`);
        }
      }
    }
  }

  const db = openDb(dbPath);
  cache.set(dbPath, db);
  return db;
}

/**
 * Close every cached connection on worker shutdown so WAL files checkpoint
 * cleanly and we don't leak handles.
 */
process.on('exit', () => {
  for (const [dbPath, db] of cache) {
    try {
      db.close();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn(`[db-worker] shutdown close failed for ${dbPath}: ${msg}`);
    }
  }
  cache.clear();
});

// SCAN-1064: allow-list + shape checks on the Piscina task payload. Without
// them a malformed worker message reaches `db.prepare(undefined)` and throws
// an opaque better-sqlite3 error; explicit validation gives us a clean
// E_BAD_TASK error the caller can map to a 500 without ambiguity.
const KNOWN_OPS = new Set(['get', 'all', 'run', 'transaction']);
function assertTask(task) {
  if (!task || typeof task !== 'object') {
    throw Object.assign(new Error('db-worker: task must be an object'), { code: 'E_BAD_TASK' });
  }
  if (typeof task.dbPath !== 'string' || task.dbPath.length === 0) {
    throw Object.assign(new Error('db-worker: task.dbPath must be a non-empty string'), { code: 'E_BAD_TASK' });
  }
  if (typeof task.op !== 'string' || !KNOWN_OPS.has(task.op)) {
    throw Object.assign(new Error(`db-worker: unknown op: ${String(task.op)}`), { code: 'E_BAD_TASK' });
  }
  if (task.op === 'transaction') {
    if (!Array.isArray(task.queries)) {
      throw Object.assign(new Error('db-worker: transaction requires queries array'), { code: 'E_BAD_TASK' });
    }
    for (const q of task.queries) {
      if (!q || typeof q.sql !== 'string') {
        throw Object.assign(new Error('db-worker: transaction query.sql must be a string'), { code: 'E_BAD_TASK' });
      }
    }
  } else {
    if (typeof task.sql !== 'string' || task.sql.length === 0) {
      throw Object.assign(new Error('db-worker: task.sql must be a non-empty string'), { code: 'E_BAD_TASK' });
    }
  }
}

export default function execute(task) {
  assertTask(task);
  const db = getConnection(task.dbPath);

  switch (task.op) {
    case 'get': {
      const stmt = db.prepare(task.sql);
      return task.params?.length ? stmt.get(...task.params) : stmt.get();
    }
    case 'all': {
      const stmt = db.prepare(task.sql);
      return task.params?.length ? stmt.all(...task.params) : stmt.all();
    }
    case 'run': {
      const stmt = db.prepare(task.sql);
      const result = task.params?.length ? stmt.run(...task.params) : stmt.run();
      return { changes: result.changes, lastInsertRowid: Number(result.lastInsertRowid) };
    }
    case 'transaction': {
      if (!task.queries?.length) return [];
      const results = [];
      const txn = db.transaction(() => {
        for (const q of task.queries) {
          const stmt = db.prepare(q.sql);
          const result = q.params?.length ? stmt.run(...q.params) : stmt.run();
          // Guarded UPDATE / DELETE: if expectChanges is set and the query
          // touched fewer rows than expected (e.g. WHERE in_stock >= ? failed
          // because stock dropped between the precheck and the transaction),
          // throw so the better-sqlite3 transaction rolls back all prior
          // inserts. The error is tagged so the caller can map it to a 409.
          if (q.expectChanges && result.changes === 0) {
            const err = new Error(q.expectChangesError || 'Guarded update failed — row no longer matches condition');
            err.code = 'E_EXPECT_CHANGES';
            throw err;
          }
          results.push({ changes: result.changes, lastInsertRowid: Number(result.lastInsertRowid) });
        }
      });
      txn();
      return results;
    }
    default:
      // Unreachable — assertTask already rejects unknown ops — but keep for
      // exhaustiveness.
      throw Object.assign(new Error(`db-worker: unknown op: ${task.op}`), { code: 'E_BAD_TASK' });
  }
}
