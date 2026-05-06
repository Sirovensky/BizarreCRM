import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import jwt from 'jsonwebtoken';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { config } from '../../config.js';

const mockState = vi.hoisted(() => ({
  masterDb: null as Database.Database | null,
}));

vi.mock('../../db/master-connection.js', () => ({
  getMasterDb: () => mockState.masterDb,
}));

let superAdminRouter: typeof import('../super-admin.routes.js').default | null = null;

function sqliteDate(offset: number): string {
  return `2026-01-0${offset} 00:00:00`;
}

function buildMasterDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE tenants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      slug TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      domain TEXT,
      plan TEXT NOT NULL DEFAULT 'free',
      status TEXT NOT NULL DEFAULT 'active',
      db_path TEXT NOT NULL,
      admin_email TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE super_admins (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      is_active INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE super_admin_sessions (
      id TEXT PRIMARY KEY,
      super_admin_id INTEGER NOT NULL,
      expires_at TEXT NOT NULL
    );
    CREATE TABLE tenant_auth_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenant_id INTEGER,
      tenant_slug TEXT,
      event TEXT NOT NULL,
      user_id INTEGER,
      username TEXT,
      ip_address TEXT,
      user_agent TEXT,
      details TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE master_audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      super_admin_id INTEGER,
      action TEXT NOT NULL,
      details TEXT,
      ip_address TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  db.prepare('INSERT INTO super_admins (id, username, is_active) VALUES (1, ?, 1)').run('root');
  db.prepare('INSERT INTO super_admin_sessions (id, super_admin_id, expires_at) VALUES (?, 1, ?)')
    .run('test-session', '2099-01-01 00:00:00');

  const insert = db.prepare(`
    INSERT INTO tenants (slug, name, plan, status, db_path, admin_email, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);
  [
    ['alpha-shop', 'Alpha Shop', 'free', 'active', 'alpha.db', 'alpha@example.com', sqliteDate(1)],
    ['beta-shop', 'Beta Shop', 'pro', 'active', 'beta.db', 'beta@example.com', sqliteDate(2)],
    ['gamma-shop', 'Gamma Shop', 'pro', 'active', 'gamma.db', 'gamma@example.com', sqliteDate(3)],
    ['delta-shop', 'Delta Shop', 'free', 'suspended', 'delta.db', 'delta@example.com', sqliteDate(4)],
    ['epsilon-shop', 'Epsilon Shop', 'free', 'deleted', 'epsilon.db', 'epsilon@example.com', sqliteDate(5)],
  ].forEach(([slug, name, plan, status, dbPath, email, createdAt]) => {
    insert.run(slug, name, plan, status, dbPath, email, createdAt, createdAt);
  });

  db.prepare(`
    INSERT INTO tenant_auth_events (tenant_id, tenant_slug, event, created_at)
    VALUES (?, ?, ?, ?)
  `).run(1, 'alpha-shop', 'login_success', '2026-02-02 12:00:00');
  db.prepare(`
    INSERT INTO tenant_auth_events (tenant_id, tenant_slug, event, created_at)
    VALUES (?, ?, ?, ?)
  `).run(2, 'beta-shop', 'login_failed', '2026-02-03 12:00:00');
  db.prepare(`
    INSERT INTO master_audit_log (action, details, ip_address, created_at)
    VALUES (?, ?, ?, ?)
  `).run(
    'tenant_suspended',
    JSON.stringify({ slug: 'delta-shop', tenant_id: 4, previous_status: 'active' }),
    '127.0.0.1',
    '2026-02-04 12:00:00',
  );
  db.prepare(`
    INSERT INTO master_audit_log (action, details, ip_address, created_at)
    VALUES (?, ?, ?, ?)
  `).run(
    'tenant_suspended',
    JSON.stringify({ slug: 'alpha-shop', tenant_id: 1, previous_status: 'active' }),
    '127.0.0.1',
    '2026-01-20 12:00:00',
  );

  return db;
}

function authToken(): string {
  return jwt.sign(
    { superAdminId: 1, sessionId: 'test-session', role: 'super_admin' },
    config.superAdminSecret,
    {
      algorithm: 'HS256',
      issuer: 'bizarre-crm',
      audience: 'bizarre-crm-super-admin',
      expiresIn: '30m',
    },
  );
}

function createApp(): Express {
  const app = express();
  app.use(express.json());
  if (!superAdminRouter) throw new Error('super-admin router was not loaded');
  app.use('/super-admin/api', superAdminRouter);
  return app;
}

async function getJson(app: Express, path: string) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      headers: { authorization: `Bearer ${authToken()}` },
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

beforeEach(async () => {
  mockState.masterDb = buildMasterDb();
  superAdminRouter ??= (await import('../super-admin.routes.js')).default;
});

afterEach(() => {
  mockState.masterDb?.close();
  mockState.masterDb = null;
});

describe('super-admin tenant pagination', () => {
  it('returns paginated tenant rows with totals and redacted db paths', async () => {
    const app = createApp();

    const response = await getJson(
      app,
      '/super-admin/api/tenants?page=2&per_page=2&status=active&search=Shop',
    );

    expect(response.status).toBe(200);
    expect(response.body.data.pagination).toMatchObject({
      page: 2,
      per_page: 2,
      total: 3,
      total_pages: 2,
      search: 'Shop',
      sort: 'created_at',
      order: 'desc',
    });
    expect(response.body.data.tenants).toHaveLength(1);
    expect(response.body.data.tenants[0]).toMatchObject({
      slug: 'alpha-shop',
      db_size_mb: 0,
      last_active: '2026-02-02 12:00:00',
      suspended_at: null,
    });
    expect(response.body.data.tenants[0]).not.toHaveProperty('db_path');
  });

  it('keeps the legacy unpaginated list shape when no page params are sent', async () => {
    const app = createApp();

    const response = await getJson(app, '/super-admin/api/tenants?search=Shop');

    expect(response.status).toBe(200);
    expect(response.body.data.pagination).toBeUndefined();
    expect(response.body.data.tenants.map((tenant: { slug: string }) => tenant.slug)).toEqual([
      'delta-shop',
      'gamma-shop',
      'beta-shop',
      'alpha-shop',
    ]);
    expect(response.body.data.tenants.find((tenant: { slug: string }) => tenant.slug === 'delta-shop')).toMatchObject({
      suspended_at: '2026-02-04 12:00:00',
    });
    expect(response.body.data.tenants.find((tenant: { slug: string }) => tenant.slug === 'beta-shop')).toMatchObject({
      last_active: null,
    });
  });

  it('caps out-of-bounds tenant pages and exposes pagination metadata', async () => {
    const app = createApp();

    const response = await getJson(
      app,
      '/super-admin/api/tenants?page=999999999&per_page=2&status=active&search=Shop',
    );

    expect(response.status).toBe(200);
    expect(response.body.data.pagination).toMatchObject({
      page: 2,
      per_page: 2,
      total: 3,
      total_pages: 2,
      out_of_bounds: true,
      requested_page: 999999999,
    });
    expect(response.body.data.tenants.map((tenant: { slug: string }) => tenant.slug)).toEqual([
      'alpha-shop',
    ]);
  });
});

describe('super-admin platform config schema', () => {
  it('marks active, dead, and coming-soon platform config fields', async () => {
    const app = createApp();

    const response = await getJson(app, '/super-admin/api/config/schema');

    expect(response.status).toBe(200);
    const fields = response.body.data.fields as Array<{
      key: string;
      status?: string;
      statusReason?: string;
    }>;
    const byKey = Object.fromEntries(fields.map((field) => [field.key, field]));

    expect(byKey.management_api_enabled).toMatchObject({ status: 'active' });
    expect(byKey.management_rate_limit_bypass).toMatchObject({ status: 'dead' });
    expect(byKey.management_rate_limit_bypass.statusReason).toContain('rate limiter');
    expect(byKey.telemetry_opt_in).toMatchObject({ status: 'coming_soon' });
    expect(byKey.telemetry_opt_in.statusReason).toContain('telemetry');
  });
});
