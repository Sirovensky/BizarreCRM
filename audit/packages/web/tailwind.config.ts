import type { Config } from 'tailwindcss';
import path from 'path';

const webRoot = path.resolve(__dirname);

export default {
  content: [
    path.join(webRoot, 'index.html'),
    path.join(webRoot, 'src/**/*.{js,ts,jsx,tsx}'),
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // POS redesign wave (2026-04-24) — brand cream `#fdeed0` is the
        // project-wide primary (replacing previous orange). Dark end of the
        // ramp pairs with `onPrimary #2b1400` for AA on light backgrounds.
        primary: {
          50:  '#fffefb',
          100: '#fefcf4',
          200: '#fdf8e8',
          300: '#fdf4d6',
          400: '#fdf0c8',
          500: '#fdeed0',   // ← brand cream (canonical primary — matches iOS/Android dark accent)
          600: '#f5dca7',   // warm honey (hover on dark surfaces)
          700: '#e9c477',   // golden (active/focus on dark)
          800: '#d6a54b',   // amber (light-mode accent, AA on white at 2.8:1 with dark text)
          900: '#2b1400',   // onPrimary dark brown (AA on cream fills — 10.7:1)
          950: '#1a0b00',
        },
        // @audit-fixed (WEB-FM-002 / Fixer-K 2026-04-24): `bg-brand-*` /
        // `text-brand-*` / `border-brand-*` are referenced 21+ times across
        // Sidebar, Header, CommandPalette, DashboardPage, etc. but the palette
        // was never declared — Tailwind silently drops the rules so the
        // notification highlight, sidebar active indicator, and command-palette
        // focus row rendered unstyled. Aliasing `brand` to the canonical
        // `primary` ramp keeps the existing class names working without a
        // 21-site rename. If a distinct brand ramp is ever introduced, swap
        // these values; the keys are stable.
        brand: {
          50:  '#fffefb',
          100: '#fefcf4',
          200: '#fdf8e8',
          300: '#fdf4d6',
          400: '#fdf0c8',
          500: '#fdeed0',
          600: '#f5dca7',
          700: '#e9c477',
          800: '#d6a54b',
          900: '#2b1400',
          950: '#1a0b00',
        },
        accent: {
          50: '#eff6ff',
          100: '#dbeafe',
          200: '#bfdbfe',
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          800: '#1e40af',
          900: '#1e3a8a',
        },
        surface: {
          // Surface ramp via CSS vars so dark mode can swap to iPad's
          // Liquid Glass palette while light mode keeps the warm stone tones
          // that complement the cream primary. Light values + dark overrides
          // live in src/styles/globals.css under :root and .dark.
          //
          // Light = stone (warm neutrals: #FAFAF9 → #0C0A09).
          // Dark  = iPad mockup hex (mockups/ios-ipad-pos.html):
          //   --bg-deep #050403, --bg #0c0b09, --surface-solid #141211,
          //   --surface-elev #1b1917. Cream primary stays identical.
          50:  'rgb(var(--surface-50) / <alpha-value>)',
          100: 'rgb(var(--surface-100) / <alpha-value>)',
          200: 'rgb(var(--surface-200) / <alpha-value>)',
          300: 'rgb(var(--surface-300) / <alpha-value>)',
          400: 'rgb(var(--surface-400) / <alpha-value>)',
          500: 'rgb(var(--surface-500) / <alpha-value>)',
          600: 'rgb(var(--surface-600) / <alpha-value>)',
          700: 'rgb(var(--surface-700) / <alpha-value>)',
          800: 'rgb(var(--surface-800) / <alpha-value>)',
          900: 'rgb(var(--surface-900) / <alpha-value>)',
          950: 'rgb(var(--surface-950) / <alpha-value>)',
        },
        // WEB-FQ-004 / FIXED-by-Fixer-JJJ 2026-04-25 — semantic status palette.
        // 244+ raw `text-red-*`/`bg-green-*` callsites currently bake the brand
        // status colors into hex via Tailwind's default ramp, so any future
        // re-tone (e.g. error red → cardinal) requires a global find-replace.
        // These aliased ramps map to the existing default Tailwind values so
        // adoption is incremental: new code uses `text-error-500`,
        // `border-warning-300`, etc.; old `text-red-*` keeps working until
        // migrated. Swap these maps in one place to retone the entire app.
        error: {
          50: '#fef2f2',
          100: '#fee2e2',
          200: '#fecaca',
          300: '#fca5a5',
          400: '#f87171',
          500: '#ef4444',
          600: '#dc2626',
          700: '#b91c1c',
          800: '#991b1b',
          900: '#7f1d1d',
          950: '#450a0a',
        },
        success: {
          50: '#f0fdf4',
          100: '#dcfce7',
          200: '#bbf7d0',
          300: '#86efac',
          400: '#4ade80',
          500: '#22c55e',
          600: '#16a34a',
          700: '#15803d',
          800: '#166534',
          900: '#14532d',
          950: '#052e16',
        },
        warning: {
          50: '#fffbeb',
          100: '#fef3c7',
          200: '#fde68a',
          300: '#fcd34d',
          400: '#fbbf24',
          500: '#f59e0b',
          600: '#d97706',
          700: '#b45309',
          800: '#92400e',
          900: '#78350f',
          950: '#451a03',
        },
        info: {
          50: '#eff6ff',
          100: '#dbeafe',
          200: '#bfdbfe',
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          800: '#1e40af',
          900: '#1e3a8a',
          950: '#172554',
        },
      },
      // WEB-FQ-001 / WEB-FE-003 (Fixer-Z 2026-04-25): canonical brand fonts
       // per §project_brand_fonts. `display` is the new heading family
       // (Bebas Neue), `sans` is body (Futura Medium → Jost free proxy on
       // Google Fonts), `logo` keeps Saved By Zero as the head of the chain
       // even though the @font-face is still pending self-host (falls back
       // to Bebas Neue, then Jost — never Inter again). Existing
       // `font-sans` / `font-mono` consumers stay valid; `font-display`
       // and `font-logo` are new tokens for headings + the logo wordmark.
      fontFamily: {
        display: ['Bebas Neue', 'Jost', 'system-ui', 'sans-serif'],
        sans: ['Jost', 'Futura', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
        logo: ['Saved By Zero', 'Bebas Neue', 'Jost', 'sans-serif'],
      },
      animation: {
        'slide-in': 'slideIn 0.2s ease-out',
        'fade-in': 'fadeIn 0.15s ease-out',
      },
      keyframes: {
        slideIn: {
          '0%': { transform: 'translateX(-10px)', opacity: '0' },
          '100%': { transform: 'translateX(0)', opacity: '1' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
      },
    },
  },
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  plugins: [require('tailwindcss-animate')],
} satisfies Config;
