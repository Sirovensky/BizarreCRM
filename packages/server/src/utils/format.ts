export function formatCurrency(amount: number, currency: string = 'USD'): string {
  // @audit-fixed: Intl.NumberFormat throws RangeError on NaN / non-finite
  // amounts in some Node releases and on unknown ISO currency codes like
  // "USD ". Defensive normalization so a bad DB row can't crash an invoice.
  const safeAmount = Number.isFinite(amount) ? amount : 0;
  const safeCurrency = typeof currency === 'string' && /^[A-Z]{3}$/.test(currency.trim().toUpperCase())
    ? currency.trim().toUpperCase()
    : 'USD';
  try {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: safeCurrency }).format(safeAmount);
  } catch {
    return `$${safeAmount.toFixed(2)}`;
  }
}

// SW-D16: Accept timezone parameter, fallback to America/Denver
export function formatDate(date: string | Date, timezone: string = 'America/Denver'): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric', timeZone: timezone });
}

export function formatDateTime(date: string | Date, timezone: string = 'America/Denver'): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return d.toLocaleString('en-US', { year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: timezone });
}

/** Read store_timezone and store_currency from the DB for use with format helpers.
 *  Returns { timezone, currency } with sensible defaults. */
export function getStoreLocale(db: any): { timezone: string; currency: string } {
  const tz = (db.prepare("SELECT value FROM store_config WHERE key = 'store_timezone'").get() as any)?.value;
  const cur = (db.prepare("SELECT value FROM store_config WHERE key = 'store_currency'").get() as any)?.value;
  return {
    timezone: tz || 'America/Denver',
    currency: cur || 'USD',
  };
}

export function generateOrderId(prefix: string, id: number): string {
  return `${prefix}-${id.toString().padStart(4, '0')}`;
}
