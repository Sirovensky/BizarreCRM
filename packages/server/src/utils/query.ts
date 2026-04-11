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

/**
 * Escape a user-supplied string so it can be safely used as the middle of a
 * SQL LIKE pattern such as `%${escapeLike(input)}%`.
 *
 * Parameterised queries already prevent classical SQL injection through `?`
 * bindings — SQLite will never interpret the bound value as SQL. But the
 * `%` and `_` characters ARE wildcards inside a LIKE pattern, so a caller
 * who types `%` or `_` can broaden the match (enumeration / DoS) or make
 * the index useless. Escaping these characters along with the backslash
 * escape character means a user's literal `%`, `_`, or `\` matches only
 * those literal characters.
 *
 * Usage:
 *   const like = `%${escapeLike(keyword)}%`;
 *   db.prepare("... WHERE name LIKE ? ESCAPE '\\'").all(like);
 *
 * IMPORTANT: the SQL statement MUST include `ESCAPE '\'` (or a different
 * escape char) for the escape characters added by this function to work.
 * Without `ESCAPE '\'`, SQLite has no default escape character and the
 * backslashes become noise in the pattern. Use `likePattern()` below to
 * get both the escaped value AND a reminder of the escape clause.
 */
export function escapeLike(input: string): string {
  if (typeof input !== 'string') return '';
  // Escape the escape character FIRST, otherwise escaping `%` and `_` would
  // double-escape themselves.
  return input.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

/**
 * Convenience wrapper — returns `%${escaped}%` for "contains" searches.
 * Remember to append `ESCAPE '\'` to the LIKE clause in your SQL.
 */
export function likeContains(input: string): string {
  return `%${escapeLike(input)}%`;
}

/**
 * Convenience wrapper — returns `${escaped}%` for "starts with" searches.
 * Remember to append `ESCAPE '\'` to the LIKE clause in your SQL.
 */
export function likeStartsWith(input: string): string {
  return `${escapeLike(input)}%`;
}

/**
 * Convenience wrapper — returns `%${escaped}` for "ends with" searches.
 * Remember to append `ESCAPE '\'` to the LIKE clause in your SQL.
 */
export function likeEndsWith(input: string): string {
  return `%${escapeLike(input)}`;
}

/**
 * Validate that a string is a safe SQL identifier (table/column/trigger
 * name) before interpolating it into a query. Throws on rejection so the
 * caller gets a clean error and the log entry records the attempt.
 *
 * Allows lowercase letters, digits, and underscores — matching SQLite's
 * standard identifier shape and rejecting quoted-identifier tricks,
 * Unicode confusables, spaces, and SQL meta characters.
 *
 * Pass an optional `allowed` Set to enforce a hard whitelist on top of
 * the regex; this is the preferred defence-in-depth pattern for public-
 * facing code paths (sort columns, ORDER BY, dynamic SET builders).
 */
export function assertSafeIdentifier(
  name: string,
  kind: string,
  allowed?: ReadonlySet<string>,
): string {
  if (typeof name !== 'string' || !/^[a-z_][a-z0-9_]*$/i.test(name)) {
    throw new Error(`Invalid ${kind}: ${name}`);
  }
  if (allowed && !allowed.has(name)) {
    throw new Error(`Disallowed ${kind}: ${name}`);
  }
  return name;
}
