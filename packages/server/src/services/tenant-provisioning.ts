import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { getTenantDb, closeTenantDb } from '../db/tenant-pool.js';
import { createTenantDnsRecord, deleteTenantDnsRecord } from './cloudflareDns.js';
import { PLAN_DEFINITIONS, type TenantPlan } from '@bizarre-crm/shared';

const VALID_PLANS = new Set(Object.keys(PLAN_DEFINITIONS) as TenantPlan[]);

const RESERVED_SLUGS = new Set([
  'www', 'api', 'admin', 'master', 'app', 'mail', 'smtp', 'ftp',
  'cdn', 'static', 'assets', 'status', 'docs', 'help', 'support',
  'billing', 'signup', 'login', 'register', 'test', 'demo',
]);

const SLUG_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;

interface ProvisionOptions {
  slug: string;
  name: string;
  adminEmail: string;
  adminPassword?: string;
  adminFirstName?: string;
  adminLastName?: string;
  plan?: string;
}

interface ProvisionResult {
  success: boolean;
  tenantId?: number;
  slug?: string;
  setupToken?: string;
  error?: string;
}

/**
 * Validate a tenant slug.
 */
export function validateSlug(slug: string): { valid: boolean; error?: string } {
  if (!slug) return { valid: false, error: 'Slug is required' };
  if (slug.length < 3) return { valid: false, error: 'Slug must be at least 3 characters' };
  if (slug.length > 30) return { valid: false, error: 'Slug must be at most 30 characters' };
  if (!SLUG_REGEX.test(slug)) return { valid: false, error: 'Slug must contain only lowercase letters, numbers, and hyphens' };
  if (RESERVED_SLUGS.has(slug)) return { valid: false, error: 'This name is reserved' };
  return { valid: true };
}

/**
 * Check if a slug is available.
 */
export function isSlugAvailable(slug: string): boolean {
  const masterDb = getMasterDb();
  if (!masterDb) return false;
  const existing = masterDb.prepare('SELECT id FROM tenants WHERE slug = ?').get(slug);
  return !existing;
}

/**
 * Provision a new tenant: reserve slug in master DB first, then copy template DB, create admin user.
 *
 * IMPORTANT: The master DB INSERT happens FIRST to prevent race conditions on slug uniqueness.
 * If later steps fail, the master record is cleaned up.
 */
export async function provisionTenant(opts: ProvisionOptions): Promise<ProvisionResult> {
  const masterDb = getMasterDb();
  if (!masterDb) return { success: false, error: 'Multi-tenant mode not enabled' };

  // Validate slug
  const slugCheck = validateSlug(opts.slug);
  if (!slugCheck.valid) return { success: false, error: slugCheck.error };

  // Validate other fields
  if (!opts.name || opts.name.trim().length < 2) {
    return { success: false, error: 'Shop name must be at least 2 characters' };
  }
  if (!opts.adminEmail || !opts.adminEmail.includes('@')) {
    return { success: false, error: 'Valid email address is required' };
  }

  // Validate plan — must be one of the known TenantPlan values
  if (opts.plan && !VALID_PLANS.has(opts.plan as TenantPlan)) {
    return { success: false, error: `Invalid plan "${opts.plan}". Must be one of: ${Array.from(VALID_PLANS).join(', ')}` };
  }
  // Password is optional — shop admin sets their own on first login

  const templatePath = config.templateDbPath;
  if (!fs.existsSync(templatePath)) {
    return { success: false, error: 'Template database not found. Server may need restart.' };
  }

  // Ensure tenant data directory exists
  if (!fs.existsSync(config.tenantDataDir)) {
    fs.mkdirSync(config.tenantDataDir, { recursive: true });
  }

  const dbFilename = `${opts.slug}.db`;
  const dbPath = path.join(config.tenantDataDir, dbFilename);

  // STEP 1: Reserve slug in master DB FIRST to prevent race conditions.
  // Check if a soft-deleted tenant with this slug exists — reclaim it
  let tenantId: number;
  let setupToken = '';
  const existing = masterDb.prepare('SELECT id, status FROM tenants WHERE slug = ?').get(opts.slug) as any;
  if (existing && existing.status === 'deleted') {
    // Reclaim the deleted slug — update the existing row
    masterDb.prepare(`
      UPDATE tenants SET name = ?, db_path = ?, admin_email = ?, plan = ?, status = 'provisioning', trial_ends_at = datetime('now', '+14 days'), updated_at = datetime('now')
      WHERE id = ?
    `).run(opts.name.trim(), dbFilename, opts.adminEmail, opts.plan || 'free', existing.id);
    tenantId = existing.id;
    // Clean up old DB file if it exists
    const oldDbPath = path.join(config.tenantDataDir, dbFilename);
    if (fs.existsSync(oldDbPath)) fs.unlinkSync(oldDbPath);
  } else {
    // The UNIQUE constraint on slug ensures only one concurrent request wins.
    try {
      const result = masterDb.prepare(`
        INSERT INTO tenants (slug, name, db_path, admin_email, plan, status, trial_ends_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'provisioning', datetime('now', '+14 days'), datetime('now'), datetime('now'))
      `).run(
        opts.slug,
        opts.name.trim(),
        dbFilename,
        opts.adminEmail,
        opts.plan || 'free',
      );
      tenantId = Number(result.lastInsertRowid);
    } catch (err: any) {
      if (err.message?.includes('UNIQUE constraint')) {
        return { success: false, error: 'This shop name is already taken' };
      }
      console.error(`[Provision] Failed to reserve slug for ${opts.slug}:`, err);
      return { success: false, error: 'Failed to register shop. Please try again or contact support.' };
    }
  }

  // Track Cloudflare DNS record created during this provisioning (if any),
  // so cleanup() can remove it on rollback. Declared before cleanup() so the
  // closure captures it by reference — later assignment is visible to cleanup.
  let cloudflareRecordId: string | null = null;

  // Helper to clean up master record + any files on failure
  const cleanup = () => {
    try { masterDb.prepare('DELETE FROM tenants WHERE id = ?').run(tenantId); } catch {}
    try { fs.unlinkSync(dbPath); } catch {}
    // Also remove WAL/SHM files that better-sqlite3 may have created
    try { fs.unlinkSync(dbPath + '-wal'); } catch {}
    try { fs.unlinkSync(dbPath + '-shm'); } catch {}
    const uploadsDir = path.join(config.uploadsPath, opts.slug);
    try { fs.rmSync(uploadsDir, { recursive: true, force: true }); } catch {}
    // Clean up Cloudflare DNS record if one was created before failure.
    // Fire-and-forget: we don't wait on this, since cleanup must be synchronous
    // to keep the existing call sites simple. A failed cleanup is logged.
    if (cloudflareRecordId) {
      deleteTenantDnsRecord(cloudflareRecordId).catch((err) => {
        console.error(`[Provision] Failed to clean up DNS record ${cloudflareRecordId} for ${opts.slug}:`, err);
      });
    }
  };

  // STEP 2: Copy template database
  try {
    fs.copyFileSync(templatePath, dbPath);
  } catch (err) {
    cleanup();
    return { success: false, error: 'Failed to create shop database' };
  }

  // STEP 3: Open the new tenant DB and create admin user
  try {
    const tenantDb = new Database(dbPath);
    tenantDb.pragma('journal_mode = WAL');
    tenantDb.pragma('foreign_keys = ON');

    // Set store name in config
    tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('store_name', ?)`).run(opts.name);

    if (opts.adminPassword) {
      // Signup provided credentials — create admin user immediately
      const passwordHash = await bcrypt.hash(opts.adminPassword, 12);
      const defaultPin = await bcrypt.hash('1234', 12);
      tenantDb.prepare(`
        INSERT INTO users (username, email, password_hash, password_set, first_name, last_name, role, pin, is_active)
        VALUES (?, ?, ?, 1, ?, ?, 'admin', ?, 1)
      `).run(
        opts.adminEmail.split('@')[0], // username from email prefix
        opts.adminEmail,
        passwordHash,
        opts.adminFirstName || 'Admin',
        opts.adminLastName || '',
        defaultPin,
      );
      // Mark setup as complete so the shop is immediately accessible
      tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_completed', 'true')`).run();
    } else {
      // No password provided — generate setup token for later account creation
      setupToken = crypto.randomBytes(32).toString('hex');
      const setupExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
      tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token', ?)`).run(setupToken);
      tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token_expires', ?)`).run(setupExpiry);
    }

    tenantDb.close();
  } catch (err: any) {
    cleanup();
    console.error(`[Provision] Failed to set up shop for ${opts.slug}:`, err);
    return { success: false, error: 'Failed to set up shop. Please try again or contact support.' };
  }

  // STEP 4: Create uploads directory for tenant
  try {
    const uploadsDir = path.join(config.uploadsPath, opts.slug);
    if (!fs.existsSync(uploadsDir)) {
      fs.mkdirSync(uploadsDir, { recursive: true });
    }
  } catch (err) {
    cleanup();
    console.error(`[Provision] Failed to create uploads dir for ${opts.slug}:`, err);
    return { success: false, error: 'Failed to set up shop storage. Please try again.' };
  }

  // STEP 5: Create Cloudflare DNS record so the subdomain resolves.
  // Skipped (no-op) if Cloudflare is not configured — dev / single-tenant / localhost
  // setups don't need DNS auto-provisioning. If the API call fails, we roll back
  // the entire provisioning via cleanup() so no "active" tenant exists without DNS.
  if (config.cloudflareEnabled) {
    try {
      cloudflareRecordId = await createTenantDnsRecord(opts.slug);
      masterDb.prepare(
        "UPDATE tenants SET cloudflare_record_id = ? WHERE id = ?"
      ).run(cloudflareRecordId, tenantId);
    } catch (err) {
      cleanup();
      console.error(`[Provision] Failed to create DNS record for ${opts.slug}:`, err);
      return { success: false, error: 'Failed to configure subdomain. Please try again or contact support.' };
    }
  }

  // STEP 6: Activate the tenant (change from 'provisioning' to 'active')
  try {
    masterDb.prepare(
      "UPDATE tenants SET status = 'active', updated_at = datetime('now') WHERE id = ?"
    ).run(tenantId);
  } catch (err) {
    cleanup();
    console.error(`[Provision] Failed to activate tenant ${opts.slug}:`, err);
    return { success: false, error: 'Failed to finalize shop setup.' };
  }

  console.log(`[Tenant] Provisioned: ${opts.slug} (ID: ${tenantId})`);
  return { success: true, tenantId, slug: opts.slug, setupToken };
}

/**
 * Suspend a tenant (blocks access but preserves data).
 */
export function suspendTenant(slug: string): { success: boolean; error?: string } {
  const masterDb = getMasterDb();
  if (!masterDb) return { success: false, error: 'Multi-tenant mode not enabled' };

  const result = masterDb.prepare(
    "UPDATE tenants SET status = 'suspended', updated_at = datetime('now') WHERE slug = ? AND status = 'active'"
  ).run(slug);

  if (result.changes === 0) return { success: false, error: 'Tenant not found or not active' };

  closeTenantDb(slug);
  console.log(`[Tenant] Suspended: ${slug}`);
  return { success: true };
}

/**
 * Reactivate a suspended tenant.
 */
export function activateTenant(slug: string): { success: boolean; error?: string } {
  const masterDb = getMasterDb();
  if (!masterDb) return { success: false, error: 'Multi-tenant mode not enabled' };

  const result = masterDb.prepare(
    "UPDATE tenants SET status = 'active', updated_at = datetime('now') WHERE slug = ? AND status = 'suspended'"
  ).run(slug);

  if (result.changes === 0) return { success: false, error: 'Tenant not found or not suspended' };

  console.log(`[Tenant] Activated: ${slug}`);
  return { success: true };
}

/**
 * Soft-delete a tenant (marks as deleted, closes DB connection, removes DNS record).
 *
 * The DB soft-delete is the source of truth — if the Cloudflare API call to
 * remove the DNS record fails, we log the orphan and still return success.
 * Orphans can be cleaned up later via the backfill script or manually.
 */
export async function deleteTenant(slug: string): Promise<{ success: boolean; error?: string }> {
  const masterDb = getMasterDb();
  if (!masterDb) return { success: false, error: 'Multi-tenant mode not enabled' };

  // Fetch the tenant's DNS record ID before we soft-delete it, so we can
  // clean it up in Cloudflare afterwards.
  const tenant = masterDb.prepare(
    "SELECT id, cloudflare_record_id FROM tenants WHERE slug = ? AND status != 'deleted'"
  ).get(slug) as { id: number; cloudflare_record_id: string | null } | undefined;

  if (!tenant) return { success: false, error: 'Tenant not found' };

  masterDb.prepare(
    "UPDATE tenants SET status = 'deleted', updated_at = datetime('now') WHERE id = ?"
  ).run(tenant.id);

  closeTenantDb(slug);

  // Remove the Cloudflare DNS record if one exists. Failure here leaves an
  // orphaned record pointing at our server — the tenant is still functionally
  // deleted (404 at routing time), so we log and continue.
  if (tenant.cloudflare_record_id && config.cloudflareEnabled) {
    try {
      await deleteTenantDnsRecord(tenant.cloudflare_record_id);
    } catch (err) {
      console.error(`[Tenant] Failed to delete DNS record for ${slug} (orphan left in Cloudflare):`, err);
    }
  }

  console.log(`[Tenant] Deleted: ${slug}`);
  return { success: true };
}

/**
 * Get tenant details by slug.
 */
export function getTenantBySlug(slug: string): any | null {
  const masterDb = getMasterDb();
  if (!masterDb) return null;
  return masterDb.prepare('SELECT * FROM tenants WHERE slug = ?').get(slug) || null;
}

/**
 * Clean up stale provisioning records left behind if the server crashed
 * mid-provisioning. Call on server startup. Deletes master DB records
 * stuck in 'provisioning' status for longer than the given threshold,
 * along with any partially-created DB files and upload directories.
 */
export function cleanupStaleProvisioningRecords(maxAgeMs: number = 30 * 60 * 1000): number {
  const masterDb = getMasterDb();
  if (!masterDb) return 0;

  const cutoffIso = new Date(Date.now() - maxAgeMs).toISOString();

  const staleRows = masterDb.prepare(
    "SELECT id, slug, db_path FROM tenants WHERE status = 'provisioning' AND created_at < ?"
  ).all(cutoffIso) as Array<{ id: number; slug: string; db_path: string }>;

  for (const row of staleRows) {
    // Remove partial DB files
    const dbPath = path.join(config.tenantDataDir, row.db_path);
    try { fs.unlinkSync(dbPath); } catch {}
    try { fs.unlinkSync(dbPath + '-wal'); } catch {}
    try { fs.unlinkSync(dbPath + '-shm'); } catch {}

    // Remove partial uploads directory
    const uploadsDir = path.join(config.uploadsPath, row.slug);
    try { fs.rmSync(uploadsDir, { recursive: true, force: true }); } catch {}

    // Delete master record
    try { masterDb.prepare('DELETE FROM tenants WHERE id = ?').run(row.id); } catch {}

    console.log(`[Tenant] Cleaned up stale provisioning record: ${row.slug} (ID: ${row.id})`);
  }

  if (staleRows.length > 0) {
    console.log(`[Tenant] Cleaned up ${staleRows.length} stale provisioning record(s)`);
  }

  return staleRows.length;
}

/**
 * List all tenants with optional filtering.
 */
export function listTenants(filters?: { status?: string; plan?: string }): any[] {
  const masterDb = getMasterDb();
  if (!masterDb) return [];

  let where = "WHERE status != 'deleted'";
  const params: any[] = [];
  if (filters?.status) { where += ' AND status = ?'; params.push(filters.status); }
  if (filters?.plan) { where += ' AND plan = ?'; params.push(filters.plan); }

  return masterDb.prepare(`SELECT * FROM tenants ${where} ORDER BY created_at DESC`).all(...params) as any[];
}
