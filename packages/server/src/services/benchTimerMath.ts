/**
 * Shared bench-timer math + row shape.
 *
 * Extracted from bench.routes.ts so other routes (tickets.routes.ts status
 * change, etc.) can compute elapsed seconds + labor cost identically when
 * they need to auto-stop a running timer (WEB-UIUX-650).
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('benchTimerMath');

export interface BenchTimerRow {
  id: number;
  ticket_id: number;
  ticket_device_id: number | null;
  user_id: number;
  started_at: string;
  ended_at: string | null;
  pause_log_json: string | null;
  total_seconds: number | null;
  labor_rate_cents: number | null;
  labor_cost_cents: number | null;
  notes: string | null;
}

export interface PauseSegment {
  pause_at: string;
  resume_at?: string;
}

export function parseJson<T>(val: string | null | undefined, fallback: T): T {
  if (!val) return fallback;
  try {
    return JSON.parse(val) as T;
  } catch {
    return fallback;
  }
}

/**
 * Integer-safe labor cost: (seconds * rate_cents) / 3600, rounded to the
 * nearest whole cent. Multiplying first avoids float drift.
 */
export function computeLaborCostCents(seconds: number, rateCents: number): number {
  if (!isFinite(seconds) || !isFinite(rateCents)) return 0;
  if (seconds <= 0 || rateCents <= 0) return 0;
  return Math.round((seconds * rateCents) / 3600);
}

/**
 * Live elapsed seconds, subtracting any time spent paused. Works for both
 * finished timers (uses `ended_at`) and live ones (uses "now").
 */
export function computeElapsedSeconds(row: BenchTimerRow): number {
  const start = new Date(row.started_at).getTime();
  const end = row.ended_at ? new Date(row.ended_at).getTime() : Date.now();
  if (Number.isNaN(start) || Number.isNaN(end)) return 0;

  const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
  let paused = 0;
  for (const p of pauses) {
    const pa = new Date(p.pause_at).getTime();
    const pr = p.resume_at ? new Date(p.resume_at).getTime() : end;
    if (Number.isFinite(pa) && Number.isFinite(pr) && pr > pa) paused += pr - pa;
  }

  const active = end - start - paused;
  const seconds = Math.max(0, Math.round(active / 1000));
  const MAX_SECONDS_PER_SESSION = 24 * 3600;
  if (seconds > MAX_SECONDS_PER_SESSION) {
    logger.warn('bench timer session exceeds 24h — capping', { start, end, seconds });
    return MAX_SECONDS_PER_SESSION;
  }
  return seconds;
}

export function isCurrentlyPaused(row: BenchTimerRow): boolean {
  const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
  if (pauses.length === 0) return false;
  const last = pauses[pauses.length - 1];
  return !!last && !last.resume_at;
}
