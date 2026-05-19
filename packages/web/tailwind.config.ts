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
        // Runtime-themed primary ramp. Defaults are defined in globals.css
        // and AppShell replaces the CSS variables from store_config
        // `theme_primary_color` after settings load.
        // WEB-UIUX-418: semantic token for text rendered on top of a primary-
        // colored surface. Resolves to --text-on-primary in globals.css, which
        // defaults to near-black for the cream ramp. When the primary accent is
        // swapped to a dark color, AppShell must also update --text-on-primary
        // to a light value (e.g. 255 255 255). Use `text-on-primary` on any
        // element that sits on a `bg-primary-*` surface instead of hard-coding
        // `text-primary-950`.
        'on-primary': 'rgb(var(--text-on-primary) / <alpha-value>)',
        primary: {
          50:  'rgb(var(--primary-50) / <alpha-value>)',
          100: 'rgb(var(--primary-100) / <alpha-value>)',
          200: 'rgb(var(--primary-200) / <alpha-value>)',
          300: 'rgb(var(--primary-300) / <alpha-value>)',
          400: 'rgb(var(--primary-400) / <alpha-value>)',
          500: 'rgb(var(--primary-500) / <alpha-value>)',
          600: 'rgb(var(--primary-600) / <alpha-value>)',
          700: 'rgb(var(--primary-700) / <alpha-value>)',
          800: 'rgb(var(--primary-800) / <alpha-value>)',
          900: 'rgb(var(--primary-900) / <alpha-value>)',
          950: 'rgb(var(--primary-950) / <alpha-value>)',
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
          50:  'rgb(var(--primary-50) / <alpha-value>)',
          100: 'rgb(var(--primary-100) / <alpha-value>)',
          200: 'rgb(var(--primary-200) / <alpha-value>)',
          300: 'rgb(var(--primary-300) / <alpha-value>)',
          400: 'rgb(var(--primary-400) / <alpha-value>)',
          500: 'rgb(var(--primary-500) / <alpha-value>)',
          600: 'rgb(var(--primary-600) / <alpha-value>)',
          700: 'rgb(var(--primary-700) / <alpha-value>)',
          800: 'rgb(var(--primary-800) / <alpha-value>)',
          900: 'rgb(var(--primary-900) / <alpha-value>)',
          950: 'rgb(var(--primary-950) / <alpha-value>)',
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
      // App UI fonts: DM Serif Display (headings), DM Sans (body).
       // Corporate/landing fonts: Futura, Bebas Neue, Saved By Zero.
      fontFamily: {
        display: ['DM Serif Display', 'Georgia', 'serif'],
        sans: ['DM Sans', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
        logo: ['Saved By Zero', 'DM Serif Display', 'Georgia', 'serif'],
        // Corporate brand fonts — landing page + marketing only
        'brand-display': ['Bebas Neue', 'Futura', 'system-ui', 'sans-serif'],
        'brand-sans': ['Futura', 'system-ui', '-apple-system', 'sans-serif'],
        'brand-logo': ['Saved By Zero', 'Bebas Neue', 'Futura', 'sans-serif'],
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
      // @audit-fixed (WEB-UIUX-299 2026-05-06): canonical z-index scale.
      // Existing raw values (60, 80, 100, 101, 9998, 9999) were undocumented,
      // causing modal-on-modal stacking bugs (e.g. ConfirmDialog behind
      // QuickSmsModal). Named tokens make intent explicit and enforce ordering.
      // Migration is incremental: new/edited components use `z-modal` etc.;
      // existing raw `z-[N]` classes continue working until replaced.
      //
      // Layer order (low → high):
      //   dropdown (40) < popover (50) < modalOverlay (90) < modal (100)
      //   < confirmDialog (110) < toast (120) < tooltip (130)
      zIndex: {
        dropdown:      '40',   // Select menus, autocomplete panels
        popover:       '50',   // Popovers, date-pickers, colour pickers
        modalOverlay:  '90',   // Backdrop behind a modal
        modal:         '100',  // First-level modal / drawer
        confirmDialog: '110',  // ConfirmDialog layered over a modal
        toast:         '120',  // Toast / snackbar notifications
        tooltip:       '130',  // Tooltips — always on top
      },
      // @audit-fixed (WEB-UIUX-565 2026-05-06): canonical elevation / shadow scale.
      // Previously cards used shadow-sm, modals shadow-2xl, and dropdowns varied
      // between shadow-lg and shadow-xl arbitrarily. WEB-UIUX-12 (tick 3) locked
      // lead modals to shadow-xl; this comment codifies the full ladder so future
      // components use consistent values without per-PR negotiation.
      //
      // Elevation ladder (low → high):
      //   button / card   → shadow-sm   (Tailwind default: 0 1px 2px)
      //   popover         → shadow-md   (Tailwind default: 0 4px 6px)
      //   dropdown        → shadow-lg   (Tailwind default: 0 10px 15px)
      //   modal / drawer  → shadow-xl   (Tailwind default: 0 20px 25px)
      //   toast / snackbar→ shadow-2xl  (Tailwind default: 0 25px 50px)
      //
      // No custom values are defined here — Tailwind's built-in scale covers every
      // tier. Keep new components within these five steps; do not introduce
      // shadow-3xl or arbitrary shadow-[…] values without updating this ladder.
      boxShadow: {},
    },
  },
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  plugins: [require('tailwindcss-animate')],
} satisfies Config;
