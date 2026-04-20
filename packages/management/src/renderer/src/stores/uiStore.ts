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

interface UiState {
  sidebarCollapsed: boolean;
  theme: 'dark' | 'light';

  toggleSidebar: () => void;
  setTheme: (theme: 'dark' | 'light') => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarCollapsed: initialCollapsed(),
  theme: 'dark',

  toggleSidebar: () =>
    set((state) => ({ sidebarCollapsed: !state.sidebarCollapsed })),

  setTheme: (theme) => {
    // Apply to DOM
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
    set({ theme });
  },
}));
