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

// Admin-only gate for high-stakes reversal operations like reverse-close
// (WEB-UIUX-1161 / 1171). Manager scope intentionally not granted — the
// reopen path nukes a frozen z_report + variance audit row and we want a
// per-shop attestable trail that the elevation happened.
function requireAdminStrict(req: any): void {
  if (req?.user?.role !== 'admin') {
    throw new AppError('Admin role required', 403);
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
  // WEB-UIUX-679: Z-report print audit (migration 186).
  printed_at: string | null;
  printed_by_user_id: number | null;
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

/**
 * GET /pos-enrich/quick-add — Android cart Catalog tab tiles.
 *
 * Returns the same Today's Top-5 list as /top-five when the shop has any
 * sales today. When the rollup is empty (fresh shop, brand-new day, training
 * mode) we fall back to the first 10 active inventory items by name so the
 * Android Catalog tab always renders SOMETHING tappable instead of a blank
 * grid. Response shape matches PosApi.QuickAddItem on Android: each item is
 * { id, name, sku, price_cents, type }.
 */
router.get(
  '/quick-add',
  asyncHandler(async (req, res) => {
    const top = await queryTopFiveProductsToday(req.asyncDb);
    let rows: Array<{ id: number; name: string; sku: string | null; retail_price: number; item_type: string }>;
    if (top.length > 0) {
      rows = top.map(t => ({
        id: t.inventory_item_id,
        name: t.name,
        sku: t.sku,
        retail_price: t.retail_price ?? 0,
        item_type: 'product',
      }));
    } else {
      rows = await req.asyncDb.all<{ id: number; name: string; sku: string | null; retail_price: number; item_type: string }>(
        `SELECT id, name, sku, retail_price, item_type
           FROM inventory_items
          WHERE is_active = 1 AND in_stock > 0
          ORDER BY name ASC LIMIT 10`,
      );
    }
    const items = rows.map(r => ({
      id: r.id,
      name: r.name,
      sku: r.sku,
      price_cents: Math.round((Number(r.retail_price) || 0) * 100),
      type: r.item_type === 'service' ? 'service' : 'inventory',
    }));
    res.json({ success: true, data: { items } });
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
  // WEB-UIUX-1159: also fold in `cash_register` rows from the legacy
  // CashRegisterPage path so paid-in (cash_in) bumps the expected drawer
  // and paid-out (cash_out, vendor refund / petty cash) reduces it. Prior
  // computation summed `payments` only, so a shift with $50 cash-in + $0
  // sales correctly counted as $250 in drawer would have shown a $50 OVER
  // variance after every shift — phantom investigation for an in-balance
  // till. Single query so we still keep the original `payments` scan +
  // the new `cash_register` scan in parallel-friendly shape.
  const registerRow = await adb.get<{ paid_in: number; paid_out: number }>(
    `SELECT COALESCE(SUM(CASE WHEN type = 'cash_in'  THEN CAST(ROUND(COALESCE(amount,0) * 100) AS INTEGER) ELSE 0 END), 0) AS paid_in,
            COALESCE(SUM(CASE WHEN type = 'cash_out' THEN CAST(ROUND(COALESCE(amount,0) * 100) AS INTEGER) ELSE 0 END), 0) AS paid_out
       FROM cash_register
      WHERE created_at BETWEEN ? AND ?`,
    openedAt,
    closedAt,
  );
  const adjustments = (registerRow?.paid_in ?? 0) - (registerRow?.paid_out ?? 0);
  return openingFloatCents + cashIn + adjustments;
}

async function getCurrentShift(adb: AsyncDb): Promise<DrawerShiftRow | undefined> {
  return adb.get<DrawerShiftRow>(
    `SELECT * FROM cash_drawer_shifts WHERE closed_at IS NULL ORDER BY id DESC LIMIT 1`,
  );
}

router.get(
  '/drawer/current',
  asyncHandler(async (req, res) => {
    // WEB-UIUX-1172: opening_float_cents + opener id are shop-confidential
    // (burglary risk). Allow admin/manager unconditionally; allow a cashier
    // ONLY if they are the opener of the currently open shift. Other
    // authenticated users (techs, support) get null + a 200 so the POS UI
    // still renders without leaking the float amount.
    const shift = await getCurrentShift(req.asyncDb);
    const role = (req as any)?.user?.role;
    const userId = (req as any)?.user?.id;
    const isPrivileged = role === 'admin' || role === 'manager';
    const isOnShift = !!shift && shift.opened_by_user_id === userId;
    if (!shift || isPrivileged || isOnShift) {
      res.json({ success: true, data: shift ?? null });
      return;
    }
    res.json({ success: true, data: null });
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
    // Closing a drawer writes final variance + z-report. WEB-UIUX-1165:
    // allow the shift opener to close their own shift even when not a
    // manager — they own the till for the duration, and the end-of-shift
    // close is the natural pair to /open which has no role gate. Closing
    // someone else's shift still requires manager/admin (preserves the
    // dual-control intent for cross-cashier reconciliation).
    const adb: AsyncDb = req.asyncDb;
    const shiftId = parseInt(qs(req.params.id), 10);
    if (!shiftId || isNaN(shiftId)) throw new AppError('Invalid shift id', 400);

    const shift = await adb.get<DrawerShiftRow>(
      `SELECT * FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    if (!shift) throw new AppError('Shift not found', 404);
    if (shift.closed_at) throw new AppError('Shift already closed', 409);
    const role = (req as any)?.user?.role;
    const isSelfClose = shift.opened_by_user_id === (req as any)?.user?.id;
    if (!isSelfClose && role !== 'admin' && role !== 'manager') {
      throw new AppError(
        'Only the cashier who opened this shift, a manager, or an admin can close it.',
        403,
      );
    }

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

/**
 * WEB-UIUX-1161 / 1171: admin reverse-close. Operator close-with-typo
 * (`2200` instead of `220.00`) was permanent — variance lived in the audit
 * trail forever and the next shift inherited a fictitious starting position
 * if the prior over/undercounted. Endpoint NULLs the close fields so the
 * shift returns to "open" state, with a fresh audit row capturing reason +
 * the values that were cleared. Refuses to reopen when another shift is
 * already open (preserves the "only one open shift" invariant) or when the
 * shift is older than 7 days (a generous correction window without making
 * audit timestamps mutable forever).
 */
router.post(
  '/drawer/:id/reopen',
  asyncHandler(async (req, res) => {
    requireAdminStrict(req);
    const adb: AsyncDb = req.asyncDb;
    const shiftId = parseInt(qs(req.params.id), 10);
    if (!shiftId || isNaN(shiftId)) throw new AppError('Invalid shift id', 400);

    const reason = req.body?.reason ? validateTextLength(req.body.reason, 500, 'reason') : null;
    if (!reason || !reason.trim()) {
      throw new AppError('reason required for reopen (audit trail)', 400);
    }

    const shift = await adb.get<DrawerShiftRow>(
      `SELECT * FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    if (!shift) throw new AppError('Shift not found', 404);
    if (!shift.closed_at) throw new AppError('Shift is already open', 409);

    // 7-day correction window keeps the reopen path bounded; older rows
    // require an explicit audit-tooling intervention rather than silent
    // mutation of week-old close timestamps.
    const closedMs = Date.parse(shift.closed_at);
    if (Number.isFinite(closedMs) && Date.now() - closedMs > 7 * 24 * 60 * 60 * 1000) {
      throw new AppError('Shift was closed more than 7 days ago — reopen window expired', 409);
    }

    const conflict = await adb.get<{ id: number }>(
      `SELECT id FROM cash_drawer_shifts WHERE closed_at IS NULL AND id <> ? LIMIT 1`,
      shiftId,
    );
    if (conflict) {
      throw new AppError(
        `Another shift (#${conflict.id}) is currently open — close it before reopening shift #${shiftId}.`,
        409,
      );
    }

    // Snapshot the values we're about to nuke so the audit row has the
    // full pre-reopen state.
    const snapshot = {
      closed_at: shift.closed_at,
      closing_counted_cents: shift.closing_counted_cents,
      expected_cents: shift.expected_cents,
      variance_cents: shift.variance_cents,
      closed_by_user_id: shift.closed_by_user_id,
    };

    const db = req.db;
    const tx = db.transaction(() => {
      const result = db
        .prepare(
          `UPDATE cash_drawer_shifts
              SET closed_at             = NULL,
                  closing_counted_cents = NULL,
                  expected_cents        = NULL,
                  variance_cents        = NULL,
                  z_report_json         = NULL,
                  closed_by_user_id     = NULL
            WHERE id = ? AND closed_at IS NOT NULL`,
        )
        .run(shiftId);
      if (result.changes !== 1) {
        throw new AppError('Shift state changed during reopen (race)', 409);
      }
    });
    tx();

    audit(req.db, 'drawer_shift_reopened', req.user!.id, req.ip || 'unknown', {
      shift_id: shiftId,
      reason: reason.trim(),
      cleared: snapshot,
    });
    logger.info('drawer_shift_reopened', {
      shift_id: shiftId,
      user_id: req.user!.id,
      variance_cents_cleared: snapshot.variance_cents,
    });

    const row = await adb.get<DrawerShiftRow>(
      `SELECT * FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    res.json({ success: true, data: row });
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
  // WEB-UIUX-1162: counted_cents/variance_cents are null while the shift is
  // open (no till count exists yet); the client renders "in progress" instead
  // of a phantom variance.
  counted_cents: number | null;
  variance_cents: number | null;
  // WEB-UIUX-1170: include opener / closer name + shift duration + notes so
  // the printed Z-report carries the audit context many jurisdictions require
  // on EOD reports. Names are resolved by joining users on opened_by /
  // closed_by user ids; absent rows fall back to null.
  opened_by_name: string | null;
  closed_by_name: string | null;
  duration_minutes: number | null;
  notes: string | null;
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
  countedCents: number | null,
  expectedCents: number,
  varianceCents: number | null,
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

  // WEB-UIUX-1170: resolve opener + closer names + compute shift duration so
  // the Z-report can stamp who-opened / who-closed / minutes-on-shift.
  const openedBy = shift.opened_by_user_id
    ? await adb.get<{ first_name: string | null; last_name: string | null }>(
        'SELECT first_name, last_name FROM users WHERE id = ?',
        shift.opened_by_user_id,
      )
    : null;
  const closedBy = shift.closed_by_user_id
    ? await adb.get<{ first_name: string | null; last_name: string | null }>(
        'SELECT first_name, last_name FROM users WHERE id = ?',
        shift.closed_by_user_id,
      )
    : null;
  const fmtName = (u: { first_name: string | null; last_name: string | null } | null | undefined) => {
    if (!u) return null;
    const n = `${u.first_name ?? ''} ${u.last_name ?? ''}`.trim();
    return n || null;
  };
  let durationMinutes: number | null = null;
  if (shift.opened_at) {
    const endMs = new Date(closedAt).getTime();
    const startMs = new Date(shift.opened_at).getTime();
    if (Number.isFinite(endMs) && Number.isFinite(startMs) && endMs >= startMs) {
      durationMinutes = Math.round((endMs - startMs) / 60_000);
    }
  }

  return {
    shift_id: shift.id,
    opened_at: shift.opened_at,
    closed_at: closedAt,
    opening_float_cents: shift.opening_float_cents,
    expected_cents: expectedCents,
    counted_cents: countedCents,
    variance_cents: varianceCents,
    opened_by_name: fmtName(openedBy),
    closed_by_name: fmtName(closedBy),
    duration_minutes: durationMinutes,
    notes: shift.notes ?? null,
    payment_breakdown: breakdown,
    totals: totalsRow ?? { gross_cents: 0, refund_cents: 0, net_cents: 0, transaction_count: 0 },
  };
}

// WEB-UIUX-1168: paginated list of closed shifts so operators can reprint a
// Z-report after the modal was dismissed and the paper was lost. Admin /
// manager only — opening_float + variance are shop-confidential.
router.get(
  '/drawer/history',
  asyncHandler(async (req, res) => {
    const role = (req as any)?.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager required', 403);
    }
    const adb: AsyncDb = req.asyncDb;
    const page = Math.max(1, parseInt(qs(req.query.page as string) || '1', 10) || 1);
    const perPageRaw = parseInt(qs(req.query.per_page as string) || '25', 10) || 25;
    const perPage = Math.max(1, Math.min(100, perPageRaw));
    const offset = (page - 1) * perPage;
    const totalRow = await adb.get<{ c: number }>(
      `SELECT COUNT(*) AS c FROM cash_drawer_shifts WHERE closed_at IS NOT NULL`,
    );
    const total = totalRow?.c ?? 0;
    const rows = await adb.all<any>(
      `SELECT s.id, s.opened_at, s.closed_at, s.opening_float_cents,
              s.closing_counted_cents, s.expected_cents, s.variance_cents,
              s.opened_by_user_id, s.closed_by_user_id,
              ou.first_name || ' ' || ou.last_name AS opened_by_name,
              cu.first_name || ' ' || cu.last_name AS closed_by_name
         FROM cash_drawer_shifts s
    LEFT JOIN users ou ON ou.id = s.opened_by_user_id
    LEFT JOIN users cu ON cu.id = s.closed_by_user_id
        WHERE s.closed_at IS NOT NULL
     ORDER BY s.closed_at DESC
        LIMIT ? OFFSET ?`,
      perPage, offset,
    );
    res.json({
      success: true,
      data: rows,
      pagination: { page, per_page: perPage, total, total_pages: Math.max(1, Math.ceil(total / perPage)) },
    });
  }),
);

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
    // WEB-UIUX-1162: when the shift is still open, an admin previewing the
    // Z-report should see "in progress" not a phantom $X-short variance
    // generated from `counted_cents=0`. Build the report without a counted
    // value and tag it `in_progress=true` so the client can render an
    // "awaiting close" placeholder instead of the red variance banner.
    const isInProgress = !shift.closed_at;
    const report = await buildZReport(
      adb,
      shift,
      now,
      isInProgress ? null : (shift.closing_counted_cents ?? 0),
      shift.expected_cents ?? shift.opening_float_cents,
      isInProgress ? null : (shift.variance_cents ?? 0),
    );
    res.json({
      success: true,
      data: {
        ...report,
        in_progress: isInProgress,
        // WEB-UIUX-679: surface print audit on the z-report response so
        // ShiftHistoryPage can render "Last printed 2026-05-12 by Alice"
        // alongside the existing reprint button.
        printed_at: shift.printed_at ?? null,
        printed_by_user_id: shift.printed_by_user_id ?? null,
      },
    });
  }),
);

// WEB-UIUX-679: POST /drawer/:id/mark-printed — stamp printed_at on the
// shift so the audit trail records every paper or PDF copy. Idempotent in
// the sense that re-printing simply overwrites the timestamp (operators
// commonly reprint after a paper jam). Admin/manager only; cashier who
// closed the shift can also re-print their own.
router.post(
  '/drawer/:id/mark-printed',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const shiftId = parseInt(qs(req.params.id), 10);
    if (!shiftId || isNaN(shiftId)) throw new AppError('Invalid shift id', 400);
    const shift = await adb.get<DrawerShiftRow>(
      `SELECT id, closed_by_user_id, closed_at FROM cash_drawer_shifts WHERE id = ?`,
      shiftId,
    );
    if (!shift) throw new AppError('Shift not found', 404);
    if (!shift.closed_at) throw new AppError('Shift is still open', 409);
    const role = (req as any)?.user?.role;
    const callerId = (req as any)?.user?.id;
    const isSelfClose = shift.closed_by_user_id === callerId;
    if (role !== 'admin' && role !== 'manager' && !isSelfClose) {
      throw new AppError(
        'Only the cashier who closed this shift, a manager, or an admin can mark a Z-report as printed.',
        403,
      );
    }
    const nowIso = new Date().toISOString();
    await adb.run(
      `UPDATE cash_drawer_shifts SET printed_at = ?, printed_by_user_id = ? WHERE id = ?`,
      nowIso, callerId, shiftId,
    );
    res.json({ success: true, data: { printed_at: nowIso, printed_by_user_id: callerId } });
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
    const kind = req.body?.kind === 'create_ticket' ? 'create_ticket' : 'checkout';
    const previous = parseTrainingTxList(session.fake_transactions_json);
    let cartParsed: unknown;
    try {
      cartParsed = JSON.parse(cartSerialized);
    } catch (parseErr) {
      logger.error('cart_parse_failed', { err: parseErr instanceof Error ? parseErr.message : String(parseErr) });
      throw new AppError('Corrupt cart session data', 500);
    }
    const nextEntry = {
      at: new Date().toISOString(),
      kind,
      cart: cartParsed,
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
    await adb.run(`
      UPDATE onboarding_state
      SET sandbox_completed_at = COALESCE(sandbox_completed_at, datetime('now')),
          updated_at = datetime('now')
      WHERE id = 1
    `);
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
