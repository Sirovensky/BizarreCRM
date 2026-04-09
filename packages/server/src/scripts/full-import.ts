#!/usr/bin/env npx tsx
/**
 * Full RepairDesk Import — run all import steps in sequence.
 *
 * Steps:
 *  1. Import customers, tickets, invoices, inventory, SMS (via bulk import endpoint)
 *  2. Re-import notes/history for each ticket (individual fetches)
 *
 * Prerequisites:
 *  - Server must be running (this calls the API endpoints)
 *  - RepairDesk API key must be saved in Settings > Data Import (stored in store_config DB table)
 *
 * Usage:
 *   1. Start the server: PORT=443 npx tsx src/index.ts
 *   2. In another terminal: npx tsx src/scripts/full-import.ts
 *
 * To reset and start fresh:
 *   npx tsx src/scripts/reset-database.ts
 *   PORT=443 npx tsx src/index.ts     # (recreates DB with seed data)
 *   npx tsx src/scripts/full-import.ts
 */

const SERVER_URL = process.env.SERVER_URL || 'http://localhost:443';

async function login(): Promise<string> {
  const resp = await fetch(`${SERVER_URL}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'admin', password: 'admin123' }),
  });
  const json = await resp.json() as { data: { accessToken: string } };
  return json.data.accessToken;
}

async function startImport(token: string): Promise<number> {
  const resp = await fetch(`${SERVER_URL}/api/v1/import/start`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      entities: ['customers', 'tickets', 'invoices', 'inventory', 'sms'],
    }),
  });
  const json = await resp.json() as { success: boolean; data: { runs: Array<{ id: number }> } };
  if (!json.success) throw new Error('Failed to start import');
  console.log('Import started. Run IDs:', json.data.runs.map(r => r.id));
  return json.data.runs[0]?.id || 0;
}

async function pollStatus(token: string): Promise<void> {
  let running = true;
  while (running) {
    await new Promise(resolve => setTimeout(resolve, 3000));
    const resp = await fetch(`${SERVER_URL}/api/v1/import/status`, {
      headers: { 'Authorization': `Bearer ${token}` },
    });
    const json = await resp.json() as { data: { runs: Array<{ entity_type: string; status: string; imported: number; total_records: number; errors: number }> } };
    const runs = json.data?.runs || [];

    console.log('--- Import Progress ---');
    for (const run of runs) {
      console.log(`  ${run.entity_type}: ${run.status} — ${run.imported}/${run.total_records} (${run.errors} errors)`);
    }

    running = runs.some(r => r.status === 'running' || r.status === 'pending');
  }
  console.log('\nBulk import complete!');
}

async function main(): Promise<void> {
  console.log('=== Full RepairDesk Import ===\n');

  console.log('Step 1: Logging in...');
  const token = await login();
  console.log('Logged in.\n');

  console.log('Step 2: Starting bulk import (customers, tickets, invoices, inventory, SMS)...');
  await startImport(token);
  await pollStatus(token);

  console.log('\nStep 3: Re-importing notes/history for each ticket...');
  console.log('(This fetches each ticket individually from RD API — takes a while)\n');

  // Import the reimport-notes module — it runs main() on import
  await import('./reimport-notes.js');

  console.log('\n=== All Import Steps Complete ===');
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
