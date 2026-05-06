import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it } from 'vitest';
import settingsRouter from '../settings.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AuthUser } from '../../middleware/auth.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';

function createInlineAsyncDb(db: Database.Database): AsyncDb {
  return {
    dbPath: ':memory:settings-users-permissions',
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

function makeUser(overrides: Partial<AuthUser> = {}): AuthUser {
  return {
    id: 1,
    username: 'admin',
    email: 'admin@example.com',
    first_name: 'Ada',
    last_name: 'Admin',
    role: 'admin',
    permissions: null,
    sessionId: 'settings-test-session',
    customRolePermissions: null,
    permissionOverrides: null,
    ...overrides,
  };
}

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      username TEXT NOT NULL,
      email TEXT,
      first_name TEXT,
      last_name TEXT,
      role TEXT NOT NULL,
      permissions TEXT DEFAULT '{}',
      is_active INTEGER NOT NULL DEFAULT 1,
      password_hash TEXT,
      pin TEXT,
      home_location_id INTEGER,
      updated_at TEXT
    );
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL
    );
	    CREATE TABLE audit_logs (
	      id INTEGER PRIMARY KEY AUTOINCREMENT,
	      event TEXT NOT NULL,
	      user_id INTEGER,
	      ip_address TEXT,
	      details TEXT,
	      created_at TEXT NOT NULL DEFAULT (datetime('now'))
	    );
	    CREATE TABLE store_config (
	      key TEXT PRIMARY KEY,
	      value TEXT NOT NULL
	    );
	    CREATE TABLE locations (
	      id INTEGER PRIMARY KEY,
	      name TEXT NOT NULL,
	      address_line TEXT,
	      city TEXT,
	      state TEXT,
	      postcode TEXT,
	      country TEXT NOT NULL DEFAULT 'US',
	      phone TEXT,
	      email TEXT,
	      timezone TEXT,
	      is_active INTEGER NOT NULL DEFAULT 1
	    );
	    INSERT INTO users (id, username, email, first_name, last_name, role)
	    VALUES (1, 'admin', 'admin@example.com', 'Ada', 'Admin', 'admin'),
	           (2, 'tech', 'tech@example.com', 'Tess', 'Tech', 'technician');
	  `);
  return db;
}

function createApp(db: Database.Database, user: AuthUser = makeUser()): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    req.user = user;
    next();
  });
  app.use('/settings', settingsRouter);
  app.use(errorHandler);
  return app;
}

async function requestJson(
  app: Express,
  path: string,
  options: { method?: string; body?: unknown } = {},
) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: options.method ?? 'GET',
      headers: options.body === undefined ? undefined : { 'content-type': 'application/json' },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
    const text = await response.text();
    return {
      status: response.status,
      body: text ? JSON.parse(text) as any : null,
    };
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

describe('settings user updates', () => {
  it('rejects legacy raw permissions payloads so permission edits use the audited roles route', async () => {
    db = buildDb();
    const app = createApp(db);

    const response = await requestJson(app, '/settings/users/2', {
      method: 'PUT',
      body: {
        first_name: 'Tessa',
        permissions: { 'users.manage': true },
      },
    });

    expect(response.status).toBe(400);
    expect(response.body.message).toBe(
      'permissions are managed through /api/v1/roles/users/:id/permissions',
    );

    const target = db.prepare('SELECT first_name, permissions FROM users WHERE id = 2').get() as {
      first_name: string;
      permissions: string;
    };
    expect(target.first_name).toBe('Tess');
    expect(target.permissions).toBe('{}');
  });
});

describe('settings config location overlay', () => {
  it('uses an existing location row for print contact fields without partitioning store_config', async () => {
    db = buildDb();
    db.exec(`
      INSERT INTO store_config (key, value) VALUES
        ('store_name', 'North Bench'),
        ('store_address', '1 North Rd'),
        ('store_phone', '1115550000'),
        ('store_email', 'north@example.com'),
        ('invoice_footer', 'Global invoice footer');
      INSERT INTO locations
        (id, name, address_line, city, state, postcode, country, phone, email, timezone)
      VALUES
        (2, 'Downtown Repair', '22 Market St', 'Denver', 'CO', '80202', 'US', '2225550000', 'downtown@example.com', 'America/Denver');
    `);
    const app = createApp(db);

    const response = await requestJson(app, '/settings/config?location_id=2');

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      store_name: 'Downtown Repair',
      store_address: '22 Market St, Denver, CO 80202',
      store_phone: '2225550000',
      store_email: 'downtown@example.com',
      store_timezone: 'America/Denver',
      invoice_footer: 'Global invoice footer',
    });
  });

  it('rejects malformed location_id instead of silently falling back to the wrong store', async () => {
    db = buildDb();
    db.prepare('INSERT INTO store_config (key, value) VALUES (?, ?)').run('store_name', 'North Bench');
    const app = createApp(db);

    const response = await requestJson(app, '/settings/config?location_id=abc');

    expect(response.status).toBe(400);
    expect(response.body.message).toBe('location_id must be a positive integer');
  });
});
