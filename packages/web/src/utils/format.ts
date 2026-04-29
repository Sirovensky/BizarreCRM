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
let _currencyFmt = buildFormatter(_currencyCode, _locale);

function buildFormatter(code: string, locale: string = _locale): Intl.NumberFormat {
  return new Intl.NumberFormat(locale, { style: 'currency', currency: code });
}

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
    ? buildFormatter(code, localeOverride ?? _locale)
    : _currencyFmt;
  if (amount == null || isNaN(Number(amount))) {
    return fmt.format(0);
  }
  try {
    return fmt.format(Number(amount));
  } catch (err) {
    // Fallback for unknown currency codes — surface the bad code so misconfigured
    // tenant currency settings don't hide behind a silent USD substitution.
    console.error(`[formatCurrency] format failed for code "${code}" — falling back to USD`, err);
    return new Intl.NumberFormat(localeOverride ?? _locale, { style: 'currency', currency: 'USD' }).format(Number(amount) || 0);
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
    return buildFormatter(currencyOverride ?? _currencyCode).format(0);
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
export function formatDate(iso: string | null | undefined, localeOverride?: string): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleDateString(localeOverride ?? _locale, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function formatDateTime(iso: string | null | undefined, localeOverride?: string): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleString(localeOverride ?? _locale, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

// BUILD-FIX-002: time-only formatter referenced by CalendarPage + EmployeeListPage
// but missing. Hours+minutes only, locale-aware.
export function formatTime(iso: string | Date | null | undefined, localeOverride?: string): string {
  if (iso == null) return '\u2014';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleTimeString(localeOverride ?? _locale, { hour: 'numeric', minute: '2-digit' });
}

// @audit-fixed (WEB-FF-003 / Fixer-DD 2026-04-25): short date+time used widely
// across detail pages (Leads, Customer chat, Portal, etc.). Each had its own
// hardcoded `toLocaleString('en-US', { month: 'short', ... })`. Centralised
// here so locale flows from `initCurrencyFromSettings` instead of being pinned.
export function formatShortDateTime(iso: string | Date | null | undefined): string {
  if (iso == null) return '\u2014';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleString(_locale, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
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
export function formatTime(iso: string | Date | null | undefined): string {
  if (iso == null) return '\u2014';
  const d = iso instanceof Date ? iso : new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleTimeString(_locale, { hour: 'numeric', minute: '2-digit' });
}

/** Locale-aware integer formatter \u2014 replaces ad-hoc `n.toLocaleString()`. */
export function formatNumber(n: number | null | undefined): string {
  if (n == null || !isFinite(Number(n))) return '0';
  return new Intl.NumberFormat(_locale).format(Number(n));
}

// ─── Relative time ──────────────────────────────────────────────────────────

export function timeAgo(iso: string): string {
  // Ensure UTC interpretation -- server stores without Z suffix
  const ts = iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z';
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

// @audit-fixed: previously this returned 11-digit non-US numbers stripped of
// their plus and any spacing because the early branches only matched US
// patterns. Non-US callers (UK +44, AU +61, etc.) now keep their original
// formatting instead of being silently mangled. The strip-then-format path
// is reserved for the two known US shapes; everything else echoes the input.
//
// CROSS13 decision (2026-04-17): canonical US display is `+1 (XXX)-XXX-XXXX`
// (parens + dashes, always with +1 prefix). Matches CROSS7's on-write format
// and Android's shared formatPhoneDisplay helper. A bare 10-digit number is
// promoted to the +1 form — all stored US numbers are assumed E.164-compatible.
export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return '';
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10)
    return `+1 (${digits.slice(0, 3)})-${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11 && digits[0] === '1')
    return `+1 (${digits.slice(1, 4)})-${digits.slice(4, 7)}-${digits.slice(7)}`;
  // International or extension-bearing input: preserve the user's formatting,
  // but make sure we keep a leading "+" if the raw string had one.
  const trimmed = phone.trim();
  if (trimmed.startsWith('+')) return trimmed;
  if (digits.length > 11) return `+${digits}`;
  // WEB-FD-018 (Fixer-C12 2026-04-25): half-formatted US numbers (e.g. user
  // typed "(303) 261-19" while still entering it) used to echo back raw with
  // no `+1` hint, so display surfaces showed an inconsistent mix of
  // canonical "+1 (303)-261-1900" and raw "(303) 261-19" side-by-side. For
  // partial inputs of 4-9 digits with no leading "+" / "00" we promote to
  // a partial-progressive canonical form: keep the typed digits, add the
  // `+1` prefix and as much of the parens-dashes ladder as we have. Fewer
  // than 4 digits (area-code prefix only) is too ambiguous — fall through.
  if (digits.length >= 4 && digits.length < 10) {
    const a = digits.slice(0, 3);
    if (digits.length <= 6) return `+1 (${a})-${digits.slice(3)}`;
    return `+1 (${a})-${digits.slice(3, 6)}-${digits.slice(6)}`;
  }
  return trimmed;
}
