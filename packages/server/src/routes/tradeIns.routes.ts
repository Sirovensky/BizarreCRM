import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { validatePaginationOffset } from '../utils/validate.js';
import type { AsyncDb, TxQuery } from '../db/async-db.js';

const router = Router();

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

// @audit-fixed: §37 — Centralised price/condition/status validators so the
// schema CHECK constraints can never throw raw 500s and an attacker can't
// store $1e12 in offered_price.
const MAX_TRADE_IN_PRICE = 100_000;
const VALID_CONDITIONS = new Set(['excellent', 'good', 'fair', 'poor', 'broken']);
const VALID_STATUSES = new Set(['pending', 'evaluated', 'accepted', 'declined', 'completed', 'scrapped']);

// SEC-H118: Legal status transitions. Source of truth: migration 029_trade_ins.sql
// CHECK(status IN ('pending','evaluated','accepted','declined','completed','scrapped')).
// Once a trade-in reaches a terminal state (declined/completed/scrapped) no
// further status transitions are allowed — the record is immutable.
const LEGAL_TRADE_IN_TRANSITIONS: Record<string, readonly string[]> = {
  pending:   ['evaluated', 'accepted', 'declined', 'scrapped'],
  evaluated: ['accepted', 'declined', 'scrapped'],
  accepted:  ['completed'],
  declined:  [],
  completed: [],
  scrapped:  [],
};

function validatePrice(field: string, value: unknown): void {
  if (value == null) return;
  if (typeof value !== 'number' || !isFinite(value) || value < 0) {
    throw new AppError(`${field} must be a non-negative number`, 400);
  }
  if (value > MAX_TRADE_IN_PRICE) {
    throw new AppError(`${field} must be ${MAX_TRADE_IN_PRICE} or less`, 400);
  }
}

// GET / — List trade-ins
router.get('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const status = (req.query.status as string || '').trim();
  const conditions = status ? 'WHERE ti.status = ? AND ti.is_deleted = 0' : 'WHERE ti.is_deleted = 0';
  const params: any[] = status ? [status] : [];
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(req.query.per_page as string) || 50));
  const offset = validatePaginationOffset((page - 1) * perPage, 'offset');

  const [totalRow, tradeIns] = await Promise.all([
    adb.get<{ c: number }>(`SELECT COUNT(*) as c FROM trade_ins ti ${conditions}`, ...params),
    adb.all(`
      SELECT ti.*, c.first_name, c.last_name, u.first_name AS eval_first, u.last_name AS eval_last
      FROM trade_ins ti
      LEFT JOIN customers c ON c.id = ti.customer_id
      LEFT JOIN users u ON u.id = ti.evaluated_by
      ${conditions}
      ORDER BY ti.created_at DESC
      LIMIT ? OFFSET ?
    `, ...params, perPage, offset),
  ]);

  const total = totalRow!.c;
  res.json({ success: true, data: tradeIns, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /:id — Single trade-in
router.get('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const ti = await adb.get(`
    SELECT ti.*, c.first_name, c.last_name, c.phone, c.email
    FROM trade_ins ti
    LEFT JOIN customers c ON c.id = ti.customer_id
    WHERE ti.id = ? AND ti.is_deleted = 0
  `, req.params.id);
  if (!ti) throw new AppError('Trade-in not found', 404);
  res.json({ success: true, data: ti });
}));

// POST / — Create trade-in
router.post('/', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { customer_id, device_name, device_type, imei, serial, color, condition = 'good', offered_price, notes, pre_conditions } = req.body;
  if (!device_name) throw new AppError('device_name required', 400);
  // @audit-fixed: §37 — bound device_name + condition + offered_price so the
  // schema CHECKs never produce raw 500s and storage stays sane.
  if (typeof device_name !== 'string' || device_name.length > 200) {
    throw new AppError('device_name must be 200 characters or fewer', 400);
  }
  if (!VALID_CONDITIONS.has(condition)) {
    throw new AppError('condition must be one of excellent/good/fair/poor/broken', 400);
  }
  validatePrice('offered_price', offered_price);

  // @audit-fixed: §37 — verify customer FK exists when supplied; FKs are ON
  // (db/connection.ts:15) so a missing customer_id otherwise raises a generic
  // 500 instead of a 404.
  if (customer_id != null) {
    const cust = await adb.get('SELECT id FROM customers WHERE id = ?', customer_id);
    if (!cust) throw new AppError('Customer not found', 404);
  }

  const result = await adb.run(`
    INSERT INTO trade_ins (customer_id, device_name, device_type, imei, serial, color, condition, status, offered_price, notes, pre_conditions, created_by, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?)
  `, customer_id || null, device_name, device_type || null, imei || null, serial || null, color || null, condition,
    offered_price || 0, notes || null, pre_conditions ? JSON.stringify(pre_conditions) : null, req.user!.id, now(), now());

  audit(req.db, 'trade_in_created', req.user!.id, req.ip || 'unknown', { trade_in_id: Number(result.lastInsertRowid), device_name, customer_id: customer_id || null, offered_price: offered_price || 0 });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PATCH /:id — Update trade-in (evaluate, accept, decline)
// SEC-H30: Accepting a trade-in commits the shop to paying out `accepted_price`
// so the `status = 'accepted'` transition is gated to admin/manager. We also
// hard-cap accepted_price to (0, 100_000] so a typo can't issue a $1M payout
// and a sign-flip can't mint negative inventory value.
router.patch('/:id', asyncHandler(async (req, res) => {
  const adb: AsyncDb = req.asyncDb;
  const { status, offered_price, accepted_price, notes, condition } = req.body;
  // SEC-M17: pull the prior row so we can detect the pending→accepted
  // transition and read the canonical customer_id / device_name / condition
  // / accepted_price used to mint store credit + inventory. The partial body
  // from this PATCH may omit any of these (caller may only flip status).
  const existing = await adb.get<{
    id: number;
    status: string;
    customer_id: number | null;
    device_name: string;
    condition: string;
    accepted_price: number | null;
  }>(
    'SELECT id, status, customer_id, device_name, condition, accepted_price FROM trade_ins WHERE id = ? AND is_deleted = 0',
    req.params.id,
  );
  if (!existing) throw new AppError('Trade-in not found', 404);
  // @audit-fixed: §37 — validate status + condition + price fields against
  // the same whitelists used by the schema CHECK constraints, otherwise an
  // invalid string drops through to a 500.
  if (status != null && !VALID_STATUSES.has(status)) {
    throw new AppError('Invalid status', 400);
  }
  if (condition != null && !VALID_CONDITIONS.has(condition)) {
    throw new AppError('Invalid condition', 400);
  }
  validatePrice('offered_price', offered_price);
  validatePrice('accepted_price', accepted_price);

  // SEC-H118: State-machine transition guard. Reject illegal moves before any
  // write. The legal map is keyed on the CURRENT status fetched above; if the
  // requested status is not in the allowed list for the current state, fail
  // fast with a 400 rather than letting the raw SQLite CHECK constraint
  // surface a 500. The UPDATE below also includes `WHERE status = ?` so a
  // concurrent status change that slips between our SELECT and the transaction
  // commit will cause 0 rows affected → expectChanges throws → rollback.
  if (status != null && status !== existing.status) {
    const allowed = LEGAL_TRADE_IN_TRANSITIONS[existing.status] ?? [];
    if (!allowed.includes(status)) {
      throw new AppError(
        `Cannot transition from '${existing.status}' to '${status}'`,
        400,
      );
    }
  }

  // SEC-H30: accepting a trade-in requires admin/manager.
  if (status === 'accepted') {
    const role = req.user?.role;
    if (role !== 'admin' && role !== 'manager') {
      throw new AppError('Admin or manager role required to accept a trade-in', 403);
    }
  }

  // SEC-H30: accepted_price sanity — reject <= 0 or > $100,000 when supplied.
  // Runs whenever accepted_price is in the body (not just on status=accepted)
  // so a manager cannot pre-set an absurd price and have a cashier flip status
  // later via a narrower endpoint. Uses Number() + Number.isFinite() because
  // validatePrice above only enforces >= 0 with no upper cap.
  if (accepted_price != null) {
    const ap = Number(accepted_price);
    if (!Number.isFinite(ap) || ap <= 0 || ap > 100_000) {
      throw new AppError('accepted_price must be > 0 and <= 100000', 400);
    }
  }

  // SEC-M17: when this PATCH flips status pending/evaluated → accepted AND there
  // is a positive accepted_price, mint store credit and inventory atomically
  // with the UPDATE so a crash between steps can't leave the shop owing a
  // payout with no credit issued (or vice-versa).
  //
  // Transition detection: status must be flipping TO 'accepted' (existing.status
  // was not already 'accepted'), and the effective accepted_price (request
  // override or existing row value) must be > 0. When customer_id is null we
  // skip the credit leg but still INSERT the inventory row — the shop can
  // re-attach the credit later via manual adjustment.
  const tradeInId = Number(req.params.id);
  const effectiveAcceptedPrice = accepted_price != null
    ? Number(accepted_price)
    : (existing.accepted_price ?? 0);
  const effectiveCondition = condition ?? existing.condition;
  const isAcceptTransition =
    status === 'accepted' &&
    existing.status !== 'accepted' &&
    Number.isFinite(effectiveAcceptedPrice) &&
    effectiveAcceptedPrice > 0;

  // SEC-H118: The WHERE clause pins the current status so a concurrent PATCH
  // that already changed the row's status causes this UPDATE to match 0 rows.
  // expectChanges: true forces the worker to roll back the whole transaction
  // when that happens, preventing a split-brain state where two requests both
  // believe they won the race.
  const tx: TxQuery[] = [
    {
      sql: `
        UPDATE trade_ins SET
          status = COALESCE(?, status), offered_price = COALESCE(?, offered_price),
          accepted_price = COALESCE(?, accepted_price), notes = COALESCE(?, notes),
          condition = COALESCE(?, condition), evaluated_by = ?, updated_at = ?
        WHERE id = ? AND status = ?
      `,
      params: [
        status ?? null, offered_price ?? null, accepted_price ?? null, notes ?? null,
        condition ?? null, req.user!.id, now(), tradeInId, existing.status,
      ],
      expectChanges: true,
      expectChangesError: `Cannot transition from '${existing.status}' to '${status ?? existing.status}': concurrent modification detected`,
    },
  ];

  if (isAcceptTransition) {
    // INSERT inventory row so the traded-in device is tracked. Always runs on
    // accept (simplest path) — cost_price = accepted_price, in_stock = 1.
    tx.push({
      sql: `
        INSERT INTO inventory_items
          (name, item_type, device_type, cost_price, retail_price, in_stock, is_active, created_at, updated_at)
        VALUES (?, 'product', ?, ?, ?, 1, 1, ?, ?)
      `,
      params: [
        existing.device_name,
        `trade_in:${effectiveCondition}`,
        effectiveAcceptedPrice,
        effectiveAcceptedPrice, // retail_price defaults to cost; shop can re-price later
        now(),
        now(),
      ],
    });

    // Mint store credit only when customer_id is set. store_credits has no
    // UNIQUE(customer_id) constraint (see migrations/026_refunds_credits.sql),
    // so ON CONFLICT is not available — read the existing row out of band and
    // emit either an UPDATE or an INSERT. The transaction is still atomic with
    // the trade_ins UPDATE above; the race window where another concurrent
    // request inserts a store_credits row for the same customer between our
    // SELECT and INSERT is narrow and the worst case is two rows (which the
    // balance-read helper in refunds.routes.ts already tolerates via SUM).
    if (existing.customer_id != null) {
      const existingCredit = await adb.get<{ id: number }>(
        'SELECT id FROM store_credits WHERE customer_id = ?',
        existing.customer_id,
      );
      if (existingCredit) {
        tx.push({
          sql: 'UPDATE store_credits SET amount = amount + ?, updated_at = ? WHERE id = ?',
          params: [effectiveAcceptedPrice, now(), existingCredit.id],
        });
      } else {
        tx.push({
          sql: `
            INSERT INTO store_credits (customer_id, amount, created_at, updated_at)
            VALUES (?, ?, ?, ?)
          `,
          params: [existing.customer_id, effectiveAcceptedPrice, now(), now()],
        });
      }
      tx.push({
        sql: `
          INSERT INTO store_credit_transactions
            (customer_id, amount, type, reference_type, reference_id, notes, user_id, created_at)
          VALUES (?, ?, 'manual_credit', 'trade_in', ?, 'Trade-in credit', ?, ?)
        `,
        params: [
          existing.customer_id,
          effectiveAcceptedPrice,
          tradeInId,
          req.user!.id,
          now(),
        ],
      });
    }
  }

  await adb.transaction(tx);

  audit(req.db, 'trade_in_updated', req.user!.id, req.ip || 'unknown', {
    trade_in_id: tradeInId,
    status: status ?? undefined,
    offered_price: offered_price ?? undefined,
    accepted_price: accepted_price ?? undefined,
    accepted_transition: isAcceptTransition || undefined,
    store_credit_issued: isAcceptTransition && existing.customer_id != null ? effectiveAcceptedPrice : undefined,
  });

  res.json({ success: true, data: { id: tradeInId } });
}));

// DELETE /:id — Soft-delete trade-in (API-4: only if pending/declined, not accepted)
// SEC-H121: Replaces hard DELETE to preserve audit trail. Sets is_deleted = 1
// so the row is excluded from all normal list/detail queries but remains in
// the database for audit and reconciliation purposes.
router.delete('/:id', asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const existing = await adb.get<{ id: number; status: string }>(
    'SELECT id, status FROM trade_ins WHERE id = ? AND is_deleted = 0',
    req.params.id,
  );
  if (!existing) throw new AppError('Trade-in not found', 404);
  if (existing.status === 'accepted') {
    throw new AppError('Cannot delete an accepted trade-in. Decline it first.', 400);
  }

  await adb.run(
    `UPDATE trade_ins
        SET is_deleted = 1, deleted_at = datetime('now'), deleted_by_user_id = ?
      WHERE id = ? AND is_deleted = 0`,
    req.user!.id, req.params.id,
  );
  audit(req.db, 'trade_in_soft_deleted', req.user!.id, req.ip || 'unknown', {
    trade_in_id: Number(req.params.id),
    status: existing.status,
  });
  res.json({ success: true, data: { id: Number(req.params.id) } });
}));

export default router;
