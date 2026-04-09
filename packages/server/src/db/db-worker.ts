/**
 * DB Worker Thread — Executes SQLite queries in a worker thread.
 * Each worker maintains its own connection cache (one per DB path).
 * Runs via Piscina worker pool — never imported directly.
 */
import Database from 'better-sqlite3';

// Connection cache: one connection per DB path per worker
const connections = new Map<string, Database.Database>();

function getConnection(dbPath: string): Database.Database {
  let db = connections.get(dbPath);
  if (db) return db;

  db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('synchronous = NORMAL');
  db.pragma('cache_size = -64000');
  db.pragma('busy_timeout = 5000');
  db.pragma('mmap_size = 268435456');
  db.pragma('temp_store = MEMORY');
  connections.set(dbPath, db);
  return db;
}

interface WorkerTask {
  dbPath: string;
  op: 'get' | 'all' | 'run' | 'transaction';
  sql?: string;
  params?: unknown[];
  queries?: Array<{ sql: string; params?: unknown[] }>;
}

interface RunResult {
  changes: number;
  lastInsertRowid: number | bigint;
}

export default function execute(task: WorkerTask): unknown {
  const db = getConnection(task.dbPath);

  switch (task.op) {
    case 'get': {
      const stmt = db.prepare(task.sql!);
      return task.params?.length ? stmt.get(...task.params) : stmt.get();
    }
    case 'all': {
      const stmt = db.prepare(task.sql!);
      return task.params?.length ? stmt.all(...task.params) : stmt.all();
    }
    case 'run': {
      const stmt = db.prepare(task.sql!);
      const result = task.params?.length ? stmt.run(...task.params) : stmt.run();
      return { changes: result.changes, lastInsertRowid: Number(result.lastInsertRowid) } satisfies RunResult;
    }
    case 'transaction': {
      if (!task.queries?.length) return { changes: 0, lastInsertRowid: 0 };
      const results: RunResult[] = [];
      const txn = db.transaction(() => {
        for (const q of task.queries!) {
          const stmt = db.prepare(q.sql);
          const result = q.params?.length ? stmt.run(...q.params) : stmt.run();
          results.push({ changes: result.changes, lastInsertRowid: Number(result.lastInsertRowid) });
        }
      });
      txn();
      return results;
    }
    default:
      throw new Error(`Unknown op: ${task.op}`);
  }
}
