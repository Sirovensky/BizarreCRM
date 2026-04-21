/**
 * Error-envelope enricher.
 *
 * Monkey-patches `res.json` so every 4xx/5xx JSON response that the server
 * emits gets `code` + `request_id` fields appended before being serialised,
 * WITHOUT requiring every route handler to build the envelope by hand. This
 * is a backstop for the 390+ inline `res.status(400).json({success:false,
 * message:'...'})` sites across the codebase that haven't been migrated to
 * the `errorBody()` helper yet.
 *
 * Rules:
 *   - Only touches JSON bodies that look like error envelopes
 *     (`{ success: false, ... }` or a bare `{ message: 'x' }` on a 4xx/5xx).
 *   - Never overrides a code / request_id the handler already set — helpers
 *     using `errorBody()` take precedence.
 *   - Picks a generic fallback code based on status (`ERR_STATUS_4xx` etc.)
 *     so support can at least tell the code came from a non-migrated site
 *     ("we need to add a real code to this handler") vs a middleware.
 *   - 2xx bodies pass through untouched so success responses never change
 *     shape.
 */
import type { Request, Response, NextFunction } from 'express';

function fallbackCodeForStatus(status: number): string {
  if (status >= 500) return 'ERR_STATUS_5XX';
  if (status === 429) return 'ERR_RATE_GENERIC';
  if (status === 404) return 'ERR_NOT_FOUND';
  if (status === 403) return 'ERR_FORBIDDEN';
  if (status === 401) return 'ERR_UNAUTHENTICATED';
  if (status === 400) return 'ERR_BAD_REQUEST';
  if (status >= 400) return 'ERR_STATUS_4XX';
  return 'ERR_STATUS_UNKNOWN';
}

function looksLikeErrorEnvelope(body: unknown): body is Record<string, unknown> {
  if (!body || typeof body !== 'object') return false;
  // { success: false, ... } — the canonical CRM error shape.
  if ((body as { success?: unknown }).success === false) return true;
  // Accept `{ message: 'x' }` on a 4xx/5xx as an error envelope too so
  // older handlers that didn't set `success` still get tagged.
  if (typeof (body as { message?: unknown }).message === 'string') return true;
  return false;
}

export function errorEnvelopeMiddleware(req: Request, res: Response, next: NextFunction): void {
  const originalJson = res.json.bind(res);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  res.json = function (body: any) {
    try {
      const status = res.statusCode;
      // Only enrich 4xx / 5xx error envelopes. Success responses are passed
      // through unchanged so their shape contract stays exactly as routes
      // documented it.
      if (status >= 400 && looksLikeErrorEnvelope(body)) {
        const enriched: Record<string, unknown> = { ...(body as Record<string, unknown>) };
        if (typeof enriched.code !== 'string') {
          enriched.code = fallbackCodeForStatus(status);
        }
        if (typeof enriched.request_id !== 'string') {
          const rid = res.locals?.requestId;
          if (typeof rid === 'string') enriched.request_id = rid;
        }
        // Ensure `success: false` is present explicitly. Legacy handlers
        // that only set `{ message: 'x' }` get it added here for consistency.
        if (enriched.success === undefined) enriched.success = false;
        return originalJson(enriched);
      }
    } catch {
      // Best-effort only — never let the enricher break a response.
    }
    return originalJson(body);
  };
  next();
}
