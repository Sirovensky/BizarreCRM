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
          50:  '#fffdf8',
          100: '#fdf5e1',
          200: '#fdeed0',   // ← brand cream (the canonical primary)
          300: '#f5dca7',
          400: '#e9c477',
          500: '#d6a54b',   // mid-tone, AA on light surfaces
          600: '#a66d1f',   // caramel — Android LightColorScheme parity
          700: '#7d4e14',
          800: '#56330b',
          900: '#2b1400',   // onPrimary dark brown for cream fills
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
          50:  '#fffdf8',
          100: '#fdf5e1',
          200: '#fdeed0',
          300: '#f5dca7',
          400: '#e9c477',
          500: '#d6a54b',
          600: '#a66d1f',
          700: '#7d4e14',
          800: '#56330b',
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
          50: '#fafafa',
          100: '#f4f4f5',
          200: '#e4e4e7',
          300: '#d4d4d8',
          400: '#a1a1aa',
          500: '#71717a',
          600: '#52525b',
          700: '#3f3f46',
          800: '#27272a',
          900: '#18181b',
          950: '#09090b',
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
  plugins: [],
} satisfies Config;
