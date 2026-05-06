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
 * Parse and clamp a page-size value that may arrive under either the legacy
 * `pagesize` key OR the canonical `per_page` key.
 *
 * Canonical pagination response shape uses `per_page`; this helper lets
 * clients migrate from `pagesize` → `per_page` without a flag-day.
 * `per_page` takes precedence when both keys are present.
 *
 * @param query    - `req.query` (or any object that may contain the keys).
 * @param fallback - Size to use when neither key is present / valid.
 * @returns        Integer in [1, MAX_PAGE_SIZE].
 */
export function parsePageSizeDual(
  query: Record<string, unknown>,
  fallback = DEFAULT_PAGE_SIZE,
): number {
  // Prefer the canonical key; fall back to the legacy key.
  const raw = query['per_page'] !== undefined ? query['per_page'] : query['pagesize'];
  return parsePageSize(raw, fallback);
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

export interface KnownTotalPaginationOptions {
  page: unknown;
  pageSize: number;
  total: number;
  /**
   * Some legacy endpoints report one page for an empty result set. Leave the
   * default at 0 for routes that already expose `total_pages: 0`.
   */
  minimumTotalPages?: 0 | 1;
}

export interface KnownTotalPagination {
  requestedPage: number;
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
  offset: number;
  outOfBounds: boolean;
}

/**
 * Build pagination metadata when the route already knows the filtered total.
 *
 * This caps huge/out-of-range page requests before an OFFSET is built, so
 * callers can return the last known page plus an `out_of_bounds` flag instead
 * of spending work on a sparse empty page.
 */
export function paginateKnownTotal(options: KnownTotalPaginationOptions): KnownTotalPagination {
  const requestedPage = parsePage(options.page);
  const pageSize = Number.isFinite(options.pageSize) && options.pageSize > 0
    ? Math.floor(options.pageSize)
    : DEFAULT_PAGE_SIZE;
  const total = Number.isFinite(options.total) && options.total > 0
    ? Math.floor(options.total)
    : 0;
  const minimumTotalPages = options.minimumTotalPages ?? 0;
  const totalPages = Math.max(minimumTotalPages, Math.ceil(total / pageSize));
  const lastPage = Math.max(1, totalPages);
  const page = Math.min(requestedPage, lastPage);

  return {
    requestedPage,
    page,
    pageSize,
    total,
    totalPages,
    offset: (page - 1) * pageSize,
    outOfBounds: requestedPage > lastPage,
  };
}
