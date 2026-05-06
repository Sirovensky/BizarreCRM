import express, { type Express } from 'express';
import type { AddressInfo } from 'net';
import Database from 'better-sqlite3';
import jwt from 'jsonwebtoken';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { config } from '../../config.js';
import { PLAN_DEFINITIONS } from '@bizarre-crm/shared';

const mockState = vi.hoisted(() => ({
  masterDb: null as Database.Database | null,
  tenantDbs: new Map<string, Database.Database>(),
}));

vi.mock('../../db/master-connection.js', () => ({
  getMasterDb: () => mockState.masterDb,
}));

vi.mock('../../middleware/stepUpTotp.js', () => ({
  requireStepUpTotpSuperAdmin: () => (_req: unknown, _res: unknown, next: () => void) => next(),
}));

vi.mock('../../db/tenant-pool.js', () => ({
  getTenantDb: vi.fn(async (slug: string) => {
    const db = mockState.tenantDbs.get(slug);
    if (!db) throw new Error(`tenant db not found: ${slug}`);
    return db;
  }),
  releaseTenantDb: vi.fn(),
  getPoolStats: () => ({ size: mockState.tenantDbs.size, maxSize: 10 }),
  closeAllTenantDbs: vi.fn(),
}));

let superAdminRouter: typeof import('../super-admin.routes.js').default | null = null;

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
      max_tickets_month INTEGER,
      max_users INTEGER,
      storage_limit_mb INTEGER,
      trial_ends_at TEXT,
      stripe_customer_id TEXT,
      stripe_subscription_id TEXT,
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
  db.prepare(`
    INSERT INTO tenants (
      slug, name, plan, status, db_path, admin_email,
      max_tickets_month, max_users, storage_limit_mb,
      created_at, updated_at
    )
    VALUES (?, ?, 'free', 'active', ?, ?, ?, ?, ?, '2026-05-06 12:00:00', '2026-05-06 12:00:00')
  `).run(
    'acme-shop',
    'Acme Shop',
    'acme.db',
    'admin@acme.test',
    PLAN_DEFINITIONS.free.limits.maxTicketsMonth,
    PLAN_DEFINITIONS.free.limits.maxUsers,
    PLAN_DEFINITIONS.free.limits.storageLimitMb,
  );

  const tenantDb = new Database(':memory:');
  tenantDb.exec('CREATE TABLE store_config (key TEXT PRIMARY KEY, value TEXT)');
  tenantDb
    .prepare("INSERT INTO store_config (key, value) VALUES ('store_name', ?)")
    .run('Acme Shop');
  mockState.tenantDbs.set('acme-shop', tenantDb);

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

async function putJson(app: Express, path: string, body?: unknown) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: 'PUT',
      headers: {
        authorization: `Bearer ${authToken()}`,
        'content-type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
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
  for (const db of mockState.tenantDbs.values()) db.close();
  mockState.tenantDbs.clear();
});

describe('super-admin tenant plan updates', () => {
  it('updates the plan using shared vocabulary, resets plan limits, and audits the change', async () => {
    const app = createApp();

    const response = await putJson(app, '/super-admin/api/tenants/acme-shop', { plan: 'pro' });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      success: true,
      data: {
        slug: 'acme-shop',
        plan: 'pro',
        max_tickets_month: 999999,
        max_users: 999999,
        storage_limit_mb: PLAN_DEFINITIONS.pro.limits.storageLimitMb,
      },
    });
    expect(mockState.masterDb!.prepare('SELECT plan, max_tickets_month, max_users, storage_limit_mb FROM tenants WHERE slug = ?').get('acme-shop')).toMatchObject({
      plan: 'pro',
      max_tickets_month: 999999,
      max_users: 999999,
      storage_limit_mb: PLAN_DEFINITIONS.pro.limits.storageLimitMb,
    });

    const audit = mockState.masterDb!.prepare("SELECT details FROM master_audit_log WHERE action = 'tenant_updated'").get() as { details: string };
    const details = JSON.parse(audit.details) as Record<string, any>;
    expect(details).toMatchObject({
      slug: 'acme-shop',
      before: {
        plan: 'free',
        max_tickets_month: PLAN_DEFINITIONS.free.limits.maxTicketsMonth,
        max_users: PLAN_DEFINITIONS.free.limits.maxUsers,
        storage_limit_mb: PLAN_DEFINITIONS.free.limits.storageLimitMb,
      },
      after: {
        plan: 'pro',
        max_tickets_month: 999999,
        max_users: 999999,
        storage_limit_mb: PLAN_DEFINITIONS.pro.limits.storageLimitMb,
      },
    });
    expect(details.fields).toEqual(expect.arrayContaining(['plan', 'max_tickets_month', 'max_users', 'storage_limit_mb']));
  });

  it('rejects plan names outside the shared plan definitions', async () => {
    const app = createApp();

    const response = await putJson(app, '/super-admin/api/tenants/acme-shop', { plan: 'enterprise' });

    expect(response.status).toBe(400);
    expect(response.body.message).toContain('plan must be one of: free, pro');
    expect(mockState.masterDb!.prepare('SELECT plan FROM tenants WHERE slug = ?').get('acme-shop')).toMatchObject({
      plan: 'free',
    });
    expect(mockState.masterDb!.prepare("SELECT COUNT(*) AS count FROM master_audit_log WHERE action = 'tenant_updated'").get()).toMatchObject({
      count: 0,
    });
  });

  it('renames the tenant display name and tenant store name without changing identity fields', async () => {
    const app = createApp();

    const response = await putJson(app, '/super-admin/api/tenants/acme-shop', { name: '  Acme Repair Depot  ' });

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      success: true,
      data: {
        slug: 'acme-shop',
        name: 'Acme Repair Depot',
        db_path: 'acme.db',
      },
    });
    expect(mockState.masterDb!.prepare('SELECT slug, name, db_path FROM tenants WHERE slug = ?').get('acme-shop')).toMatchObject({
      slug: 'acme-shop',
      name: 'Acme Repair Depot',
      db_path: 'acme.db',
    });
    expect(mockState.tenantDbs.get('acme-shop')!.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get()).toMatchObject({
      value: 'Acme Repair Depot',
    });

    const audit = mockState.masterDb!.prepare("SELECT details FROM master_audit_log WHERE action = 'tenant_updated'").get() as { details: string };
    const details = JSON.parse(audit.details) as Record<string, any>;
    expect(details.fields).toEqual(['name']);
    expect(details.before).toMatchObject({ name: 'Acme Shop' });
    expect(details.after).toMatchObject({ name: 'Acme Repair Depot' });
  });

  it('rejects invalid tenant names before mutating master or tenant DB state', async () => {
    const app = createApp();

    const response = await putJson(app, '/super-admin/api/tenants/acme-shop', { name: 'Bad\u202EName' });

    expect(response.status).toBe(400);
    expect(response.body.message).toContain('name contains disallowed control or bidi codepoints');
    expect(mockState.masterDb!.prepare('SELECT slug, name, db_path FROM tenants WHERE slug = ?').get('acme-shop')).toMatchObject({
      slug: 'acme-shop',
      name: 'Acme Shop',
      db_path: 'acme.db',
    });
    expect(mockState.tenantDbs.get('acme-shop')!.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get()).toMatchObject({
      value: 'Acme Shop',
    });
  });
});
