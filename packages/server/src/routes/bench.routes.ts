/**
 * Technician "bench work" features — audit section 44.
 *
 * Three sub-domains are intentionally bundled into one route file:
 *   - /bench/timer/*    — per-user active work timers (44.6)
 *   - /bench/qc/*       — QC checklist catalogue + sign-off (44.10)
 *   - /bench/defects/*  — parts defect reporter + stats (44.14)
 *
 * Rationale for bundling: all three operate on a single ticket from the
 * SAME tech's point of view, and the frontend hits them together from one
 * toolbar on TicketDetailPage. Separating them into three files would
 * force the caller to manage three base URLs.
 *
 * Hard rule from task owner: we do NOT touch tickets.routes.ts. All logic
 * that wants to "block ticket completion unless QC passed" has to live in
 * tickets.routes.ts itself; here we only expose the helper used by that
 * check (GET /bench/qc/status/:ticketId) so an orchestrating middleware
 * can query it in the future.
 *
 * Voice notes (44.3): SKIPPED — see audit note. TODO below.
 */

import { Router } from 'express';
import crypto from 'crypto';
import path from 'path';
import fs from 'fs';
import multer from 'multer';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import { config } from '../config.js';
import { fileUploadValidator, releaseFileCount } from '../middleware/fileUploadValidator.js';
import { reserveStorage } from '../services/usageTracker.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import {
  validateRequiredString,
  validateTextLength,
  validateEnum,
  validateArrayBounds,
  validateIntegerQuantity,
} from '../utils/validate.js';

// Post-enrichment audit §9: per-user cap on defect report POSTs. Every
// report writes one row + optionally an image + optionally a notification.
// Without a cap, a fat-fingered refresh or a malicious tech can flood the
// parts_defect_reports table and spam the defect alert notification.
const BENCH_DEFECT_CATEGORY = 'bench_defect_report';
const BENCH_DEFECT_MAX = 10;
const BENCH_DEFECT_WINDOW_MS = 60 * 60 * 1000; // 10 reports per user per hour

// TODO(LOW, §26, audit 44.3, voice notes):
//   Long-press mic in notes composer, transcribe up to 60 s on a local or
//   server-side AI model. The audit explicitly flagged this as "really hard
//   to do, add last". Deferred for now — would live here as
//   POST /bench/voice-note { audio_base64 } -> { text }. SEVERITY=LOW:
//   nice-to-have feature, not a production blocker.

const logger = createLogger('bench.routes');

const router = Router();

// ────────────────────────────────────────────────────────────────────────────
// Multer — QC signatures and defect photos share the same upload policy
//
// SEC (post-enrichment §13, F1-F4 regression):
//   - allowlist ALLOWED_MIMES is enforced twice: once in multer fileFilter
//     (header MIME), and again by fileUploadValidator via magic-byte check
//     + `allowedMimes` whitelist post-multer. The fileUploadValidator is
//     mounted on every /bench upload route below.
//   - filename is `crypto.randomBytes(16).toString('hex') + validatedExt`.
//     Rejecting unknown extensions at the multer `filename` cb keeps
//     storage clean even when fileFilter lets a .jpg through that claims
//     to be image/jpeg at the header level.
//   - `limits.files` caps per-request file count so an attacker can't
//     tie multer up streaming 1000 empty "files".
//   - Per-tenant BYTE quota is enforced inside each handler via
//     `reserveStorage` (rolled back on downstream failure). Per-tenant
//     COUNT quota is enforced by fileUploadValidator.
// ────────────────────────────────────────────────────────────────────────────

const ALLOWED_MIMES = ['image/jpeg', 'image/png', 'image/webp'] as const;
const ALLOWED_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);

if (!fs.existsSync(config.uploadsPath)) {
  fs.mkdirSync(config.uploadsPath, { recursive: true });
}

function benchUploadDir(req: any, kind: string): string {
  const tenantSlug = req.tenantSlug;
  return tenantSlug
    ? path.join(config.uploadsPath, tenantSlug, 'bench', kind)
    : path.join(config.uploadsPath, 'bench', kind);
}

function makeBenchUpload(kind: string) {
  return multer({
    storage: multer.diskStorage({
      destination: (req, _file, cb) => {
        const dest = benchUploadDir(req, kind);
        if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
        cb(null, dest);
      },
      filename: (_req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
        if (!ext || !ALLOWED_EXTENSIONS.has(ext)) {
          cb(new Error('Unsupported image file extension'), '');
          return;
        }
        cb(null, `${crypto.randomBytes(16).toString('hex')}${ext}`);
      },
    }),
    limits: {
      fileSize: 5 * 1024 * 1024, // 5 MB per file (images only)
      files: 5, // no route here needs more than 2, extra buffer
    },
    fileFilter: (_req, file, cb) => {
      if ((ALLOWED_MIMES as readonly string[]).includes(file.mimetype)) cb(null, true);
      else cb(new Error('Only JPEG, PNG, WebP images allowed'));
    },
  });
}

const qcUpload = makeBenchUpload('qc-signatures');
const defectUpload = makeBenchUpload('defects');

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function parseJson<T>(val: string | null | undefined, fallback: T): T {
  if (!val) return fallback;
  try {
    return JSON.parse(val) as T;
  } catch {
    return fallback;
  }
}

async function getStoreFlag(adb: any, key: string, fallback: string): Promise<string> {
  try {
    const row = (await adb.get('SELECT value FROM store_config WHERE key = ?', key)) as
      | { value: string }
      | undefined;
    return row?.value ?? fallback;
  } catch {
    return fallback;
  }
}

interface BenchTimerRow {
  id: number;
  ticket_id: number;
  ticket_device_id: number | null;
  user_id: number;
  started_at: string;
  ended_at: string | null;
  pause_log_json: string | null;
  total_seconds: number | null;
  labor_rate_cents: number | null;
  labor_cost_cents: number | null;
  notes: string | null;
}

interface PauseSegment {
  pause_at: string;
  resume_at?: string;
}

/**
 * Validate a rate in cents — whole non-negative integer, bounded to a
 * sane ceiling. Rejects floats (e.g. "5000.5") and NaN/Infinity so we
 * never try to store "$50.005/hr" which would drift when multiplied.
 */
function validateRateCents(value: unknown, fieldName = 'labor_rate_cents'): number {
  const raw = typeof value === 'number' ? value : parseFloat(String(value));
  if (!isFinite(raw)) throw new AppError(`${fieldName} must be a number`, 400);
  if (!Number.isInteger(raw)) {
    throw new AppError(`${fieldName} must be whole cents (e.g. 5000 = $50/hr)`, 400);
  }
  if (raw < 0) throw new AppError(`${fieldName} cannot be negative`, 400);
  if (raw > 100_000_00) throw new AppError(`${fieldName} exceeds maximum`, 400); // $100,000/hr
  return raw;
}

/**
 * Integer-safe labor cost: (seconds * rate_cents) / 3600, rounded to the
 * nearest whole cent. Order matters — multiplying first avoids the float
 * drift of `(seconds / 3600) * rate_cents` when the result is not an
 * exact multiple of an hour.
 */
function computeLaborCostCents(seconds: number, rateCents: number): number {
  if (!isFinite(seconds) || !isFinite(rateCents)) return 0;
  if (seconds <= 0 || rateCents <= 0) return 0;
  // seconds and rateCents are already integers — this stays safe until
  // seconds * rateCents exceeds Number.MAX_SAFE_INTEGER (~9e15), which is
  // ~1 billion years at $100/hr. Good enough.
  return Math.round((seconds * rateCents) / 3600);
}

/**
 * Computes live elapsed seconds for a timer, subtracting any time spent
 * paused. Works for both finished timers and live ones (uses "now" when
 * ended_at is null).
 */
function computeElapsedSeconds(row: BenchTimerRow): number {
  const start = new Date(row.started_at).getTime();
  const end = row.ended_at ? new Date(row.ended_at).getTime() : Date.now();
  if (Number.isNaN(start) || Number.isNaN(end)) return 0;

  const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
  let paused = 0;
  for (const p of pauses) {
    const pa = new Date(p.pause_at).getTime();
    const pr = p.resume_at ? new Date(p.resume_at).getTime() : end;
    if (Number.isFinite(pa) && Number.isFinite(pr) && pr > pa) paused += pr - pa;
  }

  const active = end - start - paused;
  return Math.max(0, Math.round(active / 1000));
}

function isCurrentlyPaused(row: BenchTimerRow): boolean {
  const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
  if (pauses.length === 0) return false;
  const last = pauses[pauses.length - 1];
  return !!last && !last.resume_at;
}

async function requireBenchTimerEnabled(adb: any): Promise<void> {
  const flag = await getStoreFlag(adb, 'bench_timer_enabled', 'false');
  if (flag !== 'true') {
    throw new AppError('Bench timer is disabled for this store', 400);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BENCH TIMER
// ═══════════════════════════════════════════════════════════════════════════

// GET /bench/config — tell the UI what's switched on
router.get(
  '/config',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const [enabled, rate, qcRequired, defectThreshold] = await Promise.all([
      getStoreFlag(adb, 'bench_timer_enabled', 'false'),
      getStoreFlag(adb, 'bench_labor_rate_cents', '5000'),
      getStoreFlag(adb, 'qc_required', 'false'),
      getStoreFlag(adb, 'defect_alert_threshold_30d', '4'),
    ]);
    res.json({
      success: true,
      data: {
        bench_timer_enabled: enabled === 'true',
        bench_labor_rate_cents: Number(rate) || 0,
        qc_required: qcRequired === 'true',
        defect_alert_threshold_30d: Number(defectThreshold) || 4,
      },
    });
  }),
);

// GET /bench/timer/current — per-user active timer
router.get(
  '/timer/current',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user?.id;
    if (!userId) throw new AppError('Authentication required', 401);

    // Gracefully return null if the feature is off — so the frontend hook
    // can poll without throwing.
    const flag = await getStoreFlag(adb, 'bench_timer_enabled', 'false');
    if (flag !== 'true') {
      res.json({ success: true, data: null });
      return;
    }

    const row = (await adb.get(
      'SELECT * FROM bench_timers WHERE user_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1',
      userId,
    )) as BenchTimerRow | undefined;
    if (!row) {
      res.json({ success: true, data: null });
      return;
    }

    res.json({
      success: true,
      data: {
        ...row,
        pause_log: parseJson<PauseSegment[]>(row.pause_log_json, []),
        elapsed_seconds: computeElapsedSeconds(row),
        paused: isCurrentlyPaused(row),
      },
    });
  }),
);

// POST /bench/timer/start { ticket_id, ticket_device_id?, labor_rate_cents? }
router.post(
  '/timer/start',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    await requireBenchTimerEnabled(adb);

    const userId = req.user?.id;
    if (!userId) throw new AppError('Authentication required', 401);

    const ticketId = Number(req.body?.ticket_id);
    if (!Number.isFinite(ticketId) || ticketId <= 0) {
      throw new AppError('ticket_id is required', 400);
    }

    const ticketExists = await adb.get('SELECT id FROM tickets WHERE id = ?', ticketId);
    if (!ticketExists) throw new AppError('Ticket not found', 404);

    // Only one active timer per user. Close any existing one politely.
    const existing = (await adb.get(
      'SELECT * FROM bench_timers WHERE user_id = ? AND ended_at IS NULL',
      userId,
    )) as BenchTimerRow | undefined;
    if (existing) {
      const elapsed = computeElapsedSeconds(existing);
      const rate = existing.labor_rate_cents ?? 0;
      const cost = computeLaborCostCents(elapsed, rate);
      await adb.run(
        `UPDATE bench_timers SET ended_at = datetime('now'), total_seconds = ?, labor_cost_cents = ?,
           notes = COALESCE(notes || ' | ', '') || 'Auto-stopped when new timer started'
         WHERE id = ?`,
        elapsed,
        cost,
        existing.id,
      );
      logger.info('timer_auto_stopped_on_switch', {
        user_id: userId,
        old_timer_id: existing.id,
        old_ticket_id: existing.ticket_id,
      });
    }

    // Prefer the explicit body value (validated to whole cents) and fall
    // back to store_config. We validate the store_config result too so a
    // corrupted config row can't poison labor accounting.
    const bodyRate = req.body?.labor_rate_cents;
    let rateCents: number;
    if (bodyRate !== undefined && bodyRate !== null && bodyRate !== '') {
      rateCents = validateRateCents(bodyRate, 'labor_rate_cents');
    } else {
      const storeRate = Number(await getStoreFlag(adb, 'bench_labor_rate_cents', '5000'));
      rateCents = Number.isInteger(storeRate) && storeRate >= 0 ? storeRate : 5000;
    }

    // ticket_device_id is optional, but if supplied must be a real integer FK
    // so we don't stick "NaN" onto a timer row.
    let ticketDeviceId: number | null = null;
    if (req.body?.ticket_device_id !== undefined && req.body?.ticket_device_id !== null) {
      ticketDeviceId = validateIntegerQuantity(req.body.ticket_device_id, 'ticket_device_id');
      const deviceExists = await adb.get(
        'SELECT id FROM ticket_devices WHERE id = ? AND ticket_id = ?',
        ticketDeviceId,
        ticketId,
      );
      if (!deviceExists) throw new AppError('ticket_device_id not found on this ticket', 404);
    }

    const result = await adb.run(
      `INSERT INTO bench_timers (ticket_id, ticket_device_id, user_id, labor_rate_cents)
       VALUES (?, ?, ?, ?)`,
      ticketId,
      ticketDeviceId,
      userId,
      rateCents,
    );

    const newId = Number(result.lastInsertRowid);
    const row = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', newId)) as BenchTimerRow;

    audit(req.db, 'bench_timer_started', userId, req.ip ?? 'unknown', {
      timer_id: newId,
      ticket_id: ticketId,
    });

    res.status(201).json({
      success: true,
      data: { ...row, pause_log: [], elapsed_seconds: 0, paused: false },
    });
  }),
);

// POST /bench/timer/:id/pause
router.post(
  '/timer/:id/pause',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

    const row = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', id)) as
      | BenchTimerRow
      | undefined;
    if (!row) throw new AppError('Timer not found', 404);
    if (row.user_id !== req.user?.id) throw new AppError('Not your timer', 403);
    if (row.ended_at) throw new AppError('Timer already stopped', 400);
    if (isCurrentlyPaused(row)) throw new AppError('Timer already paused', 400);

    const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
    pauses.push({ pause_at: new Date().toISOString() });
    await adb.run('UPDATE bench_timers SET pause_log_json = ? WHERE id = ?', JSON.stringify(pauses), id);

    audit(req.db, 'bench_timer_paused', req.user?.id ?? null, req.ip ?? 'unknown', {
      timer_id: id,
      ticket_id: row.ticket_id,
    });

    const fresh = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', id)) as BenchTimerRow;
    res.json({
      success: true,
      data: {
        ...fresh,
        pause_log: parseJson<PauseSegment[]>(fresh.pause_log_json, []),
        elapsed_seconds: computeElapsedSeconds(fresh),
        paused: true,
      },
    });
  }),
);

// POST /bench/timer/:id/resume
router.post(
  '/timer/:id/resume',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

    const row = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', id)) as
      | BenchTimerRow
      | undefined;
    if (!row) throw new AppError('Timer not found', 404);
    if (row.user_id !== req.user?.id) throw new AppError('Not your timer', 403);
    if (row.ended_at) throw new AppError('Timer already stopped', 400);
    if (!isCurrentlyPaused(row)) throw new AppError('Timer is not paused', 400);

    const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
    const last = pauses[pauses.length - 1];
    if (last) last.resume_at = new Date().toISOString();
    await adb.run('UPDATE bench_timers SET pause_log_json = ? WHERE id = ?', JSON.stringify(pauses), id);

    audit(req.db, 'bench_timer_resumed', req.user?.id ?? null, req.ip ?? 'unknown', {
      timer_id: id,
      ticket_id: row.ticket_id,
    });

    const fresh = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', id)) as BenchTimerRow;
    res.json({
      success: true,
      data: {
        ...fresh,
        pause_log: parseJson<PauseSegment[]>(fresh.pause_log_json, []),
        elapsed_seconds: computeElapsedSeconds(fresh),
        paused: false,
      },
    });
  }),
);

// POST /bench/timer/:id/stop
router.post(
  '/timer/:id/stop',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

    const row = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', id)) as
      | BenchTimerRow
      | undefined;
    if (!row) throw new AppError('Timer not found', 404);
    if (row.user_id !== req.user?.id) throw new AppError('Not your timer', 403);
    if (row.ended_at) throw new AppError('Timer already stopped', 400);

    // If the timer is still paused, close the pause segment first so the
    // subtracted paused-time matches reality.
    if (isCurrentlyPaused(row)) {
      const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
      const last = pauses[pauses.length - 1];
      if (last) last.resume_at = new Date().toISOString();
      await adb.run('UPDATE bench_timers SET pause_log_json = ? WHERE id = ?', JSON.stringify(pauses), id);
      row.pause_log_json = JSON.stringify(pauses);
    }

    const elapsed = computeElapsedSeconds(row);
    const rate = row.labor_rate_cents ?? 0;
    const cost = computeLaborCostCents(elapsed, rate);
    const notes =
      req.body?.notes !== undefined
        ? validateTextLength(req.body.notes, 500, 'notes')
        : row.notes;

    await adb.run(
      `UPDATE bench_timers SET ended_at = datetime('now'),
        total_seconds = ?, labor_cost_cents = ?, notes = ?
       WHERE id = ?`,
      elapsed,
      cost,
      notes,
      id,
    );

    audit(req.db, 'bench_timer_stopped', req.user?.id ?? null, req.ip ?? 'unknown', {
      timer_id: id,
      ticket_id: row.ticket_id,
      total_seconds: elapsed,
      labor_cost_cents: cost,
    });

    const final = (await adb.get('SELECT * FROM bench_timers WHERE id = ?', id)) as BenchTimerRow;
    res.json({
      success: true,
      data: {
        ...final,
        pause_log: parseJson<PauseSegment[]>(final.pause_log_json, []),
        elapsed_seconds: elapsed,
        paused: false,
      },
    });
  }),
);

// GET /bench/timer/by-ticket/:ticketId — history for a ticket
router.get(
  '/timer/by-ticket/:ticketId',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const ticketId = Number(req.params.ticketId);
    if (!Number.isFinite(ticketId)) throw new AppError('Invalid ticket id', 400);

    const rows = (await adb.all(
      'SELECT * FROM bench_timers WHERE ticket_id = ? ORDER BY started_at DESC',
      ticketId,
    )) as BenchTimerRow[];

    const totalSeconds = rows
      .filter((r) => r.total_seconds != null)
      .reduce((sum, r) => sum + (r.total_seconds ?? 0), 0);
    const totalCost = rows
      .filter((r) => r.labor_cost_cents != null)
      .reduce((sum, r) => sum + (r.labor_cost_cents ?? 0), 0);

    res.json({
      success: true,
      data: {
        timers: rows.map((r) => ({
          ...r,
          pause_log: parseJson<PauseSegment[]>(r.pause_log_json, []),
          elapsed_seconds: computeElapsedSeconds(r),
          paused: isCurrentlyPaused(r),
        })),
        total_seconds: totalSeconds,
        total_cost_cents: totalCost,
      },
    });
  }),
);

// ═══════════════════════════════════════════════════════════════════════════
// QC CHECKLIST + SIGN-OFF
// ═══════════════════════════════════════════════════════════════════════════

// GET /bench/qc-checklist
router.get(
  '/qc-checklist',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const category = typeof req.query.category === 'string' ? req.query.category.trim() : '';
    const rows = category
      ? await adb.all(
          'SELECT * FROM qc_checklist_items WHERE is_active = 1 AND (device_category = ? OR device_category IS NULL) ORDER BY sort_order, id',
          category,
        )
      : await adb.all(
          'SELECT * FROM qc_checklist_items WHERE is_active = 1 ORDER BY sort_order, id',
        );
    res.json({ success: true, data: rows });
  }),
);

// POST /bench/qc-checklist — create item (admin)
router.post(
  '/qc-checklist',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
    const adb = req.asyncDb;
    const name = validateRequiredString(req.body?.name, 'name', 200);
    const deviceCategory =
      req.body?.device_category !== undefined && req.body?.device_category !== null
        ? validateTextLength(req.body.device_category, 80, 'device_category')
        : null;

    const result = await adb.run(
      `INSERT INTO qc_checklist_items (name, sort_order, is_active, device_category)
       VALUES (?, ?, ?, ?)`,
      name,
      Math.max(0, Number(req.body?.sort_order) || 0),
      req.body?.is_active === false ? 0 : 1,
      deviceCategory || null,
    );

    const row = await adb.get(
      'SELECT * FROM qc_checklist_items WHERE id = ?',
      Number(result.lastInsertRowid),
    );
    audit(req.db, 'qc_checklist_item_created', req.user?.id ?? null, req.ip ?? 'unknown', {
      id: Number(result.lastInsertRowid),
    });
    res.status(201).json({ success: true, data: row });
  }),
);

// PUT /bench/qc-checklist/:id
router.put(
  '/qc-checklist/:id',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);

    const existing = (await adb.get('SELECT * FROM qc_checklist_items WHERE id = ?', id)) as
      | { id: number; name: string; sort_order: number; is_active: number; device_category: string | null }
      | undefined;
    if (!existing) throw new AppError('Not found', 404);

    const updName =
      req.body?.name !== undefined
        ? validateRequiredString(req.body.name, 'name', 200)
        : existing.name;
    const updDeviceCategory =
      req.body?.device_category !== undefined
        ? req.body.device_category === null
          ? null
          : validateTextLength(req.body.device_category, 80, 'device_category') || null
        : existing.device_category;
    await adb.run(
      `UPDATE qc_checklist_items
       SET name = ?, sort_order = ?, is_active = ?, device_category = ?
       WHERE id = ?`,
      updName,
      req.body?.sort_order !== undefined ? Math.max(0, Number(req.body.sort_order) || 0) : existing.sort_order,
      req.body?.is_active !== undefined ? (req.body.is_active ? 1 : 0) : existing.is_active,
      updDeviceCategory,
      id,
    );
    audit(req.db, 'qc_checklist_item_updated', req.user?.id ?? null, req.ip ?? 'unknown', {
      id,
      name: updName,
    });
    const row = await adb.get('SELECT * FROM qc_checklist_items WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

// DELETE /bench/qc-checklist/:id
router.delete(
  '/qc-checklist/:id',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') throw new AppError('Admin only', 403);
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);
    await adb.run('DELETE FROM qc_checklist_items WHERE id = ?', id);
    audit(req.db, 'qc_checklist_item_deleted', req.user?.id ?? null, req.ip ?? 'unknown', { id });
    res.json({ success: true, data: { message: 'Deleted' } });
  }),
);

// GET /bench/qc/status/:ticketId — was this ticket QC-signed already?
router.get(
  '/qc/status/:ticketId',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const ticketId = Number(req.params.ticketId);
    if (!Number.isFinite(ticketId)) throw new AppError('Invalid ticket id', 400);

    const signOff = (await adb.get(
      'SELECT * FROM qc_sign_offs WHERE ticket_id = ? ORDER BY signed_at DESC LIMIT 1',
      ticketId,
    )) as
      | {
          id: number;
          ticket_id: number;
          tech_user_id: number;
          checklist_results_json: string;
          working_photo_path: string | null;
          tech_signature_path: string | null;
          signed_at: string;
        }
      | undefined;

    const qcRequired = (await getStoreFlag(adb, 'qc_required', 'false')) === 'true';

    res.json({
      success: true,
      data: {
        qc_required: qcRequired,
        signed: !!signOff,
        sign_off: signOff
          ? {
              ...signOff,
              checklist_results: parseJson<Array<{ item_id: number; passed: boolean }>>(
                signOff.checklist_results_json,
                [],
              ),
            }
          : null,
      },
    });
  }),
);

// POST /bench/qc/sign-off (multipart: photo + signature + JSON fields)
router.post(
  '/qc/sign-off',
  qcUpload.fields([
    { name: 'working_photo', maxCount: 1 },
    { name: 'tech_signature', maxCount: 1 },
  ]),
  fileUploadValidator({
    allowedMimes: ALLOWED_MIMES,
    getTenantDir: (r) => benchUploadDir(r, 'qc-signatures'),
  }),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const ticketId = Number(req.body?.ticket_id);
    if (!Number.isFinite(ticketId) || ticketId <= 0) {
      throw new AppError('ticket_id is required', 400);
    }
    const userId = req.user?.id;
    if (!userId) throw new AppError('Authentication required', 401);

    const ticket = await adb.get('SELECT id FROM tickets WHERE id = ?', ticketId);
    if (!ticket) throw new AppError('Ticket not found', 404);

    // Parse checklist results — guard parse errors + cap array length so a
    // crafted 100k-item blob doesn't DoS the DB.
    let results: unknown;
    try {
      results = JSON.parse(req.body?.checklist_results ?? '[]');
    } catch {
      throw new AppError('checklist_results must be valid JSON', 400);
    }
    const bounded = validateArrayBounds<unknown>(
      results ?? [],
      'checklist_results',
      500,
    );
    if (bounded.length === 0) {
      throw new AppError('At least one checklist item result is required', 400);
    }
    const sanitized = bounded
      .filter((r: unknown) => r && typeof r === 'object')
      .map((r: any) => ({
        item_id: Number(r.item_id),
        passed: Boolean(r.passed),
      }))
      .filter((r) => Number.isFinite(r.item_id));

    // Must-pass rule: every item in the active list for the ticket's device
    // category must have a `passed = true` entry.
    const device = (await adb.get<any>(
      'SELECT device_type FROM ticket_devices WHERE ticket_id = ? ORDER BY id LIMIT 1',
      ticketId,
    )) as { device_type: string | null } | undefined;
    const category = device?.device_type ?? null;

    const activeItems = (category
      ? await adb.all(
          'SELECT id FROM qc_checklist_items WHERE is_active = 1 AND (device_category = ? OR device_category IS NULL)',
          category,
        )
      : await adb.all(
          'SELECT id FROM qc_checklist_items WHERE is_active = 1 AND device_category IS NULL',
        )) as Array<{ id: number }>;

    const passedSet = new Set(sanitized.filter((r) => r.passed).map((r) => r.item_id));
    const missing = activeItems.filter((i) => !passedSet.has(i.id));
    if (missing.length > 0) {
      throw new AppError(
        `QC failed: ${missing.length} checklist item(s) not passed. Every item must be ticked before sign-off.`,
        400,
      );
    }

    // Files
    const files = (req.files as { [k: string]: Express.Multer.File[] } | undefined) ?? {};
    const workingPhotoFile = files.working_photo?.[0];
    const signatureFile = files.tech_signature?.[0];
    if (!workingPhotoFile) throw new AppError('working_photo image is required', 400);
    if (!signatureFile) throw new AppError('tech_signature image is required', 400);

    // SEC (§13): per-tenant byte quota — reserve BEFORE we commit the DB row.
    // If the tenant has no room for both files, delete what multer already
    // wrote to disk and release the file-count bump that fileUploadValidator
    // performed, then surface a 403.
    const totalBytes = (workingPhotoFile.size ?? 0) + (signatureFile.size ?? 0);
    if (
      !reserveStorage(
        (req as any).tenantId,
        totalBytes,
        (req as any).tenantLimits?.storageLimitMb ?? null,
      )
    ) {
      try { fs.unlinkSync(workingPhotoFile.path); } catch { /* ignore */ }
      try { fs.unlinkSync(signatureFile.path); } catch { /* ignore */ }
      releaseFileCount(req, 2);
      res.status(403).json({
        success: false,
        upgrade_required: true,
        feature: 'storage_limit',
        message: `Storage limit (${(req as any).tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for more storage.`,
      });
      return;
    }

    const tenantSlug = (req as any).tenantSlug;
    const relBase = tenantSlug
      ? `/uploads/${tenantSlug}/bench/qc-signatures`
      : '/uploads/bench/qc-signatures';
    const workingPhotoPath = `${relBase}/${workingPhotoFile.filename}`;
    const signaturePath = `${relBase}/${signatureFile.filename}`;

    let qcTicketDeviceId: number | null = null;
    if (req.body?.ticket_device_id !== undefined && req.body?.ticket_device_id !== null) {
      qcTicketDeviceId = validateIntegerQuantity(
        req.body.ticket_device_id,
        'ticket_device_id',
      );
      const deviceExists = await adb.get(
        'SELECT id FROM ticket_devices WHERE id = ? AND ticket_id = ?',
        qcTicketDeviceId,
        ticketId,
      );
      if (!deviceExists) throw new AppError('ticket_device_id not found on this ticket', 404);
    }
    const qcNotes =
      req.body?.notes !== undefined
        ? validateTextLength(req.body.notes, 1000, 'notes')
        : null;

    const result = await adb.run(
      `INSERT INTO qc_sign_offs
        (ticket_id, ticket_device_id, tech_user_id, checklist_results_json,
         tech_signature_path, working_photo_path, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ticketId,
      qcTicketDeviceId,
      userId,
      JSON.stringify(sanitized),
      signaturePath,
      workingPhotoPath,
      qcNotes || null,
    );

    audit(req.db, 'qc_sign_off', userId, req.ip ?? 'unknown', {
      ticket_id: ticketId,
      sign_off_id: Number(result.lastInsertRowid),
    });

    const row = await adb.get(
      'SELECT * FROM qc_sign_offs WHERE id = ?',
      Number(result.lastInsertRowid),
    );
    res.status(201).json({ success: true, data: row });
  }),
);

// ═══════════════════════════════════════════════════════════════════════════
// PARTS DEFECT REPORTER
// ═══════════════════════════════════════════════════════════════════════════

// POST /bench/defects/report (multipart)
router.post(
  '/defects/report',
  defectUpload.single('photo'),
  fileUploadValidator({
    allowedMimes: ALLOWED_MIMES,
    getTenantDir: (r) => benchUploadDir(r, 'defects'),
  }),
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const userId = req.user?.id;
    if (!userId) throw new AppError('Authentication required', 401);

    // Post-enrichment audit §9: per-user hourly cap on defect reports. Check
    // BEFORE the DB + disk work so an over-the-limit caller pays only for
    // the single rate-limits index lookup, not the upload + insert.
    const rateResult = consumeWindowRate(
      req.db,
      BENCH_DEFECT_CATEGORY,
      String(userId),
      BENCH_DEFECT_MAX,
      BENCH_DEFECT_WINDOW_MS,
    );
    if (!rateResult.allowed) {
      throw new AppError(
        `Defect report rate limit hit — try again in ${rateResult.retryAfterSeconds}s`,
        429,
      );
    }

    const inventoryItemId = Number(req.body?.inventory_item_id);
    if (!Number.isFinite(inventoryItemId) || inventoryItemId <= 0) {
      throw new AppError('inventory_item_id is required', 400);
    }

    const item = await adb.get(
      'SELECT id, name FROM inventory_items WHERE id = ?',
      inventoryItemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);

    const defectType = validateEnum(
      req.body?.defect_type,
      ['doa', 'intermittent', 'cosmetic', 'wrong_spec'] as const,
      'defect_type',
      false,
    );

    // ticket_id is optional; when supplied, must exist to avoid orphan rows.
    let defectTicketId: number | null = null;
    if (req.body?.ticket_id !== undefined && req.body?.ticket_id !== null) {
      defectTicketId = validateIntegerQuantity(req.body.ticket_id, 'ticket_id');
      const ticketRow = await adb.get(
        'SELECT id FROM tickets WHERE id = ?',
        defectTicketId,
      );
      if (!ticketRow) throw new AppError('ticket_id not found', 404);
    }
    const description =
      req.body?.description !== undefined
        ? validateTextLength(req.body.description, 2000, 'description')
        : null;

    const tenantSlug = (req as any).tenantSlug;
    const photo = req.file;

    // SEC (§13): reserve byte quota if a photo was uploaded.
    if (photo) {
      const bytes = photo.size ?? 0;
      if (
        !reserveStorage(
          (req as any).tenantId,
          bytes,
          (req as any).tenantLimits?.storageLimitMb ?? null,
        )
      ) {
        try { fs.unlinkSync(photo.path); } catch { /* ignore */ }
        releaseFileCount(req, 1);
        res.status(403).json({
          success: false,
          upgrade_required: true,
          feature: 'storage_limit',
          message: `Storage limit (${(req as any).tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for more storage.`,
        });
        return;
      }
    }

    const photoPath = photo
      ? `${tenantSlug ? `/uploads/${tenantSlug}/bench/defects` : '/uploads/bench/defects'}/${photo.filename}`
      : null;

    const result = await adb.run(
      `INSERT INTO parts_defect_reports
        (inventory_item_id, ticket_id, reported_by_user_id, defect_type, description, photo_path)
       VALUES (?, ?, ?, ?, ?, ?)`,
      inventoryItemId,
      defectTicketId,
      userId,
      defectType,
      description || null,
      photoPath,
    );

    // Threshold alert
    const threshold = Number(await getStoreFlag(adb, 'defect_alert_threshold_30d', '4')) || 4;
    const countRow = (await adb.get<any>(
      `SELECT COUNT(*) AS n FROM parts_defect_reports
       WHERE inventory_item_id = ? AND reported_at >= datetime('now', '-30 days')`,
      inventoryItemId,
    )) as { n: number };
    const count30d = Number(countRow?.n) || 0;

    let alertPersisted = false;
    let alertFailed = false;
    if (count30d >= threshold) {
      // Write a notification row if the table exists — we don't want to crash
      // the whole report endpoint just because the notifications table is
      // missing on an old tenant. But we DO record whether the write succeeded
      // so the response can tell the caller the honest truth instead of
      // silently claiming alert_triggered=true for a dropped notification.
      try {
        await adb.run(
          `INSERT INTO notifications (type, title, message, severity, created_at)
           VALUES ('defect_alert', ?, ?, 'warning', datetime('now'))`,
          `Defect alert: ${(item as any).name}`,
          `${count30d} defects reported in the last 30 days (threshold ${threshold}).`,
        );
        alertPersisted = true;
      } catch (err) {
        // SEC: previously `alert_error: err.message` was reflected in the
        // HTTP response, leaking raw DB / schema text (e.g. "no such table:
        // notifications") to the client. Now only a boolean is exposed;
        // operators still see the real cause via logger.warn below.
        alertFailed = true;
        logger.warn('defect alert notification insert failed', {
          error: err instanceof Error ? err.message : String(err),
          inventory_item_id: inventoryItemId,
        });
      }
    }

    audit(req.db, 'parts_defect_reported', userId, req.ip ?? 'unknown', {
      report_id: Number(result.lastInsertRowid),
      inventory_item_id: inventoryItemId,
      defect_type: defectType,
      count_30d: count30d,
    });

    const row = await adb.get(
      'SELECT * FROM parts_defect_reports WHERE id = ?',
      Number(result.lastInsertRowid),
    );

    res.status(201).json({
      success: true,
      data: {
        report: row,
        count_30d: count30d,
        threshold,
        // Honest: did the threshold math fire, AND did the notification row
        // actually persist? Both must be true to claim the alert went out.
        alert_triggered: count30d >= threshold,
        alert_persisted: alertPersisted,
        alert_failed: alertFailed,
      },
    });
  }),
);

// GET /bench/defects/stats?days=30 — top defective parts
router.get(
  '/defects/stats',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const days = Math.max(1, Math.min(365, Number(req.query.days) || 30));
    const rows = (await adb.all(
      `SELECT
         d.inventory_item_id,
         i.name,
         i.sku,
         COUNT(*) AS defect_count,
         MAX(d.reported_at) AS last_reported_at
       FROM parts_defect_reports d
       LEFT JOIN inventory_items i ON i.id = d.inventory_item_id
       WHERE d.reported_at >= datetime('now', ?)
       GROUP BY d.inventory_item_id
       ORDER BY defect_count DESC
       LIMIT 50`,
      `-${days} days`,
    )) as Array<{
      inventory_item_id: number;
      name: string | null;
      sku: string | null;
      defect_count: number;
      last_reported_at: string;
    }>;

    res.json({ success: true, data: { days, items: rows } });
  }),
);

// GET /bench/defects/by-item/:id — recent reports for a single part
router.get(
  '/defects/by-item/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new AppError('Invalid id', 400);
    const rows = await adb.all(
      `SELECT * FROM parts_defect_reports
       WHERE inventory_item_id = ?
       ORDER BY reported_at DESC
       LIMIT 100`,
      id,
    );
    res.json({ success: true, data: rows });
  }),
);

export default router;
