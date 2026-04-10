import fs from 'fs';
import path from 'path';
import { getMasterDb } from '../db/master-connection.js';
import { config } from '../config.js';

function getCurrentMonth(): string {
  return new Date().toISOString().slice(0, 7); // YYYY-MM
}

/** Increment the ticket count for the current month. Called after successful ticket creation. */
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

/** Increment the SMS sent count for the current month. */
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

/** Get usage data for a tenant for the current month. */
export function getUsage(tenantId: number): { tickets_created: number; sms_sent: number; storage_bytes: number; active_users: number } | null {
  const masterDb = getMasterDb();
  if (!masterDb) return null;
  const month = getCurrentMonth();
  const row = masterDb.prepare(
    'SELECT tickets_created, sms_sent, storage_bytes, active_users FROM tenant_usage WHERE tenant_id = ? AND month = ?'
  ).get(tenantId, month) as { tickets_created: number; sms_sent: number; storage_bytes: number; active_users: number } | undefined;
  return row || { tickets_created: 0, sms_sent: 0, storage_bytes: 0, active_users: 0 };
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
