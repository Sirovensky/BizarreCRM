import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it } from 'vitest';
import ticketsRouter from '../tickets.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';

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
      const results = db.transaction(() => queries.map((query) => {
        const result = db.prepare(query.sql).run(...(query.params ?? []));
        if (query.expectChanges && result.changes === 0) {
          throw new Error(query.expectChangesError ?? 'Expected changes');
        }
        return {
          changes: result.changes,
          lastInsertRowid: Number(result.lastInsertRowid),
        };
      }))();
      return results;
    },
  };
}

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE store_config (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE tax_classes (id INTEGER PRIMARY KEY, rate REAL NOT NULL);
    CREATE TABLE ticket_statuses (
      id INTEGER PRIMARY KEY,
      name TEXT,
      is_closed INTEGER NOT NULL DEFAULT 0,
      is_cancelled INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE tickets (
      id INTEGER PRIMARY KEY,
      order_id TEXT NOT NULL,
      customer_id INTEGER,
      status_id INTEGER,
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      discount_reason TEXT,
      total_tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      invoice_id INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT
    );
    CREATE TABLE ticket_devices (
      id INTEGER PRIMARY KEY,
      ticket_id INTEGER NOT NULL,
      device_name TEXT NOT NULL DEFAULT '',
      device_model_id INTEGER,
      service_name TEXT,
      price REAL NOT NULL DEFAULT 0,
      line_discount REAL NOT NULL DEFAULT 0,
      tax_amount REAL NOT NULL DEFAULT 0,
      tax_class_id INTEGER,
      tax_inclusive INTEGER NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0
    );
    CREATE TABLE ticket_device_parts (
      id INTEGER PRIMARY KEY,
      ticket_device_id INTEGER NOT NULL,
      inventory_item_id INTEGER,
      quantity INTEGER NOT NULL DEFAULT 1,
      price REAL NOT NULL DEFAULT 0
    );
    CREATE TABLE repair_services (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT,
      category TEXT,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE repair_prices (
      id INTEGER PRIMARY KEY,
      device_model_id INTEGER NOT NULL,
      repair_service_id INTEGER NOT NULL,
      labor_price REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT
    );
    CREATE TABLE ticket_device_quote_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ticket_device_id INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('service', 'misc')),
      repair_service_id INTEGER,
      description TEXT NOT NULL DEFAULT '',
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price REAL NOT NULL DEFAULT 0,
      line_discount REAL NOT NULL DEFAULT 0,
      tax_amount REAL NOT NULL DEFAULT 0,
      tax_class_id INTEGER,
      tax_inclusive INTEGER NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE ticket_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ticket_id INTEGER NOT NULL,
      user_id INTEGER,
      action TEXT NOT NULL,
      description TEXT NOT NULL,
      old_value TEXT,
      new_value TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    INSERT INTO ticket_statuses (id, name) VALUES (1, 'Open');
    INSERT INTO tickets (id, order_id, customer_id, status_id) VALUES (1, 'T-1', 1, 1);
    INSERT INTO ticket_devices (id, ticket_id, device_name, device_model_id) VALUES (10, 1, 'iPad Pro', 20);
    INSERT INTO repair_services (id, name, slug, category) VALUES (30, 'Screen Replacement', 'tablet-screen', 'tablet');
    INSERT INTO repair_prices (id, device_model_id, repair_service_id, labor_price, is_active, updated_at)
    VALUES (40, 20, 30, 149.99, 1, '2026-05-01 00:00:00');
  `);
  return db;
}

function createApp(db: Database.Database): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    req.user = {
      id: 7,
      username: 'admin',
      email: 'admin@example.com',
      first_name: 'Ada',
      last_name: 'Admin',
      role: 'admin',
      permissions: null,
      sessionId: 'test-session',
      customRolePermissions: null,
    };
    next();
  });
  app.use('/tickets', ticketsRouter);
  app.use(errorHandler);
  return app;
}

async function postJson(app: Express, path: string, body: unknown) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    return {
      status: response.status,
      body: await response.json() as any,
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

describe('ticket device quote-line routes', () => {
  it('adds a repair-service quote line using the device model repair price', async () => {
    db = buildDb();
    const app = createApp(db);

    const response = await postJson(app, '/tickets/devices/10/services', {
      repair_service_id: 30,
      name: 'Screen Replacement',
      labor_price: 0,
      device_id: 10,
      ticket_id: 1,
    });

    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({
      kind: 'service',
      repair_service_id: 30,
      name: 'Screen Replacement',
      price_cents: 14999,
      total_cents: 14999,
    });

    const ticket = db.prepare('SELECT subtotal, total FROM tickets WHERE id = 1').get() as { subtotal: number; total: number };
    expect(ticket.subtotal).toBeCloseTo(149.99);
    expect(ticket.total).toBeCloseTo(149.99);
  });

  it('adds a one-off misc quote line from amount_cents', async () => {
    db = buildDb();
    const app = createApp(db);

    const response = await postJson(app, '/tickets/devices/10/misc', {
      name: 'Recycling fee',
      amount_cents: 1250,
      device_id: 10,
      ticket_id: 1,
    });

    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({
      kind: 'misc',
      repair_service_id: null,
      name: 'Recycling fee',
      amount_cents: 1250,
      total_cents: 1250,
    });

    const line = db.prepare('SELECT kind, repair_service_id, description, unit_price, total FROM ticket_device_quote_lines').get() as {
      kind: string;
      repair_service_id: number | null;
      description: string;
      unit_price: number;
      total: number;
    };
    expect(line).toMatchObject({
      kind: 'misc',
      repair_service_id: null,
      description: 'Recycling fee',
      unit_price: 12.5,
      total: 12.5,
    });
  });

  it('rejects a body ticket_id that does not match the device', async () => {
    db = buildDb();
    const app = createApp(db);

    const response = await postJson(app, '/tickets/devices/10/misc', {
      name: 'Mismatched line',
      amount_cents: 500,
      device_id: 10,
      ticket_id: 999,
    });

    expect(response.status).toBe(400);
    expect(response.body.message).toBe('ticket_id does not match device ticket id');
  });
});
