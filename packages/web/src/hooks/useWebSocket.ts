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

// WEB-FO-016 (Fixer-B15 2026-04-25): wipe the module-scoped `lastMessage`
// snapshot whenever auth is cleared (logout, switchUser). The Zustand
// store persists across the auth lifecycle, so any future subscriber
// would briefly read the prior user's last WS payload — a cross-tenant
// leak shape even if no current consumer reads it. Belt-and-suspenders
// against future regressions; mirrors the queryClient.clear() that
// main.tsx already runs on the same event.
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => {
    useWsStore.setState({ lastMessage: null, isConnected: false });
  });
}

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
  toast?: (data: unknown) => string;
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
    // WEB-FN-007 (Fixer-B12 2026-04-25): dropped legacy `'sms_received'`
    // literal subscription. Server only ever broadcasts the colon-form
    // `WS_EVENTS.SMS_RECEIVED` (`sms:received`); the snake_case literal
    // never fired. Keep the canonical handler below as the single source.
    // WEB-FO-008 (Fixer-B18 2026-04-25): also invalidate `['sms-messages']`
    // (any phone) so the open thread refreshes on inbound + status updates
    // without needing a 10s `refetchInterval` poll. Generic key invalidation
    // covers every cached phone — the only one currently rendered is the
    // selected conversation, which is exactly what we want to refresh.
    [WS_EVENTS.SMS_RECEIVED]: {
      queryKeys: [['sms-conversations'], ['sms-messages']],
      toast: (data: unknown) => {
        const d = data as { from?: string; customer?: { first_name?: string } } | null;
        return `New SMS from ${d?.from || d?.customer?.first_name || 'unknown'}`;
      },
    },
    // sms:status_updated — server emits when an outbound SMS delivery status changes
    'sms:status_updated': {
      queryKeys: [['sms-conversations'], ['sms-messages']],
      toast: undefined,
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
      toast: (data: unknown) => {
        const d = data as { amount?: number | string } | null;
        return d?.amount ? `Payment of $${d.amount} received` : 'Payment received';
      },
    },
    [WS_EVENTS.INVENTORY_STOCK_CHANGED]: {
      queryKeys: [['inventory']],
      toast: undefined,
    },
    [WS_EVENTS.INVENTORY_LOW_STOCK]: {
      queryKeys: [['inventory']],
      toast: (data: unknown) => {
        const d = data as { name?: string } | null;
        return `Low stock alert: ${d?.name || 'item'}`;
      },
    },
    [WS_EVENTS.LEAD_CREATED]: {
      queryKeys: [['leads']],
      toast: () => 'New lead created',
    },
    // voice:* — server emits for call lifecycle events
    'voice:call_initiated': {
      queryKeys: [['voice', 'calls']],
      toast: undefined,
    },
    'voice:call_updated': {
      queryKeys: [['voice', 'calls']],
      toast: undefined,
    },
    'voice:inbound_call': {
      queryKeys: [['voice', 'calls']],
      toast: (data: unknown) => {
        const d = data as { from?: string } | null;
        return `Incoming call from ${d?.from || 'unknown'}`;
      },
    },
    'voice:recording_ready': {
      queryKeys: [['voice', 'calls']],
      toast: undefined,
    },
    'voice:transcription_ready': {
      queryKeys: [['voice', 'calls']],
      toast: undefined,
    },
    // import:* — server emits progress/completion events during CSV imports
    [WS_EVENTS.IMPORT_PROGRESS]: {
      queryKeys: [['imports']],
      toast: undefined,
    },
    [WS_EVENTS.IMPORT_COMPLETE]: {
      queryKeys: [['imports']],
      toast: () => 'Import complete',
    },
    // system:stall_alert — server emits when a ticket has been stalled past threshold
    [WS_EVENTS.STALL_ALERT]: {
      queryKeys: [['tickets']],
      toast: (data: unknown) => {
        const d = data as { id?: number | string } | null;
        return d?.id ? `Ticket stalled: #${d.id}` : 'A ticket has stalled';
      },
    },
    // management:* events are internal dashboard-only — no corresponding UI, skip silently
    // (WS_EVENTS.MANAGEMENT_STATS, MANAGEMENT_CRASH, etc. intentionally omitted)

    // NOTE: WS_EVENTS.CUSTOMER_CREATED / CUSTOMER_UPDATED are defined in the
    // shared constants but the server never emits them. Removed from this map
    // to avoid silently accumulating dead entries.
  };
}

// ---------------------------------------------------------------------------
// The hook
// ---------------------------------------------------------------------------
const MAX_BACKOFF = 30_000;
const INITIAL_BACKOFF = 1_000;
// WEB-FO-003: NAT idle timeouts (60-300s on cellular / corp NAT) silently
// half-close WebSockets without firing onclose. Send a {type:'ping'} every
// 30s and force-close the socket if no message of any kind has arrived
// within the watchdog window. The browser's onclose then fires reconnect.
const PING_INTERVAL_MS = 30_000;
const PONG_TIMEOUT_MS = 60_000;

export function useWebSocket() {
  const queryClient = useQueryClient();
  // Keep queryClient in a ref so connect()'s useCallback doesn't need it as a
  // dep. Without this, a queryClient identity change (e.g. React Query DevTools
  // reinstantiation) recreates connect → re-runs the mount effect → opens a new
  // WS before the old one tears down → the old socket's onclose fires
  // scheduleReconnect while the new socket is already live (SCAN-600).
  const queryClientRef = useRef(queryClient);
  useEffect(() => { queryClientRef.current = queryClient; }, [queryClient]);
  const wsRef = useRef<WebSocket | null>(null);
  const backoffRef = useRef(INITIAL_BACKOFF);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const unmountedRef = useRef(false);
  const authRejectedRef = useRef(false);
  const invalidationMap = useRef(buildInvalidationMap());
  // WEB-FO-003 heartbeat plumbing.
  const pingTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastMessageAtRef = useRef<number>(0);

  const stopHeartbeat = useCallback(() => {
    if (pingTimerRef.current) {
      clearInterval(pingTimerRef.current);
      pingTimerRef.current = null;
    }
  }, []);
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
    stopHeartbeat();
    if (wsRef.current) {
      wsRef.current.onclose = null; // Prevent reconnect on intentional close
      wsRef.current.close();
      wsRef.current = null;
    }
    setConnected(false);
  }, [setConnected, stopHeartbeat]);

  const connect = useCallback(() => {
    if (unmountedRef.current) return;
    // WEB-FJ-003 (Fixer-A15 2026-04-25): hold the bootstrap token in a
    // mutable local so we can null it out after onopen. Previously the
    // `const token` was captured inside the onopen closure and the closure
    // (kept alive by the WebSocket instance) retained the JWT for the full
    // socket lifetime — so a refresh that rotated the access token still
    // left the original (now-stale) JWT reachable from the closure heap
    // until the socket finally closed.
    let token: string | null = getToken();
    if (!token) return; // Not authenticated

    // WEB-FD-003 (Fixer-A5 2026-04-25): refuse to ship the access-token as
    // a plaintext frame over `ws:`. In production builds we hard-fail any
    // non-https origin so the JWT is never put on an unencrypted socket
    // (was: token in `JSON.stringify({type:'auth',token})` valid for the
    // full refresh window if intercepted by a corporate-MITM/proxy).
    // `localhost` and `127.0.0.1` stay permitted so dev/Vite still works.
    if (
      import.meta.env.PROD &&
      window.location.protocol === 'http:' &&
      window.location.hostname !== 'localhost' &&
      window.location.hostname !== '127.0.0.1'
    ) {
      // eslint-disable-next-line no-console
      console.error('[ws] refusing to connect over plaintext ws: in production');
      return;
    }

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
      // WEB-FI-011 (Fixer-SSS 2026-04-25): re-read the access token at
      // onopen-time so a refresh that completed between the WebSocket
      // constructor call and the open handshake is picked up. Previously
      // the token captured in `connect()` (line ~243) was sent verbatim
      // in onopen — during a 401 burst recovery the freshly-rotated
      // refresh would land first, but this socket would still send the
      // expired token, get rejected with 4001, and bounce through
      // scheduleReconnect needlessly. If localStorage is now empty
      // (logout fired between connect and onopen), close the socket
      // cleanly so reconnect logic doesn't keep looping with no token.
      const freshToken = getToken() ?? token;
      if (!freshToken) {
        try { ws.close(); } catch { /* ignore */ }
        return;
      }
      // WEB-FO-015 (Fixer-B15 2026-04-25): reset reconnect backoff at TCP
      // open rather than waiting for `auth.success`. A server that closes
      // the socket immediately after handshake WITHOUT sending a 4001/4003
      // (e.g. an upstream proxy that drops the conn mid-auth) would
      // otherwise keep escalating backoff to the 30s ceiling on every
      // connect even though TCP itself succeeds. `isConnected` still
      // requires auth.success — only the backoff anchor moves earlier.
      backoffRef.current = INITIAL_BACKOFF;
      ws.send(JSON.stringify({ type: 'auth', token: freshToken }));
      // WEB-FJ-003 (Fixer-A15 2026-04-25): release the captured bootstrap
      // token so it isn't pinned in this closure for the lifetime of the
      // socket. Re-auth after a 401-bounce will re-read localStorage via
      // getToken(), so we don't need the stale value here anymore.
      token = null;
    };

    ws.onmessage = (event) => {
      // WEB-FO-003: any message proves the socket is still alive end-to-end.
      // Track receipt so the watchdog interval can detect a half-open NAT.
      lastMessageAtRef.current = Date.now();
      try {
        const msg = JSON.parse(event.data);
        const { type, data, success } = msg;

        // Handle auth response
        if (type === 'auth') {
          if (success) {
            setConnected(true);
            authRejectedRef.current = false;
            backoffRef.current = INITIAL_BACKOFF; // Reset backoff on successful auth
            // Start heartbeat now that we are authed. Server replies with
            // {type:'pong'} which is treated as any other message above.
            stopHeartbeat();
            lastMessageAtRef.current = Date.now();
            pingTimerRef.current = setInterval(() => {
              const sock = wsRef.current;
              if (!sock || sock.readyState !== WebSocket.OPEN) return;
              // WEB-FAD-009 (Fixer-C3 2026-04-25): skip heartbeat while tab
              // is hidden — incoming events are throttled by the browser
              // anyway and the outgoing ping wastes battery on phones.
              // Reset lastMessageAtRef so the watchdog doesn't trip the
              // moment the tab becomes visible again.
              if (typeof document !== 'undefined' && document.visibilityState === 'hidden') {
                lastMessageAtRef.current = Date.now();
                return;
              }
              // Watchdog: if the socket has been silent past PONG_TIMEOUT_MS
              // the connection is half-open. Force-close so onclose fires
              // and scheduleReconnect kicks in.
              if (Date.now() - lastMessageAtRef.current > PONG_TIMEOUT_MS) {
                try { sock.close(4000, 'heartbeat-timeout'); } catch { /* ignore */ }
                return;
              }
              try { sock.send(JSON.stringify({ type: 'ping', t: Date.now() })); } catch { /* ignore */ }
            }, PING_INTERVAL_MS);
          } else {
            // Auth explicitly rejected — stop reconnecting with this token
            authRejectedRef.current = true;
            ws.close();
          }
          return;
        }

        // Server pong (or implicit pong) — already counted via
        // lastMessageAtRef above. Don't fan out to invalidation map.
        if (type === 'pong') return;

        // Store last message
        setLastMessage({ type, data });

        // Invalidate relevant query keys
        const entry = invalidationMap.current[type];
        if (entry) {
          for (const qk of entry.queryKeys) {
            // WEB-FI-010 (Fixer-SSS 2026-04-25): the previous code did
            // `qk.filter((k) => k !== undefined)` which silently demoted
            // `['ticket', undefined]` to `['ticket']` — under tanstack v5
            // that prefix-key invalidates EVERY query starting with
            // `['ticket']`, so a single `ticket:status_changed` event
            // missing `data.id` re-fetched the entire ticket subtree
            // across every page. Skip the entry entirely when ANY slot
            // is undefined so partial keys never get demoted into a
            // catch-all prefix invalidation. The dedicated
            // entity-id invalidation below (lines ~325-336) still
            // handles the targeted `['ticket', id]` refresh when the
            // server DOES send a usable id.
            if (qk.some((k) => k === undefined)) continue;
            queryClientRef.current.invalidateQueries({ queryKey: qk });
          }

          // Also invalidate specific entity if data.id is present
          // SCAN-1086: `data?.id` truthy-check dropped id=0 and empty-string
          // ids, so legit entity invalidations were silently skipped. Accept
          // any defined, non-null id and let the query layer decide what to
          // match.
          if (data != null && data.id !== undefined && data.id !== null && data.id !== '') {
            if (type.startsWith('ticket:')) {
              queryClientRef.current.invalidateQueries({ queryKey: ['ticket', String(data.id)] });
              queryClientRef.current.invalidateQueries({ queryKey: ['ticket', Number(data.id)] });
            } else if (type.startsWith('invoice:')) {
              queryClientRef.current.invalidateQueries({ queryKey: ['invoice', String(data.id)] });
              queryClientRef.current.invalidateQueries({ queryKey: ['invoice', Number(data.id)] });
            } else if (type.startsWith('inventory:')) {
              queryClientRef.current.invalidateQueries({ queryKey: ['inventory-item', String(data.id)] });
              queryClientRef.current.invalidateQueries({ queryKey: ['inventory-item', Number(data.id)] });
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
      stopHeartbeat();
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
  }, [getToken, setConnected, setLastMessage, stopHeartbeat]); // queryClient via queryClientRef (stable); scheduleReconnect via ref

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
    // SCAN-1123: if a 4001 auth-reject left `authRejectedRef=true`, previously
    // we never reconnected on visibilitychange even after a re-login in
    // another tab (that tab doesn't dispatch `auth-cleared` for this
    // window). Check for a fresh access token when returning to visible —
    // if one is present, clear the auth-reject latch and attempt to
    // reconnect with the new token. Also unconditionally reset backoff so
    // back-to-back hidden-drops don't keep escalating the retry delay.
    const handleVisibilityChange = () => {
      if (document.visibilityState !== 'visible' || wsRef.current) return;
      if (authRejectedRef.current) {
        const hasToken = !!localStorage.getItem('accessToken');
        if (!hasToken) return;
        authRejectedRef.current = false;
      }
      backoffRef.current = INITIAL_BACKOFF;
      connect();
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);

    // Close the socket immediately when the user logs out so it does not
    // linger as an authenticated connection after credentials are cleared.
    const handleAuthCleared = () => {
      authRejectedRef.current = false; // allow reconnect on next login
      disconnect();
    };
    window.addEventListener('bizarre-crm:auth-cleared', handleAuthCleared);

    // When auth becomes available (login, switchUser, or silent refresh),
    // (re)connect immediately instead of waiting for the next tab-visibility
    // change. The initial connect() at mount-time can legitimately fail if
    // the token arrives a beat after the AppShell renders; this event closes
    // that gap and also covers the cross-tab case where another tab refreshes
    // the token while this tab is visible.
    const handleAuthReady = () => {
      authRejectedRef.current = false;
      backoffRef.current = INITIAL_BACKOFF;
      if (!wsRef.current) connect();
    };
    window.addEventListener('bizarre-crm:auth-ready', handleAuthReady);

    return () => {
      unmountedRef.current = true;
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('bizarre-crm:auth-cleared', handleAuthCleared);
      window.removeEventListener('bizarre-crm:auth-ready', handleAuthReady);
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
