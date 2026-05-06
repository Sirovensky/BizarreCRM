import express, { type Express } from 'express';
import { request as httpRequest } from 'node:http';
import type { AddressInfo } from 'node:net';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import portalRouter from '../portal.routes.js';
import { errorHandler } from '../../middleware/errorHandler.js';
import type { AsyncDb, TxQuery } from '../../db/async-db.js';
import { config } from '../../config.js';
import { sendSms } from '../../services/smsProvider.js';

vi.mock('../../services/smsProvider.js', () => ({
  sendSms: vi.fn(),
  sendSmsTenant: vi.fn(),
}));

type PortalCaptchaConfigSnapshot = Pick<
  typeof config,
  | 'portalCaptchaProvider'
  | 'portalCaptchaSiteKey'
  | 'portalCaptchaSecret'
  | 'portalCaptchaEnabled'
  | 'portalCaptchaSeenIpTtlHours'
  | 'portalRecaptchaMinScore'
>;

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
    CREATE TABLE rate_limits (
      category TEXT NOT NULL,
      key TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      first_attempt INTEGER NOT NULL,
      locked_until INTEGER,
      PRIMARY KEY (category, key)
    );
    CREATE TABLE store_config (
      key TEXT PRIMARY KEY,
      value TEXT
    );
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY,
      first_name TEXT,
      phone TEXT,
      mobile TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      portal_verified INTEGER NOT NULL DEFAULT 0,
      sms_consent_transactional INTEGER NOT NULL DEFAULT 1,
      sms_opt_in INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE customer_phones (
      id INTEGER PRIMARY KEY,
      customer_id INTEGER NOT NULL,
      phone TEXT NOT NULL
    );
    CREATE TABLE portal_verification_codes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      phone TEXT NOT NULL,
      code TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL,
      used INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE portal_sessions (
      id TEXT PRIMARY KEY,
      customer_id INTEGER NOT NULL,
      token TEXT NOT NULL UNIQUE,
      scope TEXT NOT NULL DEFAULT 'ticket',
      ticket_id INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL,
      last_used_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE portal_captcha_seen_ips (
      ip_hash TEXT PRIMARY KEY,
      provider TEXT NOT NULL,
      first_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL
    );

    INSERT INTO store_config (key, value) VALUES ('store_name', 'Bizarre Test Shop');
    INSERT INTO customers (id, first_name, phone, mobile, portal_verified, sms_consent_transactional, sms_opt_in)
      VALUES (10, 'Casey', '(303) 555-1212', NULL, 0, 1, 1);
  `);
  return db;
}

function createApp(db: Database.Database): Express {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    req.db = db;
    req.asyncDb = createInlineAsyncDb(db);
    next();
  });
  app.use('/portal', portalRouter);
  app.use(errorHandler);
  return app;
}

async function requestJson(app: Express, method: string, path: string, body?: unknown) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const payload = body === undefined ? undefined : JSON.stringify(body);

    return await new Promise<{ status: number; body: any }>((resolve, reject) => {
      const req = httpRequest({
        hostname: '127.0.0.1',
        port,
        path,
        method,
        headers: payload === undefined ? undefined : {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(payload),
        },
      }, (res) => {
        const chunks: Buffer[] = [];
        res.on('data', chunk => chunks.push(Buffer.from(chunk)));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          resolve({
            status: res.statusCode ?? 0,
            body: text ? JSON.parse(text) : null,
          });
        });
      });
      req.on('error', reject);
      if (payload !== undefined) req.write(payload);
      req.end();
    });
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  }
}

let db: Database.Database | null = null;
let originalCaptchaConfig: PortalCaptchaConfigSnapshot;

function enablePortalCaptcha(provider: 'hcaptcha' | 'turnstile' | 'recaptcha' = 'hcaptcha') {
  config.portalCaptchaProvider = provider;
  config.portalCaptchaSiteKey = 'site-key';
  config.portalCaptchaSecret = 'secret-key';
  config.portalCaptchaEnabled = true;
  config.portalCaptchaSeenIpTtlHours = 24;
  config.portalRecaptchaMinScore = 0;
}

beforeEach(() => {
  originalCaptchaConfig = {
    portalCaptchaProvider: config.portalCaptchaProvider,
    portalCaptchaSiteKey: config.portalCaptchaSiteKey,
    portalCaptchaSecret: config.portalCaptchaSecret,
    portalCaptchaEnabled: config.portalCaptchaEnabled,
    portalCaptchaSeenIpTtlHours: config.portalCaptchaSeenIpTtlHours,
    portalRecaptchaMinScore: config.portalRecaptchaMinScore,
  };
  vi.mocked(sendSms).mockResolvedValue({ success: true, providerName: 'mock' });
});

afterEach(() => {
  Object.assign(config, originalCaptchaConfig);
  vi.restoreAllMocks();
  db?.close();
  db = null;
});

describe('portal register/send-code CAPTCHA gate', () => {
  it('stays off when portal CAPTCHA site key and secret are not configured', async () => {
    db = buildDb();
    config.portalCaptchaProvider = 'hcaptcha';
    config.portalCaptchaSiteKey = '';
    config.portalCaptchaSecret = '';
    config.portalCaptchaEnabled = false;

    const response = await requestJson(createApp(db), 'POST', '/portal/register/send-code', {
      phone: '(303) 555-1212',
    });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ success: true, data: { sent: true } });
    expect(sendSms).toHaveBeenCalledTimes(1);
  });

  it('requires a CAPTCHA token for the first unseen registration IP', async () => {
    db = buildDb();
    enablePortalCaptcha();
    const providerFetch = vi.spyOn(globalThis, 'fetch');

    const response = await requestJson(createApp(db), 'POST', '/portal/register/send-code', {
      phone: '(303) 555-1212',
    });

    expect(response.status).toBe(403);
    expect(response.body).toMatchObject({
      success: false,
      data: { captcha_required: true },
    });
    expect(providerFetch).not.toHaveBeenCalled();
    expect(sendSms).not.toHaveBeenCalled();
    const codes = db.prepare('SELECT COUNT(*) AS n FROM portal_verification_codes').get() as { n: number };
    expect(codes.n).toBe(0);
  });

  it('records a valid CAPTCHA by IP TTL and skips provider verification while fresh', async () => {
    db = buildDb();
    enablePortalCaptcha('turnstile');
    const providerFetch = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );

    const app = createApp(db);
    const first = await requestJson(app, 'POST', '/portal/register/send-code', {
      phone: '(303) 555-1212',
      captcha_token: 'valid-token',
    });

    expect(first.status).toBe(200);
    expect(providerFetch).toHaveBeenCalledTimes(1);
    expect(String(providerFetch.mock.calls[0][0])).toBe('https://challenges.cloudflare.com/turnstile/v0/siteverify');
    const seen = db.prepare('SELECT provider, expires_at FROM portal_captcha_seen_ips').get() as { provider: string; expires_at: string } | undefined;
    expect(seen?.provider).toBe('turnstile');

    db.prepare("DELETE FROM rate_limits WHERE category = 'portal_send_code_ip'").run();
    const second = await requestJson(app, 'POST', '/portal/register/send-code', {
      phone: '(303) 555-1212',
    });

    expect(second.status).toBe(200);
    expect(providerFetch).toHaveBeenCalledTimes(1);
    expect(sendSms).toHaveBeenCalledTimes(2);
  });
});
