export const DEFAULT_PRIMARY_ACCENT = '#fdeed0';

// Stored theme_primary_color values that mean "use the canonical brand
// ramp, not a tenant override". Both the current cream default and the
// retired caramel default (5c98638f, reverted in 51896b2e) are treated as
// pass-through so dark-mode cream from globals.css wins over an inline
// root-level override. Without this, every shop that ran the setup wizard
// during the caramel window keeps a stuck-orange primary even after we
// restored the CSS ramp.
const PASSTHROUGH_PRIMARY_COLORS = new Set([
  '#fdeed0', // current cream brand default
  '#a66d1f', // retired caramel default (5c98638f)
]);

type Rgb = { r: number; g: number; b: number };

const SHADE_KEYS = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900] as const;

function clampChannel(value: number): number {
  return Math.max(0, Math.min(255, Math.round(value)));
}

function normalizeHex(input: string | null | undefined): string {
  const raw = (input || '').trim();
  const match = raw.match(/^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/);
  if (!match) return DEFAULT_PRIMARY_ACCENT;
  const body = match[1];
  if (body.length === 3) {
    return `#${body.split('').map((ch) => ch + ch).join('')}`.toLowerCase();
  }
  return `#${body}`.toLowerCase();
}

function hexToRgb(hexInput: string): Rgb {
  const hex = normalizeHex(hexInput).slice(1);
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16),
  };
}

function mix(a: Rgb, b: Rgb, amount: number): Rgb {
  return {
    r: clampChannel(a.r + (b.r - a.r) * amount),
    g: clampChannel(a.g + (b.g - a.g) * amount),
    b: clampChannel(a.b + (b.b - a.b) * amount),
  };
}

function rgbTriplet(rgb: Rgb): string {
  return `${rgb.r} ${rgb.g} ${rgb.b}`;
}

function relativeLuminance(rgb: Rgb): number {
  const convert = (channel: number) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * convert(rgb.r) + 0.7152 * convert(rgb.g) + 0.0722 * convert(rgb.b);
}

function contrastTextFor(rgb: Rgb): Rgb {
  return relativeLuminance(rgb) > 0.45
    ? { r: 26, g: 11, b: 0 }
    : { r: 255, g: 255, b: 255 };
}

export function buildPrimaryAccentVars(color: string | null | undefined): Record<string, string> {
  const base = hexToRgb(color || DEFAULT_PRIMARY_ACCENT);
  const white = { r: 255, g: 255, b: 255 };
  const black = { r: 0, g: 0, b: 0 };
  const palette: Record<(typeof SHADE_KEYS)[number], Rgb> = {
    50: mix(base, white, 0.94),
    100: mix(base, white, 0.86),
    200: mix(base, white, 0.72),
    300: mix(base, white, 0.55),
    400: mix(base, white, 0.32),
    500: base,
    600: mix(base, black, 0.12),
    700: mix(base, black, 0.25),
    800: mix(base, black, 0.42),
    900: mix(base, black, 0.62),
  };

  const vars: Record<string, string> = {};
  for (const shade of SHADE_KEYS) {
    vars[`--primary-${shade}`] = rgbTriplet(palette[shade]);
  }
  vars['--primary-950'] = rgbTriplet(contrastTextFor(palette[600]));
  return vars;
}

export function applyPrimaryAccent(color: string | null | undefined): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  // Only override when an explicit non-default theme color is configured.
  // Empty values and the known canonical defaults (cream / retired caramel)
  // strip the inline overrides so the cream-everywhere ramp in globals.css
  // wins. The inline `style` on <html> beats both `:root` and `.dark` CSS
  // rules, so without this guard every shop that saved cream in setup ended
  // up with the mix()-derived light ramp overriding the dark-mode cream.
  const trimmed = (color || '').trim();
  const normalized = trimmed ? normalizeHex(trimmed) : '';
  if (!trimmed || PASSTHROUGH_PRIMARY_COLORS.has(normalized)) {
    SHADE_KEYS.forEach((shade) => root.style.removeProperty(`--primary-${shade}`));
    root.style.removeProperty('--primary-950');
    return;
  }
  const vars = buildPrimaryAccentVars(trimmed);
  for (const [key, value] of Object.entries(vars)) {
    root.style.setProperty(key, value);
  }
}
