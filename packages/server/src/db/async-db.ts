/**
 * Async DB — Express-friendly wrapper around the worker pool.
 * Provides the same interface as better-sqlite3 but async.
 * Attaches as req.asyncDb alongside req.db for gradual migration.
 */
import { dbGet, dbAll, dbRun, dbTransaction } from './worker-pool.js';

interface RunResult {
  changes: number;
  lastInsertRowid: number;
}

export interface AsyncDb {
  /** SELECT single row */
  get<T = unknown>(sql: string, ...params: unknown[]): Promise<T | undefined>;
  /** SELECT multiple rows */
  all<T = unknown>(sql: string, ...params: unknown[]): Promise<T[]>;
  /** INSERT/UPDATE/DELETE */
  run(sql: string, ...params: unknown[]): Promise<RunResult>;
  /** Execute multiple queries atomically */
  transaction(queries: Array<{ sql: string; params?: unknown[] }>): Promise<RunResult[]>;
  /** The DB file path this instance targets */
  readonly dbPath: string;
}

/**
 * Create an AsyncDb instance for a specific database file.
 */
export function createAsyncDb(dbPath: string): AsyncDb {
  return {
    dbPath,
    get<T = unknown>(sql: string, ...params: unknown[]): Promise<T | undefined> {
      return dbGet<T>(dbPath, sql, params.length ? params : undefined);
    },
    all<T = unknown>(sql: string, ...params: unknown[]): Promise<T[]> {
      return dbAll<T>(dbPath, sql, params.length ? params : undefined);
    },
    run(sql: string, ...params: unknown[]): Promise<RunResult> {
      return dbRun(dbPath, sql, params.length ? params : undefined);
    },
    transaction(queries: Array<{ sql: string; params?: unknown[] }>): Promise<RunResult[]> {
      return dbTransaction(dbPath, queries);
    },
  };
}
