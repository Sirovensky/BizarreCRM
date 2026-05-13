/**
 * Tenant-aware timezone helpers used by SQL queries that bucket or filter
 * UTC-stored timestamps against the tenant's local calendar.
 *
 * Extracted from reports.routes.ts so other routes (employees hours,
 * commissions, etc.) can apply the same tz offset without duplicating the
 * Intl/SQLite plumbing.
 */

/**
 * Read the tenant's configured IANA timezone from store_config so
 * date-bucketing queries (hour-of-day, day-of-week, daily totals) group on
 * the owner's local calendar rather than UTC. Falls back to UTC so existing
 * behaviour is preserved when the setting is missing.
 *
 * Uses the synchronous `req.db` wrapper because the store_config lookup is a
 * single-row cache hit and cheaper through the sync binding than round-tripping
 * Promise.all alongside the rest of the request's async queries.
 */
export function getTenantTz(req: any): string {
  try {
    const row = req.db
      ?.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'")
      .get() as { value?: string } | undefined;
    return row?.value || 'UTC';
  } catch {
    return 'UTC';
  }
}

/**
 * Convert an IANA timezone name into a SQLite datetime modifier that shifts a
 * UTC datetime to local time for date/hour bucketing. SQLite does not have
 * real timezone support, so we compute the current offset via Intl and emit
 * a `'±HH:MM'` modifier (e.g. `'-07:00'`). Returns a literal the query can
 * embed inside a strftime() / datetime() call.
 *
 * Note: offset is computed at query time from "now" so DST boundaries within
 * the selected range drift by one hour. For report accuracy that's acceptable
 * — DoW/hour reports are trend-shape indicators, not tax-time numbers.
 *
 * Returns an empty-effect modifier ('+00:00') when the timezone is UTC or
 * unrecognised so the SQL shape stays constant.
 */
export function tzModifier(timezone: string): string {
  if (!timezone || timezone === 'UTC') return '+00:00';
  try {
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      timeZoneName: 'shortOffset',
    });
    const parts = fmt.formatToParts(new Date());
    const offset = parts.find(p => p.type === 'timeZoneName')?.value || 'GMT';
    const match = offset.match(/GMT([+-])(\d{1,2})(?::(\d{2}))?/);
    if (!match) return '+00:00';
    const sign = match[1];
    const hh = match[2].padStart(2, '0');
    const mm = (match[3] || '00').padStart(2, '0');
    return `${sign}${hh}:${mm}`;
  } catch {
    return '+00:00';
  }
}
