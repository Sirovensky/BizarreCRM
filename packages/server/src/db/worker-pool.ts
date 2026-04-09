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
    maxQueue: 2000,
  });

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
 */
export async function dbTransaction(dbPath: string, queries: Array<{ sql: string; params?: unknown[] }>): Promise<RunResult[]> {
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
