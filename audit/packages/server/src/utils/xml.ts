/**
 * Escape a string for safe interpolation into XML content or attributes.
 * Handles the five XML special characters: & < > " '
 */
// @audit-fixed: Coerce null / undefined / non-string inputs defensively so an
// accidental `escapeXml(undefined)` can't crash a response serializer. Also
// strip 0x00-0x08 / 0x0B / 0x0C / 0x0E-0x1F — these code points are not legal
// in XML 1.0 regardless of escaping and cause parsers to error out downstream.
// eslint-disable-next-line no-control-regex
const ILLEGAL_XML_CHARS = /[\x00-\x08\x0B\x0C\x0E-\x1F]/g;
export function escapeXml(str: unknown): string {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(ILLEGAL_XML_CHARS, '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}
