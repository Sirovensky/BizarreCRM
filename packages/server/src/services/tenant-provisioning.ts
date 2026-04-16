import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { getTenantDb, closeTenantDb } from '../db/tenant-pool.js';
import { createTenantDnsRecord, deleteTenantDnsRecord } from './cloudflareDns.js';
import { createLogger } from '../utils/logger.js';
import { PLAN_DEFINITIONS, type TenantPlan } from '@bizarre-crm/shared';

const logger = createLogger('tenant-provisioning');

const VALID_PLANS = new Set(Object.keys(PLAN_DEFINITIONS) as TenantPlan[]);

const RESERVED_SLUGS = new Set([
  'www', 'api', 'admin', 'master', 'app', 'mail', 'smtp', 'ftp',
  'cdn', 'static', 'assets', 'status', 'docs', 'help', 'support',
  'billing', 'signup', 'login', 'register', 'test', 'demo',
]);

const SLUG_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;

/**
 * Slug statuses that make a slug UNAVAILABLE for new signups.
 *
 * Critical: 'deleted' and 'pending_deletion' are INCLUDED. This closes the
 * subdomain-takeover path described in audit TP1/TP2 — once a slug has been
 * used, it is permanently claimed in the master DB and cannot be reclaimed
 * by a new signup. If a real user wants their old slug back, support must
 * reactivate it manually (and the original tenant DB, which we archive
 * rather than delete, can be restored).
 */
const UNAVAILABLE_STATUSES = ['active', 'suspended', 'pending', 'pending_deletion', 'deleted'] as const;

/** Days of grace before a pending_deletion tenant is actually archived. */
const DELETION_GRACE_DAYS = 30;

/**
 * Ensure the tenants table has the columns we added in this audit pass.
 * Uses the same idempotent ALTER pattern as master-connection.ts so it is
 * safe to call repeatedly and safe against fresh installs where the column
 * already exists in the initial schema.
 */
function ensureTenantLifecycleColumns(masterDb: Database.Database): void {
  try { masterDb.exec("ALTER TABLE tenants ADD COLUMN deletion_scheduled_at TEXT"); } catch {}
  try { masterDb.exec("ALTER TABLE tenants ADD COLUMN archived_db_path TEXT"); } catch {}
  // TPH5: forensic breadcrumb. Updated before each provisionTenant() step so
  // a crash-stuck row tells you which step died without a disk inventory.
  try { masterDb.exec("ALTER TABLE tenants ADD COLUMN provisioning_step TEXT"); } catch {}
}

/** TPH5: record the currently-executing provisioning step for forensics. */
function setProvisioningStep(masterDb: Database.Database, tenantId: number, step: string): void {
  try {
    masterDb.prepare('UPDATE tenants SET provisioning_step = ? WHERE id = ?').run(step, tenantId);
  } catch {}
}

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
  /** Raw setup token — returned to caller exactly once, never persisted in plaintext. */
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
 * Check if a slug is available for a NEW signup.
 *
 * Returns false if ANY tenant row exists with this slug in one of the
 * UNAVAILABLE_STATUSES — including 'deleted' and 'pending_deletion'. This is
 * the TP2 fix: a cancelled tenant's slug is permanently burned from the
 * self-serve signup pool. Admin/support can manually reactivate a prior
 * tenant if the original owner comes back.
 */
export function isSlugAvailable(slug: string): boolean {
  const masterDb = getMasterDb();
  if (!masterDb) return false;
  const placeholders = UNAVAILABLE_STATUSES.map(() => '?').join(', ');
  const existing = masterDb
    .prepare(`SELECT id FROM tenants WHERE slug = ? AND status IN (${placeholders})`)
    .get(slug, ...UNAVAILABLE_STATUSES);
  return !existing;
}

/**
 * Hash a setup token with sha256. We store only the hash in the tenant DB so
 * that a read of the tenant's store_config or a DB leak never exposes a
 * usable token. The caller of provisionTenant is given the raw token exactly
 * once and is responsible for delivering it (e.g. via email link).
 */
function hashSetupToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Provision a new tenant: reserve slug in master DB first, then copy template DB, create admin user.
 *
 * IMPORTANT: The master DB INSERT happens FIRST to prevent race conditions on slug uniqueness.
 * If later steps fail, the master record is cleaned up via cleanup().
 *
 * Reclaim behaviour (TP1/TP2):
 *   Unlike the previous implementation, this function NEVER reclaims a slug
 *   whose prior tenant has status = 'deleted' or 'pending_deletion'. Those
 *   rows are terminal for signup purposes. The old tenant DB file (if any)
 *   is archived on delete, never unlinked.
 */
export async function provisionTenant(opts: ProvisionOptions): Promise<ProvisionResult> {
  try {
    return await provisionTenantInner(opts);
  } catch (err: unknown) {
    // TPH4: belt-and-suspenders. If any step threw outside its own inner
    // try/catch (future bug), this top-level catch logs the failure. The
    // step-local cleanup() closures already ran before the throw reached
    // here; this is purely observability for escaped exceptions.
    const message = err instanceof Error ? err.message : String(err);
    logger.error('provisionTenant escaped top-level catch', {
      slug: opts.slug, error: message, stack: err instanceof Error ? err.stack : undefined,
    });
    return { success: false, error: 'Provisioning failed unexpectedly. Please try again or contact support.' };
  }
}

async function provisionTenantInner(opts: ProvisionOptions): Promise<ProvisionResult> {
  const masterDb = getMasterDb();
  if (!masterDb) return { success: false, error: 'Multi-tenant mode not enabled' };
  ensureTenantLifecycleColumns(masterDb);

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

  // Pre-flight availability check: any prior use of the slug (including
  // deleted / pending_deletion) blocks new signup. This eliminates the
  // takeover window the previous reclaim path exposed.
  if (!isSlugAvailable(opts.slug)) {
    return { success: false, error: 'This shop name is already taken' };
  }

  // STEP 1: Reserve slug in master DB FIRST to prevent race conditions.
  // The UNIQUE constraint on slug ensures only one concurrent request wins.
  let tenantId: number;
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
    setProvisioningStep(masterDb, tenantId, 'step1_reserve_slug_complete');
    logger.info(`[Provision] ${opts.slug} — step 1 complete: slug reserved, tenantId=${tenantId}`);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('UNIQUE constraint')) {
      return { success: false, error: 'This shop name is already taken' };
    }
    logger.error('Failed to reserve slug', { slug: opts.slug, error: message });
    return { success: false, error: 'Failed to register shop. Please try again or contact support.' };
  }

  // Track Cloudflare DNS record created during this provisioning (if any),
  // so cleanup() can remove it on rollback. Declared before cleanup() so the
  // closure captures it by reference — later assignment is visible to cleanup.
  let cloudflareRecordId: string | null = null;

  /**
   * Clean up a FAILED provisioning attempt. This only runs on mid-provisioning
   * failures (template copy, admin user creation, etc.) — i.e. when the
   * tenant row is still in 'provisioning' status and we're aborting before
   * the tenant ever went live. Deleting the freshly-created DB file in THIS
   * scenario does not violate the "tenant DBs are sacred" rule because the
   * DB never held any real tenant data.
   *
   * TP5 fix: Cloudflare deletion is awaited so the caller gets a stable
   * post-condition. CF failures are logged but do not block cleanup completion.
   */
  const cleanup = async (): Promise<void> => {
    try { masterDb.prepare('DELETE FROM tenants WHERE id = ?').run(tenantId); } catch {}
    try { fs.unlinkSync(dbPath); } catch {}
    // Also remove WAL/SHM files that better-sqlite3 may have created
    try { fs.unlinkSync(dbPath + '-wal'); } catch {}
    try { fs.unlinkSync(dbPath + '-shm'); } catch {}
    const uploadsDir = path.join(config.uploadsPath, opts.slug);
    try { fs.rmSync(uploadsDir, { recursive: true, force: true }); } catch {}
    // Clean up Cloudflare DNS record if one was created before failure.
    // Awaited so cleanup() has a clear end; any error is logged, and we
    // record the failed deletion to master_audit_log for manual cleanup.
    if (cloudflareRecordId) {
      try {
        await deleteTenantDnsRecord(cloudflareRecordId);
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        logger.error('Cleanup failed to delete Cloudflare DNS record', {
          slug: opts.slug,
          cloudflareRecordId,
          error: message,
        });
        recordFailedDnsDeletion(masterDb, opts.slug, cloudflareRecordId, message);
      }
    }
  };

  // STEP 2: Copy template database
  setProvisioningStep(masterDb, tenantId, 'step2_copy_template');
  logger.info(`[Provision] ${opts.slug} — step 2: copy template DB`);
  try {
    fs.copyFileSync(templatePath, dbPath);
  } catch (err: unknown) {
    await cleanup();
    const message = err instanceof Error ? err.message : String(err);
    logger.error('Failed to copy template DB', { slug: opts.slug, error: message });
    return { success: false, error: 'Failed to create shop database' };
  }

  // STEP 3: Open the new tenant DB and create admin user + (optional) setup token
  setProvisioningStep(masterDb, tenantId, 'step3_open_db_and_admin');
  logger.info(`[Provision] ${opts.slug} — step 3: open tenant DB + create admin`);
  let setupToken = '';
  try {
    const tenantDb = new Database(dbPath);
    tenantDb.pragma('journal_mode = WAL');
    tenantDb.pragma('foreign_keys = ON');

    // Set store name in config
    tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('store_name', ?)`).run(opts.name);

    // @audit-fixed: previously the legacy-plaintext-token purge happened AFTER
    // the new hashed token was inserted. The window between insert and delete
    // is microscopic but means a crash mid-flight could leave both the old
    // plaintext and the new hashed token co-existing. We now purge FIRST,
    // then insert the hashed setup token, so the only path that can leave
    // anything in store_config under those keys is a partial template DB.
    tenantDb.prepare(`DELETE FROM store_config WHERE key IN ('setup_token', 'setup_token_expires')`).run();

    // Generate a setup token for email verification + first-time password
    // set. This ALWAYS runs, even when a password was supplied — the token
    // doubles as the email verification proof (TP4). Only the sha256 hash is
    // stored; the raw token is returned to the caller.
    setupToken = crypto.randomBytes(32).toString('hex');
    const setupTokenHash = hashSetupToken(setupToken);
    const setupExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    tenantDb.prepare(`
      INSERT INTO setup_tokens (tenant_id, token_hash, expires_at)
      VALUES (?, ?, ?)
    `).run(tenantId, setupTokenHash, setupExpiry);

    if (opts.adminPassword) {
      // ⚠️ TEMP-NO-EMAIL-VERIF: email verification is DISABLED for new shops
      // to unblock full-flow testing of everything downstream of signup.
      // password_set is set to 1 so the admin can log in immediately with
      // the password they chose at signup, skipping the setup-token gate.
      // setup_completed is flipped to 'true' so the App.tsx Gate 1 does not
      // push them into /setup for password reset.
      //
      // TODO(REVERT-EMAIL-VERIF): restore password_set=0 and drop the
      // setup_completed write below once we're ready to re-enable the
      // email-verification step (TP4). Grep for TEMP-NO-EMAIL-VERIF.
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
      tenantDb.prepare(
        "INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_completed', 'true')"
      ).run();
    }

    tenantDb.close();
  } catch (err: unknown) {
    await cleanup();
    const message = err instanceof Error ? err.message : String(err);
    logger.error('Failed to set up tenant DB', { slug: opts.slug, error: message });
    return { success: false, error: 'Failed to set up shop. Please try again or contact support.' };
  }

  // STEP 4: Create uploads directory for tenant
  setProvisioningStep(masterDb, tenantId, 'step4_uploads_dir');
  logger.info(`[Provision] ${opts.slug} — step 4: create uploads directory`);
  try {
    const uploadsDir = path.join(config.uploadsPath, opts.slug);
    if (!fs.existsSync(uploadsDir)) {
      fs.mkdirSync(uploadsDir, { recursive: true });
    }
  } catch (err: unknown) {
    await cleanup();
    const message = err instanceof Error ? err.message : String(err);
    logger.error('Failed to create uploads directory', { slug: opts.slug, error: message });
    return { success: false, error: 'Failed to set up shop storage. Please try again.' };
  }

  // STEP 5: Create Cloudflare DNS record so the subdomain resolves.
  // Skipped (no-op) if Cloudflare is not configured — dev / single-tenant / localhost
  // setups don't need DNS auto-provisioning. If the API call fails, we roll back
  // the entire provisioning via cleanup() so no "active" tenant exists without DNS.
  if (config.cloudflareEnabled) {
    setProvisioningStep(masterDb, tenantId, 'step5_cloudflare_dns');
    logger.info(`[Provision] ${opts.slug} — step 5: create Cloudflare DNS record`);
    try {
      cloudflareRecordId = await createTenantDnsRecord(opts.slug);
      masterDb.prepare(
        "UPDATE tenants SET cloudflare_record_id = ? WHERE id = ?"
      ).run(cloudflareRecordId, tenantId);
    } catch (err: unknown) {
      await cleanup();
      const message = err instanceof Error ? err.message : String(err);
      logger.error('Failed to create DNS record', { slug: opts.slug, error: message });
      return { success: false, error: 'Failed to configure subdomain. Please try again or contact support.' };
    }
  }

  // STEP 6: Activate the tenant (change from 'provisioning' to 'active')
  setProvisioningStep(masterDb, tenantId, 'step6_activate');
  logger.info(`[Provision] ${opts.slug} — step 6: activate tenant`);
  try {
    masterDb.prepare(
      "UPDATE tenants SET status = 'active', provisioning_step = NULL, updated_at = datetime('now') WHERE id = ?"
    ).run(tenantId);
  } catch (err: unknown) {
    await cleanup();
    const message = err instanceof Error ? err.message : String(err);
    logger.error('Failed to activate tenant', { slug: opts.slug, error: message });
    return { success: false, error: 'Failed to finalize shop setup.' };
  }

  logger.info('Provisioned tenant', { slug: opts.slug, tenantId });
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
  logger.info('Suspended tenant', { slug });
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

  logger.info('Activated tenant', { slug });
  return { success: true };
}

/**
 * Soft-delete a tenant into a 30-day grace period (TP6).
 *
 * Previously, deleteTenant immediately flipped status to 'deleted' with no
 * recovery window and left the door open for slug reclaim + unlink. Now:
 *   1. Status moves to 'pending_deletion'.
 *   2. deletion_scheduled_at is set to now + 30 days.
 *   3. Cloudflare DNS record is removed (awaited; failure is logged but does
 *      not fail the call) — TP5.
 *   4. The tenant DB file is UNTOUCHED. A separate cron (see archiveDueTenants)
 *      archives the DB file when the grace period elapses.
 *
 * Admin tooling can purge an archived tenant DB via a separate manual endpoint;
 * self-serve deletion alone never removes the DB file.
 *
 * TODO(MEDIUM, §26): wire archiveDueTenants() into the existing cron in
 * index.ts so scheduled deletions are actually processed. SEVERITY=MEDIUM:
 * tenant DBs queued for deletion sit on disk forever today; no data loss
 * (it's the OPPOSITE of data loss — nothing gets archived), but storage
 * grows unbounded after each self-serve cancellation.
 */
export async function deleteTenant(slug: string): Promise<{ success: boolean; error?: string }> {
  const masterDb = getMasterDb();
  if (!masterDb) return { success: false, error: 'Multi-tenant mode not enabled' };
  ensureTenantLifecycleColumns(masterDb);

  // Fetch the tenant's DNS record ID before we update status, so we can
  // still target it for Cloudflare cleanup.
  const tenant = masterDb.prepare(
    "SELECT id, cloudflare_record_id FROM tenants WHERE slug = ? AND status NOT IN ('deleted', 'pending_deletion')"
  ).get(slug) as { id: number; cloudflare_record_id: string | null } | undefined;

  if (!tenant) return { success: false, error: 'Tenant not found' };

  const scheduledAt = new Date(Date.now() + DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000).toISOString();
  masterDb.prepare(
    "UPDATE tenants SET status = 'pending_deletion', deletion_scheduled_at = ?, updated_at = datetime('now') WHERE id = ?"
  ).run(scheduledAt, tenant.id);

  closeTenantDb(slug);

  // Remove the Cloudflare DNS record if one exists. Failure here is logged
  // and recorded to master_audit_log for manual cleanup, but does not block
  // the deletion flow (TP5).
  if (tenant.cloudflare_record_id && config.cloudflareEnabled) {
    try {
      await deleteTenantDnsRecord(tenant.cloudflare_record_id);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      logger.error('Failed to delete DNS record on tenant deletion', {
        slug,
        tenantId: tenant.id,
        cloudflareRecordId: tenant.cloudflare_record_id,
        error: message,
      });
      recordFailedDnsDeletion(masterDb, slug, tenant.cloudflare_record_id, message);
    }
  }

  logger.info('Scheduled tenant deletion', {
    slug,
    tenantId: tenant.id,
    deletionScheduledAt: scheduledAt,
    graceDays: DELETION_GRACE_DAYS,
  });
  return { success: true };
}

/**
 * Get tenant details by slug.
 */
export function getTenantBySlug(slug: string): unknown | null {
  const masterDb = getMasterDb();
  if (!masterDb) return null;
  return masterDb.prepare('SELECT * FROM tenants WHERE slug = ?').get(slug) || null;
}

/**
 * Record a DNS-deletion failure into master_audit_log for manual cleanup.
 * Uses the existing audit table rather than adding a new one so operators
 * have a single place to find orphaned records. Swallows its own errors —
 * audit failures must never block the calling flow.
 */
function recordFailedDnsDeletion(
  masterDb: Database.Database,
  slug: string,
  cloudflareRecordId: string,
  errorMessage: string,
): void {
  try {
    masterDb.prepare(`
      INSERT INTO master_audit_log (super_admin_id, action, entity_type, entity_id, details, ip_address)
      VALUES (NULL, 'cloudflare_dns_delete_failed', 'tenant', ?, ?, NULL)
    `).run(slug, JSON.stringify({ cloudflareRecordId, errorMessage }));
  } catch (err: unknown) {
    logger.warn('Failed to record DNS deletion failure in audit log', {
      slug,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Archive a tenant DB file by moving it to the archive directory with a
 * timestamped filename. This is the SAFE alternative to unlinking — see the
 * "tenant DB files are sacred" rule in project memory.
 *
 * The archived copy can be restored by a super-admin later. Returns the
 * absolute path the file was moved to, or null if the source did not exist.
 */
export function archiveTenantDb(slug: string, dbFilename: string): string | null {
  const sourcePath = path.join(config.tenantDataDir, dbFilename);
  if (!fs.existsSync(sourcePath)) {
    logger.warn('archiveTenantDb: source not found, nothing to archive', { slug, sourcePath });
    return null;
  }

  const archiveDir = path.join(config.tenantDataDir, 'archive');
  if (!fs.existsSync(archiveDir)) {
    fs.mkdirSync(archiveDir, { recursive: true });
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const archivedName = `${slug}.archived-${timestamp}.db`;
  const archivedPath = path.join(archiveDir, archivedName);

  // Move the DB file and any sidecar journal files. We use renameSync for
  // atomicity on the same filesystem; sidecars are best-effort.
  fs.renameSync(sourcePath, archivedPath);
  try { fs.renameSync(sourcePath + '-wal', archivedPath + '-wal'); } catch {}
  try { fs.renameSync(sourcePath + '-shm', archivedPath + '-shm'); } catch {}

  logger.info('Archived tenant DB', { slug, sourcePath, archivedPath });

  const masterDb = getMasterDb();
  if (masterDb) {
    ensureTenantLifecycleColumns(masterDb);
    try {
      masterDb.prepare(
        "UPDATE tenants SET archived_db_path = ?, updated_at = datetime('now') WHERE slug = ?"
      ).run(archivedPath, slug);
    } catch (err: unknown) {
      logger.warn('Failed to record archived_db_path on tenant row', {
        slug,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // Audit trail entry so operators can find this action later.
    try {
      masterDb.prepare(`
        INSERT INTO master_audit_log (super_admin_id, action, entity_type, entity_id, details, ip_address)
        VALUES (NULL, 'tenant_db_archived', 'tenant', ?, ?, NULL)
      `).run(slug, JSON.stringify({ archivedPath }));
    } catch {}
  }

  return archivedPath;
}

/**
 * Archive any tenant DBs whose grace period has elapsed (TP6).
 *
 * TODO(MEDIUM, §26, infra): call this from the existing cron in index.ts
 * on an hourly schedule. Returns the list of slugs archived this run.
 */
export function archiveDueTenants(): string[] {
  const masterDb = getMasterDb();
  if (!masterDb) return [];
  ensureTenantLifecycleColumns(masterDb);

  const nowIso = new Date().toISOString();
  const due = masterDb.prepare(`
    SELECT id, slug, db_path FROM tenants
    WHERE status = 'pending_deletion'
      AND deletion_scheduled_at IS NOT NULL
      AND deletion_scheduled_at <= ?
      AND (archived_db_path IS NULL OR archived_db_path = '')
  `).all(nowIso) as Array<{ id: number; slug: string; db_path: string }>;

  const archived: string[] = [];
  for (const row of due) {
    try {
      closeTenantDb(row.slug);
      const archivedPath = archiveTenantDb(row.slug, row.db_path);
      if (archivedPath) {
        masterDb.prepare(
          "UPDATE tenants SET status = 'deleted', updated_at = datetime('now') WHERE id = ?"
        ).run(row.id);
        archived.push(row.slug);
      }
    } catch (err: unknown) {
      logger.error('Failed to archive due tenant', {
        slug: row.slug,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  if (archived.length > 0) {
    logger.info('Archived due tenants', { count: archived.length, slugs: archived });
  }

  return archived;
}

/**
 * Structure returned by exportTenantData. Kept narrow and forward-compatible
 * — consumers (e.g. admin.routes.ts) can widen the shape without breaking
 * clients that only read the top-level keys.
 */
export interface TenantDataExport {
  tenantId: number;
  slug: string;
  exportedAt: string;
  customers: unknown[];
  tickets: unknown[];
  invoices: unknown[];
}

/**
 * Read-only JSON dump of a tenant's core customer/ticket/invoice data for
 * GDPR data-export (TP6).
 *
 * Wire-up note: this helper intentionally lives here because it reuses the
 * tenant-pool connection logic. admin.routes.ts can wire it up to a route
 * like `GET /account/export` that streams `JSON.stringify(export)` to the
 * caller. Tables that do not exist on older tenant DBs are silently skipped
 * rather than erroring, so the export is robust to schema drift.
 */
export function exportTenantData(tenantId: number): TenantDataExport | null {
  const masterDb = getMasterDb();
  if (!masterDb) return null;

  const tenant = masterDb
    .prepare('SELECT id, slug FROM tenants WHERE id = ?')
    .get(tenantId) as { id: number; slug: string } | undefined;
  if (!tenant) return null;

  const db = getTenantDb(tenant.slug);
  if (!db) return null;

  const safeSelectAll = (sql: string): unknown[] => {
    try {
      return db.prepare(sql).all();
    } catch (err: unknown) {
      logger.warn('exportTenantData: skipped table', {
        slug: tenant.slug,
        sql,
        error: err instanceof Error ? err.message : String(err),
      });
      return [];
    }
  };

  return {
    tenantId: tenant.id,
    slug: tenant.slug,
    exportedAt: new Date().toISOString(),
    customers: safeSelectAll('SELECT * FROM customers'),
    tickets: safeSelectAll('SELECT * FROM tickets'),
    invoices: safeSelectAll('SELECT * FROM invoices'),
  };
}

/**
 * DETECT (but never modify) stale provisioning records. Called from startup
 * after migrateAllTenants(). Logs each stale row with the exact repair command
 * plus disk-presence of the tenant DB file and uploads dir. No auto-delete,
 * no auto-repair — pure visibility per TPH2.
 */
export function detectStaleProvisioningRecords(maxAgeMs: number = 30 * 60 * 1000): number {
  const masterDb = getMasterDb();
  if (!masterDb) return 0;

  const cutoffIso = new Date(Date.now() - maxAgeMs).toISOString();
  const staleRows = masterDb.prepare(
    "SELECT id, slug, db_path, created_at FROM tenants WHERE status = 'provisioning' AND created_at < ?"
  ).all(cutoffIso) as Array<{ id: number; slug: string; db_path: string; created_at: string }>;

  for (const row of staleRows) {
    const dbPath = path.join(config.tenantDataDir, row.db_path);
    const uploadsDir = path.join(config.uploadsPath, row.slug);
    const dbExists = fs.existsSync(dbPath);
    const uploadsExists = fs.existsSync(uploadsDir);
    logger.warn(
      `[Startup] Stale provisioning: ${row.slug} created ${row.created_at} — run: npx tsx scripts/repair-tenant.ts ${row.slug}`,
      { slug: row.slug, tenantId: row.id, createdAt: row.created_at, dbFileExists: dbExists, uploadsDirExists: uploadsExists }
    );
  }

  if (staleRows.length > 0) {
    logger.warn('[Startup] Stale provisioning records detected', { count: staleRows.length });
  }
  return staleRows.length;
}

/**
 * Clean up stale provisioning records left behind if the server crashed
 * mid-provisioning. Call on server startup. Deletes master DB records
 * stuck in 'provisioning' status for longer than the given threshold,
 * along with any partially-created DB files and upload directories.
 *
 * Safety note: this ONLY targets rows in 'provisioning' status — i.e. rows
 * that never completed their initial setup and never held real tenant data.
 * It will NEVER touch a row in 'active', 'suspended', 'pending_deletion',
 * or 'deleted' status, so it cannot delete a real tenant's DB. The "tenant
 * DBs are sacred" rule applies to tenants that actually went live; cleaning
 * up a half-provisioned shell is allowed.
 */
export function cleanupStaleProvisioningRecords(maxAgeMs: number = 30 * 60 * 1000): number {
  // TPH3: preserved as a thin wrapper for back-compat. The real behaviour is
  // now quarantine — moves artifacts instead of deleting them.
  return quarantineStaleProvisioningRecords(maxAgeMs);
}

/**
 * TPH3: MOVE (not delete) stale-provisioning artifacts into a quarantine
 * directory so nothing on disk is ever destroyed. The master row is marked
 * 'quarantined' (a new terminal status) and its db_path is cleared so the
 * tenant resolver cannot re-open it.
 *
 * Manual-only: called from a CLI/admin command, never auto-run at startup.
 */
export function quarantineStaleProvisioningRecords(maxAgeMs: number = 30 * 60 * 1000): number {
  const masterDb = getMasterDb();
  if (!masterDb) return 0;

  const cutoffIso = new Date(Date.now() - maxAgeMs).toISOString();
  const staleRows = masterDb.prepare(
    "SELECT id, slug, db_path FROM tenants WHERE status = 'provisioning' AND created_at < ?"
  ).all(cutoffIso) as Array<{ id: number; slug: string; db_path: string }>;

  if (staleRows.length === 0) return 0;

  const quarantineRoot = path.join(config.tenantDataDir, '.quarantine');
  if (!fs.existsSync(quarantineRoot)) {
    fs.mkdirSync(quarantineRoot, { recursive: true });
  }

  for (const row of staleRows) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const destDir = path.join(quarantineRoot, `${row.slug}-${timestamp}`);
    try { fs.mkdirSync(destDir, { recursive: true }); } catch {}

    const dbPath = path.join(config.tenantDataDir, row.db_path);
    const uploadsDir = path.join(config.uploadsPath, row.slug);

    const moveIfExists = (src: string, dest: string): void => {
      if (!fs.existsSync(src)) return;
      try { fs.renameSync(src, dest); } catch (err) {
        logger.warn('Quarantine move failed', {
          src, dest, error: err instanceof Error ? err.message : String(err),
        });
      }
    };

    moveIfExists(dbPath, path.join(destDir, path.basename(dbPath)));
    moveIfExists(dbPath + '-wal', path.join(destDir, path.basename(dbPath) + '-wal'));
    moveIfExists(dbPath + '-shm', path.join(destDir, path.basename(dbPath) + '-shm'));
    moveIfExists(uploadsDir, path.join(destDir, 'uploads'));

    try {
      masterDb.prepare(
        "UPDATE tenants SET status = 'quarantined', db_path = '', updated_at = datetime('now') WHERE id = ?"
      ).run(row.id);
    } catch (err) {
      logger.error('Failed to mark tenant quarantined', {
        slug: row.slug, error: err instanceof Error ? err.message : String(err),
      });
    }

    logger.info('Quarantined stale provisioning record', {
      slug: row.slug, tenantId: row.id, destDir,
    });
  }

  logger.info('Quarantined stale provisioning records', { count: staleRows.length });
  return staleRows.length;
}

/**
 * List all tenants with optional filtering.
 *
 * Hides 'deleted' AND 'pending_deletion' from the default listing so the
 * super-admin dashboard doesn't surface grace-period shops as active.
 */
export function listTenants(filters?: { status?: string; plan?: string }): unknown[] {
  const masterDb = getMasterDb();
  if (!masterDb) return [];

  let where = "WHERE status NOT IN ('deleted', 'pending_deletion')";
  const params: unknown[] = [];
  if (filters?.status) { where = 'WHERE status = ?'; params.push(filters.status); }
  if (filters?.plan) { where += ' AND plan = ?'; params.push(filters.plan); }

  return masterDb.prepare(`SELECT * FROM tenants ${where} ORDER BY created_at DESC`).all(...params) as unknown[];
}
