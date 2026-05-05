/**
 * Circuit Breaker — SEC-H77
 *
 * Prevents slow / failing outbound providers (Stripe, BlockChyp, Twilio, etc.)
 * from thread-starving the Node event loop.
 *
 * State machine:
 *   CLOSED     — normal operation; failures are counted.
 *   OPEN       — fast-fail; no real calls for openDurationMs.
 *   HALF_OPEN  — one probe call is attempted; success → CLOSED, failure → OPEN.
 *
 * Usage:
 *   const breaker = createBreaker('stripe');
 *   const result  = await breaker.run(() => stripe.checkout.sessions.create(...));
 */

import { createLogger } from './logger.js';

const log = createLogger('circuit-breaker');

// ─── Public types ────────────────────────────────────────────────────────────

export class CircuitBreakerOpenError extends Error {
  readonly name = 'CircuitBreakerOpenError';
  constructor(public readonly breakerName: string) {
    super(`Circuit breaker OPEN for provider "${breakerName}" — fast-failing`);
  }
}

export interface BreakerOptions {
  /** Number of consecutive failures before opening the circuit. Default: 5 */
  failureThreshold?: number;
  /** How long (ms) to stay OPEN before allowing a half-open probe. Default: 60_000 */
  openDurationMs?: number;
  /** After a half-open probe attempt, wait this long before the next probe on failure. Default: 120_000 */
  halfOpenProbeAfterMs?: number;
}

export interface CircuitBreaker {
  /** Run fn through the breaker. Throws CircuitBreakerOpenError when OPEN. */
  run<T>(fn: () => Promise<T>): Promise<T>;
  /** Current state snapshot (for metrics / health endpoints). */
  readonly state: BreakerState;
}

// ─── Internal types ──────────────────────────────────────────────────────────

type BreakerState = 'CLOSED' | 'OPEN' | 'HALF_OPEN';

interface BreakerInternalState {
  state: BreakerState;
  failureCount: number;
  lastFailureError: string | null;
  openedAt: number | null;
  halfOpenAt: number | null;
  /** True while a half-open probe is in-flight; prevents concurrent probes. */
  probeInFlight: boolean;
}

// ─── Factory ─────────────────────────────────────────────────────────────────

/**
 * Create a named circuit breaker for one outbound provider.
 * Each provider should have its own breaker instance so one flaky provider
 * cannot trip others.
 */
export function createBreaker(
  name: string,
  options: BreakerOptions = {},
): CircuitBreaker {
  const failureThreshold = options.failureThreshold ?? 5;
  const openDurationMs = options.openDurationMs ?? 60_000;
  const halfOpenProbeAfterMs = options.halfOpenProbeAfterMs ?? 120_000;

  let internal: BreakerInternalState = {
    state: 'CLOSED',
    failureCount: 0,
    lastFailureError: null,
    openedAt: null,
    halfOpenAt: null,
    probeInFlight: false,
  };

  function trip(lastError: string): void {
    internal = {
      state: 'OPEN',
      failureCount: internal.failureCount,
      lastFailureError: lastError,
      openedAt: Date.now(),
      halfOpenAt: null,
      probeInFlight: false,
    };
    log.error('circuit_breaker_open', {
      name,
      failureCount: internal.failureCount,
      lastError,
    });
  }

  function reset(): void {
    internal = {
      state: 'CLOSED',
      failureCount: 0,
      lastFailureError: null,
      openedAt: null,
      halfOpenAt: null,
      probeInFlight: false,
    };
    log.info('circuit_breaker_closed', { name });
  }

  function handleSuccess(): void {
    if (internal.state === 'HALF_OPEN') {
      reset(); // reset() clears probeInFlight
    } else {
      // Reset failure count on success in CLOSED state
      if (internal.failureCount > 0) {
        internal = { ...internal, failureCount: 0, lastFailureError: null };
      }
    }
  }

  function handleFailure(err: unknown): void {
    const errMsg = err instanceof Error ? err.message : String(err);
    internal = {
      ...internal,
      failureCount: internal.failureCount + 1,
      lastFailureError: errMsg,
    };

    if (internal.state === 'HALF_OPEN') {
      // Probe failed — re-open with extended back-off; clear in-flight flag.
      internal = {
        ...internal,
        state: 'OPEN',
        openedAt: Date.now(),
        halfOpenAt: null,
        probeInFlight: false,
      };
      log.warn('circuit_breaker_probe_failed', {
        name,
        failureCount: internal.failureCount,
        lastError: errMsg,
        nextProbeAfterMs: halfOpenProbeAfterMs,
      });
    } else if (internal.failureCount >= failureThreshold) {
      trip(errMsg);
    } else {
      log.warn('circuit_breaker_failure_counted', {
        name,
        failureCount: internal.failureCount,
        threshold: failureThreshold,
        lastError: errMsg,
      });
    }
  }

  function resolveState(): BreakerState {
    if (internal.state === 'CLOSED') return 'CLOSED';

    const now = Date.now();
    if (internal.state === 'OPEN') {
      // After openDurationMs allow one probe (only if none already in-flight)
      if (
        !internal.probeInFlight &&
        internal.openedAt !== null &&
        now - internal.openedAt >= openDurationMs
      ) {
        internal = { ...internal, state: 'HALF_OPEN', halfOpenAt: now };
        log.info('circuit_breaker_half_open', { name });
        return 'HALF_OPEN';
      }
      return 'OPEN';
    }

    // HALF_OPEN — only one probe at a time.
    // If a probe is already in-flight fast-fail additional callers.
    // If the probe window has elapsed, allow a fresh probe.
    if (internal.state === 'HALF_OPEN') {
      if (internal.probeInFlight) return 'OPEN';
      if (
        internal.halfOpenAt !== null &&
        now - internal.halfOpenAt >= halfOpenProbeAfterMs
      ) {
        // Another probe window
        internal = { ...internal, halfOpenAt: now };
        return 'HALF_OPEN';
      }
    }
    return internal.state;
  }

  async function run<T>(fn: () => Promise<T>): Promise<T> {
    const currentState = resolveState();

    if (currentState === 'OPEN') {
      throw new CircuitBreakerOpenError(name);
    }

    // Mark probe in-flight when entering half-open
    const isProbe = currentState === 'HALF_OPEN';
    if (isProbe) {
      internal = { ...internal, probeInFlight: true };
    }

    try {
      const result = await fn();
      handleSuccess();
      return result;
    } catch (err: unknown) {
      // Do not count CircuitBreakerOpenError as a provider failure
      if (err instanceof CircuitBreakerOpenError) {
        if (isProbe) internal = { ...internal, probeInFlight: false };
        throw err;
      }
      handleFailure(err);
      throw err; // re-throw original error unchanged
    }
  }

  return {
    run,
    get state(): BreakerState {
      return internal.state;
    },
  };
}
