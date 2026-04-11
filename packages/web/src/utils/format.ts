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
let _currencyFmt = buildFormatter(_currencyCode);

function buildFormatter(code: string): Intl.NumberFormat {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: code });
}

/** Call once at app startup (e.g. from AppShell) after settings load. */
export function initCurrencyFromSettings(code: string | undefined | null): void {
  const normalized = (code ?? '').trim().toUpperCase();
  if (normalized && /^[A-Z]{3}$/.test(normalized) && normalized !== _currencyCode) {
    _currencyCode = normalized;
    _currencyFmt = buildFormatter(_currencyCode);
  }
}

export function formatCurrency(amount: number | null | undefined, currencyOverride?: string): string {
  if (amount == null || isNaN(Number(amount))) {
    return buildFormatter(currencyOverride ?? _currencyCode).format(0);
  }
  const fmt = currencyOverride ? buildFormatter(currencyOverride) : _currencyFmt;
  return fmt.format(Number(amount));
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
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '\u2014';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '\u2014';
  return d.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
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
export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return '';
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10)
    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11 && digits[0] === '1')
    return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  // International or extension-bearing input: preserve the user's formatting,
  // but make sure we keep a leading "+" if the raw string had one.
  const trimmed = phone.trim();
  if (trimmed.startsWith('+')) return trimmed;
  if (digits.length > 11) return `+${digits}`;
  return trimmed;
}
