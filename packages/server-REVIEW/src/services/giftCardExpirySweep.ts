/**
 * Gift-card expiry sweep — SEC-H114 / LOGIC-004 (remaining half).
 *
 * Background
 * ----------
 * The redeem-time atomic guard shipped first: every redemption path
 * already has `AND (expires_at IS NULL OR expires_at > datetime('now'))`
 * in its WHERE clause so an expired card can never be redeemed, even
 * when its `status` column still reads 'active'. That guard is the
 * primary correctness control.
 *
 * This module is the complementary nightly reconciliation pass that
 * flips `status` from 'active' → 'expired' for all cards whose
 * `expires_at` has already passed. Without it, reporting queries,
 * dashboards, and customer-portal balance checks would show stale
 * "active" cards that are actually worthless — a UX and accuracy bug
 * rather than a security gap, but important for operational trust.
 *
 * Design decisions
 * ----------------
 * - Runs inside the existing `forEachDbAsync` + `trackInterval` pattern
 *   (see index.ts) so a single hourly tick fires for all tenants and the
 *   `shouldRunDaily` in-memory guard ensures at-most-once per calendar day
 *   per tenant. No separate cron library needed.
 * - Anchored at 1 AM local tenant timezone — one hour before the 2 AM
 *   retention sweeps so the disk I/O is spread out.
 * - Skips soft-deleted cards (`is_deleted = 0`) so restoring a deleted
 *   card doesn't silently re-activate it as "expired" either.
 * - Writes a single `audit_logs` breadcrumb per non-zero batch per tenant
 *   (event: 'gift_card_expiry_sweep') so compliance has a dated paper
 *   trail without a row-per-card explosion.
 * - Returns 0 without writing an audit row when no rows were updated
 *   (avoids noisy zero-count audit spam on quiet nights).
 *
 * Wiring
 * ------
 * Called from index.ts inside a `trackInterval(..., 60 * 60 * 1000)` that
 * checks `localHour === 1 && shouldRunDaily('gift-card-expiry:<label>', tz)`.
 * See the "SEC-H114: gift-card expiry sweep" block in index.ts.
 */

import type { Database } from 'better-sqlite3';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('giftCardExpirySweep');

/**
 * Check whether `gift_cards` table exists on this tenant DB. Returns false
 * for fresh tenants that predate the gift-cards migration so the sweep skips
 * cleanly rather than throwing.
 */
function giftCardsTableExists(db: Database): boolean {
  const row = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='gift_cards'")
    .get() as { name?: string } | undefined;
  return !!row?.name;
}

/**
 * Write a single audit breadcrumb recording how many cards were expired.
 * Swallows failures so an audit-write problem cannot abort the sweep or
 * hide the fact that the UPDATE already ran successfully.
 */
function writeExpirySweepAudit(db: Database, count: number): void {
  if (count === 0) return;

  const auditExists = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='audit_logs'")
    .get() as { name?: string } | undefined;
  if (!auditExists?.name) return;

  try {
    // SCAN-1173: don't bind the literal string 'system' to `ip_address` —
    // downstream filters that assume an IP shape (e.g. `LIKE '%.%.%.%'`)
    // skip those rows, and a future INET type migration would reject the
    // value outright. Pass null for ip_address and move the source tag
    // into details JSON instead.
    const details = JSON.stringify({
      source: 'system',
      count,
      ran_at: new Date().toISOString(),
    });
    db.prepare(
      'INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, NULL, NULL, ?)',
    ).run('gift_card_expiry_sweep', details);
  } catch (err) {
    logger.error('giftCardExpirySweep: audit write failed', {
      count,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Flip every non-deleted active gift card whose `expires_at` is in the past
 * from 'active' → 'expired'. Returns the number of rows updated.
 *
 * Safe to call on a DB where the gift_cards table does not exist yet (returns
 * 0). Idempotent — rows already in 'expired' state are never touched.
 *
 * @param db - Tenant SQLite database handle (better-sqlite3, synchronous).
 * @returns  Number of gift_cards rows whose status was set to 'expired'.
 */
export function sweepExpiredGiftCards(db: Database): number {
  if (!giftCardsTableExists(db)) return 0;

  let count = 0;
  try {
    const result = db
      .prepare(
        `UPDATE gift_cards
            SET status = 'expired'
          WHERE status = 'active'
            AND expires_at IS NOT NULL
            AND expires_at <= datetime('now')
            AND is_deleted = 0`,
      )
      .run();
    count = result.changes ?? 0;
  } catch (err) {
    logger.error('giftCardExpirySweep: UPDATE failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }

  writeExpirySweepAudit(db, count);

  if (count > 0) {
    logger.info('giftCardExpirySweep: expired gift cards flipped', { count });
  }

  return count;
}
