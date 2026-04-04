import { Router } from 'express';
import db from '../db/connection.js';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import {
  runRepairDeskImport,
  testRepairDeskConnection,
  requestCancel,
  nuclearWipe,
} from '../services/repairDeskImport.js';

const router = Router();

// ---------------------------------------------------------------------------
// GET /repairdesk/test-connection – Validate a RepairDesk API key
// ---------------------------------------------------------------------------
router.get(
  '/repairdesk/test-connection',
  asyncHandler(async (req, res) => {
    const apiKey = (req.query.api_key as string || '').trim();
    if (!apiKey) throw new AppError('api_key query parameter is required');

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
    const { api_key, entities } = req.body;

    if (!api_key) throw new AppError('api_key is required');
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
    const running = db.prepare(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    ).get();
    if (running) throw new AppError('An import is already in progress', 409);

    // Validate API key before creating runs
    const connTest = await testRepairDeskConnection(api_key);
    if (!connTest.ok) {
      throw new AppError(`RepairDesk API connection failed: ${connTest.message}`);
    }

    // Create one import_run row per entity
    const runIds: Record<string, number> = {};

    const createRuns = db.transaction(() => {
      const runs: any[] = [];

      for (const entity of entities) {
        const result = db.prepare(`
          INSERT INTO import_runs (source, entity_type, status, started_at)
          VALUES ('repairdesk', ?, 'pending', datetime('now'))
        `).run(entity);

        const id = Number(result.lastInsertRowid);
        runIds[entity] = id;

        runs.push({
          id,
          source: 'repairdesk',
          entity_type: entity,
          status: 'pending',
        });
      }

      return runs;
    });

    const runs = createRuns();

    // Kick off the import in the background (fire-and-forget)
    runRepairDeskImport({
      apiKey: api_key,
      entities: entities as any,
      runIds: runIds as any,
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
  asyncHandler(async (_req, res) => {
    const runs = db.prepare(`
      SELECT * FROM import_runs
      WHERE source = 'repairdesk'
      ORDER BY id DESC
      LIMIT 20
    `).all();

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
  asyncHandler(async (_req, res) => {
    // Signal the background import to stop
    requestCancel();

    // Also mark any pending (not-yet-started) runs as cancelled immediately
    const result = db.prepare(`
      UPDATE import_runs SET status = 'cancelled', completed_at = datetime('now')
      WHERE source = 'repairdesk' AND status = 'pending'
    `).run();

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
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const pageSize = Math.min(100, Math.max(1, parseInt(req.query.pagesize as string, 10) || 20));

    const { total } = db.prepare('SELECT COUNT(*) as total FROM import_runs').get() as { total: number };
    const totalPages = Math.ceil(total / pageSize);
    const offset = (page - 1) * pageSize;

    const runs = db.prepare(`
      SELECT * FROM import_runs
      ORDER BY id DESC
      LIMIT ? OFFSET ?
    `).all(pageSize, offset);

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
    const { api_key, confirm } = req.body;

    if (confirm !== 'NUCLEAR') {
      throw new AppError('Must send { confirm: "NUCLEAR" } to confirm data wipe');
    }
    if (!api_key) throw new AppError('api_key is required');

    // Require admin role
    if (req.user?.role !== 'admin') {
      throw new AppError('Only admin users can perform nuclear wipe', 403);
    }

    // Require password re-entry for destructive operation
    const { password } = req.body;
    if (!password) throw new AppError('Password required to confirm destructive operation', 400);
    const adminUser = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(req.user.id) as any;
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
    const running = db.prepare(
      "SELECT id FROM import_runs WHERE status IN ('running', 'pending') LIMIT 1"
    ).get();
    if (running) throw new AppError('An import is already in progress', 409);

    // Auto-backup before wipe
    try {
      const { runBackup } = await import('../services/backup.js');
      await runBackup();
      console.log('[Nuclear] Auto-backup completed before wipe');
    } catch (e) {
      console.warn('[Nuclear] Auto-backup failed, proceeding with wipe:', e);
    }

    // Step 1: Wipe all business data
    nuclearWipe();

    // Step 2: Create import runs for all entities
    const entities: Array<'customers' | 'inventory' | 'tickets' | 'invoices' | 'sms'> =
      ['customers', 'inventory', 'tickets', 'invoices', 'sms'];
    const runIds: Record<string, number> = {};
    const runs: any[] = [];

    db.transaction(() => {
      for (const entity of entities) {
        const result = db.prepare(`
          INSERT INTO import_runs (source, entity_type, status, started_at)
          VALUES ('repairdesk', ?, 'pending', datetime('now'))
        `).run(entity);
        const id = Number(result.lastInsertRowid);
        runIds[entity] = id;
        runs.push({ id, source: 'repairdesk', entity_type: entity, status: 'pending' });
      }
    })();

    // Step 3: Kick off full import in background (includes per-ticket notes fetch)
    runRepairDeskImport({
      apiKey: api_key,
      entities,
      runIds: runIds as any,
    }).catch(err => {
      console.error('[Nuclear Import] Fatal error:', err);
      db.prepare(`
        UPDATE import_runs SET status = 'failed', completed_at = datetime('now'),
        error_log = json_array(json_object('record_id', 'fatal', 'message', ?, 'timestamp', datetime('now')))
        WHERE source = 'repairdesk' AND status IN ('running', 'pending')
      `).run(String(err.message || 'Unknown').substring(0, 500));
    });

    res.status(201).json({
      success: true,
      data: {
        message: 'Nuclear wipe complete. Full reimport started (customers → inventory → tickets with notes → invoices → SMS). Poll GET /api/v1/import/repairdesk/status for progress.',
        runs,
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

// GET /oauth/authorize-url — Returns the URL to redirect the user to RD login
router.get(
  '/oauth/authorize-url',
  asyncHandler(async (req, res) => {
    const redirectUri = `${req.protocol}://${req.get('host')}/api/v1/import/oauth/callback`;
    const url = `${RD_OAUTH_BASE}/authorize?client_id=${RD_CLIENT_ID}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&state=bizarrecrm`;
    res.json({ success: true, data: { url, redirect_uri: redirectUri } });
  }),
);

// GET /oauth/callback — RepairDesk redirects here after user grants consent
router.get(
  '/oauth/callback',
  asyncHandler(async (req, res) => {
    const code = req.query.code as string;
    if (!code) {
      res.status(400).send('Missing authorization code');
      return;
    }

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
    db.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_access_token', ?)`).run(rdAccessToken);
    db.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_refresh_token', ?)`).run(rdRefreshToken || '');
    db.prepare(`INSERT OR REPLACE INTO store_config (key, value) VALUES ('rd_token_expires', ?)`).run(String(rdTokenExpiresAt));

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
  asyncHandler(async (_req, res) => {
    if (!rdRefreshToken) {
      // Try loading from store_config
      const stored = db.prepare("SELECT value FROM store_config WHERE key = 'rd_refresh_token'").get() as { value: string } | undefined;
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
  asyncHandler(async (_req, res) => {
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
