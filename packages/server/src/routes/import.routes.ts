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
import { getConfigValue } from '../utils/configEncryption.js';
import { audit } from '../utils/audit.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET /repairdesk/test-connection – Validate a RepairDesk API key
// ---------------------------------------------------------------------------
router.post(
  '/repairdesk/test-connection',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin access required', 403);
    // Accept API key from request body, or fall back to DB-stored key
    const db = req.db;
    const apiKey = (req.body?.api_key as string || '').trim()
      || getConfigValue(db, 'rd_api_key')
      || '';
    if (!apiKey) throw new AppError('No RepairDesk API key found. Set it in Settings > Data Import, or pass api_key in request body.');

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

    // Use api_key from request body, or fall back to DB-stored key
    const api_key = (req.body.api_key as string)?.trim()
      || getConfigValue(db, 'rd_api_key')
      || '';
    if (!api_key) throw new AppError('No RepairDesk API key provided. Set it in Settings > Data Import, or pass api_key in request body.');
    if (!entities || !Array.isArray(entities) || entities.length === 0) {
      throw new AppError('entities must be a non-empty array (e.g. ["customers", "tickets", "invoices", "inventory", "sms"])');
    }

    const validEntities = ['customers', 'tickets', 'invoices', 'inventory', 'sms'];
    for (const e of entities) {
      if (!validEntities.includes(e)) {
        throw new AppError(`Invalid entity: ${e}. Valid entities: ${validEntities.join(', ')}`);
      }
    }

    // Check no import is already running
    const running = await adb.get(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    );
    if (running) throw new AppError('An import is already in progress', 409);

    // Validate API key before creating runs
    const connTest = await testRepairDeskConnection(api_key);
    if (!connTest.ok) {
      throw new AppError(`RepairDesk API connection failed: ${connTest.message}`);
    }

    // Create one import_run row per entity
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    for (const entity of entities) {
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

    // Kick off the import in the background (fire-and-forget)
    runRepairDeskImport(db, {
      apiKey: api_key,
      entities: entities as any,
      runIds: runIds as any,
      tenantSlug: (req as any).tenantSlug || undefined,
    }).catch(err => {
      console.error('[Import] Unhandled error in background import:', err);
      // Mark any still-pending/running runs as failed
      db.prepare(`
        UPDATE import_runs
        SET status = 'failed', completed_at = datetime('now'),
            error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairdesk' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown error').substring(0, 500));
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

    const api_key = (req.body.api_key as string)?.trim()
      || getConfigValue(db, 'rd_api_key')
      || '';
    if (!api_key) throw new AppError('No RepairDesk API key found. Set it in Settings > Data Import, or pass api_key in request body.');

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

    // Check no import is already running
    const running = await adb.get(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    );
    if (running) throw new AppError('An import is already in progress', 409);

    // MANDATORY backup before wipe — abort if it fails (matches factory-wipe pattern)
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup(db);
      console.log('[Nuclear] Auto-backup completed before wipe');
    } catch (e: any) {
      throw new AppError(`Backup failed — nuclear wipe ABORTED. Reason: ${e.message}`, 500);
    }

    // Step 1: Wipe only RepairDesk-imported data
    nuclearWipeSource(db, 'repairdesk');

    // Step 2: Create import runs for all entities
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices' | 'sms'> =
      ['customers', 'inventory', 'tickets', 'invoices', 'sms'];
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    for (const entity of entities) {
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
      console.error('[Nuclear Import] Fatal error:', err);
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairdesk' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown').substring(0, 500));
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

    // Check no import is already running
    const running = await adb.get(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    );
    if (running) throw new AppError('An import is already in progress', 409);

    // Validate API key before creating runs
    const connTest = await testConnectionRS(api_key.trim(), subdomain.trim());
    if (!connTest.ok) {
      throw new AppError(`RepairShopr API connection failed: ${connTest.message}`);
    }

    // Create one import_run row per entity
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    for (const entity of entities) {
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
      console.error('[RepairShopr Import] Unhandled error in background import:', err);
      db.prepare(`
        UPDATE import_runs
        SET status = 'failed', completed_at = datetime('now'),
            error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairshopr' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown error').substring(0, 500));
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

    // Check no import is already running
    const running = await adb.get(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    );
    if (running) throw new AppError('An import is already in progress', 409);

    // MANDATORY backup before wipe — abort if it fails (matches factory-wipe pattern)
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup(db);
      console.log('[RepairShopr Nuclear] Auto-backup completed before wipe');
    } catch (e: any) {
      throw new AppError(`Backup failed — nuclear wipe ABORTED. Reason: ${e.message}`, 500);
    }

    // Step 1: Wipe only RepairShopr-imported data
    nuclearWipeSource(db, 'repairshopr');

    // Step 2: Create import runs for all entities
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices'> =
      ['customers', 'inventory', 'tickets', 'invoices'];
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    for (const entity of entities) {
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
      console.error('[RepairShopr Nuclear Import] Fatal error:', err);
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairshopr' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown').substring(0, 500));
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

    // Check no import is already running
    const running = await adb.get(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    );
    if (running) throw new AppError('An import is already in progress', 409);

    // Validate API key before creating runs
    const connTest = await testConnectionMRA(api_key.trim());
    if (!connTest.ok) {
      throw new AppError(`MyRepairApp API connection failed: ${connTest.message}`);
    }

    // Create one import_run row per entity
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    for (const entity of entities) {
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
      console.error('[MyRepairApp Import] Unhandled error in background import:', err);
      db.prepare(`
        UPDATE import_runs
        SET status = 'failed', completed_at = datetime('now'),
            error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'myrepairapp' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown error').substring(0, 500));
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

    // Check no import is already running
    const running = await adb.get(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    );
    if (running) throw new AppError('An import is already in progress', 409);

    // MANDATORY backup before wipe — abort if it fails (matches factory-wipe pattern)
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup(db);
      console.log('[MyRepairApp Nuclear] Auto-backup completed before wipe');
    } catch (e: any) {
      throw new AppError(`Backup failed — nuclear wipe ABORTED. Reason: ${e.message}`, 500);
    }

    // Step 1: Wipe only MyRepairApp-imported data
    nuclearWipeSource(db, 'myrepairapp');

    // Step 2: Create import runs for all entities
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices'> =
      ['customers', 'inventory', 'tickets', 'invoices'];
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    for (const entity of entities) {
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
      console.error('[MyRepairApp Nuclear Import] Fatal error:', err);
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'myrepairapp' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown').substring(0, 500));
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

    db.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_access_token', ?)`).run(rdAccessToken);
    if (tokenData.refresh_token) {
      db.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_refresh_token', ?)`).run(rdRefreshToken);
    }
    db.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_token_expires', ?)`).run(String(rdTokenExpiresAt));

    res.json({ success: true, data: { message: 'Token refreshed', expires_in: tokenData.expires_in } });
  }),
);

// GET /oauth/status — Check if we have a valid RD token
router.get(
  '/oauth/status',
  asyncHandler(async (req, res) => {
    const db = req.db;
    // Load from memory or DB
    if (!rdAccessToken) {
      const stored = db.prepare("SELECT value FROM store_config WHERE key = 'rd_access_token'").get() as { value: string } | undefined;
      if (stored?.value) {
        rdAccessToken = stored.value;
        const exp = db.prepare("SELECT value FROM store_config WHERE key = 'rd_token_expires'").get() as { value: string } | undefined;
        rdTokenExpiresAt = exp?.value ? parseInt(exp.value) : 0;
        const rt = db.prepare("SELECT value FROM store_config WHERE key = 'rd_refresh_token'").get() as { value: string } | undefined;
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
