/**
 * HTML / SMS escape helpers.
 *
 * WHY THIS EXISTS (criticalaudit-rerun §24 - AU3):
 *   Template interpolation for email bodies MUST HTML-escape user-controlled
 *   values (customer name, ticket notes, etc.) to prevent stored XSS when those
 *   values flow into HTML email bodies. SMS bodies are plain-text but must strip
 *   control characters because some providers barf on 0x00-0x1F and because a
 *   rogue NUL byte in a template could break outbound payloads.
 *
 *   Kept deliberately small and dependency-free so both `services/automations.ts`
 *   and `services/notifications.ts` can import it without dragging cheerio, dompurify,
 *   or any other HTML parser into the hot path.
 */
const HTML_ESCAPES: Readonly<Record<string, string>> = Object.freeze({
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#x27;',
  '/': '&#x2F;',
});

/**
 * Escape HTML special characters so user-controlled strings can be safely
 * interpolated into HTML email bodies. Returns a new string — input is not mutated.
 */
export function escapeHtml(input: string): string {
  if (input === null || input === undefined) return '';
  return String(input).replace(/[&<>"'/]/g, (ch) => HTML_ESCAPES[ch] ?? ch);
}

/**
 * Strip control chars (0x00-0x1F, 0x7F) that could break SMS provider payloads
 * or allow injection of protocol-level characters. Preserves newlines/tab
 * intentionally — SMS provider APIs accept them and template authors use them.
 * Returns a new string.
 */
export function stripSmsControlChars(input: string): string {
  if (input === null || input === undefined) return '';
  // eslint-disable-next-line no-control-regex
  return String(input).replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}
