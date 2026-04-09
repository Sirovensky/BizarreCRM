import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';

let masterDb: Database.Database | null = null;

/**
 * Initialize the master database (multi-tenant mode only).
 * Creates the DB file and schema if they don't exist.
 */
export function initMasterDb(): void {
  if (!config.multiTenant) return;

  const dir = path.dirname(config.masterDbPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  masterDb = new Database(config.masterDbPath);
  masterDb.pragma('journal_mode = WAL');
  masterDb.pragma('foreign_keys = ON');
  masterDb.pragma('busy_timeout = 5000');

  // Create schema
  masterDb.exec(`
    CREATE TABLE IF NOT EXISTS tenants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      slug TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      domain TEXT,
      plan TEXT NOT NULL DEFAULT 'free',
      status TEXT NOT NULL DEFAULT 'active',
      db_path TEXT NOT NULL,
      admin_email TEXT NOT NULL,
      max_users INTEGER NOT NULL DEFAULT 5,
      max_tickets_month INTEGER NOT NULL DEFAULT 500,
      storage_limit_mb INTEGER NOT NULL DEFAULT 500,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS super_admins (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      password_set INTEGER NOT NULL DEFAULT 0,
      totp_secret_enc TEXT,
      totp_secret_iv TEXT,
      totp_secret_tag TEXT,
      totp_enabled INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      last_login_at TEXT,
      last_login_ip TEXT,
      failed_login_count INTEGER NOT NULL DEFAULT 0,
      locked_until TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS super_admin_sessions (
      id TEXT PRIMARY KEY,
      super_admin_id INTEGER NOT NULL REFERENCES super_admins(id),
      ip_address TEXT,
      user_agent TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tenant_usage (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenant_id INTEGER NOT NULL REFERENCES tenants(id),
      month TEXT NOT NULL,
      tickets_created INTEGER NOT NULL DEFAULT 0,
      sms_sent INTEGER NOT NULL DEFAULT 0,
      storage_bytes INTEGER NOT NULL DEFAULT 0,
      active_users INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(tenant_id, month)
    );

    CREATE TABLE IF NOT EXISTS billing_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenant_id INTEGER NOT NULL REFERENCES tenants(id),
      period_start TEXT NOT NULL,
      period_end TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      stripe_invoice_id TEXT,
      stripe_customer_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS announcements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS master_audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      super_admin_id INTEGER REFERENCES super_admins(id),
      action TEXT NOT NULL,
      entity_type TEXT,
      entity_id TEXT,
      details TEXT,
      ip_address TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS tenant_auth_events (
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
    CREATE INDEX IF NOT EXISTS idx_tae_tenant ON tenant_auth_events(tenant_id);
    CREATE INDEX IF NOT EXISTS idx_tae_event ON tenant_auth_events(event);
    CREATE INDEX IF NOT EXISTS idx_tae_ip ON tenant_auth_events(ip_address);
    CREATE INDEX IF NOT EXISTS idx_tae_created ON tenant_auth_events(created_at);

    CREATE TABLE IF NOT EXISTS security_alerts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      severity TEXT NOT NULL DEFAULT 'warning',
      tenant_id INTEGER,
      tenant_slug TEXT,
      ip_address TEXT,
      details TEXT,
      acknowledged INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_sa_type ON security_alerts(type);
    CREATE INDEX IF NOT EXISTS idx_sa_acknowledged ON security_alerts(acknowledged);

    CREATE TABLE IF NOT EXISTS platform_config (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // Seed platform defaults if empty
  const configCount = masterDb.prepare('SELECT COUNT(*) as c FROM platform_config').get() as { c: number };
  if (configCount.c === 0) {
    masterDb.prepare("INSERT OR IGNORE INTO platform_config (key, value) VALUES ('management_api_enabled', 'false')").run();
  }

  console.log('[Multi-tenant] Master database initialized');
}

/**
 * Get the master database connection. Returns null in single-tenant mode.
 */
export function getMasterDb(): Database.Database | null {
  return masterDb;
}

/**
 * Close the master database connection.
 */
export function closeMasterDb(): void {
  if (masterDb) {
    masterDb.close();
    masterDb = null;
  }
}
