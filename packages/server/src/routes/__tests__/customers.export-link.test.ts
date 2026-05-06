import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it } from 'vitest';
import {
  customerExportDownloadRouter,
  issueCustomerExportDownloadToken,
} from '../customers.routes.js';
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

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event TEXT NOT NULL,
      user_id INTEGER,
      ip_address TEXT,
      details TEXT
    );
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      email TEXT,
      phone TEXT,
      mobile TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE customer_phones (id INTEGER PRIMARY KEY, customer_id INTEGER, phone TEXT);
    CREATE TABLE customer_emails (id INTEGER PRIMARY KEY, customer_id INTEGER, email TEXT);
    CREATE TABLE customer_assets (id INTEGER PRIMARY KEY, customer_id INTEGER, name TEXT);
    CREATE TABLE tickets (id INTEGER PRIMARY KEY, customer_id INTEGER, order_id TEXT, is_deleted INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE ticket_notes (id INTEGER PRIMARY KEY, ticket_id INTEGER, content TEXT);
    CREATE TABLE ticket_devices (id INTEGER PRIMARY KEY, ticket_id INTEGER, device_name TEXT);
    CREATE TABLE invoices (id INTEGER PRIMARY KEY, customer_id INTEGER, total REAL);
    CREATE TABLE estimates (id INTEGER PRIMARY KEY, customer_id INTEGER, total REAL);
    CREATE TABLE loaner_history (id INTEGER PRIMARY KEY, customer_id INTEGER, device_name TEXT);
    CREATE TABLE sms_messages (id INTEGER PRIMARY KEY, conv_phone TEXT, body TEXT);
    CREATE TABLE email_messages (id INTEGER PRIMARY KEY, to_address TEXT, from_address TEXT, subject TEXT);

    INSERT INTO customers (id, first_name, last_name, email, phone, mobile, is_deleted)
    VALUES (42, 'José', 'Private', 'private@example.com', '(303) 555-1000', NULL, 0);
    INSERT INTO customer_phones (id, customer_id, phone) VALUES (1, 42, '303-555-1000');
    INSERT INTO customer_emails (id, customer_id, email) VALUES (1, 42, 'alt@example.com');
    INSERT INTO customer_assets (id, customer_id, name) VALUES (1, 42, 'MacBook');
    INSERT INTO tickets (id, customer_id, order_id, is_deleted) VALUES (10, 42, 'T-10', 0);
    INSERT INTO ticket_notes (id, ticket_id, content) VALUES (11, 10, 'Private note');
    INSERT INTO ticket_devices (id, ticket_id, device_name) VALUES (12, 10, 'iPhone');
    INSERT INTO invoices (id, customer_id, total) VALUES (20, 42, 123.45);
    INSERT INTO estimates (id, customer_id, total) VALUES (30, 42, 99.99);
    INSERT INTO loaner_history (id, customer_id, device_name) VALUES (40, 42, 'Loaner phone');
    INSERT INTO sms_messages (id, conv_phone, body) VALUES (50, '3035551000', 'SMS PII');
    INSERT INTO email_messages (id, to_address, from_address, subject)
    VALUES (60, 'private@example.com', 'shop@example.com', 'Email PII');
  `);
  return db;
}

function createApp(db: Database.Database, tenantId = 0): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    req.tenantId = tenantId;
    next();
  });
  app.use('/customers', customerExportDownloadRouter);
  app.use(errorHandler);
  return app;
}

async function get(app: Express, path: string) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`);
    return {
      status: response.status,
      headers: response.headers,
      text: await response.text(),
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

describe('customer GDPR export download links', () => {
  it('streams customer export JSON from an opaque signed token with safe attachment headers', async () => {
    db = buildDb();
    const app = createApp(db);
    const { token } = issueCustomerExportDownloadToken({
      customerId: 42,
      requesterUserId: 7,
      tenantId: 0,
      ttlSeconds: 300,
    });

    const response = await get(app, `/customers/export-download/${encodeURIComponent(token)}`);

    expect(response.status).toBe(200);
    const disposition = response.headers.get('content-disposition') ?? '';
    expect(disposition).toContain('attachment; filename=');
    expect(disposition).toContain("filename*=UTF-8''");
    expect(disposition).not.toContain('José');
    expect(disposition).not.toContain('Private');
    expect(disposition).not.toContain('private@example.com');
    expect(response.headers.get('cache-control')).toContain('no-store');
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');

    const body = JSON.parse(response.text) as any;
    expect(body.customer.email).toBe('private@example.com');
    expect(body.ticket_notes[0].content).toBe('Private note');
    expect(body.sms_messages[0].body).toBe('SMS PII');

    const auditRow = db
      .prepare("SELECT event, user_id, details FROM audit_logs WHERE event = 'customer_data_export_downloaded'")
      .get() as { event: string; user_id: number; details: string };
    expect(auditRow.user_id).toBe(7);
    expect(JSON.parse(auditRow.details)).toMatchObject({ customer_id: 42 });
  });

  it('rejects tampered export tokens without revealing whether a customer exists', async () => {
    db = buildDb();
    const app = createApp(db);
    const { token } = issueCustomerExportDownloadToken({
      customerId: 42,
      requesterUserId: 7,
      tenantId: 0,
      ttlSeconds: 300,
    });
    const tampered = `${token.slice(0, -1)}${token.endsWith('a') ? 'b' : 'a'}`;

    const response = await get(app, `/customers/export-download/${encodeURIComponent(tampered)}`);

    expect(response.status).toBe(410);
    expect(response.text).not.toContain('private@example.com');
  });

  it('rejects a valid token presented on the wrong tenant context', async () => {
    db = buildDb();
    const app = createApp(db, 2);
    const { token } = issueCustomerExportDownloadToken({
      customerId: 42,
      requesterUserId: 7,
      tenantId: 1,
      ttlSeconds: 300,
    });

    const response = await get(app, `/customers/export-download/${encodeURIComponent(token)}`);

    expect(response.status).toBe(410);
    expect(response.text).not.toContain('private@example.com');
  });
});
