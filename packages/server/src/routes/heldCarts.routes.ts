/**
 * Held POS Carts — /api/v1/pos/held-carts
 *
 * SCAN-497
 * Auth:  authMiddleware applied at parent mount (index.ts) — not re-added here.
 * Authz: users see / manage only their own carts.
 *        Admin users may list all carts with ?all=1 and access any cart by id.
 * Soft-delete: discarded_at timestamp (no hard deletes).
 * cart_json: max 64 KB. metadata implicit in cart_json — no separate field.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { consumeWindowRate } from '../utils/rateLimiter.js';
import { validateId } from '../utils/validate.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';

const router = Router();
const logger = createLogger('heldCarts');

// cart_json size cap
const MAX_CART_JSON_BYTES = 64 * 1024;

// Rate-limit: 60 POSTs per minute per user (prevents rapid hold-spam)
const CREATE_RATE_MAX = 60;
const CREATE_RATE_WINDOW_MS = 60_000;

// Rate-limit: 30 deletes per minute per user
const DELETE_RATE_MAX = 30;
const DELETE_RATE_WINDOW_MS = 60_000;

function isAdmin(req: any): boolean {
  return req.user!.role === 'admin' || req.user!.role === 'superadmin';
}

interface HeldCartRow {
  id: number;
  user_id: number;
  workstation_id: number | null;
  label: string | null;
  cart_json: string;
  customer_id: number | null;
  total_cents: number | null;
  created_at: string;
  recalled_at: string | null;
  discarded_at: string | null;
}

// ---------------------------------------------------------------------------
// GET / — list held carts (own only, or all for admin with ?all=1)
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const user = req.user!;
    const showAll = req.query.all === '1' && isAdmin(req);

    // Held-cart 24-hour TTL (mockup spec §4 Frame 16). Carts older than 24h
    // are hidden from the recall list — they're rarely valid (customer left,
    // staff change, prices may have moved) and a stale snapshot can cause
    // bad inventory holds on recall. We don't hard-delete on LIST so an
    // admin can investigate via the showAll flag if needed; a daily janitor
    // pass elsewhere can hard-purge ancient rows for storage hygiene.
    const conditions: string[] = [
      'hc.recalled_at IS NULL',
      'hc.discarded_at IS NULL',
      "hc.created_at > datetime('now', '-24 hours')",
    ];
    const params: unknown[] = [];

    if (!showAll) {
      conditions.push('hc.user_id = ?');
      params.push(user.id);
    }

    // BUGHUNT-2026-05-17: cap the list at 200 rows. Without LIMIT, a
    // cashier (or admin via showAll=1) with a long history of held
    // carts loaded the entire history every time they opened the
    // panel — the response payload could easily exceed 10MB and stall
    // the browser. 200 covers any realistic in-flight workload; older
    // rows are retrieved via the per-id GET below.
    const carts = await adb.all<HeldCartRow & { owner_first_name: string | null; owner_last_name: string | null }>(
      `SELECT hc.*,
              u.first_name AS owner_first_name, u.last_name AS owner_last_name
       FROM held_carts hc
       LEFT JOIN users u ON u.id = hc.user_id
       WHERE ${conditions.join(' AND ')}
       ORDER BY hc.created_at DESC
       LIMIT 200`,
      ...params,
    );

    res.json({ success: true, data: carts });
  }),
);

// ---------------------------------------------------------------------------
// GET /:id — single cart (own only, or admin)
// ---------------------------------------------------------------------------
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const user = req.user!;

    const id = validateId(req.params.id, 'id');

    const cart = await adb.get<HeldCartRow>('SELECT * FROM held_carts WHERE id = ?', id);
    if (!cart) throw new AppError('Held cart not found', 404);

    if (cart.user_id !== user.id && !isAdmin(req)) {
      throw new AppError('Access denied', 403);
    }

    res.json({ success: true, data: cart });
  }),
);

// ---------------------------------------------------------------------------
// POST / — hold (save) a new cart
// ---------------------------------------------------------------------------
router.post(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const user = req.user!;

    // Rate-limit writes per user
    const rl = consumeWindowRate(req.db, 'held_cart_create', String(user.id), CREATE_RATE_MAX, CREATE_RATE_WINDOW_MS);
    if (!rl.allowed) {
      throw new AppError(`Too many hold requests. Retry in ${rl.retryAfterSeconds}s.`, 429);
    }

    const { cart_json, label, workstation_id, customer_id, total_cents } = req.body as {
      cart_json?: unknown;
      label?: unknown;
      workstation_id?: unknown;
      customer_id?: unknown;
      total_cents?: unknown;
    };

    if (!cart_json) throw new AppError('cart_json is required', 400);
    if (typeof cart_json !== 'string') throw new AppError('cart_json must be a string', 400);

    // Validate cart_json is parseable JSON
    try {
      JSON.parse(cart_json);
    } catch {
      throw new AppError('cart_json must be valid JSON', 400);
    }

    // Enforce 64 KB cap
    if (Buffer.byteLength(cart_json, 'utf8') > MAX_CART_JSON_BYTES) {
      throw new AppError('cart_json exceeds 64 KB limit', 413);
    }

    // Validate optional fields
    const safeLabel = label !== undefined && label !== null
      ? (typeof label === 'string' ? label.slice(0, 255) : null)
      : null;

    let safeWorkstationId: number | null = null;
    if (workstation_id !== undefined && workstation_id !== null) {
      safeWorkstationId = Number(workstation_id);
      if (!Number.isInteger(safeWorkstationId) || safeWorkstationId <= 0) {
        throw new AppError('workstation_id must be a positive integer', 400);
      }
    }

    let safeCustomerId: number | null = null;
    if (customer_id !== undefined && customer_id !== null) {
      safeCustomerId = Number(customer_id);
      if (!Number.isInteger(safeCustomerId) || safeCustomerId <= 0) {
        throw new AppError('customer_id must be a positive integer', 400);
      }
    }

    let safeTotalCents: number | null = null;
    if (total_cents !== undefined && total_cents !== null) {
      safeTotalCents = Number(total_cents);
      if (!Number.isInteger(safeTotalCents) || safeTotalCents < 0) {
        throw new AppError('total_cents must be a non-negative integer', 400);
      }
    }

    const result = await adb.run(
      `INSERT INTO held_carts (user_id, workstation_id, label, cart_json, customer_id, total_cents)
       VALUES (?, ?, ?, ?, ?, ?)`,
      user.id,
      safeWorkstationId,
      safeLabel,
      cart_json,
      safeCustomerId,
      safeTotalCents,
    );

    const cart = await adb.get<HeldCartRow>('SELECT * FROM held_carts WHERE id = ?', result.lastInsertRowid);

    logger.info('held_cart: created', { id: result.lastInsertRowid, user_id: user.id });

    audit(req.db, 'held_cart_created', user.id, req.ip || 'unknown', {
      cart_id: result.lastInsertRowid,
      total_cents: safeTotalCents,
      customer_id: safeCustomerId,
      workstation_id: safeWorkstationId,
    });

    res.status(201).json({ success: true, data: cart });
  }),
);

// ---------------------------------------------------------------------------
// DELETE /:id — soft-delete via discarded_at
// ---------------------------------------------------------------------------
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const db = req.db;
    const user = req.user!;

    // Rate-limit deletes per user
    const rl = consumeWindowRate(db, 'held_cart_delete', String(user.id), DELETE_RATE_MAX, DELETE_RATE_WINDOW_MS);
    if (!rl.allowed) {
      throw new AppError(`Too many delete requests. Retry in ${rl.retryAfterSeconds}s.`, 429);
    }

    const id = validateId(req.params.id, 'id');

    const cart = await adb.get<HeldCartRow>('SELECT * FROM held_carts WHERE id = ?', id);
    if (!cart) throw new AppError('Held cart not found', 404);
    if (cart.discarded_at) throw new AppError('Cart already discarded', 410);

    if (cart.user_id !== user.id && !isAdmin(req)) {
      throw new AppError('Access denied', 403);
    }

    // BUGHUNT-2026-05-17: guard the UPDATE WHERE discarded_at IS NULL AND
    // recalled_at IS NULL so a concurrent /recall that's already handing
    // the cart_json to a cashier doesn't get silently discarded behind
    // their back. The recalling cashier is mid-checkout when this discard
    // would otherwise land — leading to a cart that's "discarded" but
    // also actively being rung up. changes === 0 → 409.
    const discardRes = await adb.run(
      "UPDATE held_carts SET discarded_at = strftime('%Y-%m-%d %H:%M:%S', 'now') WHERE id = ? AND discarded_at IS NULL AND recalled_at IS NULL",
      id,
    );
    if (discardRes.changes === 0) {
      throw new AppError('Cart was just recalled or discarded by another cashier — refresh the held-carts list.', 409);
    }

    // Audit held-cart deletion — required per spec
    audit(db, 'held_cart_discarded', user.id, req.ip || 'unknown', {
      cart_id: id,
      owner_user_id: cart.user_id,
      by_admin: cart.user_id !== user.id,
      customer_id: cart.customer_id,
    });

    res.json({ success: true, data: { message: 'Cart discarded' } });
  }),
);

// ---------------------------------------------------------------------------
// POST /:id/recall — mark cart as recalled; return cart_json for client restore
// ---------------------------------------------------------------------------
router.post(
  '/:id/recall',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const user = req.user!;

    const id = validateId(req.params.id, 'id');

    const cart = await adb.get<HeldCartRow>('SELECT * FROM held_carts WHERE id = ?', id);
    if (!cart) throw new AppError('Held cart not found', 404);
    if (cart.discarded_at) throw new AppError('Cart has been discarded', 410);
    if (cart.recalled_at) throw new AppError('Cart has already been recalled', 409);

    // 24h TTL — match the LIST filter so a cashier with the recall URL
    // bookmarked / cached can't resurrect a stale cart.
    const createdMs = Date.parse(cart.created_at + 'Z');
    if (Number.isFinite(createdMs) && Date.now() - createdMs > 24 * 60 * 60 * 1000) {
      throw new AppError('Cart has expired (>24h old). Start a new sale.', 410);
    }

    if (cart.user_id !== user.id && !isAdmin(req)) {
      throw new AppError('Access denied', 403);
    }

    // BUGHUNT-2026-05-17: guard the UPDATE so two concurrent recalls can't
    // both succeed. Without `AND recalled_at IS NULL`, both cashiers receive
    // the cart_json and can both proceed to checkout, creating duplicate
    // invoices for the same items. WHERE clause limits to the "still
    // unclaimed" state; changes === 0 → another cashier won the race.
    const recallResult = await adb.run(
      "UPDATE held_carts SET recalled_at = strftime('%Y-%m-%d %H:%M:%S', 'now') WHERE id = ? AND recalled_at IS NULL AND discarded_at IS NULL",
      id,
    );
    if (recallResult.changes === 0) {
      throw new AppError('Cart was just recalled or discarded by another cashier — refresh the held-carts list.', 409);
    }

    logger.info('held_cart: recalled', { id, user_id: user.id });

    // Return the cart_json so the client can immediately restore it
    const updated = await adb.get<HeldCartRow>('SELECT * FROM held_carts WHERE id = ?', id);

    res.json({ success: true, data: updated });
  }),
);

export default router;
