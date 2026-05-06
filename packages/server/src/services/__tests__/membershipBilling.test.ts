import Database from 'better-sqlite3';
import { describe, expect, it, vi } from 'vitest';
import {
  runMembershipBillingOnce,
  type MembershipBillingGateway,
} from '../membershipBilling.js';

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE store_config (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event TEXT,
      user_id INTEGER,
      ip_address TEXT,
      details TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      email TEXT,
      email_opt_in INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE membership_tiers (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      monthly_price REAL NOT NULL
    );
    CREATE TABLE customer_subscriptions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      tier_id INTEGER NOT NULL,
      blockchyp_token TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      current_period_start TEXT NOT NULL,
      current_period_end TEXT NOT NULL,
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
    CREATE TABLE subscription_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subscription_id INTEGER NOT NULL,
      amount REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'success',
      blockchyp_transaction_id TEXT,
      error_message TEXT,
      billing_run_id INTEGER,
      payment_provider TEXT NOT NULL DEFAULT 'blockchyp',
      processor_transaction_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE membership_billing_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      status TEXT NOT NULL DEFAULT 'running',
      mode TEXT NOT NULL DEFAULT 'manual',
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      finished_at TEXT,
      started_by INTEGER,
      total_due INTEGER NOT NULL DEFAULT 0,
      charged_count INTEGER NOT NULL DEFAULT 0,
      failed_count INTEGER NOT NULL DEFAULT 0,
      skipped_count INTEGER NOT NULL DEFAULT 0,
      result_json TEXT,
      error_message TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX idx_membership_billing_runs_one_running
      ON membership_billing_runs(status)
      WHERE status = 'running';
    CREATE TABLE notification_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      recipient TEXT NOT NULL,
      subject TEXT,
      body TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      error TEXT,
      retry_count INTEGER NOT NULL DEFAULT 0,
      max_retries INTEGER NOT NULL DEFAULT 3,
      scheduled_at TEXT,
      sent_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    INSERT INTO store_config (key, value) VALUES ('store_name', 'Bizarre Repair');
    INSERT INTO customers (id, first_name, last_name, email, email_opt_in)
      VALUES (1, 'Ada', 'Lovelace', 'ada@example.test', 1);
    INSERT INTO membership_tiers (id, name, monthly_price)
      VALUES (10, 'Gold', 25);
  `);
  return db;
}

function insertSubscription(
  db: Database.Database,
  overrides: Partial<Record<string, unknown>> = {},
): number {
  const row = {
    customer_id: 1,
    tier_id: 10,
    blockchyp_token: 'tok_123',
    status: 'active',
    current_period_start: '2026-03-06 13:00:00',
    current_period_end: '2026-04-06 13:00:00',
    cancel_at_period_end: 0,
    auto_renew: 1,
    failed_charge_count: 0,
    next_billing_attempt_at: null,
    billing_retry_stage: 0,
    payment_provider: 'blockchyp',
    ...overrides,
  };
  const result = db.prepare(`
    INSERT INTO customer_subscriptions (
      customer_id, tier_id, blockchyp_token, status, current_period_start,
      current_period_end, cancel_at_period_end, auto_renew, failed_charge_count,
      next_billing_attempt_at, billing_retry_stage, payment_provider
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    row.customer_id,
    row.tier_id,
    row.blockchyp_token,
    row.status,
    row.current_period_start,
    row.current_period_end,
    row.cancel_at_period_end,
    row.auto_renew,
    row.failed_charge_count,
    row.next_billing_attempt_at,
    row.billing_retry_stage,
    row.payment_provider,
  );
  return Number(result.lastInsertRowid);
}

function blockChypGateway(
  charge: MembershipBillingGateway['charge'],
): MembershipBillingGateway {
  return {
    key: 'blockchyp',
    canCharge: (subscription) => !!subscription.blockchyp_token,
    unavailableReason: (_db, subscription) => subscription.blockchyp_token ? null : 'No card on file',
    charge,
  };
}

describe('membership billing service', () => {
  it('charges due BlockChyp-token subscriptions and extends from the previous period end', async () => {
    const db = buildDb();
    const id = insertSubscription(db);
    const charge = vi.fn(async () => ({ success: true, transactionId: 'bc_tx_1' }));

    const result = await runMembershipBillingOnce(db, {
      mode: 'cron',
      source: 'cron',
      now: new Date('2026-05-06T12:00:00Z'),
      gateways: [blockChypGateway(charge)],
    });

    expect(result.skipped).toBe(false);
    expect(result.run).toMatchObject({ status: 'completed', total_due: 1, charged_count: 1 });
    expect(charge).toHaveBeenCalledTimes(1);

    const sub = db.prepare('SELECT * FROM customer_subscriptions WHERE id = ?').get(id) as Record<string, unknown>;
    expect(sub.status).toBe('active');
    expect(sub.current_period_start).toBe('2026-04-06 13:00:00');
    expect(sub.current_period_end).toBe('2026-05-06 13:00:00');
    expect(sub.last_charge_at).toBe('2026-05-06 12:00:00');
    expect(sub.failed_charge_count).toBe(0);
    expect(sub.next_billing_attempt_at).toBeNull();

    const payment = db.prepare('SELECT * FROM subscription_payments WHERE subscription_id = ?').get(id) as Record<string, unknown>;
    expect(payment).toMatchObject({
      status: 'success',
      blockchyp_transaction_id: 'bc_tx_1',
      payment_provider: 'blockchyp',
      processor_transaction_id: 'bc_tx_1',
      billing_run_id: result.run?.id,
    });
  });

  it('schedules day-one retry and queues dunning email after a failed charge', async () => {
    const db = buildDb();
    const id = insertSubscription(db, { current_period_end: '2026-05-06 11:00:00' });
    const charge = vi.fn(async () => ({ success: false, error: 'Insufficient funds' }));

    const result = await runMembershipBillingOnce(db, {
      mode: 'cron',
      source: 'cron',
      now: new Date('2026-05-06T12:00:00Z'),
      gateways: [blockChypGateway(charge)],
    });

    expect(result.run).toMatchObject({ total_due: 1, failed_count: 1 });
    const sub = db.prepare('SELECT * FROM customer_subscriptions WHERE id = ?').get(id) as Record<string, unknown>;
    expect(sub).toMatchObject({
      status: 'past_due',
      failed_charge_count: 1,
      billing_retry_stage: 1,
      next_billing_attempt_at: '2026-05-07 12:00:00',
      last_charge_error: 'Insufficient funds',
      auto_renew: 1,
    });

    const queued = db.prepare('SELECT * FROM notification_queue').all() as Record<string, unknown>[];
    expect(queued).toHaveLength(1);
    expect(queued[0]).toMatchObject({
      type: 'email',
      recipient: 'ada@example.test',
      status: 'pending',
    });

    const notDueCharge = vi.fn(async () => ({ success: true, transactionId: 'too_soon' }));
    const retryTooSoon = await runMembershipBillingOnce(db, {
      mode: 'cron',
      source: 'cron',
      now: new Date('2026-05-06T13:00:00Z'),
      gateways: [blockChypGateway(notDueCharge)],
    });
    expect(retryTooSoon.run).toMatchObject({ total_due: 0 });
    expect(notDueCharge).not.toHaveBeenCalled();
  });

  it('stops auto renewal and marks billing suspended after the final retry fails', async () => {
    const db = buildDb();
    const id = insertSubscription(db, {
      status: 'past_due',
      current_period_end: '2026-05-01 00:00:00',
      failed_charge_count: 3,
      billing_retry_stage: 3,
      next_billing_attempt_at: '2026-05-06 11:00:00',
    });
    const charge = vi.fn(async () => ({ success: false, error: 'Card expired' }));

    const result = await runMembershipBillingOnce(db, {
      mode: 'cron',
      source: 'cron',
      now: new Date('2026-05-06T12:00:00Z'),
      gateways: [blockChypGateway(charge)],
    });

    expect(result.results[0]).toMatchObject({
      status: 'failed',
      attempt_number: 4,
      final_failure: true,
      next_attempt_at: null,
    });
    const sub = db.prepare('SELECT * FROM customer_subscriptions WHERE id = ?').get(id) as Record<string, unknown>;
    expect(sub).toMatchObject({
      status: 'past_due',
      failed_charge_count: 4,
      auto_renew: 0,
      next_billing_attempt_at: null,
      billing_suspended_at: '2026-05-06 12:00:00',
    });
  });

  it('skips safely when another billing run is already active', async () => {
    const db = buildDb();
    insertSubscription(db);
    db.prepare(`
      INSERT INTO membership_billing_runs (status, mode, started_at, updated_at)
      VALUES ('running', 'manual', '2026-05-06 11:30:00', '2026-05-06 11:30:00')
    `).run();
    const charge = vi.fn(async () => ({ success: true, transactionId: 'bc_tx_1' }));

    const result = await runMembershipBillingOnce(db, {
      mode: 'cron',
      source: 'cron',
      now: new Date('2026-05-06T12:00:00Z'),
      gateways: [blockChypGateway(charge)],
    });

    expect(result.skipped).toBe(true);
    expect(result.message).toBe('A membership billing run is already in progress');
    expect(charge).not.toHaveBeenCalled();
  });

  it('allows a future gateway to charge non-BlockChyp subscriptions through the same runner', async () => {
    const db = buildDb();
    const id = insertSubscription(db, {
      blockchyp_token: null,
      payment_provider: 'stripe',
      current_period_end: '2026-05-06 11:00:00',
    });
    const stripeCharge = vi.fn(async () => ({ success: true, transactionId: 'stripe_tx_1' }));
    const stripeGateway: MembershipBillingGateway = {
      key: 'stripe',
      canCharge: (subscription) => subscription.payment_provider === 'stripe',
      unavailableReason: () => null,
      charge: stripeCharge,
    };

    await runMembershipBillingOnce(db, {
      mode: 'cron',
      source: 'cron',
      now: new Date('2026-05-06T12:00:00Z'),
      gateways: [stripeGateway],
    });

    expect(stripeCharge).toHaveBeenCalledTimes(1);
    const payment = db.prepare('SELECT * FROM subscription_payments WHERE subscription_id = ?').get(id) as Record<string, unknown>;
    expect(payment).toMatchObject({
      status: 'success',
      payment_provider: 'stripe',
      blockchyp_transaction_id: null,
      processor_transaction_id: 'stripe_tx_1',
    });
  });
});
