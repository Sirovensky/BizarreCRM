import type { ParsedQs } from 'qs';

/** Coerce a query param to a string, returning '' if absent or array. */
export function qs(value: string | string[] | ParsedQs | ParsedQs[] | undefined): string {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0] as string;
  return '';
}

/** Coerce to string or return undefined if absent. */
export function qsOpt(value: string | string[] | ParsedQs | ParsedQs[] | undefined): string | undefined {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0] as string;
  return undefined;
}

/** Coerce to number, return fallback if not parseable. */
export function qsInt(value: string | string[] | ParsedQs | ParsedQs[] | undefined, fallback = 0): number {
  const s = qs(value);
  const n = parseInt(s, 10);
  return isNaN(n) ? fallback : n;
}
