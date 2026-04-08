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

  let needsRebuild = !fs.existsSync(config.templateDbPath);

  if (!needsRebuild) {
    try {
      const tempDb = new Database(config.templateDbPath);
      const applied = (tempDb.prepare("SELECT COUNT(*) as c FROM _migrations").get() as any)?.c || 0;
      tempDb.close();
      needsRebuild = applied < migrationFiles;
    } catch {
      needsRebuild = true;
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

  console.log('[Multi-tenant] Building template database...');

  const templateDb = new Database(config.templateDbPath);
  templateDb.pragma('journal_mode = WAL');
  templateDb.pragma('foreign_keys = ON');

  // Run all migrations
  runMigrations(templateDb);

  // Run seed data (statuses, tax classes, payment methods, device models)
  seedDatabase(templateDb);
  seedDeviceModels(templateDb);

  templateDb.close();
  console.log('[Multi-tenant] Template database built successfully');
}
