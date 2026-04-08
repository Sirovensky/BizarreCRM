#!/usr/bin/env npx tsx
/**
 * Re-import ticket notes and history from RepairDesk.
 *
 * The initial import used the /tickets list endpoint which returns notes=[] and hostory=[].
 * This script fetches each ticket individually via /tickets/{id} to get the full notes + history.
 *
 * Usage: npx tsx src/scripts/reimport-notes.ts
 *
 * Reads RD API key from store_config DB table (set via Settings UI).
 * Falls back to RD_API_KEY env var if DB has no key stored.
 */

import db from '../db/connection.js';

function getDbConfig(key: string): string | null {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value || null;
}

const API_KEY = getDbConfig('rd_api_key') || process.env.RD_API_KEY || '';
const BASE_URL = (getDbConfig('rd_api_url') || 'https://api.repairdesk.co/api/web/v1').replace(/\/$/, '');

if (!API_KEY) {
  console.error('No RepairDesk API key found. Set it in Settings > Data Import, or pass RD_API_KEY env var.');
  process.exit(1);
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function safeStr(val: unknown): string | null {
  if (val === undefined || val === null || val === '') return null;
  return String(val);
}

function toISODate(val: unknown): string | null {
  if (!val) return null;
  if (typeof val === 'number' || /^\d{10,13}$/.test(String(val))) {
    const ts = Number(val);
    const d = new Date(ts < 1e12 ? ts * 1000 : ts);
    if (!isNaN(d.getTime())) return d.toISOString().replace('T', ' ').substring(0, 19);
    return null;
  }
  const d = new Date(String(val));
  if (!isNaN(d.getTime())) return d.toISOString().replace('T', ' ').substring(0, 19);
  return null;
}

// Prepared statements
const insertNote = db.prepare(
  `INSERT INTO ticket_notes
    (ticket_id, ticket_device_id, user_id, type, content, is_flagged, created_at, updated_at)
   VALUES (?, ?, 1, ?, ?, ?, ?, ?)`
);
const insertHistory = db.prepare(
  `INSERT INTO ticket_history (ticket_id, user_id, action, description, created_at)
   VALUES (?, 1, ?, ?, ?)`
);
const countNotes = db.prepare(`SELECT COUNT(*) as cnt FROM ticket_notes WHERE ticket_id = ?`);
const countHistory = db.prepare(`SELECT COUNT(*) as cnt FROM ticket_history WHERE ticket_id = ?`);

// Get all imported ticket mappings (RD ID → local ID)
const mappings = db.prepare(
  `SELECT source_id, local_id FROM import_id_map WHERE entity_type = 'ticket' ORDER BY local_id`
).all() as Array<{ source_id: string; local_id: number }>;

console.log(`Found ${mappings.length} imported tickets to check for notes/history.`);

let processed = 0;
let notesImported = 0;
let historyImported = 0;
let skippedAlreadyHas = 0;
let fetchErrors = 0;

async function main(): Promise<void> {
  for (const { source_id: rdId, local_id: localTicketId } of mappings) {
    processed++;

    // Skip tickets that already have notes/history (from manual entry)
    const existingNotes = (countNotes.get(localTicketId) as { cnt: number }).cnt;
    const existingHistory = (countHistory.get(localTicketId) as { cnt: number }).cnt;
    if (existingNotes > 0 || existingHistory > 0) {
      skippedAlreadyHas++;
      continue;
    }

    // Fetch individual ticket from RD
    try {
      const url = `${BASE_URL}/tickets/${rdId}`;
      const resp = await fetch(url, {
        signal: AbortSignal.timeout(30000),
        headers: { 'Authorization': `Bearer ${API_KEY}` },
      });

      if (!resp.ok) {
        fetchErrors++;
        if (resp.status === 429) {
          console.log(`  Rate limited at ticket ${rdId}, waiting 5s...`);
          await sleep(5000);
          continue;
        }
        continue;
      }

      const json = await resp.json() as { success: boolean; data: Record<string, unknown> };
      if (!json.success) continue;

      const ticket = json.data as Record<string, unknown>;

      // Notes — RD field: notes (array), each has msg_text, type (0=internal, 1=diagnostic), is_flag, created_on
      const notes = Array.isArray(ticket.notes) ? ticket.notes : [];
      if (notes.length > 0) {
        db.transaction(() => {
          for (const note of notes) {
            const n = note as Record<string, unknown>;
            const content = safeStr(n.msg_text) || safeStr(n.tittle) || '';
            if (!content) continue;
            const noteType = n.type === 1 ? 'diagnostic' : 'internal';
            const noteDate = toISODate(n.created_on) || now();
            insertNote.run(localTicketId, null, noteType, content, n.is_flag ? 1 : 0, noteDate, noteDate);
            notesImported++;
          }
        })();
      }

      // History — RD typo field: hostory (array), each has description, creationdate
      const history = Array.isArray(ticket.hostory) ? ticket.hostory :
                      (Array.isArray((ticket as Record<string, unknown>).history) ? (ticket as Record<string, unknown>).history as unknown[] : []);
      if (history.length > 0) {
        db.transaction(() => {
          for (const h of history) {
            const entry = h as Record<string, unknown>;
            const desc = safeStr(entry.description) || '';
            if (!desc) continue;
            const hDate = toISODate(entry.creationdate) || now();
            insertHistory.run(localTicketId, 'import', desc, hDate);
            historyImported++;
          }
        })();
      }

      if (processed % 50 === 0) {
        console.log(`  Progress: ${processed}/${mappings.length} | Notes: ${notesImported} | History: ${historyImported} | Errors: ${fetchErrors}`);
      }

      // Polite delay — 200ms between requests
      await sleep(200);

    } catch (err: unknown) {
      fetchErrors++;
      const msg = err instanceof Error ? err.message : 'Unknown error';
      if (processed % 100 === 0) {
        console.log(`  Error on ticket ${rdId}: ${msg}`);
      }
    }
  }

  console.log('\n=== Re-import Complete ===');
  console.log(`Processed: ${processed}/${mappings.length}`);
  console.log(`Skipped (already has notes): ${skippedAlreadyHas}`);
  console.log(`Notes imported: ${notesImported}`);
  console.log(`History imported: ${historyImported}`);
  console.log(`Fetch errors: ${fetchErrors}`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
