import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it } from 'vitest';
import { PERMISSIONS } from '@bizarre-crm/shared';
import rolesRouter from '../roles.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AuthUser } from '../../middleware/auth.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';

let dbCounter = 0;

function createInlineAsyncDb(db: Database.Database): AsyncDb {
  const dbPath = `:memory:roles-permissions-${++dbCounter}`;
  return {
    dbPath,
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
    sessionId: 'test-session',
    customRolePermissions: null,
    permissionOverrides: null,
    ...overrides,
  };
}

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    PRAGMA foreign_keys = ON;

    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      username TEXT NOT NULL,
      email TEXT NOT NULL,
      first_name TEXT NOT NULL DEFAULT '',
      last_name TEXT NOT NULL DEFAULT '',
      role TEXT NOT NULL,
      permissions TEXT DEFAULT '{}',
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE custom_roles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE role_permissions (
      role_id INTEGER NOT NULL,
      permission_key TEXT NOT NULL,
      allowed INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (role_id, permission_key)
    );
    CREATE TABLE user_custom_roles (
      user_id INTEGER PRIMARY KEY,
      role_id INTEGER NOT NULL
    );
    CREATE TABLE user_permissions (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      permission_key TEXT NOT NULL,
      allowed INTEGER NOT NULL CHECK (allowed IN (0, 1)),
      updated_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (user_id, permission_key)
    );
    CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event TEXT NOT NULL,
      user_id INTEGER,
      ip_address TEXT,
      details TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    INSERT INTO users (id, username, email, first_name, last_name, role, permissions) VALUES
      (1, 'admin', 'admin@example.com', 'Ada', 'Admin', 'admin', '{}'),
      (2, 'manager', 'manager@example.com', 'Mina', 'Manager', 'manager', '{}'),
      (3, 'limited-admin', 'limited@example.com', 'Lee', 'Limited', 'admin', '{}');

    INSERT INTO custom_roles (id, name, description, is_active) VALUES
      (1, 'admin', 'Full administrative access', 1),
      (2, 'limited_ops', 'Limited operator role', 1);

    INSERT INTO role_permissions (role_id, permission_key, allowed) VALUES
      (2, '${PERMISSIONS.TICKETS_VIEW}', 1),
      (2, '${PERMISSIONS.CUSTOMERS_VIEW}', 1),
      (2, '${PERMISSIONS.USERS_MANAGE}', 0);

    INSERT INTO user_custom_roles (user_id, role_id) VALUES (3, 2);

    INSERT INTO user_permissions (user_id, permission_key, allowed, updated_by_user_id) VALUES
      (3, '${PERMISSIONS.INVOICES_VOID}', 1, 1),
      (3, '${PERMISSIONS.CUSTOMERS_VIEW}', 0, 1);
  `);
  return db;
}

function createApp(db: Database.Database, user: AuthUser): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    req.user = user;
    next();
  });
  app.use('/roles', rolesRouter);
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

describe('user permission override routes', () => {
  it('reports layered effective permissions for custom roles plus user overrides', async () => {
    db = buildDb();
    const app = createApp(db, makeUser());

    const response = await requestJson(app, '/roles/users/3/permissions');

    expect(response.status).toBe(200);
    const effective = new Map(
      response.body.data.effective.map((entry: { key: string; allowed: boolean; source: string }) => [entry.key, entry]),
    );
    expect(effective.get(PERMISSIONS.TICKETS_VIEW)).toMatchObject({
      allowed: true,
      source: 'custom_role',
    });
    expect(effective.get(PERMISSIONS.CUSTOMERS_VIEW)).toMatchObject({
      allowed: false,
      source: 'user_deny',
    });
    expect(effective.get(PERMISSIONS.INVOICES_VOID)).toMatchObject({
      allowed: true,
      source: 'user_grant',
    });
    expect(effective.get(PERMISSIONS.USERS_MANAGE)).toMatchObject({
      allowed: false,
      source: 'none',
    });
  });

  it('lets a non-admin with an explicit users.manage grant update and clear user overrides', async () => {
    db = buildDb();
    const manager = makeUser({
      id: 2,
      username: 'manager',
      role: 'manager',
      permissionOverrides: new Map([[PERMISSIONS.USERS_MANAGE, true]]),
    });
    const app = createApp(db, manager);

    const update = await requestJson(app, '/roles/users/2/permissions', {
      method: 'PUT',
      body: {
        updates: [
          { key: PERMISSIONS.IMPORT_EXPORT, allowed: true },
          { key: PERMISSIONS.REPORTS_VIEW, allowed: false },
        ],
      },
    });

    expect(update.status).toBe(200);
    const afterUpdate = db.prepare(
      'SELECT permission_key, allowed, updated_by_user_id FROM user_permissions WHERE user_id = 2 ORDER BY permission_key',
    ).all() as Array<{ permission_key: string; allowed: number; updated_by_user_id: number }>;
    expect(afterUpdate).toEqual([
      { permission_key: PERMISSIONS.REPORTS_VIEW, allowed: 0, updated_by_user_id: 2 },
      { permission_key: PERMISSIONS.IMPORT_EXPORT, allowed: 1, updated_by_user_id: 2 },
    ]);

    const clear = await requestJson(app, '/roles/users/2/permissions', {
      method: 'PUT',
      body: {
        updates: [{ key: PERMISSIONS.REPORTS_VIEW, allowed: null }],
      },
    });

    expect(clear.status).toBe(200);
    const deniedReport = db.prepare(
      'SELECT 1 FROM user_permissions WHERE user_id = 2 AND permission_key = ?',
    ).get(PERMISSIONS.REPORTS_VIEW);
    expect(deniedReport).toBeUndefined();
  });

  it('honors an explicit users.manage deny even for an admin caller', async () => {
    db = buildDb();
    const app = createApp(db, makeUser({
      permissionOverrides: new Map([[PERMISSIONS.USERS_MANAGE, false]]),
    }));

    const response = await requestJson(app, '/roles');

    expect(response.status).toBe(403);
    expect(response.body.message).toBe('users.manage permission required');
  });

  it('prevents callers from denying users.manage to their own account', async () => {
    db = buildDb();
    const app = createApp(db, makeUser());

    const response = await requestJson(app, '/roles/users/1/permissions', {
      method: 'PUT',
      body: {
        updates: [{ key: PERMISSIONS.USERS_MANAGE, allowed: false }],
      },
    });

    expect(response.status).toBe(400);
    expect(response.body.message).toBe('Cannot deny users.manage for your own account');
  });

  it('prevents denying users.manage to the last active admin', async () => {
    db = buildDb();
    db.prepare("UPDATE users SET role = 'cashier' WHERE id = 3").run();
    const manager = makeUser({
      id: 2,
      username: 'manager',
      role: 'manager',
      permissionOverrides: new Map([[PERMISSIONS.USERS_MANAGE, true]]),
    });
    const app = createApp(db, manager);

    const response = await requestJson(app, '/roles/users/1/permissions', {
      method: 'PUT',
      body: {
        updates: [{ key: PERMISSIONS.USERS_MANAGE, allowed: false }],
      },
    });

    expect(response.status).toBe(400);
    expect(response.body.message).toBe('Cannot deny users.manage for the last active admin');
  });

  it('keeps the built-in admin role as full access', async () => {
    db = buildDb();
    const app = createApp(db, makeUser());

    const response = await requestJson(app, '/roles/1/permissions', {
      method: 'PUT',
      body: {
        updates: [{ key: PERMISSIONS.REPORTS_VIEW, allowed: false }],
      },
    });

    expect(response.status).toBe(400);
    expect(response.body.message).toBe('Cannot revoke permissions from the built-in admin role');
  });
});
