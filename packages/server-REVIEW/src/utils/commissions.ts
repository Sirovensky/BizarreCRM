/**
 * Commission helper — the single choke point for writing, reversing, and
 * calculating commission rows. Extracted from refunds.routes.ts (which
 * previously contained the only code path that ever touched the commissions
 * table) so that ticket close, invoice payment, and POS sales can all use the
 * same lock-aware, rounding-safe logic.
 *
 * Cross-ref: audit #3 — commissions table was only populated on refund
 * reversal. Ticket close, invoice pay, POS sale never wrote a row, meaning
 * every reversal targeted a row that did not exist. Techs who thought they
 * were earning 10% were not.
 *
 * @audit-fixed: writeCommission + reverseCommission close the loop so
 *               commissions are actually recorded when they are earned.
 */
import type { AsyncDb } from '../db/async-db.js';
import { AppError } from '../middleware/errorHandler.js';
import { roundCents, toCents, fromCents } from './validate.js';
import { isCommissionLocked } from '../routes/_team.payroll.js';

export type CommissionType =
  | 'percent_ticket'
  | 'percent_service'
  | 'flat_per_ticket';

export type CommissionSource =
  | 'ticket_close'
  | 'invoice_payment'
  | 'pos_sale'
  | 'reversal'
  | 'manual';

interface UserCommissionConfig {
  id: number;
  commission_rate: number | null;
  commission_type: string | null;
}

interface WriteCommissionArgs {
  userId: number;
  /** Logical source tag stored in commissions.type — kept short so existing
   *  reports that group by `type` keep working. */
  source: CommissionSource;
  ticketId?: number | null;
  invoiceId?: number | null;
  /** Base amount (in CENTS) the commission is calculated from. Excludes tax
   *  by convention — callers are responsible for passing pre-tax cents. */
  commissionableAmountCents: number;
  /** Basis points (10000 bps = 100%). Lets the same helper serve percent
   *  and flat types without lossy float conversions. */
  rateBps?: number;
  /** Pre-computed earned amount in cents. If omitted, `calcCommissionCents`
   *  will be called with `rateBps` + `commissionableAmountCents`. */
  amountEarnedCents?: number;
  /** Reference time used for the payroll-lock check. Defaults to "now". */
  at?: string;
  notes?: string;
}

interface ReverseCommissionArgs {
  sourceType: 'ticket' | 'invoice';
  sourceId: number;
  /** 0..1 fraction to reverse. `1` reverses fully. Used for partial refunds. */
  fraction?: number;
  at?: string;
  notes?: string;
}

/**
 * Round `commissionable * (rateBps / 10000)` to whole cents using banker-safe
 * integer math. Keeps all intermediate work in integer cents × bps to avoid
 * 0.1 + 0.2 drift.
 */
export function calcCommissionCents(
  rateBps: number,
  commissionableCents: number,
): number {
  if (!Number.isFinite(rateBps) || !Number.isFinite(commissionableCents)) return 0;
  if (rateBps <= 0 || commissionableCents <= 0) return 0;
  // cents * bps / 10_000 — Math.round gives banker-safe rounding to nearest cent
  return Math.round((commissionableCents * rateBps) / 10_000);
}

function nowIso(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

/**
 * Resolve the user's commission configuration. Returns null when the user has
 * no commission setup (rate=0 or type null/'none'), in which case callers
 * should skip the write entirely — this is the hot path, we don't want to
 * burn a row for zero.
 */
async function loadUserCommissionConfig(
  adb: AsyncDb,
  userId: number,
): Promise<UserCommissionConfig | null> {
  const row = await adb.get<UserCommissionConfig>(
    'SELECT id, commission_rate, commission_type FROM users WHERE id = ?',
    userId,
  );
  if (!row) return null;
  const rate = Number(row.commission_rate ?? 0);
  const type = row.commission_type;
  if (!type || type === 'none' || rate <= 0) return null;
  return { id: row.id, commission_rate: rate, commission_type: type };
}

/**
 * Compute the earned amount for a given user config + commissionable base.
 * All inputs/outputs in CENTS so callers never round-trip through floats.
 *
 * Supported types:
 *   - percent_ticket  → rate% of commissionable base
 *   - percent_service → rate% of commissionable base (caller prorates service vs parts)
 *   - flat_per_ticket → rate in dollars, flat, ignores commissionable base
 */
export function computeCommissionCents(
  type: string,
  rate: number,
  commissionableCents: number,
): number {
  if (!Number.isFinite(rate) || rate <= 0) return 0;
  if (type === 'percent_ticket' || type === 'percent_service') {
    // rate is expressed as a percentage (e.g. 10 == 10%). Convert to bps.
    const rateBps = Math.round(rate * 100);
    return calcCommissionCents(rateBps, Math.max(0, commissionableCents));
  }
  if (type === 'flat_per_ticket') {
    // rate is a dollar amount. Flat regardless of base.
    return toCents(rate);
  }
  return 0;
}

/**
 * Insert a commissions row. Respects payroll-period locks and the user's
 * commission config. Returns the new row id, or 0 if no row was written
 * (user has no commission setup, computed amount == 0, etc.).
 *
 * @audit-fixed: centralizes the commission-write logic so ticket close +
 *               invoice payment + POS sale all go through the same
 *               lock-aware, config-aware code path.
 */
export async function writeCommission(
  adb: AsyncDb,
  args: WriteCommissionArgs,
): Promise<number> {
  const {
    userId,
    source,
    ticketId = null,
    invoiceId = null,
    commissionableAmountCents,
    amountEarnedCents,
    at,
    notes: _notes,
  } = args;

  if (!Number.isFinite(userId) || userId <= 0) return 0;

  const config = await loadUserCommissionConfig(adb, userId);
  if (!config) return 0; // no setup — skip per rules

  // Compute the earned amount if the caller didn't pre-compute it.
  let earnedCents: number;
  if (typeof amountEarnedCents === 'number' && Number.isFinite(amountEarnedCents)) {
    earnedCents = amountEarnedCents;
  } else {
    earnedCents = computeCommissionCents(
      config.commission_type!,
      Number(config.commission_rate ?? 0),
      commissionableAmountCents,
    );
  }
  if (earnedCents <= 0) return 0;

  const ts = at ?? nowIso();

  // Payroll-period lock: refuse if the period covering `ts` is locked.
  if (await isCommissionLocked(adb, ts)) {
    throw new AppError(
      'Cannot write commission — the current payroll period is locked',
      403,
    );
  }

  const earnedDollars = roundCents(fromCents(earnedCents));
  const result = await adb.run(
    `INSERT INTO commissions
       (user_id, ticket_id, invoice_id, amount, type, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    userId,
    ticketId,
    invoiceId,
    earnedDollars,
    source,
    ts,
    ts,
  );
  return Number(result.lastInsertRowid);
}

/**
 * Reverse commissions attached to a ticket OR invoice by writing negative
 * 'reversal'-typed rows. The caller specifies `fraction` (0..1) for partial
 * refunds — full refunds pass 1 (or omit).
 *
 * Looks up existing non-reversal rows and writes one negative row per.
 * @audit-fixed: extracted from refunds.routes.ts EM1 so the same code
 *               is reused by any future cancellation / void / cancel-pay path.
 */
export async function reverseCommission(
  adb: AsyncDb,
  args: ReverseCommissionArgs,
): Promise<number> {
  const { sourceType, sourceId, fraction = 1, at, notes: _notes } = args;
  if (!Number.isFinite(sourceId) || sourceId <= 0) return 0;

  const column = sourceType === 'ticket' ? 'ticket_id' : 'invoice_id';
  const rows = await adb.all<{
    id: number;
    user_id: number;
    ticket_id: number | null;
    invoice_id: number | null;
    amount: number;
  }>(
    `SELECT id, user_id, ticket_id, invoice_id, amount
       FROM commissions
      WHERE ${column} = ?
        AND COALESCE(type, '') != 'reversal'`,
    sourceId,
  );
  if (rows.length === 0) return 0;

  const ts = at ?? nowIso();
  if (await isCommissionLocked(adb, ts)) {
    throw new AppError(
      'Cannot reverse commissions — the current payroll period is locked',
      403,
    );
  }

  const clampedFraction = Math.min(1, Math.max(0, fraction));
  let written = 0;
  for (const row of rows) {
    const reversalAmount = roundCents(-row.amount * clampedFraction);
    if (reversalAmount === 0) continue;
    await adb.run(
      `INSERT INTO commissions
         (user_id, ticket_id, invoice_id, amount, type, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'reversal', ?, ?)`,
      row.user_id,
      row.ticket_id ?? null,
      row.invoice_id ?? null,
      reversalAmount,
      ts,
      ts,
    );
    written++;
  }
  return written;
}
