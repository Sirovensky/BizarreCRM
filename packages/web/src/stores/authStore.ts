import { create } from 'zustand';
import toast from 'react-hot-toast';
import type { User } from '@bizarre-crm/shared';
import { api, LOGOUT_REQUIRED_EVENT } from '../api/client';

// @audit-fixed: dispatched on every successful logout so listeners (main.tsx
// QueryClient + planStore + WS store) can wipe per-user state. Without this,
// logging in as user B would inherit user A's React Query cache, plan/usage
// data, and last-message WebSocket state.
const AUTH_CLEAR_EVENT = 'bizarre-crm:auth-cleared';
const AUTH_READY_EVENT = 'bizarre-crm:auth-ready';
function emitAuthCleared(): void {
  if (typeof window === 'undefined') return;
  try {
    window.dispatchEvent(new CustomEvent(AUTH_CLEAR_EVENT));
  } catch (err) {
    console.warn('Failed to emit auth-cleared event', err);
  }
}
// Fired whenever a fresh access token becomes available (login, switchUser,
// or silent refresh via checkAuth). Listeners like useWebSocket use this to
// (re)connect now that authentication is live, rather than waiting for the
// next tab-visibility change.
function emitAuthReady(): void {
  if (typeof window === 'undefined') return;
  try {
    window.dispatchEvent(new CustomEvent(AUTH_READY_EVENT));
  } catch (err) {
    console.warn('Failed to emit auth-ready event', err);
  }
}
export { AUTH_CLEAR_EVENT, AUTH_READY_EVENT };

// TODO(LOW, §26, DASH-6): Token expiry warning — implement when ready
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
    // Clear any previous tenant's cached data before storing new credentials.
    // This prevents Tenant B from seeing Tenant A's React Query cache entries
    // when the same browser session is reused for a different login.
    emitAuthCleared();
    // Only store access token in localStorage; refresh token is in httpOnly cookie
    localStorage.setItem('accessToken', accessToken);
    set({ user, isAuthenticated: true, isLoading: false });
    emitAuthReady();
  },

  logout: async () => {
    try { await api.post('/auth/logout'); } catch (err) {
      // Network/server error during logout — proceed with local cleanup regardless,
      // but surface the failure so it's not invisible (server-side session may linger).
      console.warn('[auth] /auth/logout failed; clearing local session anyway', err);
    }
    localStorage.removeItem('accessToken');
    set({ user: null, isAuthenticated: false, isLoading: false });
    // @audit-fixed: notify listeners (queryClient, planStore, ws state) so the
    // next user does not inherit cached data from the user that just logged out.
    emitAuthCleared();
  },

  switchUser: async (pin: string) => {
    // SCAN-1107: `completeLogin` emits `authCleared` so planStore / WS /
    // queryClient drop the prior user's state before the new credentials
    // are stored. `switchUser` was skipping that step, so a kiosk "switch
    // via PIN" flow inherited the previous user's React Query cache
    // (ticket/customer lists) and the WS socket kept subscriptions from
    // the outgoing user. Emit the clear BEFORE calling the API so listeners
    // tear down state while the PIN is still being validated.
    emitAuthCleared();
    const res = await api.post('/auth/switch-user', { pin });
    const { accessToken, user } = res.data.data;
    localStorage.setItem('accessToken', accessToken);
    set({ user, isAuthenticated: true });
    emitAuthReady();
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
        emitAuthReady();
        return;
      } catch {
        set({ isLoading: false, isAuthenticated: false });
        return;
      }
    }
    try {
      const res = await api.get('/auth/me');
      set({ user: res.data.data, isAuthenticated: true, isLoading: false });
      emitAuthReady();
    } catch {
      // Access token expired — try refresh before logging out
      try {
        const refreshRes = await api.post('/auth/refresh');
        const { accessToken, user } = refreshRes.data.data;
        localStorage.setItem('accessToken', accessToken);
        set({ user, isAuthenticated: true, isLoading: false });
        emitAuthReady();
      } catch {
        localStorage.removeItem('accessToken');
        set({ user: null, isAuthenticated: false, isLoading: false });
      }
    }
  },

  setUser: (user: User) => set({ user }),
}));

// ──────────────────────────────────────────────────────────────────
// WEB-FO-002: cross-tab auth sync via the `storage` event.
// localStorage writes in tab A fire a `storage` event in every other
// tab on the same origin. We listen for changes to `accessToken` and
// either force-logout (token removed in another tab) or re-hydrate
// the user (token added/changed in another tab — typically a sign-in
// or silent refresh). Without this, two tabs of the same user can
// drift indefinitely: one logs out and the other keeps showing
// protected pages until the next 401 round-trip.
// ──────────────────────────────────────────────────────────────────
if (typeof window !== 'undefined') {
  window.addEventListener('storage', (e: StorageEvent) => {
    if (e.key !== 'accessToken') return;
    // Token removed in another tab → mirror the logout here. Don't
    // call api/logout (the other tab already did) and don't navigate
    // if we're already on /login.
    if (e.newValue === null) {
      const wasAuthed = useAuthStore.getState().isAuthenticated;
      useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
      emitAuthCleared();
      if (wasAuthed && !window.location.pathname.startsWith('/login')) {
        window.location.href = '/login';
      }
      return;
    }
    // Token added/changed in another tab → silently re-hydrate the
    // user via /auth/me so this tab picks up the new identity (login
    // or switchUser elsewhere). checkAuth() also covers refresh-token
    // rotation so this tab uses the freshest access token on next req.
    if (e.newValue && e.newValue !== e.oldValue) {
      // Wipe per-user caches in this tab before /auth/me lands so a
      // tenant-switch doesn't bleed state across tabs.
      emitAuthCleared();
      useAuthStore.getState().checkAuth();
    }
  });
}

// ──────────────────────────────────────────────────────────────────
// Listen for forced logouts from the API client (T9 fix)
// ──────────────────────────────────────────────────────────────────
// client.ts emits a `logout-required` event whenever the refresh pipeline
// fails definitively. Previously this would silently drop the user to the
// login screen with no feedback. Now we clear store state and surface a
// toast so the user understands what happened.
if (typeof window !== 'undefined') {
  window.addEventListener(LOGOUT_REQUIRED_EVENT, (e: Event) => {
    const detail = (e as CustomEvent<{ reason: string }>).detail;
    useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
    // @audit-fixed: forced logout (refresh-failed, session-expired, etc.) must
    // also wipe per-user caches so the next sign-in starts clean.
    emitAuthCleared();
    if (detail?.reason === 'refresh-failed' || detail?.reason === 'session-expired') {
      toast.error('Your session has expired. Please sign in again.');
    }
    // AUDIT-WEB-024: clearing auth state without navigating leaves the user on
    // a protected page that immediately re-checks auth and loops. Use a hard
    // navigation so React Router picks up the cleared state cleanly.
    window.location.href = '/login';
  });
}
