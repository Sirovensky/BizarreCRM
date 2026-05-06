import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it, vi } from 'vitest';
import invoicesRouter from '../invoices.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';
import { fireWebhook } from '../../services/webhooks.js';
import { broadcast } from '../../ws/server.js';

vi.mock('../../services/webhooks.js', () => ({
  fireWebhook: vi.fn(),
}));

vi.mock('../../ws/server.js', () => ({
  broadcast: vi.fn(),
}));

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
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      organization TEXT,
      email TEXT,
      phone TEXT,
      lifetime_value_cents INTEGER DEFAULT 0,
      last_interaction_at TEXT,
      health_score INTEGER,
      health_tier TEXT,
      ltv_tier TEXT
    );
    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      username TEXT,
      email TEXT,
      first_name TEXT,
      last_name TEXT,
      role TEXT,
      commission_type TEXT,
      commission_rate REAL,
      is_active INTEGER DEFAULT 1
    );
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY,
      order_id TEXT NOT NULL,
      ticket_id INTEGER,
      customer_id INTEGER,
      status TEXT NOT NULL DEFAULT 'open',
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      discount_reason TEXT,
      total_tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      amount_paid REAL NOT NULL DEFAULT 0,
      amount_due REAL NOT NULL DEFAULT 0,
      due_date TEXT,
      due_on TEXT,
      notes TEXT,
      created_by INTEGER,
      is_deposit INTEGER NOT NULL DEFAULT 0,
      deposit_amount REAL NOT NULL DEFAULT 0,
      parent_invoice_id INTEGER,
      location_id INTEGER,
      reminder_sent_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE inventory_items (
      id INTEGER PRIMARY KEY,
      name TEXT,
      sku TEXT
    );
    CREATE TABLE invoice_line_items (
      id INTEGER PRIMARY KEY,
      invoice_id INTEGER NOT NULL,
      inventory_item_id INTEGER,
      description TEXT,
      quantity REAL,
      unit_price REAL,
      line_discount REAL,
      tax_amount REAL,
      tax_class_id INTEGER,
      total REAL,
      notes TEXT
    );
    CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      method TEXT NOT NULL,
      method_detail TEXT,
      transaction_id TEXT,
      processor TEXT,
      reference TEXT,
      processor_transaction_id TEXT,
      processor_response TEXT,
      capture_state TEXT,
      notes TEXT,
      payment_type TEXT NOT NULL DEFAULT 'payment',
      user_id INTEGER NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE commissions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      ticket_id INTEGER,
      invoice_id INTEGER,
      amount REAL NOT NULL DEFAULT 0,
      type TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE loyalty_points (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      points INTEGER NOT NULL,
      reason TEXT NOT NULL,
      reference_type TEXT NOT NULL,
      reference_id INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE activity_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      actor_user_id INTEGER,
      entity_kind TEXT NOT NULL,
      entity_id INTEGER,
      action TEXT NOT NULL,
      metadata_json TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE store_credits (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE store_credit_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      amount REAL NOT NULL,
      type TEXT NOT NULL,
      reference_type TEXT,
      reference_id INTEGER,
      notes TEXT,
      user_id INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event TEXT NOT NULL,
      user_id INTEGER,
      ip_address TEXT,
      details TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE idempotency_keys (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      key TEXT NOT NULL,
      request_hash TEXT,
      response_status INTEGER,
      response_body TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (user_id, key)
    );

    INSERT INTO store_config (key, value) VALUES
      ('portal_loyalty_enabled', 'true'),
      ('portal_loyalty_rate', '1');
    INSERT INTO customers (id, first_name, last_name, email, phone)
      VALUES (10, 'Casey', 'Customer', 'casey@example.com', '5550100');
    INSERT INTO users (id, username, email, first_name, last_name, role, commission_type, commission_rate)
      VALUES (7, 'admin', 'admin@example.com', 'Ada', 'Admin', 'admin', 'percent_ticket', 10);
  `);
  return db;
}

function seedInvoice(
  db: Database.Database,
  {
    id,
    orderId,
    total,
    totalTax,
    amountPaid,
    amountDue,
    status,
  }: {
    id: number;
    orderId: string;
    total: number;
    totalTax: number;
    amountPaid: number;
    amountDue: number;
    status: string;
  },
): void {
  db.prepare(`
    INSERT INTO invoices
      (id, order_id, customer_id, status, subtotal, total_tax, total, amount_paid, amount_due, created_by, location_id)
    VALUES (?, ?, 10, ?, ?, ?, ?, ?, ?, 7, 1)
  `).run(id, orderId, status, total - totalTax, totalTax, total, amountPaid, amountDue);
}

function createApp(db: Database.Database): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    req.tenantSlug = 'test-tenant';
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
  app.use('/invoices', invoicesRouter);
  app.use(errorHandler);
  return app;
}

async function postJson(app: Express, path: string, body: unknown, headers: Record<string, string> = {}) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
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
  vi.clearAllMocks();
});

describe('invoice payment recording', () => {
  it('records a single invoice payment with dedup, recalculation, and side effects', async () => {
    db = buildDb();
    seedInvoice(db, {
      id: 1,
      orderId: 'INV-1',
      total: 120,
      totalTax: 20,
      amountPaid: 0,
      amountDue: 120,
      status: 'open',
    });
    const app = createApp(db);

    const response = await postJson(app, '/invoices/1/payments', {
      amount: 60,
      method: 'card',
      method_detail: 'Visa',
      transaction_id: 'txn_1',
      notes: 'Counter payment',
      payment_type: 'payment',
      customer_id: 10,
    }, { 'x-idempotency-key': 'single-payment-1' });

    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({
      id: 1,
      status: 'partial',
      amount_paid: 60,
      amount_due: 60,
    });
    expect(response.body.data.payments).toHaveLength(1);

    const replay = await postJson(app, '/invoices/1/payments', {
      amount: 60,
      method: 'card',
      method_detail: 'Visa',
      transaction_id: 'txn_1',
      notes: 'Counter payment',
      payment_type: 'payment',
      customer_id: 10,
    }, { 'x-idempotency-key': 'single-payment-1' });

    expect(replay.status).toBe(201);
    expect(db.prepare('SELECT COUNT(*) AS c FROM payments WHERE invoice_id = 1').get()).toMatchObject({ c: 1 });
    expect(db.prepare('SELECT amount, method, payment_type, user_id FROM payments WHERE invoice_id = 1').get()).toMatchObject({
      amount: 60,
      method: 'card',
      payment_type: 'payment',
      user_id: 7,
    });
    expect(db.prepare('SELECT amount, type, invoice_id FROM commissions').get()).toMatchObject({
      amount: 5,
      type: 'invoice_payment',
      invoice_id: 1,
    });
    expect(db.prepare('SELECT points, reference_type, reference_id FROM loyalty_points').get()).toMatchObject({
      points: 60,
      reference_type: 'invoice',
      reference_id: 1,
    });
    expect(db.prepare('SELECT entity_kind, entity_id, action FROM activity_events').get()).toMatchObject({
      entity_kind: 'payment',
      entity_id: 1,
      action: 'received',
    });
    expect(fireWebhook).toHaveBeenCalledTimes(1);
    expect(fireWebhook).toHaveBeenCalledWith(db, 'payment_received', expect.objectContaining({
      invoice_id: 1,
      amount: 60,
      method: 'card',
      idempotency_key: 'payment:1:1',
    }));
    expect(broadcast).toHaveBeenCalledWith('invoice:payment', expect.objectContaining({ id: 1 }), 'test-tenant');
  });

  it('records bulk mark_paid through the payment recorder and recalculates from payment rows', async () => {
    db = buildDb();
    seedInvoice(db, {
      id: 2,
      orderId: 'INV-2',
      total: 80,
      totalTax: 0,
      amountPaid: 75,
      amountDue: 5,
      status: 'partial',
    });
    db.prepare(`
      INSERT INTO payments (invoice_id, amount, method, notes, payment_type, user_id, created_at)
      VALUES (2, 30, 'cash', 'Prior payment', 'payment', 7, datetime('now', '-1 day'))
    `).run();
    const app = createApp(db);

    const response = await postJson(app, '/invoices/bulk-action', {
      action: 'mark_paid',
      invoice_ids: [2],
    });

    expect(response.status).toBe(200);
    expect(response.body.data).toEqual({
      success_count: 1,
      fail_count: 0,
    });
    expect(db.prepare('SELECT amount_paid, amount_due, status FROM invoices WHERE id = 2').get()).toMatchObject({
      amount_paid: 80,
      amount_due: 0,
      status: 'paid',
    });
    expect(db.prepare("SELECT amount, method, notes, payment_type FROM payments WHERE invoice_id = 2 AND notes = 'Bulk mark-paid'").get()).toMatchObject({
      amount: 50,
      method: 'cash',
      notes: 'Bulk mark-paid',
      payment_type: 'payment',
    });
    expect(db.prepare('SELECT amount, type, invoice_id FROM commissions WHERE invoice_id = 2').get()).toMatchObject({
      amount: 5,
      type: 'invoice_payment',
      invoice_id: 2,
    });
    expect(db.prepare('SELECT points, reference_type, reference_id FROM loyalty_points WHERE reference_id = 2').get()).toMatchObject({
      points: 50,
      reference_type: 'invoice',
      reference_id: 2,
    });
    expect(fireWebhook).toHaveBeenCalledWith(db, 'payment_received', expect.objectContaining({
      invoice_id: 2,
      amount: 50,
      method: 'cash',
    }));
    expect(broadcast).toHaveBeenCalledWith('invoice:payment', expect.objectContaining({ id: 2 }), 'test-tenant');
  });
});
