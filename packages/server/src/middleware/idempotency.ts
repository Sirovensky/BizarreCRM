/**
 * Idempotency middleware — SEC-H71
 *
 * Stores idempotency keys in the per-tenant SQLite table `idempotency_keys`
 * (migration 112) instead of an in-memory Map.  This survives process restarts
 * and works correctly across multiple server processes sharing the same DB.
 *
 * Protocol:
 *   1. Client sends `X-Idempotency-Key: <opaque string>` on a POST request.
 *   2. First request for a (user_id, key) pair:
 *        - INSERT the key row with response_status = NULL (in-flight marker).
 *        - After the route handler calls res.json(), UPDATE the row with the
 *          actual status + body (capped at 64 KB).
 *   3. Retry while first request is still in-flight (response_status IS NULL):
 *        - Return 409 "Idempotent request already in progress".
 *   4. Retry after first request completed (response_status IS NOT NULL):
 *        - Return the stored status + body verbatim.
 *   5. Retry with a different request body (request_hash mismatch):
 *        - Return 422 "Idempotency-Key re-used for a different request body".
 *
 * TTL: the retentionSweeper (services/retentionSweeper.ts) deletes rows older
 * than 24 hours via the `idempotency_keys` entry in its RULES array.
 *
 * Per-tenant: `req.db` is already the tenant DB, so the table is inherently
 * per-tenant — no cross-tenant data mixing is possible.
 */

import crypto from 'node:crypto';
import { Request, Response, NextFunction } from 'express';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('idempotency');

/** Maximum byte length of a stored response body (64 KB). */
const MAX_BODY_BYTES = 64 * 1024;

/**
 * Compute a SHA-256 hex digest over the canonical request fingerprint:
 * `<METHOD>\n<path>\n<body>`.  The body is the raw JSON string (or empty
 * string if the request has no body).  This lets the middleware detect
 * when a retry reuses the same key but sends a different payload.
 *
 * SCAN-1091: previously used `req.originalUrl` which includes the query
 * string. A client that retried with a cache-buster query (`?_=12345`)
 * produced a different hash and defeated the idempotent replay — the
 * handler re-ran despite the same Idempotency-Key. Switch to
 * `req.baseUrl + req.path` so the fingerprint is path-only. Query params
 * that carry semantic meaning should live in the body of a POST anyway;
 * idempotency is defined per (key, route, body) tuple.
 */
function hashRequest(req: Request): string {
  const method = req.method.toUpperCase();
  const path = `${req.baseUrl || ''}${req.path}`;
  // Express has already parsed the body by this point; re-serialize it so the
  // hash is stable regardless of whitespace in the original wire bytes.
  const body = req.body !== undefined && req.body !== null
    ? JSON.stringify(req.body)
    : '';
  return crypto
    .createHash('sha256')
    .update(`${method}\n${path}\n${body}`)
    .digest('hex');
}

/**
 * Truncate a JSON-serialized body string to MAX_BODY_BYTES so we don't bloat
 * the DB with very large responses.  The truncated value is still valid UTF-8
 * (we slice on character boundary); the client replaying from the cache gets a
 * potentially incomplete JSON document, but that is acceptable — clients should
 * not rely on idempotency replay for large streaming responses.
 */
function capBody(serialized: string): string {
  if (Buffer.byteLength(serialized, 'utf8') <= MAX_BODY_BYTES) return serialized;
  // Slice by byte length, then trim to the last valid UTF-16 code-unit.
  return Buffer.from(serialized, 'utf8').slice(0, MAX_BODY_BYTES).toString('utf8');
}

interface IdempotencyRow {
  readonly request_hash: string | null;
  readonly response_status: number | null;
  readonly response_body: string | null;
}

/**
 * Idempotency middleware for POST endpoints.
 *
 * If the client sends an `X-Idempotency-Key` header, duplicate requests within
 * 24 hours return the stored response instead of re-executing.  Drop-in
 * replacement for the previous in-memory implementation — route handlers need
 * no changes.
 *
 * Requires `req.db` (better-sqlite3 Database) and `req.user` to be populated
 * by earlier middleware (tenantResolver + authMiddleware).
 */
export function idempotent(req: Request, res: Response, next: NextFunction): void {
  // SCAN-591: Idempotency-Key only applies to POST writes per RFC 9562.
  // GET/PATCH (and other non-POST methods) must pass through without touching
  // the idempotency_keys table — otherwise the header creates phantom rows.
  if (req.method !== 'POST') {
    next();
    return;
  }

  const key = req.headers['x-idempotency-key'] as string | undefined;
  if (!key) {
    next();
    return;
  }

  // SEC-H14 (carried over): reject absurdly long keys.
  if (key.length > 256) {
    res.status(400).json({ success: false, message: 'X-Idempotency-Key too long' });
    return;
  }
  // SEC-H14 (carried over): reject control chars / CRLF to prevent log poisoning.
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1F\x7F]/.test(key)) {
    res.status(400).json({ success: false, message: 'X-Idempotency-Key contains invalid characters' });
    return;
  }

  const userId = req.user?.id ?? 0; // 0 = anonymous (should not happen on auth-gated routes)
  const db = req.db;
  const reqHash = hashRequest(req);

  // Try to INSERT the key row (in-flight marker: response_status = NULL).
  // If the row already exists the UNIQUE(user_id, key) constraint fires.
  let existing: IdempotencyRow | undefined;
  try {
    db.prepare(
      `INSERT INTO idempotency_keys (user_id, key, request_hash)
       VALUES (?, ?, ?)`,
    ).run(userId, key, reqHash);
    // INSERT succeeded — this is the first request for this (user_id, key).
    // Fall through to the monkey-patch block below.
  } catch (err: unknown) {
    const sqliteErr = err as { code?: string };
    if (sqliteErr.code !== 'SQLITE_CONSTRAINT_UNIQUE') {
      // SCAN-604: Unexpected DB error — fail closed (503) so the caller knows
      // the idempotency guarantee cannot be honoured right now.  Retry-After: 1
      // signals that retrying after one second is appropriate.
      logger.error('idempotency: unexpected DB error on INSERT', {
        code: sqliteErr.code,
        error: err instanceof Error ? err.message : String(err),
        userId,
        path: req.originalUrl,
      });
      res.set('Retry-After', '1');
      res.status(503).json({
        success: false,
        message: 'Idempotency service temporarily unavailable; please retry',
      });
      return;
    }

    // Row already exists — look it up to decide how to respond.
    existing = db
      .prepare(
        `SELECT request_hash, response_status, response_body
           FROM idempotency_keys
          WHERE user_id = ? AND key = ?`,
      )
      .get(userId, key) as IdempotencyRow | undefined;

    if (!existing) {
      // Extremely unlikely race: row was deleted between INSERT and SELECT.
      // Treat as first-request and let the route run.
      next();
      return;
    }

    // Check for request body mismatch.
    if (existing.request_hash !== null && existing.request_hash !== reqHash) {
      res.status(422).json({
        success: false,
        message: 'Idempotency-Key re-used for a different request body',
      });
      return;
    }

    // First request still in-flight (response_status IS NULL).
    if (existing.response_status === null) {
      res.status(409).json({
        success: false,
        message: 'Idempotent request already in progress',
      });
      return;
    }

    // First request completed — replay the stored response.
    const body: unknown = existing.response_body !== null
      ? JSON.parse(existing.response_body)
      : null;
    res.status(existing.response_status).json(body);
    return;
  }

  // First-time request path: monkey-patch res.json to capture the response and
  // UPDATE the row with the real status + body once the route handler is done.
  const originalJson = res.json.bind(res);
  let captured = false;
  res.json = (body: unknown) => {
    if (!captured) {
      captured = true;
      const serialized = capBody(JSON.stringify(body));
      // best-effort UPDATE — if it fails the stored row stays with
      // response_status = NULL which causes subsequent retries to receive a 409
      // (in-progress) rather than the wrong response. That is a safe fallback.
      try {
        db.prepare(
          `UPDATE idempotency_keys
              SET response_status = ?, response_body = ?
            WHERE user_id = ? AND key = ?`,
        ).run(res.statusCode, serialized, userId, key);
      } catch {
        // swallow — the route's own response must still be sent
      }
    }
    return originalJson(body);
  };

  next();
}
