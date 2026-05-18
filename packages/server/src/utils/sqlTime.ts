/**
 * SQLite timestamp parsing helpers.
 *
 * Context (BUGHUNT-2026-05-18):
 *   SQLite has no native DATETIME type. Two formats coexist in the schema:
 *     1. `datetime('now')` default → 'YYYY-MM-DD HH:MM:SS' (UTC, NO Z suffix)
 *     2. JS-side `new Date().toISOString()` → 'YYYY-MM-DDTHH:MM:SS.sssZ'
 *
 *   V8's `new Date(string)` / `Date.parse(string)` interpret format 1 as
 *   LOCAL time (per ECMA-262). On a server in any non-UTC zone every duration,
 *   pay-period boundary, expiry check, and filename date built from a bare
 *   SQLite ts is wrong by the host's UTC offset.
 *
 *   The fix is universal: append a `Z` (and replace the space with `T`) before
 *   handing the string to `new Date(...)`.
 *
 *   This helper is the canonical implementation. Prior to its extraction the
 *   same normalizer was inlined in employees.routes (parseSqliteTs),
 *   tickets.routes (normalizeTs), and a one-liner in notifications.routes.
 *   New code MUST go through this module.
 *
 * Accepted inputs:
 *   * '2026-05-18 12:00:00'        — bare SQLite UTC
 *   * '2026-05-18T12:00:00'        — ISO without zone (treated as UTC)
 *   * '2026-05-18T12:00:00.123Z'   — ISO with Z (passed through)
 *   * '2026-05-18T12:00:00+05:00'  — ISO with offset (passed through)
 *   * '2026-05-18 12:00:00Z'       — defensive: existing Z preserved, space → T
 *
 * Returns Date(NaN) for null/empty/non-string input. Callers that need
 * to distinguish "missing" from "invalid" should null-check before calling.
 */

const SQL_TS_HAS_ZONE = /[zZ]$|[+-]\d{2}:?\d{2}$/;

export function normalizeSqliteTs(value: string | null | undefined): string {
  if (!value || typeof value !== 'string') return '';
  // Trim because we have seen ' 2026-05-18 ...' leak in from some import paths.
  const trimmed = value.trim();
  if (!trimmed) return '';
  // Already has a zone designator? Just swap any space separator for 'T' so
  // V8 reliably accepts it (some legacy rows are 'YYYY-MM-DD HH:MM:SSZ').
  if (SQL_TS_HAS_ZONE.test(trimmed)) {
    return trimmed.includes('T') ? trimmed : trimmed.replace(' ', 'T');
  }
  // Bare 'YYYY-MM-DD HH:MM:SS' or 'YYYY-MM-DDTHH:MM:SS' — assume UTC, append Z.
  return `${trimmed.replace(' ', 'T')}Z`;
}

export function parseSqliteTs(value: string | null | undefined): Date {
  const normalized = normalizeSqliteTs(value);
  if (!normalized) return new Date(NaN);
  return new Date(normalized);
}

export function sqliteTsToMs(value: string | null | undefined): number {
  return parseSqliteTs(value).getTime();
}
