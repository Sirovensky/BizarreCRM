import { Router } from 'express';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import {
  runRepairDeskImport,
  testRepairDeskConnection,
  requestCancel,
  factoryWipe,
  selectiveWipe,
  nuclearWipeSource,
} from '../services/repairDeskImport.js';
import { runBackup, getBackupSettings } from '../services/backup.js';
import {
  runRepairShoprImport,
  testConnectionRS,
  requestCancelRS,
} from '../services/repairShoprImport.js';
import {
  runMyRepairAppImport,
  testConnectionMRA,
  requestCancelMRA,
} from '../services/myRepairAppImport.js';
import fs from 'fs';
import path from 'path';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('import');

// ---------------------------------------------------------------------------
// Rate limit windows for import starts (audit section 23, PL3).
//   - Pro tenants: 1 import-start per 5 minutes, 10 per 24 hours
//   - Free tenants: 1 import-start per 60 minutes (strictly tighter — see
//     POST-ENRICH AUDIT §23.4). Free tier is a trial/evaluation experience;
//     throttling it to one import per hour stops a Free user from draining
//     the RepairDesk API quota the paying tenants also depend on.
// These are ceilings on *starts*, not record counts, so a single large
// import with big quotas is still allowed — this only prevents loop abuse.
// ---------------------------------------------------------------------------
const IMPORT_MIN_INTERVAL_MS = 5 * 60 * 1000;          // 5 minutes
const IMPORT_DAILY_WINDOW_MS = 24 * 60 * 60 * 1000;    // 24 hours
const IMPORT_MAX_PER_DAY = 10;
const IMPORT_FREE_MIN_INTERVAL_MS = 60 * 60 * 1000;    // 60 minutes (Free tier)
const IMPORT_LOCK_TTL_MS = 60 * 60 * 1000;             // 1 hour — TTL guard for stuck locks

// ---------------------------------------------------------------------------
// Error-log sanitizer (audit section 25, E10).
//
// Import failures store the error message in import_runs.error_log. The old
// code passed `String(err.message).substring(0, 500)` raw — so SQLite schema
// errors, absolute filesystem paths, and SQL fragments got persisted and
// surfaced to every tenant admin who could view the import history. This
// helper strips those leaks before the substring-and-store step.
//
// The goal is not to obliterate all debug info — the operator still needs to
// know "it broke during ticket 123" — but to drop the bits that only help an
// attacker (host paths, schema names, stack traces).
// ---------------------------------------------------------------------------
function sanitizeErrorMessage(err: unknown): string {
  const raw = err instanceof Error ? (err.message || err.name || 'Error') : String(err ?? 'Unknown error');
  let msg = String(raw);

  // Drop file paths: Windows (C:\... or C:/...) and POSIX (/foo/bar).
  msg = msg.replace(/[a-zA-Z]:[\\/][^\s"'`]+/g, '[path]');
  msg = msg.replace(/(^|[\s"'`(])\/[^\s"'`]+/g, '$1[path]');

  // Drop SQL table/column prefixes that SQLite likes to embed in constraint
  // errors, e.g. "UNIQUE constraint failed: tickets.order_id".
  msg = msg.replace(/constraint failed:\s+\w+\.\w+/gi, 'constraint failed');
  msg = msg.replace(/no such (table|column):\s+\w+(?:\.\w+)?/gi, 'no such $1');

  // Drop SQL fragments that sometimes leak in from prepared statement errors.
  msg = msg.replace(/\b(SELECT|INSERT|UPDATE|DELETE)\b[^\n]*/gi, '[sql]');

  // Drop stack trace tail ("at Foo (/path:123:45)").
  msg = msg.replace(/\s+at\s+.+?$/gm, '');

  // Collapse runs of whitespace that the substitutions may leave behind.
  msg = msg.replace(/\s{2,}/g, ' ').trim();

  if (!msg) msg = 'Import error (details redacted)';
  return msg.substring(0, 500);
}

// ---------------------------------------------------------------------------
// Atomic import lock claim/release (audit section 12, R1).
//
// Uses the singleton import_locks row (id=1, CHECK(id=1)) added in
// migration 084. Claiming is a conditional UPDATE that sets holder_id only
// when the current holder_id is NULL (or its TTL has expired). If another
// request beat us to it, result.changes === 0 and we know to return 409 —
// no TOCTOU window because the update is a single SQL statement inside a
// WAL-enforced write transaction.
// ---------------------------------------------------------------------------
function tryClaimImportLock(db: any, source: string, holderId: number): boolean {
  // Ensure the singleton row exists (idempotent — migration pre-seeded it).
  db.prepare(
    "INSERT OR IGNORE INTO import_locks (id, holder_id, source, claimed_at, expires_at) VALUES (1, NULL, NULL, NULL, NULL)"
  ).run();

  const expiresAt = new Date(Date.now() + IMPORT_LOCK_TTL_MS).toISOString();
  const result = db.prepare(`
    UPDATE import_locks
    SET holder_id = ?, source = ?, claimed_at = datetime('now'), expires_at = ?
    WHERE id = 1
      AND (holder_id IS NULL OR expires_at IS NULL OR expires_at < datetime('now'))
  `).run(holderId, source, expiresAt);

  return result.changes > 0;
}

function releaseImportLock(db: any, holderId?: number): void {
  try {
    if (holderId) {
      db.prepare(
        "UPDATE import_locks SET holder_id = NULL, source = NULL, claimed_at = NULL, expires_at = NULL WHERE id = 1 AND holder_id = ?"
      ).run(holderId);
    } else {
      db.prepare(
        "UPDATE import_locks SET holder_id = NULL, source = NULL, claimed_at = NULL, expires_at = NULL WHERE id = 1"
      ).run();
    }
  } catch (err) {
    logger.warn('Failed to release import lock', { error: err instanceof Error ? err.message : String(err) });
  }
}

// ---------------------------------------------------------------------------
// Per-tenant import rate limit enforcement (audit section 23, PL3).
//
// On each /start attempt:
//   1. Prune rate-limit rows older than 24h (or 60min for Free).
//   2. Count rows newer than 5 min → reject if >= 1 (Pro/default).
//   3. Count rows newer than 60 min → reject if >= 1 (Free tier only).
//   4. Count rows newer than 24h → reject if >= 10 (Pro/default).
//   5. Caller inserts a new row after it successfully claims the lock.
//
// This is deliberately simple and source-agnostic: we rate-limit across
// *all* import sources combined (RD + RS + MRA) because the goal is to
// prevent the tenant from thrashing external APIs in general.
//
// POST-ENRICH AUDIT §23.4: accepts the current tenantPlan so Free tenants
// get the strict 1-per-hour ceiling called out in the product spec. Old
// callers that pass no plan default to the 5-minute ceiling so single-tenant
// / admin surfaces keep working.
// ---------------------------------------------------------------------------
function enforceImportRateLimit(db: any, plan?: 'free' | 'pro' | null): void {
  // Prune old rows so the table does not grow unbounded.
  db.prepare(
    "DELETE FROM import_rate_limits WHERE started_at < datetime('now', ?)"
  ).run(`-${Math.ceil(IMPORT_DAILY_WINDOW_MS / 1000)} seconds`);

  // Free-tier strict cap: 1 import per 60 minutes. Check first so a Free
  // tenant sees the right error message instead of the generic 5-min one.
  if (plan === 'free') {
    const recentHour = db.prepare(
      "SELECT COUNT(*) as c FROM import_rate_limits WHERE started_at >= datetime('now', ?)"
    ).get(`-${Math.ceil(IMPORT_FREE_MIN_INTERVAL_MS / 1000)} seconds`) as { c: number } | undefined;
    if ((recentHour?.c ?? 0) >= 1) {
      throw new AppError(
        'Free tier allows one import per hour. Upgrade to Pro for faster import cadence.',
        429,
      );
    }
  }

  const recentMin = db.prepare(
    "SELECT COUNT(*) as c FROM import_rate_limits WHERE started_at >= datetime('now', ?)"
  ).get(`-${Math.ceil(IMPORT_MIN_INTERVAL_MS / 1000)} seconds`) as { c: number } | undefined;

  if ((recentMin?.c ?? 0) >= 1) {
    throw new AppError('Only one import allowed every 5 minutes. Please wait before starting another import.', 429);
  }

  const recentDay = db.prepare(
    "SELECT COUNT(*) as c FROM import_rate_limits WHERE started_at >= datetime('now', ?)"
  ).get(`-${Math.ceil(IMPORT_DAILY_WINDOW_MS / 1000)} seconds`) as { c: number } | undefined;

  if ((recentDay?.c ?? 0) >= IMPORT_MAX_PER_DAY) {
    throw new AppError(`Daily import limit reached (${IMPORT_MAX_PER_DAY} per 24 hours). Try again later.`, 429);
  }
}

function recordImportRateLimit(db: any, source: string, userId: number | null, ip: string): void {
  try {
    db.prepare(
      "INSERT INTO import_rate_limits (source, started_at, user_id, ip_address) VALUES (?, datetime('now'), ?, ?)"
    ).run(source, userId, ip);
  } catch (err) {
    logger.warn('Failed to record import rate limit row', { error: err instanceof Error ? err.message : String(err) });
  }
}

// ---------------------------------------------------------------------------
// GET /repairdesk/test-connection – Validate a RepairDesk API key
// ---------------------------------------------------------------------------
router.post(
  '/repairdesk/test-connection',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    // API key must be passed in the request body — it is never persisted on
    // the server. It only lives in memory for the duration of this request.
    const apiKey = (req.body?.api_key as string || '').trim();
    if (!apiKey) throw new AppError('api_key is required in the request body.');

    const result = await testRepairDeskConnection(apiKey);

    res.json({
      success: true,
      data: result,
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /repairdesk/start – Start a RepairDesk import run
// ---------------------------------------------------------------------------
router.post(
  '/repairdesk/start',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    const { entities } = req.body;

    // API key must be passed in the request body — it is never persisted on
    // the server. It only lives in memory for the duration of the import.
    const api_key = (req.body.api_key as string)?.trim() || '';
    if (!api_key) throw new AppError('api_key is required in the request body.');
    if (!entities || !Array.isArray(entities) || entities.length === 0) {
      throw new AppError('entities must be a non-empty array (e.g. ["customers", "tickets", "invoices", "inventory", "sms"])');
    }

    const validEntities = ['customers', 'tickets', 'invoices', 'inventory', 'sms'];
    for (const e of entities) {
      if (!validEntities.includes(e)) {
        throw new AppError(`Invalid entity: ${e}. Valid entities: ${validEntities.join(', ')}`);
      }
    }

    // R1: Enforce per-tenant rate limit BEFORE touching anything else.
    // Throws 429 if the 5-min or 24h ceiling is hit.
    enforceImportRateLimit(db, req.tenantPlan ?? null);

    // Validate API key before creating runs (still outside the lock — a bad
    // API key should never block legitimate later imports).
    const connTest = await testRepairDeskConnection(api_key);
    if (!connTest.ok) {
      throw new AppError(`RepairDesk API connection failed: ${connTest.message}`);
    }

    // R1: Seed the first import_run row *first*, then use its id as the
    // import lock holder. The atomic UPDATE on import_locks.holder_id wins
    // the race — if another concurrent POST beats us, the claim fails and
    // we clean up the seed row before returning 409.
    const seedResult = await adb.run(`
      INSERT INTO import_runs (source, entity_type, status, started_at)
      VALUES ('repairdesk', ?, 'pending', datetime('now'))
    `, entities[0]);
    const seedId = Number(seedResult.lastInsertRowid);

    if (!tryClaimImportLock(db, 'repairdesk', seedId)) {
      // Lost the race. Roll back the seed row so history stays clean.
      try {
        await adb.run('DELETE FROM import_runs WHERE id = ?', seedId);
      } catch { /* best-effort */ }
      throw new AppError('An import is already in progress', 409);
    }

    // Record the rate-limit row now that we hold the lock — a successful
    // claim counts against the ceiling even if the background import later
    // fails for its own reasons.
    recordImportRateLimit(db, 'repairdesk', req.user!.id, req.ip || 'unknown');

    // Create the remaining import_run rows (the first one already exists).
    const runIds: Record<string, number> = { [entities[0]]: seedId };
    const runs: any[] = [{
      id: seedId,
      source: 'repairdesk',
      entity_type: entities[0],
      status: 'pending',
    }];

    for (let i = 1; i < entities.length; i++) {
      const entity = entities[i];
      const result = await adb.run(`
        INSERT INTO import_runs (source, entity_type, status, started_at)
        VALUES ('repairdesk', ?, 'pending', datetime('now'))
      `, entity);

      const id = Number(result.lastInsertRowid);
      runIds[entity] = id;

      runs.push({
        id,
        source: 'repairdesk',
        entity_type: entity,
        status: 'pending',
      });
    }

    // Kick off the import in the background (fire-and-forget).
    // The lock is released in the finally handler attached below.
    runRepairDeskImport(db, {
      apiKey: api_key,
      entities: entities as any,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      logger.error('Unhandled error in background import', { source: 'repairdesk', error: err instanceof Error ? err.message : String(err) });
      // Mark any still-pending/running runs as failed with a sanitized message.
      db.prepare(`
        UPDATE import_runs
        SET status = 'failed', completed_at = datetime('now'),
            error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairdesk' AND status IN ('running', 'pending')
      `).run(sanitizeErrorMessage(err));
    }).finally(() => {
      releaseImportLock(db, seedId);
    });

    audit(db, 'import_started', req.user!.id, req.ip || 'unknown', { source: 'repairdesk', entities });

    res.status(201).json({
      success: true,
      data: {
        message: `Import started for: ${entities.join(', ')}. Poll GET /api/v1/import/repairdesk/status for progress.`,
        runs,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /repairdesk/status – Get latest import run status
// ---------------------------------------------------------------------------
router.get(
  '/repairdesk/status',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const runs = await adb.all(`
      SELECT * FROM import_runs
      WHERE source = 'repairdesk'
      ORDER BY id DESC
      LIMIT 20
    `);

    // Parse error_log JSON
    const parsed = runs.map((r: any) => ({
      ...r,
      error_log: safeParseJson(r.error_log, []),
    }));

    // Find if anything is currently running or pending
    const activeRun = parsed.find((r: any) => r.status === 'running' || r.status === 'pending');

    // Compute overall progress for active batch
    let overall: any = null;
    if (activeRun) {
      const batchRuns = parsed.filter((r: any) => r.status === 'running' || r.status === 'pending' || r.status === 'completed');
      overall = {
        total_entities: batchRuns.length,
        completed_entities: batchRuns.filter((r: any) => r.status === 'completed').length,
        total_records: batchRuns.reduce((sum: number, r: any) => sum + (r.total_records || 0), 0),
        imported: batchRuns.reduce((sum: number, r: any) => sum + (r.imported || 0), 0),
        skipped: batchRuns.reduce((sum: number, r: any) => sum + (r.skipped || 0), 0),
        errors: batchRuns.reduce((sum: number, r: any) => sum + (r.errors || 0), 0),
      };
    }

    res.json({
      success: true,
      data: {
        is_active: !!activeRun,
        overall,
        runs: parsed,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /repairdesk/cancel – Cancel running import
// ---------------------------------------------------------------------------
router.post(
  '/repairdesk/cancel',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    // Signal the background import to stop (per-tenant)
    requestCancel((req as any).tenantSlug || undefined);

    // Also mark any pending (not-yet-started) runs as cancelled immediately
    const result = await adb.run(`
      UPDATE import_runs SET status = 'cancelled', completed_at = datetime('now')
      WHERE source = 'repairdesk' AND status = 'pending'
    `);

    audit(db, 'import_cancelled', req.user!.id, req.ip || 'unknown', { source: 'repairdesk', cancelled_pending: result.changes });

    res.json({
      success: true,
      data: {
        message: 'Cancel requested. Running imports will stop after the current batch.',
        cancelled_pending: result.changes,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /history – List past import runs
// ---------------------------------------------------------------------------
router.get(
  '/history',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const countRow = await adb.get<{ total: number }>('SELECT COUNT(*) as total FROM import_runs');
    const total = countRow?.total ?? 0;
    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const runs = await adb.all(`
      SELECT * FROM import_runs
      ORDER BY id DESC
      LIMIT ? OFFSET ?
    `, pageSize, offset);

    const parsed = runs.map((r: any) => ({
      ...r,
      error_log: safeParseJson(r.error_log, []),
    }));

    res.json({
      success: true,
      data: {
        runs: parsed,
        pagination: { page, per_page: pageSize, total, total_pages: totalPages },
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /repairdesk/nuclear — Wipe ALL data and reimport everything from RD
// ---------------------------------------------------------------------------
router.post(
  '/repairdesk/nuclear',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const { confirm } = req.body;

    if (confirm !== 'NUCLEAR') {
      throw new AppError('Must send { confirm: "NUCLEAR" } to confirm data wipe');
    }

    // API key must be passed in the request body — it is never persisted on
    // the server. It only lives in memory for the duration of the import.
    const api_key = (req.body.api_key as string)?.trim() || '';
    if (!api_key) throw new AppError('api_key is required in the request body.');

    // Require admin role
    if (req.user?.role !== 'admin') {
      throw new AppError('Only admin users can perform nuclear wipe', 403);
    }

    // Require password re-entry for destructive operation
    const { password } = req.body;
    if (!password) throw new AppError('Password required to confirm destructive operation', 400);
    const adminUser = await adb.get<{ password_hash: string }>('SELECT password_hash FROM users WHERE id = ?', req.user.id);
    const bcryptMod = await import('bcryptjs');
    if (!adminUser || !bcryptMod.default.compareSync(password, adminUser.password_hash)) {
      throw new AppError('Invalid password', 401);
    }

    // Test connection first
    const connTest = await testRepairDeskConnection(api_key);
    if (!connTest.ok) {
      throw new AppError(`RepairDesk API connection failed: ${connTest.message}`);
    }

    // R1 + PL3: enforce per-tenant throttle and claim the singleton lock
    // atomically via a seed import_runs row.
    enforceImportRateLimit(db, req.tenantPlan ?? null);
    const seedResult = await adb.run(`
      INSERT INTO import_runs (source, entity_type, status, started_at)
      VALUES ('repairdesk', 'customers', 'pending', datetime('now'))
    `);
    const seedId = Number(seedResult.lastInsertRowid);
    if (!tryClaimImportLock(db, 'repairdesk', seedId)) {
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError('An import is already in progress', 409);
    }
    recordImportRateLimit(db, 'repairdesk', req.user!.id, req.ip || 'unknown');

    // MANDATORY backup before wipe — abort if it fails (matches factory-wipe pattern)
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup(db);
      logger.info('Auto-backup completed before nuclear wipe', { source: 'repairdesk' });
    } catch (e: unknown) {
      // Release the lock + clean seed row before surfacing the abort.
      releaseImportLock(db, seedId);
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError(`Backup failed — nuclear wipe ABORTED. Reason: ${sanitizeErrorMessage(e)}`, 500);
    }

    // Step 1: Wipe only RepairDesk-imported data
    nuclearWipeSource(db, 'repairdesk');

    // Step 2: Create import runs for all entities. Reuse the seed row as the
    // first entity ('customers') so the lock holder id stays valid.
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices' | 'sms'> =
      ['customers', 'inventory', 'tickets', 'invoices', 'sms'];
    const runIds: Record<string, number> = { customers: seedId };
    const runs: any[] = [{ id: seedId, source: 'repairdesk', entity_type: 'customers', status: 'pending' }];

    for (let i = 1; i < entities.length; i++) {
      const entity = entities[i];
      const result = await adb.run(`
        INSERT INTO import_runs (source, entity_type, status, started_at)
        VALUES ('repairdesk', ?, 'pending', datetime('now'))
      `, entity);
      const id = Number(result.lastInsertRowid);
      runIds[entity] = id;
      runs.push({ id, source: 'repairdesk', entity_type: entity, status: 'pending' });
    }

    // Step 3: Kick off full import in background (includes per-ticket notes fetch)
    runRepairDeskImport(db, {
      apiKey: api_key,
      entities,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      logger.error('Nuclear import fatal error', { source: 'repairdesk', error: err instanceof Error ? err.message : String(err) });
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairdesk' AND status IN ('running', 'pending')
      `).run(sanitizeErrorMessage(err));
    }).finally(() => {
      releaseImportLock(db, seedId);
    });

    audit(db, 'import_nuclear_wipe', req.user!.id, req.ip || 'unknown', { source: 'repairdesk' });

    res.status(201).json({
      success: true,
      data: {
        message: 'Nuclear wipe complete. Full reimport started (customers → inventory → tickets with notes → invoices → SMS). Poll GET /api/v1/import/repairdesk/status for progress.',
        runs,
      },
    });
  }),
);

// ===========================================================================
// RepairShopr routes
// ===========================================================================

// ---------------------------------------------------------------------------
// POST /repairshopr/test-connection – Validate RepairShopr API key + subdomain
// ---------------------------------------------------------------------------
router.post(
  '/repairshopr/test-connection',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const { api_key, subdomain } = req.body;
    if (!api_key || typeof api_key !== 'string' || !api_key.trim()) {
      throw new AppError('api_key is required');
    }
    if (!subdomain || typeof subdomain !== 'string' || !subdomain.trim()) {
      throw new AppError('subdomain is required');
    }

    const result = await testConnectionRS(api_key.trim(), subdomain.trim());

    res.json({
      success: true,
      data: result,
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /repairshopr/start – Start a RepairShopr import run
// ---------------------------------------------------------------------------
router.post(
  '/repairshopr/start',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    const { api_key, subdomain, entities } = req.body;

    if (!api_key || typeof api_key !== 'string' || !api_key.trim()) {
      throw new AppError('api_key is required');
    }
    if (!subdomain || typeof subdomain !== 'string' || !subdomain.trim()) {
      throw new AppError('subdomain is required');
    }
    if (!entities || !Array.isArray(entities) || entities.length === 0) {
      throw new AppError('entities must be a non-empty array (e.g. ["customers", "tickets", "invoices", "inventory"])');
    }

    const validEntities = ['customers', 'tickets', 'invoices', 'inventory'];
    for (const e of entities) {
      if (!validEntities.includes(e)) {
        throw new AppError(`Invalid entity: ${e}. Valid entities: ${validEntities.join(', ')}`);
      }
    }

    // R1 + PL3: per-tenant throttle before any external calls.
    enforceImportRateLimit(db, req.tenantPlan ?? null);

    // Validate API key before creating runs
    const connTest = await testConnectionRS(api_key.trim(), subdomain.trim());
    if (!connTest.ok) {
      throw new AppError(`RepairShopr API connection failed: ${connTest.message}`);
    }

    // R1: Atomic lock claim via a seed import_runs row.
    const seedResult = await adb.run(`
      INSERT INTO import_runs (source, entity_type, status, started_at)
      VALUES ('repairshopr', ?, 'pending', datetime('now'))
    `, entities[0]);
    const seedId = Number(seedResult.lastInsertRowid);
    if (!tryClaimImportLock(db, 'repairshopr', seedId)) {
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError('An import is already in progress', 409);
    }
    recordImportRateLimit(db, 'repairshopr', req.user!.id, req.ip || 'unknown');

    // Create the remaining import_run rows (the first one is the seed).
    const runIds: Record<string, number> = { [entities[0]]: seedId };
    const runs: any[] = [{
      id: seedId,
      source: 'repairshopr',
      entity_type: entities[0],
      status: 'pending',
    }];

    for (let i = 1; i < entities.length; i++) {
      const entity = entities[i];
      const result = await adb.run(`
        INSERT INTO import_runs (source, entity_type, status, started_at)
        VALUES ('repairshopr', ?, 'pending', datetime('now'))
      `, entity);

      const id = Number(result.lastInsertRowid);
      runIds[entity] = id;

      runs.push({
        id,
        source: 'repairshopr',
        entity_type: entity,
        status: 'pending',
      });
    }

    // Kick off the import in the background (fire-and-forget)
    runRepairShoprImport(db, {
      apiKey: api_key.trim(),
      subdomain: subdomain.trim(),
      entities: entities as any,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      logger.error('Unhandled error in background import', { source: 'repairshopr', error: err instanceof Error ? err.message : String(err) });
      db.prepare(`
        UPDATE import_runs
        SET status = 'failed', completed_at = datetime('now'),
            error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairshopr' AND status IN ('running', 'pending')
      `).run(sanitizeErrorMessage(err));
    }).finally(() => {
      releaseImportLock(db, seedId);
    });

    audit(db, 'import_started', req.user!.id, req.ip || 'unknown', { source: 'repairshopr', entities });

    res.status(201).json({
      success: true,
      data: {
        message: `Import started for: ${entities.join(', ')}. Poll GET /api/v1/import/repairshopr/status for progress.`,
        runs,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /repairshopr/status – Get latest RepairShopr import run status
// ---------------------------------------------------------------------------
router.get(
  '/repairshopr/status',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const runs = await adb.all(`
      SELECT * FROM import_runs
      WHERE source = 'repairshopr'
      ORDER BY id DESC
      LIMIT 20
    `);

    const parsed = runs.map((r: any) => ({
      ...r,
      error_log: safeParseJson(r.error_log, []),
    }));

    const activeRun = parsed.find((r: any) => r.status === 'running' || r.status === 'pending');

    let overall: any = null;
    if (activeRun) {
      const batchRuns = parsed.filter((r: any) => r.status === 'running' || r.status === 'pending' || r.status === 'completed');
      overall = {
        total_entities: batchRuns.length,
        completed_entities: batchRuns.filter((r: any) => r.status === 'completed').length,
        total_records: batchRuns.reduce((sum: number, r: any) => sum + (r.total_records || 0), 0),
        imported: batchRuns.reduce((sum: number, r: any) => sum + (r.imported || 0), 0),
        skipped: batchRuns.reduce((sum: number, r: any) => sum + (r.skipped || 0), 0),
        errors: batchRuns.reduce((sum: number, r: any) => sum + (r.errors || 0), 0),
      };
    }

    res.json({
      success: true,
      data: {
        is_active: !!activeRun,
        overall,
        runs: parsed,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /repairshopr/cancel – Cancel running RepairShopr import
// ---------------------------------------------------------------------------
router.post(
  '/repairshopr/cancel',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    requestCancelRS((req as any).tenantSlug || undefined);

    const result = await adb.run(`
      UPDATE import_runs SET status = 'cancelled', completed_at = datetime('now')
      WHERE source = 'repairshopr' AND status = 'pending'
    `);

    audit(db, 'import_cancelled', req.user!.id, req.ip || 'unknown', { source: 'repairshopr', cancelled_pending: result.changes });

    res.json({
      success: true,
      data: {
        message: 'Cancel requested. Running imports will stop after the current batch.',
        cancelled_pending: result.changes,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /repairshopr/nuclear — Wipe RepairShopr data and reimport everything
// ---------------------------------------------------------------------------
router.post(
  '/repairshopr/nuclear',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const { confirm, password, api_key, subdomain } = req.body;

    if (confirm !== 'NUCLEAR') {
      throw new AppError('Must send { confirm: "NUCLEAR" } to confirm data wipe');
    }

    if (!api_key || typeof api_key !== 'string' || !api_key.trim()) {
      throw new AppError('api_key is required');
    }
    if (!subdomain || typeof subdomain !== 'string' || !subdomain.trim()) {
      throw new AppError('subdomain is required');
    }

    // Require admin role
    if (req.user?.role !== 'admin') {
      throw new AppError('Only admin users can perform nuclear wipe', 403);
    }

    // Require password re-entry for destructive operation
    if (!password) throw new AppError('Password required to confirm destructive operation', 400);
    const adminUser = await adb.get<{ password_hash: string }>('SELECT password_hash FROM users WHERE id = ?', req.user.id);
    const bcryptMod = await import('bcryptjs');
    if (!adminUser || !bcryptMod.default.compareSync(password, adminUser.password_hash)) {
      throw new AppError('Invalid password', 401);
    }

    // Test connection first
    const connTest = await testConnectionRS(api_key.trim(), subdomain.trim());
    if (!connTest.ok) {
      throw new AppError(`RepairShopr API connection failed: ${connTest.message}`);
    }

    // R1 + PL3: per-tenant throttle + atomic lock claim via seed row.
    enforceImportRateLimit(db, req.tenantPlan ?? null);
    const seedResult = await adb.run(`
      INSERT INTO import_runs (source, entity_type, status, started_at)
      VALUES ('repairshopr', 'customers', 'pending', datetime('now'))
    `);
    const seedId = Number(seedResult.lastInsertRowid);
    if (!tryClaimImportLock(db, 'repairshopr', seedId)) {
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError('An import is already in progress', 409);
    }
    recordImportRateLimit(db, 'repairshopr', req.user!.id, req.ip || 'unknown');

    // MANDATORY backup before wipe — abort if it fails (matches factory-wipe pattern)
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup(db);
      logger.info('Auto-backup completed before nuclear wipe', { source: 'repairshopr' });
    } catch (e: unknown) {
      releaseImportLock(db, seedId);
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError(`Backup failed — nuclear wipe ABORTED. Reason: ${sanitizeErrorMessage(e)}`, 500);
    }

    // Step 1: Wipe only RepairShopr-imported data
    nuclearWipeSource(db, 'repairshopr');

    // Step 2: Create import runs for all entities. Reuse the seed row as the
    // first entity so the lock holder id stays valid.
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices'> =
      ['customers', 'inventory', 'tickets', 'invoices'];
    const runIds: Record<string, number> = { customers: seedId };
    const runs: any[] = [{ id: seedId, source: 'repairshopr', entity_type: 'customers', status: 'pending' }];

    for (let i = 1; i < entities.length; i++) {
      const entity = entities[i];
      const result = await adb.run(`
        INSERT INTO import_runs (source, entity_type, status, started_at)
        VALUES ('repairshopr', ?, 'pending', datetime('now'))
      `, entity);
      const id = Number(result.lastInsertRowid);
      runIds[entity] = id;
      runs.push({ id, source: 'repairshopr', entity_type: entity, status: 'pending' });
    }

    // Step 3: Kick off full import in background
    runRepairShoprImport(db, {
      apiKey: api_key.trim(),
      subdomain: subdomain.trim(),
      entities,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      logger.error('Nuclear import fatal error', { source: 'repairshopr', error: err instanceof Error ? err.message : String(err) });
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairshopr' AND status IN ('running', 'pending')
      `).run(sanitizeErrorMessage(err));
    }).finally(() => {
      releaseImportLock(db, seedId);
    });

    audit(db, 'import_nuclear_wipe', req.user!.id, req.ip || 'unknown', { source: 'repairshopr' });

    res.status(201).json({
      success: true,
      data: {
        message: 'Nuclear wipe complete. Full reimport started (customers -> inventory -> tickets -> invoices). Poll GET /api/v1/import/repairshopr/status for progress.',
        runs,
      },
    });
  }),
);

// ===========================================================================
// MyRepairApp routes
// ===========================================================================

// ---------------------------------------------------------------------------
// POST /myrepairapp/test-connection – Validate MyRepairApp API key
// ---------------------------------------------------------------------------
router.post(
  '/myrepairapp/test-connection',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const { api_key } = req.body;
    if (!api_key || typeof api_key !== 'string' || !api_key.trim()) {
      throw new AppError('api_key is required');
    }

    const result = await testConnectionMRA(api_key.trim());

    res.json({
      success: true,
      data: result,
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /myrepairapp/start – Start a MyRepairApp import run
// ---------------------------------------------------------------------------
router.post(
  '/myrepairapp/start',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    const { api_key, entities } = req.body;

    if (!api_key || typeof api_key !== 'string' || !api_key.trim()) {
      throw new AppError('api_key is required');
    }
    if (!entities || !Array.isArray(entities) || entities.length === 0) {
      throw new AppError('entities must be a non-empty array (e.g. ["customers", "tickets", "invoices", "inventory"])');
    }

    const validEntities = ['customers', 'tickets', 'invoices', 'inventory'];
    for (const e of entities) {
      if (!validEntities.includes(e)) {
        throw new AppError(`Invalid entity: ${e}. Valid entities: ${validEntities.join(', ')}`);
      }
    }

    // R1 + PL3: per-tenant throttle before any external calls.
    enforceImportRateLimit(db, req.tenantPlan ?? null);

    // Validate API key before creating runs
    const connTest = await testConnectionMRA(api_key.trim());
    if (!connTest.ok) {
      throw new AppError(`MyRepairApp API connection failed: ${connTest.message}`);
    }

    // R1: Atomic lock claim via a seed import_runs row.
    const seedResult = await adb.run(`
      INSERT INTO import_runs (source, entity_type, status, started_at)
      VALUES ('myrepairapp', ?, 'pending', datetime('now'))
    `, entities[0]);
    const seedId = Number(seedResult.lastInsertRowid);
    if (!tryClaimImportLock(db, 'myrepairapp', seedId)) {
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError('An import is already in progress', 409);
    }
    recordImportRateLimit(db, 'myrepairapp', req.user!.id, req.ip || 'unknown');

    // Create the remaining import_run rows (the first one is the seed).
    const runIds: Record<string, number> = { [entities[0]]: seedId };
    const runs: any[] = [{
      id: seedId,
      source: 'myrepairapp',
      entity_type: entities[0],
      status: 'pending',
    }];

    for (let i = 1; i < entities.length; i++) {
      const entity = entities[i];
      const result = await adb.run(`
        INSERT INTO import_runs (source, entity_type, status, started_at)
        VALUES ('myrepairapp', ?, 'pending', datetime('now'))
      `, entity);

      const id = Number(result.lastInsertRowid);
      runIds[entity] = id;

      runs.push({
        id,
        source: 'myrepairapp',
        entity_type: entity,
        status: 'pending',
      });
    }

    // Kick off the import in the background (fire-and-forget)
    runMyRepairAppImport(db, {
      apiKey: api_key.trim(),
      entities: entities as any,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      logger.error('Unhandled error in background import', { source: 'myrepairapp', error: err instanceof Error ? err.message : String(err) });
      db.prepare(`
        UPDATE import_runs
        SET status = 'failed', completed_at = datetime('now'),
            error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'myrepairapp' AND status IN ('running', 'pending')
      `).run(sanitizeErrorMessage(err));
    }).finally(() => {
      releaseImportLock(db, seedId);
    });

    audit(db, 'import_started', req.user!.id, req.ip || 'unknown', { source: 'myrepairapp', entities });

    res.status(201).json({
      success: true,
      data: {
        message: `Import started for: ${entities.join(', ')}. Poll GET /api/v1/import/myrepairapp/status for progress.`,
        runs,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /myrepairapp/status – Get latest MyRepairApp import run status
// ---------------------------------------------------------------------------
router.get(
  '/myrepairapp/status',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const runs = await adb.all(`
      SELECT * FROM import_runs
      WHERE source = 'myrepairapp'
      ORDER BY id DESC
      LIMIT 20
    `);

    const parsed = runs.map((r: any) => ({
      ...r,
      error_log: safeParseJson(r.error_log, []),
    }));

    const activeRun = parsed.find((r: any) => r.status === 'running' || r.status === 'pending');

    let overall: any = null;
    if (activeRun) {
      const batchRuns = parsed.filter((r: any) => r.status === 'running' || r.status === 'pending' || r.status === 'completed');
      overall = {
        total_entities: batchRuns.length,
        completed_entities: batchRuns.filter((r: any) => r.status === 'completed').length,
        total_records: batchRuns.reduce((sum: number, r: any) => sum + (r.total_records || 0), 0),
        imported: batchRuns.reduce((sum: number, r: any) => sum + (r.imported || 0), 0),
        skipped: batchRuns.reduce((sum: number, r: any) => sum + (r.skipped || 0), 0),
        errors: batchRuns.reduce((sum: number, r: any) => sum + (r.errors || 0), 0),
      };
    }

    res.json({
      success: true,
      data: {
        is_active: !!activeRun,
        overall,
        runs: parsed,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /myrepairapp/cancel – Cancel running MyRepairApp import
// ---------------------------------------------------------------------------
router.post(
  '/myrepairapp/cancel',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    const db = req.db;
    const adb = req.asyncDb;
    requestCancelMRA((req as any).tenantSlug || undefined);

    const result = await adb.run(`
      UPDATE import_runs SET status = 'cancelled', completed_at = datetime('now')
      WHERE source = 'myrepairapp' AND status = 'pending'
    `);

    audit(db, 'import_cancelled', req.user!.id, req.ip || 'unknown', { source: 'myrepairapp', cancelled_pending: result.changes });

    res.json({
      success: true,
      data: {
        message: 'Cancel requested. Running imports will stop after the current batch.',
        cancelled_pending: result.changes,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /myrepairapp/nuclear — Wipe MyRepairApp data and reimport everything
// ---------------------------------------------------------------------------
router.post(
  '/myrepairapp/nuclear',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const { confirm, password, api_key } = req.body;

    if (confirm !== 'NUCLEAR') {
      throw new AppError('Must send { confirm: "NUCLEAR" } to confirm data wipe');
    }

    if (!api_key || typeof api_key !== 'string' || !api_key.trim()) {
      throw new AppError('api_key is required');
    }

    // Require admin role
    if (req.user?.role !== 'admin') {
      throw new AppError('Only admin users can perform nuclear wipe', 403);
    }

    // Require password re-entry for destructive operation
    if (!password) throw new AppError('Password required to confirm destructive operation', 400);
    const adminUser = await adb.get<{ password_hash: string }>('SELECT password_hash FROM users WHERE id = ?', req.user.id);
    const bcryptMod = await import('bcryptjs');
    if (!adminUser || !bcryptMod.default.compareSync(password, adminUser.password_hash)) {
      throw new AppError('Invalid password', 401);
    }

    // Test connection first
    const connTest = await testConnectionMRA(api_key.trim());
    if (!connTest.ok) {
      throw new AppError(`MyRepairApp API connection failed: ${connTest.message}`);
    }

    // R1 + PL3: per-tenant throttle + atomic lock claim via seed row.
    enforceImportRateLimit(db, req.tenantPlan ?? null);
    const seedResult = await adb.run(`
      INSERT INTO import_runs (source, entity_type, status, started_at)
      VALUES ('myrepairapp', 'customers', 'pending', datetime('now'))
    `);
    const seedId = Number(seedResult.lastInsertRowid);
    if (!tryClaimImportLock(db, 'myrepairapp', seedId)) {
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError('An import is already in progress', 409);
    }
    recordImportRateLimit(db, 'myrepairapp', req.user!.id, req.ip || 'unknown');

    // MANDATORY backup before wipe — abort if it fails (matches factory-wipe pattern)
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup(db);
      logger.info('Auto-backup completed before nuclear wipe', { source: 'myrepairapp' });
    } catch (e: unknown) {
      releaseImportLock(db, seedId);
      try { await adb.run('DELETE FROM import_runs WHERE id = ?', seedId); } catch { /* best-effort */ }
      throw new AppError(`Backup failed — nuclear wipe ABORTED. Reason: ${sanitizeErrorMessage(e)}`, 500);
    }

    // Step 1: Wipe only MyRepairApp-imported data
    nuclearWipeSource(db, 'myrepairapp');

    // Step 2: Create import runs for all entities. Reuse the seed row as the
    // first entity so the lock holder id stays valid.
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices'> =
      ['customers', 'inventory', 'tickets', 'invoices'];
    const runIds: Record<string, number> = { customers: seedId };
    const runs: any[] = [{ id: seedId, source: 'myrepairapp', entity_type: 'customers', status: 'pending' }];

    for (let i = 1; i < entities.length; i++) {
      const entity = entities[i];
      const result = await adb.run(`
        INSERT INTO import_runs (source, entity_type, status, started_at)
        VALUES ('myrepairapp', ?, 'pending', datetime('now'))
      `, entity);
      const id = Number(result.lastInsertRowid);
      runIds[entity] = id;
      runs.push({ id, source: 'myrepairapp', entity_type: entity, status: 'pending' });
    }

    // Step 3: Kick off full import in background
    runMyRepairAppImport(db, {
      apiKey: api_key.trim(),
      entities,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      logger.error('Nuclear import fatal error', { source: 'myrepairapp', error: err instanceof Error ? err.message : String(err) });
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'myrepairapp' AND status IN ('running', 'pending')
      `).run(sanitizeErrorMessage(err));
    }).finally(() => {
      releaseImportLock(db, seedId);
    });

    audit(db, 'import_nuclear_wipe', req.user!.id, req.ip || 'unknown', { source: 'myrepairapp' });

    res.status(201).json({
      success: true,
      data: {
        message: 'Nuclear wipe complete. Full reimport started (customers -> inventory -> tickets -> invoices). Poll GET /api/v1/import/myrepairapp/status for progress.',
        runs,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /factory-wipe/counts — Row counts for wipe preview
// ---------------------------------------------------------------------------
router.get(
  '/factory-wipe/counts',
  asyncHandler(async (req, res) => {
    // Admin-only (authMiddleware applied at router mount)
    if (req.user?.role !== 'admin') {
      throw new AppError('Only admin users can view wipe counts', 403);
    }

    const adb = req.asyncDb;
    const ALLOWED_TABLES = new Set(['customers', 'tickets', 'invoices', 'inventory_items', 'sms_messages', 'call_logs', 'leads', 'estimates', 'expenses', 'pos_transactions']);
    const count = async (table: string): Promise<number> => {
      if (!ALLOWED_TABLES.has(table)) return 0;
      try {
        const row = await adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM ${table}`);
        return row?.c ?? 0;
      } catch {
        return 0;
      }
    };

    const [customers, tickets, invoices, inventory, sms_messages, call_logs, leads, estimates, expenses, pos_transactions] = await Promise.all([
      count('customers'),
      count('tickets'),
      count('invoices'),
      count('inventory_items'),
      count('sms_messages'),
      count('call_logs'),
      count('leads'),
      count('estimates'),
      count('expenses'),
      count('pos_transactions'),
    ]);

    res.json({
      success: true,
      data: {
        customers,
        tickets,
        invoices,
        inventory,
        sms: sms_messages + call_logs,
        leads_estimates: leads + estimates,
        expenses_pos: expenses + pos_transactions,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// POST /factory-wipe — Selective data wipe with mandatory backup
// ---------------------------------------------------------------------------
router.post(
  '/factory-wipe',
  asyncHandler(async (req, res) => {
    const db = req.db;
    const adb = req.asyncDb;
    const { confirm, password, categories } = req.body;

    // Require admin role
    if (req.user?.role !== 'admin') {
      throw new AppError('Only admin users can perform factory wipe', 403);
    }

    if (confirm !== 'FACTORY WIPE') {
      throw new AppError('Must send { confirm: "FACTORY WIPE" } to confirm', 400);
    }

    // Validate categories
    if (!categories || typeof categories !== 'object') {
      throw new AppError('categories must be an object with boolean values', 400);
    }
    const validCategories = [
      'customers', 'tickets', 'invoices', 'inventory', 'sms',
      'leads_estimates', 'expenses_pos',
      'reset_settings', 'reset_users', 'reset_statuses',
      'reset_tax_classes', 'reset_payment_methods', 'reset_templates',
    ];
    const selected = Object.keys(categories).filter(k => categories[k] === true);
    if (selected.length === 0) {
      throw new AppError('At least one category must be selected', 400);
    }
    for (const key of selected) {
      if (!validCategories.includes(key)) {
        throw new AppError(`Invalid category: ${key}. Valid: ${validCategories.join(', ')}`, 400);
      }
    }

    // Validate admin password
    const user = await adb.get<{ password_hash: string }>('SELECT password_hash FROM users WHERE id = ?', req.user!.id);
    const bcryptMod = await import('bcryptjs');
    if (!user || !bcryptMod.default.compareSync(password, user.password_hash)) {
      throw new AppError('Invalid password', 401);
    }

    // Rate limit: max 5 wipe-backups per day
    const settings = getBackupSettings(db);
    const backupDir = settings.path || path.join(process.cwd(), 'data', 'backups');
    if (!fs.existsSync(backupDir)) {
      try { fs.mkdirSync(backupDir, { recursive: true }); }
      catch { throw new AppError(`Cannot create backup directory: ${backupDir}`, 500); }
    }
    const today = new Date().toISOString().slice(0, 10);
    const todayBackups = fs.readdirSync(backupDir).filter(f => f.includes(today) && f.endsWith('.db')).length;
    if (todayBackups >= 5) {
      throw new AppError('Too many resets today (max 5). Try again in 24h or contact support to bypass.', 429);
    }

    // MANDATORY backup before any deletion — abort if it fails
    const tenantSlug = (req as any).tenantSlug || 'standalone';
    const tenantId = (req as any).tenantId || 0;
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const backupName = `${tenantSlug}-t${tenantId}-${timestamp}.db`;
    const backupPath = path.join(backupDir, backupName);

    try {
      await db.backup(backupPath);
      console.log(`[SelectiveWipe] Pre-wipe backup created: ${backupPath}`);
    } catch (e: any) {
      throw new AppError(`Backup failed — wipe ABORTED. Reason: ${e.message}`, 500);
    }

    // Perform the selective wipe
    const result = selectiveWipe(db, categories, req.user!.id);
    audit(db, 'factory_wipe', req.user!.id, req.ip || 'unknown', { categories: selected, backup: backupName });

    res.json({
      success: true,
      data: {
        message: `Selective wipe complete. ${selected.length} categories processed.`,
        categories: selected,
        deleted: result.deleted,
        backup: backupName,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// OAuth2 Flow for RepairDesk
// ---------------------------------------------------------------------------

const RD_OAUTH_BASE = 'https://api.repairdesk.co/v1/oauth2';
const RD_CLIENT_ID = process.env.RD_CLIENT_ID || '';
const RD_CLIENT_SECRET = process.env.RD_CLIENT_SECRET || '';

// Store tokens in memory (could also persist to store_config)
let rdAccessToken: string | null = null;
let rdRefreshToken: string | null = null;
let rdTokenExpiresAt: number = 0;

/** Get the current valid RD access token, or null if not authenticated */
export function getRdAccessToken(): string | null {
  if (rdAccessToken && Date.now() < rdTokenExpiresAt) return rdAccessToken;
  return null;
}

// OAuth state store: state -> expiry timestamp (5 minute TTL)
const oauthStates = new Map<string, number>();
// Clean up expired states periodically
setInterval(() => {
  const now = Date.now();
  for (const [state, expiry] of oauthStates) {
    if (now > expiry) oauthStates.delete(state);
  }
}, 60_000);

// GET /oauth/authorize-url — Returns the URL to redirect the user to RD login
router.get(
  '/oauth/authorize-url',
  asyncHandler(async (req, res) => {
    const state = crypto.randomBytes(32).toString('hex');
    oauthStates.set(state, Date.now() + 5 * 60 * 1000); // 5 minute expiry
    const redirectUri = `${req.protocol}://${req.get('host')}/api/v1/import/oauth/callback`;
    const url = `${RD_OAUTH_BASE}/authorize?client_id=${RD_CLIENT_ID}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&state=${state}`;
    res.json({ success: true, data: { url, redirect_uri: redirectUri } });
  }),
);

// GET /oauth/callback — RepairDesk redirects here after user grants consent
router.get(
  '/oauth/callback',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const code = req.query.code as string;
    const state = req.query.state as string;

    if (!code) {
      res.status(400).send('Missing authorization code');
      return;
    }

    // Validate OAuth state to prevent CSRF
    if (!state || !oauthStates.has(state)) {
      res.status(400).send('Invalid or expired OAuth state. Please try authorizing again.');
      return;
    }
    oauthStates.delete(state); // Consume the state (single-use)

    const redirectUri = `${req.protocol}://${req.get('host')}/api/v1/import/oauth/callback`;

    // Exchange code for tokens
    const tokenResp = await fetch(`${RD_OAUTH_BASE}/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        client_id: RD_CLIENT_ID,
        client_secret: RD_CLIENT_SECRET,
        redirect_uri: redirectUri,
      }),
    });

    const tokenData = await tokenResp.json() as {
      access_token?: string;
      refresh_token?: string;
      expires_in?: number;
      error?: string;
      error_description?: string;
    };

    if (!tokenResp.ok || !tokenData.access_token) {
      res.status(400).send(`OAuth error: ${tokenData.error_description || tokenData.error || 'Unknown error'}`);
      return;
    }

    rdAccessToken = tokenData.access_token;
    rdRefreshToken = tokenData.refresh_token || null;
    rdTokenExpiresAt = Date.now() + (tokenData.expires_in || 3600) * 1000;

    // Also save to store_config for persistence
    await adb.run(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_access_token', ?)`, rdAccessToken);
    await adb.run(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_refresh_token', ?)`, rdRefreshToken || '');
    await adb.run(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_token_expires', ?)`, String(rdTokenExpiresAt));

    console.log('[OAuth] RepairDesk access token obtained successfully');

    // Redirect to settings page with success message
    res.send(`
      <html><body style="font-family:sans-serif;text-align:center;padding:60px">
        <h1 style="color:#22c55e">RepairDesk Connected!</h1>
        <p>OAuth token obtained successfully. You can close this window.</p>
        <p><a href="/" style="color:#3b82f6">Go to CRM</a></p>
        <script>setTimeout(()=>window.close(),3000)</script>
      </body></html>
    `);
  }),
);

// POST /oauth/refresh — Refresh the access token
router.post(
  '/oauth/refresh',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    if (!rdRefreshToken) {
      // Try loading from store_config
      const stored = await adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'rd_refresh_token'");
      if (stored?.value) rdRefreshToken = stored.value;
    }

    if (!rdRefreshToken) throw new AppError('No refresh token available. Re-authorize via OAuth.');

    const tokenResp = await fetch(`${RD_OAUTH_BASE}/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: rdRefreshToken,
        client_id: RD_CLIENT_ID,
        client_secret: RD_CLIENT_SECRET,
      }),
    });

    const tokenData = await tokenResp.json() as {
      access_token?: string;
      refresh_token?: string;
      expires_in?: number;
      error?: string;
    };

    if (!tokenResp.ok || !tokenData.access_token) {
      throw new AppError(`Token refresh failed: ${tokenData.error || 'Unknown error'}`);
    }

    rdAccessToken = tokenData.access_token;
    if (tokenData.refresh_token) rdRefreshToken = tokenData.refresh_token;
    rdTokenExpiresAt = Date.now() + (tokenData.expires_in || 3600) * 1000;

    await adb.run(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_access_token', ?)`, rdAccessToken);
    if (tokenData.refresh_token) {
      await adb.run(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_refresh_token', ?)`, rdRefreshToken);
    }
    await adb.run(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_token_expires', ?)`, String(rdTokenExpiresAt));

    res.json({ success: true, data: { message: 'Token refreshed', expires_in: tokenData.expires_in } });
  }),
);

// GET /oauth/status — Check if we have a valid RD token
router.get(
  '/oauth/status',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    // Load from memory or DB
    if (!rdAccessToken) {
      const stored = await adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'rd_access_token'");
      if (stored?.value) {
        rdAccessToken = stored.value;
        const exp = await adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'rd_token_expires'");
        rdTokenExpiresAt = exp?.value ? parseInt(exp.value) : 0;
        const rt = await adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'rd_refresh_token'");
        rdRefreshToken = rt?.value || null;
      }
    }

    const isValid = !!rdAccessToken && Date.now() < rdTokenExpiresAt;
    const expiresIn = isValid ? Math.round((rdTokenExpiresAt - Date.now()) / 1000) : 0;

    res.json({
      success: true,
      data: {
        connected: isValid,
        has_refresh_token: !!rdRefreshToken,
        expires_in_seconds: expiresIn,
      },
    });
  }),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function safeParseJson(val: any, fallback: any = []): any {
  if (!val) return fallback;
  try { return JSON.parse(val); } catch { return fallback; }
}

export default router;
