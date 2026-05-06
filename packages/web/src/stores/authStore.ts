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
const AUTH_BROADCAST_KEY = 'bizarre-crm:auth-broadcast';
const AUTH_TAB_ID = (() => {
  try {
    return crypto.randomUUID();
  } catch {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
})();
type AuthBroadcastMessage = { type: 'cleared' | 'ready'; source: string; ts: number };
const authBroadcastChannel = typeof window !== 'undefined' && 'BroadcastChannel' in window
  ? new BroadcastChannel('bizarre-crm:auth')
  : null;
// WEB-FI-005 / FIXED-by-Fixer-A11 2026-04-25 — used to ask the App-level
// router bridge to navigate to /login via react-router instead of a hard
// `window.location.href = '/login'` reload. The hard reload was discarding
// the React tree, killing in-flight uploads, and dropping any text that
// the useDraft debounce hadn't flushed yet (up to 2 s of typed content).
// SPA navigation keeps the tree alive so `auth-cleared` listeners can run
// before the route changes and pending writes get flushed cleanly.
const REQUEST_LOGIN_NAV_EVENT = 'bizarre-crm:request-login-nav';
function requestLoginNav(): void {
  if (typeof window === 'undefined') return;
  // If nothing is listening yet (App not mounted, Suspense fallback), the
  // listener that DOES eventually mount won't help — fall back to a hard
  // nav after a microtask in that case so we never get stuck on a stale
  // protected page. Bridge handler sets `window.__bizarreLoginNavReady`
  // when it's wired up.
  try {
    window.dispatchEvent(new CustomEvent(REQUEST_LOGIN_NAV_EVENT));
  } catch (err) {
    console.warn('Failed to emit request-login-nav event', err);
  }
  setTimeout(() => {
    if (window.location.pathname.startsWith('/login')) return;
    if (!(window as unknown as { __bizarreLoginNavReady?: boolean }).__bizarreLoginNavReady) {
      window.location.href = '/login';
    }
  }, 0);
}
export { REQUEST_LOGIN_NAV_EVENT };
function clearLegacyAccessToken(): void {
  try { localStorage.removeItem('accessToken'); } catch { /* legacy cleanup only */ }
}
function broadcastAuth(type: AuthBroadcastMessage['type']): void {
  if (typeof window === 'undefined') return;
  const msg: AuthBroadcastMessage = { type, source: AUTH_TAB_ID, ts: Date.now() };
  try { authBroadcastChannel?.postMessage(msg); } catch { /* best-effort */ }
  try {
    localStorage.setItem(AUTH_BROADCAST_KEY, JSON.stringify(msg));
  } catch {
    /* storage disabled — BroadcastChannel may still have worked */
  }
}
function emitAuthCleared(broadcast = true): void {
  if (typeof window === 'undefined') return;
  try {
    window.dispatchEvent(new CustomEvent(AUTH_CLEAR_EVENT));
  } catch (err) {
    console.warn('Failed to emit auth-cleared event', err);
  }
  if (broadcast) broadcastAuth('cleared');
}
// Fired whenever the cookie-backed tenant session becomes available. Listeners
// like useWebSocket use this to (re)connect now that authentication is live.
function emitAuthReady(broadcast = true): void {
  if (typeof window === 'undefined') return;
  try {
    window.dispatchEvent(new CustomEvent(AUTH_READY_EVENT));
  } catch (err) {
    console.warn('Failed to emit auth-ready event', err);
  }
  if (broadcast) broadcastAuth('ready');
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

  completeLogin: (_accessToken, _refreshToken, user) => {
    // Clear any previous tenant's cached data before storing new credentials.
    // This prevents Tenant B from seeing Tenant A's React Query cache entries
    // when the same browser session is reused for a different login.
    emitAuthCleared(false);
    clearLegacyAccessToken();
    set({ user, isAuthenticated: true, isLoading: false });
    emitAuthReady();
  },

  logout: async () => {
    try { await api.post('/auth/logout'); } catch (err) {
      // Network/server error during logout — proceed with local cleanup regardless,
      // but surface the failure so it's not invisible (server-side session may linger).
      console.warn('[auth] /auth/logout failed; clearing local session anyway', err);
    }
    clearLegacyAccessToken();
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
    emitAuthCleared(false);
    const res = await api.post('/auth/switch-user', { pin });
    const { user } = res.data.data;
    clearLegacyAccessToken();
    set({ user, isAuthenticated: true });
    emitAuthReady();
  },

  checkAuth: async () => {
    clearLegacyAccessToken();
    const hasRefreshSession = typeof document !== 'undefined'
      && /(?:^|;\s*)csrf_token=/.test(document.cookie);
    if (!hasRefreshSession) {
      set({ user: null, isLoading: false, isAuthenticated: false });
      return;
    }
    try {
      const res = await api.get('/auth/me');
      set({ user: res.data.data, isAuthenticated: true, isLoading: false });
      emitAuthReady(false);
    } catch {
      // Access token expired — try refresh before logging out
      try {
        const refreshRes = await api.post('/auth/refresh');
        const { user } = refreshRes.data.data;
        set({ user, isAuthenticated: true, isLoading: false });
        emitAuthReady(false);
      } catch {
        clearLegacyAccessToken();
        set({ user: null, isAuthenticated: false, isLoading: false });
      }
    }
  },

  setUser: (user: User) => set({ user }),
}));

// WEB-S5-033: sweep all per-user namespaced keys on auth-cleared so kiosk
// handoffs don't leak dismissals, drafts, or recent-view data across logins.
// `recent_views:*` is handled by Sidebar's own listener; `bizarrecrm:draft:*`
// by useDraft's listener. This covers the `bizarrecrm:dismiss:*` namespace
// (useDismissible) and any future `bizarrecrm:` prefixed additions.
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => {
    try {
      const toRemove: string[] = [];
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.startsWith('bizarrecrm:dismiss:')) toRemove.push(k);
      }
      toRemove.forEach((k) => {
        try { localStorage.removeItem(k); } catch { /* best-effort */ }
      });
    } catch (err) {
      console.warn('[authStore] dismiss key sweep on auth-cleared failed', err);
    }
  });
}

// ──────────────────────────────────────────────────────────────────
// Cross-tab auth sync without storing bearer tokens.
// We broadcast only a non-secret event marker, then sibling tabs re-hydrate
// from the httpOnly cookie via /auth/me or clear local UI state.
// ──────────────────────────────────────────────────────────────────
function handleAuthBroadcastMessage(msg: AuthBroadcastMessage): void {
  if (!msg || msg.source === AUTH_TAB_ID) return;
  if (msg.type === 'cleared') {
    const wasAuthed = useAuthStore.getState().isAuthenticated;
    useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
    emitAuthCleared(false);
    if (wasAuthed && !window.location.pathname.startsWith('/login')) {
      requestLoginNav();
    }
    return;
  }

  if (msg.type === 'ready') {
    useAuthStore.setState({ isLoading: true });
    emitAuthCleared(false);
    queueMicrotask(() => {
      useAuthStore.getState().checkAuth();
    });
  }
}

if (typeof window !== 'undefined') {
  authBroadcastChannel?.addEventListener('message', (event: MessageEvent) => {
    handleAuthBroadcastMessage(event.data as AuthBroadcastMessage);
  });

  window.addEventListener('storage', (e: StorageEvent) => {
    if (e.key === AUTH_BROADCAST_KEY && e.newValue) {
      try {
        handleAuthBroadcastMessage(JSON.parse(e.newValue) as AuthBroadcastMessage);
      } catch {
        /* ignore malformed storage marker */
      }
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
    // a protected page that immediately re-checks auth and loops. Prefer the
    // react-router bridge (WEB-FI-005) so the SPA tree stays mounted long
    // enough for `useDraft`'s beforeunload flush + WS cleanup to run; falls
    // back to a hard nav if the App-level listener isn't mounted yet.
    requestLoginNav();
  });
}
