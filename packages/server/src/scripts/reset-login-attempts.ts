#!/usr/bin/env npx tsx
/**
 * Clear rate-limit rows that block login/2FA/PIN flows.
 *
 * Hits every DB that can hold a `rate_limits` row: the single-tenant DB,
 * the multi-tenant master DB, and every file under `data/tenants/`. Per-DB
 * delete counts are printed so it's obvious which accounts were unblocked.
 *
 * Usage:
 *   npx tsx src/scripts/reset-login-attempts.ts                # clear auth categories across all DBs
 *   npx tsx src/scripts/reset-login-attempts.ts --tenant <slug> # limit to one tenant DB
 *   npx tsx src/scripts/reset-login-attempts.ts --all           # include non-auth categories (signup, forgot-password, etc.)
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import Database from 'better-sqlite3';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DATA_DIR = path.resolve(__dirname, '../../data');
const TENANTS_DIR = path.join(DATA_DIR, 'tenants');

// Categories used by auth.routes.ts / middleware/auth.ts. `--all` drops the
// filter entirely (also clears 'setup', 'forgot_password', plus any future
// category that lands in the same table).
const AUTH_CATEGORIES = ['login_ip', 'login_user', 'totp', 'pin', 'setup', 'forgot_password'] as const;

interface CliArgs {
  tenantSlug: string | null;
  all: boolean;
}

function parseArgs(argv: readonly string[]): CliArgs {
  let tenantSlug: string | null = null;
  let all = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--tenant') {
      tenantSlug = argv[i + 1] ?? null;
      i++;
    } else if (arg === '--all') {
      all = true;
    } else if (arg === '--help' || arg === '-h') {
      console.log('Usage: reset-login-attempts [--tenant <slug>] [--all]');
      process.exit(0);
    }
  }
  return { tenantSlug, all };
}

interface ClearResult {
  dbPath: string;
  deleted: number;
  skipped: boolean;
  error?: string;
}

function clearRateLimits(dbPath: string, categories: readonly string[] | null): ClearResult {
  if (!fs.existsSync(dbPath)) {
    return { dbPath, deleted: 0, skipped: true };
  }

  let db: Database.Database | null = null;
  try {
    db = new Database(dbPath);

    // rate_limits table is optional — tenant DBs that haven't run migration 069
    // or master DBs on fresh installs may not have it yet. Skip gracefully.
    const tableExists = db.prepare(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'rate_limits'"
    ).get();
    if (!tableExists) {
      return { dbPath, deleted: 0, skipped: true };
    }

    let info;
    if (categories === null) {
      info = db.prepare('DELETE FROM rate_limits').run();
    } else {
      const placeholders = categories.map(() => '?').join(',');
      info = db.prepare(
        `DELETE FROM rate_limits WHERE category IN (${placeholders})`
      ).run(...categories);
    }

    return { dbPath, deleted: info.changes, skipped: false };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return { dbPath, deleted: 0, skipped: false, error: message };
  } finally {
    db?.close();
  }
}

function findTenantDbs(tenantSlug: string | null): string[] {
  if (!fs.existsSync(TENANTS_DIR)) return [];

  const files = fs.readdirSync(TENANTS_DIR).filter(f => f.endsWith('.db'));
  if (!tenantSlug) {
    return files.map(f => path.join(TENANTS_DIR, f));
  }

  const match = files.find(f => f === `${tenantSlug}.db`);
  return match ? [path.join(TENANTS_DIR, match)] : [];
}

function main(): void {
  const { tenantSlug, all } = parseArgs(process.argv.slice(2));
  const categories = all ? null : AUTH_CATEGORIES;

  console.log('=== Reset Login Attempts ===');
  console.log(`Scope: ${all ? 'ALL categories' : `auth categories [${AUTH_CATEGORIES.join(', ')}]`}`);
  if (tenantSlug) console.log(`Tenant filter: ${tenantSlug}`);
  console.log('');

  const targets: string[] = [];
  if (!tenantSlug) {
    targets.push(path.join(DATA_DIR, 'bizarre-crm.db'));
    targets.push(path.join(DATA_DIR, 'master.db'));
  }
  targets.push(...findTenantDbs(tenantSlug));

  if (targets.length === 0) {
    console.log('No DB files found to process.');
    if (tenantSlug) console.log(`(Tenant "${tenantSlug}.db" does not exist in ${TENANTS_DIR})`);
    process.exit(1);
  }

  let totalDeleted = 0;
  let hadError = false;
  for (const target of targets) {
    const result = clearRateLimits(target, categories);
    const label = path.relative(DATA_DIR, result.dbPath);
    if (result.error) {
      console.log(`  ERROR   ${label}: ${result.error}`);
      hadError = true;
    } else if (result.skipped) {
      console.log(`  skipped ${label} (missing file or no rate_limits table)`);
    } else {
      console.log(`  cleared ${label}: ${result.deleted} row(s)`);
      totalDeleted += result.deleted;
    }
  }

  console.log('');
  console.log(`Total rows deleted: ${totalDeleted}`);
  process.exit(hadError ? 1 : 0);
}

main();
