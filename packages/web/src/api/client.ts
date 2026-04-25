import axios from 'axios';
import toast from 'react-hot-toast';
import { useAuthStore } from '@/stores/authStore';

const API_BASE = '/api/v1';
const AUTH_REFRESH_PATH = '/auth/refresh';
const AUTH_REFRESH_URL = `${API_BASE}${AUTH_REFRESH_PATH}`;

/**
 * Logout-required event — emitted when the refresh pipeline has definitively
 * failed (no valid refresh cookie, or refresh endpoint rejected). The auth
 * store listens for this and clears local state. Decoupling the transport
 * layer from the store via events keeps T9's silent-catch failure mode
 * visible: the store can react and surface a toast, rather than the user
 * being silently logged out with no feedback.
 */
export const LOGOUT_REQUIRED_EVENT = 'bizarre-crm:logout-required';

interface LogoutRequiredDetail {
  reason: 'refresh-failed' | 'session-expired' | 'forced';
}

// WEB-FJ-007 / FIXED-by-Fixer-JJJ 2026-04-25 — production console output must
// not contain auth payloads, refresh request configs, or correlation ids that
// third-party browser-error shippers (Sentry, Datadog RUM, LogRocket) might
// forward into less-trusted sinks. Gate every diagnostic warn behind DEV;
// production code paths swallow silently (the user-visible toast in the
// response interceptor + forceLogout() flow already covers UX).
const devWarn: (...args: unknown[]) => void = import.meta.env.DEV
  ? (...args) => { console.warn(...args); }
  : () => {};

function emitLogoutRequired(reason: LogoutRequiredDetail['reason']) {
  try {
    window.dispatchEvent(
      new CustomEvent<LogoutRequiredDetail>(LOGOUT_REQUIRED_EVENT, { detail: { reason } }),
    );
  } catch (err) {
    // Environments without window (SSR/tests) — best-effort only
    devWarn('Failed to emit logout-required event', err);
  }
}

// SEC-H89: Read the non-httpOnly csrf_token cookie so we can forward it as
// X-CSRF-Token on POST /auth/refresh (double-submit CSRF protection).
function getCsrfTokenCookie(): string {
  if (typeof document === 'undefined') return '';
  const match = document.cookie.match(/(?:^|;\s*)csrf_token=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : '';
}

// WEB-FI-001 fix: a slow upstream (DB lock, blocked event loop, hung worker)
// previously kept axios requests pending forever — React Query never errored
// out, error boundaries never tripped, and the user stared at a forever-spinner.
// 30 s is generous enough for normal cold-start latency on small tenant DBs
// while ensuring failures surface as ECONNABORTED inside a bounded window.
// Per-route callers that need longer (file uploads, report exports) can
// override via `client.post(url, body, { timeout: 60_000 })`.
const DEFAULT_REQUEST_TIMEOUT_MS = 30_000;

const client = axios.create({
  baseURL: API_BASE,
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true, // Send httpOnly cookies with requests
  timeout: DEFAULT_REQUEST_TIMEOUT_MS,
});

// ──────────────────────────────────────────────────────────────────
// Single-flight refresh mutex
// ──────────────────────────────────────────────────────────────────
// Both the proactive scheduler and the 401 interceptor can race to refresh
// the access token. Without a shared mutex, two refreshes can fire in
// parallel and the second wins — invalidating the first caller's new token.
// `sharedRefreshPromise` is the single slot: any caller that finds it
// populated awaits the existing promise instead of starting a new one.
let sharedRefreshPromise: Promise<string> | null = null;

async function performRefresh(): Promise<string> {
  if (sharedRefreshPromise) return sharedRefreshPromise;
  sharedRefreshPromise = (async () => {
    try {
      // SEC-H89: Include the CSRF double-submit token so the server can verify
      // this refresh was initiated by our own JS (not a cross-origin CSRF request).
      const csrfToken = getCsrfTokenCookie();
      // WEB-FI-006: pin an explicit timeout. We're calling bare `axios.post`
      // (not the configured `client`) so the module default (no timeout)
      // applies — without this guard a hung refresh blocks every queued
      // 401 retry forever because `sharedRefreshPromise` never settles.
      const res = await axios.post(
        AUTH_REFRESH_URL,
        {},
        {
          withCredentials: true,
          headers: csrfToken ? { 'X-CSRF-Token': csrfToken } : {},
          timeout: 10_000,
        },
      );
      const accessToken = res.data?.data?.accessToken;
      if (!accessToken) throw new Error('Refresh response missing access token');
      localStorage.setItem('accessToken', accessToken);
      return accessToken;
    } finally {
      // Always clear the slot so the next expiry cycle can refresh again.
      sharedRefreshPromise = null;
    }
  })();
  return sharedRefreshPromise;
}

// Proactive token refresh — refresh 5 min before expiry
let refreshScheduled = false;
// WEB-FD-017: cache the decoded `exp` claim keyed by the raw token string.
// Every authenticated request used to base64-decode + JSON.parse the JWT
// payload; on a page that fires N requests this is N decodes for the same
// token. Skip the work whenever the token string hasn't changed.
let cachedTokenForExp: string | null = null;
let cachedTokenExpMs: number | null = null;
function scheduleTokenRefresh() {
  if (refreshScheduled) return;
  const token = localStorage.getItem('accessToken');
  if (!token) return;
  try {
    let expMs: number;
    if (token === cachedTokenForExp && cachedTokenExpMs != null) {
      expMs = cachedTokenExpMs;
    } else {
      const parts = token.split('.');
      if (parts.length < 3) throw new Error('malformed');
      if (parts[1].length > 4096) throw new Error('payload too large');
      const decoded = atob(parts[1]);
      if (decoded.length > 8192) throw new Error('decoded payload too large');
      const payload = JSON.parse(decoded);
      // Without this guard, a token with a missing or non-numeric `exp` would
      // turn expiresIn into NaN, Math.max(NaN, 10_000) into NaN, and setTimeout
      // into a 0-ms fire — causing a refresh storm on every request.
      if (typeof payload?.exp !== 'number' || !Number.isFinite(payload.exp)) {
        throw new Error('token missing numeric exp claim');
      }
      expMs = payload.exp * 1000;
      cachedTokenForExp = token;
      cachedTokenExpMs = expMs;
    }
    const expiresIn = expMs - Date.now();
    const refreshIn = Math.max(expiresIn - 5 * 60 * 1000, 10_000); // 5 min before expiry, min 10s
    refreshScheduled = true;
    setTimeout(async () => {
      refreshScheduled = false;
      try {
        await performRefresh();
        scheduleTokenRefresh(); // Schedule next refresh
      } catch (err) {
        // Refresh failed — let the 401 interceptor handle it on the next request
        devWarn('Proactive token refresh failed:', err);
      }
    }, refreshIn);
  } catch (err) {
    // Invalid token format — reset scheduling flag so future requests can
    // re-enter scheduleTokenRefresh instead of being silently skipped.
    refreshScheduled = false;
    // Clear the malformed token so it doesn't block every subsequent request.
    // Only remove it if it hasn't been replaced by a concurrent refresh.
    const cleared = localStorage.getItem('accessToken') === token;
    if (cleared) {
      localStorage.removeItem('accessToken');
      cachedTokenForExp = null;
      cachedTokenExpMs = null;
    }
    devWarn('Could not decode access token for refresh scheduling:', err);
    // SCAN-1084: a malformed token left the auth store thinking we were
    // authenticated until the NEXT API call 401'd. During that window the
    // UI rendered protected routes with no Authorization header and POSTs
    // silently failed. Emit the same event the 401 interceptor uses so the
    // store flips immediately.
    if (cleared) emitLogoutRequired('refresh-failed');
  }
}

// Request interceptor: attach auth token + CSRF header for refresh calls
client.interceptors.request.use((config) => {
  const token = localStorage.getItem('accessToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
    scheduleTokenRefresh();
  }
  // SEC-H89: Automatically attach the CSRF double-submit token for every
  // POST to /auth/refresh, regardless of which callsite triggered it.
  if (config.url?.includes(AUTH_REFRESH_PATH) && config.method?.toUpperCase() === 'POST') {
    const csrfToken = getCsrfTokenCookie();
    if (csrfToken) config.headers['X-CSRF-Token'] = csrfToken;
  }
  return config;
});

let isLoggingOut = false;

// Separate axios instance for logout to avoid triggering the 401 interceptor loop
const logoutClient = axios.create({ baseURL: API_BASE, withCredentials: true });

function forceLogout(reason: LogoutRequiredDetail['reason'] = 'forced') {
  if (isLoggingOut) return;
  isLoggingOut = true;
  // WEB-FD-004 (FIXED-by-Fixer-A3 2026-04-25): previously this read the
  // access token, removed it, then sent the *captured* token in the
  // Authorization header asynchronously. Two failure modes:
  //   (1) a parallel tab refreshed between read and post → we hit
  //       /auth/logout with an already-rotated token, server 401s, and
  //       the actually-current token in localStorage stays valid in the
  //       sibling tab.
  //   (2) the captured token sat in this closure (and on the wire) for
  //       the lifetime of the request — extra exposure window.
  // Fix: invalidate the access token in localStorage atomically, then call
  // /auth/logout with `withCredentials` only. The server identifies the
  // session via the refresh-token httpOnly cookie + CSRF double-submit,
  // which is the canonical mechanism for logout already.
  localStorage.removeItem('accessToken');
  // @audit-fixed: drop any pending proactive-refresh promise so the next login
  // can re-arm scheduling cleanly. Without this, `refreshScheduled` and a stale
  // `sharedRefreshPromise` would survive the logout and the new session would
  // skip its first proactive refresh window.
  refreshScheduled = false;
  sharedRefreshPromise = null;
  // Forward the CSRF double-submit token so the server accepts the
  // unauthenticated logout call.
  const csrfToken = getCsrfTokenCookie();
  // Use logoutClient (no interceptors) to avoid 401 loop
  logoutClient
    .post('/auth/logout', {}, {
      headers: csrfToken ? { 'X-CSRF-Token': csrfToken } : {},
    })
    .catch((err) => {
      // Logout endpoint failure is non-fatal — local state will still clear
      devWarn('Logout endpoint call failed:', err);
    })
    .finally(() => {
      useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
      isLoggingOut = false;
      emitLogoutRequired(reason);
    });
}

// @audit-fixed: clear scheduling/refresh state when the auth store fires a
// graceful logout (`bizarre-crm:auth-cleared`). The 401 path already calls
// forceLogout() which resets these, but a manual user-initiated logout goes
// through authStore.logout() which only clears localStorage — without this
// listener, the next login would skip the first proactive-refresh window.
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => {
    refreshScheduled = false;
    sharedRefreshPromise = null;
  });
}

// Response interceptor: handle 401 (refresh) and 403 (upgrade_required)
client.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    // Attach server-supplied error code + request_id to the thrown axios error
    // so callers (toast helpers, inline error UIs) don't have to dig through
    // `error.response.data` every time. `extractApiError()` / `formatApiError()`
    // in utils/apiError.ts are the usual consumers.
    try {
      const data = error.response?.data;
      if (data && typeof data === 'object') {
        const envelope = data as { code?: unknown; request_id?: unknown };
        const code = typeof envelope.code === 'string' ? envelope.code : null;
        const requestId = typeof envelope.request_id === 'string' ? envelope.request_id : null;
        if (code) error.errorCode = code;
        if (requestId) error.requestId = requestId;
      }
      const xrid = error.response?.headers?.['x-request-id'];
      if (!error.requestId && typeof xrid === 'string') error.requestId = xrid;

      // Dev-mode trace: every rejected request logs `{status, code, request_id,
      // url}` to the browser console. Production stays quiet to avoid leaking
      // correlation ids into log shippers that forward browser errors to
      // less-trusted sinks. Import check for Vite's import.meta.env.DEV keeps
      // this tree-shakable in production bundles.
      if (import.meta.env.DEV && error.response?.status && error.response.status >= 400) {
        // eslint-disable-next-line no-console
        console.warn('[api]', {
          status: error.response.status,
          method: error.config?.method?.toUpperCase(),
          url: error.config?.url,
          code: error.errorCode,
          requestId: error.requestId,
          message: error.response?.data?.message ?? error.message,
        });
      }
    } catch { /* best-effort tagging — never let this throw */ }

    // Tier gate 403: open the upgrade modal globally so the user sees it
    if (error.response?.status === 403 && error.response?.data?.upgrade_required) {
      // Lazy import to avoid circular deps with planStore
      import('@/stores/planStore')
        .then(({ usePlanStore, isUpgradeFeatureKey }) => {
          const rawFeature = error.response?.data?.feature;
          // Validate the feature string against the known union before handing
          // it to openUpgradeModal(). Without this, a malformed or attacker-
          // controlled 403 body could inject an arbitrary string and break
          // the type guarantee at runtime.
          if (!isUpgradeFeatureKey(rawFeature)) {
            devWarn('Ignoring 403 upgrade_required with unknown feature:', rawFeature);
            return;
          }
          usePlanStore.getState().openUpgradeModal(rawFeature);
        })
        .catch((err) => {
          devWarn('Failed to open upgrade modal:', err);
        });
      return Promise.reject(error);
    }

    // Don't intercept auth endpoints or /me check
    if (originalRequest.url?.includes('/auth/')) {
      return Promise.reject(error);
    }

    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;
      try {
        const accessToken = await performRefresh();
        originalRequest.headers.Authorization = `Bearer ${accessToken}`;
        // WEB-FI-003 fix: if the retried request still 401s the response was
        // previously rejected to the caller WITHOUT a logout — the auth store
        // still thought the user was authenticated, so the user kept seeing
        // 401 toasts on every action (clock-skew, token-version bump, role
        // change between issuance and use). Catch the second 401 here and
        // forceLogout('session-expired') so the auth store + listeners flip
        // immediately and the user is sent to /login.
        try {
          return await client(originalRequest);
        } catch (retryErr) {
          // Use a typed-narrow check rather than `any` to avoid a hard-cast.
          const retryStatus =
            typeof retryErr === 'object' && retryErr !== null
              ? (retryErr as { response?: { status?: number } }).response?.status
              : undefined;
          if (retryStatus === 401) {
            devWarn('Retried request still 401 after refresh; forcing logout.');
            forceLogout('session-expired');
          }
          return Promise.reject(retryErr);
        }
      } catch (refreshErr) {
        devWarn('Token refresh failed, logging out:', refreshErr);
        forceLogout('refresh-failed');
      }
    }

    // Show a user-visible toast for 5xx server errors so failures are never
    // silently swallowed. We skip auth endpoints (already handled above) and
    // network errors where response is undefined (offline, CORS, etc.) since
    // those have no status code to inspect.
    // WEB-FI-004 / FIXED-by-Fixer-ZZ 2026-04-25 — callers that already render
    // their own error UI in `useMutation({ onError })` can pass
    // `{ skipGlobal500Toast: true }` on the request config to suppress this
    // global toast and avoid the "Server error..." over the specific message
    // pile-up. Defaults to false so existing behavior is preserved.
    const status = error.response?.status;
    const skipGlobal = (originalRequest as { skipGlobal500Toast?: boolean })
      ?.skipGlobal500Toast === true;
    if (status !== undefined && status >= 500 && !skipGlobal) {
      const serverMsg =
        typeof error.response?.data?.message === 'string'
          ? error.response.data.message
          : null;
      toast.error(serverMsg ?? 'Server error — please try again.');
    }

    // WEB-FO-001: surface 409 Conflict on mutating requests so concurrent
    // edits don't silently overwrite a co-worker. Last-write-wins races on
    // tickets/invoices were producing "the status pill jumps under your
    // cursor" UX with zero feedback. We don't add an If-Match header here
    // (server-side optimistic-concurrency is a larger change), but if the
    // server already returns 409 (e.g. version-locked routes), the user
    // now learns about it. Filtered to write methods so list-level 409s
    // from things like duplicate-create flows bubble through their own
    // handlers untouched.
    const method = (originalRequest?.method ?? '').toLowerCase();
    if (
      status === 409 &&
      (method === 'put' || method === 'patch' || method === 'post' || method === 'delete')
    ) {
      const serverMsg =
        typeof error.response?.data?.message === 'string'
          ? error.response.data.message
          : null;
      toast.error(
        serverMsg ?? 'This item was updated elsewhere — refresh to see the latest changes.',
        { id: 'conflict-409' }, // dedupe burst on rapid double-click
      );
    }

    return Promise.reject(error);
  },
);

export default client;
export { client as api };

// ──────────────────────────────────────────────────────────────────
// Super-admin axios client — uses a separate token stored under
// 'superAdminToken'. Does NOT participate in the regular tenant
// refresh pipeline.
//
// WEB-FJ-001: SA token now lives in sessionStorage (not localStorage)
// — XSS still reads it while the tab is open, but a stolen token does
// not survive tab close, no cross-tab leak via storage events, and a
// reboot/reopen does not silently re-authenticate. Helpers below
// centralise read/write/remove so all call-sites stay consistent;
// `superAdminTokenStore` is the only thing that should touch the
// underlying storage.
// ──────────────────────────────────────────────────────────────────
export const SUPER_ADMIN_TOKEN_KEY = 'superAdminToken';
export const SUPER_ADMIN_LOGOUT_EVENT = 'bizarre-crm:super-admin-logout';

export const superAdminTokenStore = {
  get(): string | null {
    if (typeof window === 'undefined') return null;
    try {
      // Migrate any legacy localStorage token from before WEB-FJ-001 so
      // existing operators don't get an unexpected forced sign-out.
      const legacy = window.localStorage.getItem(SUPER_ADMIN_TOKEN_KEY);
      if (legacy) {
        window.sessionStorage.setItem(SUPER_ADMIN_TOKEN_KEY, legacy);
        window.localStorage.removeItem(SUPER_ADMIN_TOKEN_KEY);
        return legacy;
      }
      return window.sessionStorage.getItem(SUPER_ADMIN_TOKEN_KEY);
    } catch {
      return null;
    }
  },
  set(token: string): void {
    if (typeof window === 'undefined') return;
    try {
      window.sessionStorage.setItem(SUPER_ADMIN_TOKEN_KEY, token);
      // Clear any legacy localStorage residue.
      window.localStorage.removeItem(SUPER_ADMIN_TOKEN_KEY);
    } catch { /* quota / privacy mode — ignore */ }
  },
  remove(): void {
    if (typeof window === 'undefined') return;
    try {
      window.sessionStorage.removeItem(SUPER_ADMIN_TOKEN_KEY);
      window.localStorage.removeItem(SUPER_ADMIN_TOKEN_KEY);
    } catch { /* ignore */ }
  },
};

// WEB-FI-002 / FIXED-by-Fixer-ZZ 2026-04-25 — add explicit timeout so a hung
// super-admin request doesn't trap the operator on an indefinite spinner. The
// SA console's only credential is the bearer; there's no graceful degradation
// when a tenant call stalls. 30s matches the tenant-side default.
export const superAdminClient = axios.create({
  baseURL: '/super-admin/api',
  headers: { 'Content-Type': 'application/json' },
  timeout: 30_000,
});

superAdminClient.interceptors.request.use((config) => {
  const token = superAdminTokenStore.get();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Response interceptor: on 401/403 the super-admin token is dead. Without
// this, every subsequent call silently fails and the stored credential is
// never cleaned up. Clear the token, surface a toast, and dispatch an event
// so mounted pages can unmount the authed view.
superAdminClient.interceptors.response.use(
  (response) => response,
  (error) => {
    const status = error.response?.status;
    if (status === 401 || status === 403) {
      if (superAdminTokenStore.get()) {
        superAdminTokenStore.remove();
        try {
          window.dispatchEvent(new CustomEvent(SUPER_ADMIN_LOGOUT_EVENT));
        } catch (err) {
          devWarn('Failed to emit super-admin-logout event', err);
        }
        toast.error('Super-admin session expired. Please sign in again.');
      }
    }
    return Promise.reject(error);
  },
);
