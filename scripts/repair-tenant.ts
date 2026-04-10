/**
 * Tenant repair script — preserves data, creates whatever is missing.
 *
 * Use this when a tenant is in a broken/incomplete state (e.g. stuck in
 * `provisioning` because a signup flow crashed mid-way). It does NOT delete
 * anything. It walks through every provisioning step and creates any missing
 * piece for the given slug, then activates the tenant.
 *
 * Usage (from bizarre-crm/):
 *   npx tsx scripts/repair-tenant.ts <slug>
 *
 * Example:
 *   npx tsx scripts/repair-tenant.ts bizarreelectronics
 *
 * What it repairs:
 *   1. master.db row for the slug (must already exist — we never delete tenants)
 *   2. Tenant DB file at data/tenants/{slug}.db — copied from template.db if missing
 *   3. Schema — runMigrations applied to the tenant DB (idempotent via _migrations table)
 *   4. Admin user — if none exists, a setup token is generated and you're told the URL
 *   5. Uploads directory at uploads/{slug}/ — created if missing
 *   6. Cloudflare DNS record — created via CF API if missing and CF is configured
 *   7. Status — flipped to 'active' after all pieces are in place
 *
 * Everything is additive. No destructive operations. Safe to re-run.
 */

import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from bizarre-crm/
dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

function log(step: string, message: string): void {
  console.log(`[Repair] ${step}: ${message}`);
}

async function main(): Promise<void> {
  const slug = process.argv[2];
  if (!slug) {
    console.error('Usage: npx tsx scripts/repair-tenant.ts <slug>');
    console.error('Example: npx tsx scripts/repair-tenant.ts bizarreelectronics');
    process.exit(1);
  }

  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug)) {
    console.error(`[Repair] Invalid slug "${slug}" (must be lowercase alphanumeric + hyphens, 3-30 chars)`);
    process.exit(1);
  }

  // ─── Paths ───────────────────────────────────────────────────────
  const serverRoot = path.resolve(__dirname, '..', 'packages', 'server');
  const masterDbPath = path.join(serverRoot, 'data', 'master.db');
  const templateDbPath = path.join(serverRoot, 'data', 'template.db');
  const tenantDataDir = path.join(serverRoot, 'data', 'tenants');
  const uploadsDir = path.join(serverRoot, 'uploads', slug);
  const tenantDbFilename = `${slug}.db`;
  const tenantDbPath = path.join(tenantDataDir, tenantDbFilename);

  log('Paths', `master.db=${masterDbPath}`);
  log('Paths', `tenant.db=${tenantDbPath}`);

  // ─── 1. Master DB row check ─────────────────────────────────────
  if (!fs.existsSync(masterDbPath)) {
    console.error(`[Repair] master.db not found at ${masterDbPath}. Is this the right directory?`);
    process.exit(1);
  }

  const masterDb = new Database(masterDbPath);
  masterDb.pragma('journal_mode = WAL');

  // Ensure the cloudflare_record_id column exists (in case this script runs
  // before the server has restarted with the latest master-connection.ts)
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
    console.error(`[Repair] No tenant row in master.db for slug "${slug}".`);
    console.error('[Repair] This script repairs existing tenants — it does not create new ones.');
    console.error('[Repair] If you need to register an orphan DB file, ask for a register-orphan script.');
    masterDb.close();
    process.exit(1);
  }

  log('1/7 master.db row', `found id=${row.id}, status=${row.status}, name="${row.name}"`);

  if (row.status === 'deleted') {
    console.error(`[Repair] Tenant "${slug}" is soft-deleted. If you want to reactivate it, update the status manually first:`);
    console.error(`  UPDATE tenants SET status='provisioning' WHERE slug='${slug}';`);
    console.error('[Repair] Then re-run this script.');
    masterDb.close();
    process.exit(1);
  }

  // ─── 2. Tenant DB file ──────────────────────────────────────────
  if (!fs.existsSync(tenantDataDir)) {
    fs.mkdirSync(tenantDataDir, { recursive: true });
    log('2/7 tenant dir', `created ${tenantDataDir}`);
  }

  if (!fs.existsSync(tenantDbPath)) {
    if (!fs.existsSync(templateDbPath)) {
      console.error(`[Repair] Tenant DB missing AND template.db not found at ${templateDbPath}.`);
      console.error('[Repair] Start the server once (pm2 restart bizarre-crm) so buildTemplateDb() creates it, then re-run this script.');
      masterDb.close();
      process.exit(1);
    }
    fs.copyFileSync(templateDbPath, tenantDbPath);
    log('2/7 tenant DB', `CREATED from template.db`);
  } else {
    log('2/7 tenant DB', `exists (preserving)`);
  }

  // ─── 3. Schema / migrations ─────────────────────────────────────
  // Import runMigrations from the server source — it's the same function the
  // server uses on startup, so we're guaranteed identical behavior.
  const { runMigrations } = await import('../packages/server/src/db/migrate.js');

  const tenantDb = new Database(tenantDbPath);
  tenantDb.pragma('journal_mode = WAL');
  tenantDb.pragma('foreign_keys = ON');

  try {
    runMigrations(tenantDb);
    log('3/7 migrations', 'applied (idempotent via _migrations table)');
  } catch (err) {
    console.error('[Repair] Migration failed:', err);
    tenantDb.close();
    masterDb.close();
    process.exit(1);
  }

  // ─── 4. Store name + admin user ─────────────────────────────────
  // Ensure store_name is set
  const storeName = tenantDb.prepare("SELECT value FROM store_config WHERE key = 'store_name'").get() as { value: string } | undefined;
  if (!storeName?.value) {
    tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('store_name', ?)`).run(row.name);
    log('4/7 store_name', `set to "${row.name}"`);
  } else {
    log('4/7 store_name', `already set to "${storeName.value}"`);
  }

  // Check for any existing user (admin or otherwise)
  const userCount = (tenantDb.prepare('SELECT COUNT(*) as c FROM users').get() as { c: number }).c;

  if (userCount === 0) {
    // No users exist — generate a setup token so the user can complete account
    // creation via the web UI. We do NOT silently create an admin with a random
    // password since that would lock the user out.
    const setupToken = crypto.randomBytes(32).toString('hex');
    const setupExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token', ?)`).run(setupToken);
    tenantDb.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('setup_token_expires', ?)`).run(setupExpiry);
    log('4/7 admin user', `NONE found — generated setup token (valid 24h)`);
    console.log('');
    console.log(`  ==> Complete account setup at:`);
    console.log(`      https://${slug}.${process.env.BASE_DOMAIN}/auth/setup?token=${setupToken}`);
    console.log(`      (email: ${row.admin_email})`);
    console.log('');
  } else {
    log('4/7 admin user', `${userCount} user(s) exist (preserving)`);
  }

  tenantDb.close();

  // ─── 5. Uploads directory ───────────────────────────────────────
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
    log('5/7 uploads dir', `created ${uploadsDir}`);
  } else {
    log('5/7 uploads dir', `exists (preserving)`);
  }

  // ─── 6. Cloudflare DNS record ───────────────────────────────────
  const cfEnabled = !!(process.env.CLOUDFLARE_API_TOKEN && process.env.CLOUDFLARE_ZONE_ID && process.env.SERVER_PUBLIC_IP);

  if (!cfEnabled) {
    log('6/7 CF DNS', 'SKIPPED — Cloudflare not configured in .env');
  } else if (row.cloudflare_record_id) {
    log('6/7 CF DNS', `already linked (record_id=${row.cloudflare_record_id})`);
  } else {
    try {
      const { createTenantDnsRecord } = await import('../packages/server/src/services/cloudflareDns.js');
      const recordId = await createTenantDnsRecord(slug);
      masterDb.prepare("UPDATE tenants SET cloudflare_record_id = ? WHERE id = ?").run(recordId, row.id);
      log('6/7 CF DNS', `CREATED record ${recordId} for ${slug}.${process.env.BASE_DOMAIN}`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[Repair] CF DNS creation failed: ${msg}`);
      console.error('[Repair] Continuing — you can retry later or add the record manually in the Cloudflare dashboard.');
    }
  }

  // ─── 7. Activate the tenant ─────────────────────────────────────
  if (row.status !== 'active') {
    const r = masterDb.prepare(
      "UPDATE tenants SET status = 'active', updated_at = datetime('now') WHERE id = ?"
    ).run(row.id);
    log('7/7 status', `flipped from "${row.status}" to "active" (${r.changes} row updated)`);
  } else {
    log('7/7 status', 'already active (preserving)');
  }

  // ─── Summary ────────────────────────────────────────────────────
  const finalRow = masterDb.prepare(
    "SELECT id, slug, name, status, cloudflare_record_id, updated_at FROM tenants WHERE id = ?"
  ).get(row.id);
  console.log('');
  console.log('[Repair] Done. Final state:');
  console.log(finalRow);

  masterDb.close();
}

main().catch((err) => {
  console.error('[Repair] Fatal error:', err);
  process.exit(1);
});
