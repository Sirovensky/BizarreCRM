import { useState, useEffect, useCallback, useRef } from 'react';
import * as api from './portalApi';

// WEB-FJ-010: 15-minute idle timeout for the magic-link portal session.
// Activity is tracked via mousemove and keydown; both are throttled to at most
// one update per second to avoid flooding state updates on continuous mouse
// movement. On idle > 900s the session is cleared and the user is redirected
// to the portal login page.
const IDLE_TIMEOUT_MS = 900_000; // 15 min
const ACTIVITY_THROTTLE_MS = 1_000;

interface PortalAuthState {
  isLoading: boolean;
  isAuthenticated: boolean;
  customerName: string | null;
  scope: 'ticket' | 'full' | null;
  ticketId: number | null;
  hasAccount: boolean;
}

export function usePortalAuth() {
  const [state, setState] = useState<PortalAuthState>({
    isLoading: true,
    isAuthenticated: false,
    customerName: null,
    scope: null,
    ticketId: null,
    hasAccount: false,
  });

  // Verify existing token on mount
  useEffect(() => {
    const token = sessionStorage.getItem('portal_token');
    if (!token) {
      setState(s => ({ ...s, isLoading: false }));
      return;
    }

    api.verifySession(token).then(result => {
      if (result.valid) {
        setState({
          isLoading: false,
          isAuthenticated: true,
          customerName: result.customer_first_name || null,
          scope: result.scope || null,
          ticketId: result.ticket_id || null,
          hasAccount: result.has_account || false,
        });
      } else {
        sessionStorage.removeItem('portal_token');
        sessionStorage.removeItem('portal_scope');
        api.clearPortalSecurityTokens();
        setState(s => ({ ...s, isLoading: false }));
      }
    }).catch((err) => {
      // Only clear token on auth failures (401/403), not network errors
      const status = (err as any)?.response?.status;
      if (status === 401 || status === 403) {
        sessionStorage.removeItem('portal_token');
        sessionStorage.removeItem('portal_scope');
        api.clearPortalSecurityTokens();
      }
      setState(s => ({ ...s, isLoading: false }));
    });
  }, []);

  // WEB-S4-023: accept optional hasAccount from verifySession so that ticket-
  // scoped sessions for customers who have a registered portal account still
  // show the "Create account" upsell correctly (or suppress it when they do).
  const loginWithToken = useCallback((
    token: string,
    scope: 'ticket' | 'full',
    customerName: string,
    ticketId?: number,
    hasAccount?: boolean,
  ) => {
    sessionStorage.setItem('portal_token', token);
    sessionStorage.setItem('portal_scope', scope);
    setState({
      isLoading: false,
      isAuthenticated: true,
      customerName,
      scope,
      ticketId: ticketId || null,
      // Prefer explicit hasAccount when provided; fall back to scope inference.
      hasAccount: hasAccount !== undefined ? hasAccount : scope === 'full',
    });
  }, []);

  const logout = useCallback(async () => {
    try { await api.portalLogout(); } catch { /* ignore */ }
    sessionStorage.removeItem('portal_token');
    sessionStorage.removeItem('portal_scope');
    api.clearPortalSecurityTokens();
    setState({
      isLoading: false,
      isAuthenticated: false,
      customerName: null,
      scope: null,
      ticketId: null,
      hasAccount: false,
    });
  }, []);

  // WEB-FJ-010: idle timeout. Track last user activity; if authenticated and
  // the session has been idle for IDLE_TIMEOUT_MS, call logout and redirect to
  // the portal login page so stale sessions are not left open on shared devices.
  const lastActivityRef = useRef<number>(Date.now());
  const idleTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    // Only run the idle timer when the portal session is active.
    if (!state.isAuthenticated) {
      if (idleTimerRef.current) {
        clearInterval(idleTimerRef.current);
        idleTimerRef.current = null;
      }
      return;
    }

    lastActivityRef.current = Date.now();

    let lastThrottle = 0;
    const onActivity = () => {
      const now = Date.now();
      if (now - lastThrottle < ACTIVITY_THROTTLE_MS) return;
      lastThrottle = now;
      lastActivityRef.current = now;
    };

    window.addEventListener('mousemove', onActivity, { passive: true });
    window.addEventListener('keydown', onActivity, { passive: true });
    window.addEventListener('touchstart', onActivity, { passive: true });

    // Poll every 30s to check for idle expiry. Avoids a single long setTimeout
    // that can drift badly when the tab is backgrounded.
    idleTimerRef.current = setInterval(() => {
      if (Date.now() - lastActivityRef.current > IDLE_TIMEOUT_MS) {
        // Session expired due to inactivity — clean up and redirect to portal login.
        logout().then(() => {
          // Navigate to portal root (login page).
          if (typeof window !== 'undefined') {
            window.location.href = '/portal';
          }
        });
      }
    }, 30_000);

    return () => {
      window.removeEventListener('mousemove', onActivity);
      window.removeEventListener('keydown', onActivity);
      window.removeEventListener('touchstart', onActivity);
      if (idleTimerRef.current) {
        clearInterval(idleTimerRef.current);
        idleTimerRef.current = null;
      }
    };
  }, [state.isAuthenticated, logout]);

  return { ...state, loginWithToken, logout };
}
