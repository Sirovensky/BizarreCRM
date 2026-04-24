import axios from 'axios';
import toast from 'react-hot-toast';
import { useAuthStore } from '@/stores/authStore';

const API_BASE = '/api/v1';

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

function emitLogoutRequired(reason: LogoutRequiredDetail['reason']) {
  try {
    window.dispatchEvent(
      new CustomEvent<LogoutRequiredDetail>(LOGOUT_REQUIRED_EVENT, { detail: { reason } }),
    );
  } catch (err) {
    // Environments without window (SSR/tests) — best-effort only
    console.warn('Failed to emit logout-required event', err);
  }
}

// SEC-H89: Read the non-httpOnly csrf_token cookie so we can forward it as
// X-CSRF-Token on POST /auth/refresh (double-submit CSRF protection).
function getCsrfTokenCookie(): string {
  if (typeof document === 'undefined') return '';
  const match = document.cookie.match(/(?:^|;\s*)csrf_token=([^;]+)/);
  return match ? decodeURIComponent(match[1]) : '';
}

const client = axios.create({
  baseURL: API_BASE,
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true, // Send httpOnly cookies with requests
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
      const res = await axios.post(
        `${API_BASE}/auth/refresh`,
        {},
        { withCredentials: true, headers: csrfToken ? { 'X-CSRF-Token': csrfToken } : {} },
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
function scheduleTokenRefresh() {
  if (refreshScheduled) return;
  const token = localStorage.getItem('accessToken');
  if (!token) return;
  try {
    const parts = token.split('.');
    if (parts.length < 3) throw new Error('malformed');
    if (parts[1].length > 4096) throw new Error('payload too large');
    const decoded = atob(parts[1]);
    if (decoded.length > 8192) throw new Error('decoded payload too large');
    const payload = JSON.parse(decoded);
    const expiresIn = (payload.exp * 1000) - Date.now();
    const refreshIn = Math.max(expiresIn - 5 * 60 * 1000, 10_000); // 5 min before expiry, min 10s
    refreshScheduled = true;
    setTimeout(async () => {
      refreshScheduled = false;
      try {
        await performRefresh();
        scheduleTokenRefresh(); // Schedule next refresh
      } catch (err) {
        // Refresh failed — let the 401 interceptor handle it on the next request
        console.warn('Proactive token refresh failed:', err);
      }
    }, refreshIn);
  } catch (err) {
    // Invalid token format — reset scheduling flag so future requests can
    // re-enter scheduleTokenRefresh instead of being silently skipped.
    refreshScheduled = false;
    // Clear the malformed token so it doesn't block every subsequent request.
    // Only remove it if it hasn't been replaced by a concurrent refresh.
    if (localStorage.getItem('accessToken') === token) {
      localStorage.removeItem('accessToken');
    }
    console.warn('Could not decode access token for refresh scheduling:', err);
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
  if (config.url?.includes('/auth/refresh') && config.method?.toUpperCase() === 'POST') {
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
  const token = localStorage.getItem('accessToken');
  localStorage.removeItem('accessToken');
  // @audit-fixed: drop any pending proactive-refresh promise so the next login
  // can re-arm scheduling cleanly. Without this, `refreshScheduled` and a stale
  // `sharedRefreshPromise` would survive the logout and the new session would
  // skip its first proactive refresh window.
  refreshScheduled = false;
  sharedRefreshPromise = null;
  // Use logoutClient (no interceptors) to avoid 401 loop
  logoutClient
    .post('/auth/logout', {}, {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    })
    .catch((err) => {
      // Logout endpoint failure is non-fatal — local state will still clear
      console.warn('Logout endpoint call failed:', err);
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
        const code = typeof (data as any).code === 'string' ? (data as any).code : null;
        const requestId =
          typeof (data as any).request_id === 'string' ? (data as any).request_id : null;
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
        .then(({ usePlanStore }) => {
          const feature = error.response.data.feature;
          usePlanStore.getState().openUpgradeModal(feature);
        })
        .catch((err) => {
          console.warn('Failed to open upgrade modal:', err);
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
        return client(originalRequest);
      } catch (refreshErr) {
        console.warn('Token refresh failed, logging out:', refreshErr);
        forceLogout('refresh-failed');
      }
    }

    // Show a user-visible toast for 5xx server errors so failures are never
    // silently swallowed. We skip auth endpoints (already handled above) and
    // network errors where response is undefined (offline, CORS, etc.) since
    // those have no status code to inspect.
    const status = error.response?.status;
    if (status !== undefined && status >= 500) {
      const serverMsg =
        typeof error.response?.data?.message === 'string'
          ? error.response.data.message
          : null;
      toast.error(serverMsg ?? 'Server error — please try again.');
    }

    return Promise.reject(error);
  },
);

export default client;
export { client as api };

// ──────────────────────────────────────────────────────────────────
// Super-admin axios client — uses a separate token stored under
// 'superAdminToken' in localStorage. Does NOT participate in the
// regular tenant refresh pipeline.
// ──────────────────────────────────────────────────────────────────
export const SUPER_ADMIN_TOKEN_KEY = 'superAdminToken';

export const superAdminClient = axios.create({
  baseURL: '/super-admin/api',
  headers: { 'Content-Type': 'application/json' },
});

superAdminClient.interceptors.request.use((config) => {
  const token = localStorage.getItem(SUPER_ADMIN_TOKEN_KEY);
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});
