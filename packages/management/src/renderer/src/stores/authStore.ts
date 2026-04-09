/**
 * Auth store — manages management token and super-admin JWT state.
 * Tokens are held in memory only (never persisted to disk).
 */
import { create } from 'zustand';

type AuthMode = 'management' | 'super-admin' | null;

interface AuthState {
  isAuthenticated: boolean;
  authMode: AuthMode;
  username: string | null;

  // Actions
  loginSuccess: (mode: AuthMode, username: string) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  isAuthenticated: false,
  authMode: null,
  username: null,

  loginSuccess: (mode, username) =>
    set({ isAuthenticated: true, authMode: mode, username }),

  logout: () =>
    set({ isAuthenticated: false, authMode: null, username: null }),
}));
