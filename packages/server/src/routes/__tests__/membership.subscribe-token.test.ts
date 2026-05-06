import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import { afterEach, describe, expect, it, vi } from 'vitest';
import membershipRouter from '../membership.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';
import {
  chargeToken,
  isBlockChypEnabled,
  verifyCustomerToken,
} from '../../services/blockchyp.js';

vi.mock('../../services/blockchyp.js', () => ({
  enrollCard: vi.fn(),
  createPaymentLink: vi.fn(),
  chargeToken: vi.fn(),
  isBlockChypEnabled: vi.fn(),
  verifyCustomerToken: vi.fn(),
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
      details TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      active_subscription_id INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE membership_tiers (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT,
      monthly_price REAL NOT NULL,
      discount_pct REAL NOT NULL DEFAULT 0,
      discount_applies_to TEXT NOT NULL DEFAULT 'labor',
      benefits TEXT,
      color TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE customer_subscriptions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      tier_id INTEGER NOT NULL,
      blockchyp_token TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      current_period_start TEXT NOT NULL,
      current_period_end TEXT NOT NULL,
      signature_file TEXT,
      cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
      auto_renew INTEGER NOT NULL DEFAULT 1,
      pause_reason TEXT,
      last_charge_at TEXT,
      last_charge_amount REAL,
      failed_charge_count INTEGER NOT NULL DEFAULT 0,
      next_billing_attempt_at TEXT,
      billing_retry_stage INTEGER NOT NULL DEFAULT 0,
      last_charge_failed_at TEXT,
      last_charge_error TEXT,
      billing_suspended_at TEXT,
      payment_provider TEXT NOT NULL DEFAULT 'blockchyp',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX idx_customer_subscriptions_active_unique
      ON customer_subscriptions(customer_id)
      WHERE status IN ('active', 'past_due');
    CREATE TABLE subscription_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subscription_id INTEGER NOT NULL,
      amount REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'success',
      blockchyp_transaction_id TEXT,
      error_message TEXT,
      payment_provider TEXT NOT NULL DEFAULT 'blockchyp',
      processor_transaction_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    INSERT INTO customers (id, first_name, last_name) VALUES (10, 'Casey', 'Customer');
    INSERT INTO membership_tiers (id, name, slug, monthly_price, benefits, is_active)
      VALUES
        (20, 'Gold', 'gold', 29.99, '[]', 1),
        (21, 'Comp', 'comp', 0, '[]', 1);
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
  app.use('/membership', membershipRouter);
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
    const json = await response.json();
    return { status: response.status, json };
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  }
}

describe('membership subscribe BlockChyp token verification', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('rejects an unverified paid membership token before activating a subscription', async () => {
    const db = buildDb();
    vi.mocked(isBlockChypEnabled).mockReturnValue(true);
    vi.mocked(verifyCustomerToken).mockResolvedValue({
      success: false,
      error: 'BlockChyp token was not found',
    });
    const app = createApp(db);

    const response = await requestJson(app, 'POST', '/membership/subscribe', {
      customer_id: 10,
      tier_id: 20,
      blockchyp_token: 'tok_missing',
    });

    expect(response.status).toBe(400);
    expect(response.json).toMatchObject({
      success: false,
      message: 'BlockChyp token was not found',
    });
    expect(verifyCustomerToken).toHaveBeenCalledWith(db, 'tok_missing');
    expect(chargeToken).not.toHaveBeenCalled();
    expect(db.prepare('SELECT COUNT(*) AS count FROM customer_subscriptions').get()).toMatchObject({ count: 0 });
    expect(db.prepare('SELECT event FROM audit_logs').all()).toEqual([
      { event: 'membership_blockchyp_token_verification_failed' },
    ]);
  });

  it('verifies a paid membership token before charging and activating', async () => {
    const db = buildDb();
    vi.mocked(isBlockChypEnabled).mockReturnValue(true);
    vi.mocked(verifyCustomerToken).mockResolvedValue({
      success: true,
      token: 'tok_valid',
      maskedPan: '************1111',
      cardType: 'VISA',
    });
    vi.mocked(chargeToken).mockResolvedValue({ success: true, transactionId: 'bc_tx_1' });
    const app = createApp(db);

    const response = await requestJson(app, 'POST', '/membership/subscribe', {
      customer_id: 10,
      tier_id: 20,
      blockchyp_token: ' tok_valid ',
    });

    expect(response.status).toBe(201);
    expect(verifyCustomerToken).toHaveBeenCalledWith(db, 'tok_valid');
    expect(chargeToken).toHaveBeenCalledWith(db, 'tok_valid', '29.99', 'Gold Membership activation');

    const subscription = db.prepare('SELECT * FROM customer_subscriptions').get() as Record<string, unknown>;
    expect(subscription).toMatchObject({
      customer_id: 10,
      tier_id: 20,
      blockchyp_token: 'tok_valid',
      status: 'active',
      payment_provider: 'blockchyp',
    });
    expect(db.prepare('SELECT active_subscription_id FROM customers WHERE id = 10').get()).toMatchObject({
      active_subscription_id: subscription.id,
    });

    const events = db.prepare('SELECT event FROM audit_logs ORDER BY id').all();
    expect(events).toEqual([
      { event: 'membership_blockchyp_token_verification_success' },
      { event: 'membership_initial_charge_success' },
      { event: 'membership_subscribed' },
    ]);
  });

  it('preserves free membership activation without BlockChyp verification', async () => {
    const db = buildDb();
    const app = createApp(db);

    const response = await requestJson(app, 'POST', '/membership/subscribe', {
      customer_id: 10,
      tier_id: 21,
    });

    expect(response.status).toBe(201);
    expect(isBlockChypEnabled).not.toHaveBeenCalled();
    expect(verifyCustomerToken).not.toHaveBeenCalled();
    expect(chargeToken).not.toHaveBeenCalled();
    expect(db.prepare('SELECT * FROM customer_subscriptions').get()).toMatchObject({
      customer_id: 10,
      tier_id: 21,
      blockchyp_token: null,
      status: 'active',
      payment_provider: 'none',
    });
    expect(db.prepare('SELECT status, payment_provider FROM subscription_payments').get()).toMatchObject({
      status: 'success',
      payment_provider: 'none',
    });
  });
});
