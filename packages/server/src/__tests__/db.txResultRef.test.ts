/**
 * BUGHUNT-2026-05-17: cover the cross-statement result-ref path on the db worker.
 *
 * Why the test exists:
 *   Using SQL `last_insert_rowid()` in chained INSERTs is silently broken — each
 *   child INSERT bumps `last_insert_rowid()` to its own rowid, so children[1+]
 *   reference the prior child instead of the parent and the FK rejects the row.
 *   The worker exposes a `{ __txResultRef: 'lastInsertRowid', fromIndex: N }`
 *   marker so callers can substitute the lastInsertRowid of a prior query
 *   without relying on SQL state. This test pins that contract.
 *
 * The worker's `execute` is exercised directly (no Piscina pool) so the test
 * stays a fast unit test.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import os from 'os';

// The worker is .mjs with a sibling .d.mts stub (db-worker.d.mts) so it can
// be imported statically here for direct unit-test coverage of its query
// dispatch + cross-statement result-ref resolution.
import execute from '../db/db-worker.mjs';

describe('db-worker: cross-statement result refs', () => {
  let dbPath: string;
  let setupDb: Database.Database;

  beforeEach(() => {
    // Real on-disk DB so the worker's own connection can open the same file.
    // (The worker maintains its own per-path connection cache.)
    dbPath = path.join(os.tmpdir(), `txresultref-${process.pid}-${Date.now()}.sqlite`);
    setupDb = new Database(dbPath);
    setupDb.pragma('foreign_keys = ON');
    setupDb.exec(`
      CREATE TABLE parent (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      );
      CREATE TABLE child (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER NOT NULL REFERENCES parent(id),
        label     TEXT NOT NULL
      );
    `);
  });

  afterEach(() => {
    try { setupDb.close(); } catch { /* already closed */ }
    try { fs.unlinkSync(dbPath); } catch { /* gone */ }
  });

  // execute() is synchronous (Piscina wraps it in a Promise at the pool level);
  // testing direct, we have to call it as-is and use synchronous matchers.
  it('substitutes lastInsertRowidFrom(0) into every child INSERT', () => {
    execute({
      dbPath,
      op: 'transaction',
      queries: [
        { sql: 'INSERT INTO parent (name) VALUES (?)', params: ['p1'] },
        {
          sql: 'INSERT INTO child (parent_id, label) VALUES (?, ?)',
          params: [{ __txResultRef: 'lastInsertRowid', fromIndex: 0 }, 'a'],
        },
        {
          sql: 'INSERT INTO child (parent_id, label) VALUES (?, ?)',
          params: [{ __txResultRef: 'lastInsertRowid', fromIndex: 0 }, 'b'],
        },
        {
          sql: 'INSERT INTO child (parent_id, label) VALUES (?, ?)',
          params: [{ __txResultRef: 'lastInsertRowid', fromIndex: 0 }, 'c'],
        },
      ],
    });

    const parentId = setupDb.prepare('SELECT id FROM parent').get() as { id: number };
    const children = setupDb.prepare('SELECT parent_id, label FROM child ORDER BY id').all() as Array<{ parent_id: number; label: string }>;

    expect(children).toHaveLength(3);
    for (const c of children) {
      expect(c.parent_id).toBe(parentId.id);
    }
    expect(children.map((c) => c.label)).toEqual(['a', 'b', 'c']);
  });

  it('demonstrates SQL last_insert_rowid() is wrong for chained children (regression guard)', () => {
    // Same shape WITHOUT the marker — uses bare last_insert_rowid() and is
    // expected to fail with FK violation because child[1+] resolve to the
    // prior child's rowid instead of the parent.
    expect(() => {
      execute({
        dbPath,
        op: 'transaction',
        queries: [
          { sql: 'INSERT INTO parent (name) VALUES (?)', params: ['p1'] },
          {
            sql: 'INSERT INTO child (parent_id, label) VALUES (last_insert_rowid(), ?)',
            params: ['a'],
          },
          {
            sql: 'INSERT INTO child (parent_id, label) VALUES (last_insert_rowid(), ?)',
            params: ['b'],
          },
        ],
      });
    }).toThrow(/FOREIGN KEY/i);

    // Whole tx rolled back — no parent or child rows leaked.
    const parentCount = setupDb.prepare('SELECT COUNT(*) AS c FROM parent').get() as { c: number };
    expect(parentCount.c).toBe(0);
  });

  it('rejects an out-of-range fromIndex', () => {
    expect(() => {
      execute({
        dbPath,
        op: 'transaction',
        queries: [
          { sql: 'INSERT INTO parent (name) VALUES (?)', params: ['p1'] },
          {
            sql: 'INSERT INTO child (parent_id, label) VALUES (?, ?)',
            // fromIndex points at a query that doesn't exist yet — must throw.
            params: [{ __txResultRef: 'lastInsertRowid', fromIndex: 5 }, 'oops'],
          },
        ],
      });
    }).toThrow(/fromIndex/i);

    // The whole tx rolled back — parent insert must not persist.
    const parentCount = setupDb.prepare('SELECT COUNT(*) AS c FROM parent').get() as { c: number };
    expect(parentCount.c).toBe(0);
  });
});
