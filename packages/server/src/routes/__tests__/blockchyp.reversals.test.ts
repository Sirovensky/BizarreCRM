import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it, vi } from 'vitest';
import depositsRouter from '../deposits.routes.js';
import blockchypRouter from '../blockchyp.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';
import {
  isBlockChypEnabled,
  processRefund,
  voidCharge,
  deleteSignatureFile,
} from '../../services/blockchyp.js';

vi.mock('../../services/blockchyp.js', () => {
  class BlockChypIndeterminateError extends Error {
    transactionRef: string;
    constructor(transactionRef: string) {
      super('indeterminate');
      this.transactionRef = transactionRef;
    }
  }
  return {
    isBlockChypEnabled: vi.fn(),
    getBlockChypConfig: vi.fn(() => ({
      enabled: true,
      terminalName: 'Front Counter',
      tcEnabled: false,
      promptForTip: false,
      autoCloseTicket: false,
    })),
    testConnection: vi.fn(),
    capturePreTicketSignature: vi.fn(),
    captureCheckInSignature: vi.fn(),
    processPayment: vi.fn(),
    refreshClient: vi.fn(),
    adjustTip: vi.fn(),
    processRefund: vi.fn(),
    voidCharge: vi.fn(),
    captureCharge: vi.fn(),
    deleteSignatureFile: vi.fn(() => true),
    BlockChypIndeterminateError,
  };
});

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
    CREATE TABLE store_config (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE rate_limits (
      category TEXT NOT NULL,
      key TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      first_attempt INTEGER NOT NULL,
      locked_until INTEGER,
      PRIMARY KEY (category, key)
    );
    CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event TEXT NOT NULL,
      user_id INTEGER,
      ip_address TEXT,
      details TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      username TEXT,
      email TEXT,
      first_name TEXT,
      last_name TEXT,
      role TEXT,
      is_active INTEGER DEFAULT 1
    );
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      is_deleted INTEGER DEFAULT 0
    );
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY,
      order_id TEXT NOT NULL,
      customer_id INTEGER,
      total REAL NOT NULL DEFAULT 0,
      amount_paid REAL NOT NULL DEFAULT 0,
      amount_due REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'unpaid',
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      amount REAL NOT NULL DEFAULT 0,
      method TEXT NOT NULL,
      method_detail TEXT,
      transaction_id TEXT,
      notes TEXT,
      payment_type TEXT NOT NULL DEFAULT 'payment',
      processor TEXT,
      reference TEXT,
      processor_transaction_id TEXT,
      processor_response TEXT,
      signature_file TEXT,
      signature_file_path TEXT,
      capture_state TEXT,
      void_pending_at TEXT,
      voided_at TEXT,
      voided_by_user_id INTEGER,
      void_error TEXT,
      capture_pending_at TEXT,
      captured_at TEXT,
      captured_by_user_id INTEGER,
      capture_error TEXT,
      user_id INTEGER NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE deposits (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ticket_id INTEGER,
      customer_id INTEGER NOT NULL,
      amount_cents INTEGER NOT NULL,
      collected_at TEXT NOT NULL DEFAULT (datetime('now')),
      applied_to_invoice_id INTEGER,
      applied_at TEXT,
      refunded_at TEXT,
      notes TEXT,
      payment_id INTEGER,
      applied_payment_id INTEGER,
      processor TEXT,
      processor_transaction_id TEXT,
      processor_refund_transaction_id TEXT,
      processor_response TEXT,
      refund_pending_at TEXT,
      refund_error TEXT,
      refunded_by_user_id INTEGER,
      refund_signature_file TEXT,
      refund_signature_file_path TEXT,
      accepted_terms_name TEXT,
      accepted_terms_text TEXT,
      accepted_terms_hash TEXT,
      accepted_terms_accepted_at TEXT
    );

    INSERT INTO users (id, username, email, first_name, last_name, role)
      VALUES (7, 'admin', 'admin@example.com', 'Ada', 'Admin', 'admin');
    INSERT INTO customers (id, first_name, last_name)
      VALUES (10, 'Casey', 'Customer');
  `);
  return db;
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
  app.use('/deposits', depositsRouter);
  app.use('/blockchyp', blockchypRouter);
  app.use(errorHandler);
  return app;
}

async function requestJson(app: Express, method: string, path: string, body: unknown = {}) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method,
      headers: { 'content-type': 'application/json' },
      body: method === 'GET' ? undefined : JSON.stringify(body),
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

describe('BlockChyp deposit and payment reversals', () => {
  it('applies a deposit by inserting a deposit payment and updating invoice balance', async () => {
    db = buildDb();
    db.prepare(`
      INSERT INTO invoices (id, order_id, customer_id, total, amount_paid, amount_due, status)
      VALUES (1, 'INV-1', 10, 100, 20, 80, 'partial')
    `).run();
    db.prepare(`
      INSERT INTO deposits (id, customer_id, amount_cents, collected_at)
      VALUES (1, 10, 3000, datetime('now'))
    `).run();
    const app = createApp(db);

    const response = await requestJson(app, 'POST', '/deposits/1/apply-to-invoice', { invoice_id: 1 });

    expect(response.status).toBe(200);
    expect(response.body.data).toMatchObject({
      id: 1,
      applied_to_invoice_id: 1,
      amount_cents: 3000,
    });
    expect(db.prepare('SELECT amount_paid, amount_due, status FROM invoices WHERE id = 1').get()).toMatchObject({
      amount_paid: 50,
      amount_due: 50,
      status: 'partial',
    });
    expect(db.prepare('SELECT amount, method, payment_type, reference FROM payments WHERE invoice_id = 1').get()).toMatchObject({
      amount: 30,
      method: 'deposit',
      payment_type: 'deposit',
      reference: 'deposit-1',
    });
    expect(db.prepare('SELECT applied_payment_id FROM deposits WHERE id = 1').get()).toMatchObject({
      applied_payment_id: response.body.data.applied_payment_id,
    });
  });

  it('refunds an unapplied BlockChyp-backed deposit before marking it refunded', async () => {
    db = buildDb();
    db.prepare(`
      INSERT INTO invoices (id, order_id, customer_id, total, amount_paid, amount_due, status)
      VALUES (1, 'INV-1', 10, 25, 25, 0, 'paid')
    `).run();
    db.prepare(`
      INSERT INTO payments (
        id, invoice_id, amount, method, processor, transaction_id,
        processor_transaction_id, capture_state, user_id
      )
      VALUES (9, 1, 25, 'BlockChyp', 'blockchyp', 'bc_orig', 'bc_orig', 'captured', 7)
    `).run();
    db.prepare(`
      INSERT INTO deposits (
        id, customer_id, amount_cents, collected_at, payment_id,
        processor, processor_transaction_id
      )
      VALUES (2, 10, 2500, datetime('now'), 9, 'blockchyp', 'bc_orig')
    `).run();
    vi.mocked(isBlockChypEnabled).mockReturnValue(true);
    vi.mocked(processRefund).mockResolvedValue({
      success: true,
      transactionId: 'bc_refund',
      transactionRef: 'refund-ref',
      receiptSuggestions: { ok: true },
    });
    const app = createApp(db);

    const response = await requestJson(app, 'DELETE', '/deposits/2');

    expect(response.status).toBe(200);
    expect(processRefund).toHaveBeenCalledWith(db, 25, 'bc_orig', 'deposit-2');
    expect(db.prepare(`
      SELECT refunded_at, refund_pending_at, processor_refund_transaction_id, processor_response
        FROM deposits
       WHERE id = 2
    `).get()).toMatchObject({
      refund_pending_at: null,
      processor_refund_transaction_id: 'bc_refund',
      processor_response: JSON.stringify({ ok: true }),
    });
  });

  it('clears a deposit refund claim when BlockChyp metadata is incomplete', async () => {
    db = buildDb();
    db.prepare(`
      INSERT INTO deposits (id, customer_id, amount_cents, collected_at, processor)
      VALUES (3, 10, 1000, datetime('now'), 'blockchyp')
    `).run();
    vi.mocked(isBlockChypEnabled).mockReturnValue(true);
    const app = createApp(db);

    const response = await requestJson(app, 'DELETE', '/deposits/3');

    expect(response.status).toBe(400);
    expect(processRefund).not.toHaveBeenCalled();
    expect(db.prepare('SELECT refund_pending_at, refund_error FROM deposits WHERE id = 3').get()).toMatchObject({
      refund_pending_at: null,
      refund_error: 'Missing originating BlockChyp transaction id',
    });
  });

  it('voids BlockChyp at the processor and backs the payment out of the invoice', async () => {
    db = buildDb();
    db.prepare(`
      INSERT INTO invoices (id, order_id, customer_id, total, amount_paid, amount_due, status)
      VALUES (4, 'INV-4', 10, 100, 60, 40, 'partial')
    `).run();
    db.prepare(`
      INSERT INTO payments (
        id, invoice_id, amount, method, transaction_id, processor_transaction_id,
        signature_file, signature_file_path, capture_state, user_id
      )
      VALUES (10, 4, 40, 'BlockChyp', 'bc_sale', 'bc_sale', 'sig.png', '/tmp/sig.png', 'captured', 7)
    `).run();
    vi.mocked(isBlockChypEnabled).mockReturnValue(true);
    vi.mocked(voidCharge).mockResolvedValue({
      success: true,
      transactionId: 'bc_sale',
      transactionRef: 'void-ref',
      response: { success: true, approved: true },
    });
    vi.mocked(deleteSignatureFile).mockReturnValue(true);
    const app = createApp(db);

    const response = await requestJson(app, 'POST', '/blockchyp/void-payment', { paymentId: 10 });

    expect(response.status).toBe(200);
    expect(voidCharge).toHaveBeenCalledWith(db, 'bc_sale', '10');
    expect(db.prepare('SELECT amount_paid, amount_due, status FROM invoices WHERE id = 4').get()).toMatchObject({
      amount_paid: 20,
      amount_due: 80,
      status: 'partial',
    });
    expect(db.prepare(`
      SELECT capture_state, void_pending_at, signature_file, signature_file_path
        FROM payments
       WHERE id = 10
    `).get()).toMatchObject({
      capture_state: 'voided',
      void_pending_at: null,
      signature_file: null,
      signature_file_path: null,
    });
  });
});
