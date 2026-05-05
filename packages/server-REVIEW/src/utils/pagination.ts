/**
 * Pagination helpers — SEC-H120 (PUB-015)
 *
 * Every list endpoint MUST route client-supplied size parameters through
 * `parsePageSize` so that a malicious or buggy client cannot trigger a
 * full-table scan via `?limit=999999999`.
 *
 * Default cap: MAX_PAGE_SIZE = 100.
 *
 * Admin / export endpoints that legitimately need more rows must use a
 * locally-scoped higher cap (e.g. Math.min(n, ADMIN_MAX_PAGE_SIZE)) and
 * document the carve-out with a comment referencing this file.
 */

/** Hard cap applied to every regular list endpoint. */
export const MAX_PAGE_SIZE = 100;

/** Fallback when the client omits the size parameter. */
export const DEFAULT_PAGE_SIZE = 25;

/**
 * Parse and clamp a client-supplied page-size value.
 *
 * Accepts any `unknown` — strings, numbers, undefined — so it can be
 * passed `req.query.limit` directly without casting.
 *
 * @param raw     - Raw value from `req.query.limit`, `req.query.per_page`, etc.
 * @param fallback - Size to use when `raw` is missing / non-positive (default: DEFAULT_PAGE_SIZE).
 * @returns       Integer in [1, MAX_PAGE_SIZE].
 */
export function parsePageSize(raw: unknown, fallback = DEFAULT_PAGE_SIZE): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(Math.floor(n), MAX_PAGE_SIZE);
}

/**
 * Parse a client-supplied page number.
 *
 * @param raw - Raw value from `req.query.page`.
 * @returns   Integer >= 1.
 */
export function parsePage(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.floor(n);
}
