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
  const stored = localStorage.getItem('theme');
  if (stored === 'light' || stored === 'dark' || stored === 'system') return stored;
  return 'system';
};

const applyTheme = (theme: 'light' | 'dark' | 'system') => {
  const isDark = theme === 'dark' || (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.classList.toggle('dark', isDark);
};

// Apply on load
applyTheme(getInitialTheme());

// Listen for system changes
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  const theme = localStorage.getItem('theme') || 'system';
  if (theme === 'system') applyTheme('system');
});

export const useUiStore = create<UiState>((set) => ({
  sidebarCollapsed: localStorage.getItem('sidebarCollapsed') === 'true',
  mobileSidebarOpen: false,
  theme: getInitialTheme(),
  commandPaletteOpen: false,

  toggleSidebar: () =>
    set((state) => {
      const collapsed = !state.sidebarCollapsed;
      localStorage.setItem('sidebarCollapsed', String(collapsed));
      return { sidebarCollapsed: collapsed };
    }),

  setSidebarCollapsed: (collapsed: boolean) => {
    localStorage.setItem('sidebarCollapsed', String(collapsed));
    set({ sidebarCollapsed: collapsed });
  },

  setMobileSidebarOpen: (open: boolean) => set({ mobileSidebarOpen: open }),

  setTheme: (theme: 'light' | 'dark' | 'system') => {
    localStorage.setItem('theme', theme);
    applyTheme(theme);
    set({ theme });
  },

  setCommandPaletteOpen: (open: boolean) => set({ commandPaletteOpen: open }),
}));
