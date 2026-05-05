/**
 * Long-task registry — declares known long-running operations to the watchdog.
 *
 * The cross-platform watchdog (`packages/server/scripts/watchdog.cjs`) polls
 * `/api/v1/health/live` every 30s. The liveness handler exposes whichever long
 * task is currently in flight by reading `snapshot()` from this module.
 *
 * Caller contract:
 *   try {
 *     longTaskRegistry.start({ kind: 'tenant-migration', expectedDurationMs: 600_000 });
 *     await doTheLongThing();
 *   } finally {
 *     longTaskRegistry.end();
 *   }
 *
 * Wrap any operation expected to take more than 10 seconds. Without
 * registration, the watchdog will treat a slow operation as a wedge after
 * 90 seconds and restart the server. With registration, the watchdog extends
 * its grace threshold to `expectedDurationMs * 1.5` (capped at 30 minutes).
 *
 * Single-task only — multi-task could be added later as a Map keyed by kind+id,
 * but BizarreCRM does not currently run two long tasks concurrently.
 */
import { createLogger } from './logger.js';

const log = createLogger('longTaskRegistry');

export interface LongTask {
  kind: string;
  startedAt: number;
  expectedDurationMs: number;
  details?: Record<string, unknown>;
}

export type LongTaskInput = Omit<LongTask, 'startedAt'>;

let current: LongTask | null = null;

/**
 * Register the start of a long-running operation. If a task is already
 * registered, log a warning and overwrite — this indicates a code bug in the
 * caller (forgot to call `end()`). The new task wins so the most-recent
 * operation is reported to the watchdog.
 */
export function start(task: LongTaskInput): void {
  if (current) {
    log.warn('longTaskRegistry: start() called while another task is active — overwriting', {
      previous: { kind: current.kind, startedAt: current.startedAt },
      next: { kind: task.kind },
    });
  }
  current = {
    ...task,
    startedAt: Date.now(),
  };
}

/**
 * Clear the currently-registered task. No-op if no task is active.
 */
export function end(): void {
  current = null;
}

/**
 * Read the currently-registered task. Returns `null` if no task is active.
 * Safe to call from any context — does not mutate state.
 */
export function snapshot(): LongTask | null {
  return current;
}

/**
 * Test-only: reset internal state. Exported so unit tests do not need to
 * reach through module mutation.
 */
export function _resetForTests(): void {
  current = null;
}
