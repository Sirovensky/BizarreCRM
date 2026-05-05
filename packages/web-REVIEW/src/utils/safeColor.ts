/**
 * Validates a CSS color string to prevent CSS injection.
 *
 * INTENTIONAL: only hex colors (#rgb, #rgba, #rrggbb, #rrggbbaa) are accepted.
 * Anything else — including `currentColor`, named colors (`red`), `rgb(...)`,
 * `hsl(...)`, and CSS variables (`var(--brand-500)`) — falls back to grey.
 * If you need theme-aware colors, use Tailwind classes; if you need a custom
 * palette to flow into inline `style`, store the resolved hex in app state
 * before passing it through here.
 *
 * WEB-FD-020: Callers passing CSS vars or `currentColor` were silently
 * downgraded to grey. The doc here makes the constraint explicit.
 *
 * Returns the fallback color if the input is invalid.
 */
export function safeColor(color: string | undefined | null, fallback = '#6b7280'): string {
  if (!color) return fallback;
  const trimmed = color.trim();
  if (/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(trimmed)) return trimmed;
  return fallback;
}

// Alias that makes the hex-only constraint explicit at the call site.
// Prefer this name in new code; `safeColor` remains for back-compat.
export const safeHexColor = safeColor;
