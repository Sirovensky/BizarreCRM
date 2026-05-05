// SEC-H55: coalescing helper for `customer_viewed` audit rows.
//
// Viewing a customer (single GET /:id or a page of list-with-stats) is
// unavoidably bursty — a staff member flipping between a detail page and the
// list, or auto-refreshing a dashboard, would otherwise write one audit row
// per keystroke. That floods `audit_logs` without adding forensic value.
//
// The coalescing window is 5 minutes per (user, kind, dedupe-key) tuple:
// repeated views inside the window are skipped; the next view outside the
// window writes a fresh row. In-memory Map — per-process. A restart drops
// the window (acceptable: the first post-restart view always writes), and
// multi-process deployments would each keep their own window (acceptable:
// the worst case is N rows per window across N processes, not N-per-view).
//
// Entries self-evict on access; a tiny periodic sweep caps Map size so a
// long-running process cannot retain state for users who never return.

const COALESCE_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
const MAX_ENTRIES = 5000; // safety cap; sweeps once over this

type Key = string;

const lastAuditAt: Map<Key, number> = new Map();

function sweepIfOverCap(now: number): void {
  if (lastAuditAt.size <= MAX_ENTRIES) return;
  // Evict anything already outside the window; if still over cap, delete the
  // oldest half by insertion order (Map preserves insertion order in JS).
  for (const [k, ts] of lastAuditAt) {
    if (now - ts > COALESCE_WINDOW_MS) lastAuditAt.delete(k);
  }
  if (lastAuditAt.size > MAX_ENTRIES) {
    const toDrop = Math.floor(lastAuditAt.size / 2);
    let i = 0;
    for (const k of lastAuditAt.keys()) {
      if (i++ >= toDrop) break;
      lastAuditAt.delete(k);
    }
  }
}

/**
 * Returns true when the caller should write the audit row, false when the
 * same key was already audited inside the coalescing window.
 *
 * The key shape is `${userId}:${kind}:${dedupeKey}`:
 *  - userId  — numeric user id (or 'anon' for unauthenticated surfaces).
 *  - kind    — 'get-by-id' | 'list-with-stats'
 *  - dedupe  — customer_id for single-view; a filter+offset fingerprint
 *              for list scans so re-fetching the same page coalesces but
 *              scrolling to a new page does not.
 */
export function shouldAuditCustomerView(key: Key, now: number = Date.now()): boolean {
  const prev = lastAuditAt.get(key);
  if (prev !== undefined && now - prev < COALESCE_WINDOW_MS) {
    return false;
  }
  lastAuditAt.set(key, now);
  sweepIfOverCap(now);
  return true;
}

/** Test-only reset hook so unit tests can scope the Map per-case. */
export function __resetCustomerViewAuditCacheForTests(): void {
  lastAuditAt.clear();
}
