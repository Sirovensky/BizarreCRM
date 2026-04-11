#!/usr/bin/env npx tsx
/**
 * Re-import ticket notes and history from RepairDesk into a SPECIFIC tenant.
 *
 * The initial import used the /tickets list endpoint which returns notes=[] and hostory=[].
 * This script fetches each ticket individually via /tickets/{id} to get the full notes + history.
 *
 * Usage:
 *   RD_API_KEY=<your-key> npx tsx src/scripts/reimport-notes.ts --tenant <slug>
 *
 * --tenant <slug>   REQUIRED. Slug of the tenant to import into (looked up in master DB).
 *
 * API keys are no longer persisted in the DB — supply via env var only.
 */

import type Database from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';
import { config } from '../config.js';
import { initMasterDb, getMasterDb } from '../db/master-connection.js';
import { getTenantDb } from '../db/tenant-pool.js';

const log = createLogger('reimport-notes');

interface CliArgs {
  tenant: string;
}

/**
 * Parse process.argv looking for `--tenant <slug>` (or `--tenant=<slug>`).
 * Throws a readable error if the slug is missing so the CLI fails fast.
 */
function parseArgs(argv: readonly string[]): CliArgs {
  let tenant: string | null = null;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--tenant') {
      tenant = argv[i + 1] ?? null;
      i++;
    } else if (arg.startsWith('--tenant=')) {
      tenant = arg.slice('--tenant='.length);
    }
  }

  if (!tenant || tenant.trim() === '') {
    throw new Error('Missing required --tenant <slug> argument');
  }

  return { tenant: tenant.trim() };
}

/**
 * Resolve the tenant DB connection for the given slug. In multi-tenant mode we
 * go through the master DB + tenant pool so we write into the right physical
 * file. In single-tenant mode the script refuses to run — the whole point of
 * the flag is to prevent accidental writes to the template/main DB.
 */
function resolveTenantDb(slug: string): Database.Database {
  if (!config.multiTenant) {
    throw new Error(
      'reimport-notes requires multi-tenant mode (MULTI_TENANT=true). ' +
      'Single-tenant DBs should not be imported via this script.'
    );
  }

  initMasterDb();
  const masterDb = getMasterDb();
  if (!masterDb) {
    throw new Error('Master DB is unavailable — cannot resolve tenant');
  }

  const row = masterDb
    .prepare("SELECT slug, status FROM tenants WHERE slug = ?")
    .get(slug) as { slug: string; status: string } | undefined;

  if (!row) {
    throw new Error(`Tenant not found in master DB: ${slug}`);
  }
  if (row.status !== 'active') {
    throw new Error(`Tenant ${slug} is not active (status=${row.status})`);
  }

  return getTenantDb(slug);
}

let args: CliArgs;
try {
  args = parseArgs(process.argv.slice(2));
} catch (err) {
  log.error('Invalid CLI arguments', {
    error: err instanceof Error ? err.message : String(err),
  });
  console.error('\nUsage: RD_API_KEY=<key> npx tsx src/scripts/reimport-notes.ts --tenant <slug>\n');
  process.exit(1);
}

const API_KEY = process.env.RD_API_KEY || '';
const BASE_URL = (process.env.RD_API_URL || 'https://api.repairdesk.co/api/web/v1').replace(/\/$/, '');

if (!API_KEY) {
  log.error('No RepairDesk API key found. Set RD_API_KEY env var before running this script.');
  process.exit(1);
}

log.info('Starting re-import for tenant', { tenant: args.tenant });

let db: Database.Database;
try {
  db = resolveTenantDb(args.tenant);
} catch (err) {
  log.error('Failed to resolve tenant DB', {
    tenant: args.tenant,
    error: err instanceof Error ? err.message : String(err),
  });
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

// Prepared statements — bound to the tenant DB resolved above
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

// Get all imported ticket mappings (RD ID → local ID) for this tenant
const mappings = db.prepare(
  `SELECT source_id, local_id FROM import_id_map WHERE entity_type = 'ticket' ORDER BY local_id`
).all() as Array<{ source_id: string; local_id: number }>;

log.info('Found imported tickets to check for notes/history', {
  tenant: args.tenant,
  count: mappings.length,
});

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
          log.warn('Rate limited, waiting 5s', { ticket: rdId });
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
        log.info('Progress', {
          tenant: args.tenant,
          processed,
          total: mappings.length,
          notesImported,
          historyImported,
          fetchErrors,
        });
      }

      // Polite delay — 200ms between requests
      await sleep(200);

    } catch (err: unknown) {
      fetchErrors++;
      const msg = err instanceof Error ? err.message : 'Unknown error';
      if (processed % 100 === 0) {
        log.warn('Fetch error', { ticket: rdId, error: msg });
      }
    }
  }

  log.info('Re-import complete', {
    tenant: args.tenant,
    processed,
    total: mappings.length,
    skippedAlreadyHas,
    notesImported,
    historyImported,
    fetchErrors,
  });
}

main()
  .then(() => process.exit(0))
  .catch(err => {
    log.error('Fatal error', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
