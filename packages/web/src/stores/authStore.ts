import { create } from 'zustand';
import toast from 'react-hot-toast';
import type { User } from '@bizarre-crm/shared';
import { api, hasCsrfTokenCookie, LOGOUT_REQUIRED_EVENT } from '../api/client';

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
type AuthBroadcastMessage = { type: 'cleared' | 'ready'; source: string; ts: number; prevUserId?: string | number | null };
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
  // WEB-UIUX-813: when an impersonation session is/was active, bounce to
  // the super-admin login instead of the tenant login. Without this, an
  // SA who walks away mid-impersonation gets their token expired (15min),
  // then their browser lands on /login — at which point the next person
  // at the same kiosk can sign in as a *real* tenant admin and the UI
  // looks normal, with no signal that the previous user was an SA. By
  // routing to /super-admin/login (and surfacing a banner there) we keep
  // the separation visible.
  let target = '/login';
  try {
    if (typeof sessionStorage !== 'undefined') {
      const raw = sessionStorage.getItem('impersonation_session');
      if (raw) target = '/super-admin/login?impersonation_ended=1';
    }
  } catch { /* sessionStorage may be disabled */ }

  // If nothing is listening yet (App not mounted, Suspense fallback), the
  // listener that DOES eventually mount won't help — fall back to a hard
  // nav after a microtask in that case so we never get stuck on a stale
  // protected page. Bridge handler sets `window.__bizarreLoginNavReady`
  // when it's wired up.
  try {
    window.dispatchEvent(new CustomEvent(REQUEST_LOGIN_NAV_EVENT, { detail: { target } }));
  } catch (err) {
    console.warn('Failed to emit request-login-nav event', err);
  }
  setTimeout(() => {
    if (window.location.pathname.startsWith('/login') || window.location.pathname.startsWith('/super-admin/login')) return;
    if (!(window as unknown as { __bizarreLoginNavReady?: boolean }).__bizarreLoginNavReady) {
      window.location.href = target;
    }
  }, 0);
}
export { REQUEST_LOGIN_NAV_EVENT };
function clearLegacyAccessToken(): void {
  try { localStorage.removeItem('accessToken'); } catch { /* legacy cleanup only */ }
}
function broadcastAuth(type: AuthBroadcastMessage['type'], prevUserId?: string | number | null): void {
  if (typeof window === 'undefined') return;
  const msg: AuthBroadcastMessage = { type, source: AUTH_TAB_ID, ts: Date.now(), prevUserId };
  try { authBroadcastChannel?.postMessage(msg); } catch { /* best-effort */ }
  try {
    localStorage.setItem(AUTH_BROADCAST_KEY, JSON.stringify(msg));
  } catch {
    /* storage disabled — BroadcastChannel may still have worked */
  }
}
// WEB-UIUX-744: prevUserId is the user.id that was active BEFORE the clear.
// Wipe listeners compare it to the current store user_id; if they match, the
// clear came from a silent refresh on the SAME user (cross-tab token renewal)
// and destructive state sweeps (drafts, dismissals) are skipped.
function emitAuthCleared(broadcast = true, prevUserId?: string | number | null): void {
  if (typeof window === 'undefined') return;
  try {
    window.dispatchEvent(new CustomEvent(AUTH_CLEAR_EVENT, { detail: { prevUserId: prevUserId ?? null } }));
  } catch (err) {
    console.warn('Failed to emit auth-cleared event', err);
  }
  if (broadcast) broadcastAuth('cleared', prevUserId);
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
    const prevUser = useAuthStore.getState().user;
    emitAuthCleared(false, prevUser?.id ?? null);
    clearLegacyAccessToken();
    set({ user, isAuthenticated: true, isLoading: false });
    emitAuthReady();
  },

  logout: async () => {
    const prevUser = useAuthStore.getState().user;
    try { await api.post('/auth/logout'); } catch (err) {
      // Network/server error during logout — proceed with local cleanup regardless,
      // but surface the failure so it's not invisible (server-side session may linger).
      console.warn('[auth] /auth/logout failed; clearing local session anyway', err);
    }
    clearLegacyAccessToken();
    set({ user: null, isAuthenticated: false, isLoading: false });
    // @audit-fixed: notify listeners (queryClient, planStore, ws state) so the
    // next user does not inherit cached data from the user that just logged out.
    // Pass null as prevUserId so listeners know this is a real logout (no user
    // will be active after this) and perform full wipes unconditionally.
    emitAuthCleared(true, prevUser?.id ?? null);
  },

  switchUser: async (pin: string) => {
    // SCAN-1107: `completeLogin` emits `authCleared` so planStore / WS /
    // queryClient drop the prior user's state before the new credentials
    // are stored. `switchUser` was skipping that step, so a kiosk "switch
    // via PIN" flow inherited the previous user's React Query cache
    // (ticket/customer lists) and the WS socket kept subscriptions from
    // the outgoing user. Emit the clear BEFORE calling the API so listeners
    // tear down state while the PIN is still being validated.
    const prevUser = useAuthStore.getState().user;
    emitAuthCleared(false, prevUser?.id ?? null);
    const res = await api.post('/auth/switch-user', { pin });
    const { user } = res.data.data;
    clearLegacyAccessToken();
    set({ user, isAuthenticated: true });
    emitAuthReady();
  },

  checkAuth: async () => {
    clearLegacyAccessToken();
    const hasRefreshSession = hasCsrfTokenCookie();
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
// WEB-UIUX-744: skip the sweep when auth-cleared was fired for a silent token
// refresh with the SAME user still active (prevUserId matches current user.id).
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', (e: Event) => {
    const detail = (e as CustomEvent<{ prevUserId?: string | number | null }>).detail;
    const currentUserId = useAuthStore.getState().user?.id ?? null;
    // If prevUserId is set and equals the currently-authenticated user id, this
    // clear came from a silent refresh on the same session — do not wipe.
    if (detail?.prevUserId != null && detail.prevUserId === currentUserId) return;
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

/** WEB-UIUX-746: Returns true if any useDraft-persisted key exists in localStorage. */
function hasSavedDrafts(): boolean {
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && k.startsWith('bizarrecrm:draft:')) return true;
    }
  } catch { /* storage disabled — assume no drafts */ }
  return false;
}

function handleAuthBroadcastMessage(msg: AuthBroadcastMessage): void {
  if (!msg || msg.source === AUTH_TAB_ID) return;
  if (msg.type === 'cleared') {
    const wasAuthed = useAuthStore.getState().isAuthenticated;
    const prevUserId = useAuthStore.getState().user?.id ?? null;
    useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
    // Pass the local prevUserId so wipe listeners can decide if the user actually
    // changed. For a cross-tab logout the remote prevUserId (msg.prevUserId) may
    // differ from the local one when users differ between tabs, but we always use
    // the local tab's prevUserId since it's what the local wipe listeners compare.
    emitAuthCleared(false, prevUserId);
    if (wasAuthed && !window.location.pathname.startsWith('/login')) {
      // WEB-UIUX-746: warn the user if they had unsaved draft data before
      // redirecting, so they know work is recoverable after re-login.
      if (hasSavedDrafts()) {
        toast.error('Logged out from another tab. Drafts saved locally — re-login to recover.');
        setTimeout(requestLoginNav, 700);
      } else {
        requestLoginNav();
      }
    }
    return;
  }

  if (msg.type === 'ready') {
    // WEB-UIUX-816: if this tab has no authenticated user (oldSlug is null —
    // i.e. logged-out tab), a sibling's token write must NOT auto-hydrate
    // silently. Doing so would let tenant-B's session leak into a tab that
    // never performed an explicit login action. Require the user to confirm
    // via a reload prompt instead of calling checkAuth() directly.
    const prevUserId = useAuthStore.getState().user?.id ?? null;
    const isLoggedOut = useAuthStore.getState().user === null;
    if (isLoggedOut) {
      // Dispatch the cross-tenant event so main.tsx can surface a toast/prompt.
      // We do NOT call checkAuth() here — the user must explicitly act (reload).
      try {
        window.dispatchEvent(new CustomEvent('bizarre-crm:cross-tenant-token', {
          detail: {
            message: 'A sign-in occurred in another tab. Reload this page to sign in.',
          },
        }));
      } catch { /* best-effort */ }
      return;
    }
    // WEB-UIUX-744: a sibling tab completed a silent token refresh and broadcast
    // 'ready'. We re-hydrate via checkAuth() but must NOT wipe drafts/dismissals
    // if the same user is still active. Pass the current user.id as prevUserId so
    // wipe listeners can skip destructive sweeps when the user hasn't changed.
    useAuthStore.setState({ isLoading: true });
    emitAuthCleared(false, prevUserId);
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
    const prevUserId = useAuthStore.getState().user?.id ?? null;
    useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
    // @audit-fixed: forced logout (refresh-failed, session-expired, etc.) must
    // also wipe per-user caches so the next sign-in starts clean.
    // WEB-UIUX-745: pass prevUserId so the useDraft listener can compare it
    // to the post-relogin user_id and decline to wipe drafts when the same
    // person signs back in after a mid-action 401. Cross-user kiosk handoff
    // (different prevUserId vs new user) still triggers a full sweep.
    emitAuthCleared(true, prevUserId);
    if (detail?.reason === 'refresh-failed' || detail?.reason === 'session-expired') {
      toast.error('Your session has expired. Please sign in again.');
    }
    // WEB-UIUX-820: 'tenant-suspended' toast is shown in client.ts before
    // forceLogout() fires; no second toast here to avoid duplication.
    // AUDIT-WEB-024: clearing auth state without navigating leaves the user on
    // a protected page that immediately re-checks auth and loops. Prefer the
    // react-router bridge (WEB-FI-005) so the SPA tree stays mounted long
    // enough for `useDraft`'s beforeunload flush + WS cleanup to run; falls
    // back to a hard nav if the App-level listener isn't mounted yet.
    requestLoginNav();
  });
}
