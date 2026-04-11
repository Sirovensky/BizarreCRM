/**
 * Loyalty points ledger helpers — audit §18.
 *
 * The `loyalty_points` table (migration 089) is an append-only ledger where
 * the running balance for a customer equals `SUM(points)`. There is NO
 * column for running balance — we always recompute. Positive rows are
 * earned (invoice payment, referral reward), negative rows are spent
 * (redemption) or reversed (refund).
 *
 * Prior to this module there was NO insert path anywhere in the codebase,
 * so every customer had a permanent $0 balance even after years of paid
 * invoices. This file is the single choke point for writes so the ledger
 * invariants live in ONE place:
 *
 *   1. `points` must be a finite integer (no floats, no NaN)
 *   2. `customer_id` must reference an existing customer
 *   3. A spend (negative points) must NEVER push the balance below zero
 *   4. Every write is wrapped in a transaction together with the balance
 *      check so two parallel redemptions can't both pass the SELECT
 *   5. `reference_type` is restricted to a small known set so we can
 *      aggregate by source later (e.g. "points earned from invoices this
 *      quarter" vs "points from referrals")
 */

import type { AsyncDb } from '../db/async-db.js';
import { createLogger } from './logger.js';

const logger = createLogger('loyalty');

/**
 * Allowed reference types for a ledger row. Keep this in sync with the
 * comment block in `db/migrations/089_portal_enrichment.sql`.
 */
export type LoyaltyReferenceType =
  | 'invoice'      // Points earned from an invoice payment
  | 'referral'     // Points earned from a successful referral
  | 'manual'       // Admin-issued credit or adjustment
  | 'redemption'   // Points spent on portal redemption
  | 'refund';      // Points reversed because the source invoice was refunded

export interface LoyaltyEarnInput {
  customer_id: number;
  /** Positive for earn, negative for spend/reversal. Must be a non-zero integer. */
  points: number;
  /** Human-readable reason shown in the portal UI history list. */
  reason: string;
  reference_type: LoyaltyReferenceType;
  /** The row id in the referenced table (e.g. invoices.id). NULL for `manual`. */
  reference_id: number | null;
}

/**
 * Write a single row to the loyalty_points ledger.
 *
 * For SPEND operations (negative points), this atomically verifies the
 * current balance is sufficient BEFORE inserting — a parallel redemption
 * cannot cause a negative balance because both the SELECT and the INSERT
 * live inside one AsyncDb transaction batch.
 *
 * For EARN operations (positive points), the insert happens unconditionally
 * (there's no upper bound on how many points a customer can earn).
 *
 * Zero-point writes are rejected outright — they bloat the ledger with
 * meaningless rows and usually indicate a bug in the caller (e.g. a
 * rounding error in the earn-per-dollar calculation).
 */
export async function writeLoyaltyPoints(
  adb: AsyncDb,
  input: LoyaltyEarnInput,
): Promise<void> {
  const { customer_id, points, reason, reference_type, reference_id } = input;

  if (!Number.isInteger(customer_id) || customer_id <= 0) {
    throw new Error(`writeLoyaltyPoints: invalid customer_id: ${customer_id}`);
  }
  if (!Number.isInteger(points) || points === 0) {
    throw new Error(
      `writeLoyaltyPoints: points must be a non-zero integer, got: ${points}`,
    );
  }
  if (typeof reason !== 'string' || reason.length === 0) {
    throw new Error('writeLoyaltyPoints: reason is required');
  }

  // Spend path — enforce non-negative running balance atomically. We do
  // this with a guarded INSERT inside a transaction so the SELECT used to
  // compute the current balance and the INSERT that would take it below
  // zero cannot interleave with a second redemption from the same customer.
  if (points < 0) {
    const spend = -points;
    // Step 1: compute current balance (inside the tx wrapper below).
    // We express the guard as two queries in a single transaction batch:
    //   (a) a SELECT inside a CTE that fails if balance < spend
    //   (b) the actual INSERT
    // SQLite does not support "fail-if-zero-changes" on a SELECT, so we
    // rely on the balance check happening server-side in the worker and
    // throw if the math doesn't work out.
    //
    // The cleanest way to do this atomically is to insert conditionally:
    //   INSERT ... SELECT ? WHERE (SELECT COALESCE(SUM(points),0) FROM
    //   loyalty_points WHERE customer_id=?) >= ?
    // and then expect the insert to affect 1 row. The AsyncDb transaction
    // helper supports `expectChanges: true` so if the conditional insert
    // matches 0 rows, the whole batch rolls back.
    await adb.transaction([
      {
        sql: `
          INSERT INTO loyalty_points
            (customer_id, points, reason, reference_type, reference_id)
          SELECT ?, ?, ?, ?, ?
          WHERE (
            SELECT COALESCE(SUM(points), 0)
              FROM loyalty_points
             WHERE customer_id = ?
          ) >= ?
        `,
        params: [
          customer_id,
          points,
          reason,
          reference_type,
          reference_id,
          customer_id,
          spend,
        ],
        expectChanges: true,
        expectChangesError: 'Insufficient loyalty balance',
      },
    ]);
    logger.info('loyalty spend recorded', {
      customer_id,
      points,
      reference_type,
      reference_id,
    });
    return;
  }

  // Earn path — unconditional insert.
  await adb.run(
    `INSERT INTO loyalty_points
       (customer_id, points, reason, reference_type, reference_id)
     VALUES (?, ?, ?, ?, ?)`,
    customer_id,
    points,
    reason,
    reference_type,
    reference_id,
  );
  logger.info('loyalty earn recorded', {
    customer_id,
    points,
    reference_type,
    reference_id,
  });
}

/**
 * Read the current points balance for a customer. Returns 0 for a
 * customer with no ledger rows (never earned, never spent). Never throws
 * on a missing customer — the caller decides whether that's an error.
 */
export async function getLoyaltyBalance(
  adb: AsyncDb,
  customerId: number,
): Promise<number> {
  if (!Number.isInteger(customerId) || customerId <= 0) return 0;
  const row = await adb.get<{ balance: number | null }>(
    `SELECT COALESCE(SUM(points), 0) AS balance
       FROM loyalty_points
      WHERE customer_id = ?`,
    customerId,
  );
  return Number(row?.balance ?? 0);
}

/**
 * Compute points earned from an invoice payment, given a rate
 * expressed as "points per dollar". Floors the result so a $9.99 payment
 * at 1 pt/$ earns 9, not 10. Returns 0 if the inputs are invalid so the
 * caller can short-circuit without writing to the ledger.
 */
export function computeEarnedPoints(
  amountPaid: number,
  pointsPerDollar: number,
): number {
  if (!Number.isFinite(amountPaid) || amountPaid <= 0) return 0;
  if (!Number.isFinite(pointsPerDollar) || pointsPerDollar <= 0) return 0;
  return Math.floor(amountPaid * pointsPerDollar);
}
