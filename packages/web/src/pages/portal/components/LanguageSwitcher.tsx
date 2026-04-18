/**
 * LanguageSwitcher — minimal EN/ES toggle plus accessibility controls
 * (font size, high contrast, dark mode). Kept compact so it can live in
 * the portal header without dominating the layout.
 *
 * The a11y toggles write body classes that portal-enrichment.css picks up;
 * they persist across sessions via localStorage.
 */
import React, { useCallback, useEffect, useState } from 'react';
import { usePortalI18n, type Locale } from '../i18n';

type ContrastMode = 'normal' | 'high';
type Theme = 'light' | 'dark';

const FONT_KEY = 'portal_font_scale';
const CONTRAST_KEY = 'portal_contrast';
const THEME_KEY = 'portal_theme';

function applyFontScale(scale: number): void {
  document.documentElement.style.setProperty('--portal-font-scale', String(scale));
}

function applyContrast(mode: ContrastMode): void {
  document.body.classList.toggle('portal-high-contrast', mode === 'high');
}

function applyTheme(theme: Theme): void {
  document.body.classList.toggle('dark', theme === 'dark');
}

function readInitialFontScale(): number {
  try {
    const raw = localStorage.getItem(FONT_KEY);
    const n = raw ? parseFloat(raw) : 1;
    return Number.isFinite(n) && n > 0 ? n : 1;
  } catch {
    return 1;
  }
}

function readInitialContrast(): ContrastMode {
  try {
    return (localStorage.getItem(CONTRAST_KEY) as ContrastMode) || 'normal';
  } catch {
    return 'normal';
  }
}

function readInitialTheme(): Theme {
  try {
    const saved = localStorage.getItem(THEME_KEY);
    if (saved === 'light' || saved === 'dark') return saved;
  } catch {
    /* ignore */
  }
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return 'light';
}

export function LanguageSwitcher(): React.ReactElement {
  const { locale, setLocale, t } = usePortalI18n();
  const [fontScale, setFontScale] = useState<number>(() => readInitialFontScale());
  const [contrast, setContrast] = useState<ContrastMode>(() => readInitialContrast());
  const [theme, setTheme] = useState<Theme>(() => readInitialTheme());

  useEffect(() => {
    applyFontScale(fontScale);
    try {
      localStorage.setItem(FONT_KEY, String(fontScale));
    } catch {
      /* ignore */
    }
  }, [fontScale]);

  useEffect(() => {
    applyContrast(contrast);
    try {
      localStorage.setItem(CONTRAST_KEY, contrast);
    } catch {
      /* ignore */
    }
  }, [contrast]);

  useEffect(() => {
    applyTheme(theme);
    try {
      localStorage.setItem(THEME_KEY, theme);
    } catch {
      /* ignore */
    }
  }, [theme]);

  const adjustFont = useCallback((delta: number): void => {
    setFontScale((prev) => {
      const next = Math.min(1.5, Math.max(0.85, Math.round((prev + delta) * 100) / 100));
      return next;
    });
  }, []);

  return (
    <div
      role="toolbar"
      aria-label="Portal accessibility and language controls"
      className="flex items-center gap-2 flex-wrap text-xs"
    >
      <div className="flex items-center gap-1" role="radiogroup" aria-label={t('language.label')}>
        {(['en', 'es'] as Locale[]).map((code) => (
          <button
            key={code}
            type="button"
            role="radio"
            aria-checked={locale === code}
            onClick={() => setLocale(code)}
            className={`rounded px-2 py-1 font-medium ${
              locale === code
                ? 'bg-primary-600 text-white'
                : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-200 dark:hover:bg-gray-600'
            }`}
          >
            {code.toUpperCase()}
          </button>
        ))}
      </div>

      <button
        type="button"
        onClick={() => adjustFont(-0.05)}
        aria-label={t('a11y.font_decrease')}
        className="rounded w-7 h-7 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-200 font-bold hover:bg-gray-200 dark:hover:bg-gray-600"
      >
        A-
      </button>
      <button
        type="button"
        onClick={() => adjustFont(0.05)}
        aria-label={t('a11y.font_increase')}
        className="rounded w-7 h-7 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-200 font-bold hover:bg-gray-200 dark:hover:bg-gray-600"
      >
        A+
      </button>

      <button
        type="button"
        onClick={() => setContrast((prev) => (prev === 'high' ? 'normal' : 'high'))}
        aria-label={t('a11y.contrast_toggle')}
        aria-pressed={contrast === 'high'}
        className={`rounded w-7 h-7 font-bold ${
          contrast === 'high'
            ? 'bg-yellow-300 text-black'
            : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-200 dark:hover:bg-gray-600'
        }`}
      >
        {'\u25D1'}
      </button>

      <button
        type="button"
        onClick={() => setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'))}
        aria-label={t('a11y.dark_toggle')}
        aria-pressed={theme === 'dark'}
        className="rounded w-7 h-7 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-200 dark:hover:bg-gray-600"
      >
        {theme === 'dark' ? '\u2600' : '\u263E'}
      </button>
    </div>
  );
}
