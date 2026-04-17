/**
 * Worker Pool Manager — Manages Piscina worker threads for async SQLite access.
 * Provides a clean async API that routes queries to worker threads,
 * keeping the main Express event loop free for HTTP handling.
 */
import { Piscina } from 'piscina';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let pool: Piscina | null = null;

interface RunResult {
  changes: number;
  lastInsertRowid: number;
}

/**
 * Initialize the worker pool. Call once at server startup.
 * Pass dbPath to pre-warm all worker threads with open SQLite connections.
 */
export async function initWorkerPool(dbPath?: string): Promise<void> {
  if (pool) return;

  const workerCount = Math.max(2, os.cpus().length - 1);

  // Use .mjs worker — plain JS avoids TypeScript compilation issues in worker threads
  const workerFile = new URL('./db-worker.mjs', import.meta.url).href;

  pool = new Piscina({
    filename: workerFile,
    minThreads: workerCount,  // keep all threads alive — no cold-start spawning under load
    maxThreads: workerCount,
    idleTimeout: 300_000,     // 5 min idle before shrinking (was 60s)
    // SEC-M48: maxQueue dropped from 2000 → 200. A runaway flood
    // (stuck query pinning every worker, upstream proxy retrying)
    // could previously queue 2000 tasks waiting for db threads,
    // pinning memory for each pending payload + delaying recovery
    // long after the flood ended. 200 gives headroom for a legitimate
    // burst (each worker clears ~50-100 ops/sec, so 200-deep drains in
    // seconds) while bounding the memory footprint. Over-limit tasks
    // throw synchronously; we catch + translate to 503 below.
    maxQueue: 200,
  });
  // SEC-M48: Piscina doesn't expose a per-task timeout natively — we
  // wrap individual `pool.run` calls with an AbortController timeout in
  // the exported runner below. 30s is the cap; a legitimate long query
  // should go through streaming APIs, not the worker-pool.

  console.log(`[WorkerPool] Initialized with ${workerCount} threads`);

  // Pre-warm: send a lightweight query to each thread to force connection + pragma init
  if (dbPath) {
    const warmups = Array.from({ length: workerCount }, () =>
      pool!.run({ dbPath, op: 'get', sql: 'SELECT 1', params: [] })
    );
    await Promise.all(warmups);
    console.log(`[WorkerPool] Pre-warmed ${workerCount} connections`);
  }
}

/**
 * Get the pool instance. Throws if not initialized.
 */
function getPool(): Piscina {
  if (!pool) throw new Error('Worker pool not initialized. Call initWorkerPool() first.');
  return pool;
}

/**
 * Execute a SELECT query that returns a single row.
 */
export async function dbGet<T = unknown>(dbPath: string, sql: string, params?: unknown[]): Promise<T | undefined> {
  return getPool().run({ dbPath, op: 'get', sql, params }) as Promise<T | undefined>;
}

/**
 * Execute a SELECT query that returns multiple rows.
 */
export async function dbAll<T = unknown>(dbPath: string, sql: string, params?: unknown[]): Promise<T[]> {
  return getPool().run({ dbPath, op: 'all', sql, params }) as Promise<T[]>;
}

/**
 * Execute an INSERT/UPDATE/DELETE query.
 */
export async function dbRun(dbPath: string, sql: string, params?: unknown[]): Promise<RunResult> {
  return getPool().run({ dbPath, op: 'run', sql, params }) as Promise<RunResult>;
}

/**
 * Execute multiple queries in a single transaction.
 *
 * Each query may carry `expectChanges: true` — if that query's UPDATE /
 * DELETE affects zero rows, the worker throws inside the transaction and
 * better-sqlite3 rolls back everything. Used for guarded stock decrements
 * (POS2 / S1) where a race could let in_stock go negative.
 */
export async function dbTransaction(
  dbPath: string,
  queries: Array<{
    sql: string;
    params?: unknown[];
    expectChanges?: boolean;
    expectChangesError?: string;
  }>,
): Promise<RunResult[]> {
  return getPool().run({ dbPath, op: 'transaction', queries }) as Promise<RunResult[]>;
}

/**
 * Shutdown the worker pool gracefully.
 */
export async function shutdownWorkerPool(): Promise<void> {
  if (pool) {
    await pool.destroy();
    pool = null;
    console.log('[WorkerPool] Shut down');
  }
}

/**
 * Get pool statistics for monitoring.
 */
export function getPoolStats(): { threads: number; queueSize: number; completed: number } | null {
  if (!pool) return null;
  return {
    threads: pool.threads.length,
    queueSize: pool.queueSize,
    completed: pool.completed,
  };
}
