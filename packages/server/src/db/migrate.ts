import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export function runMigrations(db: any): void {
  // Create migrations tracking table
  db.exec(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  const migrationsDir = path.resolve(__dirname, 'migrations');
  if (!fs.existsSync(migrationsDir)) {
    console.log('No migrations directory found');
    return;
  }

  const files = fs.readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  const applied = new Set(
    db.prepare('SELECT name FROM _migrations').all().map((r: any) => r.name)
  );

  for (const file of files) {
    if (applied.has(file)) continue;

    console.log(`Running migration: ${file}`);
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf-8');

    // Some migrations target tables that only exist in the master (multi-tenant
    // controller) DB — e.g. `tenants`, `super_admins`. When migrate.ts runs
    // against a legacy single-tenant DB, those tables are absent and the
    // migration's ALTER/UPDATE would crash. Opt in with a header:
    //   -- @skip-if-no-table: tenants
    // If the named table is missing on the target DB, the migration is marked
    // as applied (so it is not re-attempted) and skipped silently.
    const skipIfNoTableMatch = /^[\t ]*--\s*@skip-if-no-table:\s*(\w+)\s*$/m.exec(sql);
    if (skipIfNoTableMatch) {
      const tableName = skipIfNoTableMatch[1];
      const tableExists = db
        .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?")
        .get(tableName);
      if (!tableExists) {
        db.prepare('INSERT INTO _migrations (name) VALUES (?)').run(file);
        console.log(`  Skipped (no such table: ${tableName}): ${file}`);
        continue;
      }
    }

    // Some migrations must run OUTSIDE a transaction — e.g. anything that
    // toggles `PRAGMA writable_schema` or issues `PRAGMA foreign_keys`, both of
    // which SQLite refuses to honor mid-transaction. Opt in with a header:
    //   -- @no-transaction
    // better-sqlite3 also locks sqlite_master in defensive mode by default.
    // unsafeMode(true) unlocks it for the duration of the exec and is
    // deterministically restored in the finally block.
    const noTransaction = /^[\t ]*--\s*@no-transaction\b/m.test(sql);

    try {
      if (noTransaction) {
        const unsafe = typeof db.unsafeMode === 'function';
        if (unsafe) db.unsafeMode(true);
        try {
          db.exec(sql);
          db.prepare('INSERT INTO _migrations (name) VALUES (?)').run(file);
        } finally {
          if (unsafe) db.unsafeMode(false);
        }
      } else {
        const runMigration = db.transaction(() => {
          db.exec(sql);
          db.prepare('INSERT INTO _migrations (name) VALUES (?)').run(file);
        });
        runMigration();
      }
      console.log(`  Applied: ${file}`);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`  FAILED migration ${file}: ${message}`);
      throw new Error(`Migration ${file} failed: ${message}`);
    }
  }
}

// Run if called directly
if (process.argv[1]?.endsWith('migrate.ts') || process.argv[1]?.endsWith('migrate.js')) {
  import('./connection.js').then(({ db }) => {
    runMigrations(db);
    console.log('Migrations complete');
    process.exit(0);
  });
}
