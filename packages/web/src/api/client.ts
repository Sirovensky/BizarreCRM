import axios from 'axios';
import { useAuthStore } from '@/stores/authStore';

const API_BASE = '/api/v1';

const client = axios.create({
  baseURL: API_BASE,
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true, // Send httpOnly cookies with requests
});

// Proactive token refresh — refresh 5 min before expiry
let refreshScheduled = false;
function scheduleTokenRefresh() {
  if (refreshScheduled) return;
  const token = localStorage.getItem('accessToken');
  if (!token) return;
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    const expiresIn = (payload.exp * 1000) - Date.now();
    const refreshIn = Math.max(expiresIn - 5 * 60 * 1000, 10_000); // 5 min before expiry, min 10s
    refreshScheduled = true;
    setTimeout(async () => {
      refreshScheduled = false;
      try {
        const res = await axios.post(`${API_BASE}/auth/refresh`, {}, { withCredentials: true });
        const { accessToken } = res.data.data;
        localStorage.setItem('accessToken', accessToken);
        scheduleTokenRefresh(); // Schedule next refresh
      } catch {
        // Refresh failed — will be caught by 401 interceptor on next request
      }
    }, refreshIn);
  } catch {
    // Invalid token format — ignore
  }
}

// Request interceptor: attach auth token
client.interceptors.request.use((config) => {
  const token = localStorage.getItem('accessToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
    scheduleTokenRefresh();
  }
  return config;
});

// Track in-flight refresh to avoid race conditions
let refreshPromise: Promise<any> | null = null;
let isLoggingOut = false;

// Separate axios instance for logout to avoid triggering the 401 interceptor loop
const logoutClient = axios.create({ baseURL: API_BASE, withCredentials: true });

function forceLogout() {
  if (isLoggingOut) return;
  isLoggingOut = true;
  const token = localStorage.getItem('accessToken');
  localStorage.removeItem('accessToken');
  // Use logoutClient (no interceptors) to avoid 401 loop
  logoutClient.post('/auth/logout', {}, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  }).catch(() => {}).finally(() => {
    useAuthStore.setState({ user: null, isAuthenticated: false, isLoading: false });
    isLoggingOut = false;
  });
}

// Response interceptor: handle 401 (refresh) and 403 (upgrade_required)
client.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    // Tier gate 403: open the upgrade modal globally so the user sees it
    if (error.response?.status === 403 && error.response?.data?.upgrade_required) {
      // Lazy import to avoid circular deps with planStore
      import('@/stores/planStore').then(({ usePlanStore }) => {
        const feature = error.response.data.feature;
        usePlanStore.getState().openUpgradeModal(feature);
      }).catch(() => {});
      return Promise.reject(error);
    }

    // Don't intercept auth endpoints or /me check
    if (originalRequest.url?.includes('/auth/')) {
      return Promise.reject(error);
    }

    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;
      try {
        if (!refreshPromise) {
          // Cookie is sent automatically via withCredentials
          refreshPromise = axios.post(`${API_BASE}/auth/refresh`, {}, { withCredentials: true });
        }
        const res = await refreshPromise;
        refreshPromise = null;
        const { accessToken } = res.data.data;
        localStorage.setItem('accessToken', accessToken);
        originalRequest.headers.Authorization = `Bearer ${accessToken}`;
        return client(originalRequest);
      } catch {
        refreshPromise = null;
        forceLogout();
      }
    }
    return Promise.reject(error);
  }
);

export default client;
export { client as api };
