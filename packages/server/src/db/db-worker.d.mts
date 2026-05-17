/**
 * Type stub for db-worker.mjs (Piscina worker entry point).
 * The runtime implementation lives in db-worker.mjs and is loaded by Piscina
 * via `new URL('./db-worker.mjs', import.meta.url)`. This stub exists so the
 * worker can also be imported statically in tests for direct exercise.
 */
export interface DbWorkerTask {
  dbPath: string;
  op: 'get' | 'all' | 'run' | 'transaction';
  sql?: string;
  params?: unknown[];
  queries?: Array<{
    sql: string;
    params?: unknown[];
    expectChanges?: boolean;
    expectChangesError?: string;
  }>;
}

declare function execute(task: DbWorkerTask): unknown;
export default execute;
