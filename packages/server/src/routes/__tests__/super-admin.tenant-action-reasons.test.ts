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

vi.mock('../../middleware/stepUpTotp.js', () => ({
  requireStepUpTotpSuperAdmin: () => (_req: unknown, _res: unknown, next: () => void) => next(),
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
    INSERT INTO tenants (slug, name, plan, status, db_path, admin_email, created_at, updated_at)
    VALUES (?, ?, 'free', ?, ?, ?, '2026-05-06 12:00:00', '2026-05-06 12:00:00')
  `).run('acme-shop', 'Acme Shop', 'active', 'acme.db', 'admin@acme.test');
  db.prepare(`
    INSERT INTO tenants (slug, name, plan, status, db_path, admin_email, created_at, updated_at)
    VALUES (?, ?, 'free', ?, ?, ?, '2026-05-06 12:00:00', '2026-05-06 12:00:00')
  `).run('paused-shop', 'Paused Shop', 'suspended', 'paused.db', 'admin@paused.test');

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

async function postJson(app: Express, path: string, body?: unknown) {
  const server = app.listen(0);
  try {
    const { port } = server.address() as AddressInfo;
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
      method: 'POST',
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
});

describe('super-admin tenant action reasons', () => {
  it('requires a reason before suspending a tenant', async () => {
    const app = createApp();

    const response = await postJson(app, '/super-admin/api/tenants/acme-shop/suspend', {});

    expect(response.status).toBe(400);
    expect(response.body.message).toContain('Suspension reason is required');
    expect(mockState.masterDb!.prepare('SELECT status FROM tenants WHERE slug = ?').get('acme-shop')).toMatchObject({
      status: 'active',
    });
    expect(mockState.masterDb!.prepare("SELECT COUNT(*) AS count FROM master_audit_log WHERE action = 'tenant_suspended'").get()).toMatchObject({
      count: 0,
    });
  });

  it('persists the suspension reason in the master audit log', async () => {
    const app = createApp();

    const response = await postJson(app, '/super-admin/api/tenants/acme-shop/suspend', {
      reason: 'Non-payment after support escalation',
    });

    expect(response.status).toBe(200);
    expect(mockState.masterDb!.prepare('SELECT status FROM tenants WHERE slug = ?').get('acme-shop')).toMatchObject({
      status: 'suspended',
    });

    const auditRow = mockState.masterDb!
      .prepare("SELECT details FROM master_audit_log WHERE action = 'tenant_suspended'")
      .get() as { details: string };
    expect(JSON.parse(auditRow.details)).toMatchObject({
      slug: 'acme-shop',
      tenant_id: 1,
      previous_status: 'active',
      reason: 'Non-payment after support escalation',
    });
  });

  it('allows activation without a reason and audits a supplied reason', async () => {
    const app = createApp();

    const first = await postJson(app, '/super-admin/api/tenants/paused-shop/activate', {});
    expect(first.status).toBe(200);

    mockState.masterDb!
      .prepare("UPDATE tenants SET status = 'suspended' WHERE slug = ?")
      .run('paused-shop');
    const second = await postJson(app, '/super-admin/api/tenants/paused-shop/activate', {
      reason: 'Balance cleared by owner',
    });

    expect(second.status).toBe(200);
    const auditRows = mockState.masterDb!
      .prepare("SELECT details FROM master_audit_log WHERE action = 'tenant_activated' ORDER BY id")
      .all() as Array<{ details: string }>;
    expect(JSON.parse(auditRows[0]!.details)).toMatchObject({
      slug: 'paused-shop',
      reason: null,
    });
    expect(JSON.parse(auditRows[1]!.details)).toMatchObject({
      slug: 'paused-shop',
      reason: 'Balance cleared by owner',
    });
  });
});
