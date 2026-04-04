import { create } from 'zustand';
import type { User } from '@bizarre-crm/shared';
import { api } from '../api/client';

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  completeLogin: (accessToken: string, refreshToken: string, user: User) => void;
  logout: () => Promise<void>;
  switchUser: (pin: string) => Promise<void>;
  checkAuth: () => Promise<void>;
  setUser: (user: User) => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isAuthenticated: !!localStorage.getItem('accessToken'),
  isLoading: true,

  completeLogin: (accessToken, _refreshToken, user) => {
    // Only store access token in localStorage; refresh token is in httpOnly cookie
    localStorage.setItem('accessToken', accessToken);
    set({ user, isAuthenticated: true, isLoading: false });
  },

  logout: async () => {
    try { await api.post('/auth/logout'); } catch {}
    localStorage.removeItem('accessToken');
    set({ user: null, isAuthenticated: false, isLoading: false });
  },

  switchUser: async (pin: string) => {
    const res = await api.post('/auth/switch-user', { pin });
    const { accessToken, user } = res.data.data;
    localStorage.setItem('accessToken', accessToken);
    set({ user, isAuthenticated: true });
  },

  checkAuth: async () => {
    const token = localStorage.getItem('accessToken');
    if (!token) { set({ isLoading: false, isAuthenticated: false }); return; }
    try {
      const res = await api.get('/auth/me');
      set({ user: res.data.data.user, isAuthenticated: true, isLoading: false });
    } catch {
      localStorage.removeItem('accessToken');
      set({ user: null, isAuthenticated: false, isLoading: false });
    }
  },

  setUser: (user: User) => set({ user }),
}));
