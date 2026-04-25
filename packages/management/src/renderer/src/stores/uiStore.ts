/**
 * UI store — dashboard theme and sidebar state.
 * Always defaults to dark mode.
 *
 * Remote-access sessions (Windows Server, RDP, VNC) often present the
 * dashboard in an 800×600 or smaller window where the full sidebar
 * label column eats ~30% of horizontal space. Auto-collapse when the
 * viewport is narrower than 900px on startup so those sessions get
 * usable content area without the operator having to click the
 * chevron. User toggles still stick within a session.
 */
import { create } from 'zustand';

const AUTO_COLLAPSE_THRESHOLD = 900;
function initialCollapsed(): boolean {
  if (typeof window === 'undefined' || typeof window.innerWidth !== 'number') return false;
  return window.innerWidth < AUTO_COLLAPSE_THRESHOLD;
}

type Density = 'default' | 'compact';

const DENSITY_KEY = 'bizarrecrm-dashboard-density';
const THEME_KEY = 'bizarrecrm-dashboard-theme';

/** Allowed density values. Anything not in this set is rejected. */
const VALID_DENSITIES = new Set<string>(['default', 'compact']);

/** Allowed theme values. Anything not in this set is rejected. */
const VALID_THEMES = new Set<string>(['dark', 'light']);

type Theme = 'dark' | 'light';

/**
 * Read and validate the persisted theme from localStorage.
 * Mirrors the density pattern: any corrupt/injected value falls back to 'dark'
 * so the store is never in an invalid state (DASH-ELEC-095).
 */
function initialTheme(): Theme {
  if (typeof window === 'undefined' || typeof localStorage === 'undefined') return 'dark';
  const stored = localStorage.getItem(THEME_KEY);
  return VALID_THEMES.has(stored ?? '') ? (stored as Theme) : 'dark';
}

function initialDensity(): Density {
  if (typeof window === 'undefined' || typeof localStorage === 'undefined') return 'default';
  const stored = localStorage.getItem(DENSITY_KEY);
  // Validate strictly against the allowed set; any unexpected value (storage
  // corruption, injected string) falls back to 'default' safely.
  return VALID_DENSITIES.has(stored ?? '') ? (stored as Density) : 'default';
}

function applyDensityToDom(d: Density): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  if (d === 'compact') root.dataset.density = 'compact';
  else delete root.dataset.density;
}

interface UiState {
  sidebarCollapsed: boolean;
  theme: Theme;
  density: Density;

  toggleSidebar: () => void;
  setTheme: (theme: Theme) => void;
  setDensity: (d: Density) => void;
}

export const useUiStore = create<UiState>((set) => {
  const density = initialDensity();
  applyDensityToDom(density);

  // Restore persisted theme and apply to DOM immediately so there is no
  // flash-of-wrong-theme between HTML load and first React render (DASH-ELEC-095).
  const theme = initialTheme();
  if (theme === 'dark') {
    document.documentElement.classList.add('dark');
  } else {
    document.documentElement.classList.remove('dark');
  }

  return {
    sidebarCollapsed: initialCollapsed(),
    theme,
    density,

    toggleSidebar: () =>
      set((state) => ({ sidebarCollapsed: !state.sidebarCollapsed })),

    setTheme: (theme) => {
      // Apply to DOM
      if (theme === 'dark') {
        document.documentElement.classList.add('dark');
      } else {
        document.documentElement.classList.remove('dark');
      }
      // Persist so the selection survives reload (DASH-ELEC-095).
      try { localStorage.setItem(THEME_KEY, theme); } catch { /* ignore quota/security errors */ }
      set({ theme });
    },

    setDensity: (d) => {
      applyDensityToDom(d);
      try { localStorage.setItem(DENSITY_KEY, d); } catch { /* ignore */ }
      set({ density: d });
    },
  };
});
