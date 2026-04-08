/**
 * Validates a CSS color string to prevent CSS injection.
 * Only allows hex colors (#rgb, #rrggbb, #rrggbbaa).
 * Returns the fallback color if the input is invalid.
 */
export function safeColor(color: string | undefined | null, fallback = '#6b7280'): string {
  if (!color) return fallback;
  const trimmed = color.trim();
  if (/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(trimmed)) return trimmed;
  return fallback;
}
