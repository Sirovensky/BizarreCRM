import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from '../config.js';
import { runMigrations } from './migrate.js';
import { seedDatabase } from './seed.js';
import { seedDeviceModels } from './device-models-seed-runner.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CORE_TEMPLATE_TABLES = ['_migrations', 'store_config', 'users', 'sessions', 'setup_tokens'];

function missingCoreTemplateTables(db: Database.Database): string[] {
  const rows = db.prepare(`
    SELECT name
    FROM sqlite_master
    WHERE type = 'table'
      AND name IN (${CORE_TEMPLATE_TABLES.map(() => '?').join(', ')})
  `).all(...CORE_TEMPLATE_TABLES) as Array<{ name: string }>;
  const found = new Set(rows.map(row => row.name));
  return CORE_TEMPLATE_TABLES.filter(table => !found.has(table));
}

/**
 * Build or refresh the template database.
 * This is a pre-migrated, pre-seeded DB that gets copied when provisioning new tenants.
 * It does NOT contain any admin user — that's created per-tenant during provisioning.
 */
export function buildTemplateDb(): void {
  if (!config.multiTenant) return;

  const dir = path.dirname(config.templateDbPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  // Check if template needs rebuilding (compare migration count)
  // Use __dirname to reliably find migrations regardless of dbPath config
  const migrationsDir = path.resolve(__dirname, 'migrations');
  const migrationFiles = fs.existsSync(migrationsDir)
    ? fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).length
    : 0;

  let rebuildReason = 'template database is missing';
  let needsRebuild = !fs.existsSync(config.templateDbPath);

  if (!needsRebuild) {
    let tempDb: Database.Database | null = null;
    try {
      tempDb = new Database(config.templateDbPath);
      const missingTables = missingCoreTemplateTables(tempDb);
      if (missingTables.length > 0) {
        needsRebuild = true;
        rebuildReason = `template missing core tables: ${missingTables.join(', ')}`;
      }
      const applied = (tempDb.prepare("SELECT COUNT(*) as c FROM _migrations").get() as any)?.c || 0;
      if (!needsRebuild && applied < migrationFiles) {
        needsRebuild = true;
        rebuildReason = `template migrations behind (${applied}/${migrationFiles})`;
      }
    } catch {
      needsRebuild = true;
      rebuildReason = 'template schema could not be inspected';
    } finally {
      try { tempDb?.close(); } catch {}
    }
  }

  if (!needsRebuild) {
    console.log('[Multi-tenant] Template database is up to date');
    return;
  }

  // Remove stale template (including WAL/SHM sidecar files)
  for (const suffix of ['', '-wal', '-shm']) {
    const filePath = config.templateDbPath + suffix;
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }
  }

  console.log(`[Multi-tenant] Building template database (${rebuildReason})...`);

  const templateDb = new Database(config.templateDbPath);
  templateDb.pragma('journal_mode = WAL');
  templateDb.pragma('foreign_keys = ON');
  // D3-2: prevent SQLITE_BUSY cascades when concurrent writers contend.
  templateDb.pragma('busy_timeout = 5000');

  // Run all migrations
  runMigrations(templateDb);

  // Run seed data (statuses, tax classes, payment methods, device models)
  seedDatabase(templateDb);
  seedDeviceModels(templateDb);

  const missingTables = missingCoreTemplateTables(templateDb);
  if (missingTables.length > 0) {
    templateDb.close();
    throw new Error(`Template database build failed; missing core tables: ${missingTables.join(', ')}`);
  }

  templateDb.close();
  console.log('[Multi-tenant] Template database built successfully');
}
