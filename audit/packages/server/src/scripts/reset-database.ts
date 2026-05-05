#!/usr/bin/env npx tsx
/**
 * Reset the database for a clean start.
 *
 * INTENDED USE: Initial setup and development only.
 * This tool does not exist for production use — it will refuse to run there.
 *
 * Deletes ALL data: customers, tickets, invoices, inventory, SMS, etc.
 * Migrations and seed data are re-applied automatically on next server start.
 *
 * Usage: npx tsx src/scripts/reset-database.ts
 */

import fs from 'fs';
import path from 'path';
import readline from 'readline';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Hard block: this script is a dev/first-setup tool only.
if (process.env.NODE_ENV === 'production') {
  console.error('');
  console.error('  ERROR: reset-database is a dev/first-setup tool and cannot run in production.');
  console.error('  To reset a production database, restore from a backup instead.');
  console.error('');
  process.exit(1);
}

const dbPath = path.resolve(__dirname, '../../data/bizarre-crm.db');
const walPath = dbPath + '-wal';
const shmPath = dbPath + '-shm';

async function main(): Promise<void> {
  console.log('');
  console.log('=== Database Reset (dev/setup) ===');
  console.log(`Database: ${dbPath}`);
  console.log('');

  if (!fs.existsSync(dbPath)) {
    console.log('No database file found — nothing to reset.');
    process.exit(0);
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  const answer = await new Promise<string>(resolve =>
    rl.question('  Delete ALL data and reset the database? (yes/no): ', resolve)
  );
  rl.close();

  if (answer.trim().toLowerCase() !== 'yes') {
    console.log('Aborted.');
    process.exit(0);
  }

  for (const file of [dbPath, walPath, shmPath]) {
    if (fs.existsSync(file)) {
      fs.unlinkSync(file);
      console.log(`Deleted: ${path.basename(file)}`);
    }
  }

  console.log('');
  console.log('Database deleted. Start the server to recreate with fresh migrations + seed data.');
  console.log('  npx tsx src/index.ts');
}

main().catch(err => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
