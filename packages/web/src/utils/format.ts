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

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleDateString(_locale, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleString(_locale, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
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
  return trimmed;
}
