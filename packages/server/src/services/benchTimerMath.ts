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
  // BUGHUNT-2026-05-16: bench_timers.started_at / ended_at are SQLite
  // DEFAULT (datetime('now')) → 'YYYY-MM-DD HH:MM:SS' (UTC, no 'Z'). V8
  // parses that as local time, so every elapsed/paused interval was wrong
  // by the server's UTC offset — labor cost charged to the customer was
  // therefore wrong on any non-UTC host.
  const normalizeTs = (v: string): number => {
    if (!v) return NaN;
    const s = v.includes('T') || v.endsWith('Z') || v.includes('+') ? v : `${v.replace(' ', 'T')}Z`;
    return new Date(s).getTime();
  };
  const start = normalizeTs(row.started_at);
  const end = row.ended_at ? normalizeTs(row.ended_at) : Date.now();
  if (Number.isNaN(start) || Number.isNaN(end)) return 0;

  const pauses = parseJson<PauseSegment[]>(row.pause_log_json, []);
  let paused = 0;
  for (const p of pauses) {
    const pa = normalizeTs(p.pause_at);
    const pr = p.resume_at ? normalizeTs(p.resume_at) : end;
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
