/**
 * UI store — dashboard theme and sidebar state.
 * Always defaults to dark mode.
 */
import { create } from 'zustand';

interface UiState {
  sidebarCollapsed: boolean;
  theme: 'dark' | 'light';

  toggleSidebar: () => void;
  setTheme: (theme: 'dark' | 'light') => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarCollapsed: false,
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
