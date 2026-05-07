import { create } from 'zustand';

interface UiState {
  sidebarCollapsed: boolean;
  mobileSidebarOpen: boolean;
  theme: 'light' | 'dark' | 'system';
  commandPaletteOpen: boolean;
  // WCAG 2.1.4: single-key shortcuts must be disableable or remappable.
  keyboardShortcutsEnabled: boolean;
  toggleSidebar: () => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  setMobileSidebarOpen: (open: boolean) => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
  setCommandPaletteOpen: (open: boolean) => void;
  setKeyboardShortcutsEnabled: (enabled: boolean) => void;
}

// Resolve the registrable parent domain so a theme cookie set on the marketing
// host (`bizarrecrm.com`) is visible on every tenant subdomain
// (`iostest.bizarrecrm.com`, etc). For dev (`localhost`) we return null and
// skip the Domain attribute — same-origin already handles persistence.
const resolveCookieBaseDomain = (): string | null => {
  if (typeof window === 'undefined') return null;
  const host = window.location.hostname;
  if (!host || host === 'localhost' || host.endsWith('.localhost')) return null;
  // Plain IPv4 / IPv6 — Domain attr disallowed.
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host) || host.includes(':')) return null;
  const parts = host.split('.');
  if (parts.length < 2) return null;
  // Take the last two labels: tenant.bizarrecrm.com → bizarrecrm.com.
  // The leading dot makes the cookie visible to every subdomain.
  return '.' + parts.slice(-2).join('.');
};

const THEME_COOKIE = 'theme';

const readThemeCookie = (): 'light' | 'dark' | 'system' | null => {
  if (typeof document === 'undefined') return null;
  const raw = document.cookie || '';
  for (const part of raw.split(';')) {
    const [k, v] = part.trim().split('=');
    if (k === THEME_COOKIE) {
      if (v === 'light' || v === 'dark' || v === 'system') return v;
      return null;
    }
  }
  return null;
};

const writeThemeCookie = (theme: 'light' | 'dark' | 'system'): void => {
  if (typeof document === 'undefined') return;
  const domain = resolveCookieBaseDomain();
  // 1 year in seconds. SameSite=Lax so cross-subdomain top-level navigation
  // (clicking a link from landing to iostest.bizarrecrm.com) still sends it.
  const parts = [
    `${THEME_COOKIE}=${theme}`,
    'path=/',
    'max-age=31536000',
    'samesite=lax',
  ];
  if (domain) parts.push(`domain=${domain}`);
  if (typeof window !== 'undefined' && window.location.protocol === 'https:') {
    parts.push('secure');
  }
  try { document.cookie = parts.join('; '); }
  catch (err) { console.warn('[uiStore] theme cookie write failed', err); }
};

const getInitialTheme = (): 'light' | 'dark' | 'system' => {
  // Cookie wins over localStorage so a theme picked on the marketing host
  // (bizarrecrm.com) carries over to the tenant login subdomain — the two
  // are different localStorage origins so localStorage alone can't bridge
  // them. The cookie is set with Domain=.bizarrecrm.com and shared across
  // every subdomain.
  const fromCookie = readThemeCookie();
  if (fromCookie) return fromCookie;
  try {
    const stored = localStorage.getItem('theme');
    if (stored === 'light' || stored === 'dark' || stored === 'system') return stored;
  } catch (err) {
    // localStorage may throw in private mode / sandboxed iframes — fall through to default.
    console.warn('[uiStore] getInitialTheme: localStorage read failed', err);
  }
  // Default: light. Users on a dark-mode OS were silently getting the app
  // in dark by default ('system' previously), which most operators don't
  // want for a POS / counter surface. Operators who want dark can flip it
  // in Settings → UI; the choice persists in localStorage and survives
  // reloads.
  return 'light';
};

const applyTheme = (theme: 'light' | 'dark' | 'system') => {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  const isDark = theme === 'dark' || (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.classList.toggle('dark', isDark);
};

// Wrap a theme apply with the `theme-transition` class so the surface CSS
// vars cross-fade across the whole tree (see globals.css `html.theme-transition *`
// rule). Without this every element repaints instantly at the same frame and
// the swap reads as a strobe. Class is removed after the transition window
// (200ms anim + 120ms slack) so per-element transitions don't keep firing on
// unrelated interactions like hover/focus.
const THEME_TRANSITION_MS = 320;
let pendingThemeTransitionTimer: ReturnType<typeof setTimeout> | null = null;
const applyThemeWithFade = (theme: 'light' | 'dark' | 'system') => {
  if (typeof document === 'undefined') {
    applyTheme(theme);
    return;
  }
  const root = document.documentElement;
  // If the user mashes the toggle, restart the window instead of stacking
  // multiple removals racing each other.
  if (pendingThemeTransitionTimer !== null) {
    clearTimeout(pendingThemeTransitionTimer);
  }
  root.classList.add('theme-transition');
  applyTheme(theme);
  pendingThemeTransitionTimer = setTimeout(() => {
    root.classList.remove('theme-transition');
    pendingThemeTransitionTimer = null;
  }, THEME_TRANSITION_MS);
};

// Apply on load (SSR-safe)
if (typeof window !== 'undefined') {
  applyTheme(getInitialTheme());
}

const readSidebarCollapsed = (): boolean => {
  try {
    return localStorage.getItem('sidebarCollapsed') === 'true';
  } catch {
    return false;
  }
};

// WCAG 2.1.4: default ON, but persisted so a user who opts out stays opted out.
const readKeyboardShortcutsEnabled = (): boolean => {
  try {
    const stored = localStorage.getItem('keyboardShortcutsEnabled');
    // Explicit 'false' opts out; anything else (including null for first-run) stays enabled.
    return stored !== 'false';
  } catch {
    return true;
  }
};

const safeWrite = (key: string, value: string): void => {
  try {
    localStorage.setItem(key, value);
  } catch (err) {
    // ignore — private mode etc.
    console.warn(`[uiStore] safeWrite("${key}") failed; setting will not persist`, err);
  }
};

export const useUiStore = create<UiState>((set) => ({
  sidebarCollapsed: readSidebarCollapsed(),
  mobileSidebarOpen: false,
  theme: getInitialTheme(),
  commandPaletteOpen: false,
  keyboardShortcutsEnabled: readKeyboardShortcutsEnabled(),

  toggleSidebar: () =>
    set((state) => {
      const collapsed = !state.sidebarCollapsed;
      safeWrite('sidebarCollapsed', String(collapsed));
      return { sidebarCollapsed: collapsed };
    }),

  setSidebarCollapsed: (collapsed: boolean) => {
    safeWrite('sidebarCollapsed', String(collapsed));
    set({ sidebarCollapsed: collapsed });
  },

  setMobileSidebarOpen: (open: boolean) => set({ mobileSidebarOpen: open }),

  setTheme: (theme: 'light' | 'dark' | 'system') => {
    // WEB-FI-018 (Fixer-SSS 2026-04-25): order matters here — the
    // `handleSystemThemeChange` matchMedia listener below reads
    // `useUiStore.getState().theme` to decide whether to re-apply
    // 'system'. If safeWrite + applyTheme run before `set`, a
    // matchMedia tick that fires in between sees the OLD theme value
    // in the store and re-paints it on top of the new one. By moving
    // `set({ theme })` first the store value is canonical before any
    // listener can run; applyTheme then paints the new class, and
    // safeWrite persists last (the localStorage write is the only
    // step nobody else reads synchronously). Net: no observable race
    // window where the store and the document class disagree.
    set({ theme });
    applyThemeWithFade(theme);
    safeWrite('theme', theme);
    // Mirror to a cross-subdomain cookie so a theme set on the marketing
    // host (bizarrecrm.com) survives navigation to <slug>.bizarrecrm.com.
    writeThemeCookie(theme);
  },

  setCommandPaletteOpen: (open: boolean) => set({ commandPaletteOpen: open }),

  setKeyboardShortcutsEnabled: (enabled: boolean) => {
    safeWrite('keyboardShortcutsEnabled', String(enabled));
    set({ keyboardShortcutsEnabled: enabled });
  },
}));

// @audit-fixed: previously the matchMedia listener referenced
// `localStorage.getItem('theme') || 'system'` which treats the empty string as
// "system", conflicting with `getInitialTheme()` which validates the value first.
// Now we read the store's theme directly so the listener stays consistent and
// future-proof against moving theme storage out of localStorage. Also guarded
// for SSR and for older Safari which lacks addEventListener on MediaQueryList.
// Listener is registered AFTER the store is created so the closure can access it.
//
// SCAN-1083: in a plain production bundle this module loads exactly once and
// the listener leak was benign. But under Vite HMR and jsdom tests (multiple
// imports of this file) we used to stack a new listener per import, so one
// system-theme flip fired applyTheme N times. Now we dedupe via a hoisted
// flag + a hoisted handler constant — if HMR re-imports the file, the flag
// is reset BUT the previous module instance's handler reference is lost to
// GC and the new one is the only subscriber. In jsdom where the global
// matchMedia mock persists across test re-imports we also hang the flag off
// the MediaQueryList so tests that re-require the store don't stack.
let themeMqAttached = false;
const handleSystemThemeChange = (): void => {
  const current = useUiStore.getState().theme;
  if (current === 'system') applyThemeWithFade('system');
};

if (typeof window !== 'undefined') {
  try {
    const mql = window.matchMedia('(prefers-color-scheme: dark)') as MediaQueryList & {
      __bizarreThemeAttached?: boolean;
    };
    if (!themeMqAttached && !mql.__bizarreThemeAttached) {
      mql.addEventListener('change', handleSystemThemeChange);
      themeMqAttached = true;
      mql.__bizarreThemeAttached = true;
    }
    // WEB-S5-025 (FIXED-by-Fixer-A19 2026-04-25): under Vite HMR this module
    // re-evaluates per edit. The hoisted `themeMqAttached` flag resets to
    // false but the previous module's listener is still attached to the live
    // MediaQueryList — `__bizarreThemeAttached` keeps the new instance from
    // re-attaching, but the OLD instance's listener (and its closure over the
    // OLD `useUiStore`) keeps firing forever. Dispose it explicitly so the
    // matchMedia listener stays exactly one across HMR reloads.
    if (import.meta.hot) {
      import.meta.hot.dispose(() => {
        try {
          mql.removeEventListener('change', handleSystemThemeChange);
          mql.__bizarreThemeAttached = false;
        } catch (e) {
          console.warn('[uiStore] HMR dispose: matchMedia detach failed', e);
        }
      });
    }
  } catch (err) {
    // No-op: legacy environments without addEventListener on MediaQueryList.
    console.warn('[uiStore] system theme listener attach failed', err);
  }
}
