import axios from 'axios';
import { useAuthStore } from '@/stores/authStore';

const API_BASE = '/api/v1';

const client = axios.create({
  baseURL: API_BASE,
  headers: { 'Content-Type': 'application/json' },
  withCredentials: true, // Send httpOnly cookies with requests
});

// Request interceptor: attach auth token
client.interceptors.request.use((config) => {
  const token = localStorage.getItem('accessToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
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

// Response interceptor: handle 401, auto-refresh via httpOnly cookie
client.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

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
