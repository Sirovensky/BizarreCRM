import { useState, useEffect, useCallback } from 'react';
import * as api from './portalApi';

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

  return { ...state, loginWithToken, logout };
}
