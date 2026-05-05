import { create } from 'zustand';

interface UiState {
  sidebarCollapsed: boolean;
  mobileSidebarOpen: boolean;
  theme: 'light' | 'dark' | 'system';
  commandPaletteOpen: boolean;
  toggleSidebar: () => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  setMobileSidebarOpen: (open: boolean) => void;
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
  setCommandPaletteOpen: (open: boolean) => void;
}

const getInitialTheme = (): 'light' | 'dark' | 'system' => {
  try {
    const stored = localStorage.getItem('theme');
    if (stored === 'light' || stored === 'dark' || stored === 'system') return stored;
  } catch (err) {
    // localStorage may throw in private mode / sandboxed iframes — fall through to default.
    console.warn('[uiStore] getInitialTheme: localStorage read failed', err);
  }
  return 'system';
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
  },

  setCommandPaletteOpen: (open: boolean) => set({ commandPaletteOpen: open }),
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
