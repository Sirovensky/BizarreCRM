#!/usr/bin/env npx tsx
/**
 * Reset the database for a clean start.
 *
 * WARNING: This deletes ALL data — customers, tickets, invoices, inventory, SMS, etc.
 * Migrations and seed data are re-applied automatically on next server start.
 *
 * Usage: npx tsx src/scripts/reset-database.ts
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const dbPath = path.resolve(__dirname, '../../data/bizarre-crm.db');
const walPath = dbPath + '-wal';
const shmPath = dbPath + '-shm';

console.log('=== Database Reset ===');
console.log(`Database: ${dbPath}`);

if (!fs.existsSync(dbPath)) {
  console.log('No database file found — nothing to reset.');
  process.exit(0);
}

// Delete the DB and WAL/SHM files
for (const file of [dbPath, walPath, shmPath]) {
  if (fs.existsSync(file)) {
    fs.unlinkSync(file);
    console.log(`Deleted: ${path.basename(file)}`);
  }
}

console.log('\nDatabase deleted. Start the server to recreate with fresh migrations + seed data.');
console.log('  npx tsx src/index.ts');
