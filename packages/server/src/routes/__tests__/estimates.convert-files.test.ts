import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it } from 'vitest';
import estimatesRouter from '../estimates.routes.js';
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

function buildBaseDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE rate_limits (
      category TEXT NOT NULL,
      key TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      first_attempt INTEGER NOT NULL,
      locked_until INTEGER,
      PRIMARY KEY (category, key)
    );
    CREATE TABLE ticket_statuses (
      id INTEGER PRIMARY KEY,
      name TEXT,
      is_default INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE estimates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      customer_id INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      total_tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      notes TEXT,
      converted_ticket_id INTEGER,
      created_by INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT
    );
    CREATE TABLE estimate_line_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      estimate_id INTEGER NOT NULL,
      inventory_item_id INTEGER,
      description TEXT NOT NULL DEFAULT '',
      quantity INTEGER NOT NULL DEFAULT 1,
      unit_price REAL NOT NULL DEFAULT 0,
      tax_amount REAL NOT NULL DEFAULT 0,
      tax_class_id INTEGER,
      total REAL NOT NULL DEFAULT 0
    );
    CREATE TABLE tickets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      customer_id INTEGER NOT NULL,
      status_id INTEGER NOT NULL,
      estimate_id INTEGER,
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      total_tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      source TEXT,
      created_by INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT
    );
    CREATE TABLE ticket_devices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ticket_id INTEGER NOT NULL,
      device_name TEXT NOT NULL DEFAULT '',
      service_id INTEGER,
      price REAL NOT NULL DEFAULT 0,
      tax_amount REAL NOT NULL DEFAULT 0,
      tax_class_id INTEGER,
      total REAL NOT NULL DEFAULT 0,
      additional_notes TEXT
    );
    CREATE TABLE ticket_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ticket_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    INSERT INTO ticket_statuses (id, name, is_default) VALUES (1, 'Open', 1);
    INSERT INTO estimates (id, order_id, customer_id, status, subtotal, discount, total_tax, total, notes, created_by)
    VALUES (1, 'EST-1', 42, 'approved', 120, 5, 10, 125, 'Customer reported cracked screen.', 7);
    INSERT INTO estimate_line_items (estimate_id, inventory_item_id, description, quantity, unit_price, tax_amount, tax_class_id, total)
    VALUES (1, 77, 'iPhone screen repair', 1, 120, 10, NULL, 130);
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
  app.use('/estimates', estimatesRouter);
  app.use(errorHandler);
  return app;
}

async function postJson(app: Express, path: string, body: unknown = {}) {
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

describe('estimate conversion file preservation', () => {
  it('links shared estimate attachments and photos to the converted ticket', async () => {
    db = buildBaseDb();
    db.exec(`
      CREATE TABLE attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        estimate_id INTEGER,
        ticket_id INTEGER,
        file_path TEXT NOT NULL,
        filename TEXT,
        updated_at TEXT
      );
      CREATE TABLE ticket_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        estimate_id INTEGER,
        ticket_id INTEGER,
        ticket_device_id INTEGER,
        type TEXT NOT NULL DEFAULT 'pre',
        file_path TEXT NOT NULL,
        caption TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      INSERT INTO attachments (estimate_id, ticket_id, file_path, filename)
      VALUES (1, NULL, 'estimate-intake.pdf', 'intake.pdf');
      INSERT INTO ticket_photos (estimate_id, ticket_id, ticket_device_id, type, file_path, caption)
      VALUES (1, NULL, NULL, 'pre', 'cracked-screen.jpg', 'Customer upload');
    `);
    const app = createApp(db);

    const response = await postJson(app, '/estimates/1/convert');

    expect(response.status).toBe(201);
    const ticketId = response.body.data.ticket.id as number;
    const device = db.prepare('SELECT id FROM ticket_devices WHERE ticket_id = ?').get(ticketId) as { id: number };
    expect(device.id).toBeGreaterThan(0);
    expect(db.prepare('SELECT estimate_id, ticket_id, file_path FROM attachments WHERE id = 1').get()).toMatchObject({
      estimate_id: 1,
      ticket_id: ticketId,
      file_path: 'estimate-intake.pdf',
    });
    expect(db.prepare('SELECT estimate_id, ticket_id, ticket_device_id, file_path FROM ticket_photos WHERE id = 1').get()).toMatchObject({
      estimate_id: 1,
      ticket_id: ticketId,
      ticket_device_id: device.id,
      file_path: 'cracked-screen.jpg',
    });
    expect(db.prepare('SELECT COUNT(*) AS count FROM ticket_photos WHERE ticket_device_id = ?').get(device.id)).toMatchObject({
      count: 1,
    });
  });

  it('copies rows from estimate-specific photo and attachment tables when present', async () => {
    db = buildBaseDb();
    db.exec(`
      CREATE TABLE estimate_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        estimate_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        filename TEXT,
        created_at TEXT
      );
      CREATE TABLE ticket_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        filename TEXT,
        created_at TEXT
      );
      CREATE TABLE estimate_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        estimate_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        caption TEXT,
        type TEXT,
        created_at TEXT
      );
      CREATE TABLE ticket_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_device_id INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'pre',
        file_path TEXT NOT NULL,
        caption TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      INSERT INTO estimate_attachments (estimate_id, file_path, filename, created_at)
      VALUES (1, 'customer-diagnostic.pdf', 'diagnostic.pdf', '2026-05-01 10:00:00');
      INSERT INTO estimate_photos (estimate_id, file_path, caption, type, created_at)
      VALUES (1, 'frame-damage.webp', 'Bent frame', 'customer', '2026-05-01 10:05:00');
    `);
    const app = createApp(db);

    const response = await postJson(app, '/estimates/1/convert');

    expect(response.status).toBe(201);
    const ticketId = response.body.data.ticket.id as number;
    const device = db.prepare('SELECT id FROM ticket_devices WHERE ticket_id = ?').get(ticketId) as { id: number };
    expect(db.prepare('SELECT ticket_id, file_path, filename FROM ticket_attachments').get()).toMatchObject({
      ticket_id: ticketId,
      file_path: 'customer-diagnostic.pdf',
      filename: 'diagnostic.pdf',
    });
    expect(db.prepare('SELECT ticket_device_id, type, file_path, caption FROM ticket_photos').get()).toMatchObject({
      ticket_device_id: device.id,
      type: 'pre',
      file_path: 'frame-damage.webp',
      caption: 'Bent frame',
    });
  });
});
