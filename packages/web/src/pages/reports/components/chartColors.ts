/**
 * Theme-aware chart palette for the Reports section.
 *
 * Chart libraries (Recharts) receive fill/stroke as raw values — they cannot
 * read Tailwind utility classes or respond to the `dark:` variant at runtime.
 * We therefore use CSS custom properties (set by the app's theme layer) so
 * dark-mode switches propagate automatically without JS-side detection.
 *
 * Each entry is a CSS `var()` expression with a light-mode fallback so charts
 * render correctly even if the theme CSS has not yet loaded.
 */

// Multi-series palette — maps to brand/semantic tokens when available,
// falls back to the equivalent Tailwind 500-level value.
export const CHART_PALETTE: readonly string[] = [
  'var(--chart-color-1, #3b82f6)',   // blue-500   — primary
  'var(--chart-color-2, #10b981)',   // emerald-500 — success
  'var(--chart-color-3, #f59e0b)',   // amber-500  — warning
  'var(--chart-color-4, #ef4444)',   // red-500    — error / danger
  'var(--chart-color-5, #8b5cf6)',   // violet-500 — accent
  'var(--chart-color-6, #ec4899)',   // pink-500   — extra-1
  'var(--chart-color-7, #06b6d4)',   // cyan-500   — extra-2
  'var(--chart-color-8, #f97316)',   // orange-500 — extra-3
  'var(--chart-color-9, #84cc16)',   // lime-500   — extra-4
  'var(--chart-color-10, #6366f1)',  // indigo-500 — extra-5
] as const;

// Semantic single-series colors
export const CHART_COLOR_PRIMARY  = 'var(--chart-color-1, #3b82f6)';
export const CHART_COLOR_SUCCESS  = 'var(--chart-color-2, #10b981)';
export const CHART_COLOR_WARNING  = 'var(--chart-color-3, #f59e0b)';
export const CHART_COLOR_DANGER   = 'var(--chart-color-4, #ef4444)';
export const CHART_COLOR_NEUTRAL  = 'var(--chart-color-neutral, #9ca3af)';
export const CHART_COLOR_MUTED    = 'var(--chart-color-muted, #d1d5db)';

// Recharts Tooltip contentStyle — uses surface CSS vars so it auto-switches
// between light (surface-100/900) and dark (surface-800) backgrounds.
export const CHART_TOOLTIP_STYLE: Record<string, string | number> = {
  backgroundColor: 'var(--color-surface-800, #1f2937)',
  border: '1px solid var(--color-surface-700, #374151)',
  borderRadius: 8,
  color: 'var(--color-surface-50, #f9fafb)',
};

// Axis tick fill — matches the existing constant already used in ReportsPage
export const CHART_AXIS_TICK_FILL = 'var(--reports-chart-axis-tick, rgb(var(--surface-500)))';
