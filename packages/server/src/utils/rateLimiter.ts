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

/** Check if the key is within the allowed attempt count for the given window. */
export function checkWindowRate(
  db: Database.Database, category: string, key: string,
  maxAttempts: number, windowMs: number,
): boolean {
  const now = Date.now();
  const row = db.prepare(
    'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?'
  ).get(category, key) as RateLimitEntry | undefined;

  if (!row) return true;

  // Window expired — clean up and allow
  if (now - row.first_attempt > windowMs) {
    db.prepare('DELETE FROM rate_limits WHERE category = ? AND key = ?').run(category, key);
    return true;
  }

  return row.count < maxAttempts;
}

/** Record a failed attempt for window-based rate limiting. */
export function recordWindowFailure(
  db: Database.Database, category: string, key: string,
  windowMs: number,
): void {
  const now = Date.now();
  const row = db.prepare(
    'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?'
  ).get(category, key) as RateLimitEntry | undefined;

  if (!row || now - row.first_attempt > windowMs) {
    db.prepare(`
      INSERT OR REPLACE INTO rate_limits (category, key, count, first_attempt)
      VALUES (?, ?, 1, ?)
    `).run(category, key, now);
  } else {
    db.prepare(
      'UPDATE rate_limits SET count = count + 1 WHERE category = ? AND key = ?'
    ).run(category, key);
  }
}

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

/** Record a TOTP failure with lockout window. */
export function recordLockoutFailure(
  db: Database.Database, category: string, key: string,
  lockoutMs: number,
): void {
  const now = Date.now();
  const row = db.prepare(
    'SELECT count, locked_until FROM rate_limits WHERE category = ? AND key = ?'
  ).get(category, key) as RateLimitEntry | undefined;

  if (!row) {
    db.prepare(`
      INSERT INTO rate_limits (category, key, count, first_attempt, locked_until)
      VALUES (?, ?, 1, ?, ?)
    `).run(category, key, now, now + lockoutMs);
  } else {
    db.prepare(
      'UPDATE rate_limits SET count = count + 1 WHERE category = ? AND key = ?'
    ).run(category, key);
  }
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
  const now = Date.now();
  const row = db.prepare(
    'SELECT count, first_attempt FROM rate_limits WHERE category = ? AND key = ?'
  ).get(category, key) as RateLimitEntry | undefined;

  // Window empty or expired — start a fresh window at count = 1 and allow.
  if (!row || now - row.first_attempt > windowMs) {
    db.prepare(`
      INSERT OR REPLACE INTO rate_limits (category, key, count, first_attempt)
      VALUES (?, ?, 1, ?)
    `).run(category, key, now);
    return { allowed: true, retryAfterSeconds: 0 };
  }

  // Over the cap — reject and tell the caller when to try again.
  if (row.count >= maxAttempts) {
    const retryAfterSeconds = Math.max(1, Math.ceil((row.first_attempt + windowMs - now) / 1000));
    return { allowed: false, retryAfterSeconds };
  }

  // Within the window and under the cap — increment and allow.
  db.prepare(
    'UPDATE rate_limits SET count = count + 1 WHERE category = ? AND key = ?'
  ).run(category, key);
  return { allowed: true, retryAfterSeconds: 0 };
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
