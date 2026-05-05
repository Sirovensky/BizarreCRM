/**
 * Tiny helper used by team.routes.ts (and may be used by tickets/commissions
 * routes in a follow-up) to check whether a given timestamp falls inside a
 * locked payroll period. Kept in its own file so callers don't have to pull
 * the whole team router.
 *
 * "Locked" = there exists a payroll_periods row whose [start_date, end_date]
 * range covers `at` AND whose locked_at IS NOT NULL.
 *
 * Cross-ref: criticalaudit.md §53 — payroll-period lock.
 */
import type { AsyncDb } from '../db/async-db.js';

export async function isCommissionLocked(adb: AsyncDb, at: string): Promise<boolean> {
  try {
    const row = await adb.get<{ id: number }>(
      `SELECT id FROM payroll_periods
       WHERE locked_at IS NOT NULL
         AND ? BETWEEN start_date AND end_date
       LIMIT 1`,
      at,
    );
    return !!row;
  } catch {
    // Defensive: if the table is somehow missing, never block writes.
    return false;
  }
}
