/**
 * DB Worker Thread — Executes SQLite queries in a worker thread.
 * Each worker maintains its own connection cache (one per DB path).
 * Written as .mjs to avoid TypeScript compilation in worker threads.
 */
import Database from 'better-sqlite3';

/** @type {Map<string, import('better-sqlite3').Database>} */
const connections = new Map();

function getConnection(dbPath) {
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
  db.pragma('wal_autocheckpoint = 10000'); // reduce checkpoint frequency (default 1000 pages)
  connections.set(dbPath, db);
  return db;
}

export default function execute(task) {
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
      throw new Error(`Unknown op: ${task.op}`);
  }
}
