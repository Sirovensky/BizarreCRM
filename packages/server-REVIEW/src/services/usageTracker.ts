import fs from 'fs';
import path from 'path';
import { getMasterDb } from '../db/master-connection.js';
import { config } from '../config.js';

/**
 * Returns the current "usage bucket" key for per-month counters that still
 * want a calendar-month shape (SMS totals, storage snapshots, etc.).
 *
 * NOTE: Ticket usage is tracked via a rolling 30-day window now (see
 * `getTicketsCreatedLast30Days` below) — this helper is ONLY for counters
 * that legitimately reset on the 1st of each month. Don't use it for tier
 * enforcement on tickets.
 */
function getCurrentMonth(): string {
  return new Date().toISOString().slice(0, 7); // YYYY-MM
}

/**
 * Increment the ticket count for the current calendar-month bucket.
 *
 * @audit-fixed: #19 — the *limit check* uses a rolling 30-day window
 * (see `getTicketsCreatedLast30Days`), but we still record per-month buckets
 * here so that historical reporting and the master-admin billing dashboard
 * keep their YYYY-MM roll-up. The counter INSERTed here is ONLY used by
 * legacy reporting — the Free-tier cap is enforced by summing the last 30
 * days of buckets at check time, so a user cannot create 50 tickets on
 * Jan 31 and 50 more on Feb 1. Rolling window = both of those fall inside
 * the same 30-day evaluation.
 *
 * Called after successful ticket creation.
 */
export function incrementTicketCount(tenantId: number | undefined): void {
  if (!config.multiTenant || !tenantId) return;
  const masterDb = getMasterDb();
  if (!masterDb) return;
  const month = getCurrentMonth();
  masterDb.prepare(`
    INSERT INTO tenant_usage (tenant_id, month, tickets_created)
    VALUES (?, ?, 1)
    ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
  `).run(tenantId, month);
}

/**
 * Increment the SMS sent count for the current month.
 *
 * @audit-fixed: callers must ONLY invoke this AFTER the underlying provider
 * confirms `success === true && simulated !== true`. Previously some call
 * sites incremented unconditionally and double-counted on retry / fallback,
 * which inflated tenant usage and could push them past their plan limit
 * artificially. The provider abstraction now exposes the `simulated` flag —
 * route handlers must guard with that flag before calling this. Documented
 * here so the next caller doesn't repeat the mistake.
 */
export function incrementSmsCount(tenantId: number | undefined): void {
  if (!config.multiTenant || !tenantId) return;
  const masterDb = getMasterDb();
  if (!masterDb) return;
  const month = getCurrentMonth();
  masterDb.prepare(`
    INSERT INTO tenant_usage (tenant_id, month, sms_sent)
    VALUES (?, ?, 1)
    ON CONFLICT(tenant_id, month) DO UPDATE SET sms_sent = sms_sent + 1
  `).run(tenantId, month);
}

/**
 * Count the tickets a tenant has created in the last rolling 30 days by
 * summing the per-month buckets that overlap the window.
 *
 * @audit-fixed: #19 — Free tier 50-ticket cap used to be enforced per
 * calendar month using `tenant_usage.month = YYYY-MM`, which meant a tenant
 * could create 50 tickets on Jan 31 and 50 more on Feb 1 (100 in 2 days)
 * without tripping the limit. We now compute a rolling window. Because
 * `tenant_usage` is bucketed per month (for billing/reporting), we take the
 * two buckets that touch the last 30 days (current month + previous month)
 * and sum them. This slightly over-counts on month boundaries (the prior
 * month bucket may include days older than 30) but always errs on the side
 * of the tenant being *blocked sooner*, which is the correct bias for a
 * tier cap. Exact accounting would require a per-ticket table, which we
 * intentionally avoid (cross-DB join cost).
 *
 * For a more precise accounting when the caller has the tenant DB in hand,
 * query the tenant's `tickets` table directly with
 * `WHERE created_at >= datetime('now', '-30 days')`. Two inline reservations
 * in tickets.routes.ts do this already — this helper is the master-DB
 * fallback used when we can only see the aggregate counters.
 */
export function getTicketsCreatedLast30Days(tenantId: number): number {
  if (!config.multiTenant || !tenantId) return 0;
  const masterDb = getMasterDb();
  if (!masterDb) return 0;

  const now = new Date();
  const currentMonth = now.toISOString().slice(0, 7); // YYYY-MM
  const prev = new Date(now);
  prev.setMonth(prev.getMonth() - 1);
  const prevMonth = prev.toISOString().slice(0, 7);

  const rows = masterDb.prepare(
    'SELECT COALESCE(SUM(tickets_created), 0) AS total FROM tenant_usage WHERE tenant_id = ? AND month IN (?, ?)'
  ).get(tenantId, currentMonth, prevMonth) as { total: number } | undefined;

  return rows?.total ?? 0;
}

/**
 * Get usage data for a tenant.
 *
 * @audit-fixed: #19 — `tickets_created` here now reflects the ROLLING 30-DAY
 * count (summed from per-month buckets), not the calendar-month count, so
 * the `/account/usage` UI, limit checks, and upgrade prompts all agree on
 * what "this period" means. `sms_sent`, `storage_bytes`, and `active_users`
 * are still the current calendar-month figures because those counters are
 * legitimately monthly (provider billing windows, storage snapshot, MAU).
 */
export function getUsage(tenantId: number): { tickets_created: number; sms_sent: number; storage_bytes: number; active_users: number } | null {
  const masterDb = getMasterDb();
  if (!masterDb) return null;
  const month = getCurrentMonth();
  const row = masterDb.prepare(
    'SELECT sms_sent, storage_bytes, active_users FROM tenant_usage WHERE tenant_id = ? AND month = ?'
  ).get(tenantId, month) as { sms_sent: number; storage_bytes: number; active_users: number } | undefined;

  const ticketsCreatedRolling = getTicketsCreatedLast30Days(tenantId);

  return {
    tickets_created: ticketsCreatedRolling,
    sms_sent: row?.sms_sent ?? 0,
    storage_bytes: row?.storage_bytes ?? 0,
    active_users: row?.active_users ?? 0,
  };
}

/** Calculate the total size in bytes of all files under a directory recursively. */
export function calculateDirectorySize(dirPath: string): number {
  if (!fs.existsSync(dirPath)) return 0;
  let total = 0;
  try {
    const entries = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(dirPath, entry.name);
      if (entry.isDirectory()) {
        total += calculateDirectorySize(full);
      } else if (entry.isFile()) {
        try {
          total += fs.statSync(full).size;
        } catch { /* file removed mid-walk */ }
      }
    }
  } catch (err) {
    console.warn(`[usageTracker] Failed to calculate directory size for ${dirPath}:`, (err as Error).message);
  }
  return total;
}

/** Add bytes to the tenant's storage usage counter (atomic). */
export function incrementStorageBytes(tenantId: number | undefined, bytes: number): void {
  if (!config.multiTenant || !tenantId || bytes <= 0) return;
  const masterDb = getMasterDb();
  if (!masterDb) return;
  const month = getCurrentMonth();
  masterDb.prepare(`
    INSERT INTO tenant_usage (tenant_id, month, storage_bytes)
    VALUES (?, ?, ?)
    ON CONFLICT(tenant_id, month) DO UPDATE SET storage_bytes = storage_bytes + ?
  `).run(tenantId, month, bytes, bytes);
}

/** Decrement bytes from the tenant's storage usage counter. Clamps at zero so the counter
 *  never goes negative even if a delete races with the daily recalc. */
export function decrementStorageBytes(tenantId: number | undefined, bytes: number): void {
  if (!config.multiTenant || !tenantId || bytes <= 0) return;
  const masterDb = getMasterDb();
  if (!masterDb) return;
  const month = getCurrentMonth();
  masterDb.prepare(`
    UPDATE tenant_usage
    SET storage_bytes = MAX(0, storage_bytes - ?)
    WHERE tenant_id = ? AND month = ?
  `).run(bytes, tenantId, month);
}

/** Set the tenant's storage usage to a specific value (used after recomputing from disk). */
export function setStorageBytes(tenantId: number | undefined, bytes: number): void {
  if (!config.multiTenant || !tenantId) return;
  const masterDb = getMasterDb();
  if (!masterDb) return;
  const month = getCurrentMonth();
  masterDb.prepare(`
    INSERT INTO tenant_usage (tenant_id, month, storage_bytes)
    VALUES (?, ?, ?)
    ON CONFLICT(tenant_id, month) DO UPDATE SET storage_bytes = ?
  `).run(tenantId, month, bytes, bytes);
}

/** Atomic check + reserve. Returns true if reservation succeeded, false if over limit.
 *  Uses a single SQLite transaction so concurrent uploads can't both pass the check.
 *  Use this in upload handlers BEFORE writing the file (or to roll back if write fails). */
export function reserveStorage(tenantId: number | undefined, bytes: number, limitMb: number | null): boolean {
  if (!config.multiTenant || !tenantId) return true;       // single-tenant: always allow
  if (limitMb == null) return true;                         // unlimited (Pro)
  if (bytes <= 0) return true;
  const masterDb = getMasterDb();
  if (!masterDb) return true;                               // master DB unavailable: don't block
  const month = getCurrentMonth();
  const limitBytes = limitMb * 1024 * 1024;

  const reservation = masterDb.transaction((): boolean => {
    const usage = masterDb.prepare(
      'SELECT storage_bytes FROM tenant_usage WHERE tenant_id = ? AND month = ?'
    ).get(tenantId, month) as { storage_bytes: number } | undefined;
    const current = usage?.storage_bytes ?? 0;
    if (current + bytes > limitBytes) {
      return false;
    }
    masterDb.prepare(`
      INSERT INTO tenant_usage (tenant_id, month, storage_bytes)
      VALUES (?, ?, ?)
      ON CONFLICT(tenant_id, month) DO UPDATE SET storage_bytes = storage_bytes + ?
    `).run(tenantId, month, bytes, bytes);
    return true;
  })();

  return reservation;
}

/**
 * Atomic check + reserve for the rolling 30-day ticket limit.
 *
 * @audit-fixed: #19 — companion to `getTicketsCreatedLast30Days`. Use this
 * from ticket-creation handlers that want to enforce the Free-tier cap
 * without walking the tenant DB. Returns `{ allowed, current, limit }`; if
 * not allowed, caller should respond 403 with `upgrade_required: true` and
 * NOT call `incrementTicketCount` (the reservation pre-increments the
 * current-month bucket on success, so the next read will see it).
 *
 * This is the master-DB-side enforcement. Routes that already have the
 * tenant DB open can continue using a direct `SELECT COUNT(*) FROM tickets
 * WHERE created_at >= datetime('now', '-30 days')` if they prefer exact
 * per-ticket accounting — both paths agree within a one-month-bucket
 * rounding margin.
 */
export function reserveTicketCreation(
  tenantId: number | undefined,
  limit: number | null,
): { allowed: boolean; current: number; limit: number | null } {
  if (!config.multiTenant || !tenantId) return { allowed: true, current: 0, limit };
  if (limit == null) return { allowed: true, current: 0, limit };                // unlimited (Pro)
  const masterDb = getMasterDb();
  if (!masterDb) return { allowed: true, current: 0, limit };                    // master DB unavailable: don't block

  const now = new Date();
  const currentMonth = now.toISOString().slice(0, 7);
  const prev = new Date(now);
  prev.setMonth(prev.getMonth() - 1);
  const prevMonth = prev.toISOString().slice(0, 7);

  const reservation = masterDb.transaction((): { allowed: boolean; current: number } => {
    const row = masterDb.prepare(
      'SELECT COALESCE(SUM(tickets_created), 0) AS total FROM tenant_usage WHERE tenant_id = ? AND month IN (?, ?)'
    ).get(tenantId, currentMonth, prevMonth) as { total: number } | undefined;
    const current = row?.total ?? 0;
    if (current >= limit) {
      return { allowed: false, current };
    }
    masterDb.prepare(`
      INSERT INTO tenant_usage (tenant_id, month, tickets_created)
      VALUES (?, ?, 1)
      ON CONFLICT(tenant_id, month) DO UPDATE SET tickets_created = tickets_created + 1
    `).run(tenantId, currentMonth);
    return { allowed: true, current: current + 1 };
  })();

  return { allowed: reservation.allowed, current: reservation.current, limit };
}

/** Check if adding `bytes` would exceed the tenant's storage limit. Returns true if over.
 *  Returns false if no limit (unlimited) or in single-tenant mode.
 *
 *  PREFER `reserveStorage()` over `wouldExceedStorageLimit() + incrementStorageBytes()` —
 *  this function is non-atomic and is left in for backward compatibility / read-only checks. */
export function wouldExceedStorageLimit(tenantId: number | undefined, addBytes: number, limitMb: number | null): boolean {
  if (!config.multiTenant || !tenantId || limitMb == null) return false;
  const masterDb = getMasterDb();
  if (!masterDb) return false;
  const month = getCurrentMonth();
  const usage = masterDb.prepare(
    'SELECT storage_bytes FROM tenant_usage WHERE tenant_id = ? AND month = ?'
  ).get(tenantId, month) as { storage_bytes: number } | undefined;
  const currentBytes = usage?.storage_bytes ?? 0;
  const limitBytes = limitMb * 1024 * 1024;
  return (currentBytes + addBytes) > limitBytes;
}
