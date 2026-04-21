import Database from 'better-sqlite3';
import bcrypt from 'bcryptjs';
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
  // @audit-fixed: Master DB was previously opened WITHOUT the same performance
  // pragmas as the single-tenant / tenant DBs (synchronous, cache_size, mmap_size,
  // temp_store, journal_size_limit, wal_autocheckpoint). Master DB is hit on every
  // tenant lookup, audit log write, rate-limit check, billing webhook, and signup
  // call — missing pragmas meant every query hit disk with NORMAL fsync and a
  // default 2MB page cache. Match connection.ts so lookups are fast and WAL growth
  // is bounded.
  masterDb.pragma('journal_mode = WAL');
  masterDb.pragma('foreign_keys = ON');
  masterDb.pragma('busy_timeout = 5000');
  masterDb.pragma('synchronous = NORMAL');
  masterDb.pragma('cache_size = -64000');
  masterDb.pragma('journal_size_limit = 67108864');
  masterDb.pragma('temp_store = MEMORY');
  masterDb.pragma('wal_autocheckpoint = 10000');

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
      trial_started_at TEXT,
      trial_ends_at TEXT,
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

  // Trial & billing columns (added for tier enforcement)
  // @audit-fixed: Previously swallowed ALL ALTER TABLE errors with `catch {}`.
  // That hid real problems (locked DB, corrupted file, out-of-disk) behind the
  // expected "duplicate column name" case. Now we re-throw anything that is not
  // a duplicate-column error so the server fails loudly on real corruption.
  const tryAddColumn = (sql: string, columnName: string): void => {
    try {
      masterDb!.exec(sql);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (!msg.includes('duplicate column name')) {
        console.error(`[MasterDb] Failed to add column ${columnName}:`, msg);
        throw err;
      }
    }
  };
  tryAddColumn("ALTER TABLE tenants ADD COLUMN trial_started_at TEXT", 'trial_started_at');
  tryAddColumn("ALTER TABLE tenants ADD COLUMN trial_ends_at TEXT", 'trial_ends_at');
  tryAddColumn("ALTER TABLE tenants ADD COLUMN stripe_customer_id TEXT", 'stripe_customer_id');
  tryAddColumn("ALTER TABLE tenants ADD COLUMN stripe_subscription_id TEXT", 'stripe_subscription_id');
  // Cloudflare DNS auto-provisioning — stores the record ID so deletion can target it
  tryAddColumn("ALTER TABLE tenants ADD COLUMN cloudflare_record_id TEXT", 'cloudflare_record_id');

  // Back-fill trial_ends_at for any active/provisioning tenant that was created before
  // the trial column was added to the INSERT statement. These rows have NULL trial_ends_at
  // which makes isTrialActive() return false — the trial never kicks in. We grant a
  // 14-day trial from created_at (capped to now+14 days so it is always in the future
  // for very new tenants) when trial_ends_at is NULL and the tenant is not already on
  // a paid plan. trial_started_at is stamped from created_at for historical accuracy.
  try {
    masterDb!.exec(`
      UPDATE tenants
      SET
        trial_started_at = created_at,
        trial_ends_at    = datetime(created_at, '+14 days')
      WHERE
        trial_ends_at IS NULL
        AND status NOT IN ('deleted', 'pending_deletion', 'quarantined')
        AND plan = 'free'
    `);
  } catch (err) {
    console.warn('[MasterDb] trial back-fill skipped:', err instanceof Error ? err.message : String(err));
  }

  // Rate-limits table (super-admin login, IP throttling, etc). Schema mirrors
  // migration 069_rate_limits.sql used by tenant DBs so the same checkWindowRate()
  // helper works against both. Previously missing from master.db, which caused
  // POST:/super-admin/api/login to crash with "no such table: rate_limits" and
  // then get auto-disabled by the crash tracker after 3 consecutive failures.
  masterDb.exec(`
    CREATE TABLE IF NOT EXISTS rate_limits (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL,
      key TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      first_attempt INTEGER NOT NULL,
      locked_until INTEGER,
      UNIQUE(category, key)
    );
    CREATE INDEX IF NOT EXISTS idx_rate_limits_category_key ON rate_limits(category, key);
    CREATE INDEX IF NOT EXISTS idx_rate_limits_first_attempt ON rate_limits(first_attempt);
  `);

  // Stripe webhook event idempotency — prevents reprocessing the same event on retries
  masterDb.exec(`
    CREATE TABLE IF NOT EXISTS stripe_webhook_events (
      stripe_event_id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      tenant_id INTEGER,
      processed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_processed_at
      ON stripe_webhook_events(processed_at);
  `);

  // Seed platform defaults if empty
  const configCount = masterDb.prepare('SELECT COUNT(*) as c FROM platform_config').get() as { c: number };
  if (configCount.c === 0) {
    masterDb.prepare("INSERT OR IGNORE INTO platform_config (key, value) VALUES ('management_api_enabled', 'false')").run();
  }

  // No default super admin is seeded — the dashboard shows a "Create Account"
  // form on first launch when no super admins exist (needsSetup: true).

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
