/**
 * Crash Resiliency Middleware
 *
 * 1. Blocks requests to auto-disabled routes (returns 503)
 * 2. Tracks the current request route for crash attribution
 * 3. Resets consecutive crash count on successful responses
 *
 * SCAN-592: Route tracking was previously a module-level mutable variable,
 * which is a race condition under concurrent requests — the last request to
 * run overwrites the value seen by uncaughtException handlers.  Replaced with
 * AsyncLocalStorage so each async execution context carries its own route
 * label, giving the crash handler accurate attribution regardless of
 * concurrency.
 */
import { AsyncLocalStorage } from 'async_hooks';
import { Request, Response, NextFunction } from 'express';
import { isRouteDisabled, resetRouteCrashCount } from '../services/crashTracker.js';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';

/** Per-request storage carrying the route label for crash attribution. */
const routeStorage = new AsyncLocalStorage<{ route: string }>();

/**
 * SCAN-1078: keying the auto-disable + crash-attribution store on `req.path`
 * meant every request for `/tickets/12345` produced a fresh label that
 * never matched the `/tickets/67890` label from the next broken request.
 * A genuinely broken handler never tripped the disable threshold because
 * consecutive crashes hit unique keys.
 *
 * We don't have `req.route` here (routing hasn't happened yet), so the
 * cheapest normalisation is to strip common id shapes from the path:
 *   - Trailing / embedded numeric ids:   /tickets/42 -> /tickets/:id
 *   - UUIDs (v4 etc.):                   /wh/<uuid>/ -> /wh/:uuid/
 *   - 24-char hex (Mongo-style, JWTs):   /x/<24hex>  -> /x/:hex
 * This keeps distinct route shapes separate while collapsing concrete ids
 * into pattern labels the tracker can count against.
 */
const UUID_RE = /\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?=\/|$)/gi;
const HEX24_RE = /\/[0-9a-f]{24}(?=\/|$)/gi;
const NUM_RE = /\/\d+(?=\/|$)/g;

export function normalizeRouteForAttribution(path: string): string {
  return path
    .replace(UUID_RE, '/:uuid')
    .replace(HEX24_RE, '/:hex')
    .replace(NUM_RE, '/:id');
}

/**
 * Returns the route label for the currently executing async context, or null
 * if called outside of a request (e.g. from a background timer).
 *
 * Consumed by the uncaughtException / unhandledRejection handlers in index.ts.
 */
export function getCurrentRoute(): string | null {
  return routeStorage.getStore()?.route ?? null;
}

export function crashGuardMiddleware(req: Request, res: Response, next: NextFunction): void {
  const routeId = `${req.method}:${normalizeRouteForAttribution(req.path)}`;

  // Check if this route has been auto-disabled due to repeated crashes
  if (isRouteDisabled(routeId)) {
    res.status(503).json(errorBody(
      ERROR_CODES.ERR_ROUTE_DISABLED,
      'This endpoint has been temporarily disabled due to repeated errors. Contact your administrator.',
      res.locals.requestId as string | undefined,
      { route: routeId },
    ));
    return;
  }

  // On successful response, reset the consecutive crash counter
  res.on('finish', () => {
    if (res.statusCode < 500) {
      resetRouteCrashCount(routeId);
    }
  });

  // Run the rest of the middleware chain inside the AsyncLocalStorage context
  // so that any uncaughtException handler can read the correct route label.
  routeStorage.run({ route: routeId }, () => next());
}
