/**
 * One-shot backfill: create Cloudflare DNS records for tenants that don't
 * already have a `cloudflare_record_id` set.
 *
 * Safe to run multiple times — `createTenantDnsRecord` is idempotent:
 * it looks for an existing record for the slug first and reuses its ID
 * instead of creating a duplicate.
 *
 * Usage (from bizarre-crm/):
 *   npx tsx scripts/backfill-cloudflare-dns.ts
 *
 * Prereq: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, SERVER_PUBLIC_IP, and
 * BASE_DOMAIN must be set in .env (and MULTI_TENANT=true).
 */

import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from bizarre-crm/ (one level up from scripts/)
dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

async function main(): Promise<void> {
  // Validate required env vars before opening the DB
  const token = process.env.CLOUDFLARE_API_TOKEN;
  const zoneId = process.env.CLOUDFLARE_ZONE_ID;
  const publicIp = process.env.SERVER_PUBLIC_IP;
  const baseDomain = process.env.BASE_DOMAIN;
  const multiTenant = process.env.MULTI_TENANT === 'true';

  if (!multiTenant) {
    console.error('[Backfill] MULTI_TENANT must be true in .env. Aborting.');
    process.exit(1);
  }
  if (!token || !zoneId || !publicIp || !baseDomain) {
    console.error('[Backfill] Missing required env vars. Check .env:');
    console.error('  CLOUDFLARE_API_TOKEN:', token ? 'set' : 'MISSING');
    console.error('  CLOUDFLARE_ZONE_ID:  ', zoneId ? 'set' : 'MISSING');
    console.error('  SERVER_PUBLIC_IP:    ', publicIp ? 'set' : 'MISSING');
    console.error('  BASE_DOMAIN:         ', baseDomain ? 'set' : 'MISSING');
    process.exit(1);
  }

  // Import the service AFTER env is loaded, so its config reads the values.
  // Path resolves to packages/server/src/services/cloudflareDns.ts via tsx.
  const { createTenantDnsRecord } = await import(
    '../packages/server/src/services/cloudflareDns.js'
  );

  const masterDbPath = path.resolve(__dirname, '..', 'packages', 'server', 'data', 'master.db');
  console.log(`[Backfill] Opening master DB: ${masterDbPath}`);
  const masterDb = new Database(masterDbPath);

  // Ensure the column exists (in case the backfill runs before the server
  // has initialized the DB with the new ALTER).
  try { masterDb.exec("ALTER TABLE tenants ADD COLUMN cloudflare_record_id TEXT"); } catch {}

  const tenants = masterDb.prepare(
    "SELECT id, slug, status, cloudflare_record_id FROM tenants WHERE status IN ('active', 'suspended', 'provisioning') AND cloudflare_record_id IS NULL ORDER BY id"
  ).all() as Array<{ id: number; slug: string; status: string; cloudflare_record_id: string | null }>;

  if (tenants.length === 0) {
    console.log('[Backfill] No tenants need DNS records. Nothing to do.');
    masterDb.close();
    return;
  }

  console.log(`[Backfill] Found ${tenants.length} tenant(s) without DNS records:`);
  for (const t of tenants) console.log(`  - ${t.slug} (id=${t.id}, status=${t.status})`);
  console.log('');

  const updateStmt = masterDb.prepare(
    "UPDATE tenants SET cloudflare_record_id = ? WHERE id = ?"
  );

  let created = 0;
  let reused = 0;
  let failed = 0;

  for (const tenant of tenants) {
    try {
      // Note: createTenantDnsRecord logs "already exists, reusing" internally
      // when it finds a pre-existing record — we can't distinguish without
      // calling findTenantDnsRecord first, so we count both as "backfilled".
      const recordId = await createTenantDnsRecord(tenant.slug);
      updateStmt.run(recordId, tenant.id);
      console.log(`[Backfill] ✓ ${tenant.slug} → record ${recordId}`);
      created++;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[Backfill] ✗ ${tenant.slug}: ${msg}`);
      failed++;
    }
  }

  masterDb.close();

  console.log('');
  console.log(`[Backfill] Done. Backfilled: ${created}, Failed: ${failed}`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error('[Backfill] Fatal error:', err);
  process.exit(1);
});
