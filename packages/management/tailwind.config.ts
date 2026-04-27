import type { Config } from 'tailwindcss';
import path from 'path';

const rendererRoot = path.resolve(__dirname, 'src/renderer');

export default {
  content: [
    path.join(rendererRoot, 'index.html'),
    path.join(rendererRoot, 'src/**/*.{js,ts,jsx,tsx}'),
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // POS redesign wave (2026-04-24) — brand cream `#fdeed0` is the
        // project-wide primary across Android, web, and management. Dark
        // end of ramp = onPrimary `#2b1400` dark brown for AA on light fills.
        primary: {
          50:  '#fffefb',
          100: '#fefcf4',
          200: '#fdf8e8',
          300: '#fdf4d6',
          400: '#fdf0c8',
          500: '#fdeed0',   // ← brand cream (canonical primary — matches iOS/Android dark accent)
          600: '#f5dca7',   // warm honey (hover on dark surfaces)
          700: '#e9c477',   // golden (active/focus on dark)
          800: '#d6a54b',   // amber
          900: '#2b1400',   // onPrimary dark brown
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
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
      animation: {
        'slide-in': 'slideIn 0.2s ease-out',
        'fade-in': 'fadeIn 0.15s ease-out',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
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
