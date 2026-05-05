/**
 * SQLite-backed rate limiter — persists across server restarts.
 * Uses better-sqlite3 (synchronous) for zero-latency checks in auth hot paths.
 */
import type Database from 'better-sqlite3';

interface RateLimitEntry {
  count: number;
  first_attempt: number;
  locked_until: number | null;
}

// ---------------------------------------------------------------------------
// Window-based rate limiting (login IP, login user, PIN)
// ---------------------------------------------------------------------------

/**
 * Check if the key is within the allowed attempt count for the given window.
 *
 * SCAN-1065: the SELECT and follow-up `recordWindowFailure` INSERT (at the
 * caller) were separate statements, so two concurrent writers could both
 * see count=N, both write N+1, and both pass the check. Wrapping the
 * SELECT (+ optional expired-window DELETE) in a transaction serialises
 * the read against other writers on the same connection. Callers that
 * want a single atomic check-and-consume should prefer `consumeWindowRate`.
 */
export function checkWindowRate(
  db: Database.Database, category: string, key: string,
  maxAttempts: number, windowMs: number,
): boolean {
  const now = Date.now();
  const tx = db.transaction((cat: string, k: string, max: number, win: number): boolean => {
    const row = db.prepare(
      'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?'
    ).get(cat, k) as RateLimitEntry | undefined;

    if (!row) return true;

    // Window expired — clean up and allow
    if (now - row.first_attempt > win) {
      db.prepare('DELETE FROM rate_limits WHERE category = ? AND key = ?').run(cat, k);
      return true;
    }

    return row.count < max;
  });
  return tx(category, key, maxAttempts, windowMs);
}

/**
 * Record an attempt for window-based rate limiting.
 *
 * @deprecated Prefer `recordWindowAttempt` or `consumeWindowRate`. The
 *   "Failure" suffix was a misnomer — this function counts every attempt
 *   (successful or not) toward the window cap, and does NOT gate on the
 *   existing count (see SCAN-1065 about the read-then-increment TOCTOU).
 *   This export exists for backwards compatibility with 15+ route imports
 *   that haven't been migrated yet.
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars -- kept for callers
export function recordWindowFailure(
  db: Database.Database, category: string, key: string,
  windowMs: number,
): void {
  // @audit-fixed: Wrap the read-modify-write in a transaction so concurrent
  // failed attempts cannot both see the same row and collapse the increment.
  // better-sqlite3 transactions serialize writers on a single connection and
  // use DEFERRED by default — good enough for a single-process CRM.
  const tx = db.transaction((cat: string, k: string, win: number) => {
    const now = Date.now();
    const row = db.prepare(
      'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?'
    ).get(cat, k) as RateLimitEntry | undefined;

    if (!row || now - row.first_attempt > win) {
      db.prepare(`
        INSERT OR REPLACE INTO rate_limits (category, key, count, first_attempt)
        VALUES (?, ?, 1, ?)
      `).run(cat, k, now);
    } else {
      db.prepare(
        'UPDATE rate_limits SET count = count + 1 WHERE category = ? AND key = ?'
      ).run(cat, k);
    }
  });
  tx(category, key, windowMs);
}

/**
 * Record an attempt (success or failure) for window-based rate limiting.
 * Alias for recordWindowFailure with a name that matches the actual behavior:
 * every call to this function counts toward the per-window cap.
 */
export const recordWindowAttempt = recordWindowFailure;

/** Clear rate limit entries for a key (e.g., on successful login). */
export function clearRateLimit(db: Database.Database, category: string, key: string): void {
  db.prepare('DELETE FROM rate_limits WHERE category = ? AND key = ?').run(category, key);
}

// ---------------------------------------------------------------------------
// Lockout-based rate limiting (TOTP)
// ---------------------------------------------------------------------------

/** Check if TOTP attempts are within limits (lockout-style). */
export function checkLockoutRate(
  db: Database.Database, category: string, key: string,
  maxAttempts: number,
): boolean {
  const now = Date.now();
  const row = db.prepare(
    'SELECT count, locked_until FROM rate_limits WHERE category = ? AND key = ?'
  ).get(category, key) as RateLimitEntry | undefined;

  if (!row) return true;

  // Lockout expired — clean up and allow
  if (row.locked_until && now > row.locked_until) {
    db.prepare('DELETE FROM rate_limits WHERE category = ? AND key = ?').run(category, key);
    return true;
  }

  return row.count < maxAttempts;
}

/**
 * Record a TOTP failure with lockout window.
 *
 * SEC-M23: previously did SELECT → branch on row existence → INSERT or
 * UPDATE. Two concurrent failures (two tabs racing the same TOTP prompt)
 * could both read row=undefined and attempt to INSERT; second one hit
 * UNIQUE(category,key) and threw. Or both saw the same count and the
 * increment got counted only once due to the separate UPDATE.
 *
 * Atomic path: `INSERT ... ON CONFLICT DO UPDATE` in a single statement.
 * The conflict UPDATE bumps the existing count; the INSERT creates the
 * first-attempt row with count=1. Either way the failure is recorded
 * exactly once without a read-check-write race.
 */
export function recordLockoutFailure(
  db: Database.Database, category: string, key: string,
  lockoutMs: number,
): void {
  const now = Date.now();
  db.prepare(`
    INSERT INTO rate_limits (category, key, count, first_attempt, locked_until)
    VALUES (?, ?, 1, ?, ?)
    ON CONFLICT(category, key) DO UPDATE SET count = count + 1
  `).run(category, key, now, now + lockoutMs);
}

// ---------------------------------------------------------------------------
// Consume-style helper — window rate limit with atomic check-and-record
// ---------------------------------------------------------------------------

export interface ConsumeResult {
  /** True when the attempt is allowed (and has been counted). */
  allowed: boolean;
  /** Seconds until the window resets — only populated when allowed === false. */
  retryAfterSeconds: number;
}

/**
 * Post-enrichment audit §9: shared helper used by route handlers for
 * write-path throttling (bulk SMS, dunning run-now, bench defect POST,
 * public payment links, etc.).
 *
 * Atomically checks whether `key` has exceeded `maxAttempts` in the last
 * `windowMs`, and if allowed records the attempt immediately. Returns a
 * structured result instead of throwing so callers can decide whether to
 * raise an AppError, audit the rejection, or fail silently.
 *
 * Keyed-by-`${category}:${key}` — category separates feature namespaces
 * (e.g. `inbox_bulk_send`, `bench_defect_report`), key distinguishes
 * identity within a namespace (userId, IP, or both).
 */
export function consumeWindowRate(
  db: Database.Database,
  category: string,
  key: string,
  maxAttempts: number,
  windowMs: number,
): ConsumeResult {
  // @audit-fixed: Serialize read-modify-write under a transaction so two
  // concurrent callers can't both observe count == maxAttempts-1 and each
  // increment to maxAttempts, doubling the real allowed throughput.
  const tx = db.transaction((cat: string, k: string, max: number, win: number): ConsumeResult => {
    const now = Date.now();
    const row = db.prepare(
      'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?'
    ).get(cat, k) as RateLimitEntry | undefined;

    // Window empty or expired — start a fresh window at count = 1 and allow.
    if (!row || now - row.first_attempt > win) {
      db.prepare(`
        INSERT OR REPLACE INTO rate_limits (category, key, count, first_attempt)
        VALUES (?, ?, 1, ?)
      `).run(cat, k, now);
      return { allowed: true, retryAfterSeconds: 0 };
    }

    // Over the cap — reject and tell the caller when to try again.
    if (row.count >= max) {
      const retryAfterSeconds = Math.max(1, Math.ceil((row.first_attempt + win - now) / 1000));
      return { allowed: false, retryAfterSeconds };
    }

    // Within the window and under the cap — increment and allow.
    db.prepare(
      'UPDATE rate_limits SET count = count + 1 WHERE category = ? AND key = ?'
    ).run(cat, k);
    return { allowed: true, retryAfterSeconds: 0 };
  });
  return tx(category, key, maxAttempts, windowMs);
}

// ---------------------------------------------------------------------------
// Cleanup — call periodically to purge expired entries
// ---------------------------------------------------------------------------

export function cleanupExpiredEntries(db: Database.Database, windowMs: number): void {
  const cutoff = Date.now() - windowMs;
  db.prepare(
    'DELETE FROM rate_limits WHERE first_attempt < ? AND (locked_until IS NULL OR locked_until < ?)'
  ).run(cutoff, Date.now());
}
