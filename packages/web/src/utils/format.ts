/**
 * Shared formatting utilities.
 *
 * These replace the many per-file duplicates of formatCurrency / formatDate /
 * formatDateTime / formatPhone / timeAgo.  Currency currently defaults to USD
 * but reads from a global setting when one is wired up.
 */

// ─── Currency ───────────────────────────────────────────────────────────────

const CURRENCY_CODE = 'USD'; // TODO: read from global shop settings

const currencyFmt = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: CURRENCY_CODE,
});

export function formatCurrency(amount: number | null | undefined): string {
  if (amount == null || isNaN(Number(amount))) return '$0.00';
  return currencyFmt.format(Number(amount));
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

export function formatPhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10)
    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11 && digits[0] === '1')
    return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  return phone;
}
