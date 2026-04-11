import { Request, Response, NextFunction } from 'express';

interface CachedResponse {
  readonly body: unknown;
  readonly statusCode: number;
  readonly timestamp: number;
}

const store = new Map<string, CachedResponse>();

const TTL_MS = 5 * 60 * 1000; // 5 minutes
// SEC-H14: Cap the idempotency store to prevent unbounded memory growth.
// If the store exceeds MAX_ENTRIES, purge entries older than 1 hour.
// If still over the limit after purge, clear the oldest entries until within bounds.
const MAX_ENTRIES = 10_000;
const PURGE_AGE_MS = 60 * 60 * 1000; // 1 hour

function enforceStoreSizeCap(): void {
  if (store.size <= MAX_ENTRIES) return;
  const purgeCutoff = Date.now() - PURGE_AGE_MS;
  for (const [key, entry] of store) {
    if (entry.timestamp < purgeCutoff) store.delete(key);
  }
  // If still over limit, remove oldest entries
  if (store.size > MAX_ENTRIES) {
    const sorted = [...store.entries()].sort((a, b) => a[1].timestamp - b[1].timestamp);
    const toRemove = store.size - MAX_ENTRIES;
    for (let i = 0; i < toRemove; i++) {
      store.delete(sorted[i][0]);
    }
  }
}

// Cleanup expired entries every 60 seconds
setInterval(() => {
  const cutoff = Date.now() - TTL_MS;
  for (const [key, entry] of store) {
    if (entry.timestamp < cutoff) store.delete(key);
  }
  // Also enforce the size cap during periodic cleanup
  enforceStoreSizeCap();
}, 60_000).unref();

/**
 * Idempotency middleware for POST endpoints.
 * If client sends `X-Idempotency-Key` header, duplicate requests within 5 minutes
 * return the cached response instead of re-executing.
 */
export function idempotent(req: Request, res: Response, next: NextFunction): void {
  const key = req.headers['x-idempotency-key'] as string | undefined;
  if (!key) {
    next();
    return;
  }

  // @audit-fixed: Reject absurdly large idempotency keys so an attacker can't
  // use this header as an unbounded input that becomes part of every Map key.
  if (key.length > 256) {
    res.status(400).json({ success: false, message: 'X-Idempotency-Key too long' });
    return;
  }
  // @audit-fixed: Reject control chars / CRLF inside the key so it can't be
  // used to poison audit logs that include the scoped key.
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1F\x7F]/.test(key)) {
    res.status(400).json({ success: false, message: 'X-Idempotency-Key contains invalid characters' });
    return;
  }

  // Scope key to user + endpoint to prevent cross-user collisions
  const scopedKey = `${req.user?.id ?? 'anon'}:${req.originalUrl}:${key}`;

  const existing = store.get(scopedKey);
  if (existing) {
    res.status(existing.statusCode).json(existing.body);
    return;
  }

  // Monkey-patch res.json to capture the response
  const originalJson = res.json.bind(res);
  // @audit-fixed: Track whether we've already cached so a second res.json()
  // call doesn't re-run enforceStoreSizeCap or overwrite the cached entry
  // with a later response (e.g. error-after-success race).
  let cached = false;
  res.json = (body: unknown) => {
    if (!cached) {
      cached = true;
      store.set(scopedKey, {
        body,
        statusCode: res.statusCode,
        timestamp: Date.now(),
      });
      // SEC-H14: Enforce size cap after inserting a new entry
      enforceStoreSizeCap();
    }
    return originalJson(body);
  };

  next();
}
