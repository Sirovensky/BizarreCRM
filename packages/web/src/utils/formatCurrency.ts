/**
 * Portal-safe currency formatter.
 *
 * Re-exports a standalone `formatCurrency` function that accepts an explicit
 * currency code so portal pages (which don't have access to the global shop
 * settings initialised by AppShell) can format amounts correctly.
 *
 * The locale argument defaults to the browser's preferred language so that
 * number separators, decimal symbol, etc. match the visitor's expectations.
 */

export function formatCurrency(
  value: number,
  currencyCode = 'USD',
  locale?: string,
): string {
  const resolvedLocale = locale ?? (typeof navigator !== 'undefined' ? navigator.language : 'en-US');
  try {
    return new Intl.NumberFormat(resolvedLocale, {
      style: 'currency',
      currency: currencyCode,
    }).format(value);
  } catch {
    // Fallback for unknown currency codes
    return new Intl.NumberFormat(resolvedLocale, {
      style: 'currency',
      currency: 'USD',
    }).format(value);
  }
}
