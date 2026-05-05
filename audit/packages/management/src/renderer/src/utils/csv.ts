/**
 * Minimal CSV exporter for dashboard tables. Produces RFC-4180 compliant
 * rows: fields containing commas, quotes, or newlines are wrapped in
 * double quotes and inner quotes are doubled. No library dependency.
 *
 * Client-side only — the dashboard never ships user data to disk through
 * anything else, so having an exfil path via "Download CSV" needs to be
 * an explicit operator action. This helper does not save to disk by
 * itself; the caller wires up the anchor-click download so the intent
 * is obvious at every use site.
 */

export function escapeCsvField(value: unknown): string {
  if (value === null || value === undefined) return '';
  const s = String(value);
  // RFC-4180 §2 note 2: fields starting with =, +, @, or - are interpreted as
  // formulas by spreadsheet applications. Prefix with a single quote so the
  // field is treated as a text literal. The quote is stripped by most parsers
  // but is visible as =' in raw CSV; this is the widely-accepted safe default.
  const needsFormulaGuard = s.length > 0 && /^[=+@\-]/.test(s);
  const guarded = needsFormulaGuard ? "'" + s : s;
  if (/[",\r\n]/.test(guarded)) {
    return '"' + guarded.replace(/"/g, '""') + '"';
  }
  return guarded;
}

export function toCsv<T extends Record<string, unknown>>(columns: readonly string[], rows: readonly T[]): string {
  const header = columns.map(escapeCsvField).join(',');
  const body = rows.map((r) => columns.map((c) => escapeCsvField(r[c])).join(',')).join('\n');
  return header + '\n' + body + '\n';
}

export function downloadCsv(filename: string, csv: string): void {
  // UTF-8 BOM so Excel opens non-ASCII columns (accented names etc.) correctly.
  const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
