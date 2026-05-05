/**
 * Tenant repair — service-layer equivalent of scripts/repair-tenant.ts (TPH6).
 *
 * Exposes repairTenant(slug) so the super-admin dashboard can invoke the
 * same additive repair logic the CLI uses, without operators dropping to
 * PowerShell. Preserves the "never delete" rule: this code only creates
 * missing pieces, never removes.
 *
 * The CLI script in scripts/repair-tenant.ts is retained — it's the canonical
 * off-server escape hatch if the server itself is broken. This service
 * reimplements the same 7 steps using the server's live master DB handle
 * and runMigrations so behaviour matches the CLI.
 */

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { runMigrations } from '../db/migrate.js';
import { createTenantDnsRecord } from './cloudflareDns.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('tenant-repair');

export interface RepairStep {
  step: string;
  message: string;
}

export interface RepairResult {
  success: boolean;
  slug: string;
  tenantId?: number;
  steps: RepairStep[];
  /** Raw setup-token URL. Present ONLY when we had to generate a new token
   *  (i.e. the tenant had zero users). Single-use, single-shown. */
  setupUrl?: string;
  error?: string;
}

export async function repairTenant(slug: string): Promise<RepairResult> {
  const steps: RepairStep[] = [];
  const push = (step: string, message: string): void => {
    steps.push({ step, message });
    logger.info(`[Repair] ${step}: ${message}`, { slug });
  };

  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug)) {
    return { success: false, slug, steps, error: 'Invalid slug format' };
  }

  const masterDb = getMasterDb();
  if (!masterDb) {
    return { success: false, slug, steps, error: 'Multi-tenant mode not enabled' };
  }

  try { masterDb.exec("ALTER TABLE tenants ADD COLUMN cloudflare_record_id TEXT"); } catch {}

  const row = masterDb.prepare(
    "SELECT id, slug, name, status, db_path, admin_email, cloudflare_record_id FROM tenants WHERE slug = ?"
  ).get(slug) as {
    id: number;
    slug: string;
    name: string;
    status: string;
    db_path: string;
    admin_email: string;
    cloudflare_record_id: string | null;
  } | undefined;

  if (!row) {
    return { success: false, slug, steps, error: 'No tenant row in master.db for this slug' };
  }
  if (row.status === 'deleted' || row.status === 'pending_deletion') {
    return {
      success: false, slug, steps,
      error: `Tenant is ${row.status}. Reactivate manually before repair.`,
    };
  }
  push('1/7 master.db row', `found id=${row.id}, status=${row.status}, name="${row.name}"`);

  const tenantDbPath = path.join(config.tenantDataDir, row.db_path || `${slug}.db`);
  if (!fs.existsSync(config.tenantDataDir)) fs.mkdirSync(config.tenantDataDir, { recursive: true });

  if (!fs.existsSync(tenantDbPath)) {
    if (!fs.existsSync(config.templateDbPath)) {
      return {
        success: false, slug, steps,
        error: `Tenant DB missing and template DB not at ${config.templateDbPath}`,
      };
    }
    fs.copyFileSync(config.templateDbPath, tenantDbPath);
    push('2/7 tenant DB', 'CREATED from template.db');
  } else {
    push('2/7 tenant DB', 'exists (preserving)');
  }

  const tenantDb = new Database(tenantDbPath);
  tenantDb.pragma('journal_mode = WAL');
  tenantDb.pragma('foreign_keys = ON');

  let setupUrl: string | undefined;
  try {
    runMigrations(tenantDb);
    push('3/7 migrations', 'applied');

    const storeName = tenantDb
      .prepare("SELECT value FROM store_config WHERE key = 'store_name'")
      .get() as { value: string } | undefined;
    if (!storeName?.value) {
      tenantDb.prepare(
        "INSERT OR REPLACE INTO store_config (key, value) VALUES ('store_name', ?)"
      ).run(row.name);
      push('4/7 store_name', `set to "${row.name}"`);
    } else {
      push('4/7 store_name', `already set to "${storeName.value}"`);
    }

    const userCount = (tenantDb
      .prepare('SELECT COUNT(*) as c FROM users')
      .get() as { c: number }).c;
    if (userCount === 0) {
      const setupToken = crypto.randomBytes(32).toString('hex');
      const setupExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
      const tokenHash = crypto.createHash('sha256').update(setupToken).digest('hex');
      try {
        tenantDb.prepare(
          'INSERT INTO setup_tokens (tenant_id, token_hash, expires_at) VALUES (?, ?, ?)'
        ).run(row.id, tokenHash, setupExpiry);
      } catch {
        tenantDb.prepare(
          "INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token', ?)"
        ).run(setupToken);
        tenantDb.prepare(
          "INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token_expires', ?)"
        ).run(setupExpiry);
      }
      const baseDomain = (process.env.BASE_DOMAIN || 'localhost').trim();
      setupUrl = `https://${slug}.${baseDomain}/auth/setup?token=${setupToken}`;
      push('4/7 admin user', 'NONE found — generated setup token (valid 24h, single-shown)');
    } else {
      push('4/7 admin user', `${userCount} user(s) exist (preserving)`);
    }
  } finally {
    tenantDb.close();
  }

  const uploadsDir = path.join(config.uploadsPath, slug);
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
    push('5/7 uploads dir', `created ${uploadsDir}`);
  } else {
    push('5/7 uploads dir', 'exists (preserving)');
  }

  if (!config.cloudflareEnabled) {
    push('6/7 CF DNS', 'SKIPPED — Cloudflare not configured');
  } else if (row.cloudflare_record_id) {
    push('6/7 CF DNS', `already linked (record_id=${row.cloudflare_record_id})`);
  } else {
    try {
      const recordId = await createTenantDnsRecord(slug);
      masterDb.prepare(
        'UPDATE tenants SET cloudflare_record_id = ? WHERE id = ?'
      ).run(recordId, row.id);
      push('6/7 CF DNS', `CREATED record ${recordId}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      push('6/7 CF DNS', `failed: ${msg} (continuing, add manually in CF dashboard)`);
    }
  }

  if (row.status !== 'active') {
    masterDb.prepare(
      "UPDATE tenants SET status = 'active', provisioning_step = NULL, updated_at = datetime('now') WHERE id = ?"
    ).run(row.id);
    push('7/7 status', `flipped from "${row.status}" to "active"`);
  } else {
    push('7/7 status', 'already active (preserving)');
  }

  return { success: true, slug, tenantId: row.id, steps, setupUrl };
}
