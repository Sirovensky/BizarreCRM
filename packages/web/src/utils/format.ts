/**
 * Shared formatting utilities.
 *
 * These replace the many per-file duplicates of formatCurrency / formatDate /
 * formatDateTime / formatPhone / timeAgo.
 *
 * Currency defaults to USD but reads from global shop settings once
 * `initCurrencyFromSettings()` is called (typically by AppShell on mount).
 */

// ─── Currency ───────────────────────────────────────────────────────────────

let _currencyCode = 'USD';
let _locale: string = typeof navigator !== 'undefined' ? navigator.language || 'en-US' : 'en-US';

const formatterCache = new Map<string, Intl.NumberFormat>();
function getFormatter(locale: string, currency: string): Intl.NumberFormat {
  const key = locale + '/' + currency;
  if (!formatterCache.has(key)) {
    formatterCache.set(key, new Intl.NumberFormat(locale, { style: 'currency', currency }));
  }
  return formatterCache.get(key)!;
}

function buildFormatter(code: string, locale: string = _locale): Intl.NumberFormat {
  return getFormatter(locale, code);
}

let _currencyFmt = buildFormatter(_currencyCode, _locale);

/** Tracks currency codes that have already triggered a format-failure warning (suppresses per-render spam). */
const _warnedCurrencyCodes = new Set<string>();

/** Call once at app startup (e.g. from AppShell) after settings load. */
export function initCurrencyFromSettings(code: string | undefined | null, locale?: string): void {
  const normalized = (code ?? '').trim().toUpperCase();
  let changed = false;
  if (normalized && /^[A-Z]{3}$/.test(normalized) && normalized !== _currencyCode) {
    _currencyCode = normalized;
    changed = true;
  }
  if (locale && locale !== _locale) {
    _locale = locale;
    changed = true;
  }
  if (changed) {
    _currencyFmt = buildFormatter(_currencyCode, _locale);
  }
}

// @audit-fixed (WEB-FM-001 / Fixer-K 2026-04-24): merged the standalone
// portal-safe `formatCurrency` (formerly utils/formatCurrency.ts) into this
// canonical helper. Third positional arg accepts an explicit locale so portal
// pages — which run before AppShell ever calls `initCurrencyFromSettings` —
// can format using the visitor's preferred language while still picking the
// tenant's currency from the explicit override. When `localeOverride` is
// omitted we keep the previous behaviour of using the module-level locale.
export function formatCurrency(
  amount: number | null | undefined,
  currencyOverride?: string,
  localeOverride?: string,
): string {
  const code = currencyOverride ?? _currencyCode;
  const useCustomLocale = !!localeOverride;
  const fmt = useCustomLocale || currencyOverride
    ? getFormatter(localeOverride ?? _locale, code)
    : _currencyFmt;
  if (amount == null || isNaN(Number(amount))) {
    return '—';
  }
  try {
    return fmt.format(Number(amount));
  } catch (err) {
    // Fallback for unknown currency codes — warn once per code so misconfigured
    // tenant currency settings surface visibly without spamming per-render.
    if (!_warnedCurrencyCodes.has(code)) {
      _warnedCurrencyCodes.add(code);
      console.error(`[formatCurrency] format failed for code "${code}" — falling back to USD`, err);
    }
    return getFormatter(localeOverride ?? _locale, 'USD').format(Number(amount) || 0);
  }
}

export function formatCurrencySymbol(currencyOverride?: string, localeOverride?: string): string {
  const code = currencyOverride ?? _currencyCode;
  try {
    const parts = new Intl.NumberFormat(localeOverride ?? _locale, {
      style: 'currency',
      currency: code,
      currencyDisplay: 'narrowSymbol',
    }).formatToParts(0);
    return parts.find((part) => part.type === 'currency')?.value ?? code;
  } catch (err) {
    if (!_warnedCurrencyCodes.has(code)) {
      _warnedCurrencyCodes.add(code);
      console.error(`[formatCurrencySymbol] format failed for code "${code}"`, err);
    }
    return code;
  }
}

/**
 * Format integer cents as a currency string. Prefer this over
 * `formatCurrency(cents / 100)` because it never rounds at the display
 * boundary and it respects the locale/currency from settings.
 *
 * Usage: `formatCents(1099)` → `"$10.99"` (with `USD` default).
 */
export function formatCents(cents: number | null | undefined, currencyOverride?: string): string {
  if (cents == null || !isFinite(Number(cents))) {
    return '—';
  }
  const n = Number(cents);
  // Integer cents → dollars without losing sign.
  return formatCurrency(n / 100, currencyOverride);
}

// ─── Dates ──────────────────────────────────────────────────────────────────

// @audit-fixed (WEB-FM-008 / Fixer-C1 2026-04-25): added optional `localeOverride`
// arg mirroring `formatCurrency` so portal pages \u2014 which run before AppShell ever
// calls `initCurrencyFromSettings` \u2014 can format dates against a visitor-supplied
// locale (`usePortalI18n`) instead of falling back to the module default.
export function formatDate(iso: string | null | undefined, localeOverride?: string, tz?: string | null): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  // WEB-UIUX-779: accept an optional IANA tz so reports + receipts can render
  // dates in the shop's `store_timezone` instead of the browser-local zone.
  const opts: Intl.DateTimeFormatOptions = {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  };
  if (tz) opts.timeZone = tz;
  return d.toLocaleDateString(localeOverride ?? _locale, opts);
}

export function formatDateTime(iso: string | null | undefined, localeOverride?: string, tz?: string | null): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  const opts: Intl.DateTimeFormatOptions = {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  };
  if (tz) opts.timeZone = tz;
  return d.toLocaleString(localeOverride ?? _locale, opts);
}

// @audit-fixed (WEB-FF-003 / Fixer-DD 2026-04-25): short date+time used widely
// across detail pages (Leads, Customer chat, Portal, etc.). Each had its own
// hardcoded `toLocaleString('en-US', { month: 'short', ... })`. Centralised
// here so locale flows from `initCurrencyFromSettings` instead of being pinned.
export function formatShortDateTime(iso: string | Date | null | undefined, tz?: string | null): string {
  if (iso == null) return '\u2014';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  const opts: Intl.DateTimeFormatOptions = {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  };
  if (tz) opts.timeZone = tz;
  return d.toLocaleString(_locale, opts);
}

/**
 * Format a time-only string (hour + minute) from an ISO timestamp or Date.
 * Mirrors the `formatShortDateTime` pattern \u2014 uses the tenant locale set by
 * `initCurrencyFromSettings` so it stays consistent with the rest of the app.
 *
 * Use this instead of bare `.toLocaleTimeString(...)` call-sites (WEB-S5-008).
 * High-traffic call-sites updated: Header notifications, Dashboard,
 * TicketListPage, InvoiceListPage, CustomerListPage.
 */
export function formatTime(iso: string | Date | null | undefined, tz?: string | null): string {
  if (iso == null) return '\u2014';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  const opts: Intl.DateTimeFormatOptions = { hour: 'numeric', minute: '2-digit' };
  if (tz) opts.timeZone = tz;
  return d.toLocaleTimeString(_locale, opts);
}

/** Locale-aware integer formatter \u2014 replaces ad-hoc `n.toLocaleString()`. */
export function formatNumber(n: number | null | undefined): string {
  if (n == null || !isFinite(Number(n))) return '0';
  return new Intl.NumberFormat(_locale).format(Number(n));
}

// ─── Ticket ID ──────────────────────────────────────────────────────────────

/** Formats a ticket/order ID as "T-XXXX". Already-prefixed strings pass through. */
export function formatTicketId(orderId: string | number): string {
  const str = String(orderId);
  return str.startsWith('T-') ? str : `T-${str.padStart(4, '0')}`;
}

// ─── Idempotency Key ─────────────────────────────────────────────────────────

/**
 * Generate a collision-resistant idempotency key.
 *
 * Prefers `crypto.randomUUID()` (available in all modern browsers and Node ≥ 14.17).
 * Falls back to a `<prefix>-<timestamp>-<random>` string for older environments
 * (e.g. Safari < 15.4 in non-secure contexts).
 *
 * Consolidates the six per-endpoint duplicates flagged in WEB-UIUX-337.
 */
export function generateIdempotencyKey(prefix = 'req'): string {
  return (
    globalThis.crypto?.randomUUID?.() ??
    `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`
  );
}

// ─── Gift-card amount heuristic ─────────────────────────────────────────────

/**
 * Server is mid-migration from float-dollars to integer-cents.
 * Treat large integers (>= 1000 in magnitude) as cents so a silent server
 * schema flip doesn't render every balance 100× wrong.
 *
 * Consolidates duplicates from GiftCardsListPage and GiftCardDetailPage
 * (WEB-UIUX-550). Call `formatCurrency(dollarsFromMaybeCents(v))` or use
 * the convenience wrappers on those pages.
 */
export function dollarsFromMaybeCents(amount: number): number {
  if (!Number.isFinite(amount)) return 0;
  return Number.isInteger(amount) && Math.abs(amount) >= 1000 ? amount / 100 : amount;
}

/**
 * Return the local-calendar date of `date` as a `YYYY-MM-DD` string.
 *
 * WHY NOT `.toISOString().slice(0, 10)`:
 *   `toISOString()` always emits UTC midnight, so for a `Date` that represents
 *   any point in time after ~4 pm local time west of UTC (e.g. UTC-8 at 8 pm =
 *   UTC+next-day 4 am) the ISO string rolls over to the *next* calendar day.
 *   This produces a silent one-day drift in every date-only field — reports,
 *   filter chips, form defaults — for users west of UTC.
 *
 * USAGE:
 *   toLocalDateString(new Date())          // "2026-05-06"
 *   toLocalDateString(someDate, 'America/New_York') // explicit tz via Intl
 *
 * @param date - A `Date` object or any value accepted by the `Date` constructor.
 * @param timeZone - Optional IANA time-zone name (e.g. `"America/Los_Angeles"`).
 *   Defaults to the runtime's local zone, which is correct for UI-only code.
 *   Pass an explicit zone for server-rendered or multi-tenant contexts.
 */
export function toLocalDateString(date: Date | string | number, timeZone?: string): string {
  const d = date instanceof Date ? date : new Date(date);
  if (isNaN(d.getTime())) return '';
  const opts: Intl.DateTimeFormatOptions = {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    ...(timeZone ? { timeZone } : {}),
  };
  // `formatToParts` gives us named parts so we can assemble ISO order
  // regardless of the locale's display order.
  const parts = new Intl.DateTimeFormat('en-CA', opts).formatToParts(d);
  // en-CA natively formats as YYYY-MM-DD, so the joined string is already ISO.
  return parts.map((p) => p.value).join('');
}

// ─── Relative time ──────────────────────────────────────────────────────────

export function timeAgo(iso: string): string {
  // Ensure UTC interpretation -- server stores without Z suffix.
  // WEB-UIUX-789: also treat ISO strings carrying a numeric offset (e.g.
  // `-05:00` or `+02:00`) as fully-qualified — previously we only skipped
  // the `+` form so `-05:00` got an extra `Z` appended (malformed). Match
  // any explicit offset suffix.
  const hasOffset = /Z$|[+-]\d{2}:?\d{2}$/.test(iso);
  const ts = hasOffset ? iso : iso + 'Z';
  const diff = Date.now() - new Date(ts).getTime();
  if (diff < 0) return 'just now';
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  const weeks = Math.floor(days / 7);
  if (weeks < 5) return `${weeks}w ago`;
  return formatDate(iso);
}

// ─── Phone ──────────────────────────────────────────────────────────────────

function groupInternationalNationalNumber(countryCode: string, national: string): string {
  if (countryCode === '44') {
    if (national.startsWith('20') && national.length === 10) {
      return `${national.slice(0, 2)} ${national.slice(2, 6)} ${national.slice(6)}`;
    }
    if (national.length === 10) {
      return `${national.slice(0, 4)} ${national.slice(4)}`;
    }
  }

  if (countryCode === '61' && national.length === 9) {
    if (national.startsWith('4')) {
      return `${national.slice(0, 1)} ${national.slice(1, 5)} ${national.slice(5)}`;
    }
    return `${national.slice(0, 1)} ${national.slice(1, 5)} ${national.slice(5)}`;
  }

  if (countryCode === '52' && national.length === 10) {
    return `${national.slice(0, 2)} ${national.slice(2, 6)} ${national.slice(6)}`;
  }

  const groups: string[] = [];
  for (let i = 0; i < national.length; i += i === 0 && national.length % 3 !== 0 ? national.length % 3 : 3) {
    const size = i === 0 && national.length % 3 !== 0 ? national.length % 3 : 3;
    groups.push(national.slice(i, i + size));
  }
  return groups.filter(Boolean).join(' ');
}

function formatKnownInternationalPhone(digits: string): string | null {
  const normalized = digits.startsWith('00') ? digits.slice(2) : digits;
  const knownCodes = ['44', '61', '52'];
  const countryCode = knownCodes.find((code) => normalized.startsWith(code));
  if (!countryCode) return null;
  const national = normalized.slice(countryCode.length);
  if (!national) return `+${countryCode}`;
  return `+${countryCode} ${groupInternationalNationalNumber(countryCode, national)}`;
}

// @audit-fixed: previously this returned 11-digit non-US numbers stripped of
// their plus and any spacing because the early branches only matched US
// patterns. Non-US callers (UK +44, AU +61, etc.) now keep their original
// formatting instead of being silently mangled. The strip-then-format path
// is reserved for the two known US shapes; everything else echoes the input.
//
// WEB-UIUX-322 (2026-05-06): canonical US display unified to `+1 (XXX) XXX-XXXX`
// (parens + space, always with +1 prefix). Aligns with formatPhoneAsYouType.
// A bare 10-digit number is promoted to the +1 form — all stored US numbers
// are assumed E.164-compatible.
export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return '';
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10)
    return `+1 (${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11 && digits[0] === '1')
    return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  // International or extension-bearing input: preserve the user's formatting,
  // but make sure we keep a leading "+" if the raw string had one.
  const trimmed = phone.trim();
  const international = formatKnownInternationalPhone(
    trimmed.startsWith('+') || digits.startsWith('00') || digits.length >= 11 ? digits : '',
  );
  if (international) return international;
  if (trimmed.startsWith('+')) return trimmed;
  if (digits.length > 11) return formatKnownInternationalPhone(digits) ?? `+${digits}`;
  // WEB-FD-018 (Fixer-C12 2026-04-25): half-formatted US numbers (e.g. user
  // typed "(303) 261-19" while still entering it) used to echo back raw with
  // no `+1` hint, so display surfaces showed an inconsistent mix of
  // canonical "+1 (303) 261-1900" and raw "(303) 261-19" side-by-side. For
  // partial inputs of 4-9 digits with no leading "+" / "00" we promote to
  // a partial-progressive canonical form: keep the typed digits, add the
  // `+1` prefix and as much of the parens-space ladder as we have. Fewer
  // than 4 digits (area-code prefix only) is too ambiguous — fall through.
  if (digits.length >= 4 && digits.length < 10) {
    const a = digits.slice(0, 3);
    if (digits.length <= 6) return `+1 (${a}) ${digits.slice(3)}`;
    return `+1 (${a}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  }
  return trimmed;
}
