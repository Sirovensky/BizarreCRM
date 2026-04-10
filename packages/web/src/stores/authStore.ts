import { create } from 'zustand';
import type { User } from '@bizarre-crm/shared';
import { api } from '../api/client';

// DASH-6: Token expiry warning (TODO — implement when ready)
// To add a "session expiring" warning:
//   1. Add `tokenExpiresAt: number | null` to AuthState.
//   2. In completeLogin(), decode the JWT (base64 middle segment), read `exp`,
//      and store it: set({ tokenExpiresAt: payload.exp * 1000 }).
//   3. Create a useTokenExpiryWarning() hook (or add to an existing layout effect)
//      that runs a setInterval every 30s checking:
//        if (tokenExpiresAt && tokenExpiresAt - Date.now() < 5 * 60 * 1000) { showWarning() }
//   4. The warning should offer "Extend session" (calls /auth/refresh) or "Logout".
//   5. Clear the interval on logout / unmount.

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
  isAuthenticated: false,
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
    if (!token) {
      // No access token — try refreshing via httpOnly cookie before giving up
      try {
        const refreshRes = await api.post('/auth/refresh');
        const { accessToken, user } = refreshRes.data.data;
        localStorage.setItem('accessToken', accessToken);
        set({ user, isAuthenticated: true, isLoading: false });
        return;
      } catch {
        set({ isLoading: false, isAuthenticated: false });
        return;
      }
    }
    try {
      const res = await api.get('/auth/me');
      set({ user: res.data.data, isAuthenticated: true, isLoading: false });
    } catch {
      // Access token expired — try refresh before logging out
      try {
        const refreshRes = await api.post('/auth/refresh');
        const { accessToken, user } = refreshRes.data.data;
        localStorage.setItem('accessToken', accessToken);
        set({ user, isAuthenticated: true, isLoading: false });
      } catch {
        localStorage.removeItem('accessToken');
        set({ user: null, isAuthenticated: false, isLoading: false });
      }
    }
  },

  setUser: (user: User) => set({ user }),
}));
