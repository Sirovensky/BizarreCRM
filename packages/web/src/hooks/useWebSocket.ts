import { useEffect, useRef, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { create } from 'zustand';
import toast from 'react-hot-toast';
import { WS_EVENTS } from '@bizarre-crm/shared';

// ---------------------------------------------------------------------------
// Shared connection state (zustand - avoids re-renders from ref-based state)
// ---------------------------------------------------------------------------
interface WsState {
  isConnected: boolean;
  lastMessage: { type: string; data: unknown } | null;
  setConnected: (v: boolean) => void;
  setLastMessage: (msg: { type: string; data: unknown }) => void;
}

export const useWsStore = create<WsState>((set) => ({
  isConnected: false,
  lastMessage: null,
  setConnected: (v) => set({ isConnected: v }),
  setLastMessage: (msg) => set({ lastMessage: msg }),
}));

// ---------------------------------------------------------------------------
// Resolve the WebSocket URL
// ---------------------------------------------------------------------------
function getWsUrl(): string {
  const loc = window.location;
  const protocol = loc.protocol === 'https:' ? 'wss:' : 'ws:';

  // Derive the default API port from the current page URL.
  // In production the page is served by the API server itself, so loc.port
  // (or the implicit port for the protocol) is the correct API port.
  const defaultPort = loc.port || (loc.protocol === 'https:' ? '443' : '80');
  const apiPort = import.meta.env.VITE_API_PORT || defaultPort;

  // If running through a Vite dev proxy (port differs from API), connect
  // directly to the API server.
  if (loc.port && loc.port !== apiPort) {
    return `${protocol}//${loc.hostname}:${apiPort}`;
  }

  // Same-origin (production): WS on the same host
  return `${protocol}//${loc.host}`;
}

// ---------------------------------------------------------------------------
// Event-to-invalidation mapping
// ---------------------------------------------------------------------------
type InvalidationEntry = {
  queryKeys: (string | number | undefined)[][];
  toast?: (data: any) => string;
};

function buildInvalidationMap(): Record<string, InvalidationEntry> {
  return {
    [WS_EVENTS.TICKET_CREATED]: {
      queryKeys: [['tickets']],
      toast: () => 'New ticket created',
    },
    [WS_EVENTS.TICKET_UPDATED]: {
      queryKeys: [['tickets']],
      // Also invalidate specific ticket if id is in the payload
      toast: undefined,
    },
    [WS_EVENTS.TICKET_STATUS_CHANGED]: {
      queryKeys: [['tickets'], ['dashboard']],
      toast: undefined,
    },
    [WS_EVENTS.TICKET_NOTE_ADDED]: {
      queryKeys: [['tickets']],
      toast: undefined,
    },
    [WS_EVENTS.TICKET_DELETED]: {
      queryKeys: [['tickets'], ['dashboard']],
      toast: undefined,
    },
    'sms_received': {
      // SMS routes currently broadcast with literal 'sms_received'
      queryKeys: [['sms-conversations']],
      toast: (data: any) => `New SMS from ${data?.from || data?.customer?.first_name || 'unknown'}`,
    },
    [WS_EVENTS.SMS_RECEIVED]: {
      queryKeys: [['sms-conversations']],
      toast: (data: any) => `New SMS from ${data?.from || data?.customer?.first_name || 'unknown'}`,
    },
    [WS_EVENTS.NOTIFICATION_NEW]: {
      queryKeys: [['notifications'], ['notification-count']],
      toast: undefined,
    },
    [WS_EVENTS.INVOICE_CREATED]: {
      queryKeys: [['invoices']],
      toast: () => 'New invoice created',
    },
    [WS_EVENTS.INVOICE_UPDATED]: {
      queryKeys: [['invoices']],
      toast: undefined,
    },
    [WS_EVENTS.PAYMENT_RECEIVED]: {
      queryKeys: [['invoices'], ['dashboard']],
      toast: (data: any) => data?.amount ? `Payment of $${data.amount} received` : 'Payment received',
    },
    [WS_EVENTS.INVENTORY_STOCK_CHANGED]: {
      queryKeys: [['inventory']],
      toast: undefined,
    },
    [WS_EVENTS.INVENTORY_LOW_STOCK]: {
      queryKeys: [['inventory']],
      toast: (data: any) => `Low stock alert: ${data?.name || 'item'}`,
    },
    [WS_EVENTS.LEAD_CREATED]: {
      queryKeys: [['leads']],
      toast: () => 'New lead created',
    },
    [WS_EVENTS.CUSTOMER_CREATED]: {
      queryKeys: [['customers']],
      toast: undefined,
    },
    [WS_EVENTS.CUSTOMER_UPDATED]: {
      queryKeys: [['customers']],
      toast: undefined,
    },
  };
}

// ---------------------------------------------------------------------------
// The hook
// ---------------------------------------------------------------------------
const MAX_BACKOFF = 30_000;
const INITIAL_BACKOFF = 1_000;

export function useWebSocket() {
  const queryClient = useQueryClient();
  const wsRef = useRef<WebSocket | null>(null);
  const backoffRef = useRef(INITIAL_BACKOFF);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const unmountedRef = useRef(false);
  const authRejectedRef = useRef(false);
  const invalidationMap = useRef(buildInvalidationMap());
  // Stable ref so connect() can call scheduleReconnect() without a circular
  // useCallback dependency or capturing a stale closure value.
  const scheduleReconnectRef = useRef<() => void>(() => { /* populated below */ });

  const { setConnected, setLastMessage } = useWsStore();

  const getToken = useCallback(() => localStorage.getItem('accessToken'), []);

  const disconnect = useCallback(() => {
    if (reconnectTimerRef.current) {
      clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }
    if (wsRef.current) {
      wsRef.current.onclose = null; // Prevent reconnect on intentional close
      wsRef.current.close();
      wsRef.current = null;
    }
    setConnected(false);
  }, [setConnected]);

  const connect = useCallback(() => {
    if (unmountedRef.current) return;
    const token = getToken();
    if (!token) return; // Not authenticated

    // Clean up any existing connection
    if (wsRef.current) {
      wsRef.current.onclose = null; // Prevent reconnect loop
      wsRef.current.close();
      wsRef.current = null;
    }

    const url = getWsUrl();
    let ws: WebSocket;
    try {
      ws = new WebSocket(url);
    } catch {
      scheduleReconnectRef.current();
      return;
    }
    wsRef.current = ws;

    ws.onopen = () => {
      // Authenticate immediately
      ws.send(JSON.stringify({ type: 'auth', token }));
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        const { type, data, success } = msg;

        // Handle auth response
        if (type === 'auth') {
          if (success) {
            setConnected(true);
            authRejectedRef.current = false;
            backoffRef.current = INITIAL_BACKOFF; // Reset backoff on successful auth
          } else {
            // Auth explicitly rejected — stop reconnecting with this token
            authRejectedRef.current = true;
            ws.close();
          }
          return;
        }

        // Store last message
        setLastMessage({ type, data });

        // Invalidate relevant query keys
        const entry = invalidationMap.current[type];
        if (entry) {
          for (const qk of entry.queryKeys) {
            queryClient.invalidateQueries({ queryKey: qk.filter((k) => k !== undefined) });
          }

          // Also invalidate specific entity if data.id is present
          if (data?.id) {
            if (type.startsWith('ticket:')) {
              queryClient.invalidateQueries({ queryKey: ['ticket', String(data.id)] });
              queryClient.invalidateQueries({ queryKey: ['ticket', Number(data.id)] });
            } else if (type.startsWith('invoice:')) {
              queryClient.invalidateQueries({ queryKey: ['invoice', String(data.id)] });
              queryClient.invalidateQueries({ queryKey: ['invoice', Number(data.id)] });
            } else if (type.startsWith('inventory:')) {
              queryClient.invalidateQueries({ queryKey: ['inventory-item', String(data.id)] });
              queryClient.invalidateQueries({ queryKey: ['inventory-item', Number(data.id)] });
            }
          }

          // Show toast if configured
          if (entry.toast) {
            const message = entry.toast(data);
            if (message) {
              toast(message, { icon: getIconForEvent(type) });
            }
          }
        }
      } catch {
        // Ignore unparsable messages
      }
    };

    ws.onclose = (event) => {
      setConnected(false);
      wsRef.current = null;
      // Don't reconnect on auth failure close codes (4001 = auth rejected, 4003 = forbidden)
      if (event.code === 4001 || event.code === 4003) {
        authRejectedRef.current = true;
        return;
      }
      scheduleReconnectRef.current();
    };

    ws.onerror = () => {
      // onerror is always followed by onclose, so reconnect happens there
    };
  }, [getToken, queryClient, setConnected, setLastMessage]); // scheduleReconnect accessed via ref, not in dep array

  const scheduleReconnect = useCallback(() => {
    if (unmountedRef.current) return;
    if (authRejectedRef.current) return; // Don't reconnect if auth was explicitly rejected
    // Don't reconnect while tab is hidden — will reconnect when tab becomes visible
    if (document.visibilityState === 'hidden') return;
    if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);

    const delay = backoffRef.current;
    backoffRef.current = Math.min(backoffRef.current * 2, MAX_BACKOFF);

    reconnectTimerRef.current = setTimeout(() => {
      reconnectTimerRef.current = null;
      connect();
    }, delay);
  }, [connect]);

  // Keep the ref in sync so connect()'s closure always calls the latest version.
  scheduleReconnectRef.current = scheduleReconnect;

  useEffect(() => {
    unmountedRef.current = false;
    connect();

    // Reconnect when tab becomes visible again (if disconnected while hidden)
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible' && !wsRef.current && !authRejectedRef.current) {
        backoffRef.current = INITIAL_BACKOFF;
        connect();
      }
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);

    // Close the socket immediately when the user logs out so it does not
    // linger as an authenticated connection after credentials are cleared.
    const handleAuthCleared = () => {
      authRejectedRef.current = false; // allow reconnect on next login
      disconnect();
    };
    window.addEventListener('bizarre-crm:auth-cleared', handleAuthCleared);

    return () => {
      unmountedRef.current = true;
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('bizarre-crm:auth-cleared', handleAuthCleared);
      disconnect();
    };
  }, [connect, disconnect]); // mount-only: disconnect is stable (useCallback with stable deps)
}

// ---------------------------------------------------------------------------
// Helper: pick a toast icon based on event type
// ---------------------------------------------------------------------------
function getIconForEvent(type: string): string {
  if (type.startsWith('ticket:')) return '\uD83D\uDCCB';   // clipboard
  if (type.startsWith('sms')) return '\uD83D\uDCF1';       // mobile phone
  if (type.startsWith('invoice:')) return '\uD83D\uDCB0';  // money bag
  if (type.startsWith('inventory:')) return '\uD83D\uDCE6'; // package
  if (type.startsWith('lead:')) return '\uD83D\uDC64';     // person
  return '\uD83D\uDD14'; // bell
}
