/**
 * Auth store — manages management token and super-admin JWT state.
 * Tokens are held in memory only (never persisted to disk).
 *
 * AUDIT-MGT-010: The store subscribes to the window-level `managementAuthExpired`
 * event dispatched by `utils/handleApiResponse.ts`. Any authenticated IPC call
 * that returns a 401-shaped response fires this event; the store clears auth
 * state and emits `managementAuthNavigateLogin` so the router can redirect.
 * This ensures auto-logout is not limited to the stats-polling channel.
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

// AUDIT-MGT-010: Subscribe once at module load. When any page detects a
// 401-shaped IPC response it dispatches 'managementAuthExpired'. We clear
// the store and then emit a navigation event that the router can listen to.
// Using a custom event (not react-router navigate()) because this code runs
// outside any React component tree.
//
// MGT-025: Convert to named handler so the Vite HMR dispose callback can
// remove it before the module is re-evaluated. Without this, every HMR
// cycle adds a duplicate listener and the store logs out multiple times per
// auth-expired event (one per accumulated listener).
const authExpiredHandler = () => {
  useAuthStore.getState().logout();
  window.dispatchEvent(new Event('managementAuthNavigateLogin'));
};

if (typeof window !== 'undefined') {
  window.addEventListener('managementAuthExpired', authExpiredHandler);

  // MGT-025: Remove the listener when Vite replaces this module during HMR
  // so that accumulated duplicate listeners don't pile up across hot reloads.
  // @ts-expect-error Vite HMR
  if (import.meta.hot) {
    // @ts-expect-error Vite HMR
    import.meta.hot.dispose(() => {
      window.removeEventListener('managementAuthExpired', authExpiredHandler);
    });
  }
}
