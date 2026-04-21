/**
 * Crash Resiliency Middleware
 *
 * 1. Blocks requests to auto-disabled routes (returns 503)
 * 2. Tracks the current request route for crash attribution
 * 3. Resets consecutive crash count on successful responses
 */
import { Request, Response, NextFunction } from 'express';
import { isRouteDisabled, resetRouteCrashCount } from '../services/crashTracker.js';
import { ERROR_CODES, errorBody } from '../utils/errorCodes.js';

/**
 * Module-level variable tracking the route currently being processed.
 * Used by the process-level uncaughtException/unhandledRejection handlers
 * to attribute crashes to specific routes. Safe in single-threaded Node.js.
 */
export let currentRequestRoute: string | null = null;

export function crashGuardMiddleware(req: Request, res: Response, next: NextFunction): void {
  const routeId = `${req.method}:${req.path}`;

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

  // Track current route for crash attribution
  currentRequestRoute = routeId;

  // On successful response, reset the consecutive crash counter
  res.on('finish', () => {
    if (res.statusCode < 500) {
      resetRouteCrashCount(routeId);
    }
    // Clear current route tracking
    if (currentRequestRoute === routeId) {
      currentRequestRoute = null;
    }
  });

  next();
}
