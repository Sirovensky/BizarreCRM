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
// Cleanup — call periodically to purge expired entries
// ---------------------------------------------------------------------------

export function cleanupExpiredEntries(db: Database.Database, windowMs: number): void {
  const cutoff = Date.now() - windowMs;
  db.prepare(
    'DELETE FROM rate_limits WHERE first_attempt < ? AND (locked_until IS NULL OR locked_until < ?)'
  ).run(cutoff, Date.now());
}
