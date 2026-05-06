import { beforeEach, describe, expect, it, vi } from 'vitest';
import Database from 'better-sqlite3';
import { setConfigValue } from '../../utils/configEncryption.js';

const stripePaymentIntentsRetrieveMock = vi.hoisted(() => vi.fn());

vi.mock('stripe', () => ({
  default: vi.fn().mockImplementation(() => ({
    accounts: { retrieveCurrent: vi.fn() },
    checkout: { sessions: { create: vi.fn() } },
    paymentIntents: {
      create: vi.fn(),
      retrieve: stripePaymentIntentsRetrieveMock,
    },
    refunds: { create: vi.fn() },
    webhooks: { constructEvent: vi.fn() },
  })),
}));

import {
  getTenantStripeConfig,
  handleTenantStripeEvent,
  isTenantStripeCheckoutEnabled,
  isTenantStripeEnabled,
  verifyTenantStripePaymentIntent,
} from '../tenantStripe.js';

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE store_config (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE users (
      id INTEGER PRIMARY KEY,
      role TEXT,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY,
      order_id TEXT,
      total REAL NOT NULL,
      amount_paid REAL NOT NULL DEFAULT 0,
      amount_due REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'unpaid',
      updated_at TEXT
    );
    CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      amount REAL NOT NULL,
      method TEXT NOT NULL,
      method_detail TEXT,
      transaction_id TEXT,
      processor TEXT,
      reference TEXT,
      processor_transaction_id TEXT,
      processor_response TEXT,
      capture_state TEXT,
      notes TEXT,
      user_id INTEGER NOT NULL,
      created_at TEXT,
      updated_at TEXT
    );
    CREATE TABLE payment_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      token TEXT NOT NULL UNIQUE,
      invoice_id INTEGER,
      customer_id INTEGER,
      amount_cents INTEGER NOT NULL,
      description TEXT,
      provider TEXT NOT NULL DEFAULT 'stripe',
      status TEXT NOT NULL DEFAULT 'active',
      paid_at TEXT,
      processor_checkout_id TEXT,
      processor_payment_intent_id TEXT,
      processor_checkout_url TEXT,
      processor_status TEXT,
      processor_response TEXT,
      created_by_user_id INTEGER
    );
    CREATE TABLE tenant_stripe_webhook_events (
      stripe_event_id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      payment_link_id INTEGER,
      payment_intent_id TEXT,
      status TEXT NOT NULL DEFAULT 'processing',
      error TEXT,
      processed_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  db.prepare("INSERT INTO users (id, role, is_active) VALUES (1, 'admin', 1)").run();
  return db;
}

describe('tenant Stripe customer payments', () => {
  beforeEach(() => {
    stripePaymentIntentsRetrieveMock.mockReset();
  });

  it('reads encrypted tenant Stripe settings without env keys', () => {
    const db = buildDb();
    setConfigValue(db, 'stripe_secret_key', 'sk_test_abc123');
    setConfigValue(db, 'stripe_publishable_key', 'pk_test_abc123');
    setConfigValue(db, 'stripe_webhook_secret', 'whsec_abc123');

    expect(isTenantStripeEnabled(db)).toBe(true);
    expect(getTenantStripeConfig(db)).toMatchObject({
      secretKey: 'sk_test_abc123',
      publishableKey: 'pk_test_abc123',
      webhookSecret: 'whsec_abc123',
      enabled: true,
    });

    const stored = db.prepare("SELECT value FROM store_config WHERE key = 'stripe_secret_key'").get() as { value: string };
    expect(stored.value).toMatch(/^enc:v1:/);
  });

  it('does not enable hosted checkout until the webhook secret is configured', () => {
    const db = buildDb();
    setConfigValue(db, 'stripe_secret_key', 'sk_test_abc123');
    setConfigValue(db, 'stripe_publishable_key', 'pk_test_abc123');

    expect(isTenantStripeEnabled(db)).toBe(true);
    expect(isTenantStripeCheckoutEnabled(db)).toBe(false);

    setConfigValue(db, 'stripe_webhook_secret', 'whsec_abc123');
    expect(isTenantStripeCheckoutEnabled(db)).toBe(true);
  });

  it('verifies PaymentIntent amount, currency, and CRM metadata before recording', async () => {
    const db = buildDb();
    setConfigValue(db, 'stripe_secret_key', 'sk_test_abc123');
    setConfigValue(db, 'stripe_publishable_key', 'pk_test_abc123');
    setConfigValue(db, 'stripe_webhook_secret', 'whsec_abc123');
    db.prepare("INSERT OR REPLACE INTO store_config (key, value) VALUES ('store_currency', 'USD')").run();

    stripePaymentIntentsRetrieveMock.mockResolvedValue({
      id: 'pi_test_123',
      status: 'succeeded',
      amount: 1250,
      amount_received: 1250,
      currency: 'usd',
      latest_charge: 'ch_test_123',
      metadata: {
        source: 'invoice',
        invoice_id: '10',
        customer_id: '12',
      },
    });

    await expect(verifyTenantStripePaymentIntent(db, 'pi_test_123', 1250, {
      allowedSources: ['invoice'],
      expectedInvoiceId: 10,
      expectedCustomerId: 12,
    })).resolves.toMatchObject({
      id: 'pi_test_123',
      amountReceivedCents: 1250,
      latestChargeId: 'ch_test_123',
    });

    await expect(verifyTenantStripePaymentIntent(db, 'pi_test_123', 1200, {
      allowedSources: ['invoice'],
      expectedInvoiceId: 10,
      expectedCustomerId: 12,
    })).rejects.toThrow('amount does not match');

    await expect(verifyTenantStripePaymentIntent(db, 'pi_test_123', 1250, {
      allowedSources: ['pos'],
    })).rejects.toThrow('not created for this payment flow');

    await expect(verifyTenantStripePaymentIntent(db, 'pi_test_123', 1250, {
      allowedSources: ['invoice'],
      expectedInvoiceId: 99,
      expectedCustomerId: 12,
    })).rejects.toThrow('invoice metadata does not match');
  });

  it('marks a payment link and invoice paid only from Stripe webhook metadata', () => {
    const db = buildDb();
    db.prepare(`
      INSERT INTO invoices (id, order_id, total, amount_paid, amount_due, status)
      VALUES (10, 'INV-10', 25, 0, 25, 'unpaid')
    `).run();
    db.prepare(`
      INSERT INTO payment_links (id, token, invoice_id, amount_cents, provider, status, created_by_user_id)
      VALUES (7, 'tok_12345678901234567890123456789012', 10, 1250, 'stripe', 'active', 1)
    `).run();

    const event = {
      id: 'evt_checkout_paid',
      type: 'checkout.session.completed',
      data: {
        object: {
          id: 'cs_test_123',
          amount_total: 1250,
          payment_status: 'paid',
          payment_intent: 'pi_test_123',
          metadata: {
            source: 'payment_link',
            payment_link_id: '7',
            payment_link_token: 'tok_12345678901234567890123456789012',
          },
          url: 'https://checkout.stripe.test/session',
        },
      },
    } as any;

    expect(handleTenantStripeEvent(db, 'demo-shop', event)).toMatchObject({
      status: 'processed',
      paymentLinkId: 7,
      paymentIntentId: 'pi_test_123',
    });

    expect(db.prepare('SELECT status, processor_payment_intent_id FROM payment_links WHERE id = 7').get()).toMatchObject({
      status: 'paid',
      processor_payment_intent_id: 'pi_test_123',
    });
    expect(db.prepare('SELECT amount_paid, amount_due, status FROM invoices WHERE id = 10').get()).toMatchObject({
      amount_paid: 12.5,
      amount_due: 12.5,
      status: 'partial',
    });
    expect(db.prepare('SELECT amount, method, processor, processor_transaction_id FROM payments').get()).toMatchObject({
      amount: 12.5,
      method: 'Stripe',
      processor: 'stripe',
      processor_transaction_id: 'pi_test_123',
    });

    expect(handleTenantStripeEvent(db, 'demo-shop', event)).toMatchObject({ status: 'duplicate' });
    expect(db.prepare('SELECT COUNT(*) AS c FROM payments').get()).toMatchObject({ c: 1 });
  });

  it('records failed webhook attempts but lets Stripe retry the same event id', () => {
    const db = buildDb();
    db.prepare(`
      INSERT INTO invoices (id, order_id, total, amount_paid, amount_due, status)
      VALUES (10, 'INV-10', 25, 0, 25, 'unpaid')
    `).run();
    db.prepare(`
      INSERT INTO payment_links (id, token, invoice_id, amount_cents, provider, status, created_by_user_id)
      VALUES (7, 'tok_12345678901234567890123456789012', 10, 1250, 'stripe', 'active', 1)
    `).run();

    const event = {
      id: 'evt_retry_after_failure',
      type: 'checkout.session.completed',
      data: {
        object: {
          id: 'cs_test_retry',
          amount_total: 1200,
          payment_status: 'paid',
          payment_intent: 'pi_test_retry',
          metadata: {
            source: 'payment_link',
            payment_link_id: '7',
            payment_link_token: 'tok_12345678901234567890123456789012',
          },
          url: 'https://checkout.stripe.test/session',
        },
      },
    } as any;

    expect(() => handleTenantStripeEvent(db, 'demo-shop', event)).toThrow('amount does not match');
    expect(db.prepare('SELECT status FROM tenant_stripe_webhook_events WHERE stripe_event_id = ?').get(event.id)).toMatchObject({
      status: 'failed',
    });
    expect(db.prepare('SELECT COUNT(*) AS c FROM payments').get()).toMatchObject({ c: 0 });

    event.data.object.amount_total = 1250;
    expect(handleTenantStripeEvent(db, 'demo-shop', event)).toMatchObject({
      status: 'processed',
      paymentLinkId: 7,
      paymentIntentId: 'pi_test_retry',
    });
    expect(db.prepare('SELECT status FROM tenant_stripe_webhook_events WHERE stripe_event_id = ?').get(event.id)).toMatchObject({
      status: 'processed',
    });
    expect(db.prepare('SELECT COUNT(*) AS c FROM payments').get()).toMatchObject({ c: 1 });
  });
});
