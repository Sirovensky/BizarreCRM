import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { hasPermission, requirePermission } from '../middleware/auth.js';
import { audit } from '../utils/audit.js';
import { validatePaginationOffset, validateId, validatePrice, roundCents, validateTextLength } from '../utils/validate.js';
import { parsePageSize, parsePage } from '../utils/pagination.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { allocateCounter, allocateUniqueOrderId, formatInvoiceOrderId } from '../utils/counters.js';
import type { AsyncDb } from '../db/async-db.js';
import { PERMISSIONS } from '@bizarre-crm/shared';

const router = Router();

// Write-side rate limit — a malicious technician could otherwise create
// unlimited loaner_history rows against random customer ids. 60/min matches
// the busiest counter-loading shift.
const LOANER_WRITE_MAX = 60;
const LOANER_WRITE_WINDOW_MS = 60_000;
const RETURN_CONDITIONS = new Set(['good', 'fair', 'poor', 'damaged', 'missing']);
const RETURN_PAYMENT_METHODS = new Set(['cash', 'check', 'external_terminal', 'other']);
const RETURN_PAYMENT_METHOD_LABELS: Record<string, string> = {
  cash: 'Cash',
  check: 'Check',
  external_terminal: 'External terminal',
  other: 'Other',
};

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function userCan(req: any, permission: string): boolean {
  const user = req.user;
  if (!user) return false;
  return hasPermission(user, permission);
}

function optionalText(value: unknown, fieldName: string, maxLength: number): string | null {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be text`, 400);
  const trimmed = value.trim();
  if (!trimmed) return null;
  return validateTextLength(trimmed, maxLength, fieldName);
}

function parseReturnPaymentFlag(value: unknown): boolean {
  return value === true || value === 'true' || value === 1 || value === '1';
}

// SEC-M18: loaner rows expose serial + IMEI + current-holder name. That
// gives any authenticated cashier a way to map hardware asset numbers to
// customers — useful for theft/resale fencing. Gate list + detail on the
// same inventory.adjust_stock grant that covers RMA reads; non-admins get
// serial + IMEI redacted so the core "which loaner is out?" workflow
// still works without handing over per-device identifiers.
function redactLoanerForRole(row: any, role: string | undefined): any {
  if (role === 'admin') return row;
  const out = { ...row };
  if ('serial' in out) out.serial = null;
  if ('imei' in out) out.imei = null;
  return out;
}

// GET / — List all loaner devices
router.get('/', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const page = parsePage(_req.query.page);
  const perPage = parsePageSize(_req.query.per_page, 50);
  const offset = validatePaginationOffset((page - 1) * perPage, 'offset');
  const total = ((await adb.get<{ c: number }>('SELECT COUNT(*) as c FROM loaner_devices WHERE is_deleted = 0'))!).c;
  const devices = await adb.all<any>(`
    SELECT ld.*,
      (SELECT COUNT(*) FROM loaner_history lh WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL) AS is_loaned_out,
      (SELECT c.first_name || ' ' || c.last_name FROM loaner_history lh
       LEFT JOIN customers c ON c.id = lh.customer_id
       WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL LIMIT 1) AS loaned_to,
      -- WEB-UIUX-641: surface the most recent active loan due_back_at +
      -- compute an is_overdue flag the client can render without re-querying.
      (SELECT lh.due_back_at FROM loaner_history lh
       WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL
       ORDER BY lh.loaned_at DESC LIMIT 1) AS due_back_at,
      (SELECT CASE WHEN lh.due_back_at IS NOT NULL AND datetime(lh.due_back_at) < datetime('now') THEN 1 ELSE 0 END
       FROM loaner_history lh
       WHERE lh.loaner_device_id = ld.id AND lh.returned_at IS NULL
       ORDER BY lh.loaned_at DESC LIMIT 1) AS is_overdue
    FROM loaner_devices ld WHERE ld.is_deleted = 0 ORDER BY ld.name LIMIT ? OFFSET ?
  `, perPage, offset);
  const redacted = devices.map((d) => redactLoanerForRole(d, _req.user?.role));
  res.json({ success: true, data: redacted, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /overdue — WEB-UIUX-641: list every active loan past its due_back_at.
// Returned shape mirrors loaner_history with the loaner device name +
// customer name joined for the dashboard widget. Pagination matches the
// list endpoint defaults (50/page). Ordered by how late the loan is.
router.get('/overdue', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const page = parsePage(req.query.page);
  const perPage = parsePageSize(req.query.per_page, 50);
  const offset = validatePaginationOffset((page - 1) * perPage, 'offset');
  const total = ((await adb.get<{ c: number }>(`
    SELECT COUNT(*) AS c
      FROM loaner_history lh
      JOIN loaner_devices ld ON ld.id = lh.loaner_device_id
     WHERE lh.returned_at IS NULL
       AND lh.due_back_at IS NOT NULL
       AND datetime(lh.due_back_at) < datetime('now')
       AND ld.is_deleted = 0
  `))!).c;
  const rows = await adb.all<any>(`
    SELECT lh.id AS history_id, lh.loaner_device_id, lh.customer_id,
           lh.loaned_at, lh.due_back_at, lh.notes,
           ld.name AS loaner_name, ld.condition,
           c.first_name, c.last_name, c.phone, c.email,
           t.id AS ticket_id, t.order_id AS ticket_order_id,
           CAST((julianday('now') - julianday(lh.due_back_at)) AS INTEGER) AS days_overdue
      FROM loaner_history lh
      JOIN loaner_devices ld ON ld.id = lh.loaner_device_id
 LEFT JOIN customers c ON c.id = lh.customer_id
 LEFT JOIN ticket_devices td ON td.id = lh.ticket_device_id
 LEFT JOIN tickets t ON t.id = td.ticket_id
     WHERE lh.returned_at IS NULL
       AND lh.due_back_at IS NOT NULL
       AND datetime(lh.due_back_at) < datetime('now')
       AND ld.is_deleted = 0
     ORDER BY lh.due_back_at ASC
     LIMIT ? OFFSET ?
  `, perPage, offset);
  res.json({ success: true, data: rows, pagination: { page, per_page: perPage, total, total_pages: Math.ceil(total / perPage) } });
}));

// GET /:id — Single loaner device with history
router.get('/:id', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const device = await adb.get('SELECT * FROM loaner_devices WHERE id = ? AND is_deleted = 0', id);
  if (!device) throw new AppError('Loaner device not found', 404);
  const history = await adb.all(`
    SELECT lh.*, c.first_name, c.last_name, t.order_id AS ticket_order_id
    FROM loaner_history lh
    LEFT JOIN customers c ON c.id = lh.customer_id
    LEFT JOIN ticket_devices td ON td.id = lh.ticket_device_id
    LEFT JOIN tickets t ON t.id = td.ticket_id
    WHERE lh.loaner_device_id = ? ORDER BY lh.loaned_at DESC
  `, id);
  const safe = redactLoanerForRole(device as any, req.user?.role);
  res.json({ success: true, data: { ...safe, history } });
}));

// POST / — Create loaner device
router.post('/', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const { name, serial, imei, condition = 'good', notes } = req.body;
  if (!name) throw new AppError('Name required', 400);
  const result = await adb.run(
    'INSERT INTO loaner_devices (name, serial, imei, condition, status, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    name, serial || null, imei || null, condition, 'available', notes || null, now(), now()
  );
  audit(req.db, 'loaner_device_created', req.user!.id, req.ip || 'unknown', { loaner_id: Number(result.lastInsertRowid), name });
  res.status(201).json({ success: true, data: { id: result.lastInsertRowid } });
}));

// PUT /:id — Update loaner device details (API-3)
router.put('/:id', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const existing = await adb.get('SELECT id FROM loaner_devices WHERE id = ? AND is_deleted = 0', id);
  if (!existing) throw new AppError('Loaner device not found', 404);

  const { name, serial, imei, condition, notes } = req.body;
  if (name !== undefined && !name) throw new AppError('Name cannot be empty', 400);

  await adb.run(`
    UPDATE loaner_devices SET
      name = COALESCE(?, name),
      serial = COALESCE(?, serial),
      imei = COALESCE(?, imei),
      condition = COALESCE(?, condition),
      notes = COALESCE(?, notes),
      updated_at = ?
    WHERE id = ?
  `, name ?? null, serial ?? null, imei ?? null, condition ?? null, notes ?? null, now(), id);
  audit(req.db, 'loaner_device_updated', req.user!.id, req.ip || 'unknown', { loaner_id: id });

  res.json({ success: true, data: { id } });
}));

// POST /:id/loan — Loan out to customer
router.post('/:id/loan', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  // SCAN-1043: per-user write rate limit on loan creation.
  const rl = consumeWindowRate(db, 'loaner_write', String(req.user!.id), LOANER_WRITE_MAX, LOANER_WRITE_WINDOW_MS);
  if (!rl.allowed) throw new AppError('Too many loaner operations — please slow down', 429);
  const id = validateId(req.params.id, 'id');
  const { customer_id, ticket_device_id, notes, due_back_at } = req.body;
  if (!customer_id) throw new AppError('customer_id required', 400);
  // WEB-UIUX-641: optional ISO timestamp / YYYY-MM-DD date string. Accept
  // either shape; store as-is so the overdue query can compare against
  // datetime('now'). Reject non-string values + obviously-bad inputs so a
  // crafted blob can't poison the column.
  let dueBackAt: string | null = null;
  if (due_back_at !== undefined && due_back_at !== null && due_back_at !== '') {
    if (typeof due_back_at !== 'string' || due_back_at.length > 32) {
      throw new AppError('due_back_at must be a YYYY-MM-DD or ISO timestamp string', 400);
    }
    const parsed = Date.parse(due_back_at);
    if (!Number.isFinite(parsed)) {
      throw new AppError('due_back_at could not be parsed as a date', 400);
    }
    dueBackAt = due_back_at;
  }
  // @audit-fixed: §37 — loaner_history.ticket_device_id is NOT NULL in
  // 001_initial.sql:502, but the previous handler accepted requests without a
  // ticket_device_id and inserted NULL, which always failed with a constraint
  // violation. Require it explicitly so the API surface matches the schema and
  // returns a clean 400 instead of a 500.
  if (!ticket_device_id) throw new AppError('ticket_device_id required', 400);

  // V6: Verify FK existence before INSERT
  const [customer, device, ticketDevice] = await Promise.all([
    adb.get('SELECT id FROM customers WHERE id = ?', customer_id),
    adb.get('SELECT * FROM loaner_devices WHERE id = ? AND is_deleted = 0', id),
    adb.get('SELECT id FROM ticket_devices WHERE id = ?', ticket_device_id),
  ]);
  if (!customer) throw new AppError('Customer not found', 404);
  if (!ticketDevice) throw new AppError('Ticket device not found', 404);

  if (!device) throw new AppError('Loaner device not found', 404);
  if ((device as any).status !== 'available') throw new AppError('Device is not available', 400);

  // Conditional UPDATE gated on status='available' — without the WHERE guard,
  // two concurrent /loan calls on the same device could both pass the SELECT
  // above and both insert loaner_history rows. If the guard rejects (0 rows
  // changed) another loaner_history insert is skipped and a 409 is returned.
  //
  // SCAN-1102: previously the UPDATE + INSERT were split async calls. If the
  // INSERT into loaner_history failed (constraint violation, disk full,
  // WAL error), the device was left `status='loaned'` with no history row —
  // so /return could never find an active loan and the device was stuck
  // forever. Wrap both statements in a sync better-sqlite3 transaction so
  // a failed INSERT rolls back the status flip.
  const txNow = now();
  const loanTx = db.transaction((): number | bigint => {
    const u = db.prepare(
      "UPDATE loaner_devices SET status = 'loaned', updated_at = ? WHERE id = ? AND status = 'available'"
    ).run(txNow, id);
    if (u.changes === 0) {
      throw new AppError('Device is not available', 409);
    }
    const r = db.prepare(
      'INSERT INTO loaner_history (loaner_device_id, ticket_device_id, customer_id, loaned_at, condition_out, notes, due_back_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).run(id, ticket_device_id, customer_id, txNow, (device as any).condition, notes || null, dueBackAt);
    return r.lastInsertRowid;
  });
  const historyId = loanTx();
  audit(db, 'loaner_device_loaned', req.user!.id, req.ip || 'unknown', { loaner_id: id, customer_id, history_id: historyId, due_back_at: dueBackAt });
  res.json({ success: true, data: { history_id: historyId } });
}));

// POST /:id/return — Return loaner
router.post('/:id/return', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const {
    condition_in,
    notes,
    return_charge_amount,
    return_charge_paid,
    return_charge_payment_method,
    return_charge_payment_reference,
  } = req.body;
  const active = await adb.get<{
    id: number;
    customer_id: number;
    ticket_device_id: number;
    loaner_name: string;
    ticket_id: number | null;
  }>(
    `SELECT lh.id, lh.customer_id, lh.ticket_device_id, ld.name AS loaner_name, td.ticket_id
       FROM loaner_history lh
       JOIN loaner_devices ld ON ld.id = lh.loaner_device_id
       LEFT JOIN ticket_devices td ON td.id = lh.ticket_device_id
      WHERE lh.loaner_device_id = ? AND lh.returned_at IS NULL
      ORDER BY lh.loaned_at DESC LIMIT 1`,
    id
  );
  if (!active) throw new AppError('Device is not currently loaned out', 400);

  const normalizedCondition = typeof condition_in === 'string' && condition_in.trim()
    ? condition_in.trim().toLowerCase()
    : 'good';
  if (!RETURN_CONDITIONS.has(normalizedCondition)) {
    throw new AppError('Invalid return condition', 400);
  }
  const cleanNotes = optionalText(notes, 'notes', 1000);
  const chargeAmount = return_charge_amount === undefined || return_charge_amount === null || return_charge_amount === ''
    ? 0
    : validatePrice(return_charge_amount, 'return_charge_amount');
  const shouldRecordPayment = parseReturnPaymentFlag(return_charge_paid);
  const paymentMethod = typeof return_charge_payment_method === 'string' && return_charge_payment_method.trim()
    ? return_charge_payment_method.trim().toLowerCase()
    : 'cash';
  const paymentReference = optionalText(return_charge_payment_reference, 'return_charge_payment_reference', 120);

  if (shouldRecordPayment && chargeAmount <= 0) {
    throw new AppError('return_charge_amount must be greater than 0 when recording a payment', 400);
  }
  if (chargeAmount <= 0 && paymentReference) {
    throw new AppError('Payment reference requires a return charge amount', 400);
  }
  if (shouldRecordPayment && !RETURN_PAYMENT_METHODS.has(paymentMethod)) {
    throw new AppError('Invalid return charge payment method', 400);
  }
  if (shouldRecordPayment && paymentMethod === 'external_terminal' && !paymentReference) {
    throw new AppError('Payment reference is required for external terminal payments', 400);
  }

  if (chargeAmount > 0 && !userCan(req, 'invoices.create')) {
    throw new AppError('Insufficient permissions to create a loaner return charge invoice', 403);
  }
  if (shouldRecordPayment && chargeAmount > 0 && !userCan(req, 'invoices.record_payment')) {
    throw new AppError('Insufficient permissions to record a loaner return charge payment', 403);
  }

  const txNow = now();
  const returnTx = db.transaction(() => {
    db.prepare('UPDATE loaner_history SET returned_at = ?, condition_in = ?, notes = COALESCE(?, notes) WHERE id = ?')
      .run(txNow, normalizedCondition, cleanNotes, active.id);
    db.prepare('UPDATE loaner_devices SET status = ?, condition = COALESCE(?, condition), updated_at = ? WHERE id = ?')
      .run('available', normalizedCondition, txNow, id);

    let charge: null | {
      id: number;
      invoice_id: number;
      invoice_order_id: string;
      payment_id: number | null;
      amount: number;
      amount_paid: number;
      amount_due: number;
      status: string;
      payment_method: string | null;
      payment_reference: string | null;
    } = null;

    if (chargeAmount > 0) {
      const orderId = formatInvoiceOrderId(allocateUniqueOrderId(db, 'invoice_order_id', 'invoices', 'order_id', 'INV-'));
      const paidAmount = shouldRecordPayment ? chargeAmount : 0;
      const amountDue = roundCents(chargeAmount - paidAmount);
      const invoiceStatus = shouldRecordPayment ? 'paid' : 'unpaid';
      const invoiceNotes = [
        `Loaner return charge for ${active.loaner_name}`,
        cleanNotes ? `Return notes: ${cleanNotes}` : null,
      ].filter(Boolean).join('\n');

      const invoiceResult = db.prepare(`
        INSERT INTO invoices (order_id, customer_id, ticket_id, subtotal, discount, total_tax, total,
          amount_paid, amount_due, status, notes, created_by)
        VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?, ?)
      `).run(orderId, active.customer_id, active.ticket_id || null, chargeAmount, chargeAmount, paidAmount, amountDue,
        invoiceStatus, invoiceNotes, req.user!.id);
      const invoiceId = Number(invoiceResult.lastInsertRowid);

      db.prepare(`
        INSERT INTO invoice_line_items (invoice_id, description, quantity, unit_price, total, notes)
        VALUES (?, ?, 1, ?, ?, ?)
      `).run(invoiceId, `Loaner return fee - ${active.loaner_name}`, chargeAmount, chargeAmount, cleanNotes);

      let paymentId: number | null = null;
      if (shouldRecordPayment) {
        const methodLabel = RETURN_PAYMENT_METHOD_LABELS[paymentMethod] || paymentMethod;
        const paymentResult = db.prepare(`
          INSERT INTO payments
            (invoice_id, amount, method, method_detail, transaction_id, notes, payment_type, user_id, reference, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, 'payment', ?, ?, ?, ?)
        `).run(
          invoiceId,
          chargeAmount,
          methodLabel,
          paymentReference,
          paymentReference,
          `Loaner return charge payment for ${active.loaner_name}`,
          req.user!.id,
          paymentReference,
          txNow,
          txNow,
        );
        paymentId = Number(paymentResult.lastInsertRowid);
      }

      const chargeResult = db.prepare(`
        INSERT INTO loaner_return_charges
          (loaner_history_id, loaner_device_id, customer_id, ticket_id, invoice_id, payment_id, amount,
           amount_paid, amount_due, status, payment_method, payment_reference, notes, created_by_user_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        active.id,
        id,
        active.customer_id,
        active.ticket_id || null,
        invoiceId,
        paymentId,
        chargeAmount,
        paidAmount,
        amountDue,
        invoiceStatus,
        shouldRecordPayment ? paymentMethod : null,
        shouldRecordPayment ? paymentReference : null,
        cleanNotes,
        req.user!.id,
        txNow,
        txNow,
      );

      charge = {
        id: Number(chargeResult.lastInsertRowid),
        invoice_id: invoiceId,
        invoice_order_id: orderId,
        payment_id: paymentId,
        amount: chargeAmount,
        amount_paid: paidAmount,
        amount_due: amountDue,
        status: invoiceStatus,
        payment_method: shouldRecordPayment ? paymentMethod : null,
        payment_reference: shouldRecordPayment ? paymentReference : null,
      };
    }

    return { charge };
  });

  const { charge } = returnTx();
  audit(db, 'loaner_device_returned', req.user!.id, req.ip || 'unknown', {
    loaner_id: id,
    history_id: active.id,
    condition_in: normalizedCondition,
    return_charge: charge,
  });
  res.json({ success: true, data: { returned: true, return_charge: charge } });
}));

// WEB-UIUX-642: POST /:id/mark-lost — terminal transition for an outstanding
// loan when the customer walked off with the device. Without this the only
// state options were `available` / `loaned`, so a never-returned device sat
// `loaned` forever and the loan history could not be closed. We resolve the
// active loaner_history row (sets returned_at + condition_in='lost'), flip
// the device to `status='lost'`, and let the operator optionally invoice the
// customer for the unreturned device via the existing return-charge body
// fields. The transition mirrors `/return` for atomicity guarantees.
router.post('/:id/mark-lost', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const db = req.db;
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const { notes, charge_amount, charge_paid, charge_payment_method, charge_payment_reference } = req.body || {};

  const device = await adb.get('SELECT * FROM loaner_devices WHERE id = ? AND is_deleted = 0', id) as any;
  if (!device) throw new AppError('Loaner device not found', 404);
  if (device.status === 'lost') throw new AppError('Device is already marked lost', 400);

  // Resolve the active loan, if any. Loaner can be marked lost even if it
  // was never loaned (e.g. shop inventory loss) — in that case we just flip
  // the device status, no history row to close.
  const active = await adb.get<any>(
    'SELECT * FROM loaner_history WHERE loaner_device_id = ? AND returned_at IS NULL ORDER BY id DESC LIMIT 1',
    id,
  );

  // Round to cents so a value like 9.999 doesn't land in the invoice as
  // a 3-decimal float. Mirrors how `/return` calls validatePrice.
  const chargeAmountNum = charge_amount === undefined || charge_amount === null
    ? null
    : Math.round(Number(charge_amount) * 100) / 100;
  if (chargeAmountNum !== null && (!Number.isFinite(chargeAmountNum) || chargeAmountNum < 0)) {
    throw new AppError('charge_amount must be a non-negative number', 400);
  }
  if (chargeAmountNum !== null && chargeAmountNum > 999999.99) {
    throw new AppError('charge_amount exceeds maximum', 400);
  }
  const recordCharge = chargeAmountNum !== null && chargeAmountNum > 0;
  const txNow = now();

  const lostTx = db.transaction((): void => {
    const u = db.prepare(
      "UPDATE loaner_devices SET status = 'lost', updated_at = ? WHERE id = ? AND is_deleted = 0"
    ).run(txNow, id);
    if (u.changes === 0) throw new AppError('Loaner device not found', 404);

    if (active) {
      db.prepare(
        `UPDATE loaner_history
            SET returned_at = ?,
                condition_in = COALESCE(condition_in, 'lost'),
                notes = COALESCE(?, notes)
          WHERE id = ?`,
      ).run(txNow, notes ?? null, active.id);
    }
  });
  lostTx();

  // Optional invoice for the unreturned device — mirrors `/return` charge.
  let charge: any = null;
  if (recordCharge && active?.customer_id) {
    try {
      // BUGHUNT-2026-05-16: mirror the `/return` charge path — use the
      // shared INV-XXXX counter so the row lands in the regular invoice
      // sequence and can never collide with a UNIQUE order_id (the prior
      // `LOAN-LOST-${id}-${Date.now()}` could collide on same-ms retries
      // and was hidden from the `INV-*` invoice list filter).
      const orderId = formatInvoiceOrderId(
        allocateUniqueOrderId(db, 'invoice_order_id', 'invoices', 'order_id', 'INV-'),
      );
      const status = charge_paid ? 'paid' : 'unpaid';
      const insertInv = await adb.run(
        `INSERT INTO invoices
           (order_id, customer_id, subtotal, total_tax, total,
            amount_paid, amount_due, status, notes, created_by, created_at, updated_at)
         VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))`,
        orderId,
        active.customer_id,
        chargeAmountNum,
        chargeAmountNum,
        charge_paid ? chargeAmountNum : 0,
        charge_paid ? 0 : chargeAmountNum,
        status,
        `Unreturned loaner device: ${device.name}`,
        req.user!.id,
      );
      charge = { invoice_id: Number(insertInv.lastInsertRowid), amount: chargeAmountNum, status };
    } catch (err) {
      // Don't fail the whole mark-lost flow if invoice creation hits a
      // schema quirk; surface in logs and return the status flip.
      const msg = err instanceof Error ? err.message : String(err);
      audit(db, 'loaner_lost_invoice_failed', req.user!.id, req.ip || 'unknown', {
        loaner_id: id,
        error: msg,
      });
    }
  }

  audit(db, 'loaner_device_marked_lost', req.user!.id, req.ip || 'unknown', {
    loaner_id: id,
    history_id: active?.id ?? null,
    charge,
  });
  res.json({ success: true, data: { id, status: 'lost', charge } });
}));

// DELETE /:id — Soft-delete loaner device
// SEC-H121: Replaces hard DELETE (and the prior loaner_history cascade) to
// preserve audit trail. The device row is marked is_deleted = 1 so it
// disappears from all normal list/detail queries. loaner_history rows are
// intentionally kept intact — they form the per-device loan audit trail.
router.delete('/:id', requirePermission(PERMISSIONS.INVENTORY_ADJUST_STOCK), asyncHandler(async (req, res) => {
  const adb = req.asyncDb;
  const id = validateId(req.params.id, 'id');
  const device = await adb.get(
    'SELECT * FROM loaner_devices WHERE id = ? AND is_deleted = 0',
    id,
  ) as any;
  if (!device) throw new AppError('Loaner device not found', 404);
  if (device.status === 'loaned') {
    throw new AppError('Cannot delete a device that is currently loaned out. Return it or mark it lost first.', 400);
  }

  await adb.run(
    `UPDATE loaner_devices
        SET is_deleted = 1, deleted_at = datetime('now'), deleted_by_user_id = ?
      WHERE id = ? AND is_deleted = 0`,
    req.user!.id, id,
  );
  audit(req.db, 'loaner_device_soft_deleted', req.user!.id, req.ip || 'unknown', {
    loaner_id: id,
    name: device.name,
  });
  res.json({ success: true, data: { id } });
}));

export default router;
