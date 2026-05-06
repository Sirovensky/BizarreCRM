import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it } from 'vitest';
import voiceRouter from '../voice.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';
import type { AuthUser } from '../../middleware/auth.js';

function createInlineAsyncDb(db: Database.Database): AsyncDb {
  return {
    dbPath: ':memory:',
    async get<T = unknown>(sql: string, ...params: unknown[]): Promise<T | undefined> {
      return db.prepare(sql).get(...params) as T | undefined;
    },
    async all<T = unknown>(sql: string, ...params: unknown[]): Promise<T[]> {
      return db.prepare(sql).all(...params) as T[];
    },
    async run(sql: string, ...params: unknown[]) {
      const result = db.prepare(sql).run(...params);
      return {
        changes: result.changes,
        lastInsertRowid: Number(result.lastInsertRowid),
      };
    },
    async transaction(queries: TxQuery[]) {
      return db.transaction(() => queries.map((query) => {
        const result = db.prepare(query.sql).run(...(query.params ?? []));
        if (query.expectChanges && result.changes === 0) {
          throw new Error(query.expectChangesError ?? 'Expected changes');
        }
        return {
          changes: result.changes,
          lastInsertRowid: Number(result.lastInsertRowid),
        };
      }))();
    },
  };
}

function makeUser(): AuthUser {
  return {
    id: 7,
    username: 'admin',
    email: 'admin@example.com',
    first_name: 'Ada',
    last_name: 'Admin',
    role: 'admin',
    permissions: null,
    sessionId: 'test-session',
    customRolePermissions: null,
    permissionOverrides: null,
  };
}

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      first_name TEXT NOT NULL DEFAULT '',
      last_name TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE call_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      direction TEXT NOT NULL DEFAULT 'outbound',
      from_number TEXT,
      to_number TEXT,
      conv_phone TEXT,
      provider TEXT,
      provider_call_id TEXT,
      status TEXT NOT NULL DEFAULT 'initiated',
      duration_secs INTEGER,
      recording_url TEXT,
      recording_local_path TEXT,
      transcription TEXT,
      transcription_status TEXT NOT NULL DEFAULT 'none',
      call_mode TEXT NOT NULL DEFAULT 'bridge',
      user_id INTEGER REFERENCES users(id),
      entity_type TEXT,
      entity_id INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    INSERT INTO users (id, first_name, last_name) VALUES (7, 'Ada', 'Admin');
    INSERT INTO call_logs (
      id,
      direction,
      from_number,
      to_number,
      conv_phone,
      provider,
      provider_call_id,
      status,
      duration_secs,
      recording_url,
      recording_local_path,
      transcription,
      transcription_status,
      call_mode,
      user_id,
      entity_type,
      entity_id
    ) VALUES (
      1,
      'outbound',
      '+13035550001',
      '+13035550002',
      '3035550002',
      'twilio',
      'CA_test',
      'completed',
      42,
      'https://api.twilio.com/2010-04-01/Accounts/AC123/Recordings/RE123.mp3',
      '/uploads/recordings/private-call.mp3',
      'Customer approved the repair.',
      'complete',
      'bridge',
      7,
      'ticket',
      11
    );
  `);
  return db;
}

function createApp(db: Database.Database): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    req.user = makeUser();
    next();
  });
  app.use('/voice', voiceRouter);
  app.use(errorHandler);
  return app;
}

async function requestJson(app: Express, path: string) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`);
    const json = await response.json() as any;
    return { status: response.status, json };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  }
}

let db: Database.Database | null = null;

afterEach(() => {
  db?.close();
  db = null;
});

describe('voice call response projection', () => {
  it('keeps recording_url but omits recording_local_path from call history rows', async () => {
    db = buildDb();
    const response = await requestJson(createApp(db), '/voice/calls');

    expect(response.status).toBe(200);
    expect(response.json.data.calls).toHaveLength(1);
    expect(response.json.data.calls[0]).toMatchObject({
      id: 1,
      recording_url: 'https://api.twilio.com/2010-04-01/Accounts/AC123/Recordings/RE123.mp3',
      user_name: 'Ada Admin',
    });
    expect(response.json.data.calls[0]).not.toHaveProperty('recording_local_path');
    expect(JSON.stringify(response.json)).not.toContain('recording_local_path');
  });

  it('keeps recording_url but omits recording_local_path from call details', async () => {
    db = buildDb();
    const response = await requestJson(createApp(db), '/voice/calls/1');

    expect(response.status).toBe(200);
    expect(response.json.data).toMatchObject({
      id: 1,
      recording_url: 'https://api.twilio.com/2010-04-01/Accounts/AC123/Recordings/RE123.mp3',
      transcription: 'Customer approved the repair.',
    });
    expect(response.json.data).not.toHaveProperty('recording_local_path');
    expect(JSON.stringify(response.json)).not.toContain('recording_local_path');
  });
});
