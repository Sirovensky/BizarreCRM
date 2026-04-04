import { Request, Response, NextFunction } from 'express';

interface CachedResponse {
  readonly body: unknown;
  readonly statusCode: number;
  readonly timestamp: number;
}

const store = new Map<string, CachedResponse>();

const TTL_MS = 5 * 60 * 1000; // 5 minutes

// Cleanup expired entries every 60 seconds
setInterval(() => {
  const cutoff = Date.now() - TTL_MS;
  for (const [key, entry] of store) {
    if (entry.timestamp < cutoff) store.delete(key);
  }
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

  // Scope key to user + endpoint to prevent cross-user collisions
  const scopedKey = `${req.user?.id ?? 'anon'}:${req.originalUrl}:${key}`;

  const existing = store.get(scopedKey);
  if (existing) {
    res.status(existing.statusCode).json(existing.body);
    return;
  }

  // Monkey-patch res.json to capture the response
  const originalJson = res.json.bind(res);
  res.json = (body: unknown) => {
    store.set(scopedKey, {
      body,
      statusCode: res.statusCode,
      timestamp: Date.now(),
    });
    return originalJson(body);
  };

  next();
}
