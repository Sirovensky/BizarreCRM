/**
 * trackInterval — tracked setInterval wrapper for graceful shutdown.
 *
 * SEC-BG7: All background timers must be registered here so shutdown() can
 * cancel them before tearing down DB handles. A timer that fires AFTER the DB
 * is closed causes "database is closed" crashes in the log.
 *
 * Usage:
 *   import { trackInterval } from '../utils/trackInterval.js';
 *   trackInterval(() => { ... }, 60_000);
 *   trackInterval(async () => { ... }, 5 * 60 * 1000, { unref: false });
 *
 * During shutdown, index.ts iterates backgroundIntervals and calls
 * clearInterval on every handle, then resets the array length to 0.
 */

import { createLogger } from './logger.js';

const log = createLogger('trackInterval');

/**
 * Every handle returned by trackInterval is pushed here so index.ts
 * shutdown() can cancel them all in one sweep.
 */
export const backgroundIntervals: NodeJS.Timeout[] = [];

/**
 * Drop-in replacement for setInterval that:
 *  - catches sync throws and async rejections so the timer is never killed
 *    by an unhandled error.
 *  - calls .unref() by default (same as the previous convention), unless
 *    `options.unref` is explicitly false.
 *  - pushes the handle into backgroundIntervals for graceful shutdown.
 */
export function trackInterval(
  fn: () => void | Promise<void>,
  ms: number,
  options: { unref?: boolean } = {},
): NodeJS.Timeout {
  const handle = setInterval(() => {
    try {
      const result = fn();
      // If the callback returns a promise, catch any rejection so the timer
      // never triggers an unhandledRejection.
      if (result && typeof (result as Promise<void>).catch === 'function') {
        (result as Promise<void>).catch((err) => {
          log.error('trackInterval: async callback rejected', {
            error: err instanceof Error ? err.message : String(err),
          });
        });
      }
    } catch (err) {
      log.error('trackInterval: sync callback threw', {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }, ms);

  if (options.unref !== false) handle.unref();
  backgroundIntervals.push(handle);
  return handle;
}
