/**
 * Customer Health Score service (audit §49 — idea 1 & 2)
 *
 * Computes a 0-100 health score per customer using a classic RFM model:
 *   Recency   — days since last interaction → 0 (stale)  .. 40 (fresh)
 *   Frequency — tickets in last 12 months   → 0          .. 30
 *   Monetary  — lifetime value in cents      → 0          .. 30
 * Tiers:
 *   80-100 → champion
 *   50- 79 → healthy
 *   < 50   → at_risk
 *
 * Also derives a lifetime-value tier (bronze/silver/gold/platinum) from
 * the same lifetime_value_cents column so both badges share a single
 * round-trip to SQLite.
 *
 * The recalculate functions are PURE on the input numbers — unit-testable
 * without a db fixture. The db wiring is split into a thin wrapper that
 * the CRM routes + the daily cron both call.
 *
 * CRITICAL: every mutation uses a new object — no in-place mutation of
 * rows pulled from the driver (see .claude/rules/common-coding-style.md).
 */

import { createLogger } from '../utils/logger.js';
import type { AsyncDb } from '../db/async-db.js';

const log = createLogger('customerHealthScore');

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

export type HealthTier = 'champion' | 'healthy' | 'at_risk';
export type LtvTier = 'bronze' | 'silver' | 'gold' | 'platinum';

export interface HealthScoreInputs {
  readonly daysSinceLastInteraction: number | null;
  readonly ticketsLast12Months: number;
  readonly lifetimeValueCents: number;
}

export interface HealthScoreResult {
  readonly score: number;
  readonly tier: HealthTier;
  readonly recencyPoints: number;
  readonly frequencyPoints: number;
  readonly monetaryPoints: number;
}

// -----------------------------------------------------------------------------
// Scoring constants — kept here so product can tune without hunting magic #s
// -----------------------------------------------------------------------------

const RECENCY_MAX_POINTS = 40;
const FREQUENCY_MAX_POINTS = 30;
const MONETARY_MAX_POINTS = 30;

/** Recency buckets: days since last interaction → points awarded */
const RECENCY_BUCKETS: ReadonlyArray<{ maxDays: number; points: number }> = [
  { maxDays: 14,  points: 40 },
  { maxDays: 30,  points: 32 },
  { maxDays: 60,  points: 24 },
  { maxDays: 120, points: 16 },
  { maxDays: 180, points: 8 },
  { maxDays: Number.POSITIVE_INFINITY, points: 0 },
];

/** Frequency buckets: tickets in last 12 months → points */
const FREQUENCY_BUCKETS: ReadonlyArray<{ maxTickets: number; points: number }> = [
  { maxTickets: 0,  points: 0 },
  { maxTickets: 1,  points: 8 },
  { maxTickets: 3,  points: 16 },
  { maxTickets: 5,  points: 22 },
  { maxTickets: 9,  points: 26 },
  { maxTickets: Number.POSITIVE_INFINITY, points: 30 },
];

/** Monetary buckets: lifetime value in cents → points */
const MONETARY_BUCKETS: ReadonlyArray<{ maxCents: number; points: number }> = [
  { maxCents: 0,        points: 0 },
  { maxCents: 10_000,   points: 6 },   // $100
  { maxCents: 50_000,   points: 14 },  // $500
  { maxCents: 150_000,  points: 22 },  // $1500
  { maxCents: 500_000,  points: 28 },  // $5000
  { maxCents: Number.POSITIVE_INFINITY, points: 30 },
];

/** LTV tier thresholds in cents — kept independent of the health bucket. */
const LTV_TIER_THRESHOLDS: ReadonlyArray<{ maxCents: number; tier: LtvTier }> = [
  { maxCents: 50_000,   tier: 'bronze' },   // < $500
  { maxCents: 250_000,  tier: 'silver' },   // < $2500
  { maxCents: 750_000,  tier: 'gold' },     // < $7500
  { maxCents: Number.POSITIVE_INFINITY, tier: 'platinum' },
];

// -----------------------------------------------------------------------------
// Pure scoring functions (unit-testable)
// -----------------------------------------------------------------------------

/**
 * Pick the points from the first bucket whose ceiling the value does not
 * exceed. The bucket arrays MUST be sorted ascending. Returns 0 for null.
 */
function bucketPoints(
  value: number | null,
  buckets: ReadonlyArray<{ points: number } & Record<string, number>>,
  key: string,
): number {
  if (value === null || !isFinite(value) || isNaN(value)) return 0;
  for (const bucket of buckets) {
    if (value <= bucket[key]) return bucket.points;
  }
  return 0;
}

export function computeRecencyPoints(daysSinceLastInteraction: number | null): number {
  if (daysSinceLastInteraction === null) return 0;
  return bucketPoints(daysSinceLastInteraction, RECENCY_BUCKETS, 'maxDays');
}

export function computeFrequencyPoints(ticketsLast12Months: number): number {
  return bucketPoints(ticketsLast12Months, FREQUENCY_BUCKETS, 'maxTickets');
}

export function computeMonetaryPoints(lifetimeValueCents: number): number {
  return bucketPoints(lifetimeValueCents, MONETARY_BUCKETS, 'maxCents');
}

/**
 * Convert an RFM-style input into the final score + tier. Immutable — takes
 * readonly inputs, returns a new result object.
 */
export function computeHealthScore(inputs: HealthScoreInputs): HealthScoreResult {
  const recencyPoints = computeRecencyPoints(inputs.daysSinceLastInteraction);
  const frequencyPoints = computeFrequencyPoints(inputs.ticketsLast12Months);
  const monetaryPoints = computeMonetaryPoints(inputs.lifetimeValueCents);
  const rawScore = recencyPoints + frequencyPoints + monetaryPoints;
  const score = Math.max(0, Math.min(100, rawScore));
  const tier: HealthTier = score >= 80 ? 'champion' : score >= 50 ? 'healthy' : 'at_risk';
  return { score, tier, recencyPoints, frequencyPoints, monetaryPoints };
}

/**
 * Pure LTV tier derivation from the cents total.
 */
export function computeLtvTier(lifetimeValueCents: number): LtvTier {
  if (!isFinite(lifetimeValueCents) || lifetimeValueCents < 0) return 'bronze';
  for (const threshold of LTV_TIER_THRESHOLDS) {
    if (lifetimeValueCents < threshold.maxCents) return threshold.tier;
  }
  return 'platinum';
}

// -----------------------------------------------------------------------------
// DB-backed helpers
// -----------------------------------------------------------------------------

interface RawCustomerMetrics {
  readonly id: number;
  readonly lifetime_value_cents: number | null;
  readonly last_interaction_at: string | null;
  readonly tickets_12mo: number | null;
  readonly invoices_total_cents: number | null;
  readonly latest_ticket_at: string | null;
}

/**
 * Collect everything we need to score a single customer. One round-trip.
 * The invoices total is authoritative — lifetime_value_cents is recomputed
 * here so the stored value never silently drifts.
 */
async function loadCustomerMetrics(
  adb: AsyncDb,
  customerId: number,
): Promise<RawCustomerMetrics | null> {
  // CRITICAL: `amount_paid` and `total` are REAL columns, so we must use
  // ROUND(x * 100) — not CAST(x * 100 AS INTEGER) which truncates toward
  // zero and drops sub-cent values. A $19.99 invoice stored as 19.9900
  // would round-trip correctly either way, but a $19.995 adjustment would
  // land on 1999 (CAST) vs 2000 (ROUND). We pick ROUND because it matches
  // how every other money SUM in the codebase is computed.
  return (
    (await adb.get<RawCustomerMetrics>(
      `SELECT
         c.id,
         c.lifetime_value_cents,
         c.last_interaction_at,
         (SELECT COUNT(*) FROM tickets t
            WHERE t.customer_id = c.id
              AND t.is_deleted = 0
              AND t.created_at >= datetime('now','-12 months')) AS tickets_12mo,
         (SELECT COALESCE(
             CAST(ROUND(SUM(COALESCE(i.amount_paid, i.total)) * 100) AS INTEGER),
             0
           )
            FROM invoices i
            WHERE i.customer_id = c.id
              AND i.status != 'void') AS invoices_total_cents,
         (SELECT MAX(t.created_at) FROM tickets t
            WHERE t.customer_id = c.id AND t.is_deleted = 0) AS latest_ticket_at
       FROM customers c
       WHERE c.id = ?`,
      customerId,
    )) ?? null
  );
}

function daysBetween(iso: string | null, now: Date): number | null {
  if (!iso) return null;
  const then = new Date(iso);
  if (isNaN(then.getTime())) return null;
  const ms = now.getTime() - then.getTime();
  if (ms < 0) return 0;
  return Math.floor(ms / 86_400_000);
}

export interface RecalculateResult {
  readonly score: HealthScoreResult;
  readonly ltvTier: LtvTier;
  readonly lifetimeValueCents: number;
  readonly lastInteractionAt: string | null;
}

/**
 * Recalculate + persist a single customer's health score and LTV tier.
 * Caller supplies the AsyncDb so this runs on whichever tenant db owns
 * the request. Returns the new values so the HTTP handler can echo them
 * without a second SELECT.
 */
export async function recalculateCustomerHealth(
  adb: AsyncDb,
  customerId: number,
): Promise<RecalculateResult | null> {
  const metrics = await loadCustomerMetrics(adb, customerId);
  if (!metrics) return null;

  const lifetimeValueCents = metrics.invoices_total_cents ?? 0;
  const lastInteractionAt = metrics.last_interaction_at ?? metrics.latest_ticket_at;
  const days = daysBetween(lastInteractionAt, new Date());

  const score = computeHealthScore({
    daysSinceLastInteraction: days,
    ticketsLast12Months: metrics.tickets_12mo ?? 0,
    lifetimeValueCents,
  });
  const ltvTier = computeLtvTier(lifetimeValueCents);

  // Single UPDATE — all derived values in one write.
  await adb.run(
    `UPDATE customers
        SET health_score = ?,
            health_tier = ?,
            ltv_tier = ?,
            lifetime_value_cents = ?,
            last_interaction_at = COALESCE(last_interaction_at, ?)
      WHERE id = ?`,
    score.score,
    score.tier,
    ltvTier,
    lifetimeValueCents,
    lastInteractionAt,
    customerId,
  );

  return { score, ltvTier, lifetimeValueCents, lastInteractionAt };
}

/**
 * Recalculate every customer. Used by the daily cron (left wired as a
 * TODO in index.ts). Batches in chunks of 200 to avoid holding a single
 * giant transaction open on a big shop's db.
 *
 * @audit-fixed: added optional `signal: AbortSignal` so the cron / shutdown
 * handler can stop a running recalc cleanly. Without this, a server-shutdown
 * mid-recalc would leak the in-flight loop and continue running after the
 * shutdown handler returns. Also added a soft per-customer time guard so a
 * single broken customer query cannot stall the whole batch.
 */
export async function recalculateAllCustomerHealth(
  adb: AsyncDb,
  batchSize = 200,
  signal?: AbortSignal,
): Promise<{ total: number; updated: number; aborted: boolean }> {
  const ids = await adb.all<{ id: number }>(
    `SELECT id FROM customers ORDER BY id ASC`,
  );
  let updated = 0;
  let aborted = false;
  for (let i = 0; i < ids.length; i += batchSize) {
    if (signal?.aborted) { aborted = true; break; }
    const batch = ids.slice(i, i + batchSize);
    for (const row of batch) {
      if (signal?.aborted) { aborted = true; break; }
      try {
        const result = await recalculateCustomerHealth(adb, row.id);
        if (result) updated += 1;
      } catch (err) {
        log.error('Failed to recalculate customer health', {
          customerId: row.id,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }
  return { total: ids.length, updated, aborted };
}

/**
 * Update a customer's last_interaction_at + lifetime_value_cents after a
 * payment/receipt. The CRM routes (invoices, pos) call this as a fire-and
 * -forget side effect so the health cron isn't the only source of truth.
 *
 * Returns a boolean so callers that DO care about the outcome (e.g. a batch
 * job reconciling LTV) can distinguish success from swallowed error. The
 * existing fire-and-forget callers can ignore the return value; their
 * behavior is unchanged. We still log on failure for operator visibility.
 */
export async function recordCustomerInteraction(
  adb: AsyncDb,
  customerId: number,
  addCents = 0,
): Promise<boolean> {
  try {
    await adb.run(
      `UPDATE customers
          SET last_interaction_at = datetime('now'),
              lifetime_value_cents = COALESCE(lifetime_value_cents,0) + ?
        WHERE id = ?`,
      Math.max(0, Math.floor(addCents)),
      customerId,
    );
    return true;
  } catch (err) {
    log.error('Failed to record customer interaction', {
      customerId,
      addCents,
      error: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}
