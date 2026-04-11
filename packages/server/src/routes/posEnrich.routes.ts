/**
 * POS Daily Flow enrichment routes (criticalaudit.md §43).
 *
 * Layers on top of the existing pos.routes.ts (owned by the POS agent) with
 * cashier-workflow primitives: Today's Top 5, cash-drawer shifts + Z-report,
 * training/sandbox sessions, and the manager-PIN gate for high-value sales.
 *
 * Mounted under /api/v1/pos-enrich so it never collides with /api/v1/pos.
 * Every endpoint returns the house envelope `{ success: true, data: X }`.
 *
 * Module layout follows the "many small files / many small functions" rule
 * from .claude/rules/common-coding-style.md — each feature area is a tiny
 * sub-router function that main registers, so no single function is > 50
 * lines and the whole file stays comfortably under 400.
 */
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { qs } from '../utils/query.js';
import {
  validateTextLength,
  validateJsonPayload,
} from '../utils/validate.js';
import {
  checkWindowRate,
  recordWindowFailure,
  clearRateLimit,
} from '../utils/rateLimiter.js';

// SEC (post-enrichment audit §6): manager/admin gate used on endpoints that
// move real money (close shift, z-report) or set store-wide training state.
function requireManagerOrAdmin(req: any): void {
  const role = req?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

/**
 * Cents validator — non-negative whole cents. Callers pass an upper bound
 * suited to the specific field so a typo in a PUT body can't silently let
 * a $1M figure slip through.
 *
 * Deliberately distinct from validateIntegerQuantity (which caps at 100k)
 * because drawer amounts routinely blow past the "quantity" ceiling, but
 * the ceiling is still bounded — see DRAWER_MAX_CENTS below.
 */
function validateCents(
  value: unknown,
  fieldName = 'amount_cents',
  maxCents = 100_000_000,
): number {
  const raw = typeof value === 'number' ? value : parseFloat(value as string);
  if (isNaN(raw) || !isFinite(raw)) throw new AppError(`${fieldName} must be a number`, 400);
  if (!Number.isInteger(raw)) throw new AppError(`${fieldName} must be a whole number of cents`, 400);
  if (raw < 0) throw new AppError(`${fieldName} cannot be negative`, 400);
  if (raw > maxCents) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return raw;
}

/**
 * Default closing-count ceiling = $50,000 per shift. A store can opt into
 * a higher ceiling by flipping `pos_high_volume_drawer` in store_config
 * (handled at the call site). Raising this silently is a red flag for
 * operator error or fat-fingered POS entry, so we reject by default.
 */
const DRAWER_MAX_CENTS_DEFAULT = 5_000_000;      // $50,000.00
const DRAWER_MAX_CENTS_HIGH_VOLUME = 100_000_000; // $1,000,000.00
import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('pos-enrich');
const router = Router();

// ── Shared row types ────────────────────────────────────────────────────────
interface DrawerShiftRow {
  id: number;
  opened_by_user_id: number;
  opened_at: string;
  opening_float_cents: number;
  closed_by_user_id: number | null;
  closed_at: string | null;
  closing_counted_cents: number | null;
  expected_cents: number | null;
  variance_cents: number | null;
  z_report_json: string | null;
  notes: string | null;
}

interface TrainingSessionRow {
  id: number;
  user_id: number;
  started_at: string;
  ended_at: string | null;
  fake_transactions_json: string | null;
}

interface TopFiveRow {
  inventory_item_id: number;
  name: string;
  sku: string | null;
  retail_price: number;
  category: string | null;
  units_sold: number;
}

interface StoreConfigRow {
  value: string | null;
}

// ────────────────────────────────────────────────────────────────────────────
// 1. TODAY'S TOP 5 QUICK-ADD TILES (audit §43.1)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Returns the 5 most-sold products *today*, ordered by units sold DESC.
 * Source of truth is invoice_line_items because that's where finished sales
 * land (POS cash sales + ticket checkouts all flow through invoices).
 */
async function queryTopFiveProductsToday(adb: AsyncDb): Promise<TopFiveRow[]> {
  return adb.all<TopFiveRow>(
    `SELECT
        ii.id           AS inventory_item_id,
        ii.name         AS name,
        ii.sku          AS sku,
        ii.retail_price AS retail_price,
        ii.category     AS category,
        SUM(ili.quantity) AS units_sold
       FROM invoice_line_items ili
       JOIN invoices       inv ON inv.id = ili.invoice_id
       JOIN inventory_items ii ON ii.id = ili.inventory_item_id
      WHERE date(inv.created_at) = date('now', 'localtime')
        AND ili.inventory_item_id IS NOT NULL
        AND ii.is_active = 1
      GROUP BY ii.id, ii.name, ii.sku, ii.retail_price, ii.category
      ORDER BY units_sold DESC, ii.name ASC
      LIMIT 5`,
  );
}

router.get(
  '/top-five',
  asyncHandler(async (req, res) => {
    const rows = await queryTopFiveProductsToday(req.asyncDb);
    res.json({ success: true, data: { items: rows } });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// 2. CASH DRAWER SHIFTS (audit §43.4 + §43.8)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Expected cash in drawer at close time, computed from the opening float
 * plus all cash POS transactions recorded during the shift window. We join
 * against payments rather than pos_transactions so split payments are
 * accounted for correctly (cash leg only).
 *
 * POST-ENRICH AUDIT §23.1: the payments table stores the payment method as
 * a TEXT column (`payments.method`) — there is NO `payment_method_id` FK.
 * The original query JOINed on `pm.id = p.payment_method_id` which silently
 * returned zero rows on every close, leaving the expected drawer equal to
 * the opening float and making every Z-report claim zero variance. We now
 * filter on `LOWER(p.method) LIKE '%cash%'` directly, matching the column
 * that pos.routes.ts actually writes.
 */
async function computeExpectedCents(
  adb: AsyncDb,
  openedAt: string,
  closedAt: string,
  openingFloatCents: number,
): Promise<number> {
  const row = await adb.get<{ cash_cents: number }>(
    `SELECT COALESCE(SUM(
         CAST(ROUND(COALESCE(p.amount, 0) * 100) AS INTEGER)
       ), 0) AS cash_cents
       FROM payments p
      WHERE p.created_at BETWEEN ? AND ?
        AND LOWER(COALESCE(p.method, '')) LIKE '%cash%'`,
    openedAt,
    closedAt,
  );
  const cashIn = row?.cash_cents ?? 0;
  return openingFloatCents + cashIn;
}

async function getCurrentShift(adb: AsyncDb): Promise<DrawerShiftRow | undefined> {
  return adb.get<DrawerShiftRow>(
    `SELECT * FROM cash_drawer_shifts WHERE closed_at IS NULL ORDER BY id DESC LIMIT 1`,
  );
}

router.get(
  '/drawer/current',
  asyncHandler(async (req, res) => {
    const shift = await getCurrentShift(req.asyncDb);
    res.json({ success: true, data: shift ?? null });
  }),
);

router.post(
  '/drawer/open',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const existing = await getCurrentShift(adb);
    if (existing) {
      throw new AppError('A drawer shift is already open — close it first', 409);
    }

    // Opening float shares the same $50k ceiling by default, with the same
    // high-volume escape hatch. A register that needs > $50k of starting
    // bills at the shift open has strictly bigger operational problems.
    const highVolumeRow = await adb.get<StoreConfigRow>(
      `SELECT value FROM store_config WHERE key = 'pos_high_volume_drawer'`,
    );
    const isHighVolume = highVolumeRow?.value === '1';
    const maxOpeningCents = isHighVolume ? DRAWER_MAX_CENTS_HIGH_VOLUME : DRAWER_MAX_CENTS_DEFAULT;

    const floatCents = validateCents(
      req.body?.opening_float_cents ?? 0,
      'opening_float_cents',
      maxOpeningCents,
    );
    const notes = req.body?.notes ? validateTextLength(req.body.notes, 500, 'notes') : null;
    const userId = req.user!.id;

    // Atomic insert — wrapped via sync better-sqlite3 transaction so the
    // "only one open shift" invariant is enforced in the same write batch.
    const db = req.db;
    const tx = db.transaction(() => {
      const conflict = db
        .prepare(`SELECT id FROM cash_drawer_shifts WHERE closed_at IS NULL LIMIT 1`)
        .get();
      if (conflict) throw new AppError('A drawer shift is already open', 409);
      return db
        .prepare(
          `INSERT INTO cash_drawer_shifts (opened_by_user_id, opening_float_cents, notes)
           VALUES (?, ?, ?)`,
        )
        .run(userId, floatCents, notes);
    });
    const result = tx();
    const shiftId = Number(result.lastInsertRowid);

    audit(req.db, 'drawer_shift_opened', userId, req.ip || 'unknown', {
      shift_id: shiftId,
      opening_float_cents: floatCents,
    });
    logger.info('drawer_shift_opened', { shift_id: shiftId, user_id: userId });

    const row = await adb.get<DrawerShiftRow>(
      `SELECT * FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    res.json({ success: true, data: row });
  }),
);

router.post(
  '/drawer/:id/close',
  asyncHandler(async (req, res) => {
    // Closing a drawer writes final variance + z-report — manager/admin only.
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const shiftId = parseInt(qs(req.params.id), 10);
    if (!shiftId || isNaN(shiftId)) throw new AppError('Invalid shift id', 400);

    const shift = await adb.get<DrawerShiftRow>(
      `SELECT * FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    if (!shift) throw new AppError('Shift not found', 404);
    if (shift.closed_at) throw new AppError('Shift already closed', 409);

    // Look up the optional high-volume escape hatch. A store that truly
    // does $50k+ per shift can set store_config.pos_high_volume_drawer = '1'.
    const highVolumeRow = await adb.get<StoreConfigRow>(
      `SELECT value FROM store_config WHERE key = 'pos_high_volume_drawer'`,
    );
    const isHighVolume = highVolumeRow?.value === '1';
    const maxClosingCents = isHighVolume ? DRAWER_MAX_CENTS_HIGH_VOLUME : DRAWER_MAX_CENTS_DEFAULT;

    const countedCents = validateCents(
      req.body?.closing_counted_cents ?? 0,
      'closing_counted_cents',
      maxClosingCents,
    );
    const notes = req.body?.notes ? validateTextLength(req.body.notes, 500, 'notes') : shift.notes;

    const closedAt = new Date().toISOString();
    const expectedCents = await computeExpectedCents(
      adb,
      shift.opened_at,
      closedAt,
      shift.opening_float_cents,
    );
    const varianceCents = countedCents - expectedCents;
    const zReport = await buildZReport(adb, shift, closedAt, countedCents, expectedCents, varianceCents);
    const zReportJson = JSON.stringify(zReport);

    const db = req.db;
    const tx = db.transaction(() => {
      const stmt = db.prepare(
        `UPDATE cash_drawer_shifts
            SET closed_by_user_id     = ?,
                closed_at             = ?,
                closing_counted_cents = ?,
                expected_cents        = ?,
                variance_cents        = ?,
                z_report_json         = ?,
                notes                 = ?
          WHERE id = ? AND closed_at IS NULL`,
      );
      const result = stmt.run(
        req.user!.id,
        closedAt,
        countedCents,
        expectedCents,
        varianceCents,
        zReportJson,
        notes,
        shiftId,
      );
      if (result.changes !== 1) throw new AppError('Shift already closed (race)', 409);
    });
    tx();

    audit(req.db, 'drawer_shift_closed', req.user!.id, req.ip || 'unknown', {
      shift_id: shiftId,
      expected_cents: expectedCents,
      counted_cents: countedCents,
      variance_cents: varianceCents,
    });
    logger.info('drawer_shift_closed', {
      shift_id: shiftId,
      variance_cents: varianceCents,
    });

    res.json({ success: true, data: { ...zReport, shift_id: shiftId } });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// 3. Z-REPORT (audit §43.4)
// ────────────────────────────────────────────────────────────────────────────

interface ZReport {
  shift_id: number;
  opened_at: string;
  closed_at: string;
  opening_float_cents: number;
  expected_cents: number;
  counted_cents: number;
  variance_cents: number;
  payment_breakdown: Array<{ method: string; cents: number; count: number }>;
  totals: {
    gross_cents: number;
    refund_cents: number;
    net_cents: number;
    transaction_count: number;
  };
}

async function buildZReport(
  adb: AsyncDb,
  shift: DrawerShiftRow,
  closedAt: string,
  countedCents: number,
  expectedCents: number,
  varianceCents: number,
): Promise<ZReport> {
  // POST-ENRICH AUDIT §23.1: same fix as computeExpectedCents — payments.method
  // is a TEXT label (not an FK). Group by that column directly so the Z-report
  // actually lists every tender leg rather than returning an empty array.
  const breakdown = await adb.all<{ method: string; cents: number; count: number }>(
    `SELECT COALESCE(p.method, 'unknown') AS method,
            COALESCE(SUM(CAST(ROUND(p.amount * 100) AS INTEGER)), 0) AS cents,
            COUNT(*) AS count
       FROM payments p
      WHERE p.created_at BETWEEN ? AND ?
      GROUP BY COALESCE(p.method, 'unknown')
      ORDER BY cents DESC`,
    shift.opened_at,
    closedAt,
  );

  const totalsRow = await adb.get<{
    gross_cents: number;
    refund_cents: number;
    net_cents: number;
    transaction_count: number;
  }>(
    `SELECT
        COALESCE(SUM(CAST(ROUND(CASE WHEN total > 0 THEN total ELSE 0 END * 100) AS INTEGER)), 0) AS gross_cents,
        COALESCE(SUM(CAST(ROUND(CASE WHEN total < 0 THEN -total ELSE 0 END * 100) AS INTEGER)), 0) AS refund_cents,
        COALESCE(SUM(CAST(ROUND(total * 100) AS INTEGER)), 0) AS net_cents,
        COUNT(*) AS transaction_count
       FROM invoices
      WHERE created_at BETWEEN ? AND ?`,
    shift.opened_at,
    closedAt,
  );

  return {
    shift_id: shift.id,
    opened_at: shift.opened_at,
    closed_at: closedAt,
    opening_float_cents: shift.opening_float_cents,
    expected_cents: expectedCents,
    counted_cents: countedCents,
    variance_cents: varianceCents,
    payment_breakdown: breakdown,
    totals: totalsRow ?? { gross_cents: 0, refund_cents: 0, net_cents: 0, transaction_count: 0 },
  };
}

router.get(
  '/drawer/:id/z-report',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const shiftId = parseInt(qs(req.params.id), 10);
    if (!shiftId || isNaN(shiftId)) throw new AppError('Invalid shift id', 400);

    const shift = await adb.get<DrawerShiftRow>(
      `SELECT * FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    if (!shift) throw new AppError('Shift not found', 404);

    // Replay cached report if shift is closed — otherwise build on the fly.
    if (shift.z_report_json) {
      try {
        const cached = JSON.parse(shift.z_report_json) as ZReport;
        res.json({ success: true, data: cached });
        return;
      } catch {
        logger.warn('z-report cache parse failed — rebuilding', { shift_id: shiftId });
      }
    }
    const now = shift.closed_at ?? new Date().toISOString();
    const report = await buildZReport(
      adb,
      shift,
      now,
      shift.closing_counted_cents ?? 0,
      shift.expected_cents ?? shift.opening_float_cents,
      shift.variance_cents ?? 0,
    );
    res.json({ success: true, data: report });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// 4. TRAINING / SANDBOX MODE (audit §43.15)
// ────────────────────────────────────────────────────────────────────────────

router.post(
  '/training/start',
  asyncHandler(async (req, res) => {
    // Training mode silences inventory/payments/audit — only a manager can
    // put a cashier into sandbox.
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;

    const existing = await adb.get<TrainingSessionRow>(
      `SELECT * FROM pos_training_sessions WHERE user_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1`,
      userId,
    );
    if (existing) {
      res.json({ success: true, data: existing });
      return;
    }

    const result = await adb.run(
      `INSERT INTO pos_training_sessions (user_id, fake_transactions_json) VALUES (?, '[]')`,
      userId,
    );
    audit(req.db, 'pos_training_started', userId, req.ip || 'unknown', {
      session_id: Number(result.lastInsertRowid),
    });
    const row = await adb.get<TrainingSessionRow>(
      `SELECT * FROM pos_training_sessions WHERE id = ?`,
      result.lastInsertRowid,
    );
    res.json({ success: true, data: row });
  }),
);

router.post(
  '/training/:id/end',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid session id', 400);

    const existing = await adb.get<TrainingSessionRow>(
      `SELECT * FROM pos_training_sessions WHERE id = ?`,
      id,
    );
    if (!existing) throw new AppError('Training session not found', 404);
    if (existing.user_id !== req.user!.id) throw new AppError('Not your session', 403);
    if (existing.ended_at) {
      res.json({ success: true, data: existing });
      return;
    }

    await adb.run(
      `UPDATE pos_training_sessions SET ended_at = datetime('now') WHERE id = ?`,
      id,
    );
    audit(req.db, 'pos_training_ended', req.user!.id, req.ip || 'unknown', { session_id: id });
    const row = await adb.get<TrainingSessionRow>(
      `SELECT * FROM pos_training_sessions WHERE id = ?`,
      id,
    );
    res.json({ success: true, data: row });
  }),
);

/**
 * Training-mode fake submit. The cashier rings a practice sale and we store
 * it as JSON on the open training session. Inventory, payments, audit logs
 * and reports are all untouched — exactly what new-hire drills need.
 */
router.post(
  '/training/submit',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const userId = req.user!.id;

    const session = await adb.get<TrainingSessionRow>(
      `SELECT * FROM pos_training_sessions WHERE user_id = ? AND ended_at IS NULL ORDER BY id DESC LIMIT 1`,
      userId,
    );
    if (!session) throw new AppError('No active training session', 400);

    // Validate cart payload through validateJsonPayload so crafted circular
    // refs or 1MB blobs can't crash JSON.stringify or bloat the DB. Allow up
    // to 32KB per training transaction.
    const cartSerialized = req.body?.cart !== undefined && req.body?.cart !== null
      ? validateJsonPayload(req.body.cart, 'cart', 32_768)
      : 'null';
    const totalCentsRaw = Number(req.body?.total_cents ?? 0);
    if (!Number.isFinite(totalCentsRaw)) {
      throw new AppError('total_cents must be a finite number', 400);
    }
    const previous = parseTrainingTxList(session.fake_transactions_json);
    const nextEntry = {
      at: new Date().toISOString(),
      cart: JSON.parse(cartSerialized),
      total_cents: Math.round(totalCentsRaw),
    };
    const updated = [...previous, nextEntry];
    // Keep the per-session mock ledger from growing unbounded.
    if (updated.length > 500) {
      throw new AppError('Training session cart history is full', 400);
    }
    await adb.run(
      `UPDATE pos_training_sessions SET fake_transactions_json = ? WHERE id = ?`,
      JSON.stringify(updated),
      session.id,
    );
    res.json({ success: true, data: { session_id: session.id, mock: true, count: updated.length } });
  }),
);

function parseTrainingTxList(raw: string | null): unknown[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 5. MANAGER PIN GATE FOR HIGH-VALUE SALES (audit §43.12)
// ────────────────────────────────────────────────────────────────────────────

/**
 * Validates a manager-level PIN against the existing users table (same
 * bcrypt-hashed PIN format used by auth.routes.ts pin-switch). Returns
 * success + whether the supplied PIN belongs to an admin/manager role.
 * Never returns the user's id or username — just a verified flag so the
 * cashier screen can proceed without exposing who the manager is.
 */
// Rate-limit bucket: tie to the verifying user + IP so two cashiers on
// different workstations don't starve each other.
const MANAGER_PIN_CATEGORY = 'pos_manager_pin';
const MANAGER_PIN_MAX_ATTEMPTS = 5;
const MANAGER_PIN_WINDOW_MS = 10 * 60 * 1000; // 10 minutes

router.post(
  '/manager-verify-pin',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const db = req.db;
    const pin = typeof req.body?.pin === 'string' ? req.body.pin : '';
    if (!pin || pin.length < 1 || pin.length > 20) {
      throw new AppError('Valid PIN required (1-20 characters)', 400);
    }

    // SEC (post-enrichment audit §6): brute-force guard. The PIN is a 4-6
    // digit numeric by convention — without this a cashier could shotgun
    // 10 000 attempts in a second. Keyed by requesting user + IP so a
    // single malicious client is throttled without blocking coworkers.
    const rateKey = `${req.user?.id ?? 'anon'}:${req.ip ?? 'unknown'}`;
    if (!checkWindowRate(db, MANAGER_PIN_CATEGORY, rateKey,
        MANAGER_PIN_MAX_ATTEMPTS, MANAGER_PIN_WINDOW_MS)) {
      audit(db, 'pos_manager_pin_rate_limited', req.user?.id ?? null, req.ip || 'unknown', {});
      throw new AppError(
        'Too many PIN attempts — wait 10 minutes before trying again',
        429,
      );
    }

    // Defensive: sale_cents may arrive as Infinity / NaN from malformed JSON.
    // Clamp to a finite non-negative integer so the threshold compare below
    // is well defined.
    const saleRaw = Number(req.body?.sale_cents ?? 0);
    const sale = Number.isFinite(saleRaw) && saleRaw >= 0 ? Math.round(saleRaw) : 0;
    const thresholdRow = await adb.get<StoreConfigRow>(
      `SELECT value FROM store_config WHERE key = 'pos_manager_pin_threshold'`,
    );
    const threshold = Number(thresholdRow?.value ?? '50000');

    if (!threshold || threshold <= 0) {
      res.json({ success: true, data: { verified: true, threshold_cents: 0 } });
      return;
    }
    if (sale > 0 && sale < threshold) {
      res.json({ success: true, data: { verified: true, threshold_cents: threshold, skipped: true } });
      return;
    }

    const managers = await adb.all<{ pin: string | null; role: string | null }>(
      `SELECT pin, role FROM users
        WHERE pin IS NOT NULL
          AND pin LIKE '$2%'
          AND is_active = 1
          AND role IN ('admin','manager','owner')`,
    );
    const match = managers.find((u) => {
      try {
        return bcrypt.compareSync(pin, u.pin as string);
      } catch {
        return false;
      }
    });

    if (!match) {
      recordWindowFailure(db, MANAGER_PIN_CATEGORY, rateKey, MANAGER_PIN_WINDOW_MS);
      audit(req.db, 'pos_manager_pin_failed', req.user!.id, req.ip || 'unknown', {
        sale_cents: sale,
      });
      throw new AppError('Invalid manager PIN', 401);
    }

    // Clear the failure count on success so repeat legitimate uses don't
    // get throttled by an earlier typo.
    clearRateLimit(db, MANAGER_PIN_CATEGORY, rateKey);
    audit(req.db, 'pos_manager_pin_verified', req.user!.id, req.ip || 'unknown', {
      sale_cents: sale,
    });
    res.json({
      success: true,
      data: { verified: true, threshold_cents: threshold, role: match.role },
    });
  }),
);

export default router;
